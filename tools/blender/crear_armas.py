# Crea en Blender los modelos de las armas de Config.Swords (menos las que ya tienen malla propia, como el
# Colmillo astral) y los exporta a un solo .fbx para importarlo en Roblox Studio:
#   blender -b --python tools/blender/crear_armas.py
# Deja armas.blend y armas.fbx en Documents\Roblox\modelos. En Studio: Archivo > Importar 3D con armas.fbx y
# guardar el modelo importado (clic derecho > Guardar en archivo) como src/shared/WeaponMeshes.rbxm.
#
# Cada arma son varios objetos "W<índice>_<Papel>", uno por color: el juego (shared/SwordModel) les pone el
# color y el material según el papel (Blade = color del arma, Edge = filo claro, Dark = veta, Trim = adornos,
# Grip = cuero, Wood = madera, Gem = gema, Glow = luz, Cloth = tela). "W<índice>_Origin" marca el centro de
# la empuñadura, y Axis_Origin / Axis_Up / Axis_Front dicen al juego la escala y los ejes de la importación.
# Medidas en studs y en ejes de la empuñadura del juego: el arma sube por +Y, es ancha en Z y fina en X,
# -Z es hacia donde mira el jugador (el filo del hacha, por ejemplo).
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos")

ROLE_COLORS = {  # solo para verlo en Blender; en el juego manda SwordModel
    "Blade": (0.55, 0.75, 1, 1), "Edge": (0.9, 0.95, 1, 1), "Dark": (0.25, 0.3, 0.45, 1),
    "Trim": (0.95, 0.75, 0.25, 1), "Grip": (0.3, 0.18, 0.1, 1), "Wood": (0.45, 0.3, 0.17, 1),
    "Gem": (1, 0.3, 0.6, 1), "Glow": (0.6, 1, 1, 1), "Cloth": (0.8, 0.2, 0.2, 1), "Marker": (1, 0, 1, 1),
}


# ---------- Geometría (ejes del juego; se pasan a Blender al final) ----------

