-- Misiones diarias y semanales: la lista de posibles y cómo se eligen. Cada día (y cada semana) todos los
-- jugadores tienen las mismas tres misiones, elegidas con una semilla fija a partir del número de día (o de
-- semana, empezando en lunes, hora UTC), así que servidor y cliente calculan lo mismo sin mandarse la lista.
-- La recompensa son Fichas de misión (Config.Items.missionToken), la moneda gratuita del juego.
local MissionList = {}

local DAY = 86400

-- kind = qué cuenta (lo suma server/Missions.add): "breaks" objetos rotos, "gacha" tiradas del gacha,
-- "traitRolls" rasgos tirados, "upgrades" mejoras compradas, "minutes" minutos jugados, "rebirth"
-- renacimientos y "rareSword" espadas de 1 entre 1M o más.
MissionList.pool = {
	daily = {
		{ id = "d_breaks60", kind = "breaks", goal = 60, reward = 2, text = "Rompe 60 objetos" },
		{ id = "d_breaks150", kind = "breaks", goal = 150, reward = 3, text = "Rompe 150 objetos" },
		{ id = "d_gacha15", kind = "gacha", goal = 15, reward = 2, text = "Tira el gacha 15 veces" },
		{ id = "d_gacha40", kind = "gacha", goal = 40, reward = 3, text = "Tira el gacha 40 veces" },
		{ id = "d_upgrades3", kind = "upgrades", goal = 3, reward = 2, text = "Compra 3 mejoras" },
		{ id = "d_minutes20", kind = "minutes", goal = 20, reward = 3, text = "Juega 20 minutos" },
		{ id = "d_traits5", kind = "traitRolls", goal = 5, reward = 3, text = "Tira 5 rasgos" },
	},
	weekly = {
		{ id = "w_breaks1000", kind = "breaks", goal = 1000, reward = 10, text = "Rompe 1000 objetos" },
		{ id = "w_gacha250", kind = "gacha", goal = 250, reward = 10, text = "Tira el gacha 250 veces" },
		{ id = "w_minutes180", kind = "minutes", goal = 180, reward = 12, text = "Juega 3 horas" },
		{ id = "w_upgrades25", kind = "upgrades", goal = 25, reward = 10, text = "Compra 25 mejoras" },
		{ id = "w_traits50", kind = "traitRolls", goal = 50, reward = 12, text = "Tira 50 rasgos" },
		{ id = "w_rebirth1", kind = "rebirth", goal = 1, reward = 15, text = "Renace una vez" },
		{ id = "w_rare3", kind = "rareSword", goal = 3, reward = 15, text = "Saca 3 espadas de 1 entre 1M o más" },
	},
}

MissionList.PER_PERIOD = 3

-- Números de día y de semana (UTC) del instante `now` (segundos Unix).
function MissionList.dayId(now: number): number
	return math.floor(now / DAY)
end

-- Las semanas empiezan en lunes: el 1 de enero de 1970 fue jueves, de ahí el +3.
function MissionList.weekId(now: number): number
	return math.floor((MissionList.dayId(now) + 3) / 7)
end

function MissionList.periodId(period: string, now: number): number
	return if period == "daily" then MissionList.dayId(now) else MissionList.weekId(now)
end

-- Segundos que faltan para que cambie el día o la semana.
function MissionList.secondsLeft(period: string, now: number): number
	if period == "daily" then
		return DAY - now % DAY
	end
	local startOfNextWeek = (MissionList.weekId(now) + 1) * 7 * DAY - 3 * DAY
	return startOfNextWeek - now
end

-- Las misiones de ese periodo y número (lista de PER_PERIOD, siempre la misma para el mismo número).
function MissionList.pick(period: string, id: number)
	local pool = table.clone(MissionList.pool[period])
	local random = Random.new(id * 2 + (if period == "daily" then 0 else 1))
	for index = #pool, 2, -1 do
		local other = random:NextInteger(1, index)
		pool[index], pool[other] = pool[other], pool[index]
	end
	local result = {}
	for index = 1, MissionList.PER_PERIOD do
		result[index] = pool[index]
	end
	return result
end

return MissionList
