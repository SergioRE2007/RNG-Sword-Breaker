# Crea en Blender las piezas del Jefe del mundo (Rey Slime) y las exporta a un .fbx para subirlo a Roblox:
#   blender -b --factory-startup --python tools/blender/crear_jefe.py [-- --only BossPortal]
# Deja jefe.blend, jefe.fbx y las vistas jefe_<Pieza><n>.png en Documents\Roblox\modelos. El .fbx se sube como
# modelo del grupo con Open Cloud (tools/blender/subir_modelo.mjs), se carga en Studio con game:GetObjects y sus
# MeshParts se vuelcan a src/shared/BossMeshes.rbxmx (PropModel las lee como las del mapa japonés).
#
# Piezas (medidas en studs, Y arriba, -Z al frente, origen en el suelo de cada una):
#   BossPortal  — portal del hub: arco de dovelas con runas, el Rey Slime pequeño con su corona encima, baba que cae,
#                 dos pilonos con cristal y peana con escalones. El disco de energía sigue siendo una Part.
#   BossIsland  — la isla flotante de la arena, de radio 80 (Config.WorldBoss.ArenaRadius): roca por debajo con
#                 estalactitas, cristales y baba, borde de hierba y rocas sueltas. Grupos: "" (la roca),
#                 "Floor" (baldosas en anillos alrededor del charco) y "Wall" (muralla con almenas y abertura en +Z).
#   BossPillar  — columna estriada con capitel, baba por encima y la cuna dorada del cristal.
#   BossCrystal — el cristal que flota encima de cada columna (una sola malla: lo mueve client/WorldBossFx).
#   BossThrone  — trono gigante del rey al fondo de la arena, sobre su peñasco.
# Usa la geometría y la exportación de crear_mapa_japones.py; los papeles nuevos (Slime, Crystal) los colorea PropModel.
import math
import os
import random
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crear_mapa_japones as jp  # noqa: E402
from crear_mapa_japones import T, R, S, box, frustum, lathe, sphere, cyl, spike, torus, blob, Piece  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

jp.ROLE_COLORS.update({"Slime": (0.47, 0.84, 0.36), "Crystal": (0.68, 0.5, 1.0)})

ARENA = 80.0  # radio de la arena (ArenaRadius)
PUDDLE = 24.4  # radio del charco del centro (Config.WorldBoss.Size.X * 0.7)
WALL_IN, WALL_OUT, WALL_H = 83.0, 85.6, 2.8
ISLAND = 100.0  # radio de la isla por arriba
PORTAL_MID = 9.5  # altura del centro del aro (ringRadius + 2 en WorldBossArena.buildPortal)


# ---------- Formas ----------

def loft(loops):
    """Sólido cerrado que une anillos de puntos del mismo tamaño, en orden (tapas en el primero y el último)."""
    k = len(loops[0])
    verts = [tuple(v) for loop in loops for v in loop]
    faces = [tuple(reversed(range(k))), tuple(k * (len(loops) - 1) + j for j in range(k))]
    for i in range(len(loops) - 1):
        for j in range(k):
            j2 = (j + 1) % k
            faces.append((k * i + j, k * i + j2, k * (i + 1) + j2, k * (i + 1) + j))
    return verts, faces


def wedge(r0, r1, a0, a1, y0, y1, bevel=0.0, steps=1):
    """Trozo de anillo tumbado (baldosa, tramo de muro): radios r0..r1, ángulos a0..a1 en radianes, de y0 a y1, con
    la cara de arriba biselada. `steps` parte el arco para que siga la curva."""
    def loop(y, k):
        out = []
        aa0, aa1 = a0 + k / max(r0, 1), a1 - k / max(r0, 1)
        for i in range(steps + 1):
            a = aa0 + (aa1 - aa0) * i / steps
            out.append(((r1 - k) * math.cos(a), y, (r1 - k) * math.sin(a)))
        for i in range(steps, -1, -1):
            a = aa0 + (aa1 - aa0) * i / steps
            out.append(((r0 + k) * math.cos(a), y, (r0 + k) * math.sin(a)))
        return out
    loops = [loop(y0, 0)]
    if bevel > 0:
        loops.append(loop(y1 - bevel, 0))
    loops.append(loop(y1, bevel))
    return loft(loops)


def voussoir(r0, r1, a0, a1, depth, mid, bevel=0.2):
    """Dovela de un arco de pie (en el plano XY, centrado en y=mid), con los bordes de las dos caras biselados."""
    def loop(z, k):
        aa0, aa1 = a0 + k / r0, a1 - k / r0
        pts = [(r0 + k, aa0), (r1 - k, aa0), (r1 - k, aa1), (r0 + k, aa1)]
        return [(r * math.cos(a), mid + r * math.sin(a), z) for r, a in pts]
    d = depth / 2
    return loft([loop(-d, bevel), loop(-d + bevel, 0), loop(d - bevel, 0), loop(d, bevel)])


