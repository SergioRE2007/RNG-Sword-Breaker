-- Piezas del Jefe del mundo (librería, sin start()): la arena flotante lejos de la isla (Config.WorldBoss.Origin) y el
-- portal del hub que lleva a ella. Solo geometría: cuándo se abre el portal y quién entra lo decide server/WorldBoss.
-- El remolino del portal, la luz de los cristales y lo que se mueve lo pone el cliente (client/WorldBossFx) por etiquetas.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)
local WorldBossInfo = require(ReplicatedStorage.Shared.WorldBossInfo)
local Tell = require(script.Parent.Tell)

local WorldBossArena = {}

local cfg = Config.WorldBoss

local STONE = Color3.fromRGB(92, 88, 104)
local STONE_DARK = Color3.fromRGB(58, 55, 70)
local MOSS = Color3.fromRGB(96, 150, 84)
local LACQUER = Color3.fromRGB(176, 52, 46)
local GOLD = Color3.fromRGB(235, 190, 80)
local CRYSTAL = Color3.fromRGB(150, 110, 255)
local JELLY = Color3.fromRGB(120, 200, 90)
local WHITE = Color3.new(1, 1, 1)

local FLOOR = 4 -- grosor del suelo de la arena
local BARRIER = 60 -- alto del muro invisible

-- Piezas de Blender (tools/blender/crear_jefe.py, Shared.BossMeshes), hechas para una arena de radio 80: se escalan
-- con ArenaRadius. Medidas de allí: radio y alto de la muralla. Sin el archivo se queda la arena de piezas sueltas.
local MODEL_RADIUS = 80
local WALL_RADIUS, WALL_HEIGHT = 84.3, 2.8
local ARENA_TINT = { Stone = Color3.fromRGB(124, 112, 156), StoneDark = Color3.fromRGB(80, 70, 110) }
local ISLAND_TINT = { Stone = Color3.fromRGB(116, 104, 140), StoneDark = Color3.fromRGB(74, 66, 94) }
local PORTAL_TINT = { Stone = Color3.fromRGB(138, 122, 182), StoneDark = Color3.fromRGB(90, 78, 134) }

-- Luz en una pieza (los farolillos y los cristales llevan la suya).
local function glow(holder: Instance?, color: Color3, range: number, brightness: number)
	if holder then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Parent = holder
	end
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Disco horizontal (cilindro tumbado) con su cara de arriba a la altura `top`.
local function disc(parent: Instance, name: string, diameter: number, height: number, center: Vector3, top: number, color: Color3, material: Enum.Material?): Part
	return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center.X, top - height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
end

