-- Capas visuales del clima: librería sin start(). client/Weather le pasa la lista `layers` de un clima de WeatherDefs
-- y recibe un mando con `step(dt, peso, vista)` (cada fotograma) y `destroy()`. Todo se crea en este cliente, dentro de
-- workspace.WeatherFx, con texturas y sonidos que trae Roblox, y nada choca ni se puede golpear. `peso` (0 a 1) es lo
-- metido que está el clima: las capas lo usan para entrar y salir poco a poco. `vista` = { eye = posición de la
-- cámara, center = punto un poco por delante de ella (donde se centran las cajas), ground = altura del suelo bajo el
-- personaje, now = os.clock(), clock = hora del servidor, started = cuándo empezó el clima (hora del servidor),
-- active = el clima sigue puesto (false mientras se va) }.
--
-- Tipos de capa (`kind`):
--   "particles": una caja invisible que acompaña a la cámara y suelta partículas. `at` dice dónde va: "above" (por
--     encima, a `height` studs), "around" (a la altura de la cámara más `height`) o "ground" (a `height` del suelo).
--     `area` = tamaño de la caja, `turn` = giro de la caja (para que lo que sale de una cara vaya con el viento),
--     `face` = cara por la que salen, `rate` = partículas por segundo con el clima entero, `life`, `speed`, `rot` y
--     `spin` = número o { mín, máx }, `spread` = { x, y }, `size`, `alpha` (transparencia) y `squash` = número o puntos
--     { { tiempo, valor }, ... }, `color` = un color o una lista, `glow` = LightEmission, `influence` = LightInfluence.
--     Para rayas que siguen su trayectoria (lluvia, rachas): `orient` = VelocityParallel y `squash` NEGATIVO (con el
--     positivo se estiran de través).
--   "sound": un sonido en bucle (`id`, `volume`, `pitch`) que sube y baja con el peso, en el grupo de efectos.
--   "lightning": rayos que caen en el mapa cada `every` segundos de media, a `radius` del centro: línea quebrada con
--     una rama, destello en toda la pantalla, luz en el punto de caída y trueno (`sound`).
--   "rainbow": arco de siete franjas con centro en `center` y radio `radius`, de cara al centro del mapa.
--   "aurora": cortinas de luz que ondulan en el cielo (`ribbons`: colores, tamaño de las rayas, altura, distancia,
--     largo, vaivén), hechas con rayas verticales de partículas.
--   "sky": imágenes en el cielo (`items`): pegadas al sol (`on = "sun"`), a la luna (`"moon"`) o a una dirección fija,
--     con su tamaño en grados, color, transparencia, giro y, si son un planeta, degradado y anillo.
--   "disc": bola negra que tapa el sol o la luna (`on`), de `size` grados: el disco del Eclipse.
--   "volcano": la erupción en la cima del Fuji (atributo VolcanoCrater de workspace): humo, lava y resplandor.
--   "meteors": bolas de luz que caen al mapa cada `every` segundos de media, con estela, y al llegar destello, ondas,
--     chispas, luz, marca en el suelo, temblor de cámara si cae cerca y estruendo.
--   "streaks": estrellas fugaces por toda la bóveda (`rate` por segundo), casi paralelas, como una lluvia de verdad.
-- Los rayos y los meteoritos caen a la misma hora y en el mismo sitio para todos los jugadores: salen de la hora del
-- servidor y de una semilla que es cuándo empezó el clima (`ticker`), sin mandar nada por la red.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Sfx)

local WeatherFx = {}

local DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"

local WHITE = Color3.new(1, 1, 1)
-- A qué distancia de la cámara se ponen las cosas del cielo. La bruma (Atmosphere) también se come los carteles y las
-- partículas: muy lejos no se ven, así que van cerca, altas (por encima de las montañas) y con el brillo subido.
local SKY_DISTANCE = 900

local player = Players.LocalPlayer

local function root(): Folder
	local found = workspace:FindFirstChild("WeatherFx")
	if not found then
		local folder = Instance.new("Folder")
		folder.Name = "WeatherFx"
		folder.Parent = workspace
		found = folder
	end
	return found :: Folder
end

