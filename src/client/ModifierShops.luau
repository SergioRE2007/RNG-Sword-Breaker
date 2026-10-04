-- Ventanas de las tiendas de modificadores del hub (Rasgos y Grados). Se abren con la tecla de
-- interacción junto a cada puesto y se cierran al alejarse. Las armas se ven en 3D con
-- WeaponPreview (como en la mochila); el resultado de cada tirada llega por ModifierRolled. A la izquierda, la espada elegida
-- (se cambia pulsando su casilla), el modificador que tiene, lo que cuesta y los botones
-- Tirar / Auto / "Parar con..." (con qué resultados se para la tirada automática). A la derecha,
-- todos los resultados posibles, del más raro al más común, con su % y su efecto.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Backpack = require(script.Parent.Backpack)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local ModifierShops = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SIZE = Vector2.new(1000, 540)
local LEFT = 520 -- ancho de la parte izquierda del cuerpo
local AUTO_DELAY = 0.45 -- segundos entre tiradas automáticas
local CLOSE_DISTANCE = 30 -- se cierra al alejarse del puesto

local random = Random.new()

local function rainbowColors(): ColorSequence
	local keys = {}
	for step = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(step / 6, Color3.fromHSV(step / 6, 0.6, 1)))
	end
	return ColorSequence.new(keys)
end

-- Degradados arcoíris de las entradas especiales: giran sin parar (los mueve ModifierShops.start).
-- (Tablas normales: en una tabla débil Luau suelta las instancias aunque sigan en pantalla.)
local spinning = {}
-- Bordes de las especiales sin arcoíris: laten (los mueve ModifierShops.start).
local pulsing = {}
-- Efectos de las filas de la lista (los mueve ModifierShops.start):
local shines = {} -- [degradado] = desfase: brillo blanco que cruza la fila de vez en cuando
local bobbing = {} -- [icono] = { phase, scale }: el icono flota y late
local sparkly = {} -- [capa] = { color, window, next }: chispas de fondo en las raras (< 1 %)
local SHINE_EVERY = 4.5 -- segundos entre dos brillos de la misma fila
local SHINE_TIME = 0.7 -- lo que tarda el brillo en cruzar
local SPARKLE_EVERY = 1.6 -- segundos entre chispas de una fila rara

local function rainbow(parent: Instance)
	local gradient = Instance.new("UIGradient")
	gradient.Color = rainbowColors()
	gradient.Parent = parent
	spinning[gradient] = true
end

-- Orden de la lista de resultados: los grados, del más raro al más común; los rasgos por tipo
-- (Especiales, Monedas, Daño, Suerte), cada tipo del más raro al más común. Devuelve una lista
-- de { header = texto } y { index = posición en la lista de Config }.
local GROUPS = {
	{ icon = "all", title = "Especiales" },
	{ icon = "coins", title = "Monedas" },
	{ icon = "damage", title = "Daño" },
	{ icon = "luck", title = "Suerte" },
}
local function displayOrder(kind: string)
	local list = Modifiers.KINDS[kind].list
	local result = {}
	if kind ~= "traits" then
		for index = #list, 1, -1 do
			table.insert(result, { index = index })
		end
		return result
	end
	for _, group in GROUPS do
		table.insert(result, { header = group.title })
		for index = #list, 1, -1 do
			if list[index].icon == group.icon then
				table.insert(result, { index = index })
			end
		end
	end
	return result
end

-- Engranaje hecho con marcos (la fuente no tiene el icono): dientes, aro y agujero.
local function gearIcon(parent: GuiObject)
	local holder = Instance.new("Frame")
	holder.Name = "Gear"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(40, 40)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local metal = Color3.fromRGB(230, 233, 240)
	for tooth = 0, 3 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(44, 9)
		bar.Rotation = tooth * 45
		bar.BackgroundColor3 = metal
		bar.BorderSizePixel = 0
		bar.Parent = holder
		Ui.round(bar, 3)
	end
	local wheel = Instance.new("Frame")
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(28, 28)
	wheel.BackgroundColor3 = metal
	wheel.Parent = holder
	Ui.round(wheel, 14)
	Ui.stroke(wheel, BLACK, 2)
	local hole = Instance.new("Frame")
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromOffset(12, 12)
	hole.BackgroundColor3 = Color3.fromRGB(80, 84, 98)
	hole.Parent = wheel
	Ui.round(hole, 6)
	Ui.stroke(hole, BLACK, 2)
	return holder
