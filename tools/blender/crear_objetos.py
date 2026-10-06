# Crea en Blender los modelos de los objetos de las parcelas (Config.Destructibles, por su posición en la lista)
# y los exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_objetos.py
# Deja objetos.blend y objetos.fbx en Documents\Roblox\modelos (y objetos1.png / objetos2.png, vistas de todos).
# En Studio: Archivo > Importar 3D con objetos.fbx y guardar el modelo importado (clic derecho > Guardar en archivo)
# como src/shared/ObjectMeshes.rbxm.
#
# Cada objeto son varios mallas "O<índice>_<Papel>", una por papel: el juego (shared/ObjectModel) les pone color y
# material (Body = color y material del objeto, Dark = su sombra, Trim = adornos claros, Gem = cristal del color del
# objeto, Glow = luz). "O<índice>_Origin" marca el centro de la caja del objeto (Config.Destructibles[i].size) y las
# marcas Axis_* dan la escala y los ejes de la importación. Medidas en studs, Y arriba. Cuanto más raro el objeto,
# más piezas, más grandes los adornos y más luz: los últimos flotan, giran y brillan.
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos")

ROLE_COLORS = {  # solo para verlo en Blender; en el juego manda ObjectModel
    "Body": (0.6, 0.6, 0.6, 1), "Dark": (0.2, 0.2, 0.25, 1), "Trim": (0.95, 0.78, 0.3, 1),
    "Gem": (0.5, 0.9, 1, 1), "Glow": (1, 0.85, 0.4, 1), "Marker": (1, 0, 1, 1),
}
# Color del cuerpo de cada objeto (el de Config.Destructibles), solo para la vista previa.
BODY = {
    1: (0.67, 0.49, 0.29), 2: (0.47, 0.29, 0.18), 3: (0.43, 0.43, 0.45), 4: (0.88, 0.86, 0.8), 5: (0.43, 0.86, 1),
    6: (1, 0.47, 0.16), 7: (0.18, 0.16, 0.24), 8: (0.9, 0.75, 0.27), 9: (0.78, 0.27, 0.12), 10: (0.24, 1, 0.55),
    11: (1, 0.94, 0.59), 12: (0.02, 0.02, 0.04), 13: (0.51, 0.2, 1), 14: (1, 0.24, 0.78), 15: (1, 1, 1),
    16: (1, 0.16, 0.24),
}


# ---------- Geometría ----------

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
    """Tronco de pirámide de base cuadrada: abajo w0 x d0, arriba w1 x d1, centrado en Y."""
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


def crystal(r, h, n=6, tip=0.28, base=0.0):
    """Cristal hexagonal de base plana (base en y=0) y punta arriba; tip = parte de la altura que es la punta."""
    return lathe([(r * 0.8, 0), (r, h * 0.12), (r, h * (1 - tip)), (0, h)], n)


def gem(r, h=None, n=6):
    """Bipirámide (gema tallada) a lo largo de Y."""
    h = h or r * 2
    return lathe([(0, -h / 2), (r, 0), (0, h / 2)], n)


def spike(r, h, n=6):
    return lathe([(r, 0), (r * 0.55, h * 0.5), (0, h)], n)


def torus(R_, r, n=24, m=6):
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


def sweep(path, r, m=6):
    """Tubo de radio r a lo largo de una curva cerrada en el plano XY (path = lista de (x, y))."""
    n = len(path)
    verts = []
    for i in range(n):
        x0, y0 = path[i - 1]
        x1, y1 = path[(i + 1) % n]
        tx, ty = x1 - x0, y1 - y0
        length = math.hypot(tx, ty)
        nx, ny = -ty / length, tx / length  # normal en el plano
        x, y = path[i]
        for j in range(m):
            b = 2 * math.pi * j / m
            verts.append((x + nx * r * math.cos(b), y + ny * r * math.cos(b), r * math.sin(b)))
    faces = []
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            faces.append((i * m + j, i2 * m + j, i2 * m + j2, i * m + j2))
    return verts, faces


def rock(radii, seed, n=9, rings=5, jitter=0.2):
    """Roca a facetas: esfera con los vértices movidos al azar (con semilla, siempre sale igual)."""
    rng = random.Random(seed)
    verts, faces = sphere(1, n, rings)
    out = []
    for x, y, z in verts:
        k = 1 + rng.uniform(-jitter, jitter) if abs(y) < 0.999 else 1
        out.append((x * k * radii[0], y * k * radii[1], z * k * radii[2]))
    return out, faces


