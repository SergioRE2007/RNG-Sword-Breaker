-- Eventos de admin (Config.AdminEvents): un multiplicador de un stat para todos durante un rato, y el mensaje grande.
-- Los pide server/AdminCommands (que es quien comprueba que la orden es de un administrador); aquí se guarda el estado
-- y se publica en workspace, de donde lo leen shared/Stats (Stats.boost) y el HUD de cada cliente (client/BoostHud):
--   "Boost_<stat>" = por cuánto multiplica y "BoostEnd_<stat>" = hasta cuándo (hora de GetServerTimeNow).
-- Un evento puede valer solo en este servidor o en todos. Los de todos se mandan con server/Broadcast y además se
-- apuntan en un MemoryStore (con caducidad, la del evento), que cada servidor mira al arrancar y cada POLL segundos:
-- así lo tiene también un servidor que abre a mitad del evento o al que se le pierde el aviso. En Studio no hay
-- MemoryStore ni más servidores: el evento vale en esa partida.
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Broadcast = require(script.Parent.Broadcast)
local Tell = require(script.Parent.Tell)

local AdminEvents = {}

local cfg = Config.AdminEvents
local MAP = "AdminBoosts"
local POLL = 60 -- cada cuánto se mira el MemoryStore
local SWEEP = 5 -- cada cuánto se retiran los caducados

-- [stat] = { mult, ends = hora Unix a la que acaba, global = vale en todos los servidores }
local active: { [string]: { mult: number, ends: number, global: boolean } } = {}
local map = nil

local function unix(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function store()
	if map == nil then
		local ok, result = pcall(function()
			return MemoryStoreService:GetHashMap(MAP)
		end)
		map = if ok then result else false
	end
	return map
end

-- ¿Vale ese evento? No se da nada por bueno: también llega de otros servidores y de lo guardado.
local function valid(stat: unknown, mult: unknown, ends: unknown): boolean
	if type(stat) ~= "string" or not cfg.Stats[stat] then
		return false
	end
	if type(mult) ~= "number" or mult ~= mult or mult <= 1 or mult > cfg.MaxMult then
		return false
	end
	local left = if type(ends) == "number" and ends == ends then ends - unix() else 0
	return left > 0 and left <= cfg.MaxMinutes * 60 + 60
end

local function publish(stat: string)
	local entry = active[stat]
	if entry and entry.ends > unix() then
		workspace:SetAttribute("BoostEnd_" .. stat, workspace:GetServerTimeNow() + entry.ends - unix())
		workspace:SetAttribute("Boost_" .. stat, entry.mult) -- el último: quien lo escucha ya tiene la hora puesta
	else
		active[stat] = nil
		workspace:SetAttribute("Boost_" .. stat, nil)
		workspace:SetAttribute("BoostEnd_" .. stat, nil)
	end
end

local function apply(stat: unknown, mult: unknown, ends: unknown, global: boolean)
	if not valid(stat, mult, ends) then
		return
	end
	local old = active[stat :: string]
	local same = old ~= nil and old.mult == mult and math.abs(old.ends - (ends :: number)) < 2
	active[stat :: string] = { mult = mult :: number, ends = ends :: number, global = global }
	publish(stat :: string)
	if not same then
		local def = cfg.Stats[stat :: string]
		local minutes = math.max(1, math.floor(((ends :: number) - unix()) / 60 + 0.5))
		Tell.all(def.color, function(reader)
			return Lang.t(reader, "Admin event! x{n} {stat} for everyone for {minutes} min.", { n = Format.multiplier(mult :: number, reader), stat = Lang.t(reader, def.name), minutes = minutes })
		end)
	end
end

local function clear(stat: unknown)
	if type(stat) == "string" and active[stat] then
		active[stat] = nil
		publish(stat)
	end
end

-- Empieza un evento. Devuelve si la orden valía.
function AdminEvents.boost(stat: unknown, mult: unknown, minutes: unknown, global: boolean): boolean
	if type(mult) ~= "number" or type(minutes) ~= "number" or minutes ~= minutes or minutes < 1 or minutes > cfg.MaxMinutes then
		return false
	end
	local rounded = math.floor(mult * 100 + 0.5) / 100
	local ends = unix() + math.floor(minutes) * 60
	if not valid(stat, rounded, ends) then
		return false
	end
	if not global then
		apply(stat, rounded, ends, false)
		return true
	end
	local memory = store()
	if memory then
		pcall(function()
			memory:SetAsync(stat, { mult = rounded, ends = ends }, math.floor(minutes) * 60)
		end)
	end
	Broadcast.send("boost", { stat = stat, mult = rounded, ends = ends })
	return true
end

-- Corta el evento de ese stat (en todos los servidores, si `global`).
function AdminEvents.stop(stat: unknown, global: boolean): boolean
	if type(stat) ~= "string" or not cfg.Stats[stat] then
		return false
	end
	if not global then
		clear(stat)
		return true
	end
	local memory = store()
	if memory then
		pcall(function()
			memory:RemoveAsync(stat)
		end)
	end
	Broadcast.send("stopBoost", { stat = stat })
	return true
end

-- Mensaje grande en la pantalla de todos (el texto llega ya filtrado por Roblox: server/AdminCommands).
function AdminEvents.banner(text: string, global: boolean)
	if global then
		Broadcast.send("banner", { text = text })
	else
		Remotes.AdminBanner:FireAllClients(text)
	end
end

-- Lo apuntado en el MemoryStore manda sobre lo que este servidor crea de los eventos de todos los servidores.
local function poll()
	local memory = store()
	if not memory then
		return
	end
	for _, stat in cfg.Order do
		local ok, saved = pcall(function()
			return memory:GetAsync(stat)
		end)
		if not ok then
			return -- sin acceso (Studio) o sin cupo: se queda como está
		end
		if type(saved) == "table" and valid(stat, saved.mult, saved.ends) then
			apply(stat, saved.mult, saved.ends, true)
		elseif active[stat] and active[stat].global then
			clear(stat)
		end
	end
end

function AdminEvents.start()
	Broadcast.on("boost", function(data)
		if type(data) == "table" then
			apply(data.stat, data.mult, data.ends, true)
		end
	end)
	Broadcast.on("stopBoost", function(data)
		if type(data) == "table" then
			clear(data.stat)
		end
	end)
	Broadcast.on("banner", function(data)
		if type(data) == "table" and type(data.text) == "string" and #data.text <= cfg.MaxMessage * 4 then
			Remotes.AdminBanner:FireAllClients(data.text)
		end
	end)
	task.spawn(function()
		while true do
			poll()
			task.wait(POLL)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SWEEP)
			for stat in active do
				publish(stat)
			end
		end
	end)
end

return AdminEvents