end

-- Icono de una entrada: la letra del grado, o un dibujo según lo que sube el rasgo.
local function entryIcon(parent: GuiObject, kind: string, entry)
	if kind == "grades" then
		local letter = Ui.label(parent, 34)
		letter.Size = UDim2.fromScale(1, 1)
		letter.Text = entry.name
		letter.TextColor3 = if entry.rainbow then WHITE else entry.color
		if entry.rainbow then
			rainbow(letter)
		end
		return
	end
	if entry.icon == "coins" then
		Ui.orbIcon(parent, entry.color)
	elseif entry.icon == "damage" then
		Ui.swordIcon(parent, entry.color)
	elseif entry.icon == "luck" then
		Ui.gemIcon(parent, entry.color)
	else
		local _, pieces = Ui.hex(parent, 34, if entry.rainbow then WHITE else entry.color)
		for _, piece in pieces do
			if entry.rainbow then
				rainbow(piece)
			end
		end
	end
end

-- Texto con el nombre de la entrada, en su color (o arcoíris).
local function paintName(label: TextLabel, entry)
	local old = label:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	if not entry then
		label.Text = "Ninguno"
		label.TextColor3 = Color3.fromRGB(150, 150, 160)
		return
	end
	label.Text = entry.name
	label.TextColor3 = if entry.rainbow then WHITE else entry.color
	if entry.rainbow then
		rainbow(label)
	end
end

