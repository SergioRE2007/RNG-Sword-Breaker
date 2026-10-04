-- Ambiente y decorado: una isla tropical. Mar turquesa a cuadros, playa, césped a cuadros,
-- palmeras, rocas, colinas y nubes de fondo, caminos con balizas, plaza del hub y un expositor con
-- las espadas más raras. Todo es decoración: no afecta al juego.
local CollectionService = game:GetService("CollectionService")
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
local MOUNTAINS = { Color3.fromRGB(95, 150, 170), Color3.fromRGB(110, 165, 175), Color3.fromRGB(85, 135, 165) }
local GRASS_TUFT = { Color3.fromRGB(60, 165, 70), Color3.fromRGB(75, 180, 75), Color3.fromRGB(110, 205, 90) }
local FLOWERS = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 130, 170), Color3.fromRGB(200, 150, 255) }
local SHALLOWS = Color3.fromRGB(120, 230, 235)

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

local function decor(item: BasePart): BasePart
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
	return item
end

local function wedge(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): WedgePart
	local item = Instance.new("WedgePart")
	item.Name = "Tuft"
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.Parent = parent
	decor(item)
	return item
end

-- Si un punto del césped está libre: fuera del hub, de las parcelas y de los caminos.
local function isOpen(position: Vector3, margin: number): boolean
	local cfg = Config.Plot
	if position.Magnitude < cfg.HubRadius + margin then
		return false
	end
	for index = 1, cfg.Count do
		local angle = (index - 1) / cfg.Count * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local along = position:Dot(direction)
		local across = math.abs(position:Dot(Vector3.new(-direction.Z, 0, direction.X)))
		if math.abs(along - cfg.RingRadius) < cfg.Size / 2 + margin and across < cfg.Size / 2 + margin then
			return false
		end
		if along > 0 and along < cfg.RingRadius and across < 12 + margin then
			return false
		end
	end
	return true
end

