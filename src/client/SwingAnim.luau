-- Animación del golpe hecha por código (no hay animaciones subidas): mueve las articulaciones del personaje
-- durante el golpe y enciende la estela del arma. Cada tipo de arma tiene sus movimientos, que se van alternando.
-- Vale para el jugador y para los demás.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)

local Performance = require(script.Parent.Performance)

local SwingAnim = {}

local MIN_DURATION = 0.26 -- con la velocidad de golpe al máximo el movimiento aún se tiene que ver
local COMBO_RESET = 0.7 -- segundos sin golpear (tras acabar el golpe) para volver al primer movimiento
local BLEND_IN = 0.12 -- parte del golpe que tarda en pasar de la postura normal a la primera postura

local HAMMER_IMPACT = 0.5 -- momento del golpe en que el martillo toca el suelo
local STILL_SPEED = 2 -- por debajo de esta velocidad (studs/s) el personaje está parado y también se le mueven las piernas

-- Cada movimiento es una lista de { momento (0 a 1), postura, paso }. Antes del primer momento se entra en la
-- primera postura, entre momentos se pasa de una a otra y tras el último se vuelve a la postura normal.
-- Sin postura se mantiene la anterior. `paso` = cómo se llega a esa postura: nada = suave; "hit" = de golpe y
-- pasándose un poco (el tajo); "in" y "out" = acelerando y frenando, para enlazar las mitades de una vuelta.
-- Golpes exagerados a propósito (pedido por el usuario): mucha carga, salto o zancada y cuerpo entero.
-- Posturas en grados (lo que no se pone vale 0):
--   spin = girar el cuerpo entero, turn = girar el torso (positivo a la izquierda), lean = inclinarlo (negativo adelante),
--   head = girar la cabeza (para que siga mirando al frente),
--   raise = subir el brazo derecho (0 abajo, 90 al frente, 180 arriba), swing = llevarlo a la izquierda,
--   elbow = doblar el codo, wrist = muñeca (negativo echa la hoja hacia delante).
--   lraise, lswing, lelbow, lwrist = lo mismo para el brazo izquierdo.
--   rhip, lhip = pierna adelante; rknee, lknee = doblar la rodilla (las piernas solo se mueven con el personaje parado).
-- Y en studs: hop = salto, lunge = zancada al frente, drop = agacharse (negativo; solo parado).
local MOVES = {
	sword = {
		{ -- tajo diagonal de derecha a izquierda, con zancada
			{ 0.16, { spin = -25, turn = -40, lean = 8, head = 35, raise = 150, swing = -40, elbow = 95, wrist = 25, lraise = 50, lswing = 25, lelbow = 30, hop = 0.4, drop = -0.2, lhip = 20, lknee = 15, rhip = -15, rknee = 20 } },
			{ 0.36, { spin = 20, turn = 40, lean = -22, head = -30, raise = 35, swing = 70, elbow = 10, wrist = -70, lraise = -45, lswing = 20, lelbow = 20, lunge = 1.4, drop = -0.4, rhip = 35, rknee = 35, lhip = -25, lknee = 15 }, "hit" },
			{ 0.62 },
		},
		{ -- revés horizontal de izquierda a derecha
			{ 0.16, { spin = 20, turn = 40, lean = -5, head = -30, raise = 85, swing = 75, elbow = 105, wrist = -25, lraise = -30, lelbow = 20, drop = -0.2, rhip = 15, rknee = 20, lhip = -15, lknee = 20 } },
			{ 0.36, { spin = -25, turn = -40, lean = -12, head = 35, raise = 80, swing = -60, elbow = 5, wrist = -65, lraise = 35, lswing = 40, lelbow = 30, lunge = 1.2, drop = -0.4, lhip = 35, lknee = 35, rhip = -25, rknee = 15 }, "hit" },
			{ 0.62 },
		},
		{ -- vuelta entera con la espada extendida y un saltito
			{ 0.14, { spin = -50, turn = -30, lean = -5, raise = 88, swing = -50, elbow = 40, wrist = -60, lraise = 60, lswing = 40, lelbow = 30, drop = -0.5, rhip = 20, rknee = 30, lhip = -15, lknee = 30 } },
			{ 0.37, { spin = 165, lean = -10, raise = 88, swing = -40, elbow = 5, wrist = -70, lraise = 70, lswing = 50, lelbow = 15, hop = 1.2 }, "in" },
			{ 0.6, { spin = 360, turn = 15, lean = -8, raise = 85, swing = -10, elbow = 8, wrist = -68, lraise = 50, lswing = 35, lelbow = 15 }, "out" },
		},
		{ -- salto y golpe desde arriba a dos manos
			{ 0.18, { lean = 18, raise = 175, elbow = 70, wrist = 30, lraise = 170, lelbow = 70, hop = 2.6, rhip = 35, rknee = 70, lhip = 10, lknee = 80 } },
			{ 0.38, { turn = 10, lean = -38, raise = 28, swing = 10, elbow = 8, wrist = -70, lraise = 30, lelbow = 10, lunge = 0.8, drop = -0.5, rhip = 40, rknee = 45, lhip = -25, lknee = 25 }, "hit" },
			{ 0.66 },
		},
	},
	dual = {
		{ -- las dos hojas de fuera adentro, cruzándose
			{ 0.16, { turn = -15, lean = 10, raise = 95, swing = -70, elbow = 40, wrist = -20, lraise = 95, lswing = 70, lelbow = 40, lwrist = -20, hop = 0.3, drop = -0.3, rhip = 15, rknee = 25, lhip = -15, lknee = 25 } },
			{ 0.36, { turn = 10, lean = -25, raise = 70, swing = 75, elbow = 15, wrist = -60, lraise = 70, lswing = -75, lelbow = 15, lwrist = -60, lunge = 1.3, drop = -0.4, rhip = 35, rknee = 35, lhip = -25, lknee = 15 }, "hit" },
			{ 0.6 },
		},
		{ -- de cruzadas a abiertas, con un saltito
			{ 0.16, { lean = -15, raise = 80, swing = 80, elbow = 60, wrist = -30, lraise = 80, lswing = -80, lelbow = 60, lwrist = -30, drop = -0.6, rhip = 20, rknee = 40, lhip = 20, lknee = 40 } },
			{ 0.36, { lean = 12, raise = 85, swing = -75, elbow = 5, wrist = -55, lraise = 85, lswing = 75, lelbow = 5, lwrist = -55, hop = 0.6, lunge = 0.8 }, "hit" },
			{ 0.6 },
		},
		{ -- batidora: vuelta entera con los dos brazos abiertos
			{ 0.14, { spin = -45, lean = -8, raise = 88, swing = -80, elbow = 5, wrist = -60, lraise = 88, lswing = 80, lelbow = 5, lwrist = -60, drop = -0.4, rhip = 15, rknee = 30, lhip = -15, lknee = 30 } },
			{ 0.37, { spin = 160, lean = -8, raise = 88, swing = -85, elbow = 5, wrist = -60, lraise = 88, lswing = 85, lelbow = 5, lwrist = -60, hop = 1 }, "in" },
			{ 0.6, { spin = 360, lean = -8, raise = 88, swing = -80, elbow = 5, wrist = -60, lraise = 88, lswing = 80, lelbow = 5, lwrist = -60 }, "out" },
		},
	},
	axe = {
		{ -- carga hacia atrás y vuelta entera en el aire con el hacha extendida
			{ 0.16, { spin = -70, turn = -30, lean = -8, raise = 85, swing = -60, elbow = 30, wrist = -60, lraise = 70, lswing = 45, lelbow = 25, drop = -0.6, rhip = 20, rknee = 35, lhip = -20, lknee = 35 } },
			{ 0.45, { spin = 150, lean = -14, raise = 92, swing = -55, elbow = 8, wrist = -75, lraise = 75, lswing = 50, lelbow = 15, hop = 1.1 }, "in" },
			{ 0.74, { spin = 360, turn = 15, lean = -10, raise = 88, swing = -40, elbow = 8, wrist = -75, lraise = 70, lswing = 45, lelbow = 15, drop = -0.3 }, "out" },
		},
	},
	hammer = {
		{ -- martillazo: salta con el martillo a dos manos por encima de la cabeza y cae con todo el cuerpo
			{ 0.3, { spin = -8, lean = 22, raise = 178, elbow = 55, wrist = 30, lraise = 172, lelbow = 60, hop = 2.8, rhip = 30, rknee = 75, lhip = 15, lknee = 85 } },
			{ HAMMER_IMPACT, { spin = 6, lean = -42, raise = 30, elbow = 5, wrist = -68, lraise = 34, lelbow = 5, lunge = 0.8, drop = -0.6, rhip = 40, rknee = 50, lhip = -25, lknee = 30 }, "hit" },
			{ 0.78 },
		},
	},
	spear = {
		{ -- estocada: se echa atrás con el codo recogido y sale disparado al frente
			{ 0.2, { spin = -20, turn = -40, lean = 8, head = 30, raise = -45, elbow = 130, lraise = 70, lelbow = 15, lunge = -0.8, drop = -0.3, lhip = 15, lknee = 20, rhip = -20, rknee = 20 } },
			{ 0.38, { spin = 15, turn = 35, lean = -28, head = -25, raise = 90, elbow = 0, lraise = -45, lelbow = 15, lunge = 2.6, drop = -0.5, rhip = 45, rknee = 45, lhip = -35, lknee = 12 }, "hit" },
			{ 0.66 },
		},
		{ -- barrido: vuelta entera con la lanza extendida
			{ 0.14, { spin = -50, turn = -25, raise = 80, swing = -50, elbow = 20, wrist = -40, lraise = 60, lswing = 40, drop = -0.5, rhip = 20, rknee = 30, lhip = -15, lknee = 30 } },
			{ 0.4, { spin = 160, lean = -8, raise = 88, swing = -45, elbow = 5, wrist = -55, lraise = 65, lswing = 45, hop = 0.9 }, "in" },
			{ 0.66, { spin = 360, turn = 15, raise = 85, swing = -30, elbow = 5, wrist = -55, lraise = 60, lswing = 40 }, "out" },
		},
	},
}
for _, moves in MOVES do
	for _, move in moves do
		for index, key in move do
			key[2] = key[2] or move[index - 1][2]
		end
	end
