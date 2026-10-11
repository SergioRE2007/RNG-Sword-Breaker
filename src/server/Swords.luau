-- YA NO SE ARRANCA (server/init): las armas equipadas no van en la mano, las dibuja cada cliente girando alrededor
-- del jugador (client/OrbitWeapons). Se guarda hasta que el sistema nuevo se dé por bueno.
-- Entrega al jugador la espada de su nivel (el modelo lo construye shared/SwordModel).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Swords = {}

local function build(level: number, metal: number, size: number): Tool
	local def = Config.Swords[level]

	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.CanBeDropped = false
	tool:SetAttribute("Sword", true)

	-- El tamaño agranda el arma (y su alcance, ver Combat); el metal le da su color y material.
	local scale = if size > 0 then Config.Sizes[size].scale else 1
	local handle = SwordModel.build(level, tool, CFrame.identity, scale, false, metal)
	if def.kind == "spear" then
		-- La lanza se lleva tumbada, apuntando hacia donde apunta el antebrazo.
		tool.Grip = CFrame.Angles(math.rad(90), 0, 0)
	end

	return tool
end

local function give(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local drawn = true
	for _, container in { character, player:FindFirstChildOfClass("Backpack") } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Sword") then
				drawn = container == character
				child:Destroy()
			end
		end
	end

	local tool = build(player:GetAttribute("SwordLevel") or 1, player:GetAttribute("SwordMetal") or 0, player:GetAttribute("SwordSize") or 0)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
	-- Cambiar el modelo conserva si el jugador la llevaba en la mano o la había guardado.
	if drawn then
		humanoid:EquipTool(tool)
	end

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
	-- Tipo, metal y tamaño de la espada equipada cambian casi a la vez: se reconstruye una sola vez.
	local scheduled = false
	local function rebuild()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			give(player)
		end)
	end
	for _, attribute in { "SwordLevel", "SwordMetal", "SwordSize" } do
		player:GetAttributeChangedSignal(attribute):Connect(rebuild)
	end
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
