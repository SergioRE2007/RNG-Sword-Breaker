-- Comercio entre jugadores. Uno invita, el otro acepta y se abre un trato: cada uno pone lo que da (monedas,
-- gemas, objetos, espadas, armadura y accesorios). Pasos, pensados contra los timos:
--   1. "editing": se cambian las ofertas; cualquier cambio quita el "aceptar" de los dos.
--   2. "confirming": cuando los dos han aceptado las ofertas quedan bloqueadas y cada uno tiene que CONFIRMAR.
--   3. "countdown": con los dos confirmados corren Config.Trade.Countdown segundos en los que cualquiera puede cancelar.
-- Al acabar la cuenta se vuelve a comprobar todo (que cada uno sigue teniendo lo que ofrece y que al otro le cabe)
-- y se cambia de una vez. El cliente solo pide; aquí se valida cada paso.
-- En Studio (Config.Test.TradeBot) hay un "Bot de pruebas" (userId 0) para probarlo con un solo jugador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Armor = require(script.Parent.Armor)
local PlayerData = require(script.Parent.PlayerData)

local Trade = {}

local cfg = Config.Trade
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)

local sessions = {} -- [Player] = trato en el que está
local invites = {} -- [invitado] = { [quien invita] = os.clock() en que caduca }
local lastRequest = {} -- [Player] = os.clock() de su última invitación
local lastSuggest = {} -- [Player] = os.clock() de su última sugerencia

local function botAllowed(): boolean
	return RunService:IsStudio() and Config.Test.TradeBot == true
end

local function newSide(player: Player?)
	return {
		player = player,
		bot = player == nil,
		name = if player then player.DisplayName else "Bot de pruebas",
		userId = if player then player.UserId else 0,
		accepted = false,
		confirmed = false,
		-- swords, armor y artifacts son conjuntos { [id o índice] = true }.
		offer = { coins = 0, gems = 0, items = {}, swords = {}, armor = {}, artifacts = {} },
	}
end

local function findArmor(data, id: unknown)
	for position, piece in data.armor do
		if piece.id == id then
			return piece, position
		end
	end
	return nil
end

local function swordView(copy)
	return { id = copy.id, sword = copy.sword, trait = copy.trait or 0, grade = copy.grade or 0, metal = copy.metal or 0, size = copy.size or 0 }
end

local function pieceView(piece)
	return { id = piece.id, slot = piece.slot, quality = piece.quality, level = piece.level, stats = piece.stats }
end

-- La sugerencia en curso de un lado tal y como la ve el cliente (con la espada o la pieza ya resueltas), o nil.
local function suggestView(side)
	local suggest = side.suggest
	if not suggest then
		return nil
	end
	local out = { intent = suggest.intent, category = suggest.category, key = suggest.key, amount = suggest.amount, ends = suggest.ends, ignored = suggest.ignored }
	local data = if side.player then PlayerData.read(side.player) else nil
	if data and suggest.category == "swords" then
		local copy = PlayerData.findSword(data, suggest.key)
		out.sword = if copy then swordView(copy) else nil
	elseif data and suggest.category == "armor" then
		local piece = findArmor(data, suggest.key)
		out.piece = if piece then pieceView(piece) else nil
	end
	return out
end

-- Lo que ofrece un lado, con todos los datos de cada cosa, tal y como lo ve el cliente.
local function view(side)
	local offer = side.offer
	local out = {
		name = side.name,
		userId = side.userId,
		accepted = side.accepted,
		confirmed = side.confirmed,
		suggest = suggestView(side),
		coins = offer.coins,
		gems = offer.gems,
		items = offer.items,
		swords = {},
		armor = {},
		artifacts = {},
	}
	if side.bot then
		out.swords, out.armor = side.fake.swords, side.fake.armor
		return out
	end
	local data = PlayerData.read(side.player)
	if not data then
		return out
	end
	for id in offer.swords do
		local copy = PlayerData.findSword(data, id)
		if copy then
			table.insert(out.swords, swordView(copy))
		end
	end
	for id in offer.armor do
		local piece = findArmor(data, id)
		if piece then
			table.insert(out.armor, pieceView(piece))
		end
	end
	for index in offer.artifacts do
		table.insert(out.artifacts, index)
	end
	table.sort(out.artifacts)
	return out
