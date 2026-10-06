# Crea en Blender las piezas del mapa del bosque japonés (cerezos, arces, pinos, bambú, torii, linternas, pagoda,
# puente, santuario, rocas, loto, carpas y farolillos) y las exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_mapa_japones.py
# Deja mapa_japones.blend, mapa_japones.fbx y mapa_japones1-3.png en Documents\Roblox\modelos. En Studio: Archivo >
# Importar 3D con mapa_japones.fbx y guardar el modelo importado (clic derecho > Guardar en archivo) como
# src/shared/MapMeshes.rbxm (y borrar el modelo de Workspace: lo trae Rojo).
#
# Cada pieza son varias mallas "<Pieza>_<Papel>", una por papel: el juego (shared/PropModel) les pone color y
# material según el papel (Wood, Red, Pink, PinkLight, Orange, Leaf, LeafDark, Stone, StoneDark, Gold, Paper,
# Roof, White, Black, Water). "<Pieza>_Origin" marca el centro del suelo de la pieza y Axis_* dan la escala y los
# ejes de la importación. Medidas en studs, Y arriba, -Z al frente. Las piezas ya vienen a su tamaño real: el
# juego solo las gira y las varía un poco de tamaño.
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos")

ROLE_COLORS = {  # solo para verlo en Blender; en el juego manda PropModel
    "Wood": (0.55, 0.35, 0.2), "Red": (0.88, 0.2, 0.2), "Pink": (1, 0.58, 0.75), "PinkLight": (1, 0.8, 0.88),
    "Orange": (1, 0.55, 0.15), "Leaf": (0.27, 0.75, 0.37), "LeafDark": (0.16, 0.55, 0.33), "Stone": (0.67, 0.68, 0.72),
    "StoneDark": (0.43, 0.44, 0.49), "Gold": (1, 0.8, 0.27), "Paper": (1, 0.92, 0.65), "Roof": (0.2, 0.28, 0.43),
    "White": (0.98, 0.96, 0.92), "Black": (0.14, 0.12, 0.16), "Water": (0.3, 0.8, 0.85), "Marker": (1, 0, 1), "Fur": (0.8, 0.35, 0.15),
    "Cream": (1, 0.94, 0.85), "Tan": (0.84, 0.63, 0.4),
}


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


def sphere(r, n=10, rings=6):
    return lathe([(r * math.cos(math.pi * j / rings - math.pi / 2) if 0 < j < rings else 0,
                   r * math.sin(math.pi * j / rings - math.pi / 2)) for j in range(rings + 1)], n)


def cyl(r, h, n=10, r2=None):
    """Cilindro (o cono truncado) con la base en y=0."""
    return lathe([(r, 0), (r if r2 is None else r2, h)], n)


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


def blob(radii, seed, n=9, rings=5, jitter=0.2):
    """Bola a facetas con los vértices movidos al azar (con semilla): copas, rocas, arbustos."""
    rng = random.Random(seed)
    verts, faces = sphere(1, n, rings)
    out = []
    for x, y, z in verts:
        k = 1 + rng.uniform(-jitter, jitter) if abs(y) < 0.999 else 1
        out.append((x * k * radii[0], y * k * radii[1], z * k * radii[2]))
    return out, faces


