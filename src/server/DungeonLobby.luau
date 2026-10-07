-- Lobby subterráneo de mazmorras. En el centro del hub se abre una boca (se corta el suelo de la isla), de ella baja una
-- escalera de caracol a una caverna bajo el mar y la isla, y en la caverna hay una sala por zona de Config.Dungeons, cada
-- una con su arco, su decorado temático y un altar (ProximityPrompt "Shop"="party") donde se abre la ventana de grupo
-- (client/Party). Todo sale de Config.DungeonLobby y de los temas de Config.DungeonThemes; sin modelos propios.
-- El cliente (client/RoomSigns) pone los carteles de las salas sobre las piezas con la etiqueta DungeonRoom (atributos
-- Index y Waiting) y client/DungeonFx la luz del lobby. Expone dónde están las salas para el grupo, la barra de
-- transporte y la vuelta de las partidas.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonThemes = require(script.Parent.DungeonThemes)

local DungeonLobby = {}

local cfg = Config.DungeonLobby
local GeometryService = game:GetService("GeometryService")

local part, disc, cylinder, deco, small, lantern = DungeonThemes.part, DungeonThemes.disc, DungeonThemes.cylinder, DungeonThemes.deco, DungeonThemes.small, DungeonThemes.lantern

local STONE_A = Color3.fromRGB(78, 76, 98)
local STONE_B = Color3.fromRGB(62, 60, 80)
local DARK = Color3.fromRGB(42, 40, 56)
local SPACE = Color3.fromRGB(12, 10, 34) -- azul casi negro del techo de galaxia
local ACCENT = Color3.fromRGB(176, 124, 255) -- violeta de las runas y los faroles del lobby
local BLACK = Color3.new(0, 0, 0)

local FLOOR = cfg.Floor
local HUB_TOP = Config.Plot.FloorHeight

local rooms: { [number]: { cframe: CFrame, pad: Vector3, sign: BasePart, width: number, depth: number } } = {}
local plaza: CFrame? = nil

-- Un bloque en un anillo alrededor del centro: `size` = (radial, alto, tangencial); `y` = centro; `theta` en radianes.
local function ringBlock(parent: Instance, name: string, theta: number, radius: number, y: number, size: Vector3, color: Color3, material: Enum.Material?): Part
	return part(parent, name, size, CFrame.new(0, y, 0) * CFrame.Angles(0, -theta, 0) * CFrame.new(radius, 0, 0), color, material)
end

local function polar(theta: number, radius: number, y: number): Vector3
	return Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
end

local function lightHolder(parent: Instance, position: Vector3, color: Color3, range: number, brightness: number)
	local holder = small(part(parent, "Light", Vector3.one * 0.5, CFrame.new(position), color, Enum.Material.SmoothPlastic))
	holder.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = holder
end

-- Suelo de la isla ----------------------------------------------------------------------------------------------

-- Sustituye un disco del suelo por otro igual con un agujero redondo en el centro (resta de sólidos en el servidor).
local function cutHole(target: BasePart, radius: number): boolean
	local cutter = Instance.new("Part")
	cutter.Shape = Enum.PartType.Cylinder
	cutter.Anchored = true
	cutter.CanCollide = false
	cutter.Size = Vector3.new(target.Size.X + 4, radius * 2, radius * 2)
	cutter.CFrame = target.CFrame
	cutter.Parent = workspace
	local ok, result = pcall(function()
		return GeometryService:SubtractAsync(target, { cutter }, { CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition, RenderFidelity = Enum.RenderFidelity.Automatic })
	end)
	cutter:Destroy()
	local piece = if ok and type(result) == "table" then result[1] else nil
	if not piece then
		warn(`DungeonLobby: no se pudo abrir el hueco en {target.Name}: {tostring(result)}`)
		return false
	end
	piece.Name = target.Name
	piece.Anchored = true
	piece.UsePartColor = true
	piece.Color = target.Color
	piece.Material = target.Material
	piece.CastShadow = target.CastShadow
	piece.CanCollide = target.CanCollide
	piece.CanQuery = target.CanQuery
	piece.Parent = target.Parent
	target:Destroy()
	return true
