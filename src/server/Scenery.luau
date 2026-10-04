-- Ambiente y decorado: una isla tropical. Mar turquesa a cuadros, playa, césped a cuadros,
-- palmeras, rocas, colinas y nubes de fondo, caminos, farolas y un expositor en el hub con
-- las espadas más raras. Todo es decoración: no afecta al juego.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local Scenery = {}

local rng = Random.new(7) -- semilla fija: el decorado sale igual en todos los servidores

local SAND = Color3.fromRGB(245, 226, 165)
local GRASS = { Color3.fromRGB(96, 200, 90), Color3.fromRGB(82, 184, 80) }
local SEA = { Color3.fromRGB(50, 200, 225), Color3.fromRGB(72, 214, 234) }
local LEAVES = { Color3.fromRGB(50, 180, 95), Color3.fromRGB(70, 200, 110), Color3.fromRGB(40, 160, 110) }
local HILLS = { Color3.fromRGB(70, 150, 225), Color3.fromRGB(90, 185, 215), Color3.fromRGB(60, 125, 205) }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

-- Disco tumbado centrado en `center`, entre las alturas bottom y top.
local function disc(parent: Instance, name: string, center: Vector3, radius: number, bottom: number, top: number, color: Color3, material: Enum.Material): Part
	local item = part(parent, name, Vector3.new(top - bottom, radius * 2, radius * 2), CFrame.new(center.X, (top + bottom) / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function decor(item: Part): Part
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
	return item
end

local function setLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(90, 90, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 135, 150)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 210)
	Lighting.GlobalShadows = true

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.1
	color.Contrast = 0.08
	color.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Color = Color3.fromRGB(170, 230, 255)
	atmosphere.Decay = Color3.fromRGB(110, 190, 255)
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
end

-- El suelo de base pasa a ser el mar, con cuadros de dos tonos.
local function buildSea(parent: Instance, islandRadius: number)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Material = Enum.Material.SmoothPlastic
		baseplate.Color = SEA[1]
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child.Transparency = 1
			end
		end
	end
	-- El SpawnLocation de fábrica queda debajo de la máquina del gacha: se esconde.
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("BasePart") then
		spawn.Transparency = 1
		spawn.CanCollide = false
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child.Transparency = 1
			end
		end
	end

	local cell = 80
	for row = -12, 11 do
		for column = -12, 11 do
			local center = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			if center.Magnitude > islandRadius - cell * 0.4 then
				decor(part(parent, "Sea", Vector3.new(cell, 0.1, cell), CFrame.new(center + Vector3.new(0, 0.03, 0)), SEA[(row + column) % 2 + 1], Enum.Material.SmoothPlastic))
			end
		end
	end
end

-- Isla: playa de arena y, encima, césped a cuadros.
local function buildIsland(parent: Instance, center: Vector3, radius: number, beach: number)
	disc(parent, "Beach", center, radius + beach, 0, 0.2, SAND, Enum.Material.Sand)
	disc(parent, "Grass", center, radius, 0, 0.3, GRASS[1], Enum.Material.SmoothPlastic)
	local cell = 24
	local reach = math.ceil(radius / cell)
	for row = -reach, reach do
		for column = -reach, reach do
			local offset = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			-- Solo las casillas que caben enteras dentro del césped.
			if (row + column) % 2 == 0 and offset.Magnitude + cell * 0.71 < radius then
				decor(part(parent, "GrassTile", Vector3.new(cell, 0.06, cell), CFrame.new(center + offset + Vector3.new(0, 0.3, 0)), GRASS[2], Enum.Material.SmoothPlastic))
			end
		end
	end
end

-- Palmera: tronco curvado por tramos y hojas largas en abanico.
local function palm(parent: Instance, position: Vector3)
	local height = rng:NextNumber(18, 28)
	local segments = 5
	local length = height / segments
	local bend = math.rad(rng:NextNumber(3, 8))
	local cframe = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for index = 1, segments do
		cframe *= CFrame.Angles(0, 0, bend)
		local width = 2.6 - index * 0.25
		part(parent, "Trunk", Vector3.new(width, length + 0.4, width), cframe * CFrame.new(0, length / 2, 0), Color3.fromRGB(150, 110, 75), Enum.Material.Wood)
		cframe *= CFrame.new(0, length, 0)
	end
	local top = CFrame.new(cframe.Position)
	local color = LEAVES[rng:NextInteger(1, #LEAVES)]
	local fronds = 7
	for index = 1, fronds do
		local frond = top * CFrame.Angles(0, index / fronds * math.pi * 2, 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -6)
		local leaf = part(parent, "Leaf", Vector3.new(3.4, 0.4, 12), frond, color, Enum.Material.SmoothPlastic)
		leaf.CanCollide = false
	end
end

local function rock(parent: Instance, position: Vector3)
	local size = rng:NextNumber(3, 7)
	local cframe = CFrame.new(position + Vector3.new(0, size * 0.3, 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1))
	part(parent, "Rock", Vector3.new(size, size * 0.8, size * 1.2), cframe, Color3.fromRGB(150, 160, 175), Enum.Material.Slate)
end

local function bush(parent: Instance, position: Vector3)
	local size = rng:NextNumber(4, 7)
	local item = part(parent, "Bush", Vector3.one * size, CFrame.new(position + Vector3.new(0, size * 0.25, 0)), LEAVES[rng:NextInteger(1, #LEAVES)], Enum.Material.Grass)
	item.Shape = Enum.PartType.Ball
	item.CanCollide = false
end

local function lamp(parent: Instance, position: Vector3, color: Color3)
	part(parent, "Post", Vector3.new(0.8, 7, 0.8), CFrame.new(position + Vector3.new(0, 3.5, 0)), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic)
	local bulb = part(parent, "Bulb", Vector3.one * 2.4, CFrame.new(position + Vector3.new(0, 7.8, 0)), color, Enum.Material.Neon)
	bulb.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = bulb
end

-- Expositor: pedestal con una espada gigante flotando y su rareza en un cartel.
local function showcase(parent: Instance, position: Vector3, sword)
	local tier = Rarity.tier(sword.rarity)
	disc(parent, "Pedestal", position, 5, 0.4, 2, Color3.fromRGB(245, 245, 250), Enum.Material.Marble)
	disc(parent, "PedestalTop", position, 4, 2, 2.6, tier.color, Enum.Material.SmoothPlastic)

	local base = CFrame.new(position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.atan2(position.X, position.Z), 0) * CFrame.Angles(0, 0, math.rad(12))
	local bladeLength = sword.bladeLength * 1.6
	decor(part(parent, "Handle", Vector3.new(0.9, 3, 0.9), base, Color3.fromRGB(70, 45, 30), Enum.Material.Wood))
	decor(part(parent, "Guard", Vector3.new(4, 0.7, 0.9), base * CFrame.new(0, 1.8, 0), Color3.fromRGB(235, 190, 60), Enum.Material.Metal))
	local blade = decor(part(parent, "Blade", Vector3.new(1.5, bladeLength, 0.4), base * CFrame.new(0, 2.1 + bladeLength / 2, 0), sword.color, sword.material))

	local light = Instance.new("PointLight")
	light.Color = tier.color
	light.Range = 16
	light.Parent = blade

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 70)
	gui.StudsOffset = Vector3.new(0, bladeLength / 2 + 4, 0)
	gui.MaxDistance = 220
	gui.Parent = blade
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.RichText = true
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 24
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = `<font color="#{tier.color:ToHex()}">1 entre {Format.short(sword.rarity)}</font>\n{sword.name}`
	label.Parent = gui
end

local function ring(count: number, radius: number, phase: number, callback: (Vector3, number) -> ())
	for index = 1, count do
		local angle = (index - 1 + phase) / count * math.pi * 2
		callback(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), index)
	end
end

function Scenery.start()
	setLighting()

	local cfg = Config.Plot
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = workspace

	local islandRadius = cfg.RingRadius + cfg.Size * 0.75 + 35
	local beach = 22
	buildSea(folder, islandRadius + beach)
	buildIsland(folder, Vector3.zero, islandRadius, beach)

	-- Caminos y farolas de cada parcela.
	ring(cfg.Count, 1, 0, function(direction, index)
		local color = Color3.fromHSV((index - 1) / cfg.Count, 0.65, 1)
		local from = cfg.HubRadius - 2
		local to = cfg.RingRadius - cfg.Size / 2
		local middle = direction * ((from + to) / 2) + Vector3.new(0, 0.2, 0)
		decor(part(folder, "Path", Vector3.new(12, 0.3, to - from), CFrame.lookAt(middle, middle + direction), SAND, Enum.Material.Sand))

		local side = Vector3.new(-direction.Z, 0, direction.X)
		lamp(folder, direction * (cfg.HubRadius - 3) + side * 8, color)
		lamp(folder, direction * (cfg.HubRadius - 3) - side * 8, color)
	end)

	-- Expositor del hub: las espadas más raras, en círculo alrededor del gacha.
	local shown = 6
	ring(shown, cfg.HubRadius * 0.55, 0.5, function(position, index)
		showcase(folder, position, Config.Swords[#Config.Swords - shown + index])
	end)

	-- Palmeras, arbustos y rocas entre las parcelas (huecos del anillo).
	ring(cfg.Count, cfg.HubRadius + 22, 0.5, function(position)
		palm(folder, position)
		bush(folder, position + Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9)))
	end)
	ring(cfg.Count, cfg.RingRadius + 8, 0.5, function(position)
		palm(folder, position)
		rock(folder, position + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12)))
		bush(folder, position + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12)))
	end)

	-- Borde de la isla: palmeras en el césped, rocas y arbustos sueltos.
	ring(26, islandRadius - 10, 0.3, function(position)
		palm(folder, position + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6)))
	end)
	ring(18, islandRadius + beach * 0.5, 0.1, function(position)
		if rng:NextNumber() < 0.5 then
			rock(folder, position)
		else
			palm(folder, position)
		end
	end)
	ring(30, islandRadius - 24, 0.7, function(position)
		bush(folder, position + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)))
	end)

	-- Islotes en el mar.
	ring(5, islandRadius + 150, 0.4, function(position)
		local size = rng:NextNumber(22, 36)
		disc(folder, "Islet", position, size, 0, 0.25, SAND, Enum.Material.Sand)
		disc(folder, "IsletGrass", position, size * 0.6, 0, 0.35, GRASS[1], Enum.Material.SmoothPlastic)
		palm(folder, position)
		palm(folder, position + Vector3.new(size * 0.3, 0, -size * 0.2))
		rock(folder, position + Vector3.new(-size * 0.3, 0, size * 0.25))
	end)

	-- Colinas azuladas en el horizonte y nubes.
	ring(14, 930, 0, function(position)
		local size = rng:NextNumber(200, 340)
		local hill = decor(part(folder, "Hill", Vector3.one * size, CFrame.new(position + Vector3.new(0, -size * 0.18, 0)), HILLS[rng:NextInteger(1, #HILLS)], Enum.Material.SmoothPlastic))
		hill.Shape = Enum.PartType.Ball
	end)
	ring(10, 480, 0.2, function(position)
		local height = rng:NextNumber(190, 260)
		for _ = 1, 3 do
			local size = rng:NextNumber(40, 70)
			local offset = Vector3.new(rng:NextNumber(-35, 35), height + rng:NextNumber(-8, 8), rng:NextNumber(-35, 35))
			local cloud = decor(part(folder, "Cloud", Vector3.one * size, CFrame.new(position + offset), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
			cloud.Shape = Enum.PartType.Ball
		end
	end)
end

return Scenery
