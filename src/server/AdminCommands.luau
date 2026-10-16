-- Órdenes del menú de admin (client/AdminTools), aparte de las del clima (server/Weather). Solo las obedece a los
-- administradores: cada una se comprueba con Admin.is, y de lo que manda el cliente no se da nada por bueno.
-- AdminCommand:FireServer(acción, ...):
--   "give", userId (0 = todos los de este servidor), objeto ("coins", "gems" o una clave de Config.Items), cantidad
--   "sword", userId (0 = todos), { sword, metal, size, trait, grade } (índices de Config; 0 = sin metal, tamaño
--     normal, sin rasgo o sin grado), cantidad: armas hechas a medida, hasta MAX_SWORDS por orden y lo que quepa
--     en la mochila (Config.MaxSwords). No cuentan para el Índice ni para la "Mejor tirada": no son tiradas.
--   "kick", userId                 echar a ese jugador del servidor
--   "goto", userId / "bring", userId   ir junto a ese jugador / traerlo junto a mí
--   "announce", texto              aviso a todo el servidor (pasa por el filtro de texto de Roblox)
--   "banner", texto                mensaje grande arriba de la pantalla de todos (también filtrado)
--   "boost", stat, multiplicador, minutos / "stopBoost", stat   evento de admin (server/AdminEvents)
-- Con "all" delante (AdminCommand:FireServer("all", acción, ...)) la orden vale en todos los servidores del juego
-- (server/Broadcast): "give" y "sword" con userId 0 (a todos los que estén jugando en ese momento), "announce",
-- "banner", "boost", "stopBoost" y "weather" (un id de clima, "none" o "auto"). Cada servidor vuelve a comprobar
-- lo que le llega.
-- Lo regalado no cuenta como monedas ganadas (clasificaciones). Cada orden deja una línea en la consola del servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Admin = require(script.Parent.Admin)
local AdminEvents = require(script.Parent.AdminEvents)
local Broadcast = require(script.Parent.Broadcast)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local AdminCommands = {}

local GOLD = Color3.fromRGB(255, 205, 70)
local BAD = Color3.fromRGB(255, 110, 110)
local MAX_ITEMS = 1e12 -- tope de una entrega de objetos
local MAX_MONEY = 1e60 -- tope de una entrega de monedas o gemas
local MAX_TEXT = 200
local MAX_SWORDS = 50 -- tope de armas de una orden

-- Nombre (para ese lector) y color de lo que se regala, o nil si no existe.
local function gift(key: unknown, reader: Player?): (string?, Color3?)
	if key == "coins" then
		return Lang.t(reader, "Coins"), Color3.fromRGB(255, 200, 60)
	elseif key == "gems" then
		return Lang.t(reader, "Gems"), Color3.fromRGB(190, 120, 255)
	end
	local item = if type(key) == "string" then Config.Items[key] else nil
	if item then
		return Lang.t(reader, item.name), item.color
	end
	return nil, nil
end

local function target(userId: unknown): Player?
	return if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Entrega a esos jugadores (ya comprobado: validItems). Devuelve a cuántos.
local function deliverItems(players: { Player }, key: string, count: number): number
	local money = key == "coins" or key == "gems"
	local given = 0
	for _, player in players do
		if PlayerData.read(player) then
			PlayerData.edit(player, function(data)
				if money then
					data[key] += count
				else
					data.items[key] += count
				end
			end)
			given += 1
			local name, color = gift(key, player)
			Tell.notice(player, color, "An admin gave you +{n} {item}", { n = Format.short(count, player), item = name })
		end
	end
	return given
end

-- Clave y cantidad de un regalo, o nil si lo que llega no vale.
local function validItems(key: unknown, amount: unknown): (string?, number?)
	if type(amount) ~= "number" or amount ~= amount or amount < 1 or not gift(key) then
		return nil, nil
	end
	local money = key == "coins" or key == "gems"
	return key :: string, math.min(math.floor(amount), if money then MAX_MONEY else MAX_ITEMS)
end

local function give(admin: Player, userId: unknown, rawKey: unknown, amount: unknown, global: boolean)
	local key, count = validItems(rawKey, amount)
	if not key or not count then
		return
	end
	local everyone = userId == 0
	local one = target(userId)
	if not everyone and not one then
		return
	end
	local name = gift(key, admin)
	if everyone and global then
		Broadcast.send("give", { key = key, count = count })
		Tell.notice(admin, GOLD, "Given on all servers: +{n} {item}", { n = Format.short(count, admin), item = name })
		print(`[Admin] {admin.Name} gives {count} {key} to all servers`)
		return
	end
	local given = deliverItems(if everyone then Players:GetPlayers() else { one :: Player }, key, count)
	if everyone then
		Tell.notice(admin, GOLD, "Given to everyone: +{n} {item}", { n = Format.short(count, admin), item = name })
	elseif given > 0 then
		Tell.notice(admin, GOLD, "Given to {name}: +{n} {item}", { name = (one :: Player).DisplayName, n = Format.short(count, admin), item = name })
	end
	print(`[Admin] {admin.Name} gives {count} {key} to {if everyone then "everyone" else (one :: Player).Name}`)
