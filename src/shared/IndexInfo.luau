-- Cuentas del Índice de armas (la colección de combinaciones arma + metal + tamaño que le han salido a cada jugador)
-- para servidor y cliente. Cada combinación es un número ("código"): lo guardado (data.index) y el atributo `Index`
-- del jugador son listas de códigos.
local Config = require(script.Parent.Config)

local IndexInfo = {}

-- arma * 10000 + metal * 100 + tamaño (0 = sin metal / tamaño normal). No depende de cuántos metales o tamaños haya,
-- así que añadir alguno al final de Config no cambia los códigos ya guardados.
function IndexInfo.code(sword: number, metal: number?, size: number?): number
	return sword * 10000 + (metal or 0) * 100 + (size or 0)
end

function IndexInfo.decode(code: number): (number, number, number)
	return code // 10000, code // 100 % 100, code % 100
end

-- ¿Es una casilla del Índice? El arma inicial no sale en las tiradas: solo existe sin metal y en tamaño normal.
function IndexInfo.valid(code: unknown): boolean
	if type(code) ~= "number" or code % 1 ~= 0 or code < 0 then -- (NaN e infinito no pasan el `% 1`)
		return false
	end
	local sword, metal, size = IndexInfo.decode(code)
	local entry = Config.Swords[sword]
	if not entry or (metal > 0 and not Config.Metals[metal]) or (size > 0 and not Config.Sizes[size]) then
		return false
	end
	return entry.rarity ~= nil or (metal == 0 and size == 0)
end

-- Limpia lo guardado: solo códigos que existen y sin repetir. nil si no había nada guardado (Índice sin estrenar).
function IndexInfo.sanitize(saved: unknown): { number }?
	if type(saved) ~= "table" then
		return nil
	end
	local list, seen = {}, {}
	for _, code in saved do
		if IndexInfo.valid(code) and not seen[code] then
			seen[code] = true
			table.insert(list, code)
		end
	end
	return list
end

-- Lista de códigos <-> texto del atributo `Index`.
function IndexInfo.encode(list: { number }): string
	return table.concat(list, ",")
end

-- Conjunto { [código] = true } a partir del atributo.
function IndexInfo.parse(text: string?): { [number]: boolean }
	local set = {}
	for entry in string.gmatch(text or "", "%d+") do
		set[tonumber(entry) :: number] = true
	end
	return set
end

-- Armas de Config.Swords de la más común a la más rara (la inicial, sin rareza, va la primera).
local ordered = {}
for index in Config.Swords do
	table.insert(ordered, index)
end
table.sort(ordered, function(a, b)
	local first, second = Config.Swords[a].rarity or 0, Config.Swords[b].rarity or 0
	return if first == second then a < b else first < second
end)

-- Armas (índices de Config.Swords) que tiene la vista de ese metal y ese tamaño, de la más común a la más rara.
function IndexInfo.swords(metal: number, size: number): { number }
	local list = {}
	for _, index in ordered do
		if IndexInfo.valid(IndexInfo.code(index, metal, size)) then
			table.insert(list, index)
		end
	end
	return list
end

-- Cuántas casillas tiene el Índice entero.
function IndexInfo.total(): number
	local views = (#Config.Metals + 1) * (#Config.Sizes + 1)
	local total = 0
	for _, sword in Config.Swords do
		total += if sword.rarity then views else 1
	end
	return total
end

return IndexInfo