class Obj:
    def __init__(self):
        self.parts = {}

    def add(self, role, shape, matrix=None):
        verts, faces = shape
        matrix = matrix or Matrix.Identity(4)
        mine = self.parts.setdefault(role, ([], []))
        base = len(mine[0])
        mine[0].extend(tuple(matrix @ Vector(v)) for v in verts)
        mine[1].extend(tuple(base + i for i in f) for f in faces)

    def ring_of(self, role, shape, count, radius, y, tilt=0.0, spin=0.0, scale=None):
        """`count` copias alrededor del eje Y, inclinadas hacia fuera `tilt` grados."""
        for i in range(count):
            a = 2 * math.pi * i / count + math.radians(spin)
            m = T(radius * math.cos(a), y, radius * math.sin(a)) @ R("Y", -math.degrees(a)) @ R("Z", -tilt)
            self.add(role, shape, m @ scale if scale is not None else m)


# ---------- Los 16 objetos, de menos a más raro (ejes del juego, centro de la caja en el origen) ----------

def caja(o):  # 3 x 3 x 3
    o.add("Body", box(2.8, 2.8, 2.8))
    for sx in (-1, 1):
        for sz in (-1, 1):
            o.add("Dark", box(0.4, 3, 0.4), T(sx * 1.3, 0, sz * 1.3))
    for y in (-1.4, 1.4):
        for s in (-1, 1):
            o.add("Dark", box(2.8, 0.22, 0.3), T(0, y, s * 1.35))
            o.add("Dark", box(0.3, 0.22, 2.8), T(s * 1.35, y, 0))
    for s in (-1, 1):  # tablón en cruz en las caras
        o.add("Trim", box(0.22, 2.9, 0.12), T(0, 0, s * 1.45) @ R("Z", 45))
        o.add("Trim", box(0.12, 2.9, 0.22), T(s * 1.45, 0, 0) @ R("X", 45))


def barril(o):  # 3 x 4.5 x 3
    def radius(y):
        return 1.5 - 0.3 * (y / 2.25) ** 2
    ys = [-2.25 + 0.5625 * i for i in range(9)]
    o.add("Body", lathe([(radius(y), y) for y in ys], 12))
    for y in (-1.6, -0.55, 0.55, 1.6):
        r = radius(y) + 0.08
        o.add("Dark", lathe([(r - 0.05, y - 0.2), (r + 0.06, y - 0.15), (r + 0.06, y + 0.15), (r - 0.05, y + 0.2)], 12))
    o.add("Trim", lathe([(1.05, 2.2), (1.05, 2.32), (0, 2.32)], 12))


def roca(o):  # 5 x 4 x 5
    o.add("Body", rock((2.4, 1.8, 2.4), 3), T(0, -0.15, 0))
    o.add("Body", rock((1.2, 0.9, 1.1), 4), T(1.2, 0.9, -0.7))
    o.add("Dark", rock((1.0, 0.45, 1.0), 5), T(-1.4, -1.6, 1.4))
    o.add("Dark", rock((1.6, 0.3, 1.4), 6), T(0.2, 1.55, 0.3))  # musgo arriba
    o.add("Trim", crystal(0.28, 1.0, 5), T(-0.6, 1.4, 1.0) @ R("X", 25))  # una veta de gema asoma


def pilar(o):  # 4 x 12 x 4
    o.add("Body", box(4, 0.8, 4), T(0, -5.6, 0))
    o.add("Body", box(3.2, 0.5, 3.2), T(0, -5.0, 0))
    o.add("Body", lathe([(1.35, -4.75), (1.2, -3.0), (1.2, 3.0), (1.35, 4.6)], 10))
    for a in range(10):  # estrías
        ang = 2 * math.pi * a / 10
        o.add("Dark", box(0.14, 8.4, 0.14), T(1.24 * math.cos(ang), 0, 1.24 * math.sin(ang)) @ R("Y", -math.degrees(ang)))
    o.add("Body", box(3.2, 0.5, 3.2), T(0, 4.85, 0))
    o.add("Body", box(4, 0.8, 4), T(0, 5.5, 0))
    for y in (-4.55, 4.5):
        o.add("Trim", lathe([(1.4, y - 0.12), (1.5, y - 0.06), (1.5, y + 0.06), (1.4, y + 0.12)], 10))
    o.add("Trim", box(1.6, 0.12, 1.6), T(0, 5.95, 0))


