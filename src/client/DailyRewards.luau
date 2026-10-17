-- Ventana de Recompensas diarias (Hud.DailyRewards; botón "Recompensas" del menú de la izquierda, Hud.HudRoot.Menu.DailyRewards).
-- Dos pestañas: "Tiempo jugado" (Body.Playtime: una tarjeta Reward_<n> por premio de Config.DailyRewards.Playtime, con su
-- barra y su botón Claim) y "Racha diaria" (Body.Streak: siete tarjetas Day_<n> y el botón Body.Streak.Claim). El
-- servidor cuenta el tiempo y lo publica en el atributo "Daily" (JSON, ver shared/DailyInfo) cada pocos segundos; aquí se
-- adelanta solo entre medias. Con algo por recoger, el botón del menú y la pestaña llevan un aviso rojo (Alert) con la cuenta.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local GRAY_TEXT = Color3.fromRGB(175, 178, 190)
local CARD_BASE = Color3.fromRGB(62, 68, 118)
-- Color de cada premio por tiempo, de menos a más.
local PLAYTIME_COLORS = {
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(70, 210, 150),
	Color3.fromRGB(150, 210, 70),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 190, 50),
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
local function rewardCell(parent: Instance, reward, size: number, order: number): TextButton
	local item = Config.Items[reward.item]
	local potion = item.potion
	local cell = Ui.cell(parent, item.color, if potion then potion.tier else nil)
	cell.Name = "Item_" .. reward.item
	cell.LayoutOrder = order
	cell.Size = UDim2.fromOffset(size, size)
	if potion then
		Potions.icon(cell, potion.family, potion.tier)
		Potions.addTag(cell, potion.tier)
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
	return cell
end

-- Fila de casillas centrada (horizontal o vertical).
local function rewardRow(parent: Instance, rewards, size: number, vertical: boolean): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rewards"
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local list = Instance.new("UIListLayout")
	list.FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = holder
	for order, reward in rewards do
		rewardCell(holder, reward, size, order)
	end
	return holder
end

-- Tarjeta con el estilo de las filas de Misiones: panel del color, borde negro (dorado si está lista) y capa oscura
-- encima cuando ya se ha recogido.
local function card(parent: Instance, name: string, color: Color3)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 12)
	local border = Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, CARD_BASE, color)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local done = Instance.new("Frame")
	done.Name = "Done"
	done.Size = UDim2.fromScale(1, 1)
	done.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
	done.BackgroundTransparency = 0.45
	done.ZIndex = 20
	done.Visible = false
	done.Parent = frame
	Ui.round(done, 12)
	local doneText = Ui.label(done, 22)
	doneText.Size = UDim2.fromScale(1, 1)
	doneText.ZIndex = 21
	doneText.TextColor3 = Ui.COLORS.green:Lerp(WHITE, 0.3)
	doneText.Rotation = -8
	doneText.Text = Lang.t(nil, "Claimed")
	return frame, border, scale, done
end

