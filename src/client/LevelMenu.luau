-- Subir de nivel las armas con gemas (pedido por el usuario; números en Config.WeaponLevel, cuentas en shared/WeaponLevel
-- y el cobro en server/WeaponLevels). Ventana `Hud.LevelUp`, que abre el botón `Body.Swords.Level` de la mochila: a la
-- izquierda todas las armas, de más a menos daño (`Body.Stock.Sword<id>`, pulsar una la elige), y a la derecha la elegida
-- (`Body.Info`): su casilla, su nivel con la barra, el daño ahora y con el siguiente nivel, lo que cuesta y los botones
-- `Body.Info.Buttons.Up1`, `Up10` y `UpMax` (sube los que pueda pagar, hasta esa cantidad).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local WeaponLevel = require(ReplicatedStorage.Shared.WeaponLevel)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponCell = require(script.Parent.WeaponCell)

local LevelMenu = {}

local player = Players.LocalPlayer
local MAX = Config.WeaponLevel.MaxLevel
local GOLD = Color3.fromRGB(255, 215, 90)
local BAR_FROM, BAR_TO = Color3.fromRGB(120, 235, 90), Color3.fromRGB(40, 170, 60)
local ACCENT = Color3.fromRGB(170, 90, 255)

local window: Frame
local selected: number? = nil -- id de la copia elegida
local refresh: () -> ()

function LevelMenu.open(id: number?)
	selected = id
	Ui.toggle("LevelUp")
end

-- Texto que crece un momento (al subir de nivel).
local function pop(item: GuiObject)
	local scale = item:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = item
	scale.Scale = 1.25
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function textLimit(label: TextLabel, max: number, min: number)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min
	limit.Parent = label
end

