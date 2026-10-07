-- Auras de las armas raras: cada arma lleva la suya, pensada para su nombre y sus colores (fuego, hielo, rayos,
-- cosmos, sombra...). El diseño de cada una está en WeaponAuraDefs; aquí se convierte en partículas, estelas,
-- aros de luz, rayos, luz y cosas que giran alrededor del arma o del jugador, y se suelta una ráfaga al atacar.
-- El servidor solo marca la hoja con la etiqueta "WeaponAura" y los atributos Level y Scale (lo hace SwordModel);
-- los efectos se crean en cada cliente, dentro de la hoja: al desaparecer el arma se van con ella.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Performance = require(script.Parent.Performance)
local Defs = require(script.Parent.WeaponAuraDefs)

local WeaponAura = {}

local TAG = "WeaponAura"
local WHITE = Color3.new(1, 1, 1)
local SMOKE_GRAY = Color3.fromRGB(45, 42, 48)

local FAR = 220 -- más lejos de la cámara no se mueven las órbitas ni los rayos
local DUAL_RATE = 0.7 -- las armas dobles reparten las partículas entre las dos hojas
local BODY = Vector3.new(4.2, 5.6, 4.2) -- caja alrededor del personaje de la que salen las partículas del jugador
local PLAYER_SPOTS = { player = true, feet = true, head = true }
local BOLT_POINTS = 6 -- vértices de cada rayo
local FLASH = 0.18 -- segundos que la luz brilla de más al atacar
-- Estelas y aros: poca luz propia, que a mediodía los quema a blanco y se pierde el color (medido en Studio).
local RIBBON_EMISSION = 0.4
local RIBBON_BRIGHTNESS = 1.25
local BOLT_BRIGHTNESS = 4 -- los rayos sí van al blanco
local FULL_BLADE = 3.5 -- largo de hoja con el que un aura lleva todas sus partículas; las puntas de lanza, menos

-- Cómo cambia de tamaño una partícula a lo largo de su vida (1 = su tamaño máximo).
local GROW = {
	pop = { { 0, 0 }, { 0.25, 1 }, { 1, 0 } },
	puff = { { 0, 0.35 }, { 1, 1 } },
	shrink = { { 0, 1 }, { 1, 0 } },
	flat = { { 0, 1 }, { 0.8, 1 }, { 1, 0 } },
	twinkle = { { 0, 0 }, { 0.15, 1 }, { 0.4, 0.35 }, { 0.65, 1 }, { 1, 0 } },
	flame = { { 0, 0.45 }, { 0.3, 1 }, { 1, 0.2 } },
	grow = { { 0, 0.1 }, { 1, 1 } },
}
-- Cómo se desvanece (0 = lo más opaca que llega a estar, 1 = invisible).
local ALPHA = {
	fade = { { 0, 0 }, { 1, 1 } },
	linger = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } },
	puff ={ { 0, 1 }, { 0.25, 0 }, { 1, 1 } },
	hold = { { 0, 0 }, { 0.7, 0 }, { 1, 1 } },
	blink = { { 0, 0 }, { 0.2, 0 }, { 0.21, 1 }, { 0.4, 1 }, { 0.41, 0 }, { 0.6, 0 }, { 0.61, 1 }, { 0.8, 1 }, { 0.81, 0 }, { 0.95, 0 }, { 1, 1 } },
}
local ARC = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) })

-- El ∞ de un arma va tumbado sobre la cara ancha de la hoja; un aro se dibuja con dos curvas cuyas puntas miran así.
local FLAT_ON_BLADE = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis)
local TANGENT = CFrame.Angles(0, -math.pi / 2, 0)

local random = Random.new()
local auras = {} -- [hoja] = estado del aura

local function tierIndex(rarity: number?): number
	local found = 1
	for index, tier in Config.RarityTiers do
		if (rarity or 0) >= tier.min then
			found = index
		end
	end
	return found
end