def cristal(o):  # 7 x 11 x 7
    o.add("Body", rock((3.2, 0.9, 3.2), 7), T(0, -5.0, 0))
    o.add("Gem", crystal(1.6, 10.4, 6, 0.3), T(0, -5.4, 0))
    o.add("Glow", crystal(0.55, 7.0, 6, 0.3), T(0, -4.6, 0))
    for i, (h, r) in enumerate([(5.5, 1.0), (4.2, 0.85), (6.2, 0.9), (3.6, 0.75), (4.8, 0.8)]):
        a = 2 * math.pi * i / 5 + 0.4
        m = T(2.3 * math.cos(a), -5.2, 2.3 * math.sin(a)) @ R("Y", -math.degrees(a)) @ R("Z", -22)
        o.add("Gem", crystal(r, h, 6, 0.3), m)
    o.add("Trim", gem(0.3, 0.9), T(2.6, -4.0, -2.4))


def roca_armas(o):  # 6 x 6 x 6
    o.add("Body", rock((2.9, 2.4, 2.9), 8), T(0, -0.7, 0))
    o.add("Dark", rock((1.2, 0.9, 1.1), 9), T(2.3, -2.4, 1.2))
    o.add("Dark", rock((1.1, 0.8, 1.2), 10), T(-2.2, -2.4, -1.4))
    for i, (x, z, tilt, spin) in enumerate([(0, 0, 0, 0), (1.1, 0.6, 18, 40), (-1.0, -0.5, -20, 200), (0.4, -1.3, 14, 120)]):
        m = T(x, 1.3 + (0.2 if i == 0 else -0.1), z) @ R("Y", spin) @ R("Z", tilt)
        o.add("Trim", box(0.3, 0.2, 1.6), m @ T(0, 1.0, 0))  # guarda
        o.add("Dark", box(0.22, 1.15, 0.22), m @ T(0, 1.55, 0))  # empuñadura
        o.add("Glow", sphere(0.2, 8, 4), m @ T(0, 2.25, 0))  # pomo luminoso
        o.add("Trim", box(0.12, 1.8, 0.5), m @ T(0, 0.1, 0))  # un poco de hoja a la vista
    for a in range(6):  # grietas de luz en la piedra
        ang = 2 * math.pi * a / 6
        o.add("Glow", box(0.14, 1.0, 0.3), T(2.55 * math.cos(ang), -0.9, 2.55 * math.sin(ang)) @ R("Y", -math.degrees(ang)) @ R("Z", 10))


def monolito(o):  # 11 x 20 x 11
    o.add("Dark", box(11, 0.8, 11), T(0, -9.6, 0))
    o.add("Body", box(9, 0.8, 9), T(0, -8.8, 0))
    o.add("Dark", box(7, 0.8, 7), T(0, -8.0, 0))
    o.add("Body", frustum(5.0, 3.0, 3.6, 2.2, 16.4), T(0, 0.4, 0))
    o.add("Dark", frustum(3.6, 2.2, 0.01, 0.01, 1.4), T(0, 9.3, 0) @ S(1, 1, 1))
    for s in (-1, 1):  # runas en las dos caras anchas
        z = 1.5 * 0.9 + 0.12
        for y, h in ((-4.5, 3.0), (0.5, 4.0), (5.0, 2.4)):
            o.add("Glow", box(0.22, h, 0.16), T(0, y, s * (1.2 + 0.18 * (1 - (y + 8) / 16.4)) ))
        o.add("Glow", box(1.6, 0.2, 0.16), T(0, 2.6, s * 1.15))
        o.add("Glow", box(1.0, 0.2, 0.16), T(0, -2.2, s * 1.35))
    for i in range(4):  # esquirlas flotando
        a = math.pi / 2 * i + math.pi / 4
        o.add("Trim", gem(0.5, 1.8), T(4.4 * math.cos(a), 4.0 + 1.4 * (i % 2), 4.4 * math.sin(a)) @ R("Z", 12))


