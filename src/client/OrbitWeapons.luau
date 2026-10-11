-- Las armas equipadas de cada jugador, a la vista: giran a su alrededor y, cuando el servidor le pone objetivo (el
-- ObjectValue "AttackTarget" del jugador, server/Combat), se lanzan contra él: lo atraviesan justo cuando pegan, salen
-- por el otro lado, lo rondan y vuelven a lanzarse, cada una a su ritmo (pedido por el usuario: antes se quedaban
-- quietas a su lado y giraban para dar el toque). Al quedarse sin objetivo vuelven a girar alrededor del jugador.
-- Todo es local: cada cliente construye con SwordModel y mueve las de los jugadores que tiene cerca (lejos de la cámara
-- no existen, y en modo Rendimiento solo las propias y sin efectos).
--   · Cada pasada se adelanta al golpe: el cliente sabe cuándo llegan las armas (Config.Loadout.Travel, o Chain si
--     saltan solas) y cada cuánto pega cada una (Stats.weaponCooldown), así que el arma cruza el objetivo a la vez que
--     llega su aviso Hit. El aviso confirma la pasada y pone en hora la siguiente: un arma solo se adelanta mientras
--     sus golpes van llegando; si uno no llega, se queda rondando hasta el siguiente aviso.
--   · workspace.OrbitWeapons.<jugador>.Weapon<hueco>: el arma de cada hueco (atributos Owner y Lead: la principal, la
--     más rara, es la que lleva el aura del jugador de client/WeaponAura).
--   · Circle: el aro del círculo del jugador local (Config.Loadout.Radius), a la vista cuando hay algo que atacar cerca;
--     se pone rojo un momento al elegir algo que queda fuera. Marker: el aro que señala su objetivo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local ForgeScene = require(script.Parent.ForgeScene)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Targeting = require(script.Parent.Targeting)

local OrbitWeapons = {}

local player = Players.LocalPlayer
local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)

local FAR = 150 -- studs de la cámara desde los que las armas de un jugador no se construyen
local ORBIT_RADIUS = 4.6 -- radio de la órbita (las armas más grandes giran algo más lejos)
local ORBIT_SPEED = 1.4 -- radianes por segundo
local ORBIT_LIFT = 0.4 -- altura del centro del arma sobre el del personaje
local GROUND_GAP = 0.8 -- lo que se separa del suelo la punta de abajo de un arma larga
local BOB = 0.3 -- cuánto suben y bajan al flotar
local FOLLOW = 11 -- lo pegada que va el arma a su sitio en la órbita (más = más pegada)
local AIM_HOLD = 0.6 -- segundos que vale el objetivo que el jugador acaba de pedir mientras el servidor contesta
local FADE_FROM, FADE_FULL = 8, 3 -- studs de la cámara entre los que un arma propia se va volviendo translúcida
local FADE_MOST = 0.85 -- lo translúcida que llega a quedar
local AIM_LOW, AIM_HIGH = 1.5, 6 -- altura sobre el suelo por la que atraviesan, entre estas dos (el centro del objetivo si cabe)
local STANDOFF = 3.5 -- studs del borde del objetivo a los que esperan las armas entre dos pasadas
local LIFT = 1.5 -- y lo que suben allí sobre la altura por la que atraviesan
local PROWL = 2.2 -- radianes por segundo a los que rondan al objetivo mientras esperan
local LAG = 0.04 -- segundos que tarda de más en llegar el aviso de un golpe (la vuelta del servidor)
local STAGGER = 0.025 -- segundos entre las armas de una misma andanada, para que no crucen todas en el mismo instante
local FAST = 0.12 -- segundos del final de un lanzamiento en los que el arma ya va lanzada: estela y giro
local SNAP = 0.03 -- si el aviso llega antes que el arma, lo que tarda esta en acabar de cruzar
local QUICK = 0.07 -- duración de una pasada que no estaba prevista (llega un golpe sin haberla empezado)
local CONFIRM = 0.3 -- segundos tras cruzar en los que un aviso aún cuenta como el golpe de esa pasada
local TURN_FAST, TURN_SLOW = 45, 12 -- lo deprisa que el arma se encara: lanzada y rondando
local SAME_BLOW = 0.05 -- segundos: los avisos de un mismo golpe que da a varios (salpica) cuentan como uno
local CHECK = 0.25 -- cada cuántos segundos se mira si hay algo que atacar cerca (para enseñar el aro)
local CIRCLE_NEAR = 30 -- studs más allá del círculo desde los que ya se enseña el aro
local CIRCLE_COLOR = Color3.fromRGB(255, 255, 255)
local CIRCLE_DENIED = Color3.fromRGB(255, 80, 70)
local CIRCLE_FADE = 0.85 -- transparencia del aro en reposo
local DENIED_TIME = 0.4 -- segundos que se queda rojo
local MARKER_COLOR = Color3.fromRGB(255, 225, 100)
local FLAT = CFrame.Angles(math.rad(90), 0, 0) -- pone de pie el eje de un cilindro: aros tumbados en el suelo

