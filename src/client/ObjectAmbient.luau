-- Vida propia de los objetos más raros de las parcelas (Config.Destructibles del 7 en adelante): giran los
-- adornos de su modelo (anillos, esquirlas), flotan, la luz late y sueltan partículas y luz. Cuanto más raro,
-- más movimiento. Es solo adorno de este cliente: mueve las mallas de sus copias locales y no toca al servidor.
-- El modo rendimiento lo para (y apaga solo las partículas y luces).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Performance = require(script.Parent.Performance)

local ObjectAmbient = {}

local RANGE = 160 -- solo se animan los que están a menos de esto de la cámara

-- Por objeto (posición en Config.Destructibles): movimiento de cada papel de la malla y partículas.
-- spin = vueltas sobre Y en rad/s, bob = {amplitud en studs, velocidad}, pulse = el brillo late.
-- sparks = { partículas por segundo, velocidad hacia arriba, tamaño, textura }; light = brillo de la luz.
local EMBER = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local STYLES = {
	[7] = { motion = { Trim = { spin = 0.6, bob = { 0.3, 1.2 } }, Glow = { pulse = true } }, sparks = { 3, 3, 0.5, EMBER } },
	[8] = { motion = { Glow = { pulse = true }, Gem = { bob = { 0.15, 1.5 } } }, sparks = { 5, 4, 0.5, EMBER } },
	[9] = { motion = { Glow = { pulse = true } }, sparks = { 7, 5, 0.9, EMBER }, smoke = 2 },
	[10] = { motion = { Trim = { spin = 1.2 }, Gem = { spin = -0.5 }, Glow = { pulse = true } }, sparks = { 9, 3, 0.5, EMBER }, light = 1 },
	[11] = { motion = { Trim = { spin = 0.8 }, Glow = { pulse = true }, Gem = { spin = -0.6 } }, sparks = { 12, 5, 0.7, EMBER }, light = 1.5 },
	[12] = { motion = { Gem = { spin = 1.0 }, Trim = { spin = -0.8 }, Dark = { spin = 0.5 }, Glow = { pulse = true } }, sparks = { 12, 2, 0.6, EMBER }, smoke = 3, light = 1 },
	[13] = { motion = { Gem = { spin = 0.7, bob = { 0.5, 1.0 } }, Trim = { spin = -0.5, bob = { 0.3, 0.8 } }, Glow = { pulse = true }, Dark = { spin = 0.4 } }, sparks = { 14, 5, 0.7, EMBER }, light = 2 },
	[14] = { motion = { Body = { spin = 1.4 }, Trim = { spin = -1.0 }, Gem = { spin = 0.6 }, Dark = { spin = -0.7 }, Glow = { pulse = true } }, sparks = { 16, 4, 0.7, EMBER }, light = 2 },
	[15] = { motion = { Trim = { spin = 0.9 }, Glow = { spin = -1.2, pulse = true }, Gem = { spin = 0.5, bob = { 0.4, 1.0 } } }, sparks = { 20, 6, 0.9, EMBER }, light = 2.5 },
	[16] = { motion = { Glow = { spin = 0.9, pulse = true }, Trim = { spin = -0.5, bob = { 0.3, 0.9 } }, Gem = { bob = { 0.3, 1.0 } } }, sparks = { 26, 7, 1.0, EMBER }, smoke = 3, light = 3 },
}

type Piece = { part: BasePart, offset: CFrame, base: number, spin: number, bob: { number }?, pulse: boolean }
local active: { [BasePart]: { pieces: { Piece }, phase: number } } = {}

local function emitter(parent: BasePart, color: Color3, spec)
	local rate, rise, size, texture = spec[1], spec[2], spec[3], spec[4]
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "AmbientSparks"
	sparks.Texture = texture
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Rate = rate
	sparks.Lifetime = NumberRange.new(1.2, 2.2)
	sparks.Speed = NumberRange.new(rise * 0.5, rise)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = parent
end

local function setup(part: BasePart)
	local index = part:GetAttribute("Index")
	local style = index and STYLES[index]
	if not style or active[part] or not part.Parent then
		return
	end
	local def = Config.Destructibles[index]
	local light = def.color:Lerp(Color3.new(1, 1, 1), 0.35)

	local pieces = {}
	for role, motion in style.motion do
		local mesh = part:FindFirstChild(role)
		if mesh and mesh:IsA("BasePart") then
			table.insert(pieces, {
				part = mesh,
				offset = part.CFrame:ToObjectSpace(mesh.CFrame),
				base = mesh.Transparency,
				spin = motion.spin or 0,
				bob = motion.bob,
				pulse = motion.pulse or false,
			})
		end
	end
	active[part] = { pieces = pieces, phase = math.random() * 6.28 }

	emitter(part, light, style.sparks)
	if style.smoke then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "AmbientSmoke"
		smoke.Texture = SMOKE
		smoke.Color = ColorSequence.new(def.color:Lerp(Color3.new(0, 0, 0), 0.6))
		smoke.Rate = style.smoke
		smoke.Lifetime = NumberRange.new(2, 3.5)
		smoke.Speed = NumberRange.new(1, 3)
		smoke.SpreadAngle = Vector2.new(30, 30)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		smoke.Parent = part
	end
	if style.light then
		local lamp = Instance.new("PointLight")
		lamp.Name = "AmbientLight"
		lamp.Color = light
		lamp.Brightness = style.light
		lamp.Range = 12 + 4 * style.light
		lamp.Parent = part
	end
end

function ObjectAmbient.start()
	local function watch(part: Instance)
		if part:IsA("BasePart") then
			-- El objeto y sus mallas llegan juntos, pero el atributo y los hijos pueden tardar un momento.
			task.delay(0.3, setup, part)
		end
	end
	CollectionService:GetInstanceAddedSignal("Destructible"):Connect(watch)
	for _, part in CollectionService:GetTagged("Destructible") do
		watch(part)
	end
	CollectionService:GetInstanceRemovedSignal("Destructible"):Connect(function(part)
		active[part :: BasePart] = nil
	end)

	RunService.Heartbeat:Connect(function()
		if Performance.get() then
			return
		end
		local camera = workspace.CurrentCamera
		local now = os.clock()
		for part, state in active do
			if not part.Parent then
				active[part] = nil
			elseif camera and (camera.CFrame.Position - part.Position).Magnitude < RANGE then
				local base = part.CFrame
				for _, piece in state.pieces do
					local frame = base
					if piece.spin ~= 0 then
						frame *= CFrame.Angles(0, (now + state.phase) * piece.spin, 0)
					end
					if piece.bob then
						frame += Vector3.new(0, math.sin((now + state.phase) * piece.bob[2]) * piece.bob[1], 0)
					end
					piece.part.CFrame = frame * piece.offset
					if piece.pulse then
						piece.part.Transparency = math.clamp(piece.base + 0.18 * math.sin((now + state.phase) * 3), 0, 1)
					end
				end
			end
		end
	end)
end

return ObjectAmbient
