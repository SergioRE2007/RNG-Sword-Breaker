-- Rotura de los objetos de las parcelas (librería sin start()): cada objeto de Config.Destructibles se rompe en
-- trozos que se parecen a él (tablones de la caja, duelas y aros del barril, esquirlas de cristal, gotas de lava…),
-- con los mismos colores y materiales que su modelo (shared/ObjectModel.look), y cuanto más raro, más espectáculo:
-- onda en el suelo, destello, chispas y, en los últimos, un rayo de luz. Todo se crea en el cliente.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local ObjectModel = require(ReplicatedStorage.Shared.ObjectModel)

local ObjectBreak = {}

local LIFETIME = 2.6
local FADE = 0.5
local rng = Random.new()

-- Trozos de cada objeto (misma posición que en Config.Destructibles): { papel, forma, cuántos, tamaño } con el
-- tamaño relativo a la dimensión mayor del objeto. Formas: block, plank (tablón), wedge (cuña), shard
-- (esquirla), orb (bola), disc (disco o aro).
local STYLES = {
	{ { "Body", "plank", 6, 0.35 }, { "Dark", "plank", 4, 0.3 }, { "Trim", "block", 2, 0.12 } }, -- Caja
	{ { "Body", "plank", 7, 0.45 }, { "Dark", "disc", 3, 0.5 }, { "Trim", "disc", 1, 0.4 } }, -- Barril
	{ { "Body", "wedge", 6, 0.28 }, { "Body", "block", 4, 0.18 }, { "Dark", "block", 3, 0.2 } }, -- Roca
	{ { "Body", "block", 4, 0.28 }, { "Body", "wedge", 4, 0.22 }, { "Trim", "block", 2, 0.14 } }, -- Pilar
	{ { "Gem", "shard", 8, 0.32 }, { "Glow", "shard", 3, 0.16 }, { "Body", "wedge", 3, 0.2 } }, -- Cristal
	{ { "Body", "wedge", 6, 0.25 }, { "Dark", "block", 3, 0.18 }, { "Trim", "plank", 4, 0.35 }, { "Glow", "block", 4, 0.1 } }, -- Roca de armas
	{ { "Body", "block", 6, 0.28 }, { "Dark", "block", 4, 0.22 }, { "Glow", "plank", 4, 0.18 }, { "Trim", "shard", 3, 0.16 } }, -- Monolito
	{ { "Body", "block", 6, 0.25 }, { "Trim", "block", 4, 0.2 }, { "Glow", "shard", 3, 0.16 }, { "Gem", "wedge", 2, 0.14 } }, -- Obelisco
	{ { "Body", "wedge", 7, 0.3 }, { "Dark", "block", 4, 0.2 }, { "Glow", "orb", 6, 0.2 } }, -- Meteorito
	{ { "Gem", "shard", 6, 0.3 }, { "Glow", "orb", 4, 0.22 }, { "Trim", "disc", 3, 0.5 }, { "Body", "block", 4, 0.18 } }, -- Núcleo
	{ { "Body", "shard", 6, 0.4 }, { "Trim", "shard", 5, 0.3 }, { "Glow", "orb", 5, 0.2 }, { "Gem", "wedge", 3, 0.2 } }, -- Estrella
	{ { "Body", "orb", 4, 0.25 }, { "Glow", "disc", 4, 0.5 }, { "Trim", "disc", 3, 0.4 }, { "Dark", "orb", 3, 0.2 } }, -- Agujero negro
	{ { "Body", "shard", 8, 0.32 }, { "Glow", "shard", 5, 0.22 }, { "Gem", "shard", 4, 0.2 }, { "Dark", "block", 3, 0.14 }, { "Trim", "disc", 2, 0.3 } }, -- Fragmento
	{ { "Gem", "shard", 6, 0.3 }, { "Glow", "orb", 4, 0.2 }, { "Body", "shard", 6, 0.16 }, { "Trim", "disc", 3, 0.4 } }, -- Singularidad
	{ { "Body", "shard", 8, 0.34 }, { "Gem", "shard", 5, 0.3 }, { "Glow", "orb", 5, 0.2 }, { "Trim", "disc", 4, 0.4 } }, -- Origen
	{ { "Body", "shard", 8, 0.34 }, { "Gem", "shard", 6, 0.3 }, { "Glow", "shard", 5, 0.24 }, { "Glow", "orb", 4, 0.16 }, { "Trim", "disc", 4, 0.4 } }, -- Infinito
}

