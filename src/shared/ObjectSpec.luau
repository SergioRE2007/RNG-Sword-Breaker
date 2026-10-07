-- Rareza, tamaño y suerte de los objetos de las parcelas (Config.ObjectRolls, ObjectRarities y ObjectSizes): la
-- tirada de lo que le toca a un objeto al aparecer y las cuentas de su vida, su premio, su suerte y sus tiradas de
-- arma. La tirada la hace solo el servidor (server/Destructibles), que publica el resultado en los atributos del
-- objeto (Quality, Size, Scale, Luck y Rolls); el cliente solo los enseña.
local Chance = require(script.Parent.Chance)
local Config = require(script.Parent.Config)

local ObjectSpec = {}

local rng = Random.new()

-- Escalas más pequeña y más grande de Config.ObjectSizes.
local LOWEST, HIGHEST = math.huge, 0
for _, size in Config.ObjectSizes do
	LOWEST = math.min(LOWEST, size.min)
	HIGHEST = math.max(HIGHEST, size.max)
end

function ObjectSpec.rarity(index: number?)
	return Config.ObjectRarities[index or 1] or Config.ObjectRarities[1]
end

function ObjectSpec.size(index: number?)
	return Config.ObjectSizes[index or 1] or Config.ObjectSizes[1]
end

-- Suerte propia del tipo de objeto (def = entrada de Config.Destructibles): cuanto más raro es de ver, más da
-- (su "1 entre N" elevado a TypeLuckPower), por el "luck" de los objetos especiales.
function ObjectSpec.typeLuck(def): number
	return (def.luck or 1) * def.rarity ^ Config.ObjectRolls.TypeLuckPower
end

-- Suerte de los objetos "de siempre" de un jugador con esa suerte de destructibles (Stats.luck): la que da un tipo
-- tan raro como los que le salen, común y de tamaño normal. Con ella se tiran el metal y el tamaño de sus armas, y
-- contra ella se mide lo difícil que era un arma para él (server/Gacha): lo que pasa de ahí es mérito del objeto
-- que le ha tocado.
function ObjectSpec.usualLuck(luck: number): number
	local rarest = Config.Destructibles[#Config.Destructibles].rarity
	return math.clamp(luck, 1, rarest) ^ Config.ObjectRolls.TypeLuckPower
end

-- Entre qué escalas puede salir ese tipo: los límites de Config.ObjectSizes, recortados para que no pase de
-- MaxWidth x MaxHeight (ni de lo que ponga el propio objeto).
function ObjectSpec.scaleLimits(def): (number, number)
	local cfg = Config.ObjectRolls
	local highest = math.min(def.maxScale or HIGHEST, cfg.MaxWidth / math.max(def.size.X, def.size.Z), cfg.MaxHeight / def.size.Y)
	return math.min(def.minScale or LOWEST, 1), math.max(highest, 1)
end

-- Suerte del objeto, la de las tiradas de arma que da al romperse: lo raro que es su tipo, por su rareza, por su
-- tamaño. Las tres cuentan.
function ObjectSpec.luck(def, quality: number, scale: number): number
	local cfg = Config.ObjectRolls
	return math.min(ObjectSpec.typeLuck(def) * ObjectSpec.rarity(quality).luck * scale ^ cfg.SizeLuckPower, cfg.MaxLuck)
end

-- Vida del objeto con esa rareza y esa escala.
function ObjectSpec.hp(def, quality: number, scale: number): number
	return def.hp * ObjectSpec.rarity(quality).hp * scale ^ Config.ObjectRolls.SizeHpPower
end

-- Por lo que se multiplican sus monedas y sus gemas.
function ObjectSpec.reward(quality: number, scale: number): number
	return ObjectSpec.rarity(quality).reward * scale ^ Config.ObjectRolls.SizeRewardPower
end

-- Posición en `list` de lo que toca: se prueba del final al principio (lo más raro primero) y el primero es el de
-- relleno. `luck(entry)` = por cuánto se multiplica la probabilidad de esa entrada.
local function pick(list, luck: (any) -> number): number
	for index = #list, 2, -1 do
		if Chance.roll(luck(list[index]) / list[index].odds) then
			return index
		end
	end
	return 1
end

-- Lo que le toca a un objeto de ese tipo al aparecer. `luck` = Stats.objectLuck del dueño. Devuelve
-- { quality, size (posiciones en Config.ObjectRarities y ObjectSizes), scale, hp, reward (multiplicador de monedas
-- y gemas), luck (suerte del objeto), rolls (tiradas de arma, ya decididas), odds ("1 entre N" de que saliera así) }.
function ObjectSpec.roll(def, luck: number)
	local cfg = Config.ObjectRolls
	local rarityLuck = luck * (def.rarityLuck or 1)
	local quality = math.max(pick(Config.ObjectRarities, function()
		return rarityLuck
	end), def.minRarity or 1)
	local rarity = ObjectSpec.rarity(quality)

	-- La suerte de tamaño solo empuja hacia los grandes: no hace salir más pequeños.
	local sizeLuck = luck * rarity.sizeLuck * (def.sizeLuck or 1)
	local size = pick(Config.ObjectSizes, function(entry)
		return if entry.min >= 1 then sizeLuck else 1
	end)
	local class = ObjectSpec.size(size)

	-- La escala cae al azar dentro de su tamaño; si el tipo no puede crecer (o encoger) tanto, se reparte en lo que sí puede.
	local scale = rng:NextNumber(class.min, class.max)
	local lowest, highest = ObjectSpec.scaleLimits(def)
	if scale > 1 then
		scale = 1 + (scale - 1) * (highest - 1) / (HIGHEST - 1)
	elseif LOWEST < 1 then
		scale = 1 - (1 - scale) * (1 - lowest) / (1 - LOWEST)
	end
	scale = math.round(scale * 100) / 100 -- al céntimo: lo que se ve en el cartel es lo que cuenta

	-- Tiradas: la parte decimal es la probabilidad de una más.
	local amount = rarity.rolls + class.rolls + (def.rolls or 0)
	local rolls = math.floor(amount)
	if amount > rolls and Chance.roll(amount - rolls) then
		rolls += 1
	end

	return {
		quality = quality,
		size = size,
		scale = scale,
		hp = ObjectSpec.hp(def, quality, scale),
		reward = ObjectSpec.reward(quality, scale),
		luck = ObjectSpec.luck(def, quality, scale),
		rolls = math.clamp(rolls, 0, cfg.MaxRolls),
		-- Los pequeños no cuentan como raros para los avisos.
		odds = rarity.odds * (if class.min >= 1 then class.odds else 1) / math.max(luck, 1e-9),
	}
end

return ObjectSpec
