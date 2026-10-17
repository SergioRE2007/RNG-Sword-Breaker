-- Recompensas diarias, librería sin start(): es la pestaña "Recompensas" de la Tienda (pedido por el usuario: había
-- demasiados botones en pantalla), y client/PassShop la monta con DailyRewards.build en Hud.PassShop.Body.Rewards.
-- Dentro, dos pestañas: "Tiempo jugado" (Rewards.Playtime.Cards.Reward_<n>, una tarjeta por premio de
-- Config.DailyRewards.Playtime) y "Racha diaria" (Rewards.Streak.Days.Day_<n>). Se cobra tocando la tarjeta (pedido por
-- el usuario: con un botón "Cobrar" quedaba raro). Las listas giran rayos detrás, laten y botan sus premios; al tocarlas
-- dan un bote con destellos y, cuando el servidor lo confirma, les cae el sello "Cobrada". Las tarjetas entran una a una
-- al enseñar la pestaña. Las animaciones van en un solo bucle que solo vive con la pestaña a la vista (y no en modo
-- rendimiento). El servidor cuenta el tiempo y lo publica en el atributo "Daily" (JSON, ver shared/DailyInfo) cada pocos
-- segundos; aquí se adelanta solo entre medias. Con algo por recoger, el botón "Tienda" del menú, la pestaña de la Tienda
-- y la de dentro llevan un aviso rojo (Alert) con la cuenta.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Lang = require(ReplicatedStorage.Shared.Lang)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Performance = require(script.Parent.Performance)
local Potions = require(script.Parent.Potions)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local DailyRewards = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 200, 60)
local RED = Color3.fromRGB(235, 55, 60)
local CARD_BASE = Color3.fromRGB(62, 68, 118)
-- Color de cada premio por tiempo, de menos a más.
local PLAYTIME_COLORS = {
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(70, 210, 150),
	Color3.fromRGB(150, 210, 70),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 200, 50),
}
local STREAK_COLOR = Color3.fromRGB(255, 140, 60)

-- Estado recibido y cuándo llegó (para adelantar el tiempo entre publicaciones).
local state = DailyInfo.sanitize(nil)
local receivedAt = os.clock()

local function readState()
	local raw = player:GetAttribute("Daily")
	if type(raw) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			state = DailyInfo.sanitize(decoded)
			receivedAt = os.clock()
		end
	end
end

-- Estado de hoy: si el servidor aún no ha cambiado de día, lo que llegó es de ayer y se cuenta como vacío.
local function current()
	local today = DailyInfo.today()
	if state.day ~= today then
		local fresh = table.clone(state)
		DailyInfo.roll(fresh, today)
		return fresh, today, 0
	end
	return state, today, state.seconds + math.max(0, os.clock() - receivedAt)
end

