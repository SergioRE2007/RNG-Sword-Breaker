-- Índice de armas: ventana `Hud.Index` (botón "Índice" del menú) con todas las armas del juego, su probabilidad y
-- su daño. A la izquierda de la ventana hay un botón por tamaño y a la derecha uno por metal: eligen la combinación
-- que se enseña. Las que al jugador le han salido con esa combinación exacta van con el borde de su rareza; las
-- demás, más oscuras pero con sus números a la vista. Lo descubierto se lee del atributo `Index` (server/Index).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local IndexInfo = require(ReplicatedStorage.Shared.IndexInfo)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local Index = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local CELL = Vector2.new(132, 170) -- más alta que ancha: nombre arriba, arma en medio y los dos números abajo
local SIDE = Vector2.new(104, 58) -- botones de tamaño y de metal, pegados por fuera a los lados de la ventana
local NEUTRAL = Ui.COLORS.gray -- botones "Normal" y "Sin metal"
local LOCKED = Color3.fromRGB(78, 80, 94) -- casilla sin descubrir
local LOCKED_MODEL = Color3.fromRGB(105, 105, 122) -- tinte de su arma
local LOCKED_NAME = Color3.fromRGB(165, 171, 192)

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local function limit(label: TextLabel, max: number, min: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = max
	constraint.MinTextSize = min
	constraint.Parent = label
end

-- Rebote de la casilla que se acaba de descubrir con la ventana abierta.
local function popIn(cell: GuiObject)
	if Performance.get() then return end -- modo rendimiento
	local scale = cell:FindFirstChild("PressScale") :: UIScale?
	if scale then
		scale.Scale = 0.3
		TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Columna de botones por fuera de la ventana, a un lado: cartelito con el título y los botones debajo.
local function column(window: GuiObject, name: string, heading: string, right: boolean): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(if right then 0 else 1, 0)
	holder.Position = if right then UDim2.new(1, 14, 0, 62) else UDim2.fromOffset(-14, 62)
	holder.Size = UDim2.fromOffset(SIDE.X, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = window

	-- (El texto va en una etiqueta de dentro: el degradado del relieve teñiría el de la propia pieza.)
	local title = Instance.new("Frame")
	title.Name = "Heading"
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Parent = holder
	Ui.pill(title, Color3.fromRGB(70, 62, 120), 9)
	local titleText = Ui.label(title, 15)
	titleText.Size = UDim2.fromScale(1, 1)
	titleText.Text = heading
	titleText.ZIndex = 2

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, 34)
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = holder
	-- En rejilla de una columna y no en lista: así el botón que crece al pasar el ratón no empuja a los demás.
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(SIDE.X, SIDE.Y)
	layout.CellPadding = UDim2.fromOffset(0, 8)
	layout.FillDirectionMaxCells = 1
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- Botón de un metal o de un tamaño: su nombre y, debajo, su "1 entre N".
local function sideButton(list: Frame, name: string, order: number, title: string, sub: string, color: Color3): TextButton
	local button = Ui.button(list, "", color)
	button.Name = name
	button.LayoutOrder = order
	local label = Ui.label(button, 17)
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 5)
	label.Size = UDim2.new(1, -10, 0, 24)
	label.Text = title
	limit(label, 17, 10)
	local odds = Ui.label(button, 12)
	odds.Name = "Odds"
	odds.AnchorPoint = Vector2.new(0.5, 1)
	odds.Position = UDim2.new(0.5, 0, 1, -10) -- por encima del labio del botón
	odds.Size = UDim2.new(1, -8, 0, 15)
	odds.Text = sub
	return button
end