def drip(r, length, n=9):
    """Gota de baba colgando: pegada arriba (y=0), cuello fino y gota gorda abajo (y=-length). length >= 3 r."""
    L = max(length, 3 * r)
    return lathe([(0, -L), (0.65 * r, -L + 0.22 * r), (r, -L + 0.8 * r), (0.82 * r, -L + 1.55 * r),
                  (0.36 * r, -0.45 * L), (0.5 * r, -0.12 * L), (0.95 * r, 0), (0, 0.45 * r)], n)


def gem(r, h, n=6, waist=0.62):
    """Cristal de dos puntas: la de abajo en y=0 y la de arriba en y=h."""
    return lathe([(0, 0), (r, h * (1 - waist) * 0.55), (r * 0.92, h * waist), (0, h)], n)


def toward(direction):
    """Giro que lleva el eje Y del juego a `direction`."""
    return Vector(direction).normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()


def slime_eyes(p, x, y, z, size=1.0, facing=-1):
    """Ojos de gominola (negro con brillo blanco) mirando hacia `facing` en Z."""
    for s in (-1, 1):
        p.add("Black", sphere(0.42 * size, 8, 5), T(x + s * 1.05 * size, y, z) @ S(1, 1.25, 0.6))
        p.add("White", sphere(0.14 * size, 6, 4), T(x + s * 1.05 * size + 0.12 * size, y + 0.2 * size, z + facing * 0.24 * size))


def crown(p, y, r, h, points=5, gem_role="Red", z=0.0, x=0.0):
    """Corona del rey: aro dorado con picos y una gema en cada punta y otra en la frente."""
    p.add("Gold", lathe([(r, 0), (r * 1.06, h * 0.12), (r * 1.06, h * 0.42), (r * 0.98, h * 0.5)], 14), T(x, y, z))
    for i in range(points):
        a = 2 * math.pi * i / points + math.pi / 2
        at = Vector((x + r * 0.96 * math.cos(a), y + h * 0.45, z + r * 0.96 * math.sin(a)))
        out = Vector((math.cos(a), 0, math.sin(a)))
        p.add("Gold", spike(r * 0.3, h * 0.75, 6), T(*at) @ toward(Vector((0, 1, 0)) + out * 0.18))
        tip = at + (Vector((0, 1, 0)) + out * 0.18).normalized() * h * 0.78
        p.add(gem_role, sphere(r * 0.13, 6, 4), T(*tip))
        p.add(gem_role, sphere(r * 0.16, 6, 4), T(x + r * 1.08 * math.cos(a + math.pi / points), y + h * 0.27, z + r * 1.08 * math.sin(a + math.pi / points)) @ S(1, 1.3, 1))
    p.add("Red", sphere(r * 0.86, 10, 5), T(x, y + h * 0.45, z) @ S(1, 0.5, 1))  # cojín de dentro


def rock_lathe(profile, n, seed, jitter=0.06, keep_top=True):
    """Como lathe, pero con los radios movidos al azar (con semilla): roca natural. El anillo de arriba no se mueve."""
    rng = random.Random(seed)
    verts, faces = lathe(profile, n)
    out = []
    for i, (x, y, z) in enumerate(verts):
        ring = i // n
        top = keep_top and ring == len(profile) - 1
        k = 1 if top else 1 + rng.uniform(-jitter, jitter)
        out.append((x * k, y + (0 if top else rng.uniform(-0.8, 0.8)), z * k))
    return out, faces


# ---------- Portal del hub ----------

