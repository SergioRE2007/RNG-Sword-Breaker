-- Cinemáticas de las tiradas de arma más raras (pedido por el usuario: "al juego le falta dopamina"). Librería sin
-- start(): la llama client/RollReveal cuando una tirada llega a un nivel con `cinematic` en sus LEVELS. Coge la
-- cámara unos segundos, enseña la escena de su tema y la devuelve; el arma sale luego en el mundo y vuela al
-- jugador como siempre. Temas:
--   star  — cae una estrella fugaz sobre el sitio del objeto roto y el arma sale del cráter de luz.
--   smith — un herrero espectral gigante la forja a martillazos en un yunque; el último la templa.
--   nova  — una estrella se encoge, calla y estalla; el arma queda girando en el núcleo.
-- Al final de todas sale la tarjeta del arma (rareza, nombre y su "1 entre N"), y el número sube contando hasta el
-- suyo (`RollCinematic.countUp`, que también usa el cartel del mundo de RollReveal).
-- Solo se ve una a la vez (las demás esperan turno, MAX_WAITING como mucho) y todo lo que toca (cámara, Hud,
-- Lighting) lo deja como estaba `release`, pase lo que pase: acabar, saltarla, un viaje o un error.
-- El herrero y la supernova se ruedan en un escenario cerrado y negro, lejos por encima del mapa, para no depender
-- de la hora ni del clima; la estrella, en el sitio de verdad.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local PropModel = require(ReplicatedStorage.Shared.PropModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Shards = require(script.Parent.Shards)
local Ui = require(script.Parent.Ui)
local WeaponAuraDefs = require(script.Parent.WeaponAuraDefs)

local RollCinematic = {}

local player = Players.LocalPlayer
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 220, 100)
local EMBER = Color3.fromRGB(255, 170, 70) -- el arma al rojo y las chispas del yunque antes de saber la rareza
local VOID = Color3.fromRGB(6, 5, 12) -- paredes del escenario

local TEX = WeaponAuraDefs.textures
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Solo en Studio: Config.Test.RevealSlow alarga todos los tiempos, para revisarla en capturas.
local BASE = if RunService:IsStudio() then Config.Test.RevealSlow or 1 else 1
-- Ritmo de cada tema: por cuánto se alargan todos sus tiempos (pedido por el usuario, que las vio a su velocidad
-- de partida y le parecieron rápidas: la estrella y el herrero, bastante más lentas; las supernovas, un poco).
local PACE = { star = 2.4, smith = 2.4, nova = 1.2 }
local SLOW = BASE -- lo que vale ahora mismo: BASE por el ritmo del tema en marcha
local SKIP = "RollCinematic:skip" -- lo que "lanza" una escena al saltarla: corta la secuencia donde esté
local MAX_WAITING = 2 -- cinemáticas esperando turno; las que lleguen de más se enseñan en el mundo
local GRACE = 0.6 -- segundos hasta que sale el botón de saltar
local TIMEOUT = 35 -- red de seguridad: ninguna dura tanto
local STAGE_UP = 700 -- studs por encima de la cámara a los que se monta el escenario
local STAGE_HALF = 90 -- media arista del cubo negro
local DISPLAY = 5 -- studs que mide el arma enseñada
local TILT = CFrame.Angles(0, 0, math.rad(-22))
local STUCK = 170 -- grados del arma clavada de punta en el cráter de la estrella (casi boca abajo)
local SCREEN = Vector2.new(1100, 700) -- por debajo de este tamaño de pantalla la tarjeta se encoge (como el HUD)
local CARD = Vector2.new(460, 176)
local CARD_HOME = UDim2.fromScale(0.5, 0.88) -- sitio de la tarjeta (su borde de abajo)
-- Segundos que tarda el "1 entre N" en subir hasta su número, por nivel de RollReveal.
local COUNT = { [2] = 0.5, [3] = 0.8, [4] = 1.1, [5] = 2.2, [6] = 3 }
-- Capas de la interfaz (la del juego ordena el ZIndex globalmente; aquí también).
local Z = { rays = 1, bars = 2, card = 3, rim = 4, chip = 5, text = 6, skip = 7, cover = 20 }

local current = nil -- la escena en marcha
local waiting = 0 -- las que esperan turno
local hooked = false

