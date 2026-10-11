-- CALENDARIO DE PROGRESO: lo que se quiere que tarde cada cosa en una partida de ~200 h. Es lo único que se toca para
-- cambiar el ritmo del juego: `lune run tools/equilibrio/generar.luau` saca de aquí los precios, las vidas y demás
-- números de Config, y `lune run tools/equilibrio/informe.luau` dice cuánto se tarda de verdad con el Config que hay.
local H = 3600
local MIN = 60

local Objetivo = {}

-- Arma más rara de Config.Swords: horas de romper objetos, con TODA la suerte al máximo (todos los objetos del tipo
-- más raro, todo cayendo de un golpe y los cinco renacimientos; sin pociones y con el clima que vaya tocando, que da
-- la mayor parte de las opciones), por cada una que sale de media. Decidido por el usuario.
-- De aquí sale Config.ObjectRolls.TypeLuckPower.
Objetivo.horasArmaTope = 500

-- Nivel n de la mejora de suerte (de `niveles`): segundos de juego en los que lo compra el jugador tipo. Muy rápido
-- al principio y cada vez más cuesta: el nivel 10 a los ~40 min, el 25 a las 15 h, el 40 a las 78 h y el último a las 170.
Objetivo.horasSuerte = 170
function Objetivo.suerte(n: number, niveles: number): number
	return Objetivo.horasSuerte * H * (n / niveles) ^ 3.5 + 8 * n
end

-- Las demás mejoras: segundo en que se compra cada nivel.
Objetivo.mejoras = {
	capacity = { 15, 45, 2 * MIN, 5 * MIN, 12 * MIN, 25 * MIN, 50 * MIN, 80 * MIN },
	rollSpeed = { 3 * MIN, 10 * MIN, 30 * MIN, 1.5 * H, 3.5 * H, 8 * H, 15 * H, 27 * H, 45 * H, 70 * H },
}
Objetivo.renacer = { 2 * H, 6.5 * H, 20 * H, 55 * H, 120 * H }
-- Parte de lo que gana que el jugador tipo dedica a cada cosa mientras le quedan niveles (de ahí salen los precios).
Objetivo.reparto = { luck = 0.5, rebirth = 0.25, rollSpeed = 0.15, capacity = 0.1 }

-- Accesorios (por su posición en Config.Artifacts) y mazmorras (Config.Dungeons): cuándo los consigue o le llega el daño.
Objetivo.accesorios = { 5 * MIN, 15 * MIN, 45 * MIN, 2 * H, 5 * H, 12 * H, 30 * H, 60 * H, 105 * H, 155 * H }
Objetivo.mazmorras = { 5 * MIN, 1 * H, 2.5 * H, 6 * H, 12 * H, 22 * H, 36 * H, 55 * H, 80 * H, 110 * H, 140 * H, 175 * H }

-- Monedas de cada tipo de objeto = base * rareza ^ potencia. Con menos de 1 un objeto raro sigue siendo un premio
-- gordo, pero no paga de golpe varios niveles (con 1 o más, sí: era la bola de nieve de antes).
Objetivo.premio = { base = 2, potencia = 0.75 }

-- Golpes que pide un objeto corriente (común y de tamaño normal) de un tipo cuando ese tipo empieza a salirle a menudo
-- al jugador (`parte` = 1 de cada 10 objetos), del primer tipo al último. Un golpe es una andanada de sus armas
-- equipadas (la vida se mide con la suma del daño de todas). Antes de eso es un objeto raro y duro (decenas
-- de golpes la primera vez que sale) y después, con las armas que va sacando, acaba cayendo de uno. Se mide ahí y no
-- cuando el tipo ya es el habitual porque, medido entonces, cada nivel de suerte llenaba la parcela de objetos que no
-- se podían romper y subir la suerte frenaba el juego (un muro de 20 h hacia la hora 80).
Objetivo.golpes = { inicio = 1, final = 3, parte = 0.1 }