-- Cómo vuela cada tipo de arma al atacar: `out` = segundos que tarda en salir por el otro lado del objetivo, `back` =
-- los que tarda en volver a lanzarse desde donde lo ronda, `turns` = vueltas que da en cada pasada (con `tumble`, de
-- cabeza, como un hacha lanzada; si no, sobre su eje, de punta) y `far` = lo lejos que sale, en veces la distancia a
-- la que esperan (la lanza, que atraviesa, sale más lejos).
local MOVES = {
	sword = { out = 0.1, back = 0.09, turns = 1, far = 1 },
	dual = { out = 0.07, back = 0.06, turns = 1, far = 0.9 },
	axe = { out = 0.13, back = 0.12, turns = 2, tumble = true, far = 1 },
	hammer = { out = 0.15, back = 0.14, turns = 1, tumble = true, far = 1 },
	spear = { out = 0.12, back = 0.09, turns = 0, far = 1.6 },
}

local folder: Folder
-- [Player] = { key, holder, phase, fresh, target, weapons = { arma } }. Cada arma lleva sus medidas (reach: de la
-- empuñadura a la punta; low; height; wide; length: la de Config), dónde va (frame: su centro, con la punta en +Y) y su
-- vuelo: mode ("orbit" girando, "in" lanzándose, "out" saliendo por el otro lado, "wait" rondando), from e inAt (de
-- dónde y cuándo se lanzó), cross (cuándo cruza), crossed (cuándo cruzó), dir (hacia dónde sale), angle y dist
-- (rondando), confirmed (ha llegado el golpe de esta pasada), planned (cuándo le toca la siguiente) y ready (cuándo
-- puede volver a pegar).
local rigs = {}
local dirty = {} -- [Player] = true: han cambiado sus armas y hay que mirar si se rehacen
local aimed: BasePart? = nil -- objetivo que el jugador local acaba de pedir
local aimedUntil = 0
local deniedUntil = 0
local circle: CylinderHandleAdornment
local marker: CylinderHandleAdornment
local circleShown = false
local checked = 0
local effects = {} -- destellos de las armas que salpican o atraviesan: { item, born, life, radius o size }

-- Esquinas de las piezas del arma, en el espacio de su empuñadura.
local function extents(handle: BasePart, model: Model): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local offset = handle.CFrame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = offset * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						low, high = low:Min(corner), high:Max(corner)
					end
				end
			end
		end
	end
	return low, high
end

