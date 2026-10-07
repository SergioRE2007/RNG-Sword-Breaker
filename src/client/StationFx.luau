-- Vida de las estaciones del hub (Forja de Grados, Mesa de encantamiento de Rasgos) y de los
-- vendedores de los puestos. El servidor (server/Stations, StallSkin) coloca las piezas y las
-- etiqueta; aquí se les ponen luces y partículas y se mueven, solo en este cliente y solo si
-- están cerca de la cámara. Etiquetas: StationFire, StationSmoke, StationSteam, StationHotMetal,
-- StationHammer, StationGlow, StationPulse, StationSpin, StationFloat, StationOrbit, StationMotes
-- y StationSeller. El modo rendimiento quita luces y partículas (Performance) y aquí se para
-- también el movimiento.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Performance = require(script.Parent.Performance)
local DayCycle = require(script.Parent.DayCycle)

local StationFx = {}

local VIEW = 170 -- más lejos de la cámara que esto, no se anima
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local random = Random.new()

type Entry = { origin: Vector3, update: (number, number) -> (), near: ((boolean) -> ())?, wasNear: boolean? }
local entries: { [Entry]: boolean } = {}
local done: { [Instance]: { [string]: boolean } } = {} -- etiquetas ya preparadas en cada pieza
local lastHit = -10 -- cuándo cayó el último martillazo (hace brillar el metal)

local function originOf(item: Instance): Vector3
	if item:IsA("Model") then
		return item:GetPivot().Position
	end
	return (item :: BasePart).Position
end

local function register(item: Instance, update: (number, number) -> (), near: ((boolean) -> ())?)
	local entry: Entry = { origin = originOf(item), update = update, near = near }
	entries[entry] = true
	item.Destroying:Connect(function()
		entries[entry] = nil
		done[item] = nil
	end)
end

local function sequence(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		table.insert(colors, colors[1])
	end
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / math.max(#colors - 1, 1), color))
	end
	return ColorSequence.new(keys)
end

local function emitter(parent: Instance, texture: string): ParticleEmitter
	local item = Instance.new("ParticleEmitter")
	item.Texture = texture
	item.LightEmission = 1
	item.Parent = parent
	return item
end

-- Pieza invisible local para colgar partículas en un punto del mundo.
local function emitterPart(position: Vector3, parent: Instance): Part
	local item = Instance.new("Part")
	item.Anchored = true
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Transparency = 1
	item.Size = Vector3.new(0.4, 0.4, 0.4)
	item.Position = position
	item.Parent = parent
	return item
end

-- Luz que late (o parpadea como una llama) con el color de la pieza.
local function setupGlow(part: BasePart)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = part:GetAttribute("Range") or 10
	local level = part:GetAttribute("Light") or 1
	light.Brightness = 0
	light.Enabled = false
	light.Shadows = false
	light.Parent = part
	local flicker = part:GetAttribute("Flicker") == true
	local seed = random:NextNumber(0, 100)
	register(part, function(now)
		local night = DayCycle.night()
		if flicker then
			light.Brightness = level * (0.8 + 0.4 * math.noise(now * 5, seed)) * night
		else
			light.Brightness = level * (0.85 + 0.15 * math.sin(now * 2 + seed)) * night
		end
		light.Enabled = night > 0
	end, function(isNear)
		light.Enabled = isNear and DayCycle.night() > 0 and not Performance.get()
	end)
end

-- Boca del horno: llamas, brasas, luz anaranjada y el neón que parpadea.
local function setupFire(part: BasePart)
	local flames = emitter(part, FIRE_TEXTURE)
	flames.Shape = Enum.ParticleEmitterShape.Box
	flames.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Rate = 40
	flames.Lifetime = NumberRange.new(0.5, 0.9)
	flames.Speed = NumberRange.new(2, 4)
	flames.SpreadAngle = Vector2.new(12, 12)
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	flames.Color = sequence(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 120, 30), Color3.fromRGB(200, 40, 20))
	flames.Rotation = NumberRange.new(-20, 20)
	local embers = emitter(part, SPARK_TEXTURE)
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.EmissionDirection = Enum.NormalId.Front
	embers.Rate = 9
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(35, 35)
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = sequence(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 26
	light.Shadows = false
	light.Parent = part
	local hot, cool = Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 100, 25)
	register(part, function(now)
		local wobble = math.noise(now * 6, 3) * 0.5 + 0.5
		local night = DayCycle.night()
		light.Brightness = (1.6 + wobble * 1.4) * night
		light.Enabled = night > 0
		part.Color = cool:Lerp(hot, wobble)
	end, function(isNear)
		flames.Enabled = isNear
		embers.Enabled = isNear
		light.Enabled = isNear and DayCycle.night() > 0 and not Performance.get()
	end)
end

-- Humo (chimenea) y vapor (barril de agua).
local function setupSmoke(part: BasePart, steam: boolean)
	local attachment = Instance.new("Attachment")
	if steam then
		-- El agua es un cilindro tumbado: su eje es X, así que el punto sale por ahí y se gira.
		attachment.CFrame = CFrame.new(part.Size.X / 2 + 0.1, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2)
	else
		attachment.Position = Vector3.new(0, part.Size.Y / 2 + 0.3, 0)
	end
	attachment.Parent = part
	local puffs = emitter(attachment, SMOKE_TEXTURE)
	puffs.LightEmission = if steam then 0.4 else 0
	puffs.Rate = if steam then 5 else 14
	puffs.Lifetime = NumberRange.new(if steam then 1.5 else 3, if steam then 2.5 else 4.5)
	puffs.Speed = NumberRange.new(if steam then 1 else 3, if steam then 2 else 5)
	puffs.SpreadAngle = Vector2.new(15, 15)
	puffs.Acceleration = Vector3.new(0.6, 0.5, 0.3)
	puffs.RotSpeed = NumberRange.new(-20, 20)
	local top = if steam then 2.6 else 7
	puffs.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, top) })
	puffs.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	puffs.Color = if steam then sequence(Color3.fromRGB(235, 245, 255)) else sequence(Color3.fromRGB(95, 92, 100), Color3.fromRGB(60, 58, 64))
	register(part, function() end, function(isNear)
		puffs.Enabled = isNear
	end)
