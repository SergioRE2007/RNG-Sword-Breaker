-- Cambio de idioma en el momento (pedido por el usuario: antes había que volver a entrar). Los textos se escriben una
-- sola vez al montar cada ventana, así que al cambiar de idioma lo que ya está en pantalla se traduce aquí, con la
-- misma tabla de shared/LangEs al derecho o al revés: cada frase de un idioma se busca en el otro, y las que llevan
-- huecos {así} se reconocen por su parte fija (lo que va en el hueco se traduce también, y los números cambian la
-- coma decimal). Lo que se escribe después ya sale en el idioma nuevo (Lang.set). Para los textos que un módulo
-- guardó al arrancar y vuelve a poner más tarde, cada texto de la interfaz se vigila desde el primer cambio.
-- Librería sin start(): la usa client/Language.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Ui = require(script.Parent.Ui)

local LangSwap = {}

local CHUNK = 200 -- textos por cuadro al repasar
local MEMO_MAX = 4000 -- frases ya traducidas que se recuerdan (los relojes cambian cada segundo)
local MIN_FIXED = 3 -- letras fijas que necesita una frase con huecos para reconocerla (si no, casaría con todo)

local player = Players.LocalPlayer

type Entry = { pattern: string, upper: string, first: string?, firstUpper: string?, holes: { string }, to: string }
type Table = { exact: { [string]: string }, exactUpper: { [string]: string }, patterns: { Entry }, memo: { [string]: string | false }, size: number }

local tables: { [string]: Table } = {}
local current = { from = "en", to = "en" }
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local busy: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local watching = false