def boss_portal(p):
    mid = PORTAL_MID
    r0, r1, depth = 7.7, 10.2, 3.2
    # Peana con escalones delante y detrás.
    p.add("StoneDark", frustum(19.4, 8.2, 18.6, 7.6, 1.2), T(0, 0.6, 0))
    p.add("Stone", frustum(18.2, 7.0, 17.8, 6.6, 0.2), T(0, 1.3, 0))
    p.add("Stone", frustum(14.6, 11.6, 14.0, 11.0, 0.6), T(0, 0.3, 0))
    p.add("Gold", box(18.8, 0.2, 0.25), T(0, 1.1, -3.85))
    p.add("Gold", box(18.8, 0.2, 0.25), T(0, 1.1, 3.85))
    # Arco de dovelas: claves doradas arriba y a los lados, las demás de piedra en dos tonos.
    count = 24
    gap = math.radians(1.1)
    for i in range(count):
        a0 = 2 * math.pi * i / count + gap / 2 + math.pi / 2 - math.pi / count
        a1 = a0 + 2 * math.pi / count - gap
        if i == 0:
            p.add("Gold", voussoir(r0 - 0.3, r1 + 0.9, a0 - gap / 2, a1 + gap / 2, depth + 0.7, mid, 0.3))
            continue
        role = "Gold" if i in (6, 18) else ("Stone" if i % 2 else "StoneDark")
        p.add(role, voussoir(r0, r1, a0, a1, depth, mid))
    for z in (-1, 1):
        p.add("Gold", torus(r0 + 0.05, 0.26, 40, 6), T(0, mid, z * (depth / 2 - 0.05)) @ R("X", 90))
        p.add("Gold", torus(r1 - 0.05, 0.22, 44, 6), T(0, mid, z * (depth / 2 - 0.05)) @ R("X", 90))
    # Runas: gemas en las dos caras del arco.
    for i in range(1, count):
        if i in (6, 18):
            continue
        a = 2 * math.pi * i / count + math.pi / 2
        rr = (r0 + r1) / 2
        for z in (-1, 1):
            p.add("Crystal", sphere(0.42, 6, 4), T(rr * math.cos(a), mid + rr * math.sin(a), z * (depth / 2 + 0.05)) @ S(1, 1, 0.45))
    # El Rey Slime pequeño encima de la clave, con su corona.
    top = mid + r1 + 0.6
    p.add("Slime", lathe([(0, 0), (3.3, 0.1), (3.9, 0.8), (3.7, 1.9), (2.9, 3.0), (1.5, 3.7), (0, 3.9)], 14), T(0, top, 0) @ S(1, 1, 0.82))
    slime_eyes(p, 0, top + 2.0, -2.7, 1.0)
    p.add("Black", box(1.2, 0.22, 0.3), T(0, top + 1.15, -2.95))
    crown(p, top + 3.25, 1.75, 2.2, 5, "Red")
    # Baba que cae por fuera del arco y por dentro de la clave.
    for k, (a, length) in enumerate(((70, 3.6), (112, 4.6), (52, 2.6), (128, 3.0), (38, 2.0))):
        t = math.radians(a)
        at = (r1 * math.cos(t), mid + r1 * math.sin(t), 0)
        p.add("Slime", sphere(1.0, 8, 5), T(*at) @ S(1.3, 0.75, 1.15))
        p.add("Slime", drip(0.5, length), T(at[0] + 0.3 * math.cos(t), at[1] - 0.2, 0.9 if k % 2 else -0.9))
    for a, length in ((80, 1.8), (98, 2.6), (88, 1.4)):
        t = math.radians(a)
        p.add("Slime", drip(0.34, length, 8), T(r0 * math.cos(t), mid + r0 * math.sin(t) + 0.15, -0.6 if a < 90 else 0.7))
    # Charcos al pie del arco.
    for s in (-1, 1):
        p.add("Slime", sphere(1, 10, 4), T(s * 6.4, 1.42, s * 0.6) @ S(2.4, 0.22, 1.7))
    # Pilonos con cristal a los lados (sustituyen a los farolillos).
    for s in (-1, 1):
        x = s * 12.6
        p.add("StoneDark", frustum(3.8, 3.8, 3.3, 3.3, 0.8), T(x, 0.4, 0))
        p.add("Stone", frustum(2.5, 2.5, 1.9, 1.9, 8.2), T(x, 0.8 + 4.1, 0))
        p.add("Gold", box(2.5, 0.35, 2.5), T(x, 3.0, 0))
        p.add("Gold", box(2.15, 0.35, 2.15), T(x, 7.4, 0))
        p.add("StoneDark", frustum(2.2, 2.2, 3.2, 3.2, 0.8), T(x, 9.3, 0))
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            p.add("Gold", spike(0.26, 1.6, 5), T(x + 1.2 * math.cos(a), 9.7, 1.2 * math.sin(a)) @ toward((math.cos(a) * 0.35, 1, math.sin(a) * 0.35)))
        p.add("Crystal", gem(0.95, 4.6), T(x, 9.75, 0))
        p.add("Crystal", gem(0.5, 2.4), T(x + 0.7, 9.8, 0.3) @ toward((0.6, 1, 0.2)))
        p.add("Crystal", gem(0.45, 2.0), T(x - 0.6, 9.8, -0.4) @ toward((-0.5, 1, -0.4)))


# ---------- Arena ----------

def island_y(radius):
    """Altura de la cara de abajo de la roca a un radio dado (para clavar estalactitas y cristales)."""
    prof = ISLAND_PROFILE
    for (ra, ya), (rb, yb) in zip(prof[1:], prof):
        if rb >= radius >= ra:
            t = (radius - ra) / max(rb - ra, 1e-6)
            return ya + (yb - ya) * t
    return prof[0][1]


# De arriba a abajo: (radio, altura). lathe los quiere de abajo a arriba: se dan la vuelta al usarlos.
ISLAND_PROFILE = [(98.0, -0.8), (97.0, -6), (93.0, -14), (84.0, -24), (70.0, -36), (52.0, -48), (34.0, -58),
                  (18.0, -68), (6.0, -76), (0.0, -80)]