function LevelMenu.start()
	local body
	window, body = Ui.window("LevelUp", Lang.t(nil, "Upgrade weapons"), Vector2.new(760, 560))

	-- Armas -----------------------------------------------------------------------------------
	local stock = Instance.new("ScrollingFrame")
	stock.Name = "Stock"
	stock.Position = UDim2.fromScale(0.02, 0.025)
	stock.Size = UDim2.fromScale(0.55, 0.95)
	stock.BackgroundColor3 = Ui.COLORS.dark
	stock.BackgroundTransparency = 0.55
	stock.BorderSizePixel = 0
	stock.ScrollBarThickness = 6
	stock.CanvasSize = UDim2.new()
	stock.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stock.Parent = body
	Ui.round(stock, 10)
	-- Cuatro columnas que llenan el ancho de la lista (casillas cuadradas).
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.21, 0.21)
	grid.CellPadding = UDim2.fromScale(0.03, 0.03)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = stock
	local cellShape = Instance.new("UIAspectRatioConstraint")
	cellShape.AspectRatio = 1
	cellShape.Parent = grid
	local padding = Instance.new("UIPadding")
	-- Margen para lo que sobresale de las casillas (crecen con el ratón y las raras llevan halo).
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = stock

	-- La elegida -----------------------------------------------------------------------------
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Position = UDim2.fromScale(0.59, 0.025)
	info.Size = UDim2.fromScale(0.39, 0.95)
	info.Parent = body
	Ui.round(info, 12)
	Ui.panel(info, Color3.fromRGB(40, 44, 82), ACCENT)
	Ui.stroke(info, Color3.new(0, 0, 0), 3)

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.AnchorPoint = Vector2.new(0.5, 0)
	preview.Position = UDim2.fromScale(0.5, 0.04)
	preview.Size = UDim2.fromScale(0.46, 0.24)
	preview.BackgroundTransparency = 1
	preview.Parent = info
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = preview

	local function line(name: string, y: number, height: number, max: number): TextLabel
		local label = Ui.label(info, max)
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(0.92, height)
		label.RichText = true
		label.ZIndex = 3
		textLimit(label, max, 10)
		return label
	end
	local title = line("Name", 0.3, 0.07, 24)
	local levelText = line("Level", 0.38, 0.08, 30)
	levelText.TextColor3 = GOLD

	-- Barra del nivel.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.475)
	bar.Size = UDim2.fromScale(0.84, 0.04)
	bar.BackgroundColor3 = Ui.COLORS.dark
	bar.BorderSizePixel = 0
	bar.ZIndex = 3
	bar.Parent = info
	Ui.round(bar, 8)
	Ui.stroke(bar, Color3.new(0, 0, 0), 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.ZIndex = 4
	fill.Parent = bar
	Ui.round(fill, 8)
	Ui.gradient(fill, BAR_FROM, BAR_TO, 90)

	local damage = line("Damage", 0.54, 0.12, 24)

	-- Precio del siguiente nivel.
	local price = Instance.new("Frame")
	price.Name = "Cost"
	price.AnchorPoint = Vector2.new(0.5, 0)
	price.Position = UDim2.fromScale(0.5, 0.685)
	price.Size = UDim2.fromScale(0.72, 0.085)
	price.ZIndex = 3
	price.Parent = info
	Ui.pill(price, Color3.fromRGB(140, 70, 220))
	Ui.stroke(price, Color3.new(0, 0, 0), 3)
	local gemBox = Instance.new("Frame")
	gemBox.Name = "Gem"
	gemBox.AnchorPoint = Vector2.new(0, 0.5)
	gemBox.Position = UDim2.fromScale(0.04, 0.5)
	gemBox.Size = UDim2.fromScale(0.3, 1.25)
	gemBox.BackgroundTransparency = 1
	gemBox.ZIndex = 4
	gemBox.Parent = price
	local gemAspect = Instance.new("UIAspectRatioConstraint")
	gemAspect.AspectRatio = 1
	gemAspect.Parent = gemBox
	Ui.image(gemBox, "gemas").ZIndex = 4
	local cost = Ui.label(price, 24)
	cost.Name = "Amount"
	cost.Position = UDim2.fromScale(0.3, 0)
	cost.Size = UDim2.fromScale(0.64, 1)
	cost.ZIndex = 4
	textLimit(cost, 24, 10)

	-- Botones.
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(0.5, 1)
	buttons.Position = UDim2.fromScale(0.5, 0.97)
	buttons.Size = UDim2.fromScale(0.92, 0.15)
	buttons.BackgroundTransparency = 1
	buttons.Parent = info
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0.04, 0)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = buttons
	local ups = {}
	for order, spec in { { "Up1", "+1", Ui.COLORS.green, 1 }, { "Up10", "+10", Ui.COLORS.blue, 10 }, { "UpMax", "Max", Ui.COLORS.purple, MAX } } do
		local button = Ui.button(buttons, Lang.t(nil, spec[2]), spec[3])
		button.Name = spec[1]
		button.Size = UDim2.fromScale(0.3, 1)
		button.TextSize = 32
		button.LayoutOrder = order
		button:SetAttribute("Base", spec[3])
		button.Activated:Connect(function()
			if not selected then
				return
			end
			Sfx.play("click", 0.5)
			Remotes.LevelSword:FireServer(selected, spec[4])
		end)
		ups[spec[1]] = button
	end
	Ui.sparkle(ups.UpMax)

	-- Casillas: se rehacen solo las que cambian (al subir de nivel cambia el atributo Swords entero).
	local cells = {} -- [id] = { cell, mark = cómo era la copia al hacerla }
	local shown = nil -- casilla grande de la elegida
	local shownMark = nil
	local lastLevel = {} -- [id] = nivel que se enseñaba (para el efecto al subir)
	local BIG = { owner = false } -- la casilla grande, sin la "E"

	local function paintInfo(copy)
		if shown and shownMark ~= (copy and WeaponCell.key(copy, BIG)) then
			shown:Destroy()
			shown = nil
		end
		if not copy then
			title.Text = Lang.t(nil, "Pick a weapon")
			levelText.Text, damage.Text, cost.Text = "", "", ""
			gemBox.Visible = false
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		if not shown then
			shown = WeaponCell.create(preview, copy, BIG)
			shown.Name = "Sword"
			shown.Size = UDim2.fromScale(1, 1)
			shownMark = WeaponCell.key(copy, BIG)
		end
		local tier = Rarity.tier(Stats.rarity(copy))
		local level = copy.level or 0
		title.Text = Ui.rarityText(Lang.t(nil, Config.Swords[copy.sword].name), tier.color, table.find(Config.RarityTiers, tier))
		levelText.Text = Lang.t(nil, "Level {n}/{max}", { n = level, max = MAX })
		fill.Size = UDim2.fromScale(level / MAX, 1)
		local now = Stats.swordDamage(copy)
		local full = level >= MAX
		gemBox.Visible = not full
		if full then
			damage.Text = `<font color="#ff8264">{Lang.t(nil, "Damage")}</font>\n{Format.multiplier(now)}`
			cost.Text = Lang.t(nil, "Max level")
		else
			local nextDamage = now * Config.WeaponLevel.PerLevel
			damage.Text = `<font color="#ff8264">{Lang.t(nil, "Damage")}</font>\n{Format.multiplier(now)} → <font color="#ffd75a">{Format.multiplier(nextDamage)}</font>`
			cost.Text = Format.short(WeaponLevel.cost(copy, level))
		end
		-- Botones en gris si no llega ni para uno.
		local gems = player:GetAttribute("Gems") or 0
		local canBuy = not full and WeaponLevel.affordable(copy, gems, 1) > 0
		for _, button in ups do
			button.BackgroundColor3 = if canBuy then button:GetAttribute("Base") else Ui.COLORS.gray
		end
		cost.TextColor3 = if full or canBuy then Color3.new(1, 1, 1) else Color3.fromRGB(255, 140, 140)
		if lastLevel[copy.id] and level > lastLevel[copy.id] then
			Sfx.play("buy")
			pop(levelText)
			pop(damage)
		end
		lastLevel[copy.id] = level
	end

	refresh = function()
		if not window.Visible then
			return
		end
		local copies = table.clone(Stats.swords(player))
		table.sort(copies, function(a, b)
			local left, right = Stats.swordDamage(a), Stats.swordDamage(b)
			if left ~= right then
				return left > right
			end
			return a.id < b.id
		end)
		local chosen = nil
		for _, copy in copies do
			if copy.id == selected then
				chosen = copy
			end
		end
		if not chosen then
			chosen = copies[1]
			selected = chosen and chosen.id
		end
		local alive = {}
		for position, copy in copies do
			alive[copy.id] = true
			local signature = WeaponCell.key(copy)
			local entry = cells[copy.id]
			if entry and entry.mark ~= signature then
				entry.cell:Destroy()
				entry = nil
			end
			if not entry then
				local cell = WeaponCell.create(stock, copy)
				cell.Name = "Sword" .. copy.id
				cell.Activated:Connect(function()
					selected = copy.id
					Sfx.play("click", 0.5)
					refresh()
				end)
				entry = { cell = cell, mark = signature }
				cells[copy.id] = entry
			end
			entry.cell.LayoutOrder = position
			local select = entry.cell:FindFirstChild("Select") :: GuiObject?
			if select then
				select.Visible = copy.id == selected
			end
		end
		for id, entry in cells do
			if not alive[id] then
				entry.cell:Destroy()
				cells[id] = nil
			end
		end
		paintInfo(chosen)
	end

	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible then
			-- Al cerrar se suelta todo (las vistas 3D cuestan) y se olvidan los niveles vistos.
			for _, entry in cells do
				entry.cell:Destroy()
			end
			cells = {}
			lastLevel = {}
			if shown then
				shown:Destroy()
				shown = nil
			end
		end
		refresh()
	end)
	player:GetAttributeChangedSignal("Swords"):Connect(refresh)
	player:GetAttributeChangedSignal("Loadout"):Connect(refresh)
	player:GetAttributeChangedSignal("Gems"):Connect(refresh)
end

return LevelMenu
