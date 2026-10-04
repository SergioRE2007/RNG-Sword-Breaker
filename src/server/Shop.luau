-- Compra de mejoras, con monedas o con gemas según la mejora. Las espadas salen del gacha (ver Gacha).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local PlayerData = require(script.Parent.PlayerData)

local Shop = {}

local function onBuyUpgrade(player: Player, name: unknown)
	if type(name) ~= "string" then
		return
	end
	local upgrade = Config.Upgrades[name]
	if not upgrade then
		return
	end
	local level = PlayerData.getUpgrade(player, name)
	if level >= upgrade.maxLevel then
		return
	end
	local spend = if upgrade.currency == "gems" then PlayerData.trySpendGems else PlayerData.trySpend
	if spend(player, Upgrades.cost(name, level)) then
		PlayerData.setUpgrade(player, name, level + 1)
	end
end

function Shop.start()
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
end

return Shop
