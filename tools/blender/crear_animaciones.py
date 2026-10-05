# Crea en Blender los muñecos R15 (mismos huesos que las articulaciones de Roblox) y todas las animaciones de
# golpe. Se lanza una vez para empezar:
#   blender -b --python tools/blender/crear_animaciones.py
# y guarda el .blend en Documents\Roblox\modelos\animaciones_golpe.blend. Después se retocan a mano en Blender
# y se pasan al juego con exportar_animaciones.py. Volver a lanzar este script BORRA los retoques.
#
# Hay un muñeco por tipo de arma ("R15_sword", "R15_axe", ...) con un arma de muestra en la mano. Cada
# animación es una Acción con el nombre "<tipo>_<n>" (golpes normales, que se van alternando en combo) o
# "<tipo>_<rareza>" (Mitica, Secreta, Divina: el golpe épico de las armas de esa rareza). Los marcadores de la
# línea de tiempo llamados "impacto:<Acción>" hacen temblar la cámara y sacan una onda del suelo en ese fotograma.
# Ejes: los muñecos miran a -Y (vista frontal de Blender), +Z arriba.
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

BLEND_PATH = os.path.join(os.path.expanduser("~"), "Documents", "Roblox", "modelos", "animaciones_golpe.blend")
FPS = 30

# Roblox (X derecha, Y arriba, Z atrás) <-> Blender. La misma matriz sirve para ir y volver.
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))


def r2b(x, y, z):
    return M @ Vector((x, y, z))


# Huesos = articulaciones (Motor6D) de Roblox: nombre, padre, inicio y fin en coordenadas de Roblox,
# y tamaño de la pieza que mueve (para verlo como el personaje).
BONES = [
    ("Root", None, (0, -0.6, 0), (0, -0.2, 0), (2, 0.4, 1)),
    ("Waist", "Root", (0, -0.2, 0), (0, 1.0, 0), (2, 1.2, 1)),
    ("Neck", "Waist", (0, 1.0, 0), (0, 2.2, 0), (1.2, 1.2, 1.2)),
    ("RightShoulder", "Waist", (1.5, 0.8, 0), (1.5, -0.2, 0), (1, 1, 1)),
    ("RightElbow", "RightShoulder", (1.5, -0.2, 0), (1.5, -1.0, 0), (1, 0.8, 1)),
    ("RightWrist", "RightElbow", (1.5, -1.0, 0), (1.5, -1.3, 0), (1, 0.3, 1)),
    ("LeftShoulder", "Waist", (-1.5, 0.8, 0), (-1.5, -0.2, 0), (1, 1, 1)),
    ("LeftElbow", "LeftShoulder", (-1.5, -0.2, 0), (-1.5, -1.0, 0), (1, 0.8, 1)),
    ("LeftWrist", "LeftElbow", (-1.5, -1.0, 0), (-1.5, -1.3, 0), (1, 0.3, 1)),
    ("RightHip", "Root", (0.5, -0.6, 0), (0.5, -1.8, 0), (1, 1.2, 1)),
    ("RightKnee", "RightHip", (0.5, -1.8, 0), (0.5, -2.9, 0), (1, 1.1, 1)),
    ("LeftHip", "Root", (-0.5, -0.6, 0), (-0.5, -1.8, 0), (1, 1.2, 1)),
    ("LeftKnee", "LeftHip", (-0.5, -1.8, 0), (-0.5, -2.9, 0), (1, 1.1, 1)),
]

# Arma de muestra de cada tipo: (hueso, centro y tamaño en Roblox). Con el brazo colgando, la espada apunta al
# frente; la lanza va a lo largo del antebrazo (como su Grip en server/Swords).
PROPS = {
    "sword": [("RightWrist", (1.5, -1.3, -2.3), (0.3, 0.15, 4)), ("RightWrist", (1.5, -1.3, -0.35), (1.2, 0.25, 0.25))],
    "axe": [("RightWrist", (1.5, -1.3, -1.8), (0.25, 0.25, 3.6)), ("RightWrist", (1.5, -0.6, -3.2), (0.2, 1.6, 1.2))],
    "dual": [("RightWrist", (1.5, -1.3, -1.8), (0.3, 0.15, 3)), ("LeftWrist", (-1.5, -1.3, -1.8), (0.3, 0.15, 3))],
    "spear": [("RightWrist", (1.5, -3.0, 0), (0.2, 8, 0.2)), ("RightWrist", (1.5, -7.5, 0), (0.45, 1, 0.45))],
    "hammer": [("RightWrist", (1.5, -1.3, -1.8), (0.3, 0.3, 3.6)), ("RightWrist", (1.5, -1.3, -3.9), (1.4, 2.2, 1.4))],
}


