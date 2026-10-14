-- Mazmorras: una arena aparte para cada partida, lejos de la isla, que se juega solo o en grupo (1 a
-- Config.Party.MaxSize jugadores). Quien las lanza (server/Party, con el grupo ya validado, vía Dungeons.launch) pasa la
-- lista de jugadores y la zona; aquí se construye la arena con el tema de la zona,
-- salen las oleadas, se mueve a los enemigos (cada uno persigue al jugador vivo más cercano), se aplica el daño en los
-- dos sentidos y se reparten los premios (Loot: cada jugador vivo tira por cada enemigo y por terminar). Los golpes
-- llegan por Combat (Dungeons.strike). La vida y la cantidad de enemigos suben con el tamaño del grupo
-- (Config.Party.Scaling).
-- Estado para el cliente en atributos del Player: Dungeon (zona, 0 = fuera), DungeonRun (id de la partida: los de
-- su grupo llevan el mismo), DungeonWave, DungeonWaves, DungeonLeft (enemigos vivos), DungeonEnds (hora del servidor a
-- la que se acaba el tiempo) y DungeonLoop (si el jugador tiene puesto "repetir": si es el líder, al superarla empieza
-- otra igual sin volver al lobby).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Destructibles = require(script.Parent.Destructibles)
local DungeonLobby = require(script.Parent.DungeonLobby)
local DungeonThemes = require(script.Parent.DungeonThemes)
local Loot = require(script.Parent.Loot)
local DropMenu = require(script.Parent.DropMenu)
local Missions = require(script.Parent.Missions)

local Dungeons = {}

local cfg = Config.Dungeon
local random = Random.new()

-- run = { id, index, level, theme, waves, slot, origin, model, members = { [Player] = member }, order = { member },
--   leader = member?, size, playerCount, hpMult, countMult, enemies = { [body] = enemy }, left, wave, state, ends,
--   nextWave, context, ended }. member = { player = Player?, ghost = true?, name, summary, slot }. Los "fantasmas" (solo en Studio, para
--   probar el escalado y las bajas con un único jugador) cuentan en el tamaño del grupo pero no pelean ni cobran.
local runs = {} -- [run] = true: partidas en curso
local runOf = {} -- [Player] = su partida
local looping = {} -- [Player] = true si quiere repetir la mazmorra en bucle
local usedSlots = {} -- [número] = true: huecos de arena ocupados
local nextRunId = 0

-- Arena ----------------------------------------------------------------------------------

-- La arena de la zona: suelo, muro, techo y adornos según su tema de Config.DungeonThemes (server/DungeonThemes).
local function buildArena(origin: Vector3, level, theme): Model
	local model = Instance.new("Model")
	model.Name = "Mazmorra"
	DungeonThemes.build(model, origin, cfg.ArenaRadius, level, theme)
	model.Parent = workspace
	return model
end

-- Enemigos -------------------------------------------------------------------------------

-- Cómo se ve cada enemigo (cuerpo de slime, cara, adornos de su "look" y animación) lo pone el cliente (client/Slimes) con
-- los atributos que deja spawnEnemy: aquí solo está la caja física, invisible.

