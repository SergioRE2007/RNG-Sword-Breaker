-- Decorado alternativo: un bosque japonés de atardecer (Config.Theme = "japan"). Cerezos y arces cargados de flor, pinos,
-- bambú, toriis rojos en la entrada de cada camino, linternas de piedra y farolillos, estanques con puente
-- y nenúfares, santuarios, pagodas, islotes con torii en el lago y el monte Fuji al fondo. Los colores son vivos y
-- hay luz dorada y rosa, bloom y niebla rosada. Las piezas con forma salen de shared/PropModel (modelos de
-- Blender); sin ese archivo se queda el suelo, la luz y el agua. Todo es decoración: no afecta al juego.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)

local SceneryJapan = {}

local rng = Random.new(11) -- semilla fija: el decorado sale igual en todos los servidores

local LAKE = { Color3.fromRGB(70, 205, 225), Color3.fromRGB(96, 222, 238) }
local SHALLOWS = Color3.fromRGB(150, 238, 240)
local GRAVEL = Color3.fromRGB(255, 236, 226)
local GRAVEL_DARK = Color3.fromRGB(246, 218, 208)
local GRASS = { Color3.fromRGB(122, 226, 132), Color3.fromRGB(104, 208, 120) }
local STONE = { Color3.fromRGB(238, 232, 244), Color3.fromRGB(216, 208, 230) }
local PETALS = { Color3.fromRGB(255, 150, 200), Color3.fromRGB(255, 190, 220), Color3.fromRGB(255, 225, 238), Color3.fromRGB(255, 120, 170) }
local MIST_MOUNTAINS = { Color3.fromRGB(176, 140, 205), Color3.fromRGB(196, 150, 200), Color3.fromRGB(150, 130, 200) }
local TREES = { "Sakura", "Sakura", "SakuraB", "SakuraB", "Maple", "Pine" }

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