def boss_island(p):
    rng = random.Random(7)
    # La roca: cuerpo principal y una franja más clara arriba (estratos).
    p.add("StoneDark", rock_lathe([(r, y) for r, y in reversed(ISLAND_PROFILE)], 44, 3, 0.05))
    p.add("Stone", rock_lathe([(88.0, -17), (95.5, -11.5), (99.6, -5), (100.6, -0.6)], 44, 5, 0.025))
    # Borde de hierba alrededor de la arena, con el contorno de fuera irregular.
    def edge(a):
        return ISLAND - 2.4 + 0.9 * math.sin(a * 7) + 0.6 * math.sin(a * 13 + 1.3)
    n = 72
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        verts, faces = loft([
            [(84.0 * math.cos(a0), y, 84.0 * math.sin(a0)), (edge(a0) * math.cos(a0), y, edge(a0) * math.sin(a0)),
             (edge(a1) * math.cos(a1), y, edge(a1) * math.sin(a1)), (84.0 * math.cos(a1), y, 84.0 * math.sin(a1))]
            for y in (-0.7, -0.15)])
        p.add("Leaf", (verts, faces))
    for i in range(34):
        a = rng.uniform(0, 2 * math.pi)
        if abs(math.degrees(a) - 90) < 9 or abs(math.degrees(a) - 270) < 14:
            continue
        rr = rng.uniform(87, 96)
        size = rng.uniform(0.8, 1.8)
        p.add("LeafDark" if i % 3 else "Leaf", blob((size * 1.3, size, size * 1.3), 40 + i, 7, 4, 0.25), T(rr * math.cos(a), -0.2 + size * 0.4, rr * math.sin(a)))
    for i in range(10):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(88, 97)
        size = rng.uniform(1.0, 2.4)
        p.add("Stone", blob((size * 1.4, size, size * 1.2), 90 + i, 7, 4, 0.25), T(rr * math.cos(a), size * 0.3 - 0.3, rr * math.sin(a)))
    # Estalactitas.
    for i in range(22):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(8, 88)
        y = island_y(rr) + 1.5
        length = rng.uniform(6, 17) * (1.2 if rr < 40 else 1)
        role = "Stone" if i % 3 == 0 else "StoneDark"
        p.add(role, spike(rng.uniform(1.6, 3.6), length, 7), T(rr * math.cos(a), y, rr * math.sin(a)) @ R("X", 180))
    # Racimos de cristales que salen de la roca.
    for i in range(9):
        a = 2 * math.pi * i / 9 + rng.uniform(-0.2, 0.2)
        y = rng.uniform(-44, -18)
        rr = next(r for r, yy in ISLAND_PROFILE if yy <= y) + 2.0
        base = Vector((rr * math.cos(a), y, rr * math.sin(a))) * 0.97
        out = Vector((math.cos(a), -0.35, math.sin(a)))
        for k in range(3):
            d = out + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.3, 0.3), rng.uniform(-0.35, 0.35)))
            p.add("Crystal", gem(rng.uniform(2.4, 4.0), rng.uniform(10, 19)), T(*base) @ toward(d))
    # Baba que se sale por el borde.
    for i in range(12):
        a = 2 * math.pi * (i + rng.uniform(0.1, 0.9)) / 12
        if abs(math.degrees(a) - 90) < 10:
            continue
        rr = edge(a) + 1.6
        p.add("Slime", sphere(1, 9, 5), T(rr * math.cos(a), -0.6, rr * math.sin(a)) @ S(2.6, 1.0, 2.6))
        p.add("Slime", drip(rng.uniform(0.9, 1.5), rng.uniform(5, 13)), T((rr + 1.2) * math.cos(a), -1.0, (rr + 1.2) * math.sin(a)))
    # Rocas sueltas que flotan alrededor.
    for i in range(8):
        a = 2 * math.pi * i / 8 + rng.uniform(-0.25, 0.25)
        rr = rng.uniform(116, 142)
        size = rng.uniform(4, 9)
        y = rng.uniform(-46, -8)
        p.add("StoneDark", blob((size, size * 0.8, size), 120 + i, 8, 5, 0.25), T(rr * math.cos(a), y, rr * math.sin(a)))
        p.add("Stone", spike(size * 0.55, size * 1.4, 6), T(rr * math.cos(a), y - size * 0.4, rr * math.sin(a)) @ R("X", 180))
        if i % 2 == 0:
            p.add("Leaf", blob((size * 0.9, size * 0.25, size * 0.9), 150 + i, 8, 3, 0.15), T(rr * math.cos(a), y + size * 0.72, rr * math.sin(a)))
        else:
            p.add("Crystal", gem(size * 0.25, size * 1.1), T(rr * math.cos(a), y + size * 0.55, rr * math.sin(a)))

    # Suelo: baldosas en anillos alrededor del charco, un tono por anillo, y aros dorados.
    p.group = "Floor"
    rings = 8
    step = (WALL_IN - 0.6 - PUDDLE - 0.6) / rings
    for k in range(rings):
        ra = PUDDLE + 0.6 + k * step
        rb = ra + step - 0.35
        count = max(12, round(2 * math.pi * (ra + rb) / 2 / 7.5))
        gap = 0.35 / ((ra + rb) / 2)
        role = "Stone" if k % 2 == 0 else "StoneDark"
        for i in range(count):
            a0 = 2 * math.pi * i / count + (k % 2) * math.pi / count
            p.add(role, wedge(ra, rb, a0 + gap / 2, a0 + 2 * math.pi / count - gap / 2, -0.05, 0.14, 0.08, 2))
    for rr, thick in ((PUDDLE + 0.2, 0.32), (PUDDLE + 0.6 + 4 * step - 0.17, 0.2)):
        p.add("Gold", torus(rr, thick, 96, 5), T(0, 0.08, 0) @ S(1, 0.4, 1))
    # Ocho runas de cristal en el anillo dorado de en medio.
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        rr = PUDDLE + 0.6 + 4 * step - 0.17
        p.add("Crystal", sphere(0.9, 6, 4), T(rr * math.cos(a), 0.12, rr * math.sin(a)) @ S(1, 0.35, 1))

    # Muralla: tramos con almenas, ribete dorado y abertura en +Z (el torii de la entrada).
    p.group = "Wall"
    segments = 72
    for i in range(segments):
        a0 = 2 * math.pi * i / segments
        a1 = 2 * math.pi * (i + 1) / segments
        center = math.degrees((a0 + a1) / 2)
        if abs(center - 90) < 9:
            continue
        g = 0.12 / WALL_IN
        p.add("Stone", wedge(WALL_IN, WALL_OUT, a0 + g, a1 - g, -0.3, WALL_H, 0.18, 2))
        if i % 2 == 0:
            p.add("StoneDark", wedge(WALL_IN + 0.15, WALL_OUT - 0.15, a0 + 0.012, a1 - 0.012, WALL_H, WALL_H + 1.5, 0.15, 1))
    p.add("Gold", torus(WALL_IN - 0.02, 0.16, 144, 4), T(0, WALL_H - 0.5, 0) @ S(1, 1, 1))
    for i in range(10):
        a = 2 * math.pi * (i + 0.37) / 10
        if abs(math.degrees(a) - 90) < 14:
            continue
        rr = (WALL_IN + WALL_OUT) / 2
        p.add("Slime", sphere(1, 9, 5), T(rr * math.cos(a), WALL_H + 0.2, rr * math.sin(a)) @ S(1.9, 0.7, 1.9))
        for side, length in ((-1, 2.2 + i % 3), (1, 1.6 + (i * 7) % 3)):
            r2 = (WALL_IN - 0.3) if side < 0 else (WALL_OUT + 0.3)
            p.add("Slime", drip(0.55, length, 8), T(r2 * math.cos(a), WALL_H + 0.1, r2 * math.sin(a)))


