-- Panel "Armas" del menú de admin (client/AdminPanel lo monta en su pestaña; librería sin start()): fabricar un arma
-- a medida (arma, metal, tamaño, rasgo y grado) y dársela a un jugador o a todos los del servidor. Solo pide: la
-- orden va por AdminCommand ("sword") y server/AdminCommands la comprueba entera.
--   `Body.Weapons.ListCard.Content.List`: a quién (`Target_0` = todos, `Target_<userId>`).
--   `Body.Weapons.SideCard.Side.Form`: `Top.Preview` (la casilla de la mochila con el arma elegida), `Top.Name` y
--     `Top.Odds`, una fila por campo (`Rows.Row_<sword|metal|size|trait|grade>.Value`) y `Bottom.Amount`, `.Max` y `.Give`.
--   `Body.Weapons.SideCard.Side.Picker`: la lista de opciones del campo pulsado (`List.Option_<índice>`) y `Back`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local AdminWeapons = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(40, 38, 80)
local PLAIN = Color3.fromRGB(120, 126, 150) -- color de "sin metal", "normal" y "ninguno"
local PAD = 12
local GAP = 8
local LIST_WIDTH = 170
local PREVIEW = 100 -- lado de la casilla del arma
local ROW = 38 -- alto de cada fila de campo y de cada opción
local BOTTOM = 46
local MAX_AMOUNT = 50 -- el mismo tope que pone el servidor (MAX_SWORDS)
local CONFIRM_TIME = 3 -- segundos que dura el "¿Seguro?" de dar a todos

-- Los campos del arma, en el orden de sus filas. `none` = nombre de la opción 0 (nil si el campo no la tiene).
local FIELDS = {
	{ key = "sword", name = "Weapon", list = Config.Swords },
	{ key = "metal", name = "Metal", list = Config.Metals, none = "No metal", top = "odds" },
	{ key = "size", name = "Size", list = Config.Sizes, none = "Normal", top = "odds" },
	{ key = "trait", name = "Trait", list = Config.Traits, none = "None", top = "damage" },
	{ key = "grade", name = "Grade", list = Config.Grades, none = "None", top = "damage" },
}

-- Panel con fondo y borde, como los demás del menú. Devuelve el marco de dentro, donde va el contenido.
local function card(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, PANEL)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(10, 8)
	content.Size = UDim2.new(1, -20, 1, -16)
	content.BackgroundTransparency = 1
	content.Parent = frame
	return content
end

local function scroller(parent: Instance, name: string): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = parent
	-- Hueco para el borde de los botones y para la barra.
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = list
	return list
end

-- Texto que encoge para caber en su botón (los nombres de armas son largos).
local function fit(button: TextButton, max: number)
	button.TextScaled = true
	button.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 11
	limit.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = button
end

-- Nombre y color de la opción `index` de un campo (0 = la de "ninguno").
local function look(field, index: number): (string, Color3)
	if index == 0 then
		return Lang.t(nil, field.none), PLAIN
	end
	local entry = field.list[index]
	if field.key == "sword" then
		return Lang.t(nil, entry.name), Rarity.tier(Permanent.rarity(index)).color
	end
	return Lang.t(nil, entry.name), entry.color
end

-- Opciones de un campo en el orden en que se enseñan: "ninguno" primero y las armas de la más común a la más rara
-- (Config.Swords no va ordenada).
local function options(field): { number }
	local order = {}
	for index in field.list do
		table.insert(order, index)
	end
	if field.key == "sword" then
		table.sort(order, function(a, b)
			local left, right = Permanent.rarity(a), Permanent.rarity(b)
			if left ~= right then
				return left < right
			end
			return a < b
		end)
	end
	if field.none then
		table.insert(order, 1, 0)
	end
	return order
end

-- La opción de más `stat` de una lista de Config (lo mejor de ese campo).
local function best(list, stat: string): number
	local pick = 1
	for index, entry in list do
		if (entry[stat] or 0) > (list[pick][stat] or 0) then
			pick = index
		end
	end
	return pick
end