end

-- Metal al rojo: late y se enciende de golpe con cada martillazo.
local function setupHotMetal(part: BasePart)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Range = 9
	light.Shadows = false
	light.Parent = part
	local cool, hot = Color3.fromRGB(235, 80, 25), Color3.fromRGB(255, 200, 110)
	register(part, function(now)
		local flash = math.clamp(1 - (now - lastHit) / 0.35, 0, 1)
		local beat = (math.sin(now * 3) + 1) / 2
		part.Color = cool:Lerp(hot, math.max(flash, beat * 0.35))
		local night = DayCycle.night()
		light.Brightness = (0.8 + beat * 0.5 + flash * 2.5) * night
		light.Enabled = night > 0
	end, function(isNear)
		light.Enabled = isNear and DayCycle.night() > 0 and not Performance.get()
	end)
end

-- Martillo: sube despacio, se queda un momento arriba y cae; al golpear saltan chispas.
local function setupHammer(model: Model)
	-- El pivote del modelo no llega bien al cliente: se gira cada pieza alrededor de la pieza "Eje".
	local axis = model:WaitForChild("Eje", 10) :: BasePart?
	if not axis then
		return
	end
	local pivot = axis.CFrame
	local original: { [BasePart]: CFrame } = {}
	for _, item in model:GetChildren() do
		if item:IsA("BasePart") then
			original[item] = item.CFrame
		end
	end
	local function pose(angle: number)
		local turn = pivot * CFrame.Angles(angle, 0, 0) * pivot:Inverse()
		for part, cframe in original do
			part.CFrame = turn * cframe
		end
	end
	local hit = model:GetAttribute("Hit") :: Vector3
	local holder = emitterPart(hit, model)
	local sparks = emitter(holder, SPARK_TEXTURE)
	sparks.Enabled = false
	sparks.Lifetime = NumberRange.new(0.35, 0.8)
	sparks.Speed = NumberRange.new(10, 22)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -45, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = sequence(Color3.fromRGB(255, 245, 190), Color3.fromRGB(255, 140, 40))
	local REST, UP, STRIKE = math.rad(14), math.rad(-25), math.rad(90)
	local PERIOD = 2.1
	local previous = 0
	register(axis, function(now)
		local phase = (now % PERIOD) / PERIOD
		local angle
		if phase < 0.5 then
			local t = phase / 0.5
			angle = STRIKE + (UP - STRIKE) * (t * t * (3 - 2 * t)) -- sube suave
		elseif phase < 0.72 then
			angle = UP + math.sin(now * 14) * math.rad(0.8) -- aguanta arriba
		elseif phase < 0.8 then
			local t = (phase - 0.72) / 0.08
			angle = UP + (STRIKE - UP) * (t * t) -- cae rápido
		else
			angle = STRIKE + math.sin((phase - 0.8) * 30) * math.rad(3) * (1 - (phase - 0.8) / 0.2) -- rebote
		end
		pose(angle)
		if previous < 0.8 and phase >= 0.8 then
			lastHit = now
			sparks:Emit(random:NextInteger(14, 22))
		end
		previous = phase
	end, function(isNear)
		if not isNear then
			previous = 0
		end
	end)
	-- Quieto en reposo por si está lejos.
	pose(REST)
