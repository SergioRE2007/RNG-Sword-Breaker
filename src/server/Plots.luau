-- Construye el hub y las parcelas, y asigna una parcela a cada jugador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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

-- plot = { index, cframe (centro, a ras de suelo, -Z mira al hub), spawnOffset, owner, tiles, spawn, label }
local plots = {}
local byPlayer = {}
local releaseCallbacks = {}

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

local function paint(plot, owned: boolean)
	local colors = if owned then FLOOR_OWNED else FLOOR_FREE
	for _, tile in plot.tiles do
		tile.part.Color = colors[tile.shade]
		tile.part.Material = if owned then OWNED_MATERIAL else Enum.Material.SmoothPlastic
	end
end

-- Muro japonés (tsuijibei) para el mapa japonés: zócalo de piedra, pared blanca con una franja del color de la
-- parcela, tejadillo de tejas azules y pilares de piedra con remate; la entrada del lado del hub lleva dos pilares
-- más altos. Mismo recorrido y mismo hueco que la valla de siempre.
local WALL_STONE = Color3.fromRGB(150, 146, 168)
local WALL_PLASTER = Color3.fromRGB(252, 246, 238)
local WALL_ROOF = Color3.fromRGB(54, 70, 124)
local GATE_RED = Color3.fromRGB(232, 52, 62)

local function stone(part: Part, material: Enum.Material?)
	part.Material = material or Enum.Material.Slate
	return part
end

local function buildWall(model: Instance, cframe: CFrame, index: number)
	local half = Config.Plot.Size / 2
	local segments = Config.Plot.Size / TILE
	local band = plotColor(index, 0.9)

	for side = 0, 3 do
		local line = cframe * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -half)
		for segment = 1, segments do
			local x = -half + (segment - 1) * TILE
			local isGate = side == 0 and (segment == segments / 2 or segment == segments / 2 + 1)
			local gatePost = side == 0 and (segment == segments / 2 or segment == segments / 2 + 2)
			if not (side == 0 and segment == segments / 2 + 1) then
				-- Pilar de piedra con un remate de teja (más alto y rojo en la entrada).
				local height = if gatePost then 8.4 else 6
				local width = if gatePost then 2.4 else 1.9
				stone(block(model, "Post", Vector3.new(width, height, width), line * CFrame.new(x, height / 2, 0), WALL_STONE))
				block(model, "PostCap", Vector3.new(width + 1.2, 0.6, width + 1.2), line * CFrame.new(x, height + 0.3, 0), if gatePost then GATE_RED else WALL_ROOF)
				block(model, "PostTop", Vector3.new(width * 0.5, 0.5, width * 0.5), line * CFrame.new(x, height + 0.85, 0), if gatePost then Color3.fromRGB(255, 210, 70) else WALL_STONE)
			end
			if not isGate then
				local middle = line * CFrame.new(x + TILE / 2, 0, 0)
				stone(block(model, "WallBase", Vector3.new(TILE, 1.5, 1.9), middle * CFrame.new(0, 0.75, 0), WALL_STONE))
				block(model, "Wall", Vector3.new(TILE, 3.0, 1.3), middle * CFrame.new(0, 3.0, 0), WALL_PLASTER)
				block(model, "WallBand", Vector3.new(TILE, 0.4, 1.4), middle * CFrame.new(0, 2.2, 0), band)
				block(model, "WallRoof", Vector3.new(TILE, 0.5, 2.6), middle * CFrame.new(0, 4.75, 0), WALL_ROOF)
				block(model, "WallRidge", Vector3.new(TILE, 0.4, 1.3), middle * CFrame.new(0, 5.2, 0), WALL_ROOF:Lerp(Color3.new(1, 1, 1), 0.15))
			end
		end
	end
end

-- Valla de postes, dos travesaños y aspas, del color de la parcela, con un hueco de entrada
-- en el lado del hub.
local function buildFence(model: Instance, cframe: CFrame, index: number)
	if JAPAN then
		buildWall(model, cframe, index)
		return
	end
	local half = Config.Plot.Size / 2
	local segments = Config.Plot.Size / TILE
	local rail = plotColor(index, 0.95)
	local post = plotColor(index, 0.6)
	local slope = math.atan2(2, TILE)
	local diagonal = math.sqrt(TILE ^ 2 + 2 ^ 2)

	for side = 0, 3 do
		local line = cframe * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -half)
		for segment = 1, segments do
			local x = -half + (segment - 1) * TILE
			-- Entrada: los dos tramos del centro del lado que mira al hub.
			local isGate = side == 0 and (segment == segments / 2 or segment == segments / 2 + 1)
			if not (side == 0 and segment == segments / 2 + 1) then
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
	local spawnOffset = Vector3.new(0, 0, -cfg.Size / 2 + 6)

	local model = Instance.new("Model")
	model.Name = "Parcela" .. index

	-- Suelo a cuadros: baldosas de dos tonos que cambian de color según tenga dueño o no.
	local tiles = {}
	local perSide = cfg.Size / TILE
	for row = 1, perSide do
		for column = 1, perSide do
			local tile = block(
				model,
				"Tile",
				Vector3.new(TILE, cfg.FloorHeight, TILE),
				cframe * CFrame.new(-cfg.Size / 2 + (column - 0.5) * TILE, -cfg.FloorHeight / 2, -cfg.Size / 2 + (row - 0.5) * TILE),
				FLOOR_FREE[1]
			)
			table.insert(tiles, { part = tile, shade = (row + column) % 2 + 1 })
		end
	end

	buildFence(model, cframe, index)

	-- Mira hacia dentro de la parcela.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = cframe * CFrame.new(spawnOffset) * CFrame.Angles(0, math.pi, 0)
	spawn.Parent = model

	local signAnchor = Instance.new("Part")
	signAnchor.Name = "Sign"
	signAnchor.Anchored = true
	signAnchor.CanCollide = false
	signAnchor.CanQuery = false
	signAnchor.Transparency = 1
	signAnchor.Size = Vector3.one
	signAnchor.CFrame = cframe * CFrame.new(0, 9, -cfg.Size / 2)
	signAnchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 50)
	gui.MaxDistance = 250
	gui.Parent = signAnchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = plotColor(index, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 28
	label.Text = "Parcela libre"
	label.Parent = gui

	model.Parent = parent
	plots[index] = { index = index, cframe = cframe, spawnOffset = spawnOffset, owner = nil, tiles = tiles, spawn = spawn, label = label }
end

local function moveToPlot(character: Model, plot)
	character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
end

local function assign(player: Player)
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			byPlayer[player] = plot
			paint(plot, true)
			plot.label.Text = "Parcela de " .. player.DisplayName
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
	warn(`[Plots] No quedan parcelas libres para {player.Name}`)
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	for _, callback in releaseCallbacks do
		callback(plot)
	end
	byPlayer[player] = nil
	plot.owner = nil
	paint(plot, false)
	plot.label.Text = "Parcela libre"
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
