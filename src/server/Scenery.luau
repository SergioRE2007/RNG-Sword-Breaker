-- Ambiente y decorado: una isla tropical. Mar turquesa a cuadros, playa, césped a cuadros,
-- palmeras, rocas, colinas y nubes de fondo, caminos con balizas, plaza del hub y un expositor con
-- las espadas más raras. Todo es decoración: no afecta al juego.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local SHOWCASE_SCALE = 2 -- tamaño de las espadas del expositor respecto a las de mano

local Scenery = {}

local rng = Random.new(7) -- semilla fija: el decorado sale igual en todos los servidores

local SAND = Color3.fromRGB(245, 226, 165)
local SAND_DARK = Color3.fromRGB(232, 208, 145)
local CURB = Color3.fromRGB(70, 130, 230)
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
		-- Con CFrame y no con Position: al agrandarla, Studio la sube para que no se solape con
		-- nada y tapa la isla.
		baseplate.CFrame = CFrame.new(0, -baseplate.Size.Y / 2, 0)
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

-- Baliza del camino: poste blanco con una bola del color de la parcela. Sin brillo (el
-- usuario no quería luces encendidas en los caminos).
local function lamp(parent: Instance, position: Vector3, color: Color3)
	part(parent, "Post", Vector3.new(0.8, 6, 0.8), CFrame.new(position + Vector3.new(0, 3, 0)), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic)
	local bulb = part(parent, "Bulb", Vector3.one * 2, CFrame.new(position + Vector3.new(0, 6.6, 0)), color, Enum.Material.SmoothPlastic)
	bulb.Shape = Enum.PartType.Ball
end

-- Camino ancho de baldosas de arena en dos tonos, con un bordillo azul a cada lado (como las
-- vías de la captura de referencia) y balizas cada cierto trecho.
local function path(parent: Instance, direction: Vector3, from: number, to: number, color: Color3)
	local width = 18
	local tile = 9
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local facing = CFrame.lookAt(Vector3.zero, direction).Rotation
	local count = math.floor((to - from) / tile)
	for step = 0, count - 1 do
		for lane = 0, 1 do
			local center = direction * (from + (step + 0.5) * tile) + side * ((lane - 0.5) * tile) + Vector3.new(0, 0.42, 0)
			local shade = if (step + lane) % 2 == 0 then SAND else SAND_DARK
			decor(part(parent, "Path", Vector3.new(tile, 0.12, tile), facing + center, shade, Enum.Material.SmoothPlastic))
		end
	end
	local length = count * tile
	for _, sign in { 1, -1 } do
		local middle = direction * (from + length / 2) + side * sign * (width / 2 + 0.6) + Vector3.new(0, 0.6, 0)
		decor(part(parent, "Curb", Vector3.new(1.2, 0.5, length), facing + middle, CURB, Enum.Material.SmoothPlastic))
	end
	for distance = from + 12, from + length - 6, 36 do
		for _, sign in { 1, -1 } do
			lamp(parent, direction * distance + side * sign * (width / 2 + 3), color)
		end
	end
end

-- Plaza del hub: dos anillos de baldosas a cuadros (junto al gacha y junto al borde) y un
-- bordillo bajo en el borde, que no choca para no tapar las entradas.
local function plaza(parent: Instance, radius: number)
	for _, band in { { inner = 16, outer = 22 }, { inner = radius - 10, outer = radius - 2 } } do
		local middle = (band.inner + band.outer) / 2
		local count = math.floor(2 * math.pi * middle / 8)
		for index = 1, count do
			local angle = index / count * math.pi * 2
			local position = Vector3.new(math.cos(angle) * middle, 0.45, math.sin(angle) * middle)
			local shade = if index % 2 == 0 then SAND else SAND_DARK
			local arc = 2 * math.pi * middle / count + 0.3
			decor(part(parent, "PlazaTile", Vector3.new(band.outer - band.inner, 0.12, arc), CFrame.new(position) * CFrame.Angles(0, -angle, 0), shade, Enum.Material.SmoothPlastic))
		end
	end
	local count = 72
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * radius, 0.7, math.sin(angle) * radius)
		decor(part(parent, "HubCurb", Vector3.new(1.4, 0.6, 2 * math.pi * radius / count + 0.2), CFrame.new(position) * CFrame.Angles(0, -angle, 0), CURB, Enum.Material.SmoothPlastic))
	end
