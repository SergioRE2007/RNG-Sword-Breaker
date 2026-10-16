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

-- Lo que le toca a un jugador cuando se va el rey. `share` = su parte (0 a 1) de todo el daño hecho en la arena; `rank` = su
-- puesto. nil si no llega a MinShare.
function WorldBossInfo.rewards(share: number, rank: number)
	local r = cfg.Rewards
	if share ~= share or share < r.MinShare then
		return nil
	end
	local rolls = math.clamp(math.floor(r.RollsBase + share * r.RollsPerShare), 1, r.MaxRolls)
	if rank <= 3 then
		rolls = math.min(rolls + r.TopBonusRolls, r.MaxRolls)
	end
	return {
		rolls = rolls,
		traitCrystal = math.min(math.ceil(r.Trait.base + share * r.Trait.perShare), r.Trait.max),
		gradeCrystal = math.min(math.ceil(r.Grade.base + share * r.Grade.perShare), r.Grade.max),
		tickets = r.Tickets[rank] or 0,
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
