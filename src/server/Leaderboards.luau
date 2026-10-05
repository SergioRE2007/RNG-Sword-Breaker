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
		title = "TIEMPO JUGADO",
		color = Color3.fromRGB(80, 190, 255),
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
		title = "DINERO GANADO",
		color = Color3.fromRGB(255, 200, 60),
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
		title = "ROBUX GASTADOS",
		color = Color3.fromRGB(120, 230, 120),
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

local MEDALS = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(215, 220, 232), Color3.fromRGB(215, 140, 80) }

local function buildBoard(parent: Instance, metric, position: Vector3, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "Clasificacion_" .. metric.key
	local base = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
	local floor = Config.Plot.FloorHeight

	local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Anchored = true
		item.Size = size
		item.CFrame = cframe
		item.Color = color
		item.Material = material or Enum.Material.SmoothPlastic
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		item.Parent = model
		return item
	end

	local width, height = 20, 26
	local dark = Color3.fromRGB(28, 30, 52)
	for _, side in { -1, 1 } do
		block("Leg", Vector3.new(1.4, 7, 1.4), base * CFrame.new(side * (width / 2 - 2), floor + 3.5, 0.2), dark)
	end
	block("Foot", Vector3.new(width - 1, 0.8, 3), base * CFrame.new(0, floor + 0.4, 0.2), metric.color:Lerp(dark, 0.5))
	local panel = block("Panel", Vector3.new(width, height, 1), base * CFrame.new(0, floor + 7 + height / 2, 0), dark)
	-- Marco de color del panel.
	block("Frame", Vector3.new(width + 1, height + 1, 0.6), base * CFrame.new(0, floor + 7 + height / 2, 0.25), metric.color)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(640, 840)
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
	backGradient.Color = ColorSequence.new(Color3.fromRGB(58, 64, 112), Color3.fromRGB(20, 22, 44))
	backGradient.Parent = back

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 96)
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.BorderSizePixel = 0
	header.Parent = back
	local headerGradient = Instance.new("UIGradient")
	headerGradient.Rotation = 90
	headerGradient.Color = ColorSequence.new(metric.color:Lerp(Color3.new(1, 1, 1), 0.25), metric.color:Lerp(Color3.new(0, 0, 0), 0.25))
	headerGradient.Parent = header
	local title = label(header, 58)
	title.Size = UDim2.fromScale(1, 1)
	title.Text = metric.title
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end

	local rows = {}
	for index = 1, TOP do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(16, 108 + (index - 1) * 66)
		row.Size = UDim2.new(1, -32, 0, 58)
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BorderSizePixel = 0
		row.Parent = back
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = row
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		local tone = MEDALS[index]
		gradient.Color = ColorSequence.new(
			if tone then tone:Lerp(Color3.fromRGB(40, 44, 80), 0.6) else Color3.fromRGB(70, 76, 128),
			if tone then tone:Lerp(Color3.fromRGB(20, 22, 44), 0.7) else Color3.fromRGB(38, 42, 78)
		)
		gradient.Parent = row
		local border = Instance.new("UIStroke")
		border.Color = tone or Color3.fromRGB(10, 12, 30)
		border.Thickness = if tone then 3 else 2
		border.Parent = row

		local rank = label(row, 40, tone)
		rank.Position = UDim2.fromOffset(6, 0)
		rank.Size = UDim2.fromOffset(52, 58)
		rank.Text = tostring(index)
		local avatar = Instance.new("ImageLabel")
		avatar.BackgroundColor3 = Color3.fromRGB(20, 22, 44)
		avatar.Position = UDim2.fromOffset(62, 5)
		avatar.Size = UDim2.fromOffset(48, 48)
		avatar.Parent = row
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = avatar
		local name = label(row, 34)
		name.Position = UDim2.fromOffset(120, 0)
		name.Size = UDim2.new(1, -330, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = label(row, 34, metric.color:Lerp(Color3.new(1, 1, 1), 0.3))
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -12, 0, 0)
		value.Size = UDim2.fromOffset(200, 58)
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { rank = rank, avatar = avatar, name = name, value = value, row = row }
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
			row.name.Text = entry.name
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
