-- Recompensas diarias (Config.DailyRewards): cuentas que comparten servidor y cliente y revisión de lo guardado.
-- data.daily = { day = número de día (MissionList.dayId), seconds = segundos jugados ese día, claimed = posiciones de
-- Config.DailyRewards.Playtime ya recogidas ese día (lista), streak = casilla de la semana que toca (1 a 7),
-- streakDay = día en que se recogió la última casilla de la semana (0 = nunca) }.
-- El servidor lo publica tal cual en el atributo "Daily" del jugador (JSON).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MissionList = require(ReplicatedStorage.Shared.MissionList)

local DailyInfo = {}

function DailyInfo.today(now: number?): number
	return MissionList.dayId(now or os.time())
end

-- Segundos que faltan para que cambie el día (a la vez que las misiones diarias).
function DailyInfo.secondsLeft(now: number?): number
	return MissionList.secondsLeft("daily", now or os.time())
end

-- Estado vacío, o el guardado revisado (números de verdad, posiciones que existen, sin repetir).
function DailyInfo.sanitize(saved: unknown)
	local state = { day = 0, seconds = 0, claimed = {}, streak = 1, streakDay = 0 }
	if type(saved) ~= "table" then
		return state
	end
	local function number(value: unknown): number?
		return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else nil
	end
	state.day = math.floor(number(saved.day) or 0)
	state.seconds = number(saved.seconds) or 0
	state.streakDay = math.floor(number(saved.streakDay) or 0)
	local streak = math.floor(number(saved.streak) or 1)
	state.streak = if streak >= 1 and streak <= #Config.DailyRewards.Streak then streak else 1
	if type(saved.claimed) == "table" then
		for _, position in saved.claimed do
			if type(position) == "number" and Config.DailyRewards.Playtime[position] and not table.find(state.claimed, position) then
				table.insert(state.claimed, position)
			end
		end
	end
	return state
end

-- Si ya ha cambiado el día: deja el tiempo y lo recogido a cero (la racha no se toca). Devuelve si ha cambiado algo.
function DailyInfo.roll(state, today: number): boolean
	if state.day == today then
		return false
	end
	state.day = today
	state.seconds = 0
	state.claimed = {}
	return true
end

-- Si la casilla de la semana de hoy está por recoger.
function DailyInfo.streakReady(state, today: number): boolean
	return state.streakDay ~= today
end

-- Si ese premio por tiempo se puede recoger ya.
function DailyInfo.playtimeReady(state, position: number, seconds: number): boolean
	local entry = Config.DailyRewards.Playtime[position]
	return entry ~= nil and not table.find(state.claimed, position) and seconds >= entry.minutes * 60
end

-- Cuántas cosas hay por recoger ahora mismo (para el aviso rojo del botón).
function DailyInfo.pending(state, today: number, seconds: number): number
	local count = if DailyInfo.streakReady(state, today) then 1 else 0
	for position in Config.DailyRewards.Playtime do
		if DailyInfo.playtimeReady(state, position, seconds) then
			count += 1
		end
	end
	return count
end

return DailyInfo