end

-- La base del mundo (2048 de lado) pasa a ser cuatro losas alrededor de un hueco cuadrado un poco mayor que la boca.
-- El pozo de piedra tapa lo que sobra entre el círculo y el cuadrado.
local function cutBaseplate(half: number)
	local base = workspace:FindFirstChild("Baseplate")
	if not base or not base:IsA("BasePart") then
		return
	end
	local size, y = base.Size, base.Position.Y
	local x2, z2 = size.X / 2, size.Z / 2
	local function slab(piece: BasePart, x0: number, x1: number, z0: number, z1: number)
		piece.Size = Vector3.new(x1 - x0, size.Y, z1 - z0)
		piece.CFrame = CFrame.new((x0 + x1) / 2, y, (z0 + z1) / 2)
	end
	local others = {}
	for index = 1, 3 do
		others[index] = base:Clone()
		others[index].Parent = base.Parent
	end
	slab(base, -x2, x2, half, z2) -- norte
	slab(others[1], -x2, x2, -z2, -half) -- sur
	slab(others[2], half, x2, -half, half) -- este
	slab(others[3], -x2, -half, -half, half) -- oeste
end

-- Quita lo que el decorado de la isla había puesto justo encima de donde va la boca.
local function clearCenterDecor()
	local scenery = workspace:FindFirstChild("Scenery")
	if not scenery then
		return
	end
	for _, item in scenery:GetChildren() do
		if item:IsA("BasePart") then
			local flat = Vector3.new(item.Position.X, 0, item.Position.Z).Magnitude
			if (item.Name == "GrassTile" and flat < cfg.HoleRadius + 19) or (item.Name == "PlazaTile" and flat < 40) then
				item:Destroy()
			end
		end
	end
end

-- Entrada en la superficie ---------------------------------------------------------------------------------------

local function buildEntrance(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "EntradaMazmorras"
	local top = HUB_TOP

	-- Borde de piedra plano alrededor de la boca.
	local segments = 36
	local mid = (cfg.HoleRadius + cfg.RimRadius) / 2
	for index = 1, segments do
		local theta = (index - 1) / segments * math.pi * 2
		deco(ringBlock(model, "Rim", theta, mid, top + 0.17, Vector3.new(cfg.RimRadius - cfg.HoleRadius, 0.35, 2 * math.pi * mid / segments + 0.35), if index % 2 == 0 then STONE_A else STONE_B, Enum.Material.Cobblestone))
	end
	-- Anillo de runas (cristal, sin Neon) pegado al borde del hueco.
	local runes = 48
	for index = 1, runes do
		local theta = (index - 1) / runes * math.pi * 2
		local rune = ringBlock(model, "Rune", theta, cfg.HoleRadius + 1, top + 0.4, Vector3.new(0.7, 0.1, 2 * math.pi * (cfg.HoleRadius + 1) / runes * 0.55), ACCENT, Enum.Material.Glass)
		rune.Transparency = 0.15
		small(rune)
	end
	-- Ocho pilares con un farol, sobre el borde.
	for index = 1, 8 do
		local theta = (index - 0.5) / 8 * math.pi * 2
		local base = CFrame.new(polar(theta, cfg.RimRadius - 1.6, top + 0.35))
		cylinder(model, "Pillar", 9, 2.6, base, STONE_A, Enum.Material.Slate)
		part(model, "Cap", Vector3.new(3.8, 0.8, 3.8), base * CFrame.new(0, 9.4, 0), STONE_B, Enum.Material.Slate)
		lantern(model, base * CFrame.new(0, 10.6, 0), ACCENT, 12, 0.25) -- poca luz: el suelo del hub es casi blanco
	end
	-- Cartel flotante sobre la boca (la etiqueta ShopSign hace que el cliente lo anime como los de las tiendas).
	local anchor = small(part(model, "Sign", Vector3.one, CFrame.new(0, top + 21, 0), ACCENT, Enum.Material.SmoothPlastic))
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 90)
	gui:SetAttribute("TextMax", 50) -- el cliente (ModifierShops) encoge la fuente con la distancia entre estos dos topes
	gui:SetAttribute("TextMin", 22)
	gui.MaxDistance = 170
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 50
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "MAZMORRAS"
	label.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Color = BLACK
	outline.Thickness = 3.5
	outline.Parent = label
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(200, 130, 255), Color3.fromRGB(255, 110, 140))
	gradient.Parent = label
	CollectionService:AddTag(gui, "ShopSign")
	-- Un resplandor violeta que sube del fondo (suave: el suelo del hub es casi blanco).
	lightHolder(model, Vector3.new(0, -14, 0), ACCENT, 26, 0.5)
	model.Parent = parent
