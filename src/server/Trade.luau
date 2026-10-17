-- Comercio entre jugadores. Uno invita, el otro acepta y se abre un trato: cada uno pone lo que da (objetos, espadas,
-- armadura y accesorios; lo que se puede cambiar lo dice Config.Trade.Allow, y monedas y gemas no están: decidido
-- por el usuario, para que el progreso no se pueda regalar). Pasos, pensados contra los timos:
--   1. "editing": se cambian las ofertas; cualquier cambio quita el "aceptar" de los dos.
--   2. "confirming": cuando los dos han aceptado las ofertas quedan bloqueadas y cada uno tiene que CONFIRMAR.
--   3. "countdown": con los dos confirmados corren Config.Trade.Countdown segundos en los que cualquiera puede cancelar.
-- Al acabar la cuenta se vuelve a comprobar todo (que cada uno sigue teniendo lo que ofrece y que al otro le cabe)
-- y se cambia de una vez. El cliente solo pide; aquí se valida cada paso.
-- En Studio (Config.Test.TradeBot) hay un "Bot de pruebas" (userId 0) para probarlo con un solo jugador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Armor = require(script.Parent.Armor)
local PlayerData = require(script.Parent.PlayerData)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)
local Policy = require(script.Parent.Policy)

local Trade = {}

local cfg = Config.Trade
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)

local sessions = {} -- [Player] = trato en el que está
local invites = {} -- [invitado] = { [quien invita] = os.clock() en que caduca }
local lastRequest = {} -- [Player] = os.clock() de su última invitación
local lastSuggest = {} -- [Player] = os.clock() de su última sugerencia

-- Tope de peticiones de trato por jugador y segundo: cada una reenvía el estado entero a los dos, así que un cliente
-- con trampas podía inundar al servidor y al otro jugador. A mano no se llega ni de lejos.
local RATE_LIMIT = 30
local calls = {} -- [Player] = { since = os.clock() en que empezó la cuenta, count }

local function limited(handler)
	return function(player: Player, ...)
		local now = os.clock()
		local bucket = calls[player]
		if not bucket or now - bucket.since >= 1 then
			calls[player] = { since = now, count = 1 }
		else
			bucket.count += 1
			if bucket.count > RATE_LIMIT then
				return
			end
		end
		handler(player, ...)
	end
end

local function botAllowed(): boolean
	return RunService:IsStudio() and Config.Test.TradeBot == true
end

