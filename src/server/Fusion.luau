-- Máquina de fusión del hub (pedida por el usuario): el jugador mete Config.Fusion.Count armas, paga gemas según la suerte
-- que suman (shared/FusionInfo) y sale una tirada de arma con esa suerte (Gacha.fuse). Las armas metidas se pierden con su
-- rasgo y su grado. La máquina es una estación que se abre sola al acercarse (pieza Counter con la etiqueta ShopStation y
-- Shop = "fusion"; la ventana es client/Fusion). Aquí se valida todo: el cliente solo pide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FusionInfo = require(ReplicatedStorage.Shared.FusionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Gacha = require(script.Parent.Gacha)
local ModifierShops = require(script.Parent.ModifierShops)
local PlayerData = require(script.Parent.PlayerData)
local Stations = require(script.Parent.Stations)
local Tell = require(script.Parent.Tell)

local Fusion = {}

local cfg = Config.Fusion
local corePosition: Vector3 = Vector3.zero -- centro del núcleo de la máquina: de ahí sale el arma
local lastFuse = {} -- [player] = os.clock() de su última fusión

local function nearMachine(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - corePosition).Magnitude <= cfg.Reach
end

local function onFuse(player: Player, ids: unknown)
	-- Exactamente Count ids enteros y distintos.
	if type(ids) ~= "table" or #ids ~= cfg.Count then
		return
	end
	local seen = {}
	for _, id in ids :: { unknown } do
		if type(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 or seen[id] then
			return
		end
		seen[id] = true
	end
	local now = os.clock()
	if now - (lastFuse[player] or 0) < cfg.Cooldown or not nearMachine(player) then
		return
	end
	local data = PlayerData.read(player)
	if not data then
		return
	end
	-- Cada copia tiene que ser suya y estar libre: ni equipada, ni en la Bolsa de oro, ni con el candado.
	local copies = {}
	for _, id in ids :: { number } do
		local copy = PlayerData.findSword(data, id)
		if not copy or PlayerData.isLocked(data, id) then
			return
		end
		table.insert(copies, copy)
	end
	local luck = FusionInfo.luck(copies)
	local cost = FusionInfo.cost(luck)
	if data.gems < cost then
		Tell.notice(player, Color3.fromRGB(255, 120, 120), "Not enough gems")
		return
	end
	lastFuse[player] = now
	-- Quitar las armas y cobrar a la vez, sin esperas entre medias; la tirada va justo después (Gacha.fuse).
	local inputs = {}
	PlayerData.edit(player, function(edited)
		for index = #edited.swords, 1, -1 do
			local copy = edited.swords[index]
			if seen[copy.id] then
				table.insert(inputs, { sword = copy.sword, metal = copy.metal or 0, size = copy.size or 0 })
				table.remove(edited.swords, index)
			end
		end
		edited.gems -= cost
	end)
	Remotes.FusionDone:FireClient(player, { swords = inputs, luck = luck })
	Gacha.fuse(player, luck, { origin = corePosition, box = Vector3.new(4, 4, 4) })
end

function Fusion.start()
	local map = workspace:WaitForChild("Map")
	local angle = math.rad(cfg.Angle)
	local position = Vector3.new(math.cos(angle) * cfg.Distance, 0, math.sin(angle) * cfg.Distance)
	local model, counter, signHeight, core = Stations.fusion(position)
	corePosition = core
	ModifierShops.addSign(counter, "fusion", "Fusion Machine", { Color3.fromRGB(90, 225, 255), Color3.fromRGB(255, 110, 210), Color3.fromRGB(255, 200, 80) }, signHeight, false)
	-- El cliente anima la máquina al fusionar (client/Fusion): sabe dónde está su núcleo por este atributo.
	counter:SetAttribute("Core", core)
	model.Parent = map

	Remotes.FuseSwords.OnServerEvent:Connect(onFuse)
	Players.PlayerRemoving:Connect(function(player)
		lastFuse[player] = nil
	end)
end

return Fusion
