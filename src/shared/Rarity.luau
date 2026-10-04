-- Nivel de rareza (nombre y color) que corresponde a un "1 entre N". Los niveles están en Config.RarityTiers.
local Config = require(script.Parent.Config)

local Rarity = {}

function Rarity.tier(rarity: number?)
	local found = Config.RarityTiers[1]
	for _, tier in Config.RarityTiers do
		if (rarity or 0) >= tier.min then
			found = tier
		end
	end
	return found
end

return Rarity
