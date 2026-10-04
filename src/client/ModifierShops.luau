-- Ventanas de las tiendas de modificadores del hub (Rasgos y Grados). Se abren con la tecla de
-- interacción junto a cada puesto y se cierran al alejarse. A la izquierda, la espada elegida
-- (se cambia pulsando su casilla), el modificador que tiene, lo que cuesta y los botones
-- Tirar / Auto / "Parar con..." (con qué resultados se para la tirada automática). A la derecha,
-- todos los resultados posibles, del más raro al más común, con su % y su efecto.
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
local Ui = require(script.Parent.Ui)

local ModifierShops = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SIZE = Vector2.new(900, 470)
local LEFT = 470 -- ancho de la parte izquierda del cuerpo
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

local function rainbow(parent: Instance)
	local gradient = Instance.new("UIGradient")
	gradient.Color = rainbowColors()
	gradient.Parent = parent
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
	slot.Position = UDim2.fromOffset(16, 16)
	slot.Size = UDim2.fromOffset(150, 150)
	local slotHint = Ui.label(slot, 16)
	slotHint.AnchorPoint = Vector2.new(0.5, 1)
	slotHint.Position = UDim2.new(0.5, 0, 1, -6)
	slotHint.Size = UDim2.new(1, -8, 0, 22)
	slotHint.TextScaled = true
	slotHint.ZIndex = 3

	local heading = Ui.label(left, 26)
	heading.Position = UDim2.fromOffset(186, 16)
	heading.Size = UDim2.fromOffset(270, 32)
	heading.Text = info.label

	local nameBox = Instance.new("Frame")
	nameBox.Name = "Current"
	nameBox.Position = UDim2.fromOffset(186, 54)
	nameBox.Size = UDim2.fromOffset(270, 58)
	nameBox.BackgroundColor3 = Ui.COLORS.dark
	nameBox.Parent = left
	Ui.round(nameBox, 10)
	Ui.stroke(nameBox, Color3.fromRGB(90, 90, 100), 3)
	local nameScale = Instance.new("UIScale")
	nameScale.Parent = nameBox
	local nameLabel = Ui.label(nameBox, 30)
	nameLabel.Size = UDim2.fromScale(1, 1)

	local effect = Ui.label(left, 17)
	effect.Position = UDim2.fromOffset(186, 118)
	effect.Size = UDim2.fromOffset(270, 24)

	local cost = Ui.label(left, 20)
	cost.Name = "Cost"
	cost.Position = UDim2.fromOffset(16, 186)
	cost.Size = UDim2.new(1, -32, 0, 30)

	local warning = Ui.label(left, 15)
	warning.Position = UDim2.fromOffset(16, 222)
	warning.Size = UDim2.new(1, -32, 0, 44)
	warning.TextWrapped = true
	warning.TextColor3 = Color3.fromRGB(200, 200, 210)
	warning.Text = `Al tirar se sustituye el {string.lower(info.label)} que tenga la espada.\nMientras esté equipada, {if kind == "traits" then "sube sus monedas, daño o suerte" else "multiplica sus monedas"}.`

	local rollButton = Ui.button(left, "Tirar", Ui.COLORS.blue)
	rollButton.Name = "Roll"
	rollButton.Position = UDim2.fromOffset(16, 300)
	rollButton.Size = UDim2.fromOffset(180, 66)
	rollButton.TextSize = 28
	local autoButton = Ui.button(left, "Auto", Ui.COLORS.red)
	autoButton.Name = "Auto"
	autoButton.Position = UDim2.fromOffset(208, 300)
	autoButton.Size = UDim2.fromOffset(180, 66)
	autoButton.TextSize = 26
	-- Con qué resultados se para la tirada automática (la fuente no tiene el icono de engranaje).
	local settingsButton = Ui.button(left, "Parar\ncon...", Ui.COLORS.gray)
	settingsButton.Name = "Settings"
	settingsButton.Position = UDim2.fromOffset(400, 300)
	settingsButton.Size = UDim2.fromOffset(62, 66)
	settingsButton.TextSize = 14

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
		local title = Ui.label(frame, 22)
		title.Position = UDim2.fromOffset(0, 8)
		title.Size = UDim2.new(1, 0, 0, 30)
		title.Text = titleText
		title.ZIndex = 6
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.Position = UDim2.fromOffset(12, 44)
		list.Size = UDim2.new(1, -24, 1, -116)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ZIndex = 6
		list.Parent = frame
		local back = Ui.button(frame, "Volver", Ui.COLORS.red)
		back.Name = "Back"
		back.AnchorPoint = Vector2.new(0.5, 1)
		back.Position = UDim2.new(0.5, 0, 1, -10)
		back.Size = UDim2.fromOffset(180, 54)
		back.TextSize = 24
		back.ZIndex = 6
		back.Activated:Connect(function()
			frame.Visible = false
		end)
		return frame, list
	end

	local picker, pickerList = overlay("Picker", "Elige una espada")
	local pickerGrid = Instance.new("UIGridLayout")
	pickerGrid.CellSize = UDim2.fromOffset(78, 78)
	pickerGrid.CellPadding = UDim2.fromOffset(8, 8)
	pickerGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pickerGrid.Parent = pickerList

	local stopper, stopList = overlay("StopAt", "La tirada automática para con:")
	local stopGrid = Instance.new("UIGridLayout")
	stopGrid.CellSize = UDim2.fromOffset(136, 46)
	stopGrid.CellPadding = UDim2.fromOffset(8, 8)
	stopGrid.SortOrder = Enum.SortOrder.LayoutOrder
	stopGrid.Parent = stopList
	for index, entry in info.list do
		local toggle = Ui.button(stopList, entry.name, Ui.COLORS.cell)
		toggle.Name = "Stop" .. index
		toggle.LayoutOrder = index
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

	-- Lista de resultados posibles (derecha), del más raro al más común.
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
	local rows = {}
	for index, entry in info.list do
		local row = Instance.new("Frame")
		row.Name = "Result" .. index
		row.LayoutOrder = -index
		row.Size = UDim2.new(1, -10, 0, 70)
		row.BackgroundColor3 = WHITE
		row.Parent = results
		Ui.round(row, 10)
		Ui.gradient(row, Color3.fromRGB(45, 45, 55), Color3.fromRGB(22, 22, 30), 90)
		local stroke = Ui.stroke(row, if entry.rainbow then WHITE else entry.color, 3)
		if entry.rainbow then
			rainbow(stroke)
		end
		local iconBox = Instance.new("Frame")
		iconBox.Position = UDim2.fromOffset(8, 4)
		iconBox.Size = UDim2.fromOffset(54, 46)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = row
		entryIcon(iconBox, kind, entry)
		local percent = Ui.label(row, 14)
		percent.Position = UDim2.fromOffset(2, 48)
		percent.Size = UDim2.fromOffset(66, 18)
		percent.Text = Modifiers.formatPercent(Modifiers.percent(kind, index))
		local title = Ui.label(row, 22)
		title.Position = UDim2.fromOffset(76, 8)
		title.Size = UDim2.new(1, -84, 0, 28)
		title.TextXAlignment = Enum.TextXAlignment.Left
		paintName(title, entry)
		if kind == "grades" then
			title.Text = "Grado " .. entry.name
		end
		local detail = Ui.label(row, 16)
		detail.Position = UDim2.fromOffset(76, 38)
		detail.Size = UDim2.new(1, -84, 0, 22)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextColor3 = Color3.fromRGB(120, 230, 120)
		detail.Text = Modifiers.effect(entry)
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
		local old = slot:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		if copy then
			local sword = Config.Swords[copy.sword]
			local tierColor = Rarity.tier(sword.rarity).color
			Ui.swordIcon(slot, sword.color)
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
		for _, copy in Stats.swords(player) do
			local sword = Config.Swords[copy.sword]
			local cell = Ui.cell(pickerList, Rarity.tier(sword.rarity).color)
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = -math.floor(Stats.swordDamage(copy))
			cell.ZIndex = 7
			Ui.swordIcon(cell, sword.color)
			local current = info.list[copy[info.field]]
			Ui.cellLabel(cell, if current then current.name else "-")
			if copy.id == equipped then
				Ui.cellTag(cell, "E", Ui.COLORS.green)
			end
			for _, descendant in cell:GetDescendants() do
				if descendant:IsA("GuiObject") then
					descendant.ZIndex = 8
				end
			end
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
		results.CanvasPosition = Vector2.new(0, math.max(0, row.AbsolutePosition.Y - results.AbsolutePosition.Y + results.CanvasPosition.Y - 80))
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
