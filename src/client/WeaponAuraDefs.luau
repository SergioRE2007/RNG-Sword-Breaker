-- Diseño de las auras de las armas: qué lleva cada arma rara y cómo es cada tipo de partícula.
-- Aquí solo hay datos; quien los convierte en efectos es client/WeaponAura. Para retocar un aura se toca este
-- archivo y nada más: no hace falta Blender ni colocar nada en Studio.
--
-- CADA ARMA (`weapons`, por su posición en Config.Swords) lleva:
--   main, second, accent   colores del aura (principal, secundario y, si hace falta, un tercero).
--   intensity              multiplica la cantidad de partículas de todas sus capas (1 = normal).
--   size, speed            multiplican el tamaño y la velocidad de todo.
--   light                  luz del arma: { range, brightness, color, pulse = latidos por segundo, flicker = parpadea }.
--   layers                 lista de capas. La primera palabra de cada capa dice qué es:
--
--   · Un tipo de partícula de `particles` ("flames", "stars", "smoke"...). Se le puede cambiar cualquier campo:
--       rate (partículas por segundo), life (duración), speed, size, colors, transparency, bright, accel...
--       at = dónde sale: "blade" (la hoja, por defecto), "tip" (la punta), "player" (alrededor del personaje),
--            "feet" (el suelo, bajo el personaje) o "head" (sobre la cabeza).
--       burst = partículas de más que suelta de golpe al atacar y al sacar el arma.
--   · "orbit": puntos que giran alrededor de la hoja o del jugador (at = "player").
--       path = "circle", "helix" (sube y baja por la hoja), "atom" (un plano inclinado por punto),
--              "infinity" (dibuja un ∞) o "spiral" (se acerca y se aleja).
--       count, radius, speed (negativa = al revés), tilt (grados), height, bob (sube y baja), rise, extend
--       (cuánto baja de la hoja la hélice: para las astas de las lanzas), orb (tamaño de la bola de luz),
--       trail (ancho de la estela), trailLife (lo que dura), transparency (de la estela), colors y emit (una capa
--       de partículas que va soltando).
--   · "ring": aro de luz. at ("blade", "player", "head", "feet"), radius, height, tilt, spin, precess (giro del
--       eje), width, colors y arcs (false = aro entero; si no, dos arcos que se persiguen).
--   · "bolts": rayos hechos por código. mode = "crawl" (recorren la hoja) o "arc" (saltan hacia fuera),
--       count, reach (lo que se separan), extend (cuánto bajan de la hoja), width, colors.
--
-- Las partículas con `at` del jugador solo salen cuando el arma está en la mano (no en la del expositor ni en las
-- tiradas), y en las armas dobles solo las pone una de las dos.
local WeaponAuraDefs = {}

local rgb = Color3.fromRGB

local GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- punto de luz difuminado
local STAR = "rbxasset://textures/particles/sparkles_main.dds" -- destello de ocho puntas
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- aro
local FLAME = "rbxasset://textures/particles/fire_main.dds" -- lenguas de fuego
local BLAZE = "rbxasset://textures/particles/explosion01_core_main.dds" -- nube de fuego (ya viene naranja)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- nube clara
local SOOT = "rbxasset://textures/particles/explosion01_smoke_main.dds" -- mancha oscura
local BUBBLE = "rbxasset://textures/particles/forcefield_vortex_main.dds" -- burbuja
local SQUARE = "rbxasset://textures/particles/SquareParticle.png" -- cuadrado

-- Rareza mínima (posición en Config.RarityTiers) para llevar aura: 4 = Épica. Las de menos no llevan nada,
-- salvo que tengan su entrada en `weapons`.
WeaponAuraDefs.FROM_TIER = 4

-- Cuánto multiplica la rareza la cantidad de partículas de un aura (lo demás se decide capa a capa).
WeaponAuraDefs.TIER_RATE = { [4] = 0.85, [5] = 1, [6] = 1.1, [7] = 1.2, [8] = 1.3 }

