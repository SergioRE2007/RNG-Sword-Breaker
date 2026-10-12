-- Tutorial de los primeros minutos (Config.Tutorial; la tarjeta y las flechas son de client/Tutorial). El paso por el
-- que va cada jugador se guarda (data.tutorial: 1 a N; 0 = terminado) y se publica en el atributo "Tutorial", con
-- "TutorialCount" para los pasos que cuentan (romper N objetos). Aquí se decide cuándo se cumple cada paso:
--   breaks, upgrades: se cuentan solos con lo que ya avisa server/Missions (Missions.listen).
--   equip, bag, lobby: el cliente avisa con TutorialCheck cuando cree que ya está y aquí se mira en los datos de verdad.
--   seen: abrir una ventana; eso solo lo sabe el cliente, y se le cree (TutorialCheck con el id del paso).
-- Al acabar se da Config.Tutorial.Reward una sola vez. TutorialSkip lo da por terminado sin premio. Quien ya tenía
-- partida guardada antes de existir el tutorial no lo ve. En Studio solo sale con Config.Test.Tutorial.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Missions = require(script.Parent.Missions)
local PlayerData = require(script.Parent.PlayerData)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Tutorial = {}

local cfg = Config.Tutorial
local DONE = 0
local LOBBY_Y = -28 -- por debajo está el lobby de las mazmorras
local COOLDOWN = 0.3
local GOLD = Color3.fromRGB(255, 200, 60)

local counts: { [Player]: number } = {}
local last: { [Player]: number } = {}

local function enabled(): boolean
	return not RunService:IsStudio() or Config.Test.Tutorial == true
end

local function publish(player: Player, data)
	player:SetAttribute("Tutorial", if enabled() then data.tutorial else DONE)
	player:SetAttribute("TutorialCount", counts[player] or 0)
end

local function advance(player: Player)
	local data = PlayerData.read(player)
	if not data or data.tutorial == DONE then
		return
	end
	counts[player] = 0
	PlayerData.edit(player, function(edited)
		edited.tutorial += 1
		if edited.tutorial > #cfg.Steps then
			edited.tutorial = DONE
			local reward = cfg.Reward
			edited.items[reward.item] += reward.amount
		end
	end)
	publish(player, data)
	if data.tutorial == DONE then
		local item = Config.Items[cfg.Reward.item]
		Tell.notice(player, GOLD, "Tutorial complete! +{n} {item}", { n = cfg.Reward.amount, item = Lang.t(player, item.name) })
	end
end

-- El paso por el que va, o nil si ya lo ha terminado (o aquí no hay tutorial).
local function current(player: Player)
	local data = PlayerData.read(player)
	if not data or not enabled() or data.tutorial == DONE then
		return nil, data
	end
	return cfg.Steps[data.tutorial], data
end

local function onProgress(player: Player, kind: string, amount: number)
	local step, data = current(player)
	if not step or step.kind ~= kind then
		return
	end
	counts[player] = (counts[player] or 0) + amount
	if counts[player] >= (step.goal or 1) then
		advance(player)
	else
		publish(player, data)
	end
end

local function onCheck(player: Player, flag: unknown)
	local now = os.clock()
	if now - (last[player] or 0) < COOLDOWN then
		return
	end
	last[player] = now
	local step, data = current(player)
	if not step then
		return
	end
	local ok = false
	if step.kind == "equip" then
		ok = #data.loadout >= 2
	elseif step.kind == "bag" then
		ok = #data.bag.slots >= 1
	elseif step.kind == "lobby" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		ok = root ~= nil and root:IsA("BasePart") and root.Position.Y < LOBBY_Y
	elseif step.kind == "seen" then
		ok = flag == step.id
	end
	if ok then
		advance(player)
	end
end

local function onSkip(player: Player)
	local step, data = current(player)
	if not step then
		return
	end
	counts[player] = 0
	PlayerData.edit(player, function(edited)
		edited.tutorial = DONE
	end)
	publish(player, data)
end

function Tutorial.start()
	Missions.listen(onProgress)
	Remotes.TutorialCheck.OnServerEvent:Connect(onCheck)
	Remotes.TutorialSkip.OnServerEvent:Connect(onSkip)
	PlayerData.onLoad(function(player)
		local data = PlayerData.read(player)
		if not data then
			return
		end
		-- Modo de pruebas (solo en Studio, sin guardar): siempre desde el principio.
		if RunService:IsStudio() and Config.Test.Tutorial == true then
			data.tutorial = 1
		end
		counts[player] = 0
		publish(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		counts[player] = nil
		last[player] = nil
	end)
end

return Tutorial
