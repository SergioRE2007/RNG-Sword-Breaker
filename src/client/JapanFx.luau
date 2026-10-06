-- Vida del mapa japonés (Config.Theme = "japan"): pétalos de cerezo que caen siempre alrededor de la cámara, motas
-- doradas que flotan, farolillos y linternas que laten con su luz y carpas que nadan en círculos por los estanques.
-- Todo es solo de este cliente; el modo rendimiento (Performance) apaga las partículas y luces y para las animaciones.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Performance = require(script.Parent.Performance)

local JapanFx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local KOI_RANGE = 220
local CRITTER_RANGE = 240

local function emitterPart(name: string): Part
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(170, 1, 170)
	anchor.Parent = workspace
	return anchor
end

local function pink(): ParticleEmitter
	local petals = Instance.new("ParticleEmitter")
	petals.Name = "Petals"
	petals.Texture = SPARKLE
	petals.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 200)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 205, 228)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 130, 180)),
	})
	petals.LightEmission = 0.35
	petals.Shape = Enum.ParticleEmitterShape.Box
	petals.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.Rate = 90
	petals.Lifetime = NumberRange.new(9, 13)
	petals.Speed = NumberRange.new(3, 6)
	petals.Acceleration = Vector3.new(4, 0, 2) -- el viento los arrastra
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-80, 80)
	petals.SpreadAngle = Vector2.new(20, 20)
	petals.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.55) })
	petals.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.1), NumberSequenceKeypoint.new(0.9, 0.1), NumberSequenceKeypoint.new(1, 1) })
	return petals
end

local function motes(): ParticleEmitter
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "Motes"
	glow.Texture = SPARKLE
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140))
	glow.LightEmission = 1
	glow.Shape = Enum.ParticleEmitterShape.Box
	glow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	glow.EmissionDirection = Enum.NormalId.Bottom
	glow.Rate = 26
	glow.Lifetime = NumberRange.new(8, 11)
	glow.Speed = NumberRange.new(0.5, 1.5)
	glow.Acceleration = Vector3.new(0, 0.2, 0)
	glow.SpreadAngle = Vector2.new(60, 60)
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.5) })
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) })
	return glow
end

-- Luciérnagas: motas verdosas que vagan despacio sobre el agua y entre el bambú.
local function fireflies(spot: BasePart)
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "Fireflies"
	glow.Texture = SPARKLE
	glow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 255, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 236, 130)),
	})
	glow.LightEmission = 1
	glow.Shape = Enum.ParticleEmitterShape.Box
	glow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	glow.Rate = math.clamp(spot.Size.X * 0.35, 5, 18)
	glow.Lifetime = NumberRange.new(3, 6)
	glow.Speed = NumberRange.new(0.3, 1.4)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.Acceleration = Vector3.new(0, 0.15, 0)
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0.1) })
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.15), NumberSequenceKeypoint.new(0.75, 0.35), NumberSequenceKeypoint.new(1, 1) })
	glow.Parent = spot
end

-- Humo de incienso: hilo blanco azulado que sube y se deshace.
local function incense(spot: BasePart)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Incense"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(240, 235, 255))
	smoke.LightEmission = 0.2
	smoke.Rate = 3
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.Acceleration = Vector3.new(0.6, 0, 0.3)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	smoke.Parent = spot
end

