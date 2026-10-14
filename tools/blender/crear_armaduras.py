# Crea en Blender los modelos de las armaduras: un diseño por mazmorra (Config.Dungeons, por su posición) y cuatro
# huecos (casco, pechera, grebas, botas), y los exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_armaduras.py [-- --only 3 7]
# Deja armaduras.blend, armaduras.fbx y vistas armaduras_<n>.png en Documents\Roblox\modelos. Las mallas se pasan
# al juego como src/shared/ArmorMeshes.rbxmx (ver shared/ArmorModel).
#
# Las piezas se diseñan sobre el cuerpo R15 de verdad (tools/blender/cuerpo_r15.obj, sacado de Studio con el
# personaje por defecto: raíz en el origen, Y arriba, -Z al frente, en studs) y cada trozo va pegado a una parte del
# cuerpo: el casco a la cabeza; la pechera al torso, los brazos y las manos (hombreras, brazales, guanteletes, capa);
# las grebas a los muslos y las piernas (escarcelas, musleras, rodilleras); las botas a los pies.
# Mallas "A<mazmorra>_<hueco>_<Parte>_<Papel>", con las coordenadas del cuerpo en reposo (REST) desplazadas por
# "A<mazmorra>_Origin". Papeles: Base = color y material de la mazmorra, Dark = su sombra, Trim = color de la calidad
# de la pieza, Gem = cristal del color de la zona, Glow = luz de la zona, Cloth = tela del color de la zona.
# Axis_* dan la escala y los ejes de la importación.
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos")
BODY_OBJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cuerpo_r15.obj")

# Centro y tamaño de cada parte del cuerpo R15 en reposo (iguales a REST de shared/ArmorModel).
REST = {
    "Head": ((0, 1.586, 0), (1.159, 1.182, 1.161)),
    "UpperTorso": ((0, 0.2, 0), (1.943, 1.698, 1.004)),
    "LowerTorso": ((0, -0.8, 0), (1.991, 0.401, 1.004)),
    "LeftUpperArm": ((-1.5, 0.369, 0), (1.001, 1.242, 1.002)),
    "RightUpperArm": ((1.5, 0.369, 0), (1.001, 1.242, 1.002)),
    "LeftLowerArm": ((-1.5, -0.224, 0), (1.001, 1.118, 1.002)),
    "RightLowerArm": ((1.5, -0.224, 0), (1.001, 1.118, 1.002)),
    "LeftHand": ((-1.5, -0.85, 0), (0.984, 0.316, 1.028)),
    "RightHand": ((1.5, -0.85, 0), (0.984, 0.316, 1.028)),
    "LeftUpperLeg": ((-0.5, -1.421, 0), (0.993, 1.363, 0.973)),
    "RightUpperLeg": ((0.5, -1.421, 0), (0.993, 1.363, 0.973)),
    "LeftLowerLeg": ((-0.5, -2.201, 0), (0.993, 1.301, 0.973)),
    "RightLowerLeg": ((0.5, -2.201, 0), (0.993, 1.301, 0.973)),
    "LeftFoot": ((-0.5, -2.85, 0), (1.009, 0.312, 1.001)),
    "RightFoot": ((0.5, -2.85, 0), (1.009, 0.312, 1.001)),
}
HEAD_Y, ARM_X, LEG_X = 1.586, 1.5, 0.5
SIDES = (-1, 1)

ROLE_COLORS = {  # solo para verlo en Blender; en el juego manda ArmorModel
    "Base": (0.6, 0.6, 0.65, 1), "Dark": (0.2, 0.2, 0.25, 1), "Trim": (0.95, 0.75, 0.25, 1),
    "Gem": (0.5, 0.9, 1, 1), "Glow": (1, 0.85, 0.4, 1), "Cloth": (0.3, 0.5, 0.3, 1), "Marker": (1, 0, 1, 1),
    "Body": (0.82, 0.74, 0.62, 1),
}
# armorColor y color de cada zona (Config.Dungeons), solo para la vista previa.
BASE = [(150, 105, 65), (175, 180, 192), (58, 50, 82), (165, 40, 52), (88, 62, 200), (200, 70, 30),
        (60, 40, 110), (205, 85, 150), (45, 70, 190), (30, 60, 80), (240, 240, 250), (215, 35, 55)]
ACCENT = [(90, 210, 110), (240, 170, 70), (160, 125, 225), (235, 70, 80), (50, 200, 210), (255, 110, 40),
          (130, 70, 255), (230, 90, 160), (60, 110, 255), (60, 255, 170), (240, 245, 255), (255, 40, 60)]
SLOTS = ["helmet", "chest", "legs", "boots"]


def side(name, s):
    return ("Left" if s < 0 else "Right") + name


# ---------- Matrices (ejes del juego; se pasan a Blender al final) ----------