end

-- Pozo y escalera de caracol ---------------------------------------------------------------------------------------

-- Devuelve el ángulo (radianes) hacia el que sale la escalera en el lobby.
local function buildShaft(parent: Instance): number
	local model = Instance.new("Model")
	model.Name = "PozoMazmorras"
	local step = 2 * math.pi / cfg.StepsPerTurn
	local exit = math.rad(cfg.ExitAngle)

	-- Sin escalera: se baja y se sube en el ascensor de luz (server/LightLift), que pone sus plataformas en el pozo.

	-- Muro del pozo: anillo grueso de bloques, con la puerta de salida abierta junto al último peldaño.
	local segments = 48
	local wallInner, wallOuter = cfg.HoleRadius, 21
	local wallMid = (wallInner + wallOuter) / 2
	local wallWidth = 2 * math.pi * wallMid / segments + 0.5
	local doorHalf = step * 1.8
	local doorHeight = 10
	for index = 1, segments do
		local theta = (index - 1) / segments * math.pi * 2
		local diff = math.abs((theta - exit + math.pi) % (2 * math.pi) - math.pi)
		local color = if index % 2 == 0 then STONE_B else DARK
		if diff <= doorHalf then
			local base = FLOOR + doorHeight
			local height = 0 - base
			ringBlock(model, "Lintel", theta, wallMid, base + height / 2, Vector3.new(wallOuter - wallInner, height, wallWidth), color, Enum.Material.Brick)
		else
			local height = 0 - FLOOR
			ringBlock(model, "Wall", theta, wallMid, FLOOR + height / 2, Vector3.new(wallOuter - wallInner, height, wallWidth), color, Enum.Material.Brick)
		end
	end

	-- Faroles por el muro.
	for index = 0, 9 do
		local theta = index * 2.399963 -- ángulo áureo: no quedan en fila
		lantern(model, CFrame.new(polar(theta, wallInner - 0.4, FLOOR + 8 + index * 8)), ACCENT, 20, 0.8)
	end
	model.Parent = parent
	return exit
end

-- Caverna ---------------------------------------------------------------------------------------------------------

-- Techo de cielo estrellado: estrellas diminutas de neón (blancas, azuladas y anaranjadas, algunas más grandes y
-- brillantes) repartidas por toda la cara de abajo del techo, y unas pocas nubes tenues de color. Solo piezas pequeñas
-- y sin choque; el cliente no hace nada (las estrellas brillan solas).
local function buildStars(parent: Instance, ceiling: number, cavern: number)
	local random = Random.new(23)
	local y = ceiling - 2.1
	local reach = cavern + 6
	local tints = { Color3.fromRGB(70, 90, 200), Color3.fromRGB(110, 70, 190) }
	for index = 1, 14 do
		local center = polar(random:NextNumber(0, 2 * math.pi), random:NextNumber(26, reach), y - random:NextNumber(0, 0.4))
		local cloud = small(disc(parent, "Cloud", center, random:NextNumber(14, 28), 0.1, tints[index % 2 + 1], Enum.Material.SmoothPlastic))
		cloud.Transparency = random:NextNumber(0.9, 0.95)
	end
	for _ = 1, 520 do
		-- Reparto uniforme por la superficie (la raíz evita que se amontonen en el centro).
		local radius = math.sqrt(random:NextNumber(22 * 22, reach * reach))
		local theta = random:NextNumber(0, 2 * math.pi)
		local roll = random:NextNumber()
		local size = random:NextNumber(0.25, 0.8) * (if roll < 0.05 then 2.4 else 1)
		local color = if roll < 0.2 then Color3.fromRGB(255, 205, 160) elseif roll < 0.45 then Color3.fromRGB(175, 205, 255) else Color3.new(1, 1, 1)
		local star = small(part(parent, "Star", Vector3.one * size, CFrame.new(polar(theta, radius, y - 0.05 - random:NextNumber(0, 0.3))), color, Enum.Material.Neon))
		star.Shape = Enum.PartType.Ball
	end
