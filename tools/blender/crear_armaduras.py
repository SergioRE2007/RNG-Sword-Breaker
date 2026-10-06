# Crea en Blender los modelos de las armaduras: un diseño por mazmorra (Config.Dungeons, por su posición) y cuatro
# huecos (casco, pechera, grebas, botas), y los exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_armaduras.py
# Deja armaduras.blend, armaduras.fbx y vistas armaduras1-4.png en Documents\Roblox\modelos. En Studio: Archivo >
# Importar 3D con armaduras.fbx y guardar el modelo importado (clic derecho > Guardar en archivo) como
# src/shared/ArmorMeshes.rbxm (y borrar el modelo de Workspace: lo trae Rojo).
#
# Cada pieza son varias mallas "A<mazmorra>_<hueco>_<Papel>" (hueco: helmet, chest, legs, boots): el juego
# (shared/ArmorModel) las pega a la parte del cuerpo R15 que cubre el hueco y les pone color y material según el
# papel (Base = color y material de la mazmorra, Dark = su sombra, Trim = color de la calidad de la pieza, Gem = cristal
# del color de la zona, Glow = luz de la zona). "A<mazmorra>_<hueco>_Origin" marca el centro de la parte del cuerpo
# y Axis_* dan la escala y los ejes. Medidas en studs, Y arriba, -Z al frente, en tamaños de personaje R15 normal:
# cabeza 1.2 cubo, torso 2 x 1.6 x 1, pierna baja 1 x 1.4 x 1, pie 1 x 0.4 x 1.1 (iguales a LIMBS de ArmorModel).
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos")

ROLE_COLORS = {  # solo para verlo en Blender; en el juego manda ArmorModel
    "Base": (0.6, 0.6, 0.65, 1), "Dark": (0.2, 0.2, 0.25, 1), "Trim": (0.95, 0.78, 0.3, 1),
    "Gem": (0.5, 0.9, 1, 1), "Glow": (1, 0.85, 0.4, 1), "Marker": (1, 0, 1, 1), "Body": (0.78, 0.7, 0.6, 1),
}
# Color base de cada diseño y de su zona (acento), solo para la vista previa.
BASE = [(0.59, 0.41, 0.25), (0.69, 0.7, 0.75), (0.23, 0.2, 0.32), (0.65, 0.16, 0.2), (0.35, 0.24, 0.78), (0.78, 0.27, 0.12),
        (0.24, 0.16, 0.43), (0.8, 0.33, 0.59), (0.18, 0.27, 0.75), (0.12, 0.24, 0.31), (0.94, 0.94, 0.98), (0.84, 0.14, 0.22)]
ACCENT = [(0.35, 0.82, 0.43), (0.94, 0.67, 0.27), (0.63, 0.49, 0.88), (0.92, 0.27, 0.31), (0.2, 0.78, 0.82), (1, 0.43, 0.16),
          (0.51, 0.27, 1), (0.9, 0.35, 0.63), (0.24, 0.43, 1), (0.24, 1, 0.67), (0.94, 0.96, 1), (1, 0.16, 0.24)]
SLOTS = ["helmet", "chest", "legs", "boots"]
# Dónde está cada hueco con el personaje de pie (solo para la vista previa y la disposición en Blender).
WORN = {"helmet": (0, 5.5, 0), "chest": (0, 4.0, 0), "legs": (-0.5, 1.2, 0), "boots": (-0.5, 0.2, 0)}


# ---------- Geometría (ejes del juego; se pasan a Blender al final) ----------

def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def R(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def S(sx, sy=None, sz=None):
    sy = sx if sy is None else sy
    sz = sx if sz is None else sz
    return Matrix.Diagonal((sx, sy, sz, 1))


def box(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    verts = [(a, b, c) for a in (-x, x) for b in (-y, y) for c in (-z, z)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces


def frustum(w0, d0, w1, d1, h):
    """Tronco de pirámide de base rectangular: abajo w0 x d0, arriba w1 x d1, centrado en Y."""
    verts = []
    for y, w, d in ((-h / 2, w0, d0), (h / 2, w1, d1)):
        verts += [(-w / 2, y, -d / 2), (w / 2, y, -d / 2), (w / 2, y, d / 2), (-w / 2, y, d / 2)]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4)] + [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)]
    return verts, faces


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


def shell(profile, n=14, open_deg=100, thick=0.09):
    """Cúpula con grosor abierta por delante (-Z): casco sin tapar la cara. profile = [(radio, y)] de abajo a arriba."""
    a0 = -math.pi / 2 + math.radians(open_deg / 2)
    a1 = -math.pi / 2 - math.radians(open_deg / 2) + 2 * math.pi
    verts, outer, inner = [], [], []
    for r, y in profile:
        o, i = [], []
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            o.append(len(verts))
            verts.append((r * math.cos(a), y, r * math.sin(a)))
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            ri = max(r - thick, 0.0)
            i.append(len(verts))
            verts.append((ri * math.cos(a), y - thick * 0.3, ri * math.sin(a)))
        outer.append(o)
        inner.append(i)
    faces = []
    for j in range(len(profile) - 1):
        for k in range(n):
            faces.append((outer[j][k], outer[j][k + 1], outer[j + 1][k + 1], outer[j + 1][k]))
            faces.append((inner[j][k + 1], inner[j][k], inner[j + 1][k], inner[j + 1][k + 1]))
        for k in (0, n):
            faces.append((outer[j][k], outer[j + 1][k], inner[j + 1][k], inner[j][k]))
    for k in range(n):
        faces.append((outer[0][k], inner[0][k], inner[0][k + 1], outer[0][k + 1]))
    return verts, faces


