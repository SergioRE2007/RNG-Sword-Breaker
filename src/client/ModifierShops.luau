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
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ForgeScene = require(script.Parent.ForgeScene)
local Ui = require(script.Parent.Ui)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local WeaponCell = require(script.Parent.WeaponCell)

local ModifierShops = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SIZE = Vector2.new(1160, 640)
-- Filas de la lista de resultados (118 de alto): el logo cuadrado y centrado en altura, y el texto a su derecha.
local ICON_SIZE = 84
local ICON_X, ICON_Y = 14, (118 - 84) / 2
local TEXT_X = 112
local LEFT = 0.53 -- parte del ancho del cuerpo que ocupa la izquierda (Scale)
-- Capas de la izquierda, de abajo arriba. La interfaz ordena el ZIndex globalmente, así que son
-- valores absolutos: la ruleta tapa la información de la espada, pero nunca BottomControls (que
-- está fuera de su área), y las capas de elegir espada / parar con tapan todo lo demás.
local Z = {
	controls = 3, -- BottomControls
	roulette = 10, -- fondo y título de la ruleta
	column = 11, -- marco de cada columna
	card = 12, -- TraitCards de la tira
	cardText = 13,
	fade = 14, -- fundido arriba y abajo de cada columna
	shade = 15, -- oscurecido de las columnas que no ganan
	selector = 16, -- marco blanco y flechas, una capa aparte por encima de todo lo de la columna
	-- (sobresale de la columna, así que no lo tapa el oscurecido: se apaga él solo)
	skip = 20, -- botón invisible para saltar la ruleta
	overlay = 30, -- "Elige una espada" y "Parar con" (tapan toda la izquierda)
}
local AUTO_DELAY = 0.2 -- segundos entre tiradas automáticas
local CLOSE_DISTANCE = 30 -- se cierra al alejarse del puesto
local OPEN_DISTANCE = 10 -- se abre sola al acercarse a la estación (la tecla E sigue valiendo)
-- Tipos de rasgo en el orden de desempate (los colores, los de sus rasgos de nivel I).
local PRIORITY_NAMES = { luck = Lang.t(nil, "Luck"), coins = Lang.t(nil, "Coins"), damage = Lang.t(nil, "Damage") }
local PRIORITY_COLORS = { luck = Color3.fromRGB(150, 230, 90), coins = Color3.fromRGB(110, 220, 120), damage = Color3.fromRGB(90, 210, 230) }

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
local breathing = {} -- [UIScale] = fase: la letra de un botón marcado de "Parar con" late
local SHINE_EVERY = 4.5 -- segundos entre dos brillos de la misma fila
local SHINE_TIME = 0.7 -- lo que tarda el brillo en cruzar
local SPARKLE_EVERY = 1.6 -- segundos entre chispas de una fila rara

-- Con `entry`, si la entrada trae sus dos tonos (Config: tones) van esos en vez del arcoíris.
local function rainbow(parent: Instance, entry: any?)
	local gradient = Instance.new("UIGradient")
	gradient.Color = Modifiers.tones(entry) or rainbowColors()
	gradient.Parent = parent
	spinning[gradient] = true
end

-- Orden de la lista de resultados: los grados, del más raro al más común; los rasgos por tipo
-- (Especiales, Monedas, Daño, Suerte), cada tipo del más raro al más común. Devuelve una lista
-- de { header = texto } y { index = posición en la lista de Config }.
local GROUPS = {
	{ icon = "all", title = Lang.t(nil, "Specials") },
	{ icon = "coins", title = Lang.t(nil, "Coins") },
	{ icon = "damage", title = Lang.t(nil, "Damage") },
	{ icon = "luck", title = Lang.t(nil, "Luck") },
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

-- Insignia de un rasgo: el logo de lo que sube (moneda, espada, trébol; los especiales, el suyo propio), sin círculos
-- alrededor (pedido por el usuario: con el medallón los logos quedaban apretados). Los de nivel (I, II, III) llevan
-- abajo tantas estrellitas como su nivel, para distinguirlos sin leer.
local COIN = Color3.fromRGB(255, 205, 60)
local function traitBadge(parent: GuiObject, entry)
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = UDim2.fromScale(1, 1)
	badge.BackgroundTransparency = 1
	badge.Parent = parent
	local square = Instance.new("UIAspectRatioConstraint")
	square.Parent = badge

	local art = Instance.new("Frame")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1.2, 1.2)
	art.BackgroundTransparency = 1
	art.Parent = badge
	local logo = Ui.traitLogo(entry)
	if logo then
		Ui.image(art, logo)
	else
		local _, pieces = Ui.hex(badge, 22, if entry.rainbow then WHITE else entry.color)
		for _, piece in pieces do
			if entry.rainbow then
				rainbow(piece, entry)
			end
		end
	end

	local level = #(string.match(entry.name, " (I+)$") or "")
	if level > 0 then
		local pips = Instance.new("Frame")
		pips.Name = "Level"
		pips.AnchorPoint = Vector2.new(0.5, 0.5)
		pips.Position = UDim2.fromScale(0.5, 0.96)
		pips.Size = UDim2.fromScale(0.9, 0.22)
		pips.BackgroundTransparency = 1
		pips.Parent = badge
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Padding = UDim.new(0.04, 0)
		row.Parent = pips
		for _ = 1, level do
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromScale(0.62, 0.62)
			pip.Rotation = 45
			pip.BackgroundColor3 = WHITE
			pip.BorderSizePixel = 0
			pip.Parent = pips
			local pipSquare = Instance.new("UIAspectRatioConstraint")
			pipSquare.DominantAxis = Enum.DominantAxis.Height
			pipSquare.Parent = pip
			Ui.gradient(pip, COIN:Lerp(WHITE, 0.4), COIN, 90)
			Ui.stroke(pip, BLACK, 1.5)
		end
	end
end

-- Icono de una entrada: la letra del grado, o la insignia del rasgo.
local function entryIcon(parent: GuiObject, kind: string, entry)
	if kind == "grades" then
		-- El ∞ de la fuente es un dibujo pequeño: va más grande para pesar lo mismo que las letras.
		local letter = Ui.label(parent, if entry.name == "∞" then 72 else 48)
		letter.Size = UDim2.fromScale(1, 1)
		letter.Text = Lang.t(nil, entry.name)
		letter.TextColor3 = if entry.rainbow then WHITE else entry.color
		if entry.rainbow then
			rainbow(letter, entry)
		end
		return
	end
	traitBadge(parent, entry)
end

-- Texto con el nombre de la entrada, en su color (o arcoíris).
local function paintName(label: TextLabel, entry)
	local old = label:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	if not entry then
		label.Text = Lang.t(nil, "None")
		label.TextColor3 = Color3.fromRGB(150, 150, 160)
		return
	end
	label.Text = Lang.t(nil, entry.name)
	label.TextColor3 = if entry.rainbow then WHITE else entry.color
	if entry.rainbow then
		rainbow(label, entry)
	end
end

