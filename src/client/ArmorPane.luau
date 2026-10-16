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
local Lang = require(ReplicatedStorage.Shared.Lang)
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

-- X roja sobre las piezas marcadas para desmontar, como la del menú de vender armas.
local MARK_COLOR = Color3.fromRGB(235, 45, 55)
local function salvageMark(cell: GuiObject): Frame
	local mark = Instance.new("Frame")
	mark.Name = "SalvageMark"
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
		bar.BackgroundTransparency = 0.25
		bar.BorderSizePixel = 0
		bar.ZIndex = 5
		bar.Parent = mark
		Ui.round(bar, 6)
	end
	return mark
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
		`<font color="{hex(quality.color)}">{Lang.t(nil, quality.name)}</font> <font color="{Ui.SOFT}">· {Lang.t(nil, cfg.Slots[piece.slot].name)}</font>`,
		`<font color="{Ui.SOFT}">{Lang.t(nil, "Dungeon:")}</font> <font color="{hex(level.color)}">{Lang.t(nil, level.name)}</font>`,
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
		local entry = { cell = cell, stroke = cell:FindFirstChildOfClass("UIStroke"), label = Ui.cellLabel(cell, Lang.t(nil, cfg.Slots[slot].name)), piece = nil, shown = nil }
		slots[slot] = entry
		Ui.tip(cell, function()
			if entry.piece then
				return pieceTip(entry.piece)
			end
			return `{Lang.t(nil, cfg.Slots[slot].name)}\n<font color="{Ui.SOFT}">{Lang.t(nil, "Empty")}</font>`, Ui.COLORS.gray
		end, true)
		cell.Activated:Connect(function()
			if entry.piece then
				Sfx.play("equip")
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
	totalsTitle.Text = Lang.t(nil, "EQUIPPED ARMOR")
	totalsTitle.TextColor3 = GOLD
	local totalsText = Ui.label(totals, 16)
	totalsText.Name = "Text"
	totalsText.Position = UDim2.fromOffset(12, 28)
	totalsText.Size = UDim2.new(1, -24, 1, -34)
	totalsText.TextXAlignment = Enum.TextXAlignment.Left
	totalsText.TextYAlignment = Enum.TextYAlignment.Top
	totalsText.LineHeight = 1.12

	-- Ocultar armadura (pedido por el usuario: que no se vea lo que llevas): el servidor no la pone en el personaje y
	-- sigue contando. El muñeco de aquí también la esconde (pedido por el usuario: antes la enseñaba igual).
	local hideButton = Ui.button(pane, Lang.t(nil, "Hide armor"), Ui.COLORS.gray)
	hideButton.Name = "Hide"
	hideButton.AnchorPoint = Vector2.new(0.5, 0)
	hideButton.Position = UDim2.fromOffset(LEFT + CENTER / 2, 8)
	hideButton.Size = UDim2.fromOffset(CENTER - 12, 36)
	hideButton.TextSize = 17
	Ui.tip(hideButton, function()
		return Lang.t(nil, "Nobody sees your armor; its stats still count."), Ui.COLORS.gray
	end)
	local function paintHide()
		local hidden = player:GetAttribute("ArmorHidden") == true
		hideButton.Text = Lang.t(nil, if hidden then "Show armor" else "Hide armor")
		hideButton.BackgroundColor3 = if hidden then Ui.COLORS.purple else Ui.COLORS.gray
	end
	paintHide()
	hideButton.Activated:Connect(function()
		Sfx.play("equip")
		Remotes.SetArmorHidden:FireServer(player:GetAttribute("ArmorHidden") ~= true)
	end)

	-- El muñeco es una copia del personaje: con la armadura escondida no la lleva y así se queda.
	local function paintCharacter()
		helpers.character(viewport)
	end
	player:GetAttributeChangedSignal("ArmorHidden"):Connect(function()
		paintHide()
		-- Espera a que el servidor quite o ponga las piezas del personaje.
		task.delay(0.35, function()
			if pane.Visible then
				paintCharacter()
			end
		end)
	end)

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

	local equipButton = Ui.button(pane, Lang.t(nil, "Equip"), Ui.COLORS.blue)
	equipButton.Name = "Equip"
	equipButton.AnchorPoint = Vector2.new(0, 1)
	equipButton.Position = UDim2.new(0, RIGHT + 4, 1, -12)
	equipButton.Size = UDim2.new(1 / 3, -(RIGHT + 28) / 3, 0, BAR)
	equipButton.TextSize = 22
	-- "Equipar mejores": la mejor pieza de cada hueco, elegida en el servidor.
	local bestButton = Ui.button(pane, Lang.t(nil, "Equip best"), Ui.COLORS.green)
	bestButton.Name = "Best"
	bestButton.AnchorPoint = Vector2.new(0.5, 1)
	bestButton.Position = UDim2.new(0.5, (RIGHT - 8) / 2, 1, -12)
	bestButton.Size = UDim2.new(1 / 3, -(RIGHT + 28) / 3, 0, BAR)
	bestButton.TextSize = 19
	local salvageButton = Ui.button(pane, Lang.t(nil, "Salvage several"), Ui.COLORS.red)
	salvageButton.Name = "Salvage"
	salvageButton.AnchorPoint = Vector2.new(1, 1)
	salvageButton.Position = UDim2.new(1, -12, 1, -12)
	salvageButton.Size = UDim2.new(1 / 3, -(RIGHT + 28) / 3, 0, BAR)
	salvageButton.TextSize = 19
	equipButton.TextWrapped = true

	local selected: number? = nil
	local cells = {} -- [id] = casilla
	local shownRaw: string? = nil
	-- Desmontar varias (pedido por el usuario: de una en una era muy lento): el botón Desmontar entra en este modo,
	-- en el que pulsar una pieza la marca con una X; los otros dos botones pasan a "Todas las sin equipar" y
	-- "Cancelar", y Desmontar pide un segundo toque para confirmar. Las equipadas no se marcan.
	local salvaging = false
	local marked = {} -- [id] = true
	local confirming = false

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
			local item = cell :: any
			item.Select.Visible = not salvaging and id == selected
			item.SalvageMark.Visible = salvaging and marked[id] == true
		end
		if salvaging then
			local count, crystals = 0, 0
			for _, other in ArmorStats.pieces(player) do
				if marked[other.id] then
					count += 1
					crystals += ArmorStats.salvage(other)
				end
			end
			if count == 0 then
				confirming = false
			end
			equipButton.Text = Lang.t(nil, "Select all")
			equipButton.TextSize = 18
			salvageButton.TextSize = 15
			equipButton.BackgroundColor3 = Ui.COLORS.blue
			bestButton.Text = Lang.t(nil, "Cancel")
			bestButton.BackgroundColor3 = Ui.COLORS.gray
			salvageButton.Text = Lang.t(nil, if confirming then "Sure? {n}\n+{crystals} crystals" else "Salvage {n}\n+{crystals} crystals", { n = count, crystals = Format.short(crystals) })
			salvageButton.BackgroundColor3 = if count > 0 then Ui.COLORS.red else Ui.COLORS.gray
			return
		end
		equipButton.TextSize = 22
		salvageButton.TextSize = 19
		bestButton.Text = Lang.t(nil, "Equip best")
		bestButton.BackgroundColor3 = Ui.COLORS.green
		equipButton.Text = Lang.t(nil, if piece and piece.worn then "Unequip" else "Equip")
		equipButton.BackgroundColor3 = if not piece then Ui.COLORS.gray elseif piece.worn then Ui.COLORS.orange else Ui.COLORS.blue
		salvageButton.Text = Lang.t(nil, "Salvage several")
		salvageButton.BackgroundColor3 = Ui.COLORS.red
	end

	local function refreshHint()
		local pieces = ArmorStats.pieces(player)
		hint.Text = if #pieces == 0
			then Lang.t(nil, "No armor: it drops in the hub dungeons.")
			elseif salvaging then Lang.t(nil, "Tap the pieces you want to salvage")
			else Lang.t(nil, "Pieces {n}/{max} · pick one and press Equip", { n = #pieces, max = cfg.MaxPieces })
		hint.TextColor3 = if salvaging then Ui.COLORS.red:Lerp(WHITE, 0.45) else WHITE
	end

	local function setSalvaging(on: boolean)
		salvaging = on
		confirming = false
		table.clear(marked)
		-- Entra con la pieza elegida ya marcada, si no la lleva puesta.
		local piece = find(selected)
		if on and piece and not piece.worn then
			marked[piece.id] = true
		end
		refreshHint()
		paintSelection()
	end

	equipButton.Activated:Connect(function()
		if salvaging then
			confirming = false
			for _, piece in ArmorStats.pieces(player) do
				marked[piece.id] = if piece.worn then nil else true
			end
			paintSelection()
		elseif find(selected) then
			Sfx.play("equip")
			Remotes.EquipArmor:FireServer(selected)
		else
			Sfx.play("error")
		end
	end)
	-- "Equipar mejores" (la mejor pieza de cada hueco, elegida en el servidor) o, desmontando, "Cancelar".
	bestButton.Activated:Connect(function()
		if salvaging then
			setSalvaging(false)
		elseif #ArmorStats.pieces(player) > 0 then
			Sfx.play("equip")
			Remotes.EquipArmor:FireServer("best")
		else
			Sfx.play("error")
		end
	end)
	salvageButton.Activated:Connect(function()
		if not salvaging then
			setSalvaging(true)
		elseif next(marked) == nil then
			Sfx.play("error")
		elseif not confirming then
			confirming = true
			paintSelection()
		else
			local ids = {}
			for id in marked do
				table.insert(ids, id)
			end
			Sfx.play("sell")
			Remotes.SalvageArmor:FireServer(ids)
			selected = nil
			setSalvaging(false)
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
			salvageMark(cell)
			cell.Activated:Connect(function()
				if salvaging then
					local current = find(piece.id)
					if not current or current.worn then
						Sfx.play("error")
						return
					end
					confirming = false
					marked[piece.id] = if marked[piece.id] then nil else true
				else
					selected = piece.id
				end
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
					paintCharacter()
				end
			end)
		end
		if not find(selected) then
			selected = nil
		end
		-- Las marcadas que ya no están (o que se han equipado) dejan de estarlo.
		for id in marked do
			local piece = find(id)
			if not piece or piece.worn then
				marked[id] = nil
			end
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
			entry.label.Text = if piece then mainStat(piece) else Lang.t(nil, cfg.Slots[slot].name)
		end

		refreshHint()
		local lines = {}
		for _, stat in cfg.StatOrder do
			local total = player:GetAttribute("Armor_" .. stat) or 0
			local info = cfg.Stats[stat]
			table.insert(lines, `<font color="{if total > 0 then hex(info.color) else Ui.SOFT}">{ArmorStats.value(stat, total)}</font> <font color="{Ui.SOFT}">{Lang.t(nil, info.name)}</font>`)
		end
		totalsText.Text = table.concat(lines, "\n")
	end

	return {
		refresh = refresh,
		show = function()
			-- Al volver a la pestaña, el modo de desmontar varias empieza apagado.
			salvaging, confirming = false, false
			table.clear(marked)
			paintCharacter()
			refresh()
		end,
	}
end

-- Para otras ventanas que enseñan piezas de armadura (el comercio).
ArmorPane.preview = preview
ArmorPane.tip = pieceTip

return ArmorPane
