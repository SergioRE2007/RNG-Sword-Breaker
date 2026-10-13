# Crea en Blender las piezas del mapa del bosque japonés (cerezos, arces, pinos, bambú, torii, linternas, pagoda,
# puente, santuario, rocas, loto, carpas y farolillos) y las exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_mapa_japones.py
# Deja mapa_japones.blend, mapa_japones.fbx y mapa_japones1-3.png en Documents\Roblox\modelos. En Studio: Archivo >
# Importar 3D con mapa_japones.fbx y guardar el modelo importado (clic derecho > Guardar en archivo) como
# src/shared/MapMeshes.rbxm (y borrar el modelo de Workspace: lo trae Rojo).
# Para actualizar algunas piezas: -- --only Torii Bridge Temple
# y pasar esa importación a src/shared/MapMeshesPatch.rbxmx (las piezas que ya tenga y no se toquen se quedan).
# PropModel sustituye solo esas piezas. Con --only cada pieza deja además su vista de prueba (Torii1.png...).
#
# Cada pieza son varias mallas "<Pieza>_<Papel>", una por papel: el juego (shared/PropModel) les pone color y
# material según el papel (Wood, Red, Pink, PinkLight, Orange, Leaf, LeafDark, Stone, StoneDark, Gold, Paper,
# Roof, White, Black, Water). "<Pieza>_Origin" marca el centro del suelo de la pieza y Axis_* dan la escala y los
# ejes de la importación. Medidas en studs, Y arriba, -Z al frente. Las piezas ya vienen a su tamaño real: el
# juego solo las gira y las varía un poco de tamaño. Una pieza grande se parte en varias con `p.group` (el templo
# sale como TempleA, TempleB y TempleC, una por piso, con el mismo origen): cada malla, por debajo de 9000 triángulos.
import math
import os
import random
import argparse

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
    "Sack": (0.8, 0.6, 0.36), "SackDark": (0.56, 0.38, 0.22), "Rope": (0.42, 0.26, 0.15),
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
        self.group = ""  # las piezas grandes se parten en varias ("TempleA", "TempleB"...) que comparten origen

    def add(self, role, shape, matrix=None):
        verts, faces = shape
        matrix = matrix or Matrix.Identity(4)
        mine = self.parts.setdefault((self.group, role), ([], []))
        base = len(mine[0])
        mine[0].extend(tuple(matrix @ Vector(v)) for v in verts)
        mine[1].extend(tuple(base + i for i in f) for f in faces)

    def branch(self, role, a, b, r0, r1, n=7):
        m, shape = limb(a, b, r0, r1, n)
        self.add(role, shape, m)


# ---------- Vigas curvas y tejados ----------

def rect(width, height):
    """Sección rectangular para `sweep`, apoyada en el camino."""
    return [(-width / 2, 0), (width / 2, 0), (width / 2, height), (-width / 2, height)]


def ridge(width, height):
    """Sección triangular para `sweep`: una fila de tejas vista de frente."""
    return [(-width / 2, 0), (width / 2, 0), (0, height)]


def circle(radius, n=7):
    return [(radius * math.cos(2 * math.pi * j / n), radius * math.sin(2 * math.pi * j / n)) for j in range(n)]


def sweep(points, section, scales=None):
    """Sólido cerrado que arrastra `section` ([(lado, arriba)]) por un camino de puntos. `scales` la agranda o la
    encoge en cada punto."""
    pts = [Vector(q) for q in points]
    k = len(section)
    verts = []
    for i, q in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = Vector((0, 1, 0)).cross(t)
        side = side.normalized() if side.length > 1e-6 else Vector((1, 0, 0))
        up = t.cross(side).normalized()
        f = scales[i] if scales else 1
        verts += [tuple(q + side * (a * f) + up * (b * f)) for a, b in section]
    faces = [tuple(reversed(range(k))), tuple(k * (len(pts) - 1) + j for j in range(k))]
    for i in range(len(pts) - 1):
        for j in range(k):
            j2 = (j + 1) % k
            faces.append((k * i + j, k * i + j2, k * (i + 1) + j2, k * (i + 1) + j))
    return verts, faces