-- Tipos de partícula. Campos: tex, colors (de la paleta del arma: "white", "main", "second", "accent", "dark",
-- "pale", o un Color3), rate, life y speed (mínimo y máximo), size (tamaño máximo, en studs), grow (cómo cambia de
-- tamaño: pop, puff, shrink, flat, twinkle, flame, grow), alpha (cómo se desvanece: fade, linger, puff, hold,
-- blink), transparency (lo más opaca que llega a estar: 0 sólida, 0.8 casi invisible), bright (cuánto brilla: por
-- encima de 1 deslumbra), spread, accel, drag, rot (giro), spin (false = sin giro inicial), emission (0 = pintura,
-- 1 = luz), lit (le afecta la luz del mapa), locked (se mueve pegada al arma), orient ("velocity" = estirada hacia
-- donde va, "flat" = tumbada en el suelo), squash, dir, z y shape/surface.
-- Medido en Studio: por debajo de estos tamaños no se ven al lado de una hoja de neón, y con más `emission` o
-- `bright` las de color se queman a blanco a mediodía (solo van al blanco chispas, destellos, rayos y bolas).
WeaponAuraDefs.particles = {
	-- Destellos de estrella pegados a la hoja.
	glints = { tex = STAR, colors = { "white", "main" }, rate = 6, life = { 0.45, 0.9 }, speed = { 0, 0.4 }, size = 1.2, grow = "pop", alpha = "fade", rot = 140, emission = 0.9, bright = 2, locked = true, z = 0.3 },
	-- Motas de luz que flotan y suben despacio.
	motes = { tex = GLOW, colors = { "white", "main", "second" }, rate = 12, life = { 1, 1.8 }, speed = { 0.3, 1.1 }, size = 0.6, grow = "pop", alpha = "hold", accel = Vector3.new(0, 0.8, 0), drag = 1, emission = 0.6, bright = 1.5 },
	-- Estrellas que se quedan titilando por donde ha pasado el arma.
	stars = { tex = STAR, colors = { "white", "main", "second" }, rate = 8, life = { 1.1, 2 }, speed = { 0, 0.5 }, size = 0.9, grow = "twinkle", alpha = "hold", rot = 60, emission = 0.9, bright = 2 },
	-- Nubes de color medio transparentes (gas de nebulosa).
	nebula = { tex = SMOKE, colors = { "main", "second" }, rate = 5, life = { 1.6, 2.6 }, speed = { 0.2, 0.7 }, size = 3.4, grow = "puff", alpha = "puff", transparency = 0.55, rot = 25, emission = 0.35, bright = 1.1 },
	-- Resplandor blando que envuelve la hoja.
	glow = { tex = GLOW, colors = { "main" }, rate = 5, life = { 0.6, 0.9 }, speed = { 0, 0 }, size = 4.5, grow = "puff", alpha = "puff", transparency = 0.7, emission = 0.6, locked = true, z = -0.5 },
	-- Llamas que suben.
	flames = { tex = FLAME, colors = { "white", "main", "second" }, rate = 22, life = { 0.5, 0.9 }, speed = { 0.6, 1.8 }, size = 2.4, grow = "flame", alpha = "linger", accel = Vector3.new(0, 5, 0), rot = 90, emission = 0.85, bright = 1.4 },
	-- Nube de fuego espesa (magma). La textura ya es naranja: el blanco la deja tal cual.
	blaze = { tex = BLAZE, colors = { "white" }, rate = 12, life = { 0.5, 0.9 }, speed = { 0.3, 1 }, size = 3, grow = "puff", alpha = "puff", transparency = 0.1, accel = Vector3.new(0, 2, 0), rot = 40, emission = 0.6, bright = 1.5 },
	-- Ascuas pequeñas que saltan y suben.
	embers = { tex = GLOW, colors = { "white", "main", "second" }, rate = 12, life = { 0.5, 1.1 }, speed = { 2.5, 6 }, size = 0.45, grow = "shrink", alpha = "hold", accel = Vector3.new(0, 5, 0), drag = 2.5, emission = 0.8, bright = 2 },
	-- Humo que sube (no brilla: le da la luz del mapa).
	smoke = { tex = SMOKE, colors = { "dark" }, rate = 4, life = { 1.2, 2 }, speed = { 0.4, 1 }, size = 2.8, grow = "puff", alpha = "puff", transparency = 0.5, accel = Vector3.new(0, 2.5, 0), rot = 30, emission = 0, lit = true },
	-- Sombra: manchas oscuras que tapan la luz.
	shadow = { tex = SOOT, colors = { "main", "second" }, rate = 9, life = { 0.8, 1.5 }, speed = { 0.2, 0.8 }, size = 3.2, grow = "puff", alpha = "puff", rot = 40, emission = 0 },
	-- Jirones de energía, como llamas frías y lentas.
	wisps = { tex = FLAME, colors = { "main", "second" }, rate = 11, life = { 0.8, 1.4 }, speed = { 0.4, 1.2 }, size = 2.4, grow = "flame", alpha = "fade", transparency = 0.1, rot = 60, emission = 0.75, bright = 1.3 },
	-- Copos que caen.
	snow = { tex = STAR, colors = { "white", "main" }, rate = 9, life = { 1.2, 2 }, speed = { 0.2, 0.8 }, size = 0.6, grow = "flat", alpha = "hold", accel = Vector3.new(0, -2.2, 0), drag = 1, rot = 90, emission = 0.6, bright = 1.3 },
	-- Vaho helado que cae.
	frost = { tex = SMOKE, colors = { "white", "main" }, rate = 4, life = { 1.2, 2 }, speed = { 0.2, 0.6 }, size = 3.2, grow = "puff", alpha = "puff", transparency = 0.6, accel = Vector3.new(0, -1.2, 0), rot = 20, emission = 0.4 },
	-- Esquirlas de cristal que saltan.
	shards = { tex = SQUARE, colors = { "white", "main" }, rate = 6, life = { 0.5, 0.9 }, speed = { 1.5, 3.5 }, size = 0.5, grow = "shrink", alpha = "hold", orient = "velocity", squash = 1.6, drag = 2, spin = false, emission = 0.5, bright = 1.3 },
	-- Rayos de luz que salen disparados.
	rays = { tex = GLOW, colors = { "white", "main" }, rate = 8, life = { 0.3, 0.55 }, speed = { 4, 8 }, size = 1.3, grow = "pop", alpha = "fade", orient = "velocity", squash = 2.2, spin = false, emission = 0.9, bright = 2 },
	-- Chispazos eléctricos, muy cortos.
	sparks = { tex = STAR, colors = { "white", "main" }, rate = 40, life = { 0.1, 0.25 }, speed = { 3, 9 }, size = 0.9, grow = "shrink", alpha = "fade", emission = 1, bright = 3 },
	-- Burbujas que suben.
	bubbles = { tex = BUBBLE, colors = { "white", "main" }, rate = 5, life = { 1.2, 2 }, speed = { 0.2, 0.7 }, size = 0.9, grow = "puff", alpha = "hold", transparency = 0.1, accel = Vector3.new(0, 2, 0), rot = 30, emission = 0.5, bright = 1.2 },
	-- Gotas que caen.
	drops = { tex = GLOW, colors = { "main", "second" }, rate = 5, life = { 0.5, 0.8 }, speed = { 0, 0.4 }, size = 0.5, grow = "flat", alpha = "hold", accel = Vector3.new(0, -16, 0), orient = "velocity", squash = 1.5, spin = false, emission = 0.5, bright = 1.5 },
	-- Cuadraditos que parpadean (fallo digital).
	pixels = { tex = SQUARE, colors = { "main", "white", "second" }, rate = 14, life = { 0.35, 0.8 }, speed = { 0.4, 1.8 }, size = 0.34, grow = "flat", alpha = "blink", spin = false, emission = 0.7, bright = 1.6 },
	-- Aros que se abren de cara a la cámara.
	rings = { tex = RING, colors = { "white", "main" }, rate = 1.2, life = { 0.6, 0.9 }, speed = { 0, 0 }, size = 4.5, grow = "grow", alpha = "fade", transparency = 0.1, spin = false, emission = 0.6, bright = 1.6, locked = true },
	-- Hojitas que caen dando vueltas.
	leaves = { tex = GLOW, colors = { "main", "second" }, rate = 6, life = { 1.2, 2 }, speed = { 0.5, 1.5 }, size = 0.55, grow = "flat", alpha = "hold", accel = Vector3.new(0, -1.6, 0), drag = 1.5, rot = 200, squash = 1.2, emission = 0.35, bright = 1.3 },
	-- Bola de luz de lo que gira (la usan las capas "orbit" con `orb`).
	orb = { tex = GLOW, colors = { "white", "main" }, rate = 22, life = { 0.14, 0.22 }, speed = { 0, 0 }, size = 0.9, grow = "shrink", alpha = "fade", spin = false, emission = 0.9, bright = 2.5 },
	-- Onda que se abre por el suelo (para at = "feet").
	groundring = { tex = RING, colors = { "pale", "main" }, rate = 0.9, life = { 1.1, 1.4 }, speed = { 0.01, 0.01 }, spread = 0, dir = "Top", orient = "flat", size = 12, grow = "grow", alpha = "linger", spin = false, emission = 0.4, bright = 2 },
	-- Penachos de energía que suben alrededor del cuerpo (para at = "player"). Con el punto de luz y no con la
	-- textura de fuego: esa tiene partes oscuras y, con colores claros, se veía como humo gris.
	aura = { tex = GLOW, colors = { "main", "second" }, rate = 20, life = { 0.6, 1 }, speed = { 3, 6 }, spread = 8, dir = "Top", size = 2.4, grow = "flame", alpha = "puff", transparency = 0.35, accel = Vector3.new(0, 4, 0), orient = "velocity", squash = 1, spin = false, emission = 0.5, bright = 1.3 },
}

