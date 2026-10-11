-- Menú de botín de las mazmorras (cliente). Sustituye a la lista de premios del cartel de resultado: al acabar la
-- partida el servidor manda el botín retenido (server/DropMenu) y aquí se enseña una tarjeta por entrada: imagen, nombre,
-- rareza, cantidad y stats. El jugador marca lo que tira y confirma; el cliente solo manda los ids marcados
-- (`DropDecision`) y el servidor comprueba que son suyos. Lo no marcado entra al inventario. Si no se contesta,
-- el servidor se lo guarda todo pasado un tiempo (la barra de abajo lo cuenta); cerrar la ventana equivale a "Quedarme todo".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorModel = require(ReplicatedStorage.Shared.ArmorModel)
local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Potions = require(script.Parent.Potions)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local DropMenu = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local armorCfg = Config.Armor
local FOV = 30

local CARD = Vector2.new(172, 262)
local CELL = 116 -- casilla cuadrada con la imagen
local Z_CONFIRM = 50

local window: Frame
local head: TextLabel
local notice: TextLabel
local grid: ScrollingFrame
local keepButton: TextButton
local throwButton: TextButton
local confirm: Frame
local confirmText: TextLabel

local state = { active = false, drops = {}, cards = {}, selected = {}, free = 0, expires = 0 }
local missing: { [string]: boolean } = {} -- objetos sin imagen propia (usan el signo de interrogación)

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Vista 3D de una pieza de armadura dentro de la casilla, con un foco del color de su calidad detrás.
local function armorPreview(cell: GuiObject, piece)
	local color = armorCfg.Qualities[piece.quality].color
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.46)
	glow.Size = UDim2.fromScale(0.72, 0.72)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Parent = cell
	Ui.round(glow, 99)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.46)
	viewport.Size = UDim2.fromScale(0.9, 0.9)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = WHITE
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.6)
	viewport.ZIndex = 3
	viewport.Parent = cell
	local model = ArmorModel.build(piece.slot, piece.quality, piece.level, viewport)
	local center, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	local distance = math.max(size.X, size.Y, size.Z) * 0.62 / math.tan(math.rad(FOV / 2))
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0.55, 0.35, -1).Unit * distance, center.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Qué se enseña de cada entrada: nombre, color de rareza, texto de rareza, nivel de rareza de la casilla,
-- stats en líneas de RichText y cómo se pinta la imagen.
local function info(drop)
	if drop.kind == "armor" then
		local piece = drop.piece
		local quality = armorCfg.Qualities[piece.quality]
		local lines = {}
		for _, entry in piece.stats do
			if not entry.bonus then
				table.insert(lines, `<font color="{hex(armorCfg.Stats[entry.stat].color)}">{ArmorStats.text(entry.stat, entry.value)}</font>`)
			end
		end
		for _, entry in piece.stats do
			if entry.bonus then
				table.insert(lines, `<font color="{hex(GOLD)}">✦ {ArmorStats.text(entry.stat, entry.value)}</font>`)
			end
		end
		local level = Config.Dungeons[piece.level]
		if level then
			table.insert(lines, `<font color="{Ui.SOFT}">{level.name}</font>`)
		end
		return {
			name = ArmorStats.name(piece),
			color = quality.color,
			rarity = quality.name,
			tier = piece.quality,
			stats = table.concat(lines, "\n"),
			amount = nil,
			icon = function(cell)
				armorPreview(cell, piece)
			end,
		}
	elseif drop.kind == "potion" then
		local family = Config.Potions.Families[drop.family]
		local color = PotionInfo.color(drop.tier)
		return {
			name = family.name,
			color = color,
			rarity = PotionInfo.tierName(drop.tier),
			tier = drop.tier,
			stats = `<font color="{hex(family.color:Lerp(WHITE, 0.3))}">{PotionInfo.effect(drop.family, drop.tier)}</font>\n<font color="{Ui.SOFT}">Dura {PotionInfo.minutes(PotionInfo.duration(drop.tier))}</font>`,
			amount = drop.amount,
			icon = function(cell)
				Potions.icon(cell, drop.family)
				Potions.addTag(cell, drop.tier, true)
			end,
		}
	end
	local item = Config.Items[drop.key]
	local isCrystal = drop.key == "traitCrystal" or drop.key == "gradeCrystal"
	if not item then
		missing[tostring(drop.key)] = true
	end
	return {
		name = if item then item.name else tostring(drop.key),
		color = if item then item.color else Ui.COLORS.gray,
		rarity = "Material",
		tier = 1,
		stats = if item then `<font color="{Ui.SOFT}">{item.description}</font>` else "",
		amount = drop.amount,
		icon = function(cell)
			if isCrystal then
				Ui.crystalIcon(cell, item.color, drop.key == "gradeCrystal")
			else
				-- Sin imagen asignada: signo de interrogación (y se apunta en `missing`).
				missing[tostring(drop.key)] = true
				local mark = Ui.label(cell, 56)
				mark.Size = UDim2.fromScale(1, 1)
				mark.Text = "?"
				mark.ZIndex = 3
			end
		end,
	}