def sphere(r, n=10, rings=6):
    return lathe([(r * math.cos(math.pi * j / rings - math.pi / 2) if 0 < j < rings else 0,
                   r * math.sin(math.pi * j / rings - math.pi / 2)) for j in range(rings + 1)], n)


def dome(r, h, n=10):
    """Media esfera achatada (base plana en y=0)."""
    return lathe([(r, 0), (r * 0.97, h * 0.3), (r * 0.8, h * 0.65), (r * 0.45, h * 0.9), (0, h)], n)


def crystal(r, h, n=6, tip=0.3):
    return lathe([(r * 0.8, 0), (r, h * 0.12), (r, h * (1 - tip)), (0, h)], n)


def gem(r, h=None, n=6):
    h = h or r * 2
    return lathe([(0, -h / 2), (r, 0), (0, h / 2)], n)


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


class Piece:
    def __init__(self):
        self.parts = {}

    def add(self, role, shape, matrix=None):
        verts, faces = shape
        matrix = matrix or Matrix.Identity(4)
        mine = self.parts.setdefault(role, ([], []))
        base = len(mine[0])
        mine[0].extend(tuple(matrix @ Vector(v)) for v in verts)
        mine[1].extend(tuple(base + i for i in f) for f in faces)


# ---------- Piezas comunes ----------

def chest_plate(p, role="Base", top=2.35, bottom=2.1):
    p.add(role, frustum(bottom, 1.28, top, 1.34, 1.5), T(0, 0.02, 0))


def greave(p, role="Base", knee=True, width=1.14):
    p.add(role, frustum(width * 0.92, width, width, width * 1.0, 1.2), T(0, -0.1, 0))
    if knee:
        p.add(role, sphere(0.52, 9, 5), T(0, 0.58, -0.05) @ S(1, 0.55, 1))


def boot(p, role="Base", toe=True):
    p.add(role, box(1.12, 0.52, 1.28), T(0, 0.04, -0.02))
    if toe:
        p.add(role, sphere(0.52, 8, 4), T(0, 0.02, -0.62) @ S(1.05, 0.55, 0.85))


def pauldron(p, kind, base="Base", acc="Trim", dark="Dark", scale=1.0):
    for s in (-1, 1):
        m = T(s * 1.34, 0.72, 0) @ R("Z", -s * 16) @ S(scale)
        if kind == "round":
            p.add(base, sphere(0.62, 10, 5), m @ S(1, 0.7, 1.15))
            p.add(acc, torus(0.58, 0.05, 18, 4), m @ T(0, -0.12, 0) @ S(1, 1, 1.1))
        elif kind == "plate":
            for i, (w, y) in enumerate(((1.0, 0.22), (0.9, 0.02), (0.78, -0.18))):
                p.add(base if i != 1 else dark, box(w, 0.13, 1.2 - i * 0.1), m @ T(s * 0.06 * i, y, 0) @ R("Z", -s * (6 + i * 4)))
            p.add(acc, box(0.12, 0.12, 0.12), m @ T(s * 0.1, 0.3, -0.45))
        elif kind == "spike":
            p.add(base, sphere(0.58, 9, 5), m @ S(1, 0.65, 1.1))
            p.add(dark, spike(0.28, 1.3), m @ T(s * 0.15, 0.1, 0) @ R("Z", -s * 40))
            p.add(acc, torus(0.5, 0.05, 16, 4), m @ T(0, -0.1, 0))
        elif kind == "wing":
            for i, ang in enumerate((10, 38, 66)):
                p.add(base if i != 1 else acc, box(1.1 - i * 0.15, 0.06, 0.55 - i * 0.05), m @ T(s * 0.2, 0.1 + i * 0.12, 0.05) @ R("Z", -s * ang) @ T(s * 0.5, 0, 0))
            p.add(dark, sphere(0.42, 8, 4), m @ S(1, 0.6, 1))
        elif kind == "crystal":
            p.add(base, sphere(0.5, 8, 4), m @ S(1, 0.6, 1.1))
            for k, (h, a, z) in enumerate(((1.1, 14, 0), (0.8, 38, 0.3), (0.7, -8, -0.3))):
                p.add(acc, crystal(0.2, h, 6), m @ T(s * 0.1, 0.1, z) @ R("Z", -s * a))
        elif kind == "planet":
            p.add(base, sphere(0.45, 9, 5), m @ T(0, 0.15, 0))
            p.add(acc, torus(0.78, 0.045, 24, 4), m @ T(0, 0.15, 0) @ R("Z", 22 * s) @ R("X", 8))
        elif kind == "shell":
            for i, (r, y) in enumerate(((0.75, 0.0), (0.58, 0.16), (0.4, 0.3))):
                p.add(base if i != 1 else dark, lathe([(r, 0), (r * 0.6, 0.12), (0, 0.17)], 10), m @ T(s * 0.05, y - 0.1, 0) @ S(1, 1, 1.15) @ R("Z", -s * 6))
            p.add(acc, gem(0.1, 0.3), m @ T(0, 0.42, 0))


def collar(p, kind, role="Dark", acc="Trim"):
    if kind == "spiked":
        for i in range(5):
            a = -80 + 40 * i
            m = T(math.sin(math.radians(a)) * 0.75, 0.82, 0.38) @ R("Z", -a * 0.5) @ R("X", 25)
            p.add(role, spike(0.14, 0.7 + 0.15 * (i % 2 == 0)), m)
    elif kind == "high":
        p.add(role, frustum(1.2, 0.3, 1.8, 0.35, 0.8), T(0, 0.85, 0.5) @ R("X", -12))
        p.add(acc, box(1.7, 0.08, 0.08), T(0, 1.22, 0.58))


# ---------- Cascos ----------

def helmet_dome(p, role="Base", r=0.72, h=0.95, open_deg=100, base_y=-0.18):
    p.add(role, shell([(r * 0.97, 0), (r, h * 0.28), (r * 0.87, h * 0.64), (r * 0.5, h * 0.92), (0.05, h)], 14, open_deg), T(0, base_y, 0))


