-- Auras de las armas: chispas, llamas, ascuas, bruma, cintas de luz girando y luz, más cuanto más rara es el arma.
-- El servidor solo marca la hoja con la etiqueta "WeaponAura" y los atributos Level y Scale (lo hace SwordModel);
-- aquí se crean los efectos, tanto en las armas de los jugadores como en las del expositor del hub.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Performance = require(script.Parent.Performance)

local WeaponAura = {}

local TAG = "WeaponAura"
local WHITE = Color3.new(1, 1, 1)

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Nivel de rareza (posición en Config.RarityTiers) desde el que aparece cada efecto.
local SPARKLES_FROM = 2 -- Poco común: chispas
local FLAMES_FROM = 3 -- Rara: llamas que suben por la hoja
local RIBBONS_FROM = 4 -- Épica: cintas de luz girando alrededor (una más por nivel, hasta 3)
local EMBERS_FROM = 5 -- Legendaria: ascuas que saltan y luz
local MIST_FROM = 6 -- Mítica: bruma de color alrededor
local RAINBOW_FROM = 7 -- Secreta: todo en arcoíris y la luz va cambiando de color
local HALO_FROM = 8 -- Divina: destellos grandes

local MAX_RIBBONS = 3

local auras = {} -- [hoja] = { ribbons = { { a, b, radius, speed, phase, half } }, light, rainbow }

local function tierIndex(rarity: number?): number
	local found = 1
	for index, tier in Config.RarityTiers do
		if (rarity or 0) >= tier.min then
			found = index
		end
	end
	return found
end

