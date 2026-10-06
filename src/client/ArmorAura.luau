-- Brillos de la armadura según su calidad (Config.Armor.Qualities; la pieza lleva el atributo "Quality" que le pone
-- shared/ArmorModel). Rara: destellos sueltos. Épica: más destellos y un punto de luz. Legendaria: contorno que late.
-- Mítica: además brasas que suben por el pecho. Se crea en cada cliente sobre las piezas de todos los jugadores; el
-- modo rendimiento apaga partículas y luces (lo hace Performance) y el contorno.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Performance = require(script.Parent.Performance)

local ArmorAura = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local outlines: { [Highlight]: number } = {} -- contorno -> fase del latido

local function biggest(model: Model): BasePart?
	local best: BasePart? = nil
	local bestSize = 0
	for _, item in model:GetChildren() do
		if item:IsA("BasePart") and item.Transparency < 1 then
			local size = item.Size.Magnitude
			if size > bestSize then
				best, bestSize = item, size
			end
		end
	end
	return best
end

local function decorate(model: Model)
	local quality = model:GetAttribute("Quality")
	if not quality or quality < 3 or model:FindFirstChild("QualityFx") then
		return
	end
	local main = biggest(model)
	local info = Config.Armor.Qualities[quality]
	if not (main and info) then
		return
	end
	local color = info.color:Lerp(Color3.new(1, 1, 1), 0.3)
	local isChest = model.Name == "Armor_chest"

	local marker = Instance.new("Folder")
	marker.Name = "QualityFx"
	marker.Parent = model

	-- Destellos que salen de la superficie de la pieza.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparkle"
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.Rate = ({ [3] = 1.5, [4] = 3, [5] = 5, [6] = 8 })[quality] or 8
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(0.2, 1)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = main

	-- Un punto de luz suave.
	if quality >= 4 and (isChest or quality >= 6) then
		local light = Instance.new("PointLight")
		light.Name = "QualityLight"
		light.Color = color
		light.Brightness = 0.25 * (quality - 3)
		light.Range = 5 + quality
		light.Parent = main
	end

	-- Contorno que late (uno por personaje: en el pecho).
	if quality >= 5 and isChest then
		local outline = Instance.new("Highlight")
		outline.Name = "QualityOutline"
		outline.Adornee = model
		outline.FillTransparency = if quality >= 6 then 0.88 else 1
		outline.FillColor = color
		outline.OutlineColor = color
		outline.OutlineTransparency = 0.4
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Parent = model
		outlines[outline] = math.random() * 6.28
	end

	-- Brasas que suben por el pecho de las Míticas.
	if quality >= 6 and isChest then
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Texture = SPARKLE
		embers.Color = ColorSequence.new(info.color)
		embers.LightEmission = 1
		embers.Shape = Enum.ParticleEmitterShape.Box
		embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		embers.Rate = 14
		embers.Lifetime = NumberRange.new(1, 1.8)
		embers.Speed = NumberRange.new(2, 4)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		embers.Parent = main
	end
end

local function watchCharacter(character: Model)
	local function check(item: Instance)
		if item:IsA("Model") and string.sub(item.Name, 1, 6) == "Armor_" then
			-- Las mallas llegan con el modelo, pero el atributo puede tardar un instante.
			task.defer(decorate, item)
			item:GetAttributeChangedSignal("Quality"):Connect(function()
				decorate(item)
			end)
		end
	end
	character.ChildAdded:Connect(check)
	for _, item in character:GetChildren() do
		check(item)
	end
end

function ArmorAura.start()
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	RunService.Heartbeat:Connect(function()
		local calm = Performance.get()
		local now = os.clock()
		for outline, phase in outlines do
			if not outline.Parent then
				outlines[outline] = nil
			else
				outline.Enabled = not calm
				outline.OutlineTransparency = 0.45 + 0.25 * math.sin(now * 2.5 + phase)
			end
		end
	end)
end

return ArmorAura