local function spawnEnemy(run, key: string)
	local def = Config.Enemies[key]
	local level = run.level
	-- Cómo se ve en esta zona (nombre, color, adornos y escala del tema); sus números siguen siendo los de Config.Enemies.
	local skin = DungeonThemes.skin(run.theme, key)
	local size: Vector3 = def.size * ((skin and skin.scale) or 1)
	local turn = random:NextNumber(0, math.pi * 2)
	-- Sin pasar de 0,85 del radio con todo su cuerpo: los grandes podían nacer metidos en la barrera invisible.
	local distance = math.min(cfg.ArenaRadius * random:NextNumber(0.55, 0.85), cfg.ArenaRadius * 0.85 - size.X / 2)
	local position = run.origin + Vector3.new(math.cos(turn) * distance, size.Y / 2 + 1, math.sin(turn) * distance)

	local body = Instance.new("Part")
	body.Name = (skin and skin.name) or def.name
	body.Size = size
	body.Color = (skin and skin.color) or def.color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Transparency = 1 -- se ve el slime que le pone cada cliente (client/Slimes)
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0) -- sin rozamiento: lo mueve LinearVelocity
	body.CollisionGroup = "Enemies" -- no choca con el decorado de la arena (server/CollisionGroups)
	body.CFrame = CFrame.lookAt(position, Vector3.new(run.origin.X, position.Y, run.origin.Z))
	local hp = def.hp * level.hp * run.hpMult
	body:SetAttribute("HP", hp)
	body:SetAttribute("MaxHP", hp)
	-- Para el slime del cliente: tipo (grunt, brute, boss), adornos del look separados por comas y hora del servidor a
	-- la que puede volver a atacar (NextAttack; con cada ataque, también AttackAt y Victim, el UserId de quien recibe).
	local look = (skin and skin.look) or def.look
	body:SetAttribute("Kind", key)
	body:SetAttribute("Look", if type(look) == "table" then table.concat(look, ",") else look or "")
	body:SetAttribute("NextAttack", workspace:GetServerTimeNow() + def.attackTime * 0.5)
	CollectionService:AddTag(body, "Enemy")

	local attachment = Instance.new("Attachment")
	attachment.Parent = body
	local mass = size.X * size.Y * size.Z
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.zero
	velocity.MaxForce = mass * 140 -- limitada: tarda un momento en arrancar y en frenar
	velocity.Parent = body
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.CFrame = body.CFrame.Rotation
	align.MaxTorque = math.huge
	align.Responsiveness = 30
	align.Parent = body

	body.Parent = run.model
	body:SetNetworkOwner(nil)
	run.enemies[body] = { def = def, size = size, hp = hp, velocity = velocity, align = align, nextAttack = os.clock() + def.attackTime * 0.5, halt = 0 }
	run.left += 1
end

-- Partidas -------------------------------------------------------------------------------

local function takeSlot(): number?
	for slot = 1, cfg.MaxRuns do
		if not usedSlots[slot] then
			usedSlots[slot] = true
			return slot
		end
	end
	return nil
end

local function hasPlayers(run): boolean
	for _, member in run.order do
		if member.player then
			return true
		end
	end
	return false
end

-- Dónde se deja al jugador al acabar la partida: en la sala de esa zona, en el lobby subterráneo (o, si el lobby no se
-- ha podido construir, junto a la boca del pozo, en el hub).
local HUB_SPOT = CFrame.new(0, Config.Plot.FloorHeight + 3, 38)
local function returnPoint(run, member): CFrame
	return DungeonLobby.returnCFrame(run.index, member.slot or 1, run.playerCount or 1) or HUB_SPOT
end

local function clearAttributes(player: Player)
	player:SetAttribute("Dungeon", 0)
	player:SetAttribute("DungeonRun", 0)
end

local function result(run, member, won: boolean, reason: string)
	local player = member.player
	if player and player.Parent then
		-- El botín retenido se ofrece en el menú (server/DropMenu); con Repetir o Auto entra solo (`granted`).
		local menu, granted = DropMenu.offer(player, member.summary)
		Remotes.DungeonEvent:FireClient(player, "result", {
			won = won,
			reason = reason,
			level = run.index,
			drops = if menu then menu.drops else nil,
			armorFree = if menu then menu.armorFree else nil,
			expires = if menu then menu.expires else nil,
			granted = granted,
		})
	end
end

-- Para la lista de la partida: los jugadores que siguen dentro.
local function publish(run)
	for _, member in run.order do
		local player = member.player
		if player and player.Parent then
			player:SetAttribute("DungeonWave", run.wave)
			player:SetAttribute("DungeonLeft", run.left)
		end
	end
end

local endRun

-- Saca a un miembro de la partida (muerte, salida, desconexión o fin). Si ya no queda ningún jugador, acaba la partida.
local function detach(run, member, bringBack: boolean)
	local index = table.find(run.order, member)
	if not index then
		return
	end
	table.remove(run.order, index)
	local player = member.player
	if player then
		run.members[player] = nil
		if runOf[player] == run then
			runOf[player] = nil
		end
		if player.Parent then
			clearAttributes(player)
			if bringBack then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					character:PivotTo(returnPoint(run, member))
					Remotes.Teleported:FireClient(player, "dungeon")
				end
			end
		end
	end
	if run.leader == member then
		run.leader = nil
		for _, other in run.order do
			if other.player then
				run.leader = other
				break
			end
		end
	end
	if not run.ended and not hasPlayers(run) then
		endRun(run, false)
	end
