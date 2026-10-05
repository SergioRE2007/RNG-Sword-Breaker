-- Comercio entre jugadores en el cliente: lista de jugadores para invitar (botón "Comercio" del menú), aviso
-- de invitación y la ventana del trato. Todo lo decide el servidor (server/Trade): aquí se pide (TradeRequest,
-- TradeRespond, TradeOffer, TradeAccept, TradeConfirm, TradeCancel) y se pinta el estado que llega por TradeState.
-- Pasos del trato: elegir y Aceptar los dos -> Confirmar los dos -> cuenta atrás en la que aún se puede cancelar.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ArmorPane = require(script.Parent.ArmorPane)
local Backpack = require(script.Parent.Backpack)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local Trade = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local TEAL = Color3.fromRGB(40, 190, 200)
local SOFT = Color3.fromRGB(190, 195, 215)

-- Capas (la interfaz ordena el ZIndex globalmente; valores absolutos de este módulo).
local Z_COUNT = 30 -- cuenta atrás, por encima de la ventana del trato
local Z_INVITE = 70 -- aviso de invitación, por encima de todo lo demás

local OFFER_CELL = 66
local STOCK_CELL = 74

local STEPS = {
	editing = "1 de 3 · Elegid qué dais y pulsad Aceptar",
	confirming = "2 de 3 · Revisad bien las dos ofertas y pulsad CONFIRMAR",
	countdown = "3 de 3 · Se va a completar: aún se puede cancelar",
}

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Lista con rejilla y barra de desplazamiento vertical.
local function scrollGrid(parent: Instance, cell: number): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell, cell)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll
	return scroll
end

local function clear(scroll: Instance)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

-- Casillas de cada tipo de cosa (las mismas en las ofertas y en tu inventario).
local function swordCell(parent: Instance, copy): TextButton
	local color = Rarity.tier(Stats.rarity(copy)).color
	local cell = Ui.cell(parent, color)
	WeaponPreview.attach(cell, copy.sword, color, copy.metal)
	Ui.tip(cell, function()
		return Backpack.swordTip(copy)
	end, true)
	return cell
end

local function armorCell(parent: Instance, piece): TextButton
	local cell = Ui.cell(parent, ArmorStats.quality(piece).color)
	ArmorPane.preview(cell, piece)
	Ui.tip(cell, function()
		return ArmorPane.tip(piece)
	end, true)
	return cell
end

local function artifactCell(parent: Instance, index: number): TextButton
	local artifact = Config.Artifacts[index]
	local color = Rarity.tier(artifact.rarity).color
	local cell = Ui.cell(parent, color)
	Ui.orbIcon(cell, artifact.color)
	Ui.tip(cell, function()
		return `{artifact.name}\n<font color="{Ui.SOFT}">Accesorio · {Config.StatNames[artifact.stat]} x{Format.multiplier(artifact.mult)}</font>`, color
	end, true)
	return cell
end

-- Monedas, gemas u objetos: icono y cantidad.
local function amountCell(parent: Instance, name: string, color: Color3, amount: number, coin: boolean?): TextButton
	local cell = Ui.cell(parent, color)
	if coin then
		Ui.orbIcon(cell, color)
	else
		Ui.gemIcon(cell, color)
	end
	Ui.cellLabel(cell, Format.short(amount))
	Ui.tip(cell, function()
		return `{Format.short(amount)} {name}`, color
	end, true)
	return cell
end

-- Lista de jugadores ----------------------------------------------------------------------

