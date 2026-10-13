-- Selección múltiple y confirmación de venta. El servidor comprueba de nuevo cada copia.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local window, refresh, paint
local selected, cells = {}, {}
local confirming = false

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
			cell.Activated:Connect(function()
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
