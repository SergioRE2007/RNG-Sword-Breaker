-- Efectos del Jefe del mundo en el mundo (librería; la arranca client/WorldBoss con WorldBossFx.start()): remolino del
-- portal del hub, sombra del rey antes de caer y su impacto, globos de gelatina que vuelan en arco a los círculos rojos,
-- zonas seguras del súper golpe, burbuja del escudo, estrellas del aturdido, estela y explosión de los barriles, y el
-- temblor de cámara. Todo es visual y local: cuándo y a quién hace daño lo decide server/WorldBoss. Lo que crea vive en
-- workspace.WorldBossFx.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)

local WorldBossFx = {}

local cfg = Config.WorldBoss
local player = Players.LocalPlayer
local rng = Random.new()

local RED = Color3.fromRGB(235, 60, 60)
local SAFE = Color3.fromRGB(90, 230, 110)
local SHIELD = Color3.fromRGB(110, 190, 255)
local STAR = Color3.fromRGB(255, 225, 90)
local GLOB_FLIGHT = 0.8 -- lo que vuela un globo antes de caer en su círculo

local folder: Folder? = nil
local shake = 0 -- fuerza del temblor de cámara que queda
local shakeBound = false
local live = {} -- efectos con su función de cada fotograma: { update(now, serverNow) -> seguir? }
local loop: RBXScriptConnection? = nil
local shadow: BasePart? = nil
local bubble: BasePart? = nil
local stars: { BasePart } = {}

local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "WorldBossFx"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = getFolder()
	return p
end

