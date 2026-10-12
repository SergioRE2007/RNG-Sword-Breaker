-- Idioma del juego. En el código los textos van en inglés y esta librería los pasa al idioma de quien los va a leer:
-- español (la tabla de shared/LangEs) para quien tiene Roblox en español, inglés para los demás (los otros idiomas los
-- traduce Roblox a partir del inglés). Vale en servidor y cliente.
--   Lang.t(jugador, "Minimum damage {n}", { n = "1.5K" })  -> "Daño mínimo 1,5K" o "Minimum damage 1.5K"
-- En el cliente el idioma es siempre el del jugador local (da igual a quién se le pase). En el servidor hay que pasar
-- el jugador que va a leer el texto; sin él sale en inglés.
-- Qué idioma es: el que el jugador tiene elegido para esta experiencia en el menú de Roblox (Ajustes → Idioma), que
-- de primeras es el de su cuenta. Lo averigua client/Language al arrancar (Lang.set) y se lo dice al servidor, que lo
-- guarda en el atributo "Lang" del jugador (server/Language); hasta entonces vale el idioma de su cuenta.
-- Un texto nuevo = escribirlo en inglés y añadir su entrada en LangEs, con los mismos huecos {así}.
local Config = require(script.Parent.Config)

local Lang = {}

Lang.es = require(script.Parent.LangEs)

-- Los servicios se piden con cuidado: las pruebas y tools/equilibrio cargan este módulo fuera de Roblox.
local function service(name: string)
	local ok, found = pcall(function()
		return game:GetService(name)
	end)
	return if ok then found else nil
end

local function ask(object, method: string): boolean
	local ok, result = pcall(function()
		return object[method](object)
	end)
	return ok and result == true
end

local RunService = service("RunService")
local isStudio = RunService ~= nil and ask(RunService, "IsStudio")
local isClient = RunService ~= nil and ask(RunService, "IsClient")

local function fromLocale(locale: unknown): string
	return if type(locale) == "string" and string.sub(string.lower(locale), 1, 2) == "es" then "es" else "en"
end

local localCode: string? = nil

-- "es" o "en" de un código de Roblox ("es-es", "en-us"...).
function Lang.fromLocale(locale: unknown): string
	return fromLocale(locale)
end

-- Solo en el cliente: el idioma del jugador local (client/Language).
function Lang.set(code: string)
	localCode = if code == "es" then "es" else "en"
end

-- "es" o "en": el idioma en el que hay que escribirle a ese jugador. Config.Test.Lang lo fuerza en Studio.
function Lang.code(player: Player?): string
	local forced = Config.Test.Lang
	if isStudio and (forced == "es" or forced == "en") then
		return forced
	end
	if isClient then
		if not localCode then
			local ok, locale = pcall(function()
				return game:GetService("LocalizationService").RobloxLocaleId
			end)
			localCode = fromLocale(if ok then locale else nil)
		end
		return localCode :: string
	end
	if player then
		-- Lo que dijo su cliente (el idioma elegido en el menú de Roblox) manda sobre el de su cuenta.
		local okSaid, said = pcall(function()
			return player:GetAttribute("Lang")
		end)
		if okSaid and (said == "es" or said == "en") then
			return said
		end
		local ok, locale = pcall(function()
			return player.LocaleId
		end)
		return fromLocale(if ok then locale else nil)
	end
	return "en"
end

local missing = {}

-- El texto (en inglés) en el idioma de ese jugador, con los huecos {nombre} rellenos con `args`.
function Lang.t(player: Player?, text: string, args: { [string]: any }?): string
	local result = text
	if Lang.code(player) == "es" then
		local found = Lang.es[text]
		if found then
			result = found
		elseif isStudio and not missing[text] then
			missing[text] = true
			warn(`[Lang] Falta en LangEs: "{text}"`)
		end
	end
	if args then
		result = string.gsub(result, "{(%w+)}", function(key)
			local value = args[key]
			return if value ~= nil then tostring(value) else nil
		end)
	end
	return result
end

-- Un número ya escrito ("1.5K", "24.8%") con la coma decimal de ese idioma: "1,5K" en español.
function Lang.decimal(player: Player?, text: string): string
	if Lang.code(player) == "es" and string.find(text, ".", 1, true) then
		return (string.gsub(text, "%.", ","))
	end
	return text
end

return Lang