end

-- Termina la partida: saca a todos (devolviéndolos al lobby si toca) y borra la arena.
function endRun(run, bringBack: boolean)
	if run.ended then
		return
	end
	run.ended = true
	runs[run] = nil
	for _, member in table.clone(run.order) do
		detach(run, member, bringBack)
	end
	usedSlots[run.slot] = nil
	run.model:Destroy()
	local onEnd = run.onEnd
	run.onEnd = nil
	if onEnd then
		task.spawn(onEnd)
	end
end

local function startWave(run)
	run.wave += 1
	run.state = "fighting"
	for _, entry in run.waves[run.wave] do
		local key, count = entry[1], entry[2]
		local def = Config.Enemies[key]
		if def then
			local total = if def.scaleCount == false then count else math.ceil(count * run.level.count * run.countMult)
			for _ = 1, total do
				spawnEnemy(run, key)
			end
		end
	end
	publish(run)
end

local launch

-- Tras ganar: otra igual con los que siguen vivos (la arena vieja se borra cuando ya está lista la nueva).
local function restart(old, survivors: { Player }, ghosts: number)
	runs[old] = nil
	old.ended = true
	-- Los que siguen vivos pasan a la partida nueva (sus atributos no se tocan); lo que quede en la vieja son fantasmas.
	for _, player in survivors do
		local member = old.members[player]
		old.members[player] = nil
		runOf[player] = nil
		local index = table.find(old.order, member)
		if index then
			table.remove(old.order, index)
		end
	end
	local onEnd = old.onEnd
	old.onEnd = nil
	local new = launch(survivors, old.index, { ghosts = ghosts, onEnd = onEnd })
	usedSlots[old.slot] = nil
	old.model:Destroy()
	if new then
		new.owner = old.owner
	else
		if onEnd then
			task.spawn(onEnd)
		end
		for number, player in survivors do
			if player.Parent then
				clearAttributes(player)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					character:PivotTo(returnPoint(old, { slot = number }))
					Remotes.Teleported:FireClient(player, "dungeon")
				end
			end
		end
	end
end

local function win(run)
	run.state = "won"
	for _, member in run.order do
		if member.player then
			Loot.roll(member.player, cfg.ClearDrops, run.context, member.summary)
			Missions.add(member.player, "dungeons")
			result(run, member, true, "clear")
		end
	end
	task.delay(cfg.ExitDelay, function()
		if run.ended or not runs[run] then
			return
		end
		local survivors = {}
		local ghosts = 0
		for _, member in run.order do
			local player = member.player
			if not player then
				ghosts += 1
				continue
			end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if player.Parent and humanoid and humanoid.Health > 0 then
				table.insert(survivors, player)
			end
		end
		if #survivors > 0 and looping[run.owner] then
			restart(run, survivors, ghosts)
		else
			endRun(run, true)
		end
	end)
end

local function kill(run, body: BasePart, killer: Player)
	local enemy = run.enemies[body]
	run.enemies[body] = nil
	run.left -= 1
	-- Mismo aviso que al romper un objeto: escombros y sonido en el cliente de cada jugador.
	for _, member in run.order do
		local player = member.player
		if player and player.Parent then
			Remotes.Broken:FireClient(player, killer, body.CFrame, body.Size, body.Color, body.Material, 0, 0)
		end
	end
	body:Destroy()
	for _, member in table.clone(run.order) do
		if member.player and member.player.Parent then
			Loot.roll(member.player, enemy.def.drops, run.context, member.summary)
			Missions.add(member.player, "enemies") -- cuenta para todo el grupo, lo mate quien lo mate
		end
	end
	publish(run)
end

-- Si esa pieza es un enemigo vivo de la partida en la que pelea el jugador (lo único de aquí que puede atacar).
function Dungeons.isEnemy(player: Player, body: Instance): boolean
	local run = runOf[player]
	return run ~= nil and run.state == "fighting" and run.enemies[body] ~= nil
end