-- Disco plano en el suelo (cilindro tumbado).
local function flat(name: string, diameter: number, at: Vector3, color: Color3, alpha: number): Part
	local p = part(name, Vector3.new(0.2, diameter, diameter), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	p.Transparency = alpha
	return p
end

local function step()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for index = #live, 1, -1 do
		if not live[index](now, serverNow) then
			table.remove(live, index)
		end
	end
	if #live == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function add(update: (number, number) -> boolean)
	table.insert(live, update)
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

-- Temblor de cámara (se suma: dos golpes seguidos tiemblan más).
function WorldBossFx.shake(amount: number)
	shake = math.min(shake + amount, 2.5)
	if shakeBound then
		return
	end
	shakeBound = true
	RunService:BindToRenderStep("WorldBossShake", Enum.RenderPriority.Camera.Value + 5, function(dt)
		local camera = workspace.CurrentCamera
		if shake <= 0.01 then
			shake = 0
			RunService:UnbindFromRenderStep("WorldBossShake")
			shakeBound = false
			return
		end
		local k = shake * 0.02
		camera.CFrame *= CFrame.Angles(rng:NextNumber(-k, k), rng:NextNumber(-k, k), rng:NextNumber(-k, k) * 0.5)
		shake = math.max(0, shake - dt * 3)
	end)
end

-- Temblor según lo lejos que esté de `at` (fuera de `radius`, nada).
local function shakeFrom(at: Vector3, amount: number, radius: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local distance = (root.Position - at).Magnitude
		if distance < radius then
			WorldBossFx.shake(amount * (1 - distance / radius))
		end
	end
end

-- Onda que se abre por el suelo.
local function ring(at: Vector3, to: number, color: Color3, life: number)
	local wave = flat("Wave", 2, at + Vector3.new(0, 0.35, 0), color, 0.3)
	local born = os.clock()
	add(function(now)
		local k = (now - born) / life
		if k >= 1 then
			wave:Destroy()
			return false
		end
		local size = 2 + (to - 2) * (1 - (1 - k) ^ 3)
		wave.Size = Vector3.new(0.2, size, size)
		wave.Transparency = 0.3 + 0.7 * k
		return true
	end)
end

-- Gotas de gelatina que saltan y caen.
local function splash(at: Vector3, color: Color3, count: number)
	if Performance.get() then
		count = math.ceil(count / 3)
	end
	for _ = 1, count do
		local drop = part("Drop", Vector3.one * rng:NextNumber(0.8, 1.8), CFrame.new(at), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		drop.Transparency = 0.2
		local velocity = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(10, 22) + Vector3.new(0, rng:NextNumber(18, 30), 0)
		local position = at
		local last = os.clock()
		add(function(now)
			local dt = now - last
			last = now
			velocity += Vector3.new(0, -workspace.Gravity * 0.5, 0) * dt
			position += velocity * dt
			if position.Y < at.Y - 1 then
				drop:Destroy()
				return false
			end
			drop.CFrame = CFrame.new(position)
			return true
		end)
	end
end

-- Caída: el rey cae en `at` (hora del servidor). Sombra que crece y, al llegar, onda y temblor.
function WorldBossFx.fall(at: number)
	local center = cfg.Origin + Vector3.new(0, 0.4, 0)
	local spot = flat("FallShadow", 4, center, Color3.new(0, 0, 0), 0.9)
	local start = workspace:GetServerTimeNow()
	add(function(_, serverNow)
		local k = math.clamp((serverNow - start) / math.max(at - start, 0.1), 0, 1)
		if serverNow >= at then
			spot:Destroy()
			ring(center, cfg.ArenaRadius * 1.6, cfg.Color, 0.8)
			shakeFrom(center, 2.2, 260)
			Sfx.play("hit_enemy", 1)
			return false
		end
		local size = 4 + (cfg.Size.X * 1.3 - 4) * k
		spot.Size = Vector3.new(0.2, size, size)
		spot.Transparency = 0.9 - 0.5 * k
		return true
	end)
end

-- Sombra del rey mientras el portal está abierto: crece hasta la hora de la caída (para quien ya espera en la arena).
function WorldBossFx.waiting(fallAt: number?)
	if shadow then
		shadow:Destroy()
		shadow = nil
	end
	if not fallAt then
		return
	end
	local center = cfg.Origin + Vector3.new(0, 0.38, 0)
	local spot = flat("WaitShadow", 4, center, Color3.new(0, 0, 0), 0.95)
	shadow = spot
	local start = fallAt - cfg.Warning
	add(function(_, serverNow)
		if shadow ~= spot or serverNow >= fallAt then
			spot:Destroy()
			if shadow == spot then
				shadow = nil
			end
			return false
		end
		local k = math.clamp((serverNow - start) / cfg.Warning, 0, 1)
		local size = 4 + (cfg.Size.X - 4) * k
		spot.Size = Vector3.new(0.2, size, size)
		spot.Transparency = 0.95 - 0.35 * k
		return true
	end)
end

-- Círculo marcado en el suelo que se llena hasta `at`. Devuelve una función que lo quita.
local function marker(at: Vector3, radius: number, color: Color3, deadline: number, fill: boolean)
	local ground = Vector3.new(at.X, cfg.Origin.Y + 0.3, at.Z)
	local edge = flat("Zone", radius * 2, ground, color, 0.55)
	local inner = flat("ZoneFill", 0.5, ground + Vector3.new(0, 0.05, 0), color, 0.3)
	local start = workspace:GetServerTimeNow()
	local done = false
	add(function(now, serverNow)
		if done or serverNow >= deadline + 0.05 then
			edge:Destroy()
			inner:Destroy()
			return false
		end
		local k = math.clamp((serverNow - start) / math.max(deadline - start, 0.1), 0, 1)
		local size = if fill then radius * 2 * k else radius * 2 * (0.85 + 0.15 * math.sin(now * 6))
		inner.Size = Vector3.new(0.2, math.max(size, 0.5), math.max(size, 0.5))
		edge.Transparency = 0.55 - 0.25 * math.abs(math.sin(now * (4 + 8 * k)))
		return true
	end)
	return function()
		done = true
	end
end

-- Bombardeo: círculos rojos y un globo por círculo que sale de lo alto del rey y cae justo a su hora.
function WorldBossFx.barrage(data)
	for _, spot in data.spots do
		marker(spot, data.radius, RED, data.at, true)
		local leave = data.at - GLOB_FLIGHT
		local from: Vector3 = data.from
		local glob: BasePart? = nil
		add(function(_, serverNow)
			if serverNow < leave then
				return true
			end
			local k = math.clamp((serverNow - leave) / GLOB_FLIGHT, 0, 1)
			if not glob then
				glob = part("Glob", Vector3.one * 4, CFrame.new(from), cfg.Color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
				glob.Transparency = 0.15
			end
			local target = Vector3.new(spot.X, cfg.Origin.Y + 1, spot.Z)
			local position = from:Lerp(target, k) + Vector3.new(0, math.sin(k * math.pi) * 30, 0)
			glob.CFrame = CFrame.new(position)
			if k >= 1 then
				glob:Destroy()
				splash(target, cfg.Color, 8)
				ring(target, data.radius * 2.2, cfg.Color, 0.45)
				shakeFrom(target, 0.6, 40)
				return false
			end
			return true
		end)
	end
end

local safeZones: { () -> () } = {}

-- Carga del súper golpe: zonas verdes seguras hasta `at`.
function WorldBossFx.charge(data)
	WorldBossFx.clearCharge()
	for _, spot in data.safe do
		table.insert(safeZones, marker(spot, data.radius, SAFE, data.at, false))
	end
end

function WorldBossFx.clearCharge()
	for _, remove in safeZones do
		remove()
	end
	table.clear(safeZones)
end

-- Súper golpe: onda roja por toda la arena y un buen temblor.
function WorldBossFx.mega()
	WorldBossFx.clearCharge()
	ring(cfg.Origin, cfg.ArenaRadius * 2.2, RED, 0.9)
	ring(cfg.Origin, cfg.ArenaRadius * 1.4, cfg.Color, 0.6)
	shakeFrom(cfg.Origin, 2.5, 300)
end

-- Barril lanzado: estela verde mientras vuela.
function WorldBossFx.launch(data)
	local barrel = data.part
	if typeof(barrel) ~= "Instance" or not barrel:IsA("BasePart") or Performance.get() then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = barrel
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = barrel
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 255, 120))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.35
	trail.Parent = barrel
end

-- Explosión (barril que llega, cristal roto): solo se ve, no empuja ni rompe nada.
function WorldBossFx.boom(at: Vector3)
	local blast = Instance.new("Explosion")
	blast.Position = at
	blast.BlastPressure = 0
	blast.BlastRadius = 0
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = getFolder()
	splash(at, Color3.fromRGB(150, 255, 120), 6)
	shakeFrom(at, 0.8, 90)
end

local function bossBody(): BasePart?
	for _, item in CollectionService:GetTagged("WorldBossTarget") do
		if item:IsA("BasePart") and item:GetAttribute("Kind") == "king" then
			return item
		end
	end
	return nil
end

-- Burbuja del escudo y estrellas del aturdido, siguiendo al rey (un bucle mientras haga falta).
local watching = false
local function watchBoss()
	if watching then
		return
	end
	watching = true
	add(function(now, serverNow)
		local body = bossBody()
		local shielded = body ~= nil and body:GetAttribute("Shield") == true
		local stunned = body ~= nil and (body:GetAttribute("Stunned") or 0) > serverNow
		if shielded and body then
			if not bubble then
				bubble = part("Shield", body.Size * 1.55, body.CFrame, SHIELD, Enum.Material.ForceField, Enum.PartType.Ball)
				bubble.Transparency = 0.1
			end
			local pulse = 1 + 0.03 * math.sin(now * 3)
			bubble.Size = Vector3.new(body.Size.X, body.Size.Y * 1.1, body.Size.Z) * 1.55 * pulse
			bubble.CFrame = CFrame.new(body.Position + Vector3.new(0, body.Size.Y * 0.1, 0))
		elseif bubble then
			bubble:Destroy()
			bubble = nil
		end
		if stunned and body then
			if #stars == 0 then
				for _ = 1, 4 do
					local star = part("Star", Vector3.new(1.6, 1.6, 0.6), body.CFrame, STAR, Enum.Material.SmoothPlastic)
					table.insert(stars, star)
				end
			end
			local top = body.Position + Vector3.new(0, body.Size.Y * 0.75, 0)
			for index, star in stars do
				local angle = now * 3 + index / #stars * math.pi * 2
				star.CFrame = CFrame.new(top + Vector3.new(math.cos(angle) * body.Size.X * 0.4, math.sin(now * 4 + index) * 0.8, math.sin(angle) * body.Size.X * 0.4)) * CFrame.Angles(0, -angle, math.rad(45))
			end
		elseif #stars > 0 then
			for _, star in stars do
				star:Destroy()
			end
			table.clear(stars)
		end
		if not body then
			watching = false
			return false
		end
		return true
	end)
end

-- Portal del hub: chispas y luz que late mientras está abierto.
local function dressPortal(disk: Instance)
	if not disk:IsA("BasePart") then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 160, 255), Color3.fromRGB(120, 220, 255))
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Parent = disk
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 140, 255)
	light.Range = 20
	light.Brightness = 0
	light.Parent = disk
	local function refresh()
		local open = disk:GetAttribute("Open") == true
		emitter.Rate = if open and not Performance.get() then 30 else 0
		light.Brightness = if open then 2 else 0
	end
	disk:GetAttributeChangedSignal("Open"):Connect(refresh)
	refresh()
