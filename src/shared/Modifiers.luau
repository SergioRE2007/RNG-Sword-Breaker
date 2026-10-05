-- Modificadores de espada que se tiran en las tiendas del hub: rasgos (Config.Traits, con
-- Cristal de rasgo) y grados (Config.Grades, con gemas). Cada entrada tiene un peso "chance";
-- aquí se calcula su % real, se tira al azar y se describe su efecto. Vale en servidor y cliente.
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local Modifiers = {}

-- kind = "traits" o "grades".
Modifiers.KINDS = {
	traits = { list = Config.Traits, field = "trait", title = "Rasgos", label = "RASGO" },
	grades = { list = Config.Grades, field = "grade", title = "Grados", label = "GRADO" },
}

local totals = {}
for kind, info in Modifiers.KINDS do
	local total = 0
	for _, entry in info.list do
		total += entry.chance
	end
	totals[kind] = total
end

-- Probabilidad en % de sacar la entrada `index`.
function Modifiers.percent(kind: string, index: number): number
	return Modifiers.KINDS[kind].list[index].chance / totals[kind] * 100
end

-- "1 entre N" de sacar la entrada `index`.
function Modifiers.odds(kind: string, index: number): number
	return 100 / Modifiers.percent(kind, index)
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

-- Entrada al azar según sus pesos.
function Modifiers.roll(kind: string, random: Random): number
	local list = Modifiers.KINDS[kind].list
	local pick = random:NextNumber() * totals[kind]
	for index, entry in list do
		pick -= entry.chance
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
