# Diseño

Incremental de espadas estilo RNG. Servidores de 8 jugadores (una parcela cada uno).

## Bucle principal

Romper objetos en tu parcela → monedas → mejorar la parcela (más objetos, más suerte) → salen objetos más raros y duros → hace falta mejor espada → gacha.

- **El dinero** mejora la parcela y la suerte. **Las espadas** salen del gacha, que es **gratis** y se tira todo el rato (una tirada cada 2 s, desde cualquier sitio); lo que limita es el tiempo por tirada y la suerte de gacha. Las **gemas** las sueltan los objetos raros (de la Roca en adelante) y se gastan en suerte de gacha.
- **Mapa**: hub circular en el centro y 8 parcelas en círculo. El jugador aparece en la suya y solo puede romper sus propios objetos.
- **Objetos**: 16 tipos (Caja → Infinito), cada uno con una rareza "1 entre N" que llega hasta 1 entre 1Sp. En cada aparición se prueba del más raro al más común; la suerte multiplica la probabilidad.
- **Todo es exponencial**: cada nivel de Suerte y de Suerte de gacha multiplica x1.5 (150 niveles, hasta ~x259Sp), y los precios crecen también exponencialmente. Las rarezas, vidas, recompensas y daños suben por órdenes de magnitud.
- **Mejoras**: "Más objetos", "Suerte" y "Velocidad de golpe" (monedas); "Suerte de gacha" (gemas, es en lo que se gastan las gemas cuando sobran).
- El golpe da a todos los objetos al alcance que estén delante del jugador.

## Hecho

- Hub y parcelas con asignación automática y cartel del dueño.
- Aparición de objetos por rareza y suerte, mejoras de cantidad y suerte.
- Gacha de espadas gratis: botones "Tirar" y "Auto" abajo, una tirada cada `Config.Gacha.RollTime` (2 s; `Stats.rollTime` es donde se restarán mejoras y gamepass). 15 espadas por rareza hasta 1 entre 1Sp (la de madera es la inicial). Una espada nueva mejor que la actual se equipa sola. La máquina del hub queda de decorado (se hincha y suelta chispas con las tiradas buenas, solo para quien tira).
- Panel del gacha arriba: pasan espadas al azar cada vez más despacio y se para en la que ha tocado, con barra del tiempo hasta la siguiente tirada. Aura del panel por nivel de rareza (`TIER_FX` en `GachaRoll`): nada (Común), brillo (Poco común), + chispas (Rara), + rayos (Épica), + temblor (Legendaria, Mítica), + arcoíris (Secreta, Divina).
- Tirada muy buena para tu suerte (1 entre 200 real o más, `Config.Gacha.ShowcaseOdds`): el panel vuela al centro y se hace orbe, se carga con el color de la rareza, estalla y destapa la carta con rayos, destello, temblor y cartel ("¡MÍTICA!"); más largo y con más efectos cuanto más rara. "Continuar" para volver (en automático sigue sola a los 3 s). Pulsar la pantalla la salta.
- Las auras (panel y personaje) van por la probabilidad real (rareza / suerte de gacha): con mucha suerte, una espada rara ya no brilla. Aura en el personaje desde 1 entre 100 real (la ven todos, `Config.Gacha.AuraOdds`): partículas y luz del color del nivel; anillos en el suelo desde Épica y columna de luz desde Mítica. Cada aura nueva quita la anterior. El aura y el aviso del chat salen cuando el jugador destapa la tirada (no antes, para no destripársela), o a los 30 s si su cliente no avisa. El aviso del chat dice la probabilidad real.
- Inventario de espadas por copias: se pueden tener varias de la misma (máximo 200), cada copia con su rasgo. Cada una se equipa, se le tira rasgo o se vende (2 gemas).
- Venta automática: el jugador escribe un número (admite 1000, 1.5K, 2M...) y las espadas menos raras que 1 entre ese número se venden solas al salir. Con el inventario lleno también se venden.
- "Roca de armas" (1 entre 2000): al romperse da una tirada gratis con la suerte de gacha x10.
- Aviso en el chat a todo el servidor cuando aparece un objeto o sale una espada que, con la suerte del jugador ya contada, era 1 entre 500 o más raro (`Config.AnnounceOdds`).
- Mejoras de velocidad de golpe (0,35 s → 0,14 s) y suerte de gacha.
- `Chance`: tiradas exactas con probabilidades diminutas.
- Interfaz: contadores arriba con una línea del daño y las suertes finales, y menú a la izquierda (Mochila, Mejoras).
- Tiendas de modificadores en el hub (pedido por el usuario, con capturas de referencia): dos puestos con toldo de rayas y cartel, entre dos caminos. Se abren con la tecla de interacción (ProximityPrompt) y se cierran al alejarse. Ventana: a la izquierda la espada elegida (se cambia pulsando su casilla), el modificador que tiene, el coste y los botones Tirar / Auto / engranaje (resultados con los que se para la automática; por defecto los de menos del 1 %); a la derecha todos los resultados con su % y su efecto: los grados del más raro al más común y los rasgos por tipo (Especiales, Monedas, Daño, Suerte). Las especiales arcoíris giran y las muy raras sin arcoíris laten. El resultado sustituye al anterior. La mochila ya no tira rasgos.
  - **Rasgos** (1 Cristal de rasgo por tirada; los objetos raros sueltan un cristal 1 de cada 5 veces): Monedas, Daño y Suerte I/II/III (x1.2 / x1.5 / x2; 24.8 % / 6.7 % / 1.5 % cada uno) y los que lo suben todo: Samurái x3 (0.9 %), Shogun x5 (0.17 %), Monarca x8 (0.039 %), Trascendente x15 (0.01 %), Eterno x30 (0.0045 %), Paradoja x57.5 (0.0019 %).
  - **Grados** (25 gemas por tirada, `Config.GradeCost`): multiplican las monedas. D x1.1 (50 %), C x1.25, B x1.5, A x2, A+ x3, S x5 (1.3 %), S+ x8, Z x12, Z+ x20, X x40, ∞ x100 (0.0016 %).
  - Rasgo y grado solo cuentan mientras la espada está equipada. Aviso en el chat si sale algo de 1 entre 500 o más raro.