local function newSide(player: Player?)
	return {
		player = player,
		bot = player == nil,
		name = if player then player.DisplayName else "Test bot",
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
	return { id = copy.id, sword = copy.sword, trait = copy.trait or 0, grade = copy.grade or 0, metal = copy.metal or 0, size = copy.size or 0, level = copy.level or 0 }
end

-- Cómo es una copia, en un texto: para comprobar al cerrar el trato que sigue igual que cuando se aceptó.
local function swordMark(copy): string
	return `{copy.sword}:{copy.trait or 0}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}:{copy.level or 0}`
end

-- Apunta cómo son las espadas que ofrece ese lado (al bloquearse las ofertas).
local function freeze(side)
	side.frozen = nil
	local data = if side.player then PlayerData.read(side.player) else nil
	if not data then
		return
	end
	side.frozen = {}
	for id in side.offer.swords do
		local copy = PlayerData.findSword(data, id)
		if copy then
			side.frozen[id] = swordMark(copy)
		end
	end
end

local function pieceView(piece)
	return { id = piece.id, slot = piece.slot, quality = piece.quality, level = piece.level, stats = piece.stats }
end

-- La petición en curso de un lado tal y como la ve el cliente, o nil. Lo pedido es del otro lado (`other`): la espada o
-- la pieza salen ya resueltas de sus datos.
local function suggestView(side, other)
	local suggest = side.suggest
	if not suggest then
		return nil
	end
	local out = { intent = suggest.intent, category = suggest.category, key = suggest.key, amount = suggest.amount, ends = suggest.ends, ignored = suggest.ignored }
	local data = if other.player then PlayerData.read(other.player) else nil
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
local function view(side, other)
	local offer = side.offer
	local out = {
		name = side.name,
		userId = side.userId,
		accepted = side.accepted,
		confirmed = side.confirmed,
		suggest = suggestView(side, other),
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
			local other = session.sides[3 - index]
			Remotes.TradeState:FireClient(side.player, { state = session.state, ends = session.ends, you = view(side, other), them = view(other, side) })
		end
	end
end

-- Cierra el trato sin cambiar nada. `text` es el aviso que ven los dos: la frase en inglés (con sus huecos en `args`)
-- o una función (lector) -> texto (ver server/Tell).
local function close(session, text: any, color: Color3, args: { [string]: any }?)
	for _, side in session.sides do
		local player = side.player
		if player and sessions[player] == session then
			sessions[player] = nil
			Remotes.TradeState:FireClient(player, nil)
			Tell.notice(player, color, text, args)
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

-- El motivo de un trato que no se puede cerrar, para leerlo cada uno en su idioma: (lector) -> texto.
local function why(text: string, side, item: string?)
	return function(reader: Player?): string
		return Lang.t(reader, text, { name = side.name, item = if item then Lang.t(reader, item) else nil })
	end
end

-- ¿Sigue teniendo ese lado todo lo que ofrece, y le cabe lo que le da el otro? Devuelve nil si todo bien, o
-- el motivo por el que no.
local function problem(side, other): any
	if side.bot then
		return nil
	end
	local data = PlayerData.read(side.player)
	if not data then
		return why("{name}'s data isn't loaded", side)
	end
	local offer = side.offer
	if data.coins < offer.coins or data.gems < offer.gems then
		return why("{name} no longer has those coins or gems", side)
	end
	for name, amount in offer.items do
		if PlayerData.tradable(data, name) < amount then
			return why("{name} no longer has those items", side)
		end
	end
	for id in offer.swords do
		local copy = PlayerData.findSword(data, id)
		if not copy or PlayerData.isLocked(data, id) then
			return why("{name} no longer has one of the swords (or it's equipped or in their bag)", side)
		end
		-- Tiene que ser la misma que el otro aceptó: con las ofertas ya bloqueadas se le podía cambiar el rasgo o
		-- descartar el grado recién tirado en la forja, y el otro recibía un arma peor que la que vio.
		if side.frozen and side.frozen[id] ~= swordMark(copy) then
			return why("{name} changed one of the swords after accepting", side)
		end
	end
	for id in offer.armor do
		if not findArmor(data, id) then
			return why("{name} no longer has one of the armor pieces", side)
		end
	end
	for index in offer.artifacts do
		if not table.find(data.artifacts, index) then
			return why("{name} no longer has one of the accessories", side)
		end
	end
	-- Lo que recibe. Sin sitio para armas o armadura el trato sigue: `give` se queda con las mejores (pedido por el
	-- usuario: muchos tratos se cancelaban por la mochila llena).
	local incoming = other.offer
	for index in incoming.artifacts do
		-- Se pueden tener repetidos, hasta el tope de copias (un trato mueve una copia de cada accesorio).
		if Stats.copies(data.artifacts, index) >= Config.ArtifactCopies and not offer.artifacts[index] then
			return why("{name} can't hold more of the accessory {item}", side, Config.Artifacts[index].name)
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
				-- Si era su última copia, deja de llevarlo puesto.
				local worn = table.find(data.gear, index)
				if worn and not table.find(data.artifacts, index) then
					table.remove(data.gear, worn)
				end
				table.insert(pack.artifacts, index)
			end
		end
	end)
	return pack
end

-- Con más armas o piezas que el tope, quita las peores hasta caber: armas por daño (sin tocar equipadas, de la bolsa
-- ni con candado) y piezas por nota (sin tocar las puestas). Las que acaban de llegar cuentan igual: si son peores que
-- todas, son ellas las que se van. Devuelve cuántas quitó de cada.
local function trim(data): (number, number)
	local swords, armor = 0, 0
	while #data.swords > Config.MaxSwords do
		local worst, worstDamage = nil, math.huge
		for position, copy in data.swords do
			if not PlayerData.isLocked(data, copy.id) then
				local damage = Stats.swordDamage(copy)
				if damage < worstDamage then
					worst, worstDamage = position, damage
				end
			end
		end
		if not worst then
			break
		end
		table.remove(data.swords, worst)
		swords += 1
	end
	while #data.armor > Config.Armor.MaxPieces do
		local worst, worstScore = nil, math.huge
		for position, piece in data.armor do
			if data.armorWorn[piece.slot] ~= piece.id then
				local score = ArmorStats.score(piece)
				if score < worstScore then
					worst, worstScore = position, score
				end
			end
		end
		if not worst then
			break
		end
		table.remove(data.armor, worst)
		armor += 1
	end
	return swords, armor
end

-- Mete un paquete en el inventario de un lado (con ids nuevos).
local function give(side, pack)
	if side.bot then
		return
	end
	local droppedSwords, droppedArmor = 0, 0
	PlayerData.editArmor(side.player, function(data)
		-- No cuenta como monedas ganadas (clasificaciones): se suman a mano, sin addCoins.
		data.coins += pack.coins
		data.gems += pack.gems
		for name, amount in pack.items do
			data.items[name] = (data.items[name] or 0) + amount
		end
		for _, copy in pack.swords do
			table.insert(data.swords, { id = data.nextSwordId, sword = copy.sword, trait = copy.trait, grade = copy.grade, metal = copy.metal, size = copy.size, level = copy.level })
			data.nextSwordId += 1
		end
		for _, piece in pack.armor do
			table.insert(data.armor, { id = data.nextArmorId, slot = piece.slot, quality = piece.quality, level = piece.level, stats = piece.stats })
			data.nextArmorId += 1
		end
		for _, index in pack.artifacts do
			if Stats.copies(data.artifacts, index) < Config.ArtifactCopies then
				table.insert(data.artifacts, index)
			end
		end
		table.sort(data.artifacts)
		droppedSwords, droppedArmor = trim(data)
	end)
	if droppedSwords + droppedArmor > 0 then
		Tell.notice(side.player, Color3.fromRGB(255, 170, 60), "Backpack full: you kept the best ones and {n} worse items were removed.", { n = droppedSwords + droppedArmor })
	end
end

-- Copia profunda de lo que toca un trato, para deshacerlo si el cambio falla a medias.
local TOUCHED = { "coins", "gems", "items", "swords", "nextSwordId", "armor", "armorWorn", "nextArmorId", "artifacts", "gear" }
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = deepCopy(item)
	end
	return out
end
local function snapshot(data)
	local copy = {}
	for _, field in TOUCHED do
		copy[field] = deepCopy(data[field])
	end
	return copy
end
local function restore(data, copy)
	for _, field in TOUCHED do
		data[field] = deepCopy(copy[field])
	end
end

local function complete(session)
	local a, b = session.sides[1], session.sides[2]
	local reason = problem(a, b) or problem(b, a)
	if reason then
		close(session, function(reader)
			return Lang.t(reader, "Trade cancelled: {reason}", { reason = reason(reader) })
		end, BAD)
		return
	end
	-- El cambio va de una vez: si algo falla a medias (se le había quitado a uno y aún no le había llegado al otro), se
	-- deja a los dos como estaban. Pasó (un jugador dio cristales y al otro no le llegaron).
	local before = {}
	for _, side in session.sides do
		if side.player then
			before[side.player] = snapshot(PlayerData.read(side.player))
		end
	end
	local ok, err = pcall(function()
		local fromA, fromB = take(a), take(b)
		give(a, fromB)
		give(b, fromA)
	end)
	if not ok then
		warn(`[Trade] Exchange failed, undone: {err}`)
		for player, copy in before do
			PlayerData.editArmor(player, function(data)
				restore(data, copy)
			end)
		end
		close(session, "Trade failed: nothing was exchanged", BAD)
		return
	end
	-- Se guardan los dos ya: si solo se guardara el primero que se va (y el servidor se cerrara mal antes de guardar al
	-- otro), lo cambiado quedaría en los dos lados.
	for _, side in session.sides do
		if side.player then
			task.spawn(PlayerData.save, side.player)
		end
	end
	close(session, "Trade complete!", GOOD)
end

-- Peticiones (definidas más abajo, con las del cliente): las usa también el bot de pruebas.
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
			side.offer.items.gradeCrystal = 5
			side.offer.items.traitCrystal = 3
		end
	end
	-- Pasa de paso cuando los dos han aceptado o confirmado.
	function session.advance()
		local a, b = session.sides[1], session.sides[2]
		if session.state == "editing" and a.accepted and b.accepted then
			session.state = "confirming"
			-- Las sugerencias solo valen mientras se eligen las ofertas.
			a.suggest, b.suggest = nil, nil
			freeze(a)
			freeze(b)
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
	-- Bot de pruebas: a los 3 s pide cristales, para ver una petición recibida.
	for index, side in session.sides do
		if side.bot then
			task.delay(3, function()
				if session.state == "editing" and not side.suggest then
					setSuggest(session, side, session.sides[3 - index], { intent = "want", category = "items", key = "traitCrystal", amount = 5 })
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
	-- Solo lo que se puede comerciar (monedas y gemas, no): esta es la única puerta por la que cambia una oferta.
	if type(category) ~= "string" or not cfg.Allow[category] then
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
		-- Los tickets de misión no se comercian (noTrade).
		if type(key) ~= "string" or not Config.Items[key] or Config.Items[key].noTrade then
			return false
		end
		-- Los atados a la cuenta (de códigos y del tutorial) no cuentan.
		local value = validAmount(amount, if side.bot then math.huge else PlayerData.tradable(data, key))
		if not value then
			return false
		end
		offer.items[key] = if value > 0 then value else nil
	elseif category == "swords" then
		-- Las equipadas y las de la Bolsa de oro no se pueden dar: hay que quitarlas antes.
		if on and (not PlayerData.findSword(data, key) or PlayerData.isLocked(data, key)) then
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
	-- Y la petición de quien cambia su oferta (se hizo viendo la de antes).
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

-- Peticiones (botón "Pedir"): un lado le pide al otro algo de su inventario (una espada, una pieza de armadura, un
-- accesorio o una cantidad de un objeto). Se guardan fuera de la oferta, así que por sí solas no mueven nada: aceptar
-- una solo la añade a la oferta de quien acepta, y el trato sigue pidiendo Aceptar, Confirmar y la cuenta atrás. Van
-- con intent = "want": el "Te doy" de antes se quitó (pedido por el usuario).
local function notice(side, text: string, color: Color3, args: { [string]: any }?)
	Tell.notice(side.player, color, text, args)
end

-- Quita la petición `suggest` de `side` si sigue siendo la suya (puede haberla sustituido otra).
local function dropSuggest(session, side, suggest)
	if side.suggest == suggest and session.state ~= "closed" then
		side.suggest = nil
		push(session)
	end
end

-- `side` responde a la petición de `other`: si acepta, va a su oferta.
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
	if suggest.category ~= "items" then
		-- Espada, pieza o accesorio: applyOffer vuelve a comprobar que lo tiene y que se puede dar.
		if not applyOffer(session, side, other, suggest.category, suggest.key, 1) then
			notice(side, "You can't give that anymore", BAD)
			push(session)
		end
		return
	end
	-- Cantidad: se suma a lo que ya ofrecía de eso, hasta lo que tenga.
	local owned = math.huge
	if side.player then
		local data = PlayerData.read(side.player)
		owned = if data then PlayerData.tradable(data, suggest.key) else 0
	end
	local already = side.offer.items[suggest.key] or 0
	local value = math.min(already + suggest.amount, owned)
	if value <= already then
		notice(side, "You don't have any of that", BAD)
		push(session)
		return
	end
	if value < already + suggest.amount then
		notice(side, "You don't have that many: what you have was added", BAD)
	end
	if not applyOffer(session, side, other, "items", suggest.key, value) then
		push(session)
	end
end

-- Pone la petición de `side` (sustituye a la que tuviera) y la hace caducar.
function setSuggest(session, side, other, suggest)
	suggest.ends = workspace:GetServerTimeNow() + cfg.SuggestTime
	side.suggest = suggest
	push(session)
	task.delay(cfg.SuggestTime, dropSuggest, session, side, suggest)
	if other.bot then
		-- Bot de pruebas: responde al segundo; ignora las de más de 1000 y acepta lo demás.
		task.delay(1, function()
			if side.suggest == suggest then
				respondSuggest(session, other, side, suggest.amount <= 1000)
			end
		end)
	end
end

local function onSuggest(player: Player, intent: unknown, category: unknown, key: unknown, amount: unknown)
	local session, side, other = sideOf(player)
	if not session or session.state ~= "editing" then
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
	if intent ~= "want" or type(category) ~= "string" or not cfg.Allow[category] or not cfg.SuggestWant[category] then
		return
	end
	local value = 1
	if category == "items" then
		if type(key) ~= "string" or not Config.Items[key] or Config.Items[key].noTrade then
			return
		end
		-- No se recorta con lo que tenga el otro: al aceptar se pone lo que tenga.
		local valid = validAmount(amount, cfg.SuggestMaxAmount)
		if not valid or valid < 1 then
			return
		end
		value = valid
	else
		-- Espada, pieza o accesorio del inventario del otro, por su id (el accesorio, por su índice). Al bot de pruebas
		-- solo se le piden cantidades.
		local data = if other.player then PlayerData.read(other.player) else nil
		if not data or type(key) ~= "number" or key ~= key then
			return
		end
		if category == "swords" then
			-- Ni las equipadas, ni las de la Bolsa de oro, ni las del candado.
			if not PlayerData.findSword(data, key) or PlayerData.isLocked(data, key) then
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
		else
			return
		end
	end
	setSuggest(session, side, other, { intent = "want", category = category, key = key, amount = value })
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
			each.frozen = nil
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
		close(session, "{name} cancelled the trade", BAD, { name = side.name })
	end
end

-- El comercio se abre con el primer renacimiento (Config.Trade.MinRebirths), contra las cuentas nuevas que solo
-- sirven para pasarle a otra lo que dan gratis.
local function unlocked(player: Player): boolean
	local data = PlayerData.read(player)
	return data ~= nil and data.rebirths >= cfg.MinRebirths
end

local function onRequest(player: Player, userId: unknown)
	local now = os.clock()
	if sessions[player] or now - (lastRequest[player] or 0) < cfg.RequestCooldown or not PlayerData.read(player) then
		return
	end
	lastRequest[player] = now
	-- Países donde Roblox no deja intercambiar objetos de pago (server/Policy).
	if not Policy.canTrade(player) then
		Tell.notice(player, BAD, "Trading isn't available in your region")
		return
	end
	if not unlocked(player) then
		Tell.notice(player, BAD, "Trading unlocks after your first rebirth")
		return
	end
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
		Tell.notice(player, BAD, "{name} is already in another trade", { name = target.DisplayName })
		return
	end
	if not Policy.canTrade(target) then
		Tell.notice(player, BAD, "{name} can't trade in their region", { name = target.DisplayName })
		return
	end
	if not unlocked(target) then
		Tell.notice(player, BAD, "{name} can't trade until their first rebirth", { name = target.DisplayName })
		return
	end
	invites[target] = invites[target] or {}
	invites[target][player] = now + cfg.InviteTime
	Remotes.TradeInvite:FireClient(target, player.UserId, player.DisplayName)
	Tell.notice(player, GOOD, "Invite sent to {name}", { name = target.DisplayName })
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
		Tell.notice(from, BAD, "{name} declined the trade", { name = player.DisplayName })
		return
	end
	if os.clock() > expires or not Policy.canTrade(player) or not Policy.canTrade(from) or not unlocked(player) or not unlocked(from) or sessions[player] or sessions[from] or not PlayerData.read(player) or not PlayerData.read(from) then
		Tell.notice(player, BAD, "The invite is no longer valid")
		return
	end
	start(from, player)
end

function Trade.start()
	Remotes.TradeRequest.OnServerEvent:Connect(onRequest)
	Remotes.TradeRespond.OnServerEvent:Connect(onRespond)
	Remotes.TradeOffer.OnServerEvent:Connect(limited(onOffer))
	Remotes.TradeAccept.OnServerEvent:Connect(limited(onAccept))
	Remotes.TradeConfirm.OnServerEvent:Connect(limited(onConfirm))
	Remotes.TradeCancel.OnServerEvent:Connect(onCancel)
	Remotes.TradeSuggest.OnServerEvent:Connect(limited(onSuggest))
	Remotes.TradeSuggestRespond.OnServerEvent:Connect(limited(onSuggestRespond))

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
			close(session, "{name} left: trade cancelled", BAD, { name = player.DisplayName })
		end
		invites[player] = nil
		for _, pending in invites do
			pending[player] = nil
		end
		lastRequest[player] = nil
		lastSuggest[player] = nil
		calls[player] = nil
	end)
end

return Trade
