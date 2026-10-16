-- Slimes: el cuerpo de slime de cada enemigo de mazmorra (pedido por el usuario: slimes de verdad, animados, con rastro
-- de líquido y ataque con su animación). El servidor (server/Dungeons) solo deja la caja física, invisible, con la
-- etiqueta Enemy y los atributos Kind (grunt, brute, boss), Look (adornos separados por comas), HP, NextAttack,
-- AttackAt y Victim. Aquí cada cliente le pone su cuerpo (piel translúcida con núcleo, burbujas y brillo, ojos que
-- miran y parpadean, boca y los adornos de client/SlimeLooks, con el color de su zona) y lo anima en un solo bucle que
-- solo vive mientras hay slimes, charcos o slimes muriendo:
--   * anda a saltos (más bajos y pesados cuanto más grande): se estira en el aire, se aplasta al caer y cada caída deja
--     un charco que se desvanece solo (MAX_PUDDLES a la vez);
--   * tiembla y se pone blanco al recibir un golpe (baja su HP);
--   * cuando ya puede volver a pegar (NextAttack) y tiene a alguien a tiro, se agacha temblando, se pone rojizo y abre
--     la boca; al pegar (AttackAt) se lanza hacia quien recibe el golpe (Victim) y salpica;
--   * al morir se aplasta en un charco grande y sus ojos y adornos saltan con unas gotas.
-- Todo es visual: cuándo pega, cuánto y adónde va lo decide el servidor. Solo se anima lo que está a VIEW studs de la
-- cámara (lo demás se esconde); en modo Rendimiento, sin núcleo, burbujas, brillos, charcos ni gotas.
-- Pendiente: sonidos de chapoteo al caer y de ataque (no hay audios todavía).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Performance = require(script.Parent.Performance)
local Shards = require(script.Parent.Shards)
local SlimeLooks = require(script.Parent.SlimeLooks)

local Slimes = {}

local VIEW = 220 -- studs desde la cámara: más lejos no se anima ni se ve
local WINDUP = 0.45 -- segundos antes de poder pegar en los que ya se agacha (si tiene a alguien a tiro)
local LUNGE = 0.45 -- lo que dura el salto del ataque
local LUNGE_PEAK = 0.32 -- parte del salto en la que llega a quien muerde
local SPAWN = 0.5 -- lo que tarda en salir del charco al aparecer
local DEATH = 0.5 -- lo que tarda en aplastarse al morir
local PUDDLE_LIFE = 3.2 -- segundos que dura un charco del rastro
local BIG_PUDDLE_LIFE = 5.5 -- el de morir
local MAX_PUDDLES = 70
local PUDDLE_ALPHA = 0.45 -- transparencia de un charco recién hecho
local MAX_DROPS = 40 -- gotas volando a la vez
local SKIN_ALPHA = 0.2 -- transparencia de la piel (deja ver el núcleo y las burbujas)
local WHITE = Color3.new(1, 1, 1)
local ANGRY = Color3.fromRGB(255, 70, 60)

-- Cómo se mueve cada tipo: altura del salto (en veces su alto), largo de cada salto (en veces su ancho), muelle de
-- la gelatina (rigidez y freno: menos = más blando y lento), si lleva cejas y colmillos y si cae con estruendo.
local KINDS = {
	grunt = { hop = 0.3, stride = 1.5, stiff = 210, damp = 10, land = 3.2 },
	brute = { hop = 0.2, stride = 1.1, stiff = 150, damp = 9, land = 4, angry = true },
	boss = { hop = 0.13, stride = 0.95, stiff = 105, damp = 7, land = 4.6, angry = true, heavy = true },
	-- El Jefe del mundo (server/WorldBoss): no anda; cae del cielo (Fall), salta en el sitio al atacar (Slam), se infla al
	-- cargar el súper golpe (ChargeFrom/ChargeTo) y se tambalea aturdido (Stunned). Todo son horas del servidor.
	king = { hop = 0.08, stride = 1, stiff = 70, damp = 6, land = 6, angry = true, heavy = true },
}
local SLAM = 0.9 -- lo que dura el salto en el sitio del rey
local CHARGE_TINT = Color3.fromRGB(255, 70, 30)
local STUN_TINT = Color3.fromRGB(255, 235, 120)