local function durationText(minutes: number): string
	if minutes >= 60 and minutes % 60 == 0 then
		return Lang.t(nil, "{n} h", { n = minutes // 60 })
	end
	return Lang.t(nil, "{n} min", { n = minutes })
end

local function ease(target: Instance, time: number, style: Enum.EasingStyle, goal, delay: number?)
	local tween = TweenService:Create(target, TweenInfo.new(time, style, Enum.EasingDirection.Out, 0, false, delay or 0), goal)
	tween:Play()
	return tween
end

-- Aviso rojo con la cantidad, en la esquina de arriba a la derecha de `parent`.
local function alertDot(parent: GuiObject, size: number): (Frame, TextLabel)
	local dot = Instance.new("Frame")
	dot.Name = "Alert"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -size * 0.25, 0, size * 0.25)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = WHITE
	dot.ZIndex = 40
	dot.Visible = false
	dot.Parent = parent
	Ui.round(dot, size // 2)
	Ui.stroke(dot, BLACK, 3)
	Ui.gradient(dot, RED:Lerp(WHITE, 0.25), RED:Lerp(BLACK, 0.2), 90)
	local text = Ui.label(dot, math.floor(size * 0.62))
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 41
	return dot, text
end

-- Casilla de un premio ({ item, amount }): el icono del objeto (o de la poción, con su tier) y la cantidad abajo.
-- Tocarla es como tocar su tarjeta.
local function rewardCell(parent: Instance, reward, size: number, order: number, onClick: () -> ()): TextButton
	local item = Config.Items[reward.item]
	local potion = item.potion
	local cell = Ui.cell(parent, item.color, if potion then potion.tier else nil)
	cell.Name = "Item_" .. reward.item
	cell.LayoutOrder = order
	cell.Size = UDim2.fromOffset(size, size)
	if potion then
		Potions.icon(cell, potion.family, potion.tier)
		Potions.addTag(cell, potion.tier, true)
		Ui.tip(cell, function()
			return Potions.tip(potion.family, potion.tier)
		end, true)
	else
		Ui.image(cell, item.image)
		Ui.tip(cell, function()
			return `{Lang.t(nil, item.name)}\n<font color="{Ui.SOFT}">{Lang.t(nil, item.description)}</font>`, item.color
		end, true)
	end
	if (reward.amount or 1) > 1 then
		Ui.cellLabel(cell, `x{reward.amount}`)
	end
	cell.Activated:Connect(onClick)
	return cell
end

-- Fila de casillas centrada (horizontal o vertical).
local function rewardRow(parent: Instance, rewards, size: number, vertical: boolean, onClick: () -> ()): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rewards"
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local list = Instance.new("UIListLayout")
	list.FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = holder
	for order, reward in rewards do
		rewardCell(holder, reward, size, order, onClick)
	end
	return holder
end

-- Destellos que salen disparados del centro de la tarjeta al tocarla.
local function burst(card: GuiObject, color: Color3)
	if Performance.get() then
		return
	end
	for index = 1, 12 do
		local spark = Instance.new("ImageLabel")
		spark.Name = "Spark"
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromScale(0.5, 0.45)
		local size = math.random(26, 44)
		spark.Size = UDim2.fromOffset(size, size)
		spark.BackgroundTransparency = 1
		spark.Image = Ui.IMAGES.boton_destello
		spark.ImageColor3 = if index % 3 == 0 then WHITE else color:Lerp(WHITE, 0.35)
		spark.ZIndex = 30
		spark.Parent = card
		local angle = index / 12 * math.pi * 2 + math.random() * 0.4
		local reach = math.random(110, 190)
		ease(spark, 0.65, Enum.EasingStyle.Quad, {
			Position = UDim2.new(0.5, math.cos(angle) * reach, 0.45, math.sin(angle) * reach),
			Size = UDim2.fromOffset(0, 0),
			Rotation = math.random(-180, 180),
			ImageTransparency = 0.4,
		})
		task.delay(0.7, spark.Destroy, spark)
	end
end

-- Tarjeta: botón con el estilo de las filas de Misiones (panel del color y borde negro, dorado si está lista), rayos que
-- giran detrás de los premios cuando está lista y, encima, la capa oscura con el sello "Cobrada".
local function card(parent: Instance, name: string, color: Color3)
	local frame = Instance.new("TextButton")
	frame.Name = name
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 12)
	local border = Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, CARD_BASE, color)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- Rayos y resplandor detrás de los premios (recortados a la tarjeta).
	local clip = Instance.new("Frame")
	clip.Name = "Glow"
	clip.Position = UDim2.fromOffset(4, 4)
	clip.Size = UDim2.new(1, -8, 1, -8)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Visible = false
	clip.Parent = frame
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(460, 460)
	rays.BackgroundTransparency = 1
	rays.Image = Ui.IMAGES.boton_rayos
	rays.ImageColor3 = color:Lerp(WHITE, 0.45)
	rays.ImageTransparency = 0.55
	rays.Parent = clip

	local done = Instance.new("Frame")
	done.Name = "Done"
	done.Size = UDim2.fromScale(1, 1)
	done.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
	done.BackgroundTransparency = 0.4
	done.ZIndex = 20
	done.Visible = false
	done.Parent = frame
	Ui.round(done, 12)
	local stamp = Ui.label(done, 34)
	stamp.Name = "Stamp"
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromScale(0.5, 0.5)
	stamp.Size = UDim2.new(1, -16, 0, 50)
	stamp.ZIndex = 21
	stamp.Rotation = -10
	stamp.TextColor3 = Ui.COLORS.green:Lerp(WHITE, 0.35)
	stamp.Text = Lang.t(nil, "Claimed")
	Ui.caps(stamp)
	local stampScale = Instance.new("UIScale")
	stampScale.Parent = stamp
	return {
		frame = frame, border = border, scale = scale, glow = clip, rays = rays, done = done, stamp = stamp,
		stampScale = stampScale, color = color, mode = nil, phase = math.random() * 6,
	}
