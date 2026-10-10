-- Eventos de clima (Config.Weather). Cada tramo de `Interval` segundos empieza un clima que dura un rato y da suerte a
-- todos (shared/Stats lo lee de aquí); el resto del tramo está despejado. Cada servidor lleva el suyo (pedido por el
-- usuario): los tramos se cuentan desde que arrancó este servidor, el primero va despejado (el primer clima llega
-- cuando lleva `Interval` segundos abierto) y el clima de cada tramo se tira con una semilla propia. El servidor solo
-- publica el estado en atributos de workspace ("Weather", "WeatherStart", "WeatherEnds": ver shared/WeatherInfo); todo
-- lo que se ve lo hace cada cliente (client/Weather).
-- La cuenta atrás del siguiente clima no la ve nadie (pedido por el usuario: ver "faltan 30 min" invita a salirse):
-- "WeatherSoon" solo se publica cuando faltan menos de `Warning` segundos, para el aviso de "se acerca un clima", y la
-- hora entera solo se manda a los administradores (remote WeatherSchedule).
-- Un administrador (server/Admin) puede poner un clima a mano en su servidor desde el menú de admin (remote
-- AdminWeather): dura lo que dura ese clima (o hasta el siguiente tramo, si es despejar) y luego vuelve el de la hora;
-- "WeatherForced" dice si el que hay está puesto a mano. Para pruebas, solo en Studio: Config.Test.Weather pone uno al
-- entrar y el atributo "WeatherForce" de workspace lo cambia en marcha (un id de Config.Weather.Events, o "none").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)
local Admin = require(script.Parent.Admin)

local Weather = {}

-- Semilla del calendario de este servidor: cada uno saca la suya al arrancar, así que cada servidor tira sus climas.
-- Solo está aquí (el cliente no la tiene), así nadie puede calcular qué clima viene después.
local SEED = Random.new():NextInteger(1, 1e9)

local STUDIO = RunService:IsStudio()
local cfg = Config.Weather

local shown: string? = nil -- id publicado ("" = despejado); nil = aún nada
local shownEnds = 0
local forced: string? = nil
local forcedAt = 0
local shownSoon: number? = nil -- hora (del reloj de aquí) del clima que está al caer, mientras se avisa a todos
local shownNext: number? = nil -- hora del siguiente clima, la que tienen los administradores

local function wallClock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local born = wallClock() -- cuándo arrancó este servidor: desde aquí se cuentan los tramos

-- Tramo de esa hora (0 = el primero) y cuándo empezó.
local function slotAt(now: number): (number, number)
	local slot = math.max(0, math.floor((now - born) / cfg.Interval))
	return slot, born + slot * cfg.Interval
end

-- Lo que toca a esa hora según el calendario: id ("" = despejado), desde cuándo, hasta cuándo y cuándo empieza el siguiente.
local function scheduled(now: number): (string, number, number, number)
	local slot, start = slotAt(now)
	local nextStart = start + cfg.Interval
	if slot == 0 then
		return "", start, nextStart, nextStart
	end
	local id = WeatherInfo.pick(slot, SEED)
	local ends = start + WeatherInfo.duration(id)
	if now < ends then
		return id, start, ends, nextStart
	end
	return "", ends, nextStart, nextStart
end

-- Lo mismo, contando lo forzado (`forced`: un id de clima o "none" = despejado), que dura lo que ese clima o, si es
-- despejar, hasta el siguiente tramo; después vuelve el del calendario.
local function wanted(now: number): (string, number, number, number)
	if forced then
		local nextStart = select(2, slotAt(forcedAt)) + cfg.Interval
		local ends = if forced == "none" then nextStart else forcedAt + WeatherInfo.duration(forced)
		if now < ends then
			return if forced == "none" then "" else forced, forcedAt, ends, math.max(nextStart, ends)
		end
		forced = nil
		if STUDIO then
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

-- Manda la hora del siguiente clima a ese jugador si es administrador.
local function tellAdmin(player: Player)
	if shownNext and Admin.is(player) then
		Remotes.WeatherSchedule:FireClient(player, shownNext + workspace:GetServerTimeNow() - wallClock())
	end
end

local function update()
	local now = wallClock()
	local id, start, ends, nextStart = wanted(now)
	workspace:SetAttribute("WeatherForced", forced ~= nil) -- para el menú de admin: ¿es del calendario o puesto a mano?
	-- Las horas se publican en el reloj que comparten servidor y clientes.
	local offset = workspace:GetServerTimeNow() - now
	-- Cuándo llega el siguiente: a todos, solo cuando ya está al caer; entero, solo a los administradores.
	local soon = if id == "" and nextStart - now <= cfg.Warning then nextStart else nil
	if (soon ~= nil) ~= (shownSoon ~= nil) or (soon and shownSoon and math.abs(soon - shownSoon) >= 0.5) then
		shownSoon = soon
		workspace:SetAttribute("WeatherSoon", if soon then soon + offset else nil)
	end
	if not shownNext or math.abs(nextStart - shownNext) >= 0.5 then
		shownNext = nextStart
		for _, player in Players:GetPlayers() do
			tellAdmin(player)
		end
	end
	if id == shown and math.abs(ends - shownEnds) < 0.5 then
		return
	end
	workspace:SetAttribute("WeatherStart", start + offset)
	workspace:SetAttribute("WeatherEnds", ends + offset)
	workspace:SetAttribute("Weather", id) -- el último: quien lo escucha ya tiene las horas puestas
	if id ~= "" and id ~= shown then
		announce(id)
	end
	shown, shownEnds = id, ends
end

-- Pone un clima a mano (un id, o "none" para despejar) desde ahora, o vuelve al del calendario (nil o algo que no valga).
local function force(value: unknown)
	forced = if type(value) == "string" and (value == "none" or cfg.Events[value]) then value else nil
	forcedAt = wallClock()
	update()
end

function Weather.start()
	if STUDIO then
		local initial = Config.Test.Weather
		if type(initial) == "string" and cfg.Events[initial] then
			workspace:SetAttribute("WeatherForce", initial)
		end
		workspace:GetAttributeChangedSignal("WeatherForce"):Connect(function()
			local value = workspace:GetAttribute("WeatherForce")
			if value ~= forced then
				force(value)
			end
		end)
		force(workspace:GetAttribute("WeatherForce"))
	end

	-- Órdenes del menú de admin, solo de administradores (server/Admin): un id de clima, "none" (despejar), "auto"
	-- (volver al calendario) o "next" (el siguiente de la lista y, tras el último, despejado). Vale para este servidor.
	Remotes.AdminWeather.OnServerEvent:Connect(function(player: Player, action: unknown)
		if not Admin.is(player) or type(action) ~= "string" then
			return
		end
		if action == "next" then
			local index = table.find(cfg.Order, shown or "") or 0
			force(cfg.Order[index + 1] or "none")
		elseif action == "auto" then
			force(nil)
		elseif action == "none" or cfg.Events[action] then
			force(action)
		end
	end)

	-- La hora del siguiente clima: a cada administrador al entrar (server/Admin lo decide con algo de retraso y lo
	-- publica en su atributo "Admin") y, desde `update`, cada vez que cambia.
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Admin"):Connect(function()
			tellAdmin(player)
		end)
		tellAdmin(player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
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