-- Estela del arma lanzada: una raya de su color que siempre mira a la cámara (la del tajo de SwordModel va de la
-- base a la punta y, con el arma volando de punta, no dibuja nada).
local function streak(root: BasePart, center: Vector3, half: number, color: Color3): Trail
	local ends = {}
	for index, side in { 1, -1 } do
		local point = Instance.new("Attachment")
		point.Name = "Dash" .. index
		point.Position = center + Vector3.new(0, 0, half * side)
		point.Parent = root
		ends[index] = point
	end
	local trail = Instance.new("Trail")
	trail.Name = "DashTrail"
	trail.Attachment0 = ends[1]
	trail.Attachment1 = ends[2]
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color:Lerp(WHITE, 0.6), color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.15)
	trail.Lifetime = 0.16
	trail.LightEmission = 0.6
	trail.Enabled = false
	trail.Parent = root
	return trail
end

local function buildWeapon(owner: Player, slot: number, copy, parent: Instance, lead: boolean)
	local model = Instance.new("Model")
	model.Name = "Weapon" .. slot
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("Lead", lead)
	-- SwordModel las hace para la mano (piezas sueltas soldadas a la empuñadura): aquí la empuñadura va anclada y se
	-- mueve por código, y las demás la siguen.
	local handle = SwordModel.build(copy.sword, model, CFrame.identity, Permanent.scale(copy), false, copy.metal)
	local offHand = model:FindFirstChild("OffHand")
	local off = offHand and offHand:FindFirstChild("OffHandle") :: BasePart?
	for _, root in { handle, off } do
		root.Anchored = true
		root.CanQuery = false
		root.CanTouch = false
	end

	local low, high = extents(handle, model)
	local center = (low + high) / 2
	local wide = math.max(high.X - low.X, high.Z - low.Z) / 2
	local key, kind = Stats.kind(copy)
	local metal = Permanent.metal(copy)
	local color = if metal then metal.color else Config.Swords[copy.sword].color
	local toHandle = CFrame.new(-center)

	-- La estela del tajo (de la base a la punta) solo se ve en las que vuelan dando vueltas de cabeza, y más corta y
	-- tenue que en la mano; en las que van de punta barría una sábana blanca al girarse (visto en Studio), así que
	-- va invisible: se sigue encendiendo porque con ella suelta su ráfaga el aura (client/WeaponAura). Y, en cada
	-- hoja, la estela de ir lanzada.
	local move = MOVES[key] or MOVES.sword
	local trails = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Trail") and item.Name == "SwingTrail" then
			item.Lifetime = 0.1
			item.Transparency = NumberSequence.new(if move.tumble then 0.55 else 1, 1)
			table.insert(trails, item)
		end
	end
	for _, root in { handle, off } do
		table.insert(trails, streak(root, center, math.clamp(wide, 0.4, 1.1), color))
	end
	model.Parent = parent
	return {
		copy = copy,
		key = key,
		kind = kind,
		move = move,
		model = model,
		handle = handle,
		off = off,
		reach = math.max(high.Y, 1),
		low = low.Y,
		height = high.Y - low.Y,
		wide = wide,
		length = Config.Swords[copy.sword].bladeLength,
		color = color,
		toHandle = toHandle,
		-- En la órbita van de pie, algo vencidas hacia donde giran y hacia fuera (la lanza, más tumbada); las dobles,
		-- cruzadas en aspa. Atacando, las dobles van una a cada lado.
		lean = if off then CFrame.identity else CFrame.Angles(math.rad(if key == "spear" then -20 else -8), 0, math.rad(10)),
		orbitMain = CFrame.new(-0.18, 0, 0) * CFrame.Angles(math.rad(24), 0, 0) * toHandle,
		orbitOff = CFrame.new(0.18, 0, 0) * CFrame.Angles(math.rad(-24), 0, 0) * toHandle,
		gap = 0.9 * wide + 0.6,
		frame = CFrame.identity,
		mix = 0,
		spin = 0,
		heading = Vector3.yAxis,
		right = Vector3.xAxis,
		mode = "orbit",
		from = Vector3.zero,
		inAt = 0,
		cross = 0,
		crossed = 0,
		dir = Vector3.xAxis,
		angle = 0,
		dist = 0,
		confirmed = false,
		planned = nil :: number?,
		ready = 0,
		outTime = move.out,
		backTime = move.back,
		side = if slot % 2 == 0 then 1 else -1,
		lastHit = 0,
		trails = trails,
		dashing = false,
		faded = 0,
	}