- Artefactos (equipo): 10 artefactos que caen al romper objetos (la suerte de parcela cuenta), 3 ranuras. Multiplican daño, suerte, monedas o gemas.
- Interfaz estilo simulador: ventana "Mochila" con pestañas Espadas / Objetos / Equipo, casillas cuadradas con borde según la rareza (Común → Divina), cartel con detalles al pasar el ratón, barra de acciones para la espada elegida ("Equipar", "Tirar rasgo", "Vender", "Equipar mejor"), y en Equipo las 3 ranuras junto al personaje. Los iconos están hechos con marcos porque no hay imágenes propias.
- Árbol de mejoras (botón "Mejoras"): pantalla completa con nodos hexagonales que salen de "Inicio"; cada mejora es una rama y cada nivel un nodo (Suerte I, II, III…). Solo se ven los comprados y los 3 siguientes, así que el árbol crece al avanzar. Se arrastra para moverse y se acerca o aleja con la rueda del ratón, pellizcando o con los botones + y - (empieza algo alejado); el cartel de cada nodo dice qué da y cuánto cuesta. Fondo con degradado y rayas suaves.
- La interfaz usa también la franja de arriba de Roblox (contadores pegados arriba con margen). Las tiendas enseñan las armas en 3D (`WeaponPreview`, como la mochila), en la casilla grande y en el selector de espada.
- Estilo de las ventanas (`Ui.window`, pedido por el usuario: "que no se vean planas"): centradas en la pantalla, con sombra, bisel claro por dentro del borde, cabecera degradada a cuadros con brillo y título con un destello que la cruza, y cuerpo oscuro con rayas diagonales suaves (`Ui.stripes`). Las tiendas son más grandes (1000x540), su lista no se mueve al tirar, los títulos de Rasgos (arcoíris) y Grados (morado) giran y los carteles de los puestos cambian de color, laten y flotan.
- Mapa: isla tropical redonda en un mar turquesa a cuadros, con playa, césped a cuadros, palmeras, arbustos, rocas, islotes, colinas azules en el horizonte y nubes. Mapa grande: parcelas de 100x100 en un anillo de radio 250 y hub de radio 90 con plaza a cuadros y bordillo azul. Caminos anchos de baldosas con bordillos azules y balizas del color de la parcela, sin brillo (pedido por el usuario). En el hub, expositor con las 6 espadas más raras flotando sobre pedestales con su "1 entre N". La base (`Baseplate`, 2048 de lado) se coloca por `CFrame` en `Scenery`: con `Position` Studio la sube y tapa la isla.
- Detalles de la isla: césped con textura (material Grass), matas de hierba y flores por el césped libre, agua poco profunda y espuma en la orilla, cordilleras nevadas en el horizonte con bancos de niebla, niebla más densa a lo lejos, rayos de sol y un leve desenfoque de lo lejano (estilo ilustración).
- Animaciones del decorado en el cliente (`Ambience`): las palmeras se mecen, las nubes giran despacio alrededor de la isla, la espuma de la orilla late, las espadas del expositor giran y flotan, y seis gaviotas vuelan en círculos. Scenery marca las piezas con etiquetas (`Sway`, `Cloud`, `Foam`, `ShowcaseSword`).
- Parcelas con suelo a cuadros (verde con dueño, gris libre) y valla de su color con entrada por el lado del hub.
- Velocidad al andar 30 (la normal de Roblox es 16), en `Config.WalkSpeed`.
- Modo de pruebas en Studio: monedas y gemas infinitas (`Config.Test.InfiniteMoney`). No actúa en el juego publicado.
- `Stats` (shared) calcula el daño y las suertes finales juntando espada, rasgo, artefactos y mejoras.
- Espadas con volumen hechas con piezas (`SwordModel`): hoja con filo, nervio y punta, guarda con remates, empuñadura y pomo. Desde la de acero, guarda dorada con cuernos y gema; las de neón brillan y sueltan chispas; desde la de cometa llevan esquirlas flotando. El expositor del hub usa el mismo modelo.
- Animación del golpe por código (`SwingAnim`), que se adapta a la velocidad de golpe y enciende una estela. La espada alterna tres tajos (diagonal, revés y desde arriba).
- Mochila con las armas en 3D (`WeaponPreview`): cada casilla enseña el modelo real del arma en diagonal sobre un círculo del color de su rareza; al pasar el ratón gira sobre sí misma y se acerca. El gacha (`GachaRoll`) sigue usando el icono plano de espada.
- Marcos animados por rareza en las casillas (`Ui.cell(padre, color, nivel)`): un brillo da vueltas por el borde, a la misma velocidad en todas (el usuario no quiere que las raras giren más rápido); desde Legendaria un halo que late; Secreta en rosa y violeta y Divina en celeste y blanco (sin arcoíris, a petición del usuario). Casillas de espadas más grandes (6 por fila) con el daño abajo a la izquierda, y botones más gruesos. Solo las casillas de espadas pasan el nivel; las de objetos y artefactos siguen con marco quieto.
- Modo de pruebas `Config.Test.AllWeapons`: una copia de cada arma al entrar en Studio.
- Auras de las armas (`WeaponAura`), más cargadas cuanto más rara es el arma: chispas (Poco común), llamas por la hoja (Rara), cintas de luz girando (Épica, hasta 3), ascuas y luz (Legendaria), bruma (Mítica), todo en arcoíris con luz que cambia de color (Secreta) y destellos grandes (Divina). Las comunes no llevan. También las llevan las espadas del expositor del hub. Vistas en captura la Divina y una Legendaria doble; el resto de niveles, sin mirar.
- Tipos de arma (`Config.WeaponKinds`), 9 armas nuevas en el gacha (3 de cada):
  - **Hachas**: el jugador da una vuelta entera y pega a todo lo que le rodea; golpean x1.7 más lento.
  - **Espadas dobles**: una en cada mano, tajos alternos casi el doble de rápidos, con menos daño por golpe y menos alcance.
  - **Lanzas**: estocada al frente, mucho alcance pero solo pega a lo que está justo delante.
  - Hay un tiempo mínimo entre golpes (`Config.MinCooldown`, 0,1 s).
