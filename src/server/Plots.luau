-- Construye el hub y las parcelas, y asigna una parcela a cada jugador.
-- La parcela crece y cambia de aspecto con los renacimientos de su dueño (Stats.plotSize y server/PlotLooks): el suelo,
-- el muro, sus luces y su decorado van en el Model "Ground" de cada parcela, que se vuelve a montar entero al cambiar.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlotLooks = require(script.Parent.PlotLooks)
local Tell = require(script.Parent.Tell)

local Plots = {}

-- Dos tonos para el suelo a cuadros.
-- En el mapa japonés (Config.Theme) las parcelas libres son de losa lila y las que tienen dueño, de tarima de madera.
local JAPAN = Config.Theme == "japan"
local FLOOR_FREE = if JAPAN then { Color3.fromRGB(198, 192, 216), Color3.fromRGB(180, 174, 200) } else { Color3.fromRGB(150, 155, 165), Color3.fromRGB(136, 141, 152) }
local FLOOR_OWNED = if JAPAN then { Color3.fromRGB(216, 162, 106), Color3.fromRGB(196, 140, 90) } else { Color3.fromRGB(128, 214, 78), Color3.fromRGB(110, 198, 64) }
local OWNED_MATERIAL = if JAPAN then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
local TILE = 10 -- lado de cada baldosa; también el largo de cada tramo de valla

-- Color propio de cada parcela (arcoíris alrededor del hub): valla y cartel.
local function plotColor(index: number, value: number): Color3
	return Color3.fromHSV((index - 1) / Config.Plot.Count, 0.65, value)
end

-- plot = { index, cframe (centro, a ras de suelo, -Z mira al hub), size (lado de ahora), look (PlotLooks.get),
-- spawnOffset, owner, ground (Model con suelo, muro y decorado), tiles, spawn, sign, label }
local plots = {}
local byPlayer = {}
local watchers = {} -- [player] = conexión al cambio de sus renacimientos
local releaseCallbacks = {}
local resizeCallbacks = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Con dueño, la tarima del aspecto de sus renacimientos y, con "border", un marco de losas en la fila de fuera.
local function paint(plot, owned: boolean)
	local look = plot.look
	local colors = if owned then (if JAPAN and look.floor then look.floor else FLOOR_OWNED) else FLOOR_FREE
	local border = owned and look.has.border
	for _, tile in plot.tiles do
		if border and tile.edge then
			tile.part.Color = PlotLooks.BORDER[tile.shade]
			tile.part.Material = Enum.Material.Slate
		else
			tile.part.Color = colors[tile.shade]
			tile.part.Material = if owned then OWNED_MATERIAL else Enum.Material.SmoothPlastic
		end
	end
end

-- Muro japonés (tsuijibei) para el mapa japonés: zócalo de piedra, pared blanca con una franja del color de la
-- parcela, tejadillo de tejas azules y pilares de piedra con remate; la entrada del lado del hub lleva dos pilares
-- más altos. Mismo recorrido y mismo hueco que la valla de siempre. Con "gold" los remates son dorados.
local WALL_STONE = Color3.fromRGB(150, 146, 168)
local WALL_PLASTER = Color3.fromRGB(252, 246, 238)
local WALL_ROOF = Color3.fromRGB(54, 70, 124)
local GATE_RED = Color3.fromRGB(232, 52, 62)

local function stone(part: Part, material: Enum.Material?)
	part.Material = material or Enum.Material.Slate
	return part
end

