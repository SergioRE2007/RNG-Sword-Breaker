-- Paneles "Jugadores" y "Servidor" del menú de admin (client/AdminPanel los monta en sus pestañas; librería sin
-- start()). Solo piden: las órdenes van por el remote AdminCommand y server/AdminCommands las comprueba una a una.
--   Jugadores (`Body.Players`): lista de los que hay en el servidor (`List.Player_<userId>`), cantidad (`Side.Amount`),
--     un botón por cosa que regalar (`Side.Gifts.Gift_<clave>`) y `Side.Actions.Goto` / `Bring` / `Kick`.
--   Servidor (`Body.Server`): datos del servidor (`Info`), aviso a todos (`Message` y `Send`) y regalo a todos los
--     que hay dentro (`Amount` y `Gifts.Gift_<clave>`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdminScope = require(script.Parent.AdminScope)
local Clover = require(script.Parent.Clover)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local AdminTools = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(40, 38, 80)
local PAD = 12
local GAP = 8
local ROW = 44 -- alto de botones y cajas
local GIFT = 62 -- alto de los botones de regalar (caben nombres de dos líneas)
local LIST_WIDTH = 190
local CONFIRM_TIME = 3 -- segundos que dura el "¿Seguro?" de echar

-- Lo que se puede regalar, en el orden de sus botones.
local GIFTS = { "coins", "gems", "missionToken", "traitCrystal", "gradeCrystal", "luckClover" }

local function giftLook(key: string): (string, Color3)
	if key == "coins" then
		return Lang.t(nil, "Coins"), Ui.COLORS.coins
	elseif key == "gems" then
		return Lang.t(nil, "Gems"), Ui.COLORS.purple
	end
	local item = Config.Items[key]
	return Lang.t(nil, item.name), item.color
end

local function heading(parent: Instance, name: string, text: string, y: number): TextLabel
	local label = Ui.label(parent, 18)
	label.Name = name
	label.Position = UDim2.fromOffset(4, y)
	label.Size = UDim2.new(1, -8, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	return label
end

local function field(parent: Instance, name: string, placeholder: string, y: number): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.Position = UDim2.fromOffset(0, y)
	box.Size = UDim2.new(1, 0, 0, ROW)
	box.TextSize = 22
	box.ClearTextOnFocus = false
	box.PlaceholderText = placeholder
	box.Text = ""
	box.Parent = parent
	Ui.field(box)
	return box
end

-- Rejilla de 3 x 2 con un botón por cosa que regalar. `send(clave, cantidad)` solo se llama con una cantidad válida.
local function gifts(parent: Instance, y: number, amount: TextBox, send: (string, number) -> ())
	local grid = Instance.new("Frame")
	grid.Name = "Gifts"
	grid.Position = UDim2.fromOffset(0, y)
	grid.Size = UDim2.new(1, 0, 0, GIFT * 2 + GAP)
	grid.BackgroundTransparency = 1
	grid.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3) - 1, 0, GIFT)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, key in GIFTS do
		local name, color = giftLook(key)
		local button = Ui.button(grid, name, color:Lerp(BLACK, 0.2))
		button.Name = "Gift_" .. key
		button.LayoutOrder = order
		button.TextScaled = true
		button.TextWrapped = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 18
		limit.MinTextSize = 12
		limit.Parent = button
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.Parent = button
		button.Activated:Connect(function()
			local count = Format.parse(amount.Text)
			if not count or count < 1 then
				Sfx.play("error")
				Ui.toast(Lang.t(nil, "Type an amount first (for example 100 or 1.5K)"), Ui.COLORS.orange)
				return
			end
			send(key, math.floor(count))
		end)
	end
	return grid
end

-- Panel con fondo y borde, como los del panel del clima.
local function card(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, PANEL)
	-- Ui.panel mete sus piezas como hijos: el contenido va en un marco de dentro.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(10, 8)
	content.Size = UDim2.new(1, -20, 1, -16)
	content.BackgroundTransparency = 1
	content.Parent = frame
	return content
end