local function decor(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- Suelo de la arena (altura de la superficie). El rey cae en el centro.
function WorldBossArena.ground(): number
	return cfg.Origin.Y
end

-- Dónde aparece quien entra: en el borde de la arena, mirando al centro, repartidos por `index`.
function WorldBossArena.spawnCFrame(index: number): CFrame
	local angle = math.rad(90 + ((index * 37) % 120) - 60)
	local center = cfg.Origin
	local at = center + Vector3.new(math.cos(angle) * cfg.ArenaRadius * 0.82, 4, math.sin(angle) * cfg.ArenaRadius * 0.82)
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

-- Arena de piezas sueltas, si no hay modelos de Blender: anillos de baldosas, roca que cuelga, borde con linternas,
-- columnas con un cristal arriba y un torii en la entrada.
local function buildBlocks(model: Model, center: Vector3, top: number, radius: number)
	disc(model, "Ring", radius * 2 - 6, 0.2, center, top + 0.1, STONE, Enum.Material.Slate)
	disc(model, "Inner", radius * 1.25, 0.24, center, top + 0.12, STONE_DARK, Enum.Material.Cobblestone)
	disc(model, "Moss", radius * 0.95, 0.28, center, top + 0.14, MOSS:Lerp(STONE, 0.5), Enum.Material.Grass)
	-- Debajo, roca que cuelga: la arena flota en el cielo.
	for index = 1, 3 do
		local width = (radius * 2 + 8) * (1 - index * 0.24)
		local rock = part(model, "Rock", Vector3.new(width, 14, width), CFrame.new(center.X, top - FLOOR - index * 12 + 5, center.Z) * CFrame.Angles(0, math.rad(index * 25), 0), STONE_DARK:Lerp(STONE, index * 0.15), Enum.Material.Rock)
		decor(rock)
	end

	-- Borde: bloques bajos de piedra con linternas cada pocos.
	local count = 36
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * (radius + 2), 0, math.sin(angle) * (radius + 2))
		local facing = CFrame.lookAt(Vector3.new(at.X, top, at.Z), Vector3.new(center.X, top, center.Z))
		part(model, "Rim", Vector3.new(radius * math.pi * 2 / count + 0.4, 2.4, 3), facing * CFrame.new(0, 1.2, 0), STONE, Enum.Material.Slate)
		if index % 4 == 0 then
			local post = part(model, "LanternPost", Vector3.new(1.2, 4, 1.2), facing * CFrame.new(0, 4.4, 0), STONE_DARK, Enum.Material.Slate)
			decor(post)
			local lamp = part(model, "Lantern", Vector3.new(2.2, 2.2, 2.2), facing * CFrame.new(0, 7.4, 0), Color3.fromRGB(255, 200, 120), Enum.Material.SmoothPlastic)
			lamp.Transparency = 0.2
			decor(lamp)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 110)
			light.Range = 18
			light.Brightness = 1.4
			light.Parent = lamp
			part(model, "LanternRoof", Vector3.new(3.4, 0.6, 3.4), facing * CFrame.new(0, 8.8, 0), LACQUER, Enum.Material.Wood).CanCollide = false
		end
	end

	-- Columnas con un cristal flotando encima (lo hace latir client/WorldBossFx por la etiqueta).
	for index = 1, 6 do
		local angle = (index - 0.5) / 6 * math.pi * 2 + math.rad(30)
		local at = center + Vector3.new(math.cos(angle) * (radius + 9), 0, math.sin(angle) * (radius + 9))
		part(model, "Pillar", Vector3.new(4, 26, 4), CFrame.new(at.X, top + 13, at.Z) * CFrame.Angles(0, angle, 0), STONE, Enum.Material.Slate)
		part(model, "PillarCap", Vector3.new(6, 1.6, 6), CFrame.new(at.X, top + 26.8, at.Z) * CFrame.Angles(0, angle, 0), STONE_DARK, Enum.Material.Slate)
		local crystal = part(model, "Crystal", Vector3.new(2.6, 5, 2.6), CFrame.new(at.X, top + 31, at.Z) * CFrame.Angles(0, angle, math.rad(45)), CRYSTAL, Enum.Material.Glass)
		crystal.Transparency = 0.15
		decor(crystal)
		CollectionService:AddTag(crystal, "WorldBossCrystalGlow")
		local light = Instance.new("PointLight")
		light.Color = CRYSTAL
		light.Range = 22
		light.Brightness = 1.2
		light.Parent = crystal
	end

	-- Torii por donde se entra (en el lado de las apariciones).
	local gate = CFrame.lookAt(center + Vector3.new(0, top - center.Y, radius + 4), Vector3.new(center.X, top, center.Z))
	for _, side in { -1, 1 } do
		part(model, "ToriiPost", Vector3.new(2.2, 20, 2.2), gate * CFrame.new(side * 9, 10, 0), LACQUER, Enum.Material.Wood)
	end
	part(model, "ToriiBeam", Vector3.new(26, 1.8, 2.6), gate * CFrame.new(0, 20.5, 0), Color3.fromRGB(40, 32, 36), Enum.Material.Wood).CanCollide = false
	part(model, "ToriiTie", Vector3.new(21, 1.2, 1.8), gate * CFrame.new(0, 16.5, 0), LACQUER, Enum.Material.Wood).CanCollide = false
