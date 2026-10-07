-- Modificadores de espada que se tiran en las tiendas del hub: rasgos (Config.Traits, con
-- Cristal de rasgo) y grados (Config.Grades, con Cristal de grado). Cada entrada tiene un peso "chance";
-- aquí se calcula su % real, se tira al azar y se describe su efecto. Vale en servidor y cliente.
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local Modifiers = {}

-- kind = "traits" o "grades".
Modifiers.KINDS = {
	-- "item" y "cost" = objeto de Config.Items que cuesta cada tirada y cuántos.
	traits = { list = Config.Traits, field = "trait", title = "Rasgos", label = "RASGO", item = "traitCrystal", cost = 1 },
	grades = { list = Config.Grades, field = "grade", title = "Grados", label = "GRADO", item = "gradeCrystal", cost = Config.GradeCost },
	armorMods = { list = Config.Armor.Mods }, -- modificadores extra de la armadura (solo se usa la tirada por pesos)
}

local totals = {}
for kind, info in Modifiers.KINDS do
	local total = 0
	for _, entry in info.list do
		total += entry.chance
	end
	totals[kind] = total
end

-- SUERTE (pociones de suerte de rasgo y de grado). No multiplica todas las probabilidades por igual: sube el peso de lo
-- raro más que el de lo común, así que lo rarísimo se acerca pero sigue siéndolo. La entrada de más peso (la más común)
-- se queda como está, la de menos peso se multiplica por la suerte entera y las de en medio por la suerte elevada a lo
-- cerca que están de la más rara, medido en escala logarítmica de su peso. Con suerte 1 (o sin ella) todo queda igual.
local ranges = {} -- [kind] = { peak = mayor peso, span = log(mayor peso / menor peso) }
for kind, info in Modifiers.KINDS do
	local peak, low = 0, math.huge
	for _, entry in info.list do
		peak = math.max(peak, entry.chance)
		low = math.min(low, entry.chance)
	end
	ranges[kind] = { peak = peak, span = math.log(peak / low) }
end

local function weight(kind: string, entry, luck: number?): number
	local range = ranges[kind]
	if not luck or luck <= 1 or range.span == 0 then
		return entry.chance
	end
	return entry.chance * luck ^ (math.log(range.peak / entry.chance) / range.span)
end

-- Probabilidad en % de sacar la entrada `index` (con la `luck` de una poción, si se le pasa).
function Modifiers.percent(kind: string, index: number, luck: number?): number
	local list = Modifiers.KINDS[kind].list
	if not luck or luck <= 1 then
		return list[index].chance / totals[kind] * 100
	end
	local total = 0
	for _, entry in list do
		total += weight(kind, entry, luck)
	end
	return weight(kind, list[index], luck) / total * 100
end

-- "1 entre N" de sacar la entrada `index` (con la `luck` de una poción, si se le pasa).
function Modifiers.odds(kind: string, index: number, luck: number?): number
	return 100 / Modifiers.percent(kind, index, luck)
end

-- 24.76 -> "24.8%", 0.0019 -> "0.0019%".
function Modifiers.formatPercent(percent: number): string
	if percent >= 10 then
		return string.format("%.1f%%", percent)
	end
	local decimals = math.clamp(math.ceil(-math.log10(percent)) + 1, 1, 6)
	local text = string.format(`%.{decimals}f`, percent):gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

-- Entrada al azar según sus pesos (con la `luck` de una poción, si se le pasa).
function Modifiers.roll(kind: string, random: Random, luck: number?): number
	local list = Modifiers.KINDS[kind].list
	local weights, total = {}, 0
	for index, entry in list do
		weights[index] = weight(kind, entry, luck)
		total += weights[index]
	end
	local pick = random:NextNumber() * total
	for index, entryWeight in weights do
		pick -= entryWeight
		if pick < 0 then
			return index
		end
	end
	return 1
end

-- Prioridad de los tipos de rasgo cuando dos tiradas son igual de raras (Monedas II y Suerte II):
-- gana el tipo que va antes. Se guarda como texto ("luck,coins,damage") en los datos del jugador.
Modifiers.PRIORITY = { "luck", "coins", "damage" }

-- Lee una prioridad guardada o recibida del cliente: tienen que ser los tres tipos sin repetir; si
-- no, la de por defecto.
function Modifiers.priority(text: unknown): { string }
	if type(text) ~= "string" then
		return table.clone(Modifiers.PRIORITY)
	end
	local order = string.split(text, ",")
	if #order ~= #Modifiers.PRIORITY then
		return table.clone(Modifiers.PRIORITY)
	end
	for _, stat in Modifiers.PRIORITY do
		if not table.find(order, stat) then
			return table.clone(Modifiers.PRIORITY)
		end
	end
	return order
end

-- ¿Es la tirada `a` mejor que `b`? Primero la más rara; si son igual de raras, la de un tipo que
-- vaya antes en `priority` (los especiales no empatan nunca: cada uno tiene su probabilidad).
function Modifiers.better(kind: string, a: number, b: number, priority: { string }): boolean
	local oddsA, oddsB = Modifiers.odds(kind, a), Modifiers.odds(kind, b)
	if oddsA ~= oddsB then
		return oddsA > oddsB
	end
	local list = Modifiers.KINDS[kind].list
	local rankA = table.find(priority, list[a].icon) or math.huge
	local rankB = table.find(priority, list[b].icon) or math.huge
	return rankA < rankB
end

-- Pity por resultado: porcentajes base normalizados, sin pociones.
function Modifiers.pityLimit(kind: string, index: number): number
	return math.ceil(Modifiers.odds(kind, index))
end

function Modifiers.newPity(saved): { [string]: { number } }
	local pity = {}
	for _, kind in { "traits", "grades" } do
		local counters = {}
		local old = if type(saved) == "table" and type(saved[kind]) == "table" then saved[kind] else {}
		for index in Modifiers.KINDS[kind].list do
			local value = tonumber(old[index] or old[tostring(index)]) or 0
			counters[index] = if value == value then math.clamp(math.floor(value), 0, Modifiers.pityLimit(kind, index)) else 0
		end
		pity[kind] = counters
	end
	return pity
end

-- Cada llamada es una tirada pagada, incluso dentro de un lote. Las garantías que coinciden quedan pendientes.
function Modifiers.rollWithPity(kind: string, random: Random, luck: number, counters: { number }, priority: { string }): number
	local guaranteed = nil
	for index in Modifiers.KINDS[kind].list do
		local limit = Modifiers.pityLimit(kind, index)
		counters[index] = math.min((counters[index] or 0) + 1, limit)
		if counters[index] >= limit and (not guaranteed or Modifiers.better(kind, index, guaranteed, priority)) then
			guaranteed = index
		end
	end
	local result = guaranteed or Modifiers.roll(kind, random, luck)
	counters[result] = 0
	return result
end

-- "x1.5 Monedas · x1.5 Daño" (solo lo que sube).
function Modifiers.effect(entry): string
	local parts = {}
	for _, stat in { "coins", "damage", "luck" } do
		local value = entry[stat]
		if value and value ~= 1 then
			local name = Config.StatNames[stat]
			table.insert(parts, `x{Format.multiplier(value)} {string.upper(string.sub(name, 1, 1))}{string.sub(name, 2)}`)
		end
	end
	return table.concat(parts, " · ")
end

return Modifiers
