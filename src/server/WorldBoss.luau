-- Jefe del mundo: a los Config.WorldBoss.First segundos de abrir el servidor, y luego cada Interval, se abre un portal
-- en el hub que lleva a una arena lejos de la isla, donde cae el Rey Slime. Todo el servidor le pega a la vez como a
-- cualquier enemigo (clic dentro del círculo: server/Combat le pasa los golpes con WorldBoss.hit). Mientras dura:
--   · Bombardeo: lanza globos a círculos rojos (los marca antes; quien siga dentro pierde vida).
--   · Invocación: salen esbirros slime que persiguen y muerden (server/WorldBossMobs).
--   · Escudo: de vez en cuando (Shield.First, luego cada Shield.Every) se protege hasta que se rompen sus cristales.
--   · Carga: prepara un golpe a toda la arena salvo unas zonas seguras; si le llegan Charge.Needed barriles (se rompen
--     a espadazos y salen disparados contra él) queda aturdido y recibe más daño.
-- El rey no tiene vida (pedido por el usuario): no se le mata. Pasados Lifetime segundos se va y reparte los premios por
-- tramos de daño (Rewards.Tiers: por cantidad, no por porcentaje) según el daño de cada uno (a todo lo de la arena; a esbirros, cristales y barriles, sin contar lo que sobra al romperlos),
-- con la tabla final del daño de todos. El estado se publica en atributos de workspace
-- (WorldBossState = idle/open/fight/over, WorldBossFall = hora de la caída, WorldBossEnds = hora a la que se va) y la lista por el remote
-- WorldBoss ("rank"); quien está en la arena lleva el atributo "WorldBoss" = true. Números en Config.WorldBoss.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Lang = require(ReplicatedStorage.Shared.Lang)
local ObjectSpec = require(ReplicatedStorage.Shared.ObjectSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local WorldBossInfo = require(ReplicatedStorage.Shared.WorldBossInfo)
local Gacha = require(script.Parent.Gacha)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)
local WorldBossArena = require(script.Parent.WorldBossArena)
local WorldBossMobs = require(script.Parent.WorldBossMobs)

local WorldBoss = {}

local cfg = Config.WorldBoss
local STUDIO = RunService:IsStudio()
local TICK = 0.1
local RANK_EVERY = 0.5 -- cada cuánto se manda la lista de daño
local PURPLE = Color3.fromRGB(190, 140, 255)
local random = Random.new()

local state = "idle"
local born = workspace:GetServerTimeNow() -- cuándo arrancó este servidor: desde aquí se cuenta el calendario
local fallAt = 0 -- hora del servidor (GetServerTimeNow) a la que cae el rey
local landAt = 0 -- cuándo ya se le puede pegar (os.clock)
local endsAt = 0 -- cuándo se va y reparte los premios (os.clock)
local boss: BasePart? = nil
local bossEntry = nil
local folder: Folder? = nil
local targets = {} -- [pieza] = { kind = "boss" | "minion" | "crystal" | "barrel", hp, maxHp, ... }
local inside = {} -- [Player] = true: los que están en la arena
local entered = {} -- [Player] = os.clock() de cuando entró
local GRACE = 3 -- segundos tras entrar en los que, si aparece lejos (el cliente aún mandaba su sitio de antes), se le recoloca
local contrib = {} -- [UserId] = { name, amount }
local averageDps = 1
local timers = { barrage = 0, summon = 0, charge = 0, shield = 0 }
local shieldUp = false
local charge = nil -- { ends, hits, safe }
local stunnedUntil = 0
local setPortal: (boolean) -> () = function() end
local elapsed, rankElapsed = 0, 0

local function testPhase(): string?
	local phase = Config.Test.WorldBossPhase
	return if STUDIO and type(phase) == "string" and phase ~= "" then phase else nil
end

local function allowed(phase: string): boolean
	local only = testPhase()
	return only == nil or only == phase
end

local function publish()
	workspace:SetAttribute("WorldBossState", state)
	workspace:SetAttribute("WorldBossFall", fallAt)
	workspace:SetAttribute("WorldBossEnds", if state == "fight" then workspace:GetServerTimeNow() + (endsAt - os.clock()) else 0)
end

-- Daño por segundo de un jugador con sus armas equipadas.
local function dpsOf(player: Player): number
	local total = 0
	for _, copy in Stats.loadout(player) do
		total += Stats.weaponDamage(player, copy) / math.max(Stats.weaponCooldown(player, copy), 0.05)
	end
	return total
end

