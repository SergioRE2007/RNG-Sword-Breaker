-- Selección múltiple y confirmación de venta. El servidor comprueba de nuevo cada copia.
-- Arrastrar (pedido por el usuario): apretar sobre un arma y pasar por encima de otras las elige todas (o las quita,
-- si la primera ya estaba elegida), como una selección con el ratón; cerca del borde de la lista, la lista se desplaza.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local SellMenu = {}
local player = Players.LocalPlayer
local window, refresh, paint, startPaint
local selected, cells = {}, {}
local confirming = false
local painting: boolean? = nil -- mientras se arrastra: true = ir eligiendo, false = ir quitando
local pointer: Vector2? = nil -- dónde está el dedo o el ratón, en las mismas coordenadas que AbsolutePosition
local EDGE = 40 -- píxeles junto al borde de la lista en los que, arrastrando, se desplaza
local EDGE_SPEED = 700 -- píxeles por segundo que se desplaza entonces

-- X roja y medio transparente encima de las armas elegidas (pedido por el usuario: es un menú de vender, que se vea
-- que se van). Dos barras cruzadas, por encima de todo lo de la casilla (vista 3D, daño, rasgo y grado: hasta 4).
local MARK_COLOR = Color3.fromRGB(235, 45, 55)
local MARK_ALPHA = 0.4 -- transparencia de la X
local function sellMark(cell: GuiObject): Frame
	local mark = Instance.new("Frame")
	mark.Name = "SellMark"
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Visible = false
	mark.ZIndex = 5
	mark.Parent = cell
	for _, turn in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.95, 0.15)
		bar.Rotation = turn
		bar.BackgroundColor3 = MARK_COLOR
		bar.BackgroundTransparency = MARK_ALPHA
		bar.BorderSizePixel = 0
		bar.ZIndex = 5
		bar.Parent = mark
		Ui.round(bar, 6)
	end
	return mark
end

function SellMenu.open(id: number?)
	selected = {}
	confirming = false
	if id and not Stats.isEquipped(player, id) and not Stats.isDeposited(player, id) then selected[id] = true end
	Ui.toggle("SellMenu")
end