-- Pieza invisible que no choca ni se puede tocar: de ella cuelgan los emisores.
local function anchor(parent: Instance, name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Parent = parent
	return part
end

local function range(value: any, fallback: number): NumberRange
	if type(value) == "table" then
		return NumberRange.new(value[1], value[2])
	end
	return NumberRange.new(value or fallback)
end

local function numbers(value: any, fallback: number): NumberSequence
	if type(value) == "table" then
		local points = {}
		for _, point in value do
			table.insert(points, NumberSequenceKeypoint.new(point[1], point[2]))
		end
		return NumberSequence.new(points)
	end
	return NumberSequence.new(value or fallback)
end

local function colors(value: any): ColorSequence
	if type(value) == "table" then
		local points = {}
		for index, color in value do
			table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#value - 1), color))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(value or WHITE)
end

local function emitterFrom(def: { [string]: any }, parent: Instance): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = def.texture or DOT
	emitter.Color = colors(def.color)
	emitter.EmissionDirection = def.face or Enum.NormalId.Bottom
	emitter.Rate = 0
	emitter.Lifetime = range(def.life, 5)
	emitter.Speed = range(def.speed, 5)
	emitter.SpreadAngle = if def.spread then Vector2.new(def.spread[1], def.spread[2]) else Vector2.zero
	emitter.Acceleration = def.accel or Vector3.zero
	emitter.Drag = def.drag or 0
	emitter.Rotation = range(def.rot, 0)
	emitter.RotSpeed = range(def.spin, 0)
	emitter.Size = numbers(def.size, 0.3)
	emitter.Transparency = numbers(def.alpha, 0)
	if def.squash then
		emitter.Squash = numbers(def.squash, 0)
	end
	if def.orient then
		emitter.Orientation = def.orient
	end
	emitter.LightEmission = def.glow or 0
	emitter.LightInfluence = def.influence or 0
	emitter.Brightness = def.bright or 1
	emitter.ZOffset = def.z or 0
	emitter.Parent = parent
	return emitter
end

-- Destello que crece y se apaga (bola, o cilindro tumbado para las ondas del suelo).
local function flash(shape: Enum.PartType, cframe: CFrame, from: Vector3, to: Vector3, color: Color3, transparency: number, time: number)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = from
	part.CFrame = cframe
	part.Parent = root()
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = to, Transparency = 1 }):Play()
	Debris:AddItem(part, time + 0.1)
end

-- Altura del suelo (o de lo que haya: un tejado, un árbol) en ese punto del mapa.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(x: number, z: number): number
	local skip = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -700, 0), rayParams)
	return if hit then hit.Position.Y else 0.5
end

-- Punto al azar del mapa, a `radius` del centro como mucho.
local function spot(random: Random, radius: number): Vector3
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(random:NextNumber()) * radius
	local x, z = math.cos(angle) * distance, math.sin(angle) * distance
	return Vector3.new(x, groundAt(x, z), z)
end

-- Sucesos a la misma hora y en el mismo sitio para todos: cada `length` segundos desde que empezó el clima se tira,
-- con una semilla que sale de esa hora, si toca uno (`chance`). Devuelve la función que hay que llamar cada fotograma.
local function ticker(length: number, chance: number, salt: number)
	local last: number? = nil
	return function(view: { [string]: any }, fire: (Random) -> ())
		local index = math.floor((view.clock - view.started) / length)
		if not last or index < last or index - last > 12 or not view.active then
			last = index -- recién montada, clima nuevo, un tirón largo o yéndose: no se recupera lo perdido
			return
		end
		while last < index do
			last += 1
			local random = Random.new(math.floor(view.started) * 131 + last * 7 + salt)
			if random:NextNumber() < chance then
				fire(random)
			end
		end
	end
end