local function aliveRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?, humanoid
	end
	return nil, nil
end

local function insideCount(): number
	local count = 0
	for _ in inside do
		count += 1
	end
	return count
end

local function addContrib(player: Player, amount: number)
	local entry = contrib[player.UserId]
	if not entry then
		entry = { name = player.DisplayName, amount = 0 }
		contrib[player.UserId] = entry
	end
	entry.amount += amount
end

local function ranking()
	local list = {}
	for userId, entry in contrib do
		table.insert(list, { userId = userId, name = entry.name, amount = entry.amount })
	end
	table.sort(list, function(a, b)
		return a.amount > b.amount
	end)
	return list
end

-- Sale de la arena. `send` = llevarlo delante del portal (si no, ya se ha ido solo: muerto, otra parte...).
local function leave(player: Player, send: boolean)
	if not inside[player] then
		return
	end
	inside[player] = nil
	player:SetAttribute("WorldBoss", nil)
	local root = aliveRoot(player)
	if send and root then
		local character = player.Character :: Model
		character:PivotTo(WorldBossArena.portalFront())
		root.AssemblyLinearVelocity = Vector3.zero
		Remotes.Teleported:FireClient(player, "portal")
	end
end

-- Entra en la arena (al tocar el portal abierto).
local function enter(player: Player)
	if inside[player] or (state ~= "open" and state ~= "fight") then
		return
	end
	if (player:GetAttribute("Dungeon") or 0) ~= 0 then
		return
	end
	local root = aliveRoot(player)
	if not root then
		return
	end
	inside[player] = true
	entered[player] = os.clock()
	player:SetAttribute("WorldBoss", true)
	local character = player.Character :: Model
	character:PivotTo(WorldBossArena.spawnCFrame(random:NextInteger(1, 40)))
	root.AssemblyLinearVelocity = Vector3.zero
	Remotes.Teleported:FireClient(player, "worldBoss")
end

local function fighters()
	local list = {}
	for player in inside do
		local root, humanoid = aliveRoot(player)
		if root and humanoid then
			table.insert(list, { player = player, root = root, humanoid = humanoid })
		end
	end
	return list
end

local function addTarget(part: BasePart, entry, hp: number)
	entry.hp = hp
	entry.maxHp = hp
	targets[part] = entry
end

local function clearMinor(kind: string?)
	for part, entry in targets do
		if entry.kind ~= "boss" and (kind == nil or entry.kind == kind) then
			targets[part] = nil
			part:Destroy()
		end
	end
end

local function countKind(kind: string): number
	local count = 0
	for _, entry in targets do
		if entry.kind == kind then
			count += 1
		end
	end
	return count
end

-- Daña a los de la arena que estén en esos círculos (o fuera de todos, con `outside`). `fraction` = parte de su vida máxima.
local function hurtZones(spots: { Vector3 }, radius: number, fraction: number, outside: boolean?)
	for _, fighter in fighters() do
		local position = fighter.root.Position
		local hit = false
		for _, spot in spots do
			if Vector2.new(position.X - spot.X, position.Z - spot.Z).Magnitude <= radius and position.Y < spot.Y + 12 then
				hit = true
				break
			end
		end
		if hit ~= (outside == true) then
			fighter.humanoid:TakeDamage(fighter.humanoid.MaxHealth * fraction)
			Remotes.DungeonEvent:FireClient(fighter.player, "hurt", { amount = fighter.humanoid.MaxHealth * fraction })
		end
	end
end

local function toInside(kind: string, data)
	for player in inside do
		Remotes.WorldBoss:FireClient(player, kind, data)
	end
end

-- Fases -------------------------------------------------------------------------------------

