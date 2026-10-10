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
local Z_SUGGEST = 50 -- tarjeta de la sugerencia recibida, por encima del inventario
local Z_INVITE = 70 -- aviso de invitación, por encima de todo lo demás

local OFFER_CELL = 104
local STOCK_CELL = 104

-- Reparto de la ventana del trato: tu inventario a la izquierda (se queda con el ancho que sobra) y, a su
-- derecha, tu oferta y la del otro, de ancho fijo para dos casillas por fila.
local EDGE = 10 -- margen y hueco entre columnas
local OFFER_WIDTH = 256
local SIDE = OFFER_WIDTH * 2 + EDGE * 4 -- lo que se le quita al ancho para la columna del inventario
local BAR = 84 -- barra de abajo (estado y botones)
local FOOT = 34 -- línea de ayuda bajo el inventario

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
	Ui.amuletIcon(cell, artifact.color)
	Ui.tip(cell, function()
		return `{artifact.name}\n<font color="{Ui.SOFT}">Accesorio · {Config.StatNames[artifact.stat]} x{Format.multiplier(artifact.mult)}</font>`, color
	end, true)
	return cell
end

-- Monedas, gemas u objetos: icono y cantidad. `kind` = "coins", "gems" o el nombre del objeto: cada uno su icono.
local function amountCell(parent: Instance, name: string, color: Color3, amount: number, kind: string): TextButton
	local cell = Ui.cell(parent, color)
	if kind == "coins" then
		Ui.image(cell, "monedas")
	elseif kind == "gems" then
		Ui.image(cell, "gemas")
	elseif kind == "missionToken" then
		Ui.starIcon(cell, color)
	else
		Ui.crystalIcon(cell, color, kind == "gradeCrystal")
	end
	Ui.cellLabel(cell, Format.short(amount))
	Ui.tip(cell, function()
		return `{Format.short(amount)} {name}`, color
	end, true)
	return cell
end

-- Sugerencias: cómo se llama lo sugerido y su casilla.
local INTENTS = { want = { "QUIERO", Ui.COLORS.orange }, give = { "TE DOY", Ui.COLORS.green } }

local function suggestName(suggest): string
	local category = suggest.category
	if category == "coins" or category == "gems" then
		return `{Format.short(suggest.amount)} {if category == "coins" then "monedas" else "gemas"}`
	elseif category == "items" then
		return `{Format.short(suggest.amount)} {Config.Items[suggest.key].name}`
	elseif category == "swords" then
		local sword = suggest.sword and Config.Swords[suggest.sword.sword]
		return if sword then sword.name else "Espada"
	elseif category == "artifacts" then
		return Config.Artifacts[suggest.key].name
	end
	return "Armadura"
end

local function suggestCell(parent: Instance, suggest): TextButton?
	local category = suggest.category
	if category == "coins" then
		return amountCell(parent, "monedas", Ui.COLORS.coins, suggest.amount, "coins")
	elseif category == "gems" then
		return amountCell(parent, "gemas", Ui.COLORS.purple, suggest.amount, "gems")
	elseif category == "items" then
		local item = Config.Items[suggest.key]
		return amountCell(parent, item.name, item.color, suggest.amount, suggest.key)
	elseif category == "swords" and suggest.sword then
		return swordCell(parent, suggest.sword)
	elseif category == "armor" and suggest.piece then
		return armorCell(parent, suggest.piece)
	elseif category == "artifacts" then
		return artifactCell(parent, suggest.key)
	end
	return nil
end

-- Mantener pulsado repite `step(tamaño)` cada vez más deprisa (pasos de 1, 10 y 100); al soltar, `release()`.
local function hold(button: GuiButton, step: (number) -> (), release: () -> ())
	local token = 0
	button.MouseButton1Down:Connect(function()
		token += 1
		local mine = token
		step(1)
		task.spawn(function()
			local started = os.clock()
			task.wait(0.4)
			while token == mine do
				local held = os.clock() - started
				step(if held > 3 then 100 elseif held > 1.5 then 10 else 1)
				task.wait(0.08)
			end
		end)
	end)
	local function stop()
		if token % 2 == 1 then
			token += 1
			release()
		end
	end
	button.MouseButton1Up:Connect(stop)
	button.MouseLeave:Connect(stop)
