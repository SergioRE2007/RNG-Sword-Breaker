# Armadura con estadísticas aleatorias

Pedido por el usuario (16-10-2026): cada pieza que cae tira de 1 a 4 stats distintas (Vida máxima, Daño, Suerte y Monedas) que se reparten un presupuesto de poder, para que una pieza con cuatro stats sea rara y versátil pero no mejor que una especializada. Todo se configura en `Config.Armor.Generator` y `Config.Armor.Priority`.

## Cómo se genera (`ArmorStats.generate`, la llama `server/Armor.roll`)

- Cantidad de stats: `Generator.Count` = 20 / 40 / 30 / 10 % para 1, 2, 3 y 4 (deben sumar 1). Las stats salen de `Generator.Pool` sin repetir.
- Valor de una stat = `Reference[stat]` × `weight` del hueco × `mult` de la calidad × `ArmorStats.scaling` de la zona (vida con el `power`, % con el `bonus`: igual que antes, así las zonas no se desequilibran) × `Budget[n]` × su parte × la tirada de la pieza.
- `Reference` = coeficientes de conversión de poder: lo que da una pieza de UNA sola stat en el hueco de peso 1, calidad Común y zona 1 (la vida va en puntos, el resto en fracciones). No se reparte la misma cifra entre Vida, Daño, Suerte y Monedas.
- `Budget[n]` = poder total de una pieza de n stats frente a una de una stat (1 / 1,10 / 1,16 / 1,20): las versátiles dan algo más en total pero cada stat suya es mucho más floja (con cuatro, a lo sumo ~0,5 de la referencia). `Split` (0,3) desvía el reparto de una parte igual y `Roll` (0,9 a 1,1) es la tirada de toda la pieza: dos piezas de la misma calidad y zona tienen un poder total parecido (de 0,9 a 1,32 veces una de una stat) y números distintos.
- `tools/equilibrio/armadura.luau [zona] [calidad]` enseña el reparto, el poder por cantidad de stats y piezas de ejemplo: es la herramienta para retocar estos números.
- La pieza nueva lleva `uid` (identificador único que no cambia nunca; `id` es solo su posición en el inventario y se renumera al cargar) y `v = 2`. Nada se vuelve a tirar al equipar, guardar, cargar ni comerciar (`Trade` conserva `uid`, `v` y stats).
- Las stats se tiran solo en el servidor: el cliente solo pide ids (`EquipArmor`) o un modo de prioridad que el servidor valida.

## Migración de piezas antiguas

Las piezas guardadas antes (sin `v`) conservan sus stats tal cual (`PlayerData.loadArmor` solo las recorta con `ArmorStats.cap`, que vale lo mayor entre la regla antigua y la nueva) y reciben su `uid` al cargar. "Spawn Speed" (`rollSpeed`) ya no sale en piezas nuevas, pero las antiguas lo conservan, cuenta en `Stats.spawnTime` y se enseña si alguna puesta lo suma.

## Equipar mejores (`ArmorStats.best`, `server/Armor`)

- Prioridad (`Config.Armor.Priority`): Equilibrado (por defecto), Vida, Daño, Suerte y Monedas. Se guarda en `data.armorPriority` y se publica en el atributo `ArmorPriority`. El cliente la cambia con `EquipArmor:FireServer("priority", modo)` (el servidor la valida contra `Priority.Weights`); `EquipArmor:FireServer("best")` usa la guardada.
- Cada modo pone un peso a cada stat. Una combinación de piezas vale la suma de peso × ln(multiplicador final de cada stat) (`ArmorStats.utility`): así 1.000.000 de vida y un 25 % de daño se comparan por lo que mejoran de verdad frente a lo que ya se suma, no por sus números crudos. Equilibrado pone la vida a 0,6 (su multiplicador sale del orden de magnitud) y los modos de una stat dejan a las otras a 0,05 para desempatar.
- Se prueban todas las combinaciones de una pieza por hueco (hasta `Priority.SearchLimit`; con más, se mejora hueco a hueco). Una pieza solo se propone para su hueco, ante un empate se queda la equipada y nunca se quita nada.
- Botón `Body.Armor.Priority` de la pestaña (cada pulsación pasa al siguiente modo, con el color de su stat).

## Interfaz

- El cartel de una pieza (`ArmorPane.tip`) lista solo las stats que tiene, en el color de cada una. Al pasar el ratón por una pieza que no se lleva, compara con la equipada en su hueco: lo que se gana, en verde, y lo que se pierde, en rojo (`ArmorStats.compare`). El resumen de "Armadura equipada" enseña Spawn Speed solo si una pieza antigua puesta lo suma.

## Equilibrio

- Monedas entra una sola vez, en `Stats.coins` (`1 + Armor_coins`); `Stats.bagMult` ya cuelga de `Stats.coins`.
- `tools/equilibrio/modelo.luau` tira las piezas con el mismo `ArmorStats.generate` y elige con el mismo `ArmorStats.utility` (Equilibrado); la tercera columna de `objetivo.armadura` y de `BalanceSnapshots` pasa de "aparición" a "monedas". Las referencias de `Generator` están calibradas con `informe.luau` para que el jugador tipo lleve una armadura parecida a la de antes; un jugador que se especializa en una stat consigue varias veces más de esa stat, a cambio de no tener las demás.
