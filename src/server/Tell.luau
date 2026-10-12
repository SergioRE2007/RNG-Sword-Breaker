-- Textos del servidor en el idioma de quien los lee (shared/Lang). Librería sin start().
--   Tell.notice(jugador, color, "Sent to {name}", { name = "..." })   aviso a un jugador
--   Tell.all(color, function(lector) return Lang.t(lector, ...) end)   anuncio a todos, cada uno en su idioma
--   Tell.world(etiqueta, "{name}'s plot", { name = "..." })            cartel del mundo (lo ven todos a la vez)
--   Tell.prompt(aviso, "Open", "Traits")                               aviso de E
-- Un hueco que también hay que traducir (el nombre de un objeto, de un arma...) se pasa ya traducido para ese
-- jugador: { item = Lang.t(jugador, item.name) } o Permanent.name(arma, metal, tamaño, jugador).
-- Un texto que depende de quien lo lee y se decide lejos de donde se manda (el motivo de un rechazo) puede ser una
-- función (lector) -> texto en vez de la frase: Tell.text la resuelve.
-- Los carteles del mundo son una sola pieza para todos, así que el servidor deja en ella la frase en inglés y sus
-- huecos (atributos "Lang" y "Lang_<hueco>") y cada cliente la traduce (client/WorldText). Un hueco con un número
-- lo escribe el cliente con Format.short; uno con { weapon = { arma, metal, tamaño } }, con Permanent.name.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Tell = {}

Tell.TAG = "LangText"

function Tell.text(reader: Player?, text: any, args: { [string]: any }?): string
	if type(text) == "function" then
		return text(reader)
	end
	return Lang.t(reader, text, args)
end

function Tell.notice(player: Player?, color: Color3?, text: any, args: { [string]: any }?)
	if player and player.Parent then
		Remotes.Notice:FireClient(player, Tell.text(player, text, args), color)
	end
end

function Tell.all(color: Color3?, build: (reader: Player) -> string)
	for _, reader in Players:GetPlayers() do
		Remotes.Announce:FireClient(reader, build(reader), color)
	end
end

-- `upper` = en mayúsculas (las pone el cliente, con tildes y ñ).
function Tell.world(label: TextLabel, text: string, args: { [string]: any }?, upper: boolean?)
	local shown = {}
	for key, value in args or {} do
		if type(value) == "table" and value.weapon then
			local sword, metal, size = value.weapon[1], value.weapon[2] or 0, value.weapon[3] or 0
			label:SetAttribute("Lang_" .. key, `weapon:{sword}:{metal}:{size}`)
			shown[key] = Permanent.name(sword, metal, size)
		else
			label:SetAttribute("Lang_" .. key, value)
			shown[key] = if type(value) == "number" then Format.short(value) else value
		end
	end
	label:SetAttribute("LangUpper", upper == true)
	label:SetAttribute("Lang", text)
	local english = Lang.t(nil, text, shown)
	label.Text = if upper then string.upper(english) else english
	CollectionService:AddTag(label, Tell.TAG)
end

function Tell.prompt(prompt: ProximityPrompt, action: string, object: string)
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt:SetAttribute("LangAction", action)
	prompt:SetAttribute("LangObject", object)
	CollectionService:AddTag(prompt, Tell.TAG)
end

return Tell
