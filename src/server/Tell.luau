-- Textos del servidor en el idioma de quien los lee (shared/Lang). Librería sin start().
--   Tell.notice(jugador, color, "Sent to {name}", { name = "..." })   aviso a un jugador
--   Tell.all(color, function(lector) return Lang.t(lector, ...) end)   anuncio a todos, cada uno en su idioma
--   Tell.rare("weapon", probabilidad, color, "{player} got {weapon}!", huecos)   lo raro de un jugador, según lo raro
--     que era para él: a su servidor o a todos (Config.Announce)
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

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Broadcast = require(script.Parent.Broadcast)

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

-- `admin` = aviso de un administrador: además del chat sale en pantalla (el chat suele estar cerrado).
function Tell.all(color: Color3?, build: (reader: Player) -> string, admin: boolean?)
	for _, reader in Players:GetPlayers() do
		Remotes.Announce:FireClient(reader, build(reader), color, admin == true)
	end
end

-- Huecos de Tell.rare: tienen que caber en JSON (viajan a otros servidores) y se traducen para cada lector.
--   número → Format.short; texto → tal cual (nombres de jugador); { t = "frase" } → Lang.t;
--   { weapon = { arma, metal, tamaño } } → Permanent.name; { odds = { arma, metal, tamaño } } → Permanent.describeOdds.
local function resolve(reader: Player, value: any): string
	if type(value) == "number" then
		return Format.short(value, reader)
	elseif type(value) ~= "table" then
		return tostring(value)
	elseif value.t then
		return Lang.t(reader, tostring(value.t))
	elseif value.weapon then
		return Permanent.name(value.weapon[1], value.weapon[2] or 0, value.weapon[3] or 0, reader)
	elseif value.odds then
		return Permanent.describeOdds(value.odds[1], value.odds[2] or 0, value.odds[3] or 0, reader)
	end
	return ""
end

local function sayRare(data: any)
	if type(data) ~= "table" or type(data.text) ~= "string" or type(data.color) ~= "string" then
		return
	end
	local ok, color = pcall(Color3.fromHex, data.color)
	if not ok then
		return
	end
	for _, reader in Players:GetPlayers() do
		local args = {}
		for key, value in (if type(data.args) == "table" then data.args else {}) do
			args[key] = resolve(reader, value)
		end
		local text = Lang.t(reader, data.text, args)
		if data.global then
			text = Lang.t(reader, "[Global] {text}", { text = text })
		end
		Remotes.Announce:FireClient(reader, text, color)
	end
end
Broadcast.on("rare", sayRare)

-- Aviso de algo que le ha salido a un jugador, según lo raro que era para él (Config.Announce[clase]): al chat de su
-- servidor o, si es rarísimo, al de todos los servidores. Por debajo no dice nada (el aviso suyo lo da quien llama).
-- `args` con los huecos de arriba, no ya traducidos.
function Tell.rare(class: string, odds: number, color: Color3, text: string, args: { [string]: any }?)
	local levels = Config.Announce[class]
	if not levels or odds < levels.Server then
		return
	end
	local data = { text = text, args = args or {}, color = color:ToHex(), global = odds >= levels.Global }
	if data.global then
		Broadcast.send("rare", data)
	else
		sayRare(data)
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