local folder: Folder? = nil
local slimes = {} -- [caja] = slime
local dying = {} -- slimes muriendo
local puddles = {} -- { part, mesh, born, life }
local spare = {} -- charcos para reutilizar
local drops = 0
local layer = 0 -- cada charco un pelín más alto que el anterior, para que no parpadeen al pisarse
local roots: { Vector3 } = {} -- dónde están los personajes este fotograma
local loop: RBXScriptConnection? = nil
local rng = Random.new()

local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Slimes"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- Pieza de adorno: anclada, sin choque ni rayos. forma "ball" = elipsoide del tamaño de la pieza.
local function piece(name: string, size: Vector3, color: Color3, material: Enum.Material?, form: string?): (BasePart, SpecialMesh?)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	local mesh: SpecialMesh? = nil
	if form == "ball" then
		mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif form == "cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
	return part, mesh
end

-- La forma del cuerpo: un elipsoide con el centro a 0,42 de su alto, así que por debajo del suelo queda un trozo y se
-- ve una cúpula de base ancha. Coordenadas del slime: origen en el suelo bajo su centro, Y arriba, cara hacia -Z.
local function shape(size: Vector3)
	local a, b, c = size.X / 2, size.Y * 0.6, size.Z / 2
	local yc = size.Y * 0.42
	local s = { a = a, b = b, c = c, yc = yc }
	local function normal(p: Vector3): Vector3
		local n = Vector3.new(p.X / (a * a), (p.Y - yc) / (b * b), p.Z / (c * c))
		return if n.Magnitude > 1e-6 then n.Unit else Vector3.yAxis
	end
	function s.top(x: number, z: number): number
		return yc + b * math.sqrt(math.max(0, 1 - (x / a) ^ 2 - (z / c) ^ 2))
	end
	function s.front(x: number, y: number): number
		return -c * math.sqrt(math.max(0, 1 - (x / a) ^ 2 - ((y - yc) / b) ^ 2))
	end
	function s.on(x: number, y: number?, z: number): CFrame
		local p = Vector3.new(x, y or s.top(x, z), z)
		local up = normal(p)
		local right = up:Cross(Vector3.zAxis)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
		return CFrame.fromMatrix(p, right, up)
	end
	function s.face(x: number, y: number, out: number): CFrame
		local p = Vector3.new(x, y, s.front(x, y))
		return CFrame.lookAt(p, p + normal(p)) * CFrame.new(0, 0, -out)
	end
	s.eye = { x = size.X * 0.2, y = yc + b * 0.3, w = size.X * 0.21, h = size.X * 0.27 }
	return s
end

local function ensureLoop()
	if not loop then
		loop = RunService.RenderStepped:Connect(Slimes.step)
	end
end

-- Charco que se desvanece solo. Con MAX_PUDDLES ya puestos se reutiliza el más viejo.
local function puddle(position: Vector3, width: number, color: Color3, life: number)
	if Performance.get() then
		return
	end
	local entry
	if #puddles >= MAX_PUDDLES then
		entry = table.remove(puddles, 1)
	else
		entry = table.remove(spare)
		if not entry then
			local part, mesh = piece("Puddle", Vector3.one, color, Enum.Material.SmoothPlastic, "ball")
			part.Reflectance = 0.25
			entry = { part = part, mesh = mesh }
		end
	end
	layer = (layer + 1) % 25
	local part = entry.part
	part.Size = Vector3.new(width, 0.16, width * rng:NextNumber(0.75, 0.95))
	part.Color = color:Lerp(WHITE, 0.1)
	part.Transparency = PUDDLE_ALPHA
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.02 + layer * 0.004, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	entry.mesh.Scale = Vector3.new(0.3, 1, 0.3)
	part.Parent = getFolder()
	entry.born = os.clock()
	entry.life = life
	table.insert(puddles, entry)
	ensureLoop()
end

-- Gotas que salen volando y caen (client/Shards las mueve).
local function splash(position: Vector3, ground: number, color: Color3, count: number, force: number, size: number)
	if Performance.get() then
		return
	end
	for _ = 1, count do
		if drops >= MAX_DROPS then
			return
		end
		drops += 1
		local drop = piece("Drop", Vector3.one * size * rng:NextNumber(0.6, 1.2), color, Enum.Material.SmoothPlastic, "ball")
		drop.Transparency = 0.15
		drop.Reflectance = 0.1
		drop.CFrame = CFrame.new(position)
		drop.Parent = getFolder()
		local turn = rng:NextNumber(0, math.pi * 2)
		local push = force * rng:NextNumber(0.4, 1)
		Shards.launch(drop, Vector3.new(math.cos(turn) * push, force * rng:NextNumber(0.7, 1.3), math.sin(turn) * push), Vector3.zero, ground)
		task.delay(rng:NextNumber(0.6, 0.9), function()
			drop:Destroy()
			drops -= 1
		end)
	end