local function buildList()
	local window, body = Ui.window("TradeList", "Comercio", Vector2.new(560, 470), function(parent)
		Ui.orbIcon(parent, TEAL)
	end)
	local note = Ui.label(body, 17)
	note.Position = UDim2.fromOffset(16, 6)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = SOFT
	note.Text = "Invita a un jugador de este servidor a comerciar."

	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.Position = UDim2.fromOffset(10, 38)
	list.Size = UDim2.new(1, -20, 1, -48)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local empty = Ui.label(body, 20)
	empty.Position = UDim2.fromScale(0, 0.4)
	empty.Size = UDim2.new(1, 0, 0, 30)
	empty.TextColor3 = SOFT
	empty.Text = "No hay nadie más en el servidor."

	local function row(order: number, name: string, userId: number, color: Color3)
		local frame = Instance.new("Frame")
		frame.Name = "Player" .. userId
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, 64)
		frame.BackgroundColor3 = WHITE
		frame.BorderSizePixel = 0
		frame.Parent = list
		Ui.round(frame, 10)
		Ui.stroke(frame, BLACK, 3)
		Ui.panel(frame, Color3.fromRGB(58, 62, 108), color)
		local label = Ui.label(frame, 24)
		label.Position = UDim2.fromOffset(22, 0)
		label.Size = UDim2.new(1, -190, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = name
		local invite = Ui.button(frame, "Invitar", Ui.COLORS.green)
		invite.Name = "Invite"
		invite.AnchorPoint = Vector2.new(1, 0.5)
		invite.Position = UDim2.new(1, -10, 0.5, 0)
		invite.Size = UDim2.fromOffset(140, 46)
		invite.TextSize = 22
		invite.Activated:Connect(function()
			Remotes.TradeRequest:FireServer(userId)
			window.Visible = false
		end)
	end

	local function rebuild()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local total = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				total += 1
				row(total, other.DisplayName, other.UserId, TEAL)
			end
		end
		if player:GetAttribute("TradeBot") == true then
			total += 1
			row(total, "Bot de pruebas", 0, GOLD)
		end
		empty.Visible = total == 0
	end
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuild)
	end)
	player:GetAttributeChangedSignal("TradeBot"):Connect(rebuild)
end

-- Aviso de invitación ---------------------------------------------------------------------

local function buildInvite()
	local card = Instance.new("Frame")
	card.Name = "TradeInvite"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 150)
	card.Size = UDim2.fromOffset(440, 120)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = Z_INVITE
	card.Parent = Ui.screen()
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.gradient(card, Color3.fromRGB(60, 80, 130), Color3.fromRGB(24, 28, 54), 90)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local text = Ui.label(card, 22)
	text.Position = UDim2.fromOffset(12, 8)
	text.Size = UDim2.new(1, -24, 0, 44)
	text.TextWrapped = true
	local accept = Ui.button(card, "Aceptar", Ui.COLORS.green)
	accept.Name = "Accept"
	accept.AnchorPoint = Vector2.new(1, 1)
	accept.Position = UDim2.new(0.5, -6, 1, -12)
	accept.Size = UDim2.fromOffset(170, 48)
	accept.TextSize = 22
	local decline = Ui.button(card, "Rechazar", Ui.COLORS.red)
	decline.Name = "Decline"
	decline.AnchorPoint = Vector2.new(0, 1)
	decline.Position = UDim2.new(0.5, 6, 1, -12)
	decline.Size = UDim2.fromOffset(170, 48)
	decline.TextSize = 22
	Ui.layer(card, Z_INVITE)

	local from: number? = nil
	local token = 0
	local function answer(yes: boolean)
		if from then
			Remotes.TradeRespond:FireServer(from, yes)
		end
		from = nil
		card.Visible = false
	end
	accept.Activated:Connect(function()
		answer(true)
	end)
	decline.Activated:Connect(function()
		answer(false)
	end)
	Remotes.TradeInvite.OnClientEvent:Connect(function(userId: number, name: string)
		from = userId
		text.Text = `<font color="{hex(GOLD)}">{name}</font> quiere comerciar contigo`
		card.Visible = true
		Sfx.play("toast")
		if not Performance.get() then
			scale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		token += 1
		local current = token
		task.delay(Config.Trade.InviteTime, function()
			if current == token and card.Visible then
				card.Visible = false
				from = nil
			end
		end)
	end)
end

-- Ventana del trato -----------------------------------------------------------------------