def obelisco(o):  # 6 x 22 x 6
    o.add("Dark", box(6, 0.8, 6), T(0, -10.6, 0))
    o.add("Trim", box(4.8, 0.8, 4.8), T(0, -9.8, 0))
    o.add("Body", frustum(3.6, 3.6, 2.0, 2.0, 18.0), T(0, -0.4, 0))
    for y in (-6.5, -1.5, 3.5):
        w = 3.6 - 1.6 * (y + 9.4) / 18.0 + 0.2
        o.add("Trim", box(w, 0.4, w), T(0, y, 0))
    for y in (-4.0, 1.0):
        for a in range(4):
            ang = math.pi / 2 * a
            w = 3.6 - 1.6 * (y + 9.4) / 18.0
            o.add("Glow", box(0.22, 1.1, 0.1), T(math.cos(ang) * (w / 2 + 0.03), y, math.sin(ang) * (w / 2 + 0.03)) @ R("Y", -math.degrees(ang) + 90))
    o.add("Trim", lathe([(1.45, 8.6), (0, 10.5)], 4), R("Y", 45))
    o.add("Glow", gem(0.35, 1.0), T(0, 10.9, 0))


def meteorito(o):  # 12 x 10 x 12
    o.add("Body", rock((5.8, 4.4, 5.8), 11, 11, 7, 0.16), T(0, -0.5, 0))
    o.add("Dark", rock((2.6, 1.2, 2.6), 12), T(0.4, 3.6, -0.2))  # costra quemada
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.6
        o.add("Dark", rock((1.6, 1.0, 1.6), 13 + i), T(5.0 * math.cos(a), -4.2, 5.0 * math.sin(a)))
    rng = random.Random(21)
    for i in range(9):  # lava entre las grietas
        a, b = rng.uniform(0, 2 * math.pi), rng.uniform(-0.2, 0.9)
        r = 4.6
        o.add("Glow", rock((rng.uniform(0.7, 1.3),) * 3, 30 + i, 7, 4, 0.2),
              T(r * math.cos(a) * math.cos(b) * 1.1, 0.4 + r * math.sin(b) * 0.8, r * math.sin(a) * math.cos(b) * 1.1))
    o.add("Glow", rock((2.2, 0.5, 2.2), 40, 9, 4), T(0.4, 4.1, -0.2))  # cráter encendido


def nucleo(o):  # 9 x 9 x 9
    o.add("Glow", sphere(1.7, 12, 8))
    o.add("Gem", sphere(2.8, 10, 6))
    for ax, rot in ((0, R("X", 90)), (1, Matrix.Identity(4)), (2, R("Z", 90))):
        o.add("Trim", torus(3.9, 0.2, 28, 6), rot)
    for s in (-1, 1):  # seis soportes sobre los ejes
        o.add("Body", box(0.6, 2.2, 2.2), T(s * 4.0, 0, 0))
        o.add("Body", box(2.2, 0.6, 2.2), T(0, s * 4.0, 0))
        o.add("Body", box(2.2, 2.2, 0.6), T(0, 0, s * 4.0))
    for s in (-1, 1):
        for t in (-1, 1):
            o.add("Dark", box(0.18, 0.18, 5.2), T(s * 3.0, t * 3.0, 0))
            o.add("Dark", box(5.2, 0.18, 0.18), T(0, s * 3.0, t * 3.0))
            o.add("Dark", box(0.18, 5.2, 0.18), T(s * 3.0, 0, t * 3.0))


def estrella(o):  # 12 x 12 x 12
    o.add("Glow", sphere(2.3, 12, 8))
    o.add("Gem", sphere(3.2, 8, 5))
    for rot in (Matrix.Identity(4), R("Z", 90), R("Z", -90), R("Z", 180), R("X", 90), R("X", -90)):
        o.add("Body", spike(1.2, 5.6), rot @ T(0, 0.8, 0))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                d = Vector((sx, sy, sz)).normalized()
                m = d.to_track_quat("Y", "Z").to_matrix().to_4x4() @ T(0, 2.4, 0)
                o.add("Trim", spike(0.8, 3.4), m)
    o.add("Trim", torus(4.8, 0.14, 40, 5), R("X", 18))
    o.add("Trim", torus(5.4, 0.12, 40, 5), R("Z", 72))
    o.add("Dark", torus(4.1, 0.1, 36, 4), R("X", 90))