end

-- Arma el cuerpo de un slime para esa caja. Cada pieza es un "item": { part, rest (CFrame en coordenadas del slime),
-- mesh?, deform (si su malla se estira con el cuerpo), base y extra (escala de la malla) }.
local function build(box: BasePart)
	local size = box.Size
	local kindName = box:GetAttribute("Kind")
	local kind = KINDS[kindName] or KINDS.grunt
	local def = Config.Enemies[kindName] or Config.Enemies.grunt
	local color = box.Color
	local light = Performance.get()
	local s = shape(size)
	local model = Instance.new("Model")
	model.Name = box.Name

	local slime = {
		box = box, size = size, kind = kind, range = def.attackRange, color = color, s = s, model = model,
		items = {}, parts = {}, frames = {}, skins = {}, bubbles = {},
		hp = box:GetAttribute("HP") or 0, born = os.clock(), yaw = 0, speed = 0, phase = 0,
		squash = 0, squashV = 0, lean = 0, leanV = 0, roll = 0, rollV = 0, wind = 0, flash = 0, tinted = false,
		blinkAt = os.clock() + rng:NextNumber(1, 3), blinkStart = -1, connections = {},
	}
	local look = box.CFrame.LookVector
	slime.yaw = math.atan2(-look.X, -look.Z)

	local function item(part: BasePart, rest: CFrame, mesh: SpecialMesh?, deform: boolean?): any
		local entry = { part = part, rest = rest, mesh = mesh, deform = deform and mesh ~= nil, base = Vector3.one, extra = Vector3.one }
		part.Parent = model
		table.insert(slime.items, entry)
		table.insert(slime.parts, part)
		table.insert(slime.frames, CFrame.identity)
		return entry
	end
	-- Pieza que se estira con el cuerpo (piel, cara).
	local function soft(name: string, partSize: Vector3, rest: CFrame, tint: Color3, alpha: number?, material: Enum.Material?)
		local part, mesh = piece(name, partSize, tint, material, "ball")
		part.Transparency = alpha or 0
		return item(part, rest, mesh, true), part
	end

	-- Cuerpo: base que se desparrama por el suelo, piel translúcida y núcleo más oscuro dentro.
	local foot, footPart = soft("Foot", Vector3.new(size.X * 0.95, size.Y * 0.3, size.Z * 0.95), CFrame.new(0, size.Y * 0.03, 0), color)
	footPart.Reflectance = 0.1
	slime.foot = foot
	local skin, skinPart = soft("Skin", Vector3.new(s.a * 2, s.b * 2, s.c * 2), CFrame.new(0, s.yc, 0), color, SKIN_ALPHA)
	skinPart.Reflectance = 0.1
	skinPart.CastShadow = true
	table.insert(slime.skins, { part = skinPart, color = color })
	table.insert(slime.skins, { part = foot.part, color = foot.part.Color })
	slime.skin = skin
	if not light then
		local core = soft("Core", Vector3.new(s.a * 1.15, s.b * 1.1, s.c * 1.15), CFrame.new(0, s.yc * 0.9, 0), color:Lerp(Color3.new(0, 0, 0), 0.3), 0.5)
		table.insert(slime.skins, { part = core.part, color = core.part.Color })
		-- Burbujas que suben por dentro.
		for index = 1, 3 do
			local bubble = piece("Bubble", Vector3.one * size.X * rng:NextNumber(0.07, 0.11), color:Lerp(WHITE, 0.6), nil, "ball")
			bubble.Transparency = 0.4
			local entry = item(bubble, CFrame.identity)
			table.insert(slime.bubbles, { item = entry, phase = index / 3, x = 0, z = 0, speed = rng:NextNumber(0.25, 0.45) })
		end
		-- Brillo de mojado arriba a un lado.
		soft("Shine", Vector3.new(size.X * 0.17, size.Y * 0.1, 0.08), s.face(s.a * 0.38, s.yc + s.b * 0.62, 0) * CFrame.Angles(0, 0, math.rad(35)), WHITE, 0.25)
		soft("Shine", Vector3.new(size.X * 0.06, size.X * 0.06, 0.06), s.face(s.a * 0.6, s.yc + s.b * 0.36, 0), WHITE, 0.3)
	end

	-- Cara: ojos (blanco, pupila y destello), boca y, los fuertes, cejas de enfado y colmillos; los pequeños, colorete.
	local eye = s.eye
	local width = if kind.angry then 0.88 else 1
	slime.eyes = {}
	for _, side in { -1, 1 } do
		local frame = s.face(side * eye.x, eye.y, 0)
		local white = soft("Eye", Vector3.new(eye.w * width, eye.h * width, 0.14), frame * CFrame.new(0, 0, -0.03), WHITE)
		local pupil = soft("Pupil", Vector3.new(eye.w * 0.5 * width, eye.h * 0.56 * width, 0.1), frame * CFrame.new(0, 0, -0.08), Color3.fromRGB(20, 16, 24))
		local glint = if light then nil else soft("Glint", Vector3.new(eye.w * 0.2, eye.w * 0.2, 0.06), frame * CFrame.new(0, 0, -0.12), WHITE)
		table.insert(slime.eyes, { frame = frame, white = white, pupil = pupil, glint = glint, w = eye.w * width, h = eye.h * width })
		if kind.angry then
			local brow = piece("Brow", Vector3.new(eye.w * 1.2, eye.h * 0.2, 0.14), color:Lerp(Color3.new(0, 0, 0), 0.7))
			item(brow, s.face(side * eye.x, eye.y + eye.h * 0.62, 0.02) * CFrame.Angles(0, 0, math.rad(side * 22)))
		elseif not light then
			soft("Blush", Vector3.new(eye.w * 0.7, eye.h * 0.32, 0.06), s.face(side * size.X * 0.34, s.yc + s.b * 0.08, 0.01), color:Lerp(Color3.fromRGB(255, 120, 150), 0.6), 0.35)
		end
	end
	local mouthY = s.yc + s.b * 0.04
	slime.mouth = soft("Mouth", Vector3.new(size.X * 0.2, size.X * 0.06, 0.1), s.face(0, mouthY, 0.02), Color3.fromRGB(55, 14, 26))
	if kind.angry then
		for _, side in { -1, 1 } do
			soft("Fang", Vector3.new(size.X * 0.05, size.X * 0.09, 0.08), s.face(side * size.X * 0.065, mouthY - size.X * 0.045, 0.05), WHITE)
		end
	end

	-- Adornos de su zona (cuernos, corona, capucha...).
	SlimeLooks.build(box:GetAttribute("Look"), function(name, partSize, rest, tint, material, form)
		local part, mesh = piece(name, partSize, tint, material, form)
		item(part, rest, mesh, false)
		return part
	end, size, color, s)

	-- El rey que cae del cielo no sale de un charco.
	if box:GetAttribute("Fall") then
		slime.born = os.clock() - SPAWN
		slime.falling = true
	end

	-- Golpes (le baja la vida) y ataques (el servidor apunta la hora y a quién).
	table.insert(slime.connections, box:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = box:GetAttribute("HP") or 0
		if hp < slime.hp then
			slime.flash = 1
			slime.squashV += 5
			slime.leanV -= 3
			slime.rollV += rng:NextNumber(-5, 5)
		end
		slime.hp = hp
	end))
	-- El rey del Jefe del mundo no tiene vida: cuenta sus golpes en "Hits". Le pegan todos a la vez: un blanco más
	-- flojo, o se quedaría blanco todo el rato.
	table.insert(slime.connections, box:GetAttributeChangedSignal("Hits"):Connect(function()
		slime.flash = math.max(slime.flash, 0.4)
		slime.squashV += 3
		slime.rollV += rng:NextNumber(-3, 3)
	end))
	table.insert(slime.connections, box:GetAttributeChangedSignal("AttackAt"):Connect(function()
		local at = box:GetAttribute("AttackAt")
		local late = if at then workspace:GetServerTimeNow() - at else math.huge
		if late > LUNGE * LUNGE_PEAK then
			return -- llega tarde: ya no da tiempo a morder a la vez que el golpe
		end
		local victim = Players:GetPlayerByUserId(box:GetAttribute("Victim") or 0)
		local character = victim and victim.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local offset = if root then root.Position - box.Position else box.CFrame.LookVector * (size.X / 2 + 2)
		local flat = Vector3.new(offset.X, 0, offset.Z)
		slime.attack = os.clock() - math.max(late, 0)
		slime.struck = false
		slime.lungeDir = if flat.Magnitude > 0.1 then flat.Unit else box.CFrame.LookVector
		slime.lungeReach = math.clamp(flat.Magnitude - size.X / 2 - 0.4, 0.5, def.attackRange + 1.5)
	end))

	model.Parent = getFolder()
	slimes[box] = slime
	-- Sale de un charco.
	if not slime.falling then
		puddle(box.Position - Vector3.new(0, size.Y / 2, 0), size.X * 1.3, color, PUDDLE_LIFE)
	end
	ensureLoop()
