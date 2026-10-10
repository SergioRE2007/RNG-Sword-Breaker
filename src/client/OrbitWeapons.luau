-- Las armas equipadas de cada jugador, a la vista: giran a su alrededor y, cuando el servidor le pone objetivo (el
-- ObjectValue "AttackTarget" del jugador, server/Combat), vuelan hasta él, dan un tajo con cada golpe de su hueco
-- (aviso Hit) y al acabar vuelven. Todo es local: cada cliente construye con SwordModel y mueve las de los jugadores
-- que tiene cerca (lejos de la cámara no existen, y en modo Rendimiento solo las propias y sin efectos).
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
local STRIKE_FOLLOW = 20 -- y al volar al objetivo: con 20 llega en Config.Loadout.Travel
local AIM_HOLD = 0.6 -- segundos que vale el objetivo que el jugador acaba de pedir mientras el servidor contesta
local FADE_FROM, FADE_FULL = 8, 3 -- studs de la cámara entre los que un arma propia se va volviendo translúcida
local FADE_MOST = 0.85 -- lo translúcida que llega a quedar
local SPREAD = 0.8 -- radianes entre dos armas alrededor del objetivo (hasta SPREAD_MAX de la primera a la última)
local SPREAD_MAX = 2.4
local AIM_LOW, AIM_HIGH = 1.5, 6 -- altura sobre el suelo a la que pegan, entre estas dos (el centro del objetivo si cabe)
local HIT_POINT = 0.3 -- parte del tajo en la que el arma baja; el resto es volver a la guardia
local SAME_BLOW = 0.05 -- segundos: los avisos de un mismo golpe que da a varios (salpica) cuentan como un solo tajo
local DUAL_GAP = 0.45 -- lo que tarda la segunda hoja de las dobles, en veces la duración del tajo
local CHECK = 0.25 -- cada cuántos segundos se mira si hay algo que atacar cerca (para enseñar el aro)
local CIRCLE_NEAR = 30 -- studs más allá del círculo desde los que ya se enseña el aro
local CIRCLE_COLOR = Color3.fromRGB(255, 255, 255)
local CIRCLE_DENIED = Color3.fromRGB(255, 80, 70)
local CIRCLE_FADE = 0.85 -- transparencia del aro en reposo
local DENIED_TIME = 0.4 -- segundos que se queda rojo
local MARKER_COLOR = Color3.fromRGB(255, 225, 100)
local FLAT = CFrame.Angles(math.rad(90), 0, 0) -- pone de pie el eje de un cilindro: aros tumbados en el suelo

-- Cómo golpea cada tipo de arma (ángulos en grados alrededor de su eje X: positivo = echada hacia atrás, negativo =
-- hacia el objetivo): `time` = segundos del tajo, `ready` = guardia, `strike` = golpe dado, `roll` = lo ladeado que
-- va el corte (alterna de lado en cada golpe) y `lunge` = cuánto avanza, en veces su largo. `thrust` = estocada.
local MOVES = {
	sword = { time = 0.24, ready = 30, strike = -105, roll = 40, lunge = 0.25 },
	dual = { time = 0.2, ready = 30, strike = -100, roll = 50, lunge = 0.2 },
	axe = { time = 0.34, ready = 60, strike = -110, roll = 12, lunge = 0.3 },
	hammer = { time = 0.4, ready = 70, strike = -100, roll = 0, lunge = 0.35 },
	spear = { time = 0.26, thrust = true },
}
local THRUST_GAP = 1.2 -- lo que le falta a la punta de la lanza para tocar al objetivo, en guardia