end

local DISTANCES = { hop = true, lunge = true, drop = true } -- valores en studs, no en grados

local EASES = {
	hit = function(t: number): number -- llega enseguida, se pasa un poco y vuelve
		local back = 1.70158
		return 1 + (back + 1) * (t - 1) ^ 3 + back * (t - 1) ^ 2
	end,
	["in"] = function(t: number): number
		return t * t
	end,
	out = function(t: number): number
		return 1 - (1 - t) ^ 2
	end,
}

-- Articulaciones: pieza donde está, nombre, valores de la postura que usa, cómo se convierten en giro y,
-- si es true, que solo se mueve con el personaje parado (las piernas: andando mandan sus pasos).
local JOINTS = {
	{ "LowerTorso", "Root", { "spin", "hop", "lunge", "drop" }, function(p)
		return CFrame.new(0, p.hop + p.drop, -p.lunge) * CFrame.Angles(0, p.spin, 0)
	end },
	{ "UpperTorso", "Waist", { "turn", "lean" }, function(p)
		return CFrame.Angles(0, p.turn, 0) * CFrame.Angles(p.lean, 0, 0)
	end },
	{ "Head", "Neck", { "head" }, function(p)
		return CFrame.Angles(0, p.head, 0)
	end },
	{ "RightUpperLeg", "RightHip", { "rhip" }, function(p)
		return CFrame.Angles(p.rhip, 0, 0)
	end, true },
	{ "RightLowerLeg", "RightKnee", { "rknee" }, function(p)
		return CFrame.Angles(-p.rknee, 0, 0)
	end, true },
	{ "LeftUpperLeg", "LeftHip", { "lhip" }, function(p)
		return CFrame.Angles(p.lhip, 0, 0)
	end, true },
	{ "LeftLowerLeg", "LeftKnee", { "lknee" }, function(p)
		return CFrame.Angles(-p.lknee, 0, 0)
	end, true },
	{ "RightUpperArm", "RightShoulder", { "raise", "swing" }, function(p)
		return CFrame.Angles(0, p.swing, 0) * CFrame.Angles(p.raise, 0, 0)
	end },
	{ "RightLowerArm", "RightElbow", { "elbow" }, function(p)
		return CFrame.Angles(p.elbow, 0, 0)
	end },
	{ "RightHand", "RightWrist", { "wrist" }, function(p)
		return CFrame.Angles(p.wrist, 0, 0)
	end },
	{ "LeftUpperArm", "LeftShoulder", { "lraise", "lswing" }, function(p)
		return CFrame.Angles(0, p.lswing, 0) * CFrame.Angles(p.lraise, 0, 0)
	end },
	{ "LeftLowerArm", "LeftElbow", { "lelbow" }, function(p)
		return CFrame.Angles(p.lelbow, 0, 0)
	end },
	{ "LeftHand", "LeftWrist", { "lwrist" }, function(p)
		return CFrame.Angles(p.lwrist, 0, 0)
	end },
}