-- Golpe de un arma del jugador a un enemigo de su partida (lo llama Combat con el daño ya calculado en el servidor).
-- `slot` = hueco del arma, para que el cliente sepa cuál da el tajo. Devuelve true si lo mata.
function Dungeons.hit(player: Player, body: BasePart, damage: number, slot: number?): boolean
	local run = runOf[player]
	local enemy = run and run.state == "fighting" and run.enemies[body]
	if not enemy then
		return false
	end
	for _, member in run.order do
		if member.player and member.player.Parent then
			Remotes.Hit:FireClient(member.player, player, body, body.Position, damage, slot)
		end
	end
	enemy.hp -= damage
	if enemy.hp <= 0 then
		kill(run, body, player)
		return true
	end
	body:SetAttribute("HP", enemy.hp)
	-- El golpe lo deja parado un momento. No lo empuja (pedido por el usuario): con varias armas pegándole desde lejos
	-- lo sacaban del círculo y se quedaban sin objetivo.
	enemy.halt = os.clock() + cfg.HitStop
	enemy.velocity.PlaneVelocity = Vector2.zero
	return false
end

-- Golpe en zona (las armas que salpican o atraviesan): pega a los enemigos de su partida a los que llega desde `origin`
-- (ver Hitbox.reaches), menos a los de `already`.
function Dungeons.strike(player: Player, origin: CFrame, range: number, arc: number, damage: number, already: { [BasePart]: boolean }?, slot: number?)
	local run = runOf[player]
	if not run or run.state ~= "fighting" then
		return
	end
	local hit = {}
	for body in run.enemies do
		if not (already and already[body]) and Destructibles.reaches(body, origin, range, arc) then
			table.insert(hit, body)
		end
	end
	for _, body in hit do
		Dungeons.hit(player, body, damage, slot)
	end
end

-- Enemigo vivo de su partida más cercano a `from`, de entre los que están a `radius` de `center` (el círculo del
-- jugador); nil si no hay ninguno. Para encadenar: al morir el objetivo, las armas saltan a este.
function Dungeons.nearest(player: Player, from: Vector3, center: Vector3, radius: number): BasePart?
	local run = runOf[player]
	if not run or run.state ~= "fighting" then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for body in run.enemies do
		local distance = (body.Position - from).Magnitude
		if distance < bestDistance and Destructibles.reaches(body, CFrame.new(center), radius, -1) then
			best, bestDistance = body, distance
		end
	end
	return best
end

-- Hacia dónde anda un enemigo que va a por `direction`: se aparta de los enemigos que tiene pegados y rodea al que le
-- tapa el paso. Antes iban en línea recta y chocan entre ellos: el de detrás se quedaba quieto para siempre empujando
-- al de delante, sin llegar a atacar.
local function steer(run, body: BasePart, enemy, direction: Vector3): Vector3
	local push = Vector3.zero
	local side = 0
	for other, mate in run.enemies do
		if other == body then
			continue
		end
		local away = body.Position - other.Position
		away = Vector3.new(away.X, 0, away.Z)
		local distance = away.Magnitude
		local reach = (enemy.size.X + mate.size.X) / 2 + 0.5
		if distance < reach and distance > 0.01 then
			local unit = away / distance
			push += unit * (reach - distance) / reach
			-- Lo tiene delante: lo rodea por el lado por el que ya está desviado (siempre el mismo para ese par).
			if unit:Dot(direction) < -0.5 then
				local cross = direction:Cross(unit).Y
				side += if cross >= 0 then 1 else -1
			end
		end
	end
	if push.Magnitude < 0.01 and side == 0 then
		return direction
	end
	-- Apartarse no lo hace retroceder: lo que empuja hacia atrás se quita, y al que tiene delante lo rodea.
	push -= direction * math.min(push:Dot(direction), 0)
	local around = Vector3.new(-direction.Z, 0, direction.X) * math.sign(side)
	local heading = direction + push * 1.5 + around * 1.2
	return if heading.Magnitude > 0.01 then heading.Unit else direction
end

