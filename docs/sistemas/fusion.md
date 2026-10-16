# Máquina de fusión

Pedida por el usuario (16-10-2026): una máquina en la que se meten 5 armas y sale una mejor, como un gacha, pagando gemas según la suerte que salga.

## Cómo funciona

- **Dónde**: en el hub, a la entrada del camino de 135°, entre Rasgos (112,5°) y Grados (157,5°): `Config.Fusion.Angle` y `Distance`. Es una estación como la Forja y la Mesa: geometría en `Stations.fusion` (plataforma, columna con esfera y núcleo rosa, dos aros dorados que giran, cinco pedestales con cristales de colores de rareza y conductos al centro; lo que se mueve lo anima `StationFx` por sus etiquetas), cartel con `ModifierShops.addSign` (etiqueta `ShopStation`, `Shop = "fusion"`, atributo `Core` = centro del núcleo).
- **Ventana** (`client/Fusion`, `Hud.Fusion`): se abre sola a `Config.Fusion.OpenDistance` studs del cartel y se cierra a 30. Arriba los cinco huecos (`Body.Slots.Slot<n>`), debajo lo que sale ("Sale: 1 entre N o más rara") y las gemas que cuesta (`Body.Info`), el aviso de que se pierden rasgos y grados (`Body.Warning`, solo si alguna los lleva; entonces Fusionar pide confirmar), la lista de armas libres de más rara a menos (`Body.Stock.Sword<id>`; pulsar mete, pulsar en un hueco devuelve) y los botones `Body.Actions.Fill` ("Rellenar": las más raras sin rasgo ni grado) y `Body.Actions.Fuse`.
- **Suerte**: la suma de las rarezas totales (arma × metal × tamaño) de las cinco (`FusionInfo.luck`). La tirada es `Permanent.rollWeapon(suma)` (`Gacha.fuse`, fuente `"fusion"`): sale siempre algo de "1 entre la suma" o más raro. No se le suma la suerte de armas del jugador (`Stats.gachaLuck`): ya va dentro de la rareza de las armas metidas. Lo que sale no se vende solo aunque esté por debajo de la venta automática. Para el espectáculo (`odds`) se mide contra la propia suma: lo normal no se celebra, lo que la supera sí.
- **Precio**: `FusionInfo.cost(suerte) = max(MinCost, ceil(CostScale × suerte ^ CostPower))`, con `1.6e-7`, `1.73` y 10. Medido con `tools/equilibrio` (jugador tipo, 1 a 130 h): sus gemas por hora son ~1e-6 × S^1,73, siendo S la suerte de fusionar cinco armas como las de su bolsa (5 × la 8.ª mejor). Así esa fusión cuesta unos 10 min de gemas a cualquier altura del juego. Las gemas son las mismas que las de la mejora Fortuna: fusionar retrasa Fortuna, y `tools/equilibrio` no cuenta la máquina.
- **Servidor** (`server/Fusion`, remote `FuseSwords({ ids })`): exactamente `Count` ids distintos, cada uno del jugador y libre (`PlayerData.isLocked`: ni equipada, ni en la Bolsa de oro, ni con candado), jugador a menos de `Reach` studs del núcleo, `Cooldown` s entre fusiones y gemas suficientes ("No tienes gemas suficientes"). Quita las armas y cobra en un solo `PlayerData.edit` y tira justo después. Avisa al cliente con `FusionDone({ swords, luck })` (para la animación) y el arma llega por `GachaRolled` con `origin` en el núcleo.
- **Animación**: las armas metidas aparecen en corro alrededor del núcleo, giran y caen a él una tras otra, destello rosa; el arma nueva sale del núcleo con `RollReveal` (orbe, destape y vuelo al jugador). La ventana se cierra al fusionar y vuelve a abrirse sola a los 4,5 s si el jugador sigue allí y no hay cinemática de tirada rara en marcha.

## Probado (16-10-2026, Studio, un jugador, `InfiniteMoney` y `AllWeapons`)

- Rellenar, suerte y precio en pantalla; fusionar: 42 → 38 armas y sale una de 1 entre 1,5e20 con suerte 3,7e18, sin errores.
- Rechazadas sin cambiar nada: con una equipada, con ids repetidos, con 4 armas, desde lejos (200 studs) y la segunda de dos seguidas.

## Pendiente

- Probar el aviso de gemas insuficientes con `InfiniteMoney = false`, el aviso de rasgos y grados con armas modificadas y verlo en móvil.
- Ritmo real: cuántas fusiones hace un jugador y cuánto le quita a Fortuna.
