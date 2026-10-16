-- Cuentas de la máquina de fusión (Config.Fusion), las mismas en servidor y cliente: la suerte de una fusión y lo que
-- cuesta en gemas.
local Config = require(script.Parent.Config)
local Permanent = require(script.Parent.Permanent)

local FusionInfo = {}

-- Suerte de la fusión: la suma de las rarezas totales (arma x metal x tamaño) de las copias que se meten. Es también el
-- "1 entre N" mínimo de lo que sale (Permanent.rollWeapon nunca da menos que la suerte que le llega).
function FusionInfo.luck(copies: { any }): number
	local total = 0
	for _, copy in copies do
		total += Permanent.rarity(copy.sword, copy.metal, copy.size)
	end
	return total
end

-- Gemas que cuesta una fusión con esa suerte (entero, nunca menos de MinCost).
function FusionInfo.cost(luck: number): number
	local cfg = Config.Fusion
	return math.max(cfg.MinCost, math.ceil(cfg.CostScale * luck ^ cfg.CostPower))
end

return FusionInfo
