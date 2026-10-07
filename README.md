# mi-juego

Incremental de espadas para Roblox, estilo RNG. Cada jugador tiene una parcela donde aparecen objetos; los rompe a espadazos, gana monedas y mejora la parcela para que salgan objetos más raros. Las armas salen de los propios objetos al romperlos, con más suerte cuanto más raro y más grande es el objeto; los objetos raros sueltan además gemas.

Todo el juego es código: no hay nada colocado a mano en Studio ni modelos propios. El código vive en `src/` y [Rojo](https://rojo.space) lo mete en Studio.

- **`CLAUDE.md`** — instrucciones para Claude: cómo arrancar, cómo probar, reglas del código. Claude lo lee solo al abrir la carpeta.
- **`docs/diseno.md`** — qué hace el juego, qué está hecho, qué está sin probar y las ideas pendientes.

## Puesta en marcha (primera vez)

1. Instalar [Git](https://git-scm.com), [Rokit](https://github.com/rojo-rbx/rokit) y Roblox Studio.
2. Clonar el repo y, dentro de la carpeta, ejecutar `rokit install` (instala Rojo 7.7.1, la versión fijada en `rokit.toml`).
3. Instalar el plugin de Rojo en Studio: `rojo plugin install`.
4. Para que Claude pueda probar el juego, tener configurado el MCP `Roblox_Studio`.

## Cada vez que te pones a trabajar

1. `git pull` para bajar lo último.
2. `rojo serve` en la carpeta del proyecto (puerto 34872).
3. En Studio: **Nuevo → Baseplate** y luego **Plugins → Rojo → Connect**.

El archivo del lugar (`.rbxl`) no se sube al repo: cada uno usa el suyo. Se puede guardar en la carpeta para no crear un Baseplate cada vez; Git lo ignora.

## Estructura

```
src/shared/   → ReplicatedStorage.Shared          (lo ven servidor y cliente)
src/server/   → ServerScriptService.Server        (la lógica; el servidor manda)
src/client/   → StarterPlayerScripts.Client       (interfaz y efectos)
```

Cada sistema es un módulo con `start()`, y el `init` de su carpeta lo arranca. El detalle de cada módulo está en `CLAUDE.md`.

### Zonas de trabajo

Cada zona tiene sus archivos. Si cada uno se queda en la suya, no hay conflictos.

| Zona | Servidor | Cliente | Shared |
|---|---|---|---|
| **Armas** (modelos, golpe, auras, mochila) | `Swords`, `Gear` | `Backpack`, `WeaponPreview`, `WeaponAura`, `SwingAnim`, `SwordController` | `SwordModel` |
| **Gacha y modificadores** (rasgos, grados, tiendas, estaciones del hub) | `Gacha`, `Traits`, `ModifierShops`, `Stations`, `StallSkin` | `GachaRoll`, `ModifierShops`, `ForgeScene`, `StationFx` | `Modifiers` |
| **Mejoras** | `Shop` | `SkillTree` | `Upgrades` |
| **Mapa y objetos** | `Plots`, `Scenery`, `Destructibles` | `Ambience` | — |
| **Combate y efectos** | `Combat`, `Movement`, `CollisionGroups` | `Effects` | `Chance` |
| **Mazmorras y grupos** (zonas, lobby subterráneo, partidas cooperativas) | `Dungeons`, `DungeonLobby`, `DungeonThemes`, `Party` | `Dungeons`, `Party`, `DungeonFx`, `RoomSigns`, `DungeonCard` | `DungeonInfo` |

### Archivos compartidos (cuidado)

Estos los toca cualquier zona, así que es donde pueden chocar dos personas:

- `shared/Config` — todos los números. Tocar solo la sección de tu zona.
- `shared/Stats` — daño y suertes finales. Cualquier bonus nuevo se suma aquí.
- `shared/Remotes` — lista de RemoteEvents.
- `server/PlayerData` — datos y guardado del jugador.
- `client/Ui` y `client/Hud` — estilo de la interfaz y contadores.
- `init.server.luau` e `init.client.luau` — una línea por cada módulo nuevo.
- `docs/diseno.md` y `CLAUDE.md`.

En estos, cambios pequeños y subirlos pronto. Un cambio grande (reorganizar `Config`, cambiar el formato de `PlayerData`, rehacer `Ui`) se avisa antes al otro.

## Cómo trabajamos entre dos

1. **Repartir por zonas** antes de empezar: uno coge espadas, otro mejoras o mapa. Se dice por el chat qué coge cada uno.
2. **Una rama por funcionalidad**, nunca directamente en `main`:
   `git switch -c espadas-tirada-multiple`
3. **Antes de empezar**, bajar lo último: `git switch main` y `git pull`.
4. **Al terminar y haber probado en Studio**, subir la rama y juntarla con `main`:
   `git push -u origin <rama>` y `gh pr create --fill`, luego `gh pr merge --squash --delete-branch`.
5. **Ramas cortas**: una funcionalidad, un día o dos como mucho. Cuanto más vive una rama, más fácil que choque.
6. Si al juntar hay conflicto, Claude lo resuelve; casi siempre será en `Config` o en `docs/diseno.md` y basta con quedarse con las dos partes.

`main` tiene que funcionar siempre: no se junta nada sin haberle dado a Jugar y mirado que no hay errores.

`Config.Test.InfiniteMoney` (dinero infinito en Studio) es para pruebas; no subir cambios de valores bajados temporalmente para probar (rarezas, vidas).