function Index.start()
	local window, body = Ui.window("Index", "Índice", Vector2.new(780, 590), function(parent)
		Ui.image(parent, "espada") -- logo provisional (el mismo que el botón del menú)
	end)

	local metal, size = 0, 0 -- lo elegido en los botones: 0 = sin metal / tamaño normal
	local cells = {} -- [arma] = { cell, view, unlocked }: lo que enseña ahora su casilla
	local render

	-- Barra de arriba: qué combinación se está viendo y cuántas se llevan descubiertas.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.Position = UDim2.fromOffset(8, 6)
	top.Size = UDim2.new(1, -16, 0, 44)
	top.BackgroundTransparency = 1
	top.Parent = body

	local viewLabel = Ui.label(top, 24)
	viewLabel.Name = "View"
	viewLabel.Position = UDim2.fromOffset(6, 0)
	viewLabel.Size = UDim2.new(1, -390, 1, 0)
	viewLabel.TextXAlignment = Enum.TextXAlignment.Left
	limit(viewLabel, 24, 14)

	local countPill = Instance.new("Frame")
	countPill.Name = "Count"
	countPill.AnchorPoint = Vector2.new(1, 0.5)
	countPill.Position = UDim2.new(1, -4, 0.5, 0)
	countPill.Size = UDim2.fromOffset(200, 36)
	countPill.Parent = top
	Ui.pill(countPill, Ui.COLORS.blue, 10)
	local countLabel = Ui.label(countPill, 19)
	countLabel.Name = "Text"
	countLabel.Size = UDim2.fromScale(1, 1)
	countLabel.ZIndex = 2

	local totalLabel = Ui.label(top, 16)
	totalLabel.Name = "Total"
	totalLabel.AnchorPoint = Vector2.new(1, 0.5)
	totalLabel.Position = UDim2.new(1, -216, 0.5, 0)
	totalLabel.Size = UDim2.fromOffset(170, 30)
	totalLabel.TextXAlignment = Enum.TextXAlignment.Right

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(8, 54)
	grid.Size = UDim2.new(1, -16, 1, -62)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(14, 16) -- los marcos gruesos y el halo ocupan parte del hueco
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local padding = Instance.new("UIPadding")
	-- Hueco para el halo de las casillas raras, que sobresale del borde.
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = grid

	-- Botones de los lados: tamaños a la izquierda y metales a la derecha (pedido por el usuario).
	local sizeButtons, metalButtons = {}, {}
	local function pick(isMetal: boolean, index: number)
		if isMetal then
			metal = index
		else
			size = index
		end
		grid.CanvasPosition = Vector2.zero
		render()
	end
	local sizeList = column(window, "Sizes", "Tamaño", false)
	local metalList = column(window, "Metals", "Metal", true)
	sizeButtons[0] = sideButton(sizeList, "Size_0", 0, "Normal", "Base", NEUTRAL)
	for index, entry in Config.Sizes do
		sizeButtons[index] = sideButton(sizeList, "Size_" .. index, index, entry.name, "1 entre " .. Format.short(entry.odds), entry.color)
	end
	metalButtons[0] = sideButton(metalList, "Metal_0", 0, "Sin metal", "Base", NEUTRAL)
	for index, entry in Config.Metals do
		metalButtons[index] = sideButton(metalList, "Metal_" .. index, index, entry.name, "1 entre " .. Format.short(entry.odds), entry.color)
	end
	for index, button in sizeButtons do
		button.Activated:Connect(function()
			pick(false, index)
		end)
	end
	for index, button in metalButtons do
		button.Activated:Connect(function()
			pick(true, index)
		end)
	end

	-- Cartel de una casilla: nombre completo, rareza, tipo, daño y de dónde sale su probabilidad.
	local function tipText(sword: number, tipMetal: number, tipSize: number, unlocked: boolean): (string, Color3)
		local entry = Config.Swords[sword]
		local copy = { sword = sword, metal = tipMetal, size = tipSize }
		local rarity = Stats.rarity(copy)
		local tier = Rarity.tier(rarity)
		local lines = {
			Permanent.name(sword, tipMetal, tipSize),
			`<font color="{hex(tier.color)}">{tier.name}</font> · {Config.WeaponKinds[entry.kind or "sword"].name}`,
			`Daño {Format.multiplier(Stats.swordDamage(copy))}`,
		}
		local metalDef, sizeDef = Permanent.metal(copy), Permanent.size(copy)
		if not entry.rarity then
			table.insert(lines, `<font color="{Ui.SOFT}">Espada inicial</font>`)
		elseif metalDef or sizeDef then
			table.insert(lines, `<font color="{Ui.SOFT}">Arma: 1 entre {Format.short(entry.rarity)}</font>`)
			if metalDef then
				table.insert(lines, `<font color="{hex(metalDef.color)}">{metalDef.name}:</font> <font color="{Ui.SOFT}">1 entre {Format.short(metalDef.odds)} · x{Format.multiplier(Permanent.damage(metalDef.odds))} daño</font>`)
			end
			if sizeDef then
				table.insert(lines, `<font color="{hex(sizeDef.color)}">{sizeDef.name}:</font> <font color="{Ui.SOFT}">1 entre {Format.short(sizeDef.odds)} · x{Format.multiplier(Permanent.damage(sizeDef.odds))} daño</font>`)
			end
			table.insert(lines, `En total: 1 entre {Format.short(rarity)}`)
		else
			table.insert(lines, `<font color="{Ui.SOFT}">1 entre {Format.short(rarity)}</font>`)
		end
		table.insert(lines, if unlocked then `<font color="#6fe07a">Descubierta</font>` else `<font color="#ff8a8a">Sin descubrir</font>`)
		return table.concat(lines, "\n"), if unlocked then tier.color else LOCKED
	end

	local function buildCell(sword: number, unlocked: boolean): TextButton
		local entry = Config.Swords[sword]
		local cellMetal, cellSize = metal, size
		local copy = { sword = sword, metal = cellMetal, size = cellSize }
		local rarity = Stats.rarity(copy)
		local tier = Rarity.tier(rarity)
		-- Sin descubrir: gris y sin el marco animado de su rareza.
		local cell = Ui.cell(grid, if unlocked then tier.color else LOCKED, if unlocked then table.find(Config.RarityTiers, tier) else nil)
		cell.Name = "Weapon" .. sword

		-- El arma, en un cuadrado centrado un poco por encima del medio (la casilla no es cuadrada).
		local preview = WeaponPreview.attach(cell, sword, tier.color, cellMetal)
		local glow = cell:FindFirstChild("Glow") :: Frame
		preview.Size = UDim2.fromScale(0.86, 0.86)
		glow.Size = UDim2.fromScale(0.66, 0.66)
		for _, item in { preview, glow } do
			item.Position = UDim2.fromScale(0.5, 0.46)
			Instance.new("UIAspectRatioConstraint").Parent = item
		end
		if not unlocked then
			preview.ImageColor3 = LOCKED_MODEL
			glow.BackgroundTransparency = 0.85
		end

		local name = Ui.label(cell, 14)
		name.Name = "Title"
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 6)
		name.Size = UDim2.new(1, -14, 0, 30)
		name.TextWrapped = true
		name.TextColor3 = if unlocked then WHITE else LOCKED_NAME
		name.Text = entry.name
		name.ZIndex = 3
		limit(name, 14, 9)

		-- Los dos números se leen igual esté o no descubierta.
		local odds = Ui.label(cell, 14)
		odds.Name = "Odds"
		odds.AnchorPoint = Vector2.new(0.5, 1)
		odds.Position = UDim2.new(0.5, 0, 1, -28)
		odds.Size = UDim2.new(1, -12, 0, 17)
		odds.TextColor3 = Color3.fromRGB(205, 212, 232)
		odds.Text = if entry.rarity then "1 entre " .. Format.short(rarity) else "Inicial"
		odds.ZIndex = 3
		limit(odds, 14, 9)

		local damage = Ui.label(cell, 20)
		damage.Name = "Damage"
		damage.AnchorPoint = Vector2.new(0.5, 1)
		damage.Position = UDim2.new(0.5, 0, 1, -5)
		damage.Size = UDim2.new(1, -12, 0, 23)
		damage.Text = "Daño " .. Format.multiplier(Stats.swordDamage(copy))
		damage.ZIndex = 3
		limit(damage, 20, 10)
		if unlocked then
			Ui.gradient(damage, WHITE, tier.color:Lerp(WHITE, 0.45), 90)
		end

		Ui.tip(cell, function()
			return tipText(sword, cellMetal, cellSize, unlocked)
		end, true)
		return cell
	end

	-- Deja la rejilla como toca tocando solo las casillas que cambian (cada una lleva su vista 3D): todas al
	-- cambiar de metal o de tamaño, y solo la recién descubierta cuando llega una tirada.
	render = function()
		local found = IndexInfo.parse(player:GetAttribute("Index"))
		local list = IndexInfo.swords(metal, size)
		local view = `{metal}:{size}`
		local listed = {}
		local unlockedHere = 0
		for position, sword in list do
			listed[sword] = true
			local unlocked = found[IndexInfo.code(sword, metal, size)] == true
			if unlocked then
				unlockedHere += 1
			end
			local old = cells[sword]
			if old and old.view == view and old.unlocked == unlocked then
				continue
			end
			local fresh = old ~= nil and old.view == view and unlocked
			if old then
				old.cell:Destroy()
			end
			local cell = buildCell(sword, unlocked)
			cell.LayoutOrder = position
			cells[sword] = { cell = cell, view = view, unlocked = unlocked }
			if fresh then
				popIn(cell)
			end
		end
		for sword, shown in cells do
			if not listed[sword] then
				shown.cell:Destroy()
				cells[sword] = nil
			end
		end

		local metalDef, sizeDef = Config.Metals[metal], Config.Sizes[size]
		viewLabel.Text = `{if metalDef then `<font color="{hex(metalDef.color)}">{metalDef.name}</font>` else "Sin metal"}  ·  {if sizeDef then `<font color="{hex(sizeDef.color)}">{sizeDef.name}</font>` else "Tamaño normal"}`
		countLabel.Text = `Descubiertas {unlockedHere}/{#list}`
		local all = 0
		for _ in found do
			all += 1
		end
		totalLabel.Text = `<font color="{Ui.SOFT}">Índice entero</font> {all}/{IndexInfo.total()}`
		for index, button in sizeButtons do
			Ui.setSelected(button, index == size)
		end
		for index, button in metalButtons do
			Ui.setSelected(button, index == metal)
		end
	end

	-- Las casillas se crean la primera vez que se abre; cerrada no se rehace nada.
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			render()
		end
	end)
	player:GetAttributeChangedSignal("Index"):Connect(function()
		if window.Visible then
			render()
		end
	end)
end

return Index