end

local function push(session)
	for index, side in session.sides do
		if side.player then
			Remotes.TradeState:FireClient(side.player, { state = session.state, ends = session.ends, you = view(side), them = view(session.sides[3 - index]) })
		end
	end
end

-- Cierra el trato sin cambiar nada. `text` es el aviso que ven los dos.
local function close(session, text: string, color: Color3)
	for _, side in session.sides do
		local player = side.player
		if player and sessions[player] == session then
			sessions[player] = nil
			Remotes.TradeState:FireClient(player, nil)
			Remotes.Notice:FireClient(player, text, color)
		end
	end
	session.state = "closed"
end

local function sideOf(player: Player)
	local session = sessions[player]
	if not session then
		return nil
	end
	for index, side in session.sides do
		if side.player == player then
			return session, side, session.sides[3 - index]
		end
	end
	return nil
end

local function isEmpty(offer): boolean
	return offer.coins == 0 and offer.gems == 0 and next(offer.items) == nil and next(offer.swords) == nil and next(offer.armor) == nil and next(offer.artifacts) == nil
end

local function count(set): number
	local total = 0
	for _ in set do
		total += 1
	end
	return total
end

-- ¿Sigue teniendo ese lado todo lo que ofrece, y le cabe lo que le da el otro? Devuelve nil si todo bien, o
-- el motivo por el que no.
local function problem(side, other): string?
	if side.bot then
		return nil
	end
	local data = PlayerData.read(side.player)
	if not data then
		return `{side.name} no tiene los datos cargados`
	end
	local offer = side.offer
	if data.coins < offer.coins or data.gems < offer.gems then
		return `{side.name} ya no tiene esas monedas o gemas`
	end
	for name, amount in offer.items do
		if (data.items[name] or 0) < amount then
			return `{side.name} ya no tiene esos objetos`
		end
	end
	for id in offer.swords do
		if not PlayerData.findSword(data, id) or id == data.equipped then
			return `{side.name} ya no tiene una de las espadas (o la lleva equipada)`
		end
	end
	for id in offer.armor do
		if not findArmor(data, id) then
			return `{side.name} ya no tiene una de las piezas de armadura`
		end
	end
	for index in offer.artifacts do
		if not table.find(data.artifacts, index) then
			return `{side.name} ya no tiene uno de los accesorios`
		end
	end
	-- Lo que recibe.
	local incoming = other.offer
	local swordsIn = if other.bot then #other.fake.swords else count(incoming.swords)
	local armorIn = if other.bot then #other.fake.armor else count(incoming.armor)
	if #data.swords - count(offer.swords) + swordsIn > Config.MaxSwords then
		return `A {side.name} no le caben tantas espadas`
	end
	if #data.armor - count(offer.armor) + armorIn > Config.Armor.MaxPieces then
		return `A {side.name} no le cabe tanta armadura`
	end
	for index in incoming.artifacts do
		if table.find(data.artifacts, index) and not offer.artifacts[index] then
			return `{side.name} ya tiene el accesorio {Config.Artifacts[index].name}`
		end
	end
	return nil
end

