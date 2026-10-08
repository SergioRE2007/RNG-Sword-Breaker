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

-- Adornos de cada "look" (Config.Enemies y los skins de Config.DungeonThemes; un enemigo puede llevar varios):
-- piezas pequeñas soldadas al cuerpo. Un look nuevo es una función más aquí. `add` pone una pieza (devuelve la
-- pieza); `size` es el tamaño del cuerpo; `color` su color. La cara es -Z.
local GOLD = Color3.fromRGB(255, 205, 60)
local BONE = Color3.fromRGB(240, 235, 215)
local LOOKS: { [string]: (add: (string, Vector3, CFrame, Color3, Enum.Material?) -> Part, size: Vector3, color: Color3) -> () } = {}

LOOKS.horns = function(add, size)
	for _, side in { -1, 1 } do
		add("Horn", Vector3.new(size.X * 0.14, size.Y * 0.35, size.X * 0.14), CFrame.new(side * size.X * 0.36, size.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(-side * 18)), BONE)
	end
end

LOOKS.crown = function(add, size)
	add("Crown", Vector3.new(size.X * 0.5, size.Y * 0.1, size.Z * 0.5), CFrame.new(0, size.Y * 0.55, 0), GOLD, Enum.Material.Foil)
	for index = 1, 4 do
		local turn = index * math.pi / 2
		add("Spike", Vector3.new(size.X * 0.08, size.Y * 0.16, size.X * 0.08), CFrame.new(math.cos(turn) * size.X * 0.2, size.Y * 0.68, math.sin(turn) * size.Z * 0.2), GOLD, Enum.Material.Foil)
	end
end

-- Hojas en la cabeza (bosque, nebulosa): láminas verdes inclinadas.
LOOKS.leaf = function(add, size, color)
	local green = color:Lerp(Color3.fromRGB(70, 190, 80), 0.6)
	for index, lean in { -26, 0, 26 } do
		add("Leaf", Vector3.new(size.X * 0.2, size.Y * 0.34, size.X * 0.05), CFrame.new((index - 2) * size.X * 0.2, size.Y * 0.64, 0) * CFrame.Angles(0, 0, math.rad(lean)), green)
	end
end

LOOKS.antlers = function(add, size)
	local wood = Color3.fromRGB(128, 96, 64)
	for _, side in { -1, 1 } do
		add("Antler", Vector3.new(size.X * 0.08, size.Y * 0.5, size.X * 0.08), CFrame.new(side * size.X * 0.3, size.Y * 0.68, 0) * CFrame.Angles(0, 0, math.rad(-side * 20)), wood, Enum.Material.Wood)
		add("Prong", Vector3.new(size.X * 0.06, size.Y * 0.24, size.X * 0.06), CFrame.new(side * size.X * 0.46, size.Y * 0.8, 0) * CFrame.Angles(0, 0, math.rad(-side * 55)), wood, Enum.Material.Wood)
	end
end

-- Capucha: un bloque oscuro sobre la cabeza.
LOOKS.hood = function(add, size, color)
	add("Hood", Vector3.new(size.X * 1.05, size.Y * 0.24, size.Z * 1.05), CFrame.new(0, size.Y * 0.4, size.Z * 0.01), color:Lerp(Color3.new(0, 0, 0), 0.55))
end

LOOKS.spikes = function(add, size, color)
	for index = 1, 5 do
		local turn = index / 5 * math.pi * 2
		add("Spike", Vector3.new(size.X * 0.1, size.Y * 0.24, size.X * 0.1), CFrame.new(math.cos(turn) * size.X * 0.28, size.Y * 0.58, math.sin(turn) * size.Z * 0.28), color:Lerp(Color3.new(1, 1, 1), 0.45))
	end
end

-- Llamitas en la cabeza (brillan, pero son pequeñas).
LOOKS.flame = function(add, size)
	for index, lean in { -14, 0, 14 } do
		add("Flame", Vector3.new(size.X * 0.12, size.Y * 0.3, size.X * 0.12), CFrame.new((index - 2) * size.X * 0.16, size.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(lean)), Color3.fromRGB(255, 150, 50), Enum.Material.Neon)
	end
end

