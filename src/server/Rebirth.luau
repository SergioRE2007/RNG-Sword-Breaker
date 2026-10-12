-- Renacimiento: se paga solo con monedas y no quita nada. Cada uno multiplica para siempre las monedas,
-- el daño y las suertes (ver Config.Rebirth y Stats.rebirthBonus). El servidor cobra y cuenta; el
-- cliente solo lo pide con el remote Rebirth.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local Missions = require(script.Parent.Missions)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Rebirth = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local lastTry = {} -- [player] = os.clock() del último intento (evita pulsar mil veces)

local function onRebirth(player: Player)
	local now = os.clock()
	if now - (lastTry[player] or 0) < 0.3 then
		return
	end
	lastTry[player] = now

	if Stats.rebirths(player) >= Config.Rebirth.max then
		Tell.notice(player, GOLD, "You've reached the maximum number of rebirths.")
		return
	end
	local cost = Stats.rebirthCost(player)
	if not PlayerData.trySpend(player, cost) then
		Tell.notice(player, Color3.fromRGB(240, 65, 75), "Not enough coins: the rebirth costs {n}", { n = Format.short(cost, player) })
		return
	end
	PlayerData.addRebirth(player)
	Missions.add(player, "rebirth")
	local count = Stats.rebirths(player)
	Tell.notice(player, GOLD, "Rebirth {count}! Coins x{n} and more forever", { count = count, n = Format.multiplier(Stats.rebirthBonus(player, "coins"), player) })
	-- Los números redondos y los primeros se anuncian a todos.
	if count <= 3 or count % 5 == 0 then
		Tell.all(GOLD, function(reader)
			return Lang.t(reader, if count == 1 then "{player} has been reborn {count} time!" else "{player} has been reborn {count} times!", { player = player.DisplayName, count = count })
		end)
	end
end

function Rebirth.start()
	Remotes.Rebirth.OnServerEvent:Connect(onRebirth)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return Rebirth
