"""Miniaturas del juego para Roblox (1920 x 1080), hechas con los modelos de verdad.

    blender --background --factory-startup --python tools/blender/crear_miniaturas.py -- [escena...]

Monta cada escena con las armas de crear_armas.py, los objetos de crear_objetos.py y las piezas de
crear_mapa_japones.py, la pinta con EEVEE sobre fondo transparente y le pone por código el cielo, los rayos, el
resplandor y los destellos. Deja `<escena>_base.png` en Documents/Roblox/miniaturas; los rótulos se los pone
después tools/blender/rotular_miniaturas.ps1.
"""

import argparse
import json
import math
import os
import random
import sys
import types

import bmesh
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "miniaturas")
W, H = 1920, 1080


def load(name):
    """Carga otro script de esta carpeta sin que exporte nada (se le quita la llamada final a main)."""
    path = os.path.join(HERE, name + ".py")
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    cut = source.rfind("\nmain()\n")
    if cut > 0:
        source = source[:cut]
    module = types.ModuleType(name)
    module.__file__ = path
    exec(compile(source, path, "exec"), module.__dict__)
    return module


ARMAS = load("crear_armas")
OBJETOS = load("crear_objetos")
MAPA = load("crear_mapa_japones")


# ---------- Materiales ----------

def rgb(r, g, b):
    return (r / 255, g / 255, b / 255)


