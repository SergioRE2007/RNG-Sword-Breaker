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
local Lang = require(ReplicatedStorage.Shared.Lang)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ArmorPane = require(script.Parent.ArmorPane)
local Backpack = require(script.Parent.Backpack)
local Performance = require(script.Parent.Performance)
local Potions = require(script.Parent.Potions)
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
local Z_MENU = 60 -- desplegable de cantidades de la pestaña de objetos
local Z_INVITE = 70 -- aviso de invitación, por encima de todo lo demás

local OFFER_CELL = 104
local STOCK_CELL = 104
local MENU_WIDTH = 150 -- desplegable de cantidades
local MENU_BUTTON = 40

-- Reparto de la ventana del trato: tu inventario a la izquierda (se queda con el ancho que sobra) y, a su
-- derecha, tu oferta y la del otro, de ancho fijo para dos casillas por fila.
local EDGE = 10 -- margen y hueco entre columnas
local OFFER_WIDTH = 256
local SIDE = OFFER_WIDTH * 2 + EDGE * 4 -- lo que se le quita al ancho para la columna del inventario
local BAR = 84 -- barra de abajo (estado y botones)
local FOOT = 34 -- línea de ayuda bajo el inventario

local STEPS = {
	editing = Lang.t(nil, "1 of 3 · Choose what you give and press Accept"),
	confirming = Lang.t(nil, "2 of 3 · Check both offers carefully and press CONFIRM"),
	countdown = Lang.t(nil, "3 of 3 · About to complete: you can still cancel"),
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
	Ui.artifactIcon(cell, artifact)
	Ui.tip(cell, function()
		return `{Lang.t(nil, artifact.name)}\n<font color="{Ui.SOFT}">{Lang.t(nil, "Accessory")} · {Lang.t(nil, Config.StatNames[artifact.stat])} x{Format.multiplier(artifact.mult)}</font>`, color
	end, true)
	return cell
end

-- Icono de monedas, gemas o un objeto (`kind` = "coins", "gems" o el nombre del objeto), el mismo que en la mochila.
local function itemIcon(cell: Instance, kind: string, color: Color3)
	local item = Config.Items[kind]
	if kind == "coins" then
		Ui.image(cell, "monedas")
	elseif kind == "gems" then
		Ui.image(cell, "gemas")
	elseif item and item.potion then
		Potions.icon(cell, item.potion.family, item.potion.tier)
		Potions.addTag(cell, item.potion.tier)
	elseif item and item.image then
		Ui.image(cell, item.image)
	else
		Ui.crystalIcon(cell, color, kind == "gradeCrystal")
	end
end

-- Monedas, gemas u objetos: icono y cantidad.
local function amountCell(parent: Instance, name: string, color: Color3, amount: number, kind: string): TextButton
	local cell = Ui.cell(parent, color)
	itemIcon(cell, kind, color)
	Ui.cellLabel(cell, Format.short(amount))
	Ui.tip(cell, function()
		return `{Format.short(amount)} {name}`, color
	end, true)
	return cell
end

-- Objetos que se cambian por cantidad, en orden: los de la mochila y luego las pociones.
local ITEM_KEYS = table.clone(Config.ItemOrder)
for _, key in Config.Potions.ItemKeys do
	table.insert(ITEM_KEYS, key)
end

-- Peticiones ("Pedir"): cómo se llama lo pedido y su casilla.
local REQUEST = Lang.t(nil, "REQUEST")

local function suggestName(suggest): string
	local category = suggest.category
	if category == "coins" or category == "gems" then
		return `{Format.short(suggest.amount)} {Lang.t(nil, if category == "coins" then "coins" else "gems")}`
	elseif category == "items" then
		return `{Format.short(suggest.amount)} {Lang.t(nil, Config.Items[suggest.key].name)}`
	elseif category == "swords" then
		local sword = suggest.sword and Config.Swords[suggest.sword.sword]
		return Lang.t(nil, if sword then sword.name else "Sword")
	elseif category == "artifacts" then
		return Lang.t(nil, Config.Artifacts[suggest.key].name)
	end
	return Lang.t(nil, "Armor")
end

local function suggestCell(parent: Instance, suggest): TextButton?
	local category = suggest.category
	if category == "coins" then
		return amountCell(parent, Lang.t(nil, "coins"), Ui.COLORS.coins, suggest.amount, "coins")
	elseif category == "gems" then
		return amountCell(parent, Lang.t(nil, "gems"), Ui.COLORS.purple, suggest.amount, "gems")
	elseif category == "items" then
		local item = Config.Items[suggest.key]
		return amountCell(parent, Lang.t(nil, item.name), item.color, suggest.amount, suggest.key)
	elseif category == "swords" and suggest.sword then
		return swordCell(parent, suggest.sword)
	elseif category == "armor" and suggest.piece then
		return armorCell(parent, suggest.piece)
	elseif category == "artifacts" then
		return artifactCell(parent, suggest.key)
	end
	return nil
end

-- Lista de jugadores ----------------------------------------------------------------------

local function buildList()
	local window, body = Ui.window("TradeList", Lang.t(nil, "Trading"), Vector2.new(560, 470), function(parent)
		Ui.image(parent, "trade")
	end)
	local note = Ui.label(body, 17)
	note.Position = UDim2.fromOffset(16, 6)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = SOFT
	note.Text = Lang.t(nil, "Invite a player on this server to trade.")

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
	empty.Text = Lang.t(nil, "There's no one else on the server.")

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
		local invite = Ui.button(frame, Lang.t(nil, "Invite"), Ui.COLORS.green)
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
			row(total, Lang.t(nil, "Test bot"), 0, GOLD)
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
	local accept = Ui.button(card, Lang.t(nil, "Accept"), Ui.COLORS.green)
	accept.Name = "Accept"
	accept.AnchorPoint = Vector2.new(1, 1)
	accept.Position = UDim2.new(0.5, -6, 1, -12)
	accept.Size = UDim2.fromOffset(170, 48)
	accept.TextSize = 22
	local decline = Ui.button(card, Lang.t(nil, "Decline"), Ui.COLORS.red)
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
		text.Text = Lang.t(nil, "{name} wants to trade with you", { name = `<font color="{hex(GOLD)}">{name}</font>` })
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
	local window, body = Ui.window("Trade", Lang.t(nil, "Trade"), Vector2.new(1160, 700), function(parent)
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
		empty.Text = Lang.t(nil, if left then "Click something in your inventory to offer it" else "Nothing yet")
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
	hint.Text = Lang.t(nil, "Click something of yours to offer it; in your offer, click it to remove it.")

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
	local stockEmpty = Ui.label(stockArea, 20)
	stockEmpty.Name = "Empty"
	stockEmpty.AnchorPoint = Vector2.new(0.5, 0.5)
	stockEmpty.Position = UDim2.fromScale(0.5, 0.5)
	stockEmpty.Size = UDim2.new(1, -40, 0, 60)
	stockEmpty.TextWrapped = true
	stockEmpty.TextColor3 = SOFT
	stockEmpty.Text = Lang.t(nil, "Nothing here")
	stockEmpty.Visible = false

	-- Modo pedir (botón "Pedir"): en vez de tu inventario se ve el del otro, y lo que se pulse se le pide.
	local asking = false
	local setAsking: (boolean) -> ()

	-- El jugador del otro lado (nil con el bot de pruebas, que solo tiene cantidades). Sus atributos se replican a todos
	-- los clientes, así que su inventario se lee de su Player como el tuyo.
	local function otherPlayer(): Player?
		return if current then Players:GetPlayerByUserId(current.them.userId) else nil
	end

	-- Pestañas.
	local tab = "swords"
	local tabButtons = {}
	local stockCells = {} -- [id o índice] = casilla de la pestaña que se ve
	local stockKey: string? = nil
	local allow = Config.Trade.Allow
	local TABS = { { "swords", Lang.t(nil, "Swords"), Ui.COLORS.red }, { "armor", Lang.t(nil, "Armor"), Ui.COLORS.orange }, { "artifacts", Lang.t(nil, "Accessories"), Ui.COLORS.purple }, { "amounts", Lang.t(nil, if allow.coins or allow.gems then "Coins and items" else "Items"), Ui.COLORS.blue } }

	local function locked(): boolean
		return current == nil or current.state ~= "editing"
	end

	-- Pestaña de objetos (pedido por el usuario): casillas como las de la mochila en la misma rejilla, solo de lo que
	-- tiene quien enseña su inventario. Con una sola unidad, pulsarla la añade o la quita; con más, abre al lado un
	-- desplegable con +1, +10, +100, Máx y Quitar. En modo pedir, el desplegable pide esa cantidad.
	-- Solo lo que se puede comerciar (Config.Trade.Allow: monedas y gemas, no).
	local AMOUNTS = {} -- { category, key, name, color }
	if allow.coins then
		table.insert(AMOUNTS, { category = "coins", name = Lang.t(nil, "Coins"), color = Ui.COLORS.coins })
	end
	if allow.gems then
		table.insert(AMOUNTS, { category = "gems", name = Lang.t(nil, "Gems"), color = Ui.COLORS.purple })
	end
	if allow.items then
		for _, key in ITEM_KEYS do
			local item = Config.Items[key]
			if not item.noTrade then
				table.insert(AMOUNTS, { category = "items", key = key, name = Lang.t(nil, item.name), color = item.color })
			end
		end
	end
	local amountCells = {} -- [entrada de AMOUNTS] = casilla de la pestaña que se ve

	-- Lo que tiene quien enseña su inventario: tú, o el otro en modo pedir (el bot, de todo).
	local function ownedOf(entry): number
		local who = if asking then otherPlayer() else player
		if not who then
			return Config.Trade.SuggestMaxAmount
		end
		return who:GetAttribute(if entry.category == "items" then "Item_" .. entry.key elseif entry.category == "coins" then "Coins" else "Gems") or 0
	end
	-- Lo que ya hay en la oferta de quien enseña su inventario.
	local function offeredOf(entry): number
		if not current then
			return 0
		end
		local side = if asking then current.them else current.you
		return if entry.category == "items" then side.items[entry.key] or 0 else side[entry.category]
	end

	-- Da o pide `amount` (math.huge = todo lo que hay; 0 = quitarlo de tu oferta). En tu oferta se suma a lo que ya hay.
	local function apply(entry, amount: number)
		local owned = ownedOf(entry)
		if asking then
			local value = math.min(amount, owned)
			if value < 1 then
				Sfx.play("error")
				return
			end
			Remotes.TradeSuggest:FireServer("want", entry.category, entry.key, value)
			setAsking(false)
			return
		end
		local value = if amount == 0 then 0 else math.min(offeredOf(entry) + amount, owned)
		Remotes.TradeOffer:FireServer(entry.category, entry.key, value)
	end

	-- Desplegable: se cierra al elegir, al pulsar fuera (`catcher`) y al rehacer el inventario. El `catcher` oscurece un
	-- poco el inventario; al no ser transparente del todo, Ui.tip ve las casillas tapadas y quita su cartel, que si no
	-- caería encima del desplegable.
	local catcher = Instance.new("TextButton")
	catcher.Name = "MenuCatcher"
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundColor3 = BLACK
	catcher.BackgroundTransparency = 0.6
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Visible = false
	catcher.ZIndex = Z_MENU - 1
	catcher.Parent = stockArea
	Ui.round(catcher, 12)
	local menu = Instance.new("Frame")
	menu.Name = "AmountMenu"
	menu.BackgroundColor3 = WHITE
	menu.BorderSizePixel = 0
	menu.Visible = false
	menu.Parent = stockArea
	Ui.round(menu, 12)
	Ui.stroke(menu, BLACK, 3)
	Ui.panel(menu, Color3.fromRGB(64, 70, 128))
	local menuScale = Instance.new("UIScale")
	menuScale.Parent = menu
	local menuContent = Instance.new("Frame")
	menuContent.Name = "Content"
	menuContent.BackgroundTransparency = 1
	menuContent.Size = UDim2.fromScale(1, 1)
	menuContent.Parent = menu
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.Padding = UDim.new(0, 6)
	menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menuContent
	local menuPadding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(menuPadding :: any)[side] = UDim.new(0, 8)
	end
	menuPadding.Parent = menuContent
	local menuTitle = Ui.label(menuContent, 17)
	menuTitle.Name = "Title"
	menuTitle.Size = UDim2.new(1, 0, 0, 24)
	menuTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local menuButtons = {} -- { button, amount }
	for order, option in { { "Add_1", 1 }, { "Add_10", 10 }, { "Add_100", 100 }, { "Add_max", math.huge }, { "Remove", 0 } } do
		local button = Ui.button(menuContent, "", Ui.COLORS.green)
		button.Name = option[1]
		button.LayoutOrder = order
		button.Size = UDim2.new(1, 0, 0, MENU_BUTTON)
		button.TextSize = 20
		table.insert(menuButtons, { button = button, amount = option[2] })
	end
	Ui.layer(menu, Z_MENU)

	local menuEntry = nil
	local function closeMenu()
		menu.Visible, catcher.Visible, menuEntry = false, false, nil
	end
	catcher.Activated:Connect(closeMenu)
	for _, option in menuButtons do
		option.button.Activated:Connect(function()
			local entry = menuEntry
			closeMenu()
			if entry and not locked() then
				apply(entry, option.amount)
			end
		end)
	end

	local function openMenu(entry, cell: GuiObject)
		local owned, offered = ownedOf(entry), offeredOf(entry)
		local left = if asking then owned else owned - offered
		local shown = 0
		for _, option in menuButtons do
			local amount = option.amount
			-- +10 y +100 solo si no llegan a todo lo que queda: para eso está Máx.
			local visible = if amount == 0 then not asking and offered > 0 elseif amount == math.huge then left > 0 else amount < left
			option.button.Visible = visible
			if visible then
				shown += 1
				option.button.Text = if amount == 0 then Lang.t(nil, "Remove") elseif amount == math.huge then Lang.t(nil, "Max") else (if asking then "" else "+") .. Format.short(amount)
				option.button.BackgroundColor3 = if amount == 0 then Ui.COLORS.red elseif asking then Ui.COLORS.orange else Ui.COLORS.green
			end
		end
		if shown == 0 then
			Sfx.play("error")
			return
		end
		menuEntry = entry
		menuTitle.Text = entry.name
		local height = 16 + 24 + shown * (MENU_BUTTON + 6)
		menu.Size = UDim2.fromOffset(MENU_WIDTH, height)
		menuScale.Scale = 1
		menu.Visible, catcher.Visible = true, true
		-- La ventana va escalada: la escala sale del ancho del menú en pantalla. Al lado de la casilla, a la derecha si cabe.
		local scale = menu.AbsoluteSize.X / MENU_WIDTH
		scale = if scale > 0 then scale else 1
		local area = stockArea.AbsoluteSize / scale
		local at = (cell.AbsolutePosition - stockArea.AbsolutePosition) / scale
		local x = at.X + cell.AbsoluteSize.X / scale + 8
		if x + MENU_WIDTH > area.X - 4 then
			x = at.X - MENU_WIDTH - 8
		end
		menu.Position = UDim2.fromOffset(math.max(4, x), math.clamp(at.Y, 4, math.max(4, area.Y - height - 4)))
		if not Performance.get() then
			menuScale.Scale = 0.85
			TweenService:Create(menuScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	-- Casilla de un objeto: icono, lo que tiene su dueño abajo y, arriba, cuánto hay ya en su oferta.
	local function amountStockCell(entry, owned: number, bot: boolean): TextButton
		local kind = entry.key or entry.category
		local item = Config.Items[kind]
		local cell = Ui.cell(stock, entry.color, if item and item.potion then item.potion.tier else nil)
		cell.Name = "Item_" .. kind
		itemIcon(cell, kind, entry.color)
		Ui.cellLabel(cell, if bot then "" else "x" .. Format.short(owned))
		local tag = Ui.cellTag(cell, "", Ui.COLORS.green)
		tag.Name = "Offered"
		tag.Visible = false
		Ui.tip(cell, function()
			if item and item.potion then
				return Potions.tip(item.potion.family, item.potion.tier, ownedOf(entry)), entry.color
			elseif item then
				return `{entry.name}\n<font color="{Ui.SOFT}">{Lang.t(nil, item.description)}</font>`, entry.color
			end
			return entry.name, entry.color
		end, true)
		cell.Activated:Connect(function()
			if locked() then
				Sfx.play("error")
				return
			end
			if ownedOf(entry) > 1 then
				openMenu(entry, cell)
			else
				apply(entry, if not asking and offeredOf(entry) > 0 then 0 else 1)
			end
		end)
		return cell
	end

	-- Marca en el inventario que se ve lo que ya está en la oferta de su dueño.
	local function paintStock()
		if not current then
			return
		end
		local offered = {}
		for _, entry in ((if asking then current.them else current.you) :: any)[tab] or {} do
			offered[if type(entry) == "table" then entry.id else entry] = true
		end
		for key, cell in stockCells do
			(cell :: any).Select.Visible = offered[key] == true
		end
		for entry, cell in amountCells do
			local amount = offeredOf(entry)
			local tag = cell:FindFirstChild("Offered") :: TextLabel
			local select = cell:FindFirstChild("Select") :: Frame
			tag.Visible = amount > 0
			tag.Text = Format.short(amount)
			tag.Size = UDim2.fromOffset(math.max(22, 10 + 9 * (utf8.len(tag.Text) or 1)), 22)
			select.Visible = amount > 0
		end
	end

	local function buildStock(force: boolean?)
		-- De quién es el inventario que se ve: el tuyo o, en modo pedir, el del otro (nil con el bot).
		local owner = if asking then otherPlayer() else player
		local key = `{tab}|{asking}|{owner and owner.UserId}`
		if owner then
			key ..= `|{owner:GetAttribute("Swords")}|{owner:GetAttribute("Loadout")}|{owner:GetAttribute("Bag")}|{owner:GetAttribute("Armor")}|{owner:GetAttribute("Artifacts")}`
		end
		if tab == "amounts" then
			for _, entry in AMOUNTS do
				key ..= `|{ownedOf(entry)}`
			end
		end
		if key == stockKey and not force then
			paintStock()
			return
		end
		stockKey = key
		closeMenu()
		clear(stock)
		table.clear(stockCells)
		table.clear(amountCells)
		local function add(cell: TextButton, id: number, order: number)
			cell.LayoutOrder = order
			stockCells[id] = cell
			cell.Activated:Connect(function()
				if locked() then
					Sfx.play("error")
					return
				end
				if asking then
					-- Lo que ya está en su oferta no se pide.
					if (cell :: any).Select.Visible then
						Sfx.play("error")
						return
					end
					Remotes.TradeSuggest:FireServer("want", tab, id, 1)
					setAsking(false)
					return
				end
				Remotes.TradeOffer:FireServer(tab, id, if (cell :: any).Select.Visible then 0 else 1)
			end)
		end
		if tab == "amounts" then
			for order, entry in AMOUNTS do
				local owned = ownedOf(entry)
				if owned > 0 then
					local cell = amountStockCell(entry, owned, owner == nil)
					cell.LayoutOrder = order
					amountCells[entry] = cell
				end
			end
		elseif not owner then
			-- El bot de pruebas no tiene armas, armadura ni accesorios que pedir.
		elseif tab == "swords" then
			local worn = Stats.list(owner, "Loadout")
			for _, copy in Stats.swords(owner) do
				-- Las equipadas, las de la Bolsa de oro y las bloqueadas con el candado de la mochila no se pueden dar.
				if not copy.locked and not table.find(worn, copy.id) and not Stats.isDeposited(owner, copy.id) then
					add(swordCell(stock, copy), copy.id, -math.floor(math.log10(Stats.rarity(copy)) * 1000))
				end
			end
		elseif tab == "armor" then
			for _, piece in ArmorStats.pieces(owner) do
				add(armorCell(stock, piece), piece.id, -(piece.level * 100 + piece.quality))
			end
		elseif tab == "artifacts" then
			-- Una casilla por accesorio aunque tenga copias repetidas: un trato mueve una copia de cada uno.
			local seen = {}
			for _, index in Stats.list(owner, "Artifacts") do
				if not seen[index] then
					seen[index] = true
					add(artifactCell(stock, index), index, -index)
				end
			end
		end
		stockEmpty.Visible = next(stockCells) == nil and next(amountCells) == nil
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
	local mainButton = Ui.button(body, Lang.t(nil, "Accept"), Ui.COLORS.green)
	mainButton.Name = "Main"
	mainButton.AnchorPoint = Vector2.new(1, 1)
	mainButton.Position = UDim2.new(1, -12, 1, -12)
	mainButton.Size = UDim2.fromOffset(230, 60)
	mainButton.TextSize = 26
	local backButton = Ui.button(body, Lang.t(nil, "Back"), Ui.COLORS.orange)
	backButton.Name = "Back"
	backButton.AnchorPoint = Vector2.new(1, 1)
	backButton.Position = UDim2.new(1, -252, 1, -12)
	backButton.Size = UDim2.fromOffset(110, 60)
	backButton.TextSize = 20
	local cancelButton = Ui.button(body, Lang.t(nil, "Cancel"), Ui.COLORS.red)
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Position = UDim2.new(1, -372, 1, -12)
	cancelButton.Size = UDim2.fromOffset(110, 60)
	cancelButton.TextSize = 20
	-- "Pedir": bocadillo con puntos y el texto a su derecha.
	local suggestButton = Ui.button(body, Lang.t(nil, "Ask") .. " ", Ui.COLORS.blue)
	suggestButton.Name = "Ask"
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
		setAsking(not asking)
	end)

	-- Petición recibida: tarjeta sobre tu inventario (las dos ofertas siguen a la vista) con "Te está pidiendo X" y
	-- Aceptar o Ignorar. Aceptarla solo lo añade a tu oferta: el trato sigue pidiendo Aceptar y Confirmar.
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
	local acceptSuggest = Ui.button(card, Lang.t(nil, "Accept"), Ui.COLORS.green)
	acceptSuggest.Name = "Accept"
	acceptSuggest.AnchorPoint = Vector2.new(1, 0)
	acceptSuggest.Position = UDim2.new(1, -12, 0, 54)
	acceptSuggest.Size = UDim2.fromOffset(156, 50)
	acceptSuggest.TextSize = 24
	local ignoreSuggest = Ui.button(card, Lang.t(nil, "Ignore"), Ui.COLORS.red)
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

	-- Tu petición: una tira bajo el inventario (donde va la ayuda) con lo que has pedido y "Quitar".
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
	local removeSuggest = Ui.button(chip, Lang.t(nil, "Remove"), Ui.COLORS.red)
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
			chipRibbon.Text = REQUEST
			chipRibbon.BackgroundColor3 = Ui.COLORS.orange
			chipText.Text = if mineSuggest.ignored then Lang.t(nil, "Ignored") else suggestName(mineSuggest)
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
		ribbon.Text = REQUEST
		ribbon.BackgroundColor3 = Ui.COLORS.orange
		from.Text = Lang.t(nil, "{name} is asking you for:", { name = current.them.name })
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

	function setAsking(on: boolean)
		local was = asking
		asking = on and current ~= nil and current.state == "editing"
		Ui.setSelected(suggestButton, asking)
		suggestButton.BackgroundColor3 = if asking then GOLD else Ui.COLORS.blue
		if current then
			if current.state ~= "editing" then
				hint.Text = Lang.t(nil, "Offers locked.")
			elseif asking then
				hint.Text = Lang.t(nil, "{name}'s inventory: click what you want to ask for.", { name = current.them.name })
			else
				hint.Text = Lang.t(nil, "Click something of yours to offer it; in your offer, click it to remove it.")
			end
		end
		-- Solo al entrar o salir del modo: cada estado que llega pasa por aquí y no debe borrar lo que se está escribiendo.
		if was ~= asking then
			-- Cambia de quién es el inventario que se ve.
			if current then
				buildStock()
			end
		elseif current then
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
		panel.badge.Text = Lang.t(nil, if not done then (if confirming then "Not confirmed" else "Choosing...") elseif confirming then "CONFIRMED" else "ACCEPTED")
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
			place(amountCell(panel.grid, Lang.t(nil, "coins"), Ui.COLORS.coins, side.coins, "coins"), "coins", nil)
		end
		if side.gems > 0 then
			place(amountCell(panel.grid, Lang.t(nil, "gems"), Ui.COLORS.purple, side.gems, "gems"), "gems", nil)
		end
		for _, name in ITEM_KEYS do
			local amount = side.items[name]
			if amount and amount > 0 then
				place(amountCell(panel.grid, Lang.t(nil, Config.Items[name].name), Config.Items[name].color, amount, name), "items", name)
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
		paintOffer(mine, current.you, Lang.t(nil, "Your offer"))
		paintOffer(theirs, current.them, Lang.t(nil, "{name}'s offer", { name = current.them.name }))
		buildStock()
		local state = current.state
		if state ~= "editing" then
			closeMenu()
		end
		status.Text = STEPS[state] or ""
		status.TextColor3 = if state == "editing" then WHITE else GOLD
		-- Fuera del paso de elegir no hay peticiones; también pone el texto de ayuda.
		setAsking(asking and state == "editing")
		suggestButton.Visible = state == "editing"
		paintSuggests()
		backButton.Visible = state == "confirming"
		mainButton.Visible = state ~= "countdown"
		cancelButton.Text = Lang.t(nil, if state == "countdown" then "CANCEL!" else "Cancel")
		cancelButton.TextSize = if state == "countdown" then 28 else 20
		cancelButton.Size = UDim2.fromOffset(if state == "countdown" then 300 else 110, 60)
		cancelButton.Position = UDim2.new(1, if state == "countdown" then -12 else (if state == "confirming" then -372 else -252), 1, -12)
		if state == "editing" then
			mainButton.Text = Lang.t(nil, if current.you.accepted then "Undo accept" else "Accept")
			mainButton.BackgroundColor3 = if current.you.accepted then Ui.COLORS.orange else Ui.COLORS.green
		elseif state == "confirming" then
			mainButton.Text = Lang.t(nil, if current.you.confirmed then "Waiting..." else "CONFIRM")
			mainButton.BackgroundColor3 = if current.you.confirmed then Ui.COLORS.gray else Ui.COLORS.green
		end
		countdown.Visible = state == "countdown"
		if state ~= lastState then
			lastState = state
			if state == "confirming" then
				Sfx.play("rare")
				Ui.toast(Lang.t(nil, "Check the offer carefully before confirming"), GOLD)
			elseif state == "countdown" then
				Sfx.play("roll")
			end
		end
	end

	Remotes.TradeState.OnClientEvent:Connect(function(state)
		if state == nil then
			current = nil
			lastState = nil
			setAsking(false)
			closeMenu()
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
	-- El inventario que se ve sigue a su dueño: el tuyo siempre y el del otro jugador mientras estás pidiendo.
	local function watch(who: Player, theirs: boolean)
		return who.AttributeChanged:Connect(function(attribute)
			if current and window.Visible and asking == theirs and (attribute == "Swords" or attribute == "Armor" or attribute == "Artifacts" or attribute == "Loadout" or attribute == "Bag" or attribute == "Coins" or attribute == "Gems" or string.sub(attribute, 1, 5) == "Item_") then
				buildStock()
			end
		end)
	end
	watch(player, false)
	local watched: RBXScriptConnection? = nil
	local watchedId = 0
	Remotes.TradeState.OnClientEvent:Connect(function(state)
		local id = if state then state.them.userId else 0
		if id == watchedId then
			return
		end
		watchedId = id
		if watched then
			watched:Disconnect()
			watched = nil
		end
		local other = Players:GetPlayerByUserId(id)
		if other then
			watched = watch(other, true)
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