local function shift(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV((h + amount) % 1, math.max(s, 0.55), math.max(v, 0.9))
end

local function sequence(colors: { Color3 }): ColorSequence
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(points)
end

local function rainbow(offset: number): ColorSequence
	local colors = {}
	for step = 0, 5 do
		table.insert(colors, Color3.fromHSV((offset + step / 5 * 0.85) % 1, 0.75, 1))
	end
	return sequence(colors)
end

local function fade(from: number, peak: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(0.25, peak),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function emitter(blade: BasePart, name: string, texture: string, colors: ColorSequence): ParticleEmitter
	local item = Instance.new("ParticleEmitter")
	item.Name = name
	item.Texture = texture
	item.Color = colors
	item.LightEmission = 0.6 -- con 1 los colores se queman a blanco a plena luz
	item.Rotation = NumberRange.new(0, 360)
	item.Parent = blade
	return item
end

local function build(blade: BasePart)
	local def = Config.Swords[blade:GetAttribute("Level")]
	if not def or auras[blade] then
		return
	end
	-- "AuraTier" (si lo pone SwordModel) limita el aura a la de ese nivel de rareza, para que sea más suave.
	local tier = math.min(tierIndex(def.rarity), blade:GetAttribute("AuraTier") or math.huge)
	if tier < SPARKLES_FROM then
		return
	end
	local scale = blade:GetAttribute("Scale") or 1
	local tierColor = Config.RarityTiers[tier].color
	local isRainbow = tier >= RAINBOW_FROM

	-- Paleta: el color del arma, dos vecinos suyos, el de su rareza y blanco.
	-- Un arma gris o blanca no tiene tono propio: se usa el de su rareza.
	local _, saturation = def.color:ToHSV()
	local base = if saturation < 0.2 then tierColor else def.color
	local warm, cool = shift(base, 0.09), shift(base, -0.11)
	local colors = if isRainbow then rainbow(0) else sequence({ WHITE, shift(base, 0), warm, tierColor, cool })

	local sparkles = emitter(blade, "AuraSparkles", SPARKLES, colors)
	sparkles.Rate = 8 + tier * 5
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(1 * scale, 3 * scale)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.Size = fade(0, (0.45 + tier * 0.06) * scale)

	if tier >= FLAMES_FROM then
		-- Salen hacia la punta (cara de arriba de la hoja) y se quedan atrás al mover el arma.
		local flames = emitter(blade, "AuraFlames", FIRE, colors)
		flames.EmissionDirection = Enum.NormalId.Top
		flames.Rate = 10 + tier * 3
		flames.Lifetime = NumberRange.new(0.45, 0.9)
		flames.Speed = NumberRange.new(1.5 * scale, 3.5 * scale)
		flames.SpreadAngle = Vector2.new(45, 45)
		flames.Acceleration = Vector3.new(0, 4 * scale, 0)
		flames.RotSpeed = NumberRange.new(-90, 90)
		flames.Size = fade(0.4 * scale, (0.9 + tier * 0.12) * scale)
		flames.Transparency = NumberSequence.new(0.2, 1)
	end

	if tier >= EMBERS_FROM then
		local embers = emitter(blade, "AuraEmbers", SPARKLES, if isRainbow then rainbow(0.5) else sequence({ WHITE, warm, tierColor }))
		embers.Rate = 10 + tier * 2
		embers.Lifetime = NumberRange.new(0.3, 0.7)
		embers.Speed = NumberRange.new(4 * scale, 9 * scale)
		embers.Drag = 4
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Size = NumberSequence.new(0.3 * scale, 0)

		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = tierColor
		light.Range = (8 + tier) * scale
		light.Brightness = 1.5
		light.Parent = blade
	end

	if tier >= MIST_FROM then
		local mist = emitter(blade, "AuraMist", SMOKE, if isRainbow then rainbow(0.3) else sequence({ tierColor, cool, warm }))
		mist.Rate = 12
		mist.Lifetime = NumberRange.new(1, 1.7)
		mist.Speed = NumberRange.new(0.5 * scale, 1.5 * scale)
		mist.SpreadAngle = Vector2.new(180, 180)
		mist.RotSpeed = NumberRange.new(-40, 40)
		mist.Size = NumberSequence.new(1.5 * scale, 3.6 * scale)
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	if tier >= HALO_FROM then
		local halo = emitter(blade, "AuraHalo", SPARKLES, rainbow(0.15))
		halo.Rate = 6
		halo.Lifetime = NumberRange.new(0.8, 1.4)
		halo.Speed = NumberRange.new(0.2, 0.8)
		halo.SpreadAngle = Vector2.new(180, 180)
		halo.RotSpeed = NumberRange.new(-60, 60)
		halo.Size = fade(0, 2.4 * scale)
		halo.Transparency = NumberSequence.new(0.2, 1)
	end

	-- Cintas: dos puntos que giran alrededor de la hoja y suben y bajan, dejando una estela entre ellos.
	local ribbons = {}
	local half = blade.Size.Y / 2
	for index = 1, math.clamp(tier - RIBBONS_FROM + 1, 0, MAX_RIBBONS) do
		local a = Instance.new("Attachment")
		a.Name = "AuraRibbonA"
		a.Parent = blade
		local b = Instance.new("Attachment")
		b.Name = "AuraRibbonB"
		b.Parent = blade

		local trail = Instance.new("Trail")
		trail.Name = "AuraRibbon"
		trail.Attachment0 = a
		trail.Attachment1 = b
		trail.Color = if isRainbow then rainbow(index / MAX_RIBBONS) else sequence({ WHITE, ({ warm, tierColor, cool })[index], tierColor })
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Lifetime = 0.8
		trail.LightEmission = 0.6
		trail.FaceCamera = true
		trail.Parent = blade

		table.insert(ribbons, {
			a = a,
			b = b,
			radius = (1 + index * 0.35) * scale,
			width = 0.6 * scale,
			speed = (if index % 2 == 0 then -1 else 1) * (5 + index),
			phase = index * 2.1,
			half = half,
		})
	end

	auras[blade] = {
		ribbons = ribbons,
		light = if isRainbow then blade:FindFirstChild("AuraLight") else nil,
	}
end

local function step()
	if Performance.get() then return end -- modo rendimiento
	local now = os.clock()
	for blade, aura in auras do
		if not blade:IsDescendantOf(workspace) then
			continue
		end
		for _, ribbon in aura.ribbons do
			local angle = now * ribbon.speed + ribbon.phase
			local y = math.sin(now * 1.7 + ribbon.phase) * ribbon.half
			local x, z = math.cos(angle) * ribbon.radius, math.sin(angle) * ribbon.radius
			ribbon.a.Position = Vector3.new(x, y, z)
			ribbon.b.Position = Vector3.new(x, y + ribbon.width, z)
		end
		if aura.light then
			aura.light.Color = Color3.fromHSV(now * 0.25 % 1, 0.7, 1)
		end
	end
end

local function watch(blade: Instance)
	if not blade:IsA("BasePart") then
		return
	end
	if blade:GetAttribute("Level") then
		build(blade)
	else
		blade:GetAttributeChangedSignal("Level"):Once(function()
			build(blade)
		end)
	end
end

function WeaponAura.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(blade)
		auras[blade] = nil
	end)
	for _, blade in CollectionService:GetTagged(TAG) do
		watch(blade)
	end
	RunService.RenderStepped:Connect(step)
end

return WeaponAura