-- Saca de un lado todo lo que ofrece y lo devuelve en un paquete.
local function take(side)
	local offer = side.offer
	local pack = { coins = offer.coins, gems = offer.gems, items = offer.items, swords = {}, armor = {}, artifacts = {} }
	if side.bot then
		pack.swords, pack.armor = side.fake.swords, side.fake.armor
		return pack
	end
	PlayerData.editArmor(side.player, function(data)
		data.coins -= offer.coins
		data.gems -= offer.gems
		for name, amount in offer.items do
			data.items[name] -= amount
		end
		for id in offer.swords do
			local copy, position = PlayerData.findSword(data, id)
			if copy then
				table.remove(data.swords, position)
				table.insert(pack.swords, copy)
			end
		end
		for id in offer.armor do
			local piece, position = findArmor(data, id)
			if piece then
				table.remove(data.armor, position)
				if data.armorWorn[piece.slot] == piece.id then
					data.armorWorn[piece.slot] = nil
				end
				table.insert(pack.armor, piece)
			end
		end
		for index in offer.artifacts do
			local position = table.find(data.artifacts, index)
			if position then
				table.remove(data.artifacts, position)
				local worn = table.find(data.gear, index)
				if worn then
					table.remove(data.gear, worn)
				end
				table.insert(pack.artifacts, index)
			end
		end
	end)
	return pack
end

-- Mete un paquete en el inventario de un lado (con ids nuevos).
local function give(side, pack)
	if side.bot then
		return
	end
	PlayerData.editArmor(side.player, function(data)
		-- No cuenta como monedas ganadas (clasificaciones): se suman a mano, sin addCoins.
		data.coins += pack.coins
		data.gems += pack.gems
		for name, amount in pack.items do
			data.items[name] = (data.items[name] or 0) + amount
		end
		for _, copy in pack.swords do
			table.insert(data.swords, { id = data.nextSwordId, sword = copy.sword, trait = copy.trait, grade = copy.grade, metal = copy.metal, size = copy.size })
			data.nextSwordId += 1
		end
		for _, piece in pack.armor do
			table.insert(data.armor, { id = data.nextArmorId, slot = piece.slot, quality = piece.quality, level = piece.level, stats = piece.stats })
			data.nextArmorId += 1
		end
		for _, index in pack.artifacts do
			if not table.find(data.artifacts, index) then
				table.insert(data.artifacts, index)
			end
		end
		table.sort(data.artifacts)
	end)
end

local function complete(session)
	local a, b = session.sides[1], session.sides[2]
	local reason = problem(a, b) or problem(b, a)
	if reason then
		close(session, "Trato cancelado: " .. reason, BAD)
		return
	end
	local fromA, fromB = take(a), take(b)
	give(a, fromB)
	give(b, fromA)
	close(session, "¡Intercambio completado!", GOOD)
end

-- Sugerencias (definidas más abajo, con las peticiones del cliente): las usa también el bot de pruebas.
local setSuggest, respondSuggest

-- Bot de pruebas: acepta y confirma un segundo después que el jugador.
local function botFollow(session)
	local bot, human
	for index, side in session.sides do
		if side.bot then
			bot, human = side, session.sides[3 - index]
		end
	end
	if not bot then
		return
	end
	task.delay(1, function()
		if session.state == "editing" and human.accepted and not bot.accepted then
			bot.accepted = true
			session.advance()
		elseif session.state == "confirming" and human.confirmed and not bot.confirmed then
			bot.confirmed = true
			session.advance()
		end
	end)
end