-- Un golpe de sonido suelto, más flojo cuanto más lejos de la cámara y con el retraso de la distancia.
local function boom(id: string | { string }, at: Vector3, eye: Vector3, volume: number, pitch: number, reach: number)
	if type(id) == "table" then
		id = id[math.random(#id)] -- varias grabaciones: una cualquiera (el sonido no tiene que coincidir entre jugadores)
	end
	local distance = (at - eye).Magnitude
	local loud = volume * math.clamp(1 - distance / reach, 0.15, 1)
	task.delay(math.min(distance / 700, 1.2), function()
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = loud
		sound.PlaybackSpeed = pitch
		sound.SoundGroup = Sfx.group()
		-- Sale de donde ha caído, para oírlo por su lado. Lo flojo que llega ya está calculado arriba: con la
		-- distancia mínima tan grande, Roblox no lo baja otra vez.
		local anchor = Instance.new("Attachment")
		anchor.Position = at
		anchor.Parent = workspace.Terrain
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.RollOffMinDistance = 10000
		sound.RollOffMaxDistance = 20000
		sound.Parent = anchor
		sound:Play()
		Debris:AddItem(anchor, 6)
	end)
end

-- Temblor corto de la cámara (como el del golpe contra el suelo de SwingAnim).
local function shake(strength: number, seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < seconds and humanoid.Parent do
			local fade = 1 - (os.clock() - began) / seconds
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength * fade
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- Destello de toda la pantalla (rayos, meteoritos grandes): sube la exposición un instante. Lo aplica y lo apaga el
-- mando de las capas (`WeatherFx.build`).
local glare = 0
local function addGlare(amount: number)
	glare = math.max(glare, amount)
end

-- Lo cerca que cae algo de la cámara: 1 al lado, `floor` a `far` studs o más.
local function nearness(at: Vector3, eye: Vector3, far: number, floor: number): number
	return math.clamp(1 - (at - eye).Magnitude / far, floor, 1)
end

type Layer = { step: (number, number, { [string]: any }) -> (), destroy: (() -> ())? }
local builders: { [string]: (def: { [string]: any }, parent: Instance) -> Layer } = {}

-- Partículas alrededor de la cámara ------------------------------------------------------------------------

builders.particles = function(def, parent)
	local box = anchor(parent, def.name or "Particles", def.area or Vector3.new(150, 1, 150))
	local emitter = emitterFrom(def, box)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

	local turn = def.turn or CFrame.identity
	local height = def.height
	return {
		step = function(_, weight, view)
			emitter.Rate = def.rate * weight
			local center = view.center
			local y = if def.at == "ground" then view.ground + (height or 0)
				elseif def.at == "around" then view.eye.Y + (height or 0)
				else view.eye.Y + (height or 40)
			box.CFrame = CFrame.new(center.X, y, center.Z) * turn
		end,
	}
end

builders.sound = function(def)
	local sound = Instance.new("Sound")
	sound.Name = "Weather"
	sound.SoundId = def.id
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = def.pitch or 1
	sound.SoundGroup = Sfx.group()
	sound.Parent = SoundService
	sound:Play()
	return {
		step = function(_, weight)
			sound.Volume = (def.volume or 0.3) * weight
		end,
		destroy = function()
			sound:Destroy()
		end,
	}
end

-- Rayos ----------------------------------------------------------------------------------------------------

-- Línea quebrada de luz entre dos puntos, hecha con tramos rectos (Beam) entre puntos de enganche.
local function bolt(holder: BasePart, from: Vector3, to: Vector3, random: Random, points: number, wander: number, width: number, color: Color3): { Instance }
	local made: { Instance } = {}
	local previous: Attachment? = nil
	local across = (to - from).Unit:Cross(Vector3.new(0.3, 0, 1).Unit)
	local other = (to - from).Unit:Cross(across)
	for index = 0, points do
		local t = index / points
		-- Los extremos, en su sitio; por el medio se va de lado.
		local drift = math.sin(t * math.pi) * wander
		local position = from:Lerp(to, t) + across * random:NextNumber(-1, 1) * drift + other * random:NextNumber(-1, 1) * drift
		local point = Instance.new("Attachment")
		point.Parent = holder
		point.WorldPosition = position
		table.insert(made, point)
		if previous then
			local beam = Instance.new("Beam")
			beam.Attachment0 = previous
			beam.Attachment1 = point
			beam.Segments = 1
			beam.Width0 = width * (1 - (index - 1) / points * 0.5)
			beam.Width1 = width * (1 - index / points * 0.5)
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(WHITE:Lerp(color, 0.25))
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 4
			beam.Parent = holder
			table.insert(made, beam)
		end
		previous = point
	end
	return made
end

builders.lightning = function(def, parent)
	local holder = anchor(parent, "Lightning", Vector3.one)
	holder.CFrame = CFrame.identity
	local color = def.color or Color3.fromRGB(210, 222, 255)
	local roll = ticker(1, 1 / (def.every or 5), 11)

	local function strike(random: Random, eye: Vector3)
		local ground = spot(random, def.radius or 380)
		local top = ground + Vector3.new(random:NextNumber(-70, 70), def.height or 270, random:NextNumber(-70, 70))
		local parts = bolt(holder, top, ground, random, 10, 22, def.width or 5, color)
		-- Una rama que sale de media altura y se pierde hacia un lado.
		local fork = top:Lerp(ground, random:NextNumber(0.3, 0.55))
		local away = Vector3.new(random:NextNumber(-1, 1), -0.7, random:NextNumber(-1, 1)).Unit * random:NextNumber(60, 110)
		for _, item in bolt(holder, fork, fork + away, random, 5, 9, (def.width or 5) * 0.5, color) do
			table.insert(parts, item)
		end

		local near = nearness(ground, eye, 520, 0.3)
		addGlare((def.flash or 1.2) * near)
		local lamp = anchor(holder.Parent :: Instance, "Strike", Vector3.one)
		lamp.Position = ground + Vector3.new(0, 4, 0)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 60
		light.Brightness = 8
		light.Parent = lamp
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		Debris:AddItem(lamp, 0.6)
		flash(Enum.PartType.Cylinder, CFrame.new(ground + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(0.3, 4, 4), Vector3.new(0.3, 34, 34), color, 0.3, 0.4)
		-- El estruendo de serie se baja de tono para que parezca un trueno; uno de verdad va casi al suyo.
		boom(def.sound or BOOM, ground, eye, 0.9, random:NextNumber(0.45, 0.7) * (if def.sound then 1.6 else 1), 900)

		-- Parpadea dos veces y se apaga.
		task.spawn(function()
			local function show(on: boolean)
				for _, item in parts do
					if item:IsA("Beam") then
						item.Enabled = on
					end
				end
			end
			task.wait(0.09)
			show(false)
			task.wait(0.05)
			show(true)
			addGlare((def.flash or 1.2) * near * 0.7)
			for fade = 1, 6 do
				task.wait(0.03)
				for _, item in parts do
					if item:IsA("Beam") then
						item.Transparency = NumberSequence.new(fade / 6)
					end
				end
			end
			for _, item in parts do
				item:Destroy()
			end
		end)
	end

	return {
		step = function(_, _, view)
			roll(view, function(random)
				strike(random, view.eye)
			end)
		end,
	}
end

-- Arcoíris -------------------------------------------------------------------------------------------------

local RAINBOW = {
	Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 150, 50), Color3.fromRGB(255, 232, 70), Color3.fromRGB(90, 220, 100),
	Color3.fromRGB(70, 190, 255), Color3.fromRGB(90, 110, 255), Color3.fromRGB(180, 100, 255),
}

builders.rainbow = function(def, parent)
	local center: Vector3 = def.center
	local toward = Vector3.new(-center.X, 0, -center.Z).Unit -- hacia el centro del mapa
	local right = toward:Cross(Vector3.yAxis).Unit
	local holder = anchor(parent, "Rainbow", Vector3.one)
	holder.CFrame = CFrame.new(center)
	local width = def.width or 16
	local beams = {}
	for index, color in RAINBOW do
		local radius = def.radius - (index - 1) * width
		local reach = radius * 4 / 3 -- con esta curvatura el arco es casi medio círculo
		-- Los enganches miran hacia arriba (su eje X), que es hacia donde se comba el arco. Primero se cuelgan y
		-- luego se colocan: su posición en el mundo se cuenta desde la pieza.
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		a0.WorldCFrame = CFrame.fromMatrix(center - right * radius, Vector3.yAxis, right)
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		a1.WorldCFrame = CFrame.fromMatrix(center + right * radius, Vector3.yAxis, right)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.CurveSize0 = reach
		beam.CurveSize1 = -reach
		beam.Segments = 40
		beam.Width0 = width * 1.25 -- un poco más anchas que su hueco: las franjas se tocan
		beam.Width1 = width * 1.25
		beam.FaceCamera = true
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		beam.Brightness = 1.5
		beam.Transparency = NumberSequence.new(1)
		beam.Parent = holder
		table.insert(beams, beam)
	end
	local shown = -1
	return {
		step = function(_, weight)
			if math.abs(weight - shown) < 0.01 then
				return
			end
			shown = weight
			-- Se pierde hacia los dos pies del arco.
			local clear = 1 - (def.alpha or 0.5) * weight
			local sequence = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.16, clear),
				NumberSequenceKeypoint.new(0.84, clear),
				NumberSequenceKeypoint.new(1, 1),
			})
			for _, beam in beams do
				beam.Transparency = sequence
			end
		end,
	}
