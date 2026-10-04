-- Tiradas de probabilidad que siguen siendo exactas con rarezas enormes (1 entre Qi, Sp...).
-- Un solo número aleatorio no tiene precisión para eso, así que se encadenan tiradas pequeñas.
local Chance = {}

local rng = Random.new()
local STEP = 1e-6

-- true con probabilidad p.
function Chance.roll(p: number): boolean
	while p < STEP do
		if rng:NextNumber() >= STEP then
			return false
		end
		p /= STEP
	end
	return rng:NextNumber() < p
end

return Chance