end

-- Arena con los modelos de Blender: isla de roca con estalactitas, cristales y baba; baldosas en anillos; muralla con
-- almenas y linternas de piedra; columnas con baba y su cristal flotando; el torii grande en la entrada y el trono del
-- rey al fondo, mirando al centro.
local function buildModels(model: Model, center: Vector3, top: number, radius: number)
	local k = radius / MODEL_RADIUS
	local origin = CFrame.new(center.X, top, center.Z)
	PropModel.place(model, "BossIsland", origin, k, ISLAND_TINT)
	PropModel.place(model, "BossIslandFloor", origin, k, ARENA_TINT)
	PropModel.place(model, "BossIslandWall", origin, k, ARENA_TINT)

	-- Linternas de piedra encima de la muralla, cada 40°, sin la de la entrada (+Z).
	for index = 0, 8 do
		local angle = math.rad(7.5 + index * 40)
		if math.abs(math.deg(angle) - 90) < 10 then
			continue
		end
		local at = center + Vector3.new(math.cos(angle) * WALL_RADIUS * k, WALL_HEIGHT * k, math.sin(angle) * WALL_RADIUS * k)
		local lantern = PropModel.place(model, "StoneLantern", CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)), 1.25, ARENA_TINT)
		glow(lantern and lantern:FindFirstChild("Paper"), Color3.fromRGB(255, 190, 110), 18, 1.4)
	end

	-- Columnas (por fuera de la muralla) con el cristal que flota y late encima (client/WorldBossFx, por la etiqueta).
	for index = 1, 6 do
		local angle = (index - 0.5) / 6 * math.pi * 2 + math.rad(30)
		local at = center + Vector3.new(math.cos(angle) * (radius + 9), 0, math.sin(angle) * (radius + 9))
		PropModel.place(model, "BossPillar", CFrame.new(at.X, top, at.Z) * CFrame.Angles(0, -angle, 0), 1, ARENA_TINT)
		local holder = PropModel.place(model, "BossCrystal", CFrame.new(at.X, top + 31, at.Z) * CFrame.Angles(0, -angle, 0))
		local crystal = holder and holder:FindFirstChild("Crystal")
		if crystal then
			CollectionService:AddTag(crystal, "WorldBossCrystalGlow")
			glow(crystal, CRYSTAL, 22, 1.2)
		end
	end

	-- Torii por donde se entra (en el lado de las apariciones) y trono del rey enfrente.
	local gate = CFrame.lookAt(center + Vector3.new(0, top - center.Y, radius + 4), Vector3.new(center.X, top, center.Z))
	PropModel.place(model, "Torii", gate, 1.35)
	local throne = center + Vector3.new(0, top - center.Y, -(MODEL_RADIUS + 30) * k)
	PropModel.place(model, "BossThrone", CFrame.lookAt(throne, Vector3.new(center.X, top, center.Z)), 1.6 * k, ARENA_TINT)
end

