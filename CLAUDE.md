# mi-juego — incremental de espadas (Roblox)

Cada jugador tiene una parcela donde aparecen objetos; los rompe a espadazos, gana monedas y mejora la parcela (más objetos, más suerte) para que salgan objetos más raros. Los raros sueltan gemas, que pagan el gacha de espadas del hub. Estilo juego RNG. El usuario habla español y no programa: todo el código lo escribe Claude. Diseño y pendientes en `docs/diseno.md`.

## Sobre el usuario

- Le preocupa el gasto de tokens: respuestas cortas, leer solo los archivos necesarios, una funcionalidad por conversación.
- Le gustan las físicas y los juegos RNG. Da ideas a grandes rasgos y espera que Claude proponga los detalles, los construya y los pruebe.
- Quiere una base sólida que se pueda ampliar; no hay modelos ni sonidos propios, todo se hace con piezas y código.

## Trabajo en equipo

Trabajan dos personas, cada una con su Claude y su Studio (reparto de zonas y archivos compartidos en `README.md`).

- Al empezar: `git switch main` y `git pull`. Una rama por funcionalidad, nunca commits directos en `main`.
- Al terminar y haber probado: commit, `git push`, PR con `gh pr create --fill` y `gh pr merge --squash --delete-branch`. Preguntar antes de juntar con `main`.
- Quedarse en los archivos de la zona de la tarea. En los compartidos (`Config`, `Stats`, `Remotes`, `PlayerData`, `Ui`, `Hud`, los `init`, `docs/diseno.md`) hacer cambios pequeños y no reordenar ni reformatear lo que no se toca.
- No subir valores de `Config` bajados temporalmente para probar.

## Al empezar una sesión

0. `git pull` (ver "Trabajo en equipo").
1. Arrancar `rojo serve` en segundo plano en esta carpeta y comprobar que responde en `http://localhost:34872/api/rojo`.
2. `list_roblox_studios` para obtener el `studio_id` del Studio abierto (`mi-juego`).
3. Si Studio no tiene conexiones al puerto 34872, pedir al usuario que pulse Rojo → Connect.

Entorno: Windows, PowerShell, Rojo 7.7.1 instalado con Rokit. Git y GitHub CLI (`gh`) instalados; repo privado `SergioRE2007/mi-juego`, rama `main`. El archivo del lugar (`.rbxl`) no se sube. El lugar no está publicado (`PlaceId` 0), así que el guardado no actúa.

## Cómo trabajar

- El código vive en `src/` y Rojo lo sincroniza a Studio (`rojo serve`, puerto 34872). Edita siempre los archivos, nunca los scripts dentro de Studio.
- Usa el MCP `Roblox_Studio` solo para probar (play, consola, captura). No vuelques el árbol entero del juego: es muy caro en tokens.
- El mapa se genera por código (`Plots`, `Scenery` y `Destructibles`), no hay nada colocado a mano salvo `Baseplate` y `SpawnLocation` (que `Scenery` repinta y esconde al arrancar). La iluminación también se pone por código en `Scenery`.
- Textos de interfaz y comentarios en español.
- Estilo visual "simulador de Roblox" (el usuario pasó capturas de referencia de otros juegos RNG): ventanas oscuras con cabecera degradada y borde negro grueso, inventarios en casillas cuadradas con el borde del color de la rareza y cartel al pasar el ratón, botones de color con relieve, fuente `FredokaOne` con borde negro. Nada plano: siempre degradado y borde. Usar los helpers de `client/Ui`, no crear estilos sueltos.
- Colores vivos pero sin pasarse: el usuario se quejó de un primer intento con neones y saturación alta. Nada de `Neon` en piezas grandes del mapa.

## Cómo probar

