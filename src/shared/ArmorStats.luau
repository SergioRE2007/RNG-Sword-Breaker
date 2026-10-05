-- Armadura: lectura del inventario, totales de lo equipado y textos de cada pieza (Config.Armor).
-- Vale en servidor y cliente. Una pieza es { id, slot, quality, level, stats = { { stat, value, bonus } } }:
-- slot = clave de Config.Armor.Slots, quality = índice de Config.Armor.Qualities, level = índice de
-- Config.Dungeons (la dificultad donde cayó), stats = sus valores ya tirados (bonus = modificador extra).
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

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

-- "Casco de cuero".
function ArmorStats.name(piece): string
	return `{cfg.Slots[piece.slot].name} {Config.Dungeons[piece.level].set}`
end

function ArmorStats.quality(piece)
	return cfg.Qualities[piece.quality]
end

-- "+120" para la vida y "+7.5%" para los porcentajes.
function ArmorStats.value(stat: string, value: number): string
	if cfg.Stats[stat].flat then
		return "+" .. Format.short(value)
	end
	return `+{Format.multiplier(value * 100)}%`
end

-- "+120 Vida máxima".
function ArmorStats.text(stat: string, value: number): string
	return `{ArmorStats.value(stat, value)} {cfg.Stats[stat].name}`
end

-- Cristales de grado que da al desmontarla.
function ArmorStats.salvage(piece): number
	return cfg.Qualities[piece.quality].value * Config.Dungeons[piece.level].loot
end

return ArmorStats
