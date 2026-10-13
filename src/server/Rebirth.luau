-- Renacimiento: hace falta tener su precio en monedas y lo quita casi todo (pedido por el usuario): todas las
-- monedas, las gemas y las mejoras, y la Bolsa de oro vuelve a la primera. A cambio multiplica para siempre las
-- monedas, el daño y las suertes (ver Config.Rebirth y Stats.rebirthBonus). El servidor comprueba, reinicia
-- (PlayerData.rebirth) y cuenta; el cliente solo lo pide con el remote Rebirth y enseña la cinemática (Reborn).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local GoldBag = require(script.Parent.GoldBag)
local Missions = require(script.Parent.Missions)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Rebirth = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local RED = Color3.fromRGB(240, 65, 75)
local COOLDOWN = 2 -- segundos entre dos intentos
local lastTry = {} -- [player] = os.clock() del último intento (evita pulsar mil veces)

local function onRebirth(player: Player)
	local now = os.clock()
	if now - (lastTry[player] or 0) < COOLDOWN then
		return
	end
	lastTry[player] = now

	if Stats.rebirths(player) >= Config.Rebirth.max then
		Tell.notice(player, GOLD, "You've reached the maximum number of rebirths.")
		return
	end
	if (player:GetAttribute("Dungeon") or 0) ~= 0 then
		Tell.notice(player, RED, "You can't rebirth inside a dungeon.")
		return
	end
	local cost = Stats.rebirthCost(player)
	-- Lo que tenía, para que la cinemática lo enseñe yéndose.
	local coins, gems = player:GetAttribute("Coins") or 0, player:GetAttribute("Gems") or 0
	if not PlayerData.rebirth(player, cost) then
		Tell.notice(player, RED, "Not enough coins: the rebirth costs {n}", { n = Format.short(cost, player) })
		return
	end
	GoldBag.refresh(player)
	Missions.add(player, "rebirth")
	local count = Stats.rebirths(player)
	Remotes.Reborn:FireAllClients(player, count, coins, gems)
	-- Los números redondos y los primeros se anuncian a todos.
	if count <= 3 or count % 5 == 0 then
		Tell.all(GOLD, function(reader)
			return Lang.t(reader, if count == 1 then "{player} has been reborn {count} time!" else "{player} has been reborn {count} times!", { player = player.DisplayName, count = count })
		end)
	end
	-- Un cambio así de gordo se guarda al momento.
	task.spawn(PlayerData.save, player)
end

function Rebirth.start()
	Remotes.Rebirth.OnServerEvent:Connect(onRebirth)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return Rebirth
