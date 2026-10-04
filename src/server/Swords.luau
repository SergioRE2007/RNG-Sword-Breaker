-- Construye la espada del jugador con piezas y se la entrega según su nivel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Swords = {}

local function addPart(tool: Tool, handle: BasePart?, name: string, size: Vector3, offset: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CanCollide = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if handle then
		part.CFrame = handle.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = tool
	return part
end

local function build(level: number): Tool
	local def = Config.Swords[level]

	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.CanBeDropped = false
	tool:SetAttribute("Sword", true)

	local handle = addPart(tool, nil, "Handle", Vector3.new(0.35, 1.2, 0.35), CFrame.identity)
	handle.Color = Color3.fromRGB(70, 45, 30)
	handle.Material = Enum.Material.Wood

	local guard = addPart(tool, handle, "Guard", Vector3.new(0.3, 0.25, 1.5), CFrame.new(0, 0.7, 0))
	guard.Color = Color3.fromRGB(60, 60, 65)
	guard.Material = Enum.Material.Metal

	local blade = addPart(tool, handle, "Blade", Vector3.new(0.15, def.bladeLength, 0.55), CFrame.new(0, 0.8 + def.bladeLength / 2, 0))
	blade.Color = def.color
	blade.Material = def.material

	local slash = Instance.new("Sound")
	slash.Name = "Slash"
	slash.SoundId = "rbxasset://sounds/swordslash.wav"
	slash.Volume = 0.6
	slash.Parent = handle

	return tool
end

local function give(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	for _, container in { character, player:FindFirstChildOfClass("Backpack") } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Sword") then
				child:Destroy()
			end
		end
	end

	local tool = build(player:GetAttribute("SwordLevel") or 1)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
	humanoid:EquipTool(tool)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		give(player)
	end)
	player:GetAttributeChangedSignal("SwordLevel"):Connect(function()
		give(player)
	end)
	if player.Character then
		give(player)
	end
end

function Swords.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Swords
