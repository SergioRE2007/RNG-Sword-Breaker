-- Nivel de las armas (Config.WeaponLevel): lo que multiplica el daño y lo que cuesta cada nivel. Vale en servidor,
-- cliente y tools/equilibrio.
local Config = require(script.Parent.Config)
local Permanent = require(script.Parent.Permanent)

local WeaponLevel = {}
local SETTINGS = Config.WeaponLevel

-- Nivel guardado limpio: entero de 0 a MaxLevel (lo que no sea un número, 0).
function WeaponLevel.sanitize(level: unknown): number
	local value = tonumber(level) or 0
	if value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, SETTINGS.MaxLevel)
end

-- Por cuánto multiplica el daño de su arma ese nivel.
function WeaponLevel.mult(level: number?): number
	return SETTINGS.PerLevel ^ (level or 0)
end

-- Gemas que cuesta subir la copia del nivel `level` al siguiente (con su rareza total: arma, metal y tamaño).
function WeaponLevel.cost(copy, level: number): number
	local rarity = Permanent.rarity(copy.sword, copy.metal, copy.size)
	-- Por encima del codo, la potencia baja a KneePower: las gemas del endgame crecen casi como la rareza de los objetos,
	-- no como rareza ^ 1,5 (un arma de 500 Sp costaba 500 No por nivel y ganaban ~100 Oc).
	local below = math.min(rarity, SETTINGS.Knee)
	local above = math.max(rarity / SETTINGS.Knee, 1)
	local base = math.max(SETTINGS.MinCost, SETTINGS.CostBase * below ^ SETTINGS.RarityPower * above ^ SETTINGS.KneePower)
	return math.ceil(base * SETTINGS.Growth ^ level)
end

-- Cuántos niveles le puede subir (hasta `wanted`) con esas gemas, y lo que cuestan juntos.
function WeaponLevel.affordable(copy, gems: number, wanted: number): (number, number)
	local level = WeaponLevel.sanitize(copy.level)
	local count, total = 0, 0
	while count < wanted and level + count < SETTINGS.MaxLevel do
		local cost = WeaponLevel.cost(copy, level + count)
		if total + cost > gems then
			break
		end
		total += cost
		count += 1
	end
	return count, total
end

return WeaponLevel