def helmet_rim(p, role="Trim", r=0.74, y=-0.2, open_deg=100):
    p.add(role, torus(r, 0.05, 20, 4), T(0, y, 0))


def horns(p, role, size=1.0, curve=1.0, y=0.3):
    for s in (-1, 1):
        base = T(s * 0.58, y, -0.05)
        p.add(role, spike(0.2 * size, 0.7 * size), base @ R("Z", -s * 55))
        p.add(role, spike(0.14 * size, 0.7 * size), base @ T(s * 0.4 * size, 0.42 * size, 0) @ R("Z", -s * (25 - 30 * curve)))


def helm_1(p):  # bosque: capucha de cuero con hoja
    helmet_dome(p, "Base", 0.78, 1.0, 90)
    p.add("Base", frustum(1.1, 0.4, 0.5, 0.35, 1.0), T(0, -0.35, 0.68) @ R("X", 8))  # cola de la capucha
    p.add("Dark", torus(0.78, 0.06, 20, 4), T(0, -0.18, 0))
    p.add("Trim", gem(0.1, 0.5, 4), T(0, 0.28, -0.74) @ R("X", 20))
    p.add("Gem", gem(0.08, 0.3, 4), T(0.24, 0.2, -0.72) @ R("Z", 40))
    p.add("Gem", gem(0.08, 0.3, 4), T(-0.24, 0.2, -0.72) @ R("Z", -40))


def helm_2(p):  # minas: yelmo de hierro con guardanariz
    helmet_dome(p, "Base", 0.74, 0.9, 80)
    helmet_rim(p, "Dark", 0.76, -0.18)
    p.add("Trim", box(0.12, 0.7, 0.1), T(0, 0.0, -0.72))  # guardanariz
    for a in range(-4, 5):
        ang = math.radians(a * 22 - 90 + 180)
        p.add("Trim", sphere(0.04, 5, 3), T(0.76 * math.cos(ang), -0.12, 0.76 * math.sin(ang)))
    p.add("Dark", box(0.1, 0.5, 0.7), T(0, 0.58, 0.0))  # cresta


def helm_3(p):  # cripta: corona de púas de obsidiana
    helmet_dome(p, "Base", 0.72, 0.8, 85)
    for i in range(7):
        a = math.radians(-100 + i * 33)
        p.add("Dark", spike(0.1, 0.55 + 0.35 * (i % 2 == 0)), T(0.62 * math.sin(a), 0.5, 0.62 * math.cos(a) * 0.9 + 0.05) @ R("X", 12 * math.cos(a)) @ R("Z", -a * 18))
    p.add("Trim", box(0.14, 0.4, 0.1), T(0, 0.1, -0.74))
    p.add("Glow", box(0.1, 0.1, 0.1), T(0, 0.38, -0.72))


def helm_4(p):  # templo: cuernos dorados y gema
    helmet_dome(p, "Base", 0.74, 0.95, 90)
    helmet_rim(p, "Trim", 0.76, -0.18)
    horns(p, "Trim", 1.0, 0.6, 0.25)
    p.add("Gem", gem(0.13, 0.4), T(0, 0.32, -0.75))
    p.add("Dark", box(0.12, 0.45, 0.9), T(0, 0.74, 0.0))


def helm_5(p):  # abismo: casco con aletas
    helmet_dome(p, "Base", 0.74, 0.85, 95)
    p.add("Dark", frustum(0.14, 1.3, 0.1, 0.7, 0.7), T(0, 0.72, 0.1) @ R("X", -6))  # aleta central
    for s in (-1, 1):
        p.add("Dark", frustum(0.1, 0.7, 0.06, 0.2, 0.55), T(s * 0.76, 0.05, 0.1) @ R("Z", -s * 40))
    p.add("Gem", sphere(0.1, 8, 4), T(0, 0.34, -0.76))
    helmet_rim(p, "Trim", 0.76, -0.18)


def helm_6(p):  # infierno: cuernos grandes y mandíbula
    helmet_dome(p, "Base", 0.74, 0.85, 80)
    horns(p, "Dark", 1.5, 0.2, 0.2)
    p.add("Trim", spike(0.1, 0.5), T(0, 0.55, -0.55) @ R("X", -35))
    for s in (-1, 1):
        p.add("Dark", spike(0.1, 0.45), T(s * 0.5, -0.45, -0.52) @ R("X", 180) @ R("Z", s * 15))
    p.add("Glow", box(0.4, 0.07, 0.08), T(0, 0.3, -0.7))


def helm_7(p):  # vacío: cogulla con ojos de luz y esquirlas
    helmet_dome(p, "Base", 0.8, 1.1, 85)
    p.add("Dark", spike(0.45, 0.9), T(0, 0.6, 0.45) @ R("X", 60))  # punta de la capucha hacia atrás
    p.add("Glow", box(0.17, 0.05, 0.05), T(-0.2, 0.18, -0.75))
    p.add("Glow", box(0.17, 0.05, 0.05), T(0.2, 0.18, -0.75))
    for i, (x, y, z) in enumerate(((-0.8, 0.9, 0.0), (0.85, 0.7, 0.1), (0.0, 1.15, 0.5))):
        p.add("Gem", gem(0.1, 0.5, 4), T(x, y, z) @ R("Z", 20 * (i - 1)))


def helm_8(p):  # nebulosa: cresta de pétalos
    helmet_dome(p, "Base", 0.74, 0.9, 95)
    for i in range(5):
        a = -50 + 25 * i
        p.add("Gem", crystal(0.13, 0.7, 5), T(math.sin(math.radians(a)) * 0.25, 0.65, 0.0) @ R("Z", -a) @ R("X", 8))
    p.add("Glow", gem(0.1, 0.34, 4), T(0, 0.32, -0.76))
    helmet_rim(p, "Trim", 0.76, -0.18)


