-- Armadura: lectura del inventario, totales de lo equipado y textos de cada pieza (Config.Armor).
-- Vale en servidor y cliente. Una pieza es { id, uid, v, slot, quality, level, stats = { { stat, value, bonus } } }:
-- slot = clave de Config.Armor.Slots, quality = índice de Config.Armor.Qualities, level = índice de
-- Config.Dungeons (la dificultad donde cayó), stats = sus valores ya tirados (bonus = modificador extra, solo en las
-- antiguas), uid = identificador único de esa pieza (no cambia nunca, a diferencia de `id`, que es su posición en el
-- inventario), v = 2 si salió del generador de estadísticas aleatorias (nil = pieza antigua, que conserva sus stats).
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)
local Lang = require(script.Parent.Lang)

local ArmorStats = {}

local cfg = Config.Armor

-- Texto del atributo "Armor": el inventario con `worn = true` en las piezas equipadas.
function ArmorStats.encode(pieces, worn): string
	local list = {}
	for _, piece in pieces do
		table.insert(list, {
			id = piece.id,
			slot = piece.slot,
			quality = piece.quality,
			level = piece.level,
			stats = piece.stats,
			uid = piece.uid,
			v = piece.v,
			worn = worn[piece.slot] == piece.id or nil,
		})
	end
	return HttpService:JSONEncode(list)
end

local cache = setmetatable({}, { __mode = "k" }) -- [Player] = { raw, pieces }

-- Piezas del jugador (leídas de su atributo "Armor"), cada una con `worn`.
function ArmorStats.pieces(player: Player)
	local raw = player:GetAttribute("Armor")
	if type(raw) ~= "string" then
		return {}
	end
	local cached = cache[player]
	if cached and cached.raw == raw then
		return cached.pieces
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	local pieces = if ok and type(decoded) == "table" then decoded else {}
	cache[player] = { raw = raw, pieces = pieces }
	return pieces
end

-- Suma de cada stat de las piezas equipadas: { health = 0, damage = 0, ... } (siempre con todos los stats).
function ArmorStats.total(pieces, worn)
	local totals = {}
	for _, stat in cfg.StatOrder do
		totals[stat] = 0
	end
	for _, piece in pieces do
		if worn[piece.slot] == piece.id then
			for _, entry in piece.stats do
				if totals[entry.stat] then
					totals[entry.stat] += entry.value
				end
			end
		end
	end
	return totals
end

-- "Leather Helmet" / "Casco de cuero": el "set" de la zona es la frase entera, con el hueco {slot} para la pieza.
function ArmorStats.name(piece, player: Player?): string
	return Lang.t(player, Config.Dungeons[piece.level].set, { slot = Lang.t(player, cfg.Slots[piece.slot].name) })
end

function ArmorStats.quality(piece)
	return cfg.Qualities[piece.quality]
end

-- "+120" para la vida y "+7.5%" para los porcentajes.
function ArmorStats.value(stat: string, value: number, player: Player?): string
	if cfg.Stats[stat].flat then
		return "+" .. Format.short(value, player)
	end
	return `+{Format.multiplier(value * 100, player)}%`
end

-- "+120 Max Health".
function ArmorStats.text(stat: string, value: number, player: Player?): string
	return `{ArmorStats.value(stat, value, player)} {Lang.t(player, cfg.Stats[stat].name)}`
end

-- Por cuánto se multiplica un stat de la armadura según la zona donde cae (índice de Config.Dungeons): la vida, por el
-- "power" de la zona (va a la par del daño de sus enemigos); los porcentajes (suerte, ataque), por su "bonus", que
-- crece mucho más despacio para que la armadura ayude sin tapar al resto de fuentes; los de scales = false, por nada.
function ArmorStats.scaling(stat: string, level: number): number
	local info = cfg.Stats[stat]
	if info.scales == false then
		return 1
	end
	local dungeon = Config.Dungeons[level]
	return if info.flat then dungeon.power else dungeon.bonus or 1
end

local gen = cfg.Generator
local priority = cfg.Priority

-- Identificador único de una pieza (se pone una sola vez, al conseguirla; las antiguas lo reciben al cargar).
function ArmorStats.uid(): string
	return HttpService:GenerateGUID(false)
end

-- Lo que da una pieza de UNA sola stat en ese hueco, calidad y zona con tirada media: la referencia del presupuesto.
function ArmorStats.reference(stat: string, slot: string, quality: number, level: number): number
	return gen.Reference[stat] * cfg.Slots[slot].weight * cfg.Qualities[quality].mult * ArmorStats.scaling(stat, level)