end

-- Pinta el estado de una tarjeta: "ready" (rayos, borde dorado que late), "done" (sello) o "locked". Al pasar de lista a
-- cobrada, el sello cae con un golpe.
local function paint(entry, mode: string)
	if entry.mode == mode then
		return
	end
	local was = entry.mode
	entry.mode = mode
	entry.glow.Visible = mode == "ready" or entry.always == true
	entry.border.Color = if mode == "ready" then GOLD else BLACK
	entry.border.Thickness = if mode == "ready" then 5 else 3
	entry.done.Visible = mode == "done"
	if was == "ready" then
		entry.rewards.Position = entry.base -- deja de botar
	end
	if mode == "done" and was == "ready" and not Performance.get() then
		entry.done.BackgroundTransparency = 1
		ease(entry.done, 0.3, Enum.EasingStyle.Quad, { BackgroundTransparency = 0.4 })
		entry.stampScale.Scale = 2.4
		entry.stamp.Rotation = -32
		ease(entry.stampScale, 0.35, Enum.EasingStyle.Back, { Scale = 1 })
		ease(entry.stamp, 0.35, Enum.EasingStyle.Back, { Rotation = -10 })
	elseif mode == "ready" and was ~= nil and not Performance.get() then
		-- Acaba de quedar lista: un bote para que se note.
		entry.scale.Scale = 1.1
		ease(entry.scale, 0.45, Enum.EasingStyle.Back, { Scale = 1 })
	end
end

-- Toque en una tarjeta: si está lista, bote y destellos y se pide; si no, se sacude.
local function press(entry, ready: boolean, request: () -> ())
	if ready then
		request()
		if not Performance.get() then
			entry.scale.Scale = 1.14
			ease(entry.scale, 0.4, Enum.EasingStyle.Back, { Scale = 1 })
			burst(entry.frame, entry.color)
		end
	else
		Sfx.play("error")
		if not Performance.get() and entry.mode ~= "done" then
			entry.frame.Rotation = 5
			ease(entry.frame, 0.45, Enum.EasingStyle.Elastic, { Rotation = 0 })
		end
	end
end

-- Al pasar el ratón por una tarjeta lista, crece un poco.
local function hover(entry)
	entry.frame.MouseEnter:Connect(function()
		entry.over = true
		if entry.mode == "ready" and not Performance.get() then
			ease(entry.scale, 0.18, Enum.EasingStyle.Back, { Scale = 1.04 })
		end
	end)
	entry.frame.MouseLeave:Connect(function()
		entry.over = false
		ease(entry.scale, 0.18, Enum.EasingStyle.Quad, { Scale = 1 })
	end)
end