end

-- Aurora ---------------------------------------------------------------------------------------------------

-- Cada cinta es una hilera de cajas a lo largo de una línea que ondula; de ellas salen rayas de luz altas y de pie
-- (siempre verticales, miren desde donde miren) que se montan unas sobre otras y hacen la cortina. Van con la cámara,
-- como si estuvieran en el cielo, lejísimos.
local AURORA_SEGMENTS = 5

builders.aurora = function(def, parent)
	local ribbons = {}
	for _, ribbon in def.ribbons do
		local length = ribbon.span / AURORA_SEGMENTS
		local angle = math.rad(ribbon.angle or 0)
		local entry = {
			def = ribbon, boxes = {}, emitters = {},
			along = Vector3.new(math.cos(angle), 0, math.sin(angle)),
			out = Vector3.new(-math.sin(angle), 0, math.cos(angle)),
		}
		for index = 1, AURORA_SEGMENTS do
			local box = anchor(parent, "Aurora", Vector3.new(length * 1.15, 6, 16))
			local emitter = emitterFrom({
				texture = DOT, color = ribbon.colors, face = Enum.NormalId.Top, life = ribbon.life or { 3, 5 }, speed = { 0, 3 },
				size = ribbon.size or 60, squash = ribbon.squash or 1.6,
				alpha = { { 0, 1 }, { 0.3, 1 - (ribbon.alpha or 0.5) }, { 0.7, 1 - (ribbon.alpha or 0.5) }, { 1, 1 } },
				glow = 1, bright = ribbon.bright or 3,
			}, box)
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			emitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
			entry.boxes[index] = box
			entry.emitters[index] = emitter
		end
		table.insert(ribbons, entry)
	end
	return {
		step = function(_, weight, view)
			local now = view.now
			local eye = view.eye
			for _, ribbon in ribbons do
				local info = ribbon.def
				local speed = info.speed or 0.25
				local phase = info.phase or 0
				local function place(index: number): Vector3
					local t = (index - 0.5) / AURORA_SEGMENTS - 0.5
					local sway = math.sin(now * speed + index * 0.9 + phase) * (info.sway or 70)
					local bob = math.sin(now * speed * 0.7 + index * 1.3 + phase * 2) * (info.bob or 25)
					return Vector3.new(eye.X, info.height + bob, eye.Z) + ribbon.along * (info.span * t) + ribbon.out * (info.distance + sway)
				end
				for index, box in ribbon.boxes do
					-- La caja se tumba a lo largo de la cinta (su eje X), siguiendo la curva.
					local here = place(index)
					local ahead = place(index + 1) - place(index - 1)
					box.CFrame = CFrame.fromMatrix(here, Vector3.new(ahead.X, 0, ahead.Z).Unit, Vector3.yAxis)
					-- Cada tramo late a su aire.
					local shimmer = 0.7 + 0.3 * math.sin(now * 0.9 + index * 1.7 + phase)
					ribbon.emitters[index].Rate = (info.rate or 14) * weight * shimmer
				end
			end
		end,
	}
