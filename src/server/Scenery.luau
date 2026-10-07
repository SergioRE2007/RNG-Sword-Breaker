-- Ambiente y decorado: una isla tropical. Mar turquesa a cuadros, playa, césped a cuadros,
-- palmeras, rocas, colinas y nubes de fondo, caminos con balizas y la plaza del hub (vacía en el
-- centro, a petición del usuario). Todo es decoración: no afecta al juego.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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
	-- El cliente (Ambience) quita parte de estas piezas en móviles.
	CollectionService:AddTag(item, "GrassDetail")
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
	local stem = decor(part(parent, "Stem", Vector3.new(0.15, height, 0.15), CFrame.new(position + Vector3.new(0, 0.3 + height / 2, 0)), GRASS_TUFT[1], Enum.Material.SmoothPlastic))
	local head = decor(part(parent, "Petals", Vector3.one * 0.75, CFrame.new(position + Vector3.new(0, 0.3 + height, 0)), FLOWERS[rng:NextInteger(1, #FLOWERS)], Enum.Material.SmoothPlastic))
	head.Shape = Enum.PartType.Ball
	-- Tallo y flor comparten posición: el cliente (Ambience) quita en móviles las mismas por posición.
	CollectionService:AddTag(stem, "FlowerPiece")
	CollectionService:AddTag(head, "FlowerPiece")
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
	Lighting.ColorShift_Bottom = Color3.fromRGB(255, 225, 190)
	Lighting.GlobalShadows = true

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.16
	color.Contrast = 0.1
	color.TintColor = Color3.fromRGB(255, 248, 238)
	color.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	-- Niebla suave: lo lejano (montañas, islotes) se pierde en azul claro.
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.38
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
		baseplate.Transparency = 1 -- conserva el suelo invisible para no cambiar las f?sicas
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

	-- Fondo oscuro separado de la superficie transl?cida.
	decor(part(parent, "Seabed", Vector3.new(1920, 0.5, 1920), CFrame.new(0, -Config.Water.Depth, 0), SEA[1]:Lerp(Color3.new(0, 0, 0), 0.65), Enum.Material.SmoothPlastic))
	local cell = 80
	for row = -12, 11 do
		for column = -12, 11 do
			local center = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			if center.Magnitude > islandRadius - cell * 0.4 then
				local tile = decor(part(parent, "Sea", Vector3.new(cell, Config.Water.Depth, cell), CFrame.new(center + Vector3.new(0, 0.03 - Config.Water.Depth / 2, 0)), SEA[(row + column) % 2 + 1], Enum.Material.Glass))
				tile.Transparency = Config.Water.Transparency
				tile.Reflectance = 0.08
				tile:SetAttribute("Phase", row * 0.7 + column * 1.1)
				CollectionService:AddTag(tile, "SeaTile")
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
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light:SetAttribute("Base", 1.2)
	light.Brightness = 0
	light.Enabled = false
	light.Parent = bulb
	CollectionService:AddTag(light, "NightLight")
end

-- Estandarte: mástil con una bandera triangular que ondea (el cliente la mece con la etiqueta Sway).
local function banner(parent: Instance, position: Vector3, color: Color3)
	local pole = decor(part(parent, "BannerPole", Vector3.new(0.6, 14, 0.6), CFrame.new(position + Vector3.new(0, 7, 0)), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic))
	pole.CanCollide = true
	local ball = decor(part(parent, "BannerTop", Vector3.one * 1.3, CFrame.new(position + Vector3.new(0, 14.3, 0)), Color3.fromRGB(255, 205, 70), Enum.Material.SmoothPlastic))
	ball.Shape = Enum.PartType.Ball
	local facing = CFrame.Angles(0, math.atan2(position.X, position.Z) + math.pi / 2, 0)
	local top = position + Vector3.new(0, 12.4, 0)
	for index, tone in { color, color:Lerp(Color3.new(1, 1, 1), 0.35) } do
		-- Dos tiras de tela, la de abajo más corta, que cuelgan del mástil hacia un lado.
		local flag = part(parent, "Flag", Vector3.new(0.3, 2.6 - index * 0.6, 7 - index * 1.6), CFrame.new(top - Vector3.new(0, (index - 1) * 2.4, 0)) * facing * CFrame.new(0, 0, -(3.8 - index * 0.8)), tone, Enum.Material.Fabric)
		decor(flag)
		flag:SetAttribute("Pivot", top)
		flag:SetAttribute("Phase", position.X * 0.1)
		CollectionService:AddTag(flag, "Sway")
	end
end

-- Caja de madera con tapa y cantos más oscuros.
local function crate(parent: Instance, position: Vector3, size: number, turn: number)
	local cframe = CFrame.new(position + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, turn, 0)
	part(parent, "Crate", Vector3.one * size, cframe, Color3.fromRGB(196, 140, 78), Enum.Material.Wood)
	for _, offset in { -0.5, 0.5 } do
		part(parent, "CrateBand", Vector3.new(size * 1.04, size * 0.12, size * 1.04), cframe * CFrame.new(0, offset * size * 0.8, 0), Color3.fromRGB(120, 80, 45), Enum.Material.Wood)
	end
end

local function barrel(parent: Instance, position: Vector3)
	local body = disc(parent, "Barrel", position, 1.7, 0.4, 4.4, Color3.fromRGB(170, 112, 62), Enum.Material.Wood)
	body.CanCollide = true
	for _, height in { 1.2, 3.6 } do
		disc(parent, "BarrelBand", position, 1.78, height - 0.15, height + 0.15, Color3.fromRGB(70, 70, 82), Enum.Material.Metal)
	end
end

-- Seta grande de colores vivos.
local function mushroom(parent: Instance, position: Vector3)
	local height = rng:NextNumber(1.6, 3)
	decor(disc(parent, "MushroomStem", position, 0.5, 0.3, 0.3 + height, Color3.fromRGB(250, 240, 220), Enum.Material.SmoothPlastic))
	local capSize = height * rng:NextNumber(1.5, 2.1)
	local cap = decor(part(parent, "MushroomCap", Vector3.new(capSize, capSize * 0.6, capSize), CFrame.new(position + Vector3.new(0, 0.3 + height, 0)), Color3.fromRGB(235, 70, 80), Enum.Material.SmoothPlastic))
	cap.Shape = Enum.PartType.Ball
	for _ = 1, 3 do
		local dot = decor(part(parent, "MushroomDot", Vector3.one * capSize * 0.2, cap.CFrame * CFrame.new(rng:NextNumber(-0.3, 0.3) * capSize, capSize * 0.22, rng:NextNumber(-0.3, 0.3) * capSize), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
		dot.Shape = Enum.PartType.Ball
	end
end

-- Loma suave: bola de césped aplastada que rompe lo plano del suelo.
local function mound(parent: Instance, position: Vector3)
	local width = rng:NextNumber(14, 30)
	local item = decor(part(parent, "Mound", Vector3.new(width, rng:NextNumber(3, 6), width * rng:NextNumber(0.8, 1.3)), CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), GRASS[rng:NextInteger(1, 2)]:Lerp(Color3.new(1, 1, 0.8), rng:NextNumber(0, 0.25)), Enum.Material.Grass))
	item.Shape = Enum.PartType.Ball
end

-- Embarcadero de tablas hacia el mar, con postes, una barca y boyas.
local function pier(parent: Instance, angle: number, from: number, length: number)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local facing = CFrame.lookAt(Vector3.zero, direction).Rotation
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local planks = math.floor(length / 2)
	for index = 0, planks - 1 do
		local center = direction * (from + index * 2 + 1) + Vector3.new(0, 1.2, 0)
		part(parent, "Plank", Vector3.new(9, 0.5, 1.8), facing + center, if index % 2 == 0 then Color3.fromRGB(176, 128, 78) else Color3.fromRGB(160, 114, 68), Enum.Material.WoodPlanks)
	end
	for index = 0, planks - 1, 3 do
		for _, sign in { 1, -1 } do
			local base = direction * (from + index * 2 + 1) + side * sign * 4.2
			decor(part(parent, "PierPost", Vector3.new(0.9, 5.5, 0.9), CFrame.new(base + Vector3.new(0, 0.2, 0)), Color3.fromRGB(110, 76, 46), Enum.Material.Wood))
		end
	end
	-- Barca atada al lado del embarcadero.
	local boat = direction * (from + length * 0.7) + side * 9 + Vector3.new(0, 0.5, 0)
	local hull = part(parent, "BoatHull", Vector3.new(4.5, 1.8, 11), CFrame.lookAt(boat, boat + direction), Color3.fromRGB(235, 90, 70), Enum.Material.SmoothPlastic)
	hull.CanCollide = false
	local stripe = decor(part(parent, "BoatStripe", Vector3.new(4.7, 0.5, 11.2), hull.CFrame * CFrame.new(0, 0.55, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
	stripe.CanCollide = false
	decor(part(parent, "BoatMast", Vector3.new(0.4, 9, 0.4), hull.CFrame * CFrame.new(0, 5, -1), Color3.fromRGB(110, 76, 46), Enum.Material.Wood))
	decor(part(parent, "BoatSail", Vector3.new(0.2, 6.5, 4.5), hull.CFrame * CFrame.new(0, 5.6, 1.4), Color3.fromRGB(255, 250, 235), Enum.Material.Fabric))
	-- Boyas rojas y blancas flotando.
	for step = 1, 4 do
		local at = direction * (from + length + step * 9) + side * ((step % 2) * 2 - 1) * 14 + Vector3.new(0, 0.5, 0)
		local buoy = decor(part(parent, "Buoy", Vector3.one * 2.4, CFrame.new(at), if step % 2 == 0 then Color3.fromRGB(240, 70, 70) else Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
		buoy.Shape = Enum.PartType.Ball
	end
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

local function ring(count: number, radius: number, phase: number, callback: (Vector3, number) -> ())
	for index = 1, count do
		local angle = (index - 1 + phase) / count * math.pi * 2
		callback(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), index)
	end
end

-- El mapa se hace por código: en el lugar de Studio solo valen el Baseplate y el SpawnLocation de fábrica. Cualquier
-- otra pieza suelta en Workspace (puesta a mano o por accidente) se quita al arrancar: una placa de hierba de 2047
-- studs sin anclar, que estaba en el lugar, salía empujada hacia arriba y acababa flotando sobre toda la isla,
-- tapando el cielo.
local function clearLoose()
	for _, item in workspace:GetChildren() do
		if item:IsA("BasePart") and not item:IsA("Terrain") and not item:IsA("SpawnLocation") and item.Name ~= "Baseplate" then
			warn(`[Scenery] Quitada de Workspace una pieza que no es del juego: {item.Name} (tamaño {item.Size})`)
			item:Destroy()
		end
	end
end

function Scenery.start()
	clearLoose()
	if Config.Theme == "japan" then
		require(script.Parent.SceneryJapan).start()
		return
	end
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

	-- Manchas de arena más clara y oscura sobre la playa y la plaza, para que no sea un color liso.
	for _ = 1, 160 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(cfg.HubRadius - 12, islandRadius + beach - 3)
		local center = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local size = rng:NextNumber(3, 9)
		local patch = decor(disc(folder, "SandPatch", center, size, 0.47, 0.5, SAND:Lerp(if rng:NextNumber() < 0.5 then Color3.new(1, 1, 1) else Color3.fromRGB(205, 170, 105), 0.35), Enum.Material.SmoothPlastic))
		patch.Transparency = 0.35
	end

	-- Estandartes de colores en el borde del hub, entre las entradas de los caminos.
	ring(cfg.Count, cfg.HubRadius - 5, 0.5, function(position, index)
		banner(folder, position, Color3.fromHSV((index - 0.5) / cfg.Count, 0.7, 1))
	end)

	-- Cajas y barriles junto al arranque de cada camino.
	ring(cfg.Count, 1, 0, function(direction, index)
		local side = Vector3.new(-direction.Z, 0, direction.X)
		for _, sign in { 1, -1 } do
			local base = direction * (cfg.HubRadius + 16 + (index % 3) * 6) + side * sign * 15
			crate(folder, base, 3.4, rng:NextNumber(0, 1))
			crate(folder, base + side * sign * 3.4 + direction * 1.2, 2.6, rng:NextNumber(0, 1))
			crate(folder, base + Vector3.new(0, 3.4, 0), 2.2, rng:NextNumber(0, 1))
			barrel(folder, base - direction * 4.5 + side * sign * 1)
		end
	end)

	-- Setas y lomas repartidas por el césped libre.
	local extras = 0
	for _ = 1, 600 do
		if extras >= 70 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * (islandRadius - 10)
		local position = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if isOpen(position, 6) then
			extras += 1
			if extras <= 12 then
				mound(folder, position)
			else
				for _ = 1, rng:NextInteger(1, 3) do
					mushroom(folder, position + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
				end
			end
		end
	end

	-- Embarcaderos con barca en dos puntos de la costa.
	pier(folder, math.rad(18), islandRadius - 2, beach + 46)
	pier(folder, math.rad(200), islandRadius - 2, beach + 40)

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
			CollectionService:AddTag(fog, "FogBank") -- el modo rendimiento (cliente) los quita
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