end

local function destroy(owner: Player)
	local rig = rigs[owner]
	if rig then
		rigs[owner] = nil
		rig.holder:Destroy()
	end
end

-- Qué armas lleva: las que se ven (tipo, metal y tamaño de cada hueco) y sus copias.
local function loadout(owner: Player)
	local copies = Stats.loadout(owner)
	local parts = {}
	for slot, copy in copies do
		parts[slot] = `{copy.sword}:{copy.metal}:{copy.size}`
	end
	return table.concat(parts, ","), copies
end

-- Construye las armas del jugador, o las deja como están si siguen siendo las mismas.
local function build(owner: Player)
	local key, copies = loadout(owner)
	local rig = rigs[owner]
	if rig and rig.key == key then
		for slot, weapon in rig.weapons do
			weapon.copy = copies[slot] -- el rasgo o el grado pueden haber cambiado
		end
		return
	end
	destroy(owner)
	local holder = Instance.new("Model")
	holder.Name = owner.Name
	local lead, rarest = 1, 0
	for slot, copy in copies do
		local rarity = Stats.rarity(copy)
		if rarity > rarest then
			lead, rarest = slot, rarity
		end
	end
	local weapons = {}
	for slot, copy in copies do
		weapons[slot] = buildWeapon(owner, slot, copy, holder, slot == lead)
	end
	holder.Parent = folder
	rigs[owner] = { key = key, holder = holder, weapons = weapons, phase = (owner.UserId % 628) / 100, fresh = true, target = nil :: BasePart? }
end

-- Objetivo al que van las armas de ese jugador. El jugador local adelanta el que acaba de pedir mientras el servidor
-- contesta.
local function targetOf(owner: Player, now: number): BasePart?
	if owner == player and aimed and now < aimedUntil and aimed:IsDescendantOf(workspace) then
		return aimed
	end
	return Targeting.current(owner)
end

-- Sitio del arma en la órbita: su centro, mirando hacia donde gira.
local function orbitFrame(rig, weapon, index: number, count: number, root: BasePart, ground: number, now: number): CFrame
	local angle = now * ORBIT_SPEED + rig.phase + (index - 1) * TAU / count
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local along = Vector3.new(-out.Z, 0, out.X)
	local y = math.max(root.Position.Y + ORBIT_LIFT, ground + weapon.height / 2 + GROUND_GAP) + math.sin(now * 2.1 + index * 1.7) * BOB
	local center = Vector3.new(root.Position.X, y, root.Position.Z) + out * (ORBIT_RADIUS + weapon.wide)
	return CFrame.lookAt(center, center + along) * weapon.lean
end

-- Ataque -------------------------------------------------------------------------------------

-- Dónde va el arma con la punta (su +Y) hacia donde vuela y el filo de canto. Guarda hacia dónde tenía el costado
-- para no girar de golpe sobre sí misma al pasar por la vertical (al darse la vuelta por arriba).
local function facing(weapon, position: Vector3): CFrame
	local heading = weapon.heading
	local right = heading:Cross(Vector3.yAxis)
	if right.Magnitude > 0.05 then
		weapon.right = if right:Dot(weapon.right) < 0 then -right.Unit else right.Unit
	end
	local back = weapon.right:Cross(heading)
	back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zAxis
	return CFrame.fromMatrix(position, heading:Cross(back), heading, back)
end

-- Encara el arma hacia `toward`, poco a poco.
local function turn(weapon, toward: Vector3, rate: number, dt: number)
	if toward.Magnitude < 1e-3 then
		return
	end
	local goal = toward.Unit
	if weapon.heading:Dot(goal) < -0.9 then
		-- Justo de espaldas no hay camino por el medio: da la vuelta por arriba.
		goal = (goal + Vector3.yAxis).Unit
	end
	local blended = weapon.heading:Lerp(goal, 1 - math.exp(-rate * dt))
	weapon.heading = if blended.Magnitude > 1e-3 then blended.Unit else goal
