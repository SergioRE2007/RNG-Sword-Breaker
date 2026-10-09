-- Aspecto de cada clima de Config.Weather.Events: solo datos, sin código (los números del juego, qué da cada uno y lo
-- raro que es, están en Config). client/Weather lee de aquí:
--   light  = luz que se mezcla sobre la de la hora (formato en client/DayCycle: colores, `blend`, `brightness`,
--            `density`, `haze`, `saturation`, `dark` y `clock` si el clima trae su propia hora).
--   clouds = { color, blend }: hacia qué color tiñe las nubes y los bancos de niebla del horizonte.
--   calm   = 0 a 1: cuánto amaina los pétalos y las motas que caen siempre (JapanFx.setCalm).
--   extras = propiedades de Lighting que cambian con el clima y vuelven solas a su valor: { bloom = { Intensity = 1 },
--            sky = { MoonAngularSize = 30, MoonTextureId = "..." }, rays = { ... }, color = { ... } } (BloomEffect,
--            Sky, SunRaysEffect y ColorCorrectionEffect). Los números entran poco a poco; lo demás, de golpe.
-- Ojo con lo lejano: la bruma (density y haze de `light`) se come también las partículas y los carteles del cielo. Lo
-- que tiene que verse lejos (la erupción, las nebulosas) pide poca bruma y mucho brillo (`bright`).
--   layers = capas de client/WeatherFx (partículas, sonido...), que explica el formato de cada una.
-- Un clima sin entrada aquí da su suerte igual y se ve con `fallback`.
local WeatherDefs = {}

local rgb = Color3.fromRGB

local DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- bola suave
local SPARK = "rbxasset://textures/particles/sparkles_main.dds" -- destello de puntas
local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- nube
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- aro
local DISC = "rbxasset://textures/whiteCircle.png" -- disco liso
local GLOW = "rbxasset://textures/glow.png" -- resplandor con rayos

-- Audios propios (hechos con tools/sonidos): el ambiente en bucle de cada clima y los golpes sueltos, con varias
-- grabaciones de las que sale una cualquiera.
local function audio(id: number): string
	return string.format("rbxassetid://%d", id)
end
local LOOPS = {
	rain = audio(126429867027338), petals = audio(106452496207802), fog = audio(130665228477090), snow = audio(106429188593546),
	storm = audio(91265788212334), goldenRain = audio(118198780864386), volcanic = audio(109989486621903), aurora = audio(77002411126025),
	bloodMoon = audio(85149091522510), eclipse = audio(99636787982030), cosmic = audio(132355092239531), starfall = audio(96805949045873),
}
local THUNDER = { audio(86071521322650), audio(84604130470234), audio(138904498013191) }
local METEOR = { audio(131981585599369), audio(98682835409009) }
local STAR = { audio(72651967546338), audio(124214242227217) }

local ALONG = Enum.ParticleOrientation.VelocityParallel
local FLAT = Enum.ParticleOrientation.VelocityPerpendicular

WeatherDefs.fallback = {
	light = { blend = 0.4, tint = rgb(235, 235, 255), brightness = 0.9 },
	layers = {},
}