-- EL JUGADOR TIPO (lo que no sale de Config). Lleva equipadas sus armas de más daño (hasta Config.Loadout.Slots), que
-- vuelan solas al objetivo. Medido en Studio con el Auto de la parcela (11 oct 2026, sin VIP): cuando todo cae de un
-- golpe rompe lo que aparece (40,7 objetos por minuto recién empezado y 130–150 con la parcela al máximo, 30 huecos y
-- uno cada 0,42 s); con objetos de varias andanadas cada arma pega a su ritmo sin perder golpes y entre un objeto roto
-- y el primer golpe al siguiente pasan 0,20 s (`salto`). Las que salpican (hachas y martillos) y las lanzas se llevan
-- además, con la parcela llena de N objetos, (N − 1) · π · (R + 0,5)² / `parcela` y (N − 1) · 0,5 · (L + 1)² / `parcela`
-- objetos de más por golpe (R = alcance de la salpicadura, L = el de la lanza). La `eficiencia` es lo que le falta a
-- una persona para ser ese personaje, y está sin medir: corregirla al jugar.
Objetivo.jugador = {
	eficiencia = 0.68, -- parte del tiempo que de verdad está rompiendo objetos: 0,8 de atención por 0,85 de la sesión en la parcela
	salto = 0.2, -- segundos entre que rompe un objeto y sus armas dan el primer golpe al siguiente (Config.Loadout.Chain y una vuelta del servidor)
	parcela = 7600, -- lo que divide en la cuenta de la salpicadura (studs cuadrados por los que se reparten los objetos)
	paciencia = 120, -- segundos que como mucho le dedica a un objeto; los más duros los deja
}
-- Lo que lleva puesto a cada hora (lo dan las mazmorras, que se equilibran para que esto se cumpla):
-- { hora, índice de Config.Traits }, { hora, índice de Config.Grades } y { hora, suerte, ataque, aparición } de la armadura.
-- El rasgo y el grado son los de su primera arma: la segunda, la tercera y la cuarta llevan cada uno cuando las tiradas
-- acumuladas llegan a 2, 3 y 4 veces su pity (el modelo saca la curva de tiradas de estas mismas tablas).
-- De aquí salen los precios (generar.luau). El informe juega las mazmorras de verdad y dice cuánto se cumple: estas
-- tablas son lo que saca su jugador (11 oct 2026) con las caídas de Config puestas para el bucle de abajo. Los
-- primeros escalones de rasgo le salen antes, por suerte y no por pity; se dejan en la hora de su pity porque de
-- ellos sale la curva de tiradas de las otras armas. La armadura va a escalones y la de verdad sube poco a poco, así
-- que quien juega sus mazmorras va algo por delante del calendario: lo completa todo hacia las 145 h y no a las 175
-- (visto bueno del usuario, 11 oct 2026). Para acercarlos habría que interpolar la tabla en modelo.partida.
Objetivo.rasgo = { { 0.2, 3 }, { 0.5, 6 }, { 1.8, 9 }, { 2.6, 10 }, { 10, 11 }, { 34, 12 }, { 85, 13 }, { 165, 14 } }
Objetivo.grado = { { 0.5, 3 }, { 1.4, 5 }, { 3.2, 6 }, { 14, 7 }, { 35, 8 }, { 78, 9 }, { 180, 10 } }
Objetivo.armadura = {
	{ 0.5, 0.07, 0, 0 },
	{ 2, 0.25, 0.07, 0.05 },
	{ 6, 0.5, 0.28, 0.06 },
	{ 15, 1, 0.7, 0.09 },
	{ 36, 1.6, 1.5, 0.12 },
	{ 70, 2.4, 2.3, 0.17 },
	{ 110, 3.7, 4.4, 0.18 },
	{ 175, 8.6, 7.6, 0.25 },
}