-- La arena: suelo con el charco de gelatina en el centro, decorado (modelos de Blender o, sin ellos, piezas sueltas),
-- luz propia y un muro invisible alrededor.
function WorldBossArena.build(): Model
	local model = Instance.new("Model")
	model.Name = "WorldBossArena"
	local center = cfg.Origin
	local top = center.Y
	local radius = cfg.ArenaRadius

	local floor = disc(model, "Floor", radius * 2 + 8, FLOOR, center, top, STONE_DARK, Enum.Material.Slate)
	local puddle = disc(model, "Jelly", cfg.Size.X * 1.4, 0.3, center, top + 0.16, JELLY, Enum.Material.SmoothPlastic)
	puddle.Transparency = 0.35
	puddle.Reflectance = 0.15
	decor(puddle)
	if PropModel.has("BossIsland") then
		floor.Color = ARENA_TINT.StoneDark
		buildModels(model, center, top, radius)
	else
		buildBlocks(model, center, top, radius)
	end

	-- Luz propia: la arena está lejos de la isla y de noche no se veía nada (cada luz llega a 60 studs).
	for index = 0, 6 do
		local angle = index / 6 * math.pi * 2
		local distance = if index == 0 then 0 else radius * 0.62
		local holder = part(model, "Light", Vector3.one, CFrame.new(center + Vector3.new(math.cos(angle) * distance, 34, math.sin(angle) * distance)), WHITE)
		holder.Transparency = 1
		decor(holder)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 236, 210)
		light.Range = 60
		light.Brightness = if index == 0 then 1.2 else 1.6
		light.Shadows = false
		light.Parent = holder
	end

	-- Muro invisible: nadie sale andando ni se cae por el borde.
	local walls = 28
	for index = 1, walls do
		local angle = (index - 0.5) / walls * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * (radius + 4), 0, math.sin(angle) * (radius + 4))
		local wall = part(model, "Barrier", Vector3.new(radius * math.pi * 2 / walls + 2, BARRIER, 2), CFrame.lookAt(Vector3.new(at.X, top + BARRIER / 2, at.Z), Vector3.new(center.X, top + BARRIER / 2, center.Z)), WHITE)
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
	end

	model.Parent = workspace
	return model
end

-- Portal de piezas sueltas (sin Shared.BossMeshes): peana, aro de bloques de piedra con remates dorados y farolillos.
local function buildRing(model: Model, base: CFrame, ringRadius: number, middle: number)
	part(model, "Base", Vector3.new(18, 1.2, 7), base * CFrame.new(0, 0.6, 0), STONE_DARK, Enum.Material.Slate)
	part(model, "Step", Vector3.new(14, 0.6, 9), base * CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate)
	local pieces = 20
	for index = 1, pieces do
		local angle = (index - 0.5) / pieces * math.pi * 2
		local at = base * CFrame.new(math.cos(angle) * ringRadius, middle + math.sin(angle) * ringRadius, 0) * CFrame.Angles(0, 0, angle)
		part(model, "Ring", Vector3.new(2, ringRadius * math.pi * 2 / pieces + 0.5, 2.4), at, if index % 5 == 0 then GOLD else STONE, if index % 5 == 0 then Enum.Material.Metal else Enum.Material.Slate)
	end
	for _, side in { -1, 1 } do
		local post = part(model, "Post", Vector3.new(1.4, 10, 1.4), base * CFrame.new(side * 11, 5, 0), LACQUER, Enum.Material.Wood)
		post.CanCollide = true
		local lamp = part(model, "Lantern", Vector3.new(2.4, 3, 2.4), base * CFrame.new(side * 11, 11.2, 0), CRYSTAL:Lerp(WHITE, 0.3), Enum.Material.SmoothPlastic)
		lamp.Transparency = 0.2
		decor(lamp)
		glow(lamp, CRYSTAL, 16, 1)
	end
end