# Las posturas se escriben con valores en grados (hop, lunge y drop en studs; lo que no se pone vale 0):
#   spin = girar el cuerpo entero, flip = voltereta (negativo hacia delante), turn = girar el torso (positivo a la
#   izquierda), lean = inclinarlo (negativo adelante), head = girar la cabeza,
#   raise = subir el brazo derecho (0 abajo, 90 al frente, 180 arriba), swing = llevarlo a la izquierda,
#   elbow = doblar el codo, wrist = muñeca (negativo echa la hoja hacia delante); lraise, lswing, lelbow, lwrist
#   lo mismo con el izquierdo; rhip, lhip = pierna adelante; rknee, lknee = doblar la rodilla;
#   hop = salto, lunge = zancada al frente, drop = agacharse (negativo).
# Giro de cada articulación en Roblox: (eje, grados) de fuera adentro, como JOINTS en el antiguo SwingAnim.
def joint_angles(p):
    g = lambda k: p.get(k, 0)
    return {
        "Root": [("Y", g("spin")), ("X", g("flip"))],
        "Waist": [("Y", g("turn")), ("X", g("lean"))],
        "Neck": [("Y", g("head"))],
        "RightHip": [("X", g("rhip"))],
        "RightKnee": [("X", -g("rknee"))],
        "LeftHip": [("X", g("lhip"))],
        "LeftKnee": [("X", -g("lknee"))],
        "RightShoulder": [("Y", g("swing")), ("X", g("raise"))],
        "RightElbow": [("X", g("elbow"))],
        "RightWrist": [("X", g("wrist"))],
        "LeftShoulder": [("Y", g("lswing")), ("X", g("lraise"))],
        "LeftElbow": [("X", g("lelbow"))],
        "LeftWrist": [("X", g("lwrist"))],
    }


ROBLOX_AXES = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0))}


def bone_axis(rc, axis):
    """Eje propio del hueso (0, 1 o 2) y signo que corresponde a ese eje de Roblox."""
    local = rc.inverted() @ (M @ ROBLOX_AXES[axis])
    index = max(range(3), key=lambda i: abs(local[i]))
    return index, 1 if local[index] > 0 else -1


def set_angles(pbone, rc, angles):
    """Pone los ángulos tal cual en el euler del hueso (así una vuelta de 360 o más se interpola entera, sin
    tomar el camino corto como haría pasando por una matriz)."""
    euler = [0.0, 0.0, 0.0]
    order = []
    for axis, degrees in angles:
        index, sign = bone_axis(rc, axis)
        euler[index] = sign * math.radians(degrees)
        order.append("XYZ"[index])
    # Euler de Blender con orden "abc" = giro c * giro b * giro a: el eje de dentro va primero.
    order.reverse()
    order += [a for a in "XYZ" if a not in order]
    pbone.rotation_mode = "".join(order)
    pbone.rotation_euler = Euler(euler, pbone.rotation_mode)


def P(base=None, **values):
    """Postura: copia de `base` cambiando `values` (raise_ = raise, que en Python es palabra reservada)."""
    pose = dict(base or {})
    for key, value in values.items():
        pose["raise" if key == "raise_" else key] = value
    return pose


# Cada animación: length = fotogramas (a 30 por segundo; en el juego se estira a la duración del golpe del arma),
# keys = { fotograma, postura, paso }, impacts = fotogramas de impacto. Empieza y acaba en la postura normal.
# Postura None = mantener la anterior. Paso = cómo se llega: None suave, "hit" de golpe pasándose un poco,
# "in" acelerando, "out" frenando, "fall" cayendo cada vez más rápido, "lin" a velocidad fija (vueltas seguidas).
ANIMS = {}

