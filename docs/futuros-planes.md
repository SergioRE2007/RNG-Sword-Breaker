# Futuros planes

Ideas aprobadas por el usuario pero sin fecha. Antes de hacer una, repasar aquí lo pensado y preguntarle lo que falte.

## Racha diaria

- Premio por entrar cada día, que crece con la racha (el día 7, un Trébol de la suerte). Si se pierde un día, vuelve
  al día 1.
- Propuesta: cartel al entrar con los 7 días y el de hoy por cobrar; la racha va en los datos guardados (día UTC,
  como las misiones). Pendiente de decidir los premios de cada día (monedas, gemas, cristales, pociones, tickets).

## Máquina de fusionar

- Juntar 5 copias iguales (misma arma, metal y tamaño) para sacar una de mejor tamaño. Da uso a los repetidos.
- Ojo: toca la economía de rarezas. Un arma fusionada tiene una rareza total mucho mayor que lo que costó sacar las
  5 copias, así que hay que decidir con `tools/equilibrio` cuántas copias pide cada paso. ¿Cuentan para el Índice
  las fusionadas? (Ahora el Índice solo cuenta tiradas propias.)
- Una estación más en el hub, como la Forja y la Mesa de encantamiento.

## Mejorar armas con gemas

- Pedido por el usuario: subir de nivel un arma gastando gemas, hasta el nivel 100. Cuanto más rara es el arma (su
  rareza total, `Permanent.rarity`), más cuesta cada nivel. Sería el segundo uso de las gemas, además de Fortuna.
- Propuesta de Claude, por decidir con el usuario:
  - El nivel va con la copia (como el rasgo y el grado): se guarda, se comercia con ella y al venderla se pierde.
    Hay que añadir un campo al atributo `Swords` sin romper lo guardado.
  - Cada nivel multiplica el daño de esa arma un poco (por ejemplo x1,02 por nivel, unos x7 en el nivel 100). Va en
    `Stats.swordDamage`, como el grado.
  - El precio usa la rareza total elevada a una potencia pequeña (con la rareza a secas, las armas de 1e24 costarían
    cantidades imposibles) y sube con el nivel.
  - Renacer quita las gemas pero no las armas: los niveles se quedan, así que las gemas dejan de "perderse" al
    renacer.
  - Es un multiplicador de daño nuevo: hay que meterlo en `tools/equilibrio/modelo.luau` y regenerar, o el
    calendario se adelanta.