end

-- Mandar la decisión y cerrar la ventana.
local function finish(ids: { number })
	if not state.active then
		return
	end
	state.active = false
	Remotes.DropDecision:FireServer(ids)
	confirm.Visible = false
	Ui.close(window)
end

local function selectedIds(): { number }
	local ids = {}
	for _, drop in state.drops do
		if state.selected[drop.id] then
			table.insert(ids, drop.id)
		end
	end
	return ids
end

-- Pinta el estado: qué tarjetas están marcadas, cuáles de armadura se desmontarían por falta de sitio y los botones.
local function refresh()
	local count = 0
	local used, flagged = 0, 0
	for _, drop in state.drops do
		local card = state.cards[drop.id]
		local chosen = state.selected[drop.id] == true
		if chosen then
			count += 1
		end
		local salvage = false
		if drop.kind == "armor" and not chosen then
			used += 1
			if used > state.free then
				salvage = true
				flagged += 1
			end
		end
		if card then
			card.Throw.Visible = chosen
			card.Salvage.Visible = salvage
			card.Stroke.Thickness = if chosen then 6 else 4
		end
	end
	throwButton.Text = if count > 0 then `Tirar seleccionados ({count})` else "Tirar seleccionados"
	throwButton.Active = count > 0
	throwButton.BackgroundTransparency = if count > 0 then 0 else 0.55
	notice.Text = if flagged > 0
		then `<font color="{hex(Ui.COLORS.orange)}">⚠ Mochila de armadura llena: {flagged} {if flagged == 1 then "pieza se desmontará" else "piezas se desmontarán"} a cambio de cristales. Tira otra cosa para hacer sitio.</font>`
		else ""
end

local function toggle(id: number)
	if not state.active then
		return
	end
	state.selected[id] = if state.selected[id] then nil else true
	Sfx.play("tick")
	refresh()
end

