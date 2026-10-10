-- Animación del golpe (no hay animaciones subidas): reproduce sobre las articulaciones del personaje los golpes
-- hechos en Blender (SwingClips, generado desde tools/blender) y enciende la estela del arma. Cada tipo de arma
-- tiene sus golpes normales, que se van alternando en combo; las armas Míticas, Secretas y Divinas hacen siempre
-- el golpe épico de su rareza. Vale para el jugador y para los demás.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local SwingClips = require(script.Parent.SwingClips)

local SwingAnim = {}

local MIN_DURATION = 0.26 -- con la velocidad de golpe al máximo el movimiento aún se tiene que ver
local COMBO_RESET = 0.7 -- segundos sin golpear (tras acabar el golpe) para volver al primer movimiento
local BLEND = 0.06 -- parte del golpe que tarda en entrar y salir de la animación que ya llevaba
local TRAIL = { 0.12, 0.85 } -- parte del golpe con la estela encendida
local STILL_SPEED = 2 -- por debajo de esta velocidad (studs/s) el personaje está parado y también se le mueven las piernas

-- Golpe épico de cada rareza (por la rareza de la copia equipada, con metal y tamaño, como su casilla).
-- Las de por encima de Divina no tienen golpe propio: hacen el de Divina.
local EPIC_BY_TIER = { ["Mítica"] = "Mitica", Secreta = "Secreta", Divina = "Divina", Eterna = "Divina", Primordial = "Divina", Absoluta = "Divina" }

-- Articulación -> pieza donde está y si solo se mueve con el personaje parado (las piernas: andando mandan sus pasos).
local JOINTS = {
	Root = { "LowerTorso" },
	Waist = { "UpperTorso" },
	Neck = { "Head" },
	RightHip = { "RightUpperLeg", true },
	RightKnee = { "RightLowerLeg", true },
	LeftHip = { "LeftUpperLeg", true },
	LeftKnee = { "LeftLowerLeg", true },
	RightShoulder = { "RightUpperArm" },
	RightElbow = { "RightLowerArm" },
	RightWrist = { "RightHand" },
	LeftShoulder = { "LeftUpperArm" },
	LeftElbow = { "LeftLowerArm" },
	LeftWrist = { "LeftHand" },
}

-- Las pistas pasan a CFrames una sola vez. COMBOS[tipo] = sus golpes normales en orden (<tipo>_1, <tipo>_2...);
-- IDLES[tipo] = su postura mientras se lleva sin golpear (<tipo>_idle; sin ella, la del Animator).
local CLIPS = {}
local COMBOS = {}
local IDLES = {}
for name, clip in SwingClips do
	local tracks = {}
	for joint, values in clip.joints do
		local frames = {}
		local stride = if joint == "Root" then 7 else 4
		for i = 1, #values, stride do
			local p = if stride == 7 then Vector3.new(values[i], values[i + 1], values[i + 2]) else Vector3.zero
			local q = i + stride - 4
			table.insert(frames, CFrame.new(p.X, p.Y, p.Z, values[q], values[q + 1], values[q + 2], values[q + 3]))
		end
		tracks[joint] = frames
	end
	CLIPS[name] = { name = name, frames = clip.frames, impacts = clip.impacts, tracks = tracks }
	local idleKind = string.match(name, "^(%a+)_idle$")
	if idleKind then
		-- Postura de reposo del arma (p. ej. la lanza en guardia): solo lo que se mueve de torso y brazos; las
		-- piernas y lo que no cambia siguen con la animación de andar.
		for joint, frames in tracks do
			local _, angle = frames[1]:ToAxisAngle()
			if joint == "Root" or JOINTS[joint][2] or math.abs(angle) < 1e-3 then
				tracks[joint] = nil
			end
		end
		IDLES[idleKind] = CLIPS[name]
	end
	local kind, index = string.match(name, "^(%a+)_(%d+)$")
	if kind then
		COMBOS[kind] = COMBOS[kind] or {}
		COMBOS[kind][tonumber(index)] = CLIPS[name]
	end
end

local active = {} -- [personaje] = golpe en curso
local combos = setmetatable({}, { __mode = "k" }) -- [personaje] = { kind, index, time, duration }
local idling = setmetatable({}, { __mode = "k" }) -- [personaje] = { clip, joints } de su postura de reposo