# --- Golpes normales (los de antes, que se alternan en combo) ---
ANIMS["sword_1"] = dict(length=30, keys=[  # tajo diagonal de derecha a izquierda, con zancada
    (5, P(spin=-25, turn=-40, lean=8, head=35, raise_=150, swing=-40, elbow=95, wrist=25, lraise=50, lswing=25, lelbow=30, hop=0.4, drop=-0.2, lhip=20, lknee=15, rhip=-15, rknee=20), None),
    (11, P(spin=20, turn=40, lean=-22, head=-30, raise_=35, swing=70, elbow=10, wrist=-70, lraise=-45, lswing=20, lelbow=20, lunge=1.4, drop=-0.4, rhip=35, rknee=35, lhip=-25, lknee=15), "hit"),
    (19, None, None),
])
ANIMS["sword_2"] = dict(length=30, keys=[  # revés horizontal de izquierda a derecha
    (5, P(spin=20, turn=40, lean=-5, head=-30, raise_=85, swing=75, elbow=105, wrist=-25, lraise=-30, lelbow=20, drop=-0.2, rhip=15, rknee=20, lhip=-15, lknee=20), None),
    (11, P(spin=-25, turn=-40, lean=-12, head=35, raise_=80, swing=-60, elbow=5, wrist=-65, lraise=35, lswing=40, lelbow=30, lunge=1.2, drop=-0.4, lhip=35, lknee=35, rhip=-25, rknee=15), "hit"),
    (19, None, None),
])
ANIMS["sword_3"] = dict(length=30, keys=[  # vuelta entera con la espada extendida y un saltito
    (4, P(spin=-50, turn=-30, lean=-5, raise_=88, swing=-50, elbow=40, wrist=-60, lraise=60, lswing=40, lelbow=30, drop=-0.5, rhip=20, rknee=30, lhip=-15, lknee=30), None),
    (11, P(spin=165, lean=-10, raise_=88, swing=-40, elbow=5, wrist=-70, lraise=70, lswing=50, lelbow=15, hop=1.2), "in"),
    (18, P(spin=360, turn=15, lean=-8, raise_=85, swing=-10, elbow=8, wrist=-68, lraise=50, lswing=35, lelbow=15), "out"),
])
ANIMS["sword_4"] = dict(length=30, keys=[  # salto y golpe desde arriba a dos manos
    (5, P(lean=18, raise_=175, elbow=70, wrist=30, lraise=170, lelbow=70, hop=2.6, rhip=35, rknee=70, lhip=10, lknee=80), None),
    (11, P(turn=10, lean=-38, raise_=28, swing=10, elbow=8, wrist=-70, lraise=30, lelbow=10, lunge=0.8, drop=-0.5, rhip=40, rknee=45, lhip=-25, lknee=25), "hit"),
    (20, None, None),
])
DUAL_OPEN = P(turn=-15, lean=10, raise_=95, swing=-70, elbow=40, wrist=-20, lraise=95, lswing=70, lelbow=40, lwrist=-20, hop=0.3, drop=-0.3, rhip=15, rknee=25, lhip=-15, lknee=25)
DUAL_CROSS = P(turn=10, lean=-25, raise_=70, swing=75, elbow=15, wrist=-60, lraise=70, lswing=-75, lelbow=15, lwrist=-60, lunge=1.3, drop=-0.4, rhip=35, rknee=35, lhip=-25, lknee=15)
DUAL_SPIN = P(lean=-8, raise_=88, swing=-80, elbow=5, wrist=-60, lraise=88, lswing=80, lelbow=5, lwrist=-60)
ANIMS["dual_1"] = dict(length=30, keys=[  # las dos hojas de fuera adentro, cruzándose
    (5, DUAL_OPEN, None),
    (11, DUAL_CROSS, "hit"),
    (18, None, None),
])
ANIMS["dual_2"] = dict(length=30, keys=[  # de cruzadas a abiertas, con un saltito
    (5, P(lean=-15, raise_=80, swing=80, elbow=60, wrist=-30, lraise=80, lswing=-80, lelbow=60, lwrist=-30, drop=-0.6, rhip=20, rknee=40, lhip=20, lknee=40), None),
    (11, P(lean=12, raise_=85, swing=-75, elbow=5, wrist=-55, lraise=85, lswing=75, lelbow=5, lwrist=-55, hop=0.6, lunge=0.8), "hit"),
    (18, None, None),
])
ANIMS["dual_3"] = dict(length=30, keys=[  # batidora: vuelta entera con los dos brazos abiertos
    (4, P(DUAL_SPIN, spin=-45, drop=-0.4, rhip=15, rknee=30, lhip=-15, lknee=30), None),
    (11, P(DUAL_SPIN, spin=160, swing=-85, lswing=85, hop=1), "in"),
    (18, P(DUAL_SPIN, spin=360), "out"),
])
ANIMS["axe_1"] = dict(length=30, keys=[  # carga hacia atrás y vuelta entera en el aire con el hacha extendida
    (5, P(spin=-70, turn=-30, lean=-8, raise_=85, swing=-60, elbow=30, wrist=-60, lraise=70, lswing=45, lelbow=25, drop=-0.6, rhip=20, rknee=35, lhip=-20, lknee=35), None),
    (14, P(spin=150, lean=-14, raise_=92, swing=-55, elbow=8, wrist=-75, lraise=75, lswing=50, lelbow=15, hop=1.1), "in"),
    (22, P(spin=360, turn=15, lean=-10, raise_=88, swing=-40, elbow=8, wrist=-75, lraise=70, lswing=45, lelbow=15, drop=-0.3), "out"),
])
HAMMER_UP = P(spin=-8, lean=22, raise_=178, elbow=55, wrist=30, lraise=172, lelbow=60, hop=2.8, rhip=30, rknee=75, lhip=15, lknee=85)
HAMMER_DOWN = P(spin=6, lean=-42, raise_=30, elbow=5, wrist=-68, lraise=34, lelbow=5, lunge=0.8, drop=-0.6, rhip=40, rknee=50, lhip=-25, lknee=30)
ANIMS["hammer_1"] = dict(length=30, impacts=[15], keys=[  # martillazo: salta con el martillo por encima y cae con todo
    (9, HAMMER_UP, None),
    (15, HAMMER_DOWN, "hit"),
    (23, None, None),
])
SPEAR_BACK = P(spin=-20, turn=-40, lean=8, head=30, raise_=-45, elbow=130, lraise=70, lelbow=15, lunge=-0.8, drop=-0.3, lhip=15, lknee=20, rhip=-20, rknee=20)
SPEAR_OUT = P(spin=15, turn=35, lean=-28, head=-25, raise_=90, elbow=0, lraise=-45, lelbow=15, lunge=2.6, drop=-0.5, rhip=45, rknee=45, lhip=-35, lknee=12)
ANIMS["spear_1"] = dict(length=30, keys=[  # estocada: se echa atrás con el codo recogido y sale disparado al frente
    (6, SPEAR_BACK, None),
    (11, SPEAR_OUT, "hit"),
    (20, None, None),
])
ANIMS["spear_2"] = dict(length=30, keys=[  # barrido: vuelta entera con la lanza extendida
    (4, P(spin=-50, turn=-25, raise_=80, swing=-50, elbow=20, wrist=-40, lraise=60, lswing=40, drop=-0.5, rhip=20, rknee=30, lhip=-15, lknee=30), None),
    (12, P(spin=160, lean=-8, raise_=88, swing=-45, elbow=5, wrist=-55, lraise=65, lswing=45, hop=0.9), "in"),
    (20, P(spin=360, turn=15, raise_=85, swing=-30, elbow=5, wrist=-55, lraise=60, lswing=40), "out"),
])

