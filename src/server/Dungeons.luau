-- Mazmorras: portal en el hub y una arena aparte para cada jugador que entra. El cliente solo pide entrar
-- (EnterDungeon con la dificultad) o salir; aquí se valida, se construye la arena lejos de la isla, salen
-- las oleadas de Config.Dungeon.Waves, se mueve a los enemigos, se aplica el daño en los dos sentidos y se
-- reparten los premios (Loot). Los golpes del jugador llegan por Combat (Dungeons.strike).
-- Estado para el cliente en atributos del Player: Dungeon (dificultad, 0 = fuera), DungeonWave, DungeonWaves,
-- DungeonLeft (enemigos vivos), DungeonEnds (hora del servidor a la que se acaba el tiempo) y DungeonLoop (si
-- tiene puesto "repetir": al superarla empieza otra igual sin volver al hub; morir o salir corta el bucle).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Destructibles = require(script.Parent.Destructibles)
local Loot = require(script.Parent.Loot)
local Plots = require(script.Parent.Plots)

local Dungeons = {}

local cfg = Config.Dungeon
local random = Random.new()

local runs = {} -- [Player] = partida en curso
local looping = {} -- [Player] = true si quiere repetir la mazmorra en bucle
local begin -- se define más abajo (la usa win para repetir)
local lastEnter = {} -- [Player] = os.clock() de su última entrada
local portalPosition: Vector3 -- en el suelo del hub
local portalFront: CFrame -- donde se deja al jugador al volver