local function buildWall(model: Instance, cframe: CFrame, index: number, size: number, look)
	local half = size / 2
	local segments = size / TILE
	local band = plotColor(index, 0.9)
	local gold = look.has.gold
	local ridge = if gold then PlotLooks.GOLD else WALL_ROOF:Lerp(Color3.new(1, 1, 1), 0.15)

	for side = 0, 3 do
		local line = cframe * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -half)
		for segment = 1, segments do
			local x = -half + (segment - 1) * TILE
			-- Detrás (side 2) hay otro paso, sin pilares de entrada: lleva a la Bolsa de oro (server/GoldBag).
			local isGate = (side == 0 or side == 2) and (segment == segments / 2 or segment == segments / 2 + 1)
			local gatePost = side == 0 and (segment == segments / 2 or segment == segments / 2 + 2)
			if not ((side == 0 or side == 2) and segment == segments / 2 + 1) then
				-- Pilar de piedra con un remate de teja (más alto y rojo en la entrada).
				local height = if gatePost then 8.4 else 6
				local width = if gatePost then 2.4 else 1.9
				stone(block(model, "Post", Vector3.new(width, height, width), line * CFrame.new(x, height / 2, 0), WALL_STONE))
				block(model, "PostCap", Vector3.new(width + 1.2, 0.6, width + 1.2), line * CFrame.new(x, height + 0.3, 0), if gatePost then GATE_RED else WALL_ROOF)
				local top = block(model, "PostTop", Vector3.new(width * 0.5, 0.5, width * 0.5), line * CFrame.new(x, height + 0.85, 0), if gatePost or gold then PlotLooks.GOLD else WALL_STONE)
				if gold then
					top.Material = Enum.Material.Metal
				end
			end
			if not isGate then
				local middle = line * CFrame.new(x + TILE / 2, 0, 0)
				stone(block(model, "WallBase", Vector3.new(TILE, 1.5, 1.9), middle * CFrame.new(0, 0.75, 0), WALL_STONE))
				block(model, "Wall", Vector3.new(TILE, 3.0, 1.3), middle * CFrame.new(0, 3.0, 0), WALL_PLASTER)
				block(model, "WallBand", Vector3.new(TILE, 0.4, 1.4), middle * CFrame.new(0, 2.2, 0), band)
				block(model, "WallRoof", Vector3.new(TILE, 0.5, 2.6), middle * CFrame.new(0, 4.75, 0), WALL_ROOF)
				block(model, "WallRidge", Vector3.new(TILE, 0.4, 1.3), middle * CFrame.new(0, 5.2, 0), ridge)
			end
		end
	end

	-- Linternas de piedra sobre los pilares (de noche las enciende el cliente): en las esquinas, en el medio de los dos
	-- lados, a cada lado del paso de atrás (su pilar central no existe) y en los dos pilares altos de la entrada.
	local spots = {
		Vector3.new(-half, 7.1, -half), Vector3.new(half, 7.1, -half), Vector3.new(-half, 7.1, half), Vector3.new(half, 7.1, half),
		Vector3.new(-10, 7.1, half), Vector3.new(10, 7.1, half), Vector3.new(-half, 7.1, 0), Vector3.new(half, 7.1, 0),
		Vector3.new(-10, 9.5, -half), Vector3.new(10, 9.5, -half),
	}
	for _, spot in spots do
		PlotLooks.lantern(model, cframe * CFrame.new(spot), 0.8, 1.4, 26)
	end
end

-- Valla de postes, dos travesaños y aspas, del color de la parcela, con un hueco de entrada
-- en el lado del hub.
local function buildFence(model: Instance, cframe: CFrame, index: number, size: number, look)
	if JAPAN then
		buildWall(model, cframe, index, size, look)
		return
	end
	local half = size / 2
	local segments = size / TILE
	local rail = plotColor(index, 0.95)
	local post = if look.has.gold then PlotLooks.GOLD else plotColor(index, 0.6)
	local slope = math.atan2(2, TILE)
	local diagonal = math.sqrt(TILE ^ 2 + 2 ^ 2)

	for side = 0, 3 do
		local line = cframe * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -half)
		for segment = 1, segments do
			local x = -half + (segment - 1) * TILE
			-- Entrada: los dos tramos del centro del lado que mira al hub, y otro paso igual detrás (a la Bolsa de oro).
			local isGate = (side == 0 or side == 2) and (segment == segments / 2 or segment == segments / 2 + 1)
			if not ((side == 0 or side == 2) and segment == segments / 2 + 1) then
				block(model, "Post", Vector3.new(1.3, 4.6, 1.3), line * CFrame.new(x, 2.3, 0), post)
			end
			if not isGate then
				local middle = line * CFrame.new(x + TILE / 2, 0, 0)
				block(model, "Rail", Vector3.new(TILE, 0.55, 0.55), middle * CFrame.new(0, 3.3, 0), rail)
				block(model, "Rail", Vector3.new(TILE, 0.55, 0.55), middle * CFrame.new(0, 1.3, 0), rail)
				for _, sign in { 1, -1 } do
					local cross = block(model, "Cross", Vector3.new(diagonal, 0.4, 0.35), middle * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, sign * slope), rail)
					cross.CanCollide = false
				end
			end
		end
	end
end

-- Mapa japonés: el camino de losas del decorado llega hasta donde empieza la parcela más grande; mientras esta es más
-- pequeña, este tramo (con las mismas losas y bordillos) lo une con su entrada.
local PATH_STONE = { Color3.fromRGB(238, 232, 244), Color3.fromRGB(216, 208, 230) }
local PATH_CURB = Color3.fromRGB(238, 52, 62)

