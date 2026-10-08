-- Eventos de clima (Config.Weather). Cada tramo de `Interval` segundos empieza un clima que dura un rato y da suerte a
-- todos (shared/Stats lo lee de aquí); el resto del tramo está despejado. El clima de cada tramo sale de la hora y de
-- una semilla, así que es el mismo en todos los servidores a la vez sin guardar ni mandarse nada. El servidor solo
-- publica el estado en atributos de workspace ("Weather", "WeatherStart", "WeatherEnds", "WeatherNext": ver
-- shared/WeatherInfo); todo lo que se ve lo hace cada cliente (client/Weather).
-- Pruebas (solo en Studio): Config.Test.Weather pone un clima al entrar, el atributo "WeatherForce" de workspace lo
-- cambia en marcha (un id de Config.Weather.Events, o "none" para despejar) y el remote AdminWeather pasa al siguiente.
-- Lo forzado dura lo que dura ese clima (o hasta el siguiente tramo, si es "none") y luego vuelve el de la hora.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)

local Weather = {}

-- Semilla del calendario. Solo está aquí (el cliente no la tiene), así nadie puede calcular qué clima viene después.
local SALT = 48611

local STUDIO = RunService:IsStudio()
local cfg = Config.Weather

local shown: string? = nil -- id publicado ("" = despejado); nil = aún nada
local shownEnds = 0
local forced: string? = nil
local forcedAt = 0

local function wallClock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

-- Lo que toca a esa hora según el calendario: id ("" = despejado), desde cuándo, hasta cuándo y cuándo empieza el siguiente.
local function scheduled(now: number): (string, number, number, number)
	local slot = math.floor(now / cfg.Interval)
	local start = slot * cfg.Interval
	local nextStart = start + cfg.Interval
	local id = WeatherInfo.pick(slot, SALT)
	local ends = start + WeatherInfo.duration(id)
	if now < ends then
		return id, start, ends, nextStart
	end
	return "", ends, nextStart, nextStart
end

-- Lo mismo, contando lo que se haya forzado en Studio.
local function wanted(now: number): (string, number, number, number)
	if STUDIO then
		local force = workspace:GetAttribute("WeatherForce")
		if force ~= forced then
			forced = if type(force) == "string" and (force == "none" or cfg.Events[force]) then force else nil
			forcedAt = now
		end
		if forced then
			local nextStart = (math.floor(forcedAt / cfg.Interval) + 1) * cfg.Interval
			local ends = if forced == "none" then nextStart else forcedAt + WeatherInfo.duration(forced)
			if now < ends then
				return if forced == "none" then "" else forced, forcedAt, ends, math.max(nextStart, ends)
			end
			forced = nil
			workspace:SetAttribute("WeatherForce", nil)
		end
	end
	return scheduled(now)
end

local function announce(id: string)
	local def = cfg.Events[id]
	local minutes = math.floor(WeatherInfo.duration(id) / 60 + 0.5)
	Remotes.Announce:FireAllClients(`¡{def.name}! {WeatherInfo.buffText(def)} para todos durante {minutes} min.`, def.color)
end

local function update()
	local now = wallClock()
	local id, start, ends, nextStart = wanted(now)
	if id == shown and math.abs(ends - shownEnds) < 0.5 then
		return
	end
	-- Las horas se publican en el reloj que comparten servidor y clientes.
	local offset = workspace:GetServerTimeNow() - now
	workspace:SetAttribute("WeatherStart", start + offset)
	workspace:SetAttribute("WeatherEnds", ends + offset)
	workspace:SetAttribute("WeatherNext", nextStart + offset)
	workspace:SetAttribute("Weather", id) -- el último: quien lo escucha ya tiene las horas puestas
	if id ~= "" and id ~= shown then
		announce(id)
	end
	shown, shownEnds = id, ends
end

function Weather.start()
	if STUDIO then
		local initial = Config.Test.Weather
		if type(initial) == "string" and cfg.Events[initial] then
			workspace:SetAttribute("WeatherForce", initial)
		end
		workspace:GetAttributeChangedSignal("WeatherForce"):Connect(update)

		-- Tecla de pruebas del cliente: siguiente clima de la lista y, tras el último, despejado.
		Remotes.AdminWeather.OnServerEvent:Connect(function()
			if not Config.Test.Admin then
				return
			end
			local index = table.find(cfg.Order, shown or "") or 0
			workspace:SetAttribute("WeatherForce", cfg.Order[index + 1] or "none")
		end)
	end

	update()
	task.spawn(function()
		while true do
			task.wait(1)
			update()
		end
	end)
end

return Weather