# Postura de reposo de cada tipo (sin poner = brazos colgando): sus golpes empiezan y acaban en ella, y
# "<tipo>_idle" la mantiene en el juego mientras se lleva el arma sin golpear. La lanza va en guardia, de pie
# con la punta arriba (con el brazo colgando apuntaba al suelo).
KIND_REST = {
    "spear": P(raise_=15, elbow=155),
}
ANIMS["spear_idle"] = dict(length=1, keys=[])

# --- Golpes épicos (Mítica, Secreta y Divina) ---
CROUCH = P(lean=25, drop=-1.0, rhip=50, rknee=90, lhip=50, lknee=90)
AIR = P(rhip=30, rknee=75, lhip=15, lknee=85)
LAND = P(lean=-45, raise_=25, elbow=5, wrist=-72, lraise=30, lelbow=5, lunge=1.0, drop=-0.7, rhip=45, rknee=55, lhip=-25, lknee=30)

ANIMS["sword_Mitica"] = dict(length=40, keys=[  # tajo giratorio: carga, vuelta entera en el aire y tajo desde arriba
    (6, P(spin=-60, turn=-35, lean=8, head=40, raise_=150, swing=-40, elbow=90, wrist=25, lraise=60, lswing=30, lelbow=30, drop=-0.4, rhip=20, rknee=35, lhip=-15, lknee=30), None),
    (14, P(spin=180, lean=-10, raise_=90, swing=-50, elbow=5, wrist=-70, lraise=70, lswing=50, lelbow=15, hop=1.4, rhip=30, rknee=60, lhip=20, lknee=70), "in"),
    (20, P(spin=360, lean=15, raise_=170, elbow=60, wrist=30, lraise=150, lelbow=50, hop=1.0, rhip=30, rknee=60, lhip=10, lknee=70), "out"),
    (25, P(spin=360, lean=-38, raise_=25, swing=15, elbow=5, wrist=-70, lraise=30, lswing=20, lelbow=10, lunge=1.5, drop=-0.5, rhip=40, rknee=45, lhip=-25, lknee=25), "hit"),
    (32, None, None),
])
ANIMS["sword_Secreta"] = dict(length=38, keys=[  # doble tajo: diagonal con zancada y, sin parar, salto y tajo cruzado
    (5, P(spin=-25, turn=-40, lean=8, head=35, raise_=150, swing=-40, elbow=95, wrist=25, lraise=50, lswing=25, lelbow=30, drop=-0.3, lhip=20, lknee=15, rhip=-15, rknee=20), None),
    (10, P(spin=20, turn=40, lean=-22, head=-30, raise_=35, swing=70, elbow=10, wrist=-70, lraise=-45, lswing=20, lelbow=20, lunge=1.2, drop=-0.4, rhip=35, rknee=35, lhip=-25, lknee=15), "hit"),
    (16, P(spin=30, turn=40, lean=15, head=-30, raise_=175, swing=40, elbow=70, wrist=30, lraise=160, lelbow=60, hop=2.4, rhip=35, rknee=70, lhip=10, lknee=80), None),
    (22, P(spin=-25, turn=-40, lean=-40, head=35, raise_=30, swing=-60, elbow=8, wrist=-70, lraise=30, lswing=40, lelbow=10, lunge=2.0, drop=-0.6, lhip=40, lknee=45, rhip=-25, rknee=25), "hit"),
    (30, None, None),
])
ANIMS["sword_Divina"] = dict(length=42, impacts=[27], keys=[  # golpe celestial: carga, sube girando muy alto y cae
    (8, P(CROUCH, spin=-30, turn=-30, head=25, raise_=-40, elbow=30, wrist=20, lraise=40, lswing=30, lelbow=40, drop=-0.9), None),
    (16, P(spin=180, lean=-5, raise_=180, elbow=20, wrist=20, lraise=175, lelbow=20, hop=4.0, rhip=10, rknee=30, lhip=30, lknee=60), "in"),
    (22, P(AIR, spin=360, lean=25, raise_=178, elbow=60, wrist=35, lraise=172, lelbow=60, hop=4.6), "out"),
    (27, P(LAND, spin=360), "fall"),
    (34, None, None),
])