end

-- Pieza NUEVA: 1 a 4 stats distintas de gen.Pool (probabilidades de gen.Count) que se reparten el presupuesto de poder
-- gen.Budget[n] (shared: lo usan el servidor, que es quien tira, y el simulador de tools/equilibrio). `rng` solo necesita
-- :NextNumber(). Devuelve la lista { { stat, value } } en el orden de cfg.StatOrder; la vida va en enteros y los
-- porcentajes en décimas de punto.
function ArmorStats.generate(slot: string, quality: number, level: number, rng)
	local total = 0
	for _, chance in gen.Count do
		total += chance
	end
	local count, pick = #gen.Count, rng:NextNumber() * total
	for n, chance in gen.Count do
		pick -= chance
		if pick < 0 then
			count = n
			break
		end
	end
	count = math.min(count, #gen.Pool)
	-- Baraja parcial: las `count` primeras de la lista son las elegidas, sin repetir.
	local pool = table.clone(gen.Pool)
	local share, sum = {}, 0
	for i = 1, count do
		local j = i + math.floor(rng:NextNumber() * (#pool - i + 1))
		pool[i], pool[j] = pool[j], pool[i]
		share[pool[i]] = 1 + (rng:NextNumber() * 2 - 1) * gen.Split
		sum += share[pool[i]]
	end
	local roll = gen.Roll.min + rng:NextNumber() * (gen.Roll.max - gen.Roll.min)
	local stats = {}
	for _, stat in cfg.StatOrder do
		if share[stat] then
			local value = ArmorStats.reference(stat, slot, quality, level) * gen.Budget[count] * share[stat] / sum * roll
			table.insert(stats, {
				stat = stat,
				value = if cfg.Stats[stat].flat then math.max(1, math.round(value)) else math.max(0.001, math.round(value * 1000) / 1000),
			})
		end
	end
	return stats
end

-- Lo más que puede valer ese stat en una pieza de esa calidad y esa zona. PlayerData recorta con esto lo guardado:
-- vale lo mayor entre lo que podían dar las reglas antiguas (la base más alta entre huecos y modificadores, con la
-- mejor tirada) y lo que puede dar el generador nuevo (el hueco de más peso, la mejor tirada y el reparto más
-- favorable de su cantidad de stats), así ni una pieza nueva ni una antigua legítima se recortan.
function ArmorStats.cap(stat: string, quality: number, level: number): number
	local base = 0
	for _, slot in cfg.Slots do
		base = math.max(base, slot.stats[stat] or 0)
	end
	for _, mod in cfg.Mods do
		if mod.stat == stat then
			base = math.max(base, mod.value)
		end
	end
	local legacy = base * cfg.Roll.max * cfg.Qualities[quality].mult * ArmorStats.scaling(stat, level)
	if not table.find(gen.Pool, stat) then
		return legacy
	end
	local weight, factor = 0, 0
	for _, slot in cfg.Slots do
		weight = math.max(weight, slot.weight)
	end
	for n, budget in gen.Budget do
		local top = 1 + gen.Split
		factor = math.max(factor, budget * top / (top + (n - 1) * (1 - gen.Split)))
	end
	local generated = gen.Reference[stat] * weight * cfg.Qualities[quality].mult * ArmorStats.scaling(stat, level) * factor * gen.Roll.max * 1.001
	return math.max(legacy, generated)
end

-- Suma de cada stat de una lista de piezas (todas, sin mirar si están equipadas).
function ArmorStats.sum(pieces): { [string]: number }
	local totals = {}
	for _, stat in cfg.StatOrder do
		totals[stat] = 0
	end
	for _, piece in pieces do
		for _, entry in piece.stats do
			if totals[entry.stat] then
				totals[entry.stat] += entry.value
			end
		end
	end
	return totals
end

-- Cuánto vale un juego de totales para un modo de "Equipar mejores": suma de peso * ln(multiplicador final) de cada
-- stat (la vida cuenta contra la vida base; las demás, como 1 + %). Es un valor relativo: mide cuánto sube cada
-- multiplicador respecto a lo que ya se tiene, así 1.000.000 de vida y un 25 % de daño se comparan por lo que
-- mejoran de verdad y no por sus números crudos.
function ArmorStats.utility(totals: { [string]: number }, mode: string?): number
	local weights = priority.Weights[mode or ""] or priority.Weights[priority.Default]
	local sum = 0
	for _, stat in cfg.StatOrder do
		local weight = weights[stat]
		if weight then
			local value = totals[stat] or 0
			sum += weight * math.log(if stat == "health" then cfg.BaseHealth + value else 1 + value)
		end
	end
	return sum
end

-- Modo válido (el guardado o el pedido por el cliente), o el de por defecto.
function ArmorStats.mode(mode: unknown): string
	return if type(mode) == "string" and priority.Weights[mode] then mode else priority.Default
end

-- Qué pieza poner en cada hueco: la combinación (una por hueco) de más utilidad (ArmorStats.utility) para ese modo,
-- calculada con las demás piezas puestas a la vez (así tiene en cuenta lo que el jugador ya suma). `worn` = { [hueco] = id }
-- lo puesto ahora: ante un empate se queda lo que ya lleva. Solo habla de huecos con alguna pieza. Devuelve
-- { [hueco] = id }.
function ArmorStats.best(pieces, worn, mode: string?): { [string]: number }
	local lists, order = {}, {}
	for _, slot in cfg.SlotOrder do
		local list = {}
		for _, piece in pieces do
			if piece.slot == slot then
				table.insert(list, piece)
			end
		end
		if #list > 0 then
			table.sort(list, function(a, b)
				local aWorn, bWorn = worn[slot] == a.id, worn[slot] == b.id
				if aWorn ~= bWorn then
					return aWorn
				end
				return a.id < b.id
			end)
			lists[slot] = list
			table.insert(order, slot)
		end
	end
	local combos = 1
	for _, slot in order do
		combos *= #lists[slot]
	end

	local picked = {}
	if combos <= priority.SearchLimit then
		local bestValue = -math.huge
		local current = {}
		local function search(index: number, totals)
			if index > #order then
				local value = ArmorStats.utility(totals, mode)
				if value > bestValue + 1e-9 then
					bestValue = value
					picked = table.clone(current)
				end
				return
			end
			local slot = order[index]
			for _, piece in lists[slot] do
				local nextTotals = table.clone(totals)
				for _, entry in piece.stats do
					if nextTotals[entry.stat] then
						nextTotals[entry.stat] += entry.value
					end
				end
				current[slot] = piece.id
				search(index + 1, nextTotals)
			end
		end
		search(1, ArmorStats.sum({}))
		return picked
	end

	-- Demasiadas combinaciones: se mejora hueco a hueco hasta que nada cambia.
	local chosen = {}
	for _, slot in order do
		chosen[slot] = lists[slot][1]
	end
	for _ = 1, 8 do
		local changed = false
		for _, slot in order do
			local others = {}
			for other, piece in chosen do
				if other ~= slot then
					table.insert(others, piece)
				end
			end
			local base = ArmorStats.sum(others)
			local bestValue = -math.huge
			local bestPiece = chosen[slot]
			for _, piece in lists[slot] do
				local totals = table.clone(base)
				for _, entry in piece.stats do
					if totals[entry.stat] then
						totals[entry.stat] += entry.value
					end
				end
				local value = ArmorStats.utility(totals, mode)
				if value > bestValue + 1e-9 then
					bestValue, bestPiece = value, piece
				end
			end
			if bestPiece ~= chosen[slot] then
				chosen[slot] = bestPiece
				changed = true
			end
		end
		if not changed then
			break
		end
	end
	for slot, piece in chosen do
		picked[slot] = piece.id
	end
	return picked
end

-- Valor de un stat en una pieza (0 si no lo tiene).
function ArmorStats.statOf(piece, stat: string): number
	local value = 0
	for _, entry in piece.stats do
		if entry.stat == stat then
			value += entry.value
		end
	end
	return value
end

-- Qué se gana y qué se pierde al cambiar `other` (la equipada en ese hueco, o nil) por `piece`: una fila por stat que
-- tenga alguna de las dos, { stat, value = nueva, old = actual, delta = nueva - actual }, en el orden de cfg.StatOrder.
function ArmorStats.compare(piece, other)
	local rows = {}
	for _, stat in cfg.StatOrder do
		local value = ArmorStats.statOf(piece, stat)
		local old = if other then ArmorStats.statOf(other, stat) else 0
		if value > 0 or old > 0 then
			table.insert(rows, { stat = stat, value = value, old = old, delta = value - old })
		end
	end
	return rows
end

-- Cristales de grado que da al desmontarla: solo cuenta su calidad (las corrientes no dan nada).
function ArmorStats.salvage(piece): number
	return cfg.Qualities[piece.quality].value
end

return ArmorStats