def helm_9(p):  # galaxia: halo en órbita
    helmet_dome(p, "Base", 0.72, 0.85, 100)
    p.add("Glow", torus(0.92, 0.04, 28, 4), T(0, 1.0, 0) @ R("X", 12))
    p.add("Trim", torus(0.78, 0.035, 28, 4), T(0, 0.95, 0) @ R("Z", -14))
    p.add("Gem", sphere(0.1, 7, 4), T(0.92, 1.0, 0.1))
    p.add("Gem", sphere(0.07, 7, 4), T(-0.7, 0.9, -0.5))
    helmet_rim(p, "Trim", 0.74, -0.18)


def helm_10(p):  # cosmos: yelmo de cristales
    helmet_dome(p, "Base", 0.74, 0.8, 90)
    for i, (x, h, a, z) in enumerate(((0, 1.2, 0, 0.0), (-0.3, 0.85, -22, 0.1), (0.3, 0.85, 22, 0.1), (-0.52, 0.55, -45, 0.0), (0.52, 0.55, 45, 0.0))):
        p.add("Gem", crystal(0.17, h, 6), T(x, 0.55, z) @ R("Z", -a))
    p.add("Trim", gem(0.1, 0.4, 4), T(0, 0.3, -0.76))
    helmet_rim(p, "Trim", 0.76, -0.18)


def helm_11(p):  # origen: alas y halo
    helmet_dome(p, "Base", 0.72, 0.85, 95)
    helmet_rim(p, "Trim", 0.74, -0.18)
    for s in (-1, 1):
        for i, ang in enumerate((15, 40, 65)):
            p.add("Base" if i % 2 == 0 else "Trim", box(0.9 - i * 0.12, 0.05, 0.28), T(s * 0.75, 0.15 + i * 0.1, 0.1) @ R("Z", -s * ang) @ T(s * 0.4, 0, 0))
    p.add("Glow", torus(0.55, 0.04, 26, 4), T(0, 1.22, 0.05))
    p.add("Gem", gem(0.11, 0.38), T(0, 0.34, -0.76))


def helm_12(p):  # infinito: corona de púas
    helmet_dome(p, "Base", 0.74, 0.8, 90)
    helmet_rim(p, "Trim", 0.76, -0.18)
    for i in range(9):
        a = math.radians(-125 + i * 31)
        big = i % 2 == 0
        p.add("Trim" if big else "Dark", spike(0.1, 1.0 if big else 0.6), T(0.62 * math.sin(a), 0.58, 0.62 * math.cos(a)) @ R("Z", -math.degrees(math.sin(a)) * 0.35) @ R("X", math.degrees(math.cos(a)) * 0.25))
    p.add("Glow", gem(0.12, 0.42), T(0, 0.32, -0.76))
    p.add("Glow", torus(0.5, 0.03, 24, 4), T(0, 1.25, 0))


# ---------- Pecheras ----------

def chest_1(p):
    chest_plate(p, "Base", 2.25, 2.05)
    for s in (-1, 1):
        p.add("Dark", box(0.18, 1.9, 0.07), T(s * 0.35, 0.05, -0.68) @ R("Z", -s * 28))
    p.add("Trim", box(0.3, 0.3, 0.1), T(0, 0.05, -0.7))
    p.add("Dark", box(2.3, 0.14, 1.36), T(0, -0.68, 0))
    pauldron(p, "round")


def chest_2(p):
    chest_plate(p, "Base")
    p.add("Dark", box(0.14, 1.4, 0.12), T(0, 0.02, -0.68))
    p.add("Dark", box(2.25, 0.12, 1.34), T(0, -0.62, 0))
    p.add("Dark", box(2.1, 0.12, 1.34), T(0, 0.35, 0.0))
    for x in (-0.75, 0.75):
        for y in (0.55, 0.0, -0.4):
            p.add("Trim", sphere(0.05, 5, 3), T(x, y, -0.68))
    pauldron(p, "plate")
    collar(p, "high", "Dark", "Trim")


def chest_3(p):  # costillas
    chest_plate(p, "Base", 2.2, 2.0)
    p.add("Trim", box(0.14, 1.3, 0.1), T(0, 0.05, -0.7))
    for i, y in enumerate((0.5, 0.2, -0.1, -0.4)):
        for s in (-1, 1):
            p.add("Trim", box(0.8 - 0.07 * i, 0.07, 0.09), T(s * 0.45, y, -0.69) @ R("Z", -s * -12))
    pauldron(p, "spike")
    collar(p, "spiked", "Dark")


def chest_4(p):  # sol
    chest_plate(p, "Base")
    p.add("Trim", torus(0.5, 0.06, 24, 4), T(0, 0.12, -0.7) @ R("X", 90))
    p.add("Glow", lathe([(0.42, 0), (0.42, 0.05)], 20), T(0, 0.12, -0.68) @ R("X", -90))
    for i in range(10):
        a = 36 * i
        p.add("Trim", spike(0.07, 0.3, 4), T(0.68 * math.cos(math.radians(a)), 0.12 + 0.68 * math.sin(math.radians(a)), -0.7) @ R("X", -90) @ R("Z", 0) @ R("Y", 0) @ R("Z", 90 + a - 90) @ S(1, 1, 1) @ R("X", 0))
    pauldron(p, "wing")
    p.add("Dark", box(2.3, 0.14, 1.36), T(0, -0.66, 0))