AXE_OUT = P(lean=-14, raise_=92, swing=-55, elbow=8, wrist=-75, lraise=75, lswing=50, lelbow=15)
ANIMS["axe_Mitica"] = dict(length=40, keys=[  # doble torbellino: dos vueltas seguidas en el aire
    (6, P(spin=-70, turn=-30, lean=-8, raise_=85, swing=-60, elbow=30, wrist=-60, lraise=70, lswing=45, lelbow=25, drop=-0.6, rhip=20, rknee=35, lhip=-20, lknee=35), None),
    (14, P(AXE_OUT, spin=250, hop=1.2), "in"),
    (22, P(AXE_OUT, spin=540, hop=1.6), "lin"),
    (29, P(spin=720, turn=15, lean=-10, raise_=88, swing=-40, elbow=8, wrist=-75, lraise=70, lswing=45, lelbow=15, drop=-0.3), "out"),
    (34, None, None),
])
ANIMS["axe_Secreta"] = dict(length=42, impacts=[26], keys=[  # salto giratorio y hachazo contra el suelo
    (7, P(CROUCH, spin=-40, turn=-30, head=25, raise_=-30, elbow=40, wrist=10, lraise=40, lswing=30, lelbow=40, drop=-0.8, rhip=45, rknee=80, lhip=45, lknee=80), None),
    (15, P(spin=180, lean=-10, raise_=170, elbow=40, wrist=30, lraise=165, lelbow=40, hop=3.0, rhip=30, rknee=60, lhip=20, lknee=70), "in"),
    (21, P(AIR, spin=360, lean=20, raise_=178, elbow=60, wrist=35, lraise=172, lelbow=60, hop=3.2), "out"),
    (26, P(LAND, spin=360), "fall"),
    (34, None, None),
])
ANIMS["axe_Divina"] = dict(length=48, impacts=[35], keys=[  # tornado: sube dando tres vueltas y cae con el hacha
    (8, P(CROUCH, spin=-90, raise_=60, swing=-70, elbow=20, wrist=-40, lraise=60, lswing=70, lelbow=20), None),
    (16, P(spin=360, lean=-10, raise_=90, swing=-80, elbow=5, wrist=-75, lraise=90, lswing=80, lelbow=5, hop=3.0), "in"),
    (24, P(spin=720, lean=-10, raise_=90, swing=-80, elbow=5, wrist=-75, lraise=90, lswing=80, lelbow=5, hop=4.5), "lin"),
    (30, P(AIR, spin=1080, lean=20, raise_=178, elbow=50, wrist=35, lraise=172, lelbow=50, hop=4.2), "out"),
    (35, P(LAND, spin=1080, lean=-48, lunge=1.2, drop=-0.8), "fall"),
    (42, None, None),
])

