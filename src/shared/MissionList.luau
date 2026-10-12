-- Misiones diarias y semanales: la lista de posibles y cómo se eligen. Cada día (y cada semana) todos los
-- jugadores tienen las mismas tres misiones, elegidas con una semilla fija a partir del número de día (o de
-- semana, empezando en lunes, hora UTC), así que servidor y cliente calculan lo mismo sin mandarse la lista.
-- La recompensa son tickets (Config.Items.missionToken), la moneda gratuita del juego, con la que se compran los pases
-- de la Tienda. Lo que paga cada misión no va con ella sino con su puesto del día (REWARDS): así, salgan las que salgan,
-- un día da 50 tickets como mucho y una semana 200 (pedido por el usuario).
local MissionList = {}

local DAY = 86400

-- kind = qué cuenta (lo suma server/Missions.add): "breaks" objetos rotos, "gacha" tiradas de arma (las dan los objetos),
-- "traitRolls" rasgos tirados, "gradeRolls" grados tirados, "minutes" minutos jugados, "dungeons" mazmorras superadas,
-- "enemies" enemigos de mazmorra derrotados y "rareSword" armas de 1 entre 1M o más.
-- Pedido por el usuario: que sean de jugar de verdad (las primeras se hacían en un rato). No hay de comprar mejoras ni
-- de renacer: quien ya lo tiene todo no podría cumplirlas. "text" va en inglés: quien lo enseña lo pasa por Lang.t.
MissionList.pool = {
	daily = {
		{ id = "d_minutes30", kind = "minutes", goal = 30, text = "Play for 30 minutes" },
		{ id = "d_breaks1000", kind = "breaks", goal = 1000, text = "Break 1000 objects" },
		{ id = "d_gacha1000", kind = "gacha", goal = 1000, text = "Get 1000 weapon rolls" },
		{ id = "d_dungeons10", kind = "dungeons", goal = 10, text = "Clear 10 dungeons" },
		{ id = "d_enemies300", kind = "enemies", goal = 300, text = "Defeat 300 enemies" },
		{ id = "d_traits15", kind = "traitRolls", goal = 15, text = "Roll 15 traits" },
		{ id = "d_grades15", kind = "gradeRolls", goal = 15, text = "Forge 15 grades" },
	},
	weekly = {
		{ id = "w_dungeons100", kind = "dungeons", goal = 100, text = "Clear 100 dungeons" },
		{ id = "w_breaks20000", kind = "breaks", goal = 20000, text = "Break 20,000 objects" },
		{ id = "w_gacha20000", kind = "gacha", goal = 20000, text = "Get 20,000 weapon rolls" },
		{ id = "w_minutes600", kind = "minutes", goal = 600, text = "Play for 10 hours" },
		{ id = "w_enemies3000", kind = "enemies", goal = 3000, text = "Defeat 3000 enemies" },
		{ id = "w_traits150", kind = "traitRolls", goal = 150, text = "Roll 150 traits" },
		{ id = "w_grades150", kind = "gradeRolls", goal = 150, text = "Forge 150 grades" },
		{ id = "w_rare100", kind = "rareSword", goal = 100, text = "Get 100 weapons of 1 in 1M or rarer" },
	},
}

MissionList.PER_PERIOD = 3
-- Tickets de cada puesto: 50 al día y 200 a la semana entre las tres.
MissionList.REWARDS = { daily = { 15, 15, 20 }, weekly = { 60, 60, 80 } }

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
		local mission = table.clone(pool[index])
		mission.reward = MissionList.REWARDS[period][index]
		result[index] = mission
	end
	return result
end

return MissionList
