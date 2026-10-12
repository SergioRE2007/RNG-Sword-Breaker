# Plan: el juego en inglés, con el español guardado

Pedido por el usuario (12 de octubre de 2026): **todos** los textos del juego pasan a inglés. La versión española de ahora se guarda y le sale sola a quien tenga Roblox en español (cualquier país). Los demás idiomas los traduce Roblox a partir del inglés.

Se hace en varios chats, una rama por parte, probando y juntando con `main` al acabar cada una. Al terminar una parte, marcarla aquí como hecha y apuntar lo que haya quedado pendiente.

## Cómo se hace

Estilo "gettext": en el código queda el texto en inglés y una tabla lo pasa a español. No hay claves inventadas.

- Módulo nuevo `src/shared/Lang` (librería, sin `start()`), que vale en servidor y cliente:
  - `Lang.t(jugador o nil, "Texto en inglés con {n}", { n = 5 })`: devuelve el texto en el idioma del jugador con los huecos rellenos. En el cliente, sin jugador, es el idioma del `LocalPlayer`.
  - `Lang.es` (en un archivo aparte, `src/shared/LangEs`): tabla `["English text {n}"] = "Texto en español {n}"`. Si falta una entrada sale el inglés y, en Studio, un `warn` con el texto que falta.
  - `Lang.code(jugador)`: `"es"` si su idioma empieza por `es`, si no `"en"`. En el cliente se lee `LocalizationService.RobloxLocaleId`; en el servidor, `player.LocaleId`.
  - `Config.Test.Lang = "en"` o `"es"` (solo Studio) fuerza el idioma para probar; vacío, el de la cuenta.
- El español de ahora no se reescribe: cada texto que se traduce al inglés se copia tal cual a `LangEs`. Es lo que pidió el usuario: guardar la versión que hay.
- Textos con trozos pegados (`"x" .. n .. " de monedas"`) se convierten en una sola frase con huecos (`"x{n} coins"`): en otro idioma el orden cambia.
- `Config`: los `name`, `description`, `perksText`, `tag`, `ribbon`, `short`, `desc`, `text` y demás textos se quedan donde están, en inglés. Quien los enseña los pasa por `Lang.t`. No mover datos de `Config` a otro archivo ni reordenar listas (lo guardado usa posiciones).
- Servidor: los avisos (`Notice`, `Announce`, `BagEvent`, tutorial, códigos, comercio...) se montan con `Lang.t(jugador, ...)`, uno por jugador. Un `Announce` a todos se manda en bucle, cada uno en su idioma.
- Números: en español "x1,5", en inglés "x1.5". `Format` necesita saber el idioma (los sufijos K, M, B... valen para los dos). Revisar `Format.multiplier` y `Format.parse`.
- `Ui.caps` sigue poniendo las mayúsculas; comprobar que no rompe nada con el inglés.
- Los comentarios del código siguen en español.
- Lo guardado no lleva textos (va por posiciones e ids): comprobarlo al empezar con una búsqueda en `PlayerData`, y si algo guarda un nombre, mantener compatibilidad.

## Los demás idiomas (Roblox)

- En el Creator Hub → Localización del juego: idioma de origen inglés, captura automática de texto y traducción automática activadas para los idiomas que quiera el usuario. Lo activa él; decirle dónde.
- El español **no** se activa ahí como traducción automática: ya lo pone el juego. Si la captura automática recoge frases en español, borrarlas de la tabla.
- Aviso ya dado al usuario: Roblox traduce bien los textos fijos; los que llevan números dentro pueden quedarse en inglés en esos idiomas. No prometer más.
- Fuera del código, a mano o con Open Cloud (clave en `Documents\Roblox\clave-roblox.txt`): nombre y descripción del juego, de los ocho pases y de los tres productos, en inglés y con su traducción al español en la tabla de localización de Roblox.

## Partes

1. **Sistema y datos.** `Lang`, `LangEs`, `Config.Test.Lang`, `Format` por idioma y todo `Config` (armas, metales, tamaños, rarezas, rasgos, grados, accesorios, objetos, mazmorras, enemigos, armadura, pociones, mejoras, pases, productos, misiones, tutorial, clima, códigos) y los módulos de `shared` que montan textos (`Rarity`, `Modifiers`, `ArmorStats`, `DungeonInfo`, `PotionInfo`, `WeatherInfo`, `Permanent.describeOdds`, `MissionList`, `IndexInfo`, `BagInfo`). Al acabar, lo que ya pase por `Lang` sale en inglés y el resto sigue en español: es normal.
2. **Ventanas.** `Backpack`, `ArmorPane`, `PassShop`, `Trade`, `ModifierShops`, `ForgeScene`, `Index`, `Missions`, `Party`, `BagMenu`, `SellMenu`, `DropMenu`, `Settings`, `Rebirth`, `SkillTree`, `AdminPanel`.
3. **HUD, mundo y servidor.** `Hud`, `MenuTile`, `AutoPlay`, `Potions`, `WeatherHud`, `Tutorial`, `Rejoin`, `Dungeons`, `RoomSigns`, `ObjectInfo`, `RollReveal`, `GachaRoll`, `GoldBag`, `Clover`, `ChatTags`, carteles del mapa (`TempleEntrance` "MAZMORRAS", `BestRoll`, estaciones) y todos los avisos del servidor.
4. **Repaso.** Una partida entera con `Config.Test.Lang = "en"` y otra con `"es"`, mirando cada ventana: textos que no caben (el inglés suele ser más corto, pero no siempre), mezclas de idiomas y avisos. Pases y productos en el Creator Hub. Actualizar `CLAUDE.md` (la regla "textos de interfaz en español" pasa a ser "en inglés en el código, español en `LangEs`") y `README.md`.

## Comprobaciones

- Prueba nueva en `tests/regressions.luau`: ningún texto entre comillas de `src/` (fuera de `LangEs` y de los comentarios) lleva á, é, í, ó, ú, ñ, ¿ ni ¡; y toda frase de `LangEs` tiene los mismos huecos `{...}` que su clave.
- Las regresiones que comparan textos en español hay que pasarlas al inglés o fijarles el idioma.
- En Studio: `Config.Test.Lang` en los dos valores, capturas de las ventanas tocadas y `LogService` sin avisos de textos que faltan.

## Estado

- [ ] Parte 1: sistema y datos
- [ ] Parte 2: ventanas
- [ ] Parte 3: HUD, mundo y servidor
- [ ] Parte 4: repaso
