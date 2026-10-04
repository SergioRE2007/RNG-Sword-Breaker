-- Construye el modelo de una espada con piezas: hoja con filo, nervio y punta, guarda, empuñadura y pomo.
-- Lo usan el servidor (la espada en la mano) y el decorado (expositor del hub).
-- Ejes de la empuñadura: la hoja sube por +Y, es ancha en Z y fina en X.
local Config = require(script.Parent.Config)

local SwordModel = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local LEATHER = Color3.fromRGB(70, 45, 30)
local STEEL = Color3.fromRGB(75, 78, 88)
local GOLD = Color3.fromRGB(235, 190, 60)

local GLOWING = { [Enum.Material.Neon] = true, [Enum.Material.ForceField] = true }

local FANCY_FROM = 4 -- desde aquí la guarda es dorada, con cuernos y gema
local SHARDS_FROM = 10 -- desde aquí flotan esquirlas junto a la hoja

local BLADE_BASE = 0.84 -- altura a la que empieza la hoja sobre el centro de la empuñadura

-- Devuelve la empuñadura ("Handle") y el cuerpo de la hoja ("Blade").
-- `anchored` = pieza de decorado: ancladas y sin soldar ni estela.
function SwordModel.build(level: number, parent: Instance, origin: CFrame, scale: number, anchored: boolean): (BasePart, BasePart)
	local def = Config.Swords[level]
	local length = def.bladeLength
	local width = 0.6 + level * 0.025
	local glowing = GLOWING[def.material] == true
	local fancy = level >= FANCY_FROM

	local edgeColor = def.color:Lerp(WHITE, 0.45)
	local darkColor = def.color:Lerp(BLACK, 0.35)
	local trimColor = if level == 1 then Color3.fromRGB(110, 75, 45) elseif fancy then GOLD else STEEL
	local trimMaterial = if level == 1 then Enum.Material.Wood else Enum.Material.Metal

	local handle: BasePart? = nil
	local function add(className: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
		local part = Instance.new(className) :: BasePart
		part.Name = name
		part.Size = size * scale
		part.CFrame = origin * (CFrame.new(offset.Position * scale) * offset.Rotation)
		part.Color = color
		part.Material = material
		part.Anchored = anchored
		part.CanCollide = false
		part.Massless = true
		part.CastShadow = handle == nil
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if handle then
			part.CanTouch = false
			part.CanQuery = false
			if not anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = part
			end
		else
			handle = part
		end
		part.Parent = parent
		return part
	end

	-- Punta: dos cuñas espalda con espalda que cierran una capa de la hoja.
	local function tip(name: string, thickness: number, layerWidth: number, height: number, color: Color3, material: Enum.Material)
		local y = BLADE_BASE + length + height / 2
		local size = Vector3.new(thickness, height, layerWidth / 2)
		add("WedgePart", name, size, CFrame.new(0, y, -layerWidth / 4), color, material)
		add("WedgePart", name, size, CFrame.new(0, y, layerWidth / 4) * CFrame.Angles(0, math.pi, 0), color, material)
	end

	-- Empuñadura y pomo.
	add("Part", "Handle", Vector3.new(0.32, 1.2, 0.32), CFrame.identity, LEATHER, if level == 1 then Enum.Material.Wood else Enum.Material.Fabric)
	for _, y in { -0.32, 0, 0.32 } do
		add("Part", "Wrap", Vector3.new(0.38, 0.1, 0.38), CFrame.new(0, y, 0), LEATHER:Lerp(BLACK, 0.4), Enum.Material.Fabric)
	end
	local pommel = add("Part", "Pommel", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, -0.78, 0), trimColor, trimMaterial) :: Part
	pommel.Shape = Enum.PartType.Ball

	-- Guarda.
	local guardLength = if fancy then 1.9 else 1.5
	add("Part", "Guard", Vector3.new(0.34, 0.24, guardLength), CFrame.new(0, 0.72, 0), trimColor, trimMaterial)
	for _, side in { -1, 1 } do
		add("Part", "GuardCap", Vector3.new(0.42, 0.36, 0.25), CFrame.new(0, 0.72, side * guardLength / 2), trimColor, trimMaterial)
		if fancy then
			add("Part", "GuardHorn", Vector3.new(0.3, 0.6, 0.2), CFrame.new(0, 1.02, side * (guardLength / 2 + 0.06)) * CFrame.Angles(side * math.rad(25), 0, 0), trimColor, trimMaterial)
		end
	end
	if fancy then
		local gem = add("Part", "Gem", Vector3.new(0.46, 0.46, 0.46), CFrame.new(0, 0.72, 0), def.color, if glowing then Enum.Material.Neon else Enum.Material.Glass) :: Part
		gem.Shape = Enum.PartType.Ball
	end

	-- Hoja: cuerpo grueso, filo más ancho y fino, y nervio central en relieve.
	local center = CFrame.new(0, BLADE_BASE + length / 2, 0)
	local coreWidth = width * 0.62
	local blade = add("Part", "Blade", Vector3.new(0.2, length, coreWidth), center, def.color, def.material)
	add("Part", "Edge", Vector3.new(0.08, length, width), center, edgeColor, def.material)
	add("Part", "Fuller", Vector3.new(0.27, length * 0.7, width * 0.16), CFrame.new(0, BLADE_BASE + length * 0.38, 0), if glowing then edgeColor else darkColor, def.material)
	tip("Tip", 0.2, coreWidth, coreWidth * 1.3, def.color, def.material)
	tip("EdgeTip", 0.08, width, width * 1.3, edgeColor, def.material)

	if level >= SHARDS_FROM then
		for index, height in { 0.22, 0.42 } do
			for _, side in { -1, 1 } do
				local offset = CFrame.new(0, BLADE_BASE + length * height, side * (width / 2 + 0.4)) * CFrame.Angles(side * math.rad(-18), 0, 0)
				add("Part", "Shard", Vector3.new(0.1, 1 - index * 0.25, 0.22), offset, edgeColor, Enum.Material.Neon)
			end
		end
	end

	if glowing then
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Range = 9 * scale
		light.Brightness = 1.2
		light.Parent = blade

		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Color = ColorSequence.new(edgeColor)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.18 * scale, 0)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(0.5, 0.9)
		sparks.Speed = NumberRange.new(0.3, 1)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 8
		sparks.Parent = blade
	end

	if not anchored then
		-- Estela del tajo: el cliente la enciende mientras dura el golpe.
		local base = Instance.new("Attachment")
		base.Name = "TrailBase"
		base.Position = Vector3.new(0, -length * scale * 0.4, 0)
		base.Parent = blade
		local point = Instance.new("Attachment")
		point.Name = "TrailTip"
		point.Position = Vector3.new(0, length * scale / 2 + width * scale, 0)
		point.Parent = blade

		local trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = base
		trail.Attachment1 = point
		trail.Color = ColorSequence.new(edgeColor, def.color)
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.Lifetime = 0.16
		trail.LightEmission = 0.6
		trail.Enabled = false
		trail.Parent = blade
	end

	return handle :: BasePart, blade
end

return SwordModel