def boss_pillar(p):
    p.add("StoneDark", frustum(6.2, 6.2, 5.4, 5.4, 1.6), T(0, 0.8, 0))
    p.add("Gold", box(5.6, 0.4, 5.6), T(0, 1.8, 0))
    # Fuste estriado.
    n, r = 16, 1.95
    loops = []
    for y in (2.0, 23.0):
        loops.append([((r - (0.16 if j % 2 else 0)) * math.cos(2 * math.pi * j / n), y,
                       (r - (0.16 if j % 2 else 0)) * math.sin(2 * math.pi * j / n)) for j in range(n)])
    p.add("Stone", loft(loops))
    p.add("Stone", lathe([(2.3, 1.95), (2.3, 2.4), (1.95, 2.8)], 16))
    for y in (8.5, 15.5):
        p.add("Gold", torus(1.92, 0.22, 20, 5), T(0, y, 0))
    p.add("Stone", lathe([(1.9, 23.0), (2.5, 24.0), (3.15, 24.9), (3.2, 25.6)], 16))
    p.add("StoneDark", frustum(6.6, 6.6, 6.2, 6.2, 1.1), T(0, 26.15, 0))
    p.add("Gold", box(6.7, 0.25, 6.7), T(0, 25.75, 0))
    # Baba por encima del capitel, que gotea por los lados.
    p.add("Slime", sphere(1, 12, 5), T(0, 26.75, 0) @ S(3.1, 0.75, 3.1))
    for k, length in enumerate((3.4, 6.0, 2.4, 4.5)):
        a = math.radians(30 + k * 97)
        p.add("Slime", drip(0.5, length, 8), T(3.15 * math.cos(a), 26.2, 3.15 * math.sin(a)))
    # Cuna dorada del cristal.
    for k in range(6):
        a = 2 * math.pi * k / 6
        p.add("Gold", spike(0.32, 2.6, 5), T(2.1 * math.cos(a), 27.0, 2.1 * math.sin(a)) @ toward((math.cos(a) * 0.4, 1, math.sin(a) * 0.4)))
    p.add("Gold", torus(2.1, 0.28, 18, 5), T(0, 27.2, 0))
    # Musgo al pie.
    for k in range(3):
        a = math.radians(40 + k * 120)
        p.add("LeafDark", blob((1.4, 0.7, 1.2), 300 + k, 7, 4, 0.25), T(3.0 * math.cos(a), 0.25, 3.0 * math.sin(a)))


def boss_crystal(p):
    p.add("Crystal", gem(1.45, 6.2, 6, 0.6), T(0, -3.1, 0))
    p.add("Crystal", gem(0.6, 2.6), T(0.55, -2.2, 0.2) @ toward((0.7, 1, 0.25)))
    p.add("Crystal", gem(0.5, 2.2), T(-0.5, -2.0, -0.3) @ toward((-0.6, 1, -0.45)))