local function buildCard(drop, order: number)
	local data = info(drop)
	local card = Instance.new("TextButton")
	card.Name = "Drop_" .. drop.id
	card.Text = ""
	card.AutoButtonColor = false
	card.LayoutOrder = order
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Parent = grid
	Ui.round(card, 12)
	local stroke = Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(58, 62, 108), data.color)
	Ui.pressable(card, 1.04)

	local cell = Ui.cell(card, data.color, data.tier)
	cell.Name = "Image"
	cell.AnchorPoint = Vector2.new(0.5, 0)
	cell.Position = UDim2.new(0.5, 0, 0, 10)
	cell.Size = UDim2.fromOffset(CELL, CELL)
	data.icon(cell)
	if data.amount and data.amount > 1 then
		Ui.cellLabel(cell, "x" .. Format.short(data.amount))
	end

	local name = Ui.label(card, 17)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(6, CELL + 14)
	name.Size = UDim2.new(1, -12, 0, 40)
	name.TextWrapped = true
	name.Text = data.name
	local rarity = Ui.label(card, 15)
	rarity.Name = "Rarity"
	rarity.Position = UDim2.fromOffset(6, CELL + 54)
	rarity.Size = UDim2.new(1, -12, 0, 18)
	rarity.Text = data.rarity
	rarity.TextColor3 = data.color:Lerp(WHITE, 0.25)
	local stats = Ui.label(card, 14)
	stats.Name = "Stats"
	stats.Position = UDim2.fromOffset(10, CELL + 74)
	stats.Size = UDim2.new(1, -20, 1, -(CELL + 80))
	stats.TextWrapped = true
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.TextYAlignment = Enum.TextYAlignment.Top
	stats.Text = data.stats

	-- Marca de "se tira" por encima de todo.
	local throw = Instance.new("Frame")
	throw.Name = "Throw"
	throw.Size = UDim2.fromScale(1, 1)
	throw.BackgroundColor3 = Color3.fromRGB(200, 30, 40)
	throw.BackgroundTransparency = 0.5
	throw.BorderSizePixel = 0
	throw.Visible = false
	throw.Active = false
	throw.ZIndex = 10
	throw.Parent = card
	Ui.round(throw, 12)
	local mark = Ui.label(throw, 34)
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "TIRAR"
	mark.Rotation = -12
	mark.ZIndex = 11

	local salvage = Ui.label(card, 13)
	salvage.Name = "Salvage"
	salvage.AnchorPoint = Vector2.new(0.5, 1)
	salvage.Position = UDim2.new(0.5, 0, 1, -4)
	salvage.Size = UDim2.new(1, -12, 0, 22)
	salvage.BackgroundTransparency = 0
	salvage.BackgroundColor3 = Ui.COLORS.orange
	salvage.Text = "Se desmontará"
	salvage.Visible = false
	salvage.ZIndex = 12
	Ui.round(salvage, 6)
	Ui.stroke(salvage, BLACK, 2)

	card.Activated:Connect(function()
		toggle(drop.id)
	end)
	cell.Activated:Connect(function()
		toggle(drop.id)
	end)
	state.cards[drop.id] = { Frame = card, Throw = throw, Salvage = salvage, Stroke = stroke }
end

-- Confirmación extra al tirar algo de rareza alta.
local function askConfirm(names: { string })
	confirmText.Text = `¿Seguro que quieres tirar esto?\n\n{table.concat(names, "\n")}`
	confirm.Visible = true
end