- `start_stop_play` para entrar y salir del modo juego; pararlo siempre al terminar.
- Para simular al jugador, `execute_luau` en el datamodel `Client`: mover el personaje con `PivotTo` y disparar los remotes (`ReplicatedStorage.Remotes.Swing:FireServer()`, `BuyUpgrade:FireServer("capacity")`), luego leer los atributos del `Player`.
- Desde `execute_luau` un `require` de un módulo del servidor devuelve una copia distinta, sin el estado del juego: no sirve para dar cosas ni leer sesiones. El estado se lee de los atributos del `Player`.
- Modo de pruebas (pedido por el usuario): `Config.Test.InfiniteMoney = true` da monedas y gemas infinitas al darle a Jugar en Studio (solo en Studio, y esa partida no se guarda). Con eso se compran mejoras y tiradas sin tener que ganar nada; para probar precios o progreso real, ponerlo a `false` un momento. `Config.Test.AllWeapons = true` (también pedido por el usuario) mete en la mochila una copia de cada arma de `Config.Swords` al entrar; la copia de un arma se equipa con `EquipSword:FireServer(id)`, y en una partida nueva el id coincide con el índice del arma.
- Para probar cosas raras (objetos raros, roca de armas, cristales, artefactos): con el juego parado, bajar temporalmente `rarity` y `hp` en `Config`, probar y restaurar los valores. Rojo no aplica cambios a una partida en marcha, y un archivo recién creado puede tardar unos segundos en llegar a Studio: si falta al entrar en juego, parar y volver a entrar.
- Para probar un arma concreta sin que salga en el gacha, en el datamodel `Server`: `player:SetAttribute("Swords", "1:<índice>:0")`, `SetAttribute("Equipped", 1)` y `SetAttribute("SwordLevel", <índice>)` (reconstruye la herramienta; el daño y el alcance reales siguen siendo los de la sesión). Para ver una postura del golpe, en `Client`: `require(PlayerScripts.Client.SwingAnim)`, `start()` y `play(personaje, 17.4, "spear")` dura 20 s.
- El gacha es gratis y se tira desde cualquier sitio: `RollGacha:FireServer()` (una vez cada `Stats.rollTime`). Para ver una rareza concreta sin depender de la suerte, tirada falsa desde el `Server`: `Remotes.GachaRolled:FireClient(jugador, índiceEspada, true, suerte, "gacha")` (con rareza / suerte ≥ `Config.Gacha.ShowcaseOdds` sale la animación grande) y `Remotes.GachaAura:FireAllClients(jugador, índiceEspada, probabilidadReal)` para el aura del personaje (las tiradas falsas no mandan aura: la de verdad la manda el servidor cuando el cliente avisa con `GachaRevealed` de que la ha destapado); Las espadas van por id de copia (el primer número de cada entrada del atributo `Swords`): `EquipSword:FireServer(id)`, `SellSword:FireServer(id)`, `RollTrait:FireServer(id)` (gasta un cristal), `SetAutoSell:FireServer(rareza)`. `ToggleGear:FireServer(indiceArtefacto)` equipa o quita un artefacto.
- Errores: `LogService:GetLogHistory()` filtrando los mensajes que no sean `MessageOutput`. `get_console_output` trae mucho ruido de la automatización.
- Para ver el mapa entero en modo juego, `screen_capture` con `camera_position` no sirve (la cámara del jugador manda): fijar la cámara desde el cliente con `RunService:BindToRenderStep("TestCam", Enum.RenderPriority.Camera.Value + 10, function() workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(330, 120, 150), Vector3.zero) end)` y luego capturar.
- Para ver la interfaz: abrir la ventana por código (`PlayerGui.Hud.Backpack.Visible = true`) y usar `user_mouse_input` con `instance_path` (p. ej. `LocalPlayer.PlayerGui.Hud.Backpack.Body.Swords.Grid.Sword2`) para pasar el ratón o pulsar pestañas (`...Backpack.TabGear`), y luego `screen_capture`.

## Estructura

- `src/shared/` → `ReplicatedStorage.Shared`
  - `Config` — todos los números (espadas, objetos, parcelas, mejoras). El equilibrio se toca solo aquí.
  - `Upgrades` — valor y precio de cada mejora según su nivel.
  - `Stats` — daño, suertes y multiplicadores finales del jugador (espada + rasgo + artefactos + mejoras), leídos de sus atributos; vale en servidor y cliente. Cualquier bonus nuevo se suma aquí.
  - `Remotes` — única definición de RemoteEvents. `Format` — abreviar números (K … Sp … Dc, `∞`) y leerlos (`Format.parse("1.5K")`). `Rarity` — nombre y color del nivel de rareza de un "1 entre N" (`Config.RarityTiers`).
  - `SwordModel` — `SwordModel.build(nivel, padre, cframe, escala, anclada)`: el modelo del arma con piezas según su tipo (espada, hacha, lanza; las dobles llevan la segunda en un Model `OffHand` que `Swords` suelda a la mano izquierda). Adornos según la rareza, brillo en las de neón. Lo usan `Swords` y el expositor de `Scenery`.
  - Tipos de arma: cada entrada de `Config.Swords` lleva `kind` (`sword` si falta) y `Config.WeaponKinds` da su cadencia (`cooldown`) y su arco de golpe (`arc`). `Stats.weapon(player)` y `Stats.cooldown(player)` son la única fuente para cliente y servidor. `Config.Swords` no va ordenada por rareza ni por daño: no usar el índice como "mejor".
  - `Chance` — `Chance.roll(p)`: tirada de probabilidad exacta aunque `p` sea diminuta. Toda tirada de rareza pasa por aquí, nunca `NextNumber() < p` a mano.
