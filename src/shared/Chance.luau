-- Tiradas de probabilidad que siguen siendo exactas con rarezas enormes (1 entre Qi, Sp...).
-- Un solo número aleatorio no tiene precisión para eso, así que se encadenan tiradas pequeñas.
local Chance = {}

local rng = Random.new()
local STEP = 1e-6

-- true con probabilidad p. Con `random` tira de ese generador (para tiradas con semilla, como la del clima de cada tramo).
function Chance.roll(p: number, random: Random?): boolean
	local source = random or rng
	while p < STEP do
		if source:NextNumber() >= STEP then
			return false
		end
		p /= STEP
	end
	return source:NextNumber() < p
end

return Chance