local function buildApproach(model: Instance, cframe: CFrame, size: number)
	local from, to = -Config.Plot.MaxSize / 2, -size / 2
	local length = to - from
	if not JAPAN or length <= 0 then
		return
	end
	local floor = Config.Plot.FloorHeight
	local count = math.ceil(length / 9)
	local step = length / count
	for row = 0, count - 1 do
		for lane = 0, 1 do
			local tile = block(model, "Path", Vector3.new(8.5, 0.12, step - 0.5), cframe * CFrame.new((lane - 0.5) * 9, 0.42 - floor, from + (row + 0.5) * step), PATH_STONE[(row + lane) % 2 + 1])
			tile.CanQuery = false
		end
	end
	for _, sign in { 1, -1 } do
		block(model, "Curb", Vector3.new(1.2, 0.5, length), cframe * CFrame.new(sign * 9.6, 0.6 - floor, from + length / 2), PATH_CURB)
	end
end

-- (Re)monta suelo, muro, luces y decorado de la parcela con su medida y su aspecto, y pone en su sitio la entrada y el
-- cartel. Lo nuevo se crea antes de quitar lo viejo, para que nadie se caiga entre medias.
local function layout(plot, size: number, look)
	local cfg = Config.Plot
	local cframe = plot.cframe
	local old = plot.size
	local ground = Instance.new("Model")
	ground.Name = "Ground"

	-- Suelo a cuadros: baldosas de dos tonos que cambian de color según tenga dueño o no.
	local tiles = {}
	local perSide = size / TILE
	for row = 1, perSide do
		for column = 1, perSide do
			local tile = block(
				ground,
				"Tile",
				Vector3.new(TILE, cfg.FloorHeight, TILE),
				cframe * CFrame.new(-size / 2 + (column - 0.5) * TILE, -cfg.FloorHeight / 2, -size / 2 + (row - 0.5) * TILE),
				FLOOR_FREE[1]
			)
			local edge = row == 1 or column == 1 or row == perSide or column == perSide
			table.insert(tiles, { part = tile, shade = (row + column) % 2 + 1, edge = edge })
		end
	end

	buildFence(ground, cframe, plot.index, size, look)
	buildApproach(ground, cframe, size)
	if plot.owner then
		PlotLooks.build({ model = ground, cframe = cframe, half = size / 2, color = plotColor(plot.index, 1), post = if JAPAN then 7.1 else 4.6 }, look)
	end

	-- Luz repartida sobre el centro sin postes que estorben a los destructibles.
	local lightCfg = Config.PlotLighting
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local anchor = block(ground, "PlotLight", Vector3.one, cframe * CFrame.new(x * size * lightCfg.Offset, lightCfg.Height, z * size * lightCfg.Offset), Color3.new(1, 1, 1))
			anchor.Transparency = 1
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.CastShadow = false
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 232, 202)
			light.Brightness = 0
			light.Enabled = false
			light:SetAttribute("Base", lightCfg.Brightness)
			light.Range = lightCfg.Range
			light.Parent = anchor
			CollectionService:AddTag(light, "NightLight")
		end
	end

	plot.size = size
	plot.look = look
	plot.tiles = tiles
	plot.spawnOffset = Vector3.new(0, 0, -size / 2 + 6)
	plot.spawn.CFrame = cframe * CFrame.new(plot.spawnOffset) * CFrame.Angles(0, math.pi, 0)
	plot.sign.CFrame = cframe * CFrame.new(0, 21, -size / 2)
	paint(plot, plot.owner ~= nil)
	ground.Parent = plot.model
	if plot.ground then
		plot.ground:Destroy()
	end
	plot.ground = ground
	plot.model:SetAttribute("Size", size)

	if old and old ~= size then
		for _, callback in resizeCallbacks do
			task.spawn(callback, plot, old)
		end
	end
end

-- Vuelve a montar la parcela si la medida o el aspecto que le tocan (por los renacimientos de su dueño) han cambiado.
local function refresh(plot, force: boolean?)
	local rebirths = if plot.owner then Stats.rebirths(plot.owner) else 0
	local size = Stats.plotSize(rebirths)
	local look = PlotLooks.get(rebirths)
	if force or size ~= plot.size or look.level ~= plot.look.level then
		layout(plot, size, look)
	end
end