end

-- Lista de jugadores ----------------------------------------------------------------------

local function buildList()
	local window, body = Ui.window("TradeList", "Comercio", Vector2.new(560, 470), function(parent)
		Ui.image(parent, "trade")
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
			Ui.close(window)
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
	Ui.panel(card, Color3.fromRGB(50, 66, 110))
	local scale = Instance.new("UIScale")
	scale.Parent = card
	Ui.popup(card, scale)
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
		Ui.close(card)
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
		Ui.open(card)
		Sfx.play("toast")
		token += 1
		local current = token
		task.delay(Config.Trade.InviteTime, function()
			if current == token and Ui.isOpen(card) then
				Ui.close(card)
				from = nil
			end
		end)
	end)
end

-- Ventana del trato -----------------------------------------------------------------------

local function buildTrade()
	local window, body = Ui.window("Trade", "Trato", Vector2.new(1160, 700), function(parent)
		Ui.image(parent, "trade")
	end)
	local current = nil -- último estado que mandó el servidor, o nil si no hay trato

	-- Las dos ofertas, a la derecha del inventario: primero la tuya y luego la del otro.
	local function offerPanel(name: string, left: boolean)
		local panel = Instance.new("Frame")
		panel.Name = name
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, if left then -EDGE * 2 - OFFER_WIDTH else -EDGE, 0, 8)
		panel.Size = UDim2.new(0, OFFER_WIDTH, 1, -8 - BAR - 8)
		panel.BackgroundColor3 = WHITE
		panel.BorderSizePixel = 0
		panel.Parent = body
		Ui.round(panel, 12)
		local stroke = Ui.stroke(panel, BLACK, 3)
		Ui.panel(panel, Color3.fromRGB(46, 50, 92))
		local title = Ui.label(panel, 21)
		title.Position = UDim2.fromOffset(10, 4)
		title.Size = UDim2.new(1, -20, 0, 30)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local badge = Ui.label(panel, 16)
		badge.Name = "Badge"
		badge.Position = UDim2.fromOffset(10, 36)
		badge.Size = UDim2.new(1, -20, 0, 26)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Ui.COLORS.dark
		Ui.round(badge, 8)
		Ui.stroke(badge, BLACK, 2)
		local grid = scrollGrid(panel, OFFER_CELL)
		grid.Name = "Grid"
		grid.Position = UDim2.fromOffset(6, 68)
		grid.Size = UDim2.new(1, -12, 1, -74)
		local empty = Ui.label(panel, 18)
		empty.AnchorPoint = Vector2.new(0.5, 0.5)
		empty.Position = UDim2.fromScale(0.5, 0.5)
		empty.Size = UDim2.new(1, -24, 0, 70)
		empty.TextWrapped = true
		empty.TextColor3 = SOFT
		empty.Text = if left then "Pulsa algo de tu inventario para ofrecerlo" else "Nada todavía"
		return { panel = panel, stroke = stroke, title = title, badge = badge, grid = grid, empty = empty, shown = nil }
	end
	local mine = offerPanel("Mine", true)
	local theirs = offerPanel("Theirs", false)

	-- Tu inventario: pestañas y casillas para añadir o quitar de tu oferta.
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Position = UDim2.fromOffset(EDGE, 8)
	tabsRow.Size = UDim2.new(1, -SIDE, 0, 38)
	tabsRow.BackgroundTransparency = 1
	tabsRow.Parent = body
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabsLayout.Parent = tabsRow
	local hint = Ui.label(body, 16)
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, EDGE + 6, 1, -BAR - 6)
	hint.Size = UDim2.new(1, -SIDE - 12, 0, FOOT)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.TextColor3 = SOFT
	hint.Text = "Pulsa algo tuyo para ofrecerlo; en tu oferta, púlsalo para quitarlo."

	local stockArea = Instance.new("Frame")
	stockArea.Name = "Stock"
	stockArea.Position = UDim2.fromOffset(EDGE, 52)
	stockArea.Size = UDim2.new(1, -SIDE, 1, -52 - BAR - FOOT - 10)
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
	amountsLayout.CellSize = UDim2.new(1, -28, 0, 50)
	amountsLayout.CellPadding = UDim2.fromOffset(10, 8)
	amountsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	amountsLayout.Parent = amounts
	local amountsPadding = Instance.new("UIPadding")
	amountsPadding.PaddingTop = UDim.new(0, 10)
	amountsPadding.PaddingLeft = UDim.new(0, 10)
	amountsPadding.Parent = amounts

	-- Modo sugerir (botón "Sugerir"): lo que se pulse o se escriba no cambia tu oferta, se le sugiere al otro.
	local suggesting = false
	local setSuggesting: (boolean) -> ()

	-- Cada fila: nombre, [−] cantidad [+] y, en modo sugerir, "Quiero" y "Te doy". `value` es la cantidad que se
	-- está tocando (con − y + o en modo sugerir); fuera de eso la casilla enseña lo que hay en tu oferta.
	local amountRows = {} -- { box, label, minus, plus, want, give, owned(), offered(), name, value, touching }
	local function amountRow(order: number, name: string, color: Color3, category: string, key: string?)
		local frame = Instance.new("Frame")
		frame.Name = "Row_" .. (key or category)
		frame.LayoutOrder = order
		frame.BackgroundColor3 = WHITE
		frame.BorderSizePixel = 0
		frame.Parent = amounts
		Ui.round(frame, 8)
		Ui.stroke(frame, BLACK, 2)
		Ui.panel(frame, Color3.fromRGB(52, 56, 100), color)
		local label = Ui.label(frame, 17)
		label.Position = UDim2.fromOffset(18, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		local box = Instance.new("TextBox")
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(1, 0.5)
		box.Size = UDim2.fromOffset(92, 32)
		box.PlaceholderText = "0"
		box.TextSize = 19
		box.ClearTextOnFocus = false
		box.Text = ""
		box.Parent = frame
		Ui.field(box)
		local function small(buttonName: string, text: string, buttonColor: Color3, width: number): TextButton
			local button = Ui.button(frame, text, buttonColor)
			button.Name = buttonName
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Size = UDim2.fromOffset(width, 32)
			button.TextSize = if width > 40 then 16 else 22
			return button
		end
		local row = {
			box = box,
			label = label,
			minus = small("Minus", "-", Ui.COLORS.gray, 30),
			plus = small("Plus", "+", Ui.COLORS.gray, 30),
			want = small("Want", "Quiero", Ui.COLORS.orange, 64),
			give = small("Give", "Te doy", Ui.COLORS.green, 64),
			name = name,
			value = 1,
			touching = false,
		}
		function row.owned(): number
			return player:GetAttribute(if category == "items" then "Item_" .. key else if category == "coins" then "Coins" else "Gems") or 0
		end
		function row.offered(): number
			if not current then
				return 0
			end
			return if category == "items" then current.you.items[key] or 0 else current.you[category]
		end
		-- En tu oferta no cabe más de lo que tienes; en una sugerencia ("Quiero") sí.
		local function clamp(value: number): number
			local top = if suggesting then Config.Trade.SuggestMaxAmount else row.owned()
			return math.clamp(math.floor(value), if suggesting then 1 else 0, math.max(top, 0))
		end
		local function show()
			box.Text = if row.value > 0 then Format.short(row.value) else ""
		end
		local function send()
			row.touching = false
			if not suggesting then
				Remotes.TradeOffer:FireServer(category, key, row.value)
			end
		end
		box.FocusLost:Connect(function()
			-- Admite 1000, 1.5K, 2M...
			row.value = clamp(Format.parse(box.Text) or 0)
			show()
			send()
		end)
		for button, sign in { [row.minus] = -1, [row.plus] = 1 } do
			hold(button, function(size: number)
				if current == nil or current.state ~= "editing" then
					return
				end
				if not suggesting and not row.touching then
					row.value = row.offered()
				end
				row.touching = true
				row.value = clamp(row.value + sign * size)
				show()
			end, send)
		end
		row.want.Activated:Connect(function()
			Remotes.TradeSuggest:FireServer("want", category, key, row.value)
			setSuggesting(false)
		end)
		row.give.Activated:Connect(function()
			Remotes.TradeSuggest:FireServer("give", category, key, math.min(row.value, row.owned()))
			setSuggesting(false)
		end)
		table.insert(amountRows, row)
	end
	-- Solo las filas de lo que se puede comerciar (Config.Trade.Allow: monedas y gemas, no); la rejilla las recoloca sola.
	local allow = Config.Trade.Allow
	local rowCount = 0
	local function allowedRow(name: string, color: Color3, category: string, key: string?)
		if allow[category] then
			rowCount += 1
			amountRow(rowCount, name, color, category, key)
		end
	end
	allowedRow("Monedas", Ui.COLORS.coins, "coins")
	allowedRow("Gemas", Ui.COLORS.purple, "gems")
	for _, key in Config.ItemOrder do
		allowedRow(Config.Items[key].name, Config.Items[key].color, "items", key)
	end

	-- Pestañas.
	local tab = "swords"
	local tabButtons = {}
	local stockCells = {} -- [id o índice] = casilla de la pestaña que se ve
	local stockKey: string? = nil
	local TABS = { { "swords", "Espadas", Ui.COLORS.red }, { "armor", "Armadura", Ui.COLORS.orange }, { "artifacts", "Accesorios", Ui.COLORS.purple }, { "amounts", if allow.coins or allow.gems then "Monedas y objetos" else "Objetos", Ui.COLORS.blue } }

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
			-- De derecha a izquierda: [Te doy] [Quiero] (solo en modo sugerir) [+] cantidad [−] y el nombre.
			local right = if suggesting then 146 else 8
			row.want.Visible, row.give.Visible = suggesting, suggesting
			row.give.Position = UDim2.new(1, -8, 0.5, 0)
			row.want.Position = UDim2.new(1, -76, 0.5, 0)
			row.plus.Position = UDim2.new(1, -right, 0.5, 0)
			row.box.Position = UDim2.new(1, -right - 34, 0.5, 0)
			row.minus.Position = UDim2.new(1, -right - 130, 0.5, 0)
			row.label.Size = UDim2.new(1, -right - 186, 1, 0)
			row.label.Text = if suggesting then row.name else `{row.name} <font color="{Ui.SOFT}">(tienes {Format.short(row.owned())})</font>`
			if not row.box:IsFocused() and not row.touching then
				local value = if suggesting then row.value else row.offered()
				row.box.Text = if value > 0 then Format.short(value) else ""
			end
		end
	end

	local function buildStock(force: boolean?)
		local key = `{tab}|{player:GetAttribute("Swords")}|{player:GetAttribute("Loadout")}|{player:GetAttribute("Armor")}|{player:GetAttribute("Artifacts")}`
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
				if suggesting then
					Remotes.TradeSuggest:FireServer("give", tab, id, 1)
					setSuggesting(false)
					return
				end
				Remotes.TradeOffer:FireServer(tab, id, if (cell :: any).Select.Visible then 0 else 1)
			end)
		end
		if tab == "swords" then
			local worn = Stats.list(player, "Loadout")
			for _, copy in Stats.swords(player) do
				-- Las equipadas no se pueden dar.
				if not table.find(worn, copy.id) then
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
		-- Las cuatro se reparten el ancho de la columna.
		button.Size = UDim2.new(1 / #TABS, -6, 0, 36)
		button.TextSize = if #entry[2] > 10 then 15 else 19
		tabButtons[entry[1]] = button
		button.Activated:Connect(function()
			tab = entry[1]
			for name, other in tabButtons do
				Ui.setSelected(other, name == tab)
			end
			buildStock()
		end)
	end
	Ui.setSelected(tabButtons[tab], true)

	-- Barra de abajo: en qué paso se está y los botones.
	local status = Ui.label(body, 20)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 16, 1, -14)
	status.Size = UDim2.new(1, -550, 0, 56)
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
	-- "Sugerir": bocadillo con puntos y el texto a su derecha.
	local suggestButton = Ui.button(body, "Sugerir ", Ui.COLORS.blue)
	suggestButton.Name = "Suggest"
	suggestButton.AnchorPoint = Vector2.new(1, 1)
	suggestButton.Position = UDim2.new(1, -372, 1, -12)
	suggestButton.Size = UDim2.fromOffset(150, 60)
	suggestButton.TextSize = 20
	suggestButton.TextXAlignment = Enum.TextXAlignment.Right
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0, 0.5)
	bubble.Position = UDim2.new(0, 12, 0.5, -2)
	bubble.Size = UDim2.fromOffset(38, 28)
	bubble.BackgroundColor3 = WHITE
	bubble.BorderSizePixel = 0
	bubble.Parent = suggestButton
	Ui.round(bubble, 10)
	Ui.stroke(bubble, BLACK, 2)
	Ui.gradient(bubble, WHITE, Color3.fromRGB(190, 200, 225), 90)
	for dot = 1, 3 do
		local point = Instance.new("Frame")
		point.AnchorPoint = Vector2.new(0.5, 0.5)
		point.Position = UDim2.fromScale(dot / 4, 0.5)
		point.Size = UDim2.fromOffset(5, 5)
		point.BackgroundColor3 = Color3.fromRGB(40, 60, 110)
		point.BorderSizePixel = 0
		point.Parent = bubble
		Ui.round(point, 3)
	end
	suggestButton.Activated:Connect(function()
		setSuggesting(not suggesting)
	end)

	-- Sugerencia recibida: tarjeta sobre tu inventario (las dos ofertas siguen a la vista) con qué se sugiere,
	-- quién, y Aceptar o Ignorar. Aceptarla solo cambia una oferta: el trato sigue pidiendo Aceptar y Confirmar.
	local card = Instance.new("Frame")
	card.Name = "SuggestIn"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(470, 176)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = stockArea
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(64, 70, 128))
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local ribbon = Ui.label(card, 22)
	ribbon.Name = "Ribbon"
	ribbon.Position = UDim2.fromOffset(12, 10)
	ribbon.Size = UDim2.fromOffset(130, 34)
	ribbon.BackgroundTransparency = 0
	Ui.round(ribbon, 9)
	Ui.stroke(ribbon, BLACK, 3)
	local from = Ui.label(card, 16)
	from.Name = "From"
	from.Position = UDim2.fromOffset(152, 10)
	from.Size = UDim2.new(1, -164, 0, 34)
	from.TextXAlignment = Enum.TextXAlignment.Left
	from.TextTruncate = Enum.TextTruncate.AtEnd
	from.TextColor3 = SOFT
	local slot = Instance.new("Frame")
	slot.Name = "Item"
	slot.Position = UDim2.fromOffset(14, 54)
	slot.Size = UDim2.fromOffset(92, 92)
	slot.BackgroundTransparency = 1
	slot.Parent = card
	local what = Ui.label(card, 30)
	what.Name = "What"
	what.Position = UDim2.fromOffset(118, 54)
	what.Size = UDim2.new(1, -118 - 178, 0, 92)
	what.TextXAlignment = Enum.TextXAlignment.Left
	what.TextWrapped = true
	what.TextColor3 = GOLD
	local acceptSuggest = Ui.button(card, "Aceptar", Ui.COLORS.green)
	acceptSuggest.Name = "Accept"
	acceptSuggest.AnchorPoint = Vector2.new(1, 0)
	acceptSuggest.Position = UDim2.new(1, -12, 0, 54)
	acceptSuggest.Size = UDim2.fromOffset(156, 50)
	acceptSuggest.TextSize = 24
	local ignoreSuggest = Ui.button(card, "Ignorar", Ui.COLORS.red)
	ignoreSuggest.Name = "Ignore"
	ignoreSuggest.AnchorPoint = Vector2.new(1, 0)
	ignoreSuggest.Position = UDim2.new(1, -12, 0, 110)
	ignoreSuggest.Size = UDim2.fromOffset(156, 36)
	ignoreSuggest.TextSize = 18
	-- Lo que le queda antes de caducar.
	local timer = Instance.new("Frame")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0, 1)
	timer.Position = UDim2.new(0, 14, 1, -10)
	timer.Size = UDim2.new(1, -28, 0, 6)
	timer.BackgroundColor3 = GOLD
	timer.BorderSizePixel = 0
	timer.Parent = card
	Ui.round(timer, 3)
	Ui.layer(card, Z_SUGGEST)
	acceptSuggest.Activated:Connect(function()
		Remotes.TradeSuggestRespond:FireServer(true)
	end)
	ignoreSuggest.Activated:Connect(function()
		Remotes.TradeSuggestRespond:FireServer(false)
	end)

	-- Tu sugerencia: una tira bajo el inventario (donde va la ayuda) con lo que has sugerido y "Quitar".
	local chip = Instance.new("Frame")
	chip.Name = "SuggestOut"
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0, EDGE, 1, -BAR - 4)
	chip.Size = UDim2.fromOffset(330, FOOT + 2)
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.Parent = body
	Ui.round(chip, 10)
	Ui.stroke(chip, BLACK, 3)
	Ui.panel(chip, Color3.fromRGB(52, 56, 100))
	local chipRibbon = Ui.label(chip, 15)
	chipRibbon.Name = "Ribbon"
	chipRibbon.AnchorPoint = Vector2.new(0, 0.5)
	chipRibbon.Position = UDim2.new(0, 8, 0.5, 0)
	chipRibbon.Size = UDim2.fromOffset(76, 24)
	chipRibbon.BackgroundTransparency = 0
	Ui.round(chipRibbon, 7)
	Ui.stroke(chipRibbon, BLACK, 2)
	local chipText = Ui.label(chip, 16)
	chipText.Name = "What"
	chipText.Position = UDim2.fromOffset(92, 0)
	chipText.Size = UDim2.new(1, -92 - 86, 1, 0)
	chipText.TextXAlignment = Enum.TextXAlignment.Left
	chipText.TextTruncate = Enum.TextTruncate.AtEnd
	local removeSuggest = Ui.button(chip, "Quitar", Ui.COLORS.red)
	removeSuggest.Name = "Remove"
	removeSuggest.AnchorPoint = Vector2.new(1, 0.5)
	removeSuggest.Position = UDim2.new(1, -8, 0.5, 0)
	removeSuggest.Size = UDim2.fromOffset(72, 26)
	removeSuggest.TextSize = 15
	removeSuggest.Activated:Connect(function()
		Remotes.TradeSuggest:FireServer(nil)
	end)

	local shownSuggest: string? = nil
	local function paintSuggests()
		local mineSuggest, theirSuggest = current.you.suggest, current.them.suggest
		chip.Visible = mineSuggest ~= nil
		hint.Visible = mineSuggest == nil
		if mineSuggest then
			local intent = INTENTS[mineSuggest.intent]
			chipRibbon.Text = intent[1]
			chipRibbon.BackgroundColor3 = intent[2]
			chipText.Text = if mineSuggest.ignored then "Ignorada" else suggestName(mineSuggest)
			chipText.TextColor3 = if mineSuggest.ignored then Ui.COLORS.red:Lerp(WHITE, 0.3) else WHITE
		end
		-- La que el otro ha visto ignorar ya no se le enseña.
		if theirSuggest and theirSuggest.ignored then
			theirSuggest = nil
		end
		card.Visible = theirSuggest ~= nil
		local key = if theirSuggest then `{theirSuggest.intent}|{theirSuggest.category}|{theirSuggest.key}|{theirSuggest.amount}|{theirSuggest.ends}` else nil
		if key == shownSuggest then
			return
		end
		shownSuggest = key
		slot:ClearAllChildren()
		if not theirSuggest then
			return
		end
		local intent = INTENTS[theirSuggest.intent]
		ribbon.Text = intent[1]
		ribbon.BackgroundColor3 = intent[2]
		from.Text = `{current.them.name} {if theirSuggest.intent == "want" then "te lo pide" else "te lo ofrece"}`
		what.Text = suggestName(theirSuggest)
		local cell = suggestCell(slot, theirSuggest)
		if cell then
			cell.Size = UDim2.fromScale(1, 1)
			-- Al final, cuando la vista 3D ya está puesta: la tarjeta va en su propia capa.
			task.defer(function()
				if cell.Parent then
					Ui.layer(cell, Z_SUGGEST)
				end
			end)
			Ui.layer(cell, Z_SUGGEST)
		end
		Sfx.play("toast")
		local left = math.max(0, theirSuggest.ends - workspace:GetServerTimeNow())
		local part = math.min(1, left / Config.Trade.SuggestTime)
		timer.Size = UDim2.new(part, -28 * part, 0, 6)
		if not Performance.get() then
			TweenService:Create(timer, TweenInfo.new(left, Enum.EasingStyle.Linear), { Size = UDim2.fromOffset(0, 6) }):Play()
			cardScale.Scale = 0.7
			TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	function setSuggesting(on: boolean)
		local was = suggesting
		suggesting = on and current ~= nil and current.state == "editing"
		Ui.setSelected(suggestButton, suggesting)
		suggestButton.BackgroundColor3 = if suggesting then GOLD else Ui.COLORS.blue
		-- Solo al entrar o salir del modo: cada estado que llega pasa por aquí y no debe borrar lo que se está escribiendo.
		if was ~= suggesting then
			for _, row in amountRows do
				row.value, row.touching = 1, false
			end
		end
		if current then
			hint.Text = if current.state ~= "editing" then "Ofertas bloqueadas." elseif suggesting then "Sugerir: pulsa algo tuyo, o pide una cantidad." else "Pulsa algo tuyo para ofrecerlo; en tu oferta, púlsalo para quitarlo."
			paintStock()
		end
	end

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

	-- Pinta la oferta de un lado (solo rehace las casillas si ha cambiado). En la tuya, cada casilla lleva una
	-- X y al pulsarla se quita de la oferta (pedido por el usuario: buscarla en el inventario era un lío).
	local function paintOffer(panel, side, title: string)
		panel.title.Text = title
		local confirming = current.state ~= "editing"
		local own = panel == mine
		if own then
			for _, child in panel.grid:GetChildren() do
				local mark = child:FindFirstChild("Remove")
				if mark then
					mark.Visible = not confirming
				end
			end
		end
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
		local function place(cell: TextButton, category: string, key: any)
			order += 1
			cell.LayoutOrder = order
			if not own then
				return
			end
			local mark = Ui.cellTag(cell, "X", Ui.COLORS.red)
			mark.Name = "Remove"
			mark.AnchorPoint = Vector2.new(1, 0)
			mark.Position = UDim2.new(1, -4, 0, 4)
			mark.Visible = not confirming
			cell.Activated:Connect(function()
				if locked() then
					Sfx.play("error")
					return
				end
				Remotes.TradeOffer:FireServer(category, key, 0)
			end)
		end
		if side.coins > 0 then
			place(amountCell(panel.grid, "monedas", Ui.COLORS.coins, side.coins, "coins"), "coins", nil)
		end
		if side.gems > 0 then
			place(amountCell(panel.grid, "gemas", Ui.COLORS.purple, side.gems, "gems"), "gems", nil)
		end
		for _, name in Config.ItemOrder do
			local amount = side.items[name]
			if amount and amount > 0 then
				place(amountCell(panel.grid, Config.Items[name].name, Config.Items[name].color, amount, name), "items", name)
			end
		end
		for _, copy in side.swords do
			place(swordCell(panel.grid, copy), "swords", copy.id)
		end
		for _, piece in side.armor do
			place(armorCell(panel.grid, piece), "armor", piece.id)
		end
		for _, index in side.artifacts do
			place(artifactCell(panel.grid, index), "artifacts", index)
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
		-- Fuera del paso de elegir no hay sugerencias; también pone el texto de ayuda.
		setSuggesting(suggesting and state == "editing")
		suggestButton.Visible = state == "editing"
		paintSuggests()
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
			setSuggesting(false)
			card.Visible, chip.Visible, shownSuggest = false, false, nil
			countdown.Visible = false
			Ui.close(window)
			return
		end
		local opening = current == nil
		current = state
		if opening then
			mine.shown, theirs.shown, stockKey = nil, nil, nil
			if not Ui.isOpen(window) then
				Ui.toggle("Trade")
			end
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
		if current and window.Visible and (attribute == "Swords" or attribute == "Armor" or attribute == "Artifacts" or attribute == "Loadout" or attribute == "Coins" or attribute == "Gems" or string.sub(attribute, 1, 5) == "Item_") then
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