def chest_5(p):  # escamas
    chest_plate(p, "Base", 2.3, 2.1)
    for row, y in enumerate((0.55, 0.25, -0.05, -0.35, -0.62)):
        for i in range(5 - (1 if row % 2 else 0)):
            x = (i - (1.5 if row % 2 else 2)) * 0.46
            p.add("Dark" if row % 2 else "Trim", gem(0.2, 0.34, 4), T(x, y, -0.7) @ R("X", 90) @ S(1, 0.5, 1.2))
    pauldron(p, "shell")


def chest_6(p):  # magma
    chest_plate(p, "Base")
    for pts in (((-0.6, 0.6), (-0.3, 0.3), (-0.45, 0.0), (-0.2, -0.4)), ((0.6, 0.5), (0.3, 0.2), (0.5, -0.1), (0.25, -0.5)), ((0.0, 0.6), (0.05, 0.2), (-0.05, -0.2))):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            length = math.hypot(x1 - x0, y1 - y0)
            ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
            p.add("Glow", box(length, 0.07, 0.06), T((x0 + x1) / 2, (y0 + y1) / 2, -0.68) @ R("Z", ang))
    pauldron(p, "spike", "Base", "Glow", "Dark", 1.15)
    collar(p, "spiked", "Dark")


def chest_7(p):  # vacío: grietas y esquirlas flotando
    chest_plate(p, "Base", 2.15, 1.95)
    for s in (-1, 1):
        p.add("Glow", box(0.06, 1.1, 0.06), T(s * 0.25, 0.0, -0.69) @ R("Z", s * 12))
    p.add("Dark", box(2.2, 0.12, 1.34), T(0, -0.66, 0))
    for s in (-1, 1):
        for i, (y, h) in enumerate(((0.95, 1.0), (0.55, 0.8), (1.25, 0.6))):
            p.add("Gem" if i != 1 else "Dark", crystal(0.17, h, 5), T(s * (1.45 + 0.12 * i), y - 0.1, 0.0) @ R("Z", -s * (20 + 12 * i)))
    collar(p, "high", "Dark", "Glow")


def chest_8(p):  # nebulosa: estrella
    chest_plate(p, "Base")
    p.add("Glow", gem(0.3, 0.9, 4), T(0, 0.1, -0.7) @ R("X", 90))
    p.add("Glow", gem(0.3, 0.9, 4), T(0, 0.1, -0.7) @ R("X", 90) @ R("Y", 45) @ S(0.8))
    p.add("Trim", torus(0.55, 0.045, 24, 4), T(0, 0.1, -0.7) @ R("X", 90))
    for s in (-1, 1):
        p.add("Gem", sphere(0.08, 6, 3), T(s * 0.85, -0.3, -0.7))
    pauldron(p, "wing", "Base", "Gem", "Dark")
    p.add("Dark", box(2.3, 0.14, 1.36), T(0, -0.66, 0))


def chest_9(p):  # galaxia: espiral de anillos
    chest_plate(p, "Base")
    p.add("Glow", torus(0.55, 0.05, 28, 4), T(0, 0.12, -0.7) @ R("X", 90))
    p.add("Trim", torus(0.8, 0.04, 30, 4), T(0, 0.12, -0.7) @ R("X", 90) @ R("Y", 20))
    p.add("Gem", sphere(0.22, 8, 4), T(0, 0.12, -0.74))
    p.add("Trim", sphere(0.07, 6, 3), T(0.55, 0.12, -0.72))
    pauldron(p, "planet", "Base", "Glow")
    p.add("Dark", box(2.3, 0.14, 1.36), T(0, -0.66, 0))


def chest_10(p):  # cosmos: racimo de cristales
    chest_plate(p, "Base")
    for h, a, x in ((1.2, 0, 0.0), (0.9, 25, 0.3), (0.9, -25, -0.3), (0.65, 50, 0.55), (0.65, -50, -0.55)):
        p.add("Gem", crystal(0.17, h, 6), T(x, -0.35, -0.7) @ R("X", -70) @ R("Z", -a * 0))
    p.add("Trim", torus(0.5, 0.05, 20, 4), T(0, -0.1, -0.68) @ R("X", 90))
    pauldron(p, "crystal", "Base", "Gem")
    p.add("Dark", box(2.3, 0.14, 1.36), T(0, -0.66, 0))


def chest_11(p):  # origen: sol de luz
    chest_plate(p, "Base")
    p.add("Trim", lathe([(0.46, 0), (0.46, 0.06)], 22), T(0, 0.12, -0.67) @ R("X", -90))
    p.add("Glow", lathe([(0.3, 0), (0.3, 0.08)], 22), T(0, 0.12, -0.7) @ R("X", -90))
    for i in range(12):
        a = 30 * i
        p.add("Glow" if i % 2 else "Trim", spike(0.06, 0.46 if i % 2 else 0.3, 4),
              T(0.6 * math.cos(math.radians(a)), 0.12 + 0.6 * math.sin(math.radians(a)), -0.68) @ R("Z", a - 90) @ R("X", 0))
    pauldron(p, "wing", "Base", "Trim", "Dark", 1.25)
    p.add("Trim", box(2.35, 0.1, 1.38), T(0, -0.66, 0))