- `src/server/` → `ServerScriptService.Server` (el `init` solo arranca módulos con `start()`)
  - `PlayerData` (monedas, gemas, inventario de espadas y espada equipada, mejoras, guardado), `Plots` (hub, parcelas y a quién pertenecen), `Destructibles` (aparición y rotura de objetos en cada parcela), `Combat` (golpes y reparto de monedas, gemas y espadas), `Movement` (velocidad al andar), `Swords` (construye y entrega la espada equipada), `Gacha` (tiradas gratis, máquina decorativa del hub, equipar), `Traits` (cristales y rasgos de espada), `Gear` (artefactos: caída y equipar), `Shop` (mejoras), `Scenery` (isla tropical: luz, mar y césped a cuadros, playa, palmeras, colinas, nubes, caminos, farolas y expositor de espadas raras en el hub; solo decoración, con semilla fija), `CollisionGroups`.
  - Espadas, objetos y artefactos se leen con `PlayerData.read` y se cambian con `PlayerData.edit`. Cada espada es una copia `{ id, sword, trait }`; `PlayerData.findSword(data, id)` la busca.
  - Vender espadas da gemas fijas (`Config.Gacha.SellValue`); no hacerlo crecer con la rareza o el gacha se paga solo.
- `src/client/` → `StarterPlayerScripts.Client`
  - `Ui` (librería de estilo sin `start()`: ventanas, botones, casillas, iconos hechos con marcos, cartel flotante `Ui.tip`, avisos `Ui.toast`), `Hud` (contadores, menú, avisos), `Backpack` (ventana `Backpack` con pestañas `Swords`/`Items`/`Gear`), `GachaRoll` (panel del gacha `Hud.GachaBar`, botones `Hud.Roll`, animación grande en la pantalla `GachaRoll` y auras por rareza en `TIER_FX`), `WeaponPreview` (librería sin `start()`: `WeaponPreview.attach(casilla, nivel, color)` pone un `ViewportFrame` con el modelo 3D del arma, que gira y se acerca al pasar el ratón; la usan las casillas de espadas de la mochila), `SkillTree` (pantalla `Upgrades`: árbol de nodos hexagonales, una rama por mejora de `Config.Upgrades` y un nodo por nivel; nodos en `Upgrades.Canvas.<mejora><nivel>`), `Effects` (escombros, números de daño, barra de vida), `SwordController` (clic → golpe), `SwingAnim` (animación del golpe por código: escribe `Transform` de las articulaciones en `Stepped`; los movimientos de cada tipo de arma están en `MOVES` como posturas en grados; enciende la estela del arma; los golpes de los demás llegan por el remote `SwingFx`. No hay animaciones subidas porque el lugar no está publicado), `WeaponAura` (auras de las armas según su rareza: partículas, cintas de luz y luz, creadas en cada cliente sobre las hojas que `SwordModel` marca con la etiqueta `WeaponAura` y los atributos `Level` y `Scale`; qué efecto entra en cada nivel de rareza está en las constantes `*_FROM`), `Ambience` (animaciones del decorado: palmeras, nubes, espuma, gaviotas, expositor).

## Reglas

- Un sistema nuevo = un módulo nuevo con `start()`, registrado en el `init` correspondiente.
- El servidor manda: el cliente solo pide (`Swing`, `RollGacha`, `EquipSword`, `SellSword`, `SetAutoSell`, `RollTrait`, `ToggleGear`, `BuyUpgrade`) y el servidor valida.
- El cliente lee el estado del jugador de los atributos del `Player`: `Coins`, `Gems`, `Swords` (inventario por copias: `id:espada:rasgo` separados por comas, rasgo 0 = ninguno), `Equipped` (id de la copia equipada), `SwordLevel` (tipo de la equipada, índice de `Config.Swords`), `AutoSell`, `Artifacts` y `Gear` (índices de `Config.Artifacts`: los que tiene y los equipados), `Item_<nombre>` y `Upgrade_<nombre>`.
- Es un juego RNG de números enormes: rarezas hasta 1 entre Sp y más. Las suertes y sus precios son siempre exponenciales (`mode = "mul"`), los números se muestran con `Format` y nada debe guardarse en un `IntValue`. Los avisos de rareza usan la probabilidad real (rareza / suerte), no la rareza a secas.
- Las mejoras se pagan con monedas salvo las que llevan `currency = "gems"`. Una mejora nueva en `Config.Upgrades` necesita `short`, `icon` y `color`, y su rama en `BRANCHES` de `SkillTree` (ahora hay 4 direcciones para 4 mejoras).
- Rojo tarda en sincronizar: casi siempre, el primer Jugar tras editar arranca con el código viejo. Antes de dar a Jugar, comprobar con `execute_luau` en `Edit` que el cambio ha llegado (p. ej. `string.find(script.Source, "texto nuevo")`), o parar y volver a entrar.
- No reordenar `Config.Swords`, `Config.Traits` ni `Config.Artifacts`: lo guardado usa la posición en la lista. Lo nuevo se añade al final.
- Los efectos visuales (escombros, números) se crean en el cliente, nunca en el servidor.
- Si cambia el formato de los datos guardados, mantén compatibilidad con lo ya guardado.