def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def R(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def box(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    verts = [(a, b, c) for a in (-x, x) for b in (-y, y) for c in (-z, z)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces


def cylinder(r, h, n=12, r2=None):
    """A lo largo de Y, centrado. r2 = radio de arriba (cono truncado)."""
    r2 = r if r2 is None else r2
    verts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        verts.append((r * math.cos(a), -h / 2, r * math.sin(a)))
        verts.append((r2 * math.cos(a), h / 2, r2 * math.sin(a)))
    faces = [(2 * i, 2 * ((i + 1) % n), 2 * ((i + 1) % n) + 1, 2 * i + 1) for i in range(n)]
    faces.append(tuple(2 * i for i in range(n)))
    faces.append(tuple(2 * i + 1 for i in range(n)))
    return verts, faces


def cone(r, h, n=10):
    """Base abajo, punta arriba (Y)."""
    verts = [(r * math.cos(2 * math.pi * i / n), -h / 2, r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    verts.append((0, h / 2, 0))
    faces = [(i, (i + 1) % n, n) for i in range(n)] + [tuple(range(n))]
    return verts, faces


def sphere(r, n=10, rings=6):
    verts = [(0, -r, 0)]
    for j in range(1, rings):
        phi = math.pi * j / rings - math.pi / 2
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append((r * math.cos(phi) * math.cos(a), r * math.sin(phi), r * math.cos(phi) * math.sin(a)))
    verts.append((0, r, 0))
    top = len(verts) - 1
    faces = [(0, 1 + (i + 1) % n, 1 + i) for i in range(n)]
    for j in range(rings - 2):
        a, b = 1 + j * n, 1 + (j + 1) * n
        faces += [(a + i, a + (i + 1) % n, b + (i + 1) % n, b + i) for i in range(n)]
    last = 1 + (rings - 2) * n
    faces += [(last + i, last + (i + 1) % n, top) for i in range(n)]
    return verts, faces


def gem(r, h=None, n=6):
    """Bipirámide (gema tallada) a lo largo de Y."""
    h = h or r * 2
    verts = [(r * math.cos(2 * math.pi * i / n), 0, r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    verts += [(0, h / 2, 0), (0, -h / 2, 0)]
    faces = [(i, (i + 1) % n, n) for i in range(n)] + [((i + 1) % n, i, n + 1) for i in range(n)]
    return verts, faces


def torus(R_, r, n=18, m=6):
    """Anillo alrededor del eje Y."""
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


def plate(points, t):
    """Placa: polígono en el plano (y, z) con grosor 2t en X (puede ser cóncavo)."""
    n = len(points)
    verts = [(t, y, z) for y, z in points] + [(-t, y, z) for y, z in points]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return verts, faces


def blade(profile, t, tip_y, tip_c=0.0):
    """Hoja en rombo: profile = [(y, media anchura, desvío en Z)], grosor t en el centro, punta en tip_y."""
    verts, faces = [], []
    for y, w, c in profile:
        th = min(t, max(w, 0.02) * 0.7)
        verts += [(0, y, c - w), (th, y, c), (0, y, c + w), (-th, y, c)]
    for k in range(len(profile) - 1):
        a, b = 4 * k, 4 * (k + 1)
        faces += [(a + i, a + (i + 1) % 4, b + (i + 1) % 4, b + i) for i in range(4)]
    faces.append((3, 2, 1, 0))
    verts.append((0, tip_y, tip_c))
    apex = len(verts) - 1
    last = 4 * (len(profile) - 1)
    faces += [(last + i, last + (i + 1) % 4, apex) for i in range(4)]
    return verts, faces


def mirror_z(points):
    return [(y, -z) for y, z in reversed(points)]


# ---------- Perfiles de hoja: lista de (u de 0 a 1 a lo largo, anchura relativa, desvío en Z / largo) ----------

def profile(shape, n=8):
    rows = []
    if shape == "straight":
        rows = [(u, 1.0, 0) for u in (0, 0.3, 0.6, 0.84)]
    elif shape == "broad":
        rows = [(0, 1.15, 0), (0.5, 1.25, 0), (0.88, 1.2, 0)]
    elif shape == "leaf":
        rows = [(u, 0.75 + 0.4 * math.sin(math.pi * u * 1.1), 0) for u in (0, 0.2, 0.4, 0.6, 0.78)]
    elif shape == "curved":
        rows = [(u, 0.9 - 0.25 * u, 0.12 * u * u) for u in (0, 0.2, 0.4, 0.6, 0.8, 0.9)]
    elif shape == "fang":
        rows = [(u, 1.05 - 0.6 * u, 0.2 * u * u) for u in (0, 0.2, 0.4, 0.6, 0.8)]
    elif shape == "flame":
        rows = [(u, 0.85 + 0.25 * math.sin(u * math.pi * 7), 0) for u in [i / 24 * 0.86 for i in range(25)]]
    elif shape == "crystal":
        rows = [(0, 0.6, 0), (0.15, 1.15, 0), (0.3, 0.8, 0), (0.5, 1.25, 0), (0.65, 0.85, 0), (0.8, 1.05, 0)]
    elif shape == "serrated":
        rows = [(u, 1.0 if i % 2 == 0 else 1.3, 0) for i, u in enumerate([i / 14 * 0.84 for i in range(15)])]
    elif shape == "tapered":
        rows = [(u, 1.0 - 0.45 * u, 0) for u in (0, 0.4, 0.8)]
    return rows


def blade_layers(w, shape, base, length, width, tip=1.0, core_shape=None):
    """Hoja con cuerpo (Blade) y filo más ancho y fino (Edge), como en SwordModel."""
    rows = profile(shape)
    end_c = rows[-1][2] * length * 1.08
    edge = [(base + u * length, width * k, c * length) for u, k, c in rows]
    w.add("Edge", *blade(edge, 0.04, base + length * tip, end_c))
    core_rows = profile(core_shape or ("straight" if shape == "serrated" else shape))
    core = [(base + u * length, width * 0.62 * k, c * length) for u, k, c in core_rows]
    w.add("Blade", *blade(core, 0.12, base + length * tip * 0.97, end_c))


# ---------- Un arma = varios objetos por papel ----------

class Weapon:
    def __init__(self, index):
        self.index = index
        self.parts = {}

    def add(self, role, verts, faces, m=None):
        m = m or Matrix.Identity(4)
        verts_, faces_ = self.parts.setdefault(role, ([], []))
        base = len(verts_)
        verts_.extend(tuple(m @ Vector(v)) for v in verts)
        faces_.extend(tuple(base + i for i in f) for f in faces)


def grip(w, pommel="ball", trim="Trim"):
    w.add("Grip", *cylinder(0.16, 1.2))
    for y in (-0.32, 0, 0.32):
        w.add("Grip", *cylinder(0.19, 0.1), T(0, y, 0))
    if pommel == "ball":
        w.add(trim, *sphere(0.25), T(0, -0.78, 0))
    elif pommel == "gem":
        w.add(trim, *cylinder(0.2, 0.14), T(0, -0.66, 0))
        w.add("Gem", *gem(0.22, 0.6), T(0, -0.95, 0))
    elif pommel == "spike":
        w.add(trim, *cylinder(0.22, 0.16), T(0, -0.68, 0))
        w.add(trim, *cone(0.2, 0.6), T(0, -1.05, 0) @ R("X", 180))
    elif pommel == "ring":
        w.add(trim, *torus(0.22, 0.07), T(0, -0.85, 0) @ R("X", 90))


def guard(w, style, G, y=0.72):
    if style == "bar":
        w.add("Trim", *box(0.34, 0.24, G), T(0, y, 0))
        for s in (-1, 1):
            w.add("Trim", *box(0.42, 0.36, 0.25), T(0, y, s * G / 2))
    elif style == "curved":
        for i in range(-3, 4):
            z = i / 3 * G / 2
            w.add("Trim", *box(0.32, 0.2, G / 6.5), T(0, y + 0.3 * (i / 3) ** 2, z) @ R("X", -i * 12))
        for s in (-1, 1):
            w.add("Trim", *sphere(0.15, 8, 5), T(0, y + 0.32, s * G / 2))
    elif style == "wings":
        w.add("Trim", *box(0.36, 0.3, 0.7), T(0, y, 0))
        wing = [(y - 0.1, 0.3), (y + 0.25, 0.3), (y + 0.75, G * 0.55), (y + 0.35, G * 0.5), (y + 0.15, G * 0.65), (y - 0.15, G * 0.45)]
        w.add("Trim", *plate(wing, 0.08))
        w.add("Trim", *plate(mirror_z(wing), 0.08))
    elif style == "disk":
        w.add("Trim", *cylinder(G / 2.6, 0.16, 16), T(0, y, 0))
        w.add("Dark", *torus(G / 2.6, 0.06, 16), T(0, y, 0))
    elif style == "crescent":
        moon = [(y - 0.15, 0), (y + 0.05, G * 0.3), (y + 0.55, G * 0.55), (y + 0.2, G * 0.6), (y - 0.1, G * 0.45)]
        w.add("Trim", *plate(moon + mirror_z(moon)[1:], 0.09))
    elif style == "ring":
        w.add("Trim", *box(0.3, 0.22, G * 0.8), T(0, y, 0))
        w.add("Trim", *torus(0.45, 0.08, 16), T(0, y, 0) @ R("Z", 90))
    elif style == "infinity":
        w.add("Trim", *box(0.3, 0.22, 0.6), T(0, y, 0))
        for s in (-1, 1):
            w.add("Trim", *torus(G * 0.22, 0.08, 16), T(0, y, s * G * 0.25) @ R("Z", 90))
    elif style == "split":
        for s in (-1, 1):
            w.add("Trim", *box(0.3, 0.22, G * 0.45), T(0, y + 0.1, s * G * 0.3) @ R("X", s * -20))
        w.add("Trim", *box(0.36, 0.34, 0.5), T(0, y, 0))


def star_guard(w, G, y=0.72):
    w.add("Trim", *sphere(0.3, 10, 6), T(0, y, 0))
    for i in range(8):
        w.add("Trim", *cone(0.12, G * 0.42, 6), T(0, y, 0) @ R("X", 45 * i + 22.5) @ T(0, G * 0.21 + 0.15, 0))


def rings(w, base, length, count, radius, role="Glow"):
    for i in range(count):
        y = base + length * (0.35 + 0.5 * i / max(count - 1, 1))
        w.add(role, *torus(radius * (1 - 0.25 * i / max(count, 1)), 0.05, 20), T(0, y, 0) @ R("X", 12 * (1 if i % 2 else -1)))


def shards(w, base, length, width, count=4, role="Glow"):
    for i in range(count):
        s = 1 if i % 2 == 0 else -1
        y = base + length * (0.2 + 0.6 * i / max(count - 1, 1))
        w.add(role, *gem(0.12, 0.6, 4), T(0, y, s * (width + 0.45)) @ R("X", s * -18))


def halo(w, y, radius, role="Glow"):
    w.add(role, *torus(radius, 0.06, 24), T(0, y, 0) @ R("Z", 90))


BLADE_BASE = 0.84


def make_sword(w, s, L):
    """Espada (y cada hoja de las dobles). s = especificación de crear_todas."""
    grip(w, s.get("pommel", "ball"))
    G = s.get("guard_len", 1.6)
    if s.get("guard") == "star":
        star_guard(w, G)
    else:
        guard(w, s.get("guard", "bar"), G)
    if s.get("guard_gem"):
        w.add("Gem", *gem(0.2, 0.5), T(0, 0.72, -0.2) @ R("X", 90))
        w.add("Gem", *gem(0.2, 0.5), T(0, 0.72, 0.2) @ R("X", 90))
    width = s.get("width", 0.33)
    blade_layers(w, s.get("shape", "straight"), BLADE_BASE, L, width)
    if s.get("fuller"):
        w.add("Dark", *box(0.27, L * 0.6, width * 0.2), T(0, BLADE_BASE + L * 0.36, 0))
    if s.get("rings"):
        rings(w, BLADE_BASE, L, s["rings"], width + 0.45)
    if s.get("shards"):
        shards(w, BLADE_BASE, L, width, s["shards"])
    if s.get("halo"):
        halo(w, 0.95, s["halo"])


def axe_head(style, k, y):
    """Polígonos (cuerpo, filo) de la cabeza del hacha hacia -Z, en (y, z)."""
    if style == "bearded":
        body = [(0.4, -0.15), (0.5, -0.6), (0.95, -1.2), (0.55, -1.32), (0.0, -1.3), (-0.8, -1.25), (-1.4, -1.0), (-0.9, -0.75), (-0.4, -0.15)]
        edge = [(0.95, -1.2), (0.55, -1.32), (0.0, -1.3), (-0.8, -1.25), (-1.4, -1.0), (-1.55, -1.12), (-0.85, -1.42), (0.0, -1.48), (0.6, -1.5), (1.1, -1.32)]
    elif style == "jagged":
        body = [(0.4, -0.15), (0.6, -0.7), (1.1, -1.25), (0.7, -1.35), (0.3, -1.25), (0, -1.4), (-0.3, -1.25), (-0.7, -1.35), (-1.1, -1.25), (-0.6, -0.7), (-0.4, -0.15)]
        edge = [(1.1, -1.25), (1.35, -1.55), (0.7, -1.35), (0.45, -1.62), (0.3, -1.25), (0, -1.72), (-0.3, -1.25), (-0.45, -1.62), (-0.7, -1.35), (-1.35, -1.55), (-1.1, -1.25)]
    elif style == "hook":
        body = [(0.35, -0.15), (0.5, -0.6), (1.15, -1.05), (1.35, -0.75), (1.2, -1.4), (0, -1.45), (-1.2, -1.4), (-1.35, -0.75), (-1.15, -1.05), (-0.5, -0.6), (-0.35, -0.15)]
        edge = [(1.2, -1.4), (1.42, -1.55), (0, -1.62), (-1.42, -1.55), (-1.2, -1.4), (0, -1.45)]
    elif style == "star":
        body = []
        for i in range(10):
            a = math.pi * i / 5 + math.pi / 2
            r = 1.15 if i % 2 == 0 else 0.5
            body.append((math.sin(a) * r, -0.85 + math.cos(a) * r))
        edge = [(0, -2.0), (0.32, -1.25), (-0.32, -1.25)]
    else:  # crescent
        body = [(0.35, -0.15), (0.55, -0.7), (1.0, -1.25), (0.6, -1.35), (0, -1.4), (-0.6, -1.35), (-1.0, -1.25), (-0.55, -0.7), (-0.35, -0.15)]
        edge = [(1.0, -1.25), (0.6, -1.35), (0, -1.4), (-0.6, -1.35), (-1.0, -1.25), (-1.15, -1.4), (-0.6, -1.52), (0, -1.58), (0.6, -1.52), (1.15, -1.4)]
    scale = lambda pts: [(y + a * k, b * k) for a, b in pts]
    return scale(body), scale(edge)


def make_axe(w, s, L):
    grip(w, s.get("pommel", "ball"))
    shaft = L + 1.2
    bottom, top = -0.9, -0.9 + shaft
    w.add("Wood", *cylinder(0.12, shaft, 10), T(0, bottom + shaft / 2, 0))
    k = 0.9 + shaft * 0.06
    y = top - 0.8 * k
    w.add("Trim", *box(0.42, 1.0 * k, 0.42), T(0, y, 0))
    w.add("Trim", *cone(0.16, 0.6 * k, 6), T(0, top + 0.3 * k, 0))
    body, edge = axe_head(s.get("head", "crescent"), k, y)
    sides = [1, -1] if s.get("double") else [1]
    for side in sides:
        flip = (lambda pts: [(a, -b) for a, b in reversed(pts)]) if side == -1 else (lambda pts: pts)
        w.add("Blade", *plate(flip(body), 0.09 * k))
        w.add("Edge", *plate(flip(edge), 0.045 * k))
    if not s.get("double"):
        w.add("Trim", *cone(0.16 * k, 0.7 * k, 6), T(0, y, 0.2) @ R("X", 90))
    if s.get("gem"):
        w.add("Gem", *gem(0.2 * k, 0.5 * k), T(0, y, 0) @ R("Z", 90))
    if s.get("halo"):
        halo(w, y, s["halo"] * k)
    if s.get("shards"):
        shards(w, y - 1.2 * k, 2.4 * k, 1.0 * k, s["shards"])


def make_hammer(w, s, L):
    grip(w, s.get("pommel", "ball"))
    shaft = L + 1.4
    bottom, top = -0.9, -0.9 + shaft
    w.add("Wood", *cylinder(0.13, shaft, 10), T(0, bottom + shaft / 2, 0))
    k = 0.85 + shaft * 0.08
    y = top - 0.35 * k
    head = s.get("head", "block")
    w.add("Trim", *box(0.5, 0.9 * k, 0.5), T(0, y, 0))
    if head == "crude":
        w.add("Blade", *box(1.0 * k, 1.1 * k, 2.1 * k), T(0, y, 0) @ R("Y", 4) @ R("X", 3))
        w.add("Blade", *box(0.85 * k, 0.95 * k, 0.6 * k), T(0.05, y + 0.08, -0.85 * k) @ R("Z", 6))
        w.add("Dark", *box(1.05 * k, 0.18 * k, 1.4 * k), T(0, y - 0.3 * k, 0))
    elif head in ("cylinder", "doom"):
        r = 0.62 * k if head == "cylinder" else 0.78 * k
        length = 2.2 * k if head == "cylinder" else 2.6 * k
        w.add("Blade", *cylinder(r, length, 14), T(0, y, 0) @ R("X", 90))
        for side in (-1, 1):
            w.add("Trim", *cylinder(r * 1.12, 0.3 * k, 14), T(0, y, side * length / 2) @ R("X", 90))
            w.add("Dark", *torus(r * 1.02, 0.07 * k, 16), T(0, y, side * length * 0.25) @ R("X", 90))
        if head == "doom":
            for i in range(6):
                w.add("Trim", *cone(0.16 * k, 0.8 * k, 6), T(0, y, 0) @ R("Z", 60 * i) @ T(0, r + 0.3 * k, 0))
            halo(w, y, 1.9 * k)
    elif head == "crystal":
        w.add("Blade", *box(0.9 * k, 1.0 * k, 1.9 * k), T(0, y, 0))
        for i, (dy, dz, rot) in enumerate([(0.3, -1.1, 70), (-0.3, -1.05, 110), (0, -1.25, 90), (0.35, 1.0, -70), (-0.3, 1.05, -110), (0.6, 0.2, 10)]):
            role = "Edge" if i % 2 else "Blade"
            w.add(role, *gem(0.26 * k, 1.1 * k, 5), T(0, y + dy * k, dz * k) @ R("X", rot))
    else:  # block
        w.add("Blade", *box(1.0 * k, 1.1 * k, 2.2 * k), T(0, y, 0))
        for side in (-1, 1):
            w.add("Trim", *box(1.12 * k, 1.22 * k, 0.32 * k), T(0, y, side * 1.1 * k))
        w.add("Dark", *box(1.06 * k, 0.2 * k, 1.5 * k), T(0, y + 0.3 * k, 0))
    if s.get("fins"):  # aletas de rayo encima de la cabeza
        bolt = [(0, -0.5), (0.5, -0.15), (0.35, -0.3), (0.85, 0.1), (0.4, -0.05), (0.55, 0.2), (0.1, -0.2)]
        for side in (-1, 1):
            w.add("Glow", *plate([(y + 0.5 * k + a * k, side * (0.5 + b) * k) for a, b in bolt], 0.06 * k))
    if s.get("spike"):
        w.add("Trim", *cone(0.2 * k, 0.9 * k, 6), T(0, y + 0.95 * k, 0))
    if s.get("gem"):
        w.add("Gem", *gem(0.25 * k, 0.55 * k), T(-0.55 * k, y, 0) @ R("Z", 90))
        w.add("Gem", *gem(0.25 * k, 0.55 * k), T(0.55 * k, y, 0) @ R("Z", 90))
    if s.get("rings"):
        for i in range(s["rings"]):
            w.add("Glow", *torus(1.35 * k + 0.25 * i, 0.05, 22), T(0, y, 0) @ R("X", 90) @ R("Z", 25 * (i + 1)))


def make_spear(w, s, L):
    grip(w, "ball")
    shaft = L
    bottom, top = -0.3 * shaft, 0.7 * shaft
    w.add("Wood", *cylinder(0.12, shaft, 10), T(0, bottom + shaft / 2, 0))
    w.add("Trim", *sphere(0.2, 8, 5), T(0, bottom, 0))
    w.add("Cloth", *cone(0.22, 0.6, 8), T(0, top - 0.6, 0) @ R("X", 180))
    w.add("Trim", *cylinder(0.21, 0.35, 10), T(0, top, 0))
    tip = s.get("tip", "leaf")
    base = top + 0.15
    if tip == "lightning":
        bolt = [(0, -0.12), (0.7, -0.35), (0.6, -0.05), (1.4, -0.3), (1.3, 0.0), (2.4, 0.0), (1.55, 0.25), (1.65, -0.02), (0.85, 0.22), (0.95, -0.02), (0.2, 0.18), (0, 0.12)]
        w.add("Blade", *plate([(base + a, b) for a, b in bolt], 0.09))
        w.add("Edge", *plate([(base + a * 1.05 - 0.05, b * 1.25) for a, b in bolt], 0.04))
    elif tip == "trident":
        w.add("Trim", *box(0.26, 0.25, 1.5), T(0, base + 0.1, 0))
        blade_layers(w, "straight", base + 0.2, 1.6, 0.17)
        for side in (-1, 1):
            w.add("Trim", *box(0.22, 0.6, 0.22), T(0, base + 0.45, side * 0.7))
            w.add("Blade", *cone(0.13, 1.0, 6), T(0, base + 1.2, side * 0.7))
            w.add("Edge", *cone(0.07, 0.4, 6), T(0, base + 0.85, side * 0.88) @ R("X", side * 70))
    else:
        length = {"leaf": 1.8, "broadleaf": 2.0, "nova": 2.2, "crystal": 2.8}.get(tip, 1.8)
        shape = {"crystal": "crystal"}.get(tip, "leaf")
        blade_layers(w, shape, base, length, 0.3 if tip != "broadleaf" else 0.4)
        if tip == "broadleaf":
            wing = [(base - 0.05, 0.15), (base + 0.15, 0.2), (base + 0.55, 0.8), (base + 0.1, 0.55)]
            w.add("Trim", *plate(wing, 0.07))
            w.add("Trim", *plate(mirror_z(wing), 0.07))
        if tip == "nova":
            for i in range(6):
                w.add("Glow", *cone(0.07, 0.8, 5), T(0, base + 0.5, 0) @ R("X", 60 * i + 30) @ T(0, 0.55, 0))
            halo(w, base + 0.5, 0.75)
        if tip == "crystal":
            w.add("Glow", *sphere(0.32, 12, 7), T(0, base - 0.45, 0))
            for i in range(2):
                w.add("Glow", *torus(0.6 + 0.25 * i, 0.05, 20), T(0, base - 0.45, 0) @ R("X", 70) @ R("Y", 60 * i))


# Diseño de cada arma por su índice en Config.Swords (mismo orden; las de malla propia no van).
SPECS = {
    1: dict(kind="sword", L=3.0, shape="broad", guard="bar", guard_len=1.2, width=0.34),  # madera
    2: dict(kind="sword", L=3.4, shape="broad", guard="bar", guard_len=1.3, width=0.36),  # piedra
    3: dict(kind="sword", L=3.8, shape="straight", guard="bar", guard_len=1.5, fuller=True),  # hierro
    4: dict(kind="sword", L=4.3, shape="straight", guard="curved", guard_len=1.7, fuller=True),  # acero
    5: dict(kind="sword", L=4.8, shape="leaf", guard="wings", guard_len=1.9, pommel="gem", guard_gem=True),  # oro
    6: dict(kind="sword", L=5.4, shape="crystal", guard="split", guard_len=1.9, pommel="gem", guard_gem=True),  # diamante
    7: dict(kind="sword", L=6.2, shape="flame", guard="ring", guard_len=1.8, pommel="gem", guard_gem=True),  # plasma
    8: dict(kind="sword", L=7.5, shape="curved", guard="disk", guard_len=1.6, pommel="spike", width=0.3),  # vacío
    9: dict(kind="sword", L=7.8, shape="broad", guard="star", guard_len=2.0, pommel="gem", fuller=True),  # solar
    10: dict(kind="sword", L=8.0, shape="curved", guard="crescent", guard_len=2.0, pommel="gem", shards=4),  # cometa
    11: dict(kind="sword", L=8.2, shape="leaf", guard="wings", guard_len=2.1, pommel="gem", rings=1, guard_gem=True),  # nebulosa
    12: dict(kind="sword", L=8.4, shape="straight", guard="star", guard_len=2.1, pommel="gem", rings=2, fuller=True),  # galáctica
    13: dict(kind="sword", L=8.6, shape="serrated", guard="split", guard_len=2.1, pommel="spike", shards=6),  # cuántica
    14: dict(kind="sword", L=8.8, shape="crystal", guard="ring", guard_len=2.0, pommel="gem", halo=1.1, guard_gem=True),  # cosmos
    15: dict(kind="sword", L=9.0, shape="flame", guard="wings", guard_len=2.5, pommel="gem", halo=1.3, rings=2, guard_gem=True),  # origen
    16: dict(kind="sword", L=9.5, shape="serrated", guard="infinity", guard_len=2.4, pommel="gem", shards=6, rings=1),  # infinito
    17: dict(kind="axe", L=3.5, head="crescent"),  # leñador
    18: dict(kind="sword", L=2.4, shape="tapered", guard="bar", guard_len=0.9, width=0.28),  # dagas
    19: dict(kind="spear", L=9.0, tip="leaf"),  # caza
    20: dict(kind="axe", L=4.5, head="bearded"),  # guerra
    21: dict(kind="sword", L=3.6, shape="curved", guard="ring", guard_len=1.1, width=0.3),  # sables
    22: dict(kind="spear", L=11.0, tip="broadleaf"),  # jade
    23: dict(kind="axe", L=5.5, head="jagged", double=True, gem=True),  # volcánica
    24: dict(kind="sword", L=5.0, shape="fang", guard="disk", guard_len=1.3, pommel="spike", width=0.34),  # eclipse
    25: dict(kind="spear", L=13.0, tip="lightning"),  # rayo
    26: dict(kind="hammer", L=3.2, head="crude"),  # mazo de piedra
    27: dict(kind="hammer", L=3.8, head="block", spike=True),  # guerra
    28: dict(kind="hammer", L=4.4, head="block", fins=True, gem=True),  # trueno
    29: dict(kind="hammer", L=5.0, head="cylinder", spike=True, gem=True),  # magmático
    30: dict(kind="hammer", L=5.4, head="crystal"),  # glacial
    31: dict(kind="hammer", L=5.8, head="cylinder", gem=True, rings=2),  # cósmico
    32: dict(kind="hammer", L=6.2, head="doom", gem=True, rings=1),  # fin del mundo
    33: dict(kind="axe", L=6.0, head="hook", double=True, gem=True),  # abismo
    34: dict(kind="sword", L=5.4, shape="fang", guard="crescent", guard_len=1.4, pommel="spike", width=0.32, shards=2),  # colmillos
    35: dict(kind="spear", L=14.0, tip="trident"),  # abisal
    36: dict(kind="axe", L=6.4, head="star", double=True, gem=True, shards=4),  # estelar
    37: dict(kind="sword", L=5.8, shape="flame", guard="wings", guard_len=1.5, pommel="gem", width=0.3),  # aurora
    38: dict(kind="spear", L=15.0, tip="nova"),  # nova
    39: dict(kind="axe", L=6.8, head="crescent", double=True, gem=True, halo=1.7),  # amanecer
    40: dict(kind="sword", L=6.2, shape="leaf", guard="star", guard_len=1.5, pommel="gem", rings=2, width=0.3),  # alba eterna
    41: dict(kind="spear", L=16.0, tip="crystal"),  # big bang
}

BUILDERS = {"sword": make_sword, "axe": make_axe, "hammer": make_hammer, "spear": make_spear}


# ---------- Pasar a Blender y exportar ----------

def to_blender(v):
    # Ejes del juego (X, Y arriba, Z atrás) -> Blender (Z arriba), de forma que el FBX (Y arriba, -Z al frente)
    # salga otra vez en ejes del juego.
    return (v[0], -v[2], v[1])


def material(role):
    mat = bpy.data.materials.get(role) or bpy.data.materials.new(role)
    mat.diffuse_color = ROLE_COLORS[role]
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


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    # Ejes y escala de referencia para el juego (a 2 studs del origen, hacia arriba y hacia delante).
    marker("Axis_Origin", (-8, 0, 0))
    marker("Axis_Up", (-8, 2, 0))
    marker("Axis_Front", (-8, 0, -2))

    for index, spec in SPECS.items():
        w = Weapon(index)
        BUILDERS[spec["kind"]](w, spec, spec["L"])
        # En fila a lo largo de X, de 10 en 10 (sólo para verlas juntas en Blender).
        offset = (((index - 1) % 10) * 4.0, 0, ((index - 1) // 10) * 22.0)
        marker("W%02d_Origin" % index, offset)
        for role, (verts, faces) in w.parts.items():
            make_object("W%02d_%s" % (index, role), role, verts, faces, offset)

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "armas.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "armas.fbx"),
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
    )
    print("Exportadas", len(SPECS), "armas y", len(bpy.data.objects), "objetos a", OUT_DIR)


main()