end

-- Cosas en el cielo -----------------------------------------------------------------------------------------

builders.sky = function(def, parent)
	local items = {}
	for order, item in def.items do
		local distance = (def.distance or SKY_DISTANCE) - order * 12 -- las de después, un poco más cerca: se pintan encima
		local studs = 2 * distance * math.tan(math.rad(item.size) / 2)
		local holder = anchor(parent, "Sky" .. order, Vector3.one)
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromScale(studs, studs)
		board.LightInfluence = 0
		board.Brightness = item.bright or 1
		board.MaxDistance = math.huge
		board.Parent = holder
		local image = Instance.new("ImageLabel")
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = item.image
		image.ImageColor3 = item.color or WHITE
		image.ImageTransparency = 1
		image.Rotation = item.turn or 0
		image.Parent = board
		if item.gradient then
			-- Planeta: una cara iluminada y la otra en sombra.
			local shade = Instance.new("UIGradient")
			shade.Color = ColorSequence.new(item.gradient[1], item.gradient[2])
			shade.Rotation = 50
			shade.Parent = image
		end
		local ring: ImageLabel? = nil
		if item.ring then
			local halo = Instance.new("ImageLabel")
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.fromScale(0.5, 0.5)
			halo.Size = UDim2.fromScale(1.6, 0.44) -- el aro de la textura ocupa solo el centro: así sobresale del planeta
			halo.Rotation = item.ring.tilt or -20
			halo.BackgroundTransparency = 1
			halo.Image = RING
			halo.ImageColor3 = item.ring.color
			halo.ImageTransparency = 1
			halo.Parent = board
			image.Size = UDim2.fromScale(0.5, 0.5)
			ring = halo
		end
		local fixed = if typeof(item.on) == "Vector3" then (item.on :: Vector3).Unit else nil
		table.insert(items, { def = item, holder = holder, image = image, ring = ring, fixed = fixed, distance = distance })
	end
	return {
		step = function(dt, weight, view)
			for _, entry in items do
				local item = entry.def
				local direction = entry.fixed
					or (if item.on == "moon" then Lighting:GetMoonDirection() else Lighting:GetSunDirection())
				entry.holder.Position = view.eye + direction * entry.distance
				local pulse = if item.pulse then 1 + item.pulse * math.sin(view.now * (item.pulseSpeed or 1.5) + entry.distance) else 1
				local solid = math.clamp((1 - (item.alpha or 0)) * weight * pulse, 0, 1)
				entry.image.ImageTransparency = 1 - solid
				if entry.ring then
					entry.ring.ImageTransparency = 1 - solid * 0.8
				end
				if item.spin then
					entry.image.Rotation += item.spin * dt
				end
			end
		end,
	}
end