def boss_throne(p):
    rng = random.Random(11)
    # Peñasco por debajo, unido al borde de la isla.
    p.add("StoneDark", blob((19, 9, 15), 21, 12, 6, 0.12), T(0, -7.5, 1))
    p.add("StoneDark", spike(9, 26, 8), T(0, -11, 1) @ R("X", 180))
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi)
        p.add("Stone", spike(rng.uniform(1.6, 3), rng.uniform(6, 12), 6), T(math.cos(a) * 10, -12, 1 + math.sin(a) * 7) @ R("X", 180))
    # Gradas.
    p.add("Stone", frustum(28, 20, 27, 19, 1.5), T(0, 0.75, 0))
    p.add("StoneDark", frustum(23, 16, 22, 15, 1.5), T(0, 2.25, 0.8))
    p.add("Stone", frustum(18.5, 12.5, 18, 12, 1.5), T(0, 3.75, 1.4))
    for y, w, z in ((1.5, 27.2, -9.55), (3.0, 22.2, -6.75), (4.5, 18.1, -4.65)):
        p.add("Gold", box(w, 0.22, 0.3), T(0, y - 0.05, z))
    # Alfombra roja por las gradas.
    p.add("Red", box(6, 0.12, 3.0), T(0, 1.55, -8.4))
    p.add("Red", box(6, 0.12, 2.6), T(0, 3.05, -5.6))
    p.add("Red", box(6, 0.12, 2.6), T(0, 4.55, -3.4))
    # Asiento con cojín de baba.
    p.add("Stone", box(14, 4, 9), T(0, 6.5, 1.5))
    p.add("Gold", box(14.3, 0.4, 9.3), T(0, 8.3, 1.5))
    p.add("Slime", lathe([(0, 0), (5.0, 0.1), (5.8, 0.8), (5.2, 1.7), (2.6, 2.3), (0, 2.45)], 14), T(0, 8.4, 1.0) @ S(1.05, 1, 0.72))
    for x, length in ((-3.5, 2.8), (1.2, 4.0), (4.2, 2.2)):
        p.add("Slime", drip(0.55, length, 8), T(x, 8.6, -2.9))
    # Respaldo con arco, marco oscuro y la corona del rey en grande.
    p.add("StoneDark", box(16.6, 22.6, 2.4), T(0, 19.5, 5.4))
    p.add("StoneDark", cyl(8.3, 2.4, 20), T(0, 30.8, 4.2) @ R("X", 90))
    p.add("Stone", box(15, 22, 3), T(0, 19.5, 4.5))
    p.add("Stone", cyl(7.5, 3, 20), T(0, 30.5, 3.0) @ R("X", 90))
    p.add("Gold", torus(7.55, 0.3, 24, 5), T(0, 30.5, 2.95) @ R("X", 90))
    for s in (-1, 1):
        p.add("Gold", box(0.5, 22, 0.4), T(s * 7.3, 19.5, 2.95))
        p.add("Red", box(3.6, 13, 0.25), T(s * 4.2, 17.5, 2.9))  # estandartes
        p.add("Gold", box(4.0, 0.4, 0.4), T(s * 4.2, 24.1, 2.85))
        p.add("Red", frustum(3.6, 0.25, 0.4, 0.25, 1.6), T(s * 4.2, 10.2, 2.9) @ R("X", 180))
    crown(p, 27.2, 3.3, 5.0, 5, "Crystal", z=0.6)
    p.add("Crystal", gem(1.2, 3.6), T(0, 21.0, 2.7) @ R("X", 90) @ T(0, -1.8, 0))
    # Brazos con bolas doradas.
    for s in (-1, 1):
        p.add("StoneDark", box(3, 3.4, 10), T(s * 8.6, 10.2, 1.5))
        p.add("Gold", sphere(1.45, 10, 6), T(s * 8.6, 12.4, -3.2))
        p.add("Gold", box(3.2, 0.3, 10.2), T(s * 8.6, 11.9, 1.5))
    # Agujas de cristal en las esquinas de las gradas.
    for s in (-1, 1):
        x = s * 12.0
        p.add("StoneDark", frustum(4.2, 4.2, 3.4, 3.4, 1.8), T(x, 2.4, -6.0))
        p.add("Crystal", gem(1.6, 11.0, 6, 0.65), T(x, 3.0, -6.0))
        p.add("Crystal", gem(0.9, 5.5), T(x + s * 1.0, 3.1, -5.4) @ toward((s * 0.6, 1, 0.3)))
        p.add("Crystal", gem(0.8, 4.4), T(x - s * 0.7, 3.1, -6.8) @ toward((-s * 0.4, 1, -0.5)))