function AdminWeapons.build(pane: Frame)
	local target = player.UserId -- 0 = todos los del servidor
	local chosen = { sword = 1, metal = 0, size = 0, trait = 0, grade = 0 }

	-- A quién -----------------------------------------------------------------------------------
	local listCard = card(pane, "ListCard", UDim2.fromOffset(PAD, PAD), UDim2.new(0, LIST_WIDTH, 1, -PAD * 2))
	local targets = scroller(listCard, "List")
	targets.Size = UDim2.fromScale(1, 1)
	local targetLayout = Instance.new("UIListLayout")
	targetLayout.Padding = UDim.new(0, 6)
	targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
	targetLayout.Parent = targets

	local side = card(pane, "SideCard", UDim2.fromOffset(PAD + LIST_WIDTH + GAP, PAD), UDim2.new(1, -(PAD * 2 + LIST_WIDTH + GAP), 1, -PAD * 2))
	side.Name = "Side"

	-- Formulario --------------------------------------------------------------------------------
	local form = Instance.new("Frame")
	form.Name = "Form"
	form.Size = UDim2.fromScale(1, 1)
	form.BackgroundTransparency = 1
	form.Parent = side

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.Size = UDim2.new(1, 0, 0, PREVIEW + 6)
	top.BackgroundTransparency = 1
	top.Parent = form
	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Position = UDim2.fromOffset(4, 4)
	preview.Size = UDim2.fromOffset(PREVIEW, PREVIEW)
	preview.BackgroundTransparency = 1
	preview.Parent = top
	local title = Ui.label(top, 17)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(PREVIEW + 16, 2)
	title.Size = UDim2.new(1, -(PREVIEW + 20), 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = Color3.fromRGB(200, 205, 225)
	local name = Ui.label(top, 22)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(PREVIEW + 16, 26)
	name.Size = UDim2.new(1, -(PREVIEW + 20), 0, 50)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.TextWrapped = true
	name.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MaxTextSize = 22
	nameLimit.MinTextSize = 13
	nameLimit.Parent = name
	local odds = Ui.label(top, 18)
	odds.Name = "Odds"
	odds.Position = UDim2.fromOffset(PREVIEW + 16, 80)
	odds.Size = UDim2.new(1, -(PREVIEW + 20), 0, 22)
	odds.TextXAlignment = Enum.TextXAlignment.Left

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromOffset(0, PREVIEW + 6 + GAP)
	rows.Size = UDim2.new(1, 0, 0, #FIELDS * ROW + (#FIELDS - 1) * 6)
	rows.BackgroundTransparency = 1
	rows.Parent = form
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rows

	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.new(1, 0, 0, BOTTOM)
	bottom.BackgroundTransparency = 1
	bottom.Parent = form
	local amount = Instance.new("TextBox")
	amount.Name = "Amount"
	amount.Size = UDim2.new(0.22, -GAP, 1, 0)
	amount.TextSize = 22
	amount.ClearTextOnFocus = false
	amount.PlaceholderText = Lang.t(nil, "Amount")
	amount.Text = "1"
	amount.Parent = bottom
	Ui.field(amount)
	local max = Ui.button(bottom, Lang.t(nil, "Max everything"), Ui.COLORS.purple)
	max.Name = "Max"
	max.Position = UDim2.fromScale(0.22, 0)
	max.Size = UDim2.new(0.38, -GAP, 1, 0)
	fit(max, 17)
	local give = Ui.button(bottom, Lang.t(nil, "Give"), Ui.COLORS.green)
	give.Name = "Give"
	give.Position = UDim2.fromScale(0.6, 0)
	give.Size = UDim2.fromScale(0.4, 1)
	give.TextSize = 22

	-- Lista de opciones del campo pulsado: ocupa el sitio del formulario mientras se elige ------------
	local picker = Instance.new("Frame")
	picker.Name = "Picker"
	picker.Size = UDim2.fromScale(1, 1)
	picker.BackgroundTransparency = 1
	picker.Visible = false
	picker.Parent = side
	local pickTitle = Ui.label(picker, 20)
	pickTitle.Name = "Title"
	pickTitle.Position = UDim2.fromOffset(4, 0)
	pickTitle.Size = UDim2.new(1, -128, 0, ROW)
	pickTitle.TextXAlignment = Enum.TextXAlignment.Left
	local back = Ui.button(picker, Lang.t(nil, "Back"), Ui.COLORS.red)
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.fromScale(1, 0)
	back.Size = UDim2.fromOffset(116, ROW)
	back.TextSize = 17
	local choices = scroller(picker, "List")
	choices.Position = UDim2.fromOffset(0, ROW + GAP)
	choices.Size = UDim2.new(1, 0, 1, -(ROW + GAP))
	local choiceLayout = Instance.new("UIGridLayout")
	choiceLayout.CellSize = UDim2.new(0.5, -4, 0, ROW)
	choiceLayout.CellPadding = UDim2.fromOffset(8, 6)
	choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choiceLayout.Parent = choices

	local values: { [string]: TextButton } = {}
	local targetButtons: { [number]: TextButton } = {}
	local asked = 0 -- cuándo se pidió el "¿Seguro?" de dar a todos

	local function paint()
		if target ~= 0 and not Players:GetPlayerByUserId(target) then
			target = player.UserId
		end
		for userId, button in targetButtons do
			Ui.setSelected(button, userId == target)
		end
		local who = Players:GetPlayerByUserId(target)
		title.Text = if who then Lang.t(nil, "Give to {name}", { name = who.DisplayName }) else Lang.t(nil, "Give to everyone on this server")
		for _, field in FIELDS do
			local text, color = look(field, chosen[field.key])
			values[field.key].Text = text
			values[field.key].BackgroundColor3 = color:Lerp(BLACK, 0.25)
		end
		-- La casilla es la de la mochila (lazy: Backpack se monta en su start), con su cartel al pasar el ratón.
		local copy = {
			id = 0,
			sword = chosen.sword,
			metal = if chosen.metal > 0 then chosen.metal else nil,
			size = if chosen.size > 0 then chosen.size else nil,
			trait = if chosen.trait > 0 then chosen.trait else nil,
			grade = if chosen.grade > 0 then chosen.grade else nil,
		}
		preview:ClearAllChildren()
		local swordCell = (require(script.Parent.Backpack) :: any).swordCell
		if swordCell then
			local cell = swordCell(preview, copy, false, false)
			cell.Name = "Cell"
			cell.Size = UDim2.fromScale(1, 1)
		end
		local tier = Rarity.tier(Permanent.rarity(chosen.sword, copy.metal, copy.size))
		name.Text = Permanent.name(chosen.sword, copy.metal, copy.size)
		name.TextColor3 = tier.color:Lerp(Color3.new(1, 1, 1), 0.35)
		odds.Text = `<font color="{Ui.SOFT}">{Permanent.describeOdds(chosen.sword, copy.metal, copy.size)}</font>`
		give.Text = Lang.t(nil, if os.clock() - asked <= CONFIRM_TIME then "Sure?" else "Give")
	end

	local function openPicker(field)
		for _, child in choices:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		pickTitle.Text = Lang.t(nil, field.name)
		for order, index in options(field) do
			local text, color = look(field, index)
			local option = Ui.button(choices, text, color:Lerp(BLACK, 0.25))
			option.Name = "Option_" .. index
			option.LayoutOrder = order
			fit(option, 17)
			Ui.setSelected(option, index == chosen[field.key])
			option.Activated:Connect(function()
				chosen[field.key] = index
				picker.Visible = false
				form.Visible = true
				paint()
			end)
		end
		choices.CanvasPosition = Vector2.zero
		form.Visible = false
		picker.Visible = true
	end
	back.Activated:Connect(function()
		picker.Visible = false
		form.Visible = true
	end)

	for order, field in FIELDS do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. field.key
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ROW)
		row.BackgroundTransparency = 1
		row.Parent = rows
		local label = Ui.label(row, 18)
		label.Name = "Label"
		label.Position = UDim2.fromOffset(4, 0)
		label.Size = UDim2.new(0.3, -8, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = Lang.t(nil, field.name)
		local value = Ui.button(row, "", PLAIN)
		value.Name = "Value"
		value.Position = UDim2.fromScale(0.3, 0)
		value.Size = UDim2.fromScale(0.7, 1)
		fit(value, 18)
		values[field.key] = value
		value.Activated:Connect(function()
			openPicker(field)
		end)
	end

	max.Activated:Connect(function()
		chosen.sword = best(Config.Swords, "damage")
		for _, field in FIELDS do
			if field.top then
				chosen[field.key] = best(field.list, field.top)
			end
		end
		paint()
	end)

	give.Activated:Connect(function()
		local count = tonumber(amount.Text)
		if not count or count < 1 or count > MAX_AMOUNT then
			Sfx.play("error")
			Ui.toast(Lang.t(nil, "Type an amount from 1 to {n}", { n = MAX_AMOUNT }), Ui.COLORS.orange)
			return
		end
		-- Dar a todo el servidor pide un segundo toque.
		if target == 0 and os.clock() - asked > CONFIRM_TIME then
			asked = os.clock()
			task.delay(CONFIRM_TIME + 0.1, paint)
			paint()
			return
		end
		asked = 0
		Remotes.AdminCommand:FireServer("sword", target, table.clone(chosen), math.floor(count))
		paint()
	end)

	local function addTarget(userId: number, text: string, color: Color3, order: number)
		if targetButtons[userId] then
			return
		end
		local button = Ui.button(targets, text, color)
		button.Name = "Target_" .. userId
		button.LayoutOrder = order
		button.Size = UDim2.new(1, 0, 0, ROW)
		button.TextSize = 16
		button.TextTruncate = Enum.TextTruncate.AtEnd
		targetButtons[userId] = button
		button.Activated:Connect(function()
			target = userId
			asked = 0
			paint()
		end)
	end
	addTarget(0, Lang.t(nil, "Everyone"), Ui.COLORS.purple, 0)
	local function addPlayer(other: Player)
		addTarget(other.UserId, other.DisplayName, if other == player then Ui.COLORS.orange else Ui.COLORS.gray, if other == player then 1 else 2)
	end
	Players.PlayerAdded:Connect(function(other)
		addPlayer(other)
		paint()
	end)
	Players.PlayerRemoving:Connect(function(other)
		local button = targetButtons[other.UserId]
		if button then
			targetButtons[other.UserId] = nil
			button:Destroy()
		end
		paint()
	end)
	for _, other in Players:GetPlayers() do
		addPlayer(other)
	end

	-- La casilla del arma sale de la mochila, que puede montarse después que este panel: se pinta al enseñarlo.
	pane:GetPropertyChangedSignal("Visible"):Connect(function()
		if pane.Visible then
			paint()
		end
	end)
	paint()
end

return AdminWeapons
