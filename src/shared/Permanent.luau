-- Modificadores permanentes de las armas (metal y tamaño, ver Config.Metals y Config.Sizes): su daño, su
-- rareza, su tirada y el nombre completo. Vale en servidor y cliente.
local Chance = require(script.Parent.Chance)
local Config = require(script.Parent.Config)

local Permanent = {}

-- Regla de equilibrio del juego: cada vez que la rareza (1 entre N) se multiplica por 2, el daño sube un 50 %.
-- Rareza 2 = x1, 4 = x1.5, 8 = x2.25... (las armas de Config.Swords ya llevan su daño calculado así).
function Permanent.damage(odds: number): number
	return Config.damageFromRarity(odds)
end

local function entry(list, index: number?)
	return if index and index > 0 then list[index] else nil
end

function Permanent.metal(copy)
	return entry(Config.Metals, copy.metal)
end

function Permanent.size(copy)
	return entry(Config.Sizes, copy.size)
end

-- Multiplicador de daño que dan el metal y el tamaño de esa copia.
function Permanent.damageMult(copy): number
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	return (if metal then Permanent.damage(metal.odds) else 1) * (if size then Permanent.damage(size.odds) else 1)
end

-- Cuánto se agranda el arma (1 si no es de ningún tamaño).
function Permanent.scale(copy): number
	local size = Permanent.size(copy)
	return if size then size.scale else 1
end

-- Rareza total ("1 entre N") de una espada con esos modificadores: la del arma por las de sus modificadores.
function Permanent.rarity(sword: number, metal: number?, size: number?): number
	local base = Config.Swords[sword].rarity or 1
	local metalEntry, sizeEntry = entry(Config.Metals, metal), entry(Config.Sizes, size)
	return base * (if metalEntry then metalEntry.odds else 1) * (if sizeEntry then sizeEntry.odds else 1)
end

-- Lo difícil que era sacar esa arma con esa suerte ("1 entre N"). El arma, el metal y el tamaño se tiran por
-- separado con la misma suerte, así que cada uno cuenta lo que le faltaba a la suerte para llegar a él, y lo que la
-- suerte ya garantiza cuenta 1. (No vale rareza total / suerte: con suerte 100, el metal de 1 entre 100 sale
-- siempre, y esa cuenta diría que todas las tiradas son de 1 entre 100.) `sideLuck` = suerte del metal y del
-- tamaño, si no es la misma que la del arma (ver server/Gacha).
function Permanent.odds(sword: number, metal: number?, size: number?, luck: number, sideLuck: number?): number
	local side = sideLuck or luck
	local metalEntry, sizeEntry = entry(Config.Metals, metal), entry(Config.Sizes, size)
	return math.max((Config.Swords[sword].rarity or 1) / luck, 1)
		* (if metalEntry then math.max(metalEntry.odds / side, 1) else 1)
		* (if sizeEntry then math.max(sizeEntry.odds / side, 1) else 1)
end

-- Tira un modificador de la lista: se prueba del más raro al más común y la suerte multiplica cada
-- probabilidad (como con las armas). Devuelve su posición, o 0 si no sale ninguno.
function Permanent.roll(list, luck: number): number
	for index = #list, 1, -1 do
		if Chance.roll(luck / list[index].odds) then
			return index
		end
	end
	return 0
end

-- Texto para resultados e inventario: probabilidades base, independientes de cualquier suerte.
function Permanent.describeOdds(sword: number, metal: number?, size: number?): string
	local Format = require(script.Parent.Format)
	local parts = { `Arma: 1 entre {Format.short(Config.Swords[sword].rarity or 1)}` }
	local metalEntry, sizeEntry = entry(Config.Metals, metal), entry(Config.Sizes, size)
	if metalEntry then
		table.insert(parts, `{metalEntry.name}: 1 entre {Format.short(metalEntry.odds)}`)
	end
	if sizeEntry then
		table.insert(parts, `{sizeEntry.name}: 1 entre {Format.short(sizeEntry.odds)}`)
	end
	return table.concat(parts, " · ")
end

-- "Espada de acero (Oro, Gigante)": el nombre del arma con sus modificadores, si los tiene.
function Permanent.name(sword: number, metal: number?, size: number?): string
	local parts = {}
	local metalEntry, sizeEntry = entry(Config.Metals, metal), entry(Config.Sizes, size)
	if metalEntry then
		table.insert(parts, metalEntry.name)
	end
	if sizeEntry then
		table.insert(parts, sizeEntry.name)
	end
	local name = Config.Swords[sword].name
	return if #parts > 0 then `{name} ({table.concat(parts, ", ")})` else name
end

return Permanent
