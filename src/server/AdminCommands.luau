-- Órdenes del menú de admin (client/AdminTools), aparte de las del clima (server/Weather). Solo las obedece a los
-- administradores: cada una se comprueba con Admin.is, y de lo que manda el cliente no se da nada por bueno.
-- AdminCommand:FireServer(acción, ...):
--   "give", userId (0 = todos los de este servidor), objeto ("coins", "gems" o una clave de Config.Items), cantidad
--   "kick", userId                 echar a ese jugador del servidor
--   "goto", userId / "bring", userId   ir junto a ese jugador / traerlo junto a mí
--   "announce", texto              aviso a todo el servidor (pasa por el filtro de texto de Roblox)
-- Lo regalado no cuenta como monedas ganadas (clasificaciones). Cada orden deja una línea en la consola del servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Admin = require(script.Parent.Admin)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local AdminCommands = {}

local GOLD = Color3.fromRGB(255, 205, 70)
local BAD = Color3.fromRGB(255, 110, 110)
local MAX_ITEMS = 1e12 -- tope de una entrega de objetos
local MAX_MONEY = 1e60 -- tope de una entrega de monedas o gemas
local MAX_TEXT = 200

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

local function give(admin: Player, userId: unknown, key: unknown, amount: unknown)
	if type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return
	end
	local money = key == "coins" or key == "gems"
	local count = math.min(math.floor(amount), if money then MAX_MONEY else MAX_ITEMS)
	if not gift(key) then
		return
	end
	local everyone = userId == 0
	local one = target(userId)
	if not everyone and not one then
		return
	end
	local given = 0
	for _, player in if everyone then Players:GetPlayers() else { one :: Player } do
		if PlayerData.read(player) then
			PlayerData.edit(player, function(data)
				if money then
					data[key :: string] += count
				else
					data.items[key :: string] += count
				end
			end)
			given += 1
			local name, color = gift(key, player)
			Tell.notice(player, color, "An admin gave you +{n} {item}", { n = Format.short(count, player), item = name })
		end
	end
	local name = gift(key, admin)
	if everyone then
		Tell.notice(admin, GOLD, "Given to everyone: +{n} {item}", { n = Format.short(count, admin), item = name })
	elseif given > 0 then
		Tell.notice(admin, GOLD, "Given to {name}: +{n} {item}", { name = (one :: Player).DisplayName, n = Format.short(count, admin), item = name })
	end
	print(`[Admin] {admin.Name} gives {count} {key} to {if everyone then "everyone" else (one :: Player).Name}`)
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

local function announce(admin: Player, text: unknown)
	if type(text) ~= "string" then
		return
	end
	local clean = string.sub((string.gsub(text, "[%c<>]", " ")), 1, MAX_TEXT)
	if string.match(clean, "^%s*$") then
		return
	end
	-- Texto escrito por una persona que van a leer otras: tiene que pasar por el filtro de Roblox.
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(clean, admin.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		Tell.notice(admin, BAD, "The message couldn't be sent")
		return
	end
	print(`[Admin] {admin.Name} announces: {filtered}`)
	Tell.all(GOLD, function()
		return filtered
	end)
end

local function onCommand(admin: Player, action: unknown, a: unknown, b: unknown, c: unknown)
	if not Admin.is(admin) then
		return
	end
	if action == "give" then
		give(admin, a, b, c)
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
	elseif action == "announce" then
		announce(admin, a)
	end
end

function AdminCommands.start()
	Remotes.AdminCommand.OnServerEvent:Connect(onCommand)
end

return AdminCommands