local function barrage(list)
	local def = cfg.Barrage
	local spots = {}
	local count = WorldBossInfo.count(def, #list)
	-- La mitad, encima de jugadores (para que haya que moverse); el resto, al azar.
	for index = 1, count do
		if index <= math.ceil(count / 2) and #list > 0 then
			local position = list[random:NextInteger(1, #list)].root.Position
			table.insert(spots, Vector3.new(position.X, cfg.Origin.Y, position.Z) + Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3)))
		else
			table.insert(spots, WorldBossMobs.spot(0.25, 0.95))
		end
	end
	local serverNow = workspace:GetServerTimeNow()
	if boss then
		boss:SetAttribute("Slam", serverNow)
	end
	toInside("barrage", { spots = spots, radius = def.Radius, at = serverNow + def.Warn, from = cfg.Origin + Vector3.new(0, cfg.Size.Y, 0) })
	task.delay(def.Warn, function()
		if state == "fight" then
			hurtZones(spots, def.Radius, def.Damage)
		end
	end)
end

local function summon(list)
	local def = cfg.Summon
	local alive = countKind("minion")
	local count = math.min(WorldBossInfo.count(def, #list), def.Max - alive)
	for _ = 1, count do
		local hp = WorldBossInfo.minorHp(averageDps, def.Seconds)
		local part, entry = WorldBossMobs.minion(folder :: Folder, hp)
		addTarget(part, entry, hp)
	end
	if boss and count > 0 then
		boss:SetAttribute("Slam", workspace:GetServerTimeNow())
	end
end

local function raiseShield(list)
	local def = cfg.Shield
	shieldUp = true
	if boss then
		boss:SetAttribute("Shield", true)
	end
	local count = WorldBossInfo.count(def, #list)
	for index = 1, count do
		local hp = WorldBossInfo.minorHp(averageDps, def.Seconds)
		local part, entry = WorldBossMobs.crystal(folder :: Folder, index, count, hp)
		addTarget(part, entry, hp)
	end
	toInside("shield", true)
end

local function dropShield()
	shieldUp = false
	timers.shield = os.clock() + (if testPhase() == "shield" then 5 else cfg.Shield.Every)
	if boss then
		boss:SetAttribute("Shield", false)
	end
	toInside("shield", false)
end

local function endCharge()
	charge = nil
	clearMinor("barrel")
	timers.charge = os.clock() + cfg.Charge.Every
	if boss then
		boss:SetAttribute("ChargeFrom", nil)
		boss:SetAttribute("ChargeTo", nil)
	end
end

local function startCharge()
	local def = cfg.Charge
	local safe = {}
	for _ = 1, def.SafeZones do
		table.insert(safe, WorldBossMobs.spot(0.45, 0.85))
	end
	local serverNow = workspace:GetServerTimeNow()
	charge = { ends = os.clock() + def.Time, hits = 0, safe = safe }
	if boss then
		boss:SetAttribute("ChargeFrom", serverNow)
		boss:SetAttribute("ChargeTo", serverNow + def.Time)
	end
	for _ = 1, def.Barrels do
		local hp = WorldBossInfo.minorHp(averageDps, def.BarrelSeconds)
		local part, entry = WorldBossMobs.barrel(folder :: Folder, hp)
		addTarget(part, entry, hp)
	end
	toInside("charge", { safe = safe, radius = def.SafeRadius, at = serverNow + def.Time, needed = def.Needed })
end

local function stun()
	local def = cfg.Charge
	stunnedUntil = os.clock() + def.StunTime
	if boss then
		boss:SetAttribute("Stunned", workspace:GetServerTimeNow() + def.StunTime)
	end
	endCharge()
	toInside("stun", { ends = workspace:GetServerTimeNow() + def.StunTime })
	-- Aturdido no ataca: lo que tocaba se aplaza.
	timers.barrage = math.max(timers.barrage, stunnedUntil + 1)
	timers.summon = math.max(timers.summon, stunnedUntil + 2)
end

local function megaSlam()
	local def = cfg.Charge
	local safe = charge and charge.safe or {}
	if boss then
		boss:SetAttribute("Slam", workspace:GetServerTimeNow())
	end
	hurtZones(safe, def.SafeRadius, def.MegaDamage, true)
	toInside("mega", true)
	endCharge()
end

-- Final ------------------------------------------------------------------------------------

local function reward(list)
	for rank, row in list do
		local player = Players:GetPlayerByUserId(row.userId)
		if not player then
			continue
		end
		local prize = WorldBossInfo.rewards(row.amount, rank)
		if prize then
			-- Tiradas: la suerte media de los objetos que le salen ahora, por Rewards.Luck. `usual` es esa misma suerte,
			-- para que la cinemática solo salga cuando la tirada ha tenido suerte de verdad (server/Gacha).
			local luck = Stats.luck(player) * Stats.spawnLuck(player)
			local boost = ObjectSpec.meanLuck(luck, Stats.objectLuck(player)) * cfg.Rewards.Luck
			local info = { name = Lang.t(player, cfg.Name), usual = boost }
			if inside[player] and boss then
				info.origin = boss.Position
				info.box = boss.Size
			end
			Gacha.give(player, boost, "worldBoss", prize.rolls, info)
			PlayerData.edit(player, function(data)
				data.items.traitCrystal = (data.items.traitCrystal or 0) + prize.traitCrystal
				data.items.gradeCrystal = (data.items.gradeCrystal or 0) + prize.gradeCrystal
				if prize.tickets > 0 then
					data.items.missionToken = (data.items.missionToken or 0) + prize.tickets
				end
				-- Pociones: las de ese tier, de cada familia.
				for _, family in Config.Potions.Order do
					if prize.potions > 0 then
						local key = `potion_{family}_{prize.potionTier}`
						if Config.Items[key] then
							data.items[key] = (data.items[key] or 0) + prize.potions
						end
					end
				end
			end)
		end
		Remotes.WorldBoss:FireClient(player, "result", { list = list, rank = rank, rewards = prize })
	end
end

-- Se acaba el tiempo: premios según el daño de cada uno, tabla final y el rey se va de un salto.
local function finish()
	if state ~= "fight" then
		return
	end
	state = "over"
	setPortal(false)
	clearMinor()
	charge = nil
	local list = ranking()
	reward(list)
	Tell.all(PURPLE, function(reader)
		return Lang.t(reader, "The {boss} has left: rewards for everyone who fought!", { boss = Lang.t(reader, cfg.Name) })
	end)
	local body = boss
	boss, bossEntry = nil, nil
	if body then
		targets[body] = nil
		-- Se va de un salto, hacia arriba y lejos (fuera de la vista no se ve su muerte de slime).
		CollectionService:RemoveTag(body, "WorldBossTarget")
		local tween = TweenService:Create(body, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = body.CFrame + Vector3.new(0, 500, 0) })
		tween:Play()
		tween.Completed:Connect(function()
			body:Destroy()
		end)
	end
	publish()
	task.delay(cfg.ReturnDelay, function()
		for player in table.clone(inside) do
			leave(player, true)
		end
		table.clear(contrib)
		state = "idle"
		fallAt = WorldBossInfo.nextFall(workspace:GetServerTimeNow() + cfg.Warning, born)
		publish()
	end)
end

-- Rotura de algo de la arena.
local function broken(part: BasePart, entry)
	targets[part] = nil
	if entry.kind == "barrel" then
		local to = cfg.Origin + Vector3.new(0, cfg.Size.Y * 0.6, 0)
		WorldBossMobs.launch(part, to, function()
			if charge and state == "fight" then
				charge.hits += 1
				if charge.hits >= cfg.Charge.Needed then
					stun()
				end
			end
		end)
	else
		if entry.kind == "crystal" then
			Remotes.WorldBoss:FireAllClients("boom", part.Position)
		end
		part:Destroy()
		if entry.kind == "crystal" and shieldUp and countKind("crystal") == 0 then
			dropShield()
		end
	end
end

-- Arranque y bucle ----------------------------------------------------------------------------

local function open()
	state = "open"
	setPortal(true)
	table.clear(contrib)
	publish()
	Tell.all(PURPLE, function(reader)
		return Lang.t(reader, "A portal has opened in the hub: the {boss} arrives in {time}!", { boss = Lang.t(reader, cfg.Name), time = WorldBossInfo.clock(fallAt - workspace:GetServerTimeNow()) })
	end)
end

local function startFight()
	-- Cae aunque no haya nadie dentro: el portal sigue abierto toda la pelea y se puede entrar en cualquier momento
	-- (antes, sin nadie dentro al caer, se cerraba y con el aviso corto del admin no daba tiempo a llegar).
	-- Esbirros, cristales y barriles aguantan lo que les quita en unos segundos un jugador medio de los que hay en la
	-- arena; sin nadie, de los del servidor que no están en una mazmorra.
	local players = {}
	for _, fighter in fighters() do
		table.insert(players, fighter.player)
	end
	if #players == 0 then
		for _, player in Players:GetPlayers() do
			if (player:GetAttribute("Dungeon") or 0) == 0 then
				table.insert(players, player)
			end
		end
	end
	local sum = 0
	for _, player in players do
		sum += dpsOf(player)
	end
	averageDps = math.max(sum / math.max(#players, 1), 1)

	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "WorldBoss"
		folder.Parent = workspace
	end
	local size = cfg.Size
	local body = Instance.new("Part")
	body.Name = cfg.Name
	body.Size = size
	body.Anchored = true
	body.Transparency = 1 -- se ve el slime que le pone cada cliente (client/Slimes)
	body.Color = cfg.Color
	body.CFrame = CFrame.new(cfg.Origin + Vector3.new(0, size.Y / 2, 0))
	body.CollisionGroup = "Enemies"
	body:SetAttribute("Kind", "king")
	body:SetAttribute("Look", cfg.Look)
	body:SetAttribute("Fall", workspace:GetServerTimeNow() + cfg.FallTime)
	CollectionService:AddTag(body, "Enemy")
	CollectionService:AddTag(body, "WorldBossTarget")
	body.Parent = folder
	boss = body
	bossEntry = { kind = "boss" }
	addTarget(body, bossEntry, math.huge) -- sin vida: no se le mata

	local now = os.clock()
	state = "fight"
	landAt = now + cfg.FallTime
	endsAt = now + cfg.Lifetime
	shieldUp, charge, stunnedUntil = false, nil, 0
	timers.barrage = landAt + 3
	timers.summon = landAt + (if testPhase() == "summon" then 1 else 12)
	timers.charge = landAt + (if testPhase() == "charge" then 2 else cfg.Charge.Every * 0.6)
	timers.shield = landAt + (if testPhase() == "shield" then 2 else cfg.Shield.First)
	toInside("fall", { at = workspace:GetServerTimeNow() + cfg.FallTime })
	publish()
	-- Al caer, aparta a quien esté debajo.
	task.delay(cfg.FallTime, function()
		for _, fighter in fighters() do
			local offset = fighter.root.Position - cfg.Origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < size.X * 0.7 then
				local out = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
				local at = cfg.Origin + out * (size.X * 0.7 + 4) + Vector3.new(0, 4, 0)
				local character = fighter.player.Character :: Model
				character:PivotTo(CFrame.lookAt(at, Vector3.new(cfg.Origin.X, at.Y, cfg.Origin.Z)))
			end
		end
	end)
end

-- Quién sigue: el que muere o se va lejos sale de la arena; el que se cae vuelve al borde.
local function checkInside(now: number)
	for player in table.clone(inside) do
		local root = aliveRoot(player)
		if not root then
			leave(player, false)
		else
			local offset = root.Position - cfg.Origin
			local far = Vector3.new(offset.X, 0, offset.Z).Magnitude > cfg.ArenaRadius + 60
			if far and now - (entered[player] or 0) > GRACE then
				leave(player, false)
			elseif far or offset.Y < -30 then
				local character = player.Character :: Model
				character:PivotTo(WorldBossArena.spawnCFrame(random:NextInteger(1, 40)))
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

local function stepFight(now: number)
	checkInside(now)
	if now >= endsAt then
		finish()
		return
	end
	if now < landAt then
		return
	end
	local list = fighters()
	WorldBossMobs.step(targets, list)

	-- Mira al jugador más cercano.
	if boss and #list > 0 then
		local nearest, best = nil, math.huge
		for _, fighter in list do
			local distance = (fighter.root.Position - boss.Position).Magnitude
			if distance < best then
				nearest, best = fighter.root.Position, distance
			end
		end
		local look = Vector3.new(nearest.X, boss.Position.Y, nearest.Z)
		if (look - boss.Position).Magnitude > 1 then
			boss.CFrame = CFrame.lookAt(boss.Position, look)
		end
	end

	if now < stunnedUntil then
		return
	end
	if boss and boss:GetAttribute("Stunned") then
		boss:SetAttribute("Stunned", nil)
	end

	-- Escudo: cada cierto tiempo, si no está cargando.
	if not shieldUp and not charge and allowed("shield") and now >= timers.shield then
		raiseShield(list)
	end
	if charge then
		if now >= charge.ends then
			megaSlam()
		end
	elseif not shieldUp and allowed("charge") and now >= timers.charge then
		startCharge()
	end
	if allowed("barrage") and now >= timers.barrage then
		timers.barrage = now + cfg.Barrage.Every
		barrage(list)
	end
	if allowed("summon") and now >= timers.summon then
		timers.summon = now + cfg.Summon.Every
		summon(list)
	end
end

local function step(dt: number)
	elapsed += dt
	if elapsed < TICK then
		return
	end
	local delta = elapsed
	elapsed = 0
	local serverNow = workspace:GetServerTimeNow()
	if state == "idle" then
		if serverNow >= fallAt - cfg.Warning then
			open()
		end
	elseif state == "open" then
		checkInside(os.clock())
		if serverNow >= fallAt then
			startFight()
		end
	elseif state == "fight" then
		stepFight(os.clock())
		rankElapsed += delta
		if rankElapsed >= RANK_EVERY and state == "fight" then
			rankElapsed = 0
			local list = ranking()
			local top = {}
			for index = 1, math.min(#list, 10) do
				top[index] = list[index]
			end
			local total = 0
			for _, row in list do
				total += row.amount
			end
			for _, player in Players:GetPlayers() do
				local mine = contrib[player.UserId]
				local rank = nil
				for index, row in list do
					if row.userId == player.UserId then
						rank = index
						break
					end
				end
				Remotes.WorldBoss:FireClient(player, "rank", { list = top, total = total, mine = mine and mine.amount or 0, rank = rank, count = #list })
			end
		end
	end
end

-- API para server/Combat ------------------------------------------------------------------------

-- Si esa pieza es algo de la arena a lo que ese jugador puede pegar ahora (el rey con escudo, no).
function WorldBoss.isTarget(player: Player, part: Instance): boolean
	if state ~= "fight" or not inside[player] or os.clock() < landAt then
		return false
	end
	local entry = targets[part :: BasePart]
	if not entry or entry.hp <= 0 then
		return false
	end
	return not (entry.kind == "boss" and shieldUp)
end

-- Golpe de un arma. Devuelve true si lo rompe o lo mata (al rey no: no tiene vida).
function WorldBoss.hit(player: Player, part: BasePart, damage: number, slot: number?): boolean
	if not WorldBoss.isTarget(player, part) then
		return false
	end
	local entry = targets[part]
	if entry.kind == "boss" and os.clock() < stunnedUntil then
		damage *= cfg.Charge.StunMult
	end
	Remotes.Hit:FireAllClients(player, part, part.Position, damage, slot)
	if entry.kind == "boss" then
		-- Sin vida: cuenta todo. "Hits" solo le sirve al cliente para que tiemble y se ponga blanco (client/Slimes).
		addContrib(player, damage)
		part:SetAttribute("Hits", (part:GetAttribute("Hits") or 0) + 1)
		return false
	end
	local dealt = math.min(damage, entry.hp)
	entry.hp -= dealt
	addContrib(player, dealt)
	part:SetAttribute("HP", entry.hp)
	if entry.hp <= 0 then
		broken(part, entry)
		return true
	end
	return false
end

-- Golpe en zona (armas que salpican o atraviesan): a lo de la arena a lo que llega desde `origin`, menos `already`.
function WorldBoss.strike(player: Player, origin: CFrame, range: number, arc: number, damage: number, already: { [BasePart]: boolean }?, slot: number?)
	local hit = {}
	for part in targets do
		if not (already and already[part]) and WorldBoss.isTarget(player, part) and Hitbox.reaches(part, origin, range, arc) then
			table.insert(hit, part)
		end
	end
	for _, part in hit do
		WorldBoss.hit(player, part, damage, slot)
	end
end

-- Lo de la arena más cercano a `from` dentro del círculo del jugador (para encadenar al romper algo).
function WorldBoss.nearest(player: Player, from: Vector3, center: Vector3, radius: number): BasePart?
	local best, bestDistance = nil, math.huge
	for part in targets do
		if WorldBoss.isTarget(player, part) then
			local distance = (part.Position - from).Magnitude
			if distance < bestDistance and Hitbox.reaches(part, CFrame.new(center), radius, -1) then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

-- Si el jugador está en la arena.
function WorldBoss.isInside(player: Player): boolean
	return inside[player] == true
end

-- Para el menú de admin: abre el portal ya y el rey cae en `warning` segundos. false si ya hay uno en marcha.
function WorldBoss.summon(warning: number?): boolean
	if state ~= "idle" then
		return false
	end
	fallAt = workspace:GetServerTimeNow() + (warning or cfg.AdminWarning)
	open()
	return true
end

function WorldBoss.start()
	WorldBossArena.build()
	local _, trigger, setOpen = WorldBossArena.buildPortal(workspace:WaitForChild("Map"))
	setPortal = setOpen
	WorldBossArena.buildBoard(workspace:WaitForChild("Map"))
	trigger.Touched:Connect(function(other)
		local player = Players:GetPlayerFromCharacter(other.Parent)
		if player then
			enter(player)
		end
	end)

	local serverNow = workspace:GetServerTimeNow()
	local test = Config.Test.WorldBoss
	if STUDIO and type(test) == "number" and test > 0 then
		fallAt = serverNow + test
	else
		fallAt = WorldBossInfo.nextFall(serverNow, born)
	end
	publish()

	Remotes.WorldBossRequest.OnServerEvent:Connect(function(player, action)
		if action == "leave" then
			leave(player, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		inside[player] = nil
		entered[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return WorldBoss