end

local function clear(slime)
	for _, connection in slime.connections do
		connection:Disconnect()
	end
	slime.model:Destroy()
end

-- Cae de un salto: se aplasta, deja su charco y, los grandes, salpican.
local function land(slime, ground: Vector3)
	local size = slime.size
	slime.squashV += slime.kind.land
	puddle(ground, size.X * rng:NextNumber(0.75, 0.95), slime.color, PUDDLE_LIFE)
	if slime.kind.heavy then
		splash(ground + Vector3.new(0, 0.5, 0), ground.Y, slime.color, 4, 14, size.X * 0.06)
	end
end

local function angleTo(target: number, current: number): number
	return (target - current + math.pi) % (math.pi * 2) - math.pi
end

-- Coloca todas las piezas: R es dónde está y cómo se inclina; (sx, sy, sz) cuánto se estira desde el suelo.
local function place(slime, root: CFrame, sx: number, sy: number, sz: number)
	local stretch = Vector3.new(sx, sy, sz)
	local frames = slime.frames
	for index, entry in slime.items do
		local rest = entry.rest
		local p = rest.Position
		frames[index] = root * CFrame.new(p.X * sx, p.Y * sy, p.Z * sz) * rest.Rotation
		if entry.deform then
			entry.mesh.Scale = entry.base * stretch * entry.extra
		end
	end
	workspace:BulkMoveTo(slime.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function tint(slime, toward: Color3?, amount: number)
	if amount > 0.01 and toward then
		for _, skin in slime.skins do
			skin.part.Color = skin.color:Lerp(toward, amount)
		end
		slime.tinted = true
	elseif slime.tinted then
		for _, skin in slime.skins do
			skin.part.Color = skin.color
		end
		slime.tinted = false
	end
end

local function update(slime, dt: number, now: number, serverNow: number, camera: Vector3)
	local box = slime.box
	local size = slime.size
	local kind = slime.kind
	local boxCFrame = box.CFrame
	local ground = boxCFrame.Position - Vector3.new(0, size.Y / 2, 0)

	-- Lejos de la cámara ni se ve ni se anima.
	local visible = (ground - camera).Magnitude < VIEW
	if visible ~= (slime.model.Parent ~= nil) then
		slime.model.Parent = if visible then getFolder() else nil
	end
	slime.visible = visible
	if not visible then
		return
	end

	-- Velocidad y rumbo (la caja ya mira a su objetivo: el servidor la gira).
	local velocity = box.AssemblyLinearVelocity
	slime.speed += (Vector3.new(velocity.X, 0, velocity.Z).Magnitude - slime.speed) * math.min(1, dt * 10)
	local look = boxCFrame.LookVector
	slime.yaw += angleTo(math.atan2(-look.X, -look.Z), slime.yaw) * math.min(1, dt * 12)

	-- A saltos: cada salto avanza su largo; al acabar uno cae (y si se ha parado, termina el que llevaba).
	local moving = slime.speed > 1.5
	local air = 0
	if moving or slime.phase > 0 then
		slime.phase += dt * math.max(slime.speed, 8) / (size.X * kind.stride)
		if slime.phase >= 1 then
			slime.phase = if moving then slime.phase % 1 else 0
			land(slime, ground)
		end
		air = math.sin(math.pi * slime.phase)
	end

	-- Quién está más cerca: a por él miran los ojos y, si está a tiro y ya puede pegar, se prepara.
	local nearest, gap = nil, math.huge
	for _, position in roots do
		local offset = position - ground
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude - size.X / 2 - 1
		if distance < gap then
			nearest, gap = position, distance
		end
	end
	local ready = serverNow >= (box:GetAttribute("NextAttack") or math.huge) - WINDUP
	local wind = if ready and gap <= slime.range + 0.5 and not slime.attack then 1 else 0
	slime.wind += (wind - slime.wind) * math.min(1, dt * 9)

	-- Ataque: salta hacia quien muerde, llega en LUNGE_PEAK y vuelve.
	local reach, lift, stretch, bite = 0, 0, 0, 0
	if slime.attack then
		local u = (now - slime.attack) / LUNGE
		if u >= 1 then
			slime.attack = nil
		else
			local e = if u < LUNGE_PEAK then math.sin(u / LUNGE_PEAK * math.pi / 2) else math.cos((u - LUNGE_PEAK) / (1 - LUNGE_PEAK) * math.pi / 2)
			reach = slime.lungeReach * e
			lift = size.Y * 0.2 * math.sin(math.min(u / (LUNGE_PEAK * 1.6), 1) * math.pi)
			stretch = (if u < LUNGE_PEAK then 0.35 else 0.08) * e
			bite = e
			if u >= LUNGE_PEAK and not slime.struck then
				slime.struck = true
				slime.squashV += kind.land * 1.3
				local at = ground + slime.lungeDir * (reach + size.X * 0.45)
				puddle(at, size.X * 0.9, slime.color, PUDDLE_LIFE)
				splash(at + Vector3.new(0, size.Y * 0.4, 0), ground.Y, slime.color, if kind.heavy then 7 else 4, 16, size.X * 0.06)
			end
		end
	end

	-- Rey: caída del cielo, salto en el sitio, carga y aturdido.
	local drop, grown, special, specialTint = 0, 1, 0, nil
	if kind == KINDS.king then
		local fall = box:GetAttribute("Fall")
		if fall and serverNow < fall then
			local u = 1 - math.clamp((fall - serverNow) / Config.WorldBoss.FallTime, 0, 1)
			drop = Config.WorldBoss.FallHeight * (1 - u * u)
			stretch = math.max(stretch, 0.25)
		elseif slime.falling then
			slime.falling = false
			slime.squashV += kind.land * 2.5
			puddle(ground, size.X * 2, slime.color, BIG_PUDDLE_LIFE)
			splash(ground + Vector3.new(0, size.Y * 0.3, 0), ground.Y, slime.color, 18, 26, size.X * 0.06)
		end
		local slam = box:GetAttribute("Slam")
		if slam then
			local u = (serverNow - slam) / SLAM
			if u >= 0 and u < 1 then
				lift += size.Y * 0.45 * math.sin(math.pi * u)
				stretch = math.max(stretch, 0.2 * math.sin(math.pi * u))
			elseif u >= 1 and slime.slammed ~= slam then
				slime.slammed = slam
				land(slime, ground)
				slime.squashV += kind.land
			end
		end
		local from, to = box:GetAttribute("ChargeFrom"), box:GetAttribute("ChargeTo")
		if from and to and serverNow >= from and serverNow < to then
			local p = (serverNow - from) / math.max(to - from, 0.1)
			grown = 1 + 0.22 * p
			special = (0.2 + 0.35 * p) * (0.6 + 0.4 * math.sin(now * (6 + 14 * p)))
			specialTint = CHARGE_TINT
		else
			local stunned = box:GetAttribute("Stunned")
			if stunned and serverNow < stunned then
				slime.roll = math.sin(now * 5) * 0.16
				slime.rollV = 0
				special = 0.15
				specialTint = STUN_TINT
				slime.dizzy = true
			else
				slime.dizzy = false
			end
		end
	end

	-- Muelles de la gelatina: aplastado (+) o estirado (-), inclinación adelante (+) / atrás y bamboleo de lado.
	local breathe = if moving then 0 else math.sin(now * 2.6 + slime.born) * 0.035
	local squashTarget = -0.15 * air + breathe + 0.26 * slime.wind
	slime.squashV += (-kind.stiff * (slime.squash - squashTarget) - kind.damp * slime.squashV) * dt
	slime.squash = math.clamp(slime.squash + slime.squashV * dt, -0.5, 0.7)
	local leanTarget = (if moving then 0.1 else 0) - 0.16 * slime.wind + 0.3 * bite
	slime.leanV += (-90 * (slime.lean - leanTarget) - 8 * slime.leanV) * dt
	slime.lean += slime.leanV * dt
	slime.rollV += (-130 * slime.roll - 6 * slime.rollV) * dt
	slime.roll += slime.rollV * dt
	slime.flash = math.max(0, slime.flash - dt * 6)

	-- Aparece creciendo desde el charco, con rebote.
	local grow = 1
	local age = (now - slime.born) / SPAWN
	if age < 1 then
		local t = age - 1
		grow = math.max(0.01, 1 + 2.7 * t ^ 3 + 1.7 * t ^ 2)
	end

	grow *= grown
	local squash = slime.squash
	local sx = (1 + 0.5 * squash) * (1 - 0.25 * stretch) * grow
	local sy = (1 - squash) * (1 - 0.15 * stretch) * grow
	local sz = (1 + 0.5 * squash) * (1 + stretch) * grow
	local tremble = if slime.wind > 0.05 then Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * size.X * 0.025 * slime.wind else Vector3.zero
	local position = ground + Vector3.new(0, size.Y * kind.hop * air + lift + drop, 0) + (if slime.lungeDir then slime.lungeDir * reach else Vector3.zero) + tremble
	local root = CFrame.new(position) * CFrame.Angles(0, slime.yaw, 0) * CFrame.Angles(-slime.lean, 0, slime.roll)

	-- La base solo se desparrama apoyada en el suelo.
	local off = math.max(air * 0.8, math.min(lift / (size.Y * 0.2), 1))
	slime.foot.extra = Vector3.one * (1 - 0.75 * off) -- en el aire se mete dentro del cuerpo

	-- Cara: parpadeo, ojos entrecerrados al prepararse y muy abiertos al morder, pupilas hacia el más cercano.
	if now >= slime.blinkAt then
		slime.blinkStart = now
		slime.blinkAt = now + rng:NextNumber(1.8, 4.5)
	end
	local blink = now - slime.blinkStart
	local open = (if blink < 0.14 then 1 - 0.9 * math.sin(blink / 0.14 * math.pi) else 1) * (1 - 0.4 * slime.wind) * (1 + 0.15 * bite) * (if slime.dizzy then 0.3 else 1)
	local lookAt = if nearest then root:PointToObjectSpace(nearest) else Vector3.new(0, size.Y * 0.6, -10)
	for _, eye in slime.eyes do
		local ox = math.clamp(lookAt.X / 14, -1, 1) * eye.w * 0.18
		local oy = math.clamp((lookAt.Y - slime.s.eye.y) / 14, -1, 1) * eye.h * 0.16
		eye.white.extra = Vector3.new(1, open, 1)
		eye.pupil.rest = eye.frame * CFrame.new(ox, oy, -0.08)
		eye.pupil.extra = Vector3.new(1, math.min(open * 1.2, 1), 1)
		if eye.glint then
			eye.glint.rest = eye.frame * CFrame.new(ox - eye.w * 0.1, oy + eye.h * 0.13, -0.12)
			eye.glint.extra = Vector3.new(1, math.min(open * 1.2, 1), 1)
		end
	end
	local mouth = math.max(slime.wind * 0.45, bite, slime.flash * 0.4)
	slime.mouth.extra = Vector3.new(1 - 0.2 * mouth, 1 + 2.6 * mouth, 1)

	-- Burbujas: suben por dentro y vuelven a salir de abajo.
	local s = slime.s
	for _, bubble in slime.bubbles do
		bubble.phase += dt * bubble.speed
		if bubble.phase >= 1 then
			bubble.phase -= 1
			local turn = rng:NextNumber(0, math.pi * 2)
			local spread = rng:NextNumber(0, 0.45)
			bubble.x, bubble.z = math.cos(turn) * spread, math.sin(turn) * spread
		end
		local y = size.Y * (0.12 + 0.72 * bubble.phase)
		local radius = math.sqrt(math.max(0, 1 - ((y - s.yc) / s.b) ^ 2)) * 0.8
		local wobble = math.sin(now * 3 + bubble.speed * 20) * 0.08
		bubble.item.rest = CFrame.new((bubble.x + wobble) * s.a * radius, y, bubble.z * s.c * radius)
	end

	-- Blanco al recibir un golpe; rojizo y latiendo al prepararse.
	if slime.flash > 0.01 then
		tint(slime, WHITE, slime.flash * 0.75)
	elseif special > 0.01 then
		tint(slime, specialTint, special)
	elseif slime.wind > 0.05 then
		tint(slime, ANGRY, slime.wind * (0.18 + 0.12 * math.sin(now * 28)))
	else
		tint(slime, nil, 0)
	end

	slime.root = root
	slime.stretch = Vector3.new(sx, sy, sz)
	place(slime, root, sx, sy, sz)
end

-- Muere: los ojos y los adornos saltan, el cuerpo se aplasta en un charco grande y desaparece.
local function die(slime)
	for _, connection in slime.connections do
		connection:Disconnect()
	end
	if not slime.visible or not slime.root or Performance.get() then
		slime.model:Destroy()
		return
	end
	local size = slime.size
	local ground = slime.root.Position
	local keep, keepFrames = {}, {}
	for _, entry in slime.items do
		if entry.part.Name == "Skin" or entry.part.Name == "Foot" or entry.part.Name == "Core" then
			table.insert(keep, entry)
			table.insert(keepFrames, CFrame.identity)
		else
			local part = entry.part
			part.Parent = getFolder()
			local away = part.Position - ground
			local flat = Vector3.new(away.X, 0, away.Z)
			local out = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			Shards.launch(part, out * rng:NextNumber(6, 14) + Vector3.new(0, rng:NextNumber(14, 24), 0), Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)), ground.Y)
			task.delay(0.9, function()
				part:Destroy()
			end)
		end
	end
	slime.items = keep
	slime.parts = {}
	for _, entry in keep do
		table.insert(slime.parts, entry.part)
	end
	slime.frames = keepFrames
	slime.dying = os.clock()
	puddle(ground, size.X * 1.7, slime.color, BIG_PUDDLE_LIFE)
	splash(ground + Vector3.new(0, size.Y * 0.5, 0), ground.Y, slime.color, if slime.kind.heavy then 14 else 9, 20, size.X * 0.07)
	table.insert(dying, slime)
	ensureLoop()