local function epicFor(character: Model, kind: string)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return nil
	end
	local ok, rarity = pcall(function()
		return Stats.rarity(Stats.equipped(player))
	end)
	local tier = ok and EPIC_BY_TIER[Rarity.tier(rarity).name]
	return tier and (CLIPS[kind .. "_" .. tier] or CLIPS["sword_" .. tier])
end

-- Articulaciones que mueve la animación, o nil si al personaje le falta alguna (no es R15).
local function findJoints(character: Model, clip)
	local found = {}
	for joint, frames in clip.tracks do
		local info = JOINTS[joint]
		local part = info and character:FindFirstChild(info[1])
		local motor = part and part:FindFirstChild(joint)
		-- Según el avatar, la articulación es un Motor6D o un AnimationConstraint; los dos tienen Transform.
		if not motor or not (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			return nil
		end
		table.insert(found, { motor = motor, frames = frames, still = info[2] == true, root = joint == "Root" })
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

		-- Parado se mueven también las piernas; al echar a andar se sueltan poco a poco.
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local moving = root ~= nil and (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > STILL_SPEED
		swing.still += ((if moving then 0 else 1) - swing.still) * math.min((now - swing.last) * 12, 1)
		swing.last = now

		-- Entre dos fotogramas se mezcla; andando no se agacha (no se hundiría en el suelo).
		local weight = smooth(math.min(t / BLEND, (1 - t) / BLEND, 1))
		local frame = t * (swing.clip.frames - 1) + 1
		local index = math.min(math.floor(frame), swing.clip.frames - 1)
		for _, joint in swing.joints do
			local cframe = joint.frames[index]:Lerp(joint.frames[index + 1], frame - index)
			if joint.root and cframe.Y < 0 then
				cframe -= Vector3.new(0, cframe.Y * (1 - swing.still), 0)
			end
			joint.motor.Transform = joint.motor.Transform:Lerp(cframe, if joint.still then weight * swing.still else weight)
		end
		setTrails(swing, t >= TRAIL[1] and t <= TRAIL[2])
	end

	-- Sin golpear, el arma que tenga postura de reposo la mantiene (los golpes de ese tipo empiezan y acaban en ella).
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or active[character] then
			continue
		end
		local def = Config.Swords[player:GetAttribute("SwordLevel") or 0]
		local clip = def and character:FindFirstChildWhichIsA("Tool") and IDLES[def.kind or "sword"]
		local idle = idling[character]
		if not clip then
			idling[character] = nil
			continue
		end
		if not idle or idle.clip ~= clip then
			local joints = findJoints(character, clip)
			if not joints then
				continue
			end
			idle = { clip = clip, joints = joints }
			idling[character] = idle
		end
		for _, joint in idle.joints do
			joint.motor.Transform = joint.frames[1]
		end
	end
end

-- Impacto contra el suelo (marcadores "impacto" de Blender): la cámara tiembla un momento y sale una onda de polvo.
local function slam(character: Model, cooldown: number)
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
	-- El estruendo sale del punto del suelo donde cae; el de los demás, algo más flojo.
	Sfx.play("slam", Sfx.cadence(cooldown) * (if character == Players.LocalPlayer.Character then 1 else 0.7), nil, ring.Position)
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
	local now = os.clock()
	local duration = math.max(cooldown * 1.15, MIN_DURATION)

	-- Golpe épico de la rareza o, si no, el siguiente del combo de su tipo.
	local clip = epicFor(character, kind)
	local index = 1
	if not clip then
		local moves = COMBOS[kind] or COMBOS.sword
		local combo = combos[character]
		if combo and combo.kind == kind and now - combo.time < combo.duration + COMBO_RESET then
			index = combo.index % #moves + 1
		end
		clip = moves[index]
	end

	local joints = findJoints(character, clip)
	if not joints then
		return false
	end
	stop(character)
	combos[character] = { kind = kind, index = index, time = now, duration = duration }
	local swing = {
		start = now,
		duration = duration,
		clip = clip,
		joints = joints,
		trails = findTrails(character),
		still = 0,
		last = now,
	}
	active[character] = swing
	for _, impact in clip.impacts do
		task.delay(duration * impact, function()
			if active[character] == swing then
				slam(character, cooldown)
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
			local cooldown, kind = Stats.cooldown(other), (Stats.weapon(other))
			SwingAnim.play(other.Character, cooldown, kind)
			Sfx.swing(kind, cooldown, other.Character, 0.7) -- el espadazo de otro: desde su sitio y algo más flojo
		end
	end)
end

return SwingAnim