end

-- Pulso de brillo (Transparency) de un neón.
local function setupPulse(part: BasePart)
	local speed = part:GetAttribute("Speed") or 2
	local seed = random:NextNumber(0, 6)
	register(part, function(now)
		part.Transparency = 0.25 + 0.4 * (math.sin(now * speed + seed) + 1) / 2
	end)
end

local function setupSpin(item: Instance)
	local speed = item:GetAttribute("Speed") or 0.5
	if item:IsA("Model") then
		local base = item:GetPivot()
		register(item, function(now)
			item:PivotTo(base * CFrame.Angles(0, now * speed, 0))
		end)
	end
end

-- Flota arriba y abajo y gira (el libro, los orbes).
local function setupFloat(item: Instance)
	local height = item:GetAttribute("BobHeight") or 0.4
	local speed = item:GetAttribute("BobSpeed") or 1.5
	local spin = item:GetAttribute("SpinSpeed") or 0
	local phase = item:GetAttribute("Phase") or 0
	if item:IsA("Model") then
		local base = item:GetPivot()
		register(item, function(now)
			item:PivotTo(base * CFrame.new(0, math.sin(now * speed + phase) * height, 0) * CFrame.Angles(0, now * spin, 0))
		end)
	else
		local part = item :: BasePart
		local base = part.CFrame
		register(part, function(now)
			part.CFrame = base * CFrame.new(0, math.sin(now * speed + phase) * height, 0) * CFrame.Angles(0, now * spin, 0)
		end)
	end
end

-- Cristal que da vueltas alrededor de un punto.
local function setupOrbit(part: BasePart)
	local center = part:GetAttribute("Center") :: Vector3
	local radius = part:GetAttribute("Radius") or 4
	local speed = part:GetAttribute("Speed") or 1
	local phase = part:GetAttribute("Phase") or 0
	local height = part:GetAttribute("Height") or center.Y
	local tilt = CFrame.Angles(math.rad(45), 0, math.rad(45))
	register(part, function(now)
		local angle = now * speed + phase
		local position = Vector3.new(center.X + math.cos(angle) * radius, height + math.sin(now * 1.3 + phase) * 0.4, center.Z + math.sin(angle) * radius)
		part.CFrame = CFrame.new(position) * CFrame.Angles(now * 1.2, now * 1.7, 0) * tilt
	end)
end

-- Chispitas mágicas que suben flotando.
local function setupMotes(part: BasePart)
	local color = part:GetAttribute("Color") or Color3.fromRGB(190, 150, 255)
	local motes = emitter(part, SPARK_TEXTURE)
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.Rate = part:GetAttribute("Rate") or 8
	motes.Lifetime = NumberRange.new(1.6, 2.8)
	motes.Speed = NumberRange.new(0.5, 2)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 1.8, 0)
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
	motes.Color = sequence(color, Color3.new(1, 1, 1), color)
	motes.RotSpeed = NumberRange.new(-60, 60)
	register(part, function() end, function(isNear)
		motes.Enabled = isNear
	end)
end