WeatherDefs.events = {
	-- Lluvia: cielo gris azulado, rayas de agua que caen inclinadas, salpicaduras en el suelo y bruma baja.
	rain = {
		light = {
			blend = 0.75, ambient = rgb(98, 110, 134), outdoor = rgb(112, 126, 152), sun = rgb(150, 165, 190),
			air = rgb(122, 136, 160), decay = rgb(72, 84, 106), tint = rgb(214, 226, 245),
			brightness = 0.55, density = 0.46, haze = 2.6, saturation = -0.12, dark = 0.5,
		},
		clouds = { color = rgb(96, 104, 124), blend = 0.85 },
		calm = 0.9,
		layers = {
			{
				kind = "particles", name = "Rain", at = "above", height = 44, area = Vector3.new(110, 1, 110),
				texture = DOT, color = rgb(214, 228, 250), rate = 1500, life = { 0.55, 0.7 }, speed = { 95, 115 },
				spread = { 3, 3 }, accel = Vector3.new(14, 0, 6), size = 0.62, squash = -2.7, orient = ALONG,
				alpha = { { 0, 1 }, { 0.1, 0.2 }, { 1, 0.2 } }, glow = 0.6, influence = 0.2,
			},
			{
				kind = "particles", name = "Splash", at = "ground", height = 0.25, area = Vector3.new(110, 0.2, 110),
				texture = RING, face = Enum.NormalId.Top, color = rgb(215, 228, 250), rate = 260, life = { 0.25, 0.4 },
				speed = { 0.5, 1 }, size = { { 0, 0.2 }, { 1, 1.3 } }, alpha = { { 0, 0.35 }, { 1, 1 } }, orient = FLAT,
				glow = 0.2, influence = 0.6,
			},
			{
				kind = "particles", name = "Haze", at = "ground", height = 3, area = Vector3.new(190, 4, 190),
				texture = SMOKE, face = Enum.NormalId.Top, color = rgb(190, 202, 222), rate = 5, life = { 9, 13 },
				speed = { 0.5, 1.5 }, spread = { 0, 180 }, accel = Vector3.new(2, 0, 1), rot = { 0, 360 }, spin = { -5, 5 },
				size = { { 0, 14 }, { 1, 26 } }, alpha = { { 0, 1 }, { 0.25, 0.86 }, { 0.75, 0.9 }, { 1, 1 } }, influence = 0.7,
			},
			{ kind = "sound", id = LOOPS.rain, volume = 0.3 },
		},
	},

	-- Vendaval de sakura: una ventisca de pétalos que cruza de lado, rachas de viento y todo teñido de rosa.
	petals = {
		light = {
			blend = 0.5, ambient = rgb(176, 124, 154), outdoor = rgb(220, 156, 190), sun = rgb(255, 176, 204),
			air = rgb(255, 188, 216), decay = rgb(255, 146, 184), tint = rgb(255, 226, 238),
			brightness = 1, density = 0.4, haze = 2.4, saturation = 0.1,
		},
		clouds = { color = rgb(255, 170, 205), blend = 0.6 },
		calm = 0.5,
		layers = {
			{
				kind = "particles", name = "Petals", at = "around", height = 8, area = Vector3.new(150, 44, 150),
				turn = CFrame.Angles(0, math.rad(-25), 0), face = Enum.NormalId.Right, texture = DISC,
				color = { rgb(255, 150, 200), rgb(255, 208, 230), rgb(255, 128, 182) }, rate = 420, life = { 3.5, 5 },
				speed = { 26, 40 }, spread = { 14, 10 }, accel = Vector3.new(0, -2.2, 0), rot = { 0, 360 }, spin = { -220, 220 },
				size = 0.42, squash = -0.9, alpha = { { 0, 1 }, { 0.1, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }, glow = 0.25, influence = 0.4,
			},
			{
				kind = "particles", name = "Gusts", at = "around", height = 4, area = Vector3.new(160, 30, 160),
				turn = CFrame.Angles(0, math.rad(-25), 0), face = Enum.NormalId.Right, texture = DOT, color = rgb(255, 236, 244),
				rate = 40, life = { 0.5, 0.8 }, speed = { 110, 150 }, spread = { 3, 3 }, size = 0.6, squash = -3, orient = ALONG,
				alpha = { { 0, 1 }, { 0.3, 0.72 }, { 1, 1 } }, glow = 0.5,
			},
			{ kind = "sound", id = LOOPS.petals, volume = 0.2 },
		},
	},

	-- Niebla: bruma blanca espesa que se come la distancia, bancos que se arrastran por el suelo y gotitas en el aire.
	fog = {
		light = {
			blend = 0.8, ambient = rgb(150, 156, 168), outdoor = rgb(170, 176, 188), sun = rgb(200, 206, 216),
			air = rgb(222, 228, 236), decay = rgb(196, 204, 216), tint = rgb(236, 240, 248),
			brightness = 0.72, density = 0.62, haze = 5, saturation = -0.22, dark = 0.6, night = 0.75,
		},
		clouds = { color = rgb(214, 220, 230), blend = 0.8 },
		calm = 0.7,
		layers = {
			{ kind = "sound", id = LOOPS.fog, volume = 0.15 },
			{
				kind = "particles", name = "Banks", at = "ground", height = 4, area = Vector3.new(210, 6, 210),
				texture = SMOKE, face = Enum.NormalId.Top, color = rgb(232, 238, 246), rate = 9, life = { 12, 17 },
				speed = { 0.4, 1.2 }, spread = { 0, 180 }, accel = Vector3.new(1.4, 0, 0.6), rot = { 0, 360 }, spin = { -4, 4 },
				size = { { 0, 18 }, { 1, 34 } }, alpha = { { 0, 1 }, { 0.2, 0.78 }, { 0.8, 0.84 }, { 1, 1 } }, influence = 0.8,
			},
			{
				kind = "particles", name = "Droplets", at = "around", height = 2, area = Vector3.new(90, 26, 90),
				texture = DOT, color = rgb(245, 248, 255), rate = 40, life = { 5, 8 }, speed = { 0.2, 0.9 },
				spread = { 180, 180 }, size = { { 0, 0 }, { 0.3, 0.22 }, { 1, 0 } }, alpha = { { 0, 1 }, { 0.3, 0.5 }, { 1, 1 } },
				glow = 0.4, influence = 0.4,
			},
		},
	},

	-- Nevada: copos lentos que el viento mece, algunos grandes cerca de la cámara, y una luz fría y azulada.
	snow = {
		light = {
			blend = 0.7, ambient = rgb(152, 166, 196), outdoor = rgb(178, 192, 218), sun = rgb(222, 232, 255),
			air = rgb(216, 228, 246), decay = rgb(172, 192, 222), tint = rgb(228, 238, 255),
			brightness = 0.85, density = 0.42, haze = 2.2, saturation = -0.1, dark = 0.25,
		},
		clouds = { color = rgb(226, 234, 246), blend = 0.85 },
		calm = 1,
		layers = {
			{
				kind = "particles", name = "Snow", at = "above", height = 30, area = Vector3.new(130, 1, 130),
				texture = DOT, color = rgb(250, 252, 255), rate = 320, life = { 5, 6.5 }, speed = { 7, 11 },
				spread = { 22, 22 }, accel = Vector3.new(2.2, 0, 1), size = { { 0, 0.2 }, { 1, 0.34 } },
				alpha = { { 0, 1 }, { 0.08, 0.1 }, { 0.9, 0.15 }, { 1, 1 } }, glow = 0.45, influence = 0.5,
			},
			{
				kind = "particles", name = "Flakes", at = "above", height = 18, area = Vector3.new(60, 1, 60),
				texture = SPARK, color = rgb(255, 255, 255), rate = 10, life = { 4, 5 }, speed = { 5, 8 },
				spread = { 25, 25 }, accel = Vector3.new(2, 0, 1), rot = { 0, 360 }, spin = { -70, 70 }, size = 0.55,
				alpha = { { 0, 1 }, { 0.1, 0.2 }, { 0.9, 0.3 }, { 1, 1 } }, glow = 0.6, influence = 0.3,
			},
			{ kind = "sound", id = LOOPS.snow, volume = 0.2 },
		},
	},

	-- Tormenta eléctrica: diluvio con viento, cielo casi negro y rayos que caen por todo el mapa con su trueno.
	storm = {
		light = {
			blend = 0.85, ambient = rgb(70, 78, 104), outdoor = rgb(84, 94, 124), sun = rgb(120, 130, 165),
			air = rgb(86, 96, 124), decay = rgb(48, 56, 80), tint = rgb(200, 210, 236),
			brightness = 0.4, density = 0.52, haze = 3.2, saturation = -0.18, dark = 0.8,
		},
		clouds = { color = rgb(58, 62, 80), blend = 0.95 },
		calm = 1,
		layers = {
			{
				kind = "particles", name = "Rain", at = "above", height = 44, area = Vector3.new(110, 1, 110),
				texture = DOT, color = rgb(196, 210, 240), rate = 1900, life = { 0.5, 0.62 }, speed = { 112, 135 },
				spread = { 4, 4 }, accel = Vector3.new(34, 0, 14), size = 0.6, squash = -2.7, orient = ALONG,
				alpha = { { 0, 1 }, { 0.1, 0.18 }, { 1, 0.18 } }, glow = 0.75, influence = 0.15,
			},
			{
				kind = "particles", name = "Splash", at = "ground", height = 0.25, area = Vector3.new(110, 0.2, 110),
				texture = RING, face = Enum.NormalId.Top, color = rgb(210, 224, 250), rate = 420, life = { 0.25, 0.4 },
				speed = { 0.5, 1 }, size = { { 0, 0.2 }, { 1, 1.5 } }, alpha = { { 0, 0.3 }, { 1, 1 } }, orient = FLAT,
				glow = 0.2, influence = 0.6,
			},
			{
				kind = "particles", name = "Haze", at = "ground", height = 3, area = Vector3.new(190, 4, 190),
				texture = SMOKE, face = Enum.NormalId.Top, color = rgb(150, 160, 186), rate = 7, life = { 8, 12 },
				speed = { 1, 3 }, spread = { 0, 180 }, accel = Vector3.new(5, 0, 2), rot = { 0, 360 }, spin = { -6, 6 },
				size = { { 0, 14 }, { 1, 28 } }, alpha = { { 0, 1 }, { 0.25, 0.84 }, { 0.75, 0.88 }, { 1, 1 } }, influence = 0.7,
			},
			{ kind = "lightning", every = 4.5, radius = 400, color = rgb(210, 222, 255), flash = 1.3, sound = THUNDER },
			{ kind = "sound", id = LOOPS.storm, volume = 0.4 },
		},
	},

	-- Lluvia dorada: llueve con sol. Gotas finas de oro, destellos en el suelo, rayos de sol y un arcoíris enorme.
	goldenRain = {
		light = {
			blend = 0.55, ambient = rgb(190, 160, 110), outdoor = rgb(230, 200, 140), sun = rgb(255, 220, 150),
			air = rgb(255, 226, 170), decay = rgb(255, 190, 120), tint = rgb(255, 244, 214),
			brightness = 1.12, density = 0.34, haze = 1.8, saturation = 0.3,
		},
		clouds = { color = rgb(255, 226, 170), blend = 0.6 },
		calm = 0.6,
		extras = { rays = { Intensity = 0.2 }, bloom = { Intensity = 0.6 } },
		layers = {
			{ kind = "sound", id = LOOPS.goldenRain, volume = 0.3 },
			{
				kind = "particles", name = "GoldRain", at = "above", height = 42, area = Vector3.new(110, 1, 110),
				texture = DOT, color = { rgb(255, 216, 96), rgb(255, 178, 46) }, rate = 620, life = { 0.7, 0.9 },
				speed = { 68, 88 }, spread = { 3, 3 }, accel = Vector3.new(8, 0, 4), size = 0.42, squash = -2.4, orient = ALONG,
				alpha = { { 0, 1 }, { 0.1, 0.15 }, { 1, 0.15 } }, glow = 0.55,
			},
			{
				kind = "particles", name = "Glints", at = "ground", height = 1.5, area = Vector3.new(110, 2, 110),
				texture = SPARK, face = Enum.NormalId.Top, color = rgb(255, 226, 120), rate = 70, life = { 1, 1.8 },
				speed = { 1, 3 }, spread = { 30, 30 }, spin = { -90, 90 }, size = { { 0, 0 }, { 0.4, 0.75 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.3, 0.1 }, { 1, 1 } }, glow = 1,
			},
			{ kind = "rainbow", center = Vector3.new(560, -60, 380), radius = 380, width = 15, alpha = 0.62 },
		},
	},

	-- Erupción del Fuji: la cima escupe lava y una columna de humo, el cielo se pone rojo y llueven ceniza y ascuas;
	-- de vez en cuando cae una piedra ardiendo en la isla.
	-- Trae su hora (el atardecer): de noche no se veía nada. Y poca bruma, que el Fuji está a más de mil studs.
	volcanic = {
		light = {
			clock = 17.95, blend = 0.7, ambient = rgb(170, 96, 78), outdoor = rgb(214, 120, 90), sun = rgb(255, 130, 76),
			air = rgb(214, 104, 70), decay = rgb(150, 60, 44), tint = rgb(255, 216, 198),
			brightness = 0.95, density = 0.3, haze = 1.2, saturation = 0.12, dark = 0.7,
		},
		clouds = { color = rgb(70, 52, 52), blend = 0.9 },
		calm = 1,
		layers = {
			{
				kind = "particles", name = "Ash", at = "above", height = 32, area = Vector3.new(130, 1, 130),
				texture = DOT, color = { rgb(96, 90, 90), rgb(156, 146, 142) }, rate = 230, life = { 6, 8 }, speed = { 5, 9 },
				spread = { 25, 25 }, accel = Vector3.new(2.5, 0, 1), size = 0.3, alpha = { { 0, 1 }, { 0.08, 0.15 }, { 0.9, 0.25 }, { 1, 1 } },
				influence = 0.8,
			},
			{
				kind = "particles", name = "Embers", at = "around", height = -4, area = Vector3.new(120, 30, 120),
				texture = DOT, face = Enum.NormalId.Top, color = { rgb(255, 210, 100), rgb(255, 90, 30) }, rate = 70, life = { 3, 5 },
				speed = { 2, 6 }, spread = { 40, 40 }, accel = Vector3.new(1.5, 2.2, 0.6), size = { { 0, 0 }, { 0.2, 0.36 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.15, 0 }, { 0.8, 0.2 }, { 1, 1 } }, glow = 1,
			},
			{
				kind = "volcano", mouth = 70, glow = 620, glowBright = 8, color = rgb(255, 120, 40),
				emitters = {
					{ -- columna de humo
						texture = SMOKE, color = { rgb(255, 130, 60), rgb(120, 70, 60), rgb(70, 56, 54) }, rate = 5, life = { 12, 16 }, speed = { 45, 70 },
						spread = { 10, 10 }, accel = Vector3.new(9, 0, 4), rot = { 0, 360 }, spin = { -8, 8 },
						size = { { 0, 80 }, { 1, 300 } }, alpha = { { 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 } }, glow = 0.35, influence = 0.2, bright = 3,
					},
					{ -- fuente de lava (muy brillante: desde la isla se ve a través de toda la bruma)
						texture = DOT, color = { rgb(255, 232, 130), rgb(255, 90, 20) }, rate = 45, life = { 2.5, 4 }, speed = { 130, 210 },
						spread = { 16, 16 }, accel = Vector3.new(0, -70, 0), size = { { 0, 30 }, { 1, 10 } },
						alpha = { { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }, glow = 1, bright = 12,
					},
				},
			},
			{
				kind = "meteors", every = 5, radius = 380, max = 4, size = { 1.6, 3 }, colors = { rgb(255, 140, 50), rgb(255, 90, 30) },
				fall = { 1.7, 2.3 }, reach = 620, slant = Vector3.new(-0.6, 0.55, -0.65), smoky = true, shed = SMOKE,
				sparks = 24, mark = 3, flash = 0.12, volume = 0.45, tail = 0.5, sound = METEOR,
			},
			{ kind = "sound", id = LOOPS.volcanic, volume = 0.35 },
		},
	},

	-- Aurora: se hace de noche y el cielo se llena de cintas verdes, celestes y violetas que ondulan.
	aurora = {
		light = {
			clock = 0.5, blend = 0.6, ambient = rgb(60, 110, 120), outdoor = rgb(80, 150, 150), sun = rgb(140, 230, 200),
			air = rgb(40, 90, 110), decay = rgb(30, 60, 90), tint = rgb(214, 255, 240),
			brightness = 1.35, density = 0.28, haze = 0.6, saturation = 0.05,
		},
		clouds = { color = rgb(60, 110, 130), blend = 0.7 },
		calm = 0.3,
		extras = { bloom = { Intensity = 0.7, Threshold = 1 } },
		layers = {
			{ kind = "sound", id = LOOPS.aurora, volume = 0.2 },
			{
				kind = "aurora",
				ribbons = {
					{ colors = { rgb(80, 255, 170), rgb(90, 220, 255), rgb(170, 120, 255) }, size = 90, height = 400, distance = 520, span = 1500, angle = 0, sway = 90, bob = 30, speed = 0.22, phase = 0, alpha = 0.42, rate = 28 },
					{ colors = { rgb(120, 255, 140), rgb(80, 255, 200) }, size = 72, height = 320, distance = 430, span = 1300, angle = 75, sway = 70, bob = 22, speed = 0.3, phase = 2, alpha = 0.4, rate = 24 },
					{ colors = { rgb(190, 110, 255), rgb(255, 120, 220), rgb(110, 170, 255) }, size = 106, height = 500, distance = 640, span = 1700, angle = 150, sway = 110, bob = 36, speed = 0.17, phase = 4, alpha = 0.36, rate = 24 },
					{ colors = { rgb(80, 255, 190), rgb(120, 200, 255) }, size = 82, height = 380, distance = 500, span = 1500, angle = 215, sway = 80, bob = 26, speed = 0.26, phase = 1, alpha = 0.42, rate = 28 },
					{ colors = { rgb(140, 255, 150), rgb(210, 130, 255) }, size = 94, height = 450, distance = 580, span = 1600, angle = 290, sway = 100, bob = 30, speed = 0.2, phase = 3, alpha = 0.4, rate = 24 },
				},
			},
			{
				kind = "particles", name = "Motes", at = "around", height = 2, area = Vector3.new(110, 30, 110),
				texture = SPARK, color = { rgb(120, 255, 190), rgb(140, 200, 255) }, rate = 36, life = { 4, 7 }, speed = { 0.3, 1.2 },
				spread = { 180, 180 }, accel = Vector3.new(0, 0.3, 0), size = { { 0, 0 }, { 0.3, 0.45 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.3, 0.15 }, { 1, 1 } }, glow = 1,
			},
		},
	},

	-- Luna de sangre: noche roja con una luna enorme y encarnada, niebla carmesí a ras de suelo y motas rojas.
	-- La luna es la del cielo, agrandada; el rojo se lo da el tinte de toda la pantalla (no tiene color propio).
	bloodMoon = {
		light = {
			clock = 20.6, blend = 0.75, ambient = rgb(140, 74, 86), outdoor = rgb(180, 92, 102), sun = rgb(255, 120, 120),
			air = rgb(120, 30, 40), decay = rgb(70, 14, 24), tint = rgb(255, 140, 140),
			brightness = 1.25, density = 0.3, haze = 1, saturation = -0.25,
		},
		clouds = { color = rgb(120, 40, 52), blend = 0.9 },
		calm = 0.4,
		extras = { sky = { MoonAngularSize = 32 }, bloom = { Intensity = 0.9, Threshold = 0.8, Size = 34 } },
		layers = {
			{
				kind = "particles", name = "RedMist", at = "ground", height = 3, area = Vector3.new(200, 5, 200),
				texture = SMOKE, face = Enum.NormalId.Top, color = rgb(170, 36, 48), rate = 7, life = { 11, 15 },
				speed = { 0.4, 1.2 }, spread = { 0, 180 }, accel = Vector3.new(1.2, 0, 0.5), rot = { 0, 360 }, spin = { -4, 4 },
				size = { { 0, 16 }, { 1, 30 } }, alpha = { { 0, 1 }, { 0.2, 0.8 }, { 0.8, 0.86 }, { 1, 1 } }, glow = 0.3, influence = 0.4,
			},
			{
				kind = "particles", name = "Motes", at = "around", height = -2, area = Vector3.new(110, 26, 110),
				texture = DOT, face = Enum.NormalId.Top, color = { rgb(255, 80, 80), rgb(255, 150, 90) }, rate = 40, life = { 4, 7 },
				speed = { 0.4, 1.4 }, spread = { 60, 60 }, accel = Vector3.new(0, 0.5, 0), size = { { 0, 0 }, { 0.3, 0.3 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.3, 0.1 }, { 1, 1 } }, glow = 1,
			},
			{ kind = "sound", id = LOOPS.bloodMoon, volume = 0.25 },
		},
	},

	-- Eclipse: se hace de noche con estrellas y en el cielo queda un disco negro con su corona de rayos. El astro es la
	-- luna del cielo con la textura cambiada por un resplandor, y el disco, una bola negra de verdad delante.
	eclipse = {
		light = {
			clock = 20.2, blend = 0.7, ambient = rgb(92, 80, 150), outdoor = rgb(116, 100, 186), sun = rgb(190, 170, 255),
			air = rgb(40, 32, 84), decay = rgb(24, 18, 60), tint = rgb(226, 216, 255),
			brightness = 1.35, density = 0.26, haze = 0.5, saturation = -0.12,
		},
		clouds = { color = rgb(70, 60, 120), blend = 0.9 },
		calm = 0.4,
		extras = { sky = { MoonTextureId = GLOW, MoonAngularSize = 64 }, bloom = { Intensity = 0.9, Threshold = 0.85, Size = 30 } },
		layers = {
			{ kind = "disc", on = "moon", size = 9.5 },
			{
				kind = "particles", name = "Motes", at = "around", height = 2, area = Vector3.new(110, 30, 110),
				texture = SPARK, color = { rgb(200, 170, 255), rgb(255, 220, 160) }, rate = 30, life = { 4, 7 }, speed = { 0.3, 1 },
				spread = { 180, 180 }, accel = Vector3.new(0, 0.25, 0), size = { { 0, 0 }, { 0.3, 0.42 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.3, 0.2 }, { 1, 1 } }, glow = 1,
			},
			{ kind = "sound", id = LOOPS.eclipse, volume = 0.25 },
		},
	},

	-- Tormenta cósmica: el cielo se abre al espacio. Nebulosas, planetas (uno con anillo), polvo de estrellas que sube
	-- del suelo y alguna estrella fugaz.
	cosmic = {
		light = {
			clock = 0, blend = 0.75, ambient = rgb(96, 66, 160), outdoor = rgb(124, 84, 200), sun = rgb(190, 140, 255),
			air = rgb(60, 30, 120), decay = rgb(30, 14, 70), tint = rgb(232, 214, 255),
			brightness = 1.2, density = 0.2, haze = 0, saturation = 0,
		},
		clouds = { color = rgb(84, 60, 150), blend = 0.85 },
		calm = 0.6,
		extras = { bloom = { Intensity = 0.85, Threshold = 0.95, Size = 30 } },
		layers = {
			{
				kind = "sky",
				items = {
					{ on = Vector3.new(0.5, 0.5, 0.7), size = 70, image = SMOKE, color = rgb(170, 80, 255), alpha = 0.15, spin = 0.6, bright = 5 },
					{ on = Vector3.new(-0.7, 0.45, 0.5), size = 60, image = SMOKE, color = rgb(70, 120, 255), alpha = 0.2, spin = -0.5, bright = 5 },
					{ on = Vector3.new(-0.3, 0.6, -0.7), size = 75, image = SMOKE, color = rgb(255, 90, 200), alpha = 0.2, spin = 0.4, bright = 5 },
					{ on = Vector3.new(0.8, 0.35, -0.4), size = 55, image = SMOKE, color = rgb(90, 220, 255), alpha = 0.2, spin = -0.7, bright = 5 },
					{ on = Vector3.new(-0.2, 0.55, 0.8), size = 40, image = GLOW, color = rgb(220, 200, 255), alpha = 0.4, spin = 1, pulse = 0.15, bright = 3 },
					{ on = Vector3.new(0.6, 0.42, -0.68), size = 30, image = DISC, gradient = { rgb(255, 196, 130), rgb(120, 50, 90) }, ring = { color = rgb(255, 224, 180), tilt = -18 }, alpha = 0, bright = 2 },
					{ on = Vector3.new(-0.75, 0.3, -0.1), size = 6, image = DISC, gradient = { rgb(150, 220, 255), rgb(40, 60, 140) }, alpha = 0, bright = 2 },
					{ on = Vector3.new(0.1, 0.75, 0.6), size = 3.5, image = DISC, gradient = { rgb(255, 150, 170), rgb(110, 40, 80) }, alpha = 0, bright = 2 },
				},
			},
			{
				kind = "particles", name = "Stardust", at = "around", height = -6, area = Vector3.new(130, 40, 130),
				texture = SPARK, face = Enum.NormalId.Top, color = { rgb(190, 140, 255), rgb(120, 220, 255), rgb(255, 150, 230) },
				rate = 110, life = { 4, 7 }, speed = { 1.5, 4 }, spread = { 20, 20 }, accel = Vector3.new(0, 1.2, 0), spin = { -80, 80 },
				size = { { 0, 0 }, { 0.25, 0.5 }, { 1, 0 } }, alpha = { { 0, 1 }, { 0.2, 0.05 }, { 0.8, 0.2 }, { 1, 1 } }, glow = 1,
			},
			{
				kind = "streaks", rate = 0.7, pool = 8, colors = { rgb(200, 150, 255), rgb(140, 220, 255) }, length = { 500, 900 },
				life = { 0.6, 1.1 }, width = { 8, 14 }, bigChance = 0,
			},
			{ kind = "sound", id = LOOPS.cosmic, volume = 0.25 },
		},
	},

	-- Lluvia de estrellas (el más raro): noche cerrada con el cielo entero cruzado por estrellas fugaces de colores, una
	-- luz blanca azulada que late, polvo de estrellas cayendo y meteoritos que se estrellan en la isla.
	starfall = {
		light = {
			clock = 0, blend = 0.7, ambient = rgb(120, 140, 205), outdoor = rgb(150, 172, 240), sun = rgb(200, 220, 255),
			air = rgb(60, 90, 170), decay = rgb(40, 60, 130), tint = rgb(226, 236, 255),
			brightness = 1.4, density = 0.2, haze = 0, saturation = 0.1,
		},
		clouds = { color = rgb(120, 150, 230), blend = 0.8 },
		calm = 0.8,
		extras = { bloom = { Intensity = 0.65, Threshold = 1, Size = 30 } },
		layers = {
			{
				kind = "sky",
				items = {
					{ on = Vector3.new(0.42, 0.78, -0.3), size = 34, image = GLOW, color = rgb(200, 226, 255), alpha = 0.3, spin = 1.5, pulse = 0.2, bright = 3 },
					{ on = Vector3.new(-0.6, 0.5, 0.6), size = 80, image = SMOKE, color = rgb(90, 130, 255), alpha = 0.5, spin = 0.4, bright = 3 },
					{ on = Vector3.new(0.7, 0.4, 0.55), size = 70, image = SMOKE, color = rgb(150, 110, 255), alpha = 0.55, spin = -0.5, bright = 3 },
				},
			},
			{
				kind = "streaks", rate = 70, pool = 130, colors = { Color3.new(1, 1, 1), rgb(150, 225, 255), rgb(255, 226, 150), rgb(255, 170, 225), rgb(170, 190, 255) },
				length = { 600, 1200 }, life = { 0.6, 1.2 }, width = { 9, 20 }, bigChance = 0.06, flash = 0.14, bright = 3,
			},
			{ kind = "sound", id = LOOPS.starfall, volume = 0.2 },
			{
				kind = "meteors", every = 2.2, radius = 400, max = 10, size = { 2.6, 5 },
				colors = { rgb(140, 225, 255), rgb(255, 226, 140), rgb(255, 160, 220), rgb(200, 180, 255) },
				fall = { 1, 1.5 }, reach = 750, slant = Vector3.new(0.42, 0.78, -0.3), column = true, sparks = 50, mark = 4, sound = STAR,
				flash = 0.32, volume = 0.7, tail = 0.7,
			},
			{
				kind = "particles", name = "Stardust", at = "above", height = 30, area = Vector3.new(130, 1, 130),
				texture = SPARK, color = { Color3.new(1, 1, 1), rgb(150, 225, 255), rgb(255, 226, 150) }, rate = 160, life = { 4, 6 },
				speed = { 6, 10 }, spread = { 18, 18 }, spin = { -100, 100 }, size = { { 0, 0 }, { 0.2, 0.5 }, { 1, 0 } },
				alpha = { { 0, 1 }, { 0.15, 0 }, { 0.8, 0.2 }, { 1, 1 } }, glow = 1,
			},
		},
	},
}

return WeatherDefs