ANIMS["dual_Mitica"] = dict(length=36, keys=[  # ráfaga cruzada: tres cruces seguidos avanzando
    (4, DUAL_OPEN, None),
    (8, P(DUAL_CROSS, lunge=0.8), "hit"),
    (13, P(DUAL_OPEN, turn=15, lunge=0.8), None),
    (17, P(DUAL_CROSS, lunge=1.6), "hit"),
    (22, P(DUAL_OPEN, lunge=1.6, hop=0.5), None),
    (26, P(DUAL_CROSS, lunge=2.6, lean=-30), "hit"),
    (31, None, None),
])
ANIMS["dual_Secreta"] = dict(length=40, keys=[  # danza de cuchillas: vuelta con los brazos abiertos y cruce desde arriba
    (5, P(DUAL_SPIN, spin=-45, drop=-0.4, rhip=15, rknee=30, lhip=-15, lknee=30), None),
    (12, P(DUAL_SPIN, spin=160, swing=-85, lswing=85, hop=1.2), "in"),
    (19, P(DUAL_SPIN, spin=360, hop=0.6), "out"),
    (24, P(spin=360, lean=15, raise_=170, swing=30, elbow=40, wrist=20, lraise=170, lswing=-30, lelbow=40, lwrist=20, hop=1.0), None),
    (29, P(spin=360, lean=-35, raise_=40, swing=60, elbow=10, wrist=-65, lraise=40, lswing=-60, lelbow=10, lwrist=-65, lunge=2.2, drop=-0.5, rhip=40, rknee=45, lhip=-25, lknee=25), "hit"),
    (35, None, None),
])
ANIMS["dual_Divina"] = dict(length=46, impacts=[29], keys=[  # voltereta de cuchillas: salto mortal y cruce al caer
    (8, P(CROUCH, raise_=-30, swing=-20, elbow=40, lraise=-30, lswing=20, lelbow=40), None),
    (16, P(flip=-180, raise_=170, elbow=20, lraise=170, lelbow=20, hop=4.0, rhip=60, rknee=100, lhip=60, lknee=100), "in"),
    (24, P(AIR, flip=-360, raise_=175, swing=30, elbow=50, wrist=30, lraise=175, lswing=-30, lelbow=50, lwrist=30, hop=4.4), "out"),
    (29, P(LAND, flip=-360, lean=-40, raise_=40, swing=70, elbow=8, wrist=-70, lraise=40, lswing=-70, lelbow=8, lwrist=-70, lunge=1.5), "fall"),
    (37, None, None),
])

