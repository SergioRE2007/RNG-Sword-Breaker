-- Compra de mejoras, con monedas o con gemas según la mejora. Las espadas salen del gacha (ver Gacha).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local PlayerData = require(script.Parent.PlayerData)
local Missions = require(script.Parent.Missions)

local Shop = {}

-- Sube un nivel esa mejora si existe, no está al máximo y el jugador puede pagarla.
local function buy(player: Player, name: string): boolean
	local upgrade = Config.Upgrades[name]
	if not upgrade then
		return false
	end
	local level = PlayerData.getUpgrade(player, name)
	if level >= upgrade.maxLevel then
		return false
	end
	local spend = if upgrade.currency == "gems" then PlayerData.trySpendGems else PlayerData.trySpend
	if not spend(player, Upgrades.cost(name, level)) then
		return false
	end
	PlayerData.setUpgrade(player, name, level + 1)
	Missions.add(player, "upgrades")
	return true
end

local function onBuyUpgrade(player: Player, name: unknown)
	if type(name) == "string" then
		buy(player, name)
	end
end

-- "Mejorar todo": va dando vueltas por las mejoras subiendo un nivel de cada una mientras pueda pagar alguna.
local function onBuyAll(player: Player)
	repeat
		local bought = false
		for _, name in Config.UpgradeOrder do
			bought = buy(player, name) or bought
		end
	until not bought
end

function Shop.start()
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
	Remotes.BuyAllUpgrades.OnServerEvent:Connect(onBuyAll)
end

return Shop