def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def R(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def S(sx, sy=None, sz=None):
    sy = sx if sy is None else sy
    sz = sx if sz is None else sz
    return Matrix.Diagonal((sx, sy, sz, 1))


def MX(s):
    """Espejo en X para el lado izquierdo (s = -1)."""
    return S(s, 1, 1)


# ---------- Formas: (vértices, caras) ----------

def box(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    verts = [(a, b, c) for a in (-x, x) for b in (-y, y) for c in (-z, z)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces


def from_bm(bm):
    bm.verts.ensure_lookup_table()
    index = {v: i for i, v in enumerate(bm.verts)}
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(index[v] for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


def bevel(shape, r=0.025, seg=2, angle=30):
    """Redondea las aristas vivas de una forma."""
    verts, faces = shape
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > math.radians(angle)]
    if edges:
        try:
            bmesh.ops.bevel(bm, geom=edges, offset=r, segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
        except Exception:
            pass
    return from_bm(bm)


def rbox(sx, sy, sz, r=0.03, seg=2):
    r = min(r, sx * 0.45, sy * 0.45, sz * 0.45)
    return bevel(box(sx, sy, sz), r, seg)


def lathe(profile, n=12):
    """Sólido de revolución sobre Y: profile = [(radio, y)] de abajo a arriba. Radio 0 = punta."""
    verts, rings = [], []
    for r, y in profile:
        start = len(verts)
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append((r * math.cos(a), y, r * math.sin(a)))
        rings.append(start)
    faces = []
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        faces += [(a + i, a + (i + 1) % n, b + (i + 1) % n, b + i) for i in range(n)]
    if profile[0][0] > 0:
        faces.append(tuple(rings[0] + i for i in reversed(range(n))))
    if profile[-1][0] > 0:
        faces.append(tuple(rings[-1] + i for i in range(n)))
    return verts, faces


def sphere(r, n=10, rings=6):
    return lathe([(r * math.cos(math.pi * j / rings - math.pi / 2) if 0 < j < rings else 0,
                   r * math.sin(math.pi * j / rings - math.pi / 2)) for j in range(rings + 1)], n)


def rivet(r=0.035):
    return lathe([(r, 0), (r * 0.85, r * 0.5), (r * 0.45, r * 0.85), (0, r)], 6)


def crystal(r, h, n=6, tip=0.3):
    return lathe([(r * 0.8, 0), (r, h * 0.12), (r, h * (1 - tip)), (0, h)], n)


def gem(r, h=None, n=6):
    h = h or r * 2
    return lathe([(0, -h / 2), (r, 0), (0, h / 2)], n)


def cut_gem(r, n=8):
    """Gema tallada mirando a +Y (corona plana arriba)."""
    return lathe([(0, -r * 0.9), (r, 0), (r * 0.62, r * 0.38), (0.0001, r * 0.4)], n)


def spike(r, h, n=6):
    return lathe([(r, 0), (r * 0.55, h * 0.5), (0, h)], n)


def torus(R_, r, n=20, m=5):
    verts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            d = R_ + r * math.cos(b)
            verts.append((d * math.cos(a), r * math.sin(b), d * math.sin(a)))
    faces = []
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            faces.append((i * m + j, i2 * m + j, i2 * m + j2, i * m + j2))
    return verts, faces


def se_point(a, rx, rz, e):
    """Punto de una superelipse en el ángulo a (0 = frente, -Z; 90° = +X). e = 2 elipse, más = más cuadrada."""
    s, c = math.sin(a), math.cos(a)
    x = rx * math.copysign(abs(s) ** (2 / e), s)
    z = -rz * math.copysign(abs(c) ** (2 / e), c)
    return x, z


def angles(span, face, n):
    full = span >= 359.9
    a0 = math.radians(face - span / 2)
    return [a0 + math.radians(span) * k / n for k in range(n if full else n + 1)], full


def ring_point(ring, a, e, keel, keel_w, inset=0.0):
    y, rx, rz = ring[0], ring[1], ring[2]
    cx = ring[3] if len(ring) > 3 else 0
    cz = ring[4] if len(ring) > 4 else 0
    kl = ring[5] if len(ring) > 5 else keel
    x, z = se_point(a, max(rx - inset, 0.004), max(rz - inset, 0.004), e)
    d = abs(math.atan2(math.sin(a), math.cos(a)))
    z -= kl * max(0.0, 1 - d / math.radians(keel_w)) ** 1.5
    return (x + cx, y, z + cz)


def loft(rings, e=2.0, thick=0.07, span=360, face=0, n=20, keel=0.0, keel_w=40):
    """Placa con grosor que rodea el eje Y: rings = [(y, rx, rz, cx=0, cz=0, quilla=keel)] de abajo a arriba.
    span < 360 la deja abierta, centrada en el ángulo face (0 = frente). keel saca una arista por delante."""
    angs, full = angles(span, face, n)
    cols = len(angs)
    verts, outer, inner = [], [], []
    for ring in rings:
        o, i = [], []
        for a in angs:
            o.append(len(verts))
            verts.append(ring_point(ring, a, e, keel, keel_w))
            i.append(len(verts))
            verts.append(ring_point(ring, a, e, keel, keel_w, thick))
        outer.append(o)
        inner.append(i)
    faces = []
    segs = cols if full else cols - 1
    for j in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % cols
            faces.append((outer[j][k], outer[j][k2], outer[j + 1][k2], outer[j + 1][k]))
            faces.append((inner[j][k2], inner[j][k], inner[j + 1][k], inner[j + 1][k2]))
    for j in (0, len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % cols
            faces.append((outer[j][k], inner[j][k], inner[j][k2], outer[j][k2]))
    if not full:
        for j in range(len(rings) - 1):
            for k in (0, cols - 1):
                faces.append((outer[j][k], outer[j + 1][k], inner[j + 1][k], inner[j][k]))
    return verts, faces


def ring_points(ring, e=2.0, span=360, face=0, n=24, keel=0.0, keel_w=40, out=0.0):
    angs, full = angles(span, face, n)
    pts = [ring_point(ring, a, e, keel, keel_w, -out) for a in angs]
    return pts, full


def dome_rings(rx, ry, rz, lat0=0, lat1=90, k=6, y0=0.0):
    rings = []
    for j in range(k + 1):
        lat = math.radians(lat0 + (lat1 - lat0) * j / k)
        c = max(math.cos(lat), 0.02)
        rings.append((y0 + ry * math.sin(lat), rx * c, rz * c))
    return rings


def sweep(path, radii, m=6, closed=False, flat=1.0):
    """Tubo a lo largo de path; radii = número o lista (0 = punta). flat aplasta la sección."""
    pts = [Vector(p) for p in path]
    count = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * count
    tangents = []
    for i in range(count):
        if closed:
            t = pts[(i + 1) % count] - pts[i - 1]
        else:
            t = pts[min(i + 1, count - 1)] - pts[max(i - 1, 0)]
        tangents.append(t.normalized())
    ref = Vector((0, 1, 0)) if abs(tangents[0].y) < 0.9 else Vector((1, 0, 0))
    normal = tangents[0].cross(ref).normalized()
    verts, starts = [], []
    for i in range(count):
        if i > 0:
            axis = tangents[i - 1].cross(tangents[i])
            if axis.length > 1e-6:
                normal = Matrix.Rotation(tangents[i - 1].angle(tangents[i]), 3, axis.normalized()) @ normal
        binormal = tangents[i].cross(normal)
        starts.append(len(verts))
        r = max(radii[i], 0.003)
        for j in range(m):
            a = 2 * math.pi * j / m
            verts.append(tuple(pts[i] + (normal * math.cos(a) * flat + binormal * math.sin(a)) * r))
    faces = []
    for i in range(count if closed else count - 1):
        a, b = starts[i], starts[(i + 1) % count]
        faces += [(a + j, a + (j + 1) % m, b + (j + 1) % m, b + j) for j in range(m)]
    if not closed:
        faces.append(tuple(starts[0] + j for j in reversed(range(m))))
        faces.append(tuple(starts[-1] + j for j in range(m)))
    return verts, faces


def bezier(p0, p1, p2, p3, steps=10):
    p0, p1, p2, p3 = Vector(p0), Vector(p1), Vector(p2), Vector(p3)
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(tuple(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3))
    return out


def taper(count, r0, r1=0.0, power=1.0):
    return [r0 + (r1 - r0) * (i / (count - 1)) ** power for i in range(count)]


def extrude(points, thick, round_=0.0):
    """Polígono (x, y) en el plano XY con grosor en Z (puede ser cóncavo). round_ redondea los cantos."""
    n = len(points)
    verts = [(x, y, -thick / 2) for x, y in points] + [(x, y, thick / 2) for x, y in points]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    shape = (verts, faces)
    return bevel(shape, round_, 1, 50) if round_ > 0 else shape


def leaf_pts(length, width, n=8, tip=1.0):
    right = [(width * math.sin(math.pi * t) ** 0.8 * (1 - 0.35 * t), length * t) for t in (i / n for i in range(1, n))]
    return [(0, 0)] + right + [(0, length * tip)] + [(-x, y) for x, y in reversed(right)]


def feather_pts(length, width, n=7):
    right = [(width * (math.sin(math.pi * min(t * 1.1, 1)) ** 0.6) * (1 - 0.5 * t), length * t) for t in (i / n for i in range(1, n))]
    return [(0.02, 0)] + right + [(0, length)] + [(-x * 0.7, y) for x, y in reversed(right)] + [(-0.02, 0)]


def blade_pts(length, width, guard=0.0):
    return [(-width * 0.35, 0), (width * 0.35, 0), (width / 2, length * 0.25), (width * 0.3, length * 0.8), (0, length),
            (-width * 0.3, length * 0.8), (-width / 2, length * 0.25)]


def flame_pts(height, width, waves=2):
    right, left = [], []
    n = 10
    for i in range(n + 1):
        t = i / n
        w = width / 2 * (1 - t) ** 0.8 * (1 + 0.25 * math.sin(t * math.pi * waves * 2))
        right.append((w + 0.12 * width * math.sin(t * 5), height * t))
        left.append((-w + 0.12 * width * math.sin(t * 5 + 1.5), height * t * 0.92))
    return right + [(0.05 * width, height)] + list(reversed(left))


def star_pts(points, r_out, r_in):
    out = []
    for i in range(points * 2):
        a = math.pi / 2 + math.pi * i / points
        r = r_out if i % 2 == 0 else r_in
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def fan_pts(r_in, r_out, a0, a1, n=8, scallop=0.0):
    """Abanico (sector de corona) entre los ángulos a0 y a1 en grados."""
    outer = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        r = r_out * (1 - scallop * abs(math.sin(i * math.pi)))
        outer.append((r * math.cos(a), r * math.sin(a)))
    inner = [(r_in * math.cos(math.radians(a)), r_in * math.sin(math.radians(a))) for a in (a1, a0)]
    return outer + inner


class Piece:
    def __init__(self):
        self.parts = {}

    def add(self, limb, role, shape, matrix=None):
        verts, faces = shape
        matrix = matrix or Matrix.Identity(4)
        mine = self.parts.setdefault((limb, role), ([], []))
        base = len(mine[0])
        mine[0].extend(tuple(matrix @ Vector(v)) for v in verts)
        mine[1].extend(tuple(base + i for i in f) for f in faces)

    def rim(self, limb, role, ring, r=0.03, e=2.0, span=360, face=0, n=24, keel=0.0, out=0.0, m=5, flat=1.0, matrix=None):
        pts, full = ring_points(ring, e, span, face, n, keel, 40, out)
        self.add(limb, role, sweep(pts, r, m, full, flat), matrix)

    def rivets(self, limb, role, ring, count, e=2.0, span=360, face=0, keel=0.0, r=0.035, matrix=None):
        angs, full = angles(span, face, count if span >= 359.9 else count - 1)
        for a in angs:
            x, y, z = ring_point(ring, a, e, keel, 40, -0.01)
            m = Matrix.Translation((x, y, z)) @ (Vector((0, 1, 0)).rotation_difference(Vector((x - (ring[3] if len(ring) > 3 else 0), 0, z - (ring[4] if len(ring) > 4 else 0))).normalized()).to_matrix().to_4x4())
            self.add(limb, role, rivet(r), (matrix or Matrix.Identity(4)) @ m)


def aim(direction):
    """Matriz que gira +Y hacia direction."""
    return Vector((0, 1, 0)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()


# ---------- Piezas comunes (coordenadas del cuerpo en reposo) ----------

E = 4.5  # superelipse de lo que rodea brazos, piernas y torso (el cuerpo R15 es casi cuadrado)


def cuirass(p, role="Base", e=E, keel=0.05, chest=0.05, low=-0.62, n=28, thick=0.06):
    rings = [(low, 1.03, 0.57), (low + 0.3, 1.02, 0.56), (0.2, 1.04, 0.57 + chest), (0.6, 1.05, 0.58 + chest * 0.6),
             (0.95, 1.02, 0.57), (1.1, 0.82, 0.5), (1.16, 0.52, 0.42)]
    p.add("UpperTorso", role, loft(rings, e, thick, n=n, keel=keel))
    return rings


def belt(p, role="Dark", y0=-0.98, y1=-0.6, r=1.08, buckle="Trim", buckle_shape=None):
    rings = [(y0, r, 0.6), (y1, r, 0.6)]
    p.add("LowerTorso", role, loft(rings, 4, 0.05, n=24))
    if buckle:
        p.add("LowerTorso", buckle, buckle_shape or rbox(0.38, 0.32, 0.08, 0.04), T(0, (y0 + y1) / 2, -0.63))
    return rings


def lames(p, limb, role, y_top, count, height, r, rz=None, step=0.12, grow=0.0, e=E, span=360, face=0, rim=None,
          rim_r=0.025, n=24, cx=0.0, cz=0.0, flare=0.02):
    """Bandas que se solapan hacia abajo (faldas, escarcelas)."""
    rz = rz or r * 0.56
    for k in range(count):
        top = y_top - step * k
        rr, rrz = r + grow * k, rz + grow * k
        ring_b = (top - height, rr + flare, rrz + flare, cx, cz)
        p.add(limb, role, loft([ring_b, (top, rr, rrz, cx, cz)], e, 0.05, span, face, n))
        if rim:
            p.rim(limb, rim, ring_b, rim_r, e, span, face, n)


def pauldron(p, s, role="Base", trim="Trim", dark="Dark", r=0.72, h=0.5, tilt=20, layers=3, lame=0.13, rivets=True,
             y=0.93, rim_r=0.035, top=90):
    """Hombrera redonda con láminas por debajo, en el brazo del lado s."""
    limb = side("UpperArm", s)
    m = T(s * 1.52, y, 0) @ R("Z", -s * tilt)
    p.add(limb, role, loft(dome_rings(r, h, r * 0.96, -8, top, 6), 2.2, 0.07, n=22), m)
    p.rim(limb, trim, (h * math.sin(math.radians(-8)), r * 1.0, r * 0.96), rim_r, 2.2, n=22, matrix=m)
    for k in range(layers):
        yy = -0.06 - lame * (k + 1)
        rr = r * (0.97 - 0.05 * k)
        ring = (yy, rr + 0.02, rr * 0.96 + 0.02)
        p.add(limb, role if k % 2 else dark, loft([ring, (yy + lame + 0.02, rr, rr * 0.96)], 2.4, 0.05, 230, s * 90, 18), m)
        p.rim(limb, trim, ring, rim_r * 0.7, 2.4, 230, s * 90, 18, matrix=m)
    if rivets:
        p.rivets(limb, trim, (0.0, r * 0.98, r * 0.94), 7, 2.2, 200, s * 90, r=0.04, matrix=m)
    return m


def rerebrace(p, s, role="Base", y0=-0.1, y1=0.62, r=0.57, rim="Trim"):
    limb = side("UpperArm", s)
    rings = [(y0, r + 0.02, r + 0.02, s * ARM_X), (y1, r, r, s * ARM_X)]
    p.add(limb, role, loft(rings, E, 0.05, n=20))
    if rim:
        p.rim(limb, rim, rings[0], 0.025, E, n=20)


def vambrace(p, s, role="Base", y0=-0.74, y1=0.12, r=0.565, flare=0.07, rim="Trim", couter="Base", couter_trim="Trim"):
    limb = side("LowerArm", s)
    rings = [(y0, r + flare, r + flare, s * ARM_X), (y0 + 0.12, r + 0.01, r + 0.01, s * ARM_X), (y1 - 0.2, r, r, s * ARM_X),
             (y1, r + 0.02, r + 0.02, s * ARM_X)]
    p.add(limb, role, loft(rings, E, 0.05, n=20))
    if rim:
        p.rim(limb, rim, rings[0], 0.03, E, n=20)
        p.rim(limb, rim, rings[-1], 0.025, E, n=20)
    if couter:
        m = T(s * ARM_X, 0.06, 0.5) @ R("X", 90)
        p.add(limb, couter, loft(dome_rings(0.32, 0.18, 0.32, 0, 90, 4), 2, 0.05, n=14), m)
        if couter_trim:
            p.add(limb, couter_trim, rivet(0.06), m @ T(0, 0.17, 0))


def gauntlet(p, s, role="Base", knuckle="Dark", trim="Trim", cuff=0.0):
    limb = side("Hand", s)
    x = s * ARM_X
    rings = [(-1.075, 0.06, 0.06, x), (-1.05, 0.44, 0.47, x), (-0.98, 0.56, 0.59, x), (-0.68, 0.58, 0.6, x)]
    p.add(limb, role, loft(rings, 4, 0.05, n=20))
    for k in range(3):  # nudillos en la cara de fuera
        p.add(limb, knuckle, rbox(0.06, 0.07, 0.7 - 0.06 * k, 0.025), T(x + s * 0.6, -0.78 - 0.08 * k, 0))
    p.rim(limb, trim, rings[-1], 0.03, 4, n=20)
    if cuff:
        lim = side("LowerArm", s)
        cring = (-0.76, 0.58 + cuff, 0.58 + cuff, x)
        p.add(lim, role, loft([cring, (-0.5, 0.58, 0.58, x)], E, 0.05, n=20))
        p.rim(lim, trim, cring, 0.03, E, n=20)


def cape(p, role="Cloth", trim=None, length=2.0, width=1.0, flare=0.5, tatter=0.0, cols=12, y_top=0.98, slit=0.0):
    """Capa a la espalda, colgada del torso. tatter = jirones en el borde; slit = abertura central."""
    rows = 7
    verts, faces = [], []
    grid = []
    for j in range(rows + 1):
        t = j / rows
        y = y_top - length * t
        rx = 0.62 * width + 0.55 * width * t
        rz = 0.56 + 0.3 * t
        cz = 0.06 + flare * t * t
        row = []
        for k in range(cols + 1):
            u = k / cols
            a = math.radians(180 - 70 - 40 * width + (140 + 80 * width) * u) if False else math.radians(105 + 150 * u)
            x, z = se_point(a, rx, rz, 2.6)
            yy = y
            if j == rows and tatter:
                yy -= tatter * (0.5 + 0.5 * math.cos(u * cols * math.pi))
            if slit and j > 2 and abs(u - 0.5) < 0.02:
                pass
            row.append(len(verts))
            verts.append((x, yy, z + cz))
            verts.append((x * 0.985, yy, (z + cz) - 0.035))
        grid.append(row)
    for j in range(rows):
        for k in range(cols):
            a, b, c, d = grid[j][k], grid[j][k + 1], grid[j + 1][k + 1], grid[j + 1][k]
            faces.append((a, b, c, d))
            faces.append((b + 1, a + 1, d + 1, c + 1))
    for j in range(rows):
        for k in (0, cols):
            faces.append((grid[j][k], grid[j + 1][k], grid[j + 1][k] + 1, grid[j][k] + 1))
    for j in (0, rows):
        for k in range(cols):
            faces.append((grid[j][k], grid[j][k] + 1, grid[j][k + 1] + 1, grid[j][k + 1]))
    p.add("UpperTorso", role, (verts, faces))
    if trim:
        p.add("UpperTorso", trim, sweep([verts[grid[0][k]] for k in range(cols + 1)], 0.04, 5))


def cuisse(p, s, role="Base", y0=-1.85, y1=-0.95, r=0.56, rim="Trim", span=280):
    limb = side("UpperLeg", s)
    rings = [(y0, r, r * 0.98, s * LEG_X), (y0 + 0.4, r + 0.01, r, s * LEG_X), (y1, r + 0.03, r + 0.02, s * LEG_X)]
    p.add(limb, role, loft(rings, E, 0.05, span, s * 90 - s * 20, 20))
    if rim:
        p.rim(limb, rim, rings[0], 0.025, E, span, s * 90 - s * 20, 20)
    return rings


def tassets(p, s, role="Base", alt="Dark", trim="Trim", count=3, y_top=-0.6, height=0.26, r=0.7, span=150, face=40, step=0.17):
    limb = side("UpperLeg", s)
    for k in range(count):
        top = y_top - step * k
        rr = r - 0.015 * k
        ring_b = (top - height, rr + 0.05, rr * 0.95 + 0.05, s * LEG_X)
        p.add(limb, role if k % 2 == 0 else alt, loft([ring_b, (top, rr, rr * 0.95, s * LEG_X)], 2.6, 0.05, span, s * face, 14))
        p.rim(limb, trim, ring_b, 0.025, 2.6, span, s * face, 14)


def poleyn(p, s, role="Base", trim="Trim", wing=True, r=0.33, y=-1.68):
    limb = side("LowerLeg", s)
    m = T(s * LEG_X, y, -0.47) @ R("X", -90)
    p.add(limb, role, loft(dome_rings(r, 0.2, r, -10, 90, 5), 2, 0.05, n=16), m)
    p.rim(limb, trim, (0.2 * math.sin(math.radians(-10)), r, r), 0.03, 2, n=16, matrix=m)
    if wing:
        p.add(limb, role, extrude(fan_pts(0.12, 0.42, -60, 60, 6, 0), 0.05, 0.015),
              T(s * (LEG_X + 0.48), y, -0.18) @ R("Y", s * 90 - s * 0) @ R("Z", 0) @ S(s, 1, 1))
        p.add(limb, trim, rivet(0.05), T(s * (LEG_X + 0.52), y, -0.18) @ R("Z", -s * 90))


def greave(p, s, role="Base", y0=-2.66, y1=-1.72, r=0.56, rim="Trim", keel=0.04):
    limb = side("LowerLeg", s)
    x = s * LEG_X
    rings = [(y0, r + 0.02, r, x), (y0 + 0.3, r - 0.02, r - 0.03, x), (y0 + 0.62, r + 0.01, r + 0.02, x, 0.03), (y1, r, r, x)]
    p.add(limb, role, loft(rings, E, 0.05, n=20, keel=keel))
    if rim:
        p.rim(limb, rim, rings[0], 0.03, E, n=20, keel=keel)
        p.rim(limb, rim, rings[-1], 0.025, E, n=20, keel=keel)
    return rings


def foot_frame(s):
    """Las secciones del pie van a lo largo de Z: y local = hacia delante (-Z del juego), z local = arriba."""
    return T(s * LEG_X, -2.86, 0) @ R("X", -90)


def sabaton(p, s, role="Base", sole="Dark", trim="Trim", toe=0.0, pointy=0.0, lame_rims=2, cuff=True, cuff_role=None,
            cuff_r=0.6, cuff_top=-2.42):
    limb = side("Foot", s)
    m = foot_frame(s)
    # Secciones (adelante, medio ancho, medio alto, 0, altura del centro): el fondo queda a ras de la suela.
    # El pie R15 no sale por delante de la pierna: la puntera se alarga para que se vea como un zapato.
    rings = [(-0.65, 0.04, 0.03, 0, 0.06), (-0.63, 0.36, 0.18, 0, 0.06), (-0.55, 0.52, 0.26, 0, 0.06), (-0.3, 0.6, 0.28, 0, 0.06), (0.15, 0.6, 0.27, 0, 0.05), (0.45, 0.56, 0.23, 0, 0.0),
             (0.68 + toe, 0.46 - pointy * 0.1, 0.17, 0, -0.05), (0.84 + toe + pointy * 0.6, 0.3 - pointy * 0.15, 0.1, 0, -0.1),
             (0.9 + toe + pointy, 0.05, 0.04, 0, -0.13)]
    p.add(limb, role, loft(rings, 6, 0.05, n=20), m)
    for k in range(lame_rims):
        ring = [(0.6 + toe, 0.49, 0.19, 0, -0.035), (0.71 + toe, 0.43, 0.155, 0, -0.06), (0.8 + toe, 0.35, 0.12, 0, -0.085)][k]
        p.rim(limb, trim, ring, 0.025, 6, 230, 180, 16, matrix=m)
    length = 1.52 + toe + pointy * 0.6
    p.add(limb, sole, rbox(1.22, 0.08, length, 0.035), T(s * LEG_X, -3.05, 0.6 - length / 2))
    p.add(limb, sole, rbox(0.9, 0.1, 0.32, 0.04), T(s * LEG_X, -3.09, 0.42))  # tacón
    if cuff:
        x = s * LEG_X
        ring = (-2.74, cuff_r, cuff_r * 0.98, x)
        top = (cuff_top, cuff_r + 0.04, cuff_r + 0.03, x)
        p.add(limb, cuff_role or role, loft([ring, top], E, 0.05, n=20))
        p.rim(limb, trim, top, 0.03, E, n=20)


def helm_crown(p, role="Base", r=0.73, ry=0.8, lat0=12, cy=None, e=2.2, n=22, keel=0.0, rz=None):
    cy = HEAD_Y + 0.04 if cy is None else cy
    rz = rz or r * 1.02
    rings = dome_rings(r, ry, rz, lat0, 90, 6, cy)
    p.add("Head", role, loft(rings, e, 0.07, n=n, keel=keel))
    return rings[0]


def helm_guard(p, role="Base", top_ring=None, y0=1.02, r=0.73, rz=None, span=240, e=2.2, n=22, flare=0.04):
    """Parte baja del casco, abierta por delante para la cara."""
    rz = rz or r * 1.02
    y1 = top_ring[0] if top_ring else HEAD_Y + 0.2
    rings = [(y0, r + flare, rz + flare), (y0 + 0.25, r, rz), (y1, top_ring[1] if top_ring else r, top_ring[2] if top_ring else rz)]
    p.add("Head", role, loft(rings, e, 0.07, span, 180, n))
    return rings


# ---------- Diseños ----------
# Cada diseño es una función por hueco que recibe la Piece. Coordenadas del cuerpo en reposo (ver REST).

# 1. Bosque: cuero de explorador, correas, pelo y hojas.

def leaf(p, limb, role, m, length=0.5, width=0.18):
    p.add(limb, role, extrude(leaf_pts(length, width), 0.03, 0.01), m)
    p.add(limb, "Dark", sweep([(0, 0.02, -0.02), (0, length * 0.85, -0.02)], 0.012, 4), m)


def helm_1(p):
    # Capucha de cuero con pico atrás, ribete cosido, broche de hojas y plumas.
    hood = [(1.0, 0.82, 0.8, 0, 0.06), (1.3, 0.78, 0.8, 0, 0.08), (1.75, 0.76, 0.8, 0, 0.1), (2.05, 0.66, 0.72, 0, 0.16),
            (2.28, 0.42, 0.5, 0, 0.3), (2.4, 0.12, 0.16, 0, 0.55), (2.42, 0.02, 0.03, 0, 0.66)]
    p.add("Head", "Base", loft(hood[:4], 2.2, 0.07, 236, 180, 22))
    p.add("Head", "Base", loft(hood[3:], 2.2, 0.07, n=22))
    edge, _ = ring_points(hood[0], 2.2, 236, 180, 22)
    front = [ring_point(r, math.radians(180 + 118), 2.2, 0, 40) for r in hood[:4]]
    front2 = [ring_point(r, math.radians(180 - 118), 2.2, 0, 40) for r in hood[:4]]
    brow = ring_points(hood[3], 2.2, 124, 0, 10)[0]
    p.add("Head", "Dark", sweep(list(reversed(front)) + brow[1:-1] + front2, 0.05, 6))
    p.add("Head", "Dark", sweep(edge, 0.045, 5))
    for k in range(9):  # puntadas
        a = math.radians(180 + 110 - 220 * k / 8)
        x, y, z = ring_point(hood[1], a, 2.2, 0, 40, -0.01)
        p.add("Head", "Trim", box(0.03, 0.12, 0.03), T(x, y, z))
    m = T(0.42, 2.0, -0.55) @ R("X", -25) @ R("Z", -30)
    for k, ang in enumerate((-35, 0, 35)):
        leaf(p, "Head", "Cloth", m @ R("Z", ang) @ T(0, 0.02, 0), 0.42 - 0.06 * abs(k - 1), 0.15)
    p.add("Head", "Gem", cut_gem(0.08), m @ R("X", 90))
    p.add("Head", "Trim", torus(0.09, 0.025, 12, 4), m @ R("X", 90))
    for k, ang in enumerate((-10, 12)):  # plumas
        pm = T(0.6, 1.85, 0.25) @ R("Z", -25 + ang) @ R("X", 25 + 10 * k)
        p.add("Head", "Cloth", extrude(feather_pts(0.75 - 0.15 * k, 0.12), 0.02, 0.008), pm)
        p.add("Head", "Trim", sweep([(0, -0.05, 0), (0, 0.7 - 0.15 * k, 0)], 0.012, 4), pm)


def chest_1(p):
    cuirass(p, "Base", 3.0, 0.0, 0.03)
    # Pelo en el cuello y los hombros.
    for k in range(18):
        a = math.radians(360 * k / 18)
        x, z = se_point(a, 0.72, 0.5, 2.4)
        p.add("UpperTorso", "Dark", sphere(0.15 + 0.03 * (k % 3), 7, 4), T(x, 1.15 + 0.03 * (k % 2), z) @ S(1, 0.8, 1))
    # Correas cruzadas por delante y por detrás con hebilla.
    for zs in (-1, 1):
        for s in SIDES:
            pts = [(s * 0.85, 0.95, zs * 0.62), (s * 0.4, 0.45, zs * 0.67), (-s * 0.35, -0.15, zs * 0.66), (-s * 0.9, -0.55, zs * 0.6)]
            p.add("UpperTorso", "Dark", sweep(pts, 0.06, 4, flat=0.4))
        p.add("UpperTorso", "Trim", rbox(0.26, 0.26, 0.06, 0.03), T(0, 0.18, zs * 0.7))
        p.add("UpperTorso", "Dark", box(0.14, 0.14, 0.08), T(0, 0.18, zs * 0.72))
    for y in (0.6, 0.3, 0.0, -0.3):  # cordones del frente
        p.add("UpperTorso", "Trim", sweep([(-0.12, y, -0.66), (0.12, y - 0.1, -0.66)], 0.015, 4))
    belt(p, "Dark", buckle="Trim")
    for x in (-0.7, 0.62):  # bolsas del cinturón
        p.add("LowerTorso", "Base", rbox(0.34, 0.36, 0.2, 0.06), T(x, -0.92, -0.66))
        p.add("LowerTorso", "Dark", rbox(0.36, 0.14, 0.22, 0.04), T(x, -0.78, -0.67))
        p.add("LowerTorso", "Trim", rivet(0.04), T(x, -0.8, -0.79) @ R("X", -90))
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.5, 0.95, 0) @ R("Z", -s * 18)
        for k in range(2):
            p.add(limb, "Base" if k == 0 else "Dark", loft(dome_rings(0.68 - 0.06 * k, 0.4, 0.64 - 0.06 * k, -15, 90, 5), 2.4, 0.06, n=18), m @ T(0, -0.12 * k, 0))
        p.rim(limb, "Trim", (0.4 * math.sin(math.radians(-15)), 0.68, 0.64), 0.025, 2.4, n=18, matrix=m)
        leaf(p, limb, "Cloth", m @ T(s * 0.2, 0.32, 0) @ R("Z", -s * 60) @ R("X", -10), 0.5, 0.2)
        vambrace(p, s, "Base", r=0.59, flare=0.05, rim="Dark", couter=None)
        for k in range(4):  # cordones del brazal
            y = -0.6 + 0.16 * k
            p.add(side("LowerArm", s), "Trim", sweep([(s * 1.5 - 0.15, y, -0.6), (s * 1.5 + 0.15, y + 0.1, -0.6)], 0.015, 4))
        gauntlet(p, s, "Dark", "Base", "Trim")
    cape(p, "Cloth", "Dark", length=2.3, width=0.85, flare=0.45, tatter=0.15)


def legs_1(p):
    for s in SIDES:
        cuisse(p, s, "Base", rim="Dark")
        limb = side("UpperLeg", s)
        for y in (-1.15, -1.6):  # correas del muslo
            p.rim(limb, "Dark", (y, 0.6, 0.59, s * LEG_X), 0.04, E, n=20, flat=0.4)
            p.add(limb, "Trim", rbox(0.14, 0.12, 0.05, 0.02), T(s * (LEG_X + 0.64), y, 0) @ R("Y", 90))
        poleyn(p, s, "Dark", "Trim", wing=False, r=0.3)
        greave(p, s, "Base", rim="Dark", keel=0.0)
        lower = side("LowerLeg", s)
        for k in range(5):  # vendas cruzadas
            y = -2.55 + 0.17 * k
            p.add(lower, "Cloth", sweep([(s * LEG_X - 0.45, y, -0.63), (s * LEG_X + 0.45, y + 0.1, -0.63)], 0.04, 4, flat=0.4))
        leaf(p, lower, "Cloth", T(s * (LEG_X + 0.62), -2.0, 0) @ R("Y", s * 90) @ R("Z", s * 15), 0.4, 0.15)


def boots_1(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", lame_rims=0, cuff_r=0.66, cuff_top=-2.3)
        limb = side("Foot", s)
        x = s * LEG_X
        p.add(limb, "Dark", loft([(-2.36, 0.74, 0.72, x), (-2.2, 0.72, 0.7, x)], 3.0, 0.05, n=20))  # vuelta de la caña
        for k in range(4):  # cordones
            y = -2.68 + 0.09 * k
            p.add(limb, "Trim", sweep([(x - 0.18, y, -0.68), (x + 0.18, y + 0.05, -0.68)], 0.015, 4))
            p.add(limb, "Trim", sweep([(x + 0.18, y, -0.68), (x - 0.18, y + 0.05, -0.68)], 0.015, 4))
        leaf(p, limb, "Cloth", T(x + s * 0.72, -2.32, 0.1) @ R("Y", s * 90) @ R("Z", s * 40), 0.36, 0.14)


# 2. Minas: caballero de hierro remachado con farol de minero.

def helm_2(p):
    # Yelmo cerrado de frente en quilla, rendijas de los ojos, penacho y farol de minero.
    rings = [(1.0, 0.76, 0.78), (1.3, 0.72, 0.76, 0, 0, 0.12), (1.65, 0.71, 0.75, 0, 0, 0.15), (1.95, 0.69, 0.73, 0, 0, 0.12),
             (2.14, 0.6, 0.64, 0, 0, 0.07), (2.27, 0.42, 0.46, 0, 0, 0.03), (2.34, 0.16, 0.18), (2.36, 0.02, 0.02)]
    p.add("Head", "Base", loft(rings, 2.4, 0.07, n=26))
    p.rim("Head", "Trim", (1.0, 0.77, 0.79), 0.045, 2.4, n=26)
    p.rim("Head", "Dark", (1.12, 0.75, 0.77, 0, 0, 0.04), 0.03, 2.4, n=26)
    for y, keel in ((1.7, 0.15), (1.82, 0.14)):  # rendijas de los ojos
        p.rim("Head", "Dark", (y, 0.71, 0.75, 0, 0, keel), 0.035, 2.4, 150, 0, 16, flat=0.5)
    p.add("Head", "Trim", sweep([(0, 1.08, -0.9), (0, 1.5, -0.93), (0, 1.95, -0.88), (0, 2.2, -0.68), (0, 2.38, -0.2)], 0.04, 5))
    for s in SIDES:
        for k in range(4):  # respiraderos
            for j in range(3):
                x, y, z = ring_point((1.3 + 0.09 * j, 0.72, 0.76, 0, 0, 0.12), math.radians(s * (22 + 9 * k)), 2.4, 0, 40, -0.005)
                p.add("Head", "Dark", sphere(0.025, 6, 3), T(x, y, z))
        p.rivets("Head", "Trim", (1.16, 0.76, 0.78), 5, 2.4, 70, s * 100, r=0.04)
    for k in range(5):  # penacho
        a = (k - 2) * 7
        pts = bezier((0, 2.32, 0.05), (math.sin(math.radians(a)) * 0.2, 2.75, 0.3), (math.sin(math.radians(a)) * 0.4, 2.6, 1.0),
                     (math.sin(math.radians(a)) * 0.55, 1.95 - 0.05 * abs(k - 2), 1.25), 10)
        p.add("Head", "Cloth", sweep(pts, taper(11, 0.09, 0.02), 6))
    p.add("Head", "Trim", lathe([(0.1, 0), (0.12, 0.08), (0.05, 0.16)], 10), T(0, 2.3, 0.05))
    # Farol de minero en la frente.
    lm = T(0, 2.1, -0.66) @ R("X", -25)
    p.add("Head", "Dark", rbox(0.32, 0.28, 0.2, 0.05), lm)
    p.add("Head", "Trim", torus(0.12, 0.03, 14, 4), lm @ T(0, 0, -0.11) @ R("X", 90))
    p.add("Head", "Glow", lathe([(0.11, 0), (0.08, 0.05)], 14), lm @ T(0, 0, -0.1) @ R("X", -90))


def chest_2(p):
    rings = cuirass(p, "Base", E, 0.08, 0.06)
    for s in SIDES:  # dos picos cruzados en el pecho
        m = T(0, 0.32, -0.76) @ R("Z", s * 40)
        p.add("UpperTorso", "Dark", sweep([(0, -0.42, 0), (0, 0.4, 0)], 0.04, 6), m)
        p.add("UpperTorso", "Trim", sweep(bezier((-0.3, 0.22, 0), (-0.12, 0.42, 0), (0.12, 0.42, 0), (0.3, 0.22, 0), 8),
                                          [0.01, 0.03, 0.045, 0.05, 0.055, 0.055, 0.05, 0.045, 0.035] , 6), m)
    p.add("UpperTorso", "Gem", cut_gem(0.08), T(0, 0.32, -0.8) @ R("X", -90))
    for s in SIDES:
        p.rivets("UpperTorso", "Trim", (0.82, 0.98, 0.57), 4, E, 70, s * 55, r=0.035)
        p.add("UpperTorso", "Trim", sweep([(s * 0.12, 0.92, -0.69), (s * 0.55, 0.62, -0.72), (s * 0.82, 0.05, -0.66)], 0.03, 5))
    p.rim("UpperTorso", "Trim", rings[0], 0.035, E, n=28, keel=0.08)
    # Gorjal y faldas.
    p.add("UpperTorso", "Dark", loft([(1.02, 0.78, 0.6), (1.24, 0.66, 0.5)], 2.6, 0.05, n=22))
    p.rim("UpperTorso", "Trim", (1.24, 0.66, 0.5), 0.03, 2.6, n=22)
    lames(p, "LowerTorso", "Base", -0.55, 3, 0.16, 1.07, 0.6, step=0.13, rim="Trim", n=24)
    p.add("LowerTorso", "Dark", rbox(0.36, 0.3, 0.08, 0.04), T(0, -0.68, -0.68))
    p.add("LowerTorso", "Trim", rivet(0.06), T(0, -0.68, -0.72) @ R("X", -90))
    for s in SIDES:
        pauldron(p, s, "Base", "Trim", "Dark", 0.66, 0.44, 22, 3)
        rerebrace(p, s, "Base")
        vambrace(p, s, "Base")
        gauntlet(p, s, "Base", "Dark", "Trim", cuff=0.06)


def legs_2(p):
    for s in SIDES:
        tassets(p, s, "Base", "Dark", "Trim", 3)
        cuisse(p, s, "Base", rim="Trim")
        p.rivets(side("UpperLeg", s), "Trim", (-1.5, 0.6, 0.59, s * LEG_X), 4, E, 120, 0, r=0.03)
        poleyn(p, s, "Base", "Trim", wing=True)
        rings = greave(p, s, "Base", rim="Trim", keel=0.06)
        p.add(side("LowerLeg", s), "Dark", rbox(0.06, 0.8, 0.06, 0.02), T(s * LEG_X, -2.2, -0.68))


def boots_2(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", toe=0.05, lame_rims=3, cuff_r=0.65, cuff_top=-2.48)
        p.add(side("Foot", s), "Trim", lathe([(0.06, 0), (0.04, 0.12)], 8), T(s * LEG_X, -2.88, 0.62) @ R("X", 90))  # espuela
        p.add(side("Foot", s), "Trim", extrude(star_pts(6, 0.1, 0.04), 0.02), T(s * LEG_X, -2.88, 0.76) @ R("Y", 90))


# ---------- Adornos ----------

def at(ring, a_deg, e=2.2, out=0.0):
    """Punto de un anillo en el ángulo a (grados, 0 = frente)."""
    return ring_point(ring, math.radians(a_deg), e, 0, 40, -out)


def facing(a_deg):
    """Gira una placa del plano XY (que mira a -Z) para que mire hacia fuera en el ángulo a."""
    return R("Y", -a_deg)


def flat(p, limb, role, pts, m, thick=0.045, round_=0.012):
    p.add(limb, role, extrude(pts, thick, round_), m)


def sun(p, limb, m, r=0.28, rays=12, ray=0.16, trim="Trim", glow="Glow"):
    """Sol: disco de luz, aro y rayos alternos (en el plano XY, mirando a -Z)."""
    p.add(limb, glow, lathe([(r * 0.82, 0), (r * 0.7, 0.04), (0.0001, 0.05)], 20), m @ R("X", -90))
    p.add(limb, trim, torus(r * 0.86, 0.035, 24, 5), m @ R("X", 90))
    for k in range(rays):
        a = 360 * k / rays
        length = ray * (1.0 if k % 2 == 0 else 0.6)
        flat(p, limb, trim, [(-0.05, 0), (0.05, 0), (0, length)], m @ R("Z", a) @ T(0, r * 0.95, 0), 0.04, 0.008)


def crescent_pts(r_out, r_in, shift, a0=200, a1=340, n=14):
    outer = [(r_out * math.cos(math.radians(a0 + (a1 - a0) * i / n)), r_out * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
    inner = []
    for i in range(n + 1):
        a = math.radians(a1 - (a1 - a0) * i / n)
        inner.append((r_in * math.cos(a), r_in * math.sin(a) + shift))
    return outer + inner


def lemniscate(a, n=48):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        d = 1 + math.sin(t) ** 2
        pts.append((a * math.cos(t) / d, a * math.sin(t) * math.cos(t) / d, 0))
    return pts


def wing(p, limb, m, feathers=7, length=1.3, roles=("Base", "Trim"), spread=None, thick=0.035, rows=2):
    """Ala en el plano XY: el hueso sale del origen hacia arriba y hacia +X, y de él cuelgan las plumas, más
    largas hacia la punta (primarias) con una fila de plumas cortas por delante (coberteras)."""
    bone = bezier((0, 0, 0), (length * 0.25, length * 0.45, 0), (length * 0.6, length * 0.6, 0), (length * 0.95, length * 0.5, 0), 12)
    p.add(limb, roles[1 % len(roles)], sweep(bone, taper(13, 0.07, 0.025), 6), m)
    for row in range(rows):
        count = feathers - row
        for k in range(count):
            t = (k + 0.5 * row) / max(feathers - 1, 1)
            q = bone[min(int(t * 12), 12)]
            ang = 188 + 62 * t
            size = length * (0.42 + 0.62 * t) * (0.5 if row else 1.0)
            fm = m @ T(q[0], q[1], -0.04 * row) @ R("Z", ang)
            flat(p, limb, roles[(row + k) % len(roles)] if row else roles[0], feather_pts(size, length * 0.11 * (1.25 if row else 1)), fm, thick, 0.008)


def crystals(p, limb, role, m, count=5, size=0.4, spread=35, seed=0, r=0.09):
    for k in range(count):
        a = (k * 137 + seed * 53) % 360
        tilt = spread * (0.2 + 0.8 * ((k * 7 + seed) % 5) / 4) if k else 0
        h = size * (1.0 if k == 0 else 0.45 + 0.4 * ((k * 3 + seed) % 4) / 3)
        p.add(limb, role, crystal(r * (1 if k == 0 else 0.7), h, 6), m @ R("Y", a) @ R("Z", tilt) @ R("Y", k * 20))


def petals(p, limb, m, count=6, length=0.5, width=0.18, roles=("Base", "Cloth"), a0=-60, a1=60, cup=15):
    for k in range(count):
        t = k / max(count - 1, 1)
        ang = a0 + (a1 - a0) * t
        p.add(limb, roles[k % len(roles)], extrude(leaf_pts(length, width), 0.03, 0.01), m @ R("Z", -ang) @ R("X", -cup))


def horn(p, limb, role, s, base, ctrl1, ctrl2, tip, r=0.14, rings=None, ring_role="Trim"):
    pts = bezier((s * base[0], base[1], base[2]), (s * ctrl1[0], ctrl1[1], ctrl1[2]), (s * ctrl2[0], ctrl2[1], ctrl2[2]), (s * tip[0], tip[1], tip[2]), 12)
    p.add(limb, role, sweep(pts, taper(13, r, 0.004, 1.3), 7))
    for i in (rings or []):
        q = Vector(pts[i])
        d = (Vector(pts[i + 1]) - Vector(pts[i - 1])).normalized()
        rr = r * (1 - (i / 12) ** 1.3) + 0.02
        p.add(limb, ring_role, torus(rr, 0.022, 14, 4), Matrix.Translation(q) @ aim(d))


def skull(p, limb, m, bone="Trim", eyes="Glow", size=1.0):
    """Calavera mirando a -Z."""
    p.add(limb, bone, sphere(0.2 * size, 10, 6), m @ S(1, 0.95, 0.9))
    p.add(limb, bone, rbox(0.24 * size, 0.12 * size, 0.18 * size, 0.04), m @ T(0, -0.17 * size, -0.04 * size))
    for s in SIDES:
        p.add(limb, eyes, sphere(0.055 * size, 6, 3), m @ T(s * 0.075 * size, 0.0, -0.165 * size))
    for k in range(4):
        p.add(limb, "Dark", box(0.012 * size, 0.06 * size, 0.02), m @ T((k - 1.5) * 0.05 * size, -0.19 * size, -0.13 * size))


def spikes_on(p, limb, role, ring, count, length, r=0.07, e=2.2, span=360, face=0, up=0.0, matrix=None):
    angs, full = angles(span, face, count if span >= 359.9 else count - 1)
    for a in angs:
        x, y, z = ring_point(ring, a, e, 0, 40, -0.02)
        out = Vector((x - (ring[3] if len(ring) > 3 else 0), 0, z - (ring[4] if len(ring) > 4 else 0))).normalized()
        d = (out + Vector((0, up, 0))).normalized()
        p.add(limb, role, spike(r, length, 6), (matrix or Matrix.Identity(4)) @ Matrix.Translation((x, y, z)) @ aim(d))


def glow_line(p, limb, pts, r=0.022, role="Glow"):
    p.add(limb, role, sweep(pts, r, 5, flat=0.6))


# 3. Cripta: rey caído de obsidiana con costillas, calaveras y capa hecha jirones.

def helm_3(p):
    top = helm_crown(p, "Base", 0.72, 0.78, 14)
    helm_guard(p, "Base", top, 1.05, 0.72, span=236)
    band = (1.92, 0.77, 0.79)
    p.add("Head", "Trim", loft([(1.82, 0.76, 0.78), (2.02, 0.75, 0.77)], 2.2, 0.05, n=24))
    for k in range(10):  # corona de púas dentadas
        a = k * 36
        x, y, z = at(band, a, 2.2, 0.02)
        h = 0.55 if k % 2 == 0 else 0.32
        if k == 0:
            h = 0.75
        flat(p, "Head", "Dark", [(-0.13, 0), (0.13, 0), (0.05, h * 0.5), (0.1, h * 0.55), (0, h)],
             T(x, 1.98, z) @ facing(a) @ R("X", -12), 0.06, 0.01)
    p.add("Head", "Gem", cut_gem(0.11), T(0, 1.92, -0.84) @ R("X", -90))
    p.add("Head", "Trim", torus(0.12, 0.03, 14, 4), T(0, 1.92, -0.81) @ R("X", 90))
    for s in SIDES:
        horn(p, "Head", "Trim", s, (0.6, 1.75, 0.1), (1.0, 2.0, 0.25), (1.05, 2.3, 0.75), (0.85, 2.7, 1.1), 0.12, [3, 6], "Dark")
    p.rim("Head", "Dark", (1.05, 0.76, 0.75), 0.04, 2.2, 236, 180, 22)


def chest_3(p):
    rings = cuirass(p, "Base", E, 0.02, 0.05)
    p.add("UpperTorso", "Trim", sweep([(0, 0.95, -0.67), (0, 0.4, -0.7), (0, -0.25, -0.67)], 0.05, 6, flat=0.6))  # esternón
    for k in range(5):  # costillas
        y = 0.78 - 0.24 * k
        w = 0.85 - 0.05 * k
        for s in SIDES:
            pts = bezier((s * 0.06, y, -0.7), (s * 0.4, y + 0.06, -0.72), (s * 0.75, y - 0.08, -0.66), (s * w, y - 0.25, -0.35), 8)
            p.add("UpperTorso", "Trim", sweep(pts, taper(9, 0.045, 0.025), 5, flat=0.6))
    for k in range(9):  # cuello de púas detrás
        a = 180 + (k - 4) * 22
        x, y, z = at((1.08, 0.72, 0.5), a, 2.4)
        p.add("UpperTorso", "Dark", spike(0.09, 0.55 - 0.05 * abs(k - 4), 6), T(x, y, z) @ aim((x * 0.6, 1.4, z)))
    belt(p, "Dark", buckle=None)
    skull(p, "LowerTorso", T(0, -0.78, -0.72), size=1.0)
    cape(p, "Cloth", "Trim", length=2.6, width=0.95, flare=0.6, tatter=0.32, cols=16)
    for s in SIDES:
        m = pauldron(p, s, "Base", "Trim", "Dark", 0.64, 0.42, 24, 2, rivets=False)
        limb = side("UpperArm", s)
        skull(p, limb, m @ T(s * 0.5, 0.05, -0.05) @ R("Y", -s * 90), size=0.9)
        for k, ang in enumerate((-25, 5, 35)):
            p.add(limb, "Dark", spike(0.09, 0.5 + 0.12 * (k == 1), 6), m @ T(s * 0.1, 0.35, (k - 1) * 0.25) @ R("Z", -s * (25 + 5 * k)) @ R("X", ang * 0.6))
        vambrace(p, s, "Base", couter="Dark", couter_trim="Trim")
        spikes_on(p, side("LowerArm", s), "Dark", (-0.3, 0.6, 0.6, s * ARM_X), 3, 0.3, 0.06, E, 60, s * 90)
        gauntlet(p, s, "Base", "Trim", "Trim")
        for k in range(3):  # garras
            p.add(side("Hand", s), "Trim", spike(0.05, 0.28, 5), T(s * ARM_X + (k - 1) * 0.2 * 0, -1.05, (k - 1) * 0.3) @ R("X", 180) @ R("Z", s * 10))


def legs_3(p):
    for s in SIDES:
        tassets(p, s, "Dark", "Base", "Trim", 2, r=0.68)
        cuisse(p, s, "Base", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=False)
        lower = side("LowerLeg", s)
        p.add(lower, "Dark", spike(0.1, 0.45, 6), T(s * LEG_X, -1.68, -0.78) @ aim((0, 0.35, -1)))
        greave(p, s, "Base", rim="Trim", keel=0.05)
        for k in (-1, 0, 1):  # huesos de la espinilla
            p.add(lower, "Trim", sweep([(s * LEG_X + k * 0.22, -2.55, -0.62 - 0.04 * (k == 0)), (s * LEG_X + k * 0.22, -1.95, -0.64 - 0.04 * (k == 0))],
                                       [0.03, 0.05], 5))


def boots_3(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", toe=0.05, pointy=0.3, lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        limb = side("Foot", s)
        p.add(limb, "Dark", spike(0.07, 0.35, 6), T(s * LEG_X, -2.8, 0.58) @ aim((0, 0.3, 1)))
        spikes_on(p, limb, "Dark", (-2.52, 0.64, 0.63, s * LEG_X), 3, 0.22, 0.05, E, 70, s * 90, 0.6)


# 4. Templo: samurái carmesí con kabuto, media luna, sode y kusazuri.

def helm_4(p):
    bowl = dome_rings(0.75, 0.68, 0.77, 0, 90, 6, 1.82)
    p.add("Head", "Base", loft(bowl, 2.2, 0.07, n=24))
    for k in range(12):  # nervios del cuenco
        a = k * 30
        pts = [at(r, a, 2.2, 0.01) for r in bowl[:-1]]
        p.add("Head", "Trim" if k % 3 == 0 else "Dark", sweep(pts, 0.022, 4))
    p.add("Head", "Trim", lathe([(0.14, 0), (0.1, 0.07), (0.05, 0.1)], 12), T(0, 2.48, 0))  # tehen
    lames(p, "Head", "Base", 1.86, 4, 0.2, 0.8, 0.82, step=0.17, grow=0.07, e=2.2, span=250, face=180, rim="Trim", flare=0.05)
    p.add("Head", "Dark", loft([(1.8, 0.95, 0.98), (1.88, 0.77, 0.79)], 2.2, 0.04, 130, 0, 14))  # visera
    p.rim("Head", "Trim", (1.8, 0.95, 0.98), 0.025, 2.2, 130, 0, 14)
    for s in SIDES:  # fukigaeshi
        flat(p, "Head", "Base", [(0, 0), (0.42, 0.05), (0.46, 0.5), (0.05, 0.42)], T(s * 0.82, 1.42, -0.42) @ R("Y", s * 70) @ S(s, 1, 1), 0.05)
        flat(p, "Head", "Trim", [(0.32, 0.12), (0.4, 0.14), (0.42, 0.4), (0.34, 0.38)], T(s * 0.82, 1.42, -0.45) @ R("Y", s * 70) @ S(s, 1, 1), 0.06)
    flat(p, "Head", "Trim", crescent_pts(0.62, 0.5, 0.2, 195, 345), T(0, 2.3, -0.82) @ R("X", 10), 0.05)  # maedate
    sun(p, "Head", T(0, 2.0, -0.86) @ R("X", 10), 0.12, 8, 0.07)


def chest_4(p):
    rings = cuirass(p, "Base", E, 0.0, 0.04)
    for y in (-0.42, -0.14, 0.14, 0.42, 0.72):  # cordones (odoshi)
        p.rim("UpperTorso", "Dark", (y, 1.03, 0.6), 0.025, E, n=28, out=0.02, flat=0.6)
        for k in range(9):
            x = -0.8 + 0.2 * k
            p.add("UpperTorso", "Cloth", box(0.04, 0.12, 0.03), T(x, y - 0.06, -0.63))
    sun(p, "UpperTorso", T(0, 0.3, -0.68), 0.26, 12, 0.16)
    p.add("UpperTorso", "Dark", loft([(1.0, 0.82, 0.62), (1.22, 0.68, 0.52)], 2.4, 0.05, 220, 180, 18))  # cuello alto atrás
    p.rim("UpperTorso", "Trim", (1.22, 0.68, 0.52), 0.03, 2.4, 220, 180, 18)
    belt(p, "Cloth", -0.98, -0.6, 1.08, buckle=None)  # obi
    for s in SIDES:
        p.add("LowerTorso", "Cloth", sphere(0.12, 8, 5), T(s * 0.12, -0.78, -0.66) @ S(1.3, 1, 0.7))
        p.add("LowerTorso", "Cloth", sweep([(s * 0.1, -0.82, -0.66), (s * 0.18, -1.15, -0.68), (s * 0.26, -1.4, -0.7)], taper(3, 0.06, 0.03), 5, flat=0.4))
    p.add("LowerTorso", "Trim", sphere(0.08, 8, 4), T(0, -0.78, -0.7))
    for s in SIDES:
        limb = side("UpperArm", s)
        lames(p, limb, "Base", 1.12, 5, 0.2, 0.66, 0.6, step=0.17, grow=0.012, e=3.0, span=150, face=s * 90, rim="Trim", cx=s * 1.45, flare=0.03)
        for k in range(5):
            x, y, z = ring_point((1.0 - 0.17 * k, 0.68, 0.62, s * 1.45), math.radians(s * 90), 3.0, 0, 40, -0.02)
            p.add(limb, "Cloth", box(0.03, 0.1, 0.18), T(x, y, z))
        vambrace(p, s, "Dark", couter="Base", couter_trim="Trim")
        for k in range(3):
            p.add(side("LowerArm", s), "Base", rbox(0.06, 0.6, 0.12, 0.02), T(s * (ARM_X + 0.62), -0.32, (k - 1) * 0.22))
        gauntlet(p, s, "Dark", "Base", "Trim")


def legs_4(p):
    for s in SIDES:
        tassets(p, s, "Base", "Base", "Trim", 4, y_top=-0.58, height=0.22, r=0.72, span=210, face=20, step=0.15)
        limb = side("UpperLeg", s)
        for k in range(4):
            for j in range(5):
                x, y, z = ring_point((-0.66 - 0.15 * k, 0.74, 0.71, s * LEG_X), math.radians(s * 20 + (j - 2) * 30), 2.6, 0, 40, -0.01)
                p.add(limb, "Cloth", box(0.03, 0.09, 0.03), T(x, y, z))
        cuisse(p, s, "Dark", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=False, r=0.3)
        greave(p, s, "Dark", rim="Trim", keel=0.0)
        lower = side("LowerLeg", s)
        for k in (-1, 0, 1):  # tablillas de la suneate
            x, y, z = ring_point((-2.2, 0.56, 0.56, s * LEG_X), math.radians(k * 32), E, 0, 40, -0.02)
            p.add(lower, "Base", rbox(0.18, 0.78, 0.06, 0.025), T(x, -2.2, z) @ R("Y", -k * 32))
            p.add(lower, "Trim", rivet(0.03), T(x, -1.88, z - 0.03) @ R("X", -90))


def boots_4(p):
    for s in SIDES:
        sabaton(p, s, "Dark", "Dark", "Trim", lame_rims=1, cuff_role="Cloth", cuff_r=0.62, cuff_top=-2.38)
        limb = side("Foot", s)
        for k in range(3):
            p.rim(limb, "Dark", (-2.68 + 0.1 * k, 0.65, 0.64, s * LEG_X), 0.025, E, n=18, flat=0.5)
        p.add(limb, "Trim", rbox(0.5, 0.05, 0.3, 0.02), T(s * LEG_X, -2.74, -0.72) @ R("X", -18))


# 5. Abismo: escamas, aletas y conchas con puntos de luz.

def fin_pts(length, height, ribs=4):
    pts = [(0, 0)]
    for k in range(ribs + 1):
        t = k / ribs
        pts.append((length * t, height * (0.35 + 0.65 * math.sin(t * math.pi * 0.85)) - (0.06 * height if k % 2 else 0)))
    pts.append((length * 1.08, height * 0.1))
    pts.append((length, 0))
    return pts


def helm_5(p):
    top = helm_crown(p, "Base", 0.72, 0.8, 14)
    helm_guard(p, "Base", top, 1.05, 0.72, span=228)
    p.rim("Head", "Trim", (1.05, 0.77, 0.79), 0.04, 2.2, 228, 180, 22)
    brow = (1.86, 0.74, 0.76)
    p.rim("Head", "Trim", brow, 0.035, 2.2, 140, 0, 14)
    fin = T(0, 2.28, -0.5) @ R("Y", -90) @ R("Z", -14)  # aleta dorsal (plano YZ, hacia atrás)
    flat(p, "Head", "Dark", fin_pts(1.25, 0.5, 5), fin, 0.05)
    for k in range(5):
        t = (k + 0.5) / 5
        p.add("Head", "Trim", sweep([(1.25 * t * 0.6, 0, 0), (1.25 * t + 0.05, 0.47 * (0.35 + 0.65 * math.sin(t * math.pi * 0.85)), 0)], [0.03, 0.012], 4), fin)
    for s in SIDES:  # aletas de las orejas
        m = T(s * 0.75, 1.65, 0.05) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 25)
        flat(p, "Head", "Dark", fin_pts(0.65, 0.42, 3), m, 0.04)
        for k in range(3):
            p.add("Head", "Trim", sweep([(0, 0, 0), (0.6 * (k + 0.6) / 3, 0.38, 0)], [0.025, 0.01], 4), m)
        for k in range(3):
            x, y, z = at(brow, s * (14 + 14 * k), 2.2, 0.02)
            p.add("Head", "Glow", sphere(0.035, 6, 3), T(x, y + 0.08, z))
    p.add("Head", "Gem", sphere(0.12, 10, 6), T(0, 1.95, -0.8))
    p.add("Head", "Trim", torus(0.13, 0.03, 14, 4), T(0, 1.95, -0.78) @ R("X", 90))


def conch(p, limb, m, roles=("Base", "Trim"), turns=2.2, size=0.55):
    """Caracola en espiral a lo largo de +Y."""
    pts, radii = [], []
    n = 30
    for i in range(n + 1):
        t = i / n
        a = turns * 2 * math.pi * t
        rr = size * 0.55 * (1 - t) ** 0.9
        pts.append((rr * math.cos(a), size * 1.1 * t, rr * math.sin(a)))
        radii.append(size * 0.36 * (1 - t) ** 1.1 + 0.01)
    p.add(limb, roles[0], sweep(pts, radii, 9), m)
    p.add(limb, roles[1], sweep(pts[:16], [r + 0.012 for r in radii[:16]], 9, flat=0.25), m @ R("Y", 12))


def scales(p, limb, role, rows, cols, x0, x1, y0, y1, z, size=0.13, alt=None, ring=None):
    for j in range(rows):
        for k in range(cols - (j % 2)):
            x = x0 + (x1 - x0) * (k + 0.5 * (j % 2)) / max(cols - 1, 1)
            y = y0 + (y1 - y0) * j / max(rows - 1, 1)
            zz = z(x, y) if callable(z) else z
            p.add(limb, alt if (alt and (j + k) % 4 == 0) else role, sphere(size, 7, 4), T(x, y, zz) @ R("X", -20) @ S(1, 0.85, 0.35))


def chest_5(p):
    cuirass(p, "Base", E, 0.0, 0.06)
    scales(p, "UpperTorso", "Dark", 7, 8, -0.78, 0.78, -0.45, 0.85, lambda x, y: -0.63 - 0.03 * (1 - abs(x)), 0.14, "Base")
    for k in range(7):
        a = 180 + (k - 3) * 26
        p.add("UpperTorso", "Dark", extrude(fin_pts(0.45, 0.25, 2), 0.035, 0.01),
              Matrix.Translation(at((1.05, 0.7, 0.52), a, 2.4)) @ facing(a) @ R("Z", 70) @ R("Y", 90))
    belt(p, "Dark", buckle="Trim", buckle_shape=sphere(0.16, 10, 6))
    p.add("LowerTorso", "Gem", sphere(0.1, 8, 5), T(0, -0.79, -0.76))
    for x in (-0.6, -0.3, 0.3, 0.6):
        p.add("LowerTorso", "Glow", sphere(0.035, 6, 3), T(x, -0.79, -0.66))
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.52, 0.95, 0) @ R("Z", -s * 22)
        p.add(limb, "Base", loft(dome_rings(0.62, 0.4, 0.6, -10, 90, 5), 2.2, 0.06, n=18), m)
        p.rim(limb, "Trim", (0.4 * math.sin(math.radians(-10)), 0.62, 0.6), 0.035, 2.2, n=18, matrix=m)
        conch(p, limb, m @ T(s * 0.05, 0.25, 0) @ R("Z", -s * 55), ("Base", "Trim"), 2.0, 0.6)
        crystals(p, limb, "Gem", m @ T(-s * 0.1, 0.3, 0.3), 3, 0.35, 30, s + 2, 0.06)
        vambrace(p, s, "Base", couter=None)
        flat(p, side("LowerArm", s), "Dark", fin_pts(0.7, 0.32, 3), T(s * (ARM_X + 0.6), -0.65, 0.1) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 80), 0.04)
        for k in range(3):
            p.add(side("LowerArm", s), "Glow", sphere(0.035, 6, 3), T(s * ARM_X + s * 0.25 * 0, -0.5 + 0.2 * k, -0.6))
        gauntlet(p, s, "Base", "Dark", "Trim")


def legs_5(p):
    for s in SIDES:
        tassets(p, s, "Dark", "Base", "Trim", 2, r=0.7)
        cuisse(p, s, "Base", rim="Trim")
        limb = side("UpperLeg", s)
        scales(p, limb, "Dark", 3, 4, s * LEG_X - 0.35, s * LEG_X + 0.35, -1.75, -1.15, -0.6, 0.12)
        poleyn(p, s, "Base", "Trim", wing=False, r=0.3)
        lower = side("LowerLeg", s)
        p.add(lower, "Gem", sphere(0.07, 8, 4), T(s * LEG_X, -1.68, -0.8))
        greave(p, s, "Base", rim="Trim", keel=0.03)
        flat(p, lower, "Dark", fin_pts(0.8, 0.35, 3), T(s * LEG_X, -2.55, 0.58) @ R("Y", 90) @ R("Z", 95), 0.04)
        for k in range(3):
            p.add(lower, "Glow", sphere(0.03, 6, 3), T(s * LEG_X + (k - 1) * 0.2, -2.0, -0.62))


def boots_5(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        limb = side("Foot", s)
        flat(p, limb, "Dark", fin_pts(0.55, 0.3, 3), T(s * (LEG_X + 0.58), -2.65, 0.3) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 15), 0.035)
        p.add(limb, "Gem", sphere(0.06, 8, 4), T(s * LEG_X, -2.62, -0.62))


# 6. Infierno: demonio de lava con cuernos enormes y grietas de fuego.

def helm_6(p):
    rings = [(1.0, 0.8, 0.82, 0, 0, 0.1), (1.3, 0.74, 0.78, 0, 0, 0.16), (1.65, 0.72, 0.76, 0, 0, 0.16), (1.95, 0.7, 0.74, 0, 0, 0.12),
             (2.15, 0.58, 0.62, 0, 0, 0.06), (2.3, 0.34, 0.38), (2.35, 0.02, 0.02)]
    p.add("Head", "Base", loft(rings, 2.4, 0.07, n=26))
    p.rim("Head", "Glow", (1.72, 0.72, 0.76, 0, 0, 0.16), 0.05, 2.4, 120, 0, 14, flat=0.45)  # visera de fuego
    p.rim("Head", "Dark", (1.82, 0.72, 0.76, 0, 0, 0.15), 0.035, 2.4, 160, 0, 16)
    for k in range(7):  # dientes de la mandíbula
        a = (k - 3) * 14
        x, y, z = at((1.1, 0.78, 0.8, 0, 0, 0.12), a, 2.4, 0.01)
        p.add("Head", "Trim", spike(0.05, 0.28 - 0.03 * abs(k - 3), 5), T(x, 1.45, z - 0.04) @ R("X", 180))
    for s in SIDES:
        horn(p, "Head", "Dark", s, (0.55, 2.0, -0.05), (1.25, 2.1, 0.1), (1.45, 2.75, -0.1), (1.05, 3.2, -0.5), 0.2, [2, 4, 6], "Trim")
        horn(p, "Head", "Dark", s, (0.6, 1.4, 0.2), (0.95, 1.35, 0.45), (0.95, 1.0, 0.7), (0.75, 0.9, 0.95), 0.1, [3], "Trim")
    flat(p, "Head", "Glow", flame_pts(0.55, 0.45, 2), T(0, 2.25, 0.05) @ R("Y", 90) @ R("Z", -10), 0.04)
    for k in range(3):
        a = (k - 1) * 30
        flat(p, "Head", "Glow", [(-0.04, 0), (0.04, 0), (0.02, 0.18), (-0.02, 0.18)], Matrix.Translation(at((2.0, 0.72, 0.76), 180 + a, 2.4, 0.01)) @ facing(180 + a) @ R("Z", 10 * (k - 1)), 0.02)


def cracks(p, limb, start, steps, dx, dy, z, seed=0, r=0.025):
    pts = [start]
    x, y = start[0], start[1]
    for k in range(steps):
        x += dx * (1 if (k + seed) % 2 else -0.6)
        y += dy
        pts.append((x, y, z if not callable(z) else z(x, y)))
    p.add(limb, "Glow", sweep(pts, taper(len(pts), r, 0.008), 4, flat=0.5))


def chest_6(p):
    cuirass(p, "Base", E, 0.07, 0.06)
    zf = lambda x, y: -0.64 - 0.06 * max(0.0, 1 - abs(x) / 0.35)
    for k, (x, y) in enumerate(((-0.5, 0.8), (0.45, 0.7), (-0.6, -0.1), (0.55, -0.2), (0.15, 0.85))):
        cracks(p, "UpperTorso", (x, y, zf(x, y)), 5, 0.1 * (1 if x < 0 else -1), -0.13, zf, k)
    p.add("UpperTorso", "Glow", sphere(0.16, 12, 8), T(0, 0.3, -0.72))
    p.add("UpperTorso", "Trim", torus(0.2, 0.045, 18, 5), T(0, 0.3, -0.72) @ R("X", 90))
    for k in range(6):
        a = 60 * k + 30
        p.add("UpperTorso", "Trim", spike(0.05, 0.18, 5), T(0, 0.3, -0.72) @ R("X", 90) @ R("Y", a) @ T(0.24, 0, 0) @ R("Z", -90))
    for k in range(7):  # cuello de cuernos
        a = 180 + (k - 3) * 28
        x, y, z = at((1.08, 0.72, 0.5), a, 2.4)
        p.add("UpperTorso", "Dark", spike(0.1, 0.45, 6), T(x, y, z) @ aim((x, 1.2, z * 1.4)))
    belt(p, "Dark", buckle="Trim", buckle_shape=extrude([(-0.2, 0.15), (0.2, 0.15), (0.12, -0.05), (0, -0.2), (-0.12, -0.05)], 0.06, 0.015))
    for s in SIDES:
        m = pauldron(p, s, "Base", "Trim", "Dark", 0.66, 0.44, 26, 2, rivets=False)
        limb = side("UpperArm", s)
        for k, ang in enumerate((-30, 0, 30)):
            p.add(limb, "Dark", spike(0.11, 0.62 - 0.12 * abs(k - 1), 6), m @ T(s * 0.15, 0.3, (k - 1) * 0.28) @ R("Z", -s * 35) @ R("X", ang))
        flat(p, limb, "Glow", flame_pts(0.45, 0.32, 2), m @ T(s * 0.55, 0.05, 0) @ R("Y", -s * 90) @ R("Z", s * 20), 0.03)
        vambrace(p, s, "Base", couter="Dark", couter_trim="Trim")
        cracks(p, side("LowerArm", s), (s * ARM_X - 0.1, -0.1, -0.59), 4, 0.06, -0.13, -0.59, s)
        spikes_on(p, side("LowerArm", s), "Dark", (-0.25, 0.6, 0.6, s * ARM_X), 3, 0.32, 0.06, E, 70, s * 90, 0.3)
        gauntlet(p, s, "Base", "Dark", "Trim")
        for k in range(3):
            p.add(side("Hand", s), "Trim", spike(0.05, 0.25, 5), T(s * ARM_X, -1.04, (k - 1) * 0.3) @ R("X", 180))


def legs_6(p):
    for s in SIDES:
        tassets(p, s, "Base", "Dark", "Trim", 3, r=0.7)
        cuisse(p, s, "Base", rim="Trim")
        cracks(p, side("UpperLeg", s), (s * LEG_X, -1.0, -0.6), 4, 0.07, -0.18, -0.6, s)
        poleyn(p, s, "Dark", "Trim", wing=False, r=0.32)
        p.add(side("LowerLeg", s), "Dark", spike(0.11, 0.5, 6), T(s * LEG_X, -1.68, -0.8) @ aim((0, 0.5, -1)))
        greave(p, s, "Base", rim="Trim", keel=0.06)
        cracks(p, side("LowerLeg", s), (s * LEG_X + 0.15, -1.95, -0.64), 4, 0.07, -0.16, -0.63, s + 1)
        spikes_on(p, side("LowerLeg", s), "Dark", (-2.2, 0.58, 0.58, s * LEG_X), 2, 0.25, 0.06, E, 60, s * 90, 0.4)


def boots_6(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", toe=0.05, lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        limb = side("Foot", s)
        for k in (-1, 0, 1):
            p.add(limb, "Trim", spike(0.06, 0.3, 5), T(s * LEG_X + k * 0.2, -2.95, -0.86 + 0.06 * abs(k)) @ aim((k * 0.3, -0.2, -1)))
        p.add(limb, "Dark", spike(0.08, 0.38, 6), T(s * LEG_X, -2.78, 0.58) @ aim((0, 0.4, 1)))
        cracks(p, limb, (s * LEG_X - 0.15, -2.5, -0.62), 2, 0.08, -0.08, -0.62, s)


# 7. Vacío: placas angulosas con costuras de luz y esquirlas que flotan.

def helm_7(p):
    rings = [(1.0, 0.78, 0.8, 0, 0, 0.15), (1.35, 0.72, 0.76, 0, 0, 0.2), (1.7, 0.72, 0.76, 0, 0, 0.2), (2.0, 0.68, 0.72, 0, 0, 0.16),
             (2.2, 0.52, 0.58, 0, 0.05, 0.1), (2.32, 0.2, 0.3, 0, 0.12, 0.05), (2.34, 0.02, 0.04, 0, 0.15)]
    p.add("Head", "Base", loft(rings, 3.0, 0.07, n=24, keel_w=50))
    for s in SIDES:  # visera en V
        pts = [at((1.62, 0.72, 0.76, 0, 0, 0.2), s * a, 3.0, 0.005) for a in (0, 12, 24, 36)]
        pts = [(x, y + 0.06 * i, z) for i, (x, y, z) in enumerate(pts)]
        glow_line(p, "Head", pts, 0.045)
        flat(p, "Head", "Dark", [(0, 0), (0.75, 0.1), (0.85, 0.3), (0.1, 0.18)], T(s * 0.7, 1.9, 0.1) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 12), 0.05)
    p.rim("Head", "Trim", (1.0, 0.79, 0.81, 0, 0, 0.15), 0.035, 3.0, n=24)
    for k in range(7):  # corona de esquirlas flotando
        a = k * (360 / 7)
        x = math.sin(math.radians(a)) * 0.62
        z = -math.cos(math.radians(a)) * 0.62
        p.add("Head", "Gem", crystal(0.06, 0.32 + 0.12 * (k % 2), 4, 0.4), T(x, 2.5 + 0.05 * (k % 2), z) @ aim((x * 0.3, 1, z * 0.3)))
    p.add("Head", "Glow", gem(0.08, 0.3, 4), T(0, 2.82, 0))


def shards(p, limb, role, centers, size=0.35):
    for k, (x, y, z, ax, ay, az) in enumerate(centers):
        p.add(limb, role, crystal(0.07 + 0.02 * (k % 2), size * (0.6 + 0.4 * (k % 3) / 2), 4, 0.45), T(x, y, z) @ aim((ax, ay, az)))


def chest_7(p):
    cuirass(p, "Base", E, 0.12, 0.06)
    for s in SIDES:
        glow_line(p, "UpperTorso", [(s * 0.05, 0.95, -0.7), (s * 0.45, 0.55, -0.68), (s * 0.5, -0.1, -0.64), (s * 0.15, -0.5, -0.66)])
        p.add("UpperTorso", "Dark", extrude([(0, 0), (0.55, 0.2), (0.75, 0.75), (0.2, 0.55)], 0.05, 0.012), T(s * 0.12, 0.25, -0.68) @ S(s, 1, 1))
    p.add("UpperTorso", "Glow", gem(0.13, 0.34, 4), T(0, 0.2, -0.76) @ R("X", 0))
    p.add("UpperTorso", "Trim", torus(0.17, 0.03, 4, 4), T(0, 0.2, -0.74) @ R("X", 90) @ R("Y", 45))
    for s in SIDES:  # alas de esquirlas a la espalda
        centers = [(s * (0.35 + 0.28 * k), 0.75 + 0.18 * k, 0.95 + 0.06 * k, s * (0.5 + 0.2 * k), 1, 0.4) for k in range(4)]
        centers += [(s * (0.45 + 0.25 * k), 0.2 + 0.06 * k, 0.95, s * (0.9), 0.2 + 0.2 * k, 0.3) for k in range(3)]
        shards(p, "UpperTorso", "Gem", centers, 0.55)
    belt(p, "Dark", buckle="Glow", buckle_shape=gem(0.12, 0.3, 4))
    for s in SIDES:
        limb = side("UpperArm", s)
        lames(p, limb, "Base", 1.12, 3, 0.26, 0.66, 0.66, step=0.2, e=6, span=200, face=s * 90, rim="Glow", rim_r=0.018, cx=s * 1.5)
        p.add(limb, "Base", loft([(1.1, 0.68, 0.68, s * 1.5), (1.22, 0.56, 0.56, s * 1.5), (1.26, 0.04, 0.04, s * 1.5)], 6, 0.05, n=20))
        shards(p, limb, "Gem", [(s * 2.15, 0.95, 0, s, 0.6, 0), (s * 2.05, 1.25, -0.25, s * 0.6, 1, -0.2), (s * 2.05, 1.2, 0.25, s * 0.6, 1, 0.2)], 0.45)
        vambrace(p, s, "Base", rim="Glow", couter="Dark", couter_trim="Glow")
        gauntlet(p, s, "Dark", "Base", "Glow")


def legs_7(p):
    for s in SIDES:
        tassets(p, s, "Base", "Dark", "Glow", 2, r=0.7)
        cuisse(p, s, "Base", rim="Glow")
        poleyn(p, s, "Dark", "Glow", wing=True, r=0.3)
        greave(p, s, "Base", rim="Glow", keel=0.1)
        glow_line(p, side("LowerLeg", s), [(s * LEG_X - 0.25, -2.55, -0.62), (s * LEG_X, -2.3, -0.7), (s * LEG_X, -1.95, -0.68)])
        shards(p, side("LowerLeg", s), "Gem", [(s * (LEG_X + 0.75), -2.0, 0.1, s, 0.3, 0.4)], 0.4)


def boots_7(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Glow", toe=0.08, pointy=0.15, lame_rims=2, cuff_r=0.6, cuff_top=-2.4)
        flat(p, side("Foot", s), "Dark", [(0, 0), (0.55, 0.05), (0.7, 0.3), (0.1, 0.15)], T(s * (LEG_X + 0.62), -2.6, 0.2) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 25), 0.04)


# 8. Nebulosa: flor de pétalos y estrellas.

def helm_8(p):
    top = helm_crown(p, "Base", 0.72, 0.76, 16)
    helm_guard(p, "Base", top, 1.08, 0.72, span=232)
    p.rim("Head", "Trim", (1.08, 0.77, 0.79), 0.04, 2.2, 232, 180, 22)
    p.add("Head", "Trim", loft([(1.84, 0.76, 0.78), (1.98, 0.75, 0.77)], 2.2, 0.04, n=24))
    for k in range(12):  # corona de pétalos abiertos
        a = k * 30
        x, y, z = at((1.98, 0.7, 0.72), a, 2.2)
        m = T(x, 1.95, z) @ facing(a) @ R("X", -35 - 10 * (k % 2))
        p.add("Head", "Cloth" if k % 2 else "Base", extrude(leaf_pts(0.55 - 0.12 * (k % 2), 0.2), 0.03, 0.01), m)
    flat(p, "Head", "Trim", star_pts(5, 0.2, 0.08), T(0, 1.95, -0.84), 0.05)
    p.add("Head", "Glow", sphere(0.07, 8, 5), T(0, 1.95, -0.88))
    for s in SIDES:
        petals(p, "Head", T(s * 0.72, 1.62, 0.1) @ R("Y", -s * 90) @ S(s, 1, 1), 3, 0.5, 0.15, ("Base", "Cloth"), 35, 85, 0)


def chest_8(p):
    cuirass(p, "Base", E, 0.03, 0.06)
    flat(p, "UpperTorso", "Trim", star_pts(5, 0.38, 0.16), T(0, 0.35, -0.7), 0.05)
    flat(p, "UpperTorso", "Dark", star_pts(5, 0.24, 0.1), T(0, 0.35, -0.73), 0.03)
    p.add("UpperTorso", "Glow", gem(0.1, 0.2, 8), T(0, 0.35, -0.77) @ R("X", 90))
    for (x, y) in ((-0.6, 0.75), (0.65, 0.55), (-0.55, -0.25), (0.5, -0.35), (0.7, 0.9)):
        flat(p, "UpperTorso", "Glow", star_pts(4, 0.07, 0.025), T(x, y, -0.66), 0.02)
    p.add("UpperTorso", "Cloth", sweep(bezier((0.85, 1.0, -0.55), (0.35, 0.4, -0.75), (-0.3, -0.1, -0.72), (-0.9, -0.55, -0.5), 12), 0.09, 6, flat=0.3))  # banda
    p.add("UpperTorso", "Cloth", sweep(bezier((0.85, 1.0, 0.55), (0.35, 0.4, 0.72), (-0.3, -0.1, 0.7), (-0.9, -0.55, 0.5), 12), 0.09, 6, flat=0.3))
    belt(p, "Dark", buckle="Trim", buckle_shape=extrude(star_pts(5, 0.18, 0.08), 0.05, 0.01))
    petals(p, "LowerTorso", T(0, -0.9, 0.6) @ R("Y", 180) @ R("Z", 180), 5, 0.65, 0.2, ("Cloth", "Base"), -40, 40, -10)
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.55, 0.95, 0) @ R("Z", -s * 20)
        p.add(limb, "Base", loft(dome_rings(0.6, 0.38, 0.58, -10, 90, 5), 2.2, 0.06, n=18), m)
        for row in range(2):  # pétalos de la hombrera
            for k in range(5):
                a = -60 + 30 * k
                pm = m @ facing(s * 90 + a) @ T(0, 0.12 - 0.18 * row, -0.5 - 0.05 * row) @ R("Z", 180) @ R("X", -35)
                p.add(limb, "Cloth" if (k + row) % 2 else "Base", extrude(leaf_pts(0.5 + 0.1 * row, 0.2), 0.03, 0.01), pm)
        p.add(limb, "Gem", sphere(0.08, 8, 5), m @ T(0, 0.38, 0))
        vambrace(p, s, "Base", couter="Base", couter_trim="Gem")
        flat(p, side("LowerArm", s), "Trim", star_pts(4, 0.12, 0.05), T(s * (ARM_X + 0.6), -0.3, 0) @ R("Y", -s * 90), 0.03)
        gauntlet(p, s, "Base", "Dark", "Trim")


def legs_8(p):
    for s in SIDES:
        limb = side("UpperLeg", s)
        for k in range(4):
            pm = T(s * LEG_X, -0.6, 0) @ facing(s * (25 + (k - 1.5) * 32)) @ T(0, 0, -0.66) @ R("Z", 180) @ R("X", -14)
            p.add(limb, "Base" if k % 2 else "Cloth", extrude(leaf_pts(0.62, 0.22), 0.03, 0.01), pm)
        cuisse(p, s, "Base", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=False, r=0.3)
        flat(p, side("LowerLeg", s), "Trim", star_pts(5, 0.16, 0.07), T(s * LEG_X, -1.68, -0.8), 0.04)
        greave(p, s, "Base", rim="Trim", keel=0.02)
        flat(p, side("LowerLeg", s), "Glow", star_pts(4, 0.06, 0.02), T(s * LEG_X, -2.3, -0.65), 0.02)


def boots_8(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", lame_rims=1, cuff_r=0.6, cuff_top=-2.48)
        limb = side("Foot", s)
        for k in range(8):
            a = k * 45
            x, y, z = at((-2.48, 0.6, 0.6, s * LEG_X), a, E)
            p.add(limb, "Cloth" if k % 2 else "Base", extrude(leaf_pts(0.32, 0.14), 0.025, 0.008), T(x, -2.5, z) @ facing(a) @ R("X", -40))
        flat(p, limb, "Trim", star_pts(5, 0.11, 0.045), T(s * LEG_X, -2.76, -0.78) @ R("X", -60), 0.03)


# 9. Galaxia: planetas, anillos en órbita y constelaciones.

def planet(p, limb, m, r=0.24, ring=0.4, tilt=25, body="Base", band="Trim"):
    p.add(limb, body, sphere(r, 14, 8), m)
    p.add(limb, band, torus(ring, 0.03, 28, 4), m @ R("Z", tilt) @ R("X", 10))
    p.add(limb, "Glow", torus(ring * 0.86, 0.015, 28, 4), m @ R("Z", tilt) @ R("X", 10))


def helm_9(p):
    top = helm_crown(p, "Base", 0.72, 0.78, 14)
    helm_guard(p, "Base", top, 1.06, 0.72, span=230)
    p.rim("Head", "Trim", (1.06, 0.77, 0.79), 0.04, 2.2, 230, 180, 22)
    p.rim("Head", "Trim", (1.88, 0.74, 0.76), 0.035, 2.2, 150, 0, 14)
    flat(p, "Head", "Trim", star_pts(4, 0.22, 0.06), T(0, 2.0, -0.84) @ R("X", 8), 0.05)
    p.add("Head", "Glow", sphere(0.06, 8, 5), T(0, 2.0, -0.88))
    m = T(0, 2.05, 0.05) @ R("X", 18) @ R("Z", -12)  # órbita alrededor de la cabeza
    p.add("Head", "Trim", torus(1.0, 0.035, 40, 5), m)
    p.add("Head", "Glow", torus(1.0, 0.07, 40, 4), m @ S(1, 0.15, 1))
    for a, r in ((40, 0.12), (200, 0.08), (300, 0.06)):
        p.add("Head", "Gem", sphere(r, 10, 6), m @ R("Y", a) @ T(1.0, 0, 0))
    for s in SIDES:
        flat(p, "Head", "Dark", [(0, 0), (0.55, 0.08), (0.6, 0.22), (0.05, 0.16)], T(s * 0.72, 1.75, 0.15) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 18), 0.04)


def chest_9(p):
    cuirass(p, "Base", E, 0.02, 0.06)
    c = (0, 0.3, -0.69)
    p.add("UpperTorso", "Glow", sphere(0.1, 10, 6), T(*c))
    p.add("UpperTorso", "Trim", torus(0.13, 0.025, 16, 4), T(*c) @ R("X", 90))
    for arm in range(3):  # brazos de la galaxia
        pts = []
        for i in range(14):
            t = i / 13
            a = arm * 2 * math.pi / 3 + t * 3.2
            r = 0.14 + 0.42 * t
            pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a) * 0.9, c[2] + 0.01 * t))
        p.add("UpperTorso", "Glow", sweep(pts, taper(14, 0.04, 0.01), 5, flat=0.5))
    stars = [(-0.75, 0.85), (-0.55, 0.6), (-0.7, 0.3), (0.62, -0.2), (0.75, -0.45), (0.5, -0.5)]
    for i, (x, y) in enumerate(stars):
        flat(p, "UpperTorso", "Trim", star_pts(4, 0.06, 0.02), T(x, y, -0.65), 0.02)
        if i not in (2, 5):
            nx, ny = stars[i + 1]
            p.add("UpperTorso", "Trim", sweep([(x, y, -0.64), (nx, ny, -0.64)], 0.012, 4))
    belt(p, "Dark", buckle="Trim", buckle_shape=sphere(0.13, 10, 6))
    cape(p, "Cloth", "Trim", length=2.5, width=1.0, flare=0.55)
    for k in range(10):  # estrellas de la capa
        x = (k % 4 - 1.5) * 0.4 + 0.1 * (k // 4)
        y = 0.6 - 0.45 * (k // 2) * 0.6 - 0.2 * (k % 2)
        t = (0.98 - y) / 2.5
        z = 0.56 + 0.3 * t + 0.06 + 0.55 * t * t + 0.03
        flat(p, "UpperTorso", "Glow", star_pts(4, 0.06, 0.02), T(x, y, z) @ R("Y", 180), 0.02)
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.55, 1.0, 0) @ R("Z", -s * 18)
        p.add(limb, "Base", loft(dome_rings(0.6, 0.36, 0.58, -10, 90, 5), 2.2, 0.06, n=18), m)
        p.rim(limb, "Trim", (0.36 * math.sin(math.radians(-10)), 0.6, 0.58), 0.03, 2.2, n=18, matrix=m)
        planet(p, limb, m @ T(s * 0.15, 0.35, 0), 0.24, 0.48, s * 25)
        vambrace(p, s, "Base", couter="Base", couter_trim="Gem")
        gauntlet(p, s, "Base", "Dark", "Trim")


def legs_9(p):
    for s in SIDES:
        tassets(p, s, "Base", "Dark", "Trim", 2, r=0.7)
        cuisse(p, s, "Base", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=False, r=0.3)
        p.add(side("LowerLeg", s), "Gem", sphere(0.09, 10, 6), T(s * LEG_X, -1.68, -0.82))
        p.add(side("LowerLeg", s), "Trim", torus(0.16, 0.02, 20, 4), T(s * LEG_X, -1.68, -0.82) @ R("X", 70) @ R("Z", 25))
        greave(p, s, "Base", rim="Trim", keel=0.03)
        flat(p, side("LowerLeg", s), "Glow", star_pts(4, 0.08, 0.025), T(s * LEG_X, -2.25, -0.65), 0.02)


def boots_9(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        limb = side("Foot", s)
        p.add(limb, "Glow", torus(0.72, 0.03, 28, 4), T(s * LEG_X, -2.55, 0) @ R("X", 8))
        p.add(limb, "Gem", sphere(0.06, 8, 5), T(s * LEG_X, -2.55, 0) @ R("X", 8) @ R("Y", 140 * s) @ T(0.72, 0, 0))


# 10. Cosmos: placas talladas y racimos de cristal.

def helm_10(p):
    rings = dome_rings(0.74, 0.8, 0.76, 14, 90, 4, HEAD_Y + 0.04)
    p.add("Head", "Base", loft(rings, 2.0, 0.07, n=8))
    p.add("Head", "Base", loft([(1.06, 0.78, 0.8), (1.4, 0.74, 0.77), (rings[0][0], rings[0][1], rings[0][2])], 2.0, 0.07, 236, 180, 8))
    p.rim("Head", "Trim", (1.06, 0.79, 0.81), 0.04, 2.0, 236, 180, 8)
    p.rim("Head", "Trim", rings[0], 0.035, 2.0, 130, 0, 4)
    crystals(p, "Head", "Gem", T(0, 2.25, 0.05), 7, 0.75, 40, 1, 0.11)
    for s in SIDES:
        crystals(p, "Head", "Gem", T(s * 0.62, 1.95, -0.1) @ R("Z", -s * 55), 3, 0.45, 25, s + 3, 0.08)
    p.add("Head", "Glow", gem(0.09, 0.3, 4), T(0, 1.95, -0.84))


def chest_10(p):
    cuirass(p, "Base", 3.0, 0.1, 0.06, n=12)
    for s in SIDES:
        p.add("UpperTorso", "Dark", extrude([(0, 0), (0.6, 0.15), (0.7, 0.7), (0.15, 0.9)], 0.05, 0.01), T(s * 0.1, -0.15, -0.69) @ S(s, 1, 1))
    p.add("UpperTorso", "Gem", gem(0.18, 0.5, 6), T(0, 0.35, -0.78) @ R("X", 0))
    p.add("UpperTorso", "Trim", torus(0.22, 0.03, 6, 4), T(0, 0.35, -0.74) @ R("X", 90))
    crystals(p, "UpperTorso", "Gem", T(0, 0.72, 0.62) @ R("X", 55), 8, 1.0, 45, 2, 0.14)
    for s in SIDES:
        crystals(p, "UpperTorso", "Gem", T(s * 0.55, 0.85, 0.55) @ R("X", 45) @ R("Z", -s * 40), 4, 0.6, 30, s + 5, 0.1)
    belt(p, "Dark", buckle="Gem", buckle_shape=gem(0.14, 0.32, 6))
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.55, 0.95, 0) @ R("Z", -s * 22)
        p.add(limb, "Base", loft(dome_rings(0.64, 0.42, 0.62, -12, 90, 3), 2.0, 0.06, n=8), m)
        p.rim(limb, "Trim", (0.42 * math.sin(math.radians(-12)), 0.64, 0.62), 0.035, 2.0, n=8, matrix=m)
        crystals(p, limb, "Gem", m @ T(s * 0.1, 0.3, 0) @ R("Z", -s * 30), 6, 0.75, 40, s + 7, 0.11)
        vambrace(p, s, "Base", couter="Base", couter_trim="Gem")
        crystals(p, side("LowerArm", s), "Gem", T(s * (ARM_X + 0.55), -0.2, 0.1) @ R("Z", -s * 80), 3, 0.35, 25, s + 9, 0.07)
        gauntlet(p, s, "Dark", "Base", "Trim")


def legs_10(p):
    for s in SIDES:
        tassets(p, s, "Base", "Dark", "Trim", 2, r=0.7)
        cuisse(p, s, "Base", rim="Trim")
        p.add(side("LowerLeg", s), "Gem", gem(0.1, 0.3, 6), T(s * LEG_X, -1.66, -0.8) @ R("X", 90))
        poleyn(p, s, "Base", "Trim", wing=True, r=0.3)
        greave(p, s, "Base", rim="Trim", keel=0.08)
        crystals(p, side("LowerLeg", s), "Gem", T(s * (LEG_X + 0.55), -2.0, 0.1) @ R("Z", -s * 70), 3, 0.4, 25, s + 11, 0.07)


def boots_10(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", toe=0.05, lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        crystals(p, side("Foot", s), "Gem", T(s * LEG_X, -2.55, 0.55) @ R("X", 70), 3, 0.4, 25, s + 13, 0.07)


# 11. Origen: ángel de mármol con alas, aureola y sol.

def helm_11(p):
    top = helm_crown(p, "Base", 0.72, 0.8, 14)
    helm_guard(p, "Base", top, 1.06, 0.72, span=230)
    p.rim("Head", "Trim", (1.06, 0.77, 0.79), 0.04, 2.2, 230, 180, 22)
    p.rim("Head", "Trim", (1.88, 0.74, 0.76), 0.035, 2.2, 150, 0, 14)
    p.add("Head", "Trim", sweep([(0, 1.9, -0.82), (0, 2.25, -0.65), (0, 2.42, -0.2), (0, 2.4, 0.3)], [0.05, 0.06, 0.05, 0.03], 6))
    sun(p, "Head", T(0, 1.98, -0.84), 0.12, 8, 0.08)
    p.add("Head", "Trim", torus(0.55, 0.045, 32, 5), T(0, 2.75, 0.15) @ R("X", -15))  # aureola
    p.add("Head", "Glow", torus(0.55, 0.09, 32, 4), T(0, 2.75, 0.15) @ R("X", -15) @ S(1, 0.25, 1))
    for s in SIDES:
        wing(p, "Head", T(s * 0.7, 1.8, 0.0) @ R("Y", -s * 70) @ MX(s) @ R("Z", 15), 6, 0.8, ("Base", "Trim"), None, 0.03)


def chest_11(p):
    cuirass(p, "Base", E, 0.04, 0.06)
    sun(p, "UpperTorso", T(0, 0.35, -0.69), 0.24, 16, 0.2)
    for s in SIDES:
        p.add("UpperTorso", "Trim", sweep(bezier((s * 0.1, 0.95, -0.66), (s * 0.5, 0.95, -0.7), (s * 0.85, 0.6, -0.66), (s * 0.85, 0.1, -0.62), 10), 0.03, 5))
        wing(p, "UpperTorso", T(s * 0.3, 0.7, 0.66) @ R("Y", -s * 22) @ MX(s) @ R("Z", 8), 9, 1.8, ("Base", "Trim"), None, 0.04)
    belt(p, "Trim", buckle="Gem", buckle_shape=gem(0.12, 0.3, 8))
    for s in SIDES:
        limb = side("UpperArm", s)
        m = T(s * 1.55, 0.95, 0) @ R("Z", -s * 20)
        p.add(limb, "Base", loft(dome_rings(0.62, 0.38, 0.6, -10, 90, 5), 2.2, 0.06, n=18), m)
        p.rim(limb, "Trim", (0.38 * math.sin(math.radians(-10)), 0.62, 0.6), 0.035, 2.2, n=18, matrix=m)
        for k in range(4):  # plumas de la hombrera
            fm = m @ facing(s * 90 + (k - 1.5) * 28) @ T(0, 0.0, -0.58) @ R("Z", 180) @ R("X", -25)
            flat(p, limb, "Base" if k % 2 else "Trim", feather_pts(0.6, 0.14), fm, 0.03, 0.008)
        vambrace(p, s, "Base", couter="Trim", couter_trim="Gem")
        gauntlet(p, s, "Base", "Trim", "Trim")


def legs_11(p):
    for s in SIDES:
        limb = side("UpperLeg", s)
        for k in range(4):
            fm = T(s * LEG_X, -0.62, 0) @ facing(s * (30 + (k - 1.5) * 32)) @ T(0, 0, -0.66) @ R("Z", 180) @ R("X", -12)
            flat(p, limb, "Base" if k % 2 else "Trim", feather_pts(0.62, 0.16), fm, 0.03, 0.008)
        cuisse(p, s, "Base", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=True, r=0.3)
        greave(p, s, "Base", rim="Trim", keel=0.03)
        sun(p, side("LowerLeg", s), T(s * LEG_X, -2.25, -0.64), 0.08, 8, 0.06)


def boots_11(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", lame_rims=2, cuff_r=0.6, cuff_top=-2.45)
        wing(p, side("Foot", s), T(s * (LEG_X + 0.62), -2.6, 0.05) @ R("Y", -s * 90) @ MX(s) @ R("Z", 25), 5, 0.55, ("Base", "Trim"), None, 0.03, 1)


# 12. Infinito: corona de cuchillas, ∞ en el pecho y capa de espadas.

def helm_12(p):
    top = helm_crown(p, "Base", 0.72, 0.78, 14)
    helm_guard(p, "Base", top, 1.05, 0.72, span=232)
    p.rim("Head", "Trim", (1.05, 0.77, 0.79), 0.04, 2.2, 232, 180, 22)
    p.add("Head", "Trim", loft([(1.82, 0.76, 0.78), (2.0, 0.75, 0.77)], 2.2, 0.05, n=24))
    for k in range(11):  # corona de cuchillas
        a = (k - 5) * 22
        h = 0.95 - 0.1 * abs(k - 5)
        x, y, z = at((1.98, 0.74, 0.76), a, 2.2, 0.02)
        flat(p, "Head", "Trim" if k % 2 == 0 else "Base", blade_pts(h, 0.2), T(x, 1.96, z) @ facing(a) @ R("X", -10), 0.04)
    p.add("Head", "Gem", cut_gem(0.13), T(0, 1.9, -0.84) @ R("X", -90))
    p.add("Head", "Glow", sweep(lemniscate(0.22), 0.025, 5, True), T(0, 1.9, -0.82))
    for s in SIDES:
        flat(p, "Head", "Base", blade_pts(0.7, 0.2), T(s * 0.72, 1.7, 0.2) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", -60), 0.04)


def chest_12(p):
    cuirass(p, "Base", E, 0.06, 0.06)
    inf = T(0, 0.32, -0.74)
    p.add("UpperTorso", "Trim", sweep(lemniscate(0.48), 0.06, 6, True), inf)
    p.add("UpperTorso", "Glow", sweep(lemniscate(0.48), 0.03, 5, True), inf @ T(0, 0, -0.04))
    p.add("UpperTorso", "Gem", cut_gem(0.09), inf @ T(0, 0, -0.04) @ R("X", -90))
    for s in SIDES:
        p.add("UpperTorso", "Trim", sweep([(s * 0.1, 0.98, -0.66), (s * 0.55, 0.85, -0.68), (s * 0.9, 0.55, -0.6)], 0.03, 5))
    for k in range(9):  # capa de espadas en abanico
        a = (k - 4) * 7.5
        length = 2.2 - 0.12 * abs(k - 4)
        m = T(0, 0.95, 0.68) @ R("X", -14) @ R("Z", 180 + a) @ T(0, 0.05, 0.03 * (k % 2))
        flat(p, "UpperTorso", "Trim" if k % 2 else "Base", blade_pts(length, 0.32), m, 0.04)
        p.add("UpperTorso", "Glow", sweep([(0, 0.15, -0.025), (0, length * 0.8, -0.025)], 0.012, 4), m)
    p.add("UpperTorso", "Gem", cut_gem(0.12), T(0, 0.9, 0.72) @ R("X", 90))
    belt(p, "Dark", buckle="Trim", buckle_shape=extrude(star_pts(4, 0.22, 0.08), 0.06, 0.015))
    for s in SIDES:
        m = pauldron(p, s, "Base", "Trim", "Dark", 0.64, 0.42, 22, 2, rivets=False)
        limb = side("UpperArm", s)
        for k in range(3):
            flat(p, limb, "Trim" if k == 1 else "Base", blade_pts(0.75 - 0.12 * abs(k - 1), 0.2), m @ T(s * 0.3, 0.2, (k - 1) * 0.25) @ R("Y", 90) @ R("Z", -s * (60 - 20 * (k - 1) * 0)) @ R("X", 0), 0.04)
        vambrace(p, s, "Base", couter="Trim", couter_trim="Gem")
        flat(p, side("LowerArm", s), "Trim", blade_pts(0.55, 0.16), T(s * (ARM_X + 0.6), -0.5, 0.15) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", -10), 0.035)
        gauntlet(p, s, "Base", "Dark", "Trim")
        for k in range(3):
            p.add(side("Hand", s), "Trim", spike(0.05, 0.3, 4), T(s * ARM_X, -1.04, (k - 1) * 0.3) @ R("X", 180))


def legs_12(p):
    for s in SIDES:
        limb = side("UpperLeg", s)
        for k in range(3):
            m = T(s * LEG_X, -0.62, 0) @ facing(s * (25 + (k - 1) * 30)) @ T(0, 0, -0.66) @ R("Z", 180) @ R("X", -12)
            flat(p, limb, "Trim" if k == 1 else "Base", blade_pts(0.75, 0.3), m, 0.04)
        cuisse(p, s, "Base", rim="Trim")
        poleyn(p, s, "Base", "Trim", wing=False, r=0.3)
        flat(p, side("LowerLeg", s), "Trim", blade_pts(0.5, 0.18), T(s * LEG_X, -1.75, -0.82) @ R("X", -20), 0.04)
        greave(p, s, "Base", rim="Trim", keel=0.06)
        p.add(side("LowerLeg", s), "Glow", sweep(lemniscate(0.12), 0.015, 4, True), T(s * LEG_X, -2.25, -0.66))


def boots_12(p):
    for s in SIDES:
        sabaton(p, s, "Base", "Dark", "Trim", toe=0.05, pointy=0.2, lame_rims=3, cuff_r=0.6, cuff_top=-2.42)
        limb = side("Foot", s)
        flat(p, limb, "Trim", blade_pts(0.55, 0.16), T(s * LEG_X, -2.8, 0.55) @ R("X", 100), 0.035)
        flat(p, limb, "Base", blade_pts(0.45, 0.14), T(s * (LEG_X + 0.6), -2.5, 0.1) @ R("Y", -s * 90) @ S(s, 1, 1) @ R("Z", 70), 0.03)


DESIGNS = {k: {"helmet": globals()["helm_%d" % k], "chest": globals()["chest_%d" % k], "legs": globals()["legs_%d" % k],
               "boots": globals()["boots_%d" % k]} for k in range(1, 13)}


# ---------- Pasar a Blender y exportar ----------

def to_blender(v):
    # Ejes del juego (X, Y arriba, Z atrás) -> Blender (Z arriba), de forma que el FBX (Y arriba, -Z al frente)
    # salga otra vez en ejes del juego.
    return (v[0], -v[2], v[1])


def material(design, role):
    name = "%d_%s" % (design, role)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    color = ROLE_COLORS[role]
    if design:
        base = tuple(c / 255 for c in BASE[design - 1])
        accent = tuple(c / 255 for c in ACCENT[design - 1])
        if role == "Base":
            color = base + (1,)
        elif role == "Dark":
            color = tuple(c * 0.5 for c in base) + (1,)
        elif role in ("Gem", "Glow"):
            color = accent + (1,)
        elif role == "Cloth":
            color = tuple(c * 0.6 for c in accent) + (1,)
    mat.diffuse_color = color
    return mat


def make_object(name, design, role, verts, faces, offset, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender((x + offset[0], y + offset[1], z + offset[2])) for x, y, z in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if smooth:
        # Aristas de más de 40° separadas: lo curvo se ve liso y los cantos siguen vivos.
        sharp = [e for e in bm.edges if not e.is_manifold or e.calc_face_angle(0) > math.radians(40)]
        bmesh.ops.split_edges(bm, edges=sharp)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    mesh.materials.append(material(design, role))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def marker(name, position):
    verts, faces = box(0.1, 0.1, 0.1)
    return make_object(name, 0, "Marker", verts, faces, position, False)


def load_body():
    """Cuerpo R15 (sin cabeza: la de Roblox no se puede leer) para las vistas; no se exporta."""
    verts, faces = [], []
    with open(BODY_OBJ) as f:
        for line in f:
            if line.startswith("v "):
                verts.append(tuple(float(x) for x in line.split()[1:4]))
            elif line.startswith("f "):
                faces.append(tuple(int(x) - 1 for x in line.split()[1:]))
    head = rbox(1.16, 1.18, 1.16, 0.3, 3)
    base = len(verts)
    verts += [(x, y + HEAD_Y, z) for x, y, z in head[0]]
    faces += [tuple(base + i for i in f) for f in head[1]]
    return verts, faces


def render_preview(path, xs):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.display.shading.show_object_outline = True
    scene.render.resolution_x = 520 * len(xs)
    scene.render.resolution_y = 720
    scene.render.filepath = path
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.12, 0.13, 0.16)
    cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 7.6 * len(xs) * 0.72
    center = (min(xs) + max(xs)) / 2
    cam.location = (center, 60, -0.1 + 60 * math.tan(math.radians(8)))
    cam.rotation_euler = (math.radians(82), 0, math.radians(180))
    scene.camera = cam
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = [int(a) for a in argv[argv.index("--only") + 1:]] if "--only" in argv else None
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    marker("Axis_Origin", (-20, 0, 0))
    marker("Axis_Up", (-20, 2, 0))
    marker("Axis_Front", (-20, 0, -2))
    body = load_body()
    built = []
    for index, design in sorted(DESIGNS.items()):
        if only and index not in only:
            continue
        x = (index - 1) * 12.0
        marker("A%02d_Origin" % index, (x, 0, 0))
        for view, turn in (("F", 0), ("B", 180)):
            # Dos maniquíes por diseño (de frente y de espaldas), solo para las vistas.
            vx = x + (0 if view == "F" else 4.2)
            rot = Matrix.Rotation(math.radians(turn + (-35 if view == "F" else 35)), 4, "Y")
            make_object("Preview_Body%02d%s" % (index, view), 0, "Body", [tuple(rot @ Vector(v)) for v in body[0]], body[1], (vx, 0, 0))
            for slot in SLOTS:
                p = Piece()
                design[slot](p)
                for (limb, role), (verts, faces) in p.parts.items():
                    moved = [tuple(rot @ Vector(v)) for v in verts]
                    if view == "F":
                        make_object("A%02d_%s_%s_%s" % (index, slot, limb, role), index, role, verts, faces, (x, 0, 0))
                        make_object("Preview_%02d%s_%s_%s_%s" % (index, view, slot, limb, role), index, role, moved, faces, (vx, 0, 0))
                    else:
                        make_object("Preview_%02d%s_%s_%s_%s" % (index, view, slot, limb, role), index, role, moved, faces, (vx, 0, 0))
        built.append(index)

    # Las piezas exportadas se esconden en la vista (se ven los maniquíes girados).
    for obj in bpy.data.objects:
        obj.hide_render = not obj.name.startswith("Preview_")
    os.makedirs(OUT_DIR, exist_ok=True)
    for index in built:
        x = (index - 1) * 12.0
        render_preview(os.path.join(OUT_DIR, "armaduras_%d.png" % index), [x, x + 4.2])
    if only:
        print("Vistas de", built)
        return
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "armaduras.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(not obj.name.startswith("Preview_"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "armaduras.fbx"),
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="OFF",
    )
    print("Exportadas", len(built), "armaduras")


main()