local function buildHub(parent: Instance)
	local cfg = Config.Plot
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Shape = Enum.PartType.Cylinder
	hub.Anchored = true
	hub.Size = Vector3.new(cfg.FloorHeight, cfg.HubRadius * 2, cfg.HubRadius * 2)
	hub.CFrame = CFrame.new(0, cfg.FloorHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	hub.Color = Color3.fromRGB(235, 195, 120)
	hub.Material = Enum.Material.Pavement
	hub.Parent = parent
end

local function buildPlot(index: number, parent: Instance)
	local cfg = Config.Plot
	local angle = (index - 1) / cfg.Count * math.pi * 2
	local center = Vector3.new(math.cos(angle) * cfg.RingRadius, cfg.FloorHeight, math.sin(angle) * cfg.RingRadius)
	local cframe = CFrame.lookAt(center, Vector3.new(0, cfg.FloorHeight, 0))

	local model = Instance.new("Model")
	model.Name = "Parcela" .. index

	-- Mira hacia dentro de la parcela (layout la pone en su sitio).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Parent = model

	local signAnchor = Instance.new("Part")
	signAnchor.Name = "Sign"
	signAnchor.Anchored = true
	signAnchor.CanCollide = false
	signAnchor.CanQuery = false
	signAnchor.Transparency = 1
	signAnchor.Size = Vector3.one
	signAnchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 140)
	gui.MaxDistance = 250
	gui.Parent = signAnchor

	-- Círculo con la cara del dueño, encima del nombre (escondido si está libre).
	local avatar = Instance.new("Frame")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.fromScale(0.5, 0)
	avatar.Size = UDim2.fromOffset(84, 84)
	avatar.BackgroundColor3 = Color3.new(0, 0, 0)
	avatar.Visible = false
	avatar.Parent = gui
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.new(1, -8, 1, -8)
	face.BackgroundColor3 = plotColor(index, 1)
	face.Parent = avatar
	local faceCorner = Instance.new("UICorner")
	faceCorner.CornerRadius = UDim.new(1, 0)
	faceCorner.Parent = face
	local faceStroke = Instance.new("UIStroke")
	faceStroke.Thickness = 3
	faceStroke.Color = plotColor(index, 1)
	faceStroke.Parent = face

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0, 1)
	label.Size = UDim2.new(1, 0, 0, 50)
	label.BackgroundTransparency = 1
	label.TextColor3 = plotColor(index, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 28
	Tell.world(label, "Free plot")
	label.Parent = gui

	local plot = { index = index, cframe = cframe, model = model, owner = nil, spawn = spawn, sign = signAnchor, label = label, avatar = avatar, face = face }
	layout(plot, cfg.Size, PlotLooks.get(0))
	model.Parent = parent
	plots[index] = plot
end

local function moveToPlot(character: Model, plot)
	character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
end

local function assign(player: Player)
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			byPlayer[player] = plot
			refresh(plot, true)
			-- Los renacimientos llegan al cargar sus datos (y suben al renacer): la parcela crece y cambia con ellos.
			watchers[player] = player:GetAttributeChangedSignal("Rebirths"):Connect(function()
				if byPlayer[player] == plot then
					refresh(plot)
				end
			end)
			Tell.world(plot.label, "{name}'s plot", { name = player.DisplayName })
			plot.face.Image = `rbxthumb://type=AvatarHeadShot&id={math.max(player.UserId, 1)}&w=150&h=150`
			plot.avatar.Visible = true
			player.RespawnLocation = plot.spawn

			-- Por si el personaje aparece antes de que RespawnLocation haga efecto.
			player.CharacterAdded:Connect(function(character)
				local root = character:WaitForChild("HumanoidRootPart", 5)
				task.wait(0.2)
				if root and byPlayer[player] == plot and (root.Position - plot.spawn.Position).Magnitude > 20 then
					moveToPlot(character, plot)
				end
			end)
			if player.Character then
				moveToPlot(player.Character, plot)
			end
			return
		end
	end
	warn(`[Plots] No free plots left for {player.Name}`)
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	for _, callback in releaseCallbacks do
		callback(plot)
	end
	if watchers[player] then
		watchers[player]:Disconnect()
		watchers[player] = nil
	end
	byPlayer[player] = nil
	plot.owner = nil
	refresh(plot, true)
	Tell.world(plot.label, "Free plot")
	plot.avatar.Visible = false
end

function Plots.get(player: Player)
	return byPlayer[player]
end

function Plots.all()
	return plots
end

-- callback(plot) se llama justo antes de que la parcela quede libre.
function Plots.onRelease(callback)
	table.insert(releaseCallbacks, callback)
end

-- callback(plot, ladoAnterior) se llama cuando la parcela cambia de medida (plot.size ya es la nueva).
function Plots.onResize(callback)
	table.insert(resizeCallbacks, callback)
end

function Plots.start()
	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = workspace

	buildHub(folder)
	for index = 1, Config.Plot.Count do
		buildPlot(index, folder)
	end

	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
end

return Plots