end

local function updateDying(slime, now: number): boolean
	local t = (now - slime.dying) / DEATH
	if t >= 1 then
		slime.model:Destroy()
		return false
	end
	-- Se hincha un instante y se aplasta.
	local puff = if t < 0.15 then math.sin(t / 0.15 * math.pi) * 0.12 else 0
	local k = math.clamp((t - 0.1) / 0.9, 0, 1)
	k = k * k * (3 - 2 * k)
	local stretch = slime.stretch or Vector3.one
	local sxz = (1 + puff + 0.9 * k)
	local sy = (1 + puff) * (1 - 0.9 * k)
	for _, entry in slime.items do
		entry.part.Transparency = math.max(entry.part.Transparency, SKIN_ALPHA + (1 - SKIN_ALPHA) * k * k)
	end
	place(slime, CFrame.new(slime.root.Position) * slime.root.Rotation, stretch.X * sxz, stretch.Y * sy, stretch.Z * sxz)
	return true
end

function Slimes.step(dt: number)
	dt = math.min(dt, 1 / 30)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero

	table.clear(roots)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(roots, root.Position)
		end
	end

	for box, slime in slimes do
		if box.Parent then
			update(slime, dt, now, serverNow, cameraPosition)
		end
	end
	for index = #dying, 1, -1 do
		if not updateDying(dying[index], now) then
			table.remove(dying, index)
		end
	end
	for index = #puddles, 1, -1 do
		local entry = puddles[index]
		local age = now - entry.born
		local k = age / entry.life
		if k >= 1 then
			entry.part.Parent = nil
			table.remove(puddles, index)
			table.insert(spare, entry)
		else
			local spread = math.min(1, age / 0.18) * (1 - 0.2 * k)
			entry.mesh.Scale = Vector3.new(spread, 1, spread)
			local fade = math.clamp((k - 0.4) / 0.6, 0, 1)
			entry.part.Transparency = PUDDLE_ALPHA + (1 - PUDDLE_ALPHA) * fade * fade
		end
	end

	if not next(slimes) and #dying == 0 and #puddles == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function added(box: Instance)
	if box:IsA("BasePart") and not slimes[box] then
		build(box)
	end
end

local function removed(box: Instance)
	local slime = slimes[box]
	if slime then
		slimes[box] = nil
		die(slime)
	end
end

function Slimes.start()
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(added)
	CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(removed)
	for _, box in CollectionService:GetTagged("Enemy") do
		added(box)
	end
	-- Al cambiar el modo Rendimiento se rehacen con o sin sus detalles.
	Performance.Changed:Connect(function()
		for box, slime in slimes do
			clear(slime)
			slimes[box] = nil
			build(box)
		end
	end)
end

return Slimes