ANIMS["spear_Mitica"] = dict(length=40, keys=[  # triple estocada: tres pinchazos seguidos avanzando
    (5, SPEAR_BACK, None),
    (9, P(SPEAR_OUT, lunge=1.2), "hit"),
    (14, P(SPEAR_BACK, lunge=0.6), None),
    (18, P(SPEAR_OUT, lunge=2.2), "hit"),
    (23, P(SPEAR_BACK, lunge=1.4), None),
    (27, P(SPEAR_OUT, lunge=3.6, lean=-35), "hit"),
    (34, None, None),
])
ANIMS["spear_Secreta"] = dict(length=42, keys=[  # remolino y estocada: vuelta con la lanza extendida y pinchazo largo
    (4, P(spin=-50, turn=-25, raise_=80, swing=-50, elbow=20, wrist=-40, lraise=60, lswing=40, drop=-0.5, rhip=20, rknee=30, lhip=-15, lknee=30), None),
    (11, P(spin=160, lean=-8, raise_=88, swing=-45, elbow=5, wrist=-55, lraise=65, lswing=45, hop=0.9), "in"),
    (18, P(spin=360, turn=15, raise_=85, swing=-30, elbow=5, wrist=-55, lraise=60, lswing=40), "out"),
    (23, P(SPEAR_BACK, spin=340), None),
    (28, P(SPEAR_OUT, spin=375, lunge=3.6), "hit"),
    (35, None, None),
])
ANIMS["spear_Divina"] = dict(length=46, impacts=[29], keys=[  # lanza del cielo: salta muy alto y se clava en el suelo
    (8, P(CROUCH, raise_=-40, elbow=60, lraise=40, lelbow=40), None),
    (17, P(spin=180, lean=-5, raise_=175, elbow=5, lraise=150, lelbow=30, hop=4.5, rhip=10, rknee=30, lhip=30, lknee=60), "in"),
    (24, P(AIR, spin=360, lean=-20, raise_=20, lraise=30, lelbow=20, hop=4.8), "out"),
    (29, P(LAND, spin=360, lean=-50, raise_=10, elbow=0, wrist=0, lraise=20, lelbow=10, lunge=1.5, drop=-0.8), "fall"),
    (37, None, None),
])

ANIMS["hammer_Mitica"] = dict(length=44, impacts=[13, 27], keys=[  # doble martillazo
    (8, P(HAMMER_UP, hop=1.5), None),
    (13, HAMMER_DOWN, "hit"),
    (21, P(HAMMER_UP, hop=2.6, spin=10), None),
    (27, P(HAMMER_DOWN, lunge=1.8, spin=0), "hit"),
    (35, None, None),
])
ANIMS["hammer_Secreta"] = dict(length=46, impacts=[27], keys=[  # martillo giratorio: vuelta con el martillo y salto
    (6, P(spin=-60, lean=-8, raise_=85, swing=-60, elbow=20, wrist=-70, lraise=80, lswing=50, lelbow=20, drop=-0.6, rhip=20, rknee=35, lhip=-20, lknee=35), None),
    (14, P(spin=180, lean=-14, raise_=90, swing=-50, elbow=5, wrist=-75, lraise=85, lswing=50, lelbow=10, hop=1.0), "in"),
    (21, P(HAMMER_UP, spin=352), "out"),
    (27, P(HAMMER_DOWN, spin=366, lunge=1.6), "hit"),
    (36, None, None),
])
ANIMS["hammer_Divina"] = dict(length=52, impacts=[32], keys=[  # meteoro: salto mortal enorme y martillazo
    (10, P(CROUCH, lean=28, raise_=-30, elbow=40, wrist=10, lraise=-20, lelbow=40, drop=-1.1, rhip=55, rknee=95, lhip=55, lknee=95), None),
    (19, P(flip=-180, raise_=178, elbow=40, wrist=30, lraise=172, lelbow=40, hop=5.0, rhip=60, rknee=100, lhip=60, lknee=100), "in"),
    (27, P(HAMMER_UP, flip=-360, hop=5.4), "out"),
    (32, P(HAMMER_DOWN, flip=-360, lean=-48, lunge=1.2, drop=-0.8), "fall"),
    (42, None, None),
])

