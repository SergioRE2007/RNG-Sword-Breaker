-- Grupos (party) de mazmorra. En el altar de cada sala del lobby (server/DungeonLobby) se abre la ventana del grupo
-- (client/Party): ahí se crea un grupo o se entra en uno abierto de esa sala, se invita a otros jugadores, el líder elige
-- la zona y las opciones, todos marcan "Listo" y el líder inicia: cuenta atrás y Dungeons.launch con todo el grupo.
-- El estado real vive solo aquí (quién está en qué grupo, quién lidera, qué zona y opciones, cuándo empieza): el
-- cliente pide con PartyRequest y se le manda el estado con PartyState. Todo se valida: la acción tiene que estar en la
-- lista, los argumentos del tipo que toca, hay un tiempo mínimo entre peticiones, para crear o entrar hay que estar junto
-- al altar de esa sala, y solo el líder cambia, expulsa, invita o inicia.
-- Reglas: entre Config.Party.MinSize y MaxSize jugadores; si el líder se va, lidera el siguiente (sin nadie, se
-- deshace); con una partida en marcha no entra nadie; al terminar la partida el grupo se deshace y los que siguen
-- vivos vuelven a su sala; un grupo que espera más de Config.Party.WaitTimeout sin empezar se deshace.
-- Pruebas: Config.Test.PartyBots mete compañeros "fantasma" (cuentan para el tamaño y el escalado, no pelean).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonInfo = require(ReplicatedStorage.Shared.DungeonInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DungeonLobby = require(script.Parent.DungeonLobby)
local Dungeons = require(script.Parent.Dungeons)

local Party = {}

local cfg = Config.Party
local RED = Color3.fromRGB(255, 120, 120)
local GREEN = Color3.fromRGB(120, 235, 130)

-- party = { id, dungeon, leader = member, members = { member }, options = { loop, public }, state, countdownEnds, token, activeAt }
-- member = { player = Player?, userId, name, ready, bot? }  (los bots no tienen player)
local parties = {}
local partyOf: { [Player]: any } = {}
local viewing: { [Player]: number } = {} -- zona de la sala que mira cada jugador con la ventana abierta
local invites: { [Player]: { [Player]: number } } = {} -- invitado -> líder -> hora a la que caduca
local lastAction: { [Player]: number } = {}
local nextId = 0

local function notice(player: Player?, text: string, color: Color3?)
	if player and player.Parent then
		Remotes.Notice:FireClient(player, text, color or RED)
	end
end

local function memberOf(party, player: Player)
	for _, member in party.members do
		if member.player == player then
			return member
		end
	end
	return nil
end

local function realCount(party): number
	local count = 0
	for _, member in party.members do
		if member.player then
			count += 1
		end
	end
	return count
end

local function liveRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function nearRoom(player: Player, zone: number): boolean
	local root = liveRoot(player)
	local pad = DungeonLobby.padPosition(zone)
	return root ~= nil and pad ~= nil and (root.Position - pad).Magnitude <= cfg.RoomDistance
end

-- ¿Puede este jugador jugar esa zona ahora? (no está ya en una partida, está vivo y le llega lo que pida la zona)
local function canPlay(player: Player, zone: number): (boolean, string?)
	if Dungeons.isBusy(player) then
		return false, "Ya estás en una mazmorra."
	end
	if not liveRoot(player) then
		return false, "No puedes entrar ahora mismo."
	end
	local lock = DungeonInfo.lock(zone, Stats.damage(player))
	if lock then
		return false, lock
	end
	return true, nil
end

-- Estado -------------------------------------------------------------------------------------------------------------

local function snapshot(party)
	local members = {}
	for _, member in party.members do
		table.insert(members, { userId = member.userId, name = member.name, ready = member.ready or member == party.leader, bot = member.bot })
	end
	return {
		id = party.id,
		dungeon = party.dungeon,
		leader = party.leader.userId,
		state = party.state,
		countdownEnds = party.countdownEnds,
		options = { loop = party.options.loop, public = party.options.public },
		max = cfg.MaxSize,
		members = members,
	}
end

local function push(player: Player)
	local party = partyOf[player]
	local room = viewing[player]
	if not party and not room then
		Remotes.PartyState:FireClient(player, nil)
		return
	end
	local payload: { [string]: any } = { room = room, mine = if party then snapshot(party) else nil }
	if not party and room then
		-- Los grupos abiertos de la sala que mira.
		local list = {}
		for _, other in parties do
			if other.dungeon == room and other.state == "lobby" and other.options.public then
				table.insert(list, { id = other.id, leader = other.leader.name, size = #other.members, max = cfg.MaxSize })
			end
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		payload.parties = list
	end
	Remotes.PartyState:FireClient(player, payload)
end

-- Cuenta a quien espera en cada sala (el cartel lo enseña) y avisa a todos los que tienen algo que ver.
local function pushAll()
	local told = {}
	for player in partyOf do
		told[player] = true
	end
	for player in viewing do
		told[player] = true
	end
	for player in told do
		if player.Parent then
			push(player)
		end
	end
	local waiting = {}
	for _, party in parties do
		if party.state == "lobby" then
			waiting[party.dungeon] = (waiting[party.dungeon] or 0) + realCount(party)
		end
	end
	for index in Config.Dungeons do
		DungeonLobby.setWaiting(index, waiting[index] or 0)
	end
end

local function touch(party)
	party.activeAt = os.clock()
end

local function cancelCountdown(party)
	if party.state == "starting" then
		party.state = "lobby"
		party.countdownEnds = 0
		party.token += 1
	end
end

-- Al cambiar algo importante (alguien entra o sale, otra zona...) hay que volver a marcar "Listo".
local function resetReady(party)
	for _, member in party.members do
		if member ~= party.leader then
			member.ready = member.bot == true
		end
	end
end

local function disband(party, text: string?)
	if parties[party.id] ~= party then
		return
	end
	parties[party.id] = nil
	party.token += 1
	local gone = {}
	for _, member in party.members do
		if member.player then
			partyOf[member.player] = nil
			table.insert(gone, member.player)
		end
	end
	for _, player in gone do
		if text then
			notice(player, text)
		end
		push(player)
	end
	pushAll()
end

local function removeMember(party, member)
	local index = table.find(party.members, member)
	if not index then
		return
	end
	table.remove(party.members, index)
	local player = member.player
	if player then
		partyOf[player] = nil
	end
	cancelCountdown(party)
	resetReady(party)
	if member == party.leader then
		party.leader = nil
		for _, other in party.members do
			if other.player then
				party.leader = other
				break
			end
		end
	end
	if not party.leader then
		disband(party)
		if player then
			push(player)
		end
		return
	end
	if member.player and party.leader.player then
		notice(party.leader.player, `{member.name} ha dejado el grupo.`, Color3.fromRGB(230, 230, 240))
	end
	touch(party)
	pushAll()
	if player then
		push(player)
	end
end

-- Compañeros fantasma de pruebas (solo en Studio).
local function addBots(party)
	if not RunService:IsStudio() then
		return
	end
	local wanted = math.min(Config.Test.PartyBots or 0, cfg.MaxSize - #party.members)
	for number = 1, wanted do
		table.insert(party.members, { userId = -number, name = `Bot {number}`, ready = true, bot = true })
	end
end

local function createParty(player: Player, zone: number, public: boolean)
	nextId += 1
	local leader = { player = player, userId = player.UserId, name = player.DisplayName, ready = true }
	local party = {
		id = nextId,
		dungeon = zone,
		leader = leader,
		members = { leader },
		options = { loop = Dungeons.getLoop(player), public = public },
		state = "lobby",
		countdownEnds = 0,
		token = 0,
		activeAt = os.clock(),
	}
	addBots(party)
	parties[party.id] = party
	partyOf[player] = party
	viewing[player] = zone
	return party
end

-- Inicio ------------------------------------------------------------------------------------------------------------

-- Por qué no se puede iniciar (texto), o nil si se puede.
local function startProblem(party): string?
	local size = #party.members
	if size < cfg.MinSize or size > cfg.MaxSize then
		return "El grupo no tiene el tamaño adecuado."
	end
	for _, member in party.members do
		if member.player then
			local ok, reason = canPlay(member.player, party.dungeon)
			if not ok then
				return `{member.name}: {reason}`
			end
			if not member.ready and member ~= party.leader then
				return `Falta que {member.name} marque Listo.`
			end
		end
	end
	return nil
end

local function launchParty(party)
	local problem = startProblem(party)
	if problem then
		party.state = "lobby"
		party.countdownEnds = 0
		notice(party.leader.player, problem)
		pushAll()
		return
	end
	local players, bots = { party.leader.player :: Player }, 0
	for _, member in party.members do
		if member.player and member ~= party.leader then
			table.insert(players, member.player)
		elseif not member.player then
			bots += 1
		end
	end
	Dungeons.setLoop(party.leader.player :: Player, party.options.loop)
	party.state = "running"
	party.countdownEnds = 0
	for _, player in players do
		viewing[player] = nil
	end
	pushAll()
	local run = Dungeons.launch(players, party.dungeon, {
		ghosts = bots,
		onEnd = function()
			disband(party)
		end,
	})
	if not run and parties[party.id] == party and party.state == "running" then
		party.state = "lobby"
		resetReady(party)
		notice(party.leader.player, "No se ha podido empezar la mazmorra. Inténtalo de nuevo.")
		for _, member in party.members do
			if member.player then
				viewing[member.player] = party.dungeon
			end
		end
		pushAll()
	end
end

-- Peticiones del cliente ----------------------------------------------------------------------------------------------

local HANDLERS: { [string]: (player: Player, a: unknown, b: unknown) -> () } = {}

local function validZone(zone: unknown): number?
	if type(zone) == "number" and Config.Dungeons[zone] then
		return zone
	end
	return nil
end

HANDLERS.open = function(player, zoneArg)
	local zone = validZone(zoneArg)
	if not zone or Dungeons.isBusy(player) or not nearRoom(player, zone) then
		return
	end
	viewing[player] = zone
	push(player)
end

HANDLERS.close = function(player)
	viewing[player] = nil
	push(player)
end

HANDLERS.create = function(player, zoneArg)
	local zone = validZone(zoneArg)
	if not zone or partyOf[player] or not nearRoom(player, zone) then
		return
	end
	local ok, reason = canPlay(player, zone)
	if not ok then
		notice(player, reason or "No puedes entrar.")
		return
	end
	createParty(player, zone, true)
	pushAll()
end

HANDLERS.solo = function(player, zoneArg)
	local zone = validZone(zoneArg)
	if not zone or partyOf[player] or not nearRoom(player, zone) then
		return
	end
	local ok, reason = canPlay(player, zone)
	if not ok then
		notice(player, reason or "No puedes entrar.")
		return
	end
	local party = createParty(player, zone, false)
	launchParty(party)
end

HANDLERS.join = function(player, idArg)
	if type(idArg) ~= "number" then
		return
	end
	local party = parties[idArg]
	if partyOf[player] or not party or party.state ~= "lobby" then
		return
	end
	local leaderPlayer = party.leader.player
	local invited = leaderPlayer ~= nil and invites[player] ~= nil and (invites[player][leaderPlayer] or 0) > os.clock()
	if not party.options.public and not invited then
		notice(player, "Es un grupo privado: hace falta invitación.")
		return
	end
	if #party.members >= cfg.MaxSize then
		notice(player, "El grupo está lleno.")
		return
	end
	if not nearRoom(player, party.dungeon) then
		return
	end
	local ok, reason = canPlay(player, party.dungeon)
	if not ok then
		notice(player, reason or "No puedes entrar.")
		return
	end
	table.insert(party.members, { player = player, userId = player.UserId, name = player.DisplayName, ready = false })
	partyOf[player] = party
	viewing[player] = party.dungeon
	invites[player] = nil
	cancelCountdown(party)
	resetReady(party)
	touch(party)
	notice(leaderPlayer, `{player.DisplayName} se ha unido al grupo.`, GREEN)
	pushAll()
end

HANDLERS.leave = function(player)
	local party = partyOf[player]
	if not party or party.state == "running" then
		return
	end
	local member = memberOf(party, player)
	if member then
		removeMember(party, member)
	end
end

HANDLERS.ready = function(player, value)
	local party = partyOf[player]
	if not party or party.state == "running" then
		return
	end
	local member = memberOf(party, player)
	if not member then
		return
	end
	local want = value == true
	if member == party.leader then
		-- El líder siempre está listo: aquí "no listo" solo sirve para cancelar la cuenta atrás.
		if not want and party.state == "starting" then
			cancelCountdown(party)
			pushAll()
		end
		return
	end
	if want then
		local ok, reason = canPlay(player, party.dungeon)
		if not ok then
			notice(player, reason or "No puedes entrar.")
			return
		end
	end
	member.ready = want
	if not want then
		cancelCountdown(party)
	end
	touch(party)
	pushAll()
end

HANDLERS.dungeon = function(player, zoneArg)
	local party = partyOf[player]
	local zone = validZone(zoneArg)
	if not party or not zone or party.leader.player ~= player or party.state ~= "lobby" or zone == party.dungeon then
		return
	end
	for _, member in party.members do
		if member.player then
			local lock = DungeonInfo.lock(zone, Stats.damage(member.player))
			if lock then
				notice(player, `{member.name}: {lock}`)
				return
			end
		end
	end
	party.dungeon = zone
	resetReady(party)
	touch(party)
	for _, member in party.members do
		if member.player then
			viewing[member.player] = zone
		end
	end
	pushAll()
end

HANDLERS.option = function(player, name, value)
	local party = partyOf[player]
	if not party or party.leader.player ~= player or party.state ~= "lobby" or type(value) ~= "boolean" then
		return
	end
	if name ~= "loop" and name ~= "public" then
		return
	end
	party.options[name] = value
	if name == "loop" then
		Dungeons.setLoop(player, value)
	end
	touch(party)
	pushAll()
end

HANDLERS.kick = function(player, userId)
	local party = partyOf[player]
	if not party or party.leader.player ~= player or party.state == "running" or type(userId) ~= "number" then
		return
	end
	for _, member in party.members do
		if member.userId == userId and member ~= party.leader then
			notice(member.player, "Te han echado del grupo.")
			removeMember(party, member)
			return
		end
	end
end

HANDLERS.invite = function(player, userId)
	local party = partyOf[player]
	if not party or party.leader.player ~= player or party.state ~= "lobby" or type(userId) ~= "number" then
		return
	end
	if #party.members >= cfg.MaxSize then
		notice(player, "El grupo está lleno.")
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player or partyOf[target] or Dungeons.isBusy(target) then
		return
	end
	local now = os.clock()
	invites[target] = invites[target] or {}
	if (invites[target][player] or 0) > now then
		return
	end
	invites[target][player] = now + cfg.InviteTime
	Remotes.PartyInvite:FireClient(target, player.UserId, player.DisplayName, party.dungeon)
	notice(player, `Invitación enviada a {target.DisplayName}.`, GREEN)
end

HANDLERS.respond = function(player, leaderId, accept)
	if type(leaderId) ~= "number" then
		return
	end
	local leader = Players:GetPlayerByUserId(leaderId)
	local pending = invites[player]
	local expires = if pending and leader then pending[leader] else nil
	if not expires or not leader then
		return
	end
	pending[leader] = nil
	if accept ~= true then
		notice(leader, `{player.DisplayName} ha rechazado la invitación.`, Color3.fromRGB(230, 230, 240))
		return
	end
	if expires < os.clock() then
		notice(player, "La invitación ha caducado.")
		return
	end
	local party = partyOf[leader]
	if partyOf[player] or not party or party.state ~= "lobby" or party.leader.player ~= leader then
		notice(player, "Ese grupo ya no está abierto.")
		return
	end
	if #party.members >= cfg.MaxSize then
		notice(player, "El grupo está lleno.")
		return
	end
	local ok, reason = canPlay(player, party.dungeon)
	if not ok then
		notice(player, reason or "No puedes entrar.")
		return
	end
	-- Si está lejos de la sala, se le lleva a ella.
	if not nearRoom(player, party.dungeon) then
		local spot = DungeonLobby.returnCFrame(party.dungeon, #party.members + 1, #party.members + 1)
		local character = player.Character
		if spot and character then
			character:PivotTo(spot)
		end
	end
	table.insert(party.members, { player = player, userId = player.UserId, name = player.DisplayName, ready = false })
	partyOf[player] = party
	viewing[player] = party.dungeon
	cancelCountdown(party)
	resetReady(party)
	touch(party)
	notice(leader, `{player.DisplayName} se ha unido al grupo.`, GREEN)
	pushAll()
end

HANDLERS.start = function(player)
	local party = partyOf[player]
	if not party or party.leader.player ~= player or party.state ~= "lobby" then
		return
	end
	local problem = startProblem(party)
	if problem then
		notice(player, problem)
		return
	end
	if cfg.StartCountdown <= 0 then
		launchParty(party)
		return
	end
	party.state = "starting"
	party.countdownEnds = workspace:GetServerTimeNow() + cfg.StartCountdown
	party.token += 1
	local token = party.token
	touch(party)
	pushAll()
	task.delay(cfg.StartCountdown, function()
		if parties[party.id] == party and party.state == "starting" and party.token == token then
			launchParty(party)
		end
	end)
end

local function onRequest(player: Player, action: unknown, a: unknown, b: unknown)
	if type(action) ~= "string" then
		return
	end
	local handler = HANDLERS[action]
	if not handler then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < cfg.ActionCooldown then
		return
	end
	lastAction[player] = now
	handler(player, a, b)
end

function Party.start()
	Remotes.PartyRequest.OnServerEvent:Connect(onRequest)

	Players.PlayerRemoving:Connect(function(player)
		local party = partyOf[player]
		if party then
			local member = memberOf(party, player)
			if member then
				removeMember(party, member)
			end
		end
		viewing[player] = nil
		invites[player] = nil
		for _, pending in invites do
			pending[player] = nil
		end
		lastAction[player] = nil
		pushAll()
	end)

	-- Un grupo que espera demasiado sin empezar se deshace.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, party in table.clone(parties) do
				if party.state == "lobby" and now - party.activeAt > cfg.WaitTimeout then
					disband(party, "El grupo se ha deshecho por esperar demasiado.")
				end
			end
		end
	end)
end

return Party