-- Mata de hierba: tres cuñas finas abiertas en abanico.
local function tuft(parent: Instance, position: Vector3)
	local color = GRASS_TUFT[rng:NextInteger(1, #GRASS_TUFT)]
	local turn = rng:NextNumber(0, math.pi * 2)
	for blade = 1, 3 do
		local height = rng:NextNumber(1.2, 2.2)
		local cframe = CFrame.new(position + Vector3.new(0, 0.3 + height / 2, 0))
			* CFrame.Angles(0, turn + blade * 2.1, 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), 0, 0)
		wedge(parent, Vector3.new(0.25, height, 0.8), cframe, color)
	end
end

-- Flor: tallo y una bola de color.
local function flower(parent: Instance, position: Vector3)
	local height = rng:NextNumber(0.9, 1.5)
	decor(part(parent, "Stem", Vector3.new(0.15, height, 0.15), CFrame.new(position + Vector3.new(0, 0.3 + height / 2, 0)), GRASS_TUFT[1], Enum.Material.SmoothPlastic))
	local head = decor(part(parent, "Petals", Vector3.one * 0.75, CFrame.new(position + Vector3.new(0, 0.3 + height, 0)), FLOWERS[rng:NextInteger(1, #FLOWERS)], Enum.Material.SmoothPlastic))
	head.Shape = Enum.PartType.Ball
end

-- Montaña lejana: un cubo con una esquina hacia arriba, medio hundido, con la punta nevada.
local MOUNTAIN_TILT = CFrame.Angles(math.rad(35.264), 0, 0) * CFrame.Angles(0, 0, math.rad(45))
local function mountain(parent: Instance, position: Vector3, size: number, height: number)
	local turn = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local reach = size * math.sqrt(3) / 2 -- del centro del cubo a la esquina
	local peak = position + Vector3.new(0, height, 0)
	local color = MOUNTAINS[rng:NextInteger(1, #MOUNTAINS)]
	decor(part(parent, "Mountain", Vector3.one * size, CFrame.new(peak - Vector3.new(0, reach, 0)) * turn * MOUNTAIN_TILT, color, Enum.Material.SmoothPlastic))
	local snow = size * 0.28
	decor(part(parent, "Snow", Vector3.one * snow, CFrame.new(peak - Vector3.new(0, snow * math.sqrt(3) / 2 - 0.5, 0)) * turn * MOUNTAIN_TILT, Color3.fromRGB(245, 250, 255), Enum.Material.SmoothPlastic))
end

-- Disco tumbado centrado en `center`, entre las alturas bottom y top.
local function disc(parent: Instance, name: string, center: Vector3, radius: number, bottom: number, top: number, color: Color3, material: Enum.Material): Part
	local item = part(parent, name, Vector3.new(top - bottom, radius * 2, radius * 2), CFrame.new(center.X, (top + bottom) / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
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

	-- Niebla suave: lo lejano (montañas, islotes) se pierde en azul claro.
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(185, 232, 255)
	atmosphere.Decay = Color3.fromRGB(120, 195, 255)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.8
	atmosphere.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.035
	rays.Spread = 0.5
	rays.Parent = Lighting

	-- Desenfoque leve de lo muy lejano, para que se vea como una ilustración.
	local focus = Instance.new("DepthOfFieldEffect")
	focus.FarIntensity = 0.22
	focus.FocusDistance = 140
	focus.InFocusRadius = 160
	focus.NearIntensity = 0
	focus.Parent = Lighting
	Lighting.ShadowSoftness = 0.35
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
	-- Agua poco profunda alrededor de la playa, y espuma en la orilla (el cliente la hace latir).
	decor(disc(parent, "Shallows", center, radius + beach + 26, 0, 0.12, SHALLOWS, Enum.Material.SmoothPlastic))
	local shore = radius + beach
	local pieces = 110
	for index = 1, pieces do
		local angle = index / pieces * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * (shore + 1.5), 0.16, math.sin(angle) * (shore + 1.5))
		local foam = decor(part(parent, "Foam", Vector3.new(3, 0.08, 2 * math.pi * shore / pieces + 0.6), CFrame.new(position) * CFrame.Angles(0, -angle, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
		foam.Transparency = 0.3
		foam:SetAttribute("Phase", angle * 3)
		CollectionService:AddTag(foam, "Foam")
	end
	disc(parent, "Beach", center, radius + beach, 0, 0.2, SAND, Enum.Material.Sand)
	disc(parent, "Grass", center, radius, 0, 0.3, GRASS[1], Enum.Material.Grass)
	local cell = 24
	local reach = math.ceil(radius / cell)
	for row = -reach, reach do
		for column = -reach, reach do
			local offset = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			-- Solo las casillas que caben enteras dentro del césped.
			if (row + column) % 2 == 0 and offset.Magnitude + cell * 0.71 < radius then
				decor(part(parent, "GrassTile", Vector3.new(cell, 0.06, cell), CFrame.new(center + offset + Vector3.new(0, 0.3, 0)), GRASS[2], Enum.Material.Grass))
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
	local phase = rng:NextNumber(0, math.pi * 2)
	for index = 1, fronds do
		local frond = top * CFrame.Angles(0, index / fronds * math.pi * 2, 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -6)
		local leaf = part(parent, "Leaf", Vector3.new(3.4, 0.4, 12), frond, color, Enum.Material.SmoothPlastic)
		leaf.CanCollide = false
		-- El cliente (Ambience) las mece alrededor de la copa.
		leaf:SetAttribute("Pivot", top.Position)
		leaf:SetAttribute("Phase", phase)
		CollectionService:AddTag(leaf, "Sway")
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
	-- En un modelo propio para que el cliente (Ambience) la haga girar y flotar.
	local holder = Instance.new("Model")
	holder.Name = "ShowcaseSword"
	holder.Parent = parent
	local _, blade = SwordModel.build(level, holder, base * CFrame.Angles(0, math.rad(90), 0), SHOWCASE_SCALE, true)
	holder.WorldPivot = CFrame.new(base.Position)
	CollectionService:AddTag(holder, "ShowcaseSword")

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

	-- Hierba y flores por el césped libre.
	local placed = 0
	for _ = 1, 4000 do
		if placed >= 700 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * (islandRadius - 6)
		local position = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if isOpen(position, 3) then
			placed += 1
			if placed % 4 == 0 then
				flower(folder, position)
				flower(folder, position + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)))
			else
				-- Matas en grupos de dos o tres.
				for _ = 1, rng:NextInteger(2, 3) do
					tuft(folder, position + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5)))
				end
			end
		end
	end

	-- Islotes en el mar.
	ring(5, islandRadius + 150, 0.4, function(position)
		local size = rng:NextNumber(22, 36)
		disc(folder, "Islet", position, size, 0, 0.25, SAND, Enum.Material.Sand)
		disc(folder, "IsletGrass", position, size * 0.6, 0, 0.35, GRASS[1], Enum.Material.SmoothPlastic)
		palm(folder, position)
		palm(folder, position + Vector3.new(size * 0.3, 0, -size * 0.2))
		rock(folder, position + Vector3.new(-size * 0.3, 0, size * 0.25))
	end)

	-- Cordilleras en el horizonte (la niebla las difumina) con bancos de niebla en la base.
	ring(11, 880, 0, function(position)
		local side = Vector3.new(-position.Z, 0, position.X).Unit
		for peak = -2, 2 do
			local size = rng:NextNumber(110, 190)
			local height = size * rng:NextNumber(0.75, 1.05) * (1 - math.abs(peak) * 0.18)
			mountain(folder, position + side * peak * size * 0.55 + position.Unit * rng:NextNumber(-40, 60), size, height)
		end
		for _ = 1, 3 do
			local fog = decor(part(folder, "Fog", Vector3.new(rng:NextNumber(260, 380), rng:NextNumber(30, 44), rng:NextNumber(90, 130)), CFrame.lookAt(position, Vector3.zero) * CFrame.new(rng:NextNumber(-120, 120), rng:NextNumber(14, 26), rng:NextNumber(-60, -10)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
			fog.Shape = Enum.PartType.Ball
			fog.Transparency = 0.2
		end
	end)
	ring(12, 600, 0.2, function(position)
		local height = rng:NextNumber(190, 260)
		for _ = 1, 3 do
			local size = rng:NextNumber(40, 70)
			local offset = Vector3.new(rng:NextNumber(-35, 35), height + rng:NextNumber(-8, 8), rng:NextNumber(-35, 35))
			local cloud = decor(part(folder, "Cloud", Vector3.one * size, CFrame.new(position + offset), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
			cloud.Shape = Enum.PartType.Ball
			CollectionService:AddTag(cloud, "Cloud")
		end
	end)
end

return Scenery