-- Disco tumbado centrado en `center`, entre las alturas bottom y top.
local function disc(parent: Instance, name: string, center: Vector3, radius: number, bottom: number, top: number, color: Color3, material: Enum.Material): Part
	local item = part(parent, name, Vector3.new(top - bottom, radius * 2, radius * 2), CFrame.new(center.X, (top + bottom) / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function ring(count: number, radius: number, phase: number, callback: (Vector3, number) -> ())
	for index = 1, count do
		local angle = (index - 1 + phase) / count * math.pi * 2
		callback(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), index)
	end
end

local function turn(): CFrame
	return CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
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
		if along > 0 and along < cfg.RingRadius and across < 14 + margin then
			return false
		end
	end
	return true
end

local function setLighting()
	Lighting.ClockTime = 17.4 -- atardecer dorado
	Lighting.Brightness = 2.1
	Lighting.Ambient = Color3.fromRGB(128, 100, 136)
	Lighting.OutdoorAmbient = Color3.fromRGB(178, 136, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 176, 130)
	Lighting.ColorShift_Bottom = Color3.fromRGB(255, 190, 215)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.4

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.22
	color.Contrast = 0.1
	color.TintColor = Color3.fromRGB(255, 236, 238)
	color.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.32
	bloom.Size = 22
	bloom.Threshold = 1.25
	bloom.Parent = Lighting

	-- Cielo con muchas estrellas para la noche (el ciclo de client/DayCycle las deja ver al oscurecer).
	local sky = Instance.new("Sky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = true
	sky.SunTextureId = "rbxasset://sky/sun.jpg"
	sky.MoonTextureId = "rbxasset://sky/moon.jpg"
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 13
	sky.Parent = Lighting
	Lighting.GeographicLatitude = 35 -- Japón: el sol y la luna cruzan el cielo en un arco realista

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.36
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(255, 196, 218)
	atmosphere.Decay = Color3.fromRGB(255, 150, 140)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.9
	atmosphere.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.045
	rays.Spread = 0.6
	rays.Parent = Lighting

	local focus = Instance.new("DepthOfFieldEffect")
	focus.FarIntensity = 0.2
	focus.FocusDistance = 140
	focus.InFocusRadius = 170
	focus.NearIntensity = 0
	focus.Parent = Lighting
end

-- El suelo de base pasa a ser el lago, con cuadros de dos tonos (el cliente, Ambience, los hace latir).
local function buildLake(parent: Instance, islandRadius: number)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.CFrame = CFrame.new(0, -baseplate.Size.Y / 2, 0)
		baseplate.Material = Enum.Material.SmoothPlastic
		baseplate.Color = LAKE[1]
		baseplate.Transparency = 1 -- conserva el suelo invisible para no cambiar las f?sicas
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child.Transparency = 1
			end
		end
	end
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
	decor(part(parent, "Seabed", Vector3.new(1920, 0.5, 1920), CFrame.new(0, -Config.Water.Depth, 0), LAKE[1]:Lerp(Color3.new(0, 0, 0), 0.65), Enum.Material.SmoothPlastic))
	local cell = 80
	for row = -12, 11 do
		for column = -12, 11 do
			local center = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			if center.Magnitude > islandRadius - cell * 0.4 then
				local tile = decor(part(parent, "Sea", Vector3.new(cell, Config.Water.Depth, cell), CFrame.new(center + Vector3.new(0, 0.03 - Config.Water.Depth / 2, 0)), LAKE[(row + column) % 2 + 1], Enum.Material.Glass))
				tile.Transparency = Config.Water.Transparency
				tile.Reflectance = 0.08
				tile:SetAttribute("Phase", row * 0.7 + column * 1.1)
				CollectionService:AddTag(tile, "SeaTile")
			end
		end
	end
end

-- Isla: orilla de gravilla rosada y, encima, césped menta a cuadros.
local function buildIsland(parent: Instance, radius: number, beach: number)
	decor(disc(parent, "Shallows", Vector3.zero, radius + beach + 26, 0, 0.12, SHALLOWS, Enum.Material.SmoothPlastic))
	local shore = radius + beach
	local pieces = 110
	for index = 1, pieces do
		local angle = index / pieces * math.pi * 2
		local position = Vector3.new(math.cos(angle) * (shore + 1.5), 0.16, math.sin(angle) * (shore + 1.5))
		local foam = decor(part(parent, "Foam", Vector3.new(3, 0.08, 2 * math.pi * shore / pieces + 0.6), CFrame.new(position) * CFrame.Angles(0, -angle, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
		foam.Transparency = 0.3
		foam:SetAttribute("Phase", angle * 3)
		CollectionService:AddTag(foam, "Foam")
	end
	disc(parent, "Beach", Vector3.zero, radius + beach, 0, 0.2, GRAVEL, Enum.Material.Sand)
	disc(parent, "Grass", Vector3.zero, radius, 0, 0.3, GRASS[1], Enum.Material.Grass)
	local cell = 24
	local reach = math.ceil(radius / cell)
	for row = -reach, reach do
		for column = -reach, reach do
			local offset = Vector3.new((column + 0.5) * cell, 0, (row + 0.5) * cell)
			if (row + column) % 2 == 0 and offset.Magnitude + cell * 0.71 < radius then
				decor(part(parent, "GrassTile", Vector3.new(cell, 0.06, cell), CFrame.new(offset + Vector3.new(0, 0.3, 0)), GRASS[2], Enum.Material.Grass))
			end
		end
	end
end

-- Plaza del hub: dos anillos de losas lilas y rosadas y un bordillo bajo laqueado en rojo.
local function plaza(parent: Instance, radius: number)
	for _, band in { { inner = 16, outer = 22 }, { inner = radius - 10, outer = radius - 2 } } do
		local middle = (band.inner + band.outer) / 2
		local count = math.floor(2 * math.pi * middle / 8)
		for index = 1, count do
			local angle = index / count * math.pi * 2
			local position = Vector3.new(math.cos(angle) * middle, 0.45, math.sin(angle) * middle)
			local arc = 2 * math.pi * middle / count + 0.3
			decor(part(parent, "PlazaTile", Vector3.new(band.outer - band.inner, 0.12, arc), CFrame.new(position) * CFrame.Angles(0, -angle, 0), STONE[index % 2 + 1], Enum.Material.SmoothPlastic))
		end
	end
	local count = 72
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * radius, 0.7, math.sin(angle) * radius)
		decor(part(parent, "HubCurb", Vector3.new(1.4, 0.6, 2 * math.pi * radius / count + 0.2), CFrame.new(position) * CFrame.Angles(0, -angle, 0), Color3.fromRGB(238, 52, 62), Enum.Material.SmoothPlastic))
	end
end

-- Marca invisible donde el cliente (JapanFx) pone luciérnagas o humo de incienso.
local function spot(parent: Instance, name: string, position: Vector3, size: Vector3, tag: string)
	local item = decor(part(parent, name, size, CFrame.new(position), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
	item.Transparency = 1
	CollectionService:AddTag(item, tag)
end

local function lit(model: Model?, brightness: number, range: number)
	local paper = model and model:FindFirstChild("Paper")
	if paper then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light:SetAttribute("Base", brightness)
		light.Brightness = 0
		light.Enabled = false
		light.Range = range
		light.Parent = paper
		CollectionService:AddTag(paper, "LanternGlow") -- el cliente (JapanFx) la hace latir
		CollectionService:AddTag(light, "NightLight")
	end
end

-- Camino de losas hasta cada parcela, con un torii a la entrada y linternas de piedra a los lados.
local function path(parent: Instance, direction: Vector3, from: number, to: number, hue: Color3, first: boolean)
	local width = 18
	local tile = 9
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local facing = CFrame.lookAt(Vector3.zero, direction).Rotation
	local count = math.floor((to - from) / tile)
	for step = 0, count - 1 do
		for lane = 0, 1 do
			local center = direction * (from + (step + 0.5) * tile) + side * ((lane - 0.5) * tile) + Vector3.new(0, 0.42, 0)
			decor(part(parent, "Path", Vector3.new(tile - 0.5, 0.12, tile - 0.5), facing + center, STONE[(step + lane) % 2 + 1], Enum.Material.SmoothPlastic))
		end
	end
	local length = count * tile
	for _, sign in { 1, -1 } do
		local middle = direction * (from + length / 2) + side * sign * (width / 2 + 0.6) + Vector3.new(0, 0.6, 0)
		decor(part(parent, "Curb", Vector3.new(1.2, 0.5, length), facing + middle, Color3.fromRGB(238, 52, 62), Enum.Material.SmoothPlastic))
	end
	-- Solo el primer camino lleva torii (con sus farolillos y dos guardianes de piedra); los demás quedan abiertos.
	local gate = direction * (from + 8)
	if first and PropModel.place(parent, "Torii", CFrame.lookAt(gate, gate + direction), 1.15) then
		for _, sign in { 1, -1 } do
			local hang = CFrame.lookAt(gate, gate + direction) * CFrame.new(sign * 4.6, 8.2, 0)
			PropModel.place(parent, "Chochin", hang, 1.1, { Red = hue })
			local guard = gate + side * sign * 11
			PropModel.place(parent, "Komainu", CFrame.lookAt(guard, guard - direction), 1.0) -- mira hacia quien llega del hub
		end
	end
	for distance = from + 34, from + length - 8, 40 do
		for _, sign in { 1, -1 } do
			local spot = direction * distance + side * sign * (width / 2 + 3.5)
			lit(PropModel.place(parent, "StoneLantern", CFrame.lookAt(spot, spot + side * -sign), 1.1), 0.9, 16)
		end
	end
	for distance = from + 50, from + length - 20, 55 do
		for _, sign in { 1, -1 } do
			local spot = direction * distance + side * sign * (width / 2 + 17 + rng:NextNumber(0, 5))
			PropModel.place(parent, TREES[rng:NextInteger(1, #TREES)], CFrame.new(spot) * turn(), rng:NextNumber(0.9, 1.15))
		end
	end
end

-- Estanque con nenúfares y un puente rojo por encima.
local function pond(parent: Instance, center: Vector3, radius: number)
	disc(parent, "PondEdge", center, radius + 2.2, 0.2, 0.55, Color3.fromRGB(196, 200, 218), Enum.Material.SmoothPlastic)
	local water = disc(parent, "Pond", center, radius, 0.3, 0.7, Color3.fromRGB(86, 214, 238), Enum.Material.Glass)
	water.Transparency = Config.Water.Transparency
	water.CanCollide = false
	water.CanQuery = false
	water:SetAttribute("Phase", center.X * 0.07 + center.Z * 0.11)
	CollectionService:AddTag(water, "SeaTile")
	decor(disc(parent, "PondBed", center, radius, 0.31, 0.35, Color3.fromRGB(26, 82, 98), Enum.Material.SmoothPlastic))
	PropModel.place(parent, "Lotus", CFrame.new(center + Vector3.new(radius * 0.25, 0.7, -radius * 0.2)) * turn(), 1.2)
	PropModel.place(parent, "Lotus", CFrame.new(center + Vector3.new(-radius * 0.35, 0.7, radius * 0.3)) * turn(), 1.0)
	local turnBridge = rng:NextNumber(0, math.pi)
	PropModel.place(parent, "Bridge", CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, turnBridge, 0), radius / 10)
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2 + 0.3
		PropModel.place(parent, "Rocks", CFrame.new(center + Vector3.new(math.cos(angle) * (radius + 3), 0.3, math.sin(angle) * (radius + 3))) * turn(), rng:NextNumber(0.4, 0.8))
	end
	-- Valla de bambú alrededor, con un hueco al azar, y luciérnagas sobre el agua.
	local gap = rng:NextInteger(1, 24)
	for index = 1, 24 do
		if index ~= gap then
			local angle = index / 24 * math.pi * 2
			local spotPosition = center + Vector3.new(math.cos(angle) * (radius + 8), 0.3, math.sin(angle) * (radius + 8))
			PropModel.place(parent, "Fence", CFrame.lookAt(spotPosition, center), 1.0)
		end
	end
	spot(parent, "Fireflies", center + Vector3.new(0, 4, 0), Vector3.new(radius * 1.6, 6, radius * 1.6), "FireflySpot")
end

-- Pétalos caídos por el suelo: discos rosas pequeños, sobre todo cerca de los árboles.
local function petals(parent: Instance, around: Vector3, count: number, spread: number)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * spread
		local size = rng:NextNumber(0.8, 1.8)
		local item = decor(disc(parent, "Petal", around + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance), size, 0.31, 0.34, PETALS[rng:NextInteger(1, #PETALS)], Enum.Material.SmoothPlastic))
		item.Transparency = 0.1
	end
end

local function tree(parent: Instance, position: Vector3)
	-- Claro entre árboles: se salta una parte para que no sea un muro de copas.
	if rng:NextNumber() < 0.4 then
		return
	end
	local name = TREES[rng:NextInteger(1, #TREES)]
	local scale = rng:NextNumber(3.0, 4.5)
	PropModel.place(parent, name, CFrame.new(position) * turn(), scale)
	if name ~= "Pine" then
		petals(parent, position, 14, 9)
	end
end

local function grove(parent: Instance, position: Vector3)
	if rng:NextNumber() < 0.25 then
		spot(parent, "Fireflies", position + Vector3.new(0, 3, 0), Vector3.new(24, 5, 24), "FireflySpot")
	end
	for _ = 1, 3 do
		PropModel.place(parent, "Bamboo", CFrame.new(position + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))) * turn(), rng:NextNumber(0.9, 1.3))
	end
end

-- Montaña lejana, morada y rosada, con la punta nevada de color crema.
local MOUNTAIN_TILT = CFrame.Angles(math.rad(35.264), 0, 0) * CFrame.Angles(0, 0, math.rad(45))
local function mountain(parent: Instance, position: Vector3, size: number, height: number)
	local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local reach = size * math.sqrt(3) / 2
	local peak = position + Vector3.new(0, height, 0)
	decor(part(parent, "Mountain", Vector3.one * size, CFrame.new(peak - Vector3.new(0, reach, 0)) * spin * MOUNTAIN_TILT, MIST_MOUNTAINS[rng:NextInteger(1, #MIST_MOUNTAINS)], Enum.Material.SmoothPlastic))
	local snow = size * 0.26
	decor(part(parent, "Snow", Vector3.one * snow, CFrame.new(peak - Vector3.new(0, snow * math.sqrt(3) / 2 - 0.5, 0)) * spin * MOUNTAIN_TILT, Color3.fromRGB(255, 240, 246), Enum.Material.SmoothPlastic))
end

-- Animales que pasean por su rincón (el cliente, JapanFx, los mueve): velocidad en studs por segundo y tamaño.
local CRITTERS = {
	Panda = { speed = 1.3, scale = 1.0 },
	RedPanda = { speed = 2.0, scale = 1.0 },
	Tiger = { speed = 3.0, scale = 1.0 },
	Fox = { speed = 3.4, scale = 2.0 },
	Tanuki = { speed = 1.8, scale = 2.0 },
	Deer = { speed = 2.8, scale = 2.0 },
	Crane = { speed = 1.0, scale = 2.0 },
}

local function critter(parent: Instance, kind: string, position: Vector3, radius: number)
	local info = CRITTERS[kind]
	local home = Vector3.new(position.X, 0.3, position.Z)
	local model = PropModel.place(parent, kind, CFrame.new(home) * turn(), info.scale)
	if model then
		model:SetAttribute("Home", home)
		model:SetAttribute("Radius", radius)
		model:SetAttribute("Speed", info.speed * rng:NextNumber(0.85, 1.15))
		model:SetAttribute("Kind", kind)
		CollectionService:AddTag(model, "Critter")
	end
end

-- Un grupito de animales alrededor de un punto, a unos pasos unos de otros.
local function herd(parent: Instance, kind: string, center: Vector3, count: number, spread: number, radius: number)
	for index = 1, count do
		local angle = index / count * math.pi * 2 + rng:NextNumber(0, 1)
		critter(parent, kind, center + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread), radius)
	end
end

function SceneryJapan.start()
	setLighting()

	local cfg = Config.Plot
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = workspace

	local islandRadius = cfg.RingRadius + cfg.Size * 0.75 + 35
	local beach = 22
	buildLake(folder, islandRadius + beach)
	buildIsland(folder, islandRadius, beach)
	plaza(folder, cfg.HubRadius)

	-- Caminos con torii y linternas, con el farolillo del color de cada parcela.
	ring(cfg.Count, 1, 0, function(direction, index)
		path(folder, direction, cfg.HubRadius, cfg.RingRadius - cfg.Size / 2, Color3.fromHSV((index - 1) / cfg.Count, 0.7, 1), index == 1)
	end)

	-- Linternas de piedra en el borde del hub, entre las entradas.
	ring(cfg.Count * 2, cfg.HubRadius - 4, 0.5, function(position)
		local direction = position.Unit
		lit(PropModel.place(folder, "StoneLantern", CFrame.lookAt(position, position + direction), 1.0), 0.9, 15)
	end)

	-- Mástiles de koinobori (carpas de tela) en el borde interior de cada hueco entre caminos.
	ring(cfg.Count, cfg.HubRadius + 22, 0.5, function(position)
		PropModel.place(folder, "Koinobori", CFrame.new(position) * turn(), 0.85)
	end)

	-- Estanques con puente en dos huecos entre parcelas, santuarios y pagodas en otros.
	local middle = (cfg.HubRadius + cfg.RingRadius) / 2 + 5
	ring(cfg.Count, middle, 0.5, function(position, index)
		if index == 1 or index == 5 then
			pond(folder, position, 24)
		elseif index == 3 or index == 7 then
			PropModel.place(folder, "Shrine", CFrame.lookAt(position, Vector3.zero) * CFrame.new(0, 0, 0), 1.25)
			PropModel.place(folder, "Bonsai", CFrame.new(position + Vector3.new(9, 0.3, 6)), 1.2)
			PropModel.place(folder, "Bonsai", CFrame.new(position + Vector3.new(-9, 0.3, 6)), 1.2)
			lit(PropModel.place(folder, "StoneLantern", CFrame.new(position + Vector3.new(12, 0.3, -6)), 1.2), 1.1, 18)
			lit(PropModel.place(folder, "StoneLantern", CFrame.new(position + Vector3.new(-12, 0.3, -6)), 1.2), 1.1, 18)
			-- Jardín zen delante del santuario, con surcos de grava, y humo de incienso.
			local garden = position - position.Unit * 17
			decor(disc(folder, "ZenGarden", garden, 15, 0.3, 0.36, Color3.fromRGB(255, 247, 240), Enum.Material.Sand))
			for ringIndex = 1, 4 do
				decor(disc(folder, "ZenRing", garden, 15 - ringIndex * 3, 0.36, 0.4 + (ringIndex % 2) * 0.02, if ringIndex % 2 == 0 then Color3.fromRGB(255, 247, 240) else Color3.fromRGB(240, 222, 214), Enum.Material.Sand))
			end
			PropModel.place(folder, "Rocks", CFrame.new(garden + Vector3.new(3, 0.4, -2)) * turn(), 0.9)
			PropModel.place(folder, "Koinobori", CFrame.new(position + Vector3.new(-18, 0, 12)) * turn(), 0.9)
			PropModel.place(folder, "Koinobori", CFrame.new(position + Vector3.new(18, 0, 12)) * turn(), 0.9)
			spot(folder, "IncenseSpot", position + Vector3.new(0, 4, 0), Vector3.new(2, 1, 2), "SmokeSpot")
		else
			tree(folder, position)
			grove(folder, position + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)))
		end
	end)
	ring(cfg.Count, cfg.RingRadius + 82, 0.5, function(position, index)
		if index % 2 == 0 then
			PropModel.place(folder, "Pagoda", CFrame.lookAt(position, Vector3.zero), 1.15)
		else
			tree(folder, position)
			tree(folder, position + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18)))
		end
	end)

	-- Bosque: cerezos, arces y pinos por los huecos y el borde de la isla, y bambú en las orillas.
	for _, distance in { cfg.HubRadius + 28, cfg.RingRadius, cfg.RingRadius + 45 } do
		ring(cfg.Count, distance, 0.5, function(position)
			tree(folder, position + Vector3.new(rng:NextNumber(-16, 16), 0, rng:NextNumber(-16, 16)))
			tree(folder, position + Vector3.new(rng:NextNumber(-16, 16), 0, rng:NextNumber(-16, 16)))
			PropModel.place(folder, "Rocks", CFrame.new(position + Vector3.new(rng:NextNumber(-14, 14), 0.2, rng:NextNumber(-14, 14))) * turn(), rng:NextNumber(0.6, 1.2))
		end)
	end
	ring(46, islandRadius - 12, 0.3, function(position)
		tree(folder, position + Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7)))
	end)
	ring(34, islandRadius - 28, 0.7, function(position)
		grove(folder, position + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)))
	end)

	-- Sin animales (quitados a petición del usuario): `herd` y `CRITTERS` siguen ahí por si vuelven.

	-- Luces de las parcelas (de noche las enciende el cliente): linternas sobre los pilares del muro, en las esquinas,
	-- en el medio de los otros tres lados y en los dos pilares altos de la entrada. Mismo reparto que
	-- Plots.buildWall: el -Z de la parcela mira al hub, el muro está a Size / 2 y sus pilares miden 6 (8,4 los de la
	-- entrada) más el remate.
	local plot = Config.Plot
	local half = plot.Size / 2
	local lampSpots = {
		Vector3.new(-half, 7.1, -half), Vector3.new(half, 7.1, -half), Vector3.new(-half, 7.1, half), Vector3.new(half, 7.1, half),
		Vector3.new(0, 7.1, half), Vector3.new(-half, 7.1, 0), Vector3.new(half, 7.1, 0),
		Vector3.new(-10, 9.5, -half), Vector3.new(10, 9.5, -half),
	}
	for index = 1, plot.Count do
		local angle = (index - 1) / plot.Count * math.pi * 2
		local center = Vector3.new(math.cos(angle) * plot.RingRadius, plot.FloorHeight, math.sin(angle) * plot.RingRadius)
		local frame = CFrame.lookAt(center, Vector3.new(0, plot.FloorHeight, 0))
		for _, spot in lampSpots do
			lit(PropModel.place(folder, "StoneLantern", frame * CFrame.new(spot), 0.8), 1.4, 26)
		end
	end

	-- Pétalos y matas de hierba por el césped libre.
	local placed = 0
	for _ = 1, 3000 do
		if placed >= 160 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * (islandRadius - 6)
		local position = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if isOpen(position, 3) then
			placed += 1
			petals(folder, position, 7, 5)
		end
	end

	-- Islotes con torii en el lago (como los santuarios sobre el agua) con un cerezo y una linterna.
	ring(5, islandRadius + 170, 0.4, function(position)
		local size = rng:NextNumber(24, 34)
		disc(folder, "Islet", position, size, 0, 0.25, GRAVEL, Enum.Material.Sand)
		disc(folder, "IsletGrass", position, size * 0.62, 0, 0.35, GRASS[1], Enum.Material.SmoothPlastic)
		PropModel.place(folder, "Torii", CFrame.lookAt(position + position.Unit * size * 0.9, Vector3.zero), 1.4)
		PropModel.place(folder, "Sakura", CFrame.new(position) * turn(), 1.1)
		lit(PropModel.place(folder, "StoneLantern", CFrame.new(position + Vector3.new(size * 0.3, 0.3, -size * 0.2)), 1.3), 1.0, 18)
		petals(folder, position, 18, size * 0.5)
	end)

	-- Horizonte: el monte Fuji y cordilleras moradas entre la niebla rosada, y nubes de atardecer.
	local fuji = PropModel.place(folder, "Fuji", CFrame.new(Vector3.new(-760, -4, -820)), 3.2, { StoneDark = Color3.fromRGB(150, 118, 190), Pink = Color3.fromRGB(255, 160, 190), White = Color3.fromRGB(255, 242, 248) })
	if fuji then
		-- Dónde está la cima, para la erupción del clima volcánico (client/WeatherFx): el cliente puede no tener el modelo.
		local center, size = fuji:GetBoundingBox()
		workspace:SetAttribute("VolcanoCrater", center.Position + Vector3.new(0, size.Y / 2, 0))
	end
	ring(11, 880, 0, function(position)
		local side = Vector3.new(-position.Z, 0, position.X).Unit
		for peak = -2, 2 do
			local size = rng:NextNumber(110, 190)
			local height = size * rng:NextNumber(0.75, 1.05) * (1 - math.abs(peak) * 0.18)
			mountain(folder, position + side * peak * size * 0.55 + position.Unit * rng:NextNumber(-40, 60), size, height)
		end
		for _ = 1, 3 do
			local fog = decor(part(folder, "Fog", Vector3.new(rng:NextNumber(260, 380), rng:NextNumber(30, 44), rng:NextNumber(90, 130)), CFrame.lookAt(position, Vector3.zero) * CFrame.new(rng:NextNumber(-120, 120), rng:NextNumber(14, 26), rng:NextNumber(-60, -10)), Color3.fromRGB(255, 226, 236), Enum.Material.SmoothPlastic))
			fog.Shape = Enum.PartType.Ball
			fog.Transparency = 0.2
			CollectionService:AddTag(fog, "FogBank")
		end
	end)
	ring(12, 600, 0.2, function(position)
		local height = rng:NextNumber(190, 260)
		for _ = 1, 3 do
			local size = rng:NextNumber(40, 70)
			local offset = Vector3.new(rng:NextNumber(-35, 35), height + rng:NextNumber(-8, 8), rng:NextNumber(-35, 35))
			local cloud = decor(part(folder, "Cloud", Vector3.one * size, CFrame.new(position + offset), Color3.fromRGB(255, 218, 232), Enum.Material.SmoothPlastic))
			cloud.Shape = Enum.PartType.Ball
			CollectionService:AddTag(cloud, "Cloud")
		end
	end)
end

return SceneryJapan