local function escape(text: string): string
	return (string.gsub(text, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Frase con huecos -> patrón que la reconoce, con un (.-) por hueco.
local function compile(template: string, upper: boolean): string
	local parts = {}
	local last = 1
	for start, finish in string.gmatch(template, "(){%w+}()") do
		local fixed = string.sub(template, last, start - 1)
		table.insert(parts, escape(if upper then Ui.upper(fixed) else fixed))
		table.insert(parts, "(.-)")
		last = finish
	end
	local fixed = string.sub(template, last)
	table.insert(parts, escape(if upper then Ui.upper(fixed) else fixed))
	return "^" .. table.concat(parts) .. "$"
end

-- La tabla para pasar de un idioma a otro ("es>en" o "en>es"), hecha la primera vez que se pide.
local function build(from: string, to: string): Table
	local key = from .. ">" .. to
	if tables[key] then
		return tables[key]
	end
	local result: Table = { exact = {}, exactUpper = {}, patterns = {}, memo = {}, size = 0 }
	for english, spanish in Lang.es do
		local source = if from == "es" then spanish else english
		local target = if from == "es" then english else spanish
		if source ~= target or string.find(source, "{%w+}") then
			if not string.find(source, "{%w+}") then
				if result.exact[source] == nil then
					result.exact[source] = target
				end
				local up = Ui.upper(source)
				if result.exactUpper[up] == nil then
					result.exactUpper[up] = target
				end
			else
				local fixed = string.gsub(string.gsub(source, "{%w+}", ""), "[%s%p]", "")
				if #fixed >= MIN_FIXED then
					local holes = {}
					for name in string.gmatch(source, "{(%w+)}") do
						table.insert(holes, name)
					end
					local startsFixed = string.sub(source, 1, 1) ~= "{"
					table.insert(result.patterns, {
						pattern = compile(source, false),
						upper = compile(source, true),
						first = if startsFixed then string.sub(source, 1, 1) else nil,
						firstUpper = if startsFixed then string.sub(Ui.upper(source), 1, 1) else nil,
						holes = holes,
						to = target,
						fixed = #fixed,
					} :: any)
				end
			end
		end
	end
	-- Las más largas primero: "Equip best" antes que "Equip {x}".
	table.sort(result.patterns, function(a: any, b: any)
		return a.fixed > b.fixed
	end)
	tables[key] = result
	return result
end

-- La coma decimal del otro idioma en un número suelto ("1,5K" <-> "1.5K"). Solo en textos sin palabras.
local function number(text: string, to: string): string?
	if string.find(text, "%a%a%a") or not string.find(text, "%d[%.,]%d") then
		return nil
	end
	local swapped = string.gsub(text, "(%d)[%.,](%d)", if to == "es" then "%1,%2" else "%1.%2")
	return if swapped ~= text then swapped else nil
end

local translate: (text: string, from: string, to: string, depth: number) -> string?

local SEPARATOR = "·" -- los textos montados a trozos los separan con esto ("x2 Monedas · x57,5 Daño")

-- Una palabra suelta, también con otra mayúscula al principio ("daño" en la tabla es "Daño").
local function word(text: string, from: string, to: string): string?
	local core, tail = string.match(text, "^(.-)([:!,]+)$")
	if core and core ~= "" then
		local done = word(core, from, to)
		return if done then done .. tail else nil
	end
	local dict = build(from, to)
	local found = dict.exact[text]
	if found then
		return found
	end
	if Ui.upper(text) == text then
		found = dict.exactUpper[text]
		return if found then Ui.upper(found) else nil
	end
	local first = string.sub(text, 1, 1)
	local isCapital = string.upper(first) == first
	found = dict.exact[(if isCapital then string.lower(first) else string.upper(first)) .. string.sub(text, 2)]
	if not found then
		return nil
	end
	local head = string.sub(found, 1, 1)
	return (if isCapital then string.upper(head) else string.lower(head)) .. string.sub(found, 2)
end

-- Palabras pegadas a números en un texto montado a trozos ("x2 Daño", "daño x4", "1º SUERTE"): se traduce el
-- tramo de palabras y los números cambian la coma decimal.
local function words(text: string, from: string, to: string): string?
	local tokens = string.split(text, " ")
	local first, last
	for index, token in tokens do
		if token ~= "" and not string.find(token, "%d") then
			first = first or index
			last = index
		elseif first then
			break
		end
	end
	if not first or (first == 1 and last == #tokens) then
		return nil
	end
	local run = table.concat(tokens, " ", first, last)
	local done = word(run, from, to)
	if not done then
		-- Frase con huecos ("Armadura de cuero: 30 %" es "{slot} de cuero").
		local core, tail = string.match(run, "^(.-)([:!,]*)$")
		local found = translate(core :: string, from, to, 1)
		done = if found then found .. tail else nil
	end
	if not done then
		return nil
	end
	local out = {}
	for index = 1, first - 1 do
		table.insert(out, number(tokens[index], to) or tokens[index])
	end
	table.insert(out, done)
	for index = last + 1, #tokens do
		table.insert(out, number(tokens[index], to) or tokens[index])
	end
	return table.concat(out, " ")
end

-- Dónde está el siguiente corte de cada clase a partir de `position`: inicio y fin (los cortes se copian tal cual).
local CUTS = {
	line = function(text: string, position: number): (number?, number?)
		local at = string.find(text, "\n", position, true)
		return at, at
	end,
	tag = function(text: string, position: number): (number?, number?)
		local at = string.find(text, "<", position, true)
		if not at then
			return nil, nil
		end
		return at, string.find(text, ">", at, true) or #text
	end,
	separator = function(text: string, position: number): (number?, number?)
		local at = string.find(text, SEPARATOR, position, true)
		return at, if at then at + #SEPARATOR - 1 else nil
	end,
}

-- Texto con varias líneas, etiquetas de RichText o trozos separados por "·": se traduce cada trozo por separado,
-- de lo grande a lo pequeño (primero las líneas; dentro de cada una, lo que hay entre etiquetas; luego los "·").
local function pieces(text: string, from: string, to: string, depth: number): (string?, boolean)
	local kind = if string.find(text, "\n", 1, true)
		then "line"
		elseif string.find(text, "<", 1, true) then "tag"
		elseif string.find(text, SEPARATOR, 1, true) then "separator"
		else nil
	if not kind then
		return nil
	end
	local cut = CUTS[kind]
	local out = {}
	local changed = false
	local complete = true
	local position = 1
	while position <= #text do
		local start, finish = cut(text, position)
		local piece = string.sub(text, position, if start then start - 1 else #text)
		if piece ~= "" then
			local lead, inner, trail = string.match(piece, "^(%s*)(.-)(%s*)$")
			local done = if inner ~= "" then translate(inner, from, to, depth + 1) else nil
			if done then
				changed = true
				table.insert(out, lead .. done .. trail)
			else
				table.insert(out, piece)
				-- Un trozo con palabras que no se ha podido traducir: el texto se queda a medias.
				if string.find(inner, "%a%a") then
					complete = false
				end
			end
		end
		if not start then
			break
		end
		table.insert(out, string.sub(text, start, finish))
		position = (finish :: number) + 1
	end
	if not changed then
		return nil, false
	end
	return table.concat(out), complete
end

-- El texto en el idioma `to`, o nil si no es una frase conocida del idioma `from`.
translate = function(text: string, from: string, to: string, depth: number): string?
	if depth > 8 or text == "" or not string.find(text, "%w") then
		return nil
	end
	local dict = build(from, to)
	local memo = dict.memo[text]
	if memo ~= nil then
		return if memo then memo else nil
	end
	local result = dict.exact[text]
	local isUpper = Ui.upper(text) == text and string.find(text, "%a") ~= nil
	if not result and isUpper then
		result = dict.exactUpper[text]
		if result then
			result = Ui.upper(result)
		end
	end
	-- Montado a trozos: si cada trozo es una frase conocida, eso manda sobre una frase con huecos que se trague
	-- varios ("+ x1,5 de" en el hueco de "{n} monedas").
	local partial: string? = nil
	if not result and (string.find(text, "[<\n]") or string.find(text, SEPARATOR, 1, true)) then
		local complete
		partial, complete = pieces(text, from, to, depth)
		if complete then
			result = partial
		end
	end
	if not result then
		local firstByte = string.sub(text, 1, 1)
		for _, entry in dict.patterns do
			local first = if isUpper then entry.firstUpper else entry.first
			if first == nil or first == firstByte then
				local found = { string.match(text, if isUpper then entry.upper else entry.pattern) }
				if #found > 0 then
					local values = {}
					local fits = true
					for index, name in entry.holes do
						local value = found[index] or ""
						-- Un hueco lleva un número, un nombre, una etiqueta de color o algo que se traduce: si se ha
						-- tragado otra línea, otro trozo o una frase que no se reconoce ("4 huecos más ... sacando"
						-- en "{n} monedas"), no es esta frase.
						-- Con "·" sí, si se traduce: el nombre de un arma es "Hierro · Titánica".
						if string.find(value, "\n", 1, true) then
							fits = false
							break
						end
						local done = translate(value, from, to, depth + 1)
						local plain = string.gsub(value, "<[^>]*>", "")
						if
							not done
							and (string.find(value, SEPARATOR, 1, true) or select(2, string.gsub(plain, "%a%a%a+", "")) >= 2)
						then
							fits = false
							break
						end
						values[name] = done or number(value, to) or value
					end
					if fits then
						result = string.gsub(entry.to, "{(%w+)}", function(name)
							return values[name] or ""
						end)
						if isUpper then
							result = Ui.upper(result)
						end
						break
					end
				end
			end
		end
	end
	if not result then
		result = partial
	end
	if not result then
		result = words(text, from, to)
	end
	if not result then
		result = number(text, to)
	end
	if dict.size >= MEMO_MAX then
		dict.memo, dict.size = {}, 0
	end
	dict.memo[text] = result or false
	dict.size += 1
	return result
end

local PROPERTIES = {
	TextLabel = { "Text" },
	TextButton = { "Text" },
	TextBox = { "PlaceholderText" },
	ProximityPrompt = { "ActionText", "ObjectText" },
}

local function swap(item: Instance, property: string)
	if busy[item] or current.from == current.to then
		return
	end
	local text = (item :: any)[property]
	local done = translate(text, current.from, current.to, 0)
	if done and done ~= text then
		busy[item] = true
		(item :: any)[property] = done
		busy[item] = nil
	end
end

local function handle(item: Instance, watch: boolean)
	local properties = PROPERTIES[item.ClassName]
	-- Los de client/WorldText los vuelve a escribir él.
	if not properties or item:GetAttribute("Lang") or item:GetAttribute("LangAction") or item:GetAttribute("LangObject") then
		return
	end
	for _, property in properties do
		swap(item, property)
		if watch and not watched[item] then
			item:GetPropertyChangedSignal(property):Connect(function()
				swap(item, property)
			end)
		end
	end
	if watch then
		watched[item] = true
	end
end

local function sweep(root: Instance, watch: boolean)
	local count = 0
	for _, item in root:GetDescendants() do
		if PROPERTIES[item.ClassName] then
			handle(item, watch)
			count += 1
			if count % CHUNK == 0 then
				task.wait()
			end
		end
	end
end

-- Un texto de un idioma al otro ("es" o "en"), o nil si no se reconoce (para probarlo desde execute_luau).
function LangSwap.translate(text: string, from: string, to: string): string?
	return translate(text, from, to, 0)
end

-- Pasa lo que hay escrito de un idioma ("es" o "en") al otro. Lang.set ya tiene que estar puesto en el nuevo.
function LangSwap.change(from: string, to: string)
	current.from, current.to = from, to
	if from == to then
		return
	end
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui and not watching then
		watching = true
		gui.DescendantAdded:Connect(function(item)
			if PROPERTIES[item.ClassName] then
				task.defer(handle, item, true)
			end
		end)
	end
	task.spawn(function()
		if gui then
			sweep(gui, true)
		end
		-- Carteles del mundo hechos por el cliente (tiradas, objetos) y avisos de E: se traducen una vez, sin vigilar.
		sweep(workspace, false)
	end)
end

return LangSwap
