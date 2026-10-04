# Diseño

Incremental de espadas estilo RNG. Servidores de 8 jugadores (una parcela cada uno).

## Bucle principal

Romper objetos en tu parcela → monedas → mejorar la parcela (más objetos, más suerte) → salen objetos más raros y duros → hace falta mejor espada → gacha.

- **El dinero** mejora la parcela y la suerte. **Las espadas** salen del gacha del hub, que se paga con **gemas**; las gemas solo las sueltan los objetos raros (de la Roca en adelante), así que subir la suerte es lo que da acceso a mejores espadas.
- **Mapa**: hub circular en el centro y 8 parcelas en círculo. El jugador aparece en la suya y solo puede romper sus propios objetos.
- **Objetos**: 16 tipos (Caja → Infinito), cada uno con una rareza "1 entre N" que llega hasta 1 entre 1Sp. En cada aparición se prueba del más raro al más común; la suerte multiplica la probabilidad.
- **Todo es exponencial**: cada nivel de Suerte y de Suerte de gacha multiplica x1.5 (150 niveles, hasta ~x259Sp), y los precios crecen también exponencialmente. Las rarezas, vidas, recompensas y daños suben por órdenes de magnitud.
- **Mejoras**: "Más objetos", "Suerte" y "Velocidad de golpe" (monedas); "Suerte de gacha" (gemas, es en lo que se gastan las gemas cuando sobran).
- El golpe da a todos los objetos al alcance que estén delante del jugador.

## Hecho

- Hub y parcelas con asignación automática y cartel del dueño.
- Aparición de objetos por rareza y suerte, mejoras de cantidad y suerte.
- Gacha de espadas: máquina en el centro del hub, 5 gemas por tirada, 15 espadas por rareza hasta 1 entre 1Sp (la de madera es la inicial). Una espada nueva mejor que la actual se equipa sola.
- Inventario de espadas por copias: se pueden tener varias de la misma (máximo 200), cada copia con su rasgo. Cada una se equipa, se le tira rasgo o se vende (2 gemas).
- Venta automática: el jugador escribe un número (admite 1000, 1.5K, 2M...) y las espadas menos raras que 1 entre ese número se venden solas al salir. Con el inventario lleno también se venden.
- "Roca de armas" (1 entre 2000): al romperse da una tirada gratis con la suerte de gacha x10.
- Animación de la tirada (pasan espadas al azar 1,2 s) y aviso en pantalla con la espada obtenida.
- Aviso en el chat a todo el servidor cuando aparece un objeto o sale una espada que, con la suerte del jugador ya contada, era 1 entre 500 o más raro (`Config.AnnounceOdds`).
- Mejoras de velocidad de golpe (0,35 s → 0,14 s) y suerte de gacha.
- `Chance`: tiradas exactas con probabilidades diminutas.
- Interfaz: contadores arriba con una línea del daño y las suertes finales, y menú a la izquierda (Mochila, Mejoras).
- Rasgos de espada: los objetos raros (los que dan gemas) sueltan un Cristal de rasgo 1 de cada 5 veces. Un cristal tira un rasgo al azar (9 rasgos, de Afilada a Cósmica 1 entre 1M) para la copia de espada elegida y sustituye al anterior. El rasgo multiplica el daño de esa espada y, mientras está equipada, la suerte de parcela y de gacha.
- Artefactos (equipo): 10 artefactos que caen al romper objetos (la suerte de parcela cuenta), 3 ranuras. Multiplican daño, suerte, monedas o gemas.
- Interfaz estilo simulador: ventana "Mochila" con pestañas Espadas / Objetos / Equipo, casillas cuadradas con borde según la rareza (Común → Divina), cartel con detalles al pasar el ratón, barra de acciones para la espada elegida ("Equipar", "Tirar rasgo", "Vender", "Equipar mejor"), y en Equipo las 3 ranuras junto al personaje. Los iconos están hechos con marcos porque no hay imágenes propias.
- Árbol de mejoras (botón "Mejoras"): pantalla completa con nodos hexagonales que salen de "Inicio"; cada mejora es una rama y cada nivel un nodo (Suerte I, II, III…). Solo se ven los comprados y los 3 siguientes, así que el árbol crece al avanzar. Se arrastra para moverse; el cartel de cada nodo dice qué da y cuánto cuesta.
- Mapa: isla tropical redonda en un mar turquesa a cuadros, con playa, césped a cuadros, palmeras, arbustos, rocas, islotes, colinas azules en el horizonte y nubes. Hub más grande (radio 60) y parcelas más separadas (anillo de radio 150). En el hub, expositor con las 6 espadas más raras flotando sobre pedestales con su "1 entre N".
- Parcelas con suelo a cuadros (verde con dueño, gris libre) y valla de su color con entrada por el lado del hub.
- Velocidad al andar 30 (la normal de Roblox es 16), en `Config.WalkSpeed`.
- Modo de pruebas en Studio: monedas y gemas infinitas (`Config.Test.InfiniteMoney`). No actúa en el juego publicado.
- `Stats` (shared) calcula el daño y las suertes finales juntando espada, rasgo, artefactos y mejoras.
- HUD, tabla de clasificación, escombros con físicas, números de daño, barra de vida.
- Guardado con DataStore (solo funciona con el lugar publicado).

