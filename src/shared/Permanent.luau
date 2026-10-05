-- Modificadores permanentes de las armas (metal y tamaño, ver Config.Metals y Config.Sizes): su daño, su
-- rareza, su tirada y el nombre completo. Vale en servidor y cliente.
local Chance = require(script.Parent.Chance)
local Config = require(script.Parent.Config)

local Permanent = {}

-- Regla de equilibrio del juego: cada vez que la rareza (1 entre N) se multiplica por 2, el daño sube un 50 %.
-- Rareza 2 = x1, 4 = x1.5, 8 = x2.25... (las armas de Config.Swords ya llevan su daño calculado así).
function Permanent.damage(odds: number): number
	return 1.5 ^ math.max(math.log(odds / 2, 2), 0)
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
