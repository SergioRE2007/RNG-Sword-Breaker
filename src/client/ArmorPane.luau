-- Pestaña "Armadura" de la mochila (librería sin start(): la monta Backpack). A la izquierda los cuatro
-- huecos (casco, pechera, grebas, botas), en el centro el personaje con lo que lleva puesto y el total de
-- stats, y a la derecha las piezas que tiene, en casillas del color de su calidad con la pieza en 3D.
-- Pulsar una pieza la elige; con los botones de abajo se equipa, se quita o se desmonta. El servidor manda:
-- aquí solo se piden EquipArmor y SalvageArmor y se pinta el atributo "Armor" (ver shared/ArmorStats).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorModel = require(ReplicatedStorage.Shared.ArmorModel)
local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local ArmorPane = {}

local player = Players.LocalPlayer
local cfg = Config.Armor
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local FOV = 30

-- Medidas de la pestaña (la ventana de la mochila tiene tamaño de diseño fijo y se escala entera).
local SLOT = 100
local SLOT_GAP = 14
local LEFT = 12 + SLOT + 12 -- donde acaba la columna de huecos
local CENTER = 214 -- ancho de la columna del personaje
local RIGHT = LEFT + CENTER + 10 -- donde empieza la lista de piezas
local BAR = 62 -- alto de los botones de abajo

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Vista 3D de una pieza dentro de una casilla, con un foco del color de su calidad detrás.
local function preview(cell: GuiObject, piece)
	local color = ArmorStats.quality(piece).color
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.44)
	glow.Size = UDim2.fromScale(0.72, 0.72)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.Parent = cell
	Ui.round(glow, 99)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.9)
	fade.Parent = glow

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.44)
	viewport.Size = UDim2.fromScale(0.9, 0.9)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = WHITE
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.6)
	viewport.ZIndex = 2
	viewport.Parent = cell
	local model = ArmorModel.build(piece.slot, piece.quality, piece.level, viewport)
	local center, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	local distance = math.max(size.X, size.Y, size.Z) * 0.62 / math.tan(math.rad(FOV / 2))
	-- De frente (la cara es -Z), un poco de lado y desde arriba.
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0.55, 0.35, -1).Unit * distance, center.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Stat principal de la pieza para el pie de la casilla: el primero de su lista.
local function mainStat(piece): string
	local first = piece.stats[1]
	return if first then ArmorStats.value(first.stat, first.value) else ""
end

local function pieceTip(piece): (string, Color3)
	local quality = ArmorStats.quality(piece)
	local level = Config.Dungeons[piece.level]
	local lines = {
		ArmorStats.name(piece),
		`<font color="{hex(quality.color)}">{quality.name}</font> <font color="{Ui.SOFT}">· {cfg.Slots[piece.slot].name}</font>`,
		`<font color="{Ui.SOFT}">Mazmorra:</font> <font color="{hex(level.color)}">{level.name}</font>`,
	}
	for _, entry in piece.stats do
		if not entry.bonus then
			table.insert(lines, `<font color="{hex(cfg.Stats[entry.stat].color)}">{ArmorStats.text(entry.stat, entry.value)}</font>`)
		end
	end
	for _, entry in piece.stats do
		if entry.bonus then
			table.insert(lines, `<font color="{hex(GOLD)}">✦ {ArmorStats.text(entry.stat, entry.value)}</font>`)
		end
	end
	table.insert(lines, if piece.worn then `<font color="{hex(Ui.COLORS.green)}">Equipada</font>` else `<font color="{Ui.SOFT}">No equipada</font>`)
	table.insert(lines, `<font color="{Ui.SOFT}">Desmontar: +{Format.short(ArmorStats.salvage(piece))} {Config.Items.gradeCrystal.name}</font>`)
	return table.concat(lines, "\n"), quality.color
end

