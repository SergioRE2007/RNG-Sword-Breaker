# Lista de tareas y mejoras pendientes

### ⚔️ Combate
- Implementar/revisar correctamente la **hitbox de los ataques**.
- Añadir **hitbox a los objetos del mapa** cuando sea necesario.
- Hacer que el **daño base de las armas dependa exclusivamente de su probabilidad/rareza base**.
- Al obtener un arma, la probabilidad mostrada debe corresponder a la **probabilidad base del arma**, sin aplicar la Luck del destructible.
  - La Luck del destructible debe influir en el **roll para conseguir el arma**, pero no modificar la probabilidad base que tiene el arma.
  - Si el arma tiene modificadores, estos sí deben reflejarse aparte.

### 🗡️ Equipamiento
- **Nada debe equiparse automáticamente.**
- El jugador debe decidir manualmente qué arma/equipamiento quiere equipar.

### 🌙 Iluminación y mapa
- Añadir iluminación a la **zona central de la parcela durante la noche**.
- Las luces del mapa deben:
  - **Apagarse durante el día**.
  - **Encenderse automáticamente durante la noche**.
- Darle algo de **profundidad visual al agua**, evitando que parezca completamente plana.

### 🐛 Bugs / problemas técnicos
- Corregir el bug en el que un **destructible puede caer encima del jugador y dejarlo atrapado dentro del suelo**.
- Revisar el **cooldown entre teletransportes** y eliminarlo si no es necesario.
- Al teletransportarse, **cerrar automáticamente cualquier menú que esté abierto**.

### 🎲 RNG / Pity
- Añadir un sistema de **Pity para Rasgos y Grados**.
- El Pity debe funcionar de forma que:
  - Cada tirada aumente el progreso hacia el Pity.
  - Cuando se alcance el límite establecido, se garantice la obtención correspondiente.
  - **100 / probabilidad** determine aproximadamente el máximo de tiradas necesarias para obtenerlo.
  - Una vez obtenido, el contador debe reiniciarse.
- Revisar que el sistema funcione correctamente tanto para **Rasgos como para Grados**.

### 🖥️ UI / Menús
- Corregir el problema del **menú de mejoras**: actualmente hay varios menús colocados uno encima de otro en la parte inferior derecha.
- Añadir un botón de **“Seleccionar todo”** en el menú de venta para poder seleccionar rápidamente todos los objetos vendibles.

### 🔄 Renacimiento
- Establecer el **máximo de renacimientos en 5**.