- HUD, tabla de clasificación, escombros con físicas, números de daño, barra de vida.
- Guardado con DataStore (solo funciona con el lugar publicado).

## Provisional o sin probar

- El hub solo tiene la máquina del gacha y el expositor de espadas raras (los carteles de las espadas se pisan vistos de lejos, y más ahora que giran).
- El decorado tiene ~7900 piezas (sobre todo matas de hierba); en Studio va a 60 fps, sin probar en móvil.
- Interfaz sin ver o sin probar a mano: pestaña Objetos; comprar pulsando un nodo del árbol, arrastrarlo y cómo queda una rama larga (Suerte y Gacha tienen 150 niveles); escribir en la casilla de venta automática; inventario lleno (200). En móvil no hay cartel al pasar el ratón.
- Mapa: tras el último retoque del mar y las colinas no se ha vuelto a mirar desde arriba, ni se ha recorrido andando. La valla de las parcelas choca (se entra por el hueco).
- La velocidad al andar (30) es para todos, no solo en pruebas; el usuario no ha confirmado si la quería así.
- Precios, vidas, rarezas, gemas por objeto y coste del gacha son una primera estimación; el usuario aún no ha dado su opinión sobre el ritmo. El arranque puede ser lento: con la espada de madera hacen falta 5 Rocas (1 entre 20) para la primera tirada.
- El gacha, la roca de armas, las mejoras nuevas y los avisos se probaron bajando temporalmente las rarezas en `Config`; con los valores reales no se han visto salir.
- Los objetos y espadas a partir de Obelisco / Espada solar, y el ritmo de las suertes (x1.5 por nivel, precio x1.55 / x1.6), son números puestos a ojo sin jugar: nadie ha llegado ahí.
- Armas nuevas: daños, rarezas y cadencias puestos a ojo. Vistos en captura los 9 modelos, la vuelta del hacha y la estocada de la lanza; los tajos de las espadas dobles y los de la espada tras rehacerlos no se han visto. Golpear objetos con cada tipo (área del hacha, alcance de la lanza) sin probar en una parcela. La mochila usa el mismo icono de espada para todos los tipos y "equipar mejor" compara solo el daño por golpe, no la cadencia.
- Rasgos, grados y artefactos: nombres, multiplicadores y probabilidades puestos por Claude sin jugar. Los rasgos se cambiaron por completo (antes: Afilada → Cósmica); como el lugar nunca se ha publicado no hay partidas guardadas con los viejos. Probado en Studio: tiradas de rasgo y de grado, automática, el engranaje y elegir espada. Sin ver: un rasgo o grado muy raro de verdad. El coste del grado (25 gemas) está sin equilibrar.
- Vender una espada da siempre 2 gemas, sea cual sea su rareza. Es a propósito: si el precio subiera con la rareza, con mucha suerte de gacha cada tirada devolvería más gemas de las que cuesta.
- Gacha gratis probado en Studio con tiradas reales y falsas (Legendaria, Secreta y el aura de Mítica forzadas). Sin probar en móvil ni con varios jugadores viendo auras a la vez.
- **Gemas con el gacha gratis**: vender espadas sigue dando 2 gemas, y con la tirada automática y venta automática salen ~60 gemas por minuto sin hacer nada, más que de los objetos raros. Hay que decidir si vender da gemas, otra cosa o nada.
- Sin probar: varios jugadores a la vez, liberar la parcela al salir, la mejora de suerte, los objetos raros, el guardado y el sonido del espadazo.
- Al publicar: máximo 8 jugadores por servidor (un noveno se queda sin parcela) y activar el acceso de Studio a los servicios de API para probar el guardado.