def frame(outer, inner, height):
    """Marco cuadrado tumbado (un anillo de vigas de una sola pieza), con la base en y=0."""
    verts = [(s * a, y, s * b) for y in (0, height) for s in (outer, inner) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces += [(i, j, 8 + j, 8 + i), (4 + j, 4 + i, 12 + i, 12 + j), (j, i, 4 + i, 4 + j), (8 + i, 8 + j, 12 + j, 12 + i)]
    return verts, faces


def giboshi(size=1.0):
    """Remate de poste en forma de cebolla."""
    return lathe([(0.34 * size, 0), (0.34 * size, 0.16 * size), (0.2 * size, 0.3 * size), (0.42 * size, 0.56 * size),
                  (0.46 * size, 0.82 * size), (0.3 * size, 1.1 * size), (0.09 * size, 1.32 * size), (0, 1.42 * size)], 8)


class HipRoof:
    """Tejado a cuatro aguas de planta cuadrada: tendido en el alero y empinado arriba, con las esquinas levantadas y
    algo salidas. `half` y `top` son la media anchura en el alero y arriba; `y0`, la altura del alero en el centro de
    cada lado. Las cuentas son las del lado de -Z; los otros tres salen girándolo."""

    def __init__(self, y0, half, top, rise, lift, flare=0.05, thick=0.6):
        self.y0, self.half, self.top, self.rise, self.lift, self.flare, self.thick = y0, half, top, rise, lift, flare, thick

    def at(self, u, v, drop=0.0):
        """Punto del tejado: u de -1 a 1 a lo largo del alero, v de 0 (alero) a 1 (arriba), `drop` por debajo."""
        w = self.half + (self.top - self.half) * v
        k = abs(u) ** 3 * (1 - v) ** 2
        w *= 1 + self.flare * k
        return Vector((u * w, self.y0 + self.rise * (0.3 * v + 0.7 * v ** 2.2) + self.lift * k - drop, -w))

    def over(self, x, v, drop=0.0):
        """Punto del tejado sobre la coordenada x del alero (para lo que sube recto, como las tejas)."""
        w = self.half + (self.top - self.half) * v
        return self.at(max(-1.0, min(1.0, x / w)), v, drop)

    def slab(self, n, m, v0=0.0, v1=1.0, drop=0.0, thick=None):
        """Losa cerrada que sigue el tejado entre v0 y v1, con su cara de arriba `drop` por debajo de él."""
        thick = self.thick if thick is None else thick
        verts, faces = [], []
        for side in range(4):
            rot = R("Y", 90 * side)
            base = len(verts)
            for layer in (0, 1):
                for i in range(n + 1):
                    for j in range(m + 1):
                        verts.append(tuple(rot @ self.at(-1 + 2 * i / n, v0 + (v1 - v0) * j / m, drop + layer * thick)))

            def index(layer, i, j):
                return base + layer * (n + 1) * (m + 1) + i * (m + 1) + j

            for i in range(n):
                for j in range(m):
                    faces.append((index(0, i, j), index(0, i + 1, j), index(0, i + 1, j + 1), index(0, i, j + 1)))
                    faces.append((index(1, i, j + 1), index(1, i + 1, j + 1), index(1, i + 1, j), index(1, i, j)))
                for j in (0, m):
                    faces.append((index(0, i, j), index(0, i + 1, j), index(1, i + 1, j), index(1, i, j)))
        return verts, faces

    def rows(self, spacing, section, v0=0.0, v1=1.0, steps=5, drop=0.0, margin=0.9):
        """Vigas que suben rectas desde el alero, una cada `spacing`; las de las esquinas acaban al llegar a la
        limatesa. Devuelve una lista de formas."""
        count = max(1, round(2 * self.half / spacing))
        out = []
        for side in range(4):
            rot = R("Y", 90 * side)
            for c in range(count):
                x = (c + 0.5 - count / 2) * 2 * self.half / count
                reach = min(v1, (self.half - abs(x) - margin) / (self.half - self.top))
                if reach < v0 + 0.06:
                    continue
                out.append(sweep([rot @ self.over(x, v0 + (reach - v0) * s / steps, drop) for s in range(steps + 1)], section))
        return out


# ---------- Árboles ----------

def trunk(p, points, radii, n=9):
    """Tronco continuo: los tramos comparten sus anillos, sin tapas ni cortes intermedios."""
    verts = [(x + r * math.cos(2 * math.pi * j / n), y, z + r * math.sin(2 * math.pi * j / n))
             for (x, y, z), r in zip(points, radii) for j in range(n)]
    faces = [tuple(reversed(range(n))), tuple((len(points) - 1) * n + j for j in range(n))]
    for i in range(len(points) - 1):
        for j in range(n):
            k = (j + 1) % n
            faces.append((i * n + j, i * n + k, (i + 1) * n + k, (i + 1) * n + j))
    p.add("Wood", (verts, faces))

def blossom_tree(p, seed, light="PinkLight", main="Pink", height=17.0):
    """Cerezo: tronco torcido, ramas largas y copas redondas de flor rosa y rosa claro."""
    rng = random.Random(seed)
    pts = [(0, 0, 0)]
    x = z = 0.0
    for i in range(1, 5):
        x += rng.uniform(-0.9, 0.9)
        z += rng.uniform(-0.9, 0.9)
        pts.append((x, height * 0.3 * i / 2.2 * 0.5 + (i * height * 0.12), z))
    trunk(p, pts, [1.45 - 0.28 * i for i in range(5)])
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
    trunk(p, pts, [1.2 - 0.25 * i for i in range(5)])
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
    """Torii bermellón de estilo myōjin, de 20 de ancho: columnas algo inclinadas hacia dentro sobre basas de piedra,
    travesaño (nuki) que las atraviesa con sus cuñas, tablilla dorada en el centro y dintel doble que se curva hacia
    arriba en las puntas (shimaki rojo y kasagi negro, más ancho por arriba)."""
    def curve(x):
        return 1.7 * (abs(x) / 10.3) ** 2.4

    def lintel(length, y, section, slant=0.0, n=16):
        """Viga a lo largo de X que sigue la curva; `slant` saca la parte de arriba en las puntas (corte inclinado)."""
        k = len(section)
        verts = []
        for i in range(n + 1):
            x = -length + 2 * length * i / n
            tip = slant * (abs(x) / length) ** 8 * (1 if x > 0 else -1)
            verts += [(x + tip * b, y + curve(x) + b, a) for a, b in section]
        faces = [tuple(reversed(range(k))), tuple(k * n + j for j in range(k))]
        for i in range(n):
            for j in range(k):
                j2 = (j + 1) % k
                faces.append((k * i + j, k * i + j2, k * (i + 1) + j2, k * (i + 1) + j))
        return verts, faces

    for s in (-1, 1):
        p.add("StoneDark", lathe([(1.95, 0), (1.95, 0.3), (1.6, 0.85), (1.25, 0.95)], 12), T(s * 6.55, 0, 0))
        p.branch("Red", (s * 6.55, 0.9, 0), (s * 6.25, 14.1, 0), 0.98, 0.84, 12)
        p.branch("Black", (s * 6.55, 0.9, 0), (s * 6.515, 2.4, 0), 1.14, 1.1, 12)  # nemaki
        p.add("Black", cyl(1.2, 0.36, 12, 1.05), T(s * 6.25, 13.95, 0))  # daiwa
        for side in (-1, 1):  # cuñas del nuki
            p.add("Black", box(0.5, 0.42, 1.4), T(s * 6.35 + side * 1.1, 10.46, 0))
        p.add("Gold", box(0.16, 0.86, 0.72), T(s * 9.05, 9.7, 0))
    p.add("Red", box(18.0, 1.1, 0.95), T(0, 9.7, 0))  # nuki
    p.add("Red", box(1.0, 3.6, 0.85), T(0, 12.0, 0))  # gakuzuka
    p.add("Black", box(2.8, 3.4, 1.3), T(0, 12.0, 0))  # tablilla, con una cara dorada a cada lado
    p.add("Gold", box(2.2, 2.8, 1.36), T(0, 12.0, 0))
    p.add("Red", lintel(9.5, 13.75, rect(1.5, 0.95)))  # shimaki
    p.add("Black", lintel(10.3, 14.7, [(-0.85, 0), (0.85, 0), (1.3, 0.85), (0, 1.3), (-1.3, 0.85)], 0.55))  # kasagi


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
    """Cinco pisos encajados en sus tejados, con aleros continuos y estructura de laca roja."""
    p.add("StoneDark", box(17, 1.2, 17), T(0, 0.6, 0))
    p.add("Stone", box(15, 0.8, 15), T(0, 1.6, 0))
    y = 2.0
    width = 11.0
    for tier in range(5):
        h = 4.6 - tier * 0.35
        p.add("White", box(width, h, width), T(0, y + h / 2, 0))
        for s in (-1, 1):
            for t in (-1, 1):
                p.add("Red", box(0.7, h + 0.2, 0.7), T(s * (width / 2 - 0.15), y + h / 2, t * (width / 2 - 0.15)))
        for level in (y + 0.12, y + h - 0.12):
            p.add("Red", box(width + 0.2, 0.28, width + 0.2), T(0, level, 0))
        p.add("Red", box(width * 0.28, h * 0.65, 0.2), T(0, y + h * 0.4, -width / 2 - 0.1))  # puerta
        p.add("Gold", box(width * 0.5, 0.18, 0.2), T(0, y + h * 0.82, -width / 2 - 0.12))
        y += h
        eave = width + 5.2 - tier * 0.4
        next_width = width - 1.35
        # La coronación sostiene el piso siguiente; antes era más estrecha y dejaba paredes voladas.
        top_width = max(1.5, next_width + 0.35) if tier < 4 else 1.5
        p.add("Roof", frustum(eave, eave, top_width, top_width, 2.3), T(0, y + 1.05, 0))
        p.add("Red", box(eave, 0.35, eave), T(0, y + 0.1, 0))
        # Remate continuo, sin las puntas separadas que parecían trozos cortados del tejado.
        p.add("Roof", box(eave + 0.16, 0.22, eave + 0.16), T(0, y + 0.28, 0))
        y += 2.1
        width -= 1.35
    p.add("Gold", cyl(0.35, 7.0, 8, 0.15), T(0, y - 0.4, 0))
    for k in range(5):
        p.add("Gold", torus(0.9 - k * 0.12, 0.14, 12, 4), T(0, y + 0.8 + k * 1.1, 0))


def bridge(p):
    """Puente de arco de 23 de largo: la cubierta nace a ras de suelo en los dos extremos (sin escalón ni estribo de
    piedra), barandilla roja con postes rematados en dorado y dos pilas de madera en el agua."""
    n = 24
    half, height = 11.5, 3.3

    def point(t, lift=0.0):
        return Vector((-half + 2 * half * t, height * math.sin(math.pi * t) + lift, 0))

    # Una sola cubierta cerrada, sin caras internas duplicadas en los bordes de los tablones.
    verts = [(v.x, v.y + dy, z) for v in (point(i / n) for i in range(n + 1))
             for dy, z in ((-0.45, -3.1), (-0.45, 3.1), (0.08, 3.1), (0.08, -3.1))]
    faces = [(3, 2, 1, 0), tuple(4 * n + j for j in range(4))]
    for i in range(n):
        for j in range(4):
            k = (j + 1) % 4
            faces.append((4 * i + j, 4 * i + k, 4 * (i + 1) + k, 4 * (i + 1) + j))
    p.add("Wood", (verts, faces))
    for s in (-1, 1):
        # Largueros curvos bajo los bordes de la cubierta y los dos pasamanos.
        p.add("Red", sweep([point(i / n, -1.0) + Vector((0, 0, s * 2.8)) for i in range(n + 1)], rect(0.5, 0.62)))
        p.add("Red", sweep([point(i / n, 2.3) + Vector((0, 0, s * 3.0)) for i in range(n + 1)], rect(0.42, 0.4)))
        p.add("Red", sweep([point(i / n, 1.15) + Vector((0, 0, s * 3.0)) for i in range(n + 1)], rect(0.24, 0.24)))
    for i in range(9):
        a = point(i / 8)
        for s in (-1, 1):
            if i in (0, 8):  # postes de entrada, más gruesos y con remate dorado
                p.add("Red", box(0.8, 3.3, 0.8), T(a.x, a.y + 1.4, s * 3.0))
                p.add("Black", box(1.0, 0.2, 1.0), T(a.x, a.y + 3.1, s * 3.0))
                p.add("Gold", giboshi(1.0), T(a.x, a.y + 3.2, s * 3.0))
            else:
                p.add("Red", box(0.42, 2.9, 0.42), T(a.x, a.y + 1.25, s * 3.0))
                p.add("Black", box(0.56, 0.16, 0.56), T(a.x, a.y + 2.78, s * 3.0))
    for t in (0.3, 0.7):  # pilas: dos postes y sus travesaños
        a = point(t)
        for s in (-1, 1):
            p.add("Wood", cyl(0.36, a.y + 0.2, 8, 0.3), T(a.x, -0.6, s * 2.4))
        p.add("Wood", box(0.5, 0.5, 5.9), T(a.x, a.y - 0.75, 0))
        p.add("Wood", box(0.3, 0.3, 5.2), T(a.x, a.y * 0.45, 0))


def shrine(p):
    """Hokora: capillita de santuario sobre un zócalo, con tejado curvado, cuerda shimenawa y papeles."""
    p.add("StoneDark", box(9, 0.9, 8), T(0, 0.45, 0))
    p.add("Stone", box(8, 0.6, 7), T(0, 1.2, 0))
    p.add("White", box(5.6, 3.6, 4.6), T(0, 3.3, 0))
    p.add("Red", box(6.0, 0.3, 5.0), T(0, 5.0, 0))
    p.add("Red", box(6.0, 0.25, 5.0), T(0, 1.6, 0))
    for s in (-1, 1):
        for t in (-1, 1):
            p.add("Red", box(0.5, 3.6, 0.5), T(s * 2.8, 3.3, t * 2.3))
    p.add("Red", box(2.2, 2.8, 0.2), T(0, 3.0, -2.35))
    p.add("Gold", box(0.5, 0.5, 0.25), T(0, 3.0, -2.5))
    p.add("Roof", frustum(8.8, 7.6, 3.2, 2.4, 2.6), T(0, 6.25, 0))
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


def paw(p, x, y, z, size, role="Stone"):
    p.add(role, sphere(1, 8, 4), T(x, y, z) @ S(size * 0.55, size * 0.34, size * 0.85))
    for k in (-1.5, -0.5, 0.5, 1.5):  # dedos y garras
        p.add(role, sphere(size * 0.17, 5, 3), T(x + k * size * 0.2, y - size * 0.05, z - size * 0.78))
        p.add("StoneDark", spike(size * 0.05, size * 0.2, 4), T(x + k * size * 0.2, y - size * 0.1, z - size * 0.92) @ R("X", -80))


def komainu(p):
    """Guardián shishi sentado, con melena de rizos tallados, ceño firme y babero rojo. Mira hacia -Z."""
    p.add("StoneDark", box(4.5, 0.55, 5.7), T(0, 0.275, 0))
    p.add("Stone", frustum(4.3, 5.5, 3.9, 5.1, 0.55), T(0, 0.825, 0))
    p.add("StoneDark", box(4.05, 0.16, 5.25), T(0, 1.12, 0))
    base = 1.2
    # Silueta compacta, con pecho ancho y patas que descansan en la misma losa.
    p.add("Stone", sphere(1, 14, 9), T(0, base + 1.2, 0.75) @ S(1.35, 1.2, 1.5))
    p.add("Stone", sphere(1, 14, 9), T(0, base + 2.25, 0.15) @ S(1.15, 1.7, 1.1))
    for side in (-1, 1):
        p.add("Stone", sphere(1, 11, 7), T(side * 1.05, base + 0.85, 0.55) @ S(0.65, 0.85, 1.0))
        paw(p, side * 1.1, base + 0.25, -0.3, 0.8)
        p.branch("Stone", (side * 0.8, base + 2.8, -0.5), (side * 0.82, base + 0.45, -1.25), 0.48, 0.33, 10)
        paw(p, side * 0.82, base + 0.24, -1.55, 0.85)
    p.add("Red", torus(0.85, 0.16, 16, 6), T(0, base + 3.05, -0.15) @ S(1.2, 1, 1))
    p.add("Red", sphere(1, 12, 7), T(0, base + 2.7, -0.95) @ S(0.85, 0.65, 0.18))
    p.add("Gold", sphere(0.2, 10, 6), T(0, base + 2.25, -1.16))
    # Melena maciza: cada rizo es un relieve corto, sin púas sueltas.
    hy, hz = base + 4.1, -0.65
    p.add("StoneDark", sphere(1, 16, 10), T(0, hy, hz + 0.3) @ S(1.6, 1.5, 1.05))
    p.add("Stone", sphere(1, 16, 10), T(0, hy, hz - 0.1) @ S(1.25, 1.12, 0.95))
    for i in range(14):
        angle = 2 * math.pi * i / 14
        cx, cy = 1.3 * math.cos(angle), hy + 1.25 * math.sin(angle)
        cz = hz + 0.05
        p.add("Stone", sphere(1, 9, 6), T(cx, cy, cz) @ S(0.42, 0.43, 0.4))
        last = None
        for j in range(17):
            t = j / 16
            a = -0.5 + 2.8 * math.pi * t
            radius = 0.29 * (1 - 0.78 * t)
            point = (cx + radius * math.cos(a), cy + radius * math.sin(a), cz - 0.34)
            if last:
                p.branch("StoneDark", last, point, 0.045, 0.045, 5)
            last = point
    for side in (-1, 1):
        p.add("Stone", sphere(1, 10, 6), T(side * 1.08, hy + 0.95, hz - 0.1) @ S(0.34, 0.44, 0.25))
        p.add("StoneDark", sphere(1, 9, 5), T(side * 1.08, hy + 0.98, hz - 0.31) @ S(0.16, 0.22, 0.06))
        p.add("StoneDark", sphere(1, 9, 6), T(side * 0.52, hy + 0.2, hz - 0.94) @ S(0.24, 0.16, 0.09))
        p.add("Stone", sphere(1, 8, 5), T(side * 0.52, hy + 0.39, hz - 0.9) @ R("Z", side * 18) @ S(0.42, 0.16, 0.2))
        p.add("Stone", sphere(1, 11, 7), T(side * 0.37, hy - 0.22, hz - 1.0) @ S(0.48, 0.34, 0.42))
        p.add("Stone", spike(0.12, 0.27, 7), T(side * 0.47, hy - 0.46, hz - 1.25) @ R("X", 180))
    p.add("StoneDark", sphere(1, 11, 6), T(0, hy - 0.02, hz - 1.34) @ S(0.38, 0.23, 0.21))
    p.add("StoneDark", sphere(1, 12, 6), T(0, hy - 0.52, hz - 1.04) @ S(0.57, 0.22, 0.25))
    p.add("Stone", sphere(1, 12, 7), T(0, hy - 0.72, hz - 0.9) @ S(0.65, 0.21, 0.49))
    # Cola enrollada, unida a la grupa.
    p.branch("Stone", (0.6, base + 0.9, 1.55), (0.6, base + 1.6, 2.0), 0.32, 0.27, 10)
    p.add("Stone", torus(0.55, 0.24, 14, 7), T(0.6, base + 2.0, 1.85) @ R("X", 90))
    p.add("StoneDark", sphere(0.18, 9, 6), T(0.6, base + 2.0, 1.72))

def temple_roof(p, y0, half, top, rise, lift, wall, collar=False):
    """Un tejado del templo: losa con filas de tejas, limatesas rematadas en dorado con su campanilla, canto dorado en
    el alero y, por debajo, sofito claro y cabios rojos hasta `wall` (media anchura de lo que lo sostiene). Devuelve
    la altura a la que acaba arriba."""
    roof = HipRoof(y0, half, top, rise, lift)
    n, m = 12, 8
    under = (half - wall) / (half - top)
    size = half / 40
    p.add("Roof", roof.slab(n, m))
    for shape in roof.rows(2.6, ridge(0.8, 0.45), drop=0.1, steps=6):
        p.add("StoneDark", shape)
    p.add("White", roof.slab(n, 4, 0.015, min(1.0, under + 0.04), roof.thick, 0.22))
    for shape in roof.rows(2.9, rect(0.6, 0.55), 0.03, under, 4, roof.thick + 0.77):
        p.add("Red", shape)
    for side in range(4):
        rot = R("Y", 90 * side)
        edge = [rot @ (roof.at(-1 + 2 * i / n, 0, roof.thick + 0.12) + Vector((0, 0, -0.14))) for i in range(n + 1)]
        p.add("Gold", sweep(edge, rect(0.5, roof.thick + 0.34)))
        hip = [rot @ roof.at(1, j / m, 0.2) for j in range(m + 1)]
        out = (hip[0] - hip[1]).normalized()
        tip = hip[0] + out * 1.8 * size + Vector((0, 0.8 * size, 0))
        p.add("StoneDark", sweep([tip] + hip, rect(1.25, 1.05)))
        # Remate de la esquina: cuerno dorado hacia arriba y afuera, y una campanilla de viento colgando.
        aim = (Vector((out.x, 0, out.z)).normalized() + Vector((0, 1.3, 0))).normalized()
        turn = Vector((0, 1, 0)).rotation_difference(aim).to_matrix().to_4x4()
        p.add("Gold", spike(0.55 * size + 0.2, 2.6 * size + 0.8, 5), T(*tip) @ turn)
        p.add("Gold", sphere(0.5 * size + 0.25, 6, 4), T(tip.x, tip.y + 0.5, tip.z))
        bell = hip[0] - Vector((0, 2.6, 0))
        p.add("Black", box(0.12, 1.3, 0.12), T(bell.x, bell.y + 1.5, bell.z))
        p.add("Gold", lathe([(0.6, 0), (0.45, 0.4), (0.3, 0.78), (0, 0.9)], 6), T(*bell))
    if collar:
        p.add("StoneDark", frame(top + 1.0, top - 0.4, 0.9), T(0, y0 + rise - 0.35, 0))
    return y0 + rise


def temple_brackets(p, y, half, inner, scale=1.0):
    """Tres hiladas de ménsulas (roja, clara, roja) que salen cada vez más bajo el alero, con tacos dorados. Devuelve
    la altura a la que acaban y lo que sobresale la última."""
    outer = half
    for index, (step, tall, role) in enumerate(((0.9, 0.7, "Red"), (1.2, 0.8, "White"), (1.2, 0.7, "Red"))):
        outer += step * scale
        p.add(role, frame(outer, inner, tall * scale), T(0, y, 0))
        y += tall * scale
    count = int((outer - 1.5) / 3.6)
    for side in range(4):
        for i in range(-count, count + 1):
            p.add("Gold", box(0.9, 0.5 * scale, 0.3), R("Y", 90 * side) @ T(i * 3.6, y - 0.35 * scale, -outer - 0.05))
    return y, outer


def temple_body(p, y, half, height, bays, round_window=False):
    """Un piso del templo: paredes claras, postes y vigas rojas, y ventanas de papel con celosía (una por vano, o una
    sola redonda en el del centro)."""
    p.add("White", box(2 * half, height, 2 * half), T(0, y + height / 2, 0))
    width = 2 * half / bays
    for side in range(4):
        rot = R("Y", 90 * side)
        for i in range(bays):  # el poste de la otra esquina lo pone el lado siguiente
            thick = 1.1 if i == 0 else 0.8
            p.add("Red", box(thick, height, thick), rot @ T(-half + width * i, y + height / 2, -half))
        for level, tall in ((0.5, 1.0), (height - 0.5, 1.0), (height * 0.32, 0.5)):
            p.add("Red", box(2 * half + 0.3, tall, 0.5), rot @ T(0, y + level, -half - 0.12))
        for i in range(bays):
            x = -half + width * (i + 0.5)
            if round_window:
                if i != bays // 2:
                    continue
                r, cy = height * 0.2, y + height * 0.6
                p.add("Paper", cyl(r, 0.3, 16), rot @ T(x, cy, -half - 0.34) @ R("X", 90))
                p.add("Black", torus(r + 0.12, 0.26, 16, 5), rot @ T(x, cy, -half - 0.2) @ R("X", 90))
                p.add("Black", box(0.18, 2 * r, 0.14), rot @ T(x, cy, -half - 0.36))
                p.add("Black", box(2 * r, 0.18, 0.14), rot @ T(x, cy, -half - 0.36))
            else:
                w, h, cy = width * 0.56, height * 0.4, y + height * 0.64
                p.add("Black", box(w + 0.5, h + 0.5, 0.3), rot @ T(x, cy, -half - 0.1))
                p.add("Paper", box(w, h, 0.36), rot @ T(x, cy, -half - 0.1))
                for k in range(1, 4):
                    p.add("Black", box(0.16, h, 0.14), rot @ T(x - w / 2 + w * k / 4, cy, -half - 0.3))
                for k in range(1, 3):
                    p.add("Black", box(w, 0.16, 0.14), rot @ T(x, cy - h / 2 + h * k / 3, -half - 0.3))


def temple_balcony(p, y, half, skirt):
    """Balcón corrido alrededor de un piso: faldón que lo apoya en el tejado de abajo (de alto `skirt`), suelo de
    madera y barandilla roja con remates dorados en las esquinas. `y` es la cara de abajo del suelo."""
    p.add("Red", frame(half - 1.0, half - 3.6, skirt), T(0, y - skirt, 0))
    p.add("Wood", box(2 * half, 0.5, 2 * half), T(0, y + 0.25, 0))
    p.add("Red", frame(half + 0.12, half - 0.6, 0.36), T(0, y - 0.1, 0))
    rail = half - 0.5
    count = max(2, round(2 * rail / 4.6))
    floor = y + 0.5
    for side in range(4):
        rot = R("Y", 90 * side)
        for i in range(count):
            x = -rail + 2 * rail * i / count
            if i == 0:
                p.add("Red", box(0.75, 3.2, 0.75), rot @ T(x, floor + 1.6, -rail))
                p.add("Gold", giboshi(1.1), rot @ T(x, floor + 3.2, -rail))
            else:
                p.add("Red", box(0.45, 2.5, 0.45), rot @ T(x, floor + 1.25, -rail))
        for level, tall in ((2.4, 0.4), (1.3, 0.26), (0.45, 0.26)):
            p.add("Red", box(2 * rail + 1.8, tall, tall), rot @ T(0, floor + level, -rail))


def temple(p):
    """Templo de tres pisos sobre la boca de las mazmorras, de 82 de ancho y casi 100 de alto. Planta baja abierta:
    doce columnas rojas con basa de piedra, vigas, friso claro, cuerda sagrada (shimenawa) en la entrada de cada lado
    y techo de casetones con un sello en el centro. Encima, tres tejados curvos de esquinas levantadas, dos pisos con
    balcón y ventanas de papel, y un remate dorado de anillos. Sale en tres piezas (TempleA, B y C: una por piso) con
    el mismo origen, el centro del suelo. La boca, el ascensor y los círculos mágicos quedan debajo, sin tocar."""
    E, INNER, H = 26.0, 10.0, 24.0  # media anchura de la línea de columnas, columnas del hueco central y su alto

    # --- A: planta baja y primer tejado ---
    p.group = "A"
    for sx in (-1, 1):
        for sz in (-1, 1):
            for a, b in ((E, E), (E, INNER), (INNER, E)):
                x, z = sx * a, sz * b
                p.add("Stone", lathe([(3.2, 0), (3.2, 0.5), (2.6, 1.0), (2.2, 1.15)], 12), T(x, 0, z))
                p.add("Red", lathe([(1.9, 1.1), (1.95, 8.0), (1.85, 16.0), (1.68, H)], 12), T(x, 0, z))
                p.add("Black", cyl(2.12, 1.6, 12, 2.06), T(x, 1.15, z))
                p.add("Gold", cyl(2.2, 0.32, 12), T(x, 2.75, z))
                p.add("Gold", cyl(1.96, 0.5, 12), T(x, 19.3, z))
                p.add("Black", frustum(3.6, 3.6, 5.0, 5.0, 1.1), T(x, H + 0.55, z))  # capitel
                p.add("Gold", box(5.2, 0.24, 5.2), T(x, H + 1.22, z))
    span = INNER - 1.85
    for side in range(4):
        rot = R("Y", 90 * side)
        # Viga entre las cabezas de las columnas (sus puntas asoman en las esquinas) y friso claro con tacos rojos.
        p.add("Red", box(2 * E + 5.4, 1.6, 1.3), rot @ T(0, 22.0, -E))
        for s in (-1, 1):
            p.add("Gold", box(0.2, 1.3, 1.0), rot @ T(s * (E + 2.75), 22.0, -E))
        p.add("White", box(2 * E, 2.5, 0.5), rot @ T(0, 24.05, -E))
        for i in range(-4, 5):
            p.add("Red", box(0.8, 2.5, 0.75), rot @ T(i * 5.2, 24.05, -E))
        # Shimenawa: cuerda de paja gruesa en el centro, con papeles en zigzag y borlas.
        rope = [Vector((span * (i / 6 - 1), 21.0 - 2.3 * (1 - (i / 6 - 1) ** 2), -E)) for i in range(13)]
        p.add("Tan", sweep([rot @ q for q in rope], circle(0.62, 7), [0.8 + 0.5 * (1 - abs(i / 6 - 1)) for i in range(13)]))
        for x in (-5.4, -1.8, 1.8, 5.4):
            top = 21.0 - 2.3 * (1 - (x / span) ** 2) - 0.6
            for k in range(3):
                p.add("White", box(0.95, 0.85, 0.08), rot @ T(x + (0.3 if k % 2 else -0.3), top - 0.45 - k * 0.8, -E - 0.1))
        for x in (-3.6, 0.0, 3.6):
            top = 21.0 - 2.3 * (1 - (x / span) ** 2) - 0.5
            p.add("Tan", cyl(0.5, 1.9, 6, 0.16), rot @ T(x, top - 1.9, -E))
    # Techo de casetones: tablero, rejilla de vigas rojas con clavos dorados y un sello redondo en el centro.
    p.add("Wood", box(2 * E - 2.0, 0.4, 2 * E - 2.0), T(0, 25.6, 0))
    step = 2 * E / 6
    for i in range(7):
        c = -E + i * step
        p.add("Red", box(2 * E, 0.8, 0.9), T(0, 24.9, c))
        p.add("Red", box(0.9, 0.78, 2 * E), T(c, 24.9, 0))
        for j in range(7):
            if 0 < i < 6 and 0 < j < 6 and (i, j) != (3, 3):
                p.add("Gold", box(1.4, 0.2, 1.4), T(c, 24.42, -E + j * step))
    p.add("Black", cyl(7.4, 0.3, 16), T(0, 24.2, 0))
    p.add("Gold", torus(7.5, 0.32, 16, 5), T(0, 24.2, 0))
    p.add("Paper", torus(5.7, 0.6, 16, 4), T(0, 24.1, 0) @ S(1, 0.3, 1))
    p.add("Gold", torus(3.0, 0.25, 12, 4), T(0, 24.15, 0))
    p.add("Gold", sphere(1.3, 8, 4), T(0, 24.1, 0) @ S(1, 0.6, 1))
    for k in range(8):
        p.add("Gold", box(1.5, 0.12, 0.3), R("Y", 45 * k) @ T(4.05, 24.15, 0))
    p.add("Red", frame(E + 1.3, E - 1.3, 1.0), T(0, 25.3, 0))  # solera sobre los capiteles
    y, wall = temple_brackets(p, 26.3, E + 1.1, E - 1.3)
    y = temple_roof(p, y - 1.7, 41.0, 16.5, 13.0, 3.2, wall)

    # --- B: segundo piso con balcón y segundo tejado ---
    p.group = "B"
    temple_balcony(p, y - 0.4, 19.4, 2.8)
    y += 0.1
    temple_body(p, y, 14.0, 9.3, 3)
    y, wall = temple_brackets(p, y + 9.3, 14.0, 12.0)
    y = temple_roof(p, y - 3.0, 27.5, 10.8, 10.5, 2.6, wall)

    # --- C: tercer piso, tejado alto y remate ---
    p.group = "C"
    temple_balcony(p, y - 0.4, 13.0, 2.6)
    y += 0.1
    temple_body(p, y, 8.6, 7.0, 3, True)
    y, wall = temple_brackets(p, y + 7.0, 8.6, 7.0, 0.85)
    y = temple_roof(p, y - 1.95, 19.5, 1.0, 13.5, 2.4, wall, True) - 0.5
    # Sōrin: base, cuenco, loto, mástil con siete anillos, llama y joya.
    p.add("Gold", frustum(3.6, 3.6, 2.8, 2.8, 1.3), T(0, y + 0.65, 0))
    p.add("Gold", sphere(1.7, 10, 5), T(0, y + 1.3, 0) @ S(1, 0.75, 1))
    p.add("Gold", lathe([(0.5, 0), (1.5, 0.5), (1.9, 0.9), (0.6, 1.0)], 10), T(0, y + 2.3, 0))
    p.add("Gold", cyl(0.38, 11.5, 8, 0.24), T(0, y + 3.0, 0))
    for k in range(7):
        p.add("Gold", torus(1.7 - k * 0.14, 0.26, 14, 5), T(0, y + 4.4 + k * 1.15, 0))
    y += 12.8
    for k in range(2):
        p.add("Gold", spike(0.95, 3.2, 4), T(0, y, 0) @ R("Y", 90 * k) @ S(1, 1, 0.14))
    p.add("Gold", sphere(0.75, 8, 5), T(0, y + 3.5, 0))
    p.add("Gold", spike(0.3, 1.3, 6), T(0, y + 4.1, 0))


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


# ---------- Bolsa de oro (server/GoldBag) ----------

def cloth(profile, n=28, folds=7, lean=(0.0, 0.0), seed=5):
    """Tela de saco: sólido de revolución sobre Y con pliegues. profile = [(radio, y, pliegue)] de abajo a arriba
    (puede volver a bajar por dentro de la boca): `pliegue` es cuánto ondula el radio con el ángulo a esa altura
    (0 = liso). `lean` = cuánto se vence hacia X y Z arriba del todo (crece con el cuadrado de la altura)."""
    rng = random.Random(seed)
    wobble = [rng.uniform(-1, 1) for _ in range(n)]
    height = max(y for _, y, _ in profile)
    verts, rings = [], []
    for r, y, fold in profile:
        rings.append(len(verts))
        k2 = (y / height) ** 2
        for i in range(n):
            a = 2 * math.pi * i / n
            k = 1 + fold * (math.cos(folds * a) + 0.35 * wobble[i])
            verts.append((r * k * math.cos(a) + lean[0] * k2, y, r * k * math.sin(a) + lean[1] * k2))
    faces = [tuple(rings[0] + i for i in reversed(range(n))), tuple(rings[-1] + i for i in range(n))]
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        faces += [(a + i, a + (i + 1) % n, b + (i + 1) % n, b + i) for i in range(n)]
    return verts, faces


SACK_HEIGHT = 12.4  # del suelo al borde de la boca
SACK_LEAN = (0.55, 0.3)  # lo que se vence la boca hacia un lado
SACK_SCALE = 1.1  # a cuánto pone el juego el saco y su pedestal (SACK_SCALE de server/GoldBag)
SACK_DISTANCE = 27.0  # studs del muro de la parcela al centro del saco (DISTANCE de server/GoldBag)
PATH_WIDTH = 9.0


def sack_lean(y):
    k = (y / SACK_HEIGHT) ** 2
    return SACK_LEAN[0] * k, SACK_LEAN[1] * k


def gold_sack(p):
    """Saco de oro atado con cuerda, con una moneda antigua de emblema, papeles shide colgando de la cuerda y oro
    rebosando por la boca. Va en dos piezas con el mismo origen: el saco (GoldSack, que el juego puede encoger según
    se vacía), su pedestal de piedra con pilas de monedas y lingotes (GoldSackBase) y el camino de losas que llega
    del paso del muro de la parcela (GoldSackPath, en studs del juego: va sin escalar). El frente (-Z) mira a la
    parcela."""
    rng = random.Random(77)
    # Tela: barriga ancha y caída, cuello estrangulado por la cuerda y boca abierta con volantes.
    p.add("Sack", cloth([
        (3.9, 0.0, 0.0), (5.4, 0.45, 0.015), (6.15, 1.5, 0.02), (6.45, 3.1, 0.025), (6.3, 4.7, 0.03),
        (5.7, 6.2, 0.045), (4.6, 7.6, 0.075), (3.2, 8.75, 0.12), (2.15, 9.5, 0.17), (1.95, 9.95, 0.17),
        (2.6, 10.4, 0.17), (3.5, 11.0, 0.18), (4.15, 11.8, 0.2), (4.3, SACK_HEIGHT, 0.21), (3.7, 12.3, 0.2),
        (2.7, 11.5, 0.14),
    ], n=42, lean=SACK_LEAN))
    # Franja oscura por dentro de la boca y remiendo cosido en un costado.
    lx, lz = sack_lean(11.5)
    p.add("SackDark", cyl(2.75, 0.3, 14), T(lx, 11.35, lz))
    patch = math.radians(118)
    px, pz = 6.05 * math.sin(patch), 6.05 * math.cos(patch)
    to_patch = T(px, 5.3, pz) @ R("Y", 118)
    p.add("SackDark", sphere(1, 8, 4), to_patch @ S(1.55, 1.3, 0.3))
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1), (0, -1.25), (0, 1.25)):
        p.add("Rope", box(0.16, 0.5, 0.14), to_patch @ T(sx * 1.2, sy * 0.85, 0.24) @ R("Z", 35 * sx if sx else 90))

    # Cuerda: dos vueltas en el cuello, nudo al frente y dos cabos con su borla.
    nx, nz = sack_lean(9.75)
    for y in (9.5, 9.98):
        p.add("Rope", torus(2.2, 0.33, 18, 6), T(nx, y, nz))
    knot = (nx, 9.7, nz - 2.5)
    p.add("Rope", sphere(0.62, 8, 5), T(*knot) @ S(1.15, 0.9, 0.9))
    for end in ((nx - 1.7, 7.0, nz - 4.45), (nx + 2.1, 7.9, nz - 4.85)):
        p.branch("Rope", knot, end, 0.26, 0.2, 6)
        p.add("Rope", sphere(0.42, 6, 4), T(*end) @ S(1, 1.35, 1))
        p.add("Gold", torus(0.3, 0.1, 8, 4), T(end[0], end[1] + 0.45, end[2]))
    # Tablilla de madera (ema) colgando del nudo, con su cordón.
    tag = T(nx + 0.2, 7.55, nz - 5.05) @ R("X", -24) @ R("Z", 7)
    p.branch("Rope", knot, (nx + 0.2, 8.5, nz - 4.5), 0.14, 0.12, 5)
    p.add("Wood", box(1.9, 2.3, 0.24), tag)
    p.add("Wood", frustum(1.9, 0.24, 0.5, 0.24, 0.55), tag @ T(0, 1.42, 0))
    p.add("Gold", cyl(0.42, 0.1, 10), tag @ T(0, -0.1, -0.13) @ R("X", -90))

    # Emblema al frente: una moneda antigua (con su agujero cuadrado) cosida a la barriga.
    front = T(0.12, 4.5, -6.42) @ R("X", -86)
    p.add("Gold", cyl(2.5, 0.38, 16), front)
    p.add("Gold", torus(2.3, 0.26, 16, 5), front @ T(0, 0.34, 0))
    p.add("Gold", torus(0.95, 0.2, 4, 4), front @ T(0, 0.34, 0) @ R("Y", 45))
    p.add("SackDark", box(1.15, 0.2, 1.15), front @ T(0, 0.36, 0))
    for quarter in range(4):
        p.add("Gold", box(0.26, 0.16, 0.7), front @ R("Y", 90 * quarter) @ T(0, 0.42, 1.62))

    # Oro rebosando: un montón en la boca, monedas sueltas encima y dos que se escapan por el borde.
    mx, mz = sack_lean(12.0)
    p.add("Gold", sphere(1, 12, 5), T(mx, 11.75, mz) @ S(3.15, 1.35, 3.15))
    for index in range(13):
        a, reach = index * 2.4, 0.35 + 0.19 * index  # en espiral: se reparten sin amontonarse
        y = 11.75 + 1.35 * math.sqrt(max(1 - (reach / 3.15) ** 2, 0)) + 0.03
        lay = T(mx + reach * math.sin(a), y, mz + reach * math.cos(a)) @ R("Y", math.degrees(a)) @ R("X", 14 + 16 * reach + rng.uniform(-8, 8))
        p.add("Gold", cyl(0.82, 0.19, 10), lay @ R("Y", rng.uniform(0, 36)))
    # De canto, clavadas en el montón.
    for degrees, tilt in ((200, 66), (95, 58), (-40, 72)):
        a = math.radians(degrees)
        p.add("Gold", cyl(0.82, 0.19, 10), T(mx + 1.5 * math.sin(a), 12.75, mz + 1.5 * math.cos(a)) @ R("Y", degrees) @ R("X", tilt))

    # Pedestal: dos escalones redondos de piedra con un aro de oro, un ruedo de losas, mojones alrededor (menos por
    # delante, donde llega el camino), pilas de monedas, monedas sueltas y lingotes.
    p.group = "Base"
    top = 0.95
    p.add("StoneDark", cyl(12.6, 0.5, 32, 12.35))
    p.add("Stone", cyl(11.5, top - 0.5, 32, 11.3), T(0, 0.5, 0))
    p.add("StoneDark", torus(11.0, 0.1, 32, 4), T(0, top, 0))
    p.add("Gold", torus(9.9, 0.16, 32, 4), T(0, top, 0))
    for index in range(16):
        degrees = index * 22.5
        p.add("StoneDark", box(0.14, 0.05, 1.05), R("Y", degrees) @ T(0, top, 10.45))  # juntas del ruedo de losas
        if 30 < degrees < 330:
            p.add("Stone", sphere(1, 8, 4), R("Y", degrees + 180) @ T(0, 0.5, 12.0) @ S(0.42, 0.34, 0.42))
    for degrees, reach, count in ((152, 8.4, 8), (170, 9.7, 4), (133, 9.5, 3), (-146, 8.5, 10), (-166, 9.9, 6),
                                  (-124, 9.6, 3), (48, 8.9, 6), (66, 9.9, 2), (-60, 9.0, 5)):
        a = math.radians(degrees)
        x, z = reach * math.sin(a), reach * math.cos(a)
        for k in range(count):
            p.add("Gold", cyl(0.86, 0.2, 10), T(x + rng.uniform(-0.09, 0.09), top + k * 0.215, z + rng.uniform(-0.09, 0.09)) @ R("Y", rng.uniform(0, 36)))
    for _ in range(14):
        a, reach = rng.uniform(0, 2 * math.pi), rng.uniform(7.4, 10.8)
        p.add("Gold", cyl(0.86, 0.2, 10), T(reach * math.sin(a), top, reach * math.cos(a)) @ R("Y", rng.uniform(0, 36)))
    # Monedas de canto, apoyadas en el saco.
    for degrees in (95, -100, 12):
        a = math.radians(degrees)
        p.add("Gold", cyl(0.86, 0.2, 10), T(6.9 * math.sin(a), top + 0.82, 6.9 * math.cos(a)) @ R("Y", degrees) @ R("X", 72))
    # Lingotes: dos juntos y uno cruzado encima.
    bars = T(8.6 * math.sin(math.radians(-92)), top, 8.6 * math.cos(math.radians(-92))) @ R("Y", -70)
    for x, y, turn in ((-0.62, 0.32, 0), (0.62, 0.32, 0), (0, 0.96, 24)):
        p.add("Gold", frustum(2.5, 1.05, 2.15, 0.72, 0.62), bars @ T(x * 1.0, y, 0) @ R("Y", 90 + turn))

    # Camino: lecho de grava oscura, losas irregulares al tresbolillo, bordillos de piedra y monedas caídas.
    p.group = "Path"
    near, far = 12.6 * SACK_SCALE - 0.7, SACK_DISTANCE + 0.6
    length = far - near
    half = PATH_WIDTH / 2
    p.add("StoneDark", box(PATH_WIDTH, 0.16, length), T(0, 0.08, -(near + far) / 2))
    rows = 4
    deep = length / rows
    for row in range(rows):
        z = -(near + (row + 0.5) * deep)
        cuts = [-half + 0.35] + sorted(rng.uniform(-half + 2.2, half - 2.2) for _ in range(1 + row % 2)) + [half - 0.35]
        if len(cuts) == 4 and cuts[2] - cuts[1] < 2.0:
            cuts = [cuts[0], (cuts[1] + cuts[2]) / 2, cuts[3]]
        for left, right in zip(cuts, cuts[1:]):
            wide, long = right - left - 0.3, deep - 0.38
            slab = T((left + right) / 2, 0.1, z + rng.uniform(-0.1, 0.1)) @ R("Y", rng.uniform(-4, 4))
            p.add("Stone", frustum(wide, long, wide - 0.3, long - 0.3, 0.26), slab @ T(0, 0.13, 0))
    for side in (-1, 1):
        z = near + 0.2
        while z < far - 1.0:
            long = rng.uniform(1.5, 2.3)
            curb = T(side * (half + 0.3) + rng.uniform(-0.08, 0.08), 0, -(z + long / 2)) @ R("Y", rng.uniform(-5, 5))
            p.add("Stone", frustum(0.95, long, 0.7, long - 0.25, rng.uniform(0.48, 0.62)), curb @ T(0, 0.27, 0))
            z += long + 0.18
    for x, z, turn in ((-3.3, 15.4, 0), (2.6, 17.9, 20), (-1.2, 21.6, 40), (3.5, 24.3, 10), (-2.9, 25.6, 65), (0.6, 14.6, 30)):
        p.add("Gold", cyl(0.8, 0.18, 10), T(x, 0.36, -z) @ R("Y", turn) @ R("X", rng.uniform(-4, 4)))
    for k in range(3):
        p.add("Gold", cyl(0.8, 0.18, 10), T(3.4 + rng.uniform(-0.07, 0.07), 0.36 + k * 0.19, -19.9 + rng.uniform(-0.07, 0.07)))