end

-- El arma se lanza desde donde está para cruzar el objetivo en el instante `cross`.
local function launch(weapon, now: number, cross: number)
	weapon.mode = "in"
	weapon.from = weapon.frame.Position
	weapon.inAt = now
	weapon.cross = math.max(cross, now + SNAP)
	weapon.confirmed = false
	weapon.planned = nil
end

-- El objetivo de las armas ha cambiado: se lanzan todas a por el nuevo, o vuelven a girar si no hay.
local function retarget(rig, owner: Player, target: BasePart?, previous: BasePart?, now: number)
	local arrive = now
	if target then
		-- Lo que tardan en llegar: lo de un clic o, si han saltado solas porque el anterior ha caído, lo de un salto.
		local asked = owner == player and aimed == target
		local chained = not asked and previous ~= nil and not previous:IsDescendantOf(workspace)
		arrive += if chained then Config.Loadout.Chain else Config.Loadout.Travel
		if asked then
			arrive += math.min(player:GetNetworkPing() * 2, 0.2) -- la petición aún tiene que llegar al servidor
		end
	end
	for slot, weapon in rig.weapons do
		if target then
			if weapon.mode == "orbit" then
				weapon.heading, weapon.right = weapon.frame.UpVector, weapon.frame.RightVector
			end
			-- La que aún no puede pegar se lanza más tarde, cuando le toque.
			launch(weapon, now, math.max(arrive, weapon.ready) + LAG + (slot - 1) * STAGGER)
		else
			weapon.mode = "orbit"
			weapon.planned = nil
		end
	end
end

-- Mueve el arma en su ataque: deja en weapon.frame dónde va y en weapon.spin la vuelta que lleva dada (0 a 1).
-- Devuelve true mientras va lanzada.
local function fly(weapon, target: BasePart, ground: number, now: number, dt: number): boolean
	local center = target.Position
	local aim = Vector3.new(center.X, math.clamp(center.Y, ground + AIM_LOW, ground + AIM_HIGH), center.Z)
	local radius = math.max(target.Size.X, target.Size.Z) / 2 + STANDOFF + weapon.reach * 0.2
	local far = radius * weapon.move.far

	-- Le toca otra pasada: sale desde donde esté.
	if weapon.mode ~= "in" and weapon.planned and now >= weapon.planned - weapon.backTime then
		launch(weapon, now, weapon.planned)
	end
	if weapon.mode == "in" and now >= weapon.cross then
		local through = Vector3.new(aim.X - weapon.from.X, 0, aim.Z - weapon.from.Z)
		if through.Magnitude > 0.5 then
			weapon.dir = through.Unit
		end
		weapon.crossed = weapon.cross
		weapon.mode = "out"
	end
	if weapon.mode == "out" and now >= weapon.crossed + weapon.outTime then
		weapon.mode = "wait"
		weapon.angle = math.atan2(weapon.dir.Z, weapon.dir.X)
		weapon.dist = far
	end

	local position: Vector3
	if weapon.mode == "in" then
		-- Coge carrerilla despacio y sale disparada.
		local span = weapon.cross - weapon.inAt
		position = weapon.from:Lerp(aim, math.clamp((now - weapon.inAt) / span, 0, 1) ^ 3)
		turn(weapon, aim - weapon.from, TURN_FAST, dt)
		weapon.spin = 0.5 * math.clamp(1 - (weapon.cross - now) / math.min(span, FAST), 0, 1)
	elseif weapon.mode == "out" then
		-- Sale por el otro lado frenando.
		local t = (now - weapon.crossed) / weapon.outTime
		local eased = 1 - (1 - t) ^ 2
		position = aim + weapon.dir * (far * eased) + Vector3.new(0, LIFT * eased, 0)
		turn(weapon, weapon.dir, TURN_FAST, dt)
		weapon.spin = 0.5 + 0.5 * t
	else
		-- Ronda al objetivo, encarada a él, hasta la siguiente pasada.
		weapon.angle += weapon.side * PROWL * dt
		weapon.dist += (radius - weapon.dist) * (1 - math.exp(-6 * dt))
		local out = Vector3.new(math.cos(weapon.angle), 0, math.sin(weapon.angle))
		position = aim + out * weapon.dist + Vector3.new(0, LIFT + math.sin(now * 3 + weapon.angle) * 0.25, 0)
		turn(weapon, aim - position, TURN_SLOW, dt)
		weapon.spin = 0
	end
	weapon.frame = facing(weapon, position)
	return weapon.mode == "out" or (weapon.mode == "in" and weapon.cross - now < FAST)