-- MAZMORRAS: cómo las juega el jugador tipo. Con esto el simulador juega también sus partidas de mazmorra (cristales,
-- armadura y lo que saca al desmontarla) y el informe dice si se cumplen las tablas de arriba.
-- Lo que dura una partida está medido en Studio con el personaje en Auto y Repetir (11 oct 2026, zona 1, en solitario,
-- oleadas de 4, 5, 7 y 4 enemigos; ya sin el empujón de los golpes, que ahora paran al enemigo): con cuatro espadas y
-- todo cayendo de un golpe, 23,1 s de una partida a la siguiente (de 22,2 a 24,0); con cuatro espadas y 5 / 17 / 97
-- golpes para esbirro, bruto y jefe, 38,8 s (de 37,5 a 40,1); con cuatro martillos y 2 / 6 / 35 golpes, 30,8 s (de
-- 30,0 a 32,2). Las armas cogen a los enemigos de uno en uno según entran en su círculo: cada oleada son los 2 s de
-- Config.Dungeon.WaveDelay, `oleada` hasta el primer golpe, los golpes de cada arma a su ritmo (medido: 0,37 / 1,43 /
-- 8,4 s por esbirro, bruto y jefe con las espadas, lo que da la cuenta) y, de un enemigo al siguiente, un salto que
-- depende de lo que haya durado la pelea con el anterior: si cae al momento hay que esperar a que llegue el siguiente
-- (`salto`: 0,53 s de media con espadas); si aguanta, los demás ya están en el círculo y solo es el vuelo (`cadena`);
-- entre medias, cadena + (salto − cadena) · e^(−pelea / `calma`) (tras un esbirro de 0,37 s, 0,34 s de media).
-- Con eso modelo.duracionMazmorra da 23,1 / 38,3 / 31,0 s para las tres medidas.
-- Los martillos salpican poco: 0,035 enemigos de más por golpe y por cada otro enemigo vivo, con 9,7 de alcance (de
-- ahí `salpica`, con la misma cuenta que en la parcela). Sin medir: la salpicadura de hachas y lanzas (se cuenta con
-- esa misma constante), las zonas con más enemigos y si aguanta vivo.
Objetivo.mazmorra = {
	parte = 0.15, -- parte de la sesión que pasa en mazmorras (el resto, 0,85, es la parcela y ya va en `eficiencia`)
	atencion = 0.8, -- parte de ese tiempo que de verdad está peleando (la misma atención que en la parcela)
	comoda = 75, -- segundos: juega la zona más alta que termina en menos de esto (la primera, en lo que tarde). El daño recomendado de cada zona es la vida que la deja en esto al jugador tipo a su hora
	entrada = 4, -- segundos de una partida a la siguiente con "Repetir" (medido: los 4 de Config.Dungeon.ExitDelay)
	oleada = 0.62, -- segundos de cada oleada entre que aparecen los enemigos y les llega el primer golpe
	salto = 0.54, -- segundos de un enemigo que cae al momento al primer golpe al siguiente (lo que tarda en entrar en el círculo)
	cadena = 0.16, -- lo mismo cuando el siguiente ya está dentro (Config.Loadout.Chain y una vuelta del servidor)
	calma = 0.6, -- segundos de pelea con un enemigo tras los que el siguiente ya suele estar dentro del círculo
	salpica = 9300, -- lo que divide en la cuenta de la salpicadura dentro de la arena (como `parcela` en Objetivo.jugador)
}
-- Quien deja el personaje en "Auto" y "Repetir" sin parar en la mejor zona, ya con el juego completado: cristales de
-- rasgo y de grado (contando los de desmontar la armadura) que saca en esas horas. Decidido por el usuario (11 oct
-- 2026, al pasar a cuatro armas; antes 15 000): con esto Paradoja (52 600 tiradas) sale en la primera arma en unos
-- 1,75 días de bucle y en las cuatro en unos 7.
Objetivo.bucle = { horas = 24, rasgo = 30000, grado = 30000 }

-- BOLSA DE ORO (Config.GoldBag): detrás de la parcela, las armas que el jugador deposita le pegan solas a un saco,
-- también mientras está desconectado y sin tope de tiempo. Decidido por el usuario (11 oct 2026): hasta entonces un
-- arma mejor solo servía para romper antes, y así da siempre más monedas.
-- `parte` = parte de todo lo que ingresa el jugador tipo que le llega de la bolsa. `reales` = horas de reloj por cada
-- hora de juego (juega unas 3 al día): la bolsa pega todo ese tiempo, así que quien juega menos saca más de ella en
-- proporción y quien está siempre dentro, casi nada de más. `crece` = por cuánto se multiplican las monedas de una
-- bolsa a la siguiente. `primera` = segundos de juego que le dura la primera.
-- El jugador tipo deja en la bolsa las armas que siguen a sus equipadas (de la 5.ª a la 8.ª de más daño, sin rasgo ni
-- grado): si deja las mejores, la bolsa le va más rápido y la parcela más despacio.
-- De aquí salen Config.GoldBag.Bags y Growth.
Objetivo.bolsa = { parte = 0.25, reales = 8, crece = 4, primera = 240 }

-- Horas de las que se guarda el estado del jugador tipo (Config.Test.Progress, para probar cada etapa en Studio).
Objetivo.fotos = { 0.5, 2, 5, 15, 40, 80, 120, 170, 200 }

return Objetivo
