# Pendiente: PR 2 (sugerencias de comercio) y PR 3 (pasada de UI)

Segunda iteración grande del juego. El **PR 1** (mazmorras con identidad, lobby subterráneo y grupos) ya está en `main`
(#68 y #69). Quedan estas dos partes, **sin empezar**. Decisiones ya tomadas con el usuario: las sugerencias de comercio son
de dos tipos ("Quiero" / "Te doy") y se juntan a `main` tras probar cada PR sin pedir permiso.

**Estado (6 oct 2026):** el **PR 2 está hecho** (rama `comercio-sugerencias`; probado con el bot: aceptar, ignorar, quitar,
caducar, rechazos y spam; falta verlo con dos jugadores reales y no ha pasado revisor Sonnet). Del PR 1 ya pasó el revisor
Sonnet y sus arreglos van en la rama `mazmorras-revision`; sigue sin probarse con dos jugadores reales. **Queda el PR 3.**

Antes de empezar: `git switch main`, `git pull`, `rojo serve`, y leer `CLAUDE.md` (ya está al día con lo del PR 1).
Para la UI, cargar las skills `roblox-ui-engineer` y `roblox-ui-designer`. Pendiente además del PR 1: probar los grupos con
dos jugadores reales y pasar un revisor Sonnet de código.

---

## PR 2 — rama `comercio-sugerencias`

Sin tocar el flujo de 3 pasos ni `problem/take/give/complete`.
- **`shared/Remotes.luau`**: `TradeSuggest` (c→s: `intent` "want"|"give"|nil=quitar, `category`, `key`, `amount`) y `TradeSuggestRespond` (c→s: `accept` bool). La sugerencia viaja dentro de `TradeState` (`you.suggest` / `them.suggest`, con la espada/pieza ya resuelta como en `view()`), sin remote nuevo de servidor a cliente.
- **`shared/Config.luau`** (`Config.Trade`, ampliado): `SuggestCooldown`, `SuggestTime`, `SuggestMaxAmount`, categorías permitidas para "Quiero" (monedas, gemas y objetos: lo intercambiable por cantidad).
- **`server/Trade.luau`** (cambios localizados): `side.suggest = {intent, category, key, amount, seq, at}` fuera de `offer`. `onSuggest` valida: estado `editing`, límite de frecuencia, tipos y `validAmount`; **"Te doy"**: pertenencia real (espada existente y no equipada, pieza de armadura, accesorio, cantidad ≤ lo que tienes); **"Quiero"**: solo categorías cantidad, cantidad ≥1 y ≤ `SuggestMaxAmount` (no se recorta con el inventario del otro, para no filtrar cuánto tiene). Una sugerencia nueva sustituye a la anterior; se borra al cambiar de estado, al cambiar su emisor su oferta, al responderse y al caducar (patrón de `token` de la cuenta atrás). `onSuggestRespond`: **ignorar** = borrar y marcar "ignorada" 2 s; **aceptar** reutiliza un `applyOffer` extraído del cuerpo de `onOffer` (mismas validaciones y el mismo reset de aceptaciones) y aplica: "Quiero" → a la oferta de quien acepta (con lo que tenga, toast si es menos), "Te doy" → a la oferta del emisor (revalidando que sigue siendo suyo). Nunca toca inventarios; el trato sigue exigiendo Aceptar + Confirmar + cuenta atrás. Bot de pruebas: sugiere y responde.
- **`client/Trade.luau`**: botón **"Sugerir"** (con icono, junto a Aceptar/Volver/Cancelar) que activa el modo sugerir: pulsar una casilla del inventario sugiere "Te doy"; en la pestaña de cantidades cada fila gana **[−] cantidad [+]** (pasos ×1/×10/×100 con pulsación larga o botón) y dos botones de enviar ("Quiero" / "Te doy"). Tarjeta de sugerencia recibida (capa propia entre `Z_COUNT` y `Z_INVITE`): cinta "Quiero"/"Te doy" con icono, la casilla del objeto (`swordCell/armorCell/artifactCell/amountCell`, cartel con detalles), cantidad grande, nombre del emisor pequeño, botones ✔ Aceptar / ✖ Ignorar; el emisor ve la suya con "Quitar" y el estado (enviada / ignorada). Sin texto largo: iconos, cantidades y colores. Distinguir mejor los iconos de gemas y de cada cristal (hoy comparten `gemIcon`).
- **Pruebas**: bot y `execute_luau` — sugerir objeto/cantidad, +/−, aceptar (cae en la oferta correcta y se invalida el "aceptado" previo), ignorar, quitar, sugerencia que caduca, que el inventario no cambia hasta completar el trato, rechazos: objeto que no se posee, equipada, cantidad negativa/NaN/enorme, categoría no permitida, estado distinto de `editing`, spam; revisión en captura.
- Docs: `CLAUDE.md` y `docs/diseno.md` (comercio).

## PR 3 — rama `ui-profundidad` (avisar al compañero antes de juntar: toca `Ui` y `Hud`)

Cargar antes `roblox-ui-engineer` y `roblox-ui-designer`; capturas **antes/después** de cada pantalla.
1. **Núcleo en `client/Ui.luau`** (cambios que se propagan a todos los `Ui.button`/`Ui.cell` sin tocar a quien los llama; respetando los acoplamientos ocultos): `Ui.bevel` con labio inferior más grueso y degradado + línea de brillo superior (`Shine`); `Ui.pressable` con hover (más brillo) y pulsado con **compresión** (el labio baja a casi 0 y la cara se hunde ~3 px, 0.95); `AutoButtonColor=false` en `Ui.button`; gancho de `ZIndex` que arregla el relieve de los botones con z manual (X de ventanas, SkillTree, gacha); constantes `Ui.STYLE` (borde, labio, radios, escalas) junto a `Ui.COLORS`; alinear `Ui.cell`/`Ui.panel`/tip/toast/slider a las mismas constantes.
2. **Helpers nuevos** (aditivos): `Ui.pill` (contadores/chips con relieve, borde y sombra), `Ui.iconButton` (botón con **sombra exterior real** y cara que se hunde; devuelve contenedor + botón; para HUD/menú/engranaje), `Ui.setSelected`, `Ui.setEnabled`, `Ui.field` (cajas de texto con degradado), `Ui.coinIcon` (icono de moneda propio).
3. **HUD (`Hud.luau`)**: contadores de monedas/gemas con `Ui.pill` (icono con zócalo, sombra, destello), `StatsDock` pasa a `Ui.panel` (hoy es el elemento más plano), botones de transporte/menú y engranaje con `Ui.iconButton`; sin cambiar información ni nombres de instancia (`Hud.HudRoot.Coins`, `.Travel.Travel_*`…). El botón "Mazmorra" pasa a "Mazmorras".
4. **Barrido de coherencia**: pestañas de Backpack/Trade con `Ui.setSelected`; paneles sueltos (Backpack `count/bar`, ArmorPane, Missions, PassShop, Dungeons, GachaRoll, SkillTree, Trade) a `Ui.panel`; campos de texto (Settings, Trade) con `Ui.field`; la ventana de Party y las tarjetas de sugerencia ya nacen con el estilo nuevo; sonido de hover suave (`tick`) y de abrir/cerrar ventana con `Sfx`.
5. Todo respeta `Performance.get()`; sin Neon ni arcoíris nuevos; comprobar en el `HudRoot` reducido (escala 0.55) que las líneas finas no desaparecen.
6. **Segunda pasada visual**: capturas de HUD, botones, mochila, comercio, party, mazmorras, gacha, tiendas, tooltips y menús → revisor Haiku sobre los `.jpg`; arreglar lo que siga plano o desentone; revisor Sonnet sobre el código.

---

---

## Reutilizo (no reinvento)

`Config`/`Remotes` (centrales), `PlayerData.read/edit`, `Loot.roll/summary`, `Destructibles.reaches`, `block/disc` de `Dungeons`, patrón `ShopSign`/`ProximityPrompt Shop=` de `ModifierShops`, patrón de etiquetas `Station*` → `DungeonFx`, `TradeInvite` como molde de la invitación de party, `swordCell/armorCell/artifactCell/amountCell` de `client/Trade`, `Ui.window/button/cell/panel/tip/toast`, `Format`, `Performance.get()`, patrón de límite de frecuencia por jugador (`last[player]`) de `Rebirth/Teleport/Gacha`, `Config.Test.*` como modo de pruebas.

## Verificación

- **Arranque de sesión**: Rojo ya responde (`:34872`); pedir "Rojo → Connect" si Studio no conecta (Studio abierto = "Place1"); `git switch -c mazmorras-lobby-party`; mirar `get_studio_state` y parar un Play ajeno; comprobar con `execute_luau` que el cambio ha llegado a Studio antes de dar a Jugar; leer errores con `LogService:GetLogHistory()`; parar siempre el Play.
- **PR 1**: las 12 mazmorras con su nombre/aspecto (capturas), arma/armadura y recompensas igual que antes; lobby: bajar/subir sin caer, 12 salas, perfil de luz; party: los casos de la lista del usuario (crear, unirse, salir, líder se va, desconexión, iniciar, límite de tamaño, peticiones no autorizadas rechazadas, entrada tardía rechazada) con bots + peticiones falsas; que `Combat`/armaduras/stats siguen igual (entrar solo y superar la 1ª como antes). **Lo que un Studio con un solo jugador no puede cubrir** (daño/bajas/premios de dos jugadores reales, `Hit`/`Broken` a todos): lo pediré como prueba manual con Studio "Test → 2 jugadores" o un amigo, y lo dejaré anotado como sin probar si no se hace.
- **PR 2**: casos de la lista del usuario con bot y `execute_luau`; inventario intacto hasta completar el trato.
- **PR 3**: antes/después de cada pantalla, hover/pulsado con `user_mouse_input`, modo rendimiento activado/desactivado, revisores Haiku/Sonnet.
- Cada PR: probar → commit (con `Co-Authored-By`) → `git push` → `gh pr create --fill` → `gh pr merge --squash --delete-branch`, y dejar `main` funcionando.

## Riesgos y decisiones abiertas (a mi criterio, avisaré en el resumen)

- **CSG en runtime** (hito 0) decide entre cortar o teselar el suelo; ambos están previstos.
- Luz bajo la isla y rendimiento (muchas piezas de lobby + arenas): medir; modo rendimiento recorta efectos.
- Equilibrio: escalado de vida/cantidad por jugador y premios por miembro son a ojo en `Config.Party.Scaling`, igual que el resto del juego.
- Sin probar con dos jugadores reales hasta que el usuario lo haga; guardado de armadura sigue sin probarse (como ya constaba).
- Fuera de alcance por ahora: habilidades especiales de jefes, desbloqueo por progreso, volver a jugar con la misma party, respuestas rápidas con emojis en el comercio.

---

## Apuntes de la exploración (para no volver a buscarlos)

**Comercio (`server/Trade`, `client/Trade`)**
- La sesión es `{ sides, state, ends, token }`; `side.offer` es lo único que leen `problem/take/give/complete`, así que una sugerencia guardada fuera de `offer` no puede tocar inventarios.
- `view(side)` ya resuelve espadas y armadura para el cliente: la sugerencia puede viajar dentro de `TradeState` (`you.suggest` / `them.suggest`).
- `onOffer` tiene la validación (`validAmount`, pertenencia, espada equipada no se ofrece): extraerla a `applyOffer` para reutilizarla al aceptar una sugerencia.
- Solo `TradeRequest` tiene límite de frecuencia; el patrón es `last[player] = os.clock()` (ver `Rebirth`, `Party`).
- Cliente: casillas reutilizables `swordCell`, `armorCell`, `artifactCell`, `amountCell`; las cantidades son un `TextBox` por fila (`Format.parse`), sin +/−; la fila de pestañas está llena; capas propias `Z_COUNT` = 30 y `Z_INVITE` = 70 (la tarjeta de sugerencia va entre las dos). Gemas y cristales comparten `Ui.gemIcon`: conviene distinguirlos.
- Probar con `Config.Test.TradeBot` (ampliar el bot para que sugiera y responda) y con `TradeSuggest:FireServer(...)` desde `execute_luau`.

**UI (`client/Ui`, `client/Hud`)**
- Todo botón visible pasa por `Ui.button` (~38 usos): cambiar `Ui.bevel`, `Ui.pressable` o `Ui.button` llega a todo el juego.
- Acoplamientos ocultos a respetar: el primer `UIStroke` directo de un `Ui.button`/`Ui.cell` es el borde (`Backpack`, `Trade`, `ArmorPane` lo buscan con `FindFirstChildOfClass("UIStroke")`); `FindFirstChild("PressScale")` en `Backpack`; el hijo `Select` de las casillas; los nombres `Rim`, `Gloss`, `Base`; los internos de `Ui.window` (`Header`, `Title`, `Body`) que usa `ModifierShops`; `Hud.HudRoot.Coins`, `.Gems`, `.Travel.Travel_*`, `.StatsDock`, `.Menu.*` (los usan las pruebas).
- La interfaz ordena el ZIndex globalmente: los botones con `.ZIndex` puesto a mano (X de las ventanas, `SkillTree`, "Continuar" del gacha) dejan el relieve por debajo; arreglarlo con un gancho de `ZIndex` en `Ui.bevel` o con `Ui.layer`.
- Lo más plano hoy: la caja de estadísticas (`Hud.luau` ~284, degradado y borde a mano en vez de `Ui.panel`), los iconos sin zócalo y unos 12 paneles sueltos (Backpack `count/bar`, `ArmorPane`, `Missions`, `PassShop`, `GachaRoll`, `SkillTree`, `Trade`).
- La sombra exterior no cabe dentro de `Ui.button` (devuelve el propio `TextButton` que los llamadores colocan): hace falta un contenedor, de ahí `Ui.iconButton`.
- El degradado del bevel tiñe también el texto de los botones que lo llevan en el propio botón: para texto nítido, `Ui.label` hija.
- `HudRoot` baja hasta escala 0.55: las líneas de menos de 2 px casi desaparecen en móvil. Todo bucle o animación nuevos respetan `Performance.get()`.
- Dos personas tocan `Ui` y `Hud`: cambios pequeños y avisar al compañero antes de juntar el PR 3.