-- Vendedor vivo: respira, mira a un lado y a otro, mueve la cabeza y los brazos un poco.
local function setupSeller(model: Model)
	-- El modelo llega por piezas: esperar a las principales y un momento a las demás.
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local head = model:WaitForChild("Head", 10) :: BasePart?
	if not root or not head or not model:WaitForChild("RightFoot", 10) then
		return
	end
	task.wait(1)
	local frame = root.CFrame.Rotation
	local original: { [BasePart]: CFrame } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			original[item] = item.CFrame
		end
	end
	local function attachment(part: Instance?, name: string): Vector3?
		local found = part and part:FindFirstChild(name)
		return if found and found:IsA("Attachment") then found.WorldPosition else nil
	end
	local neck = attachment(head, "NeckRigAttachment") or head.Position - Vector3.new(0, 0.6, 0)
	local shoulders = {
		right = attachment(model:FindFirstChild("RightUpperArm"), "RightShoulderRigAttachment"),
		left = attachment(model:FindFirstChild("LeftUpperArm"), "LeftShoulderRigAttachment"),
	}
	-- Grupos que se mueven juntos.
	local headGroup: { BasePart } = { head }
	local arms = { right = {}, left = {} }
	for _, name in { "RightUpperArm", "RightLowerArm", "RightHand" } do
		local part = model:FindFirstChild(name)
		if part then
			table.insert(arms.right, part)
		end
	end
	for _, name in { "LeftUpperArm", "LeftLowerArm", "LeftHand" } do
		local part = model:FindFirstChild(name)
		if part then
			table.insert(arms.left, part)
		end
	end
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") and (handle:FindFirstChild("HairAttachment") or handle:FindFirstChild("HatAttachment") or handle:FindFirstChild("FaceFrontAttachment")) then
			table.insert(headGroup, handle)
		end
	end
	local function around(point: Vector3, rotation: CFrame): CFrame
		local pivot = CFrame.new(point) * frame
		return pivot * rotation * pivot:Inverse()
	end
	local seed = random:NextNumber(0, 50)
	local rootPosition = root.Position
	local still = {}
	for part in original do
		still[part] = true
	end
	for _, part in headGroup do
		still[part] = nil
	end
	for _, group in arms do
		for _, part in group do
			still[part] = nil
		end
	end
	register(model, function(now)
		local t = now + seed
		local breathe = math.sin(t * 1.7) * 0.06
		local sway = around(rootPosition, CFrame.Angles(0, math.sin(t * 0.5) * math.rad(5), math.sin(t * 0.8) * math.rad(1.2)))
		local whole = CFrame.new(0, breathe, 0) * sway
		-- Cada cierto tiempo mira de lado un momento.
		local glance = math.max(0, math.sin(t * 0.37)) ^ 6 * math.rad(40) * (if math.sin(t * 0.19) > 0 then 1 else -1)
		local look = around(neck, CFrame.Angles(math.sin(t * 1.1) * math.rad(4), math.sin(t * 0.7) * math.rad(14) + glance, 0))
		for part in still do
			part.CFrame = whole * original[part]
		end
		for _, part in headGroup do
			part.CFrame = whole * look * original[part]
		end
		for side, group in arms do
			local shoulder = shoulders[side]
			local sign = if side == "right" then 1 else -1
			local swing = if shoulder then around(shoulder, CFrame.Angles(math.sin(t * 1.3 + sign) * math.rad(7), 0, sign * (math.rad(3) + math.sin(t * 1.7) * math.rad(3)))) else CFrame.identity
			for _, part in group do
				part.CFrame = whole * swing * original[part]
			end
		end
	end)
end

local SETUP: { [string]: (any) -> () } = {
	StationGlow = setupGlow,
	StationFire = setupFire,
	StationSmoke = function(part)
		setupSmoke(part, false)
	end,
	StationSteam = function(part)
		setupSmoke(part, true)
	end,
	StationHotMetal = setupHotMetal,
	StationHammer = setupHammer,
	StationPulse = setupPulse,
	StationSpin = setupSpin,
	StationFloat = setupFloat,
	StationOrbit = setupOrbit,
	StationMotes = setupMotes,
	StationSeller = setupSeller,
}

function StationFx.start()
	for name, setup in SETUP do
		local function add(item: Instance)
			-- Puede llegar antes de que estén sus piezas hijas (vendedor, martillo): cada preparación va aparte.
			task.spawn(function()
				task.wait()
				local tags = done[item]
				if item.Parent and not (tags and tags[name]) then
					done[item] = tags or {}
					done[item][name] = true
					setup(item)
				end
			end)
		end
		for _, item in CollectionService:GetTagged(name) do
			add(item)
		end
		CollectionService:GetInstanceAddedSignal(name):Connect(add)
	end

	RunService.RenderStepped:Connect(function(delta)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		local eye = camera.CFrame.Position
		local still = Performance.get()
		for entry in entries do
			local isNear = (entry.origin - eye).Magnitude < VIEW
			if entry.near and entry.wasNear ~= isNear then
				entry.wasNear = isNear
				entry.near(isNear)
			end
			if isNear and not still then
				entry.update(now, delta)
			end
		end
	end)
end

return StationFx