end

local function buildCavern(parent: Instance, cavern: number)
	local model = Instance.new("Model")
	model.Name = "CavernaMazmorras"
	local ceiling = cfg.Ceiling
	local height = ceiling - FLOOR

	disc(model, "Floor", Vector3.new(0, FLOOR - 2, 0), cavern + 4, 4, STONE_B, Enum.Material.Slate)
	-- Plaza: losas de dos tonos y un anillo de runas (todo plano y sin choque).
	deco(disc(model, "Paving", Vector3.new(0, FLOOR + 0.05, 0), cfg.PlazaRadius, 0.1, Color3.fromRGB(92, 90, 114), Enum.Material.Cobblestone))
	deco(disc(model, "PavingRing", Vector3.new(0, FLOOR + 0.08, 0), cfg.PlazaRadius - 4, 0.1, STONE_A, Enum.Material.Slate))
	deco(disc(model, "PavingInner", Vector3.new(0, FLOOR + 0.11, 0), cfg.PlazaRadius - 6, 0.1, Color3.fromRGB(92, 90, 114), Enum.Material.Cobblestone))
	deco(disc(model, "RuneRing", Vector3.new(0, FLOOR + 0.14, 0), cfg.PlazaRadius - 15, 0.1, ACCENT:Lerp(BLACK, 0.2), Enum.Material.SmoothPlastic))
	deco(disc(model, "RuneInner", Vector3.new(0, FLOOR + 0.17, 0), cfg.PlazaRadius - 16, 0.1, STONE_A, Enum.Material.Slate))

	-- Muro de la caverna.
	local segments = 40
	local width = 2 * math.pi * (cavern + 2) / segments + 0.6
	for index = 1, segments do
		local theta = (index - 1) / segments * math.pi * 2
		ringBlock(model, "Wall", theta, cavern + 2, FLOOR + height / 2, Vector3.new(6, height, width), if index % 2 == 0 then DARK else STONE_B, Enum.Material.Slate)
	end

	-- Techo: tablones sin choque, de la pared del pozo a la del fondo; estalactitas colgando.
	local planks = 72
	local from, to = 22, cavern + 8
	local plankWidth = 2 * math.pi * to / planks + 0.6
	for index = 1, planks do
		local theta = (index - 1) / planks * math.pi * 2
		small(ringBlock(model, "Ceiling", theta, (from + to) / 2, ceiling - 1, Vector3.new(to - from, 2, plankWidth), SPACE, Enum.Material.SmoothPlastic))
	end
	buildStars(model, ceiling, cavern)

	-- Farolas de la plaza (pie de piedra y farol) y luces repartidas por el techo.
	for index = 1, 12 do
		local theta = (index - 0.5) / 12 * math.pi * 2
		local base = CFrame.new(polar(theta, cfg.PlazaRadius - 3, FLOOR))
		cylinder(model, "Post", 7, 1.2, base, STONE_A, Enum.Material.Slate)
		lantern(model, base * CFrame.new(0, 8, 0), Color3.fromRGB(150, 210, 255), 34, 0.7)
	end
	for _, ring in { { 40, 8 }, { 88, 12 } } do
		for index = 1, ring[2] do
			local theta = (index - 0.5) / ring[2] * math.pi * 2 + ring[1]
			lightHolder(model, polar(theta, ring[1], ceiling - 4), Color3.fromRGB(205, 218, 255), 60, 0.6)
		end
	end

	-- Subida a la superficie: un altar junto a la boca del pozo (por si no apetece subir la escalera).
	model.Parent = parent
