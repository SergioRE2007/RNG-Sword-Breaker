# Nivel de armas (mejorar armas con gemas)

Pedido por el usuario (16-10-2026): subir de nivel cada arma gastando gemas, hasta el nivel 100; cuanto más rara, más cuesta. Es el segundo uso de las gemas, además de Fortuna.

## Cómo funciona

- Números en `Config.WeaponLevel` (`MaxLevel` 100, `PerLevel` 1,02: x7,2 en el 100, `CostBase`, `RarityPower` 1,5, `Growth` 1,06, `MinCost` 100). Cuentas en `shared/WeaponLevel`: `mult(nivel)`, `cost(copia, nivel)` = max(MinCost, CostBase × rareza total ^ RarityPower) × Growth ^ nivel (rareza total = `Permanent.rarity`), `affordable(copia, gemas, cuántos)` y `sanitize`.
- `RarityPower` 1,5 sale de medir lo que gana de gemas el jugador tipo frente a lo raras que son sus armas (las gemas por hora crecen como rareza ^ 1,5): así subir un arma cuesta parecido a cualquier hora.
- El nivel va en la copia (`copy.level`, nil = 0): se guarda, viaja en el comercio (`server/Trade`), se pierde al vender o fusionar y renacer no lo quita. En el atributo `Swords` va como octavo campo, detrás del candado: `id:espada:rasgo:grado:metal:tamaño:candado:nivel` (solo si el nivel es mayor que 0; sin nivel queda como antes). Lo lee `Stats.swords` (campo `level`).
- Daño: `Stats.swordDamage` lo multiplica por `WeaponLevel.mult(copy.level)` (y con eso `weaponDamage`, la bolsa, "Equipar mejores"…). `Stats.sellCoins` lo quita: vender no devuelve las gemas en monedas.
- Servidor: `server/WeaponLevels`, remoto `LevelSword:FireServer(id, cuántos)`: sube los que pueda pagar hasta esa cantidad; avisos "Not enough gems" y "Max level".
- Cliente: `client/LevelMenu`, ventana `Hud.LevelUp`, que abre el botón "Subir nivel" de la mochila (`Hud.Backpack.Body.Swords.Level`, con la elegida). Izquierda: todas las armas de más a menos daño (`Body.Stock.Sword<id>`, 4 columnas, solo se rehacen las casillas que cambian). Derecha (`Body.Info`): casilla grande, nombre, "Nivel n/100" con barra, daño ahora → con el siguiente, precio del siguiente nivel y botones `Buttons.Up1`, `Up10`, `UpMax`. Al subir suena "buy" y el nivel y el daño dan un salto.
- Casillas de armas (`Backpack.swordCell`): marca "Nv N" arriba en el centro; el cartel enseña "Nivel N". La Fusión avisa de que se pierden los niveles.
- `Config.Test.BestWeapons` da las armas ya al nivel máximo.

## Probado (Studio, 16-10-2026)

- Remoto: +1, +10 y "Máx" (tope 100), el daño sube x1,02 por nivel, el atributo `Swords` lleva el nivel.
- Ventana: abrir desde la mochila, elegir otra arma, +10 y Máx, botones en gris al máximo (capturas vistas). Sin errores en la consola.
- `lune run tests/regressions.luau`: comprobaciones nuevas (cobro, tope, sin gemas, guardado, nivel roto, candado + nivel, venta).
- Sin probar: "No tienes gemas suficientes" en Studio (con `InfiniteMoney` las gemas son infinitas; lo cubre la regresión), móvil, comercio de un arma con nivel entre dos jugadores.

## Equilibrio (PENDIENTE)

- `tools/equilibrio` ya lo sabe: el jugador tipo aparta `objetivo.gemasNiveles` (0,5) de sus gemas y sube el nivel más barato de sus armas equipadas (`subirNiveles` en `modelo.luau`); Fortuna cuenta solo con el resto (`generar.luau`); la línea de cada hora del informe enseña los niveles; `BalanceSnapshots` guardará `level`.
- Con `CostBase` 4e-8 maxeaba las cuatro armas en 2 h; con **4e-6** (lo que hay) los niveles suben poco a poco y solo llegan a 100 las que se quedan muchas horas (informe de 1 partida, 40 h).
- **Falta regenerar**: `lune run tools/equilibrio/generar.luau 9 aplicar` (unos 10 min, lanzarlo con `Start-Process` y esperar). Se lanzó y se cortó a medias por falta de tiempo; `Config` y `BalanceSnapshots` siguen con los números de antes, así que de momento el nivel es daño de más y el calendario va adelantado. Después, pasar `informe.luau` y mirar que el juego sigue en ~100 h.