-- Disco que tapa el sol o la luna (el Eclipse): una bola negra de verdad, lejos y en su dirección. Detrás queda la
-- textura que se le ponga al astro (un resplandor con rayos) y solo asoma la corona.
builders.disc = function(def, parent)
	local distance = def.distance or SKY_DISTANCE
	local ball = anchor(parent, "Disc", Vector3.one * 2 * distance * math.tan(math.rad(def.size) / 2))
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = def.color or Color3.new(0, 0, 0)
	return {
		step = function(_, weight, view)
			local direction = if def.on == "sun" then Lighting:GetSunDirection() else Lighting:GetMoonDirection()
			ball.Position = view.eye + direction * distance
			ball.Transparency = 1 - weight
		end,
	}
end

-- Volcán ---------------------------------------------------------------------------------------------------

builders.volcano = function(def, parent)
	local crater = workspace:GetAttribute("VolcanoCrater")
	if typeof(crater) ~= "Vector3" then
		return { step = function() end } -- mapa sin Fuji: se queda la ceniza y el cielo rojo
	end
	local mouth = anchor(parent, "Crater", Vector3.new(def.mouth or 70, 4, def.mouth or 70))
	mouth.CFrame = CFrame.new(crater)
	local emitters = {}
	for _, layer in def.emitters do
		local emitter = emitterFrom(layer, mouth)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitters[emitter] = layer.rate
	end
	-- Resplandor de la lava en la boca, a la vista desde toda la isla.
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(def.glow or 520, def.glow or 520)
	board.LightInfluence = 0
	board.Brightness = def.glowBright or 6 -- muy subido: está lejísimos y la bruma se lo come
	board.MaxDistance = math.huge
	board.Parent = mouth
	local glowImage = Instance.new("ImageLabel")
	glowImage.Size = UDim2.fromScale(1, 1)
	glowImage.BackgroundTransparency = 1
	glowImage.Image = DOT
	glowImage.ImageColor3 = def.color or Color3.fromRGB(255, 120, 40)
	glowImage.ImageTransparency = 1
	glowImage.Parent = board
	return {
		step = function(_, weight, view)
			for emitter, rate in emitters do
				emitter.Rate = rate * weight
			end
			local throb = 0.8 + 0.2 * math.sin(view.now * 2.3)
			glowImage.ImageTransparency = 1 - 0.7 * weight * throb
		end,
	}
end

-- Meteoritos -----------------------------------------------------------------------------------------------

