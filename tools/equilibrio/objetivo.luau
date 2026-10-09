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
-- al jugador (`parte` = 1 de cada 10 objetos), del primer tipo al último. Antes de eso es un objeto raro y duro (decenas
-- de golpes la primera vez que sale) y después, con el arma que va sacando, acaba cayendo de uno. Se mide ahí y no
-- cuando el tipo ya es el habitual porque, medido entonces, cada nivel de suerte llenaba la parcela de objetos que no
-- se podían romper y subir la suerte frenaba el juego (un muro de 20 h hacia la hora 80).
Objetivo.golpes = { inicio = 1, final = 3, parte = 0.1 }

-- EL JUGADOR TIPO (lo que no sale de Config). Medido en Studio con un personaje automático que anda hasta el objeto más
-- cercano y le pega al ritmo del arma (9 oct 2026): recién empezado rompe 42 objetos por minuto y con la parcela al
-- máximo (30 huecos, uno cada 0,42 s) 142, lo que aparece en los dos casos; cuando los objetos piden ~8 golpes, 24 por
-- minuto con la parcela llena y 1,14 objetos por espadazo (espada corta). De ahí `paseo` y `densidad`; la
-- `eficiencia` es lo que le falta a una persona para ser ese personaje, y está sin medir: corregirla al jugar.
Objetivo.jugador = {
	eficiencia = 0.68, -- parte del tiempo que de verdad está rompiendo objetos: 0,8 de atención por 0,85 de la sesión en la parcela
	paseo = 0.1, -- segundos de media para llegar al siguiente objeto
	densidad = 0.01, -- objetos de más que se lleva cada espadazo por cada hueco de la parcela (con 30 huecos, 1,3 por golpe: algo más que lo medido, porque las armas y los objetos del final son más grandes)
	paciencia = 400, -- golpes que como mucho le da a un objeto (un par de minutos); los más duros los deja
}
-- Lo que lleva puesto a cada hora (lo dan las mazmorras, que se equilibran para que esto se cumpla):
-- { hora, índice de Config.Traits }, { hora, índice de Config.Grades } y { hora, suerte, ataque, aparición } de la armadura.
Objetivo.rasgo = { { 0.7, 3 }, { 1.5, 6 }, { 3, 9 }, { 5, 10 }, { 18, 11 }, { 60, 12 }, { 140, 13 } }
Objetivo.grado = { { 1, 3 }, { 4, 5 }, { 10, 6 }, { 30, 7 }, { 70, 8 }, { 140, 9 } }
Objetivo.armadura = {
	{ 0.5, 0.05, 0.03, 0 },
	{ 2, 0.2, 0.15, 0.04 },
	{ 6, 0.5, 0.4, 0.06 },
	{ 15, 1, 0.8, 0.08 },
	{ 36, 2, 1.5, 0.12 },
	{ 70, 3.5, 2.5, 0.16 },
	{ 110, 5, 4, 0.2 },
	{ 175, 9, 7, 0.25 },
}

-- Horas de las que se guarda el estado del jugador tipo (Config.Test.Progress, para probar cada etapa en Studio).
Objetivo.fotos = { 0.5, 2, 5, 15, 40, 80, 120, 170, 200 }

return Objetivo