def agujero(o):  # 13 x 13 x 13
    o.add("Body", sphere(3.1, 14, 10))
    o.add("Dark", sphere(3.35, 12, 8) if False else torus(3.3, 0.09, 36, 4), R("X", 90))  # borde del horizonte
    o.add("Glow", torus(5.0, 0.95, 40, 8), S(1, 0.16, 1))
    o.add("Trim", torus(4.0, 0.34, 36, 6), S(1, 0.2, 1))
    o.add("Glow", torus(6.0, 0.22, 44, 5), S(1, 0.3, 1) @ R("X", 8))
    o.add("Gem", torus(6.1, 0.2, 44, 5), R("X", 28) @ R("Z", 12))
    o.add("Dark", torus(5.2, 0.3, 40, 5), S(1, 0.1, 1))
    for i in range(8):  # materia cayendo en espiral
        a = 2 * math.pi * i / 8
        o.add("Trim", gem(0.28, 0.9), T(6.2 * math.cos(a), 0.2 * (i % 3 - 1), 6.2 * math.sin(a)))


def fragmento(o):  # 8 x 24 x 8
    o.add("Body", lathe([(0, -11.2), (2.1, -6.0), (2.5, -1.0), (1.9, 6.0), (0, 11.6)], 5))
    o.add("Glow", lathe([(0, -9.0), (0.75, -4.5), (0.9, 0.5), (0.6, 6.0), (0, 9.8)], 5))
    for i in range(5):
        a = 2 * math.pi * i / 5
        o.add("Dark", rock((1.5, 0.9, 1.3), 50 + i), T(3.2 * math.cos(a), -11.2, 3.2 * math.sin(a)))
    for i, (h, y) in enumerate([(2.6, -6.5), (3.4, -2.0), (2.2, 2.5), (3.0, 6.5), (2.0, 9.5)]):
        a = 2.4 * i
        o.add("Gem", gem(0.55, h), T(3.4 * math.cos(a), y, 3.4 * math.sin(a)) @ R("Z", 14 * (i - 2)))
    o.add("Trim", torus(3.7, 0.15, 30, 5), T(0, -3, 0) @ R("X", 14))
    o.add("Trim", torus(3.2, 0.12, 30, 5), T(0, 4, 0) @ R("X", -16))
    o.add("Dark", torus(2.5, 0.2, 24, 5), T(0, -10.6, 0) @ S(1, 0.4, 1))


def singularidad(o):  # 10 x 10 x 10
    o.add("Glow", sphere(1.4, 10, 6))
    o.add("Gem", sphere(2.9, 9, 6))
    o.add("Trim", torus(4.4, 0.16, 36, 5), R("X", 25))
    o.add("Gem", torus(4.0, 0.14, 36, 5), R("Z", 60) @ R("X", 10))
    o.add("Dark", torus(4.7, 0.12, 36, 5), R("X", -55) @ R("Z", 30))
    for i in range(16):  # espiral de esquirlas
        t = i / 15
        a = 5.2 * t * math.pi
        r = 4.6 - 2.0 * t
        o.add("Body", gem(0.42 + 0.2 * (1 - t), 1.4), T(r * math.cos(a), -4.0 + 8.0 * t, r * math.sin(a)) @ R("Z", 25) @ R("Y", math.degrees(a)))
    for a in range(4):
        ang = math.pi / 2 * a
        o.add("Trim", spike(0.5, 1.6), T(1.8 * math.cos(ang), 0, 1.8 * math.sin(ang)) @ R("Y", -math.degrees(ang)) @ R("Z", -90))


def origen(o):  # 14 x 18 x 14
    o.add("Body", lathe([(5.9, -9.0), (5.9, -8.5), (4.4, -8.0), (4.0, -7.4), (0, -7.4)], 18))
    o.add("Trim", torus(5.6, 0.18, 36, 5), T(0, -8.5, 0))
    o.ring_of("Body", spike(0.9, 5.6), 8, 4.6, -7.4, 14)
    o.ring_of("Trim", spike(0.45, 3.0), 8, 3.6, -7.4, 8, spin=22.5)
    o.add("Gem", gem(2.6, 11.0, 8), T(0, 0.6, 0))
    o.add("Glow", gem(1.2, 6.0, 8), T(0, 0.6, 0))
    o.add("Trim", torus(4.2, 0.2, 40, 6), T(0, 0.6, 0) @ R("X", 20))
    o.add("Trim", torus(5.6, 0.2, 44, 6), T(0, 1.4, 0) @ R("Z", -26))
    o.add("Glow", torus(6.6, 0.12, 48, 5), T(0, 0.8, 0) @ R("X", -12) @ R("Y", 40))
    o.ring_of("Body", gem(0.5, 1.6), 6, 5.0, 5.4, 0)
    o.ring_of("Glow", gem(0.3, 1.0), 6, 3.0, 8.0, 0, spin=30)
    o.add("Trim", gem(0.7, 2.2), T(0, 7.2, 0))