-- Franja de arriba de cada pestaña: texto a la izquierda y a la derecha.
local function strip(parent: Instance, color: Color3): (TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "Strip"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 2)
	frame.Size = UDim2.new(1, -24, 0, 52)
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 10)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, color:Lerp(BLACK, 0.15))
	local left = Ui.label(frame, 30)
	left.Name = "Left"
	left.Position = UDim2.fromOffset(16, 0)
	left.Size = UDim2.new(0.6, -16, 1, 0)
	left.TextXAlignment = Enum.TextXAlignment.Left
	local right = Ui.label(frame, 26)
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -16, 0, 0)
	right.Size = UDim2.new(0.4, -16, 1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
	return left, right
end

-- Texto de abajo de la tarjeta: "¡Toca para cobrar!" cuando está lista (late con el bucle).
local function tapLabel(parent: Instance, size: number): TextLabel
	local label = Ui.label(parent, size)
	label.Name = "Tap"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Size = UDim2.new(1, -12, 0, size + 8)
	label.TextScaled = true
	label.Text = Lang.t(nil, "Tap to claim!")
	label.Visible = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.MinTextSize = 12
	limit.Parent = label
	Ui.gradient(label, WHITE, GOLD, 90)
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return label
end

-- Monta la pestaña dentro de `body` (el panel de la ventana `window` de la Tienda); `shopTab` es el botón de la pestaña
-- en la cabecera, que lleva su aviso.
function DailyRewards.build(window: GuiObject, body: Frame, shopTab: GuiObject)
	-- Pestañas, como en Misiones.
	local panes, tabs, tabAlerts = {}, {}, {}
	local cardsOf = { Playtime = {}, Streak = {} } -- tarjetas de cada pestaña, en orden (para la entrada)
	local function enter(name: string)
		if Performance.get() then
			return
		end
		for order, entry in cardsOf[name] do
			entry.scale.Scale = 0.6
			ease(entry.scale, 0.38, Enum.EasingStyle.Back, { Scale = 1 }, (order - 1) * 0.05)
		end
	end
	local function show(name: string)
		for key, pane in panes do
			pane.Visible = key == name
			Ui.setSelected(tabs[key], key == name)
		end
		enter(name)
	end
	for order, entry in { { "Playtime", "Playtime", Ui.COLORS.blue }, { "Streak", "Daily streak", Ui.COLORS.orange } } do
		local name = entry[1]
		local tab = Ui.button(body, Lang.t(nil, entry[2]), entry[3])
		tab.Name = "Tab" .. name
		tab.Position = UDim2.fromOffset(12 + (order - 1) * 262, 6)
		tab.Size = UDim2.fromOffset(250, 50)
		tab.TextSize = 28
		tabs[name] = tab
		tabAlerts[name] = { alertDot(tab, 30) }
		local pane = Instance.new("Frame")
		pane.Name = name
		pane.Position = UDim2.fromOffset(0, 64)
		pane.Size = UDim2.new(1, 0, 1, -64)
		pane.BackgroundTransparency = 1
		pane.Parent = body
		panes[name] = pane
		tab.Activated:Connect(function()
			show(name)
		end)
	end

	-- TIEMPO JUGADO: una tarjeta por premio, en fila: duración arriba, premios en columna, barra con lo que falta abajo.
	local playLeft, playRight = strip(panes.Playtime, Ui.COLORS.blue)
	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.Position = UDim2.fromOffset(12, 64)
	row.Size = UDim2.new(1, -24, 1, -74)
	row.BackgroundTransparency = 1
	row.Parent = panes.Playtime
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 10)
	rowList.Parent = row
	local count = #Config.DailyRewards.Playtime
	local playCards = {}
	for position, info in Config.DailyRewards.Playtime do
		local entry = card(row, "Reward_" .. position, PLAYTIME_COLORS[position] or GOLD)
		local frame, color = entry.frame, entry.color
		frame.LayoutOrder = position
		frame.Size = UDim2.new(1 / count, -10 * (count - 1) / count, 1, 0)
		local function onClick()
			local now, _, seconds = current()
			press(entry, DailyInfo.playtimeReady(now, position, seconds), function()
				Remotes.ClaimDaily:FireServer("playtime", position)
			end)
		end
		frame.Activated:Connect(onClick)
		hover(entry)

		local title = Ui.label(frame, 40)
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.new(0.5, 0, 0, 14)
		title.Size = UDim2.new(1, -10, 0, 46)
		title.Text = durationText(info.minutes)
		Ui.gradient(title, WHITE, color:Lerp(WHITE, 0.3), 90)

		local rewards = rewardRow(frame, info.rewards, 108, true, onClick)
		rewards.AnchorPoint = Vector2.new(0.5, 0.5)
		rewards.Position = UDim2.new(0.5, 0, 0.47, 0)
		rewards.Size = UDim2.new(1, -10, 0.62, 0)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0.5, 1)
		track.Position = UDim2.new(0.5, 0, 1, -14)
		track.Size = UDim2.new(1, -18, 0, 34)
		track.BackgroundColor3 = Ui.COLORS.dark
		track.Parent = frame
		Ui.round(track, 12)
		Ui.stroke(track, BLACK, 2)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = WHITE
		fill.BorderSizePixel = 0
		fill.Parent = track
		Ui.round(fill, 12)
		Ui.gradient(fill, color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.2), 90)
		local timeText = Ui.label(track, 22)
		timeText.Name = "Time"
		timeText.Size = UDim2.fromScale(1, 1)
		timeText.ZIndex = 3
		local tap = tapLabel(frame, 24)
		tap.Position = UDim2.new(0.5, 0, 1, -12)
		entry.track, entry.fill, entry.time, entry.tap, entry.rewards, entry.base = track, fill, timeText, tap, rewards, rewards.Position
		playCards[position] = entry
		table.insert(cardsOf.Playtime, entry)
	end

	-- RACHA: días 1 a 4 arriba; 5, 6 y el 7 (doble de ancho y con rayos siempre) abajo. Se cobra tocando el de hoy.
	local streakLeft, streakRight = strip(panes.Streak, STREAK_COLOR)
	local days = Instance.new("Frame")
	days.Name = "Days"
	days.Position = UDim2.fromOffset(8, 60)
	days.Size = UDim2.new(1, -16, 1, -66)
	days.BackgroundTransparency = 1
	days.Parent = panes.Streak
	local streakCards = {}
	local total = #Config.DailyRewards.Streak
	local function claimStreak(entry)
		local now, today = current()
		press(entry, entry.mode == "ready" and DailyInfo.streakReady(now, today), function()
			Remotes.ClaimDaily:FireServer("streak")
		end)
	end
	for index, rewards in Config.DailyRewards.Streak do
		local column = (index - 1) % 4
		local line = (index - 1) // 4
		local big = index == total
		local wide = big and column < 3
		local entry = card(days, "Day_" .. index, if big then GOLD else STREAK_COLOR)
		local frame, color = entry.frame, entry.color
		entry.always = big
		entry.glow.Visible = big
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		local width = if wide then 0.5 else 0.25
		frame.Position = UDim2.fromScale(column * 0.25 + width / 2, line * 0.5 + 0.25)
		frame.Size = UDim2.new(width, -10, 0.5, -10)
		local function onClick()
			claimStreak(entry)
		end
		frame.Activated:Connect(onClick)
		hover(entry)

		local title = Ui.label(frame, 30)
		title.Name = "Title"
		title.Position = UDim2.fromOffset(14, 8)
		title.Size = UDim2.new(1, -28, 0, 36)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = Lang.t(nil, "Day {n}", { n = index })
		Ui.gradient(title, WHITE, color:Lerp(WHITE, 0.3), 90)

		local todayTag = Ui.label(frame, 18)
		todayTag.Name = "Today"
		todayTag.AnchorPoint = Vector2.new(1, 0)
		todayTag.Position = UDim2.new(1, -12, 0, 12)
		todayTag.Size = UDim2.fromOffset(86, 28)
		todayTag.BackgroundTransparency = 0
		todayTag.BackgroundColor3 = GOLD:Lerp(BLACK, 0.1)
		todayTag.Text = Lang.t(nil, "Today")
		todayTag.Visible = false
		Ui.round(todayTag, 8)
		Ui.stroke(todayTag, BLACK, 2)

		local holder = rewardRow(frame, rewards, if big then 124 else 100, false, onClick)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, 0, 0.5, 6)
		holder.Size = UDim2.new(1, -10, 0.6, 0)
		local tap = tapLabel(frame, 22)
		tap.Position = UDim2.new(0.5, 0, 1, -6)
		entry.today, entry.tap, entry.rewards, entry.base = todayTag, tap, holder, holder.Position
		streakCards[index] = entry
		table.insert(cardsOf.Streak, entry)
	end

	-- Avisos del botón "Tienda" del menú y de la pestaña de la Tienda.
	local tile = Ui.hud():FindFirstChild("Menu") and Ui.hud().Menu:FindFirstChild("PassShop")
	local tileAlert = if tile then { alertDot(tile, 34) } else nil
	local shopAlert = { alertDot(shopTab, 26) }
	local pulse: Tween? = nil
	local function setAlert(alert, amount: number)
		if not alert then
			return
		end
		alert[1].Visible = amount > 0
		alert[2].Text = tostring(amount)
	end

	local function refresh()
		local now, today, seconds = current()
		local pendingPlay = 0
		-- Tiempo jugado.
		for position, info in Config.DailyRewards.Playtime do
			local entry = playCards[position]
			local goal = info.minutes * 60
			local claimed = table.find(now.claimed, position) ~= nil
			local mode = if claimed then "done" elseif seconds >= goal then "ready" else "locked"
			if mode == "ready" then
				pendingPlay += 1
			end
			paint(entry, mode)
			entry.track.Visible = mode == "locked"
			entry.tap.Visible = mode == "ready"
			entry.fill.Size = UDim2.fromScale(math.clamp(seconds / goal, 0, 1), 1)
			entry.time.Text = if mode == "locked" then PotionInfo.clock(goal - seconds) else ""
		end
		playLeft.Text = Lang.t(nil, "Played today: {time}", { time = PotionInfo.clock(seconds) })
		playRight.Text = Lang.t(nil, "Resets in {time}", { time = PotionInfo.clock(DailyInfo.secondsLeft()) })

		-- Racha: las de antes de la que toca, cobradas; la que toca, "Hoy" (lista si aún no se ha cobrado).
		local ready = DailyInfo.streakReady(now, today)
		local claimedUpTo = if ready then now.streak - 1 elseif now.streak == 1 then total else now.streak - 1
		local shown = if ready then now.streak else claimedUpTo
		for index, entry in streakCards do
			local mode = if index <= claimedUpTo then "done" elseif ready and index == now.streak then "ready" else "locked"
			paint(entry, mode)
			entry.today.Visible = index == shown
			entry.tap.Visible = mode == "ready"
		end
		streakLeft.Text = Lang.t(nil, "Day {n} of {total}", { n = shown, total = total })
		streakRight.Text = if ready then Lang.t(nil, "Tap to claim!") else Lang.t(nil, "Next in {time}", { time = PotionInfo.clock(DailyInfo.secondsLeft()) })

		local pendingStreak = if ready then 1 else 0
		setAlert(tabAlerts.Playtime, pendingPlay)
		setAlert(tabAlerts.Streak, pendingStreak)
		setAlert(tileAlert, pendingPlay + pendingStreak)
		setAlert(shopAlert, pendingPlay + pendingStreak)
		-- El aviso del menú se balancea mientras hay algo por recoger.
		local alerting = tileAlert ~= nil and pendingPlay + pendingStreak > 0 and not Performance.get()
		if alerting and not pulse then
			local dot = tileAlert[1]
			dot.Rotation = -10
			pulse = TweenService:Create(dot, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 10 })
			pulse:Play()
		elseif not alerting and pulse then
			pulse:Cancel()
			pulse = nil
			tileAlert[1].Rotation = 0
		end
	end

	local lastClaimed = #state.claimed + state.streak
	player:GetAttributeChangedSignal("Daily"):Connect(function()
		readState()
		-- Algo recién cobrado: sonido.
		local claimedNow = #state.claimed + state.streak
		if claimedNow ~= lastClaimed and window.Visible then
			Sfx.play("coin")
		end
		lastClaimed = claimedNow
		refresh()
	end)
	readState()
	lastClaimed = #state.claimed + state.streak

	-- Animación de las listas (rayos que giran, borde que late, premios que botan, texto que palpita) y de los rayos del
	-- día 7: un solo bucle, solo con la pestaña a la vista.
	local loop: RBXScriptConnection? = nil
	local clock = 0
	local function step(dt: number)
		if Performance.get() then
			return
		end
		clock += dt
		for _, list in cardsOf do
			for _, entry in list do
				if entry.glow.Visible then
					entry.rays.Rotation = (clock + entry.phase) * (if entry.mode == "ready" then 40 else 14)
				end
				if entry.mode == "ready" then
					local wave = (math.sin(clock * 4 + entry.phase) + 1) / 2
					entry.border.Color = GOLD:Lerp(WHITE, wave * 0.6)
					entry.rewards.Position = entry.base + UDim2.fromOffset(0, math.sin(clock * 3 + entry.phase) * 5)
					entry.tap:FindFirstChildOfClass("UIScale").Scale = 1 + wave * 0.08
				end
			end
		end
	end
	local function animate()
		local on = window.Visible and body.Visible and not Performance.get()
		if on and not loop then
			loop = RunService.RenderStepped:Connect(step)
		elseif not on and loop then
			loop:Disconnect()
			loop = nil
		end
	end

	-- Al enseñarse, la pestaña de dentro que tenga algo por recoger (la de tiempo si las dos), con su entrada.
	local function onShown()
		animate()
		if body.Visible and window.Visible then
			local now, today, seconds = current()
			local playReady = false
			for position in Config.DailyRewards.Playtime do
				playReady = playReady or DailyInfo.playtimeReady(now, position, seconds)
			end
			refresh()
			show(if not playReady and DailyInfo.streakReady(now, today) then "Streak" else "Playtime")
		end
	end
	body:GetPropertyChangedSignal("Visible"):Connect(onShown)
	window:GetPropertyChangedSignal("Visible"):Connect(onShown)
	show("Playtime")
	refresh()

	-- Cada segundo: los relojes y, siempre, los avisos.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return DailyRewards