WeaponAuraDefs.weapons = {
	-- ===== ÉPICAS: aura sencilla, solo en el arma =====
	[8] = { -- Espada del vacío: un agujero negro; sombra y luz morada que cae en espiral hacia la hoja
		main = rgb(140, 80, 255), second = rgb(60, 20, 140),
		layers = {
			{ "shadow", rate = 7 },
			{ "wisps", rate = 8 },
			{ "stars", rate = 5, size = 0.8, burst = 8 },
			{ "orbit", path = "spiral", count = 2, radius = 1.6, tilt = 25, speed = 4, trail = 0.35, trailLife = 0.5 },
		},
	},
	[9] = { -- Espada solar: llamas doradas y rayos de sol
		main = rgb(255, 175, 45), second = rgb(255, 90, 20),
		layers = {
			{ "flames", rate = 20 },
			{ "rays", rate = 7 },
			{ "embers", rate = 8, burst = 10 },
			{ "glow", rate = 3, colors = { "second" } },
		},
	},
	[22] = { -- Lanza de jade: espíritus verdes rondando la punta y hojas que caen
		main = rgb(90, 225, 145), second = rgb(30, 135, 90),
		layers = {
			{ "motes", rate = 16, size = 0.7, colors = { "main", "second" } },
			{ "leaves", rate = 8 },
			{ "glints", rate = 4, size = 0.9, burst = 6 },
			{ "orbit", path = "circle", count = 2, radius = 1, tilt = 30, speed = 3, orb = 0.7, trail = 0.22, trailLife = 0.45 },
		},
	},
	[23] = { -- Hacha volcánica: nube de fuego, salpicaduras de lava que caen y humo
		main = rgb(255, 125, 30), second = rgb(190, 30, 10),
		layers = {
			{ "blaze", rate = 12 },
			{ "embers", rate = 14, speed = { 3, 7 }, accel = Vector3.new(0, -9, 0), burst = 14 },
			{ "smoke", rate = 3 },
		},
	},
	[24] = { -- Hojas del eclipse: sombra morada con la corona dorada del sol tapado
		main = rgb(160, 90, 255), second = rgb(255, 205, 120),
		layers = {
			{ "shadow", rate = 6, size = 2.6, colors = { "main" } },
			{ "glints", rate = 4, colors = { "white", "second" }, burst = 6 },
			{ "ring", radius = 0.95, height = 0.3, tilt = 25, spin = 2.5, colors = { "second", "main" } },
		},
	},
	[28] = { -- Martillo del trueno: rayos que saltan de la cabeza y chispazos
		main = rgb(255, 230, 95), second = rgb(130, 195, 255),
		light = { range = 9, brightness = 0.7, flicker = true },
		layers = {
			{ "bolts", mode = "arc", count = 2, reach = 2.2 },
			{ "sparks", rate = 40, burst = 16 },
			{ "glow", rate = 5, size = 4 },
		},
	},

	-- ===== LEGENDARIAS: más capas, luz y algo girando en el arma =====
	[10] = { -- Espada de cometa: cola de polvo helado que se queda atrás y un cometa dando vueltas
		main = rgb(170, 235, 255), second = rgb(90, 150, 255),
		light = { range = 9, brightness = 0.7 },
		layers = {
			{ "motes", rate = 16, life = { 0.8, 1.4 }, speed = { 0, 0.3 }, accel = Vector3.zero },
			{ "snow", rate = 6 },
			{ "glints", rate = 5, burst = 8 },
			{ "orbit", path = "helix", count = 1, radius = 1.3, speed = 7, orb = 1, trail = 0.45, trailLife = 0.9, colors = { "white", "main", "second" } },
		},
	},
	[11] = { -- Espada nebulosa: nubes de gas rosa y violeta con estrellas dentro
		main = rgb(240, 100, 185), second = rgb(130, 90, 255),
		light = { range = 9, brightness = 0.6, pulse = 0.4 },
		layers = {
			{ "nebula", rate = 6 },
			{ "stars", rate = 7, burst = 10 },
			{ "motes", rate = 6 },
			{ "orbit", path = "helix", count = 2, radius = 1.2, speed = 3, trail = 0.7, trailLife = 1.1, transparency = 0.3, colors = { "main", "second" } },
		},
	},
	[25] = { -- Lanza del rayo: rayos que bajan por el asta y saltan de la punta
		main = rgb(255, 240, 110), second = rgb(140, 200, 255),
		light = { range = 11, brightness = 0.9, flicker = true },
		layers = {
			{ "bolts", mode = "crawl", count = 2, reach = 0.7, extend = 7 },
			{ "bolts", mode = "arc", count = 1, reach = 2, colors = { "white", "second" } },
			{ "sparks", rate = 40, burst = 18 },
			{ "glints", rate = 4, size = 0.9 },
		},
	},
	[29] = { -- Martillo magmático: magma que gotea, ascuas y humo
		main = rgb(255, 115, 30), second = rgb(150, 20, 0),
		light = { range = 10, brightness = 0.9, pulse = 0.3 },
		layers = {
			{ "blaze", rate = 14, size = 3.4 },
			{ "drops", rate = 9, size = 0.7 },
			{ "embers", rate = 12, burst = 16 },
			{ "smoke", rate = 4 },
		},
	},
	[33] = { -- Hacha del abismo: fondo del mar; oscuridad azul, burbujas y luz que se hunde
		main = rgb(95, 100, 255), second = rgb(20, 20, 95),
		light = { range = 8, brightness = 0.6, pulse = 0.25 },
		layers = {
			{ "shadow", rate = 6, colors = { "second" } },
			{ "bubbles", rate = 7, burst = 8 },
			{ "drops", rate = 4 },
			{ "motes", rate = 6, accel = Vector3.new(0, -0.8, 0) },
		},
	},
	[34] = { -- Colmillos de sombra: humo negro que se queda atrás y ojos rojos en la oscuridad
		main = rgb(150, 60, 220), second = rgb(50, 10, 80), accent = rgb(255, 60, 90),
		layers = {
			{ "shadow", rate = 10 },
			{ "wisps", rate = 7 },
			{ "glints", rate = 3, size = 1, colors = { "accent" }, burst = 6 },
			{ "orbit", path = "helix", count = 1, radius = 0.9, speed = -6, trail = 0.4, trailLife = 0.6, colors = { "main", "second" } },
		},
	},

	-- ===== MÍTICAS: aura completa en el arma y algo ligero alrededor del jugador =====
	[12] = { -- Espada galáctica: el disco de una galaxia con sus planetas alrededor de la hoja
		main = rgb(95, 135, 255), second = rgb(200, 120, 255),
		light = { range = 11, brightness = 0.9, pulse = 0.35 },
		layers = {
			{ "nebula", rate = 4, size = 3 },
			{ "stars", rate = 9, burst = 14 },
			{ "ring", radius = 1.7, tilt = 28, spin = 1.5 },
			{ "orbit", path = "circle", count = 3, radius = 1.7, tilt = 28, speed = 2.2, orb = 0.8 },
			{ "orbit", at = "player", path = "circle", count = 2, radius = 3.2, speed = 1.4, height = 0.5, orb = 0.9, emit = { "stars", rate = 6, size = 0.7 } },
		},
	},
	[13] = { -- Espada cuántica: electrones dando vueltas como en un átomo y píxeles que parpadean
		main = rgb(70, 255, 180), second = rgb(60, 170, 255),
		light = { range = 10, brightness = 0.8, pulse = 1.2 },
		layers = {
			{ "pixels", rate = 16, burst = 20 },
			{ "orbit", path = "atom", count = 3, radius = 1.4, speed = 9, orb = 0.7, trail = 0.2, trailLife = 0.35 },
			{ "rings", rate = 0.8, size = 3.6 },
			{ "pixels", at = "player", rate = 10, size = 0.4, accel = Vector3.new(0, 3, 0) },
		},
	},
	[14] = { -- Espada del cosmos: un trozo de espacio negro lleno de estrellas, con dos órbitas cruzadas
		main = rgb(150, 110, 255), second = rgb(15, 10, 40), accent = rgb(120, 220, 255),
		light = { range = 9, brightness = 0.6, pulse = 0.2 },
		layers = {
			{ "shadow", rate = 9, size = 3.6, colors = { "second" } },
			{ "stars", rate = 14, colors = { "white", "accent", "main" }, burst = 16 },
			{ "nebula", rate = 3, colors = { "main", "accent" } },
			{ "ring", radius = 1.5, height = -0.4, tilt = 60, spin = 1 },
			{ "ring", radius = 1.5, height = -0.4, tilt = -60, spin = -1.3, colors = { "accent", "main" } },
			{ "stars", at = "player", rate = 8, size = 0.8, life = { 1.5, 2.5 }, colors = { "white", "accent", "main" } },
		},
	},
	[15] = { -- Espada del origen: luz pura; rayos blancos y dorados y ondas suaves
		main = rgb(255, 245, 210), second = rgb(255, 205, 110),
		light = { range = 12, brightness = 1, pulse = 0.3 },
		layers = {
			{ "glow", rate = 4, colors = { "second" } },
			{ "rays", rate = 9, burst = 14 },
			{ "motes", rate = 9 },
			{ "rings", rate = 0.7 },
			{ "motes", at = "player", rate = 8, accel = Vector3.new(0, 2.5, 0) },
		},
	},
	[30] = { -- Martillo glacial: vaho helado, copos, esquirlas de hielo y una ventisca alrededor del jugador
		main = rgb(160, 225, 255), second = rgb(90, 150, 255),
		light = { range = 10, brightness = 0.7 },
		layers = {
			{ "frost", rate = 5 },
			{ "snow", rate = 10, burst = 16 },
			{ "shards", rate = 5 },
			{ "glints", rate = 5 },
			{ "orbit", at = "player", path = "circle", count = 2, radius = 2.8, speed = 2.4, height = 1, bob = 1.5, emit = { "snow", rate = 9 } },
		},
	},
	[31] = { -- Martillo cósmico: cosmos morado; gas, estrellas y tres astros con estela girando
		main = rgb(170, 90, 255), second = rgb(255, 120, 230), accent = rgb(120, 200, 255),
		light = { range = 11, brightness = 0.9, pulse = 0.3 },
		layers = {
			{ "nebula", rate = 6 },
			{ "stars", rate = 10, colors = { "white", "accent", "second" }, burst = 16 },
			{ "glints", rate = 4 },
			{ "orbit", path = "circle", count = 3, radius = 2.4, tilt = 35, speed = 2.6, orb = 0.9, trail = 0.3, trailLife = 0.7 },
			{ "nebula", at = "player", rate = 2.5, size = 5, transparency = 0.8 },
			{ "stars", at = "player", rate = 7, size = 0.8, colors = { "white", "accent", "second" } },
		},
	},
	[35] = { -- Lanza abisal: corrientes de agua que suben por el asta, burbujas y gotas
		main = rgb(60, 135, 255), second = rgb(20, 40, 150), accent = rgb(110, 255, 230),
		light = { range = 10, brightness = 0.8, pulse = 0.25 },
		layers = {
			{ "bubbles", rate = 7, burst = 10 },
			{ "drops", rate = 5 },
			{ "nebula", rate = 3, size = 2.8 },
			{ "orbit", path = "helix", count = 2, radius = 1, speed = 4, extend = 5, trail = 0.5, trailLife = 1, colors = { "accent", "main", "second" } },
			{ "bubbles", at = "player", rate = 5, size = 1 },
		},
	},
	[36] = { -- Hacha estelar: estrellas fugaces rosas alrededor del hacha y del jugador
		main = rgb(255, 130, 210), second = rgb(255, 220, 130),
		light = { range = 11, brightness = 0.9, pulse = 0.5 },
		layers = {
			{ "stars", rate = 12, size = 1.1, burst = 18 },
			{ "glints", rate = 6 },
			{ "motes", rate = 6 },
			{ "orbit", path = "helix", count = 2, radius = 2.8, speed = 6, orb = 1, trail = 0.35, trailLife = 0.8, colors = { "second", "main" } },
			{ "orbit", at = "player", path = "circle", count = 2, radius = 3, speed = 3, bob = 1.6, orb = 1, trail = 0.4, trailLife = 0.9, colors = { "second", "main" } },
		},
	},
	[37] = { -- Sables de aurora: cortinas de aurora boreal verde y violeta que ondean
		main = rgb(90, 255, 200), second = rgb(170, 110, 255), accent = rgb(110, 190, 255),
		light = { range = 10, brightness = 0.8, pulse = 0.2 },
		layers = {
			{ "orbit", path = "helix", count = 2, radius = 0.8, speed = 1.6, rise = 0.9, trail = 1.6, trailLife = 1.6, transparency = 0.45, colors = { "main", "accent", "second" } },
			{ "motes", rate = 9, colors = { "main", "second" } },
			{ "nebula", rate = 3, transparency = 0.75 },
			{ "glints", rate = 3, burst = 8 },
			{ "orbit", at = "player", path = "circle", count = 2, radius = 3, speed = 0.9, bob = 2, trail = 2.4, trailLife = 2.2, transparency = 0.5, colors = { "main", "accent", "second" } },
		},
	},
	[38] = { -- Lanza de nova: una estrella que estalla; ondas y rayos desde la punta
		main = rgb(255, 140, 225), second = rgb(255, 230, 160),
		light = { range = 12, brightness = 1, pulse = 0.8 },
		layers = {
			{ "rings", rate = 1.6, size = 5, burst = 2 },
			{ "rays", rate = 9, burst = 14 },
			{ "embers", rate = 8, accel = Vector3.zero, drag = 1.5 },
			{ "glow", rate = 4, size = 4 },
			{ "groundring", at = "feet", rate = 0.6 },
		},
	},

	-- ===== SECRETAS: todo lo anterior y aura completa alrededor del jugador =====
	[16] = { -- Espada del infinito: el ∞ rojo dibujándose sin parar alrededor de la hoja y del jugador
		main = rgb(255, 50, 70), second = rgb(120, 0, 30), accent = rgb(255, 210, 220),
		light = { range = 13, brightness = 1.1, pulse = 0.35 },
		layers = {
			{ "orbit", path = "infinity", count = 2, radius = 2.4, speed = 3.2, orb = 0.9, trail = 0.3, trailLife = 1.1, colors = { "accent", "main" } },
			{ "wisps", rate = 9 },
			{ "embers", rate = 9, burst = 20 },
			{ "shadow", rate = 4, colors = { "second" } },
			{ "glow", rate = 3 },
			{ "orbit", at = "player", path = "infinity", count = 2, radius = 4.2, speed = 2, orb = 1.1, trail = 0.45, trailLife = 1.6, colors = { "accent", "main" } },
			{ "aura", at = "player" },
			{ "ring", at = "feet", radius = 3.2, spin = 2.2, width = 0.25, colors = { "accent", "main" } },
			{ "groundring", at = "feet" },
			{ "embers", at = "player", rate = 12, size = 0.6, speed = { 0.5, 2 }, accel = Vector3.new(0, 4, 0) },
		},
	},
	[32] = { -- Martillo del fin del mundo: tormenta del apocalipsis; rayos blancos, humo, ceniza y el suelo temblando
		main = rgb(225, 250, 255), second = rgb(60, 70, 90), accent = rgb(255, 120, 90),
		light = { range = 13, brightness = 1.1, flicker = true },
		layers = {
			{ "bolts", mode = "arc", count = 3, reach = 3 },
			{ "shadow", rate = 8, size = 4, colors = { "second" } },
			{ "snow", rate = 8, size = 0.5, colors = { "second", "main" } },
			{ "rings", rate = 0.8, size = 6, burst = 2 },
			{ "sparks", rate = 30, burst = 24 },
			{ "groundring", at = "feet", rate = 1.2, size = 14 },
			{ "aura", at = "player", rate = 12, colors = { "pale", "second" } },
			{ "ring", at = "feet", radius = 3.4, spin = -3, width = 0.25 },
			{ "smoke", at = "player", rate = 4, colors = { "second" } },
			{ "embers", at = "player", rate = 10, size = 0.6, colors = { "accent", "main" } },
		},
	},
	[39] = { -- Hacha del amanecer: sol naciente; rayos dorados, aureola sobre la cabeza y luz que sube
		main = rgb(255, 225, 140), second = rgb(255, 150, 70), accent = rgb(255, 250, 230),
		light = { range = 13, brightness = 1.1, pulse = 0.2 },
		layers = {
			{ "rays", rate = 10, burst = 18 },
			{ "flames", rate = 10, size = 2, colors = { "accent", "main", "second" } },
			{ "motes", rate = 8 },
			{ "glow", rate = 4, colors = { "second" } },
			{ "ring", at = "head", radius = 1.1, spin = 1.2, width = 0.22, arcs = false, colors = { "accent", "main" } },
			{ "aura", at = "player", rate = 12, colors = { "main", "second" } },
			{ "motes", at = "player", rate = 10, size = 0.8, accel = Vector3.new(0, 3, 0) },
			{ "ring", at = "feet", radius = 3.2, spin = 1.4, width = 0.25, colors = { "accent", "second" } },
			{ "groundring", at = "feet" },
		},
	},
	[40] = { -- Hojas del alba eterna: luz blanca y celeste, con dos aros cruzados girando alrededor del jugador
		main = rgb(215, 245, 255), second = rgb(120, 200, 255), accent = rgb(255, 240, 200),
		light = { range = 12, brightness = 1, pulse = 0.25 },
		layers = {
			{ "glints", rate = 8, burst = 12 },
			{ "motes", rate = 8 },
			{ "orbit", path = "helix", count = 2, radius = 0.9, speed = 5, trail = 0.5, trailLife = 0.8, colors = { "white", "second" } },
			{ "glow", rate = 3, colors = { "second" } },
			{ "ring", at = "player", radius = 3, tilt = 35, spin = 1.6, precess = 0.5, width = 0.22 },
			{ "ring", at = "player", radius = 3, tilt = -35, spin = -1.9, precess = 0.5, width = 0.22, colors = { "accent", "second" } },
			{ "aura", at = "player", rate = 12, colors = { "main", "second" } },
			{ "motes", at = "player", rate = 10, size = 0.8, accel = Vector3.new(0, 2.5, 0) },
			{ "groundring", at = "feet", colors = { "white", "second" } },
		},
	},
	[41] = { -- Lanza del big bang: el estallido que lo creó todo; ondas, rayos y chispas de todos los colores
		main = rgb(255, 255, 255), second = rgb(255, 150, 60), accent = rgb(110, 200, 255),
		light = { range = 14, brightness = 1.2, pulse = 0.9 },
		layers = {
			{ "rings", rate = 2, size = 6, colors = { "main", "second" }, burst = 3 },
			{ "rays", rate = 12, colors = { "main", "accent" }, burst = 20 },
			{ "embers", rate = 12, speed = { 4, 9 }, accel = Vector3.zero, drag = 1.2, colors = { "main", "second", "accent" } },
			{ "stars", rate = 8, colors = { "main", "accent", "second" } },
			{ "glow", rate = 4, size = 5, colors = { "accent" } },
			{ "groundring", at = "feet", rate = 1.4, size = 15, colors = { "main", "accent" } },
			{ "aura", at = "player", rate = 12, colors = { "accent", "second" } },
			{ "orbit", at = "player", path = "atom", count = 3, radius = 3.4, speed = 2.6, orb = 0.9, colors = { "main", "accent" }, emit = { "stars", rate = 5, colors = { "main", "accent", "second" } } },
		},
	},
	[42] = { -- Colmillo astral: energía astral turquesa y magenta, con tres astros girando alrededor del jugador
		main = rgb(70, 235, 220), second = rgb(255, 80, 210),
		light = { range = 14, brightness = 1.2, pulse = 0.3 },
		layers = {
			{ "nebula", rate = 5 },
			{ "stars", rate = 12, burst = 20 },
			{ "orbit", path = "helix", count = 3, radius = 1.5, speed = 5, trail = 0.6, trailLife = 0.9, colors = { "main", "second" } },
			{ "wisps", rate = 7 },
			{ "glow", rate = 3 },
			{ "orbit", at = "player", path = "circle", count = 3, radius = 3.4, speed = 2.2, bob = 1.8, orb = 1, trail = 0.45, trailLife = 1.2, colors = { "main", "second" } },
			{ "aura", at = "player" },
			{ "motes", at = "player", rate = 10, size = 0.8, accel = Vector3.new(0, 3, 0) },
			{ "ring", at = "feet", radius = 3.2, spin = 2, width = 0.25, colors = { "main", "second" } },
			{ "groundring", at = "feet" },
		},
	},
}

return WeaponAuraDefs