LOOKS.halo = function(add, size)
	local ring = add("Halo", Vector3.new(size.Y * 0.06, size.X * 0.8, size.X * 0.8), CFrame.new(0, size.Y * 0.78, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 245, 190), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.15
end

LOOKS.helmet = function(add, size)
	add("Helmet", Vector3.new(size.X * 1.04, size.Y * 0.2, size.Z * 1.04), CFrame.new(0, size.Y * 0.42, 0), Color3.fromRGB(235, 190, 60), Enum.Material.Metal)
	add("Lamp", Vector3.new(size.X * 0.18, size.X * 0.18, size.X * 0.14), CFrame.new(0, size.Y * 0.46, -size.Z / 2 - 0.3), Color3.fromRGB(255, 244, 190), Enum.Material.Neon)
end

-- Calavera: cuencas negras tras los ojos y dientes.
LOOKS.skull = function(add, size)
	local eye = size.X * 0.2
	for _, side in { -1, 1 } do
		add("Socket", Vector3.new(eye * 1.55, eye * 1.8, 0.2), CFrame.new(side * size.X * 0.22, size.Y * 0.15, -size.Z / 2 - 0.05), Color3.new(0, 0, 0))
	end
	for index = -1.5, 1.5 do
		add("Tooth", Vector3.new(size.X * 0.07, size.Y * 0.1, 0.3), CFrame.new(index * size.X * 0.1, -size.Y * 0.2, -size.Z / 2 - 0.3), Color3.new(1, 1, 1))
	end
end

-- Cuerpo ya creado: ojos, boca y los adornos del look (nombre o lista de nombres).
local function decorate(body: Part, look: (string | { string })?)
	local size = body.Size
	local function add(name: string, partSize: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = partSize
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.CFrame = body.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
		part.Parent = body
		return part
	end
	-- Ojos (la cara es -Z).
	local eye = size.X * 0.2
	for _, side in { -1, 1 } do
		add("Eye", Vector3.new(eye, eye * 1.2, 0.3), CFrame.new(side * size.X * 0.22, size.Y * 0.15, -size.Z / 2 - 0.1), Color3.new(1, 1, 1))
		add("Pupil", Vector3.new(eye * 0.45, eye * 0.6, 0.3), CFrame.new(side * size.X * 0.22, size.Y * 0.12, -size.Z / 2 - 0.2), Color3.new(0, 0, 0))
	end
	add("Mouth", Vector3.new(size.X * 0.4, size.Y * 0.07, 0.3), CFrame.new(0, -size.Y * 0.2, -size.Z / 2 - 0.1), Color3.new(0, 0, 0))
	local names = if type(look) == "table" then look elseif look then { look } else {}
	for _, name in names do
		local make = LOOKS[name]
		if make then
			make(add, size, body.Color)
		end
	end
end

local function spawnEnemy(run, key: string)
	local def = Config.Enemies[key]
	local level = run.level
	-- Cómo se ve en esta zona (nombre, color, adornos y escala del tema); sus números siguen siendo los de Config.Enemies.
	local skin = DungeonThemes.skin(run.theme, key)
	local size: Vector3 = def.size * ((skin and skin.scale) or 1)
	local turn = random:NextNumber(0, math.pi * 2)
	local distance = cfg.ArenaRadius * random:NextNumber(0.55, 0.85)
	local position = run.origin + Vector3.new(math.cos(turn) * distance, size.Y / 2 + 1, math.sin(turn) * distance)

	local body = Instance.new("Part")
	body.Name = (skin and skin.name) or def.name
	body.Size = size
	body.Color = (skin and skin.color) or def.color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0) -- sin rozamiento: lo mueve LinearVelocity
	body.CFrame = CFrame.lookAt(position, Vector3.new(run.origin.X, position.Y, run.origin.Z))
	local hp = def.hp * level.hp * run.hpMult
	body:SetAttribute("HP", hp)
	body:SetAttribute("MaxHP", hp)
	CollectionService:AddTag(body, "Enemy")
	decorate(body, (skin and skin.look) or def.look)

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
	velocity.MaxForce = mass * 140 -- limitada: un espadazo lo empuja un momento
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
	run.enemies[body] = { def = def, size = size, hp = hp, velocity = velocity, align = align, nextAttack = os.clock() + def.attackTime * 0.5, mass = mass }
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
		Remotes.DungeonEvent:FireClient(player, "result", { won = won, reason = reason, level = run.index, loot = member.summary })
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
		end
	end
	publish(run)
end

-- Espadazo del jugador (lo llama Combat con el daño y el alcance ya calculados en el servidor). `already` son los
-- enemigos que ese mismo espadazo ya ha golpeado: no repiten, y aquí se apuntan los nuevos.
function Dungeons.strike(player: Player, origin: CFrame, range: number, arc: number, damage: number, already: { [BasePart]: boolean }?)
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
		if already then
			already[body] = true
		end
		local enemy = run.enemies[body]
		if not enemy then
			continue
		end
		for _, member in run.order do
			if member.player and member.player.Parent then
				Remotes.Hit:FireClient(member.player, player, body, body.Position, damage)
			end
		end
		enemy.hp -= damage
		if enemy.hp <= 0 then
			kill(run, body, player)
		else
			body:SetAttribute("HP", enemy.hp)
			-- Empujón hacia atrás.
			local away = body.Position - origin.Position
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude > 0.1 then
				body:ApplyImpulse(away.Unit * enemy.mass * 28)
			end
		end
	end
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
			local speed = if gap > def.attackRange * 0.6 then def.speed else 0
			enemy.velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
			if gap <= def.attackRange and math.abs(offset.Y) < enemy.size.Y + 6 and now >= enemy.nextAttack then
				enemy.nextAttack = now + def.attackTime
				local amount = def.damage * power
				target.humanoid:TakeDamage(amount)
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
		local member = { player = player, name = player.DisplayName, summary = Loot.summary(), slot = number }
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
			detach(run, member, false)
		end
		looping[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return Dungeons
