-- Lo que sale en la arena del Jefe del mundo además del rey (librería, sin start()): esbirros slime que persiguen y
-- muerden, cristales del escudo y barriles de gelatina que, rotos, salen disparados contra el rey. Cada cosa es una
-- pieza con la etiqueta WorldBossTarget (se le pega como a todo: client/Targeting y server/Combat) y una entrada en la
-- tabla `targets` de server/WorldBoss, que es quien lleva la vida y decide qué pasa al romperse.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WorldBossMobs = {}

local cfg = Config.WorldBoss
local random = Random.new()

local TAG = "WorldBossTarget"

local function body(folder: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, hp: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("HP", hp)
	p:SetAttribute("MaxHP", hp)
	CollectionService:AddTag(p, TAG)
	p.Parent = folder
	return p
end

-- Punto al azar del suelo de la arena entre `from` y `to` veces su radio.
function WorldBossMobs.spot(from: number, to: number): Vector3
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = cfg.ArenaRadius * random:NextNumber(from, to)
	return cfg.Origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Esbirro: caja invisible con física (la viste client/Slimes, por la etiqueta Enemy) que sale junto al rey.
function WorldBossMobs.minion(folder: Instance, hp: number)
	local def = cfg.Summon
	local size = Vector3.one * def.Size
	local ground = WorldBossMobs.spot(0.3, 0.45)
	local p = body(folder, "Minion", size, CFrame.lookAt(ground + Vector3.new(0, size.Y / 2 + 1, 0), Vector3.new(cfg.Origin.X, ground.Y + size.Y / 2 + 1, cfg.Origin.Z)), cfg.Color:Lerp(Color3.new(1, 1, 1), 0.15), hp)
	p.Transparency = 1
	p.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0)
	p.CollisionGroup = "Enemies"
	p:SetAttribute("Kind", "grunt")
	p:SetAttribute("Look", "")
	p:SetAttribute("NextAttack", workspace:GetServerTimeNow() + def.BiteEvery)
	CollectionService:AddTag(p, "Enemy")
	local attachment = Instance.new("Attachment")
	attachment.Parent = p
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.zero
	velocity.MaxForce = size.X * size.Y * size.Z * 140
	velocity.Parent = p
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.CFrame = p.CFrame.Rotation
	align.MaxTorque = math.huge
	align.Responsiveness = 30
	align.Parent = p
	p:SetNetworkOwner(nil)
	return p, { kind = "minion", velocity = velocity, align = align, nextBite = os.clock() + def.BiteEvery }
end

-- Mueve los esbirros hacia el jugador vivo más cercano y muerde al que tienen a tiro. `fighters` = lista de
-- { player, root, humanoid } de los que están en la arena.
function WorldBossMobs.step(targets, fighters)
	local def = cfg.Summon
	local now = os.clock()
	for p, entry in targets do
		if entry.kind ~= "minion" then
			continue
		end
		if p.Position.Y < cfg.Origin.Y - 20 then
			p.AssemblyLinearVelocity = Vector3.zero
			p.CFrame = CFrame.new(WorldBossMobs.spot(0.3, 0.45) + Vector3.new(0, def.Size, 0))
		end
		local target, closest = nil, math.huge
		for _, fighter in fighters do
			local offset = fighter.root.Position - p.Position
			local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if distance < closest then
				target, closest = fighter, distance
			end
		end
		if not target then
			entry.velocity.PlaneVelocity = Vector2.zero
			continue
		end
		local offset = target.root.Position - p.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		entry.align.CFrame = CFrame.lookAt(Vector3.zero, direction)
		local gap = flat.Magnitude - def.Size / 2 - 1
		local speed = if gap > def.Range * 0.6 then def.Speed else 0
		entry.velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
		if gap <= def.Range and now >= entry.nextBite then
			entry.nextBite = now + def.BiteEvery
			target.humanoid:TakeDamage(target.humanoid.MaxHealth * def.Damage)
			local serverNow = workspace:GetServerTimeNow()
			p:SetAttribute("Victim", target.player.UserId)
			p:SetAttribute("AttackAt", serverNow)
			p:SetAttribute("NextAttack", serverNow + def.BiteEvery)
		end
	end
end

-- Cristal del escudo: flota sobre un pedestal alrededor del rey. Mientras quede alguno, el rey no recibe daño.
function WorldBossMobs.crystal(folder: Instance, index: number, count: number, hp: number)
	local angle = (index - 1) / count * math.pi * 2 + random:NextNumber(-0.2, 0.2)
	local distance = cfg.ArenaRadius * 0.55
	local ground = cfg.Origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local p = body(folder, "ShieldCrystal", Vector3.new(4, 8, 4), CFrame.new(ground + Vector3.new(0, 6, 0)) * CFrame.Angles(0, angle, math.rad(45)), Color3.fromRGB(110, 190, 255), hp)
	p.Anchored = true
	p.Material = Enum.Material.Glass
	p.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 16
	light.Brightness = 2
	light.Parent = p
	local beam = Instance.new("Part")
	beam.Name = "Pedestal"
	beam.Anchored = true
	beam.CanQuery = false
	beam.Size = Vector3.new(5, 1.6, 5)
	beam.CFrame = CFrame.new(ground + Vector3.new(0, 0.8, 0))
	beam.Color = Color3.fromRGB(70, 66, 86)
	beam.Material = Enum.Material.Slate
	beam.Parent = p
	return p, { kind = "crystal" }
end

-- Barril de gelatina explosiva, en un sitio al azar de la arena.
function WorldBossMobs.barrel(folder: Instance, hp: number)
	local ground = WorldBossMobs.spot(0.35, 0.85)
	local p = body(folder, "Barrel", Vector3.new(4.4, 3.6, 3.6), CFrame.new(ground + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 98, 56), hp)
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.Material = Enum.Material.Wood
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(1.4, 3.8, 3.8)
	band.CFrame = p.CFrame
	band.Color = Color3.fromRGB(120, 230, 90)
	band.Material = Enum.Material.SmoothPlastic
	band.Parent = p
	return p, { kind = "barrel" }
end

-- Lanza un barril roto contra el rey con física (tiro parabólico que llega en Charge.Flight s). Avisa a los clientes
-- para la estela y la explosión. `onArrive` se llama al llegar.
function WorldBossMobs.launch(p: BasePart, to: Vector3, onArrive: () -> ())
	CollectionService:RemoveTag(p, TAG)
	local band = p:FindFirstChild("Band")
	if band then
		band:Destroy()
	end
	local from = p.Position
	local flight = cfg.Charge.Flight
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	p.CanCollide = false
	p.CanQuery = false
	p.Color = Color3.fromRGB(120, 230, 90)
	p.Anchored = false
	p.AssemblyLinearVelocity = (to - from) / flight - gravity * flight / 2
	p.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-8, 8), random:NextNumber(-8, 8), random:NextNumber(-8, 8))
	p:SetNetworkOwner(nil)
	Remotes.WorldBoss:FireAllClients("launch", { part = p, from = from, to = to, flight = flight })
	task.delay(flight, function()
		Remotes.WorldBoss:FireAllClients("boom", to)
		p:Destroy()
		onArrive()
	end)
end

return WorldBossMobs
