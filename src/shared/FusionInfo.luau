-- Cuentas de la máquina de fusión (Config.Fusion), las mismas en servidor y cliente: la suerte de una fusión y lo que
-- cuesta en gemas.
local Config = require(script.Parent.Config)
local Permanent = require(script.Parent.Permanent)

local FusionInfo = {}

-- Suerte de la fusión: la suma de las rarezas totales (arma x metal x tamaño) de las copias que se meten, entre
-- Config.Fusion.Divisor. Es también el "1 entre N" mínimo de lo que sale (Permanent.rollWeapon nunca da menos que la
-- suerte que le llega).
function FusionInfo.luck(copies: { any }): number
	local total = 0
	for _, copy in copies do
		total += Permanent.rarity(copy.sword, copy.metal, copy.size)
	end
	return total / Config.Fusion.Divisor
end

-- Gemas que cuesta una fusión con esa suerte (entero, nunca menos de MinCost).
function FusionInfo.cost(luck: number): number
	local cfg = Config.Fusion
	-- Por encima del codo el precio crece más despacio (KneePower): las gemas de los objetos del endgame crecen casi igual
	-- que su rareza, y con CostPower hasta arriba una fusión de 1e23 salía a ~1e29, más de lo que ganan en un día.
	local below = math.min(luck, cfg.Knee)
	local above = math.max(luck / cfg.Knee, 1)
	return math.max(cfg.MinCost, math.ceil(cfg.CostScale * below ^ cfg.CostPower * above ^ cfg.KneePower))
end

return FusionInfo