-- `helpers` = { grid = función de Backpack que crea la lista con rejilla, character = función que pinta al
-- personaje en un ViewportFrame, popIn = casilla que entra con rebote }. Devuelve { refresh, show }.
function ArmorPane.build(pane: Frame, helpers)
	-- Huecos ----------------------------------------------------------------------------
	local slotColumn = Instance.new("Frame")
	slotColumn.Name = "Slots"
	slotColumn.Position = UDim2.fromOffset(12, 12)
	slotColumn.Size = UDim2.new(0, SLOT, 1, -24)
	slotColumn.BackgroundTransparency = 1
	slotColumn.Parent = pane
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.Padding = UDim.new(0, SLOT_GAP)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = slotColumn

	local slots = {} -- [hueco] = { cell, stroke, label, piece, shown }
	for order, slot in cfg.SlotOrder do
		local cell = Ui.cell(slotColumn, Ui.COLORS.gray)
		cell.Name = "Slot_" .. slot
		cell.LayoutOrder = order
		cell.Size = UDim2.fromOffset(SLOT, SLOT)
		local entry = { cell = cell, stroke = cell:FindFirstChildOfClass("UIStroke"), label = Ui.cellLabel(cell, cfg.Slots[slot].name), piece = nil, shown = nil }
		slots[slot] = entry
		Ui.tip(cell, function()
			if entry.piece then
				return pieceTip(entry.piece)
			end
			return `{cfg.Slots[slot].name}\n<font color="{Ui.SOFT}">Vacío: elige una pieza y pulsa Equipar.</font>`, Ui.COLORS.gray
		end, true)
		cell.Activated:Connect(function()
			if entry.piece then
				Remotes.EquipArmor:FireServer(entry.piece.id)
			end
		end)
	end

	-- Personaje y totales ---------------------------------------------------------------
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Character"
	viewport.Position = UDim2.fromOffset(LEFT, 4)
	viewport.Size = UDim2.new(0, CENTER, 1, -150)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = WHITE
	viewport.Parent = pane

	local totals = Instance.new("Frame")
	totals.Name = "Totals"
	totals.AnchorPoint = Vector2.new(0, 1)
	totals.Position = UDim2.new(0, LEFT, 1, -12)
	totals.Size = UDim2.fromOffset(CENTER, 132)
	totals.BackgroundColor3 = WHITE
	totals.BorderSizePixel = 0
	totals.Parent = pane
	Ui.round(totals, 10)
	Ui.stroke(totals, BLACK, 3)
	Ui.panel(totals, Color3.fromRGB(58, 62, 108))
	local totalsTitle = Ui.label(totals, 17)
	totalsTitle.Position = UDim2.fromOffset(0, 5)
	totalsTitle.Size = UDim2.new(1, 0, 0, 20)
	totalsTitle.Text = "ARMADURA EQUIPADA"
	totalsTitle.TextColor3 = GOLD
	local totalsText = Ui.label(totals, 16)
	totalsText.Name = "Text"
	totalsText.Position = UDim2.fromOffset(12, 28)
	totalsText.Size = UDim2.new(1, -24, 1, -34)
	totalsText.TextXAlignment = Enum.TextXAlignment.Left
	totalsText.TextYAlignment = Enum.TextYAlignment.Top
	totalsText.LineHeight = 1.12

	-- Piezas ----------------------------------------------------------------------------
	local hint = Ui.label(pane, 18)
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(RIGHT, 8)
	hint.Size = UDim2.new(1, -RIGHT - 12, 0, 30)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextTruncate = Enum.TextTruncate.AtEnd

	local list = helpers.grid(pane, UDim2.fromOffset(RIGHT - 4, 40), UDim2.new(1, -RIGHT - 4, 1, -40 - BAR - 22))
	local layout = list:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	layout.CellSize = UDim2.fromOffset(92, 92)
	layout.CellPadding = UDim2.fromOffset(14, 14)

	-- Franja oscura detrás de los botones, como en la pestaña Espadas.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, RIGHT - 4, 1, -6)
	bar.Size = UDim2.new(1, -RIGHT - 4, 0, BAR + 12)
	bar.BackgroundColor3 = WHITE
	bar.BorderSizePixel = 0
	bar.Parent = pane
	Ui.round(bar, 10)
	Ui.stroke(bar, BLACK, 2)
	Ui.panel(bar, Color3.fromRGB(46, 42, 78))

	local equipButton = Ui.button(pane, "Equipar", Ui.COLORS.blue)
	equipButton.Name = "Equip"
	equipButton.AnchorPoint = Vector2.new(0, 1)
	equipButton.Position = UDim2.new(0, RIGHT + 4, 1, -12)
	equipButton.Size = UDim2.new(0.5, -(RIGHT + 16) / 2, 0, BAR)
	equipButton.TextSize = 22
	local salvageButton = Ui.button(pane, "Desmontar", Ui.COLORS.red)
	salvageButton.Name = "Salvage"
	salvageButton.AnchorPoint = Vector2.new(1, 1)
	salvageButton.Position = UDim2.new(1, -12, 1, -12)
	salvageButton.Size = UDim2.new(0.5, -(RIGHT + 16) / 2, 0, BAR)
	salvageButton.TextSize = 19

	local selected: number? = nil
	local cells = {} -- [id] = casilla
	local shownRaw: string? = nil

	local function find(id: number?)
		for _, piece in ArmorStats.pieces(player) do
			if piece.id == id then
				return piece
			end
		end
		return nil
	end

	local function paintSelection()
		local piece = find(selected)
		for id, cell in cells do
			(cell :: any).Select.Visible = id == selected
		end
		equipButton.Text = if piece and piece.worn then "Quitar" else "Equipar"
		equipButton.BackgroundColor3 = if not piece then Ui.COLORS.gray elseif piece.worn then Ui.COLORS.orange else Ui.COLORS.blue
		salvageButton.Text = if piece then `Desmontar\n+{Format.short(ArmorStats.salvage(piece))} cristales` else "Desmontar"
		salvageButton.BackgroundColor3 = if piece then Ui.COLORS.red else Ui.COLORS.gray
	end

	equipButton.Activated:Connect(function()
		if find(selected) then
			Remotes.EquipArmor:FireServer(selected)
		else
			Sfx.play("error")
		end
	end)
	salvageButton.Activated:Connect(function()
		if find(selected) then
			Remotes.SalvageArmor:FireServer(selected)
			selected = nil
		else
			Sfx.play("error")
		end
	end)

	-- Las mejores primero: por dificultad, luego por calidad.
	local function order(piece): number
		return -(piece.level * 100 + piece.quality) * 1000 + piece.id
	end

	local function sync(pieces)
		for _, cell in cells do
			cell:Destroy()
		end
		table.clear(cells)
		local count = 0
		for _, piece in pieces do
			local quality = ArmorStats.quality(piece)
			local cell = Ui.cell(list, quality.color, piece.quality)
			cell.Name = "Piece" .. piece.id
			cell.LayoutOrder = order(piece)
			preview(cell, piece)
			Ui.cellLabel(cell, mainStat(piece))
			if piece.worn then
				Ui.cellTag(cell, "E", Ui.COLORS.green)
			end
			Ui.tip(cell, function()
				return pieceTip(find(piece.id) or piece)
			end, true)
			cell.Activated:Connect(function()
				selected = piece.id
				paintSelection()
			end)
			cells[piece.id] = cell
			count += 1
			if count <= 24 then
				helpers.popIn(cell, count * 0.015)
			end
		end
	end

	local function refresh()
		local pieces = ArmorStats.pieces(player)
		local raw = player:GetAttribute("Armor")
		if raw ~= shownRaw then
			shownRaw = raw
			sync(pieces)
			-- El servidor suelda las piezas al personaje justo después: se vuelve a pintar con ellas puestas.
			task.delay(0.35, function()
				if pane.Visible then
					helpers.character(viewport)
				end
			end)
		end
		if not find(selected) then
			selected = nil
		end
		paintSelection()

		local worn = {}
		for _, piece in pieces do
			if piece.worn then
				worn[piece.slot] = piece
			end
		end
		for slot, entry in slots do
			local piece = worn[slot]
			local key = if piece then `{piece.id}` else ""
			if entry.shown ~= key then
				entry.shown = key
				for _, name in { "Glow", "Preview" } do
					local old = entry.cell:FindFirstChild(name)
					if old then
						old:Destroy()
					end
				end
				if piece then
					preview(entry.cell, piece)
				end
			end
			entry.piece = piece
			local color = if piece then ArmorStats.quality(piece).color else Ui.COLORS.gray
			entry.cell.BackgroundColor3 = color
			if entry.stroke then
				entry.stroke.Color = color
			end
			entry.label.Text = if piece then mainStat(piece) else cfg.Slots[slot].name
		end

		hint.Text = if #pieces == 0
			then "Sin armadura: cae en las mazmorras del hub."
			else `Piezas {#pieces}/{cfg.MaxPieces} · elige una y pulsa Equipar`
		local lines = {}
		for _, stat in cfg.StatOrder do
			local total = player:GetAttribute("Armor_" .. stat) or 0
			local info = cfg.Stats[stat]
			table.insert(lines, `<font color="{if total > 0 then hex(info.color) else Ui.SOFT}">{ArmorStats.value(stat, total)}</font> <font color="{Ui.SOFT}">{info.name}</font>`)
		end
		totalsText.Text = table.concat(lines, "\n")
	end

	return {
		refresh = refresh,
		show = function()
			helpers.character(viewport)
			refresh()
		end,
	}
end

-- Para otras ventanas que enseñan piezas de armadura (el comercio).
ArmorPane.preview = preview
ArmorPane.tip = pieceTip

return ArmorPane