local folder: Folder
-- [Player] = { key, holder, phase, fresh, weapons = { arma } }. Cada arma: { copy, key (tipo), kind, move, model, handle,
-- off (segunda hoja de las dobles), reach (de la empuñadura a la punta), height, length (Config), color, orbitMain y
-- orbitOff (colocación en la órbita), frame (dónde va ahora), mix (0 = órbita, 1 = atacando), slashAt, slashTime,
-- side, girth (radio del objetivo), trails, trailOn }
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
	local key, kind = Stats.kind(copy)
	local metal = Permanent.metal(copy)
	local toHandle = CFrame.new(-center)
	local orbitMain, orbitOff
	if off then
		-- Las dobles giran cruzadas, en aspa.
		orbitMain = CFrame.new(-0.18, 0, 0) * CFrame.Angles(math.rad(24), 0, 0) * toHandle
		orbitOff = CFrame.new(0.18, 0, 0) * CFrame.Angles(math.rad(-24), 0, 0) * toHandle
	else
		-- Las demás, de pie: algo vencidas hacia donde giran y hacia fuera (la lanza, más tumbada).
		orbitMain = CFrame.Angles(math.rad(if key == "spear" then -20 else -8), 0, math.rad(10)) * toHandle
	end

	-- La estela del tajo, más corta y tenue que en la mano: aquí el arma entera da la vuelta y, en las grandes,
	-- dibujaba una sábana blanca (visto en Studio).
	local trails = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Trail") and item.Name == "SwingTrail" then
			item.Lifetime = 0.1
			item.Transparency = NumberSequence.new(0.55, 1)
			table.insert(trails, item)
		end
	end
	model.Parent = parent
	return {
		copy = copy,
		key = key,
		kind = kind,
		move = MOVES[key] or MOVES.sword,
		model = model,
		handle = handle,
		off = off,
		reach = math.max(high.Y, 1),
		low = low.Y,
		height = high.Y - low.Y,
		faded = 0,
		wide = math.max(high.X - low.X, high.Z - low.Z) / 2,
		length = Config.Swords[copy.sword].bladeLength,
		color = if metal then metal.color else Config.Swords[copy.sword].color,
		orbitMain = orbitMain,
		orbitOff = orbitOff,
		frame = CFrame.identity,
		mix = 0,
		slashAt = 0,
		slashTime = 0.2,
		side = if slot % 2 == 0 then 1 else -1,
		girth = 2,
		trails = trails,
		trailOn = false,
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
	rigs[owner] = { key = key, holder = holder, weapons = weapons, phase = (owner.UserId % 628) / 100, fresh = true }
end

-- Objetivo al que van las armas de ese jugador. El jugador local adelanta el suyo mientras el servidor contesta.
local function targetOf(owner: Player, now: number): BasePart?
	local target = Targeting.current(owner)
	if not target and owner == player and aimed and now < aimedUntil and aimed:IsDescendantOf(workspace) then
		target = aimed
	end
	return target
end

-- Sitio del arma en la órbita: su centro, mirando hacia donde gira.
local function orbitFrame(rig, weapon, index: number, count: number, root: BasePart, ground: number, now: number): CFrame
	local angle = now * ORBIT_SPEED + rig.phase + (index - 1) * TAU / count
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local along = Vector3.new(-out.Z, 0, out.X)
	local y = math.max(root.Position.Y + ORBIT_LIFT, ground + weapon.height / 2 + GROUND_GAP) + math.sin(now * 2.1 + index * 1.7) * BOB
	local center = Vector3.new(root.Position.X, y, root.Position.Z) + out * (ORBIT_RADIUS + weapon.wide)
	return CFrame.lookAt(center, center + along)
end

-- Sitio del arma junto al objetivo: su empuñadura, mirándolo. Se reparten por el lado del jugador.
local function strikeFrame(weapon, index: number, count: number, root: BasePart, ground: number, target: BasePart): CFrame
	local center = target.Position
	local toPlayer = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	toPlayer = if toPlayer.Magnitude > 0.2 then toPlayer.Unit else Vector3.zAxis
	local turn = if count > 1 then ((index - 1) / (count - 1) - 0.5) * math.min(SPREAD_MAX, SPREAD * (count - 1)) else 0
	local side = CFrame.Angles(0, turn, 0):VectorToWorldSpace(toPlayer)
	local girth = math.max(target.Size.X, target.Size.Z) / 2
	weapon.girth = girth
	local aim = math.clamp(center.Y, ground + AIM_LOW, ground + AIM_HIGH)
	local distance, height
	if weapon.move.thrust then
		distance, height = girth + weapon.reach + THRUST_GAP, aim + 0.3
	else
		distance, height = girth + weapon.reach * 0.55, aim + weapon.reach * 0.35
	end
	local at = Vector3.new(center.X, height, center.Z)
	return CFrame.lookAt(at + side * distance, at)
end

-- Cuánto del golpe lleva dado (0 = en guardia, 1 = golpe dado) a `t` de 0 a 1 de su duración: baja deprisa y vuelve.
local function swing(t: number): number
	if t <= 0 or t >= 1 then
		return 0
	elseif t < HIT_POINT then
		return 1 - (1 - t / HIT_POINT) ^ 2
	end
	return 0.5 + 0.5 * math.cos((t - HIT_POINT) / (1 - HIT_POINT) * math.pi)
end

-- Postura de una hoja junto al objetivo, respecto a su sitio (strikeFrame).
local function strikePose(weapon, now: number, delay: number, side: number, shift: number): CFrame
	local move = weapon.move
	local done = swing((now - weapon.slashAt) / weapon.slashTime - delay)
	if move.thrust then
		local advance = (THRUST_GAP + math.min(weapon.girth, 3) + 1) * done
		return CFrame.new(shift, 0, -advance) * CFrame.Angles(math.rad(-94), 0, 0)
	end
	local sway = if done == 0 then math.sin(now * 2.5 + shift + weapon.side) * 4 else 0
	local angle = move.ready + (move.strike - move.ready) * done + sway
	return CFrame.new(shift, 0, -move.lunge * weapon.reach * done) * CFrame.Angles(0, 0, math.rad(move.roll) * side) * CFrame.Angles(math.rad(angle), 0, 0)
end

local function setTrail(weapon, on: boolean)
	weapon.trailOn = on
	for _, trail in weapon.trails do
		trail.Enabled = on
	end
end

local function place(weapon, now: number)
	local mix = weapon.mix
	if mix < 0.002 then
		weapon.handle.CFrame = weapon.frame * weapon.orbitMain
		if weapon.off then
			weapon.off.CFrame = weapon.frame * weapon.orbitOff
		end
	elseif weapon.off then
		-- Dobles: una hoja a cada lado, y la segunda golpea un poco después y por el otro lado.
		local gap = 0.9 * weapon.wide + 0.6
		weapon.handle.CFrame = weapon.frame * weapon.orbitMain:Lerp(strikePose(weapon, now, 0, weapon.side, -gap), mix)
		weapon.off.CFrame = weapon.frame * weapon.orbitOff:Lerp(strikePose(weapon, now, DUAL_GAP, -weapon.side, gap), mix)
	else
		weapon.handle.CFrame = weapon.frame * weapon.orbitMain:Lerp(strikePose(weapon, now, 0, weapon.side, 0), mix)
	end
	if weapon.trailOn and now - weapon.slashAt > weapon.slashTime * (if weapon.off then 1 + DUAL_GAP else 1) then
		setTrail(weapon, false)
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
	local target = targetOf(owner, now)
	local count = #rig.weapons
	local alpha = 1 - math.exp(-(if target then STRIKE_FOLLOW else FOLLOW) * dt)
	local goalMix = if target then 1 else 0
	for index, weapon in rig.weapons do
		local goal = if target then strikeFrame(weapon, index, count, root, ground, target) else orbitFrame(rig, weapon, index, count, root, ground, now)
		if rig.fresh then
			weapon.frame, weapon.mix = goal, goalMix
		else
			weapon.frame = weapon.frame:Lerp(goal, alpha)
			weapon.mix += (goalMix - weapon.mix) * alpha
		end
		place(weapon, now)
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

-- Golpe del arma de ese hueco: da el tajo, suena y, si salpica o atraviesa, enseña hasta dónde.
local function onHit(hitter: Player, _part: BasePart?, position: Vector3, _damage: number, slot: number?)
	local rig = rigs[hitter]
	local weapon = rig and slot and rig.weapons[slot]
	if not weapon then
		return
	end
	local now = os.clock()
	if now - weapon.slashAt < SAME_BLOW then
		return
	end
	local cooldown = Stats.weaponCooldown(hitter, weapon.copy)
	weapon.slashAt = now
	weapon.slashTime = math.min(weapon.move.time, cooldown * 0.9)
	weapon.side = -weapon.side
	local lite = Performance.get()
	if not lite then
		setTrail(weapon, true)
	end
	-- Sale del arma; los de los demás, más flojos.
	Sfx.swing(weapon.key, cooldown, weapon.handle.Position, if hitter == player then 0.8 else 0.5)
	local root = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if lite or not root then
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
