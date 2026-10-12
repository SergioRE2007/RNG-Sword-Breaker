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

- [x] Parte 1: sistema y datos (hecha el 12 de octubre de 2026; notas debajo)
- [x] Parte 2: ventanas (hecha el 12 de octubre de 2026; notas al final)
- [x] Parte 3: HUD, mundo y servidor (hecha el 12 de octubre de 2026; notas al final)
- [x] Parte 4: repaso (hecha el 12 de octubre de 2026; notas al final)

## Notas de la parte 1 (para las siguientes)

- `Lang.t(jugador, texto, huecos)`, `Lang.code(jugador)` y `Lang.decimal(jugador, número ya escrito)` están en `src/shared/Lang`; el español, en `src/shared/LangEs` (por secciones, en el orden de `Config`). En el cliente el idioma es siempre el del jugador local; en el servidor, sin jugador, sale inglés.
- `Config` y `MissionList` ya están en inglés, pero quien enseña un `name`, `desc`, `text`, `tag`... tal cual lo saca en inglés para todos hasta que lo pase por `Lang.t(nil, entrada.name)`: es lo que toca en las partes 2 y 3. Ojo también con `Config.StatNames` (`Backpack`, `Trade`) y con `title` y `label` de `Modifiers.KINDS`.
- Las funciones de `shared` que montan textos llevan un último argumento opcional, el jugador que lo va a leer: `Permanent.name` y `describeOdds`, `Modifiers.effect` y `formatPercent`, `ArmorStats.name`, `value` y `text`, `DungeonInfo.rewards` y `lock`, `PotionInfo.name` y `effect`, `WeatherInfo.oddsText`, `buffs` y `buffText`, `Format.short` y `multiplier`. En el cliente no hace falta pasarlo; en el servidor sí (parte 3), o el aviso sale en inglés.
- Números: `Format` pone coma decimal a quien juega en español ("1,23K"; antes salía con punto) y `Format.parse` entiende las dos.
- El "set" de armadura de `Config.Dungeons` es ahora la frase entera con hueco (`"Leather {slot}"` → `"{slot} de cuero"`), porque en inglés el orden cambia; se monta con `ArmorStats.name`.
- El rasgo "Eterno" es "Timeless" en inglés: "Eternal" ya es la rareza "Eterna" y una clave no puede tener dos traducciones. Si dos textos españoles distintos piden el mismo inglés, hay que cambiar uno de los dos ingleses.
- Los textos iguales en los dos idiomas ("VIP", "Aurora", "x2", los grados) también tienen su entrada en `LangEs`, para que no salte el aviso de texto sin traducir.
- El código de regalo `LANZAMIENTO` se queda como está: es un código que ya vale.
- `tests/regressions.luau`: la prueba de "ningún texto en español entre comillas" mira solo las carpetas de su lista `DONE` (de momento `src/shared`); al acabar las partes 2 y 3, poner `src` entero. También comprueba que todo texto de `Config` tiene su entrada en `LangEs`: una lista nueva de `Config` con textos se añade ahí.

## Notas de la parte 2 (para las siguientes)

- Las 16 ventanas ya pasan todo por `Lang.t(nil, ...)`; sus textos en español están al final de `LangEs`, una sección "Ventana X" por archivo. Probado en Studio con `Config.Test.Lang` en `"en"` y en `"es"`: sin avisos de textos que falten.
- Las ventanas de las tiendas de Rasgos y Grados se llaman `Hud.Traits` y `Hud.Grades` desde la parte 1 (su nombre sale de `Modifiers.KINDS[...].title`); `CLAUDE.md` aún dice `Hud.Rasgos` y `Hud.Grados`: corregirlo en la parte 4.
- Un mismo inglés no puede tener dos españoles, así que hay ingleses distintos a propósito: "Rebirth" (título) y "Rebirth now" (botón Renacer); "Empty" (Vacío), "Nothing equipped" (Vacía) y "Take all out" (Vaciar); "Equipped {n}/{max}" (Equipadas, armas) y "Wearing {n}/{max}" (Equipados, accesorios); "Pick a sword" y "Pick sword"; "Unequip" y "Remove" (los dos "Quitar").
- Los plurales van con dos frases enteras ("{n} piece will be salvaged..." y "{n} pieces will be salvaged..."), no con trozos.
- Quedan para la parte 3, aunque se vean dentro de ventanas: los carteles de `Potions.tip`, el título y la mazmorra que `client/Dungeons` le pasa a `DropMenu.show`, el `StatsDock` de Mejoras (lo monta `Hud`) y los avisos que manda el servidor al comprar, canjear o comerciar.
- `tests/regressions.luau`: la prueba de "ningún texto en español" mira ya `src/shared` y, de `src/client`, los archivos de su lista `WINDOWS`; al acabar la parte 3 se quita la lista y se mira todo `src`. Las piezas del martillo de la forja tenían una con ñ en el nombre ("Puño"): ahora es "Pomo".
- Herramienta que ayudó: listar los textos entre comillas de un archivo fuera de los comentarios (un script de Node de usar y tirar) y mirar aparte los `.name`, `.desc`, `.short`, `.tag`... que se enseñan sin comillas; estos últimos son los que más se escapan.

