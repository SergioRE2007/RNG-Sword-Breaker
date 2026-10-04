-- Cristales de rasgo: los sueltan los objetos raros. Se gastan en la tienda de Rasgos del hub
-- (ModifierShops).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Traits = {}

local ITEM = "traitCrystal"

-- Se llama cuando el jugador rompe un objeto (def = entrada de Config.Destructibles).
function Traits.onBroken(player: Player, def)
	local item = Config.Items[ITEM]
	if def.gems > 0 and Chance.roll(item.dropChance) then
		PlayerData.edit(player, function(data)
			data.items[ITEM] += 1
		end)
		Remotes.Notice:FireClient(player, `+1 {item.name}`, item.color)
	end
end

function Traits.start() end

return Traits