def chest_12(p):  # infinito: ∞ y capa de cuchillas
    chest_plate(p, "Base")
    path = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        d = 1 + math.sin(t) ** 2
        path.append((0.62 * math.cos(t) / d * 1.4, 0.1 + 0.62 * math.sin(t) * math.cos(t) / d * 1.4))
    verts = []
    m = 5
    n = len(path)
    for i in range(n):
        x0, y0 = path[i - 1]
        x1, y1 = path[(i + 1) % n]
        ln = math.hypot(x1 - x0, y1 - y0)
        nx, ny = -(y1 - y0) / ln, (x1 - x0) / ln
        x, y = path[i]
        for j in range(m):
            b = 2 * math.pi * j / m
            verts.append((x + nx * 0.05 * math.cos(b), y + ny * 0.05 * math.cos(b), 0.05 * math.sin(b)))
    faces = [(i * m + j, ((i + 1) % n) * m + j, ((i + 1) % n) * m + (j + 1) % m, i * m + (j + 1) % m) for i in range(n) for j in range(m)]
    p.add("Glow", (verts, faces), T(0, 0.05, -0.7))
    pauldron(p, "spike", "Base", "Trim", "Dark", 1.3)
    collar(p, "spiked", "Trim")
    for x, h in ((-0.7, 1.7), (0.0, 2.1), (0.7, 1.7)):
        p.add("Dark", frustum(0.3, 0.06, 0.1, 0.04, h), T(x, -0.9 + 0.15, 0.72) @ R("X", 8))
    p.add("Trim", box(2.35, 0.1, 1.38), T(0, -0.66, 0))


# ---------- Grebas ----------

def legs_generic(p, set_index):
    greave(p, "Base")
    p.add("Dark", box(1.2, 0.1, 1.2), T(0, -0.62, 0))
    p.add("Trim", box(0.14, 0.9, 0.08), T(0, -0.05, -0.58))


def legs_1(p):
    greave(p, "Base", False)
    for y in (0.3, -0.15, -0.5):
        p.add("Dark", box(1.16, 0.1, 1.16), T(0, y, 0))
    p.add("Trim", box(0.14, 0.14, 0.08), T(0, 0.3, -0.6))
    p.add("Base", sphere(0.5, 8, 4), T(0, 0.58, -0.05) @ S(1, 0.5, 1))


def legs_2(p):
    greave(p, "Base")
    p.add("Dark", sphere(0.34, 8, 4), T(0, 0.6, -0.5) @ S(1, 0.8, 0.5))
    p.add("Trim", box(0.12, 0.9, 0.08), T(0, -0.1, -0.58))
    for y in (0.25, -0.3):
        p.add("Trim", sphere(0.045, 5, 3), T(0.4, y, -0.56))
        p.add("Trim", sphere(0.045, 5, 3), T(-0.4, y, -0.56))


def legs_3(p):
    greave(p, "Base", False)
    for i, a in enumerate((-30, 0, 30)):
        p.add("Dark", spike(0.1, 0.55), T(0, 0.55, -0.35) @ R("Z", a) @ R("X", -50))
    p.add("Trim", sphere(0.3, 7, 4), T(0, 0.45, -0.55) @ S(1, 0.8, 0.6))
    p.add("Dark", box(1.2, 0.1, 1.2), T(0, -0.62, 0))


def legs_4(p):
    greave(p, "Base")
    p.add("Trim", box(0.16, 1.0, 0.07), T(0.3, -0.1, -0.58))
    p.add("Trim", box(0.16, 1.0, 0.07), T(-0.3, -0.1, -0.58))
    p.add("Gem", gem(0.1, 0.3), T(0, 0.55, -0.62))
    p.add("Trim", frustum(1.2, 1.2, 1.4, 1.4, 0.18), T(0, -0.65, 0))


def legs_5(p):
    greave(p, "Base")
    for s in (-1, 1):
        p.add("Dark", frustum(0.1, 0.8, 0.05, 0.2, 0.9), T(s * 0.62, -0.1, 0.1) @ R("Z", -s * 25))
    p.add("Gem", sphere(0.09, 7, 4), T(0, 0.58, -0.58))
    p.add("Trim", box(1.2, 0.1, 1.2), T(0, -0.62, 0))


def legs_6(p):
    greave(p, "Base", False)
    p.add("Dark", spike(0.25, 0.8), T(0, 0.45, -0.4) @ R("X", -75))
    p.add("Glow", box(0.07, 0.8, 0.06), T(0.3, -0.12, -0.58))
    p.add("Glow", box(0.07, 0.8, 0.06), T(-0.3, -0.12, -0.58))
    p.add("Dark", box(1.22, 0.1, 1.22), T(0, -0.62, 0))


def legs_7(p):
    greave(p, "Base", False)
    p.add("Glow", box(0.06, 1.0, 0.05), T(0.18, -0.05, -0.58) @ R("Z", 8))
    p.add("Glow", box(0.06, 1.0, 0.05), T(-0.18, -0.05, -0.58) @ R("Z", -8))
    p.add("Dark", crystal(0.14, 0.7, 5), T(0.62, 0.0, 0.1) @ R("Z", -25))
    p.add("Dark", crystal(0.14, 0.7, 5), T(-0.62, 0.0, 0.1) @ R("Z", 25))
    p.add("Dark", sphere(0.45, 8, 4), T(0, 0.58, -0.05) @ S(1, 0.5, 1))


def legs_8(p):
    greave(p, "Base")
    p.add("Gem", gem(0.14, 0.4, 5), T(0, 0.55, -0.6) @ R("X", 90))
    p.add("Trim", torus(0.6, 0.04, 20, 4), T(0, -0.05, 0) @ R("X", 8))
    p.add("Trim", torus(0.6, 0.04, 20, 4), T(0, -0.4, 0) @ R("X", -8))


def legs_9(p):
    greave(p, "Base")
    p.add("Glow", torus(0.62, 0.04, 20, 4), T(0, 0.25, 0) @ R("Z", 10))
    p.add("Trim", torus(0.62, 0.04, 20, 4), T(0, -0.25, 0) @ R("Z", -10))
    p.add("Gem", sphere(0.1, 7, 4), T(0, 0.58, -0.6))


def legs_10(p):
    greave(p, "Base")
    p.add("Gem", crystal(0.14, 0.9, 6), T(0.0, -0.45, -0.55) @ R("X", -12))
    p.add("Gem", crystal(0.1, 0.6, 6), T(0.3, -0.4, -0.52) @ R("X", -12) @ R("Z", -12))
    p.add("Gem", crystal(0.1, 0.6, 6), T(-0.3, -0.4, -0.52) @ R("X", -12) @ R("Z", 12))
    p.add("Trim", box(1.2, 0.1, 1.2), T(0, -0.62, 0))