local function newPart(shape: string, s: number): BasePart
	local part: BasePart
	if shape == "wedge" then
		part = Instance.new("WedgePart")
		part.Size = Vector3.new(s, s * 0.8, s)
	elseif shape == "shard" then
		part = Instance.new("WedgePart")
		part.Size = Vector3.new(s * 0.22, s * 1.2, s * 0.5)
	elseif shape == "plank" then
		part = Instance.new("Part")
		part.Size = Vector3.new(s * 0.3, s * 1.1, s * 0.12)
	elseif shape == "orb" then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * s * 0.55
		part = ball
	elseif shape == "disc" then
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(s * 0.12, s, s)
		part = disc
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1))
	end
	return part
end

local function fade(part: BasePart, delay: number)
	task.delay(delay, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(FADE), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(part, delay + FADE)
end

local function flash(shape: Enum.PartType, cframe: CFrame, from: Vector3, to: Vector3, color: Color3, transparency: number, time: number)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = from
	part.CFrame = cframe
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = to, Transparency = 1 }):Play()
	Debris:AddItem(part, time + 0.1)
end

-- Espectáculo de más al romperse un objeto de rareza `quality` (posición en Config.ObjectRarities), del color de esa
-- rareza y cada vez mayor: ondas en el suelo y chispas (Poco común y Rara), destello y luz (Épica), rayo de luz
-- hacia el cielo (Legendaria) y una segunda explosión (Mítica). Los comunes no lo llevan.
function ObjectBreak.burst(cframe: CFrame, size: Vector3, quality: number)
	local rarity = Config.ObjectRarities[quality]
	if not rarity or quality <= 1 then
		return
	end
	local tier = quality - 1 -- 1 (Poco común) a 5 (Mítica)
	local color = rarity.color
	local light = color:Lerp(Color3.new(1, 1, 1), 0.35)
	local wide = math.max(size.X, size.Z)
	local ground = cframe.Position - Vector3.new(0, size.Y / 2 - 0.25, 0)
	local flat = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2)

	local function wave(delay: number)
		task.delay(delay, function()
			flash(Enum.PartType.Cylinder, flat, Vector3.new(0.25, wide, wide), Vector3.new(0.25, wide * (2.5 + tier), wide * (2.5 + tier)), color, 0.25, 0.5 + tier * 0.06)
		end)
	end
	for index = 1, math.min(tier, 4) do
		wave((index - 1) * 0.12)
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(cframe.Position.X, ground.Y + math.min(size.Y / 2, 6), cframe.Position.Z)
	anchor.Parent = workspace
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparks.LightEmission = 1
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.7, 1.2 + tier * 0.15)
	sparks.Speed = NumberRange.new(14 + tier * 6, 26 + tier * 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 2
	sparks.Acceleration = Vector3.new(0, -18, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 + tier * 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = anchor
	sparks:Emit(10 + tier * 14)
	Debris:AddItem(anchor, 2.5)

	if tier >= 3 then
		flash(Enum.PartType.Ball, CFrame.new(anchor.Position), Vector3.one * wide * 0.5, Vector3.one * wide * (1.6 + tier * 0.4), light, 0.35, 0.3)
		local lamp = Instance.new("PointLight")
		lamp.Color = color
		lamp.Brightness = tier
		lamp.Range = 16 + tier * 6
		lamp.Parent = anchor
		TweenService:Create(lamp, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	end
	if tier >= 4 then
		local thick = 2 + tier
		flash(Enum.PartType.Cylinder, CFrame.new(ground + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(120, thick, thick), Vector3.new(120, 0.3, 0.3), light, 0.3, 0.9 + tier * 0.1)
	end
	if tier >= 5 then
		task.delay(0.25, function()
			if anchor.Parent then
				sparks:Emit(60)
			end
			flash(Enum.PartType.Ball, CFrame.new(anchor.Position), Vector3.one * wide, Vector3.one * wide * 4.5, light, 0.45, 0.45)
		end)
	end
end

-- Rompe el objeto `index` de Config.Destructibles que estaba en `cframe` con la caja `size`.
function ObjectBreak.play(cframe: CFrame, size: Vector3, index: number)
	local def = Config.Destructibles[index]
	local style = STYLES[index]
	if not (def and style) then
		return
	end
	local biggest = math.max(size.X, size.Y, size.Z)
	local rarity = index / #Config.Destructibles -- 0 a 1
	local light = def.color:Lerp(Color3.new(1, 1, 1), 0.35)
	local ground = cframe.Position - Vector3.new(0, size.Y / 2 - 0.2, 0)

	-- Onda en el suelo.
	flash(Enum.PartType.Cylinder, CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(0.3, biggest * 0.5, biggest * 0.5), Vector3.new(0.3, biggest * (2 + rarity * 2), biggest * (2 + rarity * 2)), light, 0.2, 0.45)
	-- Destello en el centro y, en los últimos, un rayo de luz hacia el cielo.
	if index >= 8 then
		flash(Enum.PartType.Ball, cframe, Vector3.one * biggest * 0.4, Vector3.one * biggest * (1.2 + rarity), light, 0.3, 0.25)
	end
	if index >= 13 then
		flash(Enum.PartType.Cylinder, CFrame.new(cframe.Position + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(80, biggest * 0.5, biggest * 0.5), Vector3.new(80, 0.2, 0.2), light, 0.35, 0.7)
	end

	-- Chispas del color del objeto.
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = cframe
	anchor.Parent = workspace
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(light)
	sparks.LightEmission = 1
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Speed = NumberRange.new(10 + rarity * 14, 22 + rarity * 22)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 + rarity * 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = anchor
	sparks:Emit(8 + math.floor(rarity * 30))
	Debris:AddItem(anchor, 1.5)

	-- Trozos con físicas.
	local force = 12 + math.sqrt(biggest) * 4
	for _, entry in style do
		local role, shape, count, relative = entry[1], entry[2], entry[3], entry[4]
		local color, material, transparency = ObjectModel.look(role, def)
		for _ = 1, count do
			local s = biggest * relative * rng:NextNumber(0.7, 1.15)
			local piece = newPart(shape, s)
			piece.Color = color
			piece.Material = material
			piece.Transparency = transparency
			piece.TopSurface = Enum.SurfaceType.Smooth
			piece.BottomSurface = Enum.SurfaceType.Smooth
			piece.CollisionGroup = "Debris"
			local offset = Vector3.new(
				rng:NextNumber(-0.4, 0.4) * size.X,
				rng:NextNumber(-0.4, 0.4) * size.Y,
				rng:NextNumber(-0.4, 0.4) * size.Z
			)
			piece.CFrame = (cframe * CFrame.new(offset)) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
			piece.Parent = workspace

			local outward = cframe:VectorToWorldSpace(offset)
			outward = Vector3.new(outward.X, 0, outward.Z)
			local direction = if outward.Magnitude > 0.01 then outward.Unit else Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
			local small = math.clamp(1.4 - relative, 0.7, 1.3) -- los trozos pequeños salen más lejos
			piece.AssemblyLinearVelocity = direction * force * rng:NextNumber(0.5, 1.2) * small
				+ Vector3.new(0, force * rng:NextNumber(0.6, 1.5), 0)
			piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
			-- La luz se apaga antes que la piedra.
			fade(piece, if role == "Glow" then LIFETIME * 0.6 else LIFETIME)
		end
	end
end

return ObjectBreak