-- El portal del hub: arco de piedra (modelo de Blender), disco de energía (solo se ve abierto) y una pieza invisible que,
-- al tocarla, mete al jugador en la arena. Devuelve el modelo, la pieza que se toca y cómo abrirlo o cerrarlo.
function WorldBossArena.buildPortal(map: Instance)
	local model = Instance.new("Model")
	model.Name = "WorldBossPortal"
	local position = WorldBossInfo.portalPosition()
	local floor = position.Y
	-- Mirando al centro del hub.
	local base = CFrame.lookAt(position, Vector3.new(0, floor, 0))
	local ringRadius = 7.5
	local middle = floor + ringRadius + 2

	-- Modelo de Blender (BossPortal): arco de dovelas con runas, el Rey Slime pequeño con su corona, baba que cae y dos
	-- pilonos con un cristal, cada uno con su luz. Sin el archivo, el aro de bloques de antes.
	local signHeight = middle - floor + ringRadius + 5
	if PropModel.place(model, "BossPortal", base, 1, PORTAL_TINT) then
		for _, side in { -1, 1 } do
			local holder = part(model, "Light", Vector3.one, base * CFrame.new(side * 12.6, 12, 0), WHITE)
			holder.Transparency = 1
			decor(holder)
			glow(holder, CRYSTAL, 16, 1)
		end
		signHeight = 31
	else
		buildRing(model, base, ringRadius, middle - floor)
	end
	-- Disco de energía: invisible cerrado.
	local disk = part(model, "Disk", Vector3.new(0.4, ringRadius * 2 - 1, ringRadius * 2 - 1), base * CFrame.new(0, middle - floor, 0) * CFrame.Angles(0, math.rad(90), 0), CRYSTAL, Enum.Material.Glass, Enum.PartType.Cylinder)
	disk.Transparency = 1
	decor(disk)
	CollectionService:AddTag(disk, "WorldBossPortal")
	-- Lo que se toca para entrar: algo más gordo que el disco, para que no haga falta atinar.
	local trigger = part(model, "Trigger", Vector3.new(ringRadius * 1.6, ringRadius * 1.8, 3), base * CFrame.new(0, middle - floor, 0), WHITE)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = false

	-- Cartel encima.
	local board = part(model, "Sign", Vector3.one, base * CFrame.new(0, signHeight, 0), WHITE)
	board.Transparency = 1
	decor(board)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(22, 4)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(215, 190, 255)
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = title
	Tell.world(title, "WORLD BOSS")

	model.Parent = map
	local function setOpen(open: boolean)
		disk.Transparency = if open then 0.35 else 1
		disk:SetAttribute("Open", open)
		trigger.CanTouch = open
	end
	setOpen(false)
	return model, trigger, setOpen
end