end

-- Enciende o apaga las estelas del arma lanzada (en Rendimiento no se encienden).
local function setDash(weapon, on: boolean, lite: boolean)
	if weapon.dashing == on then
		return
	end
	weapon.dashing = on
	if on and lite then
		return
	end
	for _, trail in weapon.trails do
		trail.Enabled = on
	end
end

local function place(weapon)
	local angle = TAU * weapon.move.turns * weapon.spin
	local spin = if weapon.move.tumble then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, angle, 0)
	if weapon.off then
		local main = CFrame.new(-weapon.gap, 0, 0) * spin * weapon.toHandle
		local off = CFrame.new(weapon.gap, 0, 0) * spin:Inverse() * weapon.toHandle
		weapon.handle.CFrame = weapon.frame * weapon.orbitMain:Lerp(main, weapon.mix)
		weapon.off.CFrame = weapon.frame * weapon.orbitOff:Lerp(off, weapon.mix)
	else
		weapon.handle.CFrame = weapon.frame * spin * weapon.toHandle
	end
end

-- Las armas del jugador local pasan entre él y la cámara: cerca de ella se vuelven translúcidas para no tapar la vista
-- (se mide de la cámara a la línea del arma, que una lanza larga puede tener el centro lejos y la punta encima).
local function fade(weapon, eye: Vector3)
	local frame = weapon.handle.CFrame
	local along = frame.UpVector
	local nearest = frame.Position + along * math.clamp((eye - frame.Position):Dot(along), weapon.low, weapon.reach)
	local amount = math.clamp((FADE_FROM - (nearest - eye).Magnitude) / (FADE_FROM - FADE_FULL), 0, 1) * FADE_MOST
	amount = math.round(amount * 10) / 10 -- por pasos: solo se tocan las piezas cuando cambia
	if amount ~= weapon.faded then
		weapon.faded = amount
		for _, item in weapon.model:GetDescendants() do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = amount
			end
		end
	end
end

-- Lo que hay de la raíz del personaje al suelo.
local function standing(humanoid: Humanoid, root: BasePart): number
	return (if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight) + root.Size.Y / 2
end

local function stepRig(owner: Player, now: number, dt: number, eye: Vector3, lite: boolean)
	local character = owner.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local mine = owner == player
	local shown = root ~= nil
		and humanoid.Health > 0
		and owner:GetAttribute("Swords") ~= nil
		and (mine or not lite)
		and (root.Position - eye).Magnitude < FAR
		and not (mine and ForgeScene.isActive())
	if not shown then
		destroy(owner)
		return
	end
	if dirty[owner] or not rigs[owner] then
		dirty[owner] = nil
		build(owner)
	end
	local rig = rigs[owner]
	local ground = root.Position.Y - standing(humanoid, root)
	-- Recién hechas van primero a su sitio en la órbita; el objetivo, en la vuelta siguiente.
	local target = if rig.fresh then nil else targetOf(owner, now)
	if target ~= rig.target then
		retarget(rig, owner, target, rig.target, now)
		rig.target = target
	end
	local count = #rig.weapons
	local follow = 1 - math.exp(-FOLLOW * dt)
	local blend = 1 - math.exp(-20 * dt)
	for index, weapon in rig.weapons do
		if target and weapon.mode ~= "orbit" then
			setDash(weapon, fly(weapon, target, ground, now, dt), lite)
			weapon.mix += (1 - weapon.mix) * blend
		else
			local goal = orbitFrame(rig, weapon, index, count, root, ground, now)
			weapon.frame = if rig.fresh then goal else weapon.frame:Lerp(goal, follow)
			weapon.mix = if rig.fresh then 0 else weapon.mix * (1 - blend)
			weapon.spin = 0
			setDash(weapon, false, lite)
		end
		place(weapon)
		if mine then
			fade(weapon, eye)
		end
	end
	rig.fresh = false