local function buildShop(kind: string)
	local info = Modifiers.KINDS[kind]
	local windowName = info.title
	local window, body = Ui.window(windowName, Lang.t(nil, info.title), SIZE)
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

	local state = { selected = nil, auto = false, waiting = false, last = nil, stop = {}, count = 1 }
	state.priority = Modifiers.priority(player:GetAttribute("TraitPriority"))
	for index, entry in info.list do
		state.stop[index] = Modifiers.percent(kind, index) < 1 and not entry.noStop
	end
	-- "Parar con" guardado (llega al entrar, y puede tardar más que la ventana): se aplica una sola vez; después manda lo
	-- que el jugador va marcando.
	local stopAttribute = "StopAt_" .. kind
	local stopsLoaded = false
	local stopPaints = {} -- [índice] = repinta ese botón de "Parar con"
	local function loadStops()
		local saved = Modifiers.stops(kind, player:GetAttribute(stopAttribute))
		if stopsLoaded or not saved then
			return
		end
		stopsLoaded = true
		for index in info.list do
			state.stop[index] = table.find(saved, index) ~= nil
		end
		for _, repaint in stopPaints do
			repaint()
		end
	end
	loadStops()
	-- Guarda "Parar con" y el desempate al tocarlos (pedido por el usuario: se perdían al salir del juego).
	local function savePrefs()
		stopsLoaded = true
		local marked = {}
		for index = 1, #info.list do
			if state.stop[index] then
				table.insert(marked, index)
			end
		end
		Remotes.SetModifierPrefs:FireServer(kind, table.concat(marked, ","), if kind == "traits" then table.concat(state.priority, ",") else nil)
	end

	-- Izquierda: arriba "Main" (la espada elegida y su rasgo; la ruleta lo tapa al tirar) y abajo
	-- "BottomControls", un contenedor aparte que la ruleta nunca puede cubrir.
	-- Dos tarjetas gemelas detrás de cada lado, translúcidas para que se vean las rayas del cuerpo:
	-- el mismo fondo a izquierda y derecha, con relieve (degradado, brillo y canto) en vez de plano.
	for _, side in { { "LeftBack", 0, 6, LEFT, -9 }, { "RightBack", LEFT, 3, 1 - LEFT, -9 } } do
		local card = Instance.new("Frame")
		card.Name = side[1]
		card.Position = UDim2.new(side[2], side[3], 0, 6)
		card.Size = UDim2.new(side[4], side[5], 1, -12)
		card.Parent = body
		Ui.round(card, 12)
		Ui.panel(card, Color3.fromRGB(34, 38, 74))
		card.BackgroundTransparency = 0.35
		Ui.stroke(card, BLACK, 2).Transparency = 0.35
	end

	local left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = UDim2.fromScale(LEFT, 1)
	left.BackgroundTransparency = 1
	left.Parent = body
	local leftPadding = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(leftPadding :: any)[side] = UDim.new(0, 14)
	end
	leftPadding.Parent = left

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(1, 0.8)
	main.BackgroundTransparency = 1
	main.Parent = left
	-- Información de la espada; se oculta mientras la ruleta ocupa "Main".
	local swordInfo = Instance.new("Frame")
	swordInfo.Name = "Info"
	swordInfo.Size = UDim2.fromScale(1, 1)
	swordInfo.BackgroundTransparency = 1
	swordInfo.Parent = main

	local controls = Instance.new("Frame")
	controls.Name = "BottomControls"
	controls.AnchorPoint = Vector2.new(0, 1)
	controls.Position = UDim2.fromScale(0, 1)
	controls.Size = UDim2.fromScale(1, 0.17)
	controls.BackgroundTransparency = 1
	controls.ZIndex = Z.controls
	controls.Parent = left
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0.02, 0)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controls

	-- Casilla de la espada elegida (cuadrada: manda el ancho).
	local slot = Ui.cell(swordInfo, Color3.fromRGB(230, 230, 240))
	slot.Name = "Slot"
	slot.Size = UDim2.fromScale(0.35, 0.5)
	local slotAspect = Instance.new("UIAspectRatioConstraint")
	slotAspect.DominantAxis = Enum.DominantAxis.Width
	slotAspect.Parent = slot
	-- Al pasar el ratón: estadísticas de la espada elegida (el mismo cartel que en la mochila).
	Ui.tip(slot, function()
		for _, copy in Stats.swords(player) do
			if copy.id == state.selected then
				return WeaponCell.tip(copy)
			end
		end
		return Lang.t(nil, "Click to pick a sword"), WHITE
	end)
	local slotHint = Ui.label(slot, 19)
	slotHint.AnchorPoint = Vector2.new(0.5, 1)
	slotHint.Position = UDim2.new(0.5, 0, 1, -6)
	slotHint.Size = UDim2.new(1, -8, 0.13, 0)
	slotHint.TextScaled = true
	slotHint.ZIndex = 3

	local heading = Ui.label(swordInfo, 30)
	heading.Position = UDim2.fromScale(0.385, 0)
	heading.Size = UDim2.fromScale(0.615, 0.1)
	heading.Text = Lang.t(nil, info.label)

	local nameBox = Instance.new("Frame")
	nameBox.Name = "Current"
	nameBox.Position = UDim2.fromScale(0.385, 0.115)
	nameBox.Size = UDim2.fromScale(0.615, 0.19)
	nameBox.BackgroundColor3 = Ui.COLORS.dark
	nameBox.Parent = swordInfo
	Ui.round(nameBox, 10)
	Ui.stroke(nameBox, Color3.fromRGB(90, 90, 100), 3)
	local nameScale = Instance.new("UIScale")
	nameScale.Parent = nameBox
	local nameLabel = Ui.label(nameBox, 38)
	nameLabel.Size = UDim2.fromScale(1, 1)

	local effect = Ui.label(swordInfo, 21)
	effect.Position = UDim2.fromScale(0.385, 0.33)
	effect.Size = UDim2.fromScale(0.615, 0.075)

	local cost = Ui.label(swordInfo, 24)
	cost.Name = "Cost"
	cost.Position = UDim2.fromScale(0, 0.56)
	cost.Size = UDim2.fromScale(1, 0.09)

	local warning = Ui.label(swordInfo, 18)
	warning.Position = UDim2.fromScale(0, 0.67)
	warning.Size = UDim2.fromScale(1, 0.15)
	warning.TextWrapped = true
	warning.TextColor3 = Color3.fromRGB(200, 200, 210)
	warning.Text = Lang.t(nil, "Rolling changes the sword's {kind}.", { kind = string.lower(Lang.t(nil, info.label)) })

	-- Botones de abajo, repartidos por el UIListLayout (los anchos suman 1 con los huecos).
	local function control(name: string, text: string, color: Color3, order: number, width: number, textSize: number): TextButton
		local button = Ui.button(controls, text, color)
		button.Name = name
		button.LayoutOrder = order
		button.Size = UDim2.fromScale(width, 1)
		button.TextSize = textSize
		button.ZIndex = Z.controls
		return button
	end
	local traits = kind == "traits"
	local rollButton = control("Roll", Lang.t(nil, "Roll"), Ui.COLORS.blue, 1, if traits then 0.3 else 0.42, 28)
	local autoButton = control("Auto", "Auto", Ui.COLORS.red, 2, if traits then 0.3 else 0.42, 26)
	-- Rasgos: tirar 1 o 3 de golpe (se queda con el más raro). Sirve también para la tirada automática.
	local countButton = control("Count", "x1", Ui.COLORS.gray, 3, 0.19, 30)
	countButton.Visible = traits
	-- Engranaje: con qué resultados se para la tirada automática.
	local settingsButton = control("Settings", "", Ui.COLORS.gray, 4, if traits then 0.13 else 0.12, 24)
	Ui.image(settingsButton, "ajustes")
	-- Todo BottomControls en su capa; dentro, el orden del árbol pone relieve e iconos encima del botón.
	for _, descendant in controls:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = Z.controls
		end
	end

	-- "Volver" de cada capa en la escena de la forja (ver más abajo); fuera de ella solo cierra la capa.
	local backHandlers: { [string]: () -> () } = {}

	-- Capas que tapan la parte izquierda: elegir espada y elegir con qué se para el automático.
	local function overlay(name: string, titleText: string): (Frame, ScrollingFrame)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(LEFT, 1)
		-- Sin fondo propio: se ve la tarjeta de la izquierda (igual que la de la derecha) y lo de la
		-- izquierda se esconde mientras está abierta.
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.ZIndex = Z.overlay
		frame.Parent = body
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			left.Visible = not frame.Visible
		end)
		local title = Ui.label(frame, 26)
		title.Position = UDim2.fromOffset(0, 8)
		title.Size = UDim2.new(1, 0, 0, 30)
		title.Text = titleText
		title.ZIndex = Z.overlay + 1
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.Position = UDim2.fromOffset(12, 44)
		list.Size = UDim2.new(1, -24, 1, -124)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ZIndex = Z.overlay + 1
		list.Parent = frame
		-- Margen para que no se corten los bordes de las casillas.
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = list
		local back = Ui.button(frame, Lang.t(nil, "Back"), Ui.COLORS.red)
		back.Name = "Back"
		back.AnchorPoint = Vector2.new(0.5, 1)
		back.Position = UDim2.new(0.5, 0, 1, -10)
		back.Size = UDim2.fromOffset(180, 54)
		back.TextSize = 24
		Ui.layer(back, Z.overlay + 4) -- por encima de las casillas de la lista, con su relieve
		back.Activated:Connect(function()
			if state.onPick and backHandlers[name] then
				backHandlers[name]()
			else
				frame.Visible = false
			end
		end)
		return frame, list
	end

	local picker, pickerList = overlay("Picker", Lang.t(nil, "Pick a sword"))
	local pickerGrid = Instance.new("UIGridLayout")
	pickerGrid.CellSize = UDim2.fromOffset(84, 84)
	pickerGrid.CellPadding = UDim2.fromOffset(8, 8)
	pickerGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pickerGrid.Parent = pickerList

	local stopper, stopList = overlay("StopAt", Lang.t(nil, if kind == "traits" then "Settings" else "Stop at:"))
	local STOP_OFF = Color3.fromRGB(44, 46, 66) -- botón de un resultado sin marcar
	local STOP_HEIGHT = 68 -- alto de los botones de "Parar con" y de los del orden de prioridad (mismo tamaño)
	local stopGrid = Instance.new("UIGridLayout")
	stopGrid.CellSize = UDim2.new(1 / 3, -8, 0, STOP_HEIGHT) -- tres por fila; con las letras grandes pide más alto
	stopGrid.CellPadding = UDim2.fromOffset(12, 10)
	stopGrid.SortOrder = Enum.SortOrder.LayoutOrder
	stopGrid.Parent = stopList

	-- Rasgos: arriba del todo, el orden de desempate. Si en "mejor de tres" salen dos igual de raros
	-- (Monedas II y Suerte II), se queda el tipo que va antes. Pulsar uno lo sube un puesto. Se manda
	-- con cada tirada y el servidor lo guarda.
	local priorityChips = {}
	local function paintPriority()
		for rank, stat in state.priority do
			local chip = priorityChips[stat]
			chip.LayoutOrder = rank
			chip.Text = Lang.t(nil, "{rank}. {name}", { rank = rank, name = PRIORITY_NAMES[stat] })
		end
	end
	if kind == "traits" then
		local section = Instance.new("Frame")
		section.Name = "Priority"
		section.Position = UDim2.fromOffset(12, 44)
		section.Size = UDim2.new(1, -24, 0, 30 + STOP_HEIGHT)
		section.BackgroundTransparency = 1
		section.ZIndex = Z.overlay + 1
		section.Parent = stopper
		local hint = Ui.label(section, 18)
		hint.Size = UDim2.new(1, 0, 0, 24)
		hint.TextColor3 = Color3.fromRGB(200, 200, 210)
		hint.Text = Lang.t(nil, "On a tie, the top one wins. Click to move up:")
		hint.TextScaled = true
		hint.ZIndex = Z.overlay + 1
		local hintLimit = Instance.new("UITextSizeConstraint")
		hintLimit.MaxTextSize = 18
		hintLimit.Parent = hint
		local row = Instance.new("Frame")
		row.Name = "Order"
		row.Position = UDim2.fromOffset(0, 30)
		row.Size = UDim2.new(1, 0, 0, STOP_HEIGHT)
		row.BackgroundTransparency = 1
		row.ZIndex = Z.overlay + 1
		row.Parent = section
		-- Misma rejilla que "Parar con", para que los botones del orden midan lo mismo que los de abajo.
		local rowLayout = Instance.new("UIGridLayout")
		rowLayout.CellSize = stopGrid.CellSize
		rowLayout.CellPadding = stopGrid.CellPadding
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row
		for _, stat in Modifiers.PRIORITY do
			-- Cada tipo, un botón de su color con el texto en blanco (en gris oscuro con letras de color se leía mal).
			local chip = Ui.button(row, "", PRIORITY_COLORS[stat]:Lerp(Color3.new(0, 0, 0), 0.35))
			chip.Name = stat
			chip.TextScaled = true
			local chipLimit = Instance.new("UITextSizeConstraint")
			chipLimit.MaxTextSize = 30 -- el texto del orden es más largo ("2º MONEDAS") que los nombres de abajo
			chipLimit.MinTextSize = 9
			chipLimit.Parent = chip
			local chipPadding = Instance.new("UIPadding")
			chipPadding.PaddingLeft, chipPadding.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
			chipPadding.PaddingTop, chipPadding.PaddingBottom = UDim.new(0, 4), UDim.new(0, 8)
			chipPadding.Parent = chip
			Ui.layer(chip, Z.overlay + 2)
			priorityChips[stat] = chip
			chip.Activated:Connect(function()
				local rank = table.find(state.priority, stat)
				if rank and rank > 1 then
					state.priority[rank], state.priority[rank - 1] = state.priority[rank - 1], stat
					paintPriority()
					savePrefs()
				end
			end)
		end
		paintPriority()
		-- La lista de "parar con" va debajo, con su propio título.
		local stopTitle = Ui.label(stopper, 20)
		stopTitle.Position = UDim2.fromOffset(12, 44 + 30 + STOP_HEIGHT + 6)
		stopTitle.Size = UDim2.new(1, -24, 0, 26)
		stopTitle.Text = Lang.t(nil, "Stop at:")
		stopTitle.ZIndex = Z.overlay + 1
		stopList.Position = UDim2.fromOffset(12, 44 + 30 + STOP_HEIGHT + 36)
		stopList.Size = UDim2.new(1, -24, 1, -(44 + 30 + STOP_HEIGHT + 36 + 80))
	end
	for position, item in displayOrder(kind) do
		local index = item.index
		if not index then
			continue
		end
		local entry = info.list[index]
		if entry.noStop then
			continue -- Rasgos I y II no salen en "Parar con" (pedido por el usuario: solo los III o mejores)
		end
		-- Pedido por el usuario (verde entero con el nombre en su color no se leía y quedaba feo): apagado, botón
		-- oscuro con el nombre en el color del rasgo o grado; elegido, el botón entero de ese color con el nombre en
		-- blanco, borde claro y una marca verde en la esquina. El nombre se encoge para caber en una línea.
		local tone = if entry.rainbow then Color3.fromRGB(190, 110, 255) else entry.color
		local toggle = Ui.button(stopList, "", STOP_OFF)
		toggle.Name = "Stop" .. index
		toggle.LayoutOrder = position
		-- El nombre va en una etiqueta de dentro, con margen a los lados y por encima del labio del botón.
		local name = Ui.label(toggle, 20)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(8, 2)
		name.Size = UDim2.new(1, -16, 1, -8)
		name.Text = Lang.t(nil, entry.name)
		name.TextScaled = true
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = math.clamp(math.floor(146 / (utf8.len(name.Text) :: number * 0.74)), 9, 38) -- pedido por el usuario: las letras de los grados (∞, X, Z+...) se veían chicas; el nombre largo se encoge según sus letras para no partirse en dos líneas ("TRASCENDENTE")
		nameLimit.MinTextSize = 9
		nameLimit.Parent = name
		Ui.layer(toggle, Z.overlay + 2)
		local stroke: UIStroke? = nil -- el borde del botón (el otro UIStroke es el del texto)
		for _, child in toggle:GetChildren() do
			if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
				stroke = child
			end
		end
		local check = Ui.label(toggle, 15)
		check.Name = "Check"
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, 5, 0, -5)
		check.Size = UDim2.fromOffset(22, 22)
		check.BackgroundTransparency = 0
		check.BackgroundColor3 = Color3.fromRGB(70, 210, 90)
		check.Text = "✓"
		check.ZIndex = Z.overlay + 3
		Ui.round(check, 11)
		Ui.stroke(check, Color3.new(0, 0, 0), 2)
		-- Borde animado como el de la lista de la derecha (pedido por el usuario), solo con el botón marcado: arcoíris
		-- que gira en las especiales y latido en las muy raras. Apagado, el borde sigue negro y quieto.
		local spinGradient: UIGradient? = nil
		local letterGradient: UIGradient? = nil
		local letterScale = Instance.new("UIScale")
		letterScale.Parent = name
		if entry.rainbow then
			rainbow(name, entry)
			letterGradient = name:FindFirstChildOfClass("UIGradient")
		end
		local pulses = false
		local baseThickness, baseTransparency = 0, 0
		if stroke then
			baseThickness, baseTransparency = stroke.Thickness, stroke.Transparency
			if entry.rainbow then
				rainbow(stroke, entry)
				spinGradient = stroke:FindFirstChildOfClass("UIGradient")
			else
				pulses = Modifiers.percent(kind, index) < 0.1
			end
		end
		local function paint()
			local on = state.stop[index] == true
			toggle.BackgroundColor3 = if on then tone:Lerp(Color3.new(0, 0, 0), 0.3) else STOP_OFF
			name.TextColor3 = if on then WHITE else tone:Lerp(WHITE, 0.15)
			check.Visible = on
			-- La letra, como el icono de la lista: arcoíris que corre en las especiales y un latido suave.
			if letterGradient then
				letterGradient.Enabled = on
			end
			breathing[letterScale] = if on then position * 0.9 else nil
			if not on then
				letterScale.Scale = 1
			end
			if stroke then
				stroke.Color = if not on then Color3.new(0, 0, 0) elseif entry.rainbow then WHITE else tone:Lerp(WHITE, 0.55)
				if spinGradient then
					spinGradient.Enabled = on
				end
				if pulses then
					pulsing[stroke] = if on then index else nil
					if not on then
						stroke.Thickness, stroke.Transparency = baseThickness, baseTransparency
					end
				end
			end
		end
		toggle.Activated:Connect(function()
			state.stop[index] = not state.stop[index]
			paint()
			savePrefs()
		end)
		stopPaints[index] = paint
		paint()
	end

	-- Lista de resultados posibles (derecha), en el orden de displayOrder.
	local results = Instance.new("ScrollingFrame")
	results.Name = "Results"
	results.Position = UDim2.new(LEFT, 8, 0, 8)
	results.Size = UDim2.new(1 - LEFT, -16, 1, -16)
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
	local adminPicks = {} -- [índice] = botón invisible sobre la fila (modo admin)
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
		row.Size = UDim2.new(1, -8, 0, 118)
		row.BackgroundColor3 = WHITE
		row.Parent = results
		Ui.round(row, 10)
		Ui.panel(row, Color3.fromRGB(46, 46, 62), if entry.rainbow then WHITE else entry.color)
		local stroke = Ui.stroke(row, if entry.rainbow then WHITE else entry.color, 3)
		if entry.rainbow then
			rainbow(stroke, entry)
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
		iconBox.Position = UDim2.fromOffset(ICON_X, ICON_Y)
		iconBox.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
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
			rainbow(pillStroke, entry)
		end
		local percent = Ui.label(pill, 22)
		percent.Size = UDim2.fromScale(1, 1)
		percent.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 22
		limit.Parent = percent
		percent.Text = Modifiers.formatPercent(Modifiers.percent(kind, index))
		local title = Ui.label(row, 30)
		title.Position = UDim2.fromOffset(TEXT_X, 8)
		title.Size = UDim2.new(1, -TEXT_X - 124, 0, 34)
		title.TextXAlignment = Enum.TextXAlignment.Left
		paintName(title, entry)
		if kind == "grades" then
			title.Text = Lang.t(nil, "Grade {name}", { name = Lang.t(nil, entry.name) })
		end
		if not entry.rainbow then
			-- Degradado de blanco al color de la entrada: más llamativo que el color liso.
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new(entry.color:Lerp(WHITE, 0.55), entry.color)
			gradient.Parent = title
		end
		local detail = Ui.label(row, 26)
		detail.Position = UDim2.fromOffset(TEXT_X, 46)
		detail.Size = UDim2.new(1, -TEXT_X - 12, 0, 32)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextColor3 = Color3.fromRGB(120, 235, 120)
		detail.Text = Modifiers.effect(entry)
		detail.TextScaled = true
		local detailLimit = Instance.new("UITextSizeConstraint")
		detailLimit.MaxTextSize = 26
		detailLimit.Parent = detail
		local pityLabel = Ui.label(row, 21)
		pityLabel.Name = "Pity"
		pityLabel.Position = UDim2.fromOffset(TEXT_X, 82)
		pityLabel.Size = UDim2.new(1, -TEXT_X - 12, 0, 28)
		pityLabel.TextXAlignment = Enum.TextXAlignment.Left
		pityLabel.TextScaled = true
		local pityLimit = Instance.new("UITextSizeConstraint")
		pityLimit.MaxTextSize = 21
		pityLimit.Parent = pityLabel
		pityLabel.TextColor3 = Color3.fromRGB(190, 195, 215)
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
		-- Modo admin (pruebas): con él encendido, pulsar la fila pone ese resultado en la espada elegida.
		local pick = Instance.new("TextButton")
		pick.Name = "AdminPick"
		pick.Text = ""
		pick.Size = UDim2.fromScale(1, 1)
		pick.BackgroundTransparency = 1
		pick.Visible = false
		pick.ZIndex = row.ZIndex
		pick.Parent = row
		adminPicks[index] = pick
		pick.Activated:Connect(function()
			local id = state.selected or player:GetAttribute("Equipped")
			Remotes.AdminSetModifier:FireServer(kind, id, index)
			Sfx.play("buy")
			Ui.toast(Lang.t(nil, "Admin: {name} set", { name = Lang.t(nil, entry.name) }), entry.color)
		end)
	end

	-- Botón "Admin" en la cabecera: solo se ve si el servidor dice que este jugador es admin (pruebas en
	-- Studio, Config.Test.Admin). Encendido, la lista de la derecha se puede pulsar; "Quitar" lo borra.
	local adminOn = false
	local adminButton = Ui.button((header or window) :: Instance, "Admin", Ui.COLORS.gray)
	adminButton.Name = "Admin"
	adminButton.AnchorPoint = Vector2.new(1, 0.5)
	adminButton.Position = UDim2.new(1, -86, 0.5, 0)
	adminButton.Size = UDim2.fromOffset(150, 40)
	adminButton.TextSize = 20
	local adminClear = Ui.button((header or window) :: Instance, Lang.t(nil, "Remove"), Ui.COLORS.red)
	adminClear.Name = "AdminClear"
	adminClear.AnchorPoint = Vector2.new(1, 0.5)
	adminClear.Position = UDim2.new(1, -244, 0.5, 0)
	adminClear.Size = UDim2.fromOffset(96, 40)
	adminClear.TextSize = 20
	local function paintAdmin()
		local allowed = player:GetAttribute("ModifierAdmin") == true
		if not allowed then
			adminOn = false
		end
		adminButton.Visible = allowed
		adminClear.Visible = allowed and adminOn
		adminButton.Text = "Admin: " .. Lang.t(nil, if adminOn then "YES" else "NO")
		adminButton.BackgroundColor3 = if adminOn then Ui.COLORS.orange else Ui.COLORS.gray
		for _, pick in adminPicks do
			pick.Visible = adminOn
		end
	end
	adminButton.Activated:Connect(function()
		adminOn = not adminOn
		paintAdmin()
		if adminOn then
			Ui.toast(Lang.t(nil, if kind == "traits" then "Admin: click a trait in the list to set it" else "Admin: click a grade in the list to set it"), Ui.COLORS.orange)
		end
	end)
	adminClear.Activated:Connect(function()
		Remotes.AdminSetModifier:FireServer(kind, state.selected or player:GetAttribute("Equipped"), 0)
		Ui.toast(Lang.t(nil, "Admin: removed"), Ui.COLORS.red)
	end)
	player:GetAttributeChangedSignal("ModifierAdmin"):Connect(paintAdmin)
	paintAdmin()

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
			return (player:GetAttribute("Item_traitCrystal") or 0) >= state.count
		end
		return (player:GetAttribute("Item_gradeCrystal") or 0) >= Config.GradeCost
	end

	local function refresh()
		local ok, counters = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Pity_" .. kind) or "[]")
		for index, row in rows do
			row.Pity.Visible = Modifiers.hasPity(kind, index) -- los fáciles no tienen pity
			local limit = Modifiers.pityLimit(kind, index)
			local progress = if ok and type(counters) == "table" then counters[index] or 0 else 0
			row.Pity.Text = Lang.t(nil, "Pity {n} / {max}", { n = Format.short(progress), max = Format.short(limit) }) .. (if progress >= limit then " · " .. Lang.t(nil, "Ready!") else "")
			row.Pity.TextColor3 = if progress >= limit then Ui.COLORS.orange else Color3.fromRGB(190, 195, 215)
		end
		local copy = selectedCopy()
		if not copy then
			state.selected = player:GetAttribute("Equipped")
			copy = selectedCopy()
		end
		if copy then
			local tierColor = Rarity.tier(Stats.rarity(copy)).color
			-- La casilla de siempre (client/WeaponCell), pintada dentro de la de la tienda: se rehace si cambia algo
			-- de lo que enseña (también el rasgo o el grado que acaba de salir).
			local look = WeaponCell.key(copy)
			if state.shown ~= look then
				state.shown = look
				WeaponCell.fill(slot, copy)
			end
			slot:FindFirstChildOfClass("UIStroke").Color = tierColor
			slotHint.Text = ""
			if not state.waiting then
				local current = info.list[copy[info.field]]
				paintName(nameLabel, current)
				effect.Text = if current then Modifiers.effect(current) else ""
			end
		else
			if state.shown then
				state.shown = nil
				WeaponCell.clear(slot)
			end
			slotHint.Text = Lang.t(nil, "Pick sword")
		end
		if kind == "traits" then
			cost.Text = Lang.t(nil, "Crystals: {n}", { n = Format.short(player:GetAttribute("Item_traitCrystal") or 0) })
			countButton.Text = `x{state.count}`
			countButton.BackgroundColor3 = if state.count > 3 then Ui.COLORS.purple elseif state.count == 3 then Ui.COLORS.orange else Ui.COLORS.gray
		else
			cost.Text = Lang.t(nil, "Crystals: {n}", { n = Format.short(player:GetAttribute("Item_gradeCrystal") or 0) })
		end
		cost.TextColor3 = if canAfford() then WHITE else Ui.COLORS.red
		rollButton.BackgroundColor3 = if canAfford() and copy then Ui.COLORS.blue else Ui.COLORS.gray
		autoButton.Text = Lang.t(nil, if state.auto then "Stop" else "Auto")
		autoButton.BackgroundColor3 = if state.auto then Ui.COLORS.orange else Ui.COLORS.red
	end

	local function rebuildPicker()
		for _, child in pickerList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local worn = Stats.list(player, "Loadout")
		-- Como en la mochila: de más a menos daño; a igualdad, la más rara (arma, metal y tamaño) primero.
		local copies = Stats.swords(player)
		table.sort(copies, function(a, b)
			local damageA, damageB = Stats.swordDamage(a), Stats.swordDamage(b)
			if damageA ~= damageB then
				return damageA > damageB
			end
			local rarityA, rarityB = Stats.rarity(a), Stats.rarity(b)
			if rarityA ~= rarityB then
				return rarityA > rarityB
			end
			return a.id < b.id
		end)
		for position, copy in copies do
			local cell = WeaponCell.create(pickerList, copy)
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = position
			cell.ZIndex = Z.overlay + 2
			for _, descendant in cell:GetDescendants() do
				if descendant:IsA("GuiObject") then
					descendant.ZIndex = Z.overlay + 3
				end
			end
			cell.Activated:Connect(function()
				state.selected = copy.id
				picker.Visible = false
				refresh()
				if state.onPick then
					state.onPick()
				end
			end)
		end
	end

	-- Animación del resultado: pasan nombres al azar y se para en el que ha tocado.
	-- Pase de juego: las tiradas de grado van más rápido (gradeSpeed; 4 = 400 %). Acorta la animación y la
	-- espera entre tiradas automáticas; el servidor acorta igual su tiempo mínimo.
	local function speed(): number
		return if kind == "grades" then Stats.perk(player, "gradeSpeed") or 1 else 1
	end

	local function reveal(index: number)
		local entry = info.list[index]
		local fast = speed()
		for _ = 1, math.max(1, math.round(4 / fast)) do
			paintName(nameLabel, info.list[Modifiers.roll(kind, random)])
			task.wait(0.03 / fast)
		end
		paintName(nameLabel, entry)
		effect.Text = Modifiers.effect(entry)
		nameScale.Scale = 1.3
		TweenService:Create(nameScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local row = rows[index]
		local flash = TweenService:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { BackgroundColor3 = entry.color })
		flash:Play()
		if Modifiers.percent(kind, index) < 1 then
			Ui.toast(Lang.t(nil, "{name}! ({percent})", { name = Lang.t(nil, entry.name), percent = Modifiers.formatPercent(Modifiers.percent(kind, index)) }), entry.color)
		end
	end

	-- Ruleta vertical (solo rasgos), como las cajas de CS2: una o tres columnas de rasgos que giran
	-- muy rápido y frenan hasta parar cada una en su resultado; luego se destaca la mejor. Un clic
	-- en la ruleta la salta.
	local roulette: Frame? = nil
	local rouletteTitle: TextLabel? = nil
	local rouletteColumns: Frame? = nil
	local rouletteSkip = false
	local VISIBLE = 5 -- TraitCards que se ven a la vez en cada columna
	local STRIP_ITEMS = 36
	local LAND = 30 -- posición de la tira donde se para (la tira es larga para que haya recorrido)
	local COLUMN_GAP = 0.05 -- hueco entre columnas (Scale del área)
	if kind == "traits" then
		-- Ocupa todo "Main"; BottomControls queda fuera, debajo.
		local frame = Instance.new("Frame")
		frame.Name = "Roulette"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Ui.COLORS.body
		frame.Visible = false
		frame.ZIndex = Z.roulette
		frame.Parent = main
		Ui.round(frame, 10)
		Ui.panel(frame, Color3.fromRGB(52, 55, 74))
		Ui.stripes(frame, Vector2.new(492, 347), 26, 0.95, Z.roulette)
		roulette = frame
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			swordInfo.Visible = not frame.Visible
		end)
		rouletteTitle = Ui.label(frame, 26)
		rouletteTitle.Size = UDim2.fromScale(1, 0.1)
		rouletteTitle.ZIndex = Z.roulette
		-- Área de las columnas: el margen interior deja sitio a los bordes y a que la mejor columna
		-- crezca sin salirse; el UIListLayout las pone en fila y centradas.
		local area = Instance.new("Frame")
		area.Name = "Columns"
		area.Position = UDim2.fromScale(0, 0.11)
		area.Size = UDim2.fromScale(1, 0.89)
		area.BackgroundTransparency = 1
		area.ZIndex = Z.roulette
		area.Parent = frame
		local areaPadding = Instance.new("UIPadding")
		areaPadding.PaddingLeft = UDim.new(0, 12)
		areaPadding.PaddingRight = UDim.new(0, 12)
		areaPadding.PaddingTop = UDim.new(0, 12)
		areaPadding.PaddingBottom = UDim.new(0, 12)
		areaPadding.Parent = area
		local areaLayout = Instance.new("UIListLayout")
		areaLayout.FillDirection = Enum.FillDirection.Horizontal
		areaLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		areaLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		areaLayout.Padding = UDim.new(COLUMN_GAP, 0)
		areaLayout.SortOrder = Enum.SortOrder.LayoutOrder
		areaLayout.Parent = area
		rouletteColumns = area
		local skip = Instance.new("TextButton")
		skip.Name = "Skip"
		skip.Text = ""
		skip.Size = UDim2.fromScale(1, 1)
		skip.BackgroundTransparency = 1
		skip.ZIndex = Z.skip
		skip.Parent = frame
		skip.Activated:Connect(function()
			rouletteSkip = true
		end)
	end

	-- Un TraitCard de la tira: ocupa su hueco del UIListLayout; el margen interior separa uno de otro.
	local function traitCard(strip: Frame, place: number, entry)
		local holder = Instance.new("Frame")
		holder.Name = "TraitCard"
		holder.LayoutOrder = place
		holder.Size = UDim2.fromScale(1, 1 / STRIP_ITEMS)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z.card
		holder.Parent = strip
		local holderPadding = Instance.new("UIPadding")
		holderPadding.PaddingLeft = UDim.new(0, 4)
		holderPadding.PaddingRight = UDim.new(0, 4)
		holderPadding.PaddingTop = UDim.new(0, 3)
		holderPadding.PaddingBottom = UDim.new(0, 3)
		holderPadding.Parent = holder
		local item = Instance.new("Frame")
		item.Name = "Face"
		item.Size = UDim2.fromScale(1, 1)
		item.BackgroundColor3 = WHITE
		item.ZIndex = Z.card
		item.Parent = holder
		Ui.round(item, 8)
		Ui.gradient(item, entry.color:Lerp(BLACK, 0.55), entry.color:Lerp(BLACK, 0.8), 90)
		local edge = Ui.stroke(item, if entry.rainbow then WHITE else entry.color, 2)
		if entry.rainbow then
			rainbow(edge, entry)
		end
		local name = Ui.label(item, 24)
		name.Position = UDim2.fromScale(0, 0.04)
		name.Size = UDim2.fromScale(1, 0.55)
		name.TextScaled = true
		name.ZIndex = Z.cardText
		paintName(name, entry)
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 26
		limit.Parent = name
		local detail = Ui.label(item, 15)
		detail.Position = UDim2.fromScale(0, 0.58)
		detail.Size = UDim2.fromScale(1, 0.36)
		detail.TextScaled = true
		detail.TextColor3 = Color3.fromRGB(150, 240, 150)
		detail.Text = Modifiers.effect(entry)
		detail.ZIndex = Z.cardText
		local detailLimit = Instance.new("UITextSizeConstraint")
		detailLimit.MaxTextSize = 16
		detailLimit.Parent = detail
	end

	-- Muchas tiradas de golpe (pase de juego): no caben en columnas, así que salen como cartas en una rejilla
	-- de 5 por fila, una detrás de otra, y al final se destaca la mejor.
	local function playBurst(rolls: { number }, best: number)
		local holder = roulette :: Frame
		local area = rouletteColumns :: Frame
		;(rouletteTitle :: TextLabel).Text = Lang.t(nil, "Best of {n}!", { n = #rolls })
		;(rouletteTitle :: TextLabel).TextColor3 = WHITE
		local board = Instance.new("Frame")
		board.Name = "Column" -- mismo nombre que las columnas: se borra con ellas en la siguiente tirada
		board.Size = UDim2.fromScale(1, 1)
		board.BackgroundTransparency = 1
		board.ZIndex = Z.column
		board.Parent = area
		local perRow = 5
		local rowCount = math.ceil(#rolls / perRow)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.19, math.min(0.42, 0.92 / rowCount))
		grid.CellPadding = UDim2.fromScale(0.0125, 0.04)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = board

		local bestCard = table.find(rolls, best) or 1
		local faces = {}
		for place, rolled in rolls do
			traitCard(board, place, info.list[rolled])
			local card = board:FindFirstChild("TraitCard") :: Frame
			card.Name = "Card" .. place
			local pop = Instance.new("UIScale")
			pop.Scale = 0
			pop.Parent = card
			faces[place] = { card = card, pop = pop }
			TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sfx.play("tick")
			local waited = 0
			while waited < 0.07 and not rouletteSkip do
				waited += task.wait()
			end
		end
		local settle = 0
		while settle < 0.25 and not rouletteSkip do
			settle += task.wait()
		end

		local entry = info.list[best]
		Sfx.play(if Modifiers.percent(kind, best) < 1 then "win" else "buy")
		for place, face in faces do
			face.pop.Scale = 1
			if place == bestCard then
				TweenService:Create(face.pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
			else
				local shade = Instance.new("Frame")
				shade.Size = UDim2.fromScale(1, 1)
				shade.BackgroundColor3 = BLACK
				shade.BackgroundTransparency = 1
				shade.ZIndex = Z.shade
				shade.Parent = face.card
				Ui.round(shade, 8)
				TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
			end
		end
		;(rouletteTitle :: TextLabel).Text = Lang.t(nil, entry.name)
		;(rouletteTitle :: TextLabel).TextColor3 = if entry.rainbow then WHITE else entry.color
		task.wait(if rouletteSkip then 0.25 else 0.7)
	end

	local function playRoulette(rolls: { number }, best: number)
		local holder = roulette :: Frame
		local area = rouletteColumns :: Frame
		for _, child in area:GetChildren() do
			if child.Name == "Column" then
				child:Destroy()
			end
		end
		holder.Visible = true
		rouletteSkip = false
		Sfx.play("roll")
		local count = #rolls
		if count > 3 then
			playBurst(rolls, best)
			return
		end
		;(rouletteTitle :: TextLabel).Text = Lang.t(nil, if count > 1 then "Best of three!" else "Rolling...")
		;(rouletteTitle :: TextLabel).TextColor3 = WHITE
		-- Todas las columnas con el mismo ancho: lo que queda del área tras los huecos, a partes iguales.
		local width = if count == 1 then 0.45 else (1 - (count - 1) * COLUMN_GAP) / count

		local columns = {}
		local bestColumn = table.find(rolls, best) or 1
		for column = 1, count do
			local box = Instance.new("Frame")
			box.Name = "Column"
			box.LayoutOrder = column
			box.Size = UDim2.fromScale(width, 1)
			box.BackgroundColor3 = Ui.COLORS.dark
			box.ZIndex = Z.column
			box.Parent = area
			Ui.round(box, 10)
			local stroke = Ui.stroke(box, BLACK, 4)
			local scale = Instance.new("UIScale")
			scale.Parent = box
			-- Nunca tan estrecha que no quepa el nombre de un rasgo.
			local minimum = Instance.new("UISizeConstraint")
			minimum.MinSize = Vector2.new(110, 0)
			minimum.Parent = box

			-- Los TraitCards van en "Cards", que recorta la tira; el selector va fuera, encima.
			local cards = Instance.new("Frame")
			cards.Name = "Cards"
			cards.Size = UDim2.fromScale(1, 1)
			cards.BackgroundTransparency = 1
			cards.ClipsDescendants = true
			cards.ZIndex = Z.column
			cards.Parent = box
			local strip = Instance.new("Frame")
			strip.Name = "Strip"
			strip.Size = UDim2.fromScale(1, STRIP_ITEMS / VISIBLE)
			strip.BackgroundTransparency = 1
			strip.ZIndex = Z.card
			strip.Parent = cards
			local stripLayout = Instance.new("UIListLayout")
			stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
			stripLayout.Parent = strip
			for place = 1, STRIP_ITEMS do
				traitCard(strip, place, info.list[if place == LAND then rolls[column] else Modifiers.roll(kind, random)])
			end
			-- Se funden arriba y abajo.
			for _, top in { true, false } do
				local fade = Instance.new("Frame")
				fade.AnchorPoint = Vector2.new(0, if top then 0 else 1)
				fade.Position = UDim2.fromScale(0, if top then 0 else 1)
				fade.Size = UDim2.fromScale(1, 1.4 / VISIBLE)
				fade.BackgroundColor3 = Ui.COLORS.dark
				fade.BorderSizePixel = 0
				fade.ZIndex = Z.fade
				fade.Parent = cards
				local gradient = Instance.new("UIGradient")
				gradient.Rotation = if top then 90 else -90
				gradient.Transparency = NumberSequence.new(0.05, 1)
				gradient.Parent = fade
			end
			-- Selector: marco blanco del alto de un TraitCard en el centro, con una flecha a cada lado.
			local selector = Instance.new("Frame")
			selector.Name = "Selector"
			selector.AnchorPoint = Vector2.new(0.5, 0.5)
			selector.Position = UDim2.fromScale(0.5, 0.5)
			selector.Size = UDim2.fromScale(1, 1 / VISIBLE)
			selector.BackgroundTransparency = 1
			selector.ZIndex = Z.selector
			selector.Parent = box
			Ui.round(selector, 8)
			Ui.stroke(selector, WHITE, 3)
			for _, side in { 0, 1 } do
				local arrow = Instance.new("Frame")
				arrow.Name = if side == 0 then "ArrowLeft" else "ArrowRight"
				arrow.AnchorPoint = Vector2.new(0.5, 0.5)
				arrow.Position = UDim2.fromScale(side, 0.5)
				arrow.Size = UDim2.fromScale(0.22, 0.22)
				arrow.Rotation = 45
				arrow.BackgroundColor3 = WHITE
				arrow.BorderSizePixel = 0
				arrow.ZIndex = Z.selector
				arrow.Parent = selector
				local square = Instance.new("UIAspectRatioConstraint")
				square.DominantAxis = Enum.DominantAxis.Height
				square.Parent = arrow
				Ui.stroke(arrow, BLACK, 2)
			end

			-- Frena de golpe al final (Quint): cuanto más a la derecha, más tarda en parar. Todo en
			-- Scale de la columna: cada TraitCard mide 1 / VISIBLE.
			-- Frena un poco desviada (como si fuera a caer en la de al lado) y luego se recoloca justo
			-- en el selector.
			local final = 0.5 - (LAND - 0.5) / VISIBLE
			local landing = final + (random:NextNumber() - 0.5) * 0.5 / VISIBLE
			local entry = { box = box, strip = strip, final = final, stroke = stroke, scale = scale, done = false }
			entry.tween = TweenService:Create(strip, TweenInfo.new(1.1 + (column - 1) * 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, landing) })
			entry.tween.Completed:Connect(function(playback)
				if playback ~= Enum.PlaybackState.Completed then
					return
				end
				entry.tween = TweenService:Create(strip, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(0, final) })
				entry.tween.Completed:Connect(function(settled)
					entry.done = settled == Enum.PlaybackState.Completed
				end)
				entry.tween:Play()
			end)
			entry.tween:Play()
			table.insert(columns, entry)
		end

		local finished = false
		while not finished and not rouletteSkip do
			finished = true
			for _, column in columns do
				if not column.done then
					finished = false
				end
			end
			task.wait()
		end
		for _, column in columns do
			column.tween:Cancel()
			column.strip.Position = UDim2.fromScale(0, column.final)
		end

		-- Resultado: la mejor columna crece y brilla; las demás se apagan.
		local entry = info.list[best]
		Sfx.play(if Modifiers.percent(kind, best) < 1 then "win" else "buy")
		for index, column in columns do
			if index == bestColumn then
				column.stroke.Color = if entry.rainbow then WHITE else entry.color
				column.stroke.Thickness = 6
				column.scale.Scale = 1.1
				TweenService:Create(column.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.04 }):Play()
			else
				local shade = Instance.new("Frame")
				shade.Size = UDim2.fromScale(1, 1)
				shade.BackgroundColor3 = BLACK
				shade.BackgroundTransparency = 1
				shade.ZIndex = Z.shade
				shade.Parent = column.box
				Ui.round(shade, 10)
				TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
				-- El selector entero (marco y flechas) se apaga a la vez, sin medias flechas oscuras.
				local fade = TweenInfo.new(0.3)
				for _, part in column.box.Selector:GetDescendants() do
					if part:IsA("UIStroke") then
						TweenService:Create(part, fade, { Transparency = 0.6 }):Play()
					elseif part:IsA("Frame") then
						TweenService:Create(part, fade, { BackgroundTransparency = 0.6 }):Play()
					end
				end
			end
		end
		;(rouletteTitle :: TextLabel).Text = Lang.t(nil, entry.name)
		;(rouletteTitle :: TextLabel).TextColor3 = if entry.rainbow then WHITE else entry.color
		task.wait(if rouletteSkip then 0.2 else 0.5)
	end

	local function request(): boolean
		if state.waiting or not selectedCopy() or not canAfford() then
			return false
		end
		state.waiting = true
		state.last = nil
		if kind == "traits" then
			Remotes.RollTrait:FireServer(state.selected, state.count, table.concat(state.priority, ","))
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
					Ui.toast(Lang.t(nil, if canAfford() then "Pick a sword" else (if kind == "traits" then "You're out of Trait Crystals" else "You're out of Grade Crystals")), Ui.COLORS.red)
					break
				end
			end
			while state.waiting do
				task.wait()
			end
			if state.last and state.stop[state.last] then
				break
			end
			task.wait(AUTO_DELAY / speed())
		end
		state.auto = false
		if roulette then
			roulette.Visible = false
		end
		refresh()
	end

	Remotes.ModifierRolled.OnClientEvent:Connect(function(rolledKind: string, id: number, index: number, rolls: { number }?, previous: number?)
		if rolledKind ~= kind then
			return
		end
		state.last = index
		-- Forja (Grados): la escena de la forja enseña el resultado con el martillazo.
		if state.onResult and id == state.selected then
			state.onResult(index, previous or 0)
			state.waiting = false
			refresh()
			return
		end
		-- Rasgos: ruleta con todas las tiradas y, al acabar, el resultado de siempre.
		if roulette and rolls and id == state.selected and window.Visible then
			task.spawn(function()
				playRoulette(rolls, index)
				if not state.auto then
					(roulette :: Frame).Visible = false
				end
				reveal(index)
				state.waiting = false
				refresh()
			end)
			return
		end
		if id == state.selected then
			reveal(index)
		end
		state.waiting = false
		refresh()
	end)

	-- En la forja la tarjeta de la izquierda no se enseña nunca: Volver de los ajustes lleva a la lista de
	-- armas y Volver de la lista de armas cierra la ventana (y se vuelve a la forja).
	backHandlers.StopAt = function()
		stopper.Visible = false
		rebuildPicker()
		picker.Visible = true
	end
	backHandlers.Picker = function()
		Ui.close(window)
	end

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
	countButton.Activated:Connect(function()
		if not state.waiting then
			-- x1 -> x3 -> las del pase de juego (si lo tiene) -> x1.
			local most = Stats.perk(player, "traitCount")
			if state.count == 1 then
				state.count = 3
			elseif state.count == 3 and most and most > 3 then
				state.count = most
			else
				if state.count == 3 then
					Ui.toast(Lang.t(nil, "With the Shop pass you can roll 10 at once"), Ui.COLORS.purple)
				end
				state.count = 1
			end
			refresh()
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
			if not state.onResult then
				state.auto = false
			end
			picker.Visible = false
			stopper.Visible = false
			if roulette then
				roulette.Visible = false
			end
		end
		refresh()
	end)
	player:GetAttributeChangedSignal(stopAttribute):Connect(loadStops)
	-- El orden guardado llega al entrar (o al cambiarlo desde otra partida).
	player:GetAttributeChangedSignal("TraitPriority"):Connect(function()
		state.priority = Modifiers.priority(player:GetAttribute("TraitPriority"))
		if kind == "traits" then
			paintPriority()
		end
	end)
	-- Si pierde (o gana) el pase, la cuenta de rasgos vuelve a lo que puede tirar.
	player.AttributeChanged:Connect(function(attribute)
		if string.sub(attribute, 1, 5) == "Pass_" then
			if state.count > 3 and state.count ~= Stats.perk(player, "traitCount") then
				state.count = 1
			end
			refresh()
		end
	end)
	for _, attribute in { "Swords", "Equipped", "Loadout", "Item_gradeCrystal", "Item_traitCrystal", "Pity_" .. kind } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
	-- Para la escena de la forja (ForgeScene): usa la ventana solo para elegir espada y los ajustes del auto.
	local api = {
		state = state,
		window = window,
		selectedCopy = selectedCopy,
		canAfford = canAfford,
		request = request,
		refresh = refresh,
		speed = speed,
		openPicker = function()
			if not Ui.isOpen(window) then
				Ui.toggle(windowName)
			end
			rebuildPicker()
			stopper.Visible = false
			picker.Visible = true
		end,
		openSettings = function()
			if not Ui.isOpen(window) then
				Ui.toggle(windowName)
			end
			picker.Visible = false
			stopper.Visible = true
		end,
		closeWindow = function()
			Ui.close(window)
		end,
	}
	return windowName, window, api
end

function ModifierShops.start()
	-- Los arcoíris de las especiales giran.
	game:GetService("RunService").RenderStepped:Connect(function(delta)
		if Performance.get() then return end -- modo rendimiento
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
			billboard.StudsOffset = Vector3.new(0, (billboard:GetAttribute("SignHeight") or 13) + wave * 0.5, 0)
			local label = billboard:FindFirstChildOfClass("TextLabel")
			if label then
				-- Fuente según la distancia: máxima de cerca (hasta 35 studs), se encoge al alejarse y no baja del mínimo.
				local maxSize = billboard:GetAttribute("TextMax") or 40
				local minSize = billboard:GetAttribute("TextMin") or 18
				local anchor = billboard.Parent :: BasePart
				local distance = (anchor.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
				label.TextSize = math.clamp(maxSize * 35 / math.max(distance, 1), minSize, maxSize) * (1 + wave * 0.06)
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
			icon.Position = UDim2.fromOffset(ICON_X, ICON_Y + math.sin(now * 2 + data.phase) * 3)
			data.scale.Scale = 1 + math.sin(now * 3 + data.phase) * 0.06
		end
		for scale, phase in breathing do
			if not scale.Parent then
				breathing[scale] = nil
				continue
			end
			scale.Scale = 1 + math.sin(now * 1.8 + phase) * 0.025 -- ola suave (pedido por el usuario: era muy grande y rápida)
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
		local name, window, api = buildShop(kind)
		windows[kind] = { name = name, frame = window }
		if kind == "grades" then
			ForgeScene.bind(api)
		end
	end

	-- Abrir junto al puesto y cerrar al alejarse.
	local openAt: Vector3? = nil
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local kind = prompt:GetAttribute("Shop")
		local shop = kind and windows[kind]
		if kind == "grades" then
			ForgeScene.toggle()
		elseif shop then
			local parent = prompt.Parent
			openAt = if parent and parent:IsA("BasePart") then parent.Position else nil
			Ui.toggle(shop.name)
		end
	end)
	local inside = {} -- [aviso] = true mientras el jugador está dentro del radio de apertura
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for _, prompt in CollectionService:GetTagged("ShopStation") do
					local shop = windows[prompt:GetAttribute("Shop")]
					local anchor = if prompt:IsA("BasePart") then prompt else prompt.Parent
					if not shop or not anchor or not anchor:IsA("BasePart") then
						continue
					end
					local distance = (root.Position - anchor.Position).Magnitude
					if distance < OPEN_DISTANCE and not inside[prompt] then
						inside[prompt] = true
						if prompt:GetAttribute("Shop") == "grades" then
							ForgeScene.enter()
						elseif not Ui.isOpen(shop.frame) then
							openAt = anchor.Position
							Ui.toggle(shop.name)
						end
					elseif distance > OPEN_DISTANCE + 4 then
						inside[prompt] = nil
					end
				end
			end
			if openAt and root and (root.Position - openAt).Magnitude > CLOSE_DISTANCE then
				for _, shop in windows do
					Ui.close(shop.frame)
				end
				openAt = nil
			end
		end
	end)
end

return ModifierShops