# El herrero de la cinemática de tirada (client/RollCinematic, tema "smith"). Estas medidas son las mismas que usa
# el juego para mover las piezas (SMITH en RollCinematic): si cambian aquí, cambian allí.
SMITH_WAIST = (0.0, 5.0, -7.0)  # por donde se dobla el cuerpo
SMITH_NECK = (0.0, 15.6, -6.6)
SMITH_SHOULDER = (6.5, 14.0, -6.5)  # el del martillo; el otro, con la X cambiada de signo
SMITH_UPPER = 6.5  # del hombro al codo
SMITH_FORE = 6.9  # del codo al centro del puño
SMITH_HAMMER = (16.0, 4.0, 0.0)  # por dónde se coge el martillo, que se modela aparte, de pie
SMITH_HEAD = 6.2  # del agarre al centro de la cabeza del martillo


def smith(p):
    """Herrero espectral gigante y su fragua, para la cinemática de tirada. Al contrario que el resto de piezas, mira
    a +Z (a la cámara de la escena) y su origen es el centro del escenario, así que cada cosa va ya en su sitio.
    Sale en piezas con el mismo origen para moverlas por separado: SmithTorso (sale del suelo como un genio),
    SmithHead, SmithArmA/SmithForeA (el brazo del martillo, a +X, modelado colgando recto del hombro), SmithArmB/
    SmithForeB (el que sujeta el arma), SmithHammer (de pie, a un lado), SmithAnvil y SmithForge (fragua, barril de
    temple y monolitos de runas). Papeles: StoneDark = piel, Stone = hierro, Black = cuero, Gold = adornos,
    Paper = lo que brilla (ojos, runas, brasas), White = cuernos y barba, Wood y Water."""
    rng = random.Random(41)
    wx, wy, wz = SMITH_WAIST

    # --- Torso ---
    p.group = "Torso"
    # Cola de espíritu: sale del suelo y se ensancha hasta la cintura.
    p.add("StoneDark", lathe([(0.5, 0), (1.5, 0.8), (2.6, 2.2), (3.7, 3.8), (4.3, 5.2), (4.4, 6.2)], 14), T(0, 0, wz) @ S(1, 1, 0.8))
    p.add("StoneDark", sphere(1, 14, 8), T(0, 7.2, wz) @ S(4.7, 3.0, 3.5))  # barriga
    p.add("StoneDark", sphere(1, 16, 8), T(0, 11.2, -6.8) @ S(6.3, 4.3, 4.0))  # pecho
    for side in (-1, 1):
        p.add("StoneDark", sphere(1, 10, 6), T(side * 2.5, 11.9, -3.9) @ S(2.7, 2.1, 1.5))  # pectorales
        p.add("StoneDark", sphere(1, 10, 6), T(side * 4.6, 14.3, -6.9) @ S(2.6, 1.6, 2.4))  # trapecios
    p.add("StoneDark", cyl(2.3, 2.2, 12, 1.9), T(0, 14.0, -6.6))  # cuello
    # Cinturón ancho con hebilla, y delantal de cuero con tirantes.
    p.add("Black", lathe([(4.55, 0), (4.75, 0.3), (4.75, 1.3), (4.55, 1.6)], 16), T(0, 4.9, wz) @ S(1, 1, 0.8))
    p.add("Gold", box(2.4, 2.0, 0.5), T(0, 5.7, wz + 3.75))
    p.add("Paper", box(1.2, 1.0, 0.2), T(0, 5.7, wz + 4.05) @ R("Z", 45) @ S(0.8, 0.8, 1))
    apron = T(0, 8.6, -2.95) @ R("X", 9)
    p.add("Black", frustum(6.2, 0.45, 5.0, 0.45, 6.6), apron)
    p.add("Black", frustum(4.6, 0.4, 6.0, 0.4, 3.4), T(0, 3.2, -3.3) @ R("X", -6))
    for side in (-1, 1):
        p.branch("Black", (side * 2.4, 11.7, -2.6), (side * 3.6, 14.9, -5.6), 0.5, 0.5, 4)
        p.add("Gold", cyl(0.42, 0.25, 8), T(side * 2.4, 11.2, -2.42) @ R("X", 90))
    # Núcleo de runa en el pecho, con su aro.
    core = T(0, 12.6, -2.72) @ R("X", 84)
    p.add("Gold", torus(1.25, 0.24, 14, 5), core)
    p.add("Paper", sphere(1, 10, 6), core @ S(1.0, 0.45, 1.0))
    # Hombreras de hierro con remaches de oro y pinchos.
    for side in (-1, 1):
        sx, sy, sz = side * SMITH_SHOULDER[0], SMITH_SHOULDER[1], SMITH_SHOULDER[2]
        cap = T(sx + side * 0.3, sy + 0.5, sz) @ R("Z", -side * 22)
        p.add("Stone", lathe([(3.0, 0), (2.9, 0.7), (2.3, 1.6), (1.2, 2.2), (0, 2.4)], 12), cap)
        p.add("Gold", torus(2.95, 0.22, 14, 5), cap @ T(0, 0.15, 0))
        for degrees in (-50, 0, 50):
            a = math.radians(degrees)
            p.add("Gold", spike(0.42, 1.9, 5), cap @ T(1.5 * math.sin(a) * side, 1.75, 1.5 * math.cos(a) * 0.4) @ R("Z", -side * 18 * math.sin(a) - side * 10))
    # Chimeneas de fragua en la espalda, con la boca encendida.
    for side in (-1, 1):
        pipe = T(side * 2.9, 12.2, -9.6) @ R("X", -16) @ R("Z", -side * 9)
        p.add("Stone", cyl(1.05, 6.4, 10, 0.9), pipe)
        p.add("Gold", torus(1.02, 0.22, 10, 5), pipe @ T(0, 6.2, 0))
        p.add("Gold", torus(1.1, 0.2, 10, 5), pipe @ T(0, 2.6, 0))
        p.add("Paper", cyl(0.75, 0.12, 10), pipe @ T(0, 6.38, 0))

    # --- Cabeza ---
    p.group = "Head"
    hx, hy, hz = 0.0, 18.2, -6.1
    p.add("StoneDark", sphere(1, 14, 8), T(hx, hy, hz) @ S(2.55, 2.75, 2.65))
    p.add("StoneDark", sphere(1, 10, 6), T(hx, hy - 1.7, hz + 0.9) @ S(2.0, 1.4, 1.9))  # mandíbula
    p.add("StoneDark", box(0.75, 1.5, 0.8), T(hx, hy - 0.35, hz + 2.75) @ R("X", -14))  # nariz
    # Casco: cúpula de hierro, banda de oro, cresta y protector de nariz.
    helm = T(hx, hy + 0.35, hz - 0.1)
    p.add("Stone", lathe([(2.9, 0), (2.85, 0.9), (2.3, 2.0), (1.2, 2.7), (0, 2.95)], 14), helm)
    p.add("Gold", lathe([(3.0, 0), (3.05, 0.25), (3.05, 0.75), (2.95, 0.95)], 14), helm @ T(0, -0.35, 0))
    p.add("Gold", sweep([(0, 0.4, 2.95), (0, 2.1, 2.3), (0, 3.15, 0.3), (0, 2.6, -1.9), (0, 1.0, -2.9)], rect(0.5, 0.45)), helm)
    p.add("Stone", box(0.55, 1.9, 0.35), T(hx, hy - 0.1, hz + 2.95))
    p.add("Paper", box(0.5, 0.5, 0.2), helm @ T(0, 0.25, 3.02) @ R("Z", 45))  # gema de la frente
    # Cuernos curvos hacia arriba.
    for side in (-1, 1):
        horn = [(side * 2.6, hy + 1.2, hz), (side * 4.3, hy + 1.3, hz + 0.2), (side * 5.5, hy + 2.5, hz + 0.6),
                (side * 5.7, hy + 4.2, hz + 1.0), (side * 5.0, hy + 5.6, hz + 1.3)]
        p.add("White", sweep(horn, circle(0.95, 8), [1.0, 0.92, 0.7, 0.42, 0.08]))
        p.add("Gold", torus(1.0, 0.2, 10, 5), T(side * 3.3, hy + 1.25, hz + 0.08) @ R("Z", 90))
    # Ojos encendidos en sus cuencas, y cejas.
    for side in (-1, 1):
        p.add("Black", sphere(1, 8, 5), T(side * 1.05, hy + 0.1, hz + 2.3) @ S(0.82, 0.6, 0.5))
        p.add("Paper", sphere(1, 8, 5), T(side * 1.05, hy + 0.08, hz + 2.48) @ S(0.55, 0.32, 0.4))
        p.add("White", box(1.3, 0.34, 0.5), T(side * 1.1, hy + 0.72, hz + 2.55) @ R("Z", -side * 16))
    # Barba en tres trenzas con anillos, y bigote.
    for bx, long, wide in ((0, 4.3, 1.5), (-1.55, 4.0, 1.05), (1.55, 4.0, 1.05)):
        top = (bx, hy - 1.9, hz + 2.3)
        tip = (bx * 1.15, hy - 1.9 - long, hz + 3.1)
        m, shape = limb(top, tip, wide, wide * 0.35, 8)
        p.add("White", shape, m)
        ring_at = Vector(top).lerp(Vector(tip), 0.72)
        p.add("Gold", torus(wide * 0.62, 0.17, 8, 4), T(*ring_at) @ R("X", 8))
    p.add("White", sphere(1, 10, 5), T(hx, hy - 1.75, hz + 2.2) @ S(2.25, 1.0, 1.0))
    for side in (-1, 1):
        p.branch("White", (side * 0.2, hy - 1.2, hz + 2.95), (side * 2.5, hy - 2.0, hz + 2.5), 0.42, 0.14, 6)

    # --- Brazos: colgando rectos del hombro (el juego los gira por hombro y codo) ---
    for side, tag in ((1, "A"), (-1, "B")):
        sx, sy, sz = side * SMITH_SHOULDER[0], SMITH_SHOULDER[1], SMITH_SHOULDER[2]
        elbow = sy - SMITH_UPPER
        p.group = "Arm" + tag
        p.add("StoneDark", sphere(1, 10, 6), T(sx, sy - 0.2, sz) @ S(2.15, 2.0, 2.15))
        p.branch("StoneDark", (sx, sy, sz), (sx, elbow, sz), 1.85, 1.45, 10)
        p.add("StoneDark", sphere(1, 10, 6), T(sx + side * 0.2, sy - 2.9, sz + 0.35) @ S(1.95, 2.3, 2.0))  # bíceps
        p.add("Gold", torus(1.72, 0.26, 12, 5), T(sx, sy - 4.9, sz))
        p.add("Paper", torus(1.7, 0.1, 12, 4), T(sx, sy - 4.45, sz))
        p.add("StoneDark", sphere(1.5, 10, 6), T(sx, elbow, sz))
        p.group = "Fore" + tag
        fist = elbow - SMITH_FORE
        p.branch("StoneDark", (sx, elbow, sz), (sx, fist + 1.2, sz), 1.45, 1.6, 10)
        # Brazal de hierro con cantos de oro y una runa.
        p.add("Stone", lathe([(1.75, 0), (2.0, 0.3), (2.05, 3.0), (1.8, 3.4)], 12), T(sx, fist + 1.7, sz))
        for y in (fist + 1.85, fist + 4.9):
            p.add("Gold", torus(2.02, 0.2, 12, 5), T(sx, y, sz))
        p.add("Paper", box(0.5, 1.8, 0.14), T(sx, fist + 3.4, sz + 2.02))
        for y in (3.9, 3.2):
            p.add("Paper", box(1.0, 0.34, 0.14), T(sx + 0.42, fist + y, sz + 2.02) @ R("Z", 38))
        # Puño: palma y cuatro nudillos.
        p.add("StoneDark", sphere(1, 10, 6), T(sx, fist, sz) @ S(1.75, 1.6, 1.8))
        for k in range(4):
            p.add("StoneDark", sphere(0.62, 6, 4), T(sx - 1.05 + k * 0.7, fist - 0.55, sz + 1.35))
        p.add("StoneDark", sphere(0.7, 6, 4), T(sx - side * 1.5, fist + 0.2, sz + 0.9))  # pulgar

    # --- Martillo: de pie, cogido por SMITH_HAMMER; la cabeza pega con las caras de +Z y -Z ---
    p.group = "Hammer"
    gx, gy, gz = SMITH_HAMMER
    p.add("Wood", cyl(0.5, 8.6, 8, 0.42), T(gx, gy - 2.2, gz))
    p.add("Gold", sphere(0.75, 8, 5), T(gx, gy - 2.4, gz))
    for y in (-1.2, -0.4, 0.4, 1.2):
        p.add("Black", torus(0.52, 0.14, 8, 4), T(gx, gy + y, gz))
    top = gy + SMITH_HEAD
    p.add("Stone", box(3.3, 3.2, 4.4), T(gx, top, gz))
    for face in (-1, 1):
        p.add("Stone", frustum(3.3, 3.2, 2.7, 2.6, 0.7), T(gx, top, gz + face * 2.55) @ R("X", 90 * face))
        p.add("Gold", box(3.6, 3.5, 0.55), T(gx, top, gz + face * 1.5))
        for sign in (-1, 1):
            p.add("Paper", box(0.14, 1.9, 0.5), T(gx + sign * 1.68, top, gz + face * 0.55))
    for sign in (-1, 1):
        p.add("Paper", box(0.14, 0.5, 1.9), T(gx + sign * 1.68, top + 0.55, gz) @ R("X", 0))
    p.add("Gold", cyl(0.75, 0.5, 8), T(gx, top + 1.6, gz))
    p.add("Gold", spike(0.55, 1.5, 6), T(gx, top + 2.0, gz))
    p.add("Gold", cyl(0.7, 0.5, 8), T(gx, top - 2.1, gz))

    # --- Yunque sobre su tocón: la cara de arriba queda a y = 4 ---
    p.group = "Anvil"
    ax = 1.5
    p.add("Wood", cyl(3.5, 1.25, 12, 3.3), T(ax, 0, 0) @ S(1.25, 1, 1))
    for y in (0.3, 0.95):
        p.add("Black", torus(3.42, 0.14, 14, 4), T(ax, y, 0) @ S(1.25, 1, 1))
    p.add("Stone", frustum(6.4, 3.6, 5.0, 2.8, 0.8), T(ax, 1.65, 0))
    p.add("Stone", frustum(3.6, 2.2, 3.3, 2.0, 0.9), T(ax, 2.5, 0))
    p.add("Stone", frustum(7.4, 2.9, 9.0, 3.3, 1.05), T(ax, 3.475, 0))
    p.add("Gold", box(9.02, 0.2, 3.34), T(ax, 3.1, 0))
    m, shape = limb((ax + 4.3, 3.45, 0), (ax + 8.4, 3.75, 0), 1.05, 0.12, 10)  # el cuerno
    p.add("Stone", shape, m @ S(1.4, 1, 0.55))
    p.add("Stone", box(1.6, 0.6, 3.0), T(ax - 4.6, 3.3, 0))  # el talón
    for face in (-1, 1):
        for k in range(5):
            p.add("Paper", box(0.55, 0.42, 0.12), T(ax - 2.4 + k * 1.2, 3.55, face * 1.62) @ R("Z", 45 if k % 2 else 0))

    # --- Fragua, barril de temple y monolitos de runas ---
    p.group = "Forge"
    fx, fz = -15.0, -9.0
    forge = T(fx, 0, fz) @ R("Y", 28)
    p.add("StoneDark", frustum(10.0, 8.0, 8.6, 6.8, 5.6), forge @ T(0, 2.8, 0))
    p.add("Stone", frustum(9.2, 7.4, 9.6, 7.8, 0.7), forge @ T(0, 5.95, 0))
    p.add("StoneDark", frustum(6.6, 5.2, 3.4, 3.0, 7.0), forge @ T(0, 9.8, -0.6))  # campana
    p.add("StoneDark", cyl(1.6, 9.0, 10, 1.35), forge @ T(0, 13.0, -0.6))  # chimenea
    p.add("Stone", torus(1.6, 0.32, 10, 5), forge @ T(0, 21.7, -0.6))
    p.add("Black", box(5.4, 3.3, 0.6), forge @ T(0, 3.0, 3.75))  # la boca
    p.add("Stone", frame(3.3, 2.7, 0.7), forge @ T(0, 3.0, 3.6) @ R("X", 90) @ S(1, 1, 0.62))
    for k in range(9):
        coal = forge @ T(rng.uniform(-2.1, 2.1), 1.9 + rng.uniform(0, 0.7), 3.7 + rng.uniform(0, 0.9))
        p.add("Paper" if k % 3 else "Black", blob((0.7, 0.55, 0.7), 60 + k, 6, 4, 0.25), coal)
    p.add("Stone", box(6.0, 0.5, 2.2), forge @ T(0, 1.2, 4.6))  # repisa
    # Barril de temple, con agua.
    barrel = T(11.5, 0, 3.5)
    p.add("Wood", lathe([(2.2, 0), (2.65, 1.2), (2.65, 2.6), (2.3, 3.8)], 12), barrel)
    for y in (0.7, 3.1):
        p.add("Black", torus(2.55, 0.15, 14, 4), barrel @ T(0, y, 0))
    p.add("Water", cyl(2.2, 0.1, 12), barrel @ T(0, 3.55, 0))
    # Monolitos en arco, detrás: cada uno con su runa.
    for index, degrees in enumerate((-64, -40, -16, 16, 40, 64)):
        a = math.radians(degrees)
        tall = 10.0 + 4.5 * math.cos(a * 1.4) + rng.uniform(-1, 1)
        stone = T(24 * math.sin(a), 0, -6 - 20 * math.cos(a)) @ R("Y", degrees) @ R("Z", rng.uniform(-5, 5))
        p.add("StoneDark", frustum(3.4, 2.2, 2.2, 1.5, tall), stone @ T(0, tall / 2, 0))
        p.add("StoneDark", frustum(2.2, 1.5, 0.9, 0.7, 1.2), stone @ T(0, tall + 0.6, 0))
        p.add("Paper", box(0.5, tall * 0.42, 0.14), stone @ T(0, tall * 0.56, 0.98))
        lean = 40 if index % 3 else -40
        for k, height in enumerate((0.7, 0.58) if index % 2 else (0.7, 0.44)):
            p.add("Paper", box(1.2, 0.4, 0.14), stone @ T(0.45 if lean > 0 else -0.45, tall * height, 0.98 - 0.04 * k) @ R("Z", lean))


