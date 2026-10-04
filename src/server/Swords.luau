-- Entrega al jugador la espada de su nivel (el modelo lo construye shared/SwordModel).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Swords = {}

local function build(level: number): Tool
	local def = Config.Swords[level]

	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.CanBeDropped = false
	tool:SetAttribute("Sword", true)

	local handle = SwordModel.build(level, tool, CFrame.identity, 1, false)
	if def.kind == "spear" then
		-- La lanza se lleva tumbada, apuntando hacia donde apunta el antebrazo.
		tool.Grip = CFrame.Angles(math.rad(90), 0, 0)
	end

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

	-- Espadas dobles: la segunda va soldada a la mano izquierda (la herramienta solo agarra la derecha).
	local offHand = tool:FindFirstChild("OffHand")
	if offHand then
		task.spawn(function()
			local hand = character:WaitForChild("LeftHand", 5)
			local offHandle = offHand:FindFirstChild("OffHandle")
			if not hand or not offHandle or not tool.Parent then
				return
			end
			local attachment = hand:FindFirstChild("LeftGripAttachment")
			local weld = Instance.new("Weld")
			weld.Name = "OffGrip"
			weld.Part0 = hand
			weld.Part1 = offHandle
			weld.C0 = if attachment and attachment:IsA("Attachment") then attachment.CFrame else CFrame.Angles(math.rad(-90), 0, 0)
			weld.Parent = offHandle
		end)
	end
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
