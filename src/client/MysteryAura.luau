-- Aura misteriosa (pedido por el usuario): los jugadores de Config.MysteryAura llevan siempre humo violeta, destellos y
-- una luz tenue, y de vez en cuando les sale del cuerpo el texto "emana un aura misteriosa", que sube y se desvanece.
-- Solo se ve: no da nada. Se crea en cada cliente sobre el personaje de esos jugadores.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Lang = require(ReplicatedStorage.Shared.Lang)

local MysteryAura = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local DEEP = Color3.fromRGB(70, 25, 110)
local GLOW = Color3.fromRGB(185, 120, 255)
local TEXT_EVERY = NumberRange.new(1.6, 2.8) -- segundos entre un texto y el siguiente
local TEXT_LIFE = 3
local MAX_TEXTS = 3 -- textos a la vez por jugador

local function addEffects(root: BasePart)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "MysteryAuraSmoke"
	smoke.Texture = SMOKE
	smoke.Color = ColorSequence.new(DEEP, Color3.fromRGB(30, 8, 50))
	smoke.LightEmission = 0.1
	smoke.Shape = Enum.ParticleEmitterShape.Cylinder
	smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	smoke.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Rate = 26
	smoke.Lifetime = NumberRange.new(1.4, 2.4)
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.Acceleration = Vector3.new(0, 2.5, 0)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3.6) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = root

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "MysteryAuraSparks"
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(GLOW)
	sparks.LightEmission = 1
	sparks.Shape = Enum.ParticleEmitterShape.Cylinder
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Rate = 6
	sparks.Lifetime = NumberRange.new(1, 1.6)
	sparks.Speed = NumberRange.new(1, 2.5)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = root

	local light = Instance.new("PointLight")
	light.Name = "MysteryAuraLight"
	light.Color = GLOW
	light.Brightness = 0.8
	light.Range = 10
	light.Parent = root
end

-- Un texto que sale del cuerpo, sube y se desvanece.
local function emitText(root: BasePart, alive: { n: number })
	if alive.n >= MAX_TEXTS then
		return
	end
	alive.n += 1
	local spot = Instance.new("Attachment")
	spot.Name = "MysteryAuraText"
	spot.Position = Vector3.new(math.random(-20, 20) / 10, math.random(-5, 15) / 10, math.random(-20, 20) / 10)
	spot.Parent = root

	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(9, 1.1) -- en studs: se ve más pequeño de lejos
	board.LightInfluence = 0
	board.MaxDistance = 90
	board.Adornee = spot
	board.Parent = spot

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(225, 195, 255)
	label.TextTransparency = 1
	label.Text = Lang.t(nil, "emanates a mysterious aura")
	label.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(25, 5, 40)
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = label

	local fadeIn = TweenInfo.new(0.5, Enum.EasingStyle.Sine)
	local fadeOut = TweenInfo.new(1, Enum.EasingStyle.Sine)
	TweenService:Create(spot, TweenInfo.new(TEXT_LIFE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = spot.Position + Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, fadeIn, { TextTransparency = 0.1 }):Play()
	TweenService:Create(stroke, fadeIn, { Transparency = 0 }):Play()
	task.delay(TEXT_LIFE - 1, function()
		TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
	end)
	task.delay(TEXT_LIFE, function()
		spot:Destroy()
		alive.n -= 1
	end)
end

local function watchCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) then
		return
	end
	addEffects(root)
	local alive = { n = 0 }
	local random = Random.new()
	while character.Parent and root.Parent do
		emitText(root, alive)
		task.wait(random:NextNumber(TEXT_EVERY.Min, TEXT_EVERY.Max))
	end
end

function MysteryAura.start()
	local function watchPlayer(player: Player)
		if not table.find(Config.MysteryAura or {}, player.UserId) then
			return
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(watchCharacter, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return MysteryAura