def limb(a, b, r0, r1, n=7):
    """Tronco o rama: cono truncado desde el punto a hasta el punto b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    m = T(*a) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
    return m, cyl(r0, length, n, r1)


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

    def branch(self, role, a, b, r0, r1, n=7):
        m, shape = limb(a, b, r0, r1, n)
        self.add(role, shape, m)


# ---------- Árboles ----------

def blossom_tree(p, seed, light="PinkLight", main="Pink", height=17.0):
    """Cerezo: tronco torcido, ramas largas y copas redondas de flor rosa y rosa claro."""
    rng = random.Random(seed)
    pts = [(0, 0, 0)]
    x = z = 0.0
    for i in range(1, 5):
        x += rng.uniform(-0.9, 0.9)
        z += rng.uniform(-0.9, 0.9)
        pts.append((x, height * 0.3 * i / 2.2 * 0.5 + (i * height * 0.12), z))
    for i in range(4):
        p.branch("Wood", pts[i], pts[i + 1], 1.45 - 0.28 * i, 1.45 - 0.28 * (i + 1))
    p.add("Wood", cyl(1.9, 0.8, 8, 1.4))  # raíz ancha
    top = Vector(pts[-1])
    crowns = []
    for i in range(5):  # ramas hacia fuera
        a = 2 * math.pi * i / 5 + rng.uniform(-0.3, 0.3)
        start = Vector(pts[2 + i % 2])
        end = Vector((start.x + math.cos(a) * rng.uniform(4.5, 6.5), start.y + rng.uniform(2.5, 5), start.z + math.sin(a) * rng.uniform(4.5, 6.5)))
        p.branch("Wood", start, end, 0.5, 0.2)
        crowns.append(end)
    crowns.append(top + Vector((0, 2.5, 0)))
    for i, c in enumerate(crowns):
        r = rng.uniform(3.6, 5.2)
        p.add(main if i % 2 == 0 else light, blob((r, r * 0.78, r), seed * 10 + i, 9, 5, 0.17), T(*c))
        p.add(light if i % 2 == 0 else main, blob((r * 0.55, r * 0.45, r * 0.55), seed * 20 + i, 7, 4, 0.2), T(c.x + rng.uniform(-2, 2), c.y + r * 0.55, c.z + rng.uniform(-2, 2)))


def sakura(p):
    blossom_tree(p, 3)


def sakura_b(p):
    blossom_tree(p, 11, "Pink", "PinkLight", 14.0)


def maple(p):
    blossom_tree(p, 5, "Orange", "Red", 15.0)


def pine(p):
    """Pino japonés: tronco inclinado y nubes planas de agujas en capas."""
    pts = [(0, 0, 0), (0.8, 4, 0.2), (1.6, 8, -0.3), (1.0, 12, 0.3), (0.2, 15.5, 0)]
    for i in range(4):
        p.branch("Wood", pts[i], pts[i + 1], 1.2 - 0.25 * i, 1.2 - 0.25 * (i + 1))
    for i, (x, y, z, r) in enumerate(((3.8, 7.5, 0.5, 3.6), (-3.4, 9.5, -1.0, 3.2), (2.6, 12.5, 1.5, 3.0), (0.4, 16.0, 0.0, 3.4), (-2.2, 13.5, -1.8, 2.6))):
        p.branch("Wood", pts[min(i + 1, 4)], (x * 0.6 + pts[min(i + 1, 4)][0] * 0.4, y - 0.8, z * 0.6), 0.3, 0.15)
        p.add("Leaf" if i % 2 == 0 else "LeafDark", blob((r, r * 0.38, r * 0.9), 40 + i, 10, 4, 0.14), T(x + 0.6, y, z))
        p.add("LeafDark" if i % 2 == 0 else "Leaf", blob((r * 0.7, r * 0.25, r * 0.65), 60 + i, 8, 3, 0.15), T(x + 0.6, y + r * 0.3, z))


def bamboo(p):
    """Macizo de bambú: cañas altas con nudos y hojas en la punta."""
    rng = random.Random(9)
    for i in range(8):
        a = 2 * math.pi * i / 8 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.2, 2.6)
        x, z = math.cos(a) * d, math.sin(a) * d
        h = rng.uniform(15, 23)
        lean = (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8))
        p.branch("Leaf", (x, 0, z), (x + lean[0], h, z + lean[1]), 0.34, 0.26, 6)
        for k in range(1, 6):  # nudos
            y = h * k / 6
            p.add("LeafDark", cyl(0.42, 0.22, 6), T(x + lean[0] * k / 6, y, z + lean[1] * k / 6))
        for k in range(4):  # hojas
            b = 2 * math.pi * k / 4 + i
            tip = Vector((x + lean[0], h, z + lean[1]))
            p.add("LeafDark" if k % 2 else "Leaf", spike(0.28, 3.4, 4), T(*tip) @ R("Y", math.degrees(b)) @ R("Z", -62))


# ---------- Construcciones ----------

def torii(p):
    """Torii bermellón de 18 de ancho: dos columnas, travesaño, kasagi curvado negro y bases de piedra."""
    for s in (-1, 1):
        p.add("StoneDark", cyl(1.5, 0.7, 8, 1.3), T(s * 6.4, 0, 0))
        p.add("Red", cyl(0.95, 13.5, 10, 0.8), T(s * 6.4, 0.7, 0))
        p.add("Black", cyl(1.02, 1.0, 10), T(s * 6.4, 0.7, 0))
    p.add("Red", box(15.4, 0.9, 0.9), T(0, 9.6, 0))  # nuki
    p.add("Gold", box(1.1, 2.2, 0.5), T(0, 11.2, -0.5))  # tablilla
    p.add("Black", box(16.2, 0.9, 1.5), T(0, 14.0, 0))  # shimaki
    p.add("Red", box(14.0, 0.5, 1.2), T(0, 13.4, 0))
    for s in (-1, 1):  # kasagi: los extremos se levantan
        p.add("Black", box(8.6, 1.1, 2.1), T(s * 6.4, 14.9, 0) @ R("Z", s * -9) @ T(s * 1.0, 0, 0))
        p.add("Black", box(5.5, 1.1, 2.1), T(0, 14.7, 0))
    p.add("Black", box(8.0, 0.5, 1.6), T(0, 15.55, 0) @ S(1, 1, 1))


def stone_lantern(p):
    """Ishidoro: base, poste, caja de luz con papel, tejado y remate."""
    p.add("StoneDark", cyl(1.5, 0.6, 8, 1.3))
    p.add("Stone", cyl(0.55, 2.4, 8), T(0, 0.6, 0))
    p.add("StoneDark", cyl(1.0, 0.5, 8, 1.3), T(0, 3.0, 0))
    p.add("Stone", box(1.5, 1.4, 1.5), T(0, 3.8, 0))
    p.add("Paper", box(1.0, 1.0, 1.55), T(0, 3.8, 0))
    p.add("Paper", box(1.55, 1.0, 1.0), T(0, 3.8, 0))
    p.add("StoneDark", frustum(3.1, 3.1, 1.2, 1.2, 0.9), T(0, 4.95, 0))
    p.add("Stone", sphere(0.5, 8, 4), T(0, 5.7, 0) @ S(1, 1.2, 1))
    p.add("Gold", spike(0.2, 0.7, 6), T(0, 6.0, 0))


def chochin(p):
    """Farolillo de papel rojo con aros negros, para colgar."""
    p.add("Red", lathe([(0.0, -1.0), (0.7, -0.85), (1.05, -0.35), (1.1, 0), (1.05, 0.35), (0.7, 0.85), (0, 1.0)], 12), T(0, 0, 0))
    p.add("Paper", lathe([(0.0, -0.92), (0.6, -0.75), (1.0, -0.3), (1.02, 0), (1.0, 0.3), (0.6, 0.75), (0, 0.92)], 10), S(1.02, 1, 1.02))
    for y in (-0.95, 0.95):
        p.add("Black", cyl(0.55, 0.22, 10), T(0, y - 0.11 if y < 0 else y - 0.11, 0))
    p.add("Gold", box(0.15, 1.2, 0.15), T(0, 1.5, 0))
    p.add("Black", torus(0.2, 0.04, 10, 4), T(0, 2.1, 0) @ R("X", 90))


def pagoda(p):
    """Pagoda de cinco pisos: paredes blancas con vigas rojas, tejados oscuros curvados y aguja dorada."""
    p.add("StoneDark", box(17, 1.2, 17), T(0, 0.6, 0))
    p.add("Stone", box(15, 0.8, 15), T(0, 1.6, 0))
    y = 2.0
    width = 11.0
    for tier in range(5):
        h = 4.6 - tier * 0.35
        p.add("White", box(width, h, width), T(0, y + h / 2, 0))
        for s in (-1, 1):
            for t in (-1, 1):
                p.add("Red", box(0.7, h, 0.7), T(s * width / 2, y + h / 2, t * width / 2))
        p.add("Red", box(width * 0.28, h * 0.65, 0.2), T(0, y + h * 0.4, -width / 2 - 0.1))  # puerta
        p.add("Gold", box(width * 0.5, 0.18, 0.2), T(0, y + h * 0.82, -width / 2 - 0.12))
        y += h
        eave = width + 5.2 - tier * 0.4
        p.add("Roof", frustum(eave, eave, width * 0.5, width * 0.5, 2.3), T(0, y + 1.15, 0))
        p.add("Red", box(eave, 0.35, eave), T(0, y + 0.1, 0))
        for sx in (-1, 1):
            for sz in (-1, 1):  # esquinas levantadas
                p.add("Roof", spike(0.55, 1.9, 4), T(sx * eave / 2, y + 0.3, sz * eave / 2) @ R("X", -sz * 40) @ R("Z", sx * 40))
                p.add("Gold", sphere(0.2, 6, 3), T(sx * eave / 2 + sx * 0.5, y + 1.1, sz * eave / 2 + sz * 0.5))
        y += 2.3
        width -= 1.35
    p.add("Gold", cyl(0.35, 7.0, 8, 0.15), T(0, y - 0.4, 0))
    for k in range(5):
        p.add("Gold", torus(0.9 - k * 0.12, 0.14, 12, 4), T(0, y + 0.8 + k * 1.1, 0))


def bridge(p):
    """Puente taiko rojo: arco de 18 de largo con barandillas y piedras en los extremos."""
    n = 9
    for i in range(n):
        t = i / (n - 1)
        x = -9 + 18 * t
        y = 3.2 * math.sin(math.pi * t) + 0.5
        slope = math.degrees(math.atan2(3.2 * math.pi / 18 * math.cos(math.pi * t), 1))
        p.add("Wood", box(2.2, 0.5, 6.2), T(x, y, 0) @ R("Z", slope))
        if i % 2 == 0:
            p.add("Red", box(0.5, 0.5, 6.4), T(x, y + 0.35, 0) @ R("Z", slope))
        for s in (-1, 1):
            p.add("Red", box(0.4, 1.9, 0.4), T(x, y + 1.2, s * 3.0))
            if i < n - 1:
                x2 = -9 + 18 * (i + 1) / (n - 1)
                y2 = 3.2 * math.sin(math.pi * (i + 1) / (n - 1)) + 0.5
                p.add("Red", box(math.hypot(x2 - x, y2 - y) + 0.1, 0.35, 0.35), T((x + x2) / 2, (y + y2) / 2 + 2.0, s * 3.0) @ R("Z", math.degrees(math.atan2(y2 - y, x2 - x))))
    for s in (-1, 1):
        p.add("Gold", sphere(0.5, 8, 4), T(s * 8.9, 1.6, 3.0))
        p.add("Gold", sphere(0.5, 8, 4), T(s * 8.9, 1.6, -3.0))
        p.add("StoneDark", box(2.4, 1.0, 6.8), T(s * 10.2, 0.4, 0))


def shrine(p):
    """Hokora: capillita de santuario sobre un zócalo, con tejado curvado, cuerda shimenawa y papeles."""
    p.add("StoneDark", box(9, 0.9, 8), T(0, 0.45, 0))
    p.add("Stone", box(8, 0.6, 7), T(0, 1.2, 0))
    p.add("White", box(5.6, 3.6, 4.6), T(0, 3.3, 0))
    for s in (-1, 1):
        for t in (-1, 1):
            p.add("Red", box(0.5, 3.6, 0.5), T(s * 2.8, 3.3, t * 2.3))
    p.add("Red", box(2.2, 2.8, 0.2), T(0, 3.0, -2.35))
    p.add("Gold", box(0.5, 0.5, 0.25), T(0, 3.0, -2.5))
    p.add("Roof", frustum(8.8, 7.6, 3.2, 2.4, 2.6), T(0, 6.3, 0))
    p.add("Red", box(8.8, 0.4, 7.6), T(0, 5.1, 0))
    p.add("Gold", box(0.3, 0.3, 3.0), T(0, 7.7, 0))
    for s in (-1, 1):
        p.add("Gold", spike(0.35, 1.4, 4), T(s * 1.6, 7.5, 0) @ R("Z", s * -30))
    p.add("White", torus(2.7, 0.2, 14, 4), T(0, 5.6, -3.0) @ R("X", 90) @ S(1, 1, 0.35))
    for x in (-2, -0.7, 0.7, 2):
        p.add("White", box(0.4, 1.0, 0.06), T(x, 4.9, -3.05))
    p.add("StoneDark", box(5.4, 0.5, 3.2), T(0, 0.25, -5.8))


# ---------- Naturaleza pequeña ----------

def rocks(p):
    """Rocas de jardín con musgo."""
    p.add("Stone", blob((2.6, 1.9, 2.3), 71), T(0, 1.4, 0))
    p.add("StoneDark", blob((1.6, 1.2, 1.5), 72), T(2.6, 0.9, 1.2))
    p.add("Stone", blob((1.2, 0.9, 1.1), 73), T(-2.3, 0.6, 1.6))
    p.add("Leaf", blob((2.0, 0.35, 1.7), 74, 8, 3), T(0.2, 3.0, 0.1))
    p.add("LeafDark", blob((1.0, 0.25, 0.9), 75, 7, 3), T(2.6, 1.9, 1.2))
    p.add("PinkLight", blob((0.9, 0.15, 0.8), 76, 6, 3), T(-0.8, 3.2, -0.4))


def lotus(p):
    """Nenúfares con flor de loto rosa."""
    for i, (x, z, r) in enumerate(((0, 0, 1.9), (3.0, 1.6, 1.4), (-2.6, 1.9, 1.2), (1.2, -2.8, 1.5))):
        p.add("Leaf" if i % 2 == 0 else "LeafDark", cyl(r, 0.18, 12), T(x, 0, z))
        p.add("LeafDark", box(0.2, 0.2, r * 0.9), T(x, 0.19, z - r * 0.45))
    for i, (x, z) in enumerate(((0.3, 0.2), (3.0, 1.6), (-2.6, 1.9))):
        for k in range(6):
            a = 60 * k
            p.add("Pink" if k % 2 == 0 else "PinkLight", spike(0.42, 1.5, 4), T(x, 0.25, z) @ R("Y", a) @ R("Z", -38 + 6 * (i % 2)))
        p.add("Gold", sphere(0.28, 6, 3), T(x, 0.9, z))


def koi(p):
    """Carpa koi: cuerpo largo blanco con manchas naranjas y negras, cola y aletas. Mira hacia -Z."""
    body = lathe([(0.0, -1.9), (0.55, -1.4), (0.85, -0.5), (0.85, 0.4), (0.5, 1.4), (0.2, 2.0), (0.0, 2.2)], 8)
    p.add("White", body, R("X", 90) @ S(1, 1, 0.8) @ T(0, 0, 0))
    p.add("Orange", sphere(0.7, 7, 4), T(0, 0.28, -0.4) @ S(1.1, 0.6, 1.8))
    p.add("Orange", sphere(0.5, 7, 4), T(0.2, 0.28, 1.1) @ S(1, 0.55, 1.3))
    p.add("Black", sphere(0.3, 6, 3), T(-0.3, 0.38, 0.5) @ S(1, 0.5, 1.4))
    p.add("Orange", frustum(0.12, 0.7, 1.6, 0.12, 1.5), T(0, 0, 2.7) @ R("X", 90) @ S(1, 1, 1))
    p.add("Orange", box(0.08, 0.6, 1.2), T(0, 0.62, 0.2) @ R("X", -10))
    for s in (-1, 1):
        p.add("White", box(0.9, 0.06, 0.5), T(s * 0.75, -0.2, -0.9) @ R("Y", s * -30))
    p.add("Black", sphere(0.1, 5, 3), T(0.32, 0.3, -1.45))
    p.add("Black", sphere(0.1, 5, 3), T(-0.32, 0.3, -1.45))


def bonsai(p):
    """Bonsái pequeño en maceta."""
    p.add("Red", frustum(1.8, 1.8, 2.3, 2.3, 0.9), T(0, 0.45, 0))
    p.add("Gold", box(2.35, 0.14, 2.35), T(0, 0.9, 0))
    p.add("Wood", cyl(0.2, 1.6, 6, 0.12), T(0.2, 0.9, 0) @ R("Z", -12))
    p.add("Pink", blob((1.0, 0.55, 0.95), 81, 8, 4), T(0.1, 2.7, 0.1))
    p.add("PinkLight", blob((0.6, 0.35, 0.6), 82, 7, 3), T(0.8, 2.3, 0.2))


def fence(p):
    """Valla de bambú de 8 de largo (a lo largo de X): postes con nudos, dos travesaños y ataduras."""
    for i in range(5):
        x = -4 + 2 * i
        p.add("Leaf", cyl(0.3, 3.4, 6, 0.26), T(x, 0, 0))
        p.add("LeafDark", cyl(0.36, 0.2, 6), T(x, 3.0, 0))
        p.add("LeafDark", cyl(0.36, 0.2, 6), T(x, 1.2, 0))
    for y in (1.1, 2.3):
        p.add("LeafDark", cyl(0.2, 8.0, 6), T(-4.0, y, 0) @ R("Z", -90))
        for i in range(5):
            p.add("Wood", cyl(0.34, 0.3, 6), T(-4 + 2 * i, y - 0.15, 0))
    for i in range(4):  # cañas finas entre los postes
        p.add("Leaf", cyl(0.14, 2.6, 5, 0.1), T(-3 + 2 * i, 0, 0))


def lock(p, role, pos, direction, length, width, curl=None):
    """Mechón de melena: elipsoide alargado que sale de `pos` hacia `direction` (con un rizo en la punta si `curl`)."""
    d = Vector(direction).normalized()
    m = T(*pos) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4() @ T(0, 0, length * 0.5)
    p.add(role, sphere(1, 7, 4), m @ S(width, width * 0.85, length * 0.5))
    if curl:
        tip = Vector(pos) + d * length
        p.add(curl, sphere(width * 0.85, 6, 3), T(*tip) @ T(0, width * 0.7, 0))


def paw(p, x, y, z, size, role="Stone"):
    p.add(role, sphere(1, 8, 4), T(x, y, z) @ S(size * 0.55, size * 0.34, size * 0.85))
    for k in (-1.5, -0.5, 0.5, 1.5):  # dedos y garras
        p.add(role, sphere(size * 0.17, 5, 3), T(x + k * size * 0.2, y - size * 0.05, z - size * 0.78))
        p.add("StoneDark", spike(size * 0.05, size * 0.2, 4), T(x + k * size * 0.2, y - size * 0.1, z - size * 0.92) @ R("X", -80))


def komainu(p):
    """Komainu de piedra, más realista: roca natural de base, cuerpo sentado con musculatura, patas con codo y garras,
    cabeza con ceño, boca abierta con colmillos y lengua, melena en mechones que barren hacia atrás y cola en
    abanico. Babero rojo con cascabel y musgo en la piedra. Mira hacia -Z."""
    # Base de roca natural y losa superior.
    p.add("StoneDark", blob((2.6, 0.9, 3.1), 301, 11, 6, 0.1), T(0, 0.6, 0.2))
    p.add("Stone", box(3.5, 0.7, 4.2), T(0, 1.45, 0.15))
    p.add("StoneDark", box(3.7, 0.18, 4.4), T(0, 1.82, 0.15))
    p.add("Leaf", blob((1.1, 0.12, 0.9), 302, 7, 3), T(-1.1, 1.95, 1.7))
    p.add("Leaf", blob((0.8, 0.1, 0.6), 303, 6, 3), T(1.2, 0.95, -2.2))
    base = 1.9
    # Cuarto trasero: grupa, muslos y patas traseras dobladas.
    p.add("Stone", sphere(1, 14, 8), T(0, base + 1.25, 1.0) @ S(1.35, 1.2, 1.5))
    for s in (-1, 1):
        p.add("Stone", sphere(1, 11, 6), T(s * 1.0, base + 0.95, 0.55) @ S(0.62, 0.95, 1.1))
        p.branch("Stone", (s * 1.0, base + 0.5, 0.2), (s * 0.95, base + 0.2, -0.45), 0.42, 0.3, 8)
        paw(p, s * 0.95, base + 0.12, -0.75, 0.62)
    # Torso erguido, omóplatos y pecho ancho.
    p.add("Stone", sphere(1, 14, 8), T(0, base + 2.5, 0.2) @ S(1.1, 1.9, 1.15) @ R("X", -14))
    for s in (-1, 1):
        p.add("Stone", sphere(1, 9, 5), T(s * 0.88, base + 3.3, -0.35) @ S(0.5, 0.75, 0.6))  # omóplatos
        p.add("StoneDark", box(0.06, 0.5, 0.5), T(s * 1.05, base + 1.9, 0.0) @ R("Z", s * 12))  # marca de costillas
    p.add("Stone", sphere(1, 14, 8), T(0, base + 3.2, -0.65) @ S(1.25, 1.2, 1.1))  # pecho
    # Patas delanteras: hombro, codo y muñeca; la izquierda sobre una bola de piedra.
    for s in (-1, 1):
        p.branch("Stone", (s * 0.8, base + 3.2, -0.55), (s * 0.82, base + 1.75, -0.95), 0.5, 0.4, 9)
        p.branch("Stone", (s * 0.82, base + 1.75, -0.95), (s * 0.85, base + 0.45, -1.75), 0.4, 0.3, 9)
        paw(p, s * 0.85, base + 0.18, -2.05, 0.75)
    p.add("StoneDark", sphere(0.55, 11, 6), T(-0.85, base + 0.62, -2.6))  # bola bajo la zarpa
    # Babero rojo con cascabel.
    p.add("Red", frustum(2.6, 2.0, 1.8, 1.6, 0.75), T(0, base + 4.0, -0.7) @ R("X", 8))
    p.add("Gold", sphere(0.23, 8, 5), T(0, base + 3.55, -1.55))
    p.add("Gold", box(0.55, 0.06, 0.06), T(0, base + 3.78, -1.5))
    # Cuello y cabeza.
    p.branch("Stone", (0, base + 3.7, -0.7), (0, base + 4.8, -1.05), 1.0, 0.85, 10)
    hy, hz = base + 5.15, -1.2
    p.add("Stone", sphere(1.2, 14, 8), T(0, hy, hz) @ S(1.08, 0.95, 1.0))  # cráneo
    p.add("Stone", sphere(1, 11, 6), T(0, hy - 0.2, hz - 0.95) @ S(0.82, 0.5, 0.8))  # hocico
    p.add("StoneDark", sphere(0.32, 8, 5), T(0, hy + 0.02, hz - 1.62) @ S(1.5, 0.85, 0.8))  # nariz ancha
    p.add("StoneDark", sphere(0.08, 5, 3), T(-0.2, hy - 0.02, hz - 1.88))
    p.add("StoneDark", sphere(0.08, 5, 3), T(0.2, hy - 0.02, hz - 1.88))
    p.add("Stone", sphere(1, 8, 5), T(0, hy + 0.5, hz - 0.85) @ S(0.95, 0.2, 0.4))  # arco del ceño
    p.add("Stone", box(0.1, 0.5, 0.3), T(0, hy + 0.7, hz - 0.95) @ R("X", 15))  # surco entre las cejas
    # Boca abierta: labios, mandíbula inferior, dientes y lengua.
    for s in (-1, 1):
        p.add("Stone", sphere(0.4, 8, 5), T(s * 0.5, hy - 0.38, hz - 1.0) @ S(1, 0.8, 1.1))  # carrillos
        p.add("White", spike(0.1, 0.42, 5), T(s * 0.42, hy - 0.5, hz - 1.5) @ R("X", 180))  # colmillos de arriba
        p.add("White", spike(0.09, 0.34, 5), T(s * 0.4, hy - 1.0, hz - 1.35))  # y de abajo
        p.add("White", box(0.2, 0.14, 0.08), T(s * 0.14, hy - 0.48, hz - 1.72))  # incisivos
        p.add("White", box(0.2, 0.14, 0.08), T(s * 0.14, hy - 0.88, hz - 1.62))
        p.add("StoneDark", sphere(1, 8, 5), T(s * 0.52, hy + 0.3, hz - 0.95) @ S(0.3, 0.3, 0.25))  # cuencas
        p.add("White", sphere(0.24, 8, 5), T(s * 0.53, hy + 0.3, hz - 1.0))
        p.add("Black", sphere(0.12, 6, 4), T(s * 0.54, hy + 0.3, hz - 1.2))
        p.add("StoneDark", sphere(1, 8, 4), T(s * 0.55, hy + 0.62, hz - 1.0) @ S(0.42, 0.13, 0.22) @ R("Z", s * -22))  # cejas
        p.add("Stone", sphere(1, 8, 5), T(s * 1.2, hy + 0.8, hz + 0.2) @ S(0.28, 0.42, 0.2) @ R("Z", s * -28))  # orejas
    p.add("Stone", box(1.1, 0.24, 0.9), T(0, hy - 0.95, hz - 0.85) @ R("X", 22))  # mandíbula inferior
    p.add("Red", sphere(0.34, 7, 4), T(0, hy - 0.7, hz - 0.95) @ S(1.3, 0.25, 1.5))  # lengua
    p.add("Red", box(1.0, 0.05, 0.7), T(0, hy - 0.62, hz - 0.9))  # paladar
    # Melena: tres coronas de mechones alrededor de la cara que barren hacia atrás, y una hilera por la nuca y el lomo.
    for ring_i, (radius, count, length, width) in enumerate(((1.15, 13, 1.1, 0.22), (1.45, 15, 1.6, 0.24), (1.75, 17, 2.1, 0.26))):
        for i in range(count):
            a = 2 * math.pi * i / count + ring_i * 0.18
            ca, sa = math.cos(a), math.sin(a)
            if ring_i == 0 and sa < -0.15 and abs(ca) < 0.75:
                continue  # deja libre la cara
            pos = (ca * radius * 1.05, hy + sa * radius * 0.9, hz + 0.35 + ring_i * 0.2)
            lock(p, "Stone" if (i + ring_i) % 2 == 0 else "StoneDark", pos, (ca * 0.55, sa * 0.55 - 0.1, 1.0), length, width, "Stone" if i % 3 == 0 else None)
    for i in range(7):  # lomo
        t = i / 6
        lock(p, "Stone" if i % 2 == 0 else "StoneDark", (0, base + 4.4 - t * 2.0, -0.2 + t * 0.9), (0, -0.4, 1.0), 1.2 - t * 0.3, 0.3, None)
    # Cola en abanico sobre la grupa.
    for i in range(9):
        a = -70 + i * 17.5
        lock(p, "Stone" if i % 2 == 0 else "StoneDark", (0, base + 1.5, 2.2), (math.sin(math.radians(a)) * 0.8, math.cos(math.radians(a)) * 0.9 + 0.2, 0.7), 2.4, 0.3, "Gold" if i == 4 else None)
    # Grietas y musgo.
    p.add("StoneDark", box(0.05, 0.9, 0.05), T(-0.6, base + 2.0, 1.3) @ R("Z", 14))
    p.add("StoneDark", box(0.05, 0.6, 0.05), T(1.3, base + 1.1, 0.7) @ R("Z", -22))
    p.add("Leaf", blob((0.5, 0.1, 0.4), 304, 6, 3), T(0.7, base + 2.4, 1.0))
    p.add("Leaf", blob((0.4, 0.1, 0.35), 305, 6, 3), T(-0.9, base + 1.0, 1.3))


def temple_roof(p):
    """Tejado octogonal de templo (hakkaku-dō) de dos pisos, con aleros curvos, esquinas levantadas, vigas rojas por
    debajo, paredes blancas en el piso de arriba y remate dorado de varios anillos. Origen: centro, nivel del alero."""
    # Vigas y bajo del alero.
    p.add("Red", lathe([(25.6, -0.5), (25.6, 0.0), (6.0, 0.0), (6.0, -0.6)], 8))
    for i in range(8):
        a = 360 / 8 * i + 22.5
        p.add("Red", box(18.5, 0.7, 0.8), T(0, -0.35, 0) @ R("Y", a) @ T(9.6, 0, 0))
    p.add("Gold", torus(25.2, 0.18, 8, 4), T(0, -0.1, 0))
    # Tejado bajo con pendiente cóncava (más tendida al borde) y cresta en cada esquina.
    p.add("Roof", lathe([(26.0, 0.0), (23.5, 1.0), (19.5, 2.5), (14.5, 4.6), (10.0, 6.8)], 8))
    for i in range(8):
        a = 360 / 8 * i
        p.add("Roof", spike(0.8, 5.2, 5), T(0, 0.2, 0) @ R("Y", -a) @ T(25.5, 0.1, 0) @ R("Z", -62))
        p.add("Gold", sphere(0.4, 6, 3), T(math.cos(math.radians(a)) * 30.0, 2.6, math.sin(math.radians(a)) * 30.0))
    # Piso de arriba: pared blanca con zócalo rojo, ventanas y segundo tejado.
    p.add("White", lathe([(9.5, 6.6), (9.5, 11.0)], 8))
    p.add("Red", lathe([(9.8, 6.4), (9.8, 7.4)], 8))
    p.add("Red", lathe([(9.8, 10.2), (9.8, 11.2)], 8))
    for i in range(8):
        a = 360 / 8 * i + 22.5
        p.add("Red", box(0.5, 4.8, 0.5), T(0, 8.8, 0) @ R("Y", -a - 22.5) @ T(9.6, 0, 0))
        p.add("Black", box(0.1, 2.0, 2.4), T(0, 8.9, 0) @ R("Y", -a) @ T(9.55, 0, 0))
        p.add("Gold", box(0.05, 2.1, 0.12), T(0, 8.9, 0) @ R("Y", -a) @ T(9.62, 0, 0))
    p.add("Roof", lathe([(14.5, 11.0), (12.5, 11.9), (9.5, 13.4), (6.0, 15.6), (2.0, 18.0)], 8))
    for i in range(8):
        a = 360 / 8 * i
        p.add("Roof", spike(0.6, 3.6, 5), T(0, 11.2, 0) @ R("Y", -a) @ T(14.2, 0, 0) @ R("Z", -60))
    # Remate dorado: poste, anillos y gema.
    p.add("Gold", cyl(0.4, 6.0, 8, 0.25), T(0, 17.6, 0))
    for k in range(6):
        p.add("Gold", torus(1.5 - k * 0.17, 0.2, 14, 4), T(0, 18.6 + k * 0.85, 0))
    p.add("Gold", sphere(0.8, 8, 5), T(0, 23.6, 0) @ S(1, 1.3, 1))
    p.add("Gold", spike(0.3, 1.2, 6), T(0, 24.6, 0))


def koinobori(p):
    """Koinobori: mástil con rueda de flechas dorada y cuatro carpas de tela de colores que ondean."""
    p.add("Wood", cyl(0.3, 24, 8, 0.2))
    p.add("Gold", sphere(0.55, 8, 4), T(0, 24.2, 0))
    for i in range(6):
        p.add("Gold", spike(0.2, 1.8, 4), T(0, 24.6, 0) @ R("Z", 60 * i) @ T(0, 0.5, 0))
    p.add("Gold", torus(0.55, 0.07, 14, 4), T(0, 24.6, 0) @ R("X", 90))
    for i, (role, y, length, radius) in enumerate((("Black", 21.0, 8.0, 1.6), ("Red", 17.8, 6.8, 1.35), ("Roof", 14.8, 5.6, 1.15), ("Pink", 12.2, 4.6, 0.95))):
        sag = -4 * i
        body = lathe([(radius, 0), (radius * 0.9, length * 0.3), (radius * 0.55, length * 0.7), (radius * 0.22, length)], 10)
        p.add(role, body, T(0.4, y, 0) @ R("Z", -90 - sag * 0.8))
        p.add("White", sphere(radius * 0.22, 6, 3), T(0.9, y + radius * 0.55, radius * 0.7))
        p.add("White", sphere(radius * 0.22, 6, 3), T(0.9, y + radius * 0.55, -radius * 0.7))
        p.add("Gold", torus(radius * 0.95, 0.07, 14, 4), T(0.4, y, 0) @ R("Z", 90 + sag * 0.8) @ R("X", 0))
        p.add("Black", box(0.1, 0.1, 0.1), T(0.2, y + 0.4, 0))


# ---------- Animales (miran hacia -Z, con las patas en y=0) ----------
# Cuerpo en tres bultos (pecho, vientre y grupa), patas con muslo, rodilla y caña, cuello que une el cuerpo con la
# cabeza, hocico y ojos: más natural que una bola con cuatro palos.

def leg(p, upper, x, z, top, thick, length, knee=0.3, lower=None, paw=None):
    """Pata: muslo desde (x, top, z), rodilla algo adelantada o atrasada según `knee`, caña y pie."""
    lower = lower or upper
    a = (x, top, z)
    b = (x, top - length * 0.48, z + knee)
    c = (x, 0.14, z + knee * 0.15)
    p.branch(upper, a, b, thick, thick * 0.74, 8)
    p.branch(lower, b, c, thick * 0.74, thick * 0.5, 8)
    p.add(lower, sphere(thick * 0.7, 7, 4), T(x, 0.2, z + knee * 0.15 - thick * 0.35) @ S(1, 0.5, 1.5))
    if paw:
        p.add(paw, sphere(thick * 0.6, 6, 3), T(x, 0.16, z + knee * 0.15 - thick * 0.9) @ S(1, 0.5, 0.9))


def torso(p, role, L, W, H, cy, belly=None):
    """Cuerpo en tres bultos: pecho, vientre y grupa."""
    p.add(role, sphere(1, 12, 7), T(0, cy + H * 0.05, -L * 0.2) @ S(W / 2, H / 2 * 1.05, L * 0.34))
    p.add(role, sphere(1, 12, 7), T(0, cy, 0) @ S(W / 2 * 0.92, H / 2 * 0.9, L * 0.3))
    p.add(role, sphere(1, 12, 7), T(0, cy + H * 0.03, L * 0.22) @ S(W / 2 * 0.95, H / 2 * 0.97, L * 0.3))
    if belly:
        p.add(belly, sphere(1, 10, 6), T(0, cy - H * 0.2, -L * 0.02) @ S(W / 2 * 0.8, H / 2 * 0.68, L * 0.46))


def eye(p, x, y, z, r=0.12, iris="Black"):
    p.add(iris, sphere(r, 6, 4), T(x, y, z))
    p.add("White", sphere(r * 0.4, 4, 3), T(x * 1.02, y + r * 0.35, z - r * 0.6))


def muzzle_nose(p, x, y, z, r, role="Black"):
    p.add(role, sphere(r, 6, 4), T(x, y, z) @ S(1.3, 0.85, 0.9))


def panda(p):
    L, W, H = 4.8, 3.0, 2.8
    cy = 3.0
    torso(p, "White", L, W, H, cy)
    p.add("Black", sphere(1, 12, 7), T(0, cy + 0.1, -L * 0.2) @ S(W / 2 + 0.06, H / 2 * 1.08, 0.8))  # banda de los hombros
    for s in (-1, 1):
        leg(p, "Black", s * W * 0.3, -L * 0.26, cy - 0.3, 0.7, 2.6, 0.2)
        leg(p, "Black", s * W * 0.3, L * 0.26, cy - 0.2, 0.72, 2.6, -0.3)
    p.add("White", sphere(1.3, 9, 5), T(0, cy + 0.5, -L / 2 + 0.2) @ S(1, 1, 1))  # cuello grueso
    hy, hz = cy + 1.0, -L / 2 - 0.5
    p.add("White", sphere(1.35, 12, 7), T(0, hy, hz) @ S(1.12, 0.95, 1.0))
    p.add("White", sphere(0.75, 9, 5), T(0, hy - 0.4, hz - 1.0) @ S(1, 0.72, 0.95))  # hocico
    muzzle_nose(p, 0, hy - 0.15, hz - 1.62, 0.22)
    p.add("Black", box(0.05, 0.3, 0.05), T(0, hy - 0.5, hz - 1.55))
    for s in (-1, 1):
        p.add("Black", sphere(0.48, 8, 5), T(s * 0.98, hy + 1.0, hz + 0.1))  # orejas
        p.add("Black", sphere(1, 8, 5), T(s * 0.55, hy + 0.2, hz - 1.0) @ S(0.3, 0.45, 0.2) @ R("Z", s * 28))  # manchas de los ojos
        eye(p, s * 0.52, hy + 0.2, hz - 1.18, 0.09, "Black")
        p.add("White", sphere(0.07, 4, 3), T(s * 0.52, hy + 0.23, hz - 1.26))
    p.add("White", sphere(0.42, 7, 4), T(0, cy + 0.3, L / 2 + 0.25))  # cola


def red_panda(p):
    L, W, H = 3.2, 1.8, 1.7
    cy = 1.9
    torso(p, "Fur", L, W, H, cy, "Black")
    for s in (-1, 1):
        leg(p, "Black", s * W * 0.28, -L * 0.26, cy - 0.2, 0.34, 1.6, 0.15)
        leg(p, "Black", s * W * 0.28, L * 0.24, cy - 0.15, 0.36, 1.6, -0.2)
    p.add("Fur", sphere(0.85, 9, 5), T(0, cy + 0.35, -L / 2 + 0.2))
    hy, hz = cy + 0.65, -L / 2 - 0.35
    p.add("Fur", sphere(0.95, 11, 6), T(0, hy, hz) @ S(1.2, 0.92, 1.0))
    p.add("Cream", sphere(0.55, 8, 5), T(0, hy - 0.22, hz - 0.62) @ S(1.2, 0.75, 0.85))  # hocico blanco
    muzzle_nose(p, 0, hy - 0.08, hz - 1.0, 0.12)
    for s in (-1, 1):
        p.add("Fur", spike(0.36, 0.65, 6), T(s * 0.66, hy + 0.62, hz + 0.1) @ R("Z", -s * 14))
        p.add("Cream", spike(0.2, 0.4, 5), T(s * 0.66, hy + 0.7, hz + 0.02) @ R("Z", -s * 14))
        p.add("Cream", sphere(0.34, 7, 4), T(s * 0.5, hy + 0.1, hz - 0.5) @ S(1, 0.7, 0.8))  # pómulos
        p.add("Black", sphere(1, 6, 4), T(s * 0.32, hy + 0.14, hz - 0.78) @ S(0.16, 0.28, 0.12) @ R("Z", s * -20))  # lágrimas oscuras
        eye(p, s * 0.34, hy + 0.17, hz - 0.84, 0.08)
    for i in range(8):  # cola larga anillada
        t = i / 7
        p.add("Fur" if i % 2 == 0 else "Cream", sphere(0.5 - t * 0.12, 8, 4), T(0, cy + 0.3 + math.sin(t * 2.2) * 0.9, L / 2 + 0.2 + t * 2.3) @ S(1, 1, 0.8))


def tiger(p):
    L, W, H = 7.0, 2.5, 2.9
    cy = 3.6
    torso(p, "Orange", L, W, H, cy, "White")
    p.add("Orange", sphere(1, 9, 5), T(0, cy + H * 0.5, -L * 0.22) @ S(W * 0.36, 0.5, 1.3))  # lomo con la cruz marcada
    for s in (-1, 1):
        leg(p, "Orange", s * W * 0.28, -L * 0.27, cy - 0.4, 0.62, 3.3, 0.25, None, "Cream")
        leg(p, "Orange", s * W * 0.28, L * 0.27, cy - 0.3, 0.7, 3.3, -0.55, None, "Cream")
    for i in range(10):  # rayas
        z = -L * 0.34 + i * L * 0.075
        k = math.sqrt(max(1 - (z / (L / 2 + 0.2)) ** 2, 0.06))
        p.add("Black", box(W * 0.46, 0.15, 0.3 - 0.01 * i), T(0, cy + H / 2 * k * 1.0 + 0.04, z))
        for s in (-1, 1):
            p.add("Black", box(0.16, H * (0.3 if i % 2 else 0.42), 0.26), T(s * (W / 2 * k * 0.95), cy + H * 0.12, z + (0.05 if i % 2 else 0)) @ R("Z", s * -14))
    neck_a, neck_b = (0, cy + 0.35, -L * 0.34), (0, cy + 1.0, -L * 0.5 - 0.5)
    p.branch("Orange", neck_a, neck_b, 1.15, 0.95, 9)
    hy, hz = cy + 1.1, -L / 2 - 0.9
    p.add("Orange", sphere(1.35, 12, 7), T(0, hy, hz) @ S(1.1, 0.95, 0.95))
    p.add("Cream", sphere(0.85, 9, 5), T(0, hy - 0.45, hz - 1.0) @ S(1.25, 0.75, 0.85))  # hocico
    p.add("Pink", sphere(0.2, 6, 4), T(0, hy - 0.15, hz - 1.72) @ S(1.4, 0.85, 0.8))
    p.add("Black", box(0.06, 0.4, 0.06), T(0, hy - 0.5, hz - 1.7))
    for s in (-1, 1):
        p.add("Cream", spike(0.28, 0.7, 5), T(s * 1.25, hy - 0.5, hz - 0.2) @ R("Z", -s * 100))  # patillas
        p.add("Orange", sphere(0.52, 8, 5), T(s * 1.0, hy + 1.1, hz + 0.3) @ S(1, 1, 0.6))
        p.add("Black", sphere(0.3, 6, 4), T(s * 1.0, hy + 1.1, hz + 0.52) @ S(1, 1, 0.5))
        p.add("Gold", sphere(0.17, 6, 4), T(s * 0.55, hy + 0.32, hz - 1.15))
        p.add("Black", box(0.05, 0.22, 0.05), T(s * 0.55, hy + 0.32, hz - 1.3))
        p.add("Black", box(0.55, 0.12, 0.2), T(s * 1.02, hy + 0.15, hz - 0.7) @ R("Z", s * 16))
        p.add("Black", box(0.55, 0.12, 0.2), T(s * 1.05, hy - 0.2, hz - 0.65) @ R("Z", s * -8))
    p.add("Black", box(0.18, 0.7, 0.18), T(0, hy + 0.85, hz - 0.85))
    for i in range(9):  # cola larga con anillos
        t = i / 8
        p.add("Black" if i % 2 else "Orange", sphere(0.34 - t * 0.04, 7, 4), T(0, cy - 0.2 + math.sin(t * 2.4) * 1.6, L / 2 + 0.2 + t * 3.2) @ S(1, 1, 1.4))


def fox(p):
    L, W, H = 3.6, 1.5, 1.5
    cy = 2.1
    torso(p, "Orange", L, W, H, cy, "Cream")
    for s in (-1, 1):
        leg(p, "Orange", s * W * 0.28, -L * 0.26, cy - 0.2, 0.26, 1.9, 0.2, "Black")
        leg(p, "Orange", s * W * 0.28, L * 0.26, cy - 0.15, 0.3, 1.9, -0.4, "Black")
    p.branch("Orange", (0, cy + 0.2, -L * 0.3), (0, cy + 0.65, -L / 2 - 0.2), 0.62, 0.5, 8)
    hy, hz = cy + 0.75, -L / 2 - 0.35
    p.add("Orange", sphere(0.8, 10, 6), T(0, hy, hz) @ S(1.1, 0.9, 1.0))
    p.branch("Orange", (0, hy - 0.05, hz - 0.5), (0, hy - 0.22, hz - 1.55), 0.42, 0.18, 8)  # hocico largo
    p.add("Cream", sphere(0.34, 7, 4), T(0, hy - 0.4, hz - 0.9) @ S(1, 0.6, 1.6))
    muzzle_nose(p, 0, hy - 0.2, hz - 1.62, 0.1)
    for s in (-1, 1):
        p.add("Orange", spike(0.34, 1.2, 5), T(s * 0.48, hy + 0.55, hz + 0.1) @ R("Z", -s * 6))
        p.add("Black", spike(0.2, 0.55, 5), T(s * 0.5, hy + 1.3, hz + 0.1) @ R("Z", -s * 6))
        p.add("Cream", sphere(0.34, 7, 4), T(s * 0.5, hy - 0.2, hz - 0.5) @ S(1, 0.8, 1))
        eye(p, s * 0.36, hy + 0.15, hz - 0.8, 0.08)
    for i in range(5):  # cola grande y esponjosa
        t = i / 4
        p.add("White" if i == 4 else "Orange", sphere(0.5 + 0.1 * math.sin(t * 3), 8, 4), T(0, cy + 0.3 - t * 0.2, L / 2 + 0.5 + t * 1.9) @ S(1, 1, 1.4))


def tanuki(p):
    L, W, H = 3.2, 2.4, 2.3
    cy = 1.7
    torso(p, "Wood", L, W, H, cy, "Cream")
    for s in (-1, 1):
        leg(p, "Black", s * W * 0.3, -L * 0.25, cy - 0.2, 0.34, 1.4, 0.1)
        leg(p, "Black", s * W * 0.3, L * 0.25, cy - 0.15, 0.36, 1.4, -0.2)
    p.add("Wood", sphere(0.95, 8, 5), T(0, cy + 0.45, -L / 2 + 0.2))
    hy, hz = cy + 0.75, -L / 2 - 0.3
    p.add("Wood", sphere(1.0, 11, 6), T(0, hy, hz) @ S(1.2, 0.9, 1.0))
    p.add("Cream", sphere(0.5, 8, 5), T(0, hy - 0.28, hz - 0.65) @ S(1.2, 0.7, 0.9))
    muzzle_nose(p, 0, hy - 0.08, hz - 1.05, 0.13)
    for s in (-1, 1):
        p.add("Black", sphere(1, 8, 5), T(s * 0.4, hy + 0.16, hz - 0.7) @ S(0.36, 0.2, 0.2) @ R("Z", s * -20))  # antifaz
        p.add("Black", sphere(0.3, 7, 4), T(s * 0.82, hy + 0.82, hz + 0.1))
        eye(p, s * 0.4, hy + 0.17, hz - 0.88, 0.07)
    for i in range(5):
        p.add("Wood" if i % 2 == 0 else "Black", sphere(0.62 - i * 0.07, 7, 4), T(0, cy + 0.2 + i * 0.08, L / 2 + 0.3 + i * 0.4))


def deer(p):
    L, W, H = 4.4, 1.7, 1.8
    cy = 3.6
    torso(p, "Tan", L, W, H, cy, "Cream")
    for i in range(10):  # manchas
        p.add("Cream", sphere(0.14, 5, 3), T(math.sin(i * 2.1) * 0.6, cy + H * 0.44, -L * 0.3 + i * 0.45))
    for s in (-1, 1):
        leg(p, "Tan", s * W * 0.26, -L * 0.27, cy - 0.4, 0.26, 3.6, 0.2, "Wood")
        leg(p, "Tan", s * W * 0.26, L * 0.26, cy - 0.3, 0.3, 3.6, -0.6, "Wood")
    # El cuello sale del pecho y acaba dentro de la cabeza.
    neck_a, neck_b = (0, cy + 0.45, -L * 0.34), (0, cy + 2.35, -L * 0.5 - 0.75)
    p.branch("Tan", neck_a, neck_b, 0.6, 0.36, 9)
    p.add("Cream", sphere(0.5, 7, 4), T(0, cy + 1.2, -L * 0.48 - 0.1) @ S(0.8, 1.3, 0.8))  # pechuga
    hy, hz = neck_b[1] + 0.2, neck_b[2] - 0.3
    p.add("Tan", sphere(0.55, 10, 6), T(0, hy, hz) @ S(0.85, 0.85, 1.05))  # cráneo
    p.branch("Tan", (0, hy - 0.05, hz - 0.3), (0, hy - 0.3, hz - 1.2), 0.38, 0.24, 8)  # hocico
    p.add("Cream", sphere(0.26, 6, 4), T(0, hy - 0.34, hz - 1.18) @ S(1, 0.8, 1))
    muzzle_nose(p, 0, hy - 0.26, hz - 1.4, 0.1)
    for s in (-1, 1):
        eye(p, s * 0.42, hy + 0.12, hz - 0.35, 0.09)
        p.add("Tan", sphere(1, 7, 4), T(s * 0.62, hy + 0.55, hz + 0.25) @ S(0.15, 0.5, 0.26) @ R("Z", -s * 40))  # orejas
        p.add("Cream", sphere(1, 6, 4), T(s * 0.58, hy + 0.55, hz + 0.28) @ S(0.1, 0.35, 0.16) @ R("Z", -s * 40))
        base = (s * 0.3, hy + 0.5, hz + 0.1)  # cuernas con ramas
        p.branch("Wood", base, (s * 0.45, hy + 1.6, hz + 0.45), 0.07, 0.045, 5)
        p.branch("Wood", (s * 0.4, hy + 1.1, hz + 0.3), (s * 0.7, hy + 1.8, hz + 0.1), 0.05, 0.03, 5)
        p.branch("Wood", (s * 0.45, hy + 1.6, hz + 0.45), (s * 0.7, hy + 2.2, hz + 0.6), 0.045, 0.025, 5)
        p.branch("Wood", (s * 0.45, hy + 1.6, hz + 0.45), (s * 0.3, hy + 2.3, hz + 0.3), 0.04, 0.025, 5)
    p.add("Cream", sphere(0.3, 6, 4), T(0, cy + 0.6, L / 2 + 0.2) @ S(1, 1.3, 0.7))  # rabo


def crane(p):
    p.add("White", sphere(1, 11, 6), T(0, 4.2, 0.3) @ S(0.9, 0.85, 1.6))  # cuerpo
    p.add("White", sphere(1, 9, 5), T(0, 4.1, -1.1) @ S(0.7, 0.7, 0.8))  # pecho
    for s in (-1, 1):
        p.branch("Black", (s * 0.3, 3.7, 0.1), (s * 0.3, 2.0, 0.35), 0.1, 0.07, 5)  # muslo y rodilla
        p.branch("Black", (s * 0.3, 2.0, 0.35), (s * 0.3, 0.1, 0.05), 0.07, 0.05, 5)
        p.add("Black", box(0.45, 0.06, 0.9), T(s * 0.3, 0.04, -0.3))
        p.add("White", sphere(1, 10, 5), T(s * 0.82, 4.25, 0.4) @ S(0.18, 0.62, 1.5) @ R("Z", s * 7))  # ala plegada
        for k in range(3):
            p.add("White", sphere(1, 8, 4), T(s * (0.9 + 0.03 * k), 3.9 - 0.1 * k, 0.9 + 0.3 * k) @ S(0.12, 0.28, 0.95))
        p.add("Black", sphere(1, 7, 4), T(s * 0.88, 3.7, 1.7) @ S(0.14, 0.26, 0.7))  # puntas negras
    for i in range(5):  # plumas de la cola
        p.add("Black", spike(0.1, 1.5, 4), T(0, 4.0, 1.7) @ R("X", 72) @ R("Y", (i - 2) * 14))
    pts = [(0, 4.6, -1.3), (0, 5.5, -1.9), (0, 6.5, -1.75), (0, 7.3, -1.9), (0, 7.8, -2.2)]  # cuello en S
    for a, b in zip(pts, pts[1:]):
        p.branch("White", a, b, 0.22, 0.16, 7)
        p.add("White", sphere(0.2, 6, 4), T(*b))
    p.add("White", sphere(0.32, 8, 5), T(0, 7.95, -2.35) @ S(0.9, 0.9, 1.1))
    p.add("Red", sphere(0.3, 7, 4), T(0, 8.18, -2.35) @ S(1, 0.45, 1))
    p.branch("Black", (0, 7.9, -2.55), (0, 7.8, -3.7), 0.11, 0.025, 6)  # pico
    for s in (-1, 1):
        eye(p, s * 0.26, 8.0, -2.45, 0.06)


def fuji(p):
    """Monte Fuji de fondo: cono grande con laderas en dos tonos y la cima nevada."""
    p.add("StoneDark", lathe([(120, 0), (96, 40), (62, 100), (30, 160), (14, 190)], 18))
    p.add("Pink", lathe([(100, 30), (84, 52), (76, 46), (92, 26)], 18))
    p.add("White", lathe([(31.0, 158.5), (23.0, 175), (14.5, 190.0), (0.0, 196.0)], 18))


ANIMALS = ["Panda", "RedPanda", "Tiger", "Fox", "Tanuki", "Deer", "Crane"]
PIECES = {
    "Sakura": sakura, "SakuraB": sakura_b, "Maple": maple, "Pine": pine, "Bamboo": bamboo, "Torii": torii,
    "StoneLantern": stone_lantern, "Chochin": chochin, "Pagoda": pagoda, "Bridge": bridge, "Shrine": shrine,
    "Rocks": rocks, "Lotus": lotus, "Bonsai": bonsai, "Fence": fence, "Komainu": komainu,
    "Koinobori": koinobori, "TempleRoof": temple_roof, "Panda": panda, "RedPanda": red_panda, "Tiger": tiger, "Fox": fox, "Tanuki": tanuki,
    "Deer": deer, "Crane": crane, "Fuji": fuji,
}


# ---------- Pasar a Blender y exportar ----------

def to_blender(v):
    # Ejes del juego (X, Y arriba, Z atrás) -> Blender (Z arriba), de forma que el FBX (Y arriba, -Z al frente)
    # salga otra vez en ejes del juego.
    return (v[0], -v[2], v[1])


def material(role):
    mat = bpy.data.materials.get(role) or bpy.data.materials.new(role)
    mat.diffuse_color = ROLE_COLORS[role] + (1,)
    return mat


def make_object(name, role, verts, faces, offset):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender((x + offset[0], y + offset[1], z + offset[2])) for x, y, z in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material(role))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def marker(name, position):
    verts, faces = box(0.1, 0.1, 0.1)
    make_object(name, "Marker", verts, faces, position)


def render_row(path, center_x, width, angle=0.0):
    """Vista de una fila de piezas pequeñas centrada en center_x, de `width` studs de ancho."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = int(1600 * 0.38)
    scene.render.filepath = path
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = width
    cam.location = (center_x + 120 * math.sin(math.radians(angle)), 120 * math.cos(math.radians(angle)), width * 0.19 - 1)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180 - angle))
    scene.collection.objects.link(cam)
    scene.camera = cam
    bpy.ops.render.render(write_still=True)


