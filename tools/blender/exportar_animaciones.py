# Pasa las animaciones de golpe del .blend al juego (src/client/SwingClips.luau). Se lanza tras retocarlas:
#   blender -b "%USERPROFILE%\Documents\Roblox\modelos\animaciones_golpe.blend" --python tools/blender/exportar_animaciones.py
# Exporta cada Acción del muñeco R15, fotograma a fotograma, como el giro de cada articulación en ejes de
# Roblox (y el desplazamiento del Root). El rango de la acción es el golpe entero: el juego lo estira o lo
# encoge a la duración del golpe del arma.
import os

import bpy
from mathutils import Matrix

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "src", "client", "SwingClips.luau")
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Roblox <-> Blender (ver crear_animaciones.py)


def num(value):
    text = "%.4f" % value
    text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def main():
    scene = bpy.context.scene
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]

    lines = [
        "-- GENERADO por tools/blender/exportar_animaciones.py desde animaciones_golpe.blend: no editar a mano.",
        "-- Golpes de cada tipo de arma (<tipo>_<n>, en combo) y épicos por rareza (<tipo>_Mitica/Secreta/Divina).",
        "-- Por articulación, un giro por fotograma (x, y, z, w); el Root lleva además su desplazamiento delante",
        "-- (px, py, pz). impacts = momentos (0 a 1) de los impactos.",
        "return {",
    ]
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        # Cada acción se reproduce en el muñeco de su tipo (todos tienen los mismos huesos).
        rig = bpy.data.objects.get("R15_" + action.name.split("_")[0]) or rigs[0]
        rest = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
        names = [b.name for b in rig.data.bones]
        rig.animation_data_create()
        rig.animation_data.action = action
        if hasattr(action, "slots") and len(action.slots) > 0:
            rig.animation_data.action_slot = action.slots[0]
        start, end = (int(round(f)) for f in action.frame_range)
        length = max(end - start, 1)
        tracks = {name: [] for name in names}
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            for pbone in rig.pose.bones:
                rc = rest[pbone.name]
                basis = pbone.matrix_basis
                rotation = M @ (rc @ basis.to_3x3() @ rc.inverted()) @ M
                q = rotation.to_quaternion()
                values = [q.x, q.y, q.z, q.w]
                if pbone.name == "Root":
                    values = list(M @ (rc @ basis.to_translation())) + values
                tracks[pbone.name].append(", ".join(num(v) for v in values))

        impacts = []
        for marker in scene.timeline_markers:
            if marker.name == "impacto:" + action.name and start <= marker.frame <= end:
                impacts.append(num((marker.frame - start) / length))
        lines.append("\t%s = {" % action.name)
        lines.append("\t\tframes = %d," % (end - start + 1))
        lines.append("\t\timpacts = { %s }," % ", ".join(sorted(impacts, key=float)))
        lines.append("\t\tjoints = {")
        for name in names:
            lines.append("\t\t\t%s = { %s }," % (name, ", ".join(tracks[name])))
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as file:
        file.write("\n".join(lines) + "\n")
    print("Exportado a", os.path.normpath(OUT))


main()