-- Pinta el estado de una tarjeta: "ready" (borde dorado que late), "done" (recogida) o "locked".
local function paint(entry, mode: string)
	if entry.mode == mode then
		return
	end
	entry.mode = mode
	entry.done.Visible = mode == "done"
	entry.border.Color = if mode == "ready" then GOLD else BLACK
	entry.border.Thickness = if mode == "ready" then 5 else 3
	if mode == "ready" and not Performance.get() then
		entry.scale.Scale = 1.08
		TweenService:Create(entry.scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Botón según el estado: verde para recoger, gris apagado si aún no, oscuro si ya está.
local function paintButton(button: TextButton, mode: string, text: string)
	button.Text = text -- Ui.button ya lo pasa a mayúsculas
	button.BackgroundColor3 = if mode == "ready" then Ui.COLORS.green elseif mode == "done" then Ui.COLORS.dark else Ui.COLORS.gray
	button.TextColor3 = if mode == "done" then Ui.COLORS.green:Lerp(WHITE, 0.3) elseif mode == "ready" then WHITE else GRAY_TEXT
	button.AutoButtonColor = mode == "ready"
	local glint = button:FindFirstChild("Glint")
	if glint then
		glint.Visible = mode == "ready" and not Performance.get()
	end
end

-- Franja de arriba de cada pestaña: texto a la izquierda y a la derecha.
local function strip(parent: Instance, color: Color3): (TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "Strip"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 2)
	frame.Size = UDim2.new(1, -24, 0, 40)
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 10)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, color:Lerp(BLACK, 0.15))
	local left = Ui.label(frame, 22)
	left.Name = "Left"
	left.Position = UDim2.fromOffset(14, 0)
	left.Size = UDim2.new(0.6, -14, 1, 0)
	left.TextXAlignment = Enum.TextXAlignment.Left
	local right = Ui.label(frame, 18)
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -14, 0, 0)
	right.Size = UDim2.new(0.4, -14, 1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
	return left, right
end

function DailyRewards.start()
	local window, body = Ui.window("DailyRewards", Lang.t(nil, "Daily rewards"), Vector2.new(720, 560), function(parent)
		Ui.image(parent, "codigos")
	end)

	-- Pestañas, como en Misiones.
	local panes, tabs, tabAlerts = {}, {}, {}
	local function show(name: string)
		for key, pane in panes do
			pane.Visible = key == name
			Ui.setSelected(tabs[key], key == name)
		end
	end
	for order, entry in { { "Playtime", "Playtime", Ui.COLORS.blue }, { "Streak", "Daily streak", Ui.COLORS.orange } } do
		local name = entry[1]
		local tab = Ui.button(body, Lang.t(nil, entry[2]), entry[3])
		tab.Name = "Tab" .. name
		tab.Position = UDim2.fromOffset(12 + (order - 1) * 196, 4)
		tab.Size = UDim2.fromOffset(186, 38)
		tab.TextSize = 20
		tabs[name] = tab
		tabAlerts[name] = { alertDot(tab, 24) }
		local pane = Instance.new("Frame")
		pane.Name = name
		pane.Position = UDim2.fromOffset(0, 50)
		pane.Size = UDim2.new(1, 0, 1, -50)
		pane.BackgroundTransparency = 1
		pane.Parent = body
		panes[name] = pane
		tab.Activated:Connect(function()
			show(name)
		end)
	end

	-- TIEMPO JUGADO: una tarjeta por premio, en fila.
	local playLeft, playRight = strip(panes.Playtime, Ui.COLORS.blue)
	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.Position = UDim2.fromOffset(12, 52)
	row.Size = UDim2.new(1, -24, 1, -60)
	row.BackgroundTransparency = 1
	row.Parent = panes.Playtime
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 8)
	rowList.Parent = row
	local count = #Config.DailyRewards.Playtime
	local playCards = {}
	for position, entry in Config.DailyRewards.Playtime do
		local color = PLAYTIME_COLORS[position] or GOLD
		local frame, border, scale, done = card(row, "Reward_" .. position, color)
		frame.LayoutOrder = position
		frame.Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0)

		local title = Ui.label(frame, 30)
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.new(0.5, 0, 0, 10)
		title.Size = UDim2.new(1, -10, 0, 36)
		title.Text = durationText(entry.minutes)
		Ui.gradient(title, WHITE, color:Lerp(WHITE, 0.3), 90)

		local rewards = rewardRow(frame, entry.rewards, 70, true)
		rewards.AnchorPoint = Vector2.new(0.5, 0.5)
		rewards.Position = UDim2.new(0.5, 0, 0.5, -10)
		rewards.Size = UDim2.new(1, -10, 0.5, 0)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0.5, 1)
		track.Position = UDim2.new(0.5, 0, 1, -64)
		track.Size = UDim2.new(1, -16, 0, 22)
		track.BackgroundColor3 = Ui.COLORS.dark
		track.Parent = frame
		Ui.round(track, 11)
		Ui.stroke(track, BLACK, 2)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = WHITE
		fill.BorderSizePixel = 0
		fill.Parent = track
		Ui.round(fill, 11)
		Ui.gradient(fill, color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.2), 90)
		local left = Ui.label(track, 15)
		left.Name = "Time"
		left.Size = UDim2.fromScale(1, 1)
		left.ZIndex = 3

		local claim = Ui.button(frame, Lang.t(nil, "Claim"), Ui.COLORS.green)
		claim.Name = "Claim"
		claim.AnchorPoint = Vector2.new(0.5, 1)
		claim.Position = UDim2.new(0.5, 0, 1, -10)
		claim.Size = UDim2.new(1, -16, 0, 44)
		claim.TextSize = 20
		Ui.sparkle(claim, 3)
		claim.Activated:Connect(function()
			local now, _, seconds = current()
			if DailyInfo.playtimeReady(now, position, seconds) then
				Remotes.ClaimDaily:FireServer("playtime", position)
			else
				Sfx.play("error")
			end
		end)
		playCards[position] = { border = border, scale = scale, done = done, fill = fill, time = left, claim = claim, mode = nil }
	end

	-- RACHA: días 1 a 4 arriba; 5, 6 y el 7 (doble de ancho) abajo.
	local streakLeft, streakRight = strip(panes.Streak, STREAK_COLOR)
	local days = Instance.new("Frame")
	days.Name = "Days"
	days.Position = UDim2.fromOffset(8, 48)
	days.Size = UDim2.new(1, -16, 1, -48 - 70)
	days.BackgroundTransparency = 1
	days.Parent = panes.Streak
	local streakCards = {}
	local total = #Config.DailyRewards.Streak
	for index, rewards in Config.DailyRewards.Streak do
		local column = (index - 1) % 4
		local line = (index - 1) // 4
		local wide = index == total and column < 3
		local color = if index == total then GOLD else STREAK_COLOR
		local frame, border, scale, done = card(days, "Day_" .. index, color)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		local width = if wide then 0.5 else 0.25
		frame.Position = UDim2.fromScale(column * 0.25 + width / 2, line * 0.5 + 0.25)
		frame.Size = UDim2.new(width, -8, 0.5, -8)

		local title = Ui.label(frame, 22)
		title.Name = "Title"
		title.Position = UDim2.fromOffset(10, 4)
		title.Size = UDim2.new(1, -20, 0, 30)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = Lang.t(nil, "Day {n}", { n = index })
		Ui.gradient(title, WHITE, color:Lerp(WHITE, 0.3), 90)

		local today = Ui.label(frame, 15)
		today.Name = "Today"
		today.AnchorPoint = Vector2.new(1, 0)
		today.Position = UDim2.new(1, -8, 0, 8)
		today.Size = UDim2.fromOffset(70, 22)
		today.BackgroundTransparency = 0
		today.BackgroundColor3 = GOLD:Lerp(BLACK, 0.1)
		today.Text = Lang.t(nil, "Today")
		today.Visible = false
		Ui.round(today, 8)
		Ui.stroke(today, BLACK, 2)

		local holder = rewardRow(frame, rewards, if index == total then 74 else 62, false)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -10)
		holder.Size = UDim2.new(1, -10, 1, -46)
		streakCards[index] = { border = border, scale = scale, done = done, today = today, mode = nil }
	end
	local streakClaim = Ui.button(panes.Streak, Lang.t(nil, "Claim"), Ui.COLORS.green)
	streakClaim.Name = "Claim"
	streakClaim.AnchorPoint = Vector2.new(0.5, 1)
	streakClaim.Position = UDim2.new(0.5, 0, 1, -10)
	streakClaim.Size = UDim2.fromOffset(320, 54)
	streakClaim.TextSize = 26
	Ui.sparkle(streakClaim, 3)
	streakClaim.Activated:Connect(function()
		local now, today = current()
		if DailyInfo.streakReady(now, today) then
			Remotes.ClaimDaily:FireServer("streak")
		else
			Sfx.play("error")
		end
	end)

	-- Aviso del botón del menú.
	local tile = Ui.hud():FindFirstChild("Menu") and Ui.hud().Menu:FindFirstChild("DailyRewards")
	local tileAlert = if tile then { alertDot(tile, 34) } else nil
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
		local nextAt = nil
		for position, entry in Config.DailyRewards.Playtime do
			local view = playCards[position]
			local goal = entry.minutes * 60
			local claimed = table.find(now.claimed, position) ~= nil
			local mode = if claimed then "done" elseif seconds >= goal then "ready" else "locked"
			if mode == "ready" then
				pendingPlay += 1
			elseif mode == "locked" and not nextAt then
				nextAt = goal
			end
			paint(view, mode)
			view.fill.Size = UDim2.fromScale(math.clamp(seconds / goal, 0, 1), 1)
			view.time.Text = if mode == "locked" then PotionInfo.clock(goal - seconds) else Lang.t(nil, "Ready!")
			paintButton(view.claim, mode, Lang.t(nil, if claimed then "Claimed" else "Claim"))
		end
		playLeft.Text = Lang.t(nil, "Played today: {time}", { time = PotionInfo.clock(seconds) })
		playRight.Text = Lang.t(nil, "Resets in {time}", { time = PotionInfo.clock(DailyInfo.secondsLeft()) })

		-- Racha: las de antes de la que toca, recogidas; la que toca, "Hoy" si aún no se ha recogido.
		local ready = DailyInfo.streakReady(now, today)
		local claimedUpTo = if ready then now.streak - 1 elseif now.streak == 1 then total else now.streak - 1
		local shown = if ready then now.streak else claimedUpTo
		for index, view in streakCards do
			local mode = if index <= claimedUpTo then "done" elseif ready and index == now.streak then "ready" else "locked"
			paint(view, mode)
			view.today.Visible = index == shown
		end
		streakLeft.Text = Lang.t(nil, "Day {n} of {total}", { n = shown, total = total })
		streakRight.Text = if ready then Lang.t(nil, "Ready!") else Lang.t(nil, "Next in {time}", { time = PotionInfo.clock(DailyInfo.secondsLeft()) })
		paintButton(streakClaim, if ready then "ready" else "locked", Lang.t(nil, if ready then "Claim" else "Come back tomorrow"))

		local pendingStreak = if ready then 1 else 0
		setAlert(tabAlerts.Playtime, pendingPlay)
		setAlert(tabAlerts.Streak, pendingStreak)
		setAlert(tileAlert, pendingPlay + pendingStreak)
		-- El aviso del menú late mientras hay algo por recoger.
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
		return nextAt
	end

	local lastClaimed = #state.claimed + state.streak
	player:GetAttributeChangedSignal("Daily"):Connect(function()
		readState()
		-- Algo recién recogido: sonido.
		local claimedNow = #state.claimed + state.streak
		if claimedNow ~= lastClaimed and window.Visible then
			Sfx.play("coin")
		end
		lastClaimed = claimedNow
		refresh()
	end)
	readState()
	lastClaimed = #state.claimed + state.streak

	-- Al abrir, la pestaña que tenga algo por recoger (la de tiempo si las dos).
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			local now, today, seconds = current()
			local playReady = false
			for position in Config.DailyRewards.Playtime do
				playReady = playReady or DailyInfo.playtimeReady(now, position, seconds)
			end
			show(if not playReady and DailyInfo.streakReady(now, today) then "Streak" else "Playtime")
			refresh()
		end
	end)
	show("Playtime")
	refresh()

	-- Cada segundo: los relojes con la ventana abierta y, siempre, el aviso del menú.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return DailyRewards