end

-- Índice entero de `list` (o 0, si `optional`), o nil si lo que manda el cliente no vale.
local function index(value: unknown, list, optional: boolean): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	if value == 0 and optional then
		return 0
	end
	return if list[value] then value else nil
end

-- Arma a medida y cantidad, o nil si lo que llega no vale.
local function validSwords(spec: unknown, amount: unknown)
	if type(spec) ~= "table" or type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return nil, nil
	end
	local sword = index(spec.sword, Config.Swords, false)
	local metal, size = index(spec.metal, Config.Metals, true), index(spec.size, Config.Sizes, true)
	local trait, grade = index(spec.trait, Config.Traits, true), index(spec.grade, Config.Grades, true)
	if not (sword and metal and size and trait and grade) then
		return nil, nil
	end
	return { sword = sword, metal = metal, size = size, trait = trait, grade = grade }, math.min(math.floor(amount), MAX_SWORDS)
end

-- Entrega a esos jugadores (ya comprobado: validSwords). Devuelve cuántos reciben alguna y a cuántos no les caben todas.
local function deliverSwords(players: { Player }, spec, count: number): (number, number)
	local given, short = 0, 0
	for _, player in players do
		if not PlayerData.read(player) then
			continue
		end
		local added = 0
		PlayerData.edit(player, function(data)
			for _ = 1, math.min(count, Config.MaxSwords - #data.swords) do
				table.insert(data.swords, {
					id = data.nextSwordId,
					sword = spec.sword,
					metal = if spec.metal > 0 then spec.metal else nil,
					size = if spec.size > 0 then spec.size else nil,
					trait = if spec.trait > 0 then spec.trait else nil,
					grade = if spec.grade > 0 then spec.grade else nil,
				})
				data.nextSwordId += 1
				added += 1
			end
		end)
		if added < count then
			short += 1
		end
		if added > 0 then
			given += 1
			Tell.notice(player, GOLD, "An admin gave you {n} x {weapon}", { n = added, weapon = Permanent.name(spec.sword, spec.metal, spec.size, player) })
		end
	end
	return given, short
end

local function giveSwords(admin: Player, userId: unknown, rawSpec: unknown, amount: unknown, global: boolean)
	local spec, count = validSwords(rawSpec, amount)
	if not spec or not count then
		return
	end
	local everyone = userId == 0
	local one = target(userId)
	if not everyone and not one then
		return
	end
	local name = Permanent.name(spec.sword, spec.metal, spec.size, admin)
	local log = `sword {spec.sword} (metal {spec.metal}, size {spec.size}, trait {spec.trait}, grade {spec.grade})`
	if everyone and global then
		Broadcast.send("sword", { spec = spec, count = count })
		Tell.notice(admin, GOLD, "Given on all servers: {n} x {weapon}", { n = count, weapon = name })
		print(`[Admin] {admin.Name} gives {count} x {log} to all servers`)
		return
	end
	local given, short = deliverSwords(if everyone then Players:GetPlayers() else { one :: Player }, spec, count)
	if given == 0 then
		Tell.notice(admin, BAD, "No room in the backpack for more weapons")
	elseif everyone then
		Tell.notice(admin, GOLD, "Given to everyone: {n} x {weapon}", { n = count, weapon = name })
	else
		Tell.notice(admin, GOLD, "Given to {name}: {n} x {weapon}", { name = (one :: Player).DisplayName, n = count, weapon = name })
	end
	if given > 0 and short > 0 then
		Tell.notice(admin, BAD, "Some didn't fit: the backpack holds {n} weapons", { n = Config.MaxSwords })
	end
	print(`[Admin] {admin.Name} gives {count} x {log} to {if everyone then "everyone" else (one :: Player).Name}`)
end

local function kick(admin: Player, userId: unknown)
	local player = target(userId)
	if not player or player == admin then
		return
	end
	print(`[Admin] {admin.Name} kicks {player.Name}`)
	player:Kick(Lang.t(player, "You were kicked by an admin."))
end

-- Lleva a `mover` junto a `anchor`. Ninguno de los dos puede estar en una mazmorra (cada partida tiene su arena).
local function move(admin: Player, mover: Player, anchor: Player)
	if (mover:GetAttribute("Dungeon") or 0) > 0 or (anchor:GetAttribute("Dungeon") or 0) > 0 then
		Tell.notice(admin, BAD, "That can't be done inside a dungeon")
		return
	end
	local from, to = mover.Character, rootOf(anchor)
	if not from or not to or not rootOf(mover) then
		return
	end
	from:PivotTo(to.CFrame * CFrame.new(0, 0, 5))
	local root = rootOf(mover)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Texto escrito por un administrador que van a leer otros: recortado y pasado por el filtro de Roblox. nil si se
-- queda vacío o no se puede filtrar (y se le avisa).
local function clean(admin: Player, text: unknown, limit: number): string?
	if type(text) ~= "string" then
		return nil
	end
	local short = string.sub((string.gsub(text, "[%c<>]", " ")), 1, limit)
	if string.match(short, "^%s*$") then
		return nil
	end
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(short, admin.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		Tell.notice(admin, BAD, "The message couldn't be sent")
		return nil
	end
	return filtered
end

local function tellAll(text: string)
	Tell.all(GOLD, function()
		return text
	end, true)
end

local function announce(admin: Player, text: unknown, global: boolean)
	local filtered = clean(admin, text, MAX_TEXT)
	if not filtered then
		return
	end
	print(`[Admin] {admin.Name} announces{if global then " on all servers" else ""}: {filtered}`)
	if global then
		Broadcast.send("announce", { text = filtered })
	else
		tellAll(filtered)
	end
end

local function banner(admin: Player, text: unknown, global: boolean)
	local filtered = clean(admin, text, Config.AdminEvents.MaxMessage)
	if not filtered then
		return
	end
	print(`[Admin] {admin.Name} shows the banner{if global then " on all servers" else ""}: {filtered}`)
	AdminEvents.banner(filtered, global)
end

local function boost(admin: Player, stat: unknown, mult: unknown, minutes: unknown, global: boolean)
	if AdminEvents.boost(stat, mult, minutes, global) then
		print(`[Admin] {admin.Name} starts x{mult} {stat} for {minutes} min{if global then " on all servers" else ""}`)
	else
		Tell.notice(admin, BAD, "That event isn't valid: more than x1 and up to {minutes} min", { minutes = Config.AdminEvents.MaxMinutes })
	end
end

local function weather(admin: Player, action: unknown)
	if action == "none" or action == "auto" or (type(action) == "string" and Config.Weather.Events[action]) then
		print(`[Admin] {admin.Name} sets the weather on all servers: {action}`)
		Broadcast.send("weather", { action = action })
	end
end

local function onCommand(admin: Player, action: unknown, ...: unknown)
	if not Admin.is(admin) then
		return
	end
	local args = { ... }
	local global = action == "all"
	if global then
		action = table.remove(args, 1)
	end
	local a, b, c = args[1], args[2], args[3]
	if action == "give" then
		give(admin, a, b, c, global)
	elseif action == "sword" then
		giveSwords(admin, a, b, c, global)
	elseif action == "announce" then
		announce(admin, a, global)
	elseif action == "banner" then
		banner(admin, a, global)
	elseif action == "boost" then
		boost(admin, a, b, c, global)
	elseif action == "stopBoost" then
		if AdminEvents.stop(a, global) then
			print(`[Admin] {admin.Name} stops the {a} event{if global then " on all servers" else ""}`)
		end
	elseif global then
		-- Lo demás (echar, ir, traer) no existe para todos los servidores; el clima de uno solo va por AdminWeather.
		if action == "weather" then
			weather(admin, a)
		end
	elseif action == "clover" then
		-- Trébol de prueba (suerte a medida, 0 = quitarlo): solo para el propio administrador, para probar las tiradas.
		local luck = require(script.Parent.Clover).setCustom(admin, a)
		if luck == nil then
			Tell.notice(admin, BAD, "That clover luck isn't valid")
		elseif luck > 0 then
			print(`[Admin] {admin.Name} sets a test clover of x{luck}`)
		end
	elseif action == "worldBoss" then
		-- Hacer salir ya el Jefe del mundo en este servidor (con Config.WorldBoss.AdminWarning s de aviso).
		if require(script.Parent.WorldBoss).summon() then
			print(`[Admin] {admin.Name} summons the world boss`)
		else
			Tell.notice(admin, BAD, "The world boss is already out")
		end
	elseif action == "kick" then
		kick(admin, a)
	elseif action == "goto" or action == "bring" then
		local other = target(a)
		if other and other ~= admin then
			if action == "goto" then
				move(admin, admin, other)
			else
				move(admin, other, admin)
			end
		end
	end
end

function AdminCommands.start()
	-- Lo que llega de otro servidor (o de este): se comprueba otra vez y se hace para los que están aquí.
	Broadcast.on("give", function(data)
		local key, count = validItems(type(data) == "table" and data.key, type(data) == "table" and data.count)
		if key and count then
			deliverItems(Players:GetPlayers(), key, count)
		end
	end)
	Broadcast.on("sword", function(data)
		local spec, count = validSwords(type(data) == "table" and data.spec, type(data) == "table" and data.count)
		if spec and count then
			deliverSwords(Players:GetPlayers(), spec, count)
		end
	end)
	Broadcast.on("announce", function(data)
		if type(data) == "table" and type(data.text) == "string" and #data.text <= MAX_TEXT * 4 then
			tellAll(data.text)
		end
	end)
	Broadcast.on("weather", function(data)
		if type(data) == "table" then
			-- Se pide aquí: Weather arranca después que este módulo.
			require(script.Parent.Weather).force(data.action)
		end
	end)
	Remotes.AdminCommand.OnServerEvent:Connect(onCommand)
end

return AdminCommands
