-- Carteles del mundo y avisos de E en el idioma del jugador. Son piezas que hace el servidor, una sola para todos,
-- así que él deja la frase en inglés y sus huecos en atributos (server/Tell: Tell.world y Tell.prompt) y aquí cada
-- cliente la escribe en su idioma:
--   TextLabel:        "Lang" = la frase, "Lang_<hueco>" = lo que va en cada hueco, "LangUpper" = en mayúsculas.
--                     Un hueco con un número se escribe con Format.short; "weapon:<arma>:<metal>:<tamaño>", con el
--                     nombre del arma.
--   ProximityPrompt:  "LangAction" y "LangObject".
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Ui = require(script.Parent.Ui)

local WorldText = {}

local TAG = "LangText"

local function fill(value: any): any
	if type(value) == "number" then
		return Format.short(value)
	elseif type(value) == "string" then
		local sword, metal, size = string.match(value, "^weapon:(%d+):(%d+):(%d+)$")
		if sword then
			return Permanent.name(tonumber(sword) :: number, tonumber(metal), tonumber(size))
		end
	end
	return value
end

local function set(item: Instance, property: string, text: string)
	if (item :: any)[property] ~= text then
		(item :: any)[property] = text
	end
end

local function apply(item: Instance)
	if item:IsA("ProximityPrompt") then
		local action, object = item:GetAttribute("LangAction"), item:GetAttribute("LangObject")
		if type(action) == "string" then
			set(item, "ActionText", Lang.t(nil, action))
		end
		if type(object) == "string" then
			set(item, "ObjectText", Lang.t(nil, object))
		end
		return
	end
	local text = item:GetAttribute("Lang")
	if type(text) ~= "string" or not item:IsA("TextLabel") then
		return
	end
	local args = {}
	for name, value in item:GetAttributes() do
		if string.sub(name, 1, 5) == "Lang_" then
			args[string.sub(name, 6)] = fill(value)
		end
	end
	local shown = Lang.t(nil, text, args)
	set(item, "Text", if item:GetAttribute("LangUpper") then Ui.upper(shown) else shown)
end

local function watch(item: Instance)
	apply(item)
	item.AttributeChanged:Connect(function()
		apply(item)
	end)
	-- El texto en inglés que pone el servidor llega después que los atributos: se vuelve a escribir encima.
	for _, property in if item:IsA("ProximityPrompt") then { "ActionText", "ObjectText" } else { "Text" } do
		item:GetPropertyChangedSignal(property):Connect(function()
			apply(item)
		end)
	end
end

-- Vuelve a escribirlos todos (al cambiar de idioma: client/Language).
function WorldText.refresh()
	for _, item in CollectionService:GetTagged(TAG) do
		apply(item)
	end
end

function WorldText.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	for _, item in CollectionService:GetTagged(TAG) do
		watch(item)
	end
end

return WorldText