local function start(playerA: Player, playerB: Player?)
	local session = { sides = { newSide(playerA), newSide(playerB) }, state = "editing", ends = 0, token = 0 }
	for _, side in session.sides do
		if side.player then
			sessions[side.player] = session
		else
			-- Lo que "tiene" el bot para dar: sale de la nada, solo para probar.
			side.fake = {
				swords = { { id = -1, sword = 8, trait = 10, grade = 6, metal = 3, size = 1 } },
				armor = { Armor.roll(3, 1, "helmet", 4) },
			}
			side.fake.armor[1].id = -1
			side.offer.coins, side.offer.gems = 1000, 50
			side.offer.items.gradeCrystal = 5
		end
	end
	-- Pasa de paso cuando los dos han aceptado o confirmado.
	function session.advance()
		local a, b = session.sides[1], session.sides[2]
		if session.state == "editing" and a.accepted and b.accepted then
			session.state = "confirming"
			-- Las sugerencias solo valen mientras se eligen las ofertas.
			a.suggest, b.suggest = nil, nil
		elseif session.state == "confirming" and a.confirmed and b.confirmed then
			session.state = "countdown"
			session.ends = workspace:GetServerTimeNow() + cfg.Countdown
			session.token += 1
			local token = session.token
			task.delay(cfg.Countdown, function()
				if session.state == "countdown" and session.token == token then
					complete(session)
				end
			end)
		end
		if session.state ~= "closed" then
			push(session)
			botFollow(session)
		end
	end
	push(session)
	-- Bot de pruebas: a los 3 s pide gemas, para ver una sugerencia recibida.
	for index, side in session.sides do
		if side.bot then
			task.delay(3, function()
				if session.state == "editing" and not side.suggest then
					setSuggest(session, side, session.sides[3 - index], { intent = "want", category = "gems", amount = 25 })
				end
			end)
		end
	end
end

-- Peticiones del cliente ------------------------------------------------------------------

local function validAmount(amount: unknown, owned: number): number?
	-- amount == amount descarta NaN.
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return nil
	end
	local whole = math.floor(amount)
	return if whole <= owned then whole else nil
end

-- Cambia la oferta de `side` (lo pide él, o acepta una sugerencia). Devuelve si el cambio valía.
local function applyOffer(session, side, other, category: unknown, key: unknown, amount: unknown): boolean
	-- El bot de pruebas tiene de todo, pero solo cantidades.
	local data = if side.bot then { coins = math.huge, gems = math.huge, items = {} } else PlayerData.read(side.player)
	if session.state ~= "editing" or not data then
		return false
	end
	local offer = side.offer
	local on = amount == 1 or amount == true
	-- Espadas, armadura y accesorios van por id o índice: tiene que ser un número de verdad (no NaN).
	if (category == "swords" or category == "armor" or category == "artifacts") and (side.bot or type(key) ~= "number" or key ~= key) then
		return false
	end
	if category == "coins" or category == "gems" then
		local value = validAmount(amount, data[category])
		if not value then
			return false
		end
		offer[category] = value
	elseif category == "items" then
		if type(key) ~= "string" or not Config.Items[key] then
			return false
		end
		local value = validAmount(amount, if side.bot then math.huge else data.items[key] or 0)
		if not value then
			return false
		end
		offer.items[key] = if value > 0 then value else nil
	elseif category == "swords" then
		-- La equipada no se puede dar: hay que equipar otra antes.
		if on and (not PlayerData.findSword(data, key) or key == data.equipped) then
			return false
		end
		offer.swords[key] = if on then true else nil
	elseif category == "armor" then
		if on and not findArmor(data, key) then
			return false
		end
		offer.armor[key] = if on then true else nil
	elseif category == "artifacts" then
		if on and not table.find(data.artifacts, key) then
			return false
		end
		offer.artifacts[key] = if on then true else nil
	else
		return false
	end
	-- Cualquier cambio quita el "aceptar" de los dos: nadie acepta una oferta que luego cambia.
	side.accepted, other.accepted = false, false
	-- Y la sugerencia de quien cambia su oferta: se hizo viendo la de antes.
	side.suggest = nil
	push(session)
	return true
end

local function onOffer(player: Player, category: unknown, key: unknown, amount: unknown)
	local session, side, other = sideOf(player)
	if session then
		applyOffer(session, side, other, category, key, amount)
	end
end

-- Sugerencias: "want" (quiero eso tuyo) o "give" (te doy eso mío). Se guardan fuera de la oferta, así que por sí
-- solas no mueven nada: aceptar una solo cambia una oferta, y el trato sigue pidiendo Aceptar, Confirmar y la cuenta atrás.
local function notice(side, text: string, color: Color3)
	if side.player then
		Remotes.Notice:FireClient(side.player, text, color)
	end