ANIMALS = ["Panda", "RedPanda", "Tiger", "Fox", "Tanuki", "Deer", "Crane"]
PIECES = {
    "Sakura": sakura, "SakuraB": sakura_b, "Maple": maple, "Pine": pine, "Bamboo": bamboo, "Torii": torii,
    "StoneLantern": stone_lantern, "Chochin": chochin, "Pagoda": pagoda, "Bridge": bridge, "Shrine": shrine,
    "Rocks": rocks, "Lotus": lotus, "Bonsai": bonsai, "Fence": fence, "Komainu": komainu,
    "Koinobori": koinobori, "Temple": temple, "Panda": panda, "RedPanda": red_panda, "Tiger": tiger, "Fox": fox, "Tanuki": tanuki,
    "Deer": deer, "Crane": crane, "Fuji": fuji, "GoldSack": gold_sack, "Smith": smith,
}


# Vistas de prueba de las piezas grandes: (altura que se mira, ancho en studs, giro, grados por encima).
VIEWS = {
    "Temple": [(47.0, 150.0, 28.0, 9.0), (30.0, 100.0, 35.0, -22.0), (22.0, 62.0, 12.0, 4.0)],
    "Torii": [(9.0, 34.0, 25.0, 8.0)],
    "Bridge": [(2.5, 34.0, 30.0, 18.0)],
    "Smith": [(11.0, 62.0, 170.0, 8.0), (11.0, 62.0, 215.0, 14.0), (17.0, 16.0, 180.0, 2.0), (4.0, 22.0, 195.0, 20.0)],
    "GoldSack": [(6.0, 32.0, 28.0, 16.0), (6.0, 32.0, 200.0, 12.0), (9.5, 14.0, 10.0, 34.0), (4.0, 50.0, 205.0, 38.0)],
}