def legs_11(p):
    greave(p, "Base")
    p.add("Trim", box(1.2, 0.12, 1.2), T(0, 0.28, 0))
    p.add("Trim", box(1.2, 0.12, 1.2), T(0, -0.62, 0))
    p.add("Glow", box(0.08, 0.7, 0.05), T(0, -0.15, -0.58))
    for s in (-1, 1):
        for i, ang in enumerate((20, 45)):
            p.add("Trim", box(0.6 - i * 0.1, 0.04, 0.2), T(s * 0.58, 0.1 + i * 0.1, 0.2) @ R("Z", -s * ang) @ T(s * 0.3, 0, 0))


def legs_12(p):
    greave(p, "Base", False)
    p.add("Trim", spike(0.22, 0.9), T(0, 0.45, -0.35) @ R("X", -80))
    for s in (-1, 1):
        p.add("Dark", spike(0.1, 0.8), T(s * 0.58, -0.15, 0.1) @ R("Z", -s * 45))
    p.add("Glow", box(0.08, 0.9, 0.05), T(0, -0.1, -0.58))
    p.add("Trim", box(1.24, 0.12, 1.24), T(0, -0.62, 0))


# ---------- Botas ----------

def boots_generic(p, extra=None):
    boot(p, "Base")
    p.add("Dark", box(1.14, 0.12, 1.3), T(0, -0.2, -0.02))
    p.add("Trim", box(1.18, 0.1, 1.18), T(0, 0.3, 0))
    if extra:
        extra(p)


def boots_1(p):
    boot(p, "Base")
    p.add("Dark", torus(0.6, 0.07, 18, 4), T(0, 0.3, 0) @ S(1, 1, 1.05))
    p.add("Trim", box(0.14, 0.14, 0.08), T(0, 0.2, -0.64))


def boots_2(p):
    boot(p, "Base")
    p.add("Dark", sphere(0.5, 8, 4), T(0, 0.04, -0.66) @ S(1.05, 0.5, 0.6))
    p.add("Trim", box(1.16, 0.1, 1.2), T(0, 0.3, 0))


def boots_3(p):
    boot(p, "Base")
    p.add("Dark", spike(0.1, 0.5), T(0, 0.05, -0.8) @ R("X", -85))
    p.add("Dark", spike(0.12, 0.5), T(0, 0.1, 0.6) @ R("X", 75))
    p.add("Trim", box(1.16, 0.09, 1.2), T(0, 0.3, 0))


def boots_4(p):
    boot(p, "Base")
    p.add("Trim", frustum(1.1, 1.1, 1.45, 1.45, 0.3), T(0, 0.34, 0))
    p.add("Gem", gem(0.09, 0.28), T(0, 0.2, -0.66))


def boots_5(p):
    boot(p, "Base")
    p.add("Dark", frustum(0.08, 0.7, 0.04, 0.15, 0.5), T(0.6, 0.1, 0.2) @ R("Z", -30))
    p.add("Dark", frustum(0.08, 0.7, 0.04, 0.15, 0.5), T(-0.6, 0.1, 0.2) @ R("Z", 30))
    p.add("Trim", box(1.16, 0.09, 1.2), T(0, 0.3, 0))


def boots_6(p):
    boot(p, "Base")
    p.add("Dark", spike(0.12, 0.6), T(0, 0.0, 0.58) @ R("X", 70))
    p.add("Dark", spike(0.1, 0.5), T(0.3, 0.05, -0.75) @ R("X", -80))
    p.add("Dark", spike(0.1, 0.5), T(-0.3, 0.05, -0.75) @ R("X", -80))
    p.add("Glow", box(0.5, 0.05, 0.05), T(0, 0.3, -0.62))


def boots_7(p):
    boot(p, "Base")
    p.add("Glow", torus(0.62, 0.035, 22, 4), T(0, -0.3, 0))
    p.add("Dark", crystal(0.1, 0.5, 5), T(0.62, 0.15, 0.2) @ R("Z", -30))
    p.add("Dark", crystal(0.1, 0.5, 5), T(-0.62, 0.15, 0.2) @ R("Z", 30))


def boots_8(p):
    boot(p, "Base")
    p.add("Glow", gem(0.14, 0.34, 4), T(0, 0.2, -0.66) @ R("X", 90))
    p.add("Trim", torus(0.6, 0.04, 18, 4), T(0, 0.3, 0))


def boots_9(p):
    boot(p, "Base")
    p.add("Glow", torus(0.66, 0.04, 22, 4), T(0, 0.3, 0) @ R("Z", 8))
    p.add("Gem", sphere(0.09, 6, 3), T(0.66, 0.3, 0))


def boots_10(p):
    boot(p, "Base")
    p.add("Gem", crystal(0.13, 0.6, 6), T(0, 0.0, -0.7) @ R("X", -80))
    p.add("Gem", crystal(0.1, 0.5, 6), T(0.35, 0.3, -0.5) @ R("X", -20) @ R("Z", -20))
    p.add("Trim", box(1.16, 0.09, 1.2), T(0, 0.3, 0))


def boots_11(p):
    boot(p, "Base")
    p.add("Trim", box(1.16, 0.09, 1.2), T(0, 0.3, 0))
    for s in (-1, 1):
        for i, ang in enumerate((15, 40)):
            p.add("Trim" if i else "Base", box(0.6 - i * 0.12, 0.04, 0.22), T(s * 0.58, 0.18 + i * 0.1, 0.25) @ R("Z", -s * ang) @ T(s * 0.3, 0, 0))
    p.add("Glow", box(0.5, 0.04, 0.05), T(0, 0.28, -0.62))