local FIELDS = {}
for _, joint in JOINTS do
	for _, field in joint[3] do
		table.insert(FIELDS, field)
	end
end

local active = {} -- [personaje] = golpe en curso
local combos = setmetatable({}, { __mode = "k" }) -- [personaje] = { kind, index, time }

-- Articulaciones que mueve ese movimiento, o nil si al personaje le falta alguna (no es R15).
local function findJoints(character: Model, move)
	local found = {}
	for _, joint in JOINTS do
		local used = false
		for _, key in move do
			for _, field in joint[3] do
				used = used or key[2][field] ~= nil
			end
		end
		if used then
			local part = character:FindFirstChild(joint[1])
			local motor = part and part:FindFirstChild(joint[2])
			-- Según el avatar, la articulación es un Motor6D o un AnimationConstraint; los dos tienen Transform.
			if not motor or not (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
				return nil
			end
			table.insert(found, { motor = motor, cframe = joint[4], still = joint[5] == true })
		end
	end
	return found
end

local function findTrails(character: Model): { Trail }
	local trails = {}
	local tool = character:FindFirstChildWhichIsA("Tool")
	if tool then
		for _, item in tool:GetDescendants() do
			if item:IsA("Trail") and item.Name == "SwingTrail" then
				table.insert(trails, item)
			end
		end
	end
	return trails
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Postura del movimiento en el momento t, ya en radianes.
local function sample(move, t: number)
	local from, to, progress = move[1][2], move[1][2], 0
	if t >= move[#move][1] then
		from, to = move[#move][2], move[#move][2]
	else
		for index = 1, #move - 1 do
			local a, b = move[index], move[index + 1]
			if t >= a[1] and t < b[1] then
				from, to, progress = a[2], b[2], (EASES[b[3]] or smooth)((t - a[1]) / (b[1] - a[1]))
				break
			end
		end
	end
	local pose = {}
	for _, field in FIELDS do
		local a, b = from[field] or 0, to[field] or 0
		local value = a + (b - a) * progress
		pose[field] = if DISTANCES[field] then value else math.rad(value)
	end
	return pose
end

local function setTrails(swing, enabled: boolean)
	if Performance.get() then enabled = false end -- modo rendimiento: sin estela
	for _, trail in swing.trails do
		trail.Enabled = enabled
	end
end

local function stop(character: Model)
	local swing = active[character]
	if swing then
		setTrails(swing, false)
		active[character] = nil
	end
end

-- El Animator escribe las articulaciones justo antes de Stepped; aquí se mezcla el golpe por encima.
local function step()
	local now = os.clock()
	for character, swing in active do
		local t = (now - swing.start) / swing.duration
		if t >= 1 or not character.Parent then
			stop(character)
			continue
		end

		local move = swing.move
		local first, last = move[1][1], move[#move][1]
		local weight = 1
		if t < first then
			weight = smooth(math.min(t / BLEND_IN, 1))
		elseif t > last then
			weight = 1 - smooth((t - last) / (1 - last))
		end

		-- Parado se mueven también las piernas; al echar a andar se sueltan poco a poco.
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local moving = root ~= nil and (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > STILL_SPEED
		swing.still += ((if moving then 0 else 1) - swing.still) * math.min((now - swing.last) * 12, 1)
		swing.last = now

		local pose = sample(move, t)
		pose.drop *= swing.still
		for _, joint in swing.joints do
			joint.motor.Transform = joint.motor.Transform:Lerp(joint.cframe(pose), if joint.still then weight * swing.still else weight)
		end
		setTrails(swing, t >= first and t <= last + 0.05)
	end
end

-- Impacto del martillo (solo para el jugador): la cámara tiembla un momento y una onda de polvo sale del suelo.
local function slam(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < 0.3 and humanoid.Parent do
			local fade = 1 - (os.clock() - began) / 0.3
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.6 * fade
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)

	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(235, 225, 200)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.4, 3, 3)
	ring.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 5 - Vector3.new(0, root.Size.Y / 2 + 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, 22, 22), Transparency = 1 })
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
	tween:Play()
end

-- Lanza el golpe de ese tipo de arma en el personaje. Devuelve false si su esqueleto no es R15 (no se puede animar así).
function SwingAnim.play(character: Model?, cooldown: number, kind: string): boolean
	if not character then
		return false
	end
	local moves = MOVES[kind] or MOVES.sword
	local now = os.clock()
	local duration = math.max(cooldown * 1.15, MIN_DURATION)

	local combo = combos[character]
	local index = 1
	if combo and combo.kind == kind and now - combo.time < combo.duration + COMBO_RESET then
		index = combo.index % #moves + 1
	end

	local joints = findJoints(character, moves[index])
	if not joints then
		return false
	end
	stop(character)
	combos[character] = { kind = kind, index = index, time = now, duration = duration }
	active[character] = {
		start = now,
		duration = duration,
		move = moves[index],
		joints = joints,
		trails = findTrails(character),
		still = 0,
		last = now,
	}
	if kind == "hammer" then
		task.delay(duration * HAMMER_IMPACT, function()
			if character.Parent then
				slam(character)
			end
		end)
	end
	return true
end

function SwingAnim.start()
	RunService.Stepped:Connect(step)
	-- Golpes de los demás jugadores (el propio se lanza desde SwordController sin esperar al servidor).
	Remotes.SwingFx.OnClientEvent:Connect(function(other: Player)
		if other ~= Players.LocalPlayer then
			SwingAnim.play(other.Character, Stats.cooldown(other), (Stats.weapon(other)))
		end
	end)
end

return SwingAnim
