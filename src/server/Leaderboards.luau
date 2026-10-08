-- Clasificaciones del hub: tres paneles grandes (tiempo jugado, dinero ganado y Robux gastados)
-- con los 10 mejores. Las puntuaciones globales van en OrderedDataStore (cada minuto se sube la de
-- los jugadores del servidor y se lee el top 10); si el DataStore no está disponible (lugar sin
-- publicar o sin acceso a la API en Studio) los paneles enseñan solo a los jugadores de este servidor
-- y lo avisan abajo. El dinero se guarda en escala logarítmica para que quepan los números enormes.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local Missions = require(script.Parent.Missions)

local Leaderboards = {}

local TOP = 10
local REFRESH = 60 -- segundos entre actualizaciones
local TICK = 15 -- cada cuántos segundos se suma tiempo jugado
local LOG_SCALE = 1e6

local function formatTime(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	return if hours > 0 then `{hours} h {minutes} min` else `{minutes} min`
end

-- score = lo que se guarda (entero) para ordenar; value = lo que se enseña a partir del score.
local METRICS = {
	{
		key = "playTime",
		title = "Tiempo jugado",
		color = Color3.fromRGB(80, 190, 255),
		glyph = "T",
		store = "LB_PlayTime",
		score = function(data)
			return math.floor(data.playTime)
		end,
		show = function(score)
			return formatTime(score)
		end,
	},
	{
		key = "totalCoins",
		title = "Dinero ganado",
		color = Color3.fromRGB(255, 200, 60),
		glyph = "$",
		store = "LB_Coins",
		score = function(data)
			local coins = data.totalCoins
			if coins ~= coins or coins == math.huge then
				return nil
			end
			return math.floor(math.log10(coins + 1) * LOG_SCALE)
		end,
		show = function(score)
			return Format.short(math.max(0, 10 ^ (score / LOG_SCALE) - 1))
		end,
	},
	{
		key = "robuxSpent",
		title = "Robux gastados",
		color = Color3.fromRGB(120, 230, 120),
		glyph = "R$",
		store = "LB_Robux",
		score = function(data)
			return math.floor(data.robuxSpent)
		end,
		show = function(score)
			return `R$ {Format.short(score)}`
		end,
	},
}

local boards = {} -- [key] = { rows = { rank, avatar, name, value } }
local names = {} -- [userId] = nombre (caché de GetNameFromUserIdAsync)

-- Panel -----------------------------------------------------------------------------------

local function label(parent: Instance, size: number, color: Color3?): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.Text = ""
	text.TextSize = size
	text.TextColor3 = color or Color3.new(1, 1, 1)
	text.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = text
	return text
end

local LACQUER = Color3.fromRGB(176, 38, 34) -- rojo laca de los torii
local WOOD = Color3.fromRGB(70, 42, 32)
local GOLD = Color3.fromRGB(226, 182, 80)
local ROOF = Color3.fromRGB(48, 54, 66)
local STONE = Color3.fromRGB(122, 126, 136)
local CREAM = Color3.fromRGB(255, 244, 220)

-- Color del número de puesto: del rojo del primero al amarillo del décimo.
local function rankColor(index: number): Color3
	return Color3.fromRGB(255, 84, 70):Lerp(Color3.fromRGB(255, 215, 80), (index - 1) / (TOP - 1))
end

local function buildBoard(parent: Instance, metric, position: Vector3, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "Clasificacion_" .. metric.key
	local base = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
	local floor = Config.Plot.FloorHeight

	local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Anchored = true
		item.Size = size
		item.CFrame = cframe
		item.Color = color
		item.Material = material or Enum.Material.SmoothPlastic
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			item.Shape = shape
		end
		item.Parent = model
		return item
	end

	local width, height = 20, 26
	local columnHeight = 36
	local columnX = width / 2 + 2.2
	local panelY = floor + 1.7 + 1.5 + height / 2
	local columnTop = floor + 1.7 + columnHeight

	-- Dos peldaños de piedra.
	block("Step", Vector3.new(width + 11, 1.2, 7), base * CFrame.new(0, floor + 0.6, 0.5), STONE, Enum.Material.Slate)
	block("StepTop", Vector3.new(width + 9, 0.5, 5.6), base * CFrame.new(0, floor + 1.45, 0.5), STONE:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Slate)

	-- Dos columnas de laca roja, con zócalo negro y aros dorados, como las de un torii.
	local upright = CFrame.Angles(0, 0, math.rad(90))
	for _, side in { -1, 1 } do
		local at = base * CFrame.new(side * columnX, 0, 0.4)
		block("Plinth", Vector3.new(1.4, 4.4, 4.4), at * CFrame.new(0, floor + 2.4, 0) * upright, Color3.fromRGB(30, 28, 32), nil, Enum.PartType.Cylinder)
		block("Column", Vector3.new(columnHeight - 1.4, 3.6, 3.6), at * CFrame.new(0, floor + 1.7 + (columnHeight + 1.4) / 2, 0) * upright, LACQUER, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		for _, ringY in { 4.2, columnHeight - 1.4 } do
			block("Ring", Vector3.new(0.7, 3.9, 3.9), at * CFrame.new(0, floor + 1.7 + ringY, 0) * upright, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end

	-- Panel de madera oscura con marco de laca roja y filo dorado entre las columnas.
	local panel = block("Panel", Vector3.new(width, height, 1), base * CFrame.new(0, panelY, 0), WOOD)
	block("Trim", Vector3.new(width + 0.6, height + 0.6, 1.1), base * CFrame.new(0, panelY, 0.1), GOLD, Enum.Material.Metal)
	block("Frame", Vector3.new(width + 1.8, height + 1.8, 0.8), base * CFrame.new(0, panelY, 0.3), LACQUER)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(640, 832)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Parent = panel

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.Parent = gui
	local backGradient = Instance.new("UIGradient")
	backGradient.Rotation = 90
	backGradient.Color = ColorSequence.new(Color3.fromRGB(84, 50, 38), Color3.fromRGB(36, 22, 20))
	backGradient.Parent = back

	local rows = {}
	for index = 1, TOP do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(14, 14 + (index - 1) * 80)
		row.Size = UDim2.new(1, -28, 0, 72)
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BorderSizePixel = 0
		row.Parent = back
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.fromRGB(126, 76, 50), Color3.fromRGB(62, 36, 30))
		gradient.Parent = row
		local border = Instance.new("UIStroke")
		border.Color = GOLD
		border.Thickness = 2
		border.Parent = row

		local rank = label(row, 30, rankColor(index))
		rank.Position = UDim2.fromOffset(8, 2)
		rank.Size = UDim2.fromOffset(60, 30)
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.Text = "#" .. index
		local avatar = Instance.new("ImageLabel")
		avatar.BackgroundColor3 = Color3.fromRGB(34, 20, 18)
		avatar.Position = UDim2.fromOffset(70, 10)
		avatar.Size = UDim2.fromOffset(52, 52)
		avatar.Parent = row
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = avatar
		local avatarBorder = Instance.new("UIStroke")
		avatarBorder.Color = GOLD
		avatarBorder.Thickness = 2
		avatarBorder.Parent = avatar
		local name = label(row, 34, CREAM)
		name.Position = UDim2.fromOffset(132, 8)
		name.Size = UDim2.new(1, -150, 1, -8)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = label(row, 22, metric.color:Lerp(Color3.new(1, 1, 1), 0.35))
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -10, 0, 4)
		value.Size = UDim2.fromOffset(190, 22)
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { rank = rank, avatar = avatar, name = name, value = value, row = row }
	end

	-- Tejado a dos aguas de tejas oscuras con caballete y adornos dorados en las puntas.
	local depth = 8.5
	local slope = math.rad(14)
	local half = width / 2 + 7.5
	local ridgeY = columnTop + 0.6
	for _, side in { -1, 1 } do
		block(
			"Roof",
			Vector3.new(half / math.cos(slope), 1.1, depth),
			base * CFrame.new(side * half / 2, ridgeY - half / 2 * math.tan(slope), 0.5) * CFrame.Angles(0, 0, -side * slope),
			ROOF,
			Enum.Material.Slate
		)
		block(
			"EaveTrim",
			Vector3.new(0.7, 0.9, depth + 0.3),
			base * CFrame.new(side * (half - 0.3), ridgeY - half * math.tan(slope) + 0.1, 0.5),
			GOLD,
			Enum.Material.Metal
		)
	end
	block("Ridge", Vector3.new(1.6, 1.6, depth + 0.8), base * CFrame.new(0, ridgeY + 0.2, 0.5) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(30, 34, 44), Enum.Material.Slate)
	for _, end_ in { -1, 1 } do
		block("Ornament", Vector3.new(1.4, 1.4, 1.4), base * CFrame.new(0, ridgeY + 1.2, 0.5 + end_ * (depth / 2 + 0.2)), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
	end

	-- Letrero de madera con marco dorado colgado entre las columnas, bajo el tejado.
	local signWidth, signHeight = 21.5, 4.4
	local signY = panelY + height / 2 + 0.8 + signHeight / 2
	block("SignFrame", Vector3.new(signWidth + 1, signHeight + 1, 0.5), base * CFrame.new(0, signY, 0.2), GOLD, Enum.Material.Metal)
	local banner = block("Banner", Vector3.new(signWidth, signHeight, 0.8), base * CFrame.new(0, signY, 0), WOOD)

	local bannerGui = Instance.new("SurfaceGui")
	bannerGui.Face = Enum.NormalId.Front
	bannerGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	bannerGui.CanvasSize = Vector2.new(1032, 211)
	bannerGui.LightInfluence = 0
	bannerGui.MaxDistance = 300
	bannerGui.Parent = banner
	local bannerBack = Instance.new("Frame")
	bannerBack.Size = UDim2.fromScale(1, 1)
	bannerBack.BackgroundColor3 = Color3.new(1, 1, 1)
	bannerBack.BorderSizePixel = 0
	bannerBack.Parent = bannerGui
	local bannerGradient = Instance.new("UIGradient")
	bannerGradient.Rotation = 90
	bannerGradient.Color = ColorSequence.new(Color3.fromRGB(150, 36, 32), Color3.fromRGB(84, 18, 20))
	bannerGradient.Parent = bannerBack
	local title = label(bannerBack, 88, CREAM)
	title.Size = UDim2.fromScale(1, 1)
	title.Text = metric.title
	title.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 88
	limit.Parent = title
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingLeft = UDim.new(0, 200)
	titlePad.PaddingRight = UDim.new(0, 200)
	titlePad.PaddingTop = UDim.new(0, 36)
	titlePad.PaddingBottom = UDim.new(0, 36)
	titlePad.Parent = title
	-- Dos monedas doradas (mon) a los lados con la letra de la clasificación.
	for _, side in { 0, 1 } do
		local disc = Instance.new("Frame")
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.new(side, if side == 0 then 110 else -110, 0.5, 0)
		disc.Size = UDim2.fromOffset(130, 130)
		disc.BackgroundColor3 = Color3.new(1, 1, 1)
		disc.Parent = bannerBack
		local discCorner = Instance.new("UICorner")
		discCorner.CornerRadius = UDim.new(1, 0)
		discCorner.Parent = disc
		local discGradient = Instance.new("UIGradient")
		discGradient.Rotation = 90
		discGradient.Color = ColorSequence.new(Color3.fromRGB(255, 232, 140), Color3.fromRGB(196, 140, 40))
		discGradient.Parent = disc
		local discBorder = Instance.new("UIStroke")
		discBorder.Color = Color3.new(0, 0, 0)
		discBorder.Thickness = 4
		discBorder.Parent = disc
		local glyph = label(disc, 64, metric.color:Lerp(Color3.new(1, 1, 1), 0.5))
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Text = metric.glyph
	end

	model.Parent = parent
	boards[metric.key] = { rows = rows }
end

-- Rellena el panel con una lista { { userId, name, score } } ya ordenada de mayor a menor.
local function render(metric, entries, isGlobal: boolean)
	local board = boards[metric.key]
	if not board then
		return
	end
	for index, row in board.rows do
		local entry = entries[index]
		row.row.Visible = true
		if entry then
			row.name.Text = "@" .. entry.name
			row.value.Text = metric.show(entry.score)
			row.avatar.Image = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=100&h=100`
			row.avatar.Visible = true
		else
			-- Hueco sin jugador: se queda la fila vacía para que el panel siga lleno.
			row.name.Text = "- - -"
			row.value.Text = ""
			row.avatar.Visible = false
		end
	end
end

-- Datos --------------------------------------------------------------------------------------

local function orderedStore(metric)
	if game.PlaceId == 0 then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(`{Config.DataStoreName}_{metric.store}`)
	end)
	return if ok then result else nil
end

local function nameOf(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName
	end
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok then name else "Jugador"
	return names[userId]
end

-- Los jugadores de este servidor, ordenados (también vale cuando no hay DataStore).
local function localEntries(metric)
	local entries = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerData.read(player)
		local score = data and metric.score(data)
		if score then
			table.insert(entries, { userId = player.UserId, name = player.DisplayName, score = score })
		end
	end
	table.sort(entries, function(a, b)
		return a.score > b.score
	end)
	return entries
end

local function refresh(metric)
	local store = orderedStore(metric)
	if store then
		-- Sube las puntuaciones de los jugadores de este servidor y lee el top.
		for _, player in Players:GetPlayers() do
			local data = PlayerData.read(player)
			local score = data and metric.score(data)
			if score and score > 0 then
				pcall(store.SetAsync, store, tostring(player.UserId), score)
			end
		end
		local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
		if ok then
			local page = pages:GetCurrentPage()
			local entries = {}
			for _, item in page do
				local userId = tonumber(item.key)
				if userId then
					table.insert(entries, { userId = userId, name = nameOf(userId), score = item.value })
				end
			end
			render(metric, entries, true)
			return
		end
	end
	render(metric, localEntries(metric), false)
end

-- Robux gastados: se suman cuando se completa una compra (pase de juego o producto).
local function recordPurchase(player: Player?, id: number, infoType: Enum.InfoType)
	if not player then
		return
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		PlayerData.addRobuxSpent(player, info.PriceInRobux)
	end
end

function Leaderboards.start()
	local map = workspace:WaitForChild("Map")
	local radius = Config.Plot.HubRadius - 12
	local center = Vector3.zero
	for index, metric in METRICS do
		local angle = math.rad(247.5 + (index - 1) * 45)
		buildBoard(map, metric, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), center)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased then
			recordPurchase(player, gamePassId, Enum.InfoType.GamePass)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if purchased then
			recordPurchase(Players:GetPlayerByUserId(userId), productId, Enum.InfoType.Product)
		end
	end)

	-- Tiempo jugado: se suma por tramos mientras el jugador está dentro.
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				PlayerData.addPlayTime(player, TICK)
				Missions.add(player, "minutes", TICK / 60)
			end
		end
	end)

	task.spawn(function()
		-- Las dos primeras vueltas son rápidas para que los paneles no esperen un minuto con los jugadores ya dentro.
		local waits = { 4, 10 }
		local round = 0
		while true do
			round += 1
			task.wait(waits[round] or REFRESH)
			for _, metric in METRICS do
				refresh(metric)
			end
		end
	end)
end

return Leaderboards