end

-- Quita la sugerencia `suggest` de `side` si sigue siendo la suya (puede haberla sustituido otra).
local function dropSuggest(session, side, suggest)
	if side.suggest == suggest and session.state ~= "closed" then
		side.suggest = nil
		push(session)
	end
end

-- `side` responde a la sugerencia de `other`.
function respondSuggest(session, side, other, accept: boolean)
	local suggest = other.suggest
	if session.state ~= "editing" or not suggest or suggest.ignored then
		return
	end
	if not accept then
		-- Se queda un momento marcada como ignorada para que quien la mandó lo vea.
		suggest.ignored = true
		push(session)
		task.delay(2, dropSuggest, session, other, suggest)
		return
	end
	other.suggest = nil
	if suggest.intent == "want" then
		-- Va a la oferta de quien acepta, con lo que tenga.
		local owned = math.huge
		if side.player then
			local data = PlayerData.read(side.player)
			owned = if not data then 0 elseif suggest.category == "items" then data.items[suggest.key] or 0 else data[suggest.category]
		end
		local value = math.min(suggest.amount, owned)
		if value < 1 then
			notice(side, "No tienes nada de eso", BAD)
			push(session)
			return
		end
		if value < suggest.amount then
			notice(side, "No tienes tanto: se pone lo que tienes", BAD)
		end
		if not applyOffer(session, side, other, suggest.category, suggest.key, value) then
			push(session)
		end
	elseif not applyOffer(session, other, side, suggest.category, suggest.key, suggest.amount) then
		-- "Te doy": a la oferta de quien la mandó, si sigue teniéndolo.
		notice(side, `{other.name} ya no tiene eso`, BAD)
		push(session)
	end
end

-- Pone la sugerencia de `side` (sustituye a la que tuviera) y la hace caducar.
function setSuggest(session, side, other, suggest)
	suggest.ends = workspace:GetServerTimeNow() + cfg.SuggestTime
	side.suggest = suggest
	push(session)
	task.delay(cfg.SuggestTime, dropSuggest, session, side, suggest)
	if other.bot then
		-- Bot de pruebas: responde al segundo; ignora los "Quiero" de más de 1000 y acepta lo demás.
		task.delay(1, function()
			if side.suggest == suggest then
				respondSuggest(session, other, side, not (suggest.intent == "want" and suggest.amount > 1000))
			end
		end)
	end
end

local function onSuggest(player: Player, intent: unknown, category: unknown, key: unknown, amount: unknown)
	local session, side, other = sideOf(player)
	local data = PlayerData.read(player)
	if not session or session.state ~= "editing" or not data then
		return
	end
	if intent == nil then
		if side.suggest then
			side.suggest = nil
			push(session)
		end
		return
	end
	local now = os.clock()
	if now - (lastSuggest[player] or 0) < cfg.SuggestCooldown then
		return
	end
	lastSuggest[player] = now
	local byAmount = category == "coins" or category == "gems" or category == "items"
	if category == "items" then
		if type(key) ~= "string" or not Config.Items[key] then
			return
		end
	elseif byAmount then
		key = nil
	elseif type(key) ~= "number" or key ~= key then
		return
	end
	local value = 1
	if byAmount then
		-- "Quiero" no se recorta con lo que tenga el otro, para no chivar cuánto tiene.
		local owned = if intent == "want" then cfg.SuggestMaxAmount elseif category == "items" then data.items[key] or 0 else data[category]
		local valid = validAmount(amount, owned)
		if not valid or valid < 1 then
			return
		end
		value = valid
	end
	if intent == "want" then
		if not cfg.SuggestWant[category] then
			return
		end
	elseif intent == "give" then
		if category == "swords" then
			if not PlayerData.findSword(data, key) or key == data.equipped then
				return
			end
		elseif category == "armor" then
			if not findArmor(data, key) then
				return
			end
		elseif category == "artifacts" then
			if not table.find(data.artifacts, key) then
				return
			end
		elseif not byAmount then
			return
		end
	else
		return
	end
	setSuggest(session, side, other, { intent = intent, category = category, key = key, amount = value })