def infinito(o):  # 14 x 26 x 14
    o.add("Dark", lathe([(6.8, -13.0), (6.8, -12.5), (4.0, -11.8), (0, -11.8)], 16))
    o.ring_of("Body", spike(1.0, 6.5), 8, 4.4, -12.4, 16)
    o.ring_of("Dark", spike(0.6, 4.0), 8, 5.6, -12.4, 26, spin=22.5)
    o.add("Gem", lathe([(0, -12.0), (1.9, -9.0), (2.0, 8.0), (1.5, 10.5), (0, 12.8)], 6))
    o.add("Glow", lathe([(0, -9.0), (0.7, -6.0), (0.7, 7.0), (0, 10.0)], 6))
    path = []
    for i in range(72):  # lemniscata: el símbolo ∞ vertical
        t = 2 * math.pi * i / 72
        d = 1 + math.sin(t) ** 2
        path.append((6.2 * math.cos(t) / d, 0.4 + 6.2 * math.sin(t) * math.cos(t) / d * 2.4))
    o.add("Glow", sweep(path, 0.55, 6), R("Y", 35))
    o.add("Trim", sweep(path, 0.2, 5), S(1.07, 1.07, 1) @ R("Y", 35))
    for y, r in ((8.6, 3.6), (-7.0, 4.6)):
        o.add("Trim", torus(r, 0.2, 36, 5), T(0, y, 0))
    o.add("Glow", torus(5.4, 0.12, 36, 4), T(0, 4.5, 0) @ R("X", 15))
    o.ring_of("Trim", spike(0.5, 2.6), 6, 2.6, 11.0, 12)
    o.ring_of("Body", gem(0.35, 1.4), 8, 6.0, 0.8, 0, spin=10)


BUILDERS = [caja, barril, roca, pilar, cristal, roca_armas, monolito, obelisco, meteorito, nucleo, estrella, agujero,
            fragmento, singularidad, origen, infinito]


# ---------- Pasar a Blender y exportar ----------

def to_blender(v):
    # Ejes del juego (X, Y arriba, Z atrás) -> Blender (Z arriba), de forma que el FBX (Y arriba, -Z al frente)
    # salga otra vez en ejes del juego.
    return (v[0], -v[2], v[1])


def material(index, role):
    name = "%d_%s" % (index, role)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    color = ROLE_COLORS[role]
    if role == "Body":
        color = BODY[index] + (1,)
    elif role == "Dark":
        color = tuple(c * 0.45 for c in BODY[index]) + (1,)
    elif role == "Gem":
        color = BODY[index] + (1,)
    mat.diffuse_color = color
    return mat


def make_object(name, index, role, verts, faces, offset):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender((x + offset[0], y + offset[1], z + offset[2])) for x, y, z in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material(index, role))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def marker(name, position):
    verts, faces = box(0.1, 0.1, 0.1)
    make_object(name, 0, "Marker", verts, faces, position)


def render_preview(path, first, last):
    """Vista de los objetos first..last (desde 1) en una imagen."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    count = last - first + 1
    scene.render.resolution_x = 300 * count
    scene.render.resolution_y = 700
    scene.render.filepath = path
    world = bpy.data.worlds.new("w") if not scene.world else scene.world
    scene.world = world
    world.color = (0.12, 0.13, 0.16)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 20.0 * count
    cam.location = (((first - 1) + (last - 1)) / 2 * 20.0, -80, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
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

    for index, build in enumerate(BUILDERS, start=1):
        o = Obj()
        build(o)
        offset = ((index - 1) * 20.0, 0, 0)  # en fila, de 20 en 20 (solo para verlos juntos en Blender)
        marker("O%02d_Origin" % index, offset)
        for role, (verts, faces) in o.parts.items():
            make_object("O%02d_%s" % (index, role), index, role, verts, faces, offset)

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "objetos.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "objetos.fbx"),
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
    )
    render_preview(os.path.join(OUT_DIR, "objetos1.png"), 1, 8)
    render_preview(os.path.join(OUT_DIR, "objetos2.png"), 9, 16)
    print("Exportados", len(BUILDERS), "objetos y", len(bpy.data.objects), "mallas a", OUT_DIR)


main()
