-- Animación del espadazo hecha por código (no hay animaciones subidas): mueve cintura, hombro, codo y muñeca
-- durante el golpe, alternando tres tajos, y enciende la estela de la hoja. Vale para el jugador y para los demás.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local SwingAnim = {}

local MIN_DURATION = 0.24 -- con la velocidad de golpe al máximo el tajo aún se tiene que ver
local COMBO_RESET = 0.7 -- segundos sin golpear para volver al primer tajo

-- Reparto del tiempo del tajo: preparar, golpear y volver a la postura normal.
local BLEND_IN = 0.15
local WINDUP_END = 0.25
local STRIKE_END = 0.55
local TRAIL_FROM, TRAIL_TO = 0.2, 0.7

-- Posturas en grados. lean = inclinar el torso (negativo hacia delante), turn = girarlo (positivo a la izquierda),
-- raise = subir el brazo (0 abajo, 90 al frente, 180 arriba), swing = llevarlo a la izquierda,
-- elbow = doblar el codo, wrist = muñeca (negativo echa la hoja hacia delante).
local MOVES = {
	{ -- tajo diagonal de derecha a izquierda
		windup = { lean = 5, turn = -30, raise = 155, swing = -30, elbow = 70, wrist = 25 },
		strike = { lean = -12, turn = 35, raise = 55, swing = 35, elbow = 5, wrist = -45 },
	},
	{ -- revés horizontal de izquierda a derecha
		windup = { lean = 0, turn = 40, raise = 85, swing = 45, elbow = 85, wrist = -30 },
		strike = { lean = -5, turn = -35, raise = 80, swing = -35, elbow = 5, wrist = -75 },
	},
	{ -- golpe desde arriba
		windup = { lean = 15, turn = 0, raise = 185, swing = 0, elbow = 80, wrist = 30 },
		strike = { lean = -28, turn = 5, raise = 25, swing = 10, elbow = 0, wrist = -70 },
	},
}

local JOINTS = {
	waist = { "UpperTorso", "Waist" },
	shoulder = { "RightUpperArm", "RightShoulder" },
	elbow = { "RightLowerArm", "RightElbow" },
	wrist = { "RightHand", "RightWrist" },
}

local active = {} -- [personaje] = tajo en curso
local combos = setmetatable({}, { __mode = "k" }) -- [personaje] = { index, time }

local function findJoints(character: Model)
	local joints = {}
	for key, path in JOINTS do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		-- Según el avatar, la articulación es un Motor6D o un AnimationConstraint; los dos tienen Transform.
		if not motor or not (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			return nil
		end
		joints[key] = motor
	end
	return joints
end

local function findTrail(character: Model): Trail?
	local tool = character:FindFirstChildWhichIsA("Tool")
	local blade = tool and tool:FindFirstChild("Blade")
	return blade and blade:FindFirstChild("SwingTrail") :: Trail?
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function pose(a, b, t: number)
	local function mix(key: string): number
		return math.rad(a[key] + (b[key] - a[key]) * t)
	end
	return {
		waist = CFrame.Angles(0, mix("turn"), 0) * CFrame.Angles(mix("lean"), 0, 0),
		shoulder = CFrame.Angles(0, mix("swing"), 0) * CFrame.Angles(mix("raise"), 0, 0),
		elbow = CFrame.Angles(mix("elbow"), 0, 0),
		wrist = CFrame.Angles(mix("wrist"), 0, 0),
	}
end

local function stop(character: Model)
	local swing = active[character]
	if swing then
		if swing.trail then
			swing.trail.Enabled = false
		end
		active[character] = nil
	end
end

-- El Animator escribe las articulaciones justo antes de Stepped; aquí se mezcla el tajo por encima.
local function step()
	local now = os.clock()
	for character, swing in active do
		local t = (now - swing.start) / swing.duration
		if t >= 1 or not character.Parent then
			stop(character)
			continue
		end

		local move = swing.move
		local target, weight
		if t < WINDUP_END then
			target = pose(move.windup, move.windup, 0)
			weight = smooth(math.min(t / BLEND_IN, 1))
		elseif t < STRIKE_END then
			local progress = (t - WINDUP_END) / (STRIKE_END - WINDUP_END)
			target = pose(move.windup, move.strike, progress * progress)
			weight = 1
		else
			target = pose(move.strike, move.strike, 0)
			weight = 1 - smooth((t - STRIKE_END) / (1 - STRIKE_END))
		end

		for key, motor in swing.joints do
			motor.Transform = motor.Transform:Lerp(target[key], weight)
		end
		if swing.trail then
			swing.trail.Enabled = t >= TRAIL_FROM and t <= TRAIL_TO
		end
	end
end

-- Lanza el tajo en ese personaje. Devuelve false si su esqueleto no es R15 (no se puede animar así).
function SwingAnim.play(character: Model?, cooldown: number): boolean
	if not character then
		return false
	end
	local joints = findJoints(character)
	if not joints then
		return false
	end
	stop(character)

	local now = os.clock()
	local combo = combos[character]
	local index = if combo and now - combo.time < COMBO_RESET then combo.index % #MOVES + 1 else 1
	combos[character] = { index = index, time = now }

	active[character] = {
		start = now,
		duration = math.max(cooldown * 1.15, MIN_DURATION),
		move = MOVES[index],
		joints = joints,
		trail = findTrail(character),
	}
	return true
end

function SwingAnim.start()
	RunService.Stepped:Connect(step)
	-- Tajos de los demás jugadores (el propio se lanza desde SwordController sin esperar al servidor).
	Remotes.SwingFx.OnClientEvent:Connect(function(other: Player)
		if other ~= Players.LocalPlayer then
			SwingAnim.play(other.Character, Upgrades.value("speed", other:GetAttribute("Upgrade_speed") or 0))
		end
	end)
end

return SwingAnim