def place(name):
    """Dónde va cada pieza en la escena de Blender (solo para verlas juntas): en fila, de 40 en 40."""
    if name == "Fuji":
        return 900.0
    if name == "Temple":
        return 1500.0
    if name in ANIMALS:
        return 1200.0 + ANIMALS.index(name) * 14.0  # los animales, en otra fila más junta
    return list(PIECES).index(name) * 40.0


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


def render_view(path, target, width, angle=25.0, pitch=10.0):
    """Vista de una pieza grande: `target` = (x, altura) del punto que se mira, `width` studs de ancho, girada
    `angle` grados y vista desde `pitch` grados por encima (negativo: desde abajo, para ver los aleros)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_backface_culling = True  # una cara al revés se vería como un agujero
    scene.render.resolution_x = 1300
    scene.render.resolution_y = 1000
    scene.render.filepath = path
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.55, 0.78, 0.95)
    a, b = math.radians(angle), math.radians(pitch)
    look = Vector((target[0], 0, target[1]))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = width
    cam.data.clip_end = 2000
    cam.location = look + Vector((math.sin(a) * math.cos(b), math.cos(a) * math.cos(b), math.sin(b))) * 600
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
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
    import sys
    parser = argparse.ArgumentParser(description="Generar las piezas japonesas o solo las indicadas.")
    parser.add_argument("--output-dir", default=OUT_DIR)
    parser.add_argument("--only", nargs="+", choices=tuple(PIECES))
    parser.add_argument("--skip-previews", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output_dir
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    marker("Axis_Origin", (-40, 0, 0))
    marker("Axis_Up", (-40, 2, 0))
    marker("Axis_Front", (-40, 0, -2))

    for name, build in PIECES.items():
        if args.only and name not in args.only:
            continue
        p = Piece()
        build(p)
        offset = (place(name), 0, 0)
        for group in sorted({group for group, _ in p.parts}):
            marker("%s%s_Origin" % (name, group), offset)
        for (group, role), (verts, faces) in p.parts.items():
            obj = make_object("%s%s_%s" % (name, group, role), role, verts, faces, offset)
            if len(obj.data.polygons) > 9000:
                print("AVISO: %s tiene %d triángulos" % (obj.name, len(obj.data.polygons)))

    os.makedirs(output, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, "mapa_japones.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(output, "mapa_japones.fbx"),
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
    )
    print("Exportadas", len(args.only or PIECES), "piezas")
    if args.skip_previews:
        return
    if args.only:
        for name in args.only:
            if name in VIEWS:
                for index, (center, width, angle, pitch) in enumerate(VIEWS[name]):
                    render_view(os.path.join(output, "%s%d.png" % (name, index + 1)), (place(name), center), width, angle, pitch)
            else:
                render_row(os.path.join(output, name + ".png"), place(name), 50.0, 25.0)
        return
    render_preview(os.path.join(output, "mapa_japones1.png"), (1, 6), 1.0)
    render_preview(os.path.join(output, "mapa_japones2.png"), (7, 12), 0.9)
    render_preview(os.path.join(output, "mapa_japones3.png"), (16, 17), 1.0)
    render_row(os.path.join(output, "mapa_japones4.png"), 1200.0 + 3 * 14.0, 14.0 * 8)
    render_row(os.path.join(output, "mapa_japones5.png"), 1200.0 + 3 * 14.0, 14.0 * 8, 38.0)
    render_row(os.path.join(output, "mapa_japones6.png"), place("Komainu"), 28.0, 25.0)
    for index, (center, width, angle, pitch) in enumerate(VIEWS["Temple"]):
        render_view(os.path.join(output, "mapa_japones%d.png" % (7 + index)), (place("Temple"), center), width, angle, pitch)


if __name__ == "__main__":
    main()