-- Lo que pasa cuando uno llega al suelo.
local function impact(def: { [string]: any }, at: Vector3, size: number, color: Color3, eye: Vector3)
	local light = color:Lerp(WHITE, 0.5)
	local flat = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	flash(Enum.PartType.Ball, CFrame.new(at), Vector3.one * size, Vector3.one * size * 7, light, 0.25, 0.35)
	for wave = 0, 2 do
		task.delay(wave * 0.12, function()
			flash(Enum.PartType.Cylinder, flat, Vector3.new(0.3, size, size), Vector3.new(0.3, size * (10 + wave * 4), size * (10 + wave * 4)), color, 0.3, 0.55 + wave * 0.1)
		end)
	end
	if def.column then
		flash(Enum.PartType.Cylinder, CFrame.new(at + Vector3.new(0, 70, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(140, size * 1.3, size * 1.3), Vector3.new(140, 0.2, 0.2), light, 0.35, 0.7)
	end

	local burst = anchor(root(), "Impact", Vector3.one)
	burst.Position = at + Vector3.new(0, 1.5, 0)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(WHITE, color)
	sparks.LightEmission = 1
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.8, 1.5)
	sparks.Speed = NumberRange.new(26, 60)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Drag = 1.5
	sparks.Acceleration = Vector3.new(0, -42, 0)
	sparks.RotSpeed = NumberRange.new(-200, 200)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.55), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = burst
	sparks:Emit(def.sparks or 40)
	local lamp = Instance.new("PointLight")
	lamp.Color = color
	lamp.Range = 50 + size * 8
	lamp.Brightness = 6
	lamp.Parent = burst
	TweenService:Create(lamp, TweenInfo.new(0.9), { Brightness = 0 }):Play()
	Debris:AddItem(burst, 2.5)

	-- Marca encendida que se enfría.
	local mark = Instance.new("Part")
	mark.Shape = Enum.PartType.Cylinder
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Material = Enum.Material.Neon
	mark.Color = color
	mark.Transparency = 0.35
	mark.Size = Vector3.new(0.15, size * 2.6, size * 2.6)
	mark.CFrame = flat
	mark.Parent = root()
	TweenService:Create(mark, TweenInfo.new(def.mark or 3.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(mark, (def.mark or 3.5) + 0.1)

	local character = player.Character
	local body = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if body then
		local close = 1 - (body.Position - at).Magnitude / 130
		if close > 0 then
			shake(0.9 * close, 0.35)
		end
	end
	addGlare((def.flash or 0.3) * nearness(at, eye, 420, 0.2) * size / 4)
	boom(def.sound or BOOM, at, eye, def.volume or 0.7, 0.85 + math.random() * 0.4, 700)
end

builders.meteors = function(def, parent)
	local roll = ticker(0.25, 0.25 / (def.every or 2), 23)
	local live = {}
	local slant: Vector3 = (def.slant or Vector3.new(0.5, 0.82, 0.28)).Unit

	local function launch(random: Random)
		if #live >= (def.max or 8) then
			return
		end
		local target = spot(random, def.radius or 400)
		local color = def.colors[random:NextInteger(1, #def.colors)]
		local size = random:NextNumber(def.size[1], def.size[2])
		local from = target + (slant + Vector3.new(random:NextNumber(-0.14, 0.14), 0, random:NextNumber(-0.14, 0.14))).Unit * (def.reach or 700)
		local head = Instance.new("Part")
		head.Name = "Meteor"
		head.Shape = Enum.PartType.Ball
		head.Anchored = true
		head.CanCollide = false
		head.CanQuery = false
		head.CanTouch = false
		head.CastShadow = false
		head.Material = Enum.Material.Neon
		head.Color = color:Lerp(WHITE, 0.55)
		head.Size = Vector3.one * size
		head.CFrame = CFrame.lookAt(from, target)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(size * 0.5, 0, 0)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(-size * 0.5, 0, 0)
		a1.Parent = head
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.Lifetime = def.tail or 0.6
		trail.MinLength = 0
		trail.Color = ColorSequence.new(WHITE, color)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new(1, 0.05)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Brightness = 3
		trail.Parent = head
		local shed = Instance.new("ParticleEmitter")
		shed.Texture = def.shed or SPARK
		shed.Color = ColorSequence.new(WHITE, color)
		shed.LightEmission = if def.smoky then 0.2 else 1
		shed.Rate = 70
		shed.Lifetime = NumberRange.new(0.4, 1)
		shed.Speed = NumberRange.new(2, 8)
		shed.SpreadAngle = Vector2.new(180, 180)
		shed.RotSpeed = NumberRange.new(-120, 120)
		shed.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * (if def.smoky then 1.4 else 0.7)), NumberSequenceKeypoint.new(1, 0) })
		shed.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if def.smoky then 0.4 else 0), NumberSequenceKeypoint.new(1, 1) })
		shed.Parent = head
		local lamp = Instance.new("PointLight")
		lamp.Color = color
		lamp.Range = 30 + size * 6
		lamp.Brightness = 3
		lamp.Parent = head
		head.Parent = parent
		table.insert(live, {
			head = head, from = from, to = target, color = color, size = size,
			start = os.clock(), time = random:NextNumber(def.fall[1], def.fall[2]),
		})
	end

	return {
		step = function(_, _, view)
			roll(view, launch)
			for index = #live, 1, -1 do
				local meteor = live[index]
				local t = (view.now - meteor.start) / meteor.time
				if t >= 1 then
					table.remove(live, index)
					-- La cabeza se queda un momento, invisible, para que la estela termine de apagarse sola.
					meteor.head.Transparency = 1
					meteor.head.CFrame = CFrame.new(meteor.to)
					for _, child in meteor.head:GetChildren() do
						if child:IsA("ParticleEmitter") or child:IsA("PointLight") then
							child.Enabled = false
						end
					end
					Debris:AddItem(meteor.head, 1.2)
					impact(def, meteor.to, meteor.size, meteor.color, view.eye)
				else
					local position = meteor.from:Lerp(meteor.to, t ^ 1.15) -- acelera un poco al caer
					meteor.head.CFrame = CFrame.lookAt(position, meteor.to)
				end
			end
		end,
		destroy = function()
			table.clear(live)
		end,
	}
end

-- Estrellas fugaces ------------------------------------------------------------------------------------------

-- Transparencias de una estela (cola invisible, cabeza de nada a entera), por escalones.
local STREAK_STEPS = 12
local STREAK_FADES: { [number]: NumberSequence } = {}
for step = 0, STREAK_STEPS do
	STREAK_FADES[step] = NumberSequence.new(1, 1 - step / STREAK_STEPS)
end