function AdminTools.players(pane: Frame)
	local selected: Player = player

	local listCard = card(pane, "ListCard", UDim2.fromOffset(PAD, PAD), UDim2.new(0, LIST_WIDTH, 1, -PAD * 2))
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = listCard
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 3)
	listPad.PaddingLeft = UDim.new(0, 3)
	listPad.PaddingRight = UDim.new(0, 10)
	listPad.PaddingBottom = UDim.new(0, 6)
	listPad.Parent = list

	local side = card(pane, "Side", UDim2.fromOffset(PAD + LIST_WIDTH + GAP, PAD), UDim2.new(1, -(PAD * 2 + LIST_WIDTH + GAP), 1, -PAD * 2))
	side.Parent.Name = "SideCard"
	side.Name = "Side"
	local title = heading(side, "Title", "", 0)
	title.TextSize = 20
	local amount = field(side, "Amount", Lang.t(nil, "Amount"), 30)
	amount.Text = "100"
	gifts(side, 30 + ROW + GAP, amount, function(key: string, count: number)
		Remotes.AdminCommand:FireServer("give", selected.UserId, key, count)
	end)

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.AnchorPoint = Vector2.new(0, 1)
	actions.Position = UDim2.fromScale(0, 1)
	actions.Size = UDim2.new(1, 0, 0, ROW)
	actions.BackgroundTransparency = 1
	actions.Parent = side
	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3) - 1, 1, 0)
	actionLayout.CellPadding = UDim2.fromOffset(GAP, 0)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actions
	local function action(name: string, text: string, color: Color3, order: number): TextButton
		local button = Ui.button(actions, text, color)
		button.Name = name
		button.LayoutOrder = order
		button.TextSize = 18
		return button
	end
	local goTo = action("Goto", Lang.t(nil, "Go to"), Ui.COLORS.blue, 1)
	local bring = action("Bring", Lang.t(nil, "Bring"), Ui.COLORS.green, 2)
	local kick = action("Kick", Lang.t(nil, "Kick"), Ui.COLORS.red, 3)
	goTo.Activated:Connect(function()
		Remotes.AdminCommand:FireServer("goto", selected.UserId)
	end)
	bring.Activated:Connect(function()
		Remotes.AdminCommand:FireServer("bring", selected.UserId)
	end)
	-- Echar pide un segundo toque.
	local asked = 0
	local function paintKick()
		kick.Text = Lang.t(nil, if os.clock() - asked <= CONFIRM_TIME then "Sure?" else "Kick") -- Ui.button lo pasa a mayúsculas
	end
	kick.Activated:Connect(function()
		if selected == player then
			return
		end
		if os.clock() - asked <= CONFIRM_TIME then
			asked = 0
			Remotes.AdminCommand:FireServer("kick", selected.UserId)
		else
			asked = os.clock()
			task.delay(CONFIRM_TIME + 0.1, paintKick)
		end
		paintKick()
	end)

	local buttons: { [Player]: TextButton } = {}
	local function paint()
		if not selected.Parent then
			selected = player
		end
		for other, button in buttons do
			Ui.setSelected(button, other == selected)
		end
		title.Text = Lang.t(nil, "Give to {name}", { name = selected.DisplayName })
		-- Sobre uno mismo no hay adónde ir ni a quién echar.
		local own = selected == player
		for _, button in { goTo, bring, kick } do
			button.BackgroundColor3 = if own then Ui.COLORS.gray elseif button == goTo then Ui.COLORS.blue elseif button == bring then Ui.COLORS.green else Ui.COLORS.red
		end
		asked = 0
		paintKick()
	end
	local function add(other: Player)
		if buttons[other] then
			return
		end
		local button = Ui.button(list, other.DisplayName, if other == player then Ui.COLORS.orange else Ui.COLORS.gray)
		button.Name = "Player_" .. other.UserId
		button.LayoutOrder = if other == player then 0 else 1
		button.Size = UDim2.new(1, 0, 0, 38)
		button.TextSize = 16
		button.TextTruncate = Enum.TextTruncate.AtEnd
		buttons[other] = button
		button.Activated:Connect(function()
			selected = other
			paint()
		end)
	end
	Players.PlayerAdded:Connect(function(other)
		add(other)
		paint()
	end)
	Players.PlayerRemoving:Connect(function(other)
		local button = buttons[other]
		if button then
			buttons[other] = nil
			button:Destroy()
		end
		paint()
	end)
	for _, other in Players:GetPlayers() do
		add(other)
	end
	paint()
end

