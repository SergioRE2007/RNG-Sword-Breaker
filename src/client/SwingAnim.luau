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

-- Cada movimiento es una lista de { momento (0 a 1), postura }. Antes del primer momento se entra en la primera
-- postura, entre momentos se pasa de una a otra con suavidad y tras el último se vuelve a la postura normal.
-- Posturas en grados (lo que no se pone vale 0):
--   spin = girar el cuerpo entero, turn = girar el torso (positivo a la izquierda), lean = inclinarlo (negativo adelante),
--   raise = subir el brazo derecho (0 abajo, 90 al frente, 180 arriba), swing = llevarlo a la izquierda,
--   elbow = doblar el codo, wrist = muñeca (negativo echa la hoja hacia delante).
--   lraise, lswing, lelbow, lwrist = lo mismo para el brazo izquierdo.
local MOVES = {
	sword = {
		{ -- tajo diagonal de derecha a izquierda
			{ 0.2, { spin = -8, turn = -28, lean = 4, raise = 125, swing = -25, elbow = 85, wrist = 15, lraise = 20 } },
			{ 0.6, { spin = 10, turn = 38, lean = -13, raise = 45, swing = 45, elbow = 20, wrist = -55, lraise = -25 } },
		},
		{ -- revés horizontal de izquierda a derecha
			{ 0.2, { spin = 10, turn = 35, lean = -3, raise = 80, swing = 55, elbow = 95, wrist = -20, lraise = -20 } },
			{ 0.6, { spin = -10, turn = -35, lean = -8, raise = 72, swing = -45, elbow = 15, wrist = -62, lraise = 20 } },
		},
		{ -- golpe desde arriba
			{ 0.22, { lean = 10, raise = 165, elbow = 80, wrist = 20, lraise = 30 } },
			{ 0.6, { turn = 8, lean = -24, raise = 35, swing = 10, elbow = 15, wrist = -62, lraise = -20 } },
		},
	},
	dual = {
		{ -- tajo con la derecha, la izquierda en guardia
			{ 0.2, { turn = -22, raise = 115, swing = -20, elbow = 75, wrist = 10, lraise = 55, lelbow = 15 } },
			{ 0.65, { turn = 28, lean = -8, raise = 55, swing = 40, elbow = 15, wrist = -55, lraise = 55, lelbow = 15 } },
		},
		{ -- tajo con la izquierda, la derecha en guardia
			{ 0.2, { turn = 22, lraise = 115, lswing = 20, lelbow = 75, lwrist = 10, raise = 55, elbow = 15 } },
			{ 0.65, { turn = -28, lean = -8, lraise = 55, lswing = -40, lelbow = 15, lwrist = -55, raise = 55, elbow = 15 } },
		},
	},
	axe = {
		{ -- vuelta entera con el hacha extendida
			{ 0.18, { spin = -30, turn = -25, raise = 90, swing = -55, elbow = 15, wrist = -70, lraise = 70, lswing = 45, lelbow = 20 } },
			{ 0.82, { spin = 360, raise = 90, swing = -55, elbow = 15, wrist = -70, lraise = 70, lswing = 45, lelbow = 20 } },
		},
	},
	hammer = {
		{ -- martillazo: se levanta a dos manos por encima de la cabeza y se deja caer hacia delante
			{ 0.32, { spin = -6, lean = 16, raise = 172, elbow = 50, wrist = 25, lraise = 165, lelbow = 55 } },
			{ 0.55, { spin = 6, lean = -34, raise = 38, elbow = 8, wrist = -62, lraise = 40, lelbow = 8 } },
			{ 0.78, { spin = 6, lean = -34, raise = 38, elbow = 8, wrist = -62, lraise = 40, lelbow = 8 } },
		},
	},
	spear = {
		{ -- estocada: codo atrás y brazo recto al frente
			{ 0.25, { spin = -10, turn = -35, lean = 3, raise = -35, elbow = 125, lraise = 55, lelbow = 25 } },
			{ 0.5, { spin = 12, turn = 35, lean = -14, raise = 88, elbow = 2, lraise = -25, lelbow = 10 } },
			{ 0.7, { spin = 12, turn = 35, lean = -14, raise = 88, elbow = 2, lraise = -25, lelbow = 10 } },
		},
	},
}

-- Articulaciones: pieza donde está, nombre, valores de la postura que usa y cómo se convierten en giro.
local JOINTS = {
	{ "LowerTorso", "Root", { "spin" }, function(p)
		return CFrame.Angles(0, p.spin, 0)
	end },
	{ "UpperTorso", "Waist", { "turn", "lean" }, function(p)
		return CFrame.Angles(0, p.turn, 0) * CFrame.Angles(p.lean, 0, 0)
	end },
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
			table.insert(found, { motor = motor, cframe = joint[4] })
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
				from, to, progress = a[2], b[2], smooth((t - a[1]) / (b[1] - a[1]))
				break
			end
		end
	end
	local pose = {}
	for _, field in FIELDS do
		local a, b = from[field] or 0, to[field] or 0
		pose[field] = math.rad(a + (b - a) * progress)
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

		local pose = sample(move, t)
		for _, joint in swing.joints do
			joint.motor.Transform = joint.motor.Transform:Lerp(joint.cframe(pose), weight)
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
	}
	-- El martillo toca el suelo hacia el 55 % del golpe.
	if kind == "hammer" then
		task.delay(duration * 0.55, function()
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