end

-- Salas -----------------------------------------------------------------------------------------------------------

local function buildRoom(parent: Instance, index: number, level, total: number, radius: number)
	local rc = cfg.Rooms
	local theta = math.rad(rc.FirstAngle) + (index - 1) / total * math.pi * 2
	local center = Vector3.new(math.cos(theta) * radius, FLOOR, math.sin(theta) * radius)
	local roomCF = CFrame.lookAt(center, Vector3.new(0, FLOOR, 0)) -- -Z hacia la plaza
	local theme = DungeonThemes.get(level)
	local width, depth, height = rc.Width, rc.Depth, rc.Height
	local floorLook = theme.floor
	local wallLook = theme.wall
	local c1 = wallLook.colors[1]
	local c2 = wallLook.colors[2] or c1
	local material = wallLook.material
	local model = Instance.new("Model")
	model.Name = "Sala" .. index

	-- Suelo, muros y techo.
	part(model, "Floor", Vector3.new(width, 1, depth), roomCF * CFrame.new(0, -0.4, 0), floorLook.color, floorLook.material)
	part(model, "Back", Vector3.new(width + 4, height, 2), roomCF * CFrame.new(0, height / 2, depth / 2 + 1), c1, material)
	for _, side in { -1, 1 } do
		part(model, "Side", Vector3.new(2, height, depth), roomCF * CFrame.new(side * (width / 2 + 1), height / 2, 0), c2, material)
	end
	part(model, "Roof", Vector3.new(width + 6, 2, depth + 4), roomCF * CFrame.new(0, height + 1, 1), DARK, Enum.Material.Slate)

	-- Arco de la entrada: dos pilares, dintel y una franja del color de la zona.
	for _, side in { -1, 1 } do
		part(model, "ArchPillar", Vector3.new(3.4, height + 2, 3.4), roomCF * CFrame.new(side * (width / 2 + 1.7), (height + 2) / 2, -depth / 2), c1, material)
	end
	part(model, "Lintel", Vector3.new(width + 8.8, 3.6, 3.4), roomCF * CFrame.new(0, height + 1.8, -depth / 2), c1:Lerp(BLACK, 0.12), material)
	small(part(model, "Strip",Vector3.new(width + 2, 0.5, 0.5), roomCF * CFrame.new(0, height - 0.4, -depth / 2 - 1.8), level.color, Enum.Material.Neon))

	-- Altar de grupo: disco del color de la zona con su aviso para abrir la ventana.
	deco(disc(model, "PadRim", (roomCF * CFrame.new(0, 0.25, 0)).Position, 6.6, 0.5, DARK, Enum.Material.Slate))
	deco(disc(model, "Pad", (roomCF * CFrame.new(0, 0.6, 0)).Position, 5.6, 0.4, level.color:Lerp(BLACK, 0.2), Enum.Material.SmoothPlastic))
	local altar = small(part(model, "Altar", Vector3.new(2, 2, 2), roomCF * CFrame.new(0, 2, 0), level.color, Enum.Material.SmoothPlastic))
	altar.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sala de grupo"
	prompt.ObjectText = level.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Shop", "party")
	prompt:SetAttribute("Dungeon", index)
	prompt.Parent = altar

	-- Cartel: un tablón sobre el arco (el cliente le pone encima, para cada jugador, la pantalla con el nombre, los
	-- premios y el estado de la zona) y luces.
	local sign = deco(part(model, "Sign", Vector3.new(26, 14, 0.8), roomCF * CFrame.new(0, height + 9, -depth / 2 - 1.5), DARK, Enum.Material.Slate))
	sign:SetAttribute("Index", index)
	sign:SetAttribute("Waiting", 0)
	CollectionService:AddTag(sign, "DungeonRoom")
	lightHolder(model, (roomCF * CFrame.new(0, 14, 4)).Position, theme.torch or level.color, 44, 0.9)
	lightHolder(model, (roomCF * CFrame.new(0, 4, 0)).Position, level.color, 22, 0.8)

	DungeonThemes.dressRoom(model, roomCF, width, depth, level, theme)
	model.Parent = parent
	rooms[index] = { cframe = roomCF, pad = (roomCF * CFrame.new(0, 1, 0)).Position, sign = sign, width = width, depth = depth }