builders.streaks = function(def, parent)
	local holder = anchor(parent, "Streaks", Vector3.one)
	holder.CFrame = CFrame.identity
	local random = Random.new()
	local distance = def.distance or 1800
	local fall: Vector3 = (def.fall or Vector3.new(-0.42, -0.78, 0.3)).Unit
	local pool = {}
	for _ = 1, def.pool or 40 do
		local tail = Instance.new("Attachment")
		tail.Parent = holder
		local head = Instance.new("Attachment")
		head.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = tail
		beam.Attachment1 = head
		beam.Segments = 1
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = def.bright or 3
		beam.Enabled = false
		beam.Parent = holder
		table.insert(pool, { tail = tail, head = head, beam = beam, busy = false })
	end
	local budget = 0

	local function spawn(slot)
		-- Un punto de la bóveda y, desde él, hacia donde cae la lluvia. Más cerca del horizonte que del cenit, que es
		-- hacia donde mira la cámara casi siempre.
		local elevation = math.rad(random:NextNumber(8, 66))
		local azimuth = random:NextNumber(0, math.pi * 2)
		local dome = Vector3.new(math.cos(elevation) * math.cos(azimuth), math.sin(elevation), math.cos(elevation) * math.sin(azimuth))
		local push = (fall + Vector3.new(random:NextNumber(-0.16, 0.16), random:NextNumber(-0.1, 0.1), random:NextNumber(-0.16, 0.16))).Unit
		local slide = push - dome * push:Dot(dome) -- la parte que resbala por la bóveda
		if slide.Magnitude < 0.2 then
			return
		end
		local big = random:NextNumber() < (def.bigChance or 0.05)
		local length = random:NextNumber(def.length[1], def.length[2]) * (if big then 1.6 else 1)
		local life = random:NextNumber(def.life[1], def.life[2]) * (if big then 1.4 else 1)
		local color = def.colors[random:NextInteger(1, #def.colors)]
		local width = random:NextNumber(def.width[1], def.width[2]) * (if big then 2.6 else 1)
		slot.busy = true
		slot.origin = dome * distance
		slot.velocity = slide.Unit * (length / life)
		slot.reach = length * 0.6
		slot.life = life
		slot.age = 0
		slot.fade = nil
		slot.beam.Width0 = width * 0.15
		slot.beam.Width1 = width
		slot.beam.Color = ColorSequence.new(color, WHITE:Lerp(color, 0.25))
		slot.beam.Enabled = true
		if big then
			addGlare(def.flash or 0.18)
		end
	end

	return {
		step = function(dt, weight, view)
			budget = math.min(budget + dt * def.rate * weight, 6)
			for _, slot in pool do
				if slot.busy then
					slot.age += dt
					local t = slot.age / slot.life
					if t >= 1 then
						slot.busy = false
						slot.beam.Enabled = false
					else
						local front = slot.origin + slot.velocity * slot.age
						local back = front - slot.velocity.Unit * math.min(slot.reach, slot.velocity.Magnitude * slot.age)
						slot.head.WorldPosition = view.eye + front
						slot.tail.WorldPosition = view.eye + back
						-- Aparece deprisa y se apaga al final; la cola siempre se pierde. En unos pocos escalones ya
						-- hechos (STREAK_FADES), para no crear una secuencia por estrella y fotograma.
						local step = math.floor(math.min(t / 0.15, 1, (1 - t) / 0.35) * weight * STREAK_STEPS + 0.5)
						if step ~= slot.fade then
							slot.fade = step
							slot.beam.Transparency = STREAK_FADES[step]
						end
					end
				elseif budget >= 1 then
					budget -= 1
					spawn(slot)
				end
			end
		end,
	}
end

-- Monta las capas de un clima. Devuelve su mando.
function WeatherFx.build(layers: { { [string]: any } })
	local group = Instance.new("Folder")
	group.Name = "Layers"
	group.Parent = root()
	local items: { Layer } = {}
	for _, def in layers do
		local make = builders[def.kind]
		if make then
			-- Una capa mal definida se queda sin montar y avisa; las demás siguen (y quien llama no lo reintenta
			-- cada fotograma dejando restos).
			local ok, item = pcall(make, def, group)
			if ok then
				table.insert(items, item)
			else
				warn(`[WeatherFx] No se pudo montar la capa "{def.kind}": {item}`)
			end
		end
	end
	local exposure = Lighting.ExposureCompensation
	glare = 0
	return {
		step = function(dt: number, weight: number, view: { [string]: any })
			for _, item in items do
				item.step(dt, weight, view)
			end
			-- Los destellos se apagan solos en un instante.
			if glare > 0 then
				glare = if glare < 0.01 then 0 else glare * math.max(0, 1 - dt * 6)
				Lighting.ExposureCompensation = exposure + glare
			end
		end,
		destroy = function()
			for _, item in items do
				if item.destroy then
					item.destroy()
				end
			end
			glare = 0
			Lighting.ExposureCompensation = exposure
			group:Destroy()
		end,
	}
end

return WeatherFx