def boots_12(p):
    boot(p, "Base")
    p.add("Trim", spike(0.12, 0.7), T(0, 0.0, -0.8) @ R("X", -85))
    p.add("Dark", spike(0.14, 0.6), T(0, 0.05, 0.6) @ R("X", 75))
    p.add("Glow", box(0.5, 0.05, 0.05), T(0, 0.3, -0.62))
    p.add("Trim", box(1.2, 0.1, 1.2), T(0, 0.3, 0))


DESIGNS = [
    {"helmet": helm_1, "chest": chest_1, "legs": legs_1, "boots": boots_1},
    {"helmet": helm_2, "chest": chest_2, "legs": legs_2, "boots": boots_2},
    {"helmet": helm_3, "chest": chest_3, "legs": legs_3, "boots": boots_3},
    {"helmet": helm_4, "chest": chest_4, "legs": legs_4, "boots": boots_4},
    {"helmet": helm_5, "chest": chest_5, "legs": legs_5, "boots": boots_5},
    {"helmet": helm_6, "chest": chest_6, "legs": legs_6, "boots": boots_6},
    {"helmet": helm_7, "chest": chest_7, "legs": legs_7, "boots": boots_7},
    {"helmet": helm_8, "chest": chest_8, "legs": legs_8, "boots": boots_8},
    {"helmet": helm_9, "chest": chest_9, "legs": legs_9, "boots": boots_9},
    {"helmet": helm_10, "chest": chest_10, "legs": legs_10, "boots": boots_10},
    {"helmet": helm_11, "chest": chest_11, "legs": legs_11, "boots": boots_11},
    {"helmet": helm_12, "chest": chest_12, "legs": legs_12, "boots": boots_12},
]


# ---------- Pasar a Blender y exportar ----------

def to_blender(v):
    # Ejes del juego (X, Y arriba, Z atrás) -> Blender (Z arriba), de forma que el FBX (Y arriba, -Z al frente)
    # salga otra vez en ejes del juego.
    return (v[0], -v[2], v[1])


def material(design, role):
    name = "%d_%s" % (design, role)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    color = ROLE_COLORS[role]
    if role == "Base" and design:
        color = BASE[design - 1] + (1,)
    elif role == "Dark" and design:
        color = tuple(c * 0.45 for c in BASE[design - 1]) + (1,)
    elif role in ("Gem", "Glow") and design:
        color = ACCENT[design - 1] + (1,)
    mat.diffuse_color = color
    return mat


def make_object(name, design, role, verts, faces, offset):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender((x + offset[0], y + offset[1], z + offset[2])) for x, y, z in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material(design, role))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def marker(name, position):
    verts, faces = box(0.1, 0.1, 0.1)
    return make_object(name, 0, "Marker", verts, faces, position)


def dummy_body(origin_x):
    """Muñeco de R15 solo para ver cómo queda (no se exporta)."""
    limbs = [((0, 5.5, 0), (1.2, 1.2, 1.2)), ((0, 4.0, 0), (2, 1.6, 1)), ((0, 3.0, 0), (2, 0.4, 1)),
             ((-0.5, 2.3, 0), (1, 1.0, 1)), ((0.5, 2.3, 0), (1, 1.0, 1)), ((-0.5, 1.2, 0), (1, 1.4, 1)),
             ((0.5, 1.2, 0), (1, 1.4, 1)), ((-0.5, 0.2, 0), (1, 0.4, 1.1)), ((0.5, 0.2, 0), (1, 0.4, 1.1)),
             ((-1.5, 4.2, 0), (1, 1.2, 1)), ((1.5, 4.2, 0), (1, 1.2, 1)), ((-1.5, 3.2, 0), (1, 1.0, 1)), ((1.5, 3.2, 0), (1, 1.0, 1))]
    for i, (pos, size) in enumerate(limbs):
        verts, faces = box(*size)
        obj = make_object("Preview_Body%d" % i, 0, "Body", verts, faces, (pos[0] + origin_x, pos[1], pos[2]))
    return


def render_preview(path, first, last):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    count = last - first + 1
    scene.render.resolution_x = 500 * count
    scene.render.resolution_y = 620
    scene.render.filepath = path
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.12, 0.13, 0.16)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 10.0 * count
    cam.location = (((first - 1) + (last - 1)) / 2 * 10.0, 60, 3.1)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    scene.collection.objects.link(cam)
    scene.camera = cam
    bpy.ops.render.render(write_still=True)


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    marker("Axis_Origin", (-20, 0, 0))
    marker("Axis_Up", (-20, 2, 0))
    marker("Axis_Front", (-20, 0, -2))

    for index, design in enumerate(DESIGNS, start=1):
        x = (index - 1) * 10.0
        dummy_body(x)
        for slot in SLOTS:
            p = Piece()
            design[slot](p)
            worn = WORN[slot]
            offset = (x + worn[0], worn[1], worn[2])
            marker("A%02d_%s_Origin" % (index, slot), offset)
            for role, (verts, faces) in p.parts.items():
                make_object("A%02d_%s_%s" % (index, slot, role), index, role, verts, faces, offset)
                if slot in ("legs", "boots"):  # la otra pierna, solo para la vista previa
                    make_object("Preview_%02d_%s_%s_R" % (index, slot, role), index, role, verts, faces, (x + 0.5, worn[1], worn[2]))

    os.makedirs(OUT_DIR, exist_ok=True)
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
        mesh_smooth_type="FACE",
    )
    for k in range(4):
        render_preview(os.path.join(OUT_DIR, "armaduras%d.png" % (k + 1)), 1 + 3 * k, 3 + 3 * k)
    print("Exportadas", len(DESIGNS), "armaduras")


main()