# Interpolación del tramo que LLEGA a la postura (en Blender se pone en el fotograma anterior).
EASES = {
    None: ("BEZIER", "AUTO"),
    "hit": ("BACK", "EASE_OUT"),
    "in": ("QUAD", "EASE_IN"),
    "out": ("QUAD", "EASE_OUT"),
    "fall": ("CUBIC", "EASE_IN"),
    "lin": ("LINEAR", "AUTO"),
}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    bpy.context.scene.timeline_markers.clear()


def material(name, color):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


def build_rig(kind, offset):
    data = bpy.data.armatures.new("R15_" + kind)
    rig = bpy.data.objects.new("R15_" + kind, data)
    rig.location = offset
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail, _ in BONES:
        bone = data.edit_bones.new(name)
        bone.head = r2b(*head)
        bone.tail = r2b(*tail)
        bone.roll = 0
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    data.display_type = "STICK"
    bpy.context.view_layer.update()

    body = material("Cuerpo", (0.95, 0.8, 0.6, 1))
    for name, _, head, tail, size in BONES:
        add_box(rig, name, "Pieza_%s_%s" % (kind, name), (Vector(head) + Vector(tail)) / 2, size, body)
    blade = material("Arma", (0.55, 0.95, 1, 1))
    for index, (bone, center, size) in enumerate(PROPS[kind]):
        add_box(rig, bone, "Arma_%s_%d" % (kind, index), center, size, blade)
    return rig


def add_box(rig, bone_name, name, center, size, mat):
    mesh = bpy.data.meshes.new(name)
    sx, sy, sz = (s / 2 for s in size)
    corners = [r2b(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata([tuple(c) for c in corners], [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bpy.context.view_layer.update()
    obj.matrix_world = rig.matrix_world @ Matrix.Translation(r2b(*center))
    obj.hide_select = True


def fcurves_of(action):
    if hasattr(action, "layers") and len(action.layers) > 0:
        curves = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend(bag.fcurves)
        return curves
    return list(action.fcurves)


def nearest_turn(degrees):
    return round(degrees / 360) * 360


def make_action(rig, name, anim):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action

    # Postura de reposo al principio y al final (con las vueltas enteras que haya dado, para no deshacerlas).
    rest_pose = KIND_REST.get(name.split("_")[0], {})
    keys = [(0, rest_pose, None)] + list(anim["keys"])
    last = next(p for _, p, _ in reversed(keys) if p is not None)
    keys.append((anim["length"], P(rest_pose, spin=nearest_turn(last.get("spin", 0)), flip=nearest_turn(last.get("flip", 0))), None))

    rest = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
    pose = {}
    for frame, values, _ in keys:
        if values is not None:
            pose = values
        angles = joint_angles(pose)
        for pbone in rig.pose.bones:
            set_angles(pbone, rest[pbone.name], angles[pbone.name])
            pbone.keyframe_insert("rotation_euler", frame=frame, group=pbone.name)
        root = rig.pose.bones["Root"]
        move = r2b(0, pose.get("hop", 0) + pose.get("drop", 0), -pose.get("lunge", 0))
        root.location = rest["Root"].inverted() @ move
        root.keyframe_insert("location", frame=frame, group="Root")

    frames = [k[0] for k in keys]
    for fc in fcurves_of(action):
        for point in fc.keyframe_points:
            frame = round(point.co[0])
            if frame in frames:
                index = frames.index(frame)
                step = keys[index + 1][2] if index + 1 < len(keys) else None
                point.interpolation, point.easing = EASES[step]
        fc.update()
    action.frame_range = (0, anim["length"])
    action.use_frame_range = True
    for frame in anim.get("impacts", []):
        bpy.context.scene.timeline_markers.new("impacto:" + name, frame=frame)
    return action


def main():
    clear_scene()
    scene = bpy.context.scene
    scene.render.fps = FPS
    for index, kind in enumerate(PROPS):
        rig = build_rig(kind, r2b(-8 * index, 0, 0))
        first = None
        for name, anim in ANIMS.items():
            if name.split("_")[0] == kind:
                action = make_action(rig, name, anim)
                first = first or action
        rig.animation_data.action = first
        if len(first.slots) > 0:
            rig.animation_data.action_slot = first.slots[0]
    scene.frame_start, scene.frame_end = 0, 52

    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("Guardado en", BLEND_PATH, "-", len(ANIMS), "animaciones")


main()