end

-- API -------------------------------------------------------------------------------------------------------------

-- Centro del altar de grupo de esa zona.
function DungeonLobby.padPosition(index: number): Vector3?
	local room = rooms[index]
	return if room then room.pad else nil
end

-- Dónde dejar al jugador número `k` de `n` al acabar una partida: dentro de su sala, delante del altar, mirándolo.
function DungeonLobby.returnCFrame(index: number, k: number, n: number): CFrame?
	local room = rooms[index]
	if not room then
		return nil
	end
	local spread = (k - 1) - (n - 1) / 2
	return room.cframe * CFrame.new(spread * 4, 3.2, -9) * CFrame.Angles(0, math.pi, 0)
end

-- Sitio donde aparece quien baja por la barra de transporte: en la plaza, de espaldas a la escalera.
function DungeonLobby.plazaCFrame(): CFrame?
	return plaza
end

-- Cuánta gente espera en la sala (lo lee el cartel).
function DungeonLobby.setWaiting(index: number, count: number)
	local room = rooms[index]
	if room then
		room.sign:SetAttribute("Waiting", count)
	end
end

function DungeonLobby.start()
	local map = workspace:WaitForChild("Map")
	local scenery = workspace:WaitForChild("Scenery", 15)

	-- Suelo de la isla: agujero en el hub; la base, en cuatro losas. El césped y la playa (discos enormes y finos, en los
	-- que la colisión de un agujero tan pequeño sale mal) se vacían por dentro hasta casi el borde del hub, que ya los
	-- tapa y hace de suelo por encima.
	local hole = cfg.HoleRadius
	local hub = map:FindFirstChild("Hub")
	if hub and hub:IsA("BasePart") then
		cutHole(hub, hole)
	end
	if scenery then
		for _, name in { "Grass", "Beach" } do
			local ground = scenery:FindFirstChild(name)
			if ground and ground:IsA("BasePart") then
				cutHole(ground, Config.Plot.HubRadius - 2)
			end
		end
	end
	cutBaseplate(hole + 0.7)
	clearCenterDecor()

	local total = #Config.Dungeons
	local rc = cfg.Rooms
	local radius = math.max(rc.Radius, total * (rc.Width + 8) / (2 * math.pi))
	local cavern = math.max(cfg.CavernRadius, radius + rc.Depth / 2 + 14)

	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	buildEntrance(folder)
	local exit = buildShaft(folder)
	buildCavern(folder, cavern)
	for index, level in Config.Dungeons do
		buildRoom(folder, index, level, total, radius)
	end
	-- Columnas entre sala y sala, en la línea de las entradas, para que la fila de arcos se vea continua.
	for index = 1, total do
		local theta = math.rad(rc.FirstAngle) + (index - 0.5) / total * math.pi * 2
		local base = CFrame.new(polar(theta, radius - rc.Depth / 2 - 1.5, FLOOR))
		cylinder(folder, "Column", rc.Height + 2, 3.4, base, STONE_A, Enum.Material.Slate)
		lantern(folder, base * CFrame.new(0, rc.Height + 3.4, 0), ACCENT, 34)
	end
	plaza = CFrame.lookAt(polar(exit, 32, FLOOR + 3.2), polar(exit, 60, FLOOR + 3.2))
	folder.Parent = workspace

	-- El SpawnLocation de fábrica (oculto) estaba justo encima de la boca: se aparta.
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("BasePart") then
		spawn.Position = Vector3.new(0, spawn.Position.Y, 40)
	end
end

return DungeonLobby