def render_preview(path, names, scale):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    first, last = names
    count = last - first + 1
    scene.render.resolution_x = 360 * count
    scene.render.resolution_y = 700
    scene.render.filepath = path
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.55, 0.78, 0.95)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 40.0 * count * scale
    cam.location = (((first - 1) + (last - 1)) / 2 * 40.0, 120, 12 * scale * 2)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    scene.collection.objects.link(cam)
    scene.camera = cam
    bpy.ops.render.render(write_still=True)


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    marker("Axis_Origin", (-40, 0, 0))
    marker("Axis_Up", (-40, 2, 0))
    marker("Axis_Front", (-40, 0, -2))

    for index, (name, build) in enumerate(PIECES.items()):
        p = Piece()
        build(p)
        if name == "Fuji":
            offset = (900.0, 0, 0)
        elif name in ANIMALS:
            offset = (1200.0 + ANIMALS.index(name) * 14.0, 0, 0)  # los animales, en otra fila más junta
        else:
            offset = (index * 40.0, 0, 0)  # en fila, de 40 en 40 (solo para verlas juntas en Blender)
        marker("%s_Origin" % name, offset)
        for role, (verts, faces) in p.parts.items():
            make_object("%s_%s" % (name, role), role, verts, faces, offset)

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "mapa_japones.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "mapa_japones.fbx"),
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
    )
    render_preview(os.path.join(OUT_DIR, "mapa_japones1.png"), (1, 6), 1.0)
    render_preview(os.path.join(OUT_DIR, "mapa_japones2.png"), (7, 12), 0.9)
    render_preview(os.path.join(OUT_DIR, "mapa_japones3.png"), (16, 18), 1.0)
    render_row(os.path.join(OUT_DIR, "mapa_japones4.png"), 1200.0 + 3 * 14.0, 14.0 * 8)
    render_row(os.path.join(OUT_DIR, "mapa_japones5.png"), 1200.0 + 3 * 14.0, 14.0 * 8, 38.0)
    render_row(os.path.join(OUT_DIR, "mapa_japones6.png"), 40.0 * list(PIECES).index("Komainu"), 28.0, 25.0)
    render_row(os.path.join(OUT_DIR, "mapa_japones7.png"), 40.0 * list(PIECES).index("TempleRoof"), 75.0, 25.0)
    print("Exportadas", len(PIECES), "piezas")


main()
