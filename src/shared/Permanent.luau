-- Modificadores permanentes de las armas (metal y tamaño, ver Config.Metals y Config.Sizes): su daño, su
-- rareza, su tirada y el nombre completo. Vale en servidor y cliente.
local Chance = require(script.Parent.Chance)
local Config = require(script.Parent.Config)
local Lang = require(script.Parent.Lang)

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

-- Lo difícil que era sacar esa arma con esa suerte ("1 entre N"): el arma con su metal y su tamaño es UN resultado
-- (Permanent.rollWeapon), así que es su rareza total entre la suerte.
function Permanent.odds(sword: number, metal: number?, size: number?, luck: number): number
	return math.max(Permanent.rarity(sword, metal, size) / luck, 1)
end

-- Todos los resultados de una tirada de arma: cada arma del gacha con cada metal (o ninguno) y cada tamaño (o
-- normal), de más rara a más común por su rareza total. { sword, metal, size, rarity }; 0 = sin metal / normal.
local combos = nil
function Permanent.combos()
	if not combos then
		combos = {}
		for sword, def in Config.Swords do
			if def.rarity then
				for metal = 0, #Config.Metals do
					for size = 0, #Config.Sizes do
						table.insert(combos, { sword = sword, metal = metal, size = size, rarity = Permanent.rarity(sword, metal, size) })
					end
				end
			end
		end
		table.sort(combos, function(a, b)
			if a.rarity ~= b.rarity then
				return a.rarity > b.rarity
			elseif a.sword ~= b.sword then
				return a.sword < b.sword
			elseif a.metal ~= b.metal then
				return a.metal < b.metal
			end
			return a.size < b.size
		end)
	end
	return combos
end

-- Tirada de arma (decidido por el usuario): el arma sale ya con su metal y su tamaño, como un solo resultado con su
-- rareza total, y la suerte se aplica UNA vez a esa rareza. Se prueba del resultado más raro al más común. Así un
-- arma común con el mejor metal y el mejor tamaño es rarísima, y la suerte no llena la mochila de Cobre: con suerte
-- xN salen cosas de alrededor de "1 entre N" en total, sea por el arma, por el metal o por el tamaño. (Antes el metal
-- y el tamaño se tiraban aparte, después del arma: con suerte x10, el Cobre de 1 entre 10 salía siempre.)
function Permanent.rollWeapon(luck: number): (number, number, number)
	local list = Permanent.combos()
	for _, combo in list do
		if Chance.roll(luck / combo.rarity) then
			return combo.sword, combo.metal, combo.size
		end
	end
	local last = list[#list]
	return last.sword, last.metal, last.size
end

-- Tira un modificador de la lista: se prueba del más raro al más común y la suerte multiplica cada
-- probabilidad (como con las armas). Devuelve su posición, o 0 si no sale ninguno. (Las armas ya no tiran así su
-- metal y su tamaño: ver Permanent.rollWeapon. Lo usa la calidad de la armadura.)
function Permanent.roll(list, luck: number): number
	for index = #list, 1, -1 do
		if Chance.roll(luck / list[index].odds) then
			return index
		end
	end
	return 0
end

-- Texto para resultados e inventario: un solo "1 entre N", el del arma con su metal y su tamaño (probabilidad base,
-- independiente de cualquier suerte). Pedido por el usuario: sin desglose por arma, metal y tamaño, que el juego es
-- para niños y sobraban números. "1 in 1.5K" / "1 entre 1,5K", según el idioma de `player`.
function Permanent.describeOdds(sword: number, metal: number?, size: number?, player: Player?): string
	local Format = require(script.Parent.Format)
	return Lang.t(player, "1 in {n}", { n = Format.short(Permanent.rarity(sword, metal, size), player) })
end

-- "Steel Sword (Gold, Giant)": el nombre del arma con sus modificadores, si los tiene, en el idioma de `player`.
function Permanent.name(sword: number, metal: number?, size: number?, player: Player?): string
	local parts = {}
	local metalEntry, sizeEntry = entry(Config.Metals, metal), entry(Config.Sizes, size)
	if metalEntry then
		table.insert(parts, Lang.t(player, metalEntry.name))
	end
	if sizeEntry then
		table.insert(parts, Lang.t(player, sizeEntry.name))
	end
	local name = Lang.t(player, Config.Swords[sword].name)
	return if #parts > 0 then `{name} ({table.concat(parts, ", ")})` else name
end

return Permanent
