-- Carga los módulos de src/shared de verdad (Config, ObjectSpec, Stats...) fuera de Roblox, con Lune, para que la
-- herramienta de equilibrio haga las cuentas con el mismo código y los mismos números que el juego.
-- Lo único que se sustituye es el motor: Random (por math.random), workspace (solo sus atributos) y game.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Cargar = {}

-- Generador con la misma interfaz que Random de Roblox.
local Azar = {}
Azar.__index = Azar
function Azar.new(seed: number?)
	if seed then
		math.randomseed(seed)
	end
	return setmetatable({}, Azar)
end
function Azar:NextNumber(low: number?, high: number?): number
	if low then
		return low + math.random() * ((high :: number) - low)
	end
	return math.random()
end
function Azar:NextInteger(low: number, high: number): number
	return math.random(low, high)
end

-- Ruta que se comporta como una instancia: script.Parent.Config -> "src/shared/Config".
local function node(path: string)
	return setmetatable({ path = path }, {
		__index = function(_, key)
			return node(if key == "Parent" then path:match("^(.*)/[^/]+$") else path .. "/" .. key)
		end,
	})
end

-- Devuelve `shared(nombre)` (carga un módulo de src/shared) y `mundo` (los atributos de workspace: el clima).
function Cargar.nuevo()
	local atributos = {}
	local workspace = {
		GetAttribute = function(_, name)
			return atributos[name]
		end,
		GetServerTimeNow = function()
			return 0
		end,
	}
	local services = { ReplicatedStorage = { Shared = node("src/shared") }, HttpService = {} }
	local cache = {}
	local function load(path: string)
		if cache[path] then
			return cache[path]
		end
		local env = table.clone(roblox)
		env.script = node(path)
		env.workspace = workspace
		env.game = {
			GetService = function(_, name)
				return assert(services[name], "Servicio sin adaptar: " .. name)
			end,
		}
		env.require = function(ref)
			return load(ref.path)
		end
		env.Random = Azar
		cache[path] = luau.load(fs.readFile(path .. ".luau"), { debugName = path, environment = env, injectGlobals = true })()
		return cache[path]
	end
	return function(name: string)
		return load("src/shared/" .. name)
	end, atributos
end

return Cargar
