# Verificación de las mejoras

## Pruebas automáticas

Desde la raíz, con [Lune 0.10.5](https://github.com/lune-org/lune/releases/tag/v0.10.5):

```powershell
lune run tests/regressions.luau
rojo build -o graphify-out/regression.rbxlx
```

En esta carpeta está disponible el ejecutable local en `graphify-out/tooling/lune.exe`. Esa carpeta y el lugar generado están ignorados por Git.

Resultado al implementar: **201 comprobaciones correctas, 96 scripts Luau compilados y construcción Rojo correcta**. Las pruebas cargan los módulos de producción con adaptadores para red, reloj y DataStore; también cargan las mallas reales del mapa. No ejecutan el motor de físicas ni renderizan la interfaz.

Se comprueban: daño de las 42 armas; Pity base, colisiones de garantías, prioridad, triple tirada, pago, descarte y persistencia; venta duplicada, ids inválidos o inexistentes, armas modificadas y equipada; recompensas sin autoequipar; cinco renacimientos y migración; hitboxes por tipo, altura, alcance, borde y rotación; luces de día/noche, rendimiento y llegada de nuevas luces; viajes seguidos y destinos inválidos; aparición bloqueada por visitantes sin volver a tirar; pasos del torii y colisiones de rocas a escala.

## Pendiente en Roblox Studio

Rojo debe estar conectado a `localhost:34872`. Parar y volver a iniciar la partida tras sincronizar; no abrir el lugar de pruebas encima del archivo local del usuario. Mantener los valores habituales de `Config.Test` al terminar.

- [ ] **Equipamiento**: conseguir un arma superior, accesorio y armadura con ranuras libres u ocupadas. Ninguno cambia lo equipado. Equipar manualmente, morir y volver a entrar: conservar la elección. Guardado real: probar en una copia publicada con acceso a DataStore.
  - Probado el 10-10-2026 en Studio (un jugador): 12 tiradas reales rompiendo objetos, alta en el Índice y nada cambia lo equipado (arma, accesorio, armadura); tras morir vuelve el arma elegida. Falta el guardado real en un lugar publicado.
- [ ] **Combate**: espada, hacha, dobles, lanza y martillo contra destructibles y enemigos. Probar delante/detrás, salto, límite de alcance y objetos grandes rotados. Cada objetivo recibe como máximo un impacto por ataque.
  - Probado el 10-10-2026: los cinco tipos contra objetos de la parcela (delante, detrás, al límite del alcance y saltando) golpean justo lo que prevé `Hitbox.reaches`, sin repetidos; martillo contra enemigos de mazmorra, 5 espadazos de 4 golpes sin repetidos. Sin probar objetos grandes rotados.
- [ ] **Colisiones**: atravesar torii y puentes; chocar con sus columnas y suelo, troncos, rocas, edificios y vallas. Flores, hojas, animales y escombros no empujan al personaje.
  - Probado el 10-10-2026 con un barrido de caja del tamaño del personaje (no andando): el torii se cruza por el centro y sus columnas chocan; el puente y el komainu chocan. Falta recorrerlo a pie y lo de flores, animales y escombros.
- [ ] **Aparición**: dos jugadores en una parcela, uno visitando; permanecer en las zonas de aparición y saltar. Ningún objeto nace dentro de sus cuerpos. Al liberar sitio aparece el objeto pendiente con su rareza/tamaño originales.
- [ ] **Rarezas**: obtener el mismo tipo de arma de objetos con distinta suerte. Mostrar siempre su probabilidad base, con metal y tamaño aparte. Los efectos pueden diferir según la dificultad efectiva.
- [ ] **Teletransporte**: viajar rápidamente desde Mochila, Venta, Mejoras, Rasgos, Forja, Grupo y Comercio. Cerrar ventanas y autos, recuperar cámara y ratón, cancelar el trato. Repetir al entrar/salir de mazmorras.
  - Probado el 10-10-2026: con Mochila, Índice, Tienda y Ajustes abiertas, viajar las cierra y deja cámara y ratón normales; entrar y salir de una mazmorra limpia el panel de la partida. Falta desde Mejoras, Rasgos, Forja, Grupo y Comercio.
- [ ] **Venta**: seleccionar todo, quitar una selección, cancelar la confirmación, confirmar; cotejar cantidad/gemas. Incluir armas con rasgos/grados/metal/tamaño. Equipar o comerciar una copia antes de venderla: el servidor protege la equipada e ignora las que ya no se tienen.
  - Probado el 10-10-2026 desde el remote: vende lo pedido, ignora la repetida y la que no existe y protege la equipada (también una recién equipada). Una lista con un id inválido (negativo, texto) se rechaza entera. Falta la ventana (seleccionar, cancelar, confirmar).
- [ ] **Mejoras y tiendas**: PC 1920×1080 y 1366×768; móvil 390×844 y 844×390. Revisar resumen, zoom, acciones, Pity, confirmación y desplazamiento; sin solapamientos y con texto legible. Pociones ocultas mientras Mejoras está abierto y restauradas al salir.
- [ ] **Pity**: cerca de varios límites, comprobar «Garantía pendiente», prioridad y reinicio tras obtener un resultado. Triple, automático, descarte y reconexión. La poción cambia la tirada normal, conservando el límite base. Los cambios Admin no avanzan el Pity.
  - Probado el 10-10-2026: tres tiradas de rasgo suben los contadores y ponen a 0 el del resultado; poner un rasgo con Admin no los mueve. Falta cerca de los límites, triple, automático, descarte y poción.
- [ ] **Renacimiento**: 4→5 con cobro normal; varios intentos posteriores sin cobro ni sexto renacimiento. Mostrar 5/5 y botón desactivado.
  - Probado el 10-10-2026: 8 peticiones seguidas se quedan en 5. Falta ver el 5/5 y el botón desactivado en pantalla y, sin dinero infinito, que no cobre de más.
- [ ] **Mapa**: ambos temas, día, atardecer y noche; centro de parcela visible de noche y luces realmente apagadas de día. Activar/desactivar Rendimiento y alejarse/regresar con streaming. Revisar fondo y oleaje del agua desde arriba y desde la orilla; armas y mazmorras conservan sus luces.

La curva de daño cambia el ritmo de combate entre tipos de arma. El ajuste económico posterior requiere una partida real; no se han alterado precios, vidas ni probabilidades para compensarlo.

## Candado de sesión del guardado

Lo cubren las pruebas de Lune con dos servidores simulados (esperar a que el otro guarde, echar si sigue abierto, servidor caído, servidor viejo que no puede pisar, salir y volver al mismo servidor, irse a medio cargar, modos de prueba). Con DataStore de verdad queda:

- [ ] **Studio con acceso a los servicios de API** (Ajustes del juego → Seguridad) y los modos de `Config.Test` que dan cosas apagados: jugar y parar deja la partida guardada y sin `lock`; con un `lock` de otro id y hora reciente puesto a mano en la clave `p_<UserId>`, entrar espera 30 s y echa con el aviso; con la hora vieja (más de 180 s), entra.
- [ ] **Juego publicado**: salir y entrar seguido varias veces (también con el botón de reconexión y tras un trato) carga siempre lo último; la consola del servidor no enseña avisos de `[PlayerData]`.
- [ ] **Cierre del servidor** con varios jugadores (apagar servidores desde la web): todos vuelven a entrar con lo último y sin esperar.