-- Texto de un cartel del mundo: lo escribe en el idioma de cada uno client/WorldText (Tell.world).
local function text(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, phrase: string, args: { [string]: any }?, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align or Enum.TextXAlignment.Center
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	Tell.world(label, phrase, args)
	return label
end

local function round(item: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = item
end

-- Cartel de premios a la derecha del portal (mirándolo desde el hub), pedido por el usuario: lo que da el jefe por cada
-- tramo de daño (Config.WorldBoss.Rewards.Tiers: cantidad de daño, no porcentaje); abajo, lo que suma el podio.
function WorldBossArena.buildBoard(map: Instance)
	local rewards = cfg.Rewards
	local tiers = rewards.Tiers
	local position = WorldBossInfo.portalPosition()
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	-- La derecha de quien mira el portal es la izquierda del portal; el cartel se gira un poco hacia delante del portal.
	local spot = base * CFrame.new(-19, 0, -2) * CFrame.Angles(0, math.rad(-20), 0)
	local width, height = 15, 19 -- alto para los 13 tramos
	local model = Instance.new("Model")
	model.Name = "WorldBossRewards"

	for _, side in { -1, 1 } do
		part(model, "Post", Vector3.new(1.2, height + 3, 1.2), spot * CFrame.new(side * (width / 2 + 0.4), (height + 3) / 2, 0.4), LACQUER, Enum.Material.Wood)
	end
	part(model, "Roof", Vector3.new(width + 4, 0.8, 3.4), spot * CFrame.new(0, height + 3.4, 0.4), Color3.fromRGB(40, 32, 36), Enum.Material.Wood)
	part(model, "RoofTrim", Vector3.new(width + 4.4, 0.3, 3.6), spot * CFrame.new(0, height + 2.9, 0.4), GOLD, Enum.Material.Metal).CanCollide = false
	local board = part(model, "Board", Vector3.new(width, height, 0.5), spot * CFrame.new(0, height / 2 + 2, 0.4), STONE_DARK, Enum.Material.Wood)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Rewards"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = board
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = WHITE
	back.Parent = gui
	round(back, 22)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(86, 58, 140), Color3.fromRGB(34, 24, 62))
	gradient.Parent = back
	local border = Instance.new("UIStroke")
	border.Thickness = 8
	border.Parent = back

	text(back, "Title", UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.075), GOLD, "BOSS REWARDS")
	text(back, "Subtitle", UDim2.fromScale(0.06, 0.095), UDim2.fromScale(0.88, 0.04), Color3.fromRGB(215, 200, 255), "By the damage you deal")

	-- Tabla: cabecera y una fila por tramo (te llevas la del tramo más alto al que llegas).
	local columns = {
		{ x = 0.04, w = 0.22, color = WHITE, title = "Damage" },
		{ x = 0.27, w = 0.2, color = GOLD, title = "Rolls" },
		{ x = 0.48, w = 0.24, color = Color3.fromRGB(90, 230, 255), title = "Crystals" },
		{ x = 0.73, w = 0.24, color = Color3.fromRGB(255, 140, 190), title = "Potions" },
	}
	local top, rowHeight = 0.145, 0.0485
	for _, column in columns do
		text(back, "Head_" .. column.title, UDim2.fromScale(column.x, top), UDim2.fromScale(column.w, rowHeight * 0.85), column.color, column.title)
	end
	for index, tier in tiers do
		local y = top + rowHeight * index
		local stripe = Instance.new("Frame")
		stripe.Name = "Row" .. index
		stripe.Position = UDim2.fromScale(0.03, y - 0.004)
		stripe.Size = UDim2.fromScale(0.94, rowHeight - 0.008)
		stripe.BackgroundColor3 = if index % 2 == 1 then WHITE else Color3.new(0, 0, 0)
		stripe.BackgroundTransparency = if index % 2 == 1 then 0.9 else 0.8
		stripe.Parent = back
		round(stripe, 10)
		local potions = if (tier.potions or 0) > 0 then { "{n} × {tier}", { n = tier.potions, tier = Config.Potions.Tiers[tier.potionTier] or "" } } else { "-", nil }
		local cells = { { "{n}+", { n = tier.damage } }, { "{n}", { n = tier.rolls } }, { "{n}", { n = tier.crystals } }, potions }
		for column, cell in cells do
			local def = columns[column]
			text(stripe, "Cell" .. column, UDim2.fromScale((def.x - 0.03) / 0.94, 0.1), UDim2.fromScale(def.w / 0.94, 0.8), if column == 1 then WHITE else def.color, cell[1], cell[2])
		end
	end

	-- Aclaración y podio: tirada de más y tickets.
	local footer = top + rowHeight * (#tiers + 1) + 0.005
	text(back, "Each", UDim2.fromScale(0.05, footer), UDim2.fromScale(0.9, 0.036), Color3.fromRGB(215, 200, 255), "Crystals and potions: that many of each")
	local bonus = rewards.TopBonusRolls
	text(back, "Top", UDim2.fromScale(0.05, footer + 0.04), UDim2.fromScale(0.9, 0.04), GOLD, if bonus == 1 then "Top 3: +{n} roll" else "Top 3: +{n} rolls", { n = bonus })
	text(back, "Tickets", UDim2.fromScale(0.05, footer + 0.08), UDim2.fromScale(0.9, 0.04), Color3.fromRGB(255, 190, 60), "Tickets: 1st {a} · 2nd {b} · 3rd {c}", { a = rewards.Tickets[1] or 0, b = rewards.Tickets[2] or 0, c = rewards.Tickets[3] or 0 })

	model.Parent = map
	return model
end

-- Delante del portal, mirándolo (para el botón "Ir" y para volver de la arena).
function WorldBossArena.portalFront(): CFrame
	local position = WorldBossInfo.portalPosition()
	local inward = Vector3.new(-position.X, 0, -position.Z).Unit
	local stand = position + inward * 9 + Vector3.new(0, 3, 0)
	return CFrame.lookAt(stand, Vector3.new(position.X, stand.Y, position.Z))
end

return WorldBossArena