def boss_barrel(p):
    """Barril de baba de la fase de carga, de pie: 4,4 de alto y 3,6 de ancho (la caja que se golpea en
    WorldBossMobs.barrel), con el origen abajo. Duelas que se abomban, aros de hierro y baba que rebosa por arriba."""
    p.add("Wood", lathe([(1.5, 0), (1.72, 0.6), (1.84, 1.4), (1.88, 2.2), (1.84, 3.0), (1.72, 3.8), (1.5, 4.3)], 16))
    for y, r in ((0.45, 1.66), (1.35, 1.86), (3.05, 1.86), (3.95, 1.66)):
        p.add("Black", torus(r, 0.13, 20, 4), T(0, y, 0))
    p.add("Slime", torus(1.92, 0.2, 20, 5), T(0, 2.2, 0))
    p.add("Wood", cyl(1.38, 0.15, 14), T(0, 4.15, 0))
    p.add("Slime", lathe([(0, 0), (1.45, 0.05), (1.7, 0.35), (1.3, 0.75), (0.6, 1.0), (0, 1.05)], 12), T(0, 4.15, 0))
    for k, length in enumerate((1.4, 2.4, 1.0, 1.8)):
        a = math.radians(20 + k * 90)
        p.add("Slime", drip(0.32, length, 8), T(1.62 * math.cos(a), 4.35, 1.62 * math.sin(a)))
    slime_eyes(p, 0, 4.75, -1.42, 0.45)


def boss_shield_base(p):
    """Peana del cristal del escudo (5 de ancho, origen en el suelo): piedra octogonal, ribete dorado, círculo de
    runas arriba y esquirlas de cristal alrededor."""
    p.add("StoneDark", lathe([(2.75, 0), (2.75, 0.45), (2.35, 0.65)], 8))
    p.add("Stone", lathe([(2.05, 0.6), (1.85, 1.3), (2.45, 1.45), (2.45, 1.75)], 8))
    p.add("Gold", torus(2.5, 0.12, 16, 4), T(0, 1.6, 0) @ R("Y", 22.5))
    p.add("Gold", torus(1.55, 0.1, 20, 4), T(0, 1.78, 0) @ S(1, 0.5, 1))
    for k in range(6):
        a = 2 * math.pi * k / 6
        p.add("Crystal", sphere(0.2, 6, 4), T(1.55 * math.cos(a), 1.8, 1.55 * math.sin(a)) @ S(1, 0.5, 1))
    for k in range(4):
        a = 2 * math.pi * (k + 0.5) / 4
        p.add("Crystal", gem(0.38, 1.6), T(2.55 * math.cos(a), 0.3, 2.55 * math.sin(a)) @ toward((math.cos(a) * 0.5, 1, math.sin(a) * 0.5)))


def boss_shield_crystal(p):
    """El cristal del escudo que flota (4 x 8, centrado en el origen): punta doble, esquirlas y un aro dorado."""
    p.add("Crystal", gem(1.9, 8.0, 6, 0.58), T(0, -4.0, 0))
    p.add("Crystal", gem(0.75, 3.2), T(0.9, -2.6, 0.3) @ toward((0.6, 1, 0.2)))
    p.add("Crystal", gem(0.65, 2.8), T(-0.8, -2.3, -0.4) @ toward((-0.55, 1, -0.4)))
    p.add("Gold", torus(1.95, 0.16, 20, 5), T(0, 0.2, 0) @ R("X", 12))
    for k in range(3):
        a = 2 * math.pi * k / 3
        p.add("Gold", sphere(0.28, 6, 4), T(1.95 * math.cos(a), 0.2 + 0.41 * math.sin(a), 1.95 * math.sin(a)))


def boss_board(p):
    """Marco del cartel de premios (el tablero con el texto es una Part de WorldBossArena.buildBoard, de 15 x 19, con
    la cara delantera en z=0,15): postes lacados, tejado con remate dorado, marco dorado, farolillos y la corona del
    rey con su baba encima. Origen en el suelo, al frente -Z."""
    for s in (-1, 1):
        x = s * 8.35
        p.add("StoneDark", frustum(2.4, 2.4, 2.0, 2.0, 0.8), T(x, 0.4, 0.4))
        p.add("Red", box(1.25, 22.6, 1.25), T(x, 0.8 + 11.3, 0.4))
        p.add("Gold", box(1.4, 0.3, 1.4), T(x, 1.2, 0.4))
        p.add("Gold", box(1.4, 0.3, 1.4), T(x, 21.0, 0.4))
    # Marco dorado alrededor del tablero.
    p.add("Gold", box(15.9, 0.5, 0.9), T(0, 21.25, 0.4))
    p.add("Gold", box(15.9, 0.5, 0.9), T(0, 1.75, 0.4))
    for s in (-1, 1):
        p.add("Gold", box(0.5, 19.9, 0.9), T(s * 7.75, 11.5, 0.4))
        p.add("Gold", sphere(0.45, 8, 5), T(s * 7.75, 21.25, -0.1))
        p.add("Gold", sphere(0.45, 8, 5), T(s * 7.75, 1.75, -0.1))
    # Tejado: viga roja, alero negro que se curva hacia arriba en las puntas y remate dorado.
    p.add("Red", box(18.2, 1.0, 1.5), T(0, 22.3, 0.4))
    def roof_y(x):
        return 23.1 + 0.9 * (abs(x) / 10.5) ** 2.4
    n = 16
    loops = []
    for i in range(n + 1):
        x = -10.5 + 21.0 * i / n
        y = roof_y(x)
        loops.append([(x, y, -1.6), (x, y, 2.4), (x, y + 0.7, 2.0), (x, y + 1.3, 0.4), (x, y + 0.7, -1.2)])
    p.add("Black", loft(loops))
    p.add("Gold", box(13.0, 0.35, 0.5), T(0, roof_y(0) + 1.4, 0.4))
    # Corona del rey sobre un poco de baba en el centro del tejado, y baba que gotea por el alero.
    p.add("Slime", lathe([(0, 0), (2.1, 0.08), (2.5, 0.6), (2.1, 1.3), (1.0, 1.75), (0, 1.85)], 12), T(0, roof_y(0) + 1.2, 0.4) @ S(1, 1, 0.8))
    slime_eyes(p, 0, roof_y(0) + 2.15, -1.25, 0.6)
    crown(p, roof_y(0) + 2.8, 1.25, 1.6, 5, "Red", z=0.4)
    for x, length in ((-6.0, 1.6), (-2.6, 2.4), (3.4, 1.4), (6.6, 2.0)):
        p.add("Slime", drip(0.28, length, 8), T(x, roof_y(x) + 0.2, -1.55))
    # Farolillos colgando de las puntas del alero.
    for s in (-1, 1):
        x = s * 9.6
        p.add("Black", box(0.12, 1.2, 0.12), T(x, roof_y(x) - 0.55, 0.4))
        p.add("Red", lathe([(0.0, -0.9), (0.65, -0.75), (0.95, -0.3), (1.0, 0), (0.95, 0.3), (0.65, 0.75), (0, 0.9)], 10), T(x, roof_y(x) - 2.1, 0.4))
        p.add("Paper", lathe([(0.0, -0.82), (0.55, -0.68), (0.9, -0.27), (0.92, 0), (0.9, 0.27), (0.55, 0.68), (0, 0.82)], 10), T(x, roof_y(x) - 2.1, 0.4) @ S(1.04, 1, 1.04))


