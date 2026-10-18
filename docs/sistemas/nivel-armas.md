# Nivel de armas (mejorar armas con gemas)

Pedido por el usuario (16-10-2026): subir de nivel cada arma gastando gemas, hasta el nivel 100; cuanto más rara, más cuesta. Es el segundo uso de las gemas, además de Fortuna.

## Cómo funciona

- Números en `Config.WeaponLevel` (`MaxLevel` 100, `PerLevel` 1,02: x7,2 en el 100, `CostBase`, `RarityPower` 1,5, `Growth` 1,04, `MinCost` 100). Cuentas en `shared/WeaponLevel`: `mult(nivel)`, `cost(copia, nivel)` = max(MinCost, CostBase × rareza total ^ RarityPower) × Growth ^ nivel (rareza total = `Permanent.rarity`), `affordable(copia, gemas, cuántos)` y `sanitize`.
- `RarityPower` 1,5 sale de medir lo que gana de gemas el jugador tipo frente a lo raras que son sus armas (las gemas por hora crecen como rareza ^ 1,5): así subir un arma cuesta parecido a cualquier hora.
- El nivel va en la copia (`copy.level`, nil = 0): se guarda, viaja en el comercio (`server/Trade`), se pierde al vender o fusionar y renacer no lo quita. En el atributo `Swords` va como octavo campo, detrás del candado: `id:espada:rasgo:grado:metal:tamaño:candado:nivel` (solo si el nivel es mayor que 0; sin nivel queda como antes). Lo lee `Stats.swords` (campo `level`).
- Daño: `Stats.swordDamage` lo multiplica por `WeaponLevel.mult(copy.level)` (y con eso `weaponDamage`, la bolsa, "Equipar mejores"…). `Stats.sellCoins` lo quita: vender no devuelve las gemas en monedas.
- Servidor: `server/WeaponLevels`, remoto `LevelSword:FireServer(id, cuántos)`: sube los que pueda pagar hasta esa cantidad; avisos "Not enough gems" y "Max level".
- Cliente: `client/LevelMenu`, ventana `Hud.LevelUp`, que abre el botón "Subir nivel" de la mochila (`Hud.Backpack.Body.Swords.Level`, con la elegida). Izquierda: todas las armas de más a menos daño (`Body.Stock.Sword<id>`, 4 columnas, solo se rehacen las casillas que cambian). Derecha (`Body.Info`): casilla grande, nombre, "Nivel n/100" con barra, daño ahora → con el siguiente, precio del siguiente nivel y botones `Buttons.Up1`, `Up10`, `UpMax`. Al subir suena "buy" y el nivel y el daño dan un salto.
- Casillas de armas (`client/WeaponCell`, la misma en todos los menús): marca "Nv N" arriba en el centro; la clave `WeaponCell.key` lleva el nivel, así que la casilla se rehace al subirlo (antes la mochila no lo veía); el cartel enseña "Nivel N". La Fusión avisa de que se pierden los niveles.
- `Config.Test.BestWeapons` da las armas ya al nivel máximo.

## Probado (Studio, 16-10-2026)

- Remoto: +1, +10 y "Máx" (tope 100), el daño sube x1,02 por nivel, el atributo `Swords` lleva el nivel.
- Ventana: abrir desde la mochila, elegir otra arma, +10 y Máx, botones en gris al máximo (capturas vistas). Sin errores en la consola.
- `lune run tests/regressions.luau`: comprobaciones nuevas (cobro, tope, sin gemas, guardado, nivel roto, candado + nivel, venta).
- Sin probar: móvil, comercio de un arma con nivel entre dos jugadores.

## Equilibrio

- Decidido por el usuario (17-10-2026): el nivel de armas no regenera el resto del equilibrio (vidas, precios, renacimientos siguen como estaban; el endgame más difícil vendrá aparte). Solo se ajusta `CostBase`.
- `tools/equilibrio` lo simula: el jugador tipo aparta `objetivo.gemasNiveles` (0,5) de sus gemas y sube el nivel más barato de sus armas equipadas (`subirNiveles` en `modelo.luau`); la línea de cada hora del informe enseña los niveles.
- Medido con `informe.luau 9` (mediana de 9 partidas, 100 h), 5.º renacimiento / niveles a media partida:
  - sin niveles (`gemasNiveles` 0): 86 h; nadie completa el juego en 100 h.
  - `CostBase` 4e-6: 69 h y juego completado a 90 h; niveles 87-89 a las 14 h (demasiado barato).
  - 4e-5: 73 h; niveles 10-40. 2e-4: 81 h; niveles 0-10 casi toda la partida.
  - 1e-4 (con `Growth` 1,06, hasta el 18-10-2026): 75 h, nadie completa el juego en 100 h; niveles 0-15 hasta las 20 h, 15-45 a media partida y la mejor arma cerca de 100 hacia las 90 h. Entre partidas los hitos bailan ±10 h.
- Los niveles bajan a 0 a menudo en la simulación: al cambiar a un arma nueva mejor, empieza sin nivel.
- Probado en Studio (17-10-2026): con 0 gemas, `LevelSword` da el aviso "No tienes gemas suficientes" abajo a la derecha y no cambia nada.- Bajado el 18-10-2026 (el usuario lo veía "absurdamente caro"): `CostBase` 1e-5 y `Growth` 1,04 (el primer nivel cuesta 10 veces menos y subir del 0 al 100 unas 45 veces menos). Medido con `informe.luau 5`: 5.º renacimiento a 64,5 h (antes 75 h); el jugador tipo, que aparta la mitad de sus gemas, lleva sus armas al 100 en pocas horas.