local STONE = { Color3.fromRGB(72, 70, 88), Color3.fromRGB(58, 56, 72) }
local GLOW = Color3.fromRGB(170, 90, 255)

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function disc(parent: Instance, name: string, center: Vector3, radius: number, height: number, color: Color3, material: Enum.Material): Part
	local part = block(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Portal ---------------------------------------------------------------------------------

-- Arco de piedra con un disco de cristal que gira (lo anima el cliente: etiqueta PortalSwirl), runas, cartel
-- y el aviso de "pulsa E". Mira hacia el centro del hub.
local function buildPortal(parent: Instance)
	local floor = Config.Plot.FloorHeight
	local angle = math.rad(cfg.PortalAngle)
	local radius = Config.Plot.HubRadius - 18
	portalPosition = Vector3.new(math.cos(angle) * radius, floor, math.sin(angle) * radius)
	local base = CFrame.lookAt(portalPosition, Vector3.new(0, floor, 0))
	portalFront = base * CFrame.new(0, 3.5, -12)

	local model = Instance.new("Model")
	model.Name = "PortalMazmorras"

	-- Escalones.
	block(model, "Step", Vector3.new(20, 0.8, 9), base * CFrame.new(0, 0.4, 0), STONE[1])
	block(model, "Step", Vector3.new(16, 0.8, 6), base * CFrame.new(0, 1.2, 0.5), STONE[2])
	-- Pilares y arco de dovelas.
	local opening, pillarHeight = 5.5, 9
	for _, side in { -1, 1 } do
		block(model, "Pillar", Vector3.new(2.6, pillarHeight, 2.6), base * CFrame.new(side * (opening + 1.3), 1.6 + pillarHeight / 2, 0.5), STONE[1])
		block(model, "Cap", Vector3.new(3.2, 0.8, 3.2), base * CFrame.new(side * (opening + 1.3), 1.6 + pillarHeight + 0.4, 0.5), STONE[2])
		local rune = block(model, "Rune", Vector3.new(0.9, 0.9, 0.3), base * CFrame.new(side * (opening + 1.3), 6, -0.95), GLOW, Enum.Material.Neon)
		rune.CanCollide = false
	end
	local archCenter = base * CFrame.new(0, 1.6 + pillarHeight + 0.8, 0.5)
	local stones = 7
	for index = 1, stones do
		local turn = math.rad(180 * (index - 0.5) / stones)
		local arm = opening + 1.3
		block(model, "Arch", Vector3.new(3.2, 2.6, 2.6), archCenter * CFrame.new(math.cos(turn) * arm, math.sin(turn) * arm, 0) * CFrame.Angles(0, 0, turn - math.pi / 2), STONE[index % 2 + 1])
	end

	-- Disco del portal: cristal morado, sin Neon (pieza grande). El cliente lo gira y le pone partículas.
	local swirl = block(model, "Swirl", Vector3.new(0.5, opening * 2, opening * 2 + 6), base * CFrame.new(0, 1.6 + pillarHeight / 2 + 1.4, 0.5) * CFrame.Angles(0, math.rad(90), 0), GLOW, Enum.Material.Glass)
	swirl.Shape = Enum.PartType.Cylinder
	swirl.Transparency = 0.25
	swirl.CanCollide = false
	swirl.CastShadow = false
	CollectionService:AddTag(swirl, "PortalSwirl")
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 26
	light.Brightness = 1.4
	light.Parent = swirl

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(380, 80)
	gui.StudsOffset = Vector3.new(0, 17, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = swirl
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 48
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "MAZMORRAS"
	label.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 3.5
	outline.Parent = label
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(200, 130, 255), Color3.fromRGB(255, 110, 140))
	gradient.Parent = label
	CollectionService:AddTag(gui, "ShopSign") -- el cliente (ModifierShops) lo anima como los de las tiendas

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Entrar"
	prompt.ObjectText = "Mazmorras"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Shop", "dungeons")
	prompt.Parent = swirl

	model.Parent = parent
end

-- Arena ----------------------------------------------------------------------------------

-- Plataforma redonda de piedra con muro, antorchas y un emblema del color de la dificultad.
local function buildArena(origin: Vector3, level): Model
	local model = Instance.new("Model")
	model.Name = "Mazmorra"
	local radius = cfg.ArenaRadius

	disc(model, "Floor", origin - Vector3.new(0, 2, 0), radius + 4, 4, STONE[2], Enum.Material.Slate)
	local ring = disc(model, "Ring", origin + Vector3.new(0, 0.05, 0), radius * 0.7, 0.1, STONE[1], Enum.Material.Cobblestone)
	ring.CanCollide = false
	local emblem = disc(model, "Emblem", origin + Vector3.new(0, 0.1, 0), 7, 0.1, level.color:Lerp(Color3.new(0, 0, 0), 0.6), Enum.Material.Slate)
	emblem.CanCollide = false

	local segments = 28
	local width = 2 * math.pi * (radius + 2) / segments + 0.6
	for index = 1, segments do
		local turn = (index - 1) / segments * math.pi * 2
		local outward = Vector3.new(math.cos(turn), 0, math.sin(turn))
		local facing = CFrame.lookAt(origin + outward * (radius + 2), origin)
		local tall = index % 4 == 1
		local height = if tall then 22 else 15
		block(model, "Wall", Vector3.new(width, height, 4), facing * CFrame.new(0, height / 2, 0), STONE[index % 2 + 1])
		if tall then
			local torch = block(model, "Torch", Vector3.new(1.4, 1.4, 1.4), facing * CFrame.new(0, 12, -3), Color3.fromRGB(255, 160, 60), Enum.Material.Neon)
			torch.CanCollide = false
			local light = Instance.new("PointLight")
			light.Color = level.color:Lerp(Color3.fromRGB(255, 170, 80), 0.5)
			light.Range = 40
			light.Brightness = 1.6
			light.Parent = torch
		end
	end
	-- Muro invisible por encima, para que no se pueda salir saltando.
	for index = 1, segments do
		local turn = (index - 1) / segments * math.pi * 2
		local facing = CFrame.lookAt(origin + Vector3.new(math.cos(turn), 0, math.sin(turn)) * (radius + 2), origin)
		local barrier = block(model, "Barrier", Vector3.new(width, 60, 2), facing * CFrame.new(0, 45, 0), STONE[1])
		barrier.Transparency = 1
		barrier.CanQuery = false
		barrier.CastShadow = false
	end
	model.Parent = workspace
	return model
end

-- Enemigos -------------------------------------------------------------------------------

-- Adornos por tipo de enemigo ("look" en Config.Enemies): piezas pequeñas soldadas al cuerpo.
local function decorate(body: Part, def)
	local size = def.size
	local function add(name: string, partSize: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
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
	end
	-- Ojos (la cara es -Z).
	local eye = size.X * 0.2
	for _, side in { -1, 1 } do
		add("Eye", Vector3.new(eye, eye * 1.2, 0.3), CFrame.new(side * size.X * 0.22, size.Y * 0.15, -size.Z / 2 - 0.1), Color3.new(1, 1, 1))
		add("Pupil", Vector3.new(eye * 0.45, eye * 0.6, 0.3), CFrame.new(side * size.X * 0.22, size.Y * 0.12, -size.Z / 2 - 0.2), Color3.new(0, 0, 0))
	end
	add("Mouth", Vector3.new(size.X * 0.4, size.Y * 0.07, 0.3), CFrame.new(0, -size.Y * 0.2, -size.Z / 2 - 0.1), Color3.new(0, 0, 0))
	if def.look == "horns" or def.look == "crown" then
		for _, side in { -1, 1 } do
			add("Horn", Vector3.new(size.X * 0.14, size.Y * 0.35, size.X * 0.14), CFrame.new(side * size.X * 0.36, size.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(-side * 18)), Color3.fromRGB(240, 235, 215))
		end
	end
	if def.look == "crown" then
		add("Crown", Vector3.new(size.X * 0.5, size.Y * 0.1, size.Z * 0.5), CFrame.new(0, size.Y * 0.55, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Foil)
		for index = 1, 4 do
			local turn = index * math.pi / 2
			add("Spike", Vector3.new(size.X * 0.08, size.Y * 0.16, size.X * 0.08), CFrame.new(math.cos(turn) * size.X * 0.2, size.Y * 0.68, math.sin(turn) * size.Z * 0.2), Color3.fromRGB(255, 205, 60), Enum.Material.Foil)
		end
	end
end

local function spawnEnemy(run, key: string)
	local def = Config.Enemies[key]
	local level = run.level
	local turn = random:NextNumber(0, math.pi * 2)
	local distance = cfg.ArenaRadius * random:NextNumber(0.55, 0.85)
	local position = run.origin + Vector3.new(math.cos(turn) * distance, def.size.Y / 2 + 1, math.sin(turn) * distance)

	local body = Instance.new("Part")
	body.Name = def.name
	body.Size = def.size
	body.Color = def.color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0) -- sin rozamiento: lo mueve LinearVelocity
	body.CFrame = CFrame.lookAt(position, Vector3.new(run.origin.X, position.Y, run.origin.Z))
	local hp = def.hp * level.hp
	body:SetAttribute("HP", hp)
	body:SetAttribute("MaxHP", hp)
	CollectionService:AddTag(body, "Enemy")
	decorate(body, def)

	local attachment = Instance.new("Attachment")
	attachment.Parent = body
	local mass = def.size.X * def.size.Y * def.size.Z
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
	run.enemies[body] = { def = def, hp = hp, velocity = velocity, align = align, nextAttack = os.clock() + def.attackTime * 0.5, mass = mass }
	run.alive += 1
end

-- Partidas -------------------------------------------------------------------------------

local function publish(run)
	local player = run.player
	player:SetAttribute("DungeonWave", run.wave)
	player:SetAttribute("DungeonLeft", run.alive)
end

local function startWave(run)
	run.wave += 1
	run.state = "fighting"
	for _, entry in cfg.Waves[run.wave] do
		local key, count = entry[1], entry[2]
		local def = Config.Enemies[key]
		if def then
			local total = if def.scaleCount == false then count else math.ceil(count * run.level.count)
			for _ = 1, total do
				spawnEnemy(run, key)
			end
		end
	end
	publish(run)
end

-- Termina la partida: borra la arena y, si toca, devuelve al jugador al portal.
local function finish(run, bringBack: boolean)
	local player = run.player
	if runs[player] ~= run then
		return
	end
	runs[player] = nil
	if player.Parent then
		player:SetAttribute("Dungeon", 0)
		if bringBack then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				character:PivotTo(portalFront)
			end
		end
	end
	run.model:Destroy()
end

local function result(run, won: boolean, reason: string)
	if run.player.Parent then
		Remotes.DungeonEvent:FireClient(run.player, "result", { won = won, reason = reason, level = run.index, loot = run.summary })
	end
end

local function win(run)
	run.state = "won"
	Loot.roll(run.player, cfg.ClearDrops, run.context, run.summary)
	result(run, true, "clear")
	task.delay(cfg.ExitDelay, function()
		local player = run.player
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if runs[player] == run and looping[player] and humanoid and humanoid.Health > 0 then
			-- Repetir: se cambia la arena por una nueva sin sacarlo de ella.
			finish(run, false)
			begin(player, run.index)
		else
			finish(run, true)
		end
	end)
end

local function kill(run, body: BasePart)
	local enemy = run.enemies[body]
	run.enemies[body] = nil
	run.alive -= 1
	-- Mismo aviso que al romper un objeto: escombros y sonido en el cliente.
	Remotes.Broken:FireClient(run.player, run.player, body.CFrame, body.Size, body.Color, body.Material, 0, 0)
	body:Destroy()
	Loot.roll(run.player, enemy.def.drops, run.context, run.summary)
	publish(run)
end

-- Espadazo del jugador (lo llama Combat con el daño y el alcance ya calculados en el servidor).
function Dungeons.strike(player: Player, origin: CFrame, range: number, arc: number, damage: number)
	local run = runs[player]
	if not run or run.state ~= "fighting" then
		return
	end
	local hit = {}
	for body in run.enemies do
		if Destructibles.reaches(body, origin, range, arc) then
			table.insert(hit, body)
		end
	end
	for _, body in hit do
		local enemy = run.enemies[body]
		Remotes.Hit:FireClient(player, player, body, body.Position, damage)
		enemy.hp -= damage
		if enemy.hp <= 0 then
			kill(run, body)
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
	for player, run in runs do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if run.state == "loading" then
			continue
		end
		if not root or not humanoid or humanoid.Health <= 0 then
			result(run, false, "dead")
			finish(run, false)
			continue
		end
		-- Se ha ido de la arena (barra de transporte, caída...).
		if (root.Position - run.origin).Magnitude > cfg.ArenaRadius + 80 then
			finish(run, false)
			continue
		end
		if run.state == "won" then
			continue
		end
		if now >= run.ends then
			result(run, false, "time")
			finish(run, true)
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
				body.CFrame = CFrame.new(run.origin + Vector3.new(0, def.size.Y / 2 + 2, cfg.ArenaRadius * 0.6))
			end
			local offset = root.Position - body.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local gap = flat.Magnitude - def.size.X / 2 - 1
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
			enemy.align.CFrame = CFrame.lookAt(Vector3.zero, direction)
			local speed = if gap > def.attackRange * 0.6 then def.speed else 0
			enemy.velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
			if gap <= def.attackRange and math.abs(offset.Y) < def.size.Y + 6 and now >= enemy.nextAttack then
				enemy.nextAttack = now + def.attackTime
				local amount = def.damage * power
				humanoid:TakeDamage(amount)
				Remotes.DungeonEvent:FireClient(player, "hurt", { amount = amount, from = body })
			end
		end

		if run.alive <= 0 then
			if run.wave >= #cfg.Waves then
				win(run)
			else
				run.state = "waiting"
				run.nextWave = now + cfg.WaveDelay
			end
		end
	end
end

-- Empieza una partida en esa dificultad (ya validada por quien llama): arena nueva y jugador dentro.
function begin(player: Player, index: number)
	local now = os.clock()
	local level = Config.Dungeons[index]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not level or runs[player] or not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Un hueco por jugador: el de su parcela.
	local plot = Plots.get(player)
	local slot = if plot then plot.index else 0
	local origin = cfg.Origin + Vector3.new(slot * cfg.Spacing, 0, 0)
	local run = {
		player = player,
		players = { player }, -- de momento se entra solo; la lista queda preparada para grupos
		index = index,
		level = level,
		origin = origin,
		model = buildArena(origin, level),
		enemies = {},
		alive = 0,
		wave = 0,
		state = "loading",
		ends = now + cfg.TimeLimit,
		nextWave = 0,
		summary = Loot.summary(),
		context = { level = index, loot = level.loot, qualityLuck = level.qualityLuck },
	}
	runs[player] = run

	-- Con StreamingEnabled la arena puede no haberle llegado aún: se pide antes de moverlo.
	pcall(function()
		player:RequestStreamAroundAsync(origin, 5)
	end)
	if runs[player] ~= run then
		return
	end
	if not character.Parent or humanoid.Health <= 0 then
		finish(run, false)
		return
	end
	character:PivotTo(CFrame.new(origin + Vector3.new(0, 4, 0)))
	humanoid.Health = humanoid.MaxHealth
	run.ends = os.clock() + cfg.TimeLimit
	run.nextWave = os.clock() + cfg.WaveDelay
	run.state = "waiting"
	player:SetAttribute("DungeonWaves", #cfg.Waves)
	player:SetAttribute("DungeonWave", 0)
	player:SetAttribute("DungeonLeft", 0)
	player:SetAttribute("DungeonEnds", workspace:GetServerTimeNow() + cfg.TimeLimit)
	player:SetAttribute("Dungeon", index)
end

local function onEnter(player: Player, index: unknown)
	local now = os.clock()
	local level = if type(index) == "number" then Config.Dungeons[index] else nil
	if not level or runs[player] or now - (lastEnter[player] or 0) < cfg.EnterCooldown then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (root.Position - portalPosition).Magnitude > cfg.EnterDistance then
		return
	end
	lastEnter[player] = now
	begin(player, index :: number)
end

local function onLoop(player: Player, enabled: unknown)
	looping[player] = enabled == true or nil
	player:SetAttribute("DungeonLoop", enabled == true)
end

local function onLeave(player: Player)
	local run = runs[player]
	if run and run.state ~= "loading" and run.state ~= "won" then
		result(run, false, "left")
		finish(run, true)
	end
end

function Dungeons.start()
	buildPortal(workspace:WaitForChild("Map"))

	Remotes.EnterDungeon.OnServerEvent:Connect(onEnter)
	Remotes.LeaveDungeon.OnServerEvent:Connect(onLeave)
	Remotes.SetDungeonLoop.OnServerEvent:Connect(onLoop)
	local function onPlayer(player: Player)
		player:SetAttribute("Dungeon", 0)
		player:SetAttribute("DungeonLoop", false)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local run = runs[player]
		if run then
			finish(run, false)
		end
		lastEnter[player] = nil
		looping[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return Dungeons