end

-- Aros y destellos ---------------------------------------------------------------------------

local function ring(name: string, color: Color3): CylinderHandleAdornment
	local item = Instance.new("CylinderHandleAdornment")
	item.Name = name
	item.Adornee = workspace.Terrain
	item.Height = 0.06
	item.Color3 = color
	item.Visible = false
	item.Parent = folder
	return item
end

-- Destello de un golpe que salpica: un aro que se abre hasta donde llega.
local function splash(center: Vector3, radius: number, color: Color3)
	local item = ring("Splash", color:Lerp(WHITE, 0.4))
	item.CFrame = CFrame.new(center) * FLAT
	item.Visible = true
	table.insert(effects, { item = item, born = os.clock(), life = 0.3, radius = radius })
end

-- Destello de un golpe que atraviesa: una raya desde el objetivo hasta donde llega.
local function pierce(origin: CFrame, length: number, color: Color3)
	local item = Instance.new("BoxHandleAdornment")
	item.Name = "Pierce"
	item.Adornee = workspace.Terrain
	item.Color3 = color:Lerp(WHITE, 0.4)
	item.CFrame = origin * CFrame.new(0, 0, -length / 2)
	item.Parent = folder
	table.insert(effects, { item = item, born = os.clock(), life = 0.25, size = Vector3.new(0.5, 0.5, length) })
end

local function stepEffects(now: number)
	for index = #effects, 1, -1 do
		local effect = effects[index]
		local t = (now - effect.born) / effect.life
		if t >= 1 then
			effect.item:Destroy()
			table.remove(effects, index)
			continue
		end
		local out = 1 - (1 - t) ^ 2
		if effect.radius then
			effect.item.Radius = effect.radius * (0.25 + 0.75 * out)
			effect.item.InnerRadius = math.max(effect.item.Radius - 0.9 * (1 - t) - 0.1, 0)
		else
			effect.item.Size = Vector3.new(effect.size.X * (1 - t), effect.size.Y * (1 - t), effect.size.Z)
		end
		effect.item.Transparency = 0.25 + 0.75 * t
	end
end

-- Aro del círculo del jugador y aro de su objetivo.
local function stepCircle(now: number)
	local root = Targeting.root()
	local humanoid = root and (root.Parent :: Model):FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or ForgeScene.isActive() then
		circle.Visible, marker.Visible = false, false
		return
	end
	local radius = Config.Loadout.Radius
	if now - checked > CHECK then
		checked = now
		circleShown = Targeting.nearest(radius + CIRCLE_NEAR) ~= nil
	end
	local ground = root.Position.Y - standing(humanoid, root)
	local denied = now < deniedUntil
	circle.Visible = circleShown or denied
	if circle.Visible then
		circle.CFrame = CFrame.new(root.Position.X, ground + 0.12, root.Position.Z) * FLAT
		circle.Radius = radius
		circle.InnerRadius = radius - (if denied then 0.6 else 0.3)
		circle.Color3 = if denied then CIRCLE_DENIED else CIRCLE_COLOR
		circle.Transparency = if denied then 0.25 else CIRCLE_FADE
	end
	local target = targetOf(player, now)
	marker.Visible = target ~= nil
	if target then
		local girth = math.max(target.Size.X, target.Size.Z) / 2 + 0.8
		marker.CFrame = CFrame.new(target.Position.X, ground + 0.15, target.Position.Z) * FLAT * CFrame.Angles(0, 0, now * 2.5)
		marker.Radius = girth
		marker.InnerRadius = girth - 0.3
		marker.Transparency = 0.3 + 0.2 * math.sin(now * 7)
	end