function AdminTools.server(pane: Frame, window: Frame)
	local content = card(pane, "Card", UDim2.fromOffset(PAD, PAD), UDim2.new(1, -PAD * 2, 1, -PAD * 2))
	content.Parent.Name = "Card"
	local info = heading(content, "Info", "", 0)

	-- Aviso a todo el servidor.
	local messageTitle = heading(content, "MessageTitle", "", 30)
	local row = Instance.new("Frame")
	row.Name = "MessageRow"
	row.Position = UDim2.fromOffset(0, 58)
	row.Size = UDim2.new(1, 0, 0, ROW)
	row.BackgroundTransparency = 1
	row.Parent = content
	local message = field(row, "Message", Lang.t(nil, "Write a message for everyone"), 0)
	message.Size = UDim2.new(1, -(120 + GAP), 1, 0)
	message.TextSize = 18
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.ClipsDescendants = true
	local messagePad = Instance.new("UIPadding")
	messagePad.PaddingLeft = UDim.new(0, 10)
	messagePad.PaddingRight = UDim.new(0, 10)
	messagePad.Parent = message
	local send = Ui.button(row, Lang.t(nil, "Send"), Ui.COLORS.green)
	send.Name = "Send"
	send.AnchorPoint = Vector2.new(1, 0)
	send.Position = UDim2.fromScale(1, 0)
	send.Size = UDim2.new(0, 120, 1, 0)
	send.TextSize = 18
	send.Activated:Connect(function()
		if string.match(message.Text, "^%s*$") then
			Sfx.play("error")
			return
		end
		AdminScope.command("announce", message.Text)
		message.Text = ""
	end)

	-- Regalo a todos los que están dentro.
	local top = 58 + ROW + 14
	local giftTitle = heading(content, "GiftTitle", "", top)
	-- Avisos y regalos van a este servidor o a todos, según el botón de la ventana (client/AdminScope).
	local function paintScope()
		messageTitle.Text = Lang.t(nil, if AdminScope.all then "Announcement to all servers" else "Announcement to this server")
		giftTitle.Text = Lang.t(nil, if AdminScope.all then "Give to everyone on all servers" else "Give to everyone on this server")
	end
	AdminScope.Changed:Connect(paintScope)
	paintScope()
	local amount = field(content, "Amount", Lang.t(nil, "Amount"), top + 28)
	amount.Text = "10"
	gifts(content, top + 28 + ROW + GAP, amount, function(key: string, count: number)
		AdminScope.command("give", 0, key, count)
	end)

	-- Trébol de prueba (pedido por el usuario, para probar las cinemáticas de tirada): suerte a medida, sin gastar
	-- tréboles y solo para quien lo pide. "Usar" lo pone, cierra el menú y deja elegir el objeto; mientras está puesto,
	-- los tréboles de la mochila también dan esa suerte. "Quitar" vuelve al trébol normal.
	local cloverTop = top + 28 + ROW + GAP + GIFT * 2 + GAP + 10
	local cloverTitle = heading(content, "CloverTitle", "", cloverTop)
	local cloverRow = Instance.new("Frame")
	cloverRow.Name = "CloverRow"
	cloverRow.Position = UDim2.fromOffset(0, cloverTop + 28)
	cloverRow.Size = UDim2.new(1, 0, 0, ROW)
	cloverRow.BackgroundTransparency = 1
	cloverRow.Parent = content
	local luck = field(cloverRow, "Luck", Lang.t(nil, "Luck (for example 10K)"), 0)
	luck.Size = UDim2.new(1, -(120 + GAP) * 2, 1, 0)
	luck.Text = "10K"
	local use = Ui.button(cloverRow, Lang.t(nil, "Use"), Ui.COLORS.green)
	use.Name = "Use"
	use.AnchorPoint = Vector2.new(1, 0)
	use.Position = UDim2.new(1, -(120 + GAP), 0, 0)
	use.Size = UDim2.new(0, 120, 1, 0)
	use.TextSize = 18
	local off = Ui.button(cloverRow, Lang.t(nil, "Remove"), Ui.COLORS.red)
	off.Name = "Off"
	off.AnchorPoint = Vector2.new(1, 0)
	off.Position = UDim2.fromScale(1, 0)
	off.Size = UDim2.new(0, 120, 1, 0)
	off.TextSize = 18
	local function paintClover()
		local now = player:GetAttribute("CloverTest")
		cloverTitle.Text = if type(now) == "number" then Lang.t(nil, "Test clover: x{n} on", { n = Format.short(now) }) else Lang.t(nil, "Test clover: custom luck, costs nothing")
	end
	player:GetAttributeChangedSignal("CloverTest"):Connect(paintClover)
	paintClover()
	use.Activated:Connect(function()
		local value = Format.parse(luck.Text)
		if not value or value < 1 then
			Sfx.play("error")
			Ui.toast(Lang.t(nil, "Type the luck first (for example 10K)"), Ui.COLORS.orange)
			return
		end
		Remotes.AdminCommand:FireServer("clover", value)
		Ui.close(window)
		Clover.pick(true)
	end)
	off.Activated:Connect(function()
		Remotes.AdminCommand:FireServer("clover", 0)
	end)

	-- Cuánta gente hay y cuánto lleva abierto: se repinta con el panel a la vista.
	local function refresh()
		local minutes = math.floor(workspace.DistributedGameTime / 60)
		info.Text = Lang.t(nil, "Players here: {n} · open for {h} h {m} min", { n = #Players:GetPlayers(), h = minutes // 60, m = minutes % 60 })
	end
	refresh()
	task.spawn(function()
		while true do
			task.wait(5)
			if window.Visible and pane.Visible then
				refresh()
			end
		end
	end)
	pane:GetPropertyChangedSignal("Visible"):Connect(refresh)
end

return AdminTools