end

-- Algo de la arena del rey acaba de aparecer: si es el rey, se vigila su escudo y su aturdido.
local function onTarget(item: Instance)
	if item:GetAttribute("Kind") == "king" then
		watchBoss()
	end
end

-- Cristales de las columnas de la arena: giran despacio y suben y bajan (solo estando en la arena).
local function animateCrystals()
	local crystals = {}
	local function track(item: Instance)
		if item:IsA("BasePart") then
			table.insert(crystals, { part = item, base = item.CFrame, phase = rng:NextNumber(0, 6) })
		end
	end
	for _, item in CollectionService:GetTagged("WorldBossCrystalGlow") do
		track(item)
	end
	CollectionService:GetInstanceAddedSignal("WorldBossCrystalGlow"):Connect(track)
	RunService.Heartbeat:Connect(function()
		if player:GetAttribute("WorldBoss") ~= true or #crystals == 0 then
			return
		end
		local now = os.clock()
		local parts, frames = {}, {}
		for _, crystal in crystals do
			table.insert(parts, crystal.part)
			table.insert(frames, crystal.base * CFrame.new(0, math.sin(now * 1.5 + crystal.phase) * 0.8, 0) * CFrame.Angles(0, now * 0.6, 0))
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

function WorldBossFx.start()
	for _, disk in CollectionService:GetTagged("WorldBossPortal") do
		dressPortal(disk)
	end
	CollectionService:GetInstanceAddedSignal("WorldBossPortal"):Connect(dressPortal)
	for _, item in CollectionService:GetTagged("WorldBossTarget") do
		onTarget(item)
	end
	CollectionService:GetInstanceAddedSignal("WorldBossTarget"):Connect(onTarget)
	animateCrystals()
end

return WorldBossFx