local function step()
	local now = os.clock()
	for run in runs do
		if run.state == "loading" then
			continue
		end
		local won = run.state == "won"

		-- Quién sigue en pie: el que muere o se va de la arena sale de la partida (con su cartel, salvo tras ganar).
		local targets = {}
		for _, member in table.clone(run.order) do
			local player = member.player
			if not player then
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then
				if not won then
					result(run, member, false, "dead")
				end
				detach(run, member, false)
			elseif (root.Position - run.origin).Magnitude > cfg.ArenaRadius + 80 then
				-- Se ha ido de la arena (barra de transporte, caída...).
				if not won then
					result(run, member, false, "left")
				end
				detach(run, member, false)
			else
				table.insert(targets, { member = member, player = player, root = root, humanoid = humanoid })
			end
		end
		if run.ended or won then
			continue
		end

		if now >= run.ends then
			for _, target in targets do
				result(run, target.member, false, "time")
			end
			endRun(run, true)
			continue
		end
		if run.state == "waiting" then
			if now >= run.nextWave then
				startWave(run)
			end
			continue
		end

		local power = run.level.power
		for body, enemy in run.enemies do
			local def = enemy.def
			-- Si se cae de la plataforma vuelve a entrar por el borde.
			if body.Position.Y < run.origin.Y - 20 then
				body.AssemblyLinearVelocity = Vector3.zero
				body.CFrame = CFrame.new(run.origin + Vector3.new(0, enemy.size.Y / 2 + 2, cfg.ArenaRadius * 0.6))
			end
			-- Persigue al jugador vivo más cercano.
			local target, closest = nil, math.huge
			for _, candidate in targets do
				local offset = candidate.root.Position - body.Position
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if distance < closest then
					target, closest = candidate, distance
				end
			end
			if not target then
				break
			end
			local offset = target.root.Position - body.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local gap = flat.Magnitude - enemy.size.X / 2 - 1
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
			enemy.align.CFrame = CFrame.lookAt(Vector3.zero, direction)
			local speed = if gap > def.attackRange * 0.6 and now >= enemy.halt then def.speed else 0
			local heading = if speed > 0 then steer(run, body, enemy, direction) else direction
			enemy.velocity.PlaneVelocity = Vector2.new(heading.X, heading.Z) * speed
			if gap <= def.attackRange and math.abs(offset.Y) < enemy.size.Y + 6 and now >= enemy.nextAttack then
				enemy.nextAttack = now + def.attackTime
				local amount = def.damage * power
				target.humanoid:TakeDamage(amount)
				-- Solo para la animación del ataque en los clientes: no cambia cuándo pega ni cuánto.
				local serverNow = workspace:GetServerTimeNow()
				body:SetAttribute("Victim", target.player.UserId)
				body:SetAttribute("AttackAt", serverNow)
				body:SetAttribute("NextAttack", serverNow + def.attackTime)
				Remotes.DungeonEvent:FireClient(target.player, "hurt", { amount = amount, from = body })
			end
		end

		if run.left <= 0 then
			if run.wave >= #run.waves then
				win(run)
			else
				run.state = "waiting"
				run.nextWave = now + cfg.WaveDelay
			end
		end
	end
end