end

-- Expositor: pedestal con una espada gigante flotando y su rareza en un cartel.
local function showcase(parent: Instance, position: Vector3, level: number)
	local sword = Config.Swords[level]
	local tier = Rarity.tier(sword.rarity)
	disc(parent, "Pedestal", position, 5, 0.4, 2, Color3.fromRGB(245, 245, 250), Enum.Material.Marble)
	disc(parent, "PedestalTop", position, 4, 2, 2.6, tier.color, Enum.Material.SmoothPlastic)

	local base = CFrame.new(position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.atan2(position.X, position.Z), 0) * CFrame.Angles(0, 0, math.rad(12))
	local bladeLength = sword.bladeLength * SHOWCASE_SCALE
	-- El modelo es ancho en Z: se gira para que enseñe la cara plana hacia el hub.
	local _, blade = SwordModel.build(level, parent, base * CFrame.Angles(0, math.rad(90), 0), SHOWCASE_SCALE, true)

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

	plaza(folder, cfg.HubRadius)

	-- Camino del hub a cada parcela, con balizas del color de la parcela.
	ring(cfg.Count, 1, 0, function(direction, index)
		local color = Color3.fromHSV((index - 1) / cfg.Count, 0.65, 1)
		path(folder, direction, cfg.HubRadius, cfg.RingRadius - cfg.Size / 2, color)
	end)

	-- Expositor del hub: las espadas más raras, en círculo alrededor del gacha.
	local shown = 6
	local rarest = {}
	for level, sword in Config.Swords do
		if sword.rarity then
			table.insert(rarest, level)
		end
	end
	table.sort(rarest, function(a, b)
		return Config.Swords[a].rarity < Config.Swords[b].rarity
	end)
	ring(shown, cfg.HubRadius * 0.55, 0.5, function(position, index)
		local level = rarest[#rarest - shown + index]
		if level then
			showcase(folder, position, level)
		end
	end)

	-- Palmeras, arbustos y rocas entre las parcelas (huecos del anillo).
	ring(cfg.Count, cfg.HubRadius + 25, 0.5, function(position)
		palm(folder, position)
		bush(folder, position + Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9)))
	end)
	for _, distance in { (cfg.HubRadius + cfg.RingRadius) / 2 + 20, cfg.RingRadius, cfg.RingRadius + 45 } do
		ring(cfg.Count, distance, 0.5, function(position)
			palm(folder, position)
			palm(folder, position + Vector3.new(rng:NextNumber(-16, 16), 0, rng:NextNumber(-16, 16)))
			rock(folder, position + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)))
			bush(folder, position + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)))
		end)
	end

	-- Borde de la isla: palmeras en el césped, rocas y arbustos sueltos.
	ring(40, islandRadius - 10, 0.3, function(position)
		palm(folder, position + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6)))
	end)
	ring(28, islandRadius + beach * 0.5, 0.1, function(position)
		if rng:NextNumber() < 0.5 then
			rock(folder, position)
		else
			palm(folder, position)
		end
	end)
	ring(46, islandRadius - 24, 0.7, function(position)
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
	ring(16, 1100, 0, function(position)
		local size = rng:NextNumber(200, 340)
		local hill = decor(part(folder, "Hill", Vector3.one * size, CFrame.new(position + Vector3.new(0, -size * 0.18, 0)), HILLS[rng:NextInteger(1, #HILLS)], Enum.Material.SmoothPlastic))
		hill.Shape = Enum.PartType.Ball
	end)
	ring(12, 600, 0.2, function(position)
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