local function build()
	local body
	window, body = Ui.window("DropMenu", "¡BOTÍN!", Vector2.new(780, 580))

	head = Ui.label(body, 24)
	head.Name = "Head"
	head.Position = UDim2.fromOffset(12, 8)
	head.Size = UDim2.new(1, -24, 0, 32)
	head.TextXAlignment = Enum.TextXAlignment.Left

	notice = Ui.label(body, 16)
	notice.Name = "Notice"
	notice.Position = UDim2.fromOffset(12, 40)
	notice.Size = UDim2.new(1, -24, 0, 40)
	notice.TextWrapped = true
	notice.TextXAlignment = Enum.TextXAlignment.Left
	notice.TextYAlignment = Enum.TextYAlignment.Top

	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(8, 84)
	grid.Size = UDim2.new(1, -16, 1, -84 - 84)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD.X, CARD.Y)
	layout.CellPadding = UDim2.fromOffset(10, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = grid

	-- Franja de abajo: contador de tiempo y los dos botones.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 8, 1, -8)
	bar.Size = UDim2.new(1, -16, 0, 70)
	bar.BackgroundTransparency = 1
	bar.Parent = body
	keepButton = Ui.button(bar, "Quedarme todo", Ui.COLORS.green)
	keepButton.Name = "KeepAll"
	keepButton.Size = UDim2.new(0.5, -6, 1, 0)
	keepButton.TextSize = 24
	throwButton = Ui.button(bar, "Tirar seleccionados", Ui.COLORS.red)
	throwButton.Name = "ThrowSelected"
	throwButton.AnchorPoint = Vector2.new(1, 0)
	throwButton.Position = UDim2.fromScale(1, 0)
	throwButton.Size = UDim2.new(0.5, -6, 1, 0)
	throwButton.TextSize = 24

	keepButton.Activated:Connect(function()
		finish({})
	end)
	throwButton.Activated:Connect(function()
		local ids = selectedIds()
		if #ids == 0 then
			Ui.toast("Marca primero lo que quieras tirar", Ui.COLORS.orange)
			return
		end
		local names = {}
		for _, drop in state.drops do
			if state.selected[drop.id] and drop.high then
				local data = info(drop)
				table.insert(names, `<font color="{hex(data.color)}">{data.name} ({data.rarity})</font>`)
			end
		end
		if #names > 0 then
			askConfirm(names)
		else
			finish(ids)
		end
	end)

	-- Ventanita de confirmación, por encima de todo.
	confirm = Instance.new("Frame")
	confirm.Name = "Confirm"
	confirm.Size = UDim2.fromScale(1, 1)
	confirm.BackgroundColor3 = BLACK
	confirm.BackgroundTransparency = 0.35
	confirm.BorderSizePixel = 0
	confirm.Visible = false
	confirm.Active = true
	confirm.Parent = body
	Ui.round(confirm, 12)
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(480, 280)
	box.BackgroundColor3 = WHITE
	box.BorderSizePixel = 0
	box.Parent = confirm
	Ui.round(box, 14)
	Ui.stroke(box, BLACK, 5)
	Ui.panel(box, Color3.fromRGB(70, 44, 60))
	local title = Ui.label(box, 26)
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Text = "¡Es de rareza alta!"
	title.TextColor3 = GOLD
	confirmText = Ui.label(box, 18)
	confirmText.Position = UDim2.fromOffset(16, 50)
	confirmText.Size = UDim2.new(1, -32, 1, -130)
	confirmText.TextWrapped = true
	confirmText.TextYAlignment = Enum.TextYAlignment.Top
	local yes = Ui.button(box, "Sí, tirar", Ui.COLORS.red)
	yes.AnchorPoint = Vector2.new(0, 1)
	yes.Position = UDim2.new(0, 16, 1, -14)
	yes.Size = UDim2.new(0.5, -22, 0, 52)
	yes.TextSize = 22
	local no = Ui.button(box, "No, volver", Ui.COLORS.gray)
	no.AnchorPoint = Vector2.new(1, 1)
	no.Position = UDim2.new(1, -16, 1, -14)
	no.Size = UDim2.new(0.5, -22, 0, 52)
	no.TextSize = 22
	yes.Activated:Connect(function()
		finish(selectedIds())
	end)
	no.Activated:Connect(function()
		confirm.Visible = false
	end)
	Ui.layer(confirm, Z_CONFIRM)

	-- Cerrar con la X (o por cualquier otro camino) sin contestar equivale a "Quedarme todo".
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible and state.active then
			finish({})
		end
	end)
end

-- Abre el menú con el botín del servidor. `title` y `color` = cómo acabó la partida; `levelName` = la mazmorra.
function DropMenu.show(data, title: string, color: Color3, levelName: string?)
	for _, card in state.cards do
		card.Frame:Destroy()
	end
	state = { active = true, drops = data.drops, cards = {}, selected = {}, free = data.armorFree or 0, expires = data.expires or 0 }
	confirm.Visible = false
	head.Text = `<font color="{hex(color)}">{title}</font>{if levelName then `  <font color="{Ui.SOFT}">· {levelName}</font>` else ""}`
	for order, drop in data.drops do
		buildCard(drop, order)
	end
	grid.CanvasPosition = Vector2.zero
	refresh()
	Ui.open(window)

	-- Cuenta atrás hasta que el servidor se lo guarde todo.
	local current = state
	task.spawn(function()
		while state == current and current.active do
			local left = math.max(0, math.ceil(current.expires - workspace:GetServerTimeNow()))
			keepButton.Text = `Quedarme todo ({left} s)`
			task.wait(0.5)
		end
	end)
	if next(missing) then
		local keys = {}
		for key in missing do
			table.insert(keys, key)
		end
		warn("DropMenu: objetos sin imagen asignada (usan '?'): " .. table.concat(keys, ", "))
	end
end

function DropMenu.start()
	build()
end

return DropMenu