local function buildTrade()
	local window, body = Ui.window("Trade", "Trato", Vector2.new(1000, 620), function(parent)
		Ui.orbIcon(parent, TEAL)
	end)
	local current = nil -- último estado que mandó el servidor, o nil si no hay trato

	-- Las dos ofertas, una al lado de la otra.
	local function offerPanel(name: string, left: boolean)
		local panel = Instance.new("Frame")
		panel.Name = name
		panel.AnchorPoint = Vector2.new(if left then 0 else 1, 0)
		panel.Position = UDim2.new(if left then 0 else 1, if left then 10 else -10, 0, 8)
		panel.Size = UDim2.new(0.5, -15, 0, 214)
		panel.BackgroundColor3 = WHITE
		panel.BorderSizePixel = 0
		panel.Parent = body
		Ui.round(panel, 12)
		local stroke = Ui.stroke(panel, BLACK, 3)
		Ui.panel(panel, Color3.fromRGB(46, 50, 92))
		local title = Ui.label(panel, 22)
		title.Position = UDim2.fromOffset(14, 4)
		title.Size = UDim2.new(1, -190, 0, 30)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local badge = Ui.label(panel, 16)
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -10, 0, 6)
		badge.Size = UDim2.fromOffset(160, 26)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Ui.COLORS.dark
		Ui.round(badge, 8)
		Ui.stroke(badge, BLACK, 2)
		local grid = scrollGrid(panel, OFFER_CELL)
		grid.Name = "Grid"
		grid.Position = UDim2.fromOffset(6, 36)
		grid.Size = UDim2.new(1, -12, 1, -42)
		local empty = Ui.label(panel, 18)
		empty.Position = UDim2.fromScale(0, 0.5)
		empty.Size = UDim2.new(1, 0, 0, 24)
		empty.TextColor3 = SOFT
		empty.Text = "Nada todavía"
		return { panel = panel, stroke = stroke, title = title, badge = badge, grid = grid, empty = empty, shown = nil }
	end
	local mine = offerPanel("Mine", true)
	local theirs = offerPanel("Theirs", false)

	-- Tu inventario: pestañas y casillas para añadir o quitar de tu oferta.
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Position = UDim2.fromOffset(10, 230)
	tabsRow.Size = UDim2.new(1, -20, 0, 38)
	tabsRow.BackgroundTransparency = 1
	tabsRow.Parent = body
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabsLayout.Parent = tabsRow
	local hint = Ui.label(tabsRow, 16)
	hint.LayoutOrder = 99
	hint.Size = UDim2.fromOffset(300, 38)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = SOFT
	hint.Text = "Pulsa algo tuyo para añadirlo o quitarlo."

	local stockArea = Instance.new("Frame")
	stockArea.Name = "Stock"
	stockArea.Position = UDim2.fromOffset(10, 274)
	stockArea.Size = UDim2.new(1, -20, 1, -274 - 80)
	stockArea.BackgroundColor3 = WHITE
	stockArea.BorderSizePixel = 0
	stockArea.Parent = body
	Ui.round(stockArea, 12)
	Ui.stroke(stockArea, BLACK, 3)
	Ui.gradient(stockArea, Color3.fromRGB(40, 42, 74), Color3.fromRGB(20, 21, 40), 90)
	local stock = scrollGrid(stockArea, STOCK_CELL)
	stock.Name = "Grid"
	stock.Size = UDim2.fromScale(1, 1)

	-- Cantidades (monedas, gemas y objetos): una fila por cosa con su casilla para escribir.
	local amounts = Instance.new("ScrollingFrame")
	amounts.Name = "Amounts"
	amounts.Size = UDim2.fromScale(1, 1)
	amounts.BackgroundTransparency = 1
	amounts.BorderSizePixel = 0
	amounts.ScrollBarThickness = 8
	amounts.CanvasSize = UDim2.new()
	amounts.AutomaticCanvasSize = Enum.AutomaticSize.Y
	amounts.Visible = false
	amounts.Parent = stockArea
	local amountsLayout = Instance.new("UIGridLayout")
	amountsLayout.CellSize = UDim2.new(0.5, -14, 0, 46)
	amountsLayout.CellPadding = UDim2.fromOffset(10, 8)
	amountsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	amountsLayout.Parent = amounts
	local amountsPadding = Instance.new("UIPadding")
	amountsPadding.PaddingTop = UDim.new(0, 10)
	amountsPadding.PaddingLeft = UDim.new(0, 10)
	amountsPadding.Parent = amounts

	local amountRows = {} -- { box, label, owned(), offered(), name }
	local function amountRow(order: number, name: string, color: Color3, owned: () -> number, offered: () -> number, send: (number) -> ())
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.BackgroundColor3 = WHITE
		row.BorderSizePixel = 0
		row.Parent = amounts
		Ui.round(row, 8)
		Ui.stroke(row, BLACK, 2)
		Ui.panel(row, Color3.fromRGB(52, 56, 100), color)
		local label = Ui.label(row, 17)
		label.Position = UDim2.fromOffset(18, 0)
		label.Size = UDim2.new(1, -170, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		local box = Instance.new("TextBox")
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(1, 0.5)
		box.Position = UDim2.new(1, -8, 0.5, 0)
		box.Size = UDim2.fromOffset(140, 32)
		box.BackgroundColor3 = Ui.COLORS.dark
		box.TextColor3 = WHITE
		box.PlaceholderText = "0"
		box.PlaceholderColor3 = Color3.fromRGB(120, 124, 140)
		box.Font = Ui.FONT
		box.TextSize = 19
		box.ClearTextOnFocus = false
		box.Text = ""
		box.Parent = row
		Ui.round(box, 8)
		Ui.stroke(box, BLACK, 2)
		box.FocusLost:Connect(function()
			-- Admite 1000, 1.5K, 2M...; se queda en lo que tengas como mucho.
			local value = Format.parse(box.Text) or 0
			local have = owned()
			if have ~= math.huge then
				value = math.min(value, have)
			end
			send(math.max(0, math.floor(value)))
		end)
		table.insert(amountRows, { box = box, label = label, owned = owned, offered = offered, name = name, color = color })
	end
	amountRow(1, "Monedas", Ui.COLORS.coins, function()
		return player:GetAttribute("Coins") or 0
	end, function()
		return if current then current.you.coins else 0
	end, function(value)
		Remotes.TradeOffer:FireServer("coins", nil, value)
	end)
	amountRow(2, "Gemas", Ui.COLORS.purple, function()
		return player:GetAttribute("Gems") or 0
	end, function()
		return if current then current.you.gems else 0
	end, function(value)
		Remotes.TradeOffer:FireServer("gems", nil, value)
	end)
	for order, key in Config.ItemOrder do
		local item = Config.Items[key]
		amountRow(2 + order, item.name, item.color, function()
			return player:GetAttribute("Item_" .. key) or 0
		end, function()
			return if current then current.you.items[key] or 0 else 0
		end, function(value)
			Remotes.TradeOffer:FireServer("items", key, value)
		end)
	end

	-- Pestañas.
	local tab = "swords"
	local tabButtons = {}
	local stockCells = {} -- [id o índice] = casilla de la pestaña que se ve
	local stockKey: string? = nil
	local TABS = { { "swords", "Espadas", Ui.COLORS.red }, { "armor", "Armadura", Ui.COLORS.orange }, { "artifacts", "Accesorios", Ui.COLORS.purple }, { "amounts", "Monedas y objetos", Ui.COLORS.blue } }

	local function locked(): boolean
		return current == nil or current.state ~= "editing"
	end

	-- Marca en tu inventario lo que ya está en tu oferta.
	local function paintStock()
		if not current then
			return
		end
		local offered = {}
		for _, entry in (current.you :: any)[tab] or {} do
			offered[if type(entry) == "table" then entry.id else entry] = true
		end
		for key, cell in stockCells do
			(cell :: any).Select.Visible = offered[key] == true
		end
		for _, row in amountRows do
			row.label.Text = `{row.name} <font color="{Ui.SOFT}">(tienes {Format.short(row.owned())})</font>`
			if not row.box:IsFocused() then
				local value = row.offered()
				row.box.Text = if value > 0 then Format.short(value) else ""
			end
		end
	end

	local function buildStock(force: boolean?)
		local key = `{tab}|{player:GetAttribute("Swords")}|{player:GetAttribute("Equipped")}|{player:GetAttribute("Armor")}|{player:GetAttribute("Artifacts")}`
		if key == stockKey and not force then
			paintStock()
			return
		end
		stockKey = key
		clear(stock)
		table.clear(stockCells)
		stock.Visible = tab ~= "amounts"
		amounts.Visible = tab == "amounts"
		local function add(cell: TextButton, id: number, order: number)
			cell.LayoutOrder = order
			stockCells[id] = cell
			cell.Activated:Connect(function()
				if locked() then
					Sfx.play("error")
					return
				end
				Remotes.TradeOffer:FireServer(tab, id, if (cell :: any).Select.Visible then 0 else 1)
			end)
		end
		if tab == "swords" then
			local equipped = player:GetAttribute("Equipped")
			for _, copy in Stats.swords(player) do
				-- La equipada no se puede dar.
				if copy.id ~= equipped then
					add(swordCell(stock, copy), copy.id, -math.floor(math.log10(Stats.rarity(copy)) * 1000))
				end
			end
		elseif tab == "armor" then
			for _, piece in ArmorStats.pieces(player) do
				add(armorCell(stock, piece), piece.id, -(piece.level * 100 + piece.quality))
			end
		elseif tab == "artifacts" then
			for _, index in Stats.list(player, "Artifacts") do
				add(artifactCell(stock, index), index, -index)
			end
		end
		paintStock()
	end

	for order, entry in TABS do
		local button = Ui.button(tabsRow, entry[2], entry[3])
		button.Name = "Tab_" .. entry[1]
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(if entry[1] == "amounts" then 200 else 140, 36)
		button.TextSize = 19
		tabButtons[entry[1]] = button
		button.Activated:Connect(function()
			tab = entry[1]
			for name, other in tabButtons do
				local stroke = other:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = if name == tab then WHITE else BLACK
				end
			end
			buildStock()
		end)
	end

	-- Barra de abajo: en qué paso se está y los botones.
	local status = Ui.label(body, 20)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 16, 1, -14)
	status.Size = UDim2.new(1, -470, 0, 56)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextWrapped = true
	local mainButton = Ui.button(body, "Aceptar", Ui.COLORS.green)
	mainButton.Name = "Main"
	mainButton.AnchorPoint = Vector2.new(1, 1)
	mainButton.Position = UDim2.new(1, -12, 1, -12)
	mainButton.Size = UDim2.fromOffset(230, 60)
	mainButton.TextSize = 26
	local backButton = Ui.button(body, "Volver", Ui.COLORS.orange)
	backButton.Name = "Back"
	backButton.AnchorPoint = Vector2.new(1, 1)
	backButton.Position = UDim2.new(1, -252, 1, -12)
	backButton.Size = UDim2.fromOffset(110, 60)
	backButton.TextSize = 20
	local cancelButton = Ui.button(body, "Cancelar", Ui.COLORS.red)
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Position = UDim2.new(1, -372, 1, -12)
	cancelButton.Size = UDim2.fromOffset(110, 60)
	cancelButton.TextSize = 20

	-- Cuenta atrás, grande y en el centro.
	local countdown = Ui.label(window, 120)
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.45)
	countdown.Size = UDim2.fromOffset(260, 160)
	countdown.TextColor3 = GOLD
	countdown.Visible = false
	countdown.ZIndex = Z_COUNT
	local countScale = Instance.new("UIScale")
	countScale.Parent = countdown

	mainButton.Activated:Connect(function()
		if not current then
			return
		end
		if current.state == "editing" then
			Remotes.TradeAccept:FireServer(not current.you.accepted)
		elseif current.state == "confirming" and not current.you.confirmed then
			Remotes.TradeConfirm:FireServer()
		end
	end)
	backButton.Activated:Connect(function()
		Remotes.TradeAccept:FireServer(false)
	end)
	cancelButton.Activated:Connect(function()
		Remotes.TradeCancel:FireServer()
	end)

	-- Pinta la oferta de un lado (solo rehace las casillas si ha cambiado).
	local function paintOffer(panel, side, title: string)
		panel.title.Text = title
		local confirming = current.state ~= "editing"
		local done = if confirming then side.confirmed else side.accepted
		panel.badge.Text = if not done then (if confirming then "Sin confirmar" else "Eligiendo...") elseif confirming then "CONFIRMADO" else "ACEPTADO"
		panel.badge.TextColor3 = if done then Ui.COLORS.green:Lerp(WHITE, 0.3) else SOFT
		panel.stroke.Color = if done then Ui.COLORS.green else BLACK
		local key = HttpService:JSONEncode({ side.coins == math.huge and "inf" or side.coins, side.gems == math.huge and "inf" or side.gems, side.items, side.swords, side.armor, side.artifacts })
		if panel.shown == key then
			return
		end
		panel.shown = key
		clear(panel.grid)
		local order = 0
		local function place(cell: TextButton)
			order += 1
			cell.LayoutOrder = order
		end
		if side.coins > 0 then
			place(amountCell(panel.grid, "monedas", Ui.COLORS.coins, side.coins, true))
		end
		if side.gems > 0 then
			place(amountCell(panel.grid, "gemas", Ui.COLORS.purple, side.gems))
		end
		for _, name in Config.ItemOrder do
			local amount = side.items[name]
			if amount and amount > 0 then
				place(amountCell(panel.grid, Config.Items[name].name, Config.Items[name].color, amount))
			end
		end
		for _, copy in side.swords do
			place(swordCell(panel.grid, copy))
		end
		for _, piece in side.armor do
			place(armorCell(panel.grid, piece))
		end
		for _, index in side.artifacts do
			place(artifactCell(panel.grid, index))
		end
		panel.empty.Visible = order == 0
	end

	local lastState: string? = nil
	local function render()
		if not current then
			return
		end
		paintOffer(mine, current.you, "Tu oferta")
		paintOffer(theirs, current.them, `Oferta de {current.them.name}`)
		buildStock()
		local state = current.state
		status.Text = STEPS[state] or ""
		status.TextColor3 = if state == "editing" then WHITE else GOLD
		hint.Text = if state == "editing" then "Pulsa algo tuyo para añadirlo o quitarlo." else "Ofertas bloqueadas."
		backButton.Visible = state == "confirming"
		mainButton.Visible = state ~= "countdown"
		cancelButton.Text = if state == "countdown" then "¡CANCELAR!" else "Cancelar"
		cancelButton.TextSize = if state == "countdown" then 28 else 20
		cancelButton.Size = UDim2.fromOffset(if state == "countdown" then 300 else 110, 60)
		cancelButton.Position = UDim2.new(1, if state == "countdown" then -12 else (if state == "confirming" then -372 else -252), 1, -12)
		if state == "editing" then
			mainButton.Text = if current.you.accepted then "Quitar aceptar" else "Aceptar"
			mainButton.BackgroundColor3 = if current.you.accepted then Ui.COLORS.orange else Ui.COLORS.green
		elseif state == "confirming" then
			mainButton.Text = if current.you.confirmed then "Esperando..." else "CONFIRMAR"
			mainButton.BackgroundColor3 = if current.you.confirmed then Ui.COLORS.gray else Ui.COLORS.green
		end
		countdown.Visible = state == "countdown"
		if state ~= lastState then
			lastState = state
			if state == "confirming" then
				Sfx.play("rare")
				Ui.toast("Revisa bien la oferta antes de confirmar", GOLD)
			elseif state == "countdown" then
				Sfx.play("roll")
			end
		end
	end

	Remotes.TradeState.OnClientEvent:Connect(function(state)
		if state == nil then
			current = nil
			lastState = nil
			countdown.Visible = false
			window.Visible = false
			return
		end
		local opening = current == nil
		current = state
		if opening then
			mine.shown, theirs.shown, stockKey = nil, nil, nil
			if not window.Visible then
				Ui.toggle("Trade")
			end
			Sfx.play("open")
		end
		render()
	end)
	-- Cerrar la ventana (la X, o abrir otra) cancela el trato.
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible and current then
			Remotes.TradeCancel:FireServer()
		end
	end)
	player.AttributeChanged:Connect(function(attribute)
		if current and window.Visible and (attribute == "Swords" or attribute == "Armor" or attribute == "Artifacts" or attribute == "Equipped" or attribute == "Coins" or attribute == "Gems" or string.sub(attribute, 1, 5) == "Item_") then
			buildStock()
		end
	end)
	-- La cuenta atrás late cada segundo.
	task.spawn(function()
		local shown = -1
		while true do
			task.wait(0.1)
			if current and current.state == "countdown" then
				local left = math.max(0, math.ceil(current.ends - workspace:GetServerTimeNow()))
				countdown.Text = tostring(left)
				if left ~= shown then
					shown = left
					Sfx.play("tick")
					if not Performance.get() then
						countScale.Scale = 1.4
						TweenService:Create(countScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
					end
				end
			else
				shown = -1
			end
		end
	end)
end

function Trade.start()
	buildList()
	buildInvite()
	buildTrade()
end

return Trade