def lin(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def vivid(c, amount=1.25):
    gray = sum(c) / 3
    return tuple(min(max(gray + (v - gray) * amount, 0), 1) for v in c)


WHITE = (1, 1, 1)
BLACK = (0.02, 0.02, 0.03)
_mats = {}


def mat(color, emit=0.0, metal=0.0, rough=0.45, glow=None):
    key = (tuple(round(v, 3) for v in color), emit, metal, rough, glow)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("m%d" % len(_mats))
    m.use_nodes = True
    node = m.node_tree.nodes["Principled BSDF"]
    node.inputs["Base Color"].default_value = lin(color) + (1,)
    node.inputs["Metallic"].default_value = metal
    node.inputs["Roughness"].default_value = rough
    node.inputs["Emission Color"].default_value = lin(glow or color) + (1,)
    node.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


GOLD = lambda: mat((1, 0.72, 0.14), emit=0.18, metal=0.85, rough=0.25)


# ---------- Geometría ----------

def Rx(d):
    return Matrix.Rotation(math.radians(d), 4, "X")


def Ry(d):
    return Matrix.Rotation(math.radians(d), 4, "Y")


def Rz(d):
    return Matrix.Rotation(math.radians(d), 4, "Z")


def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def Sc(s):
    return Matrix.Scale(s, 4)


def link(name, mesh, material, matrix, smooth=False):
    mesh.materials.append(material)
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = matrix
    return obj


def game_mesh(name, verts, faces, material, matrix):
    """Malla de los otros scripts (ejes del juego: Y arriba, Z atrás) puesta en ejes de Blender."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(v[0], -v[2], v[1]) for v in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return link(name, mesh, material, matrix)


def prim(kind, size, matrix, material, bevel=0.0, seg=20):
    bm = bmesh.new()
    if kind == "box":
        bmesh.ops.create_cube(bm, size=1)
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=0.5)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.5, depth=1)
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.0, depth=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=4, profile=0.5, affect="EDGES")
    mesh = bpy.data.meshes.new(kind)
    bm.to_mesh(mesh)
    bm.free()
    return link(kind, mesh, material, matrix, smooth=kind == "sphere" or bevel > 0)


def galaxy():
    """Material de galaxia: nubes moradas, rosas y azules que brillan, con estrellas blancas."""
    m = bpy.data.materials.new("galaxy")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.55
    noise.inputs["Detail"].default_value = 6.0
    ramp = nodes.new("ShaderNodeValToRGB")
    stops = [(0.32, rgb(20, 10, 80)), (0.48, rgb(80, 20, 180)), (0.6, rgb(190, 40, 220)), (0.74, rgb(255, 150, 240))]
    while len(ramp.color_ramp.elements) < len(stops):
        ramp.color_ramp.elements.new(0.5)
    for element, (position, color) in zip(ramp.color_ramp.elements, stops):
        element.position, element.color = position, lin(color) + (1,)
    stars = nodes.new("ShaderNodeTexVoronoi")
    stars.inputs["Scale"].default_value = 3.2
    dots = nodes.new("ShaderNodeMath")
    dots.operation = "LESS_THAN"
    dots.inputs[1].default_value = 0.09
    mixer = nodes.new("ShaderNodeMix")
    mixer.data_type = "RGBA"
    mixer.inputs["B"].default_value = (1, 1, 1, 1)
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    links.new(coord.outputs["Object"], stars.inputs["Vector"])
    links.new(noise.outputs[0], ramp.inputs[0])
    links.new(stars.outputs["Distance"], dots.inputs[0])
    links.new(dots.outputs[0], mixer.inputs["Factor"])
    links.new(ramp.outputs["Color"], mixer.inputs["A"])
    links.new(mixer.outputs["Result"], bsdf.inputs["Base Color"])
    links.new(mixer.outputs["Result"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.75
    bsdf.inputs["Roughness"].default_value = 0.3
    return m


def weapon(index, matrix, color, glow=1.0, accent=None, blade=None, **changes):
    spec = dict(ARMAS.SPECS[index], **changes)
    w = ARMAS.Weapon(index)
    ARMAS.BUILDERS[spec["kind"]](w, spec, spec["L"])
    light = mix(color, WHITE, 0.6)
    accent = accent or light
    mats = {
        "Blade": mat(color, emit=0.35 * glow, metal=0.2, rough=0.25),
        "Edge": mat(mix(color, WHITE, 0.45), emit=0.7 * glow, rough=0.2),
        "Dark": mat(mix(color, BLACK, 0.72), metal=0.5, rough=0.35),
        "Trim": GOLD(),
        "Grip": mat((0.22, 0.13, 0.1), rough=0.7),
        "Wood": mat((0.5, 0.32, 0.17), rough=0.7),
        "Gem": mat(accent, emit=1.0 * glow, rough=0.15),
        "Glow": mat(accent, emit=1.6 * glow),
        "Cloth": mat((0.85, 0.15, 0.2)),
    }
    if blade:
        mats["Blade"] = mats["Dark"] = blade
    for role, (verts, faces) in w.parts.items():
        game_mesh("W%d_%s" % (index, role), verts, faces, mats[role], matrix @ Rz(90))


MAP_LOOK = {"Paper": dict(emit=2.5), "Gold": dict(metal=0.9, rough=0.25, emit=0.3), "Water": dict(rough=0.1)}


def piece(name, matrix, tint=None, skip=(), look=None):
    p = MAPA.Piece()
    MAPA.PIECES[name](p)
    for (group, role), (verts, faces) in p.parts.items():
        if group in skip:
            continue
        color = vivid(MAPA.ROLE_COLORS[role][:3], 1.2)
        if tint and role in tint:
            color = tint[role]
        game_mesh(name + role, verts, faces, mat(color, **(look or MAP_LOOK).get(role, {})), matrix)


def split(obj, point, normal, moves, inside):
    """Parte `obj` por el plano (punto y normal del mundo) y deja dos mitades: la del lado de la normal se mueve
    con moves[0] y la otra con moves[1]. El corte se tapa con el material `inside`."""
    world_matrix = obj.matrix_world.copy()
    local_point = world_matrix.inverted() @ Vector(point)
    local_normal = (world_matrix.to_3x3().transposed() @ Vector(normal)).normalized()
    for side in (0, 1):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        cut = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=local_point,
                                     plane_no=local_normal, clear_inner=side == 0, clear_outer=side == 1)
        try:
            edges = [e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            bmesh.ops.edgeloop_fill(bm, edges=edges, mat_nr=1)
        except Exception:
            pass
        mesh = bpy.data.meshes.new(obj.name + "half")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(obj.data.materials[0])
        mesh.materials.append(inside)
        half = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.scene.collection.objects.link(half)
        half.matrix_world = moves[side] @ world_matrix
    bpy.data.objects.remove(obj)


def slash(center, along, normal, radius, start, end, width, material, depth=0.0):
    """Estela del tajo: media luna en el plano de la cámara, tangente a `along` en `center`."""
    along, normal = Vector(along).normalized(), Vector(normal).normalized()
    middle = Vector(center) + normal * radius
    verts, faces, steps = [], [], 40
    for i in range(steps + 1):
        u = i / steps
        t = math.radians(start + (end - start) * u)
        thick = width * math.sin(math.pi * u) ** 0.6
        for r in (radius, radius - thick):
            point = middle + (along * math.sin(t) - normal * math.cos(t)) * r
            verts.append((point.x, point.y + depth, point.z))
    for i in range(steps):
        a = i * 2
        faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new("slash")
    mesh.from_pydata(verts, [], faces)
    link("slash", mesh, material, Matrix.Identity(4))


def destructible(index, matrix, glow=0.0, cut=None):
    o = OBJETOS.Obj()
    OBJETOS.BUILDERS[index - 1](o)
    body = vivid(OBJETOS.BODY[index], 1.2)
    mats = {
        "Body": mat(body, emit=glow * 0.3, rough=0.6),
        "Dark": mat(mix(body, BLACK, 0.55), rough=0.6),
        "Trim": GOLD(),
        "Gem": mat(mix(body, WHITE, 0.3), emit=2.0 + glow),
        "Glow": mat(mix(body, WHITE, 0.5), emit=3.5 + glow),
    }
    for role, (verts, faces) in o.parts.items():
        obj = game_mesh("O%d_%s" % (index, role), verts, faces, mats[role], matrix)
        if cut:
            split(obj, *cut)


# ---------- Personaje ----------

NOOB = dict(skin=rgb(255, 214, 40), torso=rgb(30, 120, 255), legs=rgb(120, 205, 50), hair=rgb(120, 62, 28))


PRO = dict(skin=rgb(240, 196, 150), torso=rgb(34, 26, 48), legs=rgb(26, 20, 38), hair=rgb(44, 26, 70))


def hand(root, side, r):
    """Punto de la mano de un brazo de `character` (side -1 izquierdo, 1 derecho)."""
    rot = Rz(r[2]) @ Ry(r[1]) @ Rx(r[0])
    return root @ T(1.5 * side, 0, 3.75) @ rot @ Vector((0, 0, -1.75))


def character(root, look=NOOB, arm_l=(0, 150, 0), arm_r=(0, -150, 0), leg_l=(0, 0, 0), leg_r=(0, 0, 0),
              head=(0, 0, 0), mouth="wow", hair=True, eyes=None, brows="up", sweat=False):
    """Personaje de bloques de 5,3 de alto con los pies en el origen, mirando a -Y. Cada brazo y pierna es
    (giro X, giro Y, giro Z) en grados desde colgando; `head`, lo que gira la cabeza. `eyes` = color de unos ojos
    que brillan; mouth "wow", "sad", "grin" o lisa; brows "up" (sorpresa o pena) o "angry"."""
    skin = mat(look["skin"], rough=0.55)
    torso = mat(look["torso"], rough=0.55)
    legs = mat(look["legs"], rough=0.55)
    black = mat(BLACK, rough=0.3)

    def rot(r):
        return Rz(r[2]) @ Ry(r[1]) @ Rx(r[0])

    prim("box", (2, 1, 2), root @ T(0, 0, 3), torso, 0.12)
    for side, r in ((-1, leg_l), (1, leg_r)):
        prim("box", (0.96, 0.96, 2), root @ T(0.51 * side, 0, 2) @ rot(r) @ T(0, 0, -1), legs, 0.1)
    for side, r in ((-1, arm_l), (1, arm_r)):
        prim("box", (0.96, 0.96, 2), root @ T(1.5 * side, 0, 3.75) @ rot(r) @ T(0, 0, -0.8), skin, 0.1)

    neck = root @ T(0, 0, 4.0) @ rot(head)
    prim("box", (1.36, 1.36, 1.3), neck @ T(0, 0, 0.68), skin, 0.36)
    front = -0.69
    tilt = 14 if brows == "up" else -22
    for side in (-1, 1):
        if eyes:
            prim("sphere", (0.36, 0.1, 0.24), neck @ T(0.3 * side, front, 0.84) @ Ry(-12 * side), mat(eyes, emit=6.0))
        else:
            prim("sphere", (0.3, 0.1, 0.44), neck @ T(0.3 * side, front, 0.86), black)
            prim("sphere", (0.12, 0.08, 0.16), neck @ T(0.3 * side + 0.05, front - 0.04, 0.96), mat(WHITE, emit=1.5))
        prim("box", (0.38, 0.06, 0.09), neck @ T(0.31 * side, front, 1.12 if eyes else 1.2) @ Ry(tilt * side), black, 0.02)
    if sweat:
        drop = mat(rgb(90, 200, 255), emit=0.6, rough=0.1)
        prim("sphere", (0.3, 0.2, 0.3), neck @ T(0.95, front + 0.2, 1.3), drop)
        prim("cone", (0.3, 0.2, 0.4), neck @ T(0.95, front + 0.2, 1.52), drop, seg=12)
    if mouth == "sad":
        for side in (-1, 1):
            prim("box", (0.34, 0.08, 0.08), neck @ T(0.15 * side, front, 0.33) @ Ry(28 * side), black, 0.03)
    elif mouth == "grin":
        prim("box", (0.7, 0.08, 0.22), neck @ T(0.06, front, 0.36) @ Ry(-6), black, 0.06)
        prim("box", (0.62, 0.1, 0.1), neck @ T(0.06, front - 0.01, 0.4) @ Ry(-6), mat(WHITE, emit=0.6), 0.02)
    elif mouth == "wow":
        prim("sphere", (0.52, 0.1, 0.42), neck @ T(0, front, 0.36), mat((0.35, 0.05, 0.08), rough=0.4))
        prim("sphere", (0.34, 0.1, 0.2), neck @ T(0, front - 0.02, 0.26), mat((1, 0.42, 0.5), rough=0.4))
        prim("box", (0.36, 0.06, 0.1), neck @ T(0, front - 0.04, 0.52), mat(WHITE, emit=0.6), 0.02)
    else:
        prim("sphere", (0.62, 0.1, 0.16), neck @ T(0, front, 0.36), black)
    if hair:
        brown = mat(look["hair"], rough=0.6)
        prim("box", (1.44, 1.44, 0.5), neck @ T(0, 0.04, 1.2), brown, 0.2)
        prim("box", (1.44, 0.6, 1.0), neck @ T(0, 0.46, 0.8), brown, 0.2)
        rng = random.Random(4)
        for i in range(9):
            x, y = (i % 3 - 1) * 0.42, (i // 3 - 1) * 0.42
            tilt = Rx(-22 + rng.uniform(-14, 14)) @ Ry(rng.uniform(-22, 22))
            prim("cone", (0.52, 0.52, 0.8), neck @ T(x, y, 1.42) @ tilt @ T(0, 0, 0.3), brown, seg=6)


# ---------- Escena, cámara y luz ----------

def reset():
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
        for item in list(collection):
            collection.remove(item)
    _mats.clear()
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            pass
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    try:
        scene.eevee.taa_render_samples = 48
    except AttributeError:
        pass
    return scene


def world(color, strength=1.0):
    scene = bpy.context.scene
    w = scene.world or bpy.data.worlds.new("w")
    scene.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    node = w.node_tree.nodes.get("Background")
    node.inputs[0].default_value = lin(color) + (1,)
    node.inputs[1].default_value = strength


def camera(position, target, lens=30.0):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    cam.data.clip_end = 5000
    cam.location = position
    cam.rotation_euler = (Vector(target) - Vector(position)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    bpy.context.view_layer.update()  # sin esto, project() usa la cámara sin colocar
    return cam


def sun(direction, color, energy):
    light = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    light.data.energy = energy
    light.data.color = color
    light.data.angle = math.radians(6)
    light.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(light)


def lamp(position, color, energy, radius=2.0):
    light = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "POINT"))
    light.data.energy = energy
    light.data.color = color
    light.data.shadow_soft_size = radius
    light.location = position
    bpy.context.scene.collection.objects.link(light)


def project(point):
    """Punto del mundo -> píxel (x, y desde abajo)."""
    scene = bpy.context.scene
    v = world_to_camera_view(scene, scene.camera, Vector(point))
    return (v.x * W, v.y * H)


# ---------- Imagen final (cielo, rayos, resplandor, destellos) ----------

def blur(a, r):
    for axis in (0, 1):
        pad = [(r + 1, r) if i == axis else (0, 0) for i in range(a.ndim)]
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        a = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)
    return a


def soft(a, r, passes=3):
    for _ in range(passes):
        a = blur(a, r)
    return a


def finish(render_path, out_path, sky, rays=None, sparkles=(), glow=0.45, tint=None, clouds=(), divider=None, sky2=None):
    """sky = [(altura 0..1, color)...]; rays = dict(center=(x, y), color, count, alpha, reach, core). Con `divider`,
    `sky2` es el cielo de la mitad derecha."""
    image = bpy.data.images.load(render_path)
    px = np.empty(W * H * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    px = px.reshape(H, W, 4)
    fg, alpha = px[..., :3], px[..., 3:4]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    stops = sorted(sky)
    t = yy / (H - 1)
    bg = np.stack([np.interp(t, [s[0] for s in stops], [s[1][i] for s in stops]) for i in range(3)], axis=-1)
    if divider and sky2:
        stops = sorted(sky2)
        right = np.stack([np.interp(t, [s[0] for s in stops], [s[1][i] for s in stops]) for i in range(3)], axis=-1)
        side = np.clip(xx - (divider[1] + (divider[0] - divider[1]) * yy / H), 0, 1)[..., None]
        bg = bg * (1 - side) + right * side
    for cx, cy, size in clouds:  # nubes: varias bolas blancas juntas
        puff = np.zeros((H, W), dtype=np.float32)
        for dx, dy, r in ((0, 0, 1.0), (-0.9, -0.15, 0.7), (0.9, -0.12, 0.75), (-0.4, 0.35, 0.7), (0.45, 0.3, 0.6)):
            puff += np.exp(-(((xx - cx - dx * size) / (r * size)) ** 2 + ((yy - cy - dy * size) / (r * size * 0.62)) ** 2) * 1.6)
        puff = np.clip((puff - 0.35) / 0.25, 0, 1)[..., None]
        bg = bg * (1 - puff * 0.95) + puff * 0.95
    if rays:
        cx, cy = rays["center"]
        angle = np.arctan2(yy - cy, xx - cx)
        dist = np.hypot(xx - cx, yy - cy)
        beam = 0.5 + 0.5 * np.sin(angle * rays.get("count", 14) + rays.get("phase", 0.4))
        beam = np.clip((beam - 0.35) / 0.3, 0, 1)
        beam = beam * beam * (3 - 2 * beam) * np.clip(dist / 160.0, 0, 1)  # sin el moaré del centro
        fall = np.exp(-dist / rays.get("reach", 900.0))
        color = np.array(rays["color"], dtype=np.float32)
        bg = bg + (beam * fall * rays.get("alpha", 0.5))[..., None] * color
        core = np.exp(-(dist / rays.get("core", 260.0)) ** 2)
        bg = bg + core[..., None] * np.array(rays.get("core_color", (1, 1, 0.85)), dtype=np.float32) * rays.get("core_alpha", 0.9)
    out = fg * alpha + np.clip(bg, 0, 1) * (1 - alpha)

    # Resplandor: lo más claro se desborda alrededor.
    bright = out * np.clip((out.max(axis=-1, keepdims=True) - 0.9) / 0.1, 0, 1)
    small = bright.reshape(H // 4, 4, W // 4, 4, 3).mean(axis=(1, 3))
    halo = soft(small, 4) * 0.7 + soft(small, 14) * 0.55 + soft(small, 40) * 0.4
    halo = soft(np.repeat(np.repeat(halo, 4, axis=0), 4, axis=1), 2, 2)
    out = 1 - (1 - np.clip(out, 0, 1)) * (1 - np.clip(halo * glow, 0, 1))

    for x, y, size, color in sparkles:
        dx, dy = np.abs(xx - x), np.abs(yy - y)
        star = np.exp(-dx / size) * np.exp(-dy / (size * 0.045)) + np.exp(-dy / size) * np.exp(-dx / (size * 0.045))
        star = star + np.exp(-(np.hypot(dx, dy) / (size * 0.22)) ** 2) * 1.2
        out = out + np.clip(star, 0, 1.5)[..., None] * np.array(color, dtype=np.float32)

    gray = out.mean(axis=-1, keepdims=True)
    out = gray + (out - gray) * 1.18
    out = (out - 0.5) * 1.08 + 0.5
    if tint:
        out = out * np.array(tint, dtype=np.float32)
    vignette = 1 - 0.42 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) ** 1.3 * 0.5
    out = np.clip(out * vignette[..., None], 0, 1)

    if divider:  # franja oscura en diagonal: (x arriba, x abajo, grosor)
        line = divider[1] + (divider[0] - divider[1]) * yy / H
        band = np.clip((divider[2] / 2 + 1 - np.abs(xx - line)), 0, 1)[..., None]
        out = out * (1 - band) + np.array(rgb(22, 26, 60), dtype=np.float32) * band

    result = bpy.data.images.new("out", W, H, alpha=False)
    result.pixels.foreach_set(np.concatenate([out, np.ones((H, W, 1), dtype=np.float32)], axis=-1).astype(np.float32).ravel())
    result.filepath_raw = out_path
    result.file_format = "PNG"
    result.save()


def render(name, labels=(), **post):
    os.makedirs(OUT_DIR, exist_ok=True)
    raw = os.path.join(OUT_DIR, name + "_raw.png")
    bpy.context.scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    finish(raw, os.path.join(OUT_DIR, name + "_base.png"), **post)
    with open(os.path.join(OUT_DIR, name + ".json"), "w", encoding="utf-8") as handle:
        json.dump(list(labels), handle)
    print("Hecha", name)


def label(text, x, y, size, angle=0.0, top="#FFFFFF", bottom="#FFD23F", outline="#000000", rainbow=False):
    """Rótulo que pone rotular_miniaturas.ps1: centro en píxeles desde arriba a la izquierda."""
    return dict(text=text, x=x, y=y, size=size, angle=angle, top=top, bottom=bottom, outline=outline, rainbow=rainbow)


def over(point, dy=0.0):
    """Píxel (desde arriba) de un punto del mundo, para colgarle un rótulo."""
    x, y = project(point)
    return x, H - y + dy


# ---------- Piezas sueltas de las escenas ----------

def burst(center, count, rng, spread=(13, 6, 11), kinds=("coin", "gem", "plank"), gem_colors=None, size=1.0):
    """Monedas, gemas y tablas saliendo disparadas de `center`."""
    gem_colors = gem_colors or [rgb(190, 90, 255), rgb(90, 230, 255), rgb(255, 80, 200)]
    spots = []
    for i in range(count):
        kind = kinds[i % len(kinds)]
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 0.5), rng.uniform(-0.15, 1))).normalized()
        reach = rng.uniform(0.25, 1.0) ** 0.7
        pos = Vector(center) + Vector((d.x * spread[0], d.y * spread[1], d.z * spread[2])) * reach
        spin = Rz(rng.uniform(0, 360)) @ Rx(rng.uniform(0, 360)) @ Ry(rng.uniform(0, 360))
        m = T(*pos) @ spin
        if kind == "coin":
            s = rng.uniform(0.8, 1.5) * size
            prim("cyl", (s, s, s * 0.16), m, GOLD(), seg=24)
            prim("cyl", (s * 0.7, s * 0.7, s * 0.2), m, mat((1, 0.86, 0.3), emit=0.3, metal=0.8, rough=0.2), seg=24)
        elif kind == "gem":
            s = rng.uniform(0.6, 1.1) * size
            color = rng.choice(gem_colors)
            verts, faces = OBJETOS.gem(s * 0.55, s * 1.3)
            game_mesh("gem", verts, faces, mat(color, emit=0.9, rough=0.1), m)
            spots.append((pos, color))
        else:
            s = rng.uniform(0.7, 1.3) * size
            prim("box", (s * 2.2, s * 0.5, s * 0.2), m, mat(rgb(170, 112, 60), rough=0.7), 0.03)
    return spots


def ground(color, slab=None):
    prim("box", (4000, 4000, 1), T(0, 1200, -0.5), mat(color, rough=0.9))
    if slab:
        prim("cyl", (slab[0], slab[0], 0.5), T(slab[1][0], slab[1][1], 0.0), mat(slab[2], rough=0.6), seg=48)


# ---------- Escenas ----------

def scene_main():
    reset()
    rng = random.Random(7)
    world((1.0, 0.75, 0.88), 0.5)
    cam = camera((0, -27, 5.2), (0.8, 0, 7.0), 29)
    sun((0.45, 0.75, -0.55), (1, 0.93, 0.8), 2.3)
    ground(rgb(70, 170, 80), (30, (5, 6), rgb(150, 110, 215)))

    # El arma enorme saliendo de la caja rota.
    base = Vector((4.6, 1.5, 3.0))
    red = rgb(255, 40, 80)
    weapon(16, T(base.x, 0.5, 4.0) @ Ry(30) @ Rz(-8) @ Sc(1.6), rgb(235, 20, 50), glow=0.55, accent=rgb(255, 215, 90), width=0.6)
    lamp(base + Vector((0, -6, 9)), (1, 0.6, 0.6), 1500, 3)
    lamp(base + Vector((-3, -5, 2)), (1, 0.8, 0.4), 1500, 2)
    destructible(1, T(base.x - 0.6, base.y + 0.6, 0.0) @ Rz(25) @ Sc(1.6))
    gems = burst(Vector((base.x, 0, 2.2)), 60, rng, spread=(15, 7, 10))

    # Las armas equipadas, volando alrededor.
    weapon(28, T(16.2, -4, 12.6) @ Ry(-140) @ Rx(-15) @ Sc(1.1), rgb(255, 225, 70), glow=0.8)
    weapon(7, T(-0.6, 3, 8.6) @ Ry(-38) @ Sc(1.0), rgb(255, 70, 220), glow=1.1)
    weapon(39, T(13.2, -6, 2.6) @ Ry(-60) @ Rx(-10) @ Sc(0.8), rgb(255, 225, 150), glow=0.8, accent=rgb(255, 150, 60))


    # El personaje, delante y a la izquierda, flipando.
    hero = T(-7.2, -10.5, -1.6) @ Rz(26) @ Rx(-6) @ Sc(1.75)
    character(hero, arm_l=(-15, 150, 0), arm_r=(-25, -118, 0), head=(-12, 0, 16))
    lamp((-10, -20, 9), (1, 0.95, 0.9), 2600, 4)
    lamp((-2, -8, 9), (1, 0.4, 0.6), 1200, 2)

    # El mapa, detrás.
    piece("Sakura", T(-21, 26, 0) @ Rz(40) @ Sc(1.25))
    piece("SakuraB", T(24, 34, 0) @ Rz(200) @ Sc(1.35))
    piece("Sakura", T(-44, 62, 0) @ Rz(120) @ Sc(1.6))
    piece("Maple", T(40, 66, 0) @ Rz(10) @ Sc(1.6))
    piece("Torii", T(28, 60, 0) @ Rz(-14) @ Sc(1.5))
    piece("Pagoda", T(-34, 110, 0) @ Sc(1.9))
    piece("StoneLantern", T(-9.5, 9, 0) @ Sc(1.3))
    piece("StoneLantern", T(17, 14, 0) @ Sc(1.3))
    piece("Fuji", T(-330, 620, -4) @ Sc(1.0))

    center = project(base + Vector((4.2, 0, 8.5)))
    sparkles = [(project(p) + (rng.uniform(26, 48), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    tip = project(base + Vector((9.0, -0.5, 16.4)))
    sparkles += [(tip[0], tip[1], 120, (1, 0.95, 0.85)), (center[0] + 60, center[1] - 120, 70, (1, 0.8, 0.9))]
    render(
        "principal",
        sky=[(0.0, rgb(255, 196, 120)), (0.42, rgb(255, 128, 150)), (0.75, rgb(170, 80, 220)), (1.0, rgb(70, 40, 170))],
        rays=dict(center=center, color=(1.0, 0.85, 0.55), count=18, alpha=0.5, reach=1500, core=380,
                  core_color=(1, 0.88, 0.5), core_alpha=0.55),
        sparkles=sparkles,
        labels=[
            label("1 IN 1,000,000", 690, 150, 190, -4, "#FFF36B", "#FF9A1F"),
            label("LEGENDARY PULL!", 560, 322, 96, -4, "#FFFFFF", "#FF8FE0"),
        ],
    )


def pedestal(x, y, color, radius=2.3):
    prim("cyl", (radius * 2, radius * 2, 0.9), T(x, y, 0.45), mat(rgb(40, 34, 70), metal=0.4, rough=0.3), seg=40)
    prim("cyl", (radius * 2.12, radius * 2.12, 0.22), T(x, y, 0.8), mat(color, emit=0.55), seg=40)
    prim("cyl", (radius * 1.5, radius * 1.5, 0.3), T(x, y, 0.95), mat(mix(color, BLACK, 0.3), emit=0.15), seg=40)


def scene_rarities():
    reset()
    rng = random.Random(3)
    world((0.55, 0.45, 0.95), 0.45)
    camera((0, -27, 6.4), (0, 0, 5.5), 32)
    sun((0.3, 0.8, -0.5), (1, 0.95, 1), 1.6)
    prim("box", (4000, 4000, 1), T(0, 1200, -0.5), mat(rgb(48, 30, 110), metal=0.3, rough=0.25))
    tiers = [
        (3, "COMMON", "1 IN 5", rgb(190, 195, 205), rgb(200, 205, 210), 4.5, {}),
        (6, "RARE", "1 IN 254", rgb(70, 150, 255), rgb(90, 230, 255), 6.0, {}),
        (8, "EPIC", "1 IN 25K", rgb(180, 90, 255), rgb(140, 70, 255), 7.5, dict(width=0.45)),
        (29, "LEGENDARY", "1 IN 20M", rgb(255, 190, 40), rgb(255, 110, 30), 9.0, {}),
        (16, "SECRET", "1 IN 567Q", rgb(255, 90, 210), rgb(255, 40, 80), 11.2, dict(width=0.6)),
    ]
    labels, sparkles = [], []
    xs = [-13.8, -8.0, -2.2, 4.0, 11.0]
    for i, (index, name, odds, tier, color, height, changes) in enumerate(tiers):
        x, y = xs[i], 0
        pedestal(x, y, tier, 2.0 + i * 0.25)
        scale = height / (ARMAS.SPECS[index]["L"] + 1.3)
        lean = (-7, 6, -5, 7, -10)[i]
        weapon(index, T(x, y, 1.4 + 1.0 * scale) @ Ry(lean) @ Sc(scale), color, glow=0.6 + i * 0.3,
               accent=mix(tier, WHITE, 0.3), **changes)
        lamp((x, y - 5, 4 + height * 0.5), tier, 900 + i * 700, 2)
        top = (x + math.sin(math.radians(lean)) * height, y, 2.2 + height)
        hexa = "#%02X%02X%02X" % tuple(int(v * 255) for v in mix(tier, WHITE, 0.25))
        bx, by = over((x, y, 0.0))
        labels.append(label(name, bx, by + 62, 40 + i * 4, 0, "#FFFFFF", hexa))
        labels.append(label(odds, bx, by + 136, 58 + i * 8, -2, "#FFFFFF", hexa))
        sparkles.append((project(top) + (40 + i * 22, mix(tier, WHITE, 0.6))))
    last = Vector((xs[4], 0, 8))
    gems = burst(last, 30, rng, spread=(6, 4, 9), kinds=("coin", "gem"), gem_colors=[rgb(255, 90, 210), rgb(255, 220, 90)], size=0.7)
    sparkles += [(project(p) + (rng.uniform(22, 40), (1, 0.8, 0.95))) for p, c in gems[::2]]
    labels.append(label("HOW LUCKY ARE YOU?", 640, 120, 118, -3, "#FFF36B", "#FF9A1F"))
    render(
        "rarezas",
        sky=[(0.0, rgb(120, 60, 200)), (0.45, rgb(70, 40, 170)), (1.0, rgb(18, 12, 60))],
        rays=dict(center=project(last + Vector((0, 0, 1))), color=(1.0, 0.5, 0.85), count=20, alpha=0.75, reach=1300,
                  core=380, core_color=(1, 0.6, 0.9), core_alpha=0.4),
        sparkles=sparkles, labels=labels,
    )


def scene_bag():
    reset()
    rng = random.Random(11)
    world((0.8, 0.92, 1.0), 0.6)
    camera((0, -36, 7.5), (1.5, 0, 8.0), 30)
    sun((0.5, 0.7, -0.6), (1, 0.96, 0.85), 2.6)
    ground(rgb(84, 190, 90))
    sack = Vector((6.5, 2, 0))
    piece("GoldSack", T(*sack) @ Rz(200) @ Sc(1.25), skip=("Path",))
    lamp(sack + Vector((-4, -9, 12)), (1, 0.85, 0.4), 5000, 3)
    mouth = sack + Vector((0, -1, 15.5))
    gems = burst(mouth, 90, rng, spread=(17, 8, 9), kinds=("coin", "coin", "coin", "gem"), size=1.25,
                 gem_colors=[rgb(90, 230, 255), rgb(255, 90, 210)])
    burst(sack + Vector((0, -7, 0.5)), 26, rng, spread=(12, 5, 0.6), kinds=("coin",), size=1.3)

    # Las armas depositadas, lanzadas contra el saco.
    weapon(7, T(-3.5, -1, 12.5) @ Ry(118) @ Sc(1.15), rgb(255, 70, 220), glow=1.1)
    weapon(8, T(-4.5, 0, 6.2) @ Ry(96) @ Sc(1.0), rgb(140, 70, 255), glow=1.0, width=0.45)
    weapon(28, T(17.5, -2, 4.0) @ Ry(-70) @ Sc(1.15), rgb(255, 225, 70), glow=0.8)

    hero = T(-8.6, -14, -1.6) @ Rz(30) @ Rx(-5) @ Sc(1.75)
    character(hero, arm_l=(-12, 152, 0), arm_r=(-12, -152, 0), head=(-10, 0, 14))
    lamp((-11, -24, 10), (1, 0.97, 0.9), 3000, 4)

    piece("Sakura", T(-26, 30, 0) @ Rz(40) @ Sc(1.3))
    piece("SakuraB", T(30, 38, 0) @ Rz(200) @ Sc(1.4))
    piece("Pine", T(-8, 52, 0) @ Sc(1.5))
    piece("Maple", T(46, 70, 0) @ Sc(1.6))
    piece("Fuji", T(-260, 640, -4))

    sparkles = [(project(p) + (rng.uniform(26, 46), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    sparkles.append(project(mouth) + (130, (1, 0.95, 0.7)))
    plus = over(sack + Vector((-9.5, -4, 12.5)))
    render(
        "bolsa",
        sky=[(0.0, rgb(190, 240, 255)), (0.45, rgb(90, 190, 255)), (1.0, rgb(30, 110, 235))],
        rays=dict(center=project(sack + Vector((0, 0, 9))), color=(1.0, 0.95, 0.6), count=18, alpha=0.7, reach=1500,
                  core=430, core_color=(1, 0.95, 0.6), core_alpha=0.8),
        sparkles=sparkles,
        labels=[
            label("AFK = COINS!", 560, 140, 180, -4, "#FFF36B", "#FF9A1F"),
            label("+1,000,000,000", plus[0], plus[1], 84, 8, "#EAFFB0", "#5BE04A"),
        ],
    )


def scene_smith():
    reset()
    rng = random.Random(5)
    world((0.25, 0.3, 0.6), 0.5)
    camera((0, -34, 3.0), (0.5, 0, 11.0), 26)
    sun((0.2, 0.9, -0.4), (0.6, 0.7, 1), 1.0)
    prim("box", (4000, 4000, 1), T(0, 1200, -0.5), mat(rgb(30, 22, 44), rough=0.8))
    ghost = {role: dict(emit=0.25) for role in MAPA.ROLE_COLORS}
    ghost["Paper"] = dict(emit=2.2)
    piece("Smith", T(0, 0, 0), look=ghost, tint={"Paper": rgb(255, 120, 30)})
    lamp((0, -12, 5), (1, 0.5, 0.15), 30000, 3)
    lamp((-18, -10, 26), (0.4, 0.6, 1), 26000, 5)
    lamp((18, -10, 26), (1, 0.4, 0.8), 22000, 5)
    weapon(16, T(0, -3.0, 5.0) @ Ry(-12) @ Sc(1.0), rgb(255, 140, 30), glow=2.2, accent=rgb(255, 230, 150), width=0.6)
    hero = T(-6.4, -22, -1.2) @ Rz(28) @ Rx(-8) @ Sc(1.3)
    character(hero, arm_l=(-12, 150, 0), arm_r=(-12, -150, 0), head=(-14, 0, 10))
    lamp((-8, -29, 6), (1, 0.85, 0.7), 1600, 3)
    gems = burst(Vector((0, -8, 6)), 40, rng, spread=(22, 6, 14), kinds=("gem",), size=0.6,
                 gem_colors=[rgb(255, 150, 40), rgb(255, 220, 90)])
    sparkles = [(project(p) + (rng.uniform(22, 44), (1, 0.8, 0.5))) for p, c in gems[::2]]
    render(
        "herrero",
        sky=[(0.0, rgb(255, 120, 40)), (0.3, rgb(120, 40, 90)), (1.0, rgb(14, 10, 40))],
        rays=dict(center=project((0, 0, 9)), color=(1.0, 0.5, 0.2), count=16, alpha=0.42, reach=1300, core=420,
                  core_color=(1, 0.6, 0.25), core_alpha=0.7),
        sparkles=sparkles,
        labels=[
            label("1 IN 10,000", 440, 130, 150, -5, "#FFF36B", "#FF9A1F"),
            label("GIANT BLACKSMITH?!", 1180, 965, 120, -2, "#FFFFFF", "#8FD8FF"),
        ],
    )


def scene_ranks():
    reset()
    rng = random.Random(9)
    world((0.85, 0.95, 1.0), 0.7)
    camera((0, -30, 4.2), (0, 0, 6.2), 32)
    sun((0.35, 0.8, -0.6), (1, 0.97, 0.9), 2.6)
    ground(rgb(92, 205, 60))
    for i in range(260):  # matas de hierba más claras y más oscuras
        x, y = rng.uniform(-60, 60), rng.uniform(-22, 90)
        shade = mix(rgb(92, 205, 60), rng.choice([rgb(150, 235, 80), rgb(60, 170, 50)]), rng.uniform(0.3, 0.8))
        prim("cone", (0.9, 0.9, rng.uniform(0.5, 1.1)), T(x, y, 0.25) @ Rz(rng.uniform(0, 90)), mat(shade, rough=0.9), seg=4)

    left, right = Vector((-9.2, 0, 0)), Vector((8.8, 0, 0))
    for spot, radius in ((left, 2.2), (right, 4.6)):
        prim("cyl", (radius * 2, radius * 2, 0.06), T(spot.x, spot.y, 0.04), mat(rgb(40, 110, 40), rough=1), seg=40)
    weapon(1, T(left.x, 0, 2.0) @ Ry(-14) @ Sc(1.5), rgb(150, 105, 60), glow=0.0)
    weapon(16, T(right.x, 0, 2.6) @ Ry(9) @ Sc(1.12), rgb(120, 40, 220), glow=0.4, accent=rgb(255, 120, 255),
           blade=galaxy(), width=1.25)
    lamp(right + Vector((0, -6, 7)), (0.8, 0.5, 1), 700, 3)
    lamp(left + Vector((0, -6, 5)), (1, 1, 1), 500, 3)

    glow_at = project(right + Vector((-1.0, 0, 7.2)))
    sparkles = []
    for i in range(16):
        a, r = rng.uniform(0, 6.28), rng.uniform(120, 330)
        sparkles.append((glow_at[0] + math.cos(a) * r * 0.7, glow_at[1] + math.sin(a) * r, rng.uniform(22, 60), (1, 0.9, 1)))
    render(
        "rangos",
        sky=[(0.0, rgb(200, 240, 255)), (0.5, rgb(110, 200, 255)), (1.0, rgb(40, 140, 250))],
        clouds=[(260, 560, 150), (820, 690, 120), (1250, 600, 170), (1750, 720, 130), (560, 900, 110), (1560, 930, 120)],
        rays=dict(center=glow_at, color=(1, 1, 1), count=14, alpha=0.45, reach=700, core=300, core_color=(1, 0.92, 1),
                  core_alpha=0.7),
        sparkles=sparkles, divider=(1010, 880, 20),
        labels=[
            label("RANK 1", 470, 120, 150, 0, "#FFFFFF", "#DDE6F5"),
            label("1 IN 2", 470, 262, 96, 0, "#FFF36B", "#FF9A1F"),
            label("RANK 999", 1440, 120, 160, 0, "#FFFFFF", "#DDE6F5"),
            label("1 IN 999,999,999", 1440, 262, 92, 0, rainbow=True),
        ],
    )


def scene_slice():
    reset()
    rng = random.Random(21)
    world((1.0, 0.78, 0.9), 0.5)
    camera((0, -30, 5.6), (0.5, 0, 7.4), 30)
    sun((0.45, 0.75, -0.55), (1, 0.93, 0.8), 2.3)
    ground(rgb(70, 170, 80), (26, (0, 4), rgb(150, 110, 215)))

    # El cristal, partido en diagonal: la mitad de arriba sale despedida.
    center = Vector((0, 0, 6.6))
    angle = math.radians(32)
    along = Vector((math.cos(angle), 0, math.sin(angle)))
    normal = Vector((-math.sin(angle), 0, math.cos(angle)))
    pivot = T(*center)
    up = T(*(normal * 2.6 - along * 1.3)) @ pivot @ Ry(-9) @ pivot.inverted()
    down = T(*(-normal * 0.5 + along * 0.5)) @ pivot @ Ry(4) @ pivot.inverted()
    hot = mat(rgb(255, 225, 120), emit=1.3)
    destructible(1, T(0, 0, 1.6) @ Rz(28) @ Rx(-8) @ Sc(3.3), cut=(center, normal, (up, down), hot))
    lamp(center + Vector((0, -9, 2)), (1, 0.9, 0.7), 1500, 3)

    # La espada, al final del tajo, cruzando el hueco.
    red = rgb(235, 20, 50)
    hilt = center + along * 12.5 + normal * 0.9 + Vector((0, -1.6, 0))
    weapon(16, T(*hilt) @ Ry(-90 - 32 - 3) @ Sc(1.9), red, glow=0.6, accent=rgb(255, 215, 90), width=0.75)
    lamp(hilt + Vector((-6, -5, 0)), (1, 0.5, 0.5), 1800, 3)
    slash(center + normal * 1.0, along, normal, 24, -40, 20, 1.5, mat(rgb(255, 120, 150), emit=1.0), 1.2)
    slash(center + normal * 1.0, along, normal, 24.3, -34, 16, 0.55, mat((1, 1, 1), emit=2.0), 1.0)

    gems = burst(center + Vector((0, -2, 0)), 60, rng, spread=(16, 6, 9), size=1.1)
    burst(center + Vector((0, -3, -5.5)), 20, rng, spread=(13, 5, 1.5), kinds=("coin", "gem"))

    piece("Sakura", T(-24, 28, 0) @ Rz(40) @ Sc(1.3))
    piece("SakuraB", T(26, 34, 0) @ Rz(200) @ Sc(1.4))
    piece("Torii", T(-30, 64, 0) @ Rz(14) @ Sc(1.5))
    piece("Pagoda", T(40, 110, 0) @ Sc(1.9))
    piece("StoneLantern", T(-13, 10, 0) @ Sc(1.3))
    piece("StoneLantern", T(14, 12, 0) @ Sc(1.3))
    piece("Fuji", T(-300, 620, -4))

    middle = project(center)
    sparkles = [(project(p) + (rng.uniform(26, 50), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    sparkles += [(middle[0], middle[1], 110, (1, 1, 0.9))]
    render(
        "tajo",
        sky=[(0.0, rgb(255, 196, 120)), (0.42, rgb(255, 128, 150)), (0.75, rgb(170, 80, 220)), (1.0, rgb(70, 40, 170))],
        rays=dict(center=middle, color=(1.0, 0.9, 0.6), count=18, alpha=0.5, reach=1500, core=380,
                  core_color=(1, 0.9, 0.55), core_alpha=0.4),
        sparkles=sparkles,
        labels=[
            label("BREAK EVERYTHING!", 640, 130, 132, -4, "#FFF36B", "#FF9A1F"),
            label("1 IN 1,000,000 DROPS!", 1400, 985, 84, -3, "#FFFFFF", "#8FE9FF"),
        ],
    )


# ---------- Piezas de las escenas de octubre (cofres, portal, slimes, medallas) ----------

PURPLE = rgb(170, 70, 255)


def torus(major, minor, matrix, material, seg=48):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=12)
    obj = bpy.context.active_object
    obj.matrix_world = matrix
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def text(body, matrix, size, material, extrude=0.15):
    """Texto en 3D mirando a -Y (para el "?" de las medallas)."""
    curve = bpy.data.curves.new("text", "FONT")
    curve.body = body
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = 0.04
    curve.align_x, curve.align_y = "CENTER", "CENTER"
    curve.materials.append(material)
    obj = bpy.data.objects.new("text", curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = matrix @ Rx(90)
    return obj


def chest(matrix, opened=False):
    """Cofre de 3 x 2 con bandas de oro; abierto, lleno de monedas que brillan."""
    wood = mat(rgb(160, 92, 44), rough=0.7)
    dark = mat(rgb(84, 46, 24), rough=0.8)
    prim("box", (3, 2, 1.8), matrix @ T(0, 0, 0.9), wood, 0.06)
    prim("box", (3.1, 2.1, 0.22), matrix @ T(0, 0, 0.11), dark, 0.04)
    for x in (-1.25, 1.25):
        prim("box", (0.28, 2.12, 1.84), matrix @ T(x, 0, 0.92), GOLD(), 0.04)
    if opened:
        prim("sphere", (2.7, 1.7, 1.2), matrix @ T(0, 0, 1.75), mat(rgb(255, 200, 60), emit=0.9, metal=0.6, rough=0.3))
        lid = matrix @ T(0, 1.0, 1.8) @ Rx(-112)
    else:
        lid = matrix @ T(0, 1.0, 1.8)
    prim("box", (3, 2, 0.8), lid @ T(0, -1.0, 0.4), wood, 0.25)
    for x in (-1.25, 1.25):
        prim("box", (0.28, 2.12, 0.84), lid @ T(x, -1.0, 0.4), GOLD(), 0.12)
    if not opened:
        prim("box", (0.5, 0.2, 0.6), matrix @ T(0, -1.08, 1.7), GOLD(), 0.05)


def pile(center, radius, height, count, rng, gem_colors=None):
    """Montón de monedas (y alguna gema) con forma de loma."""
    center = Vector(center)
    gold = mat(rgb(255, 196, 50), emit=0.35, metal=0.7, rough=0.3)
    prim("sphere", (radius * 1.9, radius * 1.9, height * 1.8), T(*center), gold)
    gem_colors = gem_colors or [rgb(190, 90, 255), rgb(255, 80, 200), rgb(90, 200, 255)]
    spots = []
    for i in range(count):
        r, a = radius * math.sqrt(rng.random()), rng.uniform(0, 6.283)
        z = height * 0.9 * max(0.0, 1 - (r / radius) ** 2) ** 0.5
        pos = center + Vector((math.cos(a) * r, math.sin(a) * r, z + 0.1))
        m = T(*pos) @ Rz(rng.uniform(0, 360)) @ Rx(rng.uniform(-35, 35))
        if i % 7 == 3:
            color = rng.choice(gem_colors)
            s = rng.uniform(0.7, 1.2)
            verts, faces = OBJETOS.gem(s * 0.55, s * 1.3)
            game_mesh("gem", verts, faces, mat(color, emit=0.9, rough=0.1), m @ Rx(rng.uniform(40, 80)))
            spots.append((pos, color))
        else:
            s = rng.uniform(0.7, 1.0)
            prim("cyl", (s, s, s * 0.16), m, GOLD(), seg=20)
    return spots


def vortex(origin):
    """Material del remolino del portal: espiral morada y rosa que brilla, centrada en `origin`."""
    m = bpy.data.materials.new("vortex")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coord = nodes.new("ShaderNodeTexCoord")
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.rings_direction = "SPHERICAL"
    coord.object = origin
    wave.inputs["Scale"].default_value = 0.45
    wave.inputs["Distortion"].default_value = 2.5
    wave.inputs["Detail"].default_value = 3.0
    ramp = nodes.new("ShaderNodeValToRGB")
    stops = [(0.0, rgb(40, 10, 90)), (0.45, rgb(130, 40, 230)), (0.8, rgb(230, 120, 255)), (1.0, rgb(255, 230, 255))]
    while len(ramp.color_ramp.elements) < len(stops):
        ramp.color_ramp.elements.new(0.5)
    for element, (position, color) in zip(ramp.color_ramp.elements, stops):
        element.position, element.color = position, lin(color) + (1,)
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    links.new(wave.outputs["Fac"], ramp.inputs[0])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.2
    return m


def portal(base, width, height, rng):
    """Arco de bloques de piedra con runas moradas y un remolino dentro; `base` es el centro del suelo del arco.
    Devuelve el centro del remolino."""
    base = Vector(base)
    stone = mat(rgb(78, 70, 98), rough=0.85)
    stone_dark = mat(rgb(52, 46, 70), rough=0.85)
    rune = mat(PURPLE, emit=5.0)
    radius = width / 2
    spring = base.z + height - radius
    blocks = []
    z = base.z
    while z < spring:
        for side in (-1, 1):
            blocks.append(T(base.x + side * radius, base.y, z + 1.0) @ Ry(rng.uniform(-3, 3)))
        z += 2.1
    steps = int(math.pi * radius / 2.3)
    for i in range(steps + 1):
        a = math.pi * i / steps
        blocks.append(T(base.x + radius * math.cos(a), base.y, spring + radius * math.sin(a)) @ Ry(-math.degrees(a) - 90))
    for i, m in enumerate(blocks):
        prim("box", (2.6, 3.0, 2.1), m @ Rz(rng.uniform(-3, 3)), stone if i % 3 else stone_dark, 0.12)
        if i % 4 == 1:  # placa con runa
            prim("box", (1.3, 0.12, 1.2), m @ T(0, -1.56, 0), mat(rgb(30, 20, 50)), 0.02)
            prim("box", (0.9, 0.14, 0.12), m @ T(0, -1.6, 0.35), rune)
            prim("box", (0.9, 0.14, 0.12), m @ T(0, -1.6, -0.35), rune)
            prim("box", (0.12, 0.14, 0.82), m @ T(0.39, -1.6, 0), rune)
            prim("box", (0.12, 0.14, 0.82), m @ T(-0.39, -1.6, 0), rune)
    origin = bpy.data.objects.new("vortex", None)
    bpy.context.scene.collection.objects.link(origin)
    origin.location = (base.x, base.y, spring)
    swirl = vortex(origin)
    inner = radius - 1.1
    prim("cyl", (inner * 2, inner * 2, 0.3), T(base.x, base.y + 0.4, spring) @ Rx(90), swirl, seg=48)
    prim("box", (inner * 2, 0.3, spring - base.z), T(base.x, base.y + 0.4, (spring + base.z) / 2), swirl)
    for i in range(5):  # aros del remolino, cada vez más dentro y más claros
        r = inner * (0.9 - i * 0.17)
        torus(r, 0.12 + 0.04 * i, T(base.x, base.y + 0.1 - i * 0.05, spring - i * 0.3) @ Rx(90) @ Ry(8 * (i % 2 * 2 - 1)),
              mat(mix(PURPLE, WHITE, i * 0.18), emit=4.0 + i))
    center = Vector((base.x, base.y - 2.5, spring - 1.0))
    lamp(center, (0.75, 0.35, 1), 6000, 6)
    return center


def slime(matrix, color, eyes=rgb(255, 60, 90), horns=True):
    """Slime de mazmorra enfadado, mirando a -Y."""
    body = mat(color, emit=0.3, rough=0.15)
    prim("sphere", (3.2, 3.0, 2.4), matrix @ T(0, 0, 1.15), body, seg=28)
    prim("sphere", (1.1, 0.6, 0.6), matrix @ T(-0.7, -1.0, 1.85), mat(mix(color, WHITE, 0.7), emit=0.6), seg=16)
    for side in (-1, 1):
        prim("sphere", (0.55, 0.2, 0.38), matrix @ T(0.55 * side, -1.38, 1.3) @ Ry(18 * side), mat(eyes, emit=6.0))
        prim("box", (0.7, 0.15, 0.14), matrix @ T(0.55 * side, -1.4, 1.68) @ Ry(-24 * side), mat(BLACK), 0.03)
        if horns:
            prim("cone", (0.5, 0.5, 1.2), matrix @ T(0.9 * side, 0, 2.3) @ Ry(25 * side) @ T(0, 0, 0.4), mat(rgb(40, 30, 50)), seg=10)
    prim("box", (0.9, 0.12, 0.3), matrix @ T(0, -1.42, 0.85), mat(BLACK), 0.08)


def medallion(matrix, base, rim, deco, rng):
    """Medalla de rasgo misterioso con un "?" enorme, mirando a -Y."""
    prim("cyl", (6.4, 6.4, 0.8), matrix @ Rx(90), mat(mix(base, BLACK, 0.65), metal=0.4, rough=0.3), seg=48)
    prim("cyl", (5.2, 5.2, 0.9), matrix @ T(0, -0.05, 0) @ Rx(90), mat(base, emit=0.8, rough=0.3), seg=48)
    torus(3.15, 0.38, matrix @ Rx(90), mat(rim, emit=1.2, metal=0.6, rough=0.2))
    text("?", matrix @ T(0, -0.6, -0.15), 5.0, mat(rgb(255, 230, 90), emit=1.6, metal=0.3, rough=0.25), 0.35)
    glow = mat(mix(base, WHITE, 0.4), emit=3.0)
    if deco == "fire":  # llamas alrededor
        for i in range(14):
            a = 360 * i / 14
            prim("cone", (1.2, 0.6, rng.uniform(1.6, 2.8)), matrix @ Ry(a) @ T(0, 0, 3.3) @ T(0, 0, 0.8),
                 mat(rng.choice([rgb(255, 120, 30), rgb(255, 200, 60), rgb(255, 60, 30)]), emit=3.0), seg=8)
    elif deco == "crown":  # alas y corona de oro
        for side in (-1, 1):
            for j in range(4):
                prim("box", (3.2 - j * 0.5, 0.3, 0.7), matrix @ T(side * (3.4 + j * 0.2), 0.3, 1.2 - j * 0.9)
                     @ Ry(side * (25 - j * 14)) @ T(side * 1.2, 0, 0), GOLD(), 0.15)
        for i in range(5):
            prim("cone", (0.8, 0.5, 1.8 - abs(i - 2) * 0.35), matrix @ T((i - 2) * 0.9, 0.2, 3.7), GOLD(), seg=6)
        prim("box", (4.6, 0.6, 0.5), matrix @ T(0, 0.2, 3.3), GOLD(), 0.1)
    elif deco == "ice":  # pinchos de hielo
        ice = mat(rgb(150, 230, 255), emit=1.5, rough=0.05)
        for i in range(10):
            a = 360 * i / 10 + 18
            prim("cone", (1.0, 1.0, rng.uniform(2.0, 3.0)), matrix @ Ry(a) @ T(0, 0, 3.2) @ T(0, 0, 0.9), ice, seg=4)
    elif deco == "cosmic":  # órbita y estrellas
        torus(4.6, 0.22, matrix @ Rx(90) @ Rx(68) @ Ry(-20), mat(rgb(220, 220, 255), emit=1.4, metal=0.6, rough=0.2))
        for i in range(6):
            a = rng.uniform(0, 6.28)
            prim("sphere", (0.5, 0.5, 0.5), matrix @ T(math.cos(a) * 4.2, -0.8, math.sin(a) * 4.2), glow, seg=10)
    return matrix @ Vector((0, 0, 0))


def scene_noob_pro():
    reset()
    rng = random.Random(13)
    world((0.9, 0.85, 0.95), 0.55)
    camera((0, -36, 5.4), (0, 0, 6.6), 30)
    sun((0.4, 0.75, -0.55), (1, 0.95, 0.85), 2.2)
    ground(rgb(176, 160, 150))
    prim("cyl", (40, 40, 0.1), T(15, 4, 0.02), mat(rgb(60, 40, 80), rough=0.6), seg=48)  # suelo morado del pro

    # El noob: espada de madera, cofre pequeño y cuatro monedas.
    noob = T(-9.6, -8, 0) @ Rz(22) @ Sc(1.6)
    arm = (-62, 0, -12)
    character(noob, arm_l=(-8, 18, 0), arm_r=arm, head=(-6, 0, -8), mouth="sad", sweat=True)
    weapon(1, T(*hand(noob, 1, arm)) @ Ry(38) @ Rx(-12) @ Sc(1.2), rgb(150, 105, 60), glow=0.0)
    lamp((-12, -18, 9), (1, 0.97, 0.9), 2200, 4)
    chest(T(-15.5, -4, 0) @ Rz(24) @ Sc(0.95))
    for i in range(4):
        prim("cyl", (0.9, 0.9, 0.15), T(-12.5 + i * 0.8, -6.5 + i * 0.3, 0.1 + 0.15 * (i % 2)) @ Rx(6), GOLD(), seg=20)
    piece("Torii", T(-24, 30, 0) @ Rz(12) @ Sc(1.35))
    piece("Sakura", T(-40, 38, 0) @ Rz(40) @ Sc(1.4))
    piece("SakuraB", T(-8, 60, 0) @ Rz(200) @ Sc(1.4))
    piece("Komainu", T(-22, 8, 0) @ Rz(180 + 35) @ Sc(1.1))
    piece("StoneLantern", T(-4, 12, 0) @ Sc(1.2))
    piece("Pagoda", T(-30, 120, 0) @ Sc(1.8))
    piece("Fuji", T(-330, 620, -4))

    # El pro: ropa oscura, corona, ojos que brillan, espada de galaxia gigante y montones de oro.
    pro = T(8.6, -6, 0) @ Rz(-18) @ Sc(1.7)
    arm = (-55, 0, -25)
    character(pro, look=PRO, arm_l=arm, arm_r=(-30, -60, 0), head=(-4, 0, 10), mouth="grin", eyes=rgb(200, 90, 255),
              brows="angry")
    trim = mat(PURPLE, emit=2.5)
    for side in (-1, 1):  # hombreras
        prim("box", (1.3, 1.3, 0.55), pro @ T(1.5 * side, 0, 4.05) @ Ry(-12 * side), mat(rgb(40, 30, 60), metal=0.5, rough=0.3), 0.18)
        prim("box", (1.36, 1.36, 0.14), pro @ T(1.5 * side, 0, 3.8) @ Ry(-12 * side), trim, 0.04)
    prim("box", (2.06, 1.06, 0.22), pro @ T(0, 0, 2.15), GOLD(), 0.05)
    prim("box", (0.18, 1.04, 1.9), pro @ T(0, 0, 3.0), trim, 0.03)
    prim("box", (3.4, 0.16, 4.6), pro @ T(0, 0.72, 2.7) @ Rx(10), mat(rgb(30, 18, 50), rough=0.5), 0.05)  # capa
    prim("cyl", (1.45, 1.45, 0.35), pro @ T(0, 0, 5.62), GOLD(), seg=24)  # corona
    for i in range(6):
        prim("cone", (0.4, 0.4, 0.7), pro @ Rz(60 * i) @ T(0.62, 0, 5.95), GOLD(), seg=6)
    prim("box", (0.3, 0.12, 0.3), pro @ T(0, -0.72, 5.65) @ Ry(45), mat(PURPLE, emit=3), 0.02)
    grip = hand(pro, -1, arm)
    weapon(16, T(*grip) @ Rz(-15) @ Ry(122) @ Rx(-8) @ Sc(1.5), rgb(120, 40, 220), glow=0.6, accent=rgb(255, 120, 255),
           blade=galaxy(), width=1.25)
    lamp((10, -16, 8), (0.8, 0.45, 1), 2600, 3)
    lamp((18, -8, 2), (1, 0.4, 1), 1800, 3)
    for i in range(40):  # chispas de energía alrededor
        p = Vector((8.6, -6, 5)) + Vector((rng.uniform(-6, 6), rng.uniform(-3, 3), rng.uniform(-4, 5)))
        prim("sphere", (0.25, 0.25, 0.25), T(*p), mat(mix(PURPLE, WHITE, rng.uniform(0, 0.6)), emit=6), seg=8)
    gems = pile((16, -3, 0), 5.5, 3.0, 70, rng)
    gems += pile((3.5, -2, 0), 3.2, 1.6, 30, rng)
    gems += pile((22, 5, 0), 4, 2.4, 30, rng)
    chest(T(13, 3, 0) @ Rz(-20) @ Sc(1.3), opened=True)
    chest(T(23.5, -6, 0) @ Rz(-40) @ Sc(1.2), opened=True)
    swirl = portal((16, 26, 0), 16, 22, rng)
    temple = {"Red": rgb(110, 30, 70), "Roof": rgb(40, 24, 70), "Wood": rgb(70, 40, 60), "White": rgb(120, 100, 150)}
    piece("Temple", T(26, 80, 0) @ Rz(180) @ Sc(0.5), tint=temple)
    piece("Komainu", T(6, 14, 0) @ Rz(180 - 30) @ Sc(1.1), tint={"Stone": rgb(110, 100, 130), "StoneDark": rgb(70, 60, 90)})

    sparkles = [(project(p) + (rng.uniform(26, 46), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    sparkles += [(project(grip) + (90, (1, 0.85, 1)))]
    render(
        "noobpro",
        sky=[(0.0, rgb(255, 235, 240)), (0.45, rgb(140, 205, 255)), (1.0, rgb(50, 140, 250))],
        sky2=[(0.0, rgb(255, 130, 220)), (0.45, rgb(150, 60, 210)), (1.0, rgb(36, 14, 80))],
        clouds=[(200, 640, 120), (600, 760, 100), (330, 930, 90)],
        rays=dict(center=project(swirl), color=(0.85, 0.45, 1.0), count=16, alpha=0.5, reach=900, core=300,
                  core_color=(0.9, 0.6, 1), core_alpha=0.5),
        sparkles=sparkles, divider=(1000, 860, 18),
        labels=[
            label("NOOB", 450, 125, 170, -3, "#FFFFFF", "#C9D6EA"),
            label("VS", 950, 140, 150, -8, "#FFE066", "#FF3B1F"),
            label("PRO", 1430, 125, 190, -3, "#FFF36B", "#FF9A1F"),
        ],
    )


def scene_dungeon():
    reset()
    rng = random.Random(17)
    world((1.0, 0.75, 0.95), 0.55)
    camera((0, -34, 3.2), (1.5, 0, 10.5), 27)
    sun((0.35, 0.8, -0.5), (1, 0.85, 0.85), 1.8)
    ground(rgb(120, 108, 128))
    step = mat(rgb(96, 88, 112), rough=0.85)
    for i in range(6):  # escalera hasta el portal
        prim("box", (24 - i * 1.2, 2.2, 0.5 * (i + 1)), T(2, 4 + i * 2.2, 0.25 * (i + 1)), step, 0.08)
    swirl = portal((2, 18, 3.0), 22, 28, rng)
    # Slimes saliendo del portal: el jefe dentro, y tres bajando la escalera.
    slime(T(2, 22, 8) @ Sc(4.2), rgb(120, 40, 200), eyes=rgb(255, 80, 255))
    slime(T(-4, 9, 1.5) @ Rz(15) @ Sc(1.6), rgb(170, 80, 255))
    slime(T(8, 8, 1.5) @ Rz(-20) @ Sc(1.8), rgb(130, 60, 240))
    slime(T(3, 13, 2.5) @ Sc(1.3), rgb(200, 90, 255), horns=False)
    for i in range(10):  # rocas flotando alrededor del portal
        a = rng.uniform(0, math.pi)
        p = Vector((2 + math.cos(a) * 15, 16, 17 + math.sin(a) * 14))
        prim("box", [rng.uniform(0.8, 1.8)] * 3, T(*p) @ Rz(rng.uniform(0, 90)) @ Rx(rng.uniform(0, 90)),
             mat(rgb(60, 50, 80), rough=0.8), 0.1)

    temple = {"Red": rgb(190, 40, 60), "Roof": rgb(40, 30, 70)}
    piece("Temple", T(2, 75, 0) @ Rz(180) @ Sc(0.5), tint=temple)
    piece("Torii", T(-27, 24, 0) @ Rz(-10) @ Sc(1.5))
    piece("Torii", T(31, 24, 0) @ Rz(10) @ Sc(1.5))
    piece("Komainu", T(-14, 1, 0) @ Rz(180 + 30) @ Sc(1.3))
    piece("Komainu", T(18, 1, 0) @ Rz(180 - 30) @ Sc(1.3))
    piece("Sakura", T(-40, 40, 0) @ Rz(40) @ Sc(1.6))
    piece("SakuraB", T(42, 42, 0) @ Rz(200) @ Sc(1.6))
    piece("Pagoda", T(-48, 110, 0) @ Sc(1.9))
    piece("Pagoda", T(55, 120, 0) @ Rz(30) @ Sc(1.7))

    # El héroe, de espaldas, con la espada de galaxia en alto.
    hero = T(-8.5, -11, -1.2) @ Rz(180 + 28) @ Sc(1.7)
    arm = (0, -45, 0)
    character(hero, look=PRO, arm_l=(-60, -20, 0), arm_r=arm, head=(0, 0, -10))
    prim("box", (2.1, 1.1, 0.3), hero @ T(0, 0, 3.95), mat(rgb(220, 30, 40)), 0.1)
    grip = hand(hero, 1, arm)
    weapon(16, T(*grip) @ Rz(180 + 28) @ Ry(-35) @ Sc(1.45), rgb(120, 40, 220), glow=0.6, accent=rgb(255, 120, 255),
           blade=galaxy(), width=1.25)
    lamp((-10, -24, 9), (1, 0.6, 0.9), 2500, 4)

    gems = pile((-17, -4, 0), 5, 2.6, 50, rng)
    gems += pile((21, -5, 0), 5.5, 3.0, 55, rng)
    chest(T(-20, 2, 0) @ Rz(30) @ Sc(1.3), opened=True)
    chest(T(24, 2, 0) @ Rz(-35) @ Sc(1.3), opened=True)

    sparkles = [(project(p) + (rng.uniform(26, 46), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    render(
        "mazmorras",
        sky=[(0.0, rgb(255, 170, 200)), (0.45, rgb(210, 110, 230)), (1.0, rgb(70, 50, 190))],
        rays=dict(center=project(swirl), color=(0.85, 0.4, 1.0), count=18, alpha=0.6, reach=1100, core=360,
                  core_color=(0.95, 0.6, 1), core_alpha=0.6),
        sparkles=sparkles,
        labels=[
            label("DUNGEONS", 1340, 760, 150, -4, "#FFE066", "#FF8A1F"),
            label("OP!", 1340, 920, 190, -4, "#F6C8FF", "#A23BFF"),
        ],
    )


def scene_trait():
    reset()
    rng = random.Random(23)
    world((1.0, 0.8, 0.95), 0.55)
    camera((0, -38, 6.0), (0, 0, 10.0), 28)
    sun((0.35, 0.8, -0.5), (1, 0.92, 0.9), 2.0)
    ground(rgb(130, 118, 140))
    swirl = portal((0, 12, 0), 20, 30, rng)

    # La espada secreta en el centro, en diagonal, y las cuatro medallas de rasgo.
    weapon(16, T(5.5, -2, 21) @ Ry(215) @ Sc(2.3), rgb(120, 40, 220), glow=0.7, accent=rgb(255, 120, 255),
           blade=galaxy(), width=1.25)
    lamp((0, -12, 12), (0.85, 0.5, 1), 4000, 5)
    tops = []
    for x, z, base, rim, deco in (
        (-13.5, 18.0, rgb(200, 40, 30), rgb(255, 170, 60), "fire"),
        (-15.0, 6.5, rgb(150, 90, 20), rgb(255, 210, 80), "crown"),
        (13.5, 18.0, rgb(30, 70, 200), rgb(140, 230, 255), "ice"),
        (15.0, 6.5, rgb(70, 30, 140), rgb(220, 210, 255), "cosmic"),
    ):
        tops.append(medallion(T(x, -6, z) @ Rz(-x * 1.2) @ Sc(0.95), base, rim, deco, rng))
        lamp((x, -12, z), mix(rim, WHITE, 0.3), 1200, 3)

    piece("Torii", T(-28, 24, 0) @ Rz(-10) @ Sc(1.6))
    piece("Sakura", T(-44, 36, 0) @ Rz(40) @ Sc(1.6))
    piece("SakuraB", T(40, 34, 0) @ Rz(200) @ Sc(1.6))
    piece("Pagoda", T(36, 80, 0) @ Rz(20) @ Sc(1.9))
    piece("Pagoda", T(-40, 110, 0) @ Sc(1.8))
    piece("Komainu", T(-21, 4, 0) @ Rz(180 + 30) @ Sc(1.3))
    gems = pile((-19, -8, 0), 5.5, 2.8, 55, rng)
    gems += pile((19, -8, 0), 5.5, 2.8, 55, rng)
    chest(T(-24, -2, 0) @ Rz(30) @ Sc(1.3), opened=True)
    chest(T(24, -2, 0) @ Rz(-30) @ Sc(1.3), opened=True)
    burst(Vector((0, -4, 10)), 40, rng, spread=(20, 4, 12), kinds=("gem", "coin"), size=0.8)

    sparkles = [(project(p) + (rng.uniform(26, 46), mix(c, WHITE, 0.6))) for p, c in gems[::3]]
    sparkles += [(project(p) + (70, (1, 0.95, 0.85))) for p in tops]
    render(
        "rasgo",
        sky=[(0.0, rgb(255, 180, 210)), (0.5, rgb(170, 120, 240)), (1.0, rgb(60, 110, 240))],
        rays=dict(center=project(swirl), color=(0.85, 0.45, 1.0), count=20, alpha=0.55, reach=1200, core=380,
                  core_color=(0.95, 0.65, 1), core_alpha=0.55),
        sparkles=sparkles,
        labels=[
            label("SECRET", 960, 740, 150, -2, "#FFFFFF", "#E2CCFF"),
            label("TRAIT!", 960, 925, 210, -2, "#FFF36B", "#FF9A1F"),
        ],
    )


SCENES = {"tajo": scene_slice, "rangos": scene_ranks, "principal": scene_main, "rarezas": scene_rarities, "bolsa": scene_bag,
          "herrero": scene_smith, "noobpro": scene_noob_pro, "mazmorras": scene_dungeon, "rasgo": scene_trait}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenes", nargs="*", default=list(SCENES))
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    for name in args.scenes:
        SCENES[name]()


main()