end

-- Avisos -------------------------------------------------------------------------------------

-- Golpe del arma de ese hueco: confirma su pasada (o la da ya, si no la había empezado), deja prevista la siguiente,
-- suena y, si salpica o atraviesa, enseña hasta dónde.
local function onHit(hitter: Player, _part: BasePart?, position: Vector3, _damage: number, slot: number?)
	local rig = rigs[hitter]
	local weapon = rig and slot and rig.weapons[slot]
	if not weapon then
		return
	end
	local now = os.clock()
	if now - weapon.lastHit < SAME_BLOW then
		return
	end
	weapon.lastHit = now
	local cooldown = Stats.weaponCooldown(hitter, weapon.copy)
	weapon.ready = now + cooldown
	-- Con un arma muy rápida las pasadas se encogen para caber entre dos golpes.
	local squeeze = math.min(1, cooldown * 0.9 / (weapon.move.out + weapon.move.back))
	weapon.outTime, weapon.backTime = weapon.move.out * squeeze, weapon.move.back * squeeze
	if weapon.mode ~= "orbit" then
		if weapon.mode == "in" then
			weapon.cross = math.min(weapon.cross, now + SNAP)
		elseif weapon.confirmed or now - weapon.crossed > CONFIRM then
			launch(weapon, now, now + QUICK * squeeze)
		end
		weapon.confirmed = true
		weapon.planned = now + cooldown
	end

	-- Sale del arma; los de los demás, más flojos.
	Sfx.swing(weapon.key, cooldown, weapon.handle.Position, if hitter == player then 0.8 else 0.5)
	local root = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if Performance.get() or not root then
		return
	end
	local origin, range = Hitbox.spread(weapon.kind, weapon.length, root.Position, position)
	if not origin then
		return
	end
	if (weapon.kind.area or 0) > 0 then
		local humanoid = (hitter.Character :: Model):FindFirstChildOfClass("Humanoid")
		local ground = if humanoid then root.Position.Y - standing(humanoid, root) else position.Y
		splash(Vector3.new(position.X, ground + 0.2, position.Z), range, weapon.color)
	else
		pierce(origin.Rotation + Vector3.new(position.X, math.min(position.Y, root.Position.Y + 2), position.Z), range, weapon.color)
	end
end

-- El jugador local acaba de pedir ese objetivo: sus armas salen ya, sin esperar a que el servidor conteste.
function OrbitWeapons.aim(part: BasePart?)
	aimed = part
	aimedUntil = os.clock() + AIM_HOLD
end

-- Lo que ha elegido queda fuera del círculo: el aro se pone rojo un momento.
function OrbitWeapons.deny()
	deniedUntil = os.clock() + DENIED_TIME
end

local function watch(owner: Player)
	for _, attribute in { "Loadout", "Swords" } do
		owner:GetAttributeChangedSignal(attribute):Connect(function()
			dirty[owner] = true
		end)
	end
end

function OrbitWeapons.start()
	folder = Instance.new("Folder")
	folder.Name = "OrbitWeapons"
	folder.Parent = workspace
	circle = ring("Circle", CIRCLE_COLOR)
	marker = ring("Marker", MARKER_COLOR)
	marker.Angle = 300

	Players.PlayerAdded:Connect(watch)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerRemoving:Connect(function(other)
		destroy(other)
		dirty[other] = nil
	end)
	Remotes.Hit.OnClientEvent:Connect(onHit)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local lite = Performance.get()
		for _, other in Players:GetPlayers() do
			stepRig(other, now, dt, eye, lite)
		end
		stepCircle(now)
		stepEffects(now)
	end)
end

return OrbitWeapons