function JapanFx.start()
	if Config.Theme ~= "japan" then
		return
	end

	-- Una nube de pétalos y motas que acompaña a la cámara: cae desde arriba y se renueva sola.
	local sky = emitterPart("JapanSky")
	pink().Parent = sky
	local low = emitterPart("JapanLow")
	motes().Parent = low

	-- Luciérnagas e incienso donde el servidor puso las marcas.
	for tag, make in { FireflySpot = fireflies, SmokeSpot = incense } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(make)
		for _, item in CollectionService:GetTagged(tag) do
			make(item)
		end
	end

	local koi = {}
	local lamps = {}
	local function track(list: { [Instance]: boolean }, tag: string)
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(item)
			list[item] = true
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(item)
			list[item] = nil
		end)
		for _, item in CollectionService:GetTagged(tag) do
			list[item] = true
		end
	end
	track(koi, "Koi")
	track(lamps, "LanternGlow")

	-- Estado de cada animal (posición, hacia dónde mira y a dónde va); parten de su casa.
	local critters: { [Model]: { pos: Vector3, facing: Vector3, target: Vector3?, wait: number, phase: number } } = {}
	local function addCritter(model: Instance)
		local home = model:GetAttribute("Home")
		if model:IsA("Model") and home then
			local look = model:GetPivot().LookVector
			critters[model] = { pos = home, facing = Vector3.new(look.X, 0, look.Z), target = nil, wait = math.random() * 4, phase = math.random() * 6.28 }
		end
	end
	CollectionService:GetInstanceAddedSignal("Critter"):Connect(function(model)
		task.defer(addCritter, model) -- los atributos llegan con el modelo, pero por si acaso
	end)
	for _, model in CollectionService:GetTagged("Critter") do
		addCritter(model)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position
		sky.CFrame = CFrame.new(position.X, position.Y + 42, position.Z)
		low.CFrame = CFrame.new(position.X, position.Y + 9, position.Z)
		if Performance.get() then
			return
		end
		local now = os.clock()

		for fish in koi do
			local model = fish :: Model
			if model.Parent then
				local center = model:GetAttribute("Center")
				if center and (center - position).Magnitude < KOI_RANGE then
					local angle = now * model:GetAttribute("Speed") + model:GetAttribute("Phase")
					local radius = model:GetAttribute("Radius") + math.sin(now * 0.7 + model:GetAttribute("Phase")) * 1.2
					local spot = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
					local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(model:GetAttribute("Speed"))
					model:PivotTo(CFrame.lookAt(spot, spot + heading) * CFrame.Angles(0, math.sin(now * 5 + angle) * 0.18, 0))
				end
			end
		end

		-- Los animales pasean por su rincón: eligen un punto, andan hasta él dando saltitos, descansan y repiten.
		for model, state in critters do
			if not model.Parent then
				critters[model] = nil
			elseif (state.pos - position).Magnitude < CRITTER_RANGE then
				local home = model:GetAttribute("Home")
				local speed = model:GetAttribute("Speed")
				local hop = 0
				if state.wait > 0 then
					state.wait -= dt
					hop = math.sin(now * 2 + state.phase) * 0.03 -- respira
				else
					if not state.target then
						local angle = math.random() * math.pi * 2
						local distance = math.sqrt(math.random()) * model:GetAttribute("Radius")
						state.target = home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
					end
					local offset = state.target - state.pos
					if offset.Magnitude < 0.5 then
						state.target = nil
						state.wait = 2 + math.random() * 5
					else
						local step = offset.Unit
						state.facing = state.facing:Lerp(step, math.min(dt * 5, 1))
						state.pos += step * math.min(speed * dt, offset.Magnitude)
						hop = math.abs(math.sin(now * speed * 2.4 + state.phase)) * 0.14
					end
				end
				if state.facing.Magnitude > 0.01 then
					local spot = state.pos + Vector3.new(0, hop, 0)
					model:PivotTo(CFrame.lookAt(spot, spot + state.facing))
				end
			end
		end

		-- Los farolillos laten a unos 20 cuadros por segundo: de sobra para una luz.
		acc += dt
		if acc >= 0.05 then
			acc = 0
			for lamp in lamps do
				local paper = lamp :: BasePart
				if paper.Parent then
					local wave = 0.5 + 0.5 * math.sin(now * 2.2 + paper.Position.X * 0.37 + paper.Position.Z * 0.21)
					paper.Transparency = 0.05 + 0.2 * wave
					local light = paper:FindFirstChildOfClass("PointLight")
					if light then
						light.Brightness = 0.7 + 0.5 * wave
					end
				end
			end
		end
	end)
end

return JapanFx
