-- Cuentas del Jefe del mundo (librería, sin start()): vida de lo que no es el rey (él no tiene), cuántas cosas salen
-- según los jugadores, premios y la hora del siguiente. Sin estado ni servicios, para que valgan igual en el servidor, en el cliente y en las pruebas de Lune.
-- Los números están en Config.WorldBoss.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBossInfo = {}

local cfg = Config.WorldBoss

-- Vida de un esbirro, cristal o barril: lo que quita un jugador medio en esos segundos.
function WorldBossInfo.minorHp(averageDps: number, seconds: number): number
	return math.max(averageDps * seconds, 1)
end

-- Cuántos salen de algo (globos, esbirros, cristales) con `players` jugadores en la arena.
function WorldBossInfo.count(def, players: number): number
	return math.clamp(math.floor(def.Base + def.PerPlayer * players + 0.5), 1, def.Max or math.huge)
end

-- Tramo de Rewards.Tiers al que llega ese daño (el más alto), o nil si no llega al primero.
function WorldBossInfo.tier(damage: number): number?
	local reached = nil
	for index, tier in cfg.Rewards.Tiers do
		if damage >= tier.damage then
			reached = index
		end
	end
	return reached
end

-- Lo que le toca a un jugador cuando se va el rey: el tramo de su daño (pedido por el usuario: por cantidad de daño, no
-- por porcentaje) y, si es de los tres que más daño han hecho (`rank`), las tiradas y los tickets del podio. nil si no
-- llega al primer tramo. potions = cuántas de cada familia, del tier potionTier.
function WorldBossInfo.rewards(damage: number, rank: number)
	local r = cfg.Rewards
	local index = if damage == damage then WorldBossInfo.tier(damage) else nil
	if not index then
		return nil
	end
	local tier = r.Tiers[index]
	local podium = rank <= 3
	return {
		tier = index,
		rolls = math.min(tier.rolls + (if podium then r.TopBonusRolls else 0), r.MaxRolls),
		traitCrystal = tier.crystals,
		gradeCrystal = tier.crystals,
		potions = tier.potions or 0,
		potionTier = tier.potionTier or 1,
		tickets = if podium then r.Tickets[rank] or 0 else 0,
	}
end

-- Hora de la siguiente caída después de `now` en un servidor que arrancó en `born` (las dos de GetServerTimeNow): a los
-- First segundos de abrir y luego cada Interval.
function WorldBossInfo.nextFall(now: number, born: number): number
	local first = born + cfg.First
	if now < first then
		return first
	end
	return first + (math.floor((now - first) / cfg.Interval) + 1) * cfg.Interval
end

-- Dónde está el portal del hub (en el suelo).
function WorldBossInfo.portalPosition(): Vector3
	local angle = math.rad(cfg.Portal.Angle)
	return Vector3.new(math.cos(angle) * cfg.Portal.Distance, Config.Plot.FloorHeight, math.sin(angle) * cfg.Portal.Distance)
end

-- "M:SS" de unos segundos.
function WorldBossInfo.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return WorldBossInfo