local function buildShop(kind: string)
	local info = Modifiers.KINDS[kind]
	local windowName = info.title
	local window, body = Ui.window(windowName, info.title, SIZE)
	local header = window:FindFirstChild("Header")
	local headerGradient = header and header:FindFirstChildOfClass("UIGradient")
	if headerGradient then
		headerGradient.Color = if kind == "traits" then rainbowColors() else ColorSequence.new(Color3.fromRGB(150, 70, 255), Color3.fromRGB(210, 120, 255))
	end
	-- Título animado: arcoíris que gira en Rasgos, morado y blanco que gira en Grados.
	local heading = header and header:FindFirstChild("Title")
	if heading then
		local shine = heading:FindFirstChildOfClass("UIGradient")
		if shine then
			shine:Destroy()
		end
		if kind == "traits" then
			rainbow(heading)
		else
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
			gradient.Parent = heading
			spinning[gradient] = true
		end
	end

	local state = { selected = nil, auto = false, waiting = false, last = nil, stop = {} }
	for index in info.list do
		state.stop[index] = Modifiers.percent(kind, index) < 1
	end

	local left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = UDim2.new(0, LEFT, 1, 0)
	left.BackgroundTransparency = 1
	left.Parent = body

	-- Casilla de la espada elegida.
	local slot = Ui.cell(left, Color3.fromRGB(230, 230, 240))
	slot.Name = "Slot"
	slot.Position = UDim2.fromOffset(18, 18)
	slot.Size = UDim2.fromOffset(172, 172)
	-- Al pasar el ratón: estadísticas de la espada elegida (el mismo cartel que en la mochila).
	Ui.tip(slot, function()
		for _, copy in Stats.swords(player) do
			if copy.id == state.selected then
				return Backpack.swordTip(copy)
			end
		end
		return "Pulsa para elegir una espada", WHITE
	end)
	local slotHint = Ui.label(slot, 19)
	slotHint.AnchorPoint = Vector2.new(0.5, 1)
	slotHint.Position = UDim2.new(0.5, 0, 1, -6)
	slotHint.Size = UDim2.new(1, -8, 0, 22)
	slotHint.TextScaled = true
	slotHint.ZIndex = 3

	local heading = Ui.label(left, 30)
	heading.Position = UDim2.fromOffset(208, 18)
	heading.Size = UDim2.fromOffset(294, 34)
	heading.Text = info.label

	local nameBox = Instance.new("Frame")
	nameBox.Name = "Current"
	nameBox.Position = UDim2.fromOffset(208, 58)
	nameBox.Size = UDim2.fromOffset(294, 66)
	nameBox.BackgroundColor3 = Ui.COLORS.dark
	nameBox.Parent = left
	Ui.round(nameBox, 10)
	Ui.stroke(nameBox, Color3.fromRGB(90, 90, 100), 3)
	local nameScale = Instance.new("UIScale")
	nameScale.Parent = nameBox
	local nameLabel = Ui.label(nameBox, 38)
	nameLabel.Size = UDim2.fromScale(1, 1)

	local effect = Ui.label(left, 21)
	effect.Position = UDim2.fromOffset(208, 132)
	effect.Size = UDim2.fromOffset(294, 26)

	local cost = Ui.label(left, 24)
	cost.Name = "Cost"
	cost.Position = UDim2.fromOffset(16, 214)
	cost.Size = UDim2.new(1, -32, 0, 30)

	local warning = Ui.label(left, 18)
	warning.Position = UDim2.fromOffset(16, 252)
	warning.Size = UDim2.new(1, -32, 0, 52)
	warning.TextWrapped = true
	warning.TextColor3 = Color3.fromRGB(200, 200, 210)
	warning.Text = `Al tirar se sustituye el {string.lower(info.label)} que tenga la espada.\nMientras esté equipada, {if kind == "traits" then "sube sus monedas, daño o suerte" else "multiplica sus monedas"}.`

	local rollButton = Ui.button(left, "Tirar", Ui.COLORS.blue)
	rollButton.Name = "Roll"
	rollButton.Position = UDim2.fromOffset(18, 362)
	rollButton.Size = UDim2.fromOffset(200, 74)
	rollButton.TextSize = 28
	local autoButton = Ui.button(left, "Auto", Ui.COLORS.red)
	autoButton.Name = "Auto"
	autoButton.Position = UDim2.fromOffset(230, 362)
	autoButton.Size = UDim2.fromOffset(200, 74)
	autoButton.TextSize = 26
	-- Engranaje: con qué resultados se para la tirada automática.
	local settingsButton = Ui.button(left, "", Ui.COLORS.gray)
	settingsButton.Name = "Settings"
	settingsButton.Position = UDim2.fromOffset(442, 362)
	settingsButton.Size = UDim2.fromOffset(66, 74)
	gearIcon(settingsButton)

	-- Capas que tapan la parte izquierda: elegir espada y elegir con qué se para el automático.
	local function overlay(name: string, titleText: string): (Frame, ScrollingFrame)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.new(0, LEFT, 1, 0)
		frame.BackgroundColor3 = Ui.COLORS.body
		frame.Visible = false
		frame.ZIndex = 5
		frame.Parent = body
		Ui.round(frame, 10)
		local title = Ui.label(frame, 26)
		title.Position = UDim2.fromOffset(0, 8)
		title.Size = UDim2.new(1, 0, 0, 30)
		title.Text = titleText
		title.ZIndex = 6
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.Position = UDim2.fromOffset(12, 44)
		list.Size = UDim2.new(1, -24, 1, -124)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ZIndex = 6
		list.Parent = frame
		-- Margen para que no se corten los bordes de las casillas.
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = list
		local back = Ui.button(frame, "Volver", Ui.COLORS.red)
		back.Name = "Back"
		back.AnchorPoint = Vector2.new(0.5, 1)
		back.Position = UDim2.new(0.5, 0, 1, -10)
		back.Size = UDim2.fromOffset(180, 54)
		back.TextSize = 24
		back.ZIndex = 9 -- por encima de las casillas de la lista
		back.Activated:Connect(function()
			frame.Visible = false
		end)
		return frame, list
	end

	local picker, pickerList = overlay("Picker", "Elige una espada")
	local pickerGrid = Instance.new("UIGridLayout")
	pickerGrid.CellSize = UDim2.fromOffset(84, 84)
	pickerGrid.CellPadding = UDim2.fromOffset(8, 8)
	pickerGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pickerGrid.Parent = pickerList

	local stopper, stopList = overlay("StopAt", "La tirada automática para con:")
	local stopGrid = Instance.new("UIGridLayout")
	stopGrid.CellSize = UDim2.fromOffset(136, 46)
	stopGrid.CellPadding = UDim2.fromOffset(8, 8)
	stopGrid.SortOrder = Enum.SortOrder.LayoutOrder
	stopGrid.Parent = stopList
	for position, item in displayOrder(kind) do
		local index = item.index
		if not index then
			continue
		end
		local entry = info.list[index]
		local toggle = Ui.button(stopList, entry.name, Ui.COLORS.cell)
		toggle.Name = "Stop" .. index
		toggle.LayoutOrder = position
		toggle.TextSize = 24
		toggle.ZIndex = 7
		toggle.TextColor3 = if entry.rainbow then WHITE else entry.color
		local function paint()
			toggle.BackgroundColor3 = if state.stop[index] then Color3.fromRGB(60, 150, 60) else Ui.COLORS.cell
		end
		toggle.Activated:Connect(function()
			state.stop[index] = not state.stop[index]
			paint()
		end)
		paint()
	end

	-- Lista de resultados posibles (derecha), en el orden de displayOrder.
	local results = Instance.new("ScrollingFrame")
	results.Name = "Results"
	results.Position = UDim2.fromOffset(LEFT + 8, 8)
	results.Size = UDim2.new(1, -LEFT - 16, 1, -16)
	results.BackgroundTransparency = 1
	results.BorderSizePixel = 0
	results.ScrollBarThickness = 6
	results.AutomaticCanvasSize = Enum.AutomaticSize.Y
	results.CanvasSize = UDim2.new()
	results.Parent = body
	local resultsLayout = Instance.new("UIListLayout")
	resultsLayout.Padding = UDim.new(0, 8)
	resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultsLayout.Parent = results
	-- Margen para que no se corten los bordes de las filas ni choquen con la barra.
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = results
	local rows = {}
	for position, item in displayOrder(kind) do
		if item.header then
			local header = Ui.label(results, 26)
			header.Name = "Header" .. position
			header.LayoutOrder = position
			header.Size = UDim2.new(1, 0, 0, 32)
			header.TextXAlignment = Enum.TextXAlignment.Left
			header.Text = item.header
			if position == 1 then
				rainbow(header)
			end
			continue
		end
		local index = item.index
		local entry = info.list[index]
		local row = Instance.new("Frame")
		row.Name = "Result" .. index
		row.LayoutOrder = position
		row.Size = UDim2.new(1, -8, 0, 92)
		row.BackgroundColor3 = WHITE
		row.Parent = results
		Ui.round(row, 10)
		Ui.gradient(row, Color3.fromRGB(45, 45, 55), Color3.fromRGB(22, 22, 30), 90)
		local stroke = Ui.stroke(row, if entry.rainbow then WHITE else entry.color, 3)
		if entry.rainbow then
			rainbow(stroke)
		elseif Modifiers.percent(kind, index) < 0.1 then
			pulsing[stroke] = index
		end
		-- Brillo: una franja blanca (degradado de transparencia) que cruza la fila.
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.Size = UDim2.fromScale(1, 1)
		shine.BackgroundColor3 = WHITE
		shine.ZIndex = row.ZIndex
		shine.Parent = row
		Ui.round(shine, 10)
		local shineGradient = Instance.new("UIGradient")
		shineGradient.Rotation = 20
		shineGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		shineGradient.Offset = Vector2.new(-1, 0)
		shineGradient.Parent = shine
		shines[shineGradient] = position * 0.37
		if Modifiers.percent(kind, index) < 1 then
			-- Capa de las chispas, creada antes que el icono y los textos para quedar por detrás.
			local sparkLayer = Instance.new("Frame")
			sparkLayer.Name = "Sparkles"
			sparkLayer.Size = UDim2.fromScale(1, 1)
			sparkLayer.BackgroundTransparency = 1
			sparkLayer.ZIndex = row.ZIndex
			sparkLayer.Parent = row
			sparkly[sparkLayer] = { color = if entry.rainbow then WHITE else entry.color, window = window, next = 0 }
		end
		-- Icono a la izquierda; arriba el nombre y el % en una etiqueta a la derecha; abajo el efecto a lo ancho.
		local iconBox = Instance.new("Frame")
		iconBox.Position = UDim2.fromOffset(12, 17)
		iconBox.Size = UDim2.fromOffset(62, 58)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = row
		entryIcon(iconBox, kind, entry)
		local iconScale = Instance.new("UIScale")
		iconScale.Parent = iconBox
		bobbing[iconBox] = { phase = position * 0.9, scale = iconScale }
		local pill = Instance.new("Frame")
		pill.Name = "Percent"
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, -12, 0, 10)
		pill.Size = UDim2.fromOffset(104, 34)
		pill.BackgroundColor3 = Ui.COLORS.dark
		pill.Parent = row
		Ui.round(pill, 10)
		local pillStroke = Ui.stroke(pill, if entry.rainbow then WHITE else entry.color, 2)
		if entry.rainbow then
			rainbow(pillStroke)
		end
		local percent = Ui.label(pill, 22)
		percent.Size = UDim2.fromScale(1, 1)
		percent.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 22
		limit.Parent = percent
		percent.Text = Modifiers.formatPercent(Modifiers.percent(kind, index))
		local title = Ui.label(row, 30)
		title.Position = UDim2.fromOffset(86, 8)
		title.Size = UDim2.new(1, -210, 0, 34)
		title.TextXAlignment = Enum.TextXAlignment.Left
		paintName(title, entry)
		if kind == "grades" then
			title.Text = "Grado " .. entry.name
		end
		if not entry.rainbow then
			-- Degradado de blanco al color de la entrada: más llamativo que el color liso.
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new(entry.color:Lerp(WHITE, 0.55), entry.color)
			gradient.Parent = title
		end
		local detail = Ui.label(row, 20)
		detail.Position = UDim2.fromOffset(86, 54)
		detail.Size = UDim2.new(1, -98, 0, 26)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextColor3 = Color3.fromRGB(120, 235, 120)
		detail.Text = Modifiers.effect(entry)
		detail.TextScaled = true
		local detailLimit = Instance.new("UITextSizeConstraint")
		detailLimit.MaxTextSize = 20
		detailLimit.Parent = detail
		-- Crece un poco al pasar el ratón.
		local grow = Instance.new("UIScale")
		grow.Parent = row
		row.MouseEnter:Connect(function()
			TweenService:Create(grow, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
		end)
		row.MouseLeave:Connect(function()
			TweenService:Create(grow, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		rows[index] = row
	end

	-- Estado --------------------------------------------------------------------------
	local function selectedCopy()
		for _, copy in Stats.swords(player) do
			if copy.id == state.selected then
				return copy
			end
		end
		return nil
	end

	local function canAfford(): boolean
		if kind == "traits" then
			return (player:GetAttribute("Item_traitCrystal") or 0) >= 1
		end
		return (player:GetAttribute("Gems") or 0) >= Config.GradeCost
	end

	local function refresh()
		local copy = selectedCopy()
		if not copy then
			state.selected = player:GetAttribute("Equipped")
			copy = selectedCopy()
		end
		if copy then
			local sword = Config.Swords[copy.sword]
			local tierColor = Rarity.tier(sword.rarity).color
			if state.shown ~= copy.sword then
				state.shown = copy.sword
				for _, name in { "Glow", "Preview" } do
					local old = slot:FindFirstChild(name)
					if old then
						old:Destroy()
					end
				end
				WeaponPreview.attach(slot, copy.sword, tierColor)
			end
			slot:FindFirstChildOfClass("UIStroke").Color = tierColor
			slotHint.Text = sword.name
			if not state.waiting then
				local current = info.list[copy[info.field]]
				paintName(nameLabel, current)
				effect.Text = if current then Modifiers.effect(current) else ""
			end
		else
			slotHint.Text = "Elige espada"
		end
		if kind == "traits" then
			cost.Text = `Cristales de rasgo: {Format.short(player:GetAttribute("Item_traitCrystal") or 0)}  ·  1 por tirada`
		else
			cost.Text = `Gemas: {Format.short(player:GetAttribute("Gems") or 0)}  ·  {Config.GradeCost} por tirada`
		end
		cost.TextColor3 = if canAfford() then WHITE else Ui.COLORS.red
		rollButton.BackgroundColor3 = if canAfford() and copy then Ui.COLORS.blue else Ui.COLORS.gray
		autoButton.Text = if state.auto then "Parar" else "Auto"
		autoButton.BackgroundColor3 = if state.auto then Ui.COLORS.orange else Ui.COLORS.red
	end

	local function rebuildPicker()
		for _, child in pickerList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local equipped = player:GetAttribute("Equipped")
		-- De la más rara a la más común; dentro de la misma rareza, de más a menos daño.
		local copies = Stats.swords(player)
		table.sort(copies, function(a, b)
			-- La espada inicial no tiene rareza: cuenta como la más común.
			local rarityA, rarityB = Config.Swords[a.sword].rarity or 1, Config.Swords[b.sword].rarity or 1
			if rarityA ~= rarityB then
				return rarityA > rarityB
			end
			return Stats.swordDamage(a) > Stats.swordDamage(b)
		end)
		for position, copy in copies do
			local sword = Config.Swords[copy.sword]
			local cell = Ui.cell(pickerList, Rarity.tier(sword.rarity).color)
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = position
			cell.ZIndex = 7
			WeaponPreview.attach(cell, copy.sword, Rarity.tier(sword.rarity).color)
			local current = info.list[copy[info.field]]
			if current then
				Ui.cellLabel(cell, current.name)
			end
			if copy.id == equipped then
				Ui.cellTag(cell, "E", Ui.COLORS.green)
			end
			for _, descendant in cell:GetDescendants() do
				if descendant:IsA("GuiObject") then
					descendant.ZIndex = 8
				end
			end
			Ui.tip(cell, function()
				return Backpack.swordTip(copy)
			end)
			cell.Activated:Connect(function()
				state.selected = copy.id
				picker.Visible = false
				refresh()
			end)
		end
	end

	-- Animación del resultado: pasan nombres al azar y se para en el que ha tocado.
	local function reveal(index: number)
		local entry = info.list[index]
		for _ = 1, 7 do
			paintName(nameLabel, info.list[Modifiers.roll(kind, random)])
			task.wait(0.045)
		end
		paintName(nameLabel, entry)
		effect.Text = Modifiers.effect(entry)
		nameScale.Scale = 1.3
		TweenService:Create(nameScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local row = rows[index]
		local flash = TweenService:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { BackgroundColor3 = entry.color })
		flash:Play()
		if Modifiers.percent(kind, index) < 1 then
			Ui.toast(`¡{entry.name}! ({Modifiers.formatPercent(Modifiers.percent(kind, index))})`, entry.color)
		end
	end

	local function request(): boolean
		if state.waiting or not selectedCopy() or not canAfford() then
			return false
		end
		state.waiting = true
		state.last = nil
		if kind == "traits" then
			Remotes.RollTrait:FireServer(state.selected)
		else
			Remotes.RollGrade:FireServer(state.selected)
		end
		-- Si el servidor no contesta (demasiado pronto), se puede volver a pedir.
		task.delay(1.5, function()
			if state.waiting and not state.last then
				state.waiting = false
			end
		end)
		return true
	end

	local function autoLoop()
		while state.auto and window.Visible do
			if not request() then
				if not state.waiting then
					Ui.toast(if canAfford() then "Elige una espada" else (if kind == "traits" then "No te quedan Cristales de rasgo" else "No te quedan gemas"), Ui.COLORS.red)
					break
				end
			end
			while state.waiting do
				task.wait()
			end
			if state.last and state.stop[state.last] then
				break
			end
			task.wait(AUTO_DELAY)
		end
		state.auto = false
		refresh()
	end

	Remotes.ModifierRolled.OnClientEvent:Connect(function(rolledKind: string, id: number, index: number)
		if rolledKind ~= kind then
			return
		end
		state.last = index
		if id == state.selected then
			reveal(index)
		end
		state.waiting = false
		refresh()
	end)

	slot.Activated:Connect(function()
		rebuildPicker()
		stopper.Visible = false
		picker.Visible = not picker.Visible
	end)
	settingsButton.Activated:Connect(function()
		picker.Visible = false
		stopper.Visible = not stopper.Visible
	end)
	rollButton.Activated:Connect(function()
		if not state.auto then
			request()
		end
	end)
	autoButton.Activated:Connect(function()
		state.auto = not state.auto
		refresh()
		if state.auto then
			task.spawn(autoLoop)
		end
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible then
			state.auto = false
			picker.Visible = false
			stopper.Visible = false
		end
		refresh()
	end)
	for _, attribute in { "Swords", "Equipped", "Gems", "Item_traitCrystal" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
	return windowName, window
end

function ModifierShops.start()
	-- Los arcoíris de las especiales giran.
	game:GetService("RunService").RenderStepped:Connect(function(delta)
		for gradient in spinning do
			if gradient.Parent then
				gradient.Rotation = (gradient.Rotation + delta * 120) % 360
			else
				spinning[gradient] = nil
			end
		end
		local now = os.clock()
		-- Carteles de los puestos: los colores giran, el cartel late y flota.
		for _, sign in CollectionService:GetTagged("ShopSign") do
			local billboard = sign :: BillboardGui
			local wave = math.sin(now * 2.2)
			billboard.StudsOffset = Vector3.new(0, 13 + wave * 0.5, 0)
			local label = billboard:FindFirstChildOfClass("TextLabel")
			if label then
				label.TextSize = 48 * (1 + wave * 0.06)
				local gradient = label:FindFirstChildOfClass("UIGradient")
				if gradient then
					gradient.Rotation = (now * 90) % 360
				end
			end
		end
		for stroke, phase in pulsing do
			if not stroke.Parent then
				pulsing[stroke] = nil
				continue
			end
			local wave = (math.sin(now * 4 + phase) + 1) / 2
			stroke.Thickness = 2.5 + wave * 2.5
			stroke.Transparency = 0.35 - wave * 0.35
		end
		-- Filas de la lista: brillo que cruza, iconos que flotan y laten, chispas en las raras.
		for gradient, phase in shines do
			if not gradient.Parent then
				shines[gradient] = nil
				continue
			end
			local t = (now + phase) % SHINE_EVERY
			gradient.Offset = Vector2.new(if t < SHINE_TIME then -1 + 2 * t / SHINE_TIME else -1, 0)
		end
		for icon, data in bobbing do
			if not icon.Parent then
				bobbing[icon] = nil
				continue
			end
			icon.Position = UDim2.fromOffset(12, 17 + math.sin(now * 2 + data.phase) * 3)
			data.scale.Scale = 1 + math.sin(now * 3 + data.phase) * 0.06
		end
		for layer, data in sparkly do
			if not layer.Parent then
				sparkly[layer] = nil
				continue
			end
			if not data.window.Visible or now < data.next then
				continue
			end
			data.next = now + SPARKLE_EVERY * (0.6 + random:NextNumber() * 0.8)
			-- Chispa (rombo blanco con borde del color) que crece y se apaga en un punto al azar.
			local spark = Instance.new("Frame")
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.Position = UDim2.fromScale(random:NextNumber(0.05, 0.8), random:NextNumber(0.15, 0.85))
			spark.Size = UDim2.fromOffset(0, 0)
			spark.Rotation = 45
			spark.BackgroundColor3 = WHITE
			spark.BorderSizePixel = 0
			spark.BackgroundTransparency = 0.4
			spark.ZIndex = layer.ZIndex
			spark.Parent = layer
			Ui.stroke(spark, data.color, 1).Transparency = 0.4
			local size = random:NextInteger(5, 8)
			local grow = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
			TweenService:Create(spark, grow, { Size = UDim2.fromOffset(size, size) }):Play()
			task.delay(0.5, function()
				spark:Destroy()
			end)
		end
	end)

	local windows = {}
	for _, kind in { "traits", "grades" } do
		local name, window = buildShop(kind)
		windows[kind] = { name = name, frame = window }
	end

	-- Abrir junto al puesto y cerrar al alejarse.
	local openAt: Vector3? = nil
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local kind = prompt:GetAttribute("Shop")
		local shop = kind and windows[kind]
		if shop then
			local parent = prompt.Parent
			openAt = if parent and parent:IsA("BasePart") then parent.Position else nil
			Ui.toggle(shop.name)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if openAt and root and (root.Position - openAt).Magnitude > CLOSE_DISTANCE then
				for _, shop in windows do
					shop.frame.Visible = false
				end
				openAt = nil
			end
		end
	end)
end

return ModifierShops