## Fase 2: pendiente

Hecha (ver "Hecho"). Ideas que quedaron fuera:

- Que los demás jugadores vean el efecto de la máquina cuando alguien tira.

## Velocidad de tirada y gamepass (pedido por el usuario)

Como el gacha es gratis y se tira todo el rato, lo que se mejora es lo rápido que se tira:

- **Rama "Velocidad de tirada"** en el árbol de mejoras (`Config.Upgrades`, una dirección más en `BRANCHES` de `SkillTree`): baja `Stats.rollTime` nivel a nivel desde 2 s.
- **Gamepass** (Robux): tirada más rápida, doble tirada (dos espadas por tirada), más suerte de gacha. La tirada automática se queda gratis.

## Ideas para más adelante

- **Comercio entre jugadores** (pedido por el usuario, a futuro): intercambiar espadas, artefactos y cristales. Las espadas ya son copias individuales con id, así que se pueden pasar de un jugador a otro; los artefactos siguen siendo uno por tipo.
- Más ramas en el árbol de mejoras (monedas, daño, velocidad al andar, tamaño de mochila…), como en la captura de referencia del usuario.
- Vender varias espadas a la vez, venta automática también por rasgo.
- Más tipos de objetos.
- Nivel del jugador y experiencia, enemigos, renacimiento.
- **Clasificaciones** (pedido por el usuario, más adelante): paneles grandes en el hub, como en la captura de referencia, con las mejores tiradas ("mejor tirada" con su 1 entre N), más monedas y más tiradas; globales entre servidores con OrderedDataStore (necesita el lugar publicado).
- Decorado de parcelas, sonido al romper, partículas, modelos de espada más trabajados.