## Provisional o sin probar

- El hub solo tiene la máquina del gacha y el expositor de espadas raras (decorativo: las espadas no giran y sus carteles se pisan vistos de lejos).
- Interfaz sin ver o sin probar a mano: pestaña Objetos; comprar pulsando un nodo del árbol, arrastrarlo y cómo queda una rama larga (Suerte y Gacha tienen 150 niveles); escribir en la casilla de venta automática; inventario lleno (200). En móvil no hay cartel al pasar el ratón.
- Mapa: tras el último retoque del mar y las colinas no se ha vuelto a mirar desde arriba, ni se ha recorrido andando. La valla de las parcelas choca (se entra por el hueco).
- La velocidad al andar (30) es para todos, no solo en pruebas; el usuario no ha confirmado si la quería así.
- Precios, vidas, rarezas, gemas por objeto y coste del gacha son una primera estimación; el usuario aún no ha dado su opinión sobre el ritmo. El arranque puede ser lento: con la espada de madera hacen falta 5 Rocas (1 entre 20) para la primera tirada.
- El gacha, la roca de armas, las mejoras nuevas y los avisos se probaron bajando temporalmente las rarezas en `Config`; con los valores reales no se han visto salir.
- Los objetos y espadas a partir de Obelisco / Espada solar, y el ritmo de las suertes (x1.5 por nivel, precio x1.55 / x1.6), son números puestos a ojo sin jugar: nadie ha llegado ahí.
- Rasgos y artefactos: nombres, multiplicadores y rarezas inventados por Claude sin jugar. Probado con rarezas bajadas: caída de cristal, tirada de rasgo, caída y equipar/quitar artefactos. Sin ver: rasgos raros y las 3 ranuras llenas.
- Vender una espada da siempre 2 gemas, sea cual sea su rareza. Es a propósito: si el precio subiera con la rareza, con mucha suerte de gacha cada tirada devolvería más gemas de las que cuesta.
- La tirada cuesta siempre 5 gemas: con muchas gemas no hay tirada múltiple ni automática.
- Sin probar: varios jugadores a la vez, liberar la parcela al salir, la mejora de suerte, los objetos raros, el guardado y el sonido del espadazo.
- Al publicar: máximo 8 jugadores por servidor (un noveno se queda sin parcela) y activar el acceso de Studio a los servicios de API para probar el guardado.

## Fase 2: pendiente

Hecha (ver "Hecho"). Ideas que quedaron fuera:

- Tirada múltiple o automática del gacha.
- Efecto en la propia máquina al tirar (luces, partículas).

## Ideas para más adelante

- **Comercio entre jugadores** (pedido por el usuario, a futuro): intercambiar espadas, artefactos y cristales. Las espadas ya son copias individuales con id, así que se pueden pasar de un jugador a otro; los artefactos siguen siendo uno por tipo.
- Más ramas en el árbol de mejoras (monedas, daño, velocidad al andar, tamaño de mochila…), como en la captura de referencia del usuario.
- Vender varias espadas a la vez, venta automática también por rasgo.
- Cristales de grado (otro modificador aparte del rasgo), más tipos de objetos.
- Nivel del jugador y experiencia, enemigos, renacimiento.
- Contenido del hub (tiendas, clasificaciones globales).
- Decorado de parcelas, sonido al romper, partículas, modelos de espada más trabajados.