end

local function onSuggestRespond(player: Player, accept: unknown)
	local session, side, other = sideOf(player)
	if session then
		respondSuggest(session, side, other, accept == true)
	end
end

local function onAccept(player: Player, value: unknown)
	local session, side, other = sideOf(player)
	if not session then
		return
	end
	if session.state == "editing" then
		if value == true and isEmpty(side.offer) and isEmpty(other.offer) then
			return
		end
		side.accepted = value == true
		session.advance()
	elseif session.state == "confirming" and value ~= true then
		-- "Volver": se desbloquean las ofertas y hay que aceptar otra vez.
		session.state = "editing"
		for _, each in session.sides do
			each.accepted, each.confirmed = false, false
		end
		push(session)
	end
end

local function onConfirm(player: Player)
	local session, side = sideOf(player)
	if session and session.state == "confirming" then
		side.confirmed = true
		session.advance()
	end
end

local function onCancel(player: Player)
	local session, side = sideOf(player)
	if session then
		close(session, `{side.name} ha cancelado el trato`, BAD)
	end
end

local function onRequest(player: Player, userId: unknown)
	local now = os.clock()
	if sessions[player] or now - (lastRequest[player] or 0) < cfg.RequestCooldown or not PlayerData.read(player) then
		return
	end
	lastRequest[player] = now
	if userId == 0 then
		if botAllowed() then
			start(player, nil)
		end
		return
	end
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target or target == player then
		return
	end
	if sessions[target] then
		Remotes.Notice:FireClient(player, `{target.DisplayName} ya está en otro trato`, BAD)
		return
	end
	invites[target] = invites[target] or {}
	invites[target][player] = now + cfg.InviteTime
	Remotes.TradeInvite:FireClient(target, player.UserId, player.DisplayName)
	Remotes.Notice:FireClient(player, `Invitación enviada a {target.DisplayName}`, GOOD)
end

local function onRespond(player: Player, userId: unknown, accept: unknown)
	local from = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local pending = invites[player]
	local expires = from and pending and pending[from]
	if not from or not expires then
		return
	end
	pending[from] = nil
	if accept ~= true then
		Remotes.Notice:FireClient(from, `{player.DisplayName} ha rechazado el trato`, BAD)
		return
	end
	if os.clock() > expires or sessions[player] or sessions[from] or not PlayerData.read(player) or not PlayerData.read(from) then
		Remotes.Notice:FireClient(player, "La invitación ya no vale", BAD)
		return
	end
	start(from, player)
end

function Trade.start()
	Remotes.TradeRequest.OnServerEvent:Connect(onRequest)
	Remotes.TradeRespond.OnServerEvent:Connect(onRespond)
	Remotes.TradeOffer.OnServerEvent:Connect(onOffer)
	Remotes.TradeAccept.OnServerEvent:Connect(onAccept)
	Remotes.TradeConfirm.OnServerEvent:Connect(onConfirm)
	Remotes.TradeCancel.OnServerEvent:Connect(onCancel)
	Remotes.TradeSuggest.OnServerEvent:Connect(onSuggest)
	Remotes.TradeSuggestRespond.OnServerEvent:Connect(onSuggestRespond)

	local function onPlayer(player: Player)
		player:SetAttribute("TradeBot", botAllowed())
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			close(session, `{player.DisplayName} se ha ido: trato cancelado`, BAD)
		end
		invites[player] = nil
		for _, pending in invites do
			pending[player] = nil
		end
		lastRequest[player] = nil
		lastSuggest[player] = nil
	end)
end

return Trade
