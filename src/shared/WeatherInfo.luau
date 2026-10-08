-- Cuentas y textos del clima (Config.Weather) para servidor y cliente: qué clima hay, por cuánto multiplica cada
-- suerte, cuál toca en cada tramo y lo raro que es. El clima en curso lo publica server/Weather en atributos de
-- workspace: "Weather" (id, o "" si está despejado), "WeatherStart", "WeatherEnds" (cuándo empezó y cuándo acaba; con
-- el cielo despejado, desde y hasta cuándo) y "WeatherNext" (cuándo empieza el siguiente), en hora de GetServerTimeNow.
local Chance = require(script.Parent.Chance)
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local WeatherInfo = {}

-- Clima en curso: su id y su entrada de Config.Weather.Events; nil si está despejado.
function WeatherInfo.current(): (string?, { [string]: any }?)
	local id = workspace:GetAttribute("Weather")
	local def = if type(id) == "string" then Config.Weather.Events[id] else nil
	if def then
		return id, def
	end
	return nil, nil
end

-- Por cuánto multiplica el clima en curso esa suerte: "luck" (destructibles) o "weaponLuck" (armas). 1 si no la da.
function WeatherInfo.multiplier(stat: string): number
	local _, def = WeatherInfo.current()
	return if def then def[stat] or 1 else 1
end

-- Segundos que dura ese clima (nunca más que el tramo).
function WeatherInfo.duration(id: string): number
	local cfg = Config.Weather
	return math.min(cfg.Events[id].duration or cfg.Duration, cfg.Interval)
end

-- Clima del tramo número `slot` (la hora entre Config.Weather.Interval). Sale siempre el mismo para el mismo tramo y
-- la misma `salt`, que es como todos los servidores tienen el mismo clima a la vez; la sal la guarda el servidor.
-- Se prueba del más raro al más común y el primero de `Order` es el de relleno.
function WeatherInfo.pick(slot: number, salt: number): string
	local order = Config.Weather.Order
	local random = Random.new(slot * 7919 + salt)
	for index = #order, 2, -1 do
		if Chance.roll(1 / Config.Weather.Events[order[index]].rarity, random) then
			return order[index]
		end
	end
	return order[1]
end

-- Probabilidad real de que a un tramo le toque ese clima: a cada uno le quita sitio todo lo que es más raro que él,
-- así que no es 1 / "rarity" a secas. Es la que enseñan los carteles como "1 entre N".
function WeatherInfo.chance(id: string): number
	local order = Config.Weather.Order
	local left = 1
	for index = #order, 1, -1 do
		local p = if index == 1 then 1 else math.min(1 / Config.Weather.Events[order[index]].rarity, 1)
		if order[index] == id then
			return left * p
		end
		left *= 1 - p
	end
	return 0
end

-- "1 entre 6.2", "1 entre 151", "1 entre 500": con un decimal solo en los comunes.
function WeatherInfo.oddsText(id: string): string
	local chance = WeatherInfo.chance(id)
	local odds = if chance > 0 then 1 / chance else math.huge
	return `1 entre {Format.multiplier(if odds < 20 then math.floor(odds * 10 + 0.5) / 10 else math.floor(odds + 0.5))}`
end

-- Nombre y color de su rareza (Config.RarityTiers).
function WeatherInfo.tier(def: { [string]: any })
	return Config.RarityTiers[def.tier] or Config.RarityTiers[1]
end

-- Lo que da ese clima: { { name = "Suerte de destructibles", short = "Suerte", value = 2 }, ... }.
function WeatherInfo.buffs(def: { [string]: any }): { { name: string, short: string, value: number } }
	local list = {}
	if def.luck and def.luck ~= 1 then
		table.insert(list, { name = "Suerte de destructibles", short = "Suerte", value = def.luck })
	end
	if def.weaponLuck and def.weaponLuck ~= 1 then
		table.insert(list, { name = "Suerte de armas", short = "Armas", value = def.weaponLuck })
	end
	return list
end

-- "Suerte de destructibles x2 · Suerte de armas x1.5".
function WeatherInfo.buffText(def: { [string]: any }): string
	local parts = {}
	for _, buff in WeatherInfo.buffs(def) do
		table.insert(parts, `{buff.name} x{Format.multiplier(buff.value)}`)
	end
	return table.concat(parts, " · ")
end

return WeatherInfo