## Notas de la parte 3 (para la 4)

- Avisos del servidor: librería nueva `server/Tell`. `Tell.notice(jugador, color, "Frase {hueco}", { hueco = ... })` para uno y `Tell.all(color, function(lector) return Lang.t(lector, ...) end)` para todos, cada uno en su idioma (ya no se usa `Announce:FireAllClients`). Los nombres que van dentro (objeto, arma, pase) se pasan ya traducidos para ese lector. Un motivo que se decide lejos de donde se manda (por qué no se puede entrar a una mazmorra o cerrar un trato) es la frase en inglés o una función `(lector) -> texto`; `Tell.text` la resuelve.
- Carteles del mundo y avisos de E (una sola pieza para todos): el servidor deja la frase en inglés en atributos con `Tell.world(etiqueta, frase, huecos, mayúsculas)` y `Tell.prompt(aviso, acción, objeto)` (etiqueta `LangText`) y el módulo nuevo `client/WorldText` la escribe en el idioma de cada jugador. Van así: parcelas, "MAZMORRAS" (boca y templo), Mejor tirada, clasificaciones, tiendas del hub, ascensor de luz y salas de grupo. Un cartel nuevo hecho en el servidor se pone con `Tell.world`, no con `.Text`.
- Los `warn` de consola están en inglés (no los lee el jugador y la prueba no deja tildes entre comillas); sin entrada en `LangEs`.
- El marcador de la lista de jugadores (`leaderstats`) se llama ahora "Coins" (antes "Monedas"): no pasa por `Lang`, lo traduce Roblox si acaso.
- Ingleses distintos a propósito, como en la parte 2: el botón del menú es "Rebirths" (Renacer; "Rebirth" ya es Renacimiento) y las estadísticas de Mejoras son "Luck (objects)" y "Luck (weapons)" (Suerte objetos / Suerte armas; "Object luck" y "Weapon luck" ya son las largas).
- Arreglado de paso, roto desde la parte 1: `WeatherHud` elegía el color de la suerte de armas comparando con el texto "Armas" (ahora `buff.stat`, que da `WeatherInfo.buffs`), y `SwingAnim` (que no se arranca) buscaba las rarezas por su nombre en español.
- `tests/regressions.luau`: la prueba de "ningún texto en español" mira ya todo `src`; solo deja pasar las letras sueltas (las tablas que suben las tildes a mayúsculas).
- Probado en Studio con `Config.Test.Lang` en `"en"` y en `"es"`: menú, transporte, estadísticas, cartel del objeto, carteles del mundo, avisos (código, poción, renacer, mejor tirada, trato cancelado) y panel de mazmorra, sin avisos de textos que falten. Sin mirar con capturas: si algún texto en inglés no cabe (parte 4). Tampoco se han visto en marcha el cartel de reconexión, el del autoclicker ni la tirada gratis antigua (`GachaRoll`).
- Para la parte 4, además de lo que ya dice: `CLAUDE.md` habla de `Remotes.Announce:FireAllClients`, de textos en español en ejemplos de prueba ("Quiero 5 Cristal de rasgo", "Botín añadido a tu inventario") y de `Hud.Rasgos`/`Hud.Grados`; añadir allí `Tell` y `WorldText`. El nombre del bot de comercio es "Test bot".

## Notas de la parte 4

- Repaso en Studio con `Config.Test.Lang` en `"en"` y en `"es"`: HUD, las ventanas (mochila, tienda, renacer, ajustes, comercio con el bot, misiones, rasgos, grados, índice, grupo, bolsa, venta, admin, carteles de autoclicker y reconexión), carteles y avisos de E del mundo y una mazmorra entera con su cartel y su menú de botín. Con capturas las de más texto y, todas, con un recorrido por código de los textos de `PlayerGui` (`TextFits`, palabras del otro idioma) y `LogService`: ni mezclas de idioma ni entradas que falten.
- Lo único que no cabía: el detalle del cartel de reconexión en inglés (tres líneas en sitio para dos). Se acortó el inglés ("Keeps Roblox from kicking you for being idle...").
- Roblox: los ocho pases y los tres productos tienen ya nombre y descripción en inglés (Open Cloud, `PATCH` con `name` y `description`).
- Pendiente, del usuario en el Creator Hub: nombre y descripción del juego en inglés, la traducción al español de juego, pases y productos en la tabla de localización de Roblox, y activar la captura y la traducción automáticas para los demás idiomas (sin el español).
- Sin ver en marcha: la tirada gratis antigua (`GachaRoll`, apagada con `FreeRoll = false`) y los textos del juego publicado con una cuenta de verdad en inglés (en Studio el idioma se fuerza).
- `CLAUDE.md` tiene una sección "Idioma" con las reglas; los textos de pantalla que cita en otras secciones siguen siendo los españoles.
