-- Cuentas y textos de las pociones (Config.Potions) para servidor y cliente: clave del objeto, por cuánto multiplica,
-- cuánto dura, cómo se escribe el tiempo que queda. Los números salen siempre de Config.
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local PotionInfo = {}

-- ¿Existe esa familia con ese tier? (para validar lo que llega del cliente)
function PotionInfo.valid(family: unknown, tier: unknown): boolean
	if type(family) ~= "string" or type(tier) ~= "number" then
		return false
	end
	local info = Config.Potions.Families[family]
	return info ~= nil and info.values[tier] ~= nil
end

-- Clave de la poción en Config.Items y en el inventario ("potion_damage_3").
function PotionInfo.key(family: string, tier: number): string
	return `potion_{family}_{tier}`
end

function PotionInfo.name(family: string, tier: number): string
	return Config.Items[PotionInfo.key(family, tier)].name
end

-- Nombre del tier ("III", "Divina") y su color (el de la rareza de esa posición).
function PotionInfo.tierName(tier: number): string
	return Config.Potions.Tiers[tier]
end

function PotionInfo.color(tier: number): Color3
	return Config.RarityTiers[tier].color
end

-- Por cuánto multiplica la poción de esa familia y tier (la de vida suma un %, así que es 1 + su valor). 1 si no existe.
function PotionInfo.multiplier(family: string, tier: number): number
	local info = Config.Potions.Families[family]
	local value = info and info.values[tier]
	if not value then
		return 1
	end
	return if info.additive then 1 + value else value
end

-- "Daño x1.55", "Vida máxima +50 %".
function PotionInfo.effect(family: string, tier: number): string
	local info = Config.Potions.Families[family]
	local value = info.values[tier]
	if info.additive then
		return `{info.effect} +{Format.multiplier(value * 100)} %`
	end
	return `{info.effect} x{Format.multiplier(value)}`
end

-- Duración de un tier en segundos de juego, y lo más que puede acumular sumando pociones iguales.
function PotionInfo.duration(tier: number): number
	return Config.Potions.Durations[tier]
end

function PotionInfo.cap(tier: number): number
	return Config.Potions.Durations[tier] * Config.Potions.MaxStack
end

-- 2700 -> "45 min", 5400 -> "90 min".
function PotionInfo.minutes(seconds: number): string
	return `{math.floor(seconds / 60 + 0.5)} min`
end

-- Pociones activas guardadas en los datos del jugador ({ [familia] = { tier, seconds } }) -> solo las válidas: familias y
-- tiers que existan y tiempo por delante, nunca más de lo que deja sumar el juego (por si cambia Config). Vale con
-- cualquier cosa (nil, texto, una tabla rara): lo que no cuadra se descarta, sin errores.
function PotionInfo.sanitize(saved: unknown): { [string]: { tier: number, seconds: number } }
	local result = {}
	if type(saved) ~= "table" then
		return result
	end
	for family, info in Config.Potions.Families do
		local entry = (saved :: any)[family]
		if type(entry) == "table" and type(entry.tier) == "number" and info.values[entry.tier] and type(entry.seconds) == "number" and entry.seconds > 0 then
			-- seconds > 0 descarta NaN y negativos; el tope recorta infinitos y lo que ya no cabe.
			result[family] = { tier = entry.tier, seconds = math.min(entry.seconds, PotionInfo.cap(entry.tier)) }
		end
	end
	return result
end

-- Tiempo que queda: "MM:SS" por debajo de una hora y "H:MM:SS" desde una hora.
function PotionInfo.clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local hours = seconds // 3600
	local minutes = seconds % 3600 // 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
	end
	return string.format("%02d:%02d", minutes, seconds % 60)
end

return PotionInfo
