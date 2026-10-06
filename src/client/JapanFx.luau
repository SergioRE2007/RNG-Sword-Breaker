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

function JapanFx.start()
	if Config.Theme ~= "japan" then
		return
	end

	-- Una nube de pétalos y motas que acompaña a la cámara: cae desde arriba y se renueva sola.
	local sky = emitterPart("JapanSky")
	pink().Parent = sky
	local low = emitterPart("JapanLow")
	motes().Parent = low

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