function SellMenu.start()
	local body
	window, body = Ui.window("SellMenu", Lang.t(nil, "Sell weapons"), Vector2.new(740, 560))
	local summary = Ui.label(body, 22)
	summary.Size = UDim2.fromScale(1, 0.09)
	summary.TextWrapped = true
	local stock = Instance.new("ScrollingFrame")
	stock.Name = "Stock"
	stock.Position = UDim2.fromScale(0.02, 0.11)
	stock.Size = UDim2.fromScale(0.96, 0.68)
	stock.BackgroundTransparency = 1
	stock.BorderSizePixel = 0
	stock.ScrollBarThickness = 6
	stock.CanvasSize = UDim2.new()
	stock.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stock.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(100, 100)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stock
	local padding = Instance.new("UIPadding")
	-- Hueco para lo que sobresale de las casillas (crecen al pasar el ratón y las raras llevan halo): con menos, el borde
	-- de la fila de arriba se cortaba contra el de la lista.
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = stock
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Position = UDim2.fromScale(0.02, 0.83)
	actions.Size = UDim2.fromScale(0.96, 0.15)
	actions.BackgroundTransparency = 1
	actions.Parent = body
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0.02, 0)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = actions
	local buttons = {}
	-- Solo dos botones (pedido por el usuario): quitar la selección es pulsar las casillas y salir, la X de la ventana.
	for order, spec in { { "SelectAll", Lang.t(nil, "Select all"), Ui.COLORS.blue }, { "Sell", Lang.t(nil, "Sell selected"), Ui.COLORS.red } } do
		local button = Ui.button(actions, spec[2], spec[3])
		button.Name = spec[1]
		button.Size = UDim2.fromScale(0.49, 1)
		button.LayoutOrder = order
		button.TextWrapped = true
		button.TextSize = 20
		buttons[spec[1]] = button
	end
	-- Arrastrar para elegir ---------------------------------------------------------------
	local function screenPoint(input: InputObject): Vector2
		-- Mismo origen que AbsolutePosition (debajo de la franja de arriba de Roblox, aunque el Hud la tape: su
		-- AbsolutePosition es (0, -58)), así que no hay que sumarle nada.
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	local function inside(object: GuiObject, point: Vector2): boolean
		local corner, size = object.AbsolutePosition, object.AbsoluteSize
		return point.X >= corner.X and point.Y >= corner.Y and point.X <= corner.X + size.X and point.Y <= corner.Y + size.Y
	end
	-- Pone la casilla que haya bajo el puntero como toque (solo las que se ven dentro de la lista). Por encima o por
	-- debajo de la lista cuenta su borde, que es lo que va pasando mientras se desplaza sola.
	local function paintUnder()
		if painting == nil or not pointer then
			return
		end
		local top = stock.AbsolutePosition.Y
		local point = Vector2.new(pointer.X, math.clamp(pointer.Y, top + 2, top + stock.AbsoluteSize.Y - 2))
		if not inside(stock, point) then
			return
		end
		for id, cell in cells do
			if inside(cell, point) then
				local want = if painting then true else nil
				if selected[id] ~= want then
					selected[id] = want
					confirming = false
					Sfx.play("click", 0.35)
					paint()
				end
				return
			end
		end
	end
	local function stopPaint()
		painting, pointer = nil, nil
		stock.ScrollingEnabled = true
	end
	function startPaint(id: number, input: InputObject)
		painting = not selected[id]
		pointer = screenPoint(input)
		-- En pantallas táctiles el dedo arrastra la selección, no la lista (se desplaza sola en los bordes).
		stock.ScrollingEnabled = false
		paintUnder()
	end
	UserInputService.InputChanged:Connect(function(input)
		if painting ~= nil and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			pointer = screenPoint(input)
			paintUnder()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			stopPaint()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if painting == nil or not pointer then
			return
		end
		if not window.Visible then
			stopPaint()
			return
		end
		-- Junto al borde de arriba o de abajo de la lista, se desplaza hacia ese lado y sigue eligiendo.
		local top, bottom = stock.AbsolutePosition.Y, stock.AbsolutePosition.Y + stock.AbsoluteSize.Y
		local direction = if pointer.Y < top + EDGE then -1 elseif pointer.Y > bottom - EDGE then 1 else 0
		if direction ~= 0 then
			local limit = math.max(0, stock.AbsoluteCanvasSize.Y - stock.AbsoluteWindowSize.Y)
			local y = math.clamp(stock.CanvasPosition.Y + direction * EDGE_SPEED * dt, 0, limit)
			if y ~= stock.CanvasPosition.Y then
				stock.CanvasPosition = Vector2.new(stock.CanvasPosition.X, y)
				paintUnder()
			end
		end
	end)

	paint = function()
		local count = 0
		for id, cell in cells do
			-- Elegida: fondo rojo y la X, sin el borde blanco de seleccionado (pedido por el usuario).
			cell.SellMark.Visible = selected[id] == true
			local base = if selected[id] then MARK_COLOR else cell:GetAttribute("Base")
			cell.BackgroundColor3 = base
			local glow = cell:FindFirstChild("Glow") :: Frame? -- el círculo de luz de WeaponPreview, detrás del arma
			if glow then
				glow.BackgroundColor3 = base
			end
			if selected[id] then count += 1 end
		end
		if count == 0 then confirming = false end
		summary.Text = Lang.t(nil, if confirming then "Confirm sale? {count} · +{gems} gems" else "Selected: {count} · +{gems} gems", { count = count, gems = Format.short(count * Config.Gacha.SellValue) })
		buttons.Sell.Text = if confirming then Lang.t(nil, "Confirm sale") else Lang.t(nil, "Sell selected")
		buttons.Sell.Interactable = count > 0
	end
	refresh = function()
		if not window.Visible then return end
		confirming = false
		for _, cell in cells do cell:Destroy() end
		cells = {}
		local eligible = {}
		-- Pedido por el usuario: mismo orden (de más a menos daño) y misma casilla y cartel que en la mochila; antes
		-- iban por orden de llegada y con otra información. Backpack se pide aquí porque él ya pide este módulo.
		local swordCell = (require(script.Parent.Backpack) :: any).swordCell
		local copies = table.clone(Stats.swords(player))
		table.sort(copies, function(a, b)
			local left, right = Stats.swordDamage(a), Stats.swordDamage(b)
			if left ~= right then
				return left > right
			end
			return a.id < b.id
		end)
		for position, copy in copies do
			-- Las bloqueadas con el candado de la mochila no salen (el servidor tampoco las vende).
			if copy.locked or Stats.isEquipped(player, copy.id) or Stats.isDeposited(player, copy.id) then continue end
			eligible[copy.id] = true
			local tier = Rarity.tier(Stats.rarity(copy))
			local cell = swordCell(stock, copy, false, false)
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = position
			cell:SetAttribute("Base", tier.color) -- color de su fondo sin elegir
			sellMark(cell)
			cell.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					startPaint(copy.id, input)
				end
			end)
			cell.Activated:Connect(function(input)
				-- Con mando o teclado no hay arrastre: pulsar la cambia, como antes.
				if input and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					return
				end
				confirming = false
				selected[copy.id] = if selected[copy.id] then nil else true
				paint()
			end)
			cells[copy.id] = cell
		end
		for id in selected do
			if not eligible[id] then selected[id] = nil end
		end
		paint()
	end
	buttons.SelectAll.Activated:Connect(function()
		confirming = false
		for id in cells do selected[id] = true end
		paint()
	end)
	buttons.Sell.Activated:Connect(function()
		if not confirming then
			confirming = true
			paint()
			return
		end
		local ids = {}
		for id in selected do table.insert(ids, id) end
		Sfx.play("sell")
		Remotes.SellSwords:FireServer(ids)
		selected = {}
		confirming = false
		paint()
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	player:GetAttributeChangedSignal("Swords"):Connect(refresh)
	player:GetAttributeChangedSignal("Loadout"):Connect(refresh)
end

return SellMenu