local function shift(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV((h + amount) % 1, math.max(s, 0.55), math.max(v, 0.9))
end

local function pick(palette, ref): Color3
	return if typeof(ref) == "Color3" then ref else palette[ref] or palette.main
end

local function gradient(palette, refs): ColorSequence
	if #refs == 1 then
		return ColorSequence.new(pick(palette, refs[1]))
	end
	local points = table.create(#refs)
	for index, ref in refs do
		points[index] = ColorSequenceKeypoint.new((index - 1) / (#refs - 1), pick(palette, ref))
	end
	return ColorSequence.new(points)
end

local function reversed(list)
	local out = table.create(#list)
	for index, value in list do
		out[#list - index + 1] = value
	end
	return out
end

local function curve(points, map: (number) -> number): NumberSequence
	local keys = table.create(#points)
	for index, point in points do
		keys[index] = NumberSequenceKeypoint.new(point[1], map(point[2]))
	end
	return NumberSequence.new(keys)
end

local function attachment(parent: Instance, name: string, position: Vector3?): Attachment
	local item = Instance.new("Attachment")
	item.Name = name
	if position then
		item.Position = position
	end
	item.Parent = parent
	return item
end

-- Aura de un arma sin entrada en WeaponAuraDefs (una nueva): sale de su color y crece con su rareza.
local function generic(def, tier: number)
	local _, saturation = def.color:ToHSV()
	-- Un arma gris o blanca no tiene tono propio: se usa el de su rareza.
	local main = if saturation < 0.2 then Config.RarityTiers[tier].color else def.color
	local layers: { any } = { { "glints" }, { "motes" } }
	local spec = { main = main, second = shift(main, 0.09), layers = layers, light = nil :: any }
	if tier >= 5 then
		table.insert(layers, { "orbit", path = "helix", count = math.min(tier - 4, 3), radius = 1.3, speed = 5, trail = 0.5 })
		spec.light = { range = 9, brightness = 0.7 }
	end
	if tier >= 6 then
		table.insert(layers, { "stars", burst = 10 })
		table.insert(layers, { "motes", at = "player", rate = 6, accel = Vector3.new(0, 2.5, 0) })
	end
	if tier >= 7 then
		table.insert(layers, { "glow" })
		table.insert(layers, { "groundring", at = "feet" })
	end
	return spec
end

-- Caja invisible que sigue al personaje: de ella salen las partículas "del jugador". Vive dentro de la hoja.
local function body(state): Part
	if state.body then
		return state.body
	end
	local part = Instance.new("Part")
	part.Name = "AuraBody"
	part.Size = BODY
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.new(state.blade.Position)
	attachment(part, "Feet", Vector3.new(0, -BODY.Y / 2 + 0.2, 0))
	attachment(part, "Head", Vector3.new(0, BODY.Y / 2 + 0.5, 0))
	part.Parent = state.blade
	state.body = part
	return part
end

local function spot(state, at: string?): Instance
	if at == "player" then
		return body(state)
	elseif at == "feet" or at == "head" then
		return body(state):FindFirstChild(if at == "feet" then "Feet" else "Head") :: Instance
	elseif at == "tip" then
		state.tip = state.tip or attachment(state.blade, "AuraTip", Vector3.new(0, state.half, 0))
		return state.tip
	end
	return state.blade
end

local function emitter(parent: Instance, spec, palette, k): ParticleEmitter
	local item = Instance.new("ParticleEmitter")
	item.Name = "Aura_" .. spec[1]
	item.Texture = spec.tex
	item.Color = gradient(palette, spec.colors)
	item.Rate = spec.rate * k.rate
	item.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	item.Speed = NumberRange.new(spec.speed[1] * k.speed, spec.speed[2] * k.speed)
	item.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	item.Size = curve(GROW[spec.grow], function(value)
		return value * spec.size * k.size
	end)
	local solid = spec.transparency or 0
	item.Transparency = curve(ALPHA[spec.alpha], function(value)
		return solid + value * (1 - solid)
	end)
	item.Acceleration = (spec.accel or Vector3.zero) * k.speed
	item.Drag = spec.drag or 0
	if spec.spin ~= false then
		item.Rotation = NumberRange.new(0, 360)
	end
	if spec.rot then
		item.RotSpeed = NumberRange.new(-spec.rot, spec.rot)
	end
	item.LightEmission = spec.emission or 0.6 -- con 1 los colores se queman a blanco a plena luz
	item.LightInfluence = if spec.lit then 1 else 0
	item.Brightness = spec.bright or 1
	item.LockedToPart = spec.locked == true
	item.ZOffset = spec.z or 0
	if spec.orient == "velocity" then
		item.Orientation = Enum.ParticleOrientation.VelocityParallel
	elseif spec.orient == "flat" then
		item.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
	if spec.squash then
		item.Squash = NumberSequence.new(spec.squash)
	end
	if spec.dir then
		item.EmissionDirection = (Enum.NormalId :: any)[spec.dir]
	end
	if spec.shape then
		item.Shape = (Enum.ParticleEmitterShape :: any)[spec.shape]
		item.ShapeStyle = if spec.surface then Enum.ParticleEmitterShapeStyle.Surface else Enum.ParticleEmitterShapeStyle.Volume
	end
	item.Parent = parent
	return item
end

-- Capa de partículas: el tipo de WeaponAuraDefs.particles con lo que la capa le cambie.
local function addParticles(state, layer, onPlayer: boolean, parent: Instance?)
	local preset = Defs.particles[layer[1]]
	if not preset then
		warn(`WeaponAura: no existe el tipo de partícula "{layer[1]}"`)
		return
	end
	local spec = table.clone(preset)
	for key, value in layer do
		spec[key] = value
	end
	local item = emitter(parent or spot(state, layer.at), spec, state.palette, if onPlayer then state.onPlayer else state.onBlade)
	if spec.burst then
		table.insert(state.bursts, { emitter = item, count = spec.burst })
	end
end

-- Puntos que giran alrededor de la hoja o del jugador; cada uno puede llevar bola de luz, estela y partículas.
local function addOrbit(state, layer, onPlayer: boolean)
	local parent = if onPlayer then body(state) else state.blade
	local k = if onPlayer then state.onPlayer else state.onBlade
	local count = layer.count or 1
	local path = layer.path or "circle"
	local refs = layer.colors or { "white", "main" }
	local extend = (layer.extend or 0) * k.size
	for index = 1, count do
		local turn = (index - 1) / count
		local a = attachment(parent, "AuraOrbit")
		local orbiter = {
			a = a,
			b = nil :: Attachment?,
			width = 0,
			path = path,
			radius = (layer.radius or 1.5) * k.size,
			speed = layer.speed or 3,
			phase = turn * math.pi * 2,
			center = Vector3.new(0, if onPlayer then layer.height or 0 else (layer.height or 0) * state.half - (if path == "helix" then extend / 2 else 0), 0),
			tilt = CFrame.Angles(math.rad(layer.tilt or 0), 0, 0),
			bob = layer.bob or 0,
			rise = layer.rise or 1.7,
			span = state.half + extend / 2,
		}
		if path == "infinity" then
			orbiter.tilt = if onPlayer then CFrame.identity else FLAT_ON_BLADE
		elseif path == "atom" then
			orbiter.tilt = CFrame.Angles(0, turn * math.pi, 0) * CFrame.Angles(math.rad(layer.tilt or 60), 0, 0)
		end

		if layer.trail then
			local b = attachment(parent, "AuraOrbitEdge")
			local trail = Instance.new("Trail")
			trail.Name = "AuraTrail"
			trail.Attachment0 = a
			trail.Attachment1 = b
			trail.Color = gradient(state.palette, if index % 2 == 0 then reversed(refs) else refs)
			local solid = layer.transparency or 0
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, solid),
				NumberSequenceKeypoint.new(0.5, solid + (1 - solid) * 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.WidthScale = NumberSequence.new(1, 0.15)
			trail.Lifetime = layer.trailLife or 0.6
			trail.MinLength = 0.03
			trail.LightEmission = RIBBON_EMISSION
			trail.LightInfluence = 0
			trail.Brightness = RIBBON_BRIGHTNESS
			trail.FaceCamera = true
			trail.Parent = parent
			orbiter.b = b
			orbiter.width = layer.trail * k.size
			if not onPlayer then
				table.insert(state.trails, trail)
			end
		end
		if layer.orb then
			addParticles(state, { "orb", size = layer.orb, colors = refs }, onPlayer, a)
		end
		if layer.emit then
			addParticles(state, layer.emit, onPlayer, a)
		end
		table.insert(state.orbiters, orbiter)
	end
end

-- Aro de luz: dos curvas (medio círculo cada una) entre dos puntos opuestos, que giran con él.
local function addRing(state, layer, onPlayer: boolean)
	local parent = if onPlayer then body(state) else state.blade
	local k = if onPlayer then state.onPlayer else state.onBlade
	local radius = (layer.radius or 1.5) * k.size
	local center
	if layer.at == "head" then
		center = Vector3.new(0, BODY.Y / 2 + 0.5, 0)
	elseif layer.at == "feet" then
		center = Vector3.new(0, -BODY.Y / 2 + 0.25, 0)
	elseif onPlayer then
		center = Vector3.new(0, layer.height or 0, 0)
	else
		center = Vector3.new(0, (layer.height or 0) * state.half, 0)
	end

	local a0 = attachment(parent, "AuraRingA")
	local a1 = attachment(parent, "AuraRingB")
	local reach = radius * 4 / 3 -- con esta curvatura cada mitad es casi un semicírculo
	local colors = gradient(state.palette, layer.colors or { "white", "main" })
	for half = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Name = "AuraRing"
		beam.Attachment0 = if half == 1 then a0 else a1
		beam.Attachment1 = if half == 1 then a1 else a0
		beam.CurveSize0 = if half == 1 then reach else -reach
		beam.CurveSize1 = if half == 1 then -reach else reach
		beam.Segments = 20
		beam.Width0 = (layer.width or 0.14) * k.size
		beam.Width1 = beam.Width0
		beam.FaceCamera = true
		beam.Color = colors
		beam.Transparency = if layer.arcs == false then NumberSequence.new(0.2) else ARC
		beam.LightEmission = RIBBON_EMISSION
		beam.LightInfluence = 0
		beam.Brightness = RIBBON_BRIGHTNESS
		beam.Parent = parent
	end
	table.insert(state.rings, {
		a0 = a0,
		a1 = a1,
		out0 = CFrame.new(radius, 0, 0) * TANGENT,
		out1 = CFrame.new(-radius, 0, 0) * TANGENT,
		center = CFrame.new(center),
		tilt = CFrame.Angles(math.rad(layer.tilt or 0), 0, 0),
		spin = layer.spin or 1,
		precess = layer.precess or 0,
	})
end

-- Rayos: una línea quebrada de tramos rectos que cambia de forma varias veces por segundo.
local function addBolts(state, layer)
	local blade = state.blade
	local k = state.onBlade
	local refs = layer.colors or { "white", "main" }
	local from, to = pick(state.palette, refs[1]), pick(state.palette, refs[#refs])
	local width = (layer.width or 0.22) * k.size
	for _ = 1, layer.count or 1 do
		local points = table.create(BOLT_POINTS)
		for index = 1, BOLT_POINTS do
			points[index] = attachment(blade, "AuraBoltPoint")
		end
		local beams = table.create(BOLT_POINTS - 1)
		for index = 1, BOLT_POINTS - 1 do
			local beam = Instance.new("Beam")
			beam.Name = "AuraBolt"
			beam.Attachment0 = points[index]
			beam.Attachment1 = points[index + 1]
			beam.Segments = 1
			beam.Width0 = width
			beam.Width1 = width
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(from:Lerp(to, (index - 1) / (BOLT_POINTS - 1)), from:Lerp(to, index / (BOLT_POINTS - 1)))
			beam.Transparency = NumberSequence.new(0)
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = BOLT_BRIGHTNESS
			beam.Parent = blade
			beams[index] = beam
		end
		table.insert(state.bolts, {
			points = points,
			beams = beams,
			crawl = layer.mode == "crawl",
			reach = (layer.reach or 1.5) * k.size,
			extend = (layer.extend or 0) * k.size,
			on = layer.on or 0.7,
			next = 0,
		})
	end
end

local function reshape(state, bolt, now: number)
	bolt.next = now + random:NextNumber(0.05, 0.13)
	local visible = random:NextNumber() < bolt.on
	for _, beam in bolt.beams do
		beam.Enabled = visible
	end
	if not visible then
		return
	end
	local from, to, jitter
	if bolt.crawl then
		-- Recorre un trozo de la hoja (y del asta, con `extend`), serpenteando a su alrededor.
		local bottom = -state.half - bolt.extend
		local length = state.half - bottom
		local start = bottom + random:NextNumber(0, 0.5) * length
		from = Vector3.new(0, start, 0)
		to = Vector3.new(0, math.min(state.half, start + random:NextNumber(0.35, 0.6) * length), 0)
		jitter = bolt.reach
	else
		-- Salta de la superficie de la hoja hacia fuera (desde dentro, la cabeza de un martillo lo taparía).
		local half = state.blade.Size / 2
		local out = random:NextUnitVector()
		from = out / math.max(math.abs(out.X) / half.X, math.abs(out.Y) / half.Y, math.abs(out.Z) / half.Z)
		to = from + (out + random:NextUnitVector() * 0.5).Unit * bolt.reach * random:NextNumber(0.6, 1)
		jitter = bolt.reach * 0.22
	end
	for index, point in bolt.points do
		local position = from:Lerp(to, (index - 1) / (BOLT_POINTS - 1))
		if index > 1 then
			position += random:NextUnitVector() * jitter * random:NextNumber(0.3, 1)
		end
		point.Position = position
	end
end

local function addLight(state, spec, scale: number)
	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = pick(state.palette, spec.color or "main")
	light.Range = math.min((spec.range or 10) * math.sqrt(scale), 24)
	light.Brightness = spec.brightness or 1
	light.Shadows = false
	light.Parent = state.blade
	state.light = light
	state.lightSpec = spec
end

-- Ráfaga al atacar y al sacar el arma: las capas con `burst` sueltan partículas de golpe y la luz da un fogonazo.
local function burst(state, strength: number)
	if Performance.get() then
		return
	end
	for _, entry in state.bursts do
		entry.emitter:Emit(math.ceil(entry.count * strength))
	end
	state.flash = os.clock() + FLASH
end

-- Empieza o acaba un tajo. Mientras dura, las estelas de lo que gira en la hoja se apagan: la hoja va tan deprisa
-- que dibujarían rectas enormes por toda la pantalla (visto en Studio). Las del jugador siguen.
local function swing(state, on: boolean)
	for _, trail in state.trails do
		if on then
			trail:Clear()
		end
		trail.Enabled = not on
	end
	if on then
		burst(state, 1)
	end
end

local function build(blade: BasePart)
	local def = Config.Swords[blade:GetAttribute("Level")]
	if not def or auras[blade] or not blade:HasTag(TAG) then
		return
	end
	-- Las armas de las vistas 3D y las de las tiradas (escaladas con ScaleTo) no llevan aura.
	local model = blade:FindFirstAncestorWhichIsA("Model")
	if blade:FindFirstAncestorWhichIsA("ViewportFrame") or (model and math.abs(model:GetScale() - 1) > 0.01) then
		return
	end
	local tier = tierIndex(def.rarity)
	local spec = Defs.weapons[blade:GetAttribute("Level")] or (if tier >= Defs.FROM_TIER then generic(def, tier) else nil)
	if not spec then
		return
	end

	local scale = blade:GetAttribute("Scale") or 1
	local rate = (spec.intensity or 1) * (Defs.TIER_RATE[tier] or 1)
	-- En una hoja pequeña (la punta de una lanza) las mismas partículas se amontonan: lleva menos.
	local crowd = math.clamp(math.max(blade.Size.Y, blade.Size.Z) / (FULL_BLADE * scale), 0.55, 1)
	local main = spec.main
	local state = {
		blade = blade,
		half = blade.Size.Y / 2,
		palette = {
			white = WHITE,
			main = main,
			second = spec.second or shift(main, 0.09),
			accent = spec.accent or main:Lerp(WHITE, 0.5),
			pale = main:Lerp(WHITE, 0.6),
			dark = SMOKE_GRAY,
		},
		-- Multiplicadores de cantidad, tamaño y velocidad: en el arma cuentan su tamaño (Grande, Gigante...).
		onBlade = { rate = rate * crowd * (if def.kind == "dual" then DUAL_RATE else 1), size = scale * (spec.size or 1), speed = scale * (spec.speed or 1) },
		onPlayer = { rate = rate, size = spec.size or 1, speed = spec.speed or 1 },
		orbiters = {},
		rings = {},
		bolts = {},
		bursts = {},
		trails = {},
		body = nil :: Part?,
		tip = nil :: Attachment?,
		light = nil :: PointLight?,
		lightSpec = nil :: any,
		seed = random:NextNumber(0, 100),
		flash = 0,
	}

	-- Lo del jugador solo con el arma en la mano, y una vez (en las dobles lo pone la hoja principal).
	local worn = not blade.Anchored and not (blade.Parent and blade.Parent.Name == "OffHand")
	for _, layer in spec.layers do
		local onPlayer = PLAYER_SPOTS[layer.at] == true
		if onPlayer and not worn then
			continue
		end
		local kind = layer[1]
		if kind == "orbit" then
			addOrbit(state, layer, onPlayer)
		elseif kind == "ring" then
			addRing(state, layer, onPlayer)
		elseif kind == "bolts" then
			addBolts(state, layer)
		else
			addParticles(state, layer, onPlayer)
		end
	end
	if spec.light then
		addLight(state, spec.light, scale)
	end
	auras[blade] = state

	if not blade.Anchored then
		-- La estela del tajo la enciende SwingAnim mientras dura el golpe: con ella se sabe que se está atacando.
		task.spawn(function()
			local trail = blade:WaitForChild("SwingTrail", 10) :: Trail?
			if trail and auras[blade] == state then
				trail:GetPropertyChangedSignal("Enabled"):Connect(function()
					swing(state, trail.Enabled)
				end)
			end
		end)
		task.delay(0.3, function()
			if auras[blade] == state and blade:IsDescendantOf(workspace) then
				burst(state, 1.5)
			end
		end)
	end
end

-- Centro del personaje que lleva el arma y lo que hay de él al suelo.
local function wearer(blade: BasePart): (BasePart?, number)
	local model = blade.Parent
	for _ = 1, 3 do
		if not model then
			break
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local root = humanoid.RootPart
			return root, if root then humanoid.HipHeight + root.Size.Y / 2 else 0
		end
		model = model.Parent
	end
	return nil, 0
end

local function orbit(orbiter, now: number)
	local angle = now * orbiter.speed + orbiter.phase
	local radius = orbiter.radius
	local path = orbiter.path
	local point
	if path == "infinity" then
		local sin, cos = math.sin(angle), math.cos(angle)
		local narrow = radius / (1 + sin * sin)
		point = Vector3.new(narrow * cos, 0, narrow * sin * cos)
	else
		local y = 0
		if path == "helix" then
			y = math.sin(now * orbiter.rise + orbiter.phase) * orbiter.span
		elseif path == "spiral" then
			radius *= 0.2 + 0.8 * math.abs(math.sin(now * 0.9 + orbiter.phase))
		end
		if orbiter.bob ~= 0 then
			y += math.sin(now * 1.3 + orbiter.phase * 1.7) * orbiter.bob
		end
		point = Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
	end
	local position = orbiter.center + orbiter.tilt * point
	orbiter.a.Position = position
	if orbiter.b then
		orbiter.b.Position = position + Vector3.new(0, orbiter.width, 0)
	end
end

local function step()
	if Performance.get() then return end -- modo rendimiento
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for blade, state in auras do
		if not blade:IsDescendantOf(workspace) then
			continue
		end
		if state.body then
			local root, ground = wearer(blade)
			if root then
				local _, yaw = root.CFrame:ToOrientation()
				state.body.CFrame = CFrame.new(root.Position + Vector3.new(0, BODY.Y / 2 - ground, 0)) * CFrame.Angles(0, yaw, 0)
			end
		end
		if (blade.Position - eye).Magnitude > FAR then
			continue
		end
		for _, orbiter in state.orbiters do
			orbit(orbiter, now)
		end
		for _, ring in state.rings do
			local frame = ring.center * CFrame.Angles(0, now * ring.precess, 0) * ring.tilt * CFrame.Angles(0, now * ring.spin, 0)
			ring.a0.CFrame = frame * ring.out0
			ring.a1.CFrame = frame * ring.out1
		end
		for _, bolt in state.bolts do
			if now >= bolt.next then
				reshape(state, bolt, now)
			end
		end
		if state.light then
			local spec = state.lightSpec
			local level = spec.brightness or 1
			if spec.flicker then
				level *= 0.55 + 1.5 * math.abs(math.noise(now * 9, state.seed))
			elseif spec.pulse then
				level *= 1 + 0.25 * math.sin((now * spec.pulse + state.seed) * math.pi * 2)
			end
			if now < state.flash then
				level *= 1.8
			end
			state.light.Brightness = level
		end
	end
end

local function watch(blade: Instance)
	if not blade:IsA("BasePart") then
		return
	end
	if blade:GetAttribute("Level") then
		build(blade)
	else
		blade:GetAttributeChangedSignal("Level"):Once(function()
			build(blade)
		end)
	end
end

function WeaponAura.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(blade)
		auras[blade] = nil
	end)
	for _, blade in CollectionService:GetTagged(TAG) do
		watch(blade)
	end
	RunService.RenderStepped:Connect(step)
end

return WeaponAura