PIECES = {"BossPortal": boss_portal, "BossIsland": boss_island, "BossPillar": boss_pillar, "BossCrystal": boss_crystal,
          "BossThrone": boss_throne, "BossBarrel": boss_barrel, "BossShieldBase": boss_shield_base,
          "BossShieldCrystal": boss_shield_crystal, "BossBoard": boss_board}

# Vistas de prueba: (altura que se mira, ancho en studs, giro, grados por encima).
VIEWS = {
    "BossPortal": [(12.0, 40.0, 20.0, 10.0), (12.0, 40.0, 320.0, 25.0)],
    "BossIsland": [(-20.0, 300.0, 20.0, 12.0), (0.0, 230.0, 20.0, 50.0), (-25.0, 250.0, 340.0, -14.0)],
    "BossPillar": [(14.0, 34.0, 20.0, 10.0)],
    "BossCrystal": [(0.0, 10.0, 20.0, 10.0)],
    "BossThrone": [(14.0, 60.0, 20.0, 12.0), (8.0, 60.0, 315.0, 25.0)],
    "BossBarrel": [(2.5, 9.0, 20.0, 15.0)],
    "BossShieldBase": [(1.0, 9.0, 20.0, 25.0)],
    "BossShieldCrystal": [(0.0, 11.0, 20.0, 10.0)],
    "BossBoard": [(13.0, 30.0, 20.0, 8.0)],
}


def place(name):
    """Dónde va cada pieza en la escena de Blender (solo para verlas por separado)."""
    return {"BossPortal": 0.0, "BossIsland": 400.0, "BossPillar": 80.0, "BossCrystal": 120.0, "BossThrone": 180.0, "BossBarrel": 240.0, "BossShieldBase": 260.0,
            "BossShieldCrystal": 280.0, "BossBoard": 320.0}[name]


def main():
    parser = argparse.ArgumentParser(description="Generar las piezas del Jefe del mundo.")
    parser.add_argument("--output-dir", default=jp.OUT_DIR)
    parser.add_argument("--only", nargs="+", choices=tuple(PIECES))
    parser.add_argument("--skip-previews", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output_dir
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)

    jp.marker("Axis_Origin", (-40, 0, 0))
    jp.marker("Axis_Up", (-40, 2, 0))
    jp.marker("Axis_Front", (-40, 0, -2))
    names = args.only or list(PIECES)
    for name in names:
        p = Piece()
        PIECES[name](p)
        offset = (place(name), 0, 0)
        for group in sorted({group for group, _ in p.parts}):
            jp.marker("%s%s_Origin" % (name, group), offset)
        for (group, role), (verts, faces) in p.parts.items():
            obj = jp.make_object("%s%s_%s" % (name, group, role), role, verts, faces, offset)
            if len(obj.data.polygons) > 9000:
                print("AVISO: %s tiene %d triángulos" % (obj.name, len(obj.data.polygons)))

    os.makedirs(output, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, "jefe.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(output, "jefe.fbx"),
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
    )
    print("Exportadas", len(names), "piezas,", len(bpy.data.objects), "mallas")
    if args.skip_previews:
        return
    for name in names:
        for index, (center, width, angle, pitch) in enumerate(VIEWS[name]):
            jp.render_view(os.path.join(output, "jefe_%s%d.png" % (name, index + 1)), (place(name), center), width, angle, pitch)


if __name__ == "__main__":
    main()
