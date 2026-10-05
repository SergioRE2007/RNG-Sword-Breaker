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

local Rebirth = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local lastTry = {} -- [player] = os.clock() del último intento (evita pulsar mil veces)

local function onRebirth(player: Player)
	local now = os.clock()
	if now - (lastTry[player] or 0) < 0.3 then
		return
	end
	lastTry[player] = now

	local cost = Stats.rebirthCost(player)
	if not PlayerData.trySpend(player, cost) then
		Remotes.Notice:FireClient(player, `Te faltan monedas: el renacimiento cuesta {Format.short(cost)}`, Color3.fromRGB(240, 65, 75))
		return
	end
	PlayerData.addRebirth(player)
	local count = Stats.rebirths(player)
	Remotes.Notice:FireClient(player, `¡Renacimiento {count}! Monedas x{Format.multiplier(Stats.rebirthBonus(player, "coins"))} y más para siempre`, GOLD)
	-- Los números redondos y los primeros se anuncian a todos.
	if count <= 3 or count % 5 == 0 then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha renacido {count} {if count == 1 then "vez" else "veces"}!`, GOLD)
	end
end

function Rebirth.start()
	Remotes.Rebirth.OnServerEvent:Connect(onRebirth)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return Rebirth