-- Empieza una partida en esa zona con esos jugadores (ya validados por quien llama: el grupo, la sala...).
-- Devuelve la partida, o nil si no se ha podido (zona inexistente, alguien ya dentro o muerto, sin huecos de arena).
-- `opts.ghosts` = miembros fantasma (solo en Studio, para probar el escalado con un único jugador).
function launch(players: { Player }, index: number, opts: { ghosts: number?, onEnd: (() -> ())? }?)
	local level = Config.Dungeons[index]
	if not level or #players == 0 or #players > Config.Party.MaxSize then
		return nil
	end
	for _, player in players do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if runOf[player] or not player.Parent or not character or not humanoid or humanoid.Health <= 0 then
			return nil
		end
	end
	local slot = takeSlot()
	if not slot then
		return nil
	end

	local ghosts = if RunService:IsStudio() and opts and opts.ghosts then math.max(0, math.floor(opts.ghosts)) else 0
	local size = #players + ghosts
	local origin = cfg.Origin + Vector3.new(slot * cfg.Spacing, 0, 0)
	local theme = DungeonThemes.get(level)
	nextRunId += 1
	local run = {
		id = nextRunId,
		index = index,
		level = level,
		theme = theme,
		waves = theme.waves or cfg.Waves,
		slot = slot,
		origin = origin,
		model = buildArena(origin, level, theme),
		members = {},
		order = {},
		size = size,
		hpMult = 1 + Config.Party.Scaling.hp * (size - 1),
		countMult = 1 + Config.Party.Scaling.count * (size - 1),
		enemies = {},
		left = 0,
		wave = 0,
		state = "loading",
		ends = os.clock() + cfg.TimeLimit,
		nextWave = 0,
		context = { level = index, loot = level.loot, qualityLuck = level.qualityLuck },
		ended = false,
		onEnd = if opts then opts.onEnd else nil,
	}
	run.playerCount = #players
	for number, player in players do
		local member = { player = player, name = player.DisplayName, summary = Loot.summary(true), slot = number }
		run.members[player] = member
		table.insert(run.order, member)
		runOf[player] = run
	end
	run.leader = run.order[1]
	-- Quien la lanzó: su "Repetir" es el que vale aunque caiga y pase a liderar otro.
	run.owner = players[1]
	for number = 1, ghosts do
		table.insert(run.order, { ghost = true, name = `Bot {number}`, summary = Loot.summary() })
	end
	runs[run] = true

	-- Con StreamingEnabled la arena puede no haberle llegado aún: se pide antes de moverlos.
	for _, player in players do
		pcall(function()
			player:RequestStreamAroundAsync(origin, 5)
		end)
	end
	if run.ended then
		return nil
	end

	-- Cada uno aparece en un punto de un círculo pequeño alrededor del centro, mirando a él.
	local joined = 0
	for _, member in table.clone(run.order) do
		local player = member.player
		if not player then
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player.Parent or not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
			detach(run, member, false)
			continue
		end
		joined += 1
		local turn = (joined - 1) / math.max(#players, 1) * math.pi * 2
		local spot = origin + Vector3.new(math.cos(turn) * 7, 4, math.sin(turn) * 7)
		character:PivotTo(if #players == 1 then CFrame.new(origin + Vector3.new(0, 4, 0)) else CFrame.lookAt(spot, origin + Vector3.new(0, 4, 0)))
		Remotes.Teleported:FireClient(player, "dungeon")
		humanoid.Health = humanoid.MaxHealth
	end
	if run.ended then
		return nil
	end

	run.ends = os.clock() + cfg.TimeLimit
	run.nextWave = os.clock() + cfg.WaveDelay
	run.state = "waiting"
	for _, member in run.order do
		local player = member.player
		if player then
			player:SetAttribute("DungeonWaves", #run.waves)
			player:SetAttribute("DungeonWave", 0)
			player:SetAttribute("DungeonLeft", 0)
			player:SetAttribute("DungeonEnds", workspace:GetServerTimeNow() + cfg.TimeLimit)
			player:SetAttribute("DungeonRun", run.id)
			player:SetAttribute("Dungeon", index)
		end
	end
	return run
end

-- El jugador sale de su partida (botón "Salir"). No vale mientras carga ni ya ganada.
function Dungeons.leave(player: Player)
	local run = runOf[player]
	local member = run and run.members[player]
	if run and member and run.state ~= "loading" and run.state ~= "won" then
		result(run, member, false, "left")
		detach(run, member, true)
	end
end

-- Lanza una partida (lo hace server/Party al iniciar un grupo, ya validado). Ver `launch`; `opts.onEnd` se llama cuando
-- la partida termina del todo (también si se repite: solo al final de la última).
function Dungeons.launch(players: { Player }, index: number, opts: { ghosts: number?, onEnd: (() -> ())? }?)
	return launch(players, index, opts)
end

-- ¿Está ya en una partida? (el grupo lo pregunta antes de nada)
function Dungeons.isBusy(player: Player): boolean
	return runOf[player] ~= nil
end

-- "Repetir": si el jugador lidera la partida, al superarla empieza otra igual con los que sigan vivos. Se queda puesto
-- entre partidas (la ventana del grupo y el botón del panel de la partida lo cambian).
function Dungeons.setLoop(player: Player, enabled: boolean)
	looping[player] = if enabled then true else nil
	player:SetAttribute("DungeonLoop", enabled)
end

function Dungeons.getLoop(player: Player): boolean
	return looping[player] == true
end

local function onLoop(player: Player, enabled: unknown)
	Dungeons.setLoop(player, enabled == true)
end

function Dungeons.start()
	Remotes.LeaveDungeon.OnServerEvent:Connect(Dungeons.leave)
	Remotes.SetDungeonLoop.OnServerEvent:Connect(onLoop)
	local function onPlayer(player: Player)
		clearAttributes(player)
		player:SetAttribute("DungeonLoop", false)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local run = runOf[player]
		local member = run and run.members[player]
		if run and member then
			DropMenu.keepAll(player, member.summary)
			detach(run, member, false)
		end
		looping[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return Dungeons