-- Utilidades ----------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local created = TweenService:Create(instance, TweenInfo.new(seconds * SLOW, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	created:Play()
	return created
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function outCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Pasa del final y vuelve: lo que aparece "salta" un poco.
local function outBack(t: number): number
	local c = 1.70158
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function seq(points: { { number } }): NumberSequence
	local list = {}
	for _, point in points do
		table.insert(list, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(list)
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Corta la secuencia si la han saltado o ya no hay escena.
local function check(s)
	if s.skipped or s.released then
		error(SKIP, 0)
	end
end

local function wait(s, seconds: number)
	local elapsed = 0
	while elapsed < seconds * SLOW do
		elapsed += RunService.RenderStepped:Wait()
		check(s)
	end
end

-- Llama a `step(avance de 0 a 1)` cada fotograma durante `seconds` (espera a que acabe).
local function animate(s, seconds: number, step: (number) -> ())
	local total = seconds * SLOW
	local elapsed = 0
	while elapsed < total do
		elapsed += RunService.RenderStepped:Wait()
		check(s)
		step(math.min(elapsed / total, 1))
	end
end

-- Pieza de efecto: anclada, sin sombra ni colisiones.
local function piece(s, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = s.folder
	return part
end

-- Pieza invisible de la que cuelgan partículas y luces.
local function point(s, position: Vector3, size: number?): Part
	return piece(s, Enum.PartType.Block, Vector3.one * (size or 1), CFrame.new(position), WHITE, 1)
end

-- Pieza de luz que crece hasta `to` mientras se apaga, y se borra.
local function fading(s, shape: Enum.PartType, cframe: CFrame, from: Vector3, to: Vector3, color: Color3, transparency: number, seconds: number)
	local part = piece(s, shape, from, cframe, color, transparency)
	tween(part, seconds, { Size = to, Transparency = 1 })
	Debris:AddItem(part, seconds * SLOW + 0.1)
end

-- Onda plana que se abre; `tilt` la saca del suelo (para las explosiones en el aire).
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
local function ring(s, position: Vector3, from: number, to: number, color: Color3, seconds: number, tilt: CFrame?)
	fading(s, Enum.PartType.Cylinder, CFrame.new(position) * (tilt or CFrame.identity) * FLAT, Vector3.new(0.15, from, from), Vector3.new(0.15, to, to), color, 0.3, seconds)
end

local function emitter(parent: Instance, props: { [string]: any }, count: number?): ParticleEmitter
	local created = Instance.new("ParticleEmitter")
	created.Rate = 0
	created.LightInfluence = 0
	for name, value in props do
		(created :: any)[name] = value
	end
	created.Parent = parent
	if count then
		created:Emit(count)
	end
	return created
end

-- Chispas que saltan de golpe.
local function sparks(parent: Instance, color: Color3, count: number, speed: number, size: number)
	emitter(parent, {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.4 * SLOW, 1 * SLOW),
		Speed = NumberRange.new(speed * 0.4 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2.5,
		Size = seq({ { 0, size }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 1, 1 } }),
	}, count)
end

-- Chispas de fragua: saltan hacia arriba en abanico y caen con su peso.
local function forgeSparks(parent: Instance, color: Color3, count: number, speed: number)
	emitter(parent, {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.6 * SLOW, 1.3 * SLOW),
		Speed = NumberRange.new(speed * 0.35 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(75, 75),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60 / (SLOW * SLOW), 0),
		Drag = 0.8 / SLOW,
		Size = seq({ { 0, 0.75 }, { 0.6, 0.45 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
	}, count)
end

-- Columna de luz que sube desde `position`: se abre de golpe y se va cerrando.
local function pillar(s, position: Vector3, height: number, width: number, color: Color3, seconds: number)
	local base = point(s, position)
	local low, high = Instance.new("Attachment"), Instance.new("Attachment")
	high.Position = Vector3.new(0, height, 0)
	-- La textura es un resplandor redondo estirado a lo largo: da los bordes suaves (un Beam liso, o varios encimados,
	-- se ven como rectángulos de canto duro). Empieza bajo el suelo para que lo más vivo quede cerca de la base.
	low.Position = Vector3.new(0, -height * 0.45, 0)
	low.Parent, high.Parent = base, base
	for _, layer in { { 1.2, 0.5, 0.3 }, { 0.45, 0.05, 0.75 } } do
		local wide = width * layer[1]
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = low, high
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Texture = TEX.halo
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(color:Lerp(WHITE, layer[3]))
		beam.Transparency = NumberSequence.new(layer[2])
		beam.Width0, beam.Width1 = wide * 0.2, wide * 0.2
		beam.Parent = base
		tween(beam, 0.1, { Width0 = wide, Width1 = wide * 0.7 })
		task.delay(0.1 * SLOW, function()
			if beam.Parent then
				tween(beam, seconds, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
	end
	Debris:AddItem(base, (seconds + 0.1) * SLOW + 0.1)
end

-- Rayo en zigzag de `from` a `to`: un núcleo blanco dentro de un resplandor del color, que se apaga.
local function bolt(s, from: Vector3, to: Vector3, color: Color3, width: number, seconds: number)
	local points = { from }
	local steps = 8
	local span = (to - from).Magnitude
	for index = 1, steps - 1 do
		table.insert(points, from:Lerp(to, index / steps) + rng:NextUnitVector() * span * 0.05)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local long = (b - a).Magnitude
		local cframe = CFrame.lookAt((a + b) / 2, b)
		for _, layer in { { WHITE, width * 0.35, 0 }, { color, width, 0.55 } } do
			local part = piece(s, Enum.PartType.Block, Vector3.new(layer[2], layer[2], long), cframe, layer[1], layer[3])
			tween(part, seconds, { Transparency = 1, Size = Vector3.new(0.05, 0.05, long) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(part, seconds * SLOW + 0.1)
		end
	end
end

-- Vida de una partícula en segundos de escena: Roblox no deja pasar de 20 (a cámara lenta se quedan en eso).
local function life(from: number, to: number?): NumberRange
	return NumberRange.new(math.min(from * SLOW, 20), math.min((to or from) * SLOW, 20))
end

-- Brasas que se quedan subiendo de `parent` durante `seconds`.
local function embers(parent: Instance, color: Color3, rate: number, seconds: number)
	local created = emitter(parent, {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		Rate = rate / SLOW,
		Lifetime = life(1.2, 2.2),
		Speed = NumberRange.new(1 / SLOW, 4 / SLOW),
		SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 3 / (SLOW * SLOW), 0),
		Size = seq({ { 0, 0.5 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
	})
	task.delay(seconds * SLOW, function()
		created.Enabled = false
	end)
end

-- Llamaradas (textura animada de fuego) que saltan hacia fuera.
local function flames(parent: Instance, color: Color3, count: number, speed: number, size: number)
	emitter(parent, {
		Texture = TEX.fire,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color),
		LightEmission = 0.8,
		Brightness = 1.6,
		Lifetime = life(0.5, 0.9),
		Speed = NumberRange.new(speed * 0.4 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2 / SLOW,
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, size * 0.4 }, { 0.4, size }, { 1, size * 0.6 } }),
		Transparency = seq({ { 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 } }),
	}, count)
end

-- Destello alargado de lente: una línea de luz centrada en `centre`, a lo largo de `axis`, que se apaga hacia las
-- puntas. Devuelve el Beam (cuelga de su propia pieza: borrar `.Parent`).
local function streak(s, centre: Vector3, axis: Vector3, length: number, width: number, color: Color3): Beam
	local base = point(s, centre)
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Position, b.Position = -axis * length / 2, axis * length / 2
	a.Parent, b.Parent = base, base
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a, b
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color:Lerp(WHITE, 0.4))
	beam.Transparency = seq({ { 0, 1 }, { 0.5, 0.15 }, { 1, 1 } })
	beam.Width0, beam.Width1 = width, width
	beam.Parent = base
	return beam
end

-- Anillo de polvo que se abre a ras de suelo.
local function dustRing(s, position: Vector3, color: Color3, count: number, speed: number)
	local base = point(s, position)
	for index = 1, count do
		local out = Instance.new("Attachment")
		out.CFrame = CFrame.Angles(0, index / count * math.pi * 2, 0) * CFrame.Angles(0, 0, -math.pi / 2)
		out.Parent = base
		emitter(out, {
			Texture = SMOKE,
			Color = ColorSequence.new(color),
			LightEmission = 0.15,
			Lifetime = life(0.8, 1.4),
			Speed = NumberRange.new(speed * 0.6 / SLOW, speed / SLOW),
			SpreadAngle = Vector2.new(9, 9),
			EmissionDirection = Enum.NormalId.Top,
			Drag = 1.6 / SLOW,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30 / SLOW, 30 / SLOW),
			Size = seq({ { 0, 1.4 }, { 1, 5.5 } }),
			Transparency = seq({ { 0, 0.45 }, { 0.6, 0.7 }, { 1, 1 } }),
		}, 2)
	end
end

-- Grietas de luz que salen del centro por el suelo, en zigzag, y se apagan.
local function cracks(s, centre: Vector3, color: Color3, count: number, length: number, seconds: number)
	for index = 1, count do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local from = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 1.2
		local reach = length * rng:NextNumber(0.55, 1)
		for step = 1, 3 do
			angle += rng:NextNumber(-0.55, 0.55)
			local to = from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach / 3
			local part = piece(s, Enum.PartType.Block, Vector3.new(0.42 - step * 0.1, 0.08, reach / 3), CFrame.lookAt((from + to) / 2, to), color, 0.1)
			tween(part, seconds, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(part, seconds * SLOW + 0.1)
			from = to
		end
	end
end

-- Estrella fugaz pequeña que cruza de `from` a `to`.
local function meteor(s, from: Vector3, to: Vector3, color: Color3, size: number, seconds: number)
	local head = piece(s, Enum.PartType.Ball, Vector3.one * size, CFrame.new(from), WHITE, 0)
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Position, b.Position = Vector3.new(0, size / 2, 0), Vector3.new(0, -size / 2, 0)
	a.Parent, b.Parent = head, head
	local tail = Instance.new("Trail")
	tail.Attachment0, tail.Attachment1 = a, b
	tail.Color = ColorSequence.new(WHITE, color)
	tail.Transparency = seq({ { 0, 0 }, { 1, 1 } })
	tail.WidthScale = seq({ { 0, 1 }, { 1, 0 } })
	tail.Lifetime = 0.3 * SLOW
	tail.LightEmission = 1
	tail.FaceCamera = true
	tail.Parent = head
	tween(head, seconds, { Position = to }, Enum.EasingStyle.Linear)
	task.delay(seconds * SLOW, function()
		head.Transparency = 1
	end)
	Debris:AddItem(head, (seconds + 0.35) * SLOW)
end

-- Polvo de estrellas que sale hacia fuera.
local function stardust(parent: Instance, color: Color3, count: number, speed: number, size: number)
	emitter(parent, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 0.8,
		Brightness = 1.6,
		Lifetime = NumberRange.new(0.8 * SLOW, 1.6 * SLOW),
		Speed = NumberRange.new(speed * 0.3 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		RotSpeed = NumberRange.new(-60, 60),
		Size = seq({ { 0, 0 }, { 0.2, size }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
	}, count)
end

-- Textura de cara a la cámara que aparece, se queda y se va (estallidos, destellos, remolinos). Las de fondo
-- negro (nova, vortex, portal) van con `emission` 1 o se ven como cuadrados negros.
local function sprite(parent: Instance, texture: string, color: Color3, size: number, seconds: number, turn: number, emission: number, grow: boolean?, angle: number?)
	emitter(parent, {
		Texture = texture,
		Color = ColorSequence.new(color),
		LightEmission = emission,
		Brightness = 1.4,
		Lifetime = life(seconds),
		Speed = NumberRange.new(0),
		Rotation = if angle then NumberRange.new(angle) else NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(turn / SLOW),
		LockedToPart = true,
		Size = if grow then seq({ { 0, size * 0.15 }, { 1, size } }) else seq({ { 0, 0 }, { 0.15, size }, { 0.8, size }, { 1, size * 0.7 } }),
		Transparency = seq({ { 0, 1 }, { 0.12, 0.3 }, { 0.6, 0.45 }, { 1, 1 } }),
	}, 1)
end

-- Rayos de luz girando detrás del arma enseñada. La textura es un haz hacia un solo lado: con una sola copia se
-- veía, según el giro, como una franja suelta a un lado del arma; con tres repartidas hace la estrella entera.
local function shine(parent: Instance, color: Color3, size: number, seconds: number)
	for index = 0, 2 do
		sprite(parent, TEX.shine, color, size, seconds, 14, 1, false, index * 120)
	end
end

-- Sello tumbado en el suelo, girando. Flojo y medio transparente a propósito: a mediodía se quema a blanco.
local function sealOn(s, position: Vector3, texture: string, color: Color3, size: number, seconds: number, turn: number): Part
	local base = point(s, position)
	emitter(base, {
		Texture = texture,
		Color = ColorSequence.new(color),
		LightEmission = 0.4,
		Brightness = 1.1,
		Lifetime = NumberRange.new(seconds * SLOW),
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0),
		RotSpeed = NumberRange.new(turn / SLOW),
		LockedToPart = true,
		Size = seq({ { 0, 0 }, { 0.08, size }, { 0.9, size }, { 1, size * 0.6 } }),
		Transparency = seq({ { 0, 1 }, { 0.1, 0.45 }, { 0.85, 0.5 }, { 1, 1 } }),
	}, 1)
	return base
end

-- Para las tiradas que se enseñan en el mundo (client/RollReveal): de `s` solo usan `s.folder`, la carpeta donde
-- crean sus piezas.
RollCinematic.fx = { pillar = pillar, embers = embers, flames = flames, dustRing = dustRing }

-- El arma ---------------------------------------------------------------------------------

--Modelo del arma de verdad, anclado y con el giro en su centro, encogido al mínimo. Devuelve también cuánto hay
-- que escalarlo para que mida `display` studs (lo usa también RollReveal).
function RollCinematic.sword(index: number, metal: number?, parent: Instance, display: number?): (Model, number)
	local model = Instance.new("Model")
	model.Name = "Sword"
	SwordModel.build(index, model, CFrame.identity, 1, true, metal)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CastShadow = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	local box, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	-- Todas se enseñan del mismo largo, salvo las muy finas (lanzas), que a ese largo casi no se verían: algo más.
	local long = math.max(size.X, size.Y, size.Z, 0.1)
	local wide = math.max(size.X + size.Y + size.Z - long - math.min(size.X, size.Y, size.Z), 0.1)
	local fit = (display or DISPLAY) / long * math.clamp(math.sqrt(long / wide / 4), 1, 1.5)
	model:ScaleTo(fit * 0.02)
	model.Parent = parent
	return model, fit
end

-- Pone el arma en la escena: la mueve el bucle de la escena con lo que diga `s.weapon` (sitio, giro, tamaño).
local function weapon(s, info, position: Vector3, display: number)
	local model, fit = RollCinematic.sword(info.roll.index, info.roll.metal, s.folder, display)
	local outline = Instance.new("Highlight")
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.OutlineColor = info.bright
	outline.FillColor = WHITE
	outline.FillTransparency = 0.85
	outline.Parent = model
	s.weapon = { model = model, fit = fit, outline = outline, position = position, yaw = 0, spin = 0, scale = 0.02, shown = 0, tilt = TILT, bob = 0 }
	return s.weapon
end

-- El contador ---------------------------------------------------------------------------

-- El número sube de 1 a `target` en `seconds`, por multiplicación (vale igual con 150 que con 1 Sp): arranca
-- deprisa y frena al llegar. `paint(texto abreviado, llegó)` lo escribe; cada tramo suena un tic más agudo.
-- `step`, opcional, se llama cada fotograma (para cortar: puede lanzar).
function RollCinematic.countUp(target: number, seconds: number, paint: (string, boolean) -> (), step: (() -> ())?)
	local total = seconds * SLOW
	local elapsed = 0
	local note = -1
	while elapsed < total do
		elapsed += RunService.RenderStepped:Wait()
		if step then
			step()
		end
		local eased = 1 - (1 - math.min(elapsed / total, 1)) ^ 2
		paint(Format.short(math.max(1, math.floor(target ^ eased))), false)
		local now = math.floor(eased * 14)
		if now ~= note then
			note = now
			Sfx.play("tick", 0.7, 2 ^ (now / 12))
		end
	end
	paint(Format.short(target), true)
end

function RollCinematic.countTime(level: number): number?
	return COUNT[level]
end

-- La interfaz ---------------------------------------------------------------------------

local function buildGui(s, info)
	local view = workspace.CurrentCamera.ViewportSize
	local factor = math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), 0.6, 1)
	local color, bright = info.color, info.bright

	local gui = Instance.new("ScreenGui")
	gui.Name = "RollCinematic"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	-- Tapa a pantalla completa: fundidos a negro y destellos.
	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = BLACK
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.ZIndex = Z.cover
	cover.Parent = gui

	-- Barras de cine.
	local bars = {}
	for index, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = if index == 1 then "BarTop" else "BarBottom"
		bar.AnchorPoint = Vector2.new(0, 1 - anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, 0.085)
		bar.BackgroundColor3 = BLACK
		bar.BorderSizePixel = 0
		bar.ZIndex = Z.bars
		bar.Parent = gui
		tween(bar, 0.3, { AnchorPoint = Vector2.new(0, anchor) })
		bars[index] = bar
	end

	-- Frase del nivel, arriba.
	local line = Ui.label(gui, math.round(30 * factor))
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(0.5, 0.115)
	line.Size = UDim2.fromScale(0.9, 0.07)
	line.Text = Ui.upper(Lang.t(nil, info.line))
	line.TextColor3 = if info.level >= 6 then GOLD else bright
	line.TextTransparency = 1
	line.ZIndex = Z.text
	local lineStroke = line:FindFirstChildOfClass("UIStroke")
	if lineStroke then
		lineStroke.Transparency = 1
	end

	-- Tarjeta del arma, abajo en el centro: rayos girando detrás, chapa de rareza, nombre y el "1 entre N" en grande.
	local holder = Instance.new("Frame")
	holder.Name = "Card"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = CARD_HOME
	holder.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder

	local rays = Ui.image(holder, "boton_rayos")
	rays.Name = "Rays"
	rays.Size = UDim2.fromOffset(CARD.X * 1.25, CARD.X * 1.25)
	rays.ImageColor3 = if info.level >= 6 then GOLD else bright
	rays.ImageTransparency = 1
	rays.ZIndex = Z.rays
	-- Segunda tanda de rayos, más corta y clara, girando al revés: se enciende cuando el número llega.
	local rays2 = Ui.image(holder, "boton_rayos")
	rays2.Name = "RaysInner"
	rays2.Size = UDim2.fromOffset(CARD.X * 0.9, CARD.X * 0.9)
	rays2.ImageColor3 = (if info.level >= 6 then GOLD else bright):Lerp(WHITE, 0.6)
	rays2.ImageTransparency = 1
	rays2.ZIndex = Z.rays

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = WHITE
	plate.BorderSizePixel = 0
	plate.ZIndex = Z.card
	plate.Parent = holder
	Ui.round(plate, 18)
	Ui.gradient(plate, Color3.fromRGB(52, 46, 84):Lerp(color, 0.18), Color3.fromRGB(18, 16, 32), 90)
	Ui.stroke(plate, BLACK, 5)
	-- Canto del color de la rareza por dentro del borde negro.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.BackgroundTransparency = 1
	rim.ZIndex = Z.rim
	rim.Parent = holder
	Ui.round(rim, 14)
	Ui.stroke(rim, if info.level >= 6 then GOLD else bright, 3)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(10, 8)
	gloss.Size = UDim2.new(1, -20, 0.3, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.9
	gloss.BorderSizePixel = 0
	gloss.ZIndex = Z.rim
	gloss.Parent = holder
	Ui.round(gloss, 12)
	-- Brillo que recorre la tarjeta en diagonal: un marco blanco cuyo degradado solo deja ver una franja, que se
	-- mueve con `Offset` (sin recortes ni piezas giradas: un hijo girado se sale del recorte).
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0.5, 0.5)
	sheen.Position = UDim2.fromScale(0.5, 0.5)
	sheen.Size = UDim2.new(1, -10, 1, -10)
	sheen.BackgroundColor3 = WHITE
	sheen.BorderSizePixel = 0
	sheen.ZIndex = Z.rim
	sheen.Parent = holder
	Ui.round(sheen, 14)
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = seq({ { 0, 1 }, { 0.38, 1 }, { 0.5, 0.6 }, { 0.62, 1 }, { 1, 1 } })
	band.Offset = Vector2.new(-1, 0)
	band.Parent = sheen

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = content

	local rarityText = Ui.upper(Lang.t(nil, info.tier.name))
	local chip = Instance.new("Frame")
	chip.Name = "Rarity"
	chip.LayoutOrder = 1
	chip.Size = UDim2.fromOffset(TextService:GetTextSize(rarityText, 22, Ui.FONT, Vector2.new(1000, 34)).X + 40, 34)
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.ZIndex = Z.chip
	chip.Parent = content
	Ui.round(chip, 11)
	Ui.gradient(chip, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.4), 90)
	Ui.stroke(chip, BLACK, 3)
	local chipText = Ui.label(chip, 22)
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.Text = rarityText
	chipText.ZIndex = Z.text
	local chipScale = Instance.new("UIScale")
	chipScale.Scale = 0
	chipScale.Parent = chip

	local roll = info.roll
	local sword = Config.Swords[roll.index]
	local nameColor = if roll.metal and roll.metal > 0 then Config.Metals[roll.metal].color else sword.color
	local name = Ui.label(content, 27)
	name.Name = "Title"
	name.LayoutOrder = 2
	name.Size = UDim2.new(1, -28, 0, 34)
	name.TextScaled = true
	name.Text = Permanent.name(roll.index, roll.metal, roll.size)
	name.TextColor3 = nameColor:Lerp(WHITE, 0.4)
	name.TextTransparency = 1
	name.ZIndex = Z.text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 27
	limit.MinTextSize = 14
	limit.Parent = name

	local odds = Ui.label(content, 44)
	odds.Name = "Odds"
	odds.LayoutOrder = 3
	odds.Size = UDim2.new(1, -28, 0, 54)
	odds.Text = ""
	odds.TextColor3 = WHITE
	odds.ZIndex = Z.text
	local oddsScale = Instance.new("UIScale")
	oddsScale.Parent = odds

	if not roll.kept then
		local sold = Ui.label(content, 16)
		sold.Name = "Sold"
		sold.LayoutOrder = 4
		sold.Size = UDim2.new(1, -28, 0, 18)
		sold.Text = Lang.t(nil, "sold")
		sold.TextColor3 = Ui.COLORS.orange
		sold.ZIndex = Z.text
		chip.Size = UDim2.fromOffset(chip.Size.X.Offset, 30)
	end

	-- Saltar: solo con su botón (un clic cualquiera no vale: el jugador va haciendo clic para atacar y se la saltaría
	-- sin querer).
	local skip = Ui.button(gui, Lang.t(nil, "Skip"), Ui.COLORS.gray)
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 0.9, 0)
	skip.Size = UDim2.fromOffset(150, 52)
	skip.TextSize = 22
	skip.ZIndex = Z.skip
	skip.Visible = false
	local skipScale = Instance.new("UIScale")
	skipScale.Scale = factor
	skipScale.Parent = skip
	skip.Activated:Connect(function()
		s.skipped = true
	end)
	task.delay(GRACE, function()
		if gui.Parent then
			skip.Visible = true
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	s.gui = gui
	s.ui = { cover = cover, line = line, lineStroke = lineStroke, holder = holder, scale = scale, factor = factor, rays = rays, rays2 = rays2, band = band, lineSize = line.TextSize, chipScale = chipScale, name = name, odds = odds, oddsScale = oddsScale }
end

-- Fundido de la tapa: a `transparency` en `seconds`.
local function cover(s, color: Color3, from: number, to: number, seconds: number)
	local frame = s.ui.cover
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = from
	tween(frame, seconds, { BackgroundTransparency = to })
end

local function showLine(s)
	local ui = s.ui
	tween(ui.line, 0.25, { TextTransparency = 0 })
	if ui.lineStroke then
		tween(ui.lineStroke, 0.25, { Transparency = 0 })
	end
end

-- Cambia la frase de arriba de golpe (la escalera de rarezas de la supernova), con un salto.
local function setLine(s, text: string, color: Color3)
	local ui = s.ui
	ui.line.Text = Ui.upper(text)
	ui.line.TextColor3 = color
	ui.line.TextTransparency = 0
	if ui.lineStroke then
		ui.lineStroke.Transparency = 0
	end
	local size = ui.lineSize
	ui.line.TextSize = math.round(size * 1.5)
	tween(ui.line, 0.22, { TextSize = size }, Enum.EasingStyle.Back)
end

-- El brillo cruza la tarjeta de lado a lado.
local function sweep(s)
	local band = s.ui.band
	band.Offset = Vector2.new(-1, 0)
	tween(band, 0.55, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- Sacudida de la tarjeta, que se va apagando. Va por su cuenta: no corta la secuencia.
local function jolt(s, power: number, seconds: number)
	local holder = s.ui.holder
	local total = seconds * SLOW
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local left = 1 - elapsed / total
		if left <= 0 or not holder.Parent then
			connection:Disconnect()
			holder.Position = CARD_HOME
			holder.Rotation = 0
			return
		end
		holder.Position = CARD_HOME + UDim2.fromOffset(rng:NextNumber(-1, 1) * power * left, rng:NextNumber(-1, 1) * power * left)
		holder.Rotation = rng:NextNumber(-1, 1) * power * 0.22 * left
	end)
end

-- La tarjeta: entra de golpe, salta la rareza, luego el nombre y, lo último, el "1 entre N" subiendo hasta su
-- número, que se planta con una sacudida.
local function card(s, info)
	local ui = s.ui
	local roll = info.roll
	ui.line.Text = Ui.upper(Lang.t(nil, info.line))
	ui.line.TextColor3 = if info.level >= 6 then GOLD else info.bright
	showLine(s)
	-- Sube ladeada desde abajo, pasándose de tamaño, y al asentarse da un golpe de zoom y la recorre el brillo.
	ui.holder.Rotation = -9
	ui.holder.Position = CARD_HOME + UDim2.fromScale(0, 0.1)
	tween(ui.scale, 0.3, { Scale = ui.factor }, Enum.EasingStyle.Back)
	tween(ui.holder, 0.3, { Rotation = 0, Position = CARD_HOME }, Enum.EasingStyle.Back)
	wait(s, 0.2)
	s.punch = math.min(s.punch, -3)
	s.shake = math.max(s.shake, 0.12)
	tween(ui.rays, 0.3, { ImageTransparency = 0.8 })
	sweep(s)
	tween(ui.chipScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	Sfx.play("tick", 1, 1)
	wait(s, 0.2)
	tween(ui.name, 0.18, { TextTransparency = 0 })
	local nameStroke = ui.name:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Transparency = 1
		tween(nameStroke, 0.18, { Transparency = 0 })
	end
	wait(s, 0.22)
	RollCinematic.countUp(Permanent.rarity(roll.index, roll.metal, roll.size), COUNT[info.level] or 1, function(text, arrived)
		ui.odds.Text = if arrived then Permanent.describeOdds(roll.index, roll.metal, roll.size) else Lang.t(nil, "1 in {n}", { n = text })
	end, function()
		check(s)
	end)
	-- Llegó: golpe del número, rayos detrás y destello del color de la rareza.
	ui.odds.TextColor3 = if info.level >= 6 then GOLD else info.bright:Lerp(WHITE, 0.25)
	ui.oddsScale.Scale = 1.7
	tween(ui.oddsScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Los rayos de detrás dan un fogonazo: crecen de golpe y vuelven, y los de dentro se encienden.
	local size = ui.rays.Size
	ui.rays.Size = UDim2.fromOffset(size.X.Offset * 1.35, size.Y.Offset * 1.35)
	ui.rays.ImageTransparency = 0.25
	tween(ui.rays, 0.5, { ImageTransparency = 0.5, Size = size }, Enum.EasingStyle.Back)
	ui.rays2.ImageTransparency = 0.15
	tween(ui.rays2, 0.6, { ImageTransparency = 0.7 })
	sweep(s)
	jolt(s, 9, 0.4)
	cover(s, info.bright, 0.7, 1, 0.45)
	Sfx.play(if info.level >= 4 then "win" else "rare")
	s.shake = math.max(s.shake, 0.3)
	s.punch = math.min(s.punch, -6)
	s.blur.Size = 10
	tween(s.blur, 0.4, { Size = 0 })
end

-- La escena -----------------------------------------------------------------------------

local function hud(): ScreenGui?
	local gui = player:FindFirstChild("PlayerGui")
	return gui and gui:FindFirstChild("Hud") :: ScreenGui?
end

-- Esconde toda la interfaz mientras dura (pedido por el usuario, "para que sea más cinemático"): las capas de
-- PlayerGui, los carteles del mundo (los de las parcelas, los objetos, los sacos...; los que van siempre a la
-- vista se verían hasta a través del escenario) y lo de Roblox (chat, lista de jugadores). Devuelve lo escondido,
-- para volver a enseñarlo. Los números flotantes (en Terrain) no se tocan: son de un fondo común que se reutiliza.
local function hideUi(): { Instance }
	local hidden = {}
	local function hide(item: Instance)
		if (item:IsA("ScreenGui") or item:IsA("BillboardGui")) and item.Enabled and item.Name ~= "RollCinematic" then
			item.Enabled = false
			table.insert(hidden, item)
		end
	end
	local gui = player:FindFirstChild("PlayerGui")
	if gui then
		for _, item in gui:GetChildren() do
			hide(item)
		end
	end
	for _, child in workspace:GetChildren() do
		if child ~= workspace.Terrain then
			hide(child)
			for _, item in child:GetDescendants() do
				hide(item)
			end
		end
	end
	return hidden
end

local function setCore(on: boolean)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, on)
end

-- Devuelve la cámara, el Hud y Lighting, y borra el escenario. Se puede llamar varias veces.
local function release(s)
	if s.released then
		return
	end
	s.released = true
	s.loop:Disconnect()
	local camera = workspace.CurrentCamera
	camera.FieldOfView = s.saved.fov
	camera.CameraType = s.saved.type
	for _, item in s.hidden do
		if item.Parent then
			(item :: any).Enabled = true
		end
	end
	setCore(true)
	if s.haze then
		s.haze.Density = s.hazeWas
	end
	s.correction:Destroy()
	s.blur:Destroy()
	s.folder:Destroy()
end

local function newScene(info)
	local camera = workspace.CurrentCamera
	local s = {
		skipped = false,
		released = false,
		saved = { type = camera.CameraType, fov = camera.FieldOfView, cframe = camera.CFrame },
		cam = camera.CFrame,
		fov = camera.FieldOfView,
		shake = 0,
		punch = 0,
		clock = 0,
		spinning = {},
		hidden = hideUi(),
	}
	setCore(false)
	local folder = Instance.new("Folder")
	folder.Name = "RollCinematic"
	folder.Parent = workspace
	s.folder = folder
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "RollCinematic"
	correction.Parent = Lighting
	s.correction = correction
	-- Desenfoque para los golpes gordos: a 0 no se nota.
	local blur = Instance.new("BlurEffect")
	blur.Name = "RollCinematic"
	blur.Size = 0
	blur.Parent = Lighting
	s.blur = blur
	buildGui(s, info)
	camera.CameraType = Enum.CameraType.Scriptable

	-- Un solo bucle: cámara (con su temblor), arma, rayos y los rayos de la tarjeta.
	s.loop = RunService.RenderStepped:Connect(function(dt)
		s.clock += dt
		local jolt = CFrame.identity
		if s.shake > 0.01 then
			jolt = CFrame.new(rng:NextNumber(-1, 1) * s.shake, rng:NextNumber(-1, 1) * s.shake, 0)
			s.shake *= math.exp(-dt * 7 / SLOW)
		end
		camera.CFrame = s.cam * jolt
		-- `punch`: golpe de zoom que se va solo (negativo = se acerca).
		camera.FieldOfView = s.fov + s.punch
		s.punch *= math.exp(-dt * 8 / SLOW)
		if s.tick then
			s.tick(dt) -- lo que mueva la escena cada fotograma (el herrero)
		end
		if s.haze then
			s.haze.Density = 0 -- cada fotograma: el ciclo de día y el clima la van cambiando
		end
		local held = s.weapon
		if held and held.model.Parent then
			held.yaw += held.spin * dt
			held.bob += dt
			if held.scale ~= held.shown then
				held.shown = held.scale
				held.model:ScaleTo(held.fit * math.max(held.scale, 0.02))
			end
			held.model:PivotTo(CFrame.new(held.position + Vector3.new(0, math.sin(held.bob * 2.6) * 0.12 * held.spin / 2.5, 0)) * CFrame.Angles(0, held.yaw, 0) * held.tilt)
		end
		for _, ray in s.spinning do
			-- `own`: gira sobre su propio eje ya inclinado (un disco ladeado), no alrededor del de la cámara.
			local turn = CFrame.Angles(0, 0, s.clock * ray.speed)
			ray.part.CFrame = CFrame.new(ray.centre) * (if ray.own then ray.tilt * turn else turn * ray.tilt)
		end
		s.ui.rays.Rotation = s.clock * 40
		s.ui.rays2.Rotation = -s.clock * 26
	end)
	return s
end

-- Escenario cerrado y negro, lejos por encima del mapa. Devuelve su centro.
local function stage(s): Vector3
	local centre = workspace.CurrentCamera.CFrame.Position + Vector3.new(0, STAGE_UP, 0)
	local side = STAGE_HALF * 2
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		for _, sign in { -1, 1 } do
			piece(s, Enum.PartType.Block, Vector3.one * side - axis * (side - 2), CFrame.new(centre + axis * sign * STAGE_HALF), VOID, 0, Enum.Material.SmoothPlastic)
		end
	end
	s.correction.Contrast = 0.12
	s.correction.Saturation = 0.1
	s.staged = true
	-- Sin bruma: a esa distancia teñía las paredes del color del cielo (un lado naranja al atardecer).
	local haze = Lighting:FindFirstChildOfClass("Atmosphere")
	if haze then
		s.hazeWas = haze.Density
		s.haze = haze
	end
	return centre
end

-- Rayos largos que giran detrás del arma.
local function rays(s, centre: Vector3, count: number, length: number, color: Color3)
	for index = 1, count do
		local part = piece(s, Enum.PartType.Block, Vector3.new(1.3, length, 0.05), CFrame.new(centre), color, 1)
		tween(part, 0.5, { Transparency = 0.86 })
		table.insert(s.spinning, { part = part, centre = centre, speed = 0.35, tilt = CFrame.Angles(0, 0, index * math.pi / count) })
	end
end

-- Dónde poner la cámara para ver `focus` desde `eye` sin nada del mapa en medio (vallas, árboles): si algo tapa, se
-- acerca hasta delante de ello. El personaje y lo de la escena no cuentan.
local function clearView(s, focus: Vector3, eye: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { s.folder, player.Character :: Instance }
	params.RespectCanCollide = true
	local found = workspace:Raycast(focus, eye - focus, params)
	if found then
		local reach = math.max((found.Position - focus).Magnitude - 1.5, 6)
		return focus + (eye - focus).Unit * reach
	end
	return eye
end

-- Temas ---------------------------------------------------------------------------------

local THEMES = {}

-- Estrella fugaz: en el sitio de verdad. La cámara mira al cielo, la estrella cae sobre donde estaba el objeto y
-- el arma sale del cráter de luz.
function THEMES.star(s, info)
	local color, bright = info.color, info.bright
	local floor = Vector3.new(info.origin.X, info.ground + 0.2, info.origin.Z)
	local root = rootPart()
	local toward = ((if root then root.Position else s.saved.cframe.Position) - floor) * Vector3.new(1, 0, 1)
	toward = if toward.Magnitude > 0.5 then toward.Unit else Vector3.zAxis
	local side = Vector3.yAxis:Cross(toward)
	local hit = floor + Vector3.new(0, 0.8, 0)
	local sky = floor + side * 60 - toward * 35 + Vector3.new(0, 150, 0)
	-- La cámara, a un lado del jugador (no detrás de él, que lo taparía todo) y sin vallas en medio.
	local eye = clearView(s, floor + Vector3.new(0, 3, 0), floor + toward * 8 - side * 19 + Vector3.new(0, 3, 0))

	-- 1. El cielo se oscurece y la cámara baja a mirar hacia arriba.
	tween(s.correction, 0.5, { Brightness = -0.2, Contrast = 0.2, TintColor = Color3.fromRGB(175, 185, 255) })
	Sfx.play("charge", 0.8, 0.8)
	local from = s.saved.cframe
	local up = CFrame.lookAt(eye, floor:Lerp(sky, 0.7))
	animate(s, 0.55, function(t)
		s.cam = from:Lerp(up, smooth(t))
		s.fov = lerp(s.saved.fov, 64, t)
	end)

	-- 2. Se encienden estrellas en el cielo y cruzan dos fugaces pequeñas: avisan de la buena.
	local high = floor:Lerp(sky, 0.6)
	for index = 1, 10 do
		task.delay(index * 0.06 * SLOW, function()
			if not s.released then
				local spot = point(s, high + side * rng:NextNumber(-46, 46) + toward * rng:NextNumber(-12, 12) + Vector3.new(0, rng:NextNumber(-18, 24), 0))
				sprite(spot, TEX.star, WHITE:Lerp(bright, rng:NextNumber(0, 0.6)), rng:NextNumber(3, 7), 2.4, 30, 0.9)
			end
		end)
	end
	wait(s, 0.3)
	meteor(s, high + side * 44 + Vector3.new(0, 22, 0), high - side * 8 + Vector3.new(0, 2, 0), bright, 0.9, 0.3)
	wait(s, 0.28)
	meteor(s, high - side * 40 + toward * 10 + Vector3.new(0, 26, 0), high + side * 14 + Vector3.new(0, -4, 0), color, 1.1, 0.32)
	wait(s, 0.3)

	-- 3. Un destello en lo alto, y cae: cabeza de fuego y cola larga.
	local star = piece(s, Enum.PartType.Ball, Vector3.one * 3.2, CFrame.new(sky), bright, 0)
	local lamp = Instance.new("PointLight")
	lamp.Color = bright
	lamp.Brightness = 2
	lamp.Range = 30
	lamp.Parent = star
	sprite(star, TEX.star, WHITE, 26, 0.9, 25, 0.8)
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Position, b.Position = Vector3.new(0, 1.2, 0), Vector3.new(0, -1.2, 0)
	a.Parent, b.Parent = star, star
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a, b
	trail.Color = ColorSequence.new(WHITE, color)
	trail.Transparency = seq({ { 0, 0.15 }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 1 }, { 1, 0 } })
	trail.Lifetime = 0.5 * SLOW
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = star
	-- Cola larga y ancha del color de la rareza, detrás de la blanca.
	local c, d = Instance.new("Attachment"), Instance.new("Attachment")
	c.Position, d.Position = Vector3.new(0, 2.3, 0), Vector3.new(0, -2.3, 0)
	c.Parent, d.Parent = star, star
	local tail = Instance.new("Trail")
	tail.Attachment0, tail.Attachment1 = c, d
	tail.Color = ColorSequence.new(bright, color)
	-- Tenue: es una banda lisa, y más opaca se le ven los cantos.
	tail.Transparency = seq({ { 0, 0.6 }, { 1, 1 } })
	tail.WidthScale = seq({ { 0, 1 }, { 1, 0.1 } })
	tail.Lifetime = 1.3 * SLOW
	tail.LightEmission = 1
	tail.FaceCamera = true
	tail.Parent = star
	local fire = emitter(star, {
		Texture = TEX.fire,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 0.8,
		Brightness = 1.8,
		Rate = 34 / SLOW,
		Lifetime = life(0.3, 0.5),
		Speed = NumberRange.new(0, 3 / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 7 }, { 1, 2.5 } }),
		Transparency = seq({ { 0, 0.15 }, { 0.6, 0.45 }, { 1, 1 } }),
	})
	local dust = emitter(star, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 0.8,
		Rate = 70 / SLOW,
		Lifetime = NumberRange.new(0.5 * SLOW, 0.9 * SLOW),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Size = seq({ { 0, 1.6 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	})
	Sfx.play("cine_fall")
	wait(s, 0.4)
	animate(s, 0.7, function(t)
		local at = sky:Lerp(hit, t ^ 2.2)
		star.Position = at
		s.cam = CFrame.lookAt(eye, at:Lerp(hit + Vector3.new(0, 3, 0), t ^ 3))
	end)

	-- 4. Impacto. Parada de imagen: un instante con la estrella clavada y en blanco, antes de que todo salte.
	dust.Enabled = false
	fire.Enabled = false
	trail.Enabled = false
	tail.Enabled = false
	star.Color = WHITE
	star.Size = Vector3.one * 6
	s.punch = -12
	Sfx.play("cine_impact")
	wait(s, 0.05)
	-- Destello, ondas, sello y cráter de luz con grietas, trozos de suelo, anillo de polvo, columna de luz y brasas.
	star.Transparency = 1
	lamp.Range = 22
	tween(lamp, 1.2, { Brightness = 0.9 })
	cover(s, bright:Lerp(WHITE, 0.6), 0.25, 1, 0.5)
	s.shake = 1
	s.blur.Size = 14
	tween(s.blur, 0.5, { Size = 0 })
	Sfx.play("reveal_4")
	local crater = piece(s, Enum.PartType.Cylinder, Vector3.new(0.12, 8, 8), CFrame.new(floor) * FLAT, color, 0.45) -- del color a secas: aclarado, a mediodía se queda en blanco
	tween(crater, 3.4, { Transparency = 1, Size = Vector3.new(0.12, 4.5, 4.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	cracks(s, floor + Vector3.new(0, 0.04, 0), bright, 9, 10, 3.2)
	dustRing(s, floor + Vector3.new(0, 0.5, 0), Color3.fromRGB(205, 195, 185):Lerp(color, 0.25), 14, 34)
	for index = 1, 16 do
		local out = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0).LookVector
		local glowing = index % 4 == 0 -- alguno, al rojo del color de la rareza
		local chunk = piece(
			s,
			Enum.PartType.Block,
			Vector3.new(rng:NextNumber(0.5, 1.3), rng:NextNumber(0.4, 0.9), rng:NextNumber(0.5, 1.3)),
			CFrame.new(floor + out * rng:NextNumber(1, 3) + Vector3.new(0, 0.6, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			if glowing then bright else Color3.fromRGB(72, 64, 62),
			0,
			if glowing then Enum.Material.Neon else Enum.Material.Slate
		)
		Shards.launch(chunk, out * rng:NextNumber(9, 24) + Vector3.new(0, rng:NextNumber(26, 46), 0), rng:NextUnitVector() * 9, info.ground)
		task.delay(rng:NextNumber(1.6, 2.4) * SLOW, function()
			if chunk.Parent then
				tween(chunk, 0.4, { Size = Vector3.zero })
			end
		end)
	end
	pillar(s, floor, 70, 8, bright, 1.3)
	embers(point(s, floor, 6), color, 16, 3.2)
	for wave = 1, 3 do
		task.delay((wave - 1) * 0.12 * SLOW, function()
			if not s.released then
				ring(s, floor, 3, 26 + wave * 10, bright, 0.7)
			end
		end)
	end
	sealOn(s, floor, TEX.seal, color, 15, 6, 35)
	sealOn(s, floor + Vector3.new(0, 0.05, 0), TEX.seal2, bright, 11, 6, -50)
	fading(s, Enum.PartType.Ball, CFrame.new(hit), Vector3.one * 2, Vector3.one * 16, bright, 0.35, 0.45)
	local burst = point(s, hit)
	stardust(burst, color, 70, 34, 2.2)
	sparks(burst, color, 60, 30, 1.1)
	forgeSparks(burst, color, 50, 40)
	flames(burst, color, 10, 16, 6)
	sprite(burst, TEX.nova, bright, 20, 0.7, -220, 1, true)

	-- 5. El arma aparece clavada en el cráter, de punta, mientras la cámara se acerca; tiembla...
	local stuck = hit + Vector3.new(0, 1.3, 0)
	local held = weapon(s, info, stuck, DISPLAY)
	held.tilt = CFrame.Angles(0, 0, math.rad(STUCK))
	local impact = s.cam
	local close = CFrame.lookAt(clearView(s, floor + Vector3.new(0, 4.4, 0), floor + toward * 4 - side * 10 + Vector3.new(0, 4.4, 0)), floor + Vector3.new(0, 4.3, 0))
	local top = floor + Vector3.new(0, 5.4, 0)
	animate(s, 0.45, function(t)
		held.scale = outBack(math.min(t * 1.6, 1))
		s.cam = impact:Lerp(close, smooth(t))
		s.fov = lerp(64, 54, t)
	end)
	animate(s, 0.25, function(t)
		held.position = stuck + side * math.sin(t * math.pi * 6) * 0.07 * (1 - t)
	end)
	-- ...y sale de un tirón, dando la vuelta, hasta quedarse girando sobre el cráter.
	Sfx.play("equip", 0.8, 1.2)
	sparks(burst, color, 24, 18, 0.8)
	animate(s, 0.7, function(t)
		local e = outCubic(t)
		held.position = stuck:Lerp(top, e)
		held.tilt = CFrame.Angles(0, 0, math.rad(lerp(STUCK, -22, smooth(t))))
		held.spin = lerp(13, 2.5, e)
	end)
	local halo = point(s, top)
	shine(halo, bright, 11, 5)
	card(s, info)
	animate(s, 1, function(t)
		s.cam = close * CFrame.new(0, 0, -1.2 * t)
	end)
	-- 6. Vuelta a la cámara del jugador.
	tween(s.correction, 0.3, { Brightness = 0, Contrast = 0, TintColor = WHITE })
	local back = s.cam
	animate(s, 0.3, function(t)
		s.cam = back:Lerp(s.saved.cframe, smooth(t))
		s.fov = lerp(54, s.saved.fov, t)
	end)
end

-- El herrero de antes, hecho con piezas: solo sale si faltan las mallas de Blender (Shared.MapMeshesPatch).
local function smithOfParts(s, info)
	local color, bright = info.color, info.bright
	local spirit = color:Lerp(BLACK, 0.7) -- cuerpo oscuro: lo dibujan el contorno de luz y las dos luces
	cover(s, BLACK, 1, 0, 0.18)
	wait(s, 0.18)
	local centre = stage(s)
	local function at(x: number, y: number, z: number): Vector3
		return centre + Vector3.new(x, y, z)
	end
	local camWide = CFrame.lookAt(at(-6, 7, 32), at(1, 9.5, -2))
	local camNear = CFrame.lookAt(at(-2, 6, 25), at(1.2, 9, -1))
	s.cam, s.fov = camWide, 58

	-- Suelo, yunque y luz de fragua.
	piece(s, Enum.PartType.Cylinder, Vector3.new(0.6, 44, 44), CFrame.new(at(0, -0.3, 0)) * FLAT, Color3.fromRGB(20, 18, 30), 0, Enum.Material.Slate)
	sealOn(s, at(0, 0.1, 0), TEX.seal, color, 26, 14, 14)
	sealOn(s, at(0, 0.15, 0), TEX.seal2, bright, 17, 14, -22)
	local iron = Color3.fromRGB(96, 98, 116)
	piece(s, Enum.PartType.Block, Vector3.new(7, 1.2, 3.4), CFrame.new(at(1.5, 0.6, 0)), iron, 0, Enum.Material.Metal)
	piece(s, Enum.PartType.Block, Vector3.new(4.4, 1.6, 2.2), CFrame.new(at(1.5, 2, 0)), iron, 0, Enum.Material.Metal)
	local anvilTop = piece(s, Enum.PartType.Block, Vector3.new(9, 1.2, 3.2), CFrame.new(at(1.5, 3.4, 0)), iron:Lerp(WHITE, 0.08), 0, Enum.Material.Metal)
	piece(s, Enum.PartType.Block, Vector3.new(2.6, 0.8, 2), CFrame.new(at(-4, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(-8)), iron, 0, Enum.Material.Metal)
	local fire = Instance.new("PointLight")
	fire.Color = EMBER
	fire.Brightness = 3
	fire.Range = 30
	fire.Parent = point(s, at(1.5, 6, 3))
	local fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(190, 205, 255)
	fill.Brightness = 1.1
	fill.Range = 46
	fill.Parent = point(s, at(-9, 17, 8))

	-- El herrero: torso, cabeza con cuernos y ojos, hombros y dos brazos. Sale de una nube; sin piernas.
	local ghost = {}
	local figure = Instance.new("Model")
	figure.Name = "Smith"
	figure.Parent = s.folder
	local aura = Instance.new("Highlight")
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.OutlineColor = bright
	aura.FillColor = color
	aura.FillTransparency = 1
	aura.OutlineTransparency = 1
	aura.Parent = figure
	local function body(shape: Enum.PartType, size: Vector3, cframe: CFrame, tone: Color3?): Part
		local part = piece(s, shape, size, cframe, tone or spirit, 1, Enum.Material.Slate)
		part.Parent = figure
		table.insert(ghost, part)
		return part
	end
	body(Enum.PartType.Block, Vector3.new(7, 6.4, 3.6), CFrame.new(at(0, 9.6, -6.4)) * CFrame.Angles(math.rad(10), 0, 0))
	body(Enum.PartType.Block, Vector3.new(5.2, 3.4, 3), CFrame.new(at(0, 5.2, -6.9)))
	body(Enum.PartType.Ball, Vector3.one * 3.7, CFrame.new(at(0, 14.6, -5.7)))
	body(Enum.PartType.Block, Vector3.new(0.7, 2.6, 0.7), CFrame.new(at(-1.7, 16.7, -5.7)) * CFrame.Angles(0, 0, math.rad(24)))
	body(Enum.PartType.Block, Vector3.new(0.7, 2.6, 0.7), CFrame.new(at(1.7, 16.7, -5.7)) * CFrame.Angles(0, 0, math.rad(-24)))
	body(Enum.PartType.Ball, Vector3.one * 3, CFrame.new(at(-4.3, 12, -5.9)))
	body(Enum.PartType.Ball, Vector3.one * 3, CFrame.new(at(4.3, 12, -5.9)))
	-- Delantal, cinturón y hombreras, para que no sea un muñeco de cajas.
	body(Enum.PartType.Block, Vector3.new(5.6, 5.4, 0.5), CFrame.new(at(0, 7.4, -4.7)) * CFrame.Angles(math.rad(10), 0, 0), spirit:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(7.4, 1, 4), CFrame.new(at(0, 7, -6.6)), iron:Lerp(BLACK, 0.5))
	body(Enum.PartType.Block, Vector3.new(3.8, 1, 3.8), CFrame.new(at(-4.5, 13.3, -5.9)) * CFrame.Angles(0, 0, math.rad(18)), iron:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(3.8, 1, 3.8), CFrame.new(at(4.5, 13.3, -5.9)) * CFrame.Angles(0, 0, math.rad(-18)), iron:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(4.2, 1.5, 4.2), CFrame.new(at(0, 15.9, -5.7)), iron:Lerp(BLACK, 0.4))
	-- Ojos y un núcleo de luz en el pecho.
	local eyes = {
		piece(s, Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(at(-0.8, 14.7, -4)), WHITE, 1),
		piece(s, Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(at(0.8, 14.7, -4)), WHITE, 1),
		piece(s, Enum.PartType.Ball, Vector3.one * 1.5, CFrame.new(at(0, 11, -4.3)), bright, 1),
	}
	-- Brazo izquierdo: quieto, sujetando el arma por el mango.
	local grip = at(-2.4, 4.4, -0.4)
	local leftShoulder = at(-4.3, 11.6, -5.6)
	body(Enum.PartType.Block, Vector3.new(1.9, 1.9, (grip - leftShoulder).Magnitude), CFrame.lookAt(leftShoulder:Lerp(grip, 0.5), grip))
	-- Brazo derecho con el martillo: gira en el hombro. 150° = arriba y atrás; 322° = sobre el yunque.
	local shoulder = CFrame.new(at(4.3, 11.6, -5.6))
	local arm = {
		{ part = body(Enum.PartType.Block, Vector3.new(1.9, 7.4, 1.9), shoulder), offset = CFrame.new(0, -3.5, 0) },
		{ part = body(Enum.PartType.Block, Vector3.new(0.8, 3.4, 0.8), shoulder, iron:Lerp(WHITE, 0.2)), offset = CFrame.new(0, -7, 0) },
		{ part = body(Enum.PartType.Block, Vector3.new(3.2, 2.5, 2.5), shoulder, iron:Lerp(WHITE, 0.3)), offset = CFrame.new(0, -8.5, 0) },
	}
	local function swing(degrees: number)
		local turn = shoulder * CFrame.Angles(math.rad(degrees), 0, 0)
		for _, link in arm do
			link.part.CFrame = turn * link.offset
		end
	end
	swing(322)
	local mist = point(s, at(0, 2.5, -7), 9)
	emitter(mist, {
		Texture = SMOKE,
		Color = ColorSequence.new(spirit),
		LightEmission = 0.5,
		Rate = 14,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(60, 60),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-12, 12),
		Size = seq({ { 0, 4 }, { 1, 9 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.7 }, { 1, 1 } }),
	})
	for _, part in ghost do
		tween(part, 0.45, { Transparency = 0 })
	end
	tween(aura, 0.45, { OutlineTransparency = 0 })
	for _, eye in eyes do
		tween(eye, 0.45, { Transparency = 0 })
	end

	-- El arma, tumbada en el yunque y al rojo: se ve la forma, no los colores.
	local held = weapon(s, info, at(1.5, 4.25, 0), 6)
	held.tilt = CFrame.Angles(0, 0, -math.pi / 2)
	held.scale = 1
	held.outline.FillColor = EMBER
	held.outline.FillTransparency = 0
	held.outline.OutlineColor = WHITE

	cover(s, BLACK, 0, 1, 0.3)
	Sfx.play("cine_smith")
	wait(s, 0.3)

	-- 1. Tres martillazos, cada uno más fuerte; la cámara se va acercando.
	local strikePoint = at(4.3, 4.6, -0.4)
	local hits = 3
	local progress = 0
	local function push(amount: number)
		progress = math.min(progress + amount, 1)
		s.cam = camWide:Lerp(camNear, smooth(progress))
	end
	for hit = 1, hits do
		local last = hit == hits
		animate(s, if last then 0.6 else 0.4, function(t)
			swing(lerp(322, if last then 135 else 150, outCubic(t)))
			push(0.004)
		end)
		wait(s, if last then 0.22 else 0.06)
		animate(s, 0.1, function(t)
			swing(lerp(if last then 135 else 150, 322, t * t))
		end)
		local spot = point(s, strikePoint)
		s.shake = if last then 1.3 else 0.35 + hit * 0.15
		fire.Brightness = 7
		tween(fire, 0.3, { Brightness = 3 })
		if last then
			break
		end
		Sfx.play("cine_hammer", 1, 0.9 + hit * 0.1)
		sparks(spot, EMBER, 30 + hit * 20, 26, 0.9)
		ring(s, strikePoint - Vector3.new(0, 0.5, 0), 2, 12, EMBER, 0.35)
		animate(s, 0.12, function(t)
			swing(lerp(322, 304, outCubic(t)))
		end)
	end

	-- 2. El último la templa: estalla en el color de la rareza y el arma se enfría a sus colores de verdad.
	Sfx.play("cine_quench")
	Sfx.play("reveal_5")
	cover(s, bright:Lerp(WHITE, 0.5), 0.15, 1, 0.55)
	local spot = point(s, strikePoint)
	sparks(spot, color, 120, 40, 1.3)
	stardust(spot, color, 50, 26, 1.8)
	sprite(spot, TEX.nova, bright, 22, 0.7, -240, 1, true)
	for wave = 1, 3 do
		task.delay((wave - 1) * 0.12 * SLOW, function()
			if not s.released then
				ring(s, at(1.5, 0.3, 0), 4, 34 + wave * 8, bright, 0.7)
			end
		end)
	end
	emitter(point(s, at(1.5, 4.4, 0), 5), {
		Texture = SMOKE,
		Color = ColorSequence.new(WHITE),
		Lifetime = NumberRange.new(0.8 * SLOW, 1.4 * SLOW),
		Speed = NumberRange.new(4 / SLOW, 9 / SLOW),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 1.5 }, { 1, 6 } }),
		Transparency = seq({ { 0, 0.5 }, { 1, 1 } }),
	}, 16)
	tween(held.outline, 0.6, { FillTransparency = 0.88, OutlineColor = bright, FillColor = WHITE })
	tween(fire, 0.5, { Color = color, Brightness = 1.3 })
	tween(fill, 0.5, { Brightness = 1.6, Color = bright })

	-- 3. El herrero se aparta y el arma se levanta del yunque, girando.
	for _, part in ghost do
		tween(part, 0.8, { Transparency = 0.75 })
	end
	for _, eye in eyes do
		tween(eye, 0.8, { Transparency = 0.6 })
	end
	tween(aura, 0.8, { OutlineTransparency = 0.6, FillTransparency = 1 })
	local camShow = CFrame.lookAt(at(1.5, 7.8, 15), at(1.5, 6.4, 0))
	local lifted = at(1.5, 8.6, 1.5)
	local lying = held.position
	local struck = s.cam
	animate(s, 0.85, function(t)
		local e = smooth(t)
		swing(lerp(322, 230, e))
		held.position = lying:Lerp(lifted, e)
		held.tilt = CFrame.Angles(0, 0, math.rad(lerp(-90, -22, e)))
		held.spin = 2.5 * e
		s.cam = struck:Lerp(camShow, e)
		s.fov = lerp(58, 50, e)
	end)
	rays(s, lifted - Vector3.new(0, 0, 3), 5, 30, bright)
	card(s, info)
	animate(s, 1.1, function(t)
		s.cam = camShow * CFrame.new(0, 0, -1.2 * t)
	end)
end

-- Herrero celestial: un gigante espectral saca la hoja al rojo de la fragua, la forja a martillazos en el yunque y,
-- con el último, le cae un rayo, se templa y se ve cuál es. Hasta entonces todo va en naranja de fragua: el color
-- de la rareza no se ve hasta el temple. El herrero es un modelo de Blender en piezas (smith() de
-- tools/blender/crear_mapa_japones.py) que se mueve por articulaciones: el cuerpo se dobla por la cintura, la
-- cabeza por el cuello y cada brazo se resuelve desde el hombro hasta donde tiene que estar el puño.
-- Medidas del modelo, en studs desde el centro del escenario: las mismas que en el script de Blender.
local SMITH = {
	waist = Vector3.new(0, 5, -7),
	neck = Vector3.new(0, 15.6, -6.6),
	shoulder = Vector3.new(6.5, 14, -6.5), -- el del martillo; el otro, con la X cambiada de signo
	upper = 6.5, -- del hombro al codo
	fore = 6.9, -- del codo al centro del puño
	grip = Vector3.new(16, 4, 0), -- por dónde se coge el martillo en el modelo
}
local SMITH_BODY = { "SmithTorso", "SmithHead", "SmithArmA", "SmithForeA", "SmithArmB", "SmithForeB", "SmithHammer" }

-- Dónde queda el codo (y el puño, si no llega) de un brazo que va de `shoulder` a `target`, doblado hacia `pole`.
local function reach(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3)
	local toward = target - shoulder
	local far = math.clamp(toward.Magnitude, 1, SMITH.upper + SMITH.fore - 0.05)
	local dir = toward.Unit
	local along = (SMITH.upper ^ 2 - SMITH.fore ^ 2 + far ^ 2) / (2 * far)
	local out = math.sqrt(math.max(SMITH.upper ^ 2 - along ^ 2, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 0.01 then bend.Unit else Vector3.xAxis
	return shoulder + dir * along + bend * out, shoulder + dir * far
end

-- Marco de un hueso modelado colgando hacia abajo: va de `from` a `to` con su cara de delante mirando a `front`.
local function bone(from: Vector3, to: Vector3, front: Vector3): CFrame
	local up = (from - to).Unit
	local right = up:Cross(front)
	right = if right.Magnitude > 0.01 then right.Unit else up:Cross(Vector3.xAxis).Unit
	return CFrame.fromMatrix(from, right, up)
end

function THEMES.smith(s, info)
	if not PropModel.has("SmithTorso") then
		return smithOfParts(s, info)
	end
	local color, bright = info.color, info.bright
	cover(s, BLACK, 1, 0, 0.18)
	wait(s, 0.18)
	local centre = stage(s)
	local origin = CFrame.new(centre)
	local function at(x: number, y: number, z: number): Vector3
		return centre + Vector3.new(x, y, z)
	end
	local function look(from: Vector3, to: Vector3): CFrame
		return CFrame.lookAt(centre + from, centre + to)
	end

	-- Decorado: suelo, sellos, fragua con monolitos y yunque.
	piece(s, Enum.PartType.Cylinder, Vector3.new(0.6, 76, 76), CFrame.new(at(0, -0.3, 0)) * FLAT, Color3.fromRGB(22, 20, 32), 0, Enum.Material.Slate)
	sealOn(s, at(0, 0.1, 0), TEX.seal, EMBER, 30, 20, 14)
	sealOn(s, at(0, 0.15, 0), TEX.seal2, EMBER:Lerp(WHITE, 0.3), 19, 20, -22)
	local iron = Color3.fromRGB(104, 106, 126)
	local gold = Color3.fromRGB(222, 168, 74)
	local glow = {} -- lo que brilla (ojos, runas, brasas): naranja hasta el temple
	local dim = {} -- lo demás del herrero: al final se queda en silueta oscura
	local hot = Color3.fromRGB(255, 132, 44) -- naranja hondo: más claro, el resplandor se come la cara
	local function dress(model: Model?, looks: { [string]: { any } }, list: { BasePart }?)
		if not model then
			return
		end
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				local found = looks[part.Name]
				if found then
					part.Color = found[1]
					part.Material = found[2]
				end
				part.CastShadow = false
				if part.Name == "Paper" then
					part.Transparency = 0
					table.insert(glow, part)
				end
				if list then
					table.insert(list, part)
				end
			end
		end
	end
	local set = {
		StoneDark = { Color3.fromRGB(50, 48, 64), Enum.Material.Slate },
		Stone = { iron, Enum.Material.Metal },
		Black = { Color3.fromRGB(20, 16, 22), Enum.Material.SmoothPlastic },
		Gold = { gold, Enum.Material.Metal },
		Paper = { hot, Enum.Material.Neon },
		Wood = { Color3.fromRGB(58, 40, 32), Enum.Material.Wood },
		Water = { Color3.fromRGB(90, 170, 220), Enum.Material.Glass },
	}
	dress(PropModel.place(s.folder, "SmithForge", origin), set)
	dress(PropModel.place(s.folder, "SmithAnvil", origin), set)

	-- El herrero: piel de sombra, hierro, oro y cuero, con el contorno de luz.
	local figure = Instance.new("Model")
	figure.Name = "Smith"
	figure.Parent = s.folder
	local aura = Instance.new("Highlight")
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.OutlineColor = EMBER
	aura.FillColor = EMBER
	aura.FillTransparency = 1
	aura.OutlineTransparency = 1
	aura.Parent = figure
	local skin = {
		StoneDark = { Color3.fromRGB(44, 46, 70), Enum.Material.SmoothPlastic },
		Stone = { iron, Enum.Material.Metal },
		Black = { Color3.fromRGB(34, 24, 26), Enum.Material.SmoothPlastic },
		Gold = { gold, Enum.Material.Metal },
		Paper = { hot, Enum.Material.Neon },
		White = { Color3.fromRGB(128, 124, 144), Enum.Material.SmoothPlastic },
		Wood = { Color3.fromRGB(58, 40, 32), Enum.Material.Wood },
	}
	local ghost = {}
	local body = {}
	for _, name in SMITH_BODY do
		local model = PropModel.place(figure, name, origin)
		dress(model, skin, ghost)
		body[name] = model
	end
	for _, part in ghost do
		part.Transparency = 1
		if part.Name ~= "Paper" then
			table.insert(dim, part)
		end
	end

	-- Luces: la fragua, el yunque, un relleno frío y una de contra detrás del gigante.
	local function lamp(position: Vector3, tone: Color3, brightness: number, range: number): (PointLight, Part)
		local holder = point(s, position)
		local light = Instance.new("PointLight")
		light.Color = tone
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = holder
		return light, holder
	end
	local furnace = lamp(at(-11.5, 5, -3.5), EMBER, 2.4, 30)
	local fire = lamp(at(2, 7, 4), EMBER, 1, 30)
	local fill = lamp(at(-10, 20, 16), Color3.fromRGB(170, 190, 255), 0.8, 60)
	local rim = lamp(at(0, 17, -17), EMBER, 1.6, 40)

	-- Brasas y humo: la boca de la fragua, su chimenea y la niebla de la que sale el gigante.
	emitter(point(s, at(-12.9, 3, -5.2), 3), {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, EMBER),
		LightEmission = 1,
		Rate = 26 / SLOW,
		Lifetime = NumberRange.new(1.2 * SLOW, 2.4 * SLOW),
		Speed = NumberRange.new(2 / SLOW, 6 / SLOW),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 4 / (SLOW * SLOW), 0),
		Size = seq({ { 0, 0.5 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
	})
	emitter(point(s, at(-14.4, 22, -9.5), 2), {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(70, 62, 70)),
		Rate = 5 / SLOW,
		Lifetime = NumberRange.new(2.5 * SLOW, 3.5 * SLOW),
		Speed = NumberRange.new(3 / SLOW, 5 / SLOW),
		SpreadAngle = Vector2.new(12, 12),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-10 / SLOW, 10 / SLOW),
		Size = seq({ { 0, 2 }, { 1, 8 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.6 }, { 1, 1 } }),
	})
	local mist = emitter(point(s, at(0, 2, -7), 10), {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(60, 62, 96)),
		LightEmission = 0.4,
		Rate = 16 / SLOW,
		Lifetime = NumberRange.new(2 * SLOW, 3 * SLOW),
		Speed = NumberRange.new(0.6 / SLOW, 1.6 / SLOW),
		SpreadAngle = Vector2.new(70, 70),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-12 / SLOW, 12 / SLOW),
		Size = seq({ { 0, 5 }, { 1, 11 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
	}, 12)
	-- Motas de ceniza que flotan por todo el escenario: dan fondo a los planos.
	emitter(point(s, at(0, 12, 4), 50), {
		Texture = SPARKLE,
		Color = ColorSequence.new(EMBER),
		LightEmission = 1,
		Rate = 22 / SLOW,
		Lifetime = NumberRange.new(2 * SLOW, 3.5 * SLOW),
		Speed = NumberRange.new(0.4 / SLOW, 1.4 / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 1.2 / (SLOW * SLOW), 0),
		Size = seq({ { 0, 0 }, { 0.3, 0.28 }, { 1, 0 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.2 }, { 1, 1 } }),
	}, 30)

	-- El arma, al rojo: se ve la forma, no los colores. Empieza con la hoja metida en la fragua.
	local lying = at(1.5, 4.5, 0)
	local held = weapon(s, info, at(-12.4, 3.7, -4.6), 7)
	held.tilt = CFrame.Angles(0, 0, -math.pi / 2)
	held.scale = 1
	held.yaw = math.pi
	held.outline.FillColor = EMBER
	held.outline.FillTransparency = 0
	held.outline.OutlineColor = WHITE
	local heat, heatAt = lamp(held.position, EMBER, 1.2, 12)
	local trail = emitter(heatAt, {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, EMBER),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.4 * SLOW, 0.8 * SLOW),
		Speed = NumberRange.new(1 / SLOW, 4 / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -14 / (SLOW * SLOW), 0),
		Size = seq({ { 0, 0.55 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 1, 1 } }),
	})

	-- La postura: adónde va cada puño, cómo va el martillo y cuánto se dobla el cuerpo. La escena solo cambia esta
	-- tabla; el bucle de la escena coloca las piezas cada fotograma (y lo hace respirar).
	local READY = { fist = Vector3.new(8, 11, -2.5), handle = Vector3.new(-0.4, 0.75, 0.5), face = Vector3.new(0, -0.3, 1), lean = 4, twist = 0, nod = 14, turn = -6 }
	local RAISED = { fist = Vector3.new(8.5, 21, -9), handle = Vector3.new(0.1, 0.8, -0.6), face = Vector3.new(0, 0.6, 0.8), lean = -8, twist = 12, nod = -6, turn = 6 }
	local BIG = { fist = Vector3.new(7.5, 23, -10.5), handle = Vector3.new(0, 0.55, -0.85), face = Vector3.new(0, 0.85, 0.55), lean = -12, twist = 16, nod = -14, turn = 8 }
	local IMPACT = { fist = Vector3.new(7, 7.8, -5), handle = Vector3.new(-3.5, -0.4, 5), face = Vector3.new(0, -1, 0), lean = 13, twist = -8, nod = 24, turn = -6 }
	local REST = { fist = Vector3.new(11, 7.4, -6.5), handle = Vector3.new(0.3, -1, -0.1), face = Vector3.new(0, 0.1, 1), lean = 5, twist = -4, nod = 18, turn = -6 }
	local pose = table.clone(READY)
	pose.rise = -3
	pose.hold = Vector3.zero -- el puño que sujeta, relativo al escenario (lo pone `carry`)
	local function carry()
		-- El puño que sujeta va en el mango: el arma tumbada, con la punta hacia donde diga su giro.
		pose.hold = (held.position - centre) + CFrame.Angles(0, held.yaw, 0):VectorToWorldSpace(Vector3.new(-3.7, 0.2, 0))
	end
	carry()
	local strikeAt = at(3.5, 4.6, 0)
	s.tick = function()
		local breath = math.sin(s.clock * 1.7) * 0.14
		local torso = CFrame.new(centre + Vector3.new(0, pose.rise + breath, 0))
			* CFrame.new(SMITH.waist)
			* CFrame.Angles(math.rad(pose.lean), math.rad(pose.twist), 0)
			* CFrame.new(-SMITH.waist)
		body.SmithTorso:PivotTo(torso)
		body.SmithHead:PivotTo(torso * CFrame.new(SMITH.neck) * CFrame.Angles(math.rad(pose.nod), math.rad(pose.turn), 0) * CFrame.new(-SMITH.neck))
		local front = -torso.LookVector
		local grip = centre + pose.fist
		for _, arm in { { 1, "A", grip }, { -1, "B", centre + pose.hold } } do
			local rest = SMITH.shoulder * Vector3.new(arm[1], 1, 1)
			local shoulder = torso * rest
			local elbow, fist = reach(shoulder, arm[3], torso:VectorToWorldSpace(Vector3.new(arm[1], 0.15, -0.7)))
			body["SmithArm" .. arm[2]]:PivotTo(bone(shoulder, elbow, front) * CFrame.new(-rest))
			body["SmithFore" .. arm[2]]:PivotTo(bone(elbow, fist, front) * CFrame.new(-(rest - Vector3.new(0, SMITH.upper, 0))))
			if arm[1] == 1 then
				grip = fist
			end
		end
		local handle = pose.handle.Unit
		local face = pose.face - handle * pose.face:Dot(handle)
		face = if face.Magnitude > 0.01 then face.Unit else Vector3.zAxis
		body.SmithHammer:PivotTo(CFrame.fromMatrix(grip, handle:Cross(face), handle) * CFrame.new(-SMITH.grip))
		heatAt.Position = held.position
		-- La fragua parpadea.
		furnace.Brightness = 2.2 + math.noise(s.clock * 3.1, 0.5) * 0.9
	end
	-- Lleva la postura hasta `target` en `seconds`; `arc` saca el puño hacia delante a mitad de camino (el martillo
	-- baja por delante, no a través del hombro) y `extra(avance)` va con cada fotograma.
	local function move(target, seconds: number, ease: (number) -> number, arc: number?, extra: ((number) -> ())?)
		local from = table.clone(pose)
		animate(s, seconds, function(t)
			local e = ease(t)
			pose.fist = from.fist:Lerp(target.fist, e) + Vector3.new(0, 0, (arc or 0) * math.sin(math.clamp(e, 0, 1) * math.pi))
			pose.handle = from.handle.Unit:Lerp(target.handle.Unit, e)
			pose.face = from.face:Lerp(target.face, e)
			for _, key in { "lean", "twist", "nod", "turn" } do
				pose[key] = lerp(from[key], target[key], e)
			end
			if extra then
				extra(t)
			end
		end)
	end
	local function accelerate(t: number): number
		return t * t * t
	end

	-- Planos de cámara.
	local camRise = look(Vector3.new(5, 2.4, 24), Vector3.new(-1, 12.5, -6))
	local camWide = look(Vector3.new(-7, 7.5, 35), Vector3.new(0.5, 10.5, -3))
	local camAnvil = look(Vector3.new(-6.5, 5.6, 12), Vector3.new(3.2, 5.2, 0))
	local camLow = look(Vector3.new(0, 5.4, 16), Vector3.new(2.5, 13.5, -6))
	local camFinal = look(Vector3.new(-4.5, 8, 27), Vector3.new(1.5, 8.5, -2))
	local camShow = look(Vector3.new(1.5, 12.2, 24), Vector3.new(1.5, 11.6, 4))
	s.cam, s.fov = camRise, 64

	-- 1. Sale de la niebla: aparece el cuerpo, se le encienden los ojos y las runas, y la cámara sube por él.
	cover(s, BLACK, 0, 1, 0.45)
	Sfx.play("cine_smith")
	for _, part in ghost do
		tween(part, 0.6, { Transparency = if part.Name == "Water" then 0.2 else 0 })
	end
	tween(aura, 0.6, { OutlineTransparency = 0.45 })
	mist:Emit(20)
	animate(s, 1, function(t)
		pose.rise = lerp(-3, 0, outCubic(t))
		s.cam = camRise * CFrame.new(0, 1.6 * smooth(t), -2.5 * t)
	end)

	-- 2. Saca la hoja de la fragua y la deja en el yunque, soltando brasas.
	s.cam, s.fov = camWide, 60
	trail.Rate = 60 / SLOW
	local start = held.position
	animate(s, 0.8, function(t)
		local e = smooth(t)
		held.position = start:Lerp(lying, e) + Vector3.new(0, math.sin(e * math.pi) * 5, math.sin(e * math.pi) * 3)
		held.yaw = math.pi * (1 - e)
		carry()
		pose.nod = lerp(14, 22, e)
		pose.turn = lerp(-22, -4, e)
		s.cam = camWide * CFrame.new(0, 0, -3 * e)
	end)
	trail.Rate = 0
	Sfx.play("forge_hit", 0.5, 0.8)
	sparks(point(s, lying), EMBER, 14, 14, 0.7)

	-- 3. Tres martillazos, cada uno más fuerte y desde un plano distinto. Con cada uno la hoja se pone más blanca.
	local function strike(hit: number, last: boolean)
		local from, to
		if hit == 1 then
			from, to = camWide * CFrame.new(0, 0, -3), camWide * CFrame.new(0, 0, -6)
		elseif hit == 2 then
			from, to = camAnvil, camAnvil * CFrame.new(0, 0.4, -1.5)
		else
			from, to = camLow, camLow * CFrame.new(0, 0.6, -2)
		end
		s.cam, s.fov = from, if hit == 3 then 70 elseif hit == 2 then 52 else 60
		if last then
			-- El último se carga: las runas del martillo se van poniendo blancas y todo tiembla un poco.
			Sfx.play("charge", 0.9, 0.7)
			for _, part in body.SmithHammer:GetChildren() do
				if part.Name == "Paper" then
					tween(part, 0.8, { Color = WHITE })
				end
			end
			tween(aura, 0.8, { OutlineColor = WHITE })
		end
		move(if last then BIG else RAISED, if last then 0.85 else 0.46, outCubic, 0, function(t)
			s.cam = from:Lerp(to, smooth(t))
			if last then
				s.shake = math.max(s.shake, 0.08 * t)
			end
		end)
		wait(s, if last then 0.24 else 0.07)
		if last then
			s.cam, s.fov = camFinal, 58
		end
		move(IMPACT, if last then 0.12 else 0.1, accelerate, 6)
	end
	local function clang(hit: number)
		local spot = point(s, strikeAt)
		s.shake = 0.4 + hit * 0.2
		s.punch = -5 - hit * 2
		fire.Brightness = 8
		tween(fire, 0.4, { Brightness = 1 })
		Sfx.play("cine_hammer", 1, 0.85 + hit * 0.1)
		forgeSparks(spot, EMBER, 40 + hit * 30, 34 + hit * 6)
		sparks(spot, EMBER, 16 + hit * 10, 22, 0.9)
		sprite(spot, TEX.nova, EMBER:Lerp(WHITE, 0.4), 7 + hit * 2, 0.35, 200, 1, true)
		ring(s, strikeAt - Vector3.new(0, 0.5, 0), 2, 13 + hit * 4, EMBER, 0.4)
		ring(s, at(1.5, 0.3, 0), 6, 22 + hit * 6, EMBER, 0.6)
		held.outline.FillColor = EMBER:Lerp(WHITE, hit * 0.3)
		for _, part in glow do
			part.Color = hot:Lerp(WHITE, 0.6)
			tween(part, 0.5, { Color = hot })
		end
		-- Parada de imagen: el golpe se queda clavado un instante antes de rebotar.
		wait(s, 0.05)
		move(READY, 0.2, outBack)
	end
	for hit = 1, 2 do
		strike(hit, false)
		clang(hit)
		wait(s, 0.05)
	end
	strike(3, true)

	-- 4. El último: cae un rayo del color de la rareza, la hoja se templa y todo lo que brillaba cambia a ese color.
	Sfx.play("cine_quench")
	Sfx.play("reveal_5")
	cover(s, bright:Lerp(WHITE, 0.6), 0.05, 1, 0.7)
	s.shake = 1.5
	s.punch = -14
	s.blur.Size = 22
	tween(s.blur, 0.6, { Size = 0 })
	bolt(s, at(1.5, 80, -4), strikeAt, bright, 1.6, 0.5)
	bolt(s, at(-9, 80, 3), strikeAt, bright, 0.8, 0.4)
	bolt(s, at(12, 80, 2), strikeAt, bright, 0.8, 0.45)
	pillar(s, at(3.5, 4, 0), 80, 9, bright, 1.1)
	local spot = point(s, strikeAt)
	forgeSparks(spot, color, 160, 48)
	sparks(spot, color, 90, 40, 1.3)
	stardust(spot, color, 60, 28, 1.9)
	sprite(spot, TEX.nova, bright, 26, 0.7, -240, 1, true)
	for wave = 1, 3 do
		task.delay((wave - 1) * 0.12 * SLOW, function()
			if not s.released then
				ring(s, at(1.5, 0.3, 0), 4, 40 + wave * 10, bright, 0.7)
			end
		end)
	end
	sealOn(s, at(0, 0.2, 0), TEX.seal, color, 32, 10, 30)
	sealOn(s, at(0, 0.25, 0), TEX.seal2, bright, 20, 10, -44)
	emitter(point(s, at(1.5, 4.4, 0), 6), {
		Texture = SMOKE,
		Color = ColorSequence.new(WHITE),
		Rate = 14 / SLOW,
		Lifetime = NumberRange.new(1 * SLOW, 1.8 * SLOW),
		Speed = NumberRange.new(5 / SLOW, 11 / SLOW),
		SpreadAngle = Vector2.new(22, 22),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20 / SLOW, 20 / SLOW),
		Size = seq({ { 0, 1.5 }, { 1, 7 } }),
		Transparency = seq({ { 0, 0.45 }, { 1, 1 } }),
	}, 20)
	for _, part in glow do
		part.Color = WHITE
		tween(part, 0.7, { Color = bright })
	end
	tween(held.outline, 0.7, { FillTransparency = 0.88, OutlineColor = bright, FillColor = WHITE })
	tween(aura, 0.7, { OutlineColor = bright })
	tween(fire, 0.6, { Color = color, Brightness = 1 })
	tween(rim, 0.6, { Color = color, Brightness = 1.3 })
	tween(furnace, 0.6, { Color = color })
	tween(heat, 0.6, { Color = bright })
	tween(fill, 0.6, { Brightness = 1.1, Color = bright:Lerp(WHITE, 0.4) })
	wait(s, 0.07)
	move(READY, 0.3, outBack)
	wait(s, 0.25)

	-- 5. Baja el martillo, levanta el arma hacia la cámara y la suelta: se queda flotando y girando.
	local lifted = at(1.5, 11, 5)
	local struck = s.cam
	local released = Vector3.new(-4.5, 8.5, -1)
	move(REST, 1, smooth, 0, function(t)
		local e = smooth(t)
		held.position = lying:Lerp(lifted, e)
		held.tilt = CFrame.Angles(0, 0, math.rad(lerp(-90, -22, e)))
		held.spin = 2.5 * e
		if t < 0.55 then
			carry()
		else
			pose.hold = pose.hold:Lerp(released, 0.08)
		end
		s.cam = struck:Lerp(camShow, e)
		s.fov = lerp(58, 50, e)
	end)
	shine(point(s, lifted), bright, 13, 6)
	-- El gigante se queda detrás en silueta oscura, con sus runas encendidas, para que mande el arma.
	local shadow = color:Lerp(BLACK, 0.88)
	for _, part in dim do
		tween(part, 0.9, { Color = shadow })
	end
	tween(fill, 0.9, { Brightness = 0.3 })
	tween(fire, 0.9, { Brightness = 0.5 })
	card(s, info)
	animate(s, 1.1, function(t)
		s.cam = camShow * CFrame.new(0, 0, -1.4 * t)
	end)
end

-- Supernova: lo más raro del juego, así que va despacio y sube por pasos (pedido por el usuario: la primera versión
-- le pareció muy rápida). La estrella late y va subiendo de rareza, un color detrás de otro y cada vez más deprisa,
-- hasta la del arma; se encoge tragando luz, calla un instante y estalla. El arma sale como una silueta blanca,
-- revienta en sus colores y el "1 entre N" sube contando; al llegar, otra explosión (dos y lluvia de estrellas en
-- la absoluta).
function THEMES.nova(s, info)
	local color, bright = info.color, info.bright
	local jackpot = info.level >= 6
	cover(s, BLACK, 1, 0, 0.18)
	wait(s, 0.18)
	local centre = stage(s)
	local function camAt(distance: number, height: number): CFrame
		return CFrame.lookAt(centre + Vector3.new(distance * 0.18, height, distance), centre)
	end
	s.cam, s.fov = camAt(52, 3), 70

	-- Campo de estrellas y la estrella.
	local field = point(s, centre, 110)
	emitter(field, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, bright),
		LightEmission = 0.8,
		Rate = 60,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(0, 0.5),
		Size = seq({ { 0, 0 }, { 0.5, 1.3 }, { 1, 0 } }),
		Transparency = seq({ { 0, 1 }, { 0.5, 0.2 }, { 1, 1 } }),
	}, 60)
	-- Escalera de rarezas: de unas cuantas por debajo hasta la del arma.
	local last = 1
	for index, tier in Config.RarityTiers do
		if tier.name == info.tier.name then
			last = index
		end
	end
	local steps = {}
	for index = math.max(1, last - (if jackpot then 7 else 5)), last do
		table.insert(steps, Config.RarityTiers[index])
	end
	local tone = steps[1].color
	local star = piece(s, Enum.PartType.Ball, Vector3.one * 7, CFrame.new(centre), tone:Lerp(WHITE, 0.3), 0)
	local lamp = Instance.new("PointLight")
	lamp.Color = tone
	lamp.Brightness = 3
	lamp.Range = 60
	lamp.Parent = star
	local core = point(s, centre)
	local corona = emitter(core, {
		Texture = TEX.shine,
		Color = ColorSequence.new(tone),
		LightEmission = 1,
		Rate = 12,
		Lifetime = NumberRange.new(0.9, 1.2),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(20),
		LockedToPart = true,
		Size = seq({ { 0, 16 }, { 0.5, 26 }, { 1, 16 } }),
		Transparency = seq({ { 0, 1 }, { 0.5, 0.35 }, { 1, 1 } }),
	})
	-- Disco de acreción, tumbado y algo inclinado hacia la cámara, y dos aros que dan vueltas a su alrededor.
	local plane = CFrame.Angles(math.rad(18), 0, math.rad(8))
	local function flat(texture: string, size: number, turn: number, tilt: CFrame, faint: number)
		local base = point(s, centre)
		base.CFrame = CFrame.new(centre) * tilt
		local created = emitter(base, {
			Texture = texture,
			Color = ColorSequence.new(tone),
			LightEmission = 1,
			Rate = 2 / SLOW,
			Lifetime = life(1.2),
			Speed = NumberRange.new(0.01),
			SpreadAngle = Vector2.zero,
			EmissionDirection = Enum.NormalId.Top,
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(turn / SLOW),
			LockedToPart = true,
			Size = NumberSequence.new(size),
			Transparency = seq({ { 0, 1 }, { 0.5, faint }, { 1, 1 } }),
		}, 1)
		return { emitter = created, part = base, size = size }
	end
	local disc = flat(TEX.disc, 46, 70, plane, 0.45)
	local hoops = {
		flat(TEX.portal, 24, 40, CFrame.identity, 0.55),
		flat(TEX.portal, 32, -30, CFrame.identity, 0.66),
	}
	hoops[1].tilt, hoops[1].speed = CFrame.Angles(math.rad(64), 0, 0), 0.5
	hoops[2].tilt, hoops[2].speed = CFrame.Angles(math.rad(-50), 0, math.rad(20)), -0.35
	local swirl = { disc, hoops[1], hoops[2] }
	-- Planetas en órbita: la estrella se los traga al encogerse (`pull` = cuánto queda de su órbita).
	local planets = {}
	for index, spec in { { 15, 1.7, Color3.fromRGB(110, 170, 255) }, { 21, 2.6, Color3.fromRGB(255, 150, 90) }, { 27, 1.4, Color3.fromRGB(150, 255, 190) }, { 33, 2.1, Color3.fromRGB(225, 140, 255) } } do
		planets[index] = {
			part = piece(s, Enum.PartType.Ball, Vector3.one * spec[2], CFrame.new(centre), spec[3], 0, Enum.Material.SmoothPlastic),
			radius = spec[1],
			size = spec[2],
			color = spec[3],
			angle = index * 1.9,
			pull = 1,
		}
	end
	-- Destello de lente: una línea de luz que cruza la estrella y late con ella.
	local lens = streak(s, centre, Vector3.xAxis, 96, 1.3, tone)
	s.tick = function(dt)
		local step = dt / SLOW
		for _, hoop in hoops do
			hoop.part.CFrame = CFrame.new(centre) * CFrame.Angles(0, s.clock * hoop.speed / SLOW, 0) * hoop.tilt
		end
		for _, planet in planets do
			if planet.part.Parent then
				local radius = planet.radius * planet.pull
				planet.angle += step * 14 / math.max(radius, 3) -- más deprisa cuanto más cerca
				planet.part.CFrame = CFrame.new(centre) * plane * CFrame.new(math.cos(planet.angle) * radius, 0, math.sin(planet.angle) * radius)
			end
		end
	end
	cover(s, BLACK, 0, 1, 0.4)
	Sfx.play("cine_star")

	-- 1. Late y sube de rareza, cada paso más deprisa, más grande y más agudo; la cámara se va acercando.
	local distance = 52
	local size = 7
	local function beat(seconds: number, grow: number)
		local from, to = size, size + grow
		local near = distance - 1.4
		local far = distance
		animate(s, seconds, function(t)
			-- Salta de tamaño y se asienta.
			star.Size = Vector3.one * (lerp(from, to, outCubic(t)) + math.sin(t * math.pi) * 1.6)
			distance = lerp(far, near, t)
			s.cam = camAt(distance, 3)
		end)
		size = to
	end
	setLine(s, Lang.t(nil, steps[1].name), steps[1].color:Lerp(WHITE, 0.3))
	beat(0.9, 0)
	for index = 2, #steps do
		local tier = steps[index]
		local final = index == #steps
		tone = tier.color
		local light = tone:Lerp(WHITE, 0.3)
		star.Color = light
		lamp.Color = tone
		corona.Color = ColorSequence.new(tone)
		for _, item in swirl do
			item.emitter.Color = ColorSequence.new(tone)
		end
		lens.Color = ColorSequence.new(light)
		lens.Width0, lens.Width1 = 5 + index, 5 + index
		tween(lens, 0.4, { Width0 = 1.3, Width1 = 1.3 })
		flames(core, tone, 4 + index, 22, 6 + index * 0.5)
		setLine(s, Lang.t(nil, tier.name), light)
		cover(s, light, 0.72, 1, 0.3)
		s.shake = 0.25 + index * 0.1
		ring(s, centre, 6, 60 + index * 8, light, 0.6, CFrame.Angles(math.rad(14), 0, math.rad(index * 23 - 60)))
		sparks(core, tone, 20 + index * 8, 40, 1.4)
		Sfx.play("charge", 1, 2 ^ ((index - 1) * 2 / 12))
		if final then
			-- Es esta: se queda, con su estallido.
			Sfx.play("rare")
			sprite(core, TEX.nova, light, 40, 0.8, -200, 1, true)
			stardust(core, tone, 60, 50, 2.6)
			beat(1.1, 2.5)
		else
			beat(lerp(0.62, 0.3, (index - 2) / math.max(#steps - 2, 1)), 0.7)
		end
	end
	local hot = bright:Lerp(WHITE, 0.3)

	-- 2. Se encoge: traga luz de alrededor, cada vez más deprisa, y todo se oscurece.
	local whirl = emitter(core, {
		Texture = TEX.vortex,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 3 / SLOW,
		Lifetime = NumberRange.new(1 * SLOW),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(260 / SLOW),
		LockedToPart = true,
		Size = seq({ { 0, 30 }, { 1, 2 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }),
	})
	local collapse = if jackpot then 3 else 2.4
	tween(s.correction, collapse, { Brightness = -0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(s.ui.line, collapse * 0.6, { TextTransparency = 1 })
	if s.ui.lineStroke then
		tween(s.ui.lineStroke, collapse * 0.6, { Transparency = 1 })
	end
	local note = -1
	local full, wide = size, distance
	Sfx.play("cine_collapse")
	tween(lens, collapse, { Width0 = 0.3, Width1 = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	animate(s, collapse, function(t)
		local e = t * t
		-- El disco y los aros se cierran, y los planetas caen en espiral, de dentro afuera, uno detrás de otro.
		for _, item in swirl do
			item.emitter.Size = NumberSequence.new(lerp(item.size, 3, e))
		end
		for index, planet in planets do
			local fall = math.clamp(e * 1.25 - (index - 1) * 0.08, 0, 1)
			planet.pull = 1 - fall
			if planet.part.Parent then
				if fall >= 1 then
					planet.part:Destroy()
					sparks(core, planet.color, 16, 30, 1.3)
					Sfx.play("tick", 0.8, 0.6 + index * 0.15)
					s.shake = math.max(s.shake, 0.3)
				else
					planet.part.Size = Vector3.one * planet.size * math.min(1, planet.pull * 4 + 0.15)
				end
			end
		end
		star.Size = Vector3.one * lerp(full, 0.6, e)
		star.Color = hot
		lamp.Range = lerp(60, 14, e)
		s.cam = camAt(lerp(wide, 28, e), 3 - 2 * e)
		s.fov = lerp(70, 42, e)
		s.shake = math.max(s.shake, 0.22 * e)
		for _ = 1, 2 do
			if rng:NextNumber() < 0.2 + 0.7 * t then
				local streak = piece(s, Enum.PartType.Ball, Vector3.one * 0.45, CFrame.new(centre + rng:NextUnitVector() * rng:NextNumber(22, 40)), bright, 0.2)
				tween(streak, 0.32, { Position = centre, Size = Vector3.one * 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(streak, 0.32 * SLOW + 0.05)
			end
		end
		-- Latidos que se van juntando.
		local now = math.floor(e * 16)
		if now ~= note then
			note = now
			Sfx.play("charge", 0.5, 2 ^ (now / 12))
			ring(s, centre, 44 - now * 2, 2, bright, 0.3, CFrame.Angles(math.rad(14), 0, math.rad(now * 31)))
		end
	end)

	-- 3. Silencio: un punto en la oscuridad.
	whirl.Enabled = false
	corona.Enabled = false
	for _, item in swirl do
		item.emitter.Enabled = false
		item.emitter:Clear()
	end
	star.Size = Vector3.one * 0.3
	lamp.Brightness = 0.4
	wait(s, 0.8)

	-- 4. Estalla: onda que desenfoca la pantalla, destellos de lente en cruz y llamaradas.
	local function explode(shade: Color3, power: number, sound: string?)
		cover(s, shade:Lerp(WHITE, 0.75), 0, 1, 0.6)
		s.shake = 1.6 * power
		s.punch = -16 * power
		s.blur.Size = 30 * power
		tween(s.blur, 0.8, { Size = 0 })
		for _, axis in { Vector3.xAxis, Vector3.yAxis } do
			local line = streak(s, centre, axis, 170 * power, (if axis == Vector3.xAxis then 10 else 5) * power, shade)
			tween(line, 1, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(line.Parent, 1 * SLOW + 0.1)
		end
		Sfx.play(sound or "cine_boom", math.min(power, 1))
		fading(s, Enum.PartType.Ball, CFrame.new(centre), Vector3.one, Vector3.one * 90 * power, shade, 0.3, 0.9)
		fading(s, Enum.PartType.Ball, CFrame.new(centre), Vector3.one, Vector3.one * 40 * power, WHITE, 0.2, 0.45)
		ring(s, centre, 2, 110 * power, shade, 0.9, CFrame.Angles(math.rad(10), 0, math.rad(18)))
		ring(s, centre, 2, 90 * power, WHITE, 0.75, CFrame.Angles(math.rad(-16), 0, math.rad(-35)))
		ring(s, centre, 2, 70 * power, shade, 1.1, CFrame.Angles(math.rad(22), 0, math.rad(60)))
		local burst = point(s, centre)
		sprite(burst, TEX.nova, shade, 46 * power, 0.9, -200, 1, true)
		stardust(burst, shade, 140, 70, 3)
		sparks(burst, shade, 110, 60, 1.8)
		flames(burst, shade, math.round(22 * power), 56, 15)
	end
	star:Destroy()
	lens.Parent:Destroy()
	explode(bright, 1)
	Sfx.play("reveal_5")
	tween(s.correction, 0.4, { Brightness = 0.05 })
	-- Lo que queda: una nebulosa de colores detrás, que se va abriendo despacio.
	local hue, sat, value = color:ToHSV()
	local cloud = piece(s, Enum.PartType.Block, Vector3.new(84, 46, 10), CFrame.new(centre - Vector3.new(0, 0, 18)), WHITE, 1)
	for _, shade in { color, bright, Color3.fromHSV((hue + 0.13) % 1, sat * 0.8, value), Color3.fromHSV((hue + 0.87) % 1, sat, value * 0.8) } do
		emitter(cloud, {
			Texture = SMOKE,
			Color = ColorSequence.new(shade),
			LightEmission = 0.7,
			Rate = 4 / SLOW,
			Lifetime = life(3, 4.5),
			Speed = NumberRange.new(0.3 / SLOW, 1.2 / SLOW),
			SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-8 / SLOW, 8 / SLOW),
			Size = seq({ { 0, 10 }, { 1, 24 } }),
			Transparency = seq({ { 0, 1 }, { 0.25, 0.8 }, { 0.75, 0.84 }, { 1, 1 } }),
		}, 7)
	end
	local glow = Instance.new("PointLight")
	glow.Color = bright
	glow.Brightness = 2.2
	glow.Range = 50
	glow.Parent = core

	-- 5. El arma sale del núcleo como una silueta de luz, girando deprisa, mientras la cámara se acerca...
	local held = weapon(s, info, centre, 6)
	held.spin = 22
	held.outline.FillTransparency = 0
	held.outline.OutlineColor = WHITE
	local back = camAt(28, 1)
	local near = CFrame.lookAt(centre + Vector3.new(0, -0.6, 15.5), centre + Vector3.new(0, -2.6, 0))
	s.fov = 92
	animate(s, 1.5, function(t)
		local e = outCubic(t)
		held.scale = outBack(math.min(t * 1.8, 1))
		held.spin = lerp(22, 7, e)
		s.cam = back:Lerp(near, e)
		s.fov = lerp(92, 52, e)
	end)
	wait(s, 0.25)
	-- ...y revienta en sus colores.
	tween(held.outline, 0.35, { FillTransparency = 0.88, OutlineColor = bright })
	cover(s, bright:Lerp(WHITE, 0.6), 0.2, 1, 0.5)
	s.shake = 0.8
	Sfx.play("reveal_4")
	sprite(core, TEX.nova, bright, 26, 0.7, 220, 1, true)
	stardust(core, color, 80, 40, 2.4)
	ring(s, centre, 2, 60, bright, 0.7, CFrame.Angles(math.rad(12), 0, 0))
	rays(s, centre - Vector3.new(0, 0, 4), if jackpot then 9 else 6, 60, bright)
	-- En la absoluta el destello de detrás va más pequeño: a su tamaño normal quemaba a blanco el centro y tapaba
	-- la galaxia (y la punta del arma).
	shine(core, bright, if jackpot then 7 else 16, 12)
	if jackpot then
		-- La absoluta: una galaxia espiral dorada girando detrás del arma.
		-- Por delante de los rayos (que la taparían) y justo detrás del arma. Hecha con puntos de luz en tres
		-- brazos: la textura de remolino del pack, a ese tamaño, no se veía. Pequeña (tiene que caber entera en el
		-- plano: con 21 studs de radio solo se veían manchas sueltas), con muchos puntos pequeños y de oro hondo
		-- (aclarados salían beige) y un poco ladeada.
		local base = point(s, centre - Vector3.new(0, 0, 3.5))
		local deep = Color3.fromRGB(255, 170, 40)
		local function spot(position: Vector3, shade: Color3, size: number, alpha: number)
			local at = Instance.new("Attachment")
			at.Position = position
			at.Parent = base
			emitter(at, {
				Texture = TEX.halo,
				Color = ColorSequence.new(shade),
				LightEmission = 1,
				Rate = 1 / SLOW,
				Lifetime = life(1.4, 1.6),
				Speed = NumberRange.new(0),
				LockedToPart = true,
				Size = seq({ { 0, size * 0.5 }, { 0.5, size }, { 1, size * 0.5 } }),
				Transparency = seq({ { 0, 1 }, { 0.3, alpha }, { 0.7, alpha }, { 1, 1 } }),
			}, 1)
		end
		-- Los brazos empiezan fuera del arma y sin núcleo: con puntos hasta el centro se sumaban en una mancha
		-- blanca que se comía el arma.
		for arm = 0, 2 do
			for index = 1, 24 do
				local t = index / 24
				local angle = arm * math.pi * 2 / 3 + t * 3.6 + rng:NextNumber(-0.08, 0.08)
				local reach = 10 * (0.42 + 0.58 * t) + rng:NextNumber(-0.3, 0.3)
				spot(Vector3.new(math.cos(angle) * reach, math.sin(angle) * reach, 0), GOLD:Lerp(deep, 0.4 + 0.6 * t), lerp(1.7, 1, t), 0.3)
			end
		end
		table.insert(s.spinning, { part = base, centre = base.Position, speed = 0.35, tilt = CFrame.Angles(math.rad(-25), 0, math.rad(-14)), own = true })
	end
	animate(s, 0.5, function(t)
		held.spin = lerp(7, 2.5, t)
	end)

	-- 6. La tarjeta, con el número subiendo; al llegar, otra explosión.
	card(s, info)
	explode(if jackpot then GOLD else bright, if jackpot then 0.8 else 0.55, if jackpot then "cine_gold" else nil)
	if jackpot then
		-- Premio gordo: lluvia de estrellas (con su polvo) y una explosión más.
		local above = point(s, centre + Vector3.new(0, 26, 0), 50)
		emitter(above, {
			Texture = TEX.stardust,
			Color = ColorSequence.new(GOLD, WHITE),
			LightEmission = 0.8,
			Rate = 40 / SLOW,
			Lifetime = life(2, 3),
			Speed = NumberRange.new(8 / SLOW, 14 / SLOW),
			EmissionDirection = Enum.NormalId.Bottom,
			RotSpeed = NumberRange.new(-60, 60),
			Size = seq({ { 0, 1.1 }, { 1, 0.3 } }),
			Transparency = seq({ { 0, 0.2 }, { 0.8, 0.4 }, { 1, 1 } }),
		})
		emitter(above, {
			Texture = TEX.star,
			Color = ColorSequence.new(WHITE, GOLD),
			LightEmission = 0.8,
			Rate = 60 / SLOW,
			Lifetime = NumberRange.new(1.6 * SLOW, 2.4 * SLOW),
			Speed = NumberRange.new(16 / SLOW, 26 / SLOW),
			EmissionDirection = Enum.NormalId.Bottom,
			RotSpeed = NumberRange.new(-90, 90),
			Size = seq({ { 0, 1.8 }, { 1, 0.4 } }),
			Transparency = seq({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
		})
		wait(s, 0.7)
		explode(bright, 0.7)
		Sfx.play("win")
	end
	local hold = if jackpot then 3 else 2.2
	animate(s, hold, function(t)
		s.cam = near * CFrame.Angles(0, math.rad(lerp(-5, 5, smooth(t))), 0) * CFrame.new(0, 0, -1.4 * t)
	end)
end

-- Entrada -------------------------------------------------------------------------------

local function free(): boolean
	if Performance.get() or player:GetAttribute("RollCinematics") == false or Ui.anyOpen() or not rootPart() then
		return false
	end
	local gui = player:FindFirstChild("PlayerGui")
	local layer = hud()
	-- Eligiendo objeto para el trébol o con la pantalla de Mejoras abierta, no.
	local picking = layer and layer:FindFirstChild("CloverPick", true) :: GuiObject?
	local upgrades = gui and gui:FindFirstChild("UpgradesScreen") :: ScreenGui?
	local tree = upgrades and upgrades:FindFirstChild("Upgrades") :: GuiObject?
	return not (picking and picking.Visible) and not (tree and tree.Visible)
end

-- ¿Hay una cinemática en marcha? Mientras tanto SwordController no ataca con el clic.
function RollCinematic.isActive(): boolean
	return current ~= nil
end

-- Pide turno para una cinemática: false si ahora no toca (modo Rendimiento, ajuste apagado, una ventana abierta,
-- otra escena con la cámara, como la forja, o demasiadas esperando). Quien recibe true tiene que llamar a `play`.
function RollCinematic.reserve(): boolean
	if not free() or waiting >= MAX_WAITING then
		return false
	end
	if not current and workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	waiting += 1
	return true
end

-- Enseña la cinemática del tema `theme` y espera a que acabe o la salten. `info` = { roll, tier, level, line,
-- origin (dónde estaba el orbe), ground (Y del suelo) }. Devuelve false si al final no se pudo enseñar.
function RollCinematic.play(theme: string, info): boolean
	while current do
		task.wait(0.1)
	end
	waiting -= 1
	if not THEMES[theme] or not free() or workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	if not hooked then
		hooked = true
		-- Un viaje (barra de transporte, mazmorra) corta la que haya.
		Remotes.Teleported.OnClientEvent:Connect(function()
			if current then
				current.skipped = true
			end
		end)
	end
	info.color = info.tier.color
	info.bright = info.color:Lerp(WHITE, 0.35)
	SLOW = BASE * (PACE[theme] or 1)
	local s = newScene(info)
	current = s
	task.delay(TIMEOUT * SLOW, function()
		s.skipped = true
	end)
	local ok, problem = pcall(THEMES[theme], s, info)
	if not ok and problem ~= SKIP then
		warn(`[RollCinematic] {problem}`)
	end
	if ok and s.staged and not s.skipped then
		-- De vuelta del escenario: fundido a negro, se devuelve la cámara y se abre.
		pcall(function()
			cover(s, BLACK, 1, 0, 0.2)
			wait(s, 0.22)
		end)
		release(s)
		s.ui.holder.Visible = false
		s.ui.line.Visible = false
		tween(s.ui.cover, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.3 * SLOW)
	else
		release(s)
	end
	s.gui:Destroy()
	SLOW = BASE
	current = nil
	return true
end

return RollCinematic
