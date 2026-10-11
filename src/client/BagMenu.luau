-- Menú de la Bolsa de oro (pedido por el usuario: dejar armas desde la mochila era poco intuitivo): se abre haciendo
-- clic en tu saco, tocándolo o con su aviso de E cuando estás cerca. Arriba, los huecos de la bolsa (pulsar un arma la
-- saca) y cómo va; abajo, tus demás armas de más a menos daño, las equipadas al final (pulsar una la deja). Solo pide: `SetBag` con el id de
-- la copia, "best" (las mejores sin equipar) o "clear" (vaciarla); el servidor decide (server/GoldBag) y aquí se pinta
-- lo que publican los atributos "Swords", "Loadout", "Bag", "BagStage", "BagTaken", "BagAt" y "BagRate".
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BagInfo = require(ReplicatedStorage.Shared.BagInfo)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)

local Backpack = require(script.Parent.Backpack)
local ForgeScene = require(script.Parent.ForgeScene)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local BagMenu = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 70)
local GOLD_HEX = "#ffd45a"

local TAG = "GoldBag"
local NAME = "BagMenu"
local REACH = 48 -- studs del saco desde los que se puede abrir con un clic
local PROMPT_REACH = 26 -- y desde los que sale el aviso de E (el pedestal mide 14 de radio)
local HOVER_EVERY = 0.1 -- segundos entre miradas a si el ratón está sobre el saco
local PICK_MARGIN = 1.5 -- studs de más alrededor del saco que cuentan como darle
local REFRESH = 0.25 -- cada cuánto se pone al día la barra con la ventana abierta
local SLOT = 104 -- lado de las casillas de los huecos
local SLOT_SMALL = 64 -- con los huecos del pase (Stats.bagSlots) van en dos filas, más pequeñas
local SLOT_AREA = 4 * SLOT + 3 * 14 -- ancho que ocupan los huecos sin el pase
local CELL = 92 -- y de las de tus armas
-- Capas de la barra (la interfaz ordena el ZIndex globalmente: lo demás va en la capa de su padre, por orden).
local Z = { fill = 2, text = 3 }

local window: Frame
local slotRow: Frame
local stockGrid: ScrollingFrame
local stageTitle: TextLabel
local barFill: Frame
local barAmount: TextLabel
local rateLabel: TextLabel
local slotGrid: UIGridLayout
local slotHint: TextLabel
local infoPanel: Frame
local stockTitle: TextLabel
local bestButton: TextButton
local clearButton: TextButton

local slotKey = "" -- de qué depende lo que enseñan los huecos
local stockCells = {} -- [id de la copia] = casilla
local stockKeys = {} -- [id de la copia] = de qué depende lo que enseña
local highlight: Highlight? = nil
local prompt: ProximityPrompt? = nil
local ticking = false -- el bucle de la barra ya está en marcha

-- Tu saco (el de la parcela que tienes), o nil.
local function myBag(): Model?
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsA("Model") and model:GetAttribute("Owner") == player.UserId and model.PrimaryPart then
			return model
		end
	end
	return nil
end

local function near(model: Model, reach: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - model.PrimaryPart.Position).Magnitude <= reach
end

-- Si ese punto de la pantalla señala tu saco y estás lo bastante cerca para abrirlo. El saco no entra en los rayos
-- del juego (su caja no se puede consultar): se cuenta como una bola de su tamaño.
function BagMenu.pointed(point: Vector2): boolean
	local camera = workspace.CurrentCamera
	local model = myBag()
	if not camera or not model or not near(model, REACH) then
		return false
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local center = model.PrimaryPart.Position
	local along = (center - ray.Origin):Dot(ray.Direction.Unit)
	if along <= 0 then
		return false
	end
	local gap = (ray.Origin + ray.Direction.Unit * along - center).Magnitude
	return gap <= (model:GetAttribute("Radius") or 6.5) + PICK_MARGIN
end

local function coinsPerHit(copy): number
	return BagInfo.coins(Stats.bagHit(player, copy))
end

local function swordTip(copy, line: string)
	local text, color, animated = Backpack.swordTip(copy)
	return `{text}\n<font color="{GOLD_HEX}">+{Format.short(coinsPerHit(copy))} monedas por golpe</font>\n<font color="{Ui.SOFT}">{line}</font>`, color, animated
end

-- Casilla de un arma: vista 3D, lo que saca por golpe abajo y sus marcas (metal, tamaño y rasgo, como en la mochila).
local function swordCell(parent: Instance, copy): TextButton
	local tier = Rarity.tier(Stats.rarity(copy))
	local cell = Ui.cell(parent, tier.color, table.find(Config.RarityTiers, tier))
	WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
	local amount = Ui.cellLabel(cell, "+" .. Format.short(coinsPerHit(copy)))
	amount.Name = "Coins"
	amount.Size = UDim2.new(1, -8, 0, 24)
	Ui.gradient(amount, WHITE, GOLD, 90)
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	if metal then
		local dot = Instance.new("Frame")
		dot.Name = "Metal"
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -6, 0, 6)
		dot.Size = UDim2.fromOffset(16, 16)
		dot.BackgroundColor3 = metal.color
		dot.BorderSizePixel = 0
		dot.ZIndex = 3
		dot.Parent = cell
		Ui.round(dot, 8)
		Ui.stroke(dot, BLACK, 2)
	end
	if size then
		local tag = Ui.cellTag(cell, string.sub(size.name, 1, 1), size.color)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -4, 0, if metal then 26 else 4)
	end
	return cell
end

-- Hueco libre de la bolsa: marco oscuro con un "+".
local function emptySlot(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, 10)
	Ui.stroke(frame, BLACK, 3)
	Ui.gradient(frame, Color3.fromRGB(52, 42, 30), Color3.fromRGB(24, 20, 16), 90)
	local plus = Ui.label(frame, 46)
	plus.Name = "Plus"
	plus.Position = UDim2.fromScale(0, 0.06)
	plus.Size = UDim2.fromScale(1, 0.62)
	plus.Text = "+"
	plus.TextColor3 = Color3.fromRGB(150, 128, 92)
	local free = Ui.label(frame, 15)
	free.Name = "Free"
	free.Position = UDim2.fromScale(0, 0.68)
	free.Size = UDim2.fromScale(1, 0.24)
	free.Text = "Libre"
	free.TextColor3 = Color3.fromRGB(190, 170, 136)
	return frame
end

local function ask(what: number | string)
	Sfx.play("equip")
	Remotes.SetBag:FireServer(what)
end

-- Los huecos de arriba: se rehacen solo si cambian las depositadas (son cuatro casillas).
local function syncSlots(deposited)
	local parts = {}
	for _, copy in deposited do
		table.insert(parts, `{copy.id}:{copy.sword}:{copy.trait}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}`)
	end
	local count = Stats.bagSlots(player)
	local key = table.concat(parts, ",") .. "|" .. tostring(player:GetAttribute("BagRate")) .. "|" .. count
	if key == slotKey then
		return
	end
	slotKey = key
	-- Con los huecos del pase: dos filas de casillas más pequeñas, sin la frase de abajo, y más sitio para los datos.
	local double = count > Config.GoldBag.Slots
	local side, gap = if double then SLOT_SMALL else SLOT, if double then 8 else 14
	local columns = if double then math.ceil(count / 2) else count
	local width = columns * side + (columns - 1) * gap
	slotGrid.CellSize = UDim2.fromOffset(side, side)
	slotGrid.CellPadding = UDim2.fromOffset(gap, gap)
	slotGrid.FillDirectionMaxCells = columns
	slotRow.Size = UDim2.fromOffset(width, if double then 2 * side + gap else side)
	slotHint.Visible = not double
	infoPanel.Size = UDim2.new(1, -(width + 14 + 14 + 12), 0, 132)
	for _, child in slotRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for slot = 1, count do
		local copy = deposited[slot]
		local item: GuiObject
		if copy then
			local cell = swordCell(slotRow, copy)
			Ui.tip(cell, function()
				return swordTip(copy, "Pulsa para sacarla de la bolsa")
			end, true)
			cell.Activated:Connect(function()
				ask(copy.id)
			end)
			item = cell
		else
			item = emptySlot(slotRow)
		end
		item.Name = "Slot" .. slot
		item.LayoutOrder = slot
	end
end

-- Tus demás armas: solo se tocan las casillas que cambian (cada una lleva su vista 3D).
local function syncStock(copies, worn: { number }, deposited)
	local inBag = {}
	for _, copy in deposited do
		inBag[copy.id] = true
	end
	local full = #deposited >= Stats.bagSlots(player)
	local global = tostring(player:GetAttribute("BagRate")) -- si cambia lo global del jugador, cambia lo que saca cada una
	local seen = {}
	local shown = {}
	for _, copy in copies do
		if inBag[copy.id] then
			continue
		end
		seen[copy.id] = true
		table.insert(shown, copy)
		local isEquipped = table.find(worn, copy.id) ~= nil
		local key = `{copy.sword}:{copy.trait}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}:{isEquipped}:{global}`
		if stockKeys[copy.id] == key then
			continue
		end
		if stockCells[copy.id] then
			stockCells[copy.id]:Destroy()
		end
		stockKeys[copy.id] = key
		local cell = swordCell(stockGrid, copy)
		cell.Name = "Sword" .. copy.id
		if isEquipped then
			Ui.cellTag(cell, "E", Ui.COLORS.green)
		end
		Ui.tip(cell, function()
			local line = if Stats.isEquipped(player, copy.id) then "Equipada: dejará de estarlo"
				elseif #Stats.list(player, "Bag") >= Stats.bagSlots(player) then "Bolsa llena: cambia a la peor"
				else "Pulsa: a la bolsa"
			return swordTip(copy, line)
		end, true)
		cell.Activated:Connect(function()
			ask(copy.id)
		end)
		stockCells[copy.id] = cell
	end
	for id, cell in stockCells do
		if not seen[id] then
			cell:Destroy()
			stockCells[id] = nil
			stockKeys[id] = nil
		end
	end
	-- De más a menos daño, con las equipadas al final: dejar una de esas la quita del equipo.
	table.sort(shown, function(a, b)
		local wornA, wornB = table.find(worn, a.id) ~= nil, table.find(worn, b.id) ~= nil
		if wornA ~= wornB then
			return wornB
		end
		local left, right = Stats.swordDamage(a), Stats.swordDamage(b)
		return if left ~= right then left > right else a.id < b.id
	end)
	for position, copy in shown do
		local cell = stockCells[copy.id]
		if cell then
			cell.LayoutOrder = position
		end
	end
	stockTitle.Text = `Tus armas <font color="{Ui.SOFT}">· {if full then "bolsa llena" else "pulsa una para dejarla"}</font>`
end

-- Cómo va la bolsa: por cuál vas, lo que le queda (lo calcula el cliente entre aviso y aviso) y lo que sacan tus armas.
local function syncProgress(deposited)
	local stage = player:GetAttribute("BagStage") or 1
	local full = BagInfo.size(stage)
	local rate = player:GetAttribute("BagRate") or 0
	local elapsed = math.max(workspace:GetServerTimeNow() - (player:GetAttribute("BagAt") or 0), 0)
	local taken = math.clamp((player:GetAttribute("BagTaken") or 0) + rate * elapsed, 0, full)
	stageTitle.Text = `BOLSA Nº {stage}`
	barFill.Size = UDim2.fromScale(math.clamp(1 - taken / full, 0, 1), 1)
	barAmount.Text = Format.short(math.ceil(full - taken))
	local perHit = 0
	for _, copy in deposited do
		perHit += coinsPerHit(copy)
	end
	rateLabel.Text = if #deposited == 0 then `<font color="{Ui.SOFT}">Sin armas: no saca nada</font>`
		else `Golpes: <font color="{GOLD_HEX}">+{Format.short(perHit)}</font>`
end

-- Crear una casilla puede esperar (la vista 3D carga su arma): un refresco que llega a medias se apunta y se hace
-- al acabar, para que no se pisen.
local refreshing, again = false, false
local function refresh()
	if not window.Visible then
		return
	end
	if refreshing then
		again = true
		return
	end
	refreshing = true
	repeat
		again = false
		local deposited = Stats.deposited(player)
		syncSlots(deposited)
		syncStock(Stats.swords(player), Stats.list(player, "Loadout"), deposited)
		syncProgress(deposited)
		clearButton.BackgroundColor3 = if #deposited > 0 then Ui.COLORS.red else Ui.COLORS.gray
	until not again
	refreshing = false
end

function BagMenu.open()
	if ForgeScene.isActive() or Ui.isOpen(window) then
		return
	end
	Ui.toggle(NAME) -- al hacerse visible se rellena (ver start)
end

local function build()
	local body
	window, body = Ui.window(NAME, "Bolsa de oro", Vector2.new(720, 560), function(parent)
		Ui.image(parent, "monedas")
	end)

	-- Arriba: los huecos de la bolsa y cómo va.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.Position = UDim2.fromOffset(8, 8)
	top.Size = UDim2.new(1, -16, 0, 156)
	top.BorderSizePixel = 0
	top.Parent = body
	Ui.round(top, 12)
	Ui.stroke(top, BLACK, 3)
	Ui.panel(top, Color3.fromRGB(86, 62, 34))

	slotRow = Instance.new("Frame")
	slotRow.Name = "Slots"
	slotRow.Position = UDim2.fromOffset(14, 12)
	slotRow.Size = UDim2.fromOffset(SLOT_AREA, SLOT)
	slotRow.BackgroundTransparency = 1
	slotRow.Parent = top
	local row = Instance.new("UIGridLayout")
	row.CellSize = UDim2.fromOffset(SLOT, SLOT)
	row.CellPadding = UDim2.fromOffset(14, 0)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = slotRow
	slotGrid = row

	local hint = Ui.label(top, 15)
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(14, 122)
	hint.Size = UDim2.fromOffset(slotRow.Size.X.Offset, 24)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.fromRGB(232, 214, 180)
	hint.Text = "Estas armas pegan al saco solas, también cuando no estás"
	hint.TextScaled = true
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 15
	hintLimit.MinTextSize = 10
	hintLimit.Parent = hint
	slotHint = hint

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(1, 0)
	info.Position = UDim2.new(1, -12, 0, 12)
	info.Size = UDim2.new(1, -(slotRow.Size.X.Offset + 14 + 14 + 12), 0, 132)
	info.BackgroundTransparency = 1
	info.Parent = top
	infoPanel = info

	stageTitle = Ui.label(info, 26)
	stageTitle.Name = "Title"
	stageTitle.Size = UDim2.new(1, 0, 0, 36)
	stageTitle.TextScaled = true
	Ui.gradient(stageTitle, WHITE, GOLD, 90)
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 26
	titleLimit.MinTextSize = 14
	titleLimit.Parent = stageTitle

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(0, 44)
	bar.Size = UDim2.new(1, 0, 0, 38)
	bar.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
	bar.BorderSizePixel = 0
	bar.Parent = info
	Ui.round(bar, 9)
	Ui.stroke(bar, BLACK, 3)
	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = WHITE
	barFill.BorderSizePixel = 0
	barFill.ZIndex = Z.fill
	barFill.Parent = bar
	Ui.round(barFill, 9)
	Ui.gradient(barFill, Color3.fromRGB(255, 226, 110), Color3.fromRGB(240, 150, 30), 90)
	local coin = Ui.image(bar, "monedas")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 4, 0.5, 0)
	coin.Size = UDim2.fromOffset(30, 30)
	coin.ZIndex = Z.text
	barAmount = Ui.label(bar, 21)
	barAmount.Name = "Amount"
	barAmount.Size = UDim2.fromScale(1, 1)
	barAmount.ZIndex = Z.text

	rateLabel = Ui.label(info, 19)
	rateLabel.Name = "Rate"
	rateLabel.Position = UDim2.fromOffset(0, 92)
	rateLabel.Size = UDim2.new(1, 0, 0, 34)
	rateLabel.TextScaled = true
	local rateLimit = Instance.new("UITextSizeConstraint")
	rateLimit.MaxTextSize = 20
	rateLimit.MinTextSize = 11
	rateLimit.Parent = rateLabel

	-- En medio: título de tus armas y las dos acciones rápidas.
	stockTitle = Ui.label(body, 22)
	stockTitle.Name = "Title"
	stockTitle.Position = UDim2.fromOffset(14, 170)
	stockTitle.Size = UDim2.new(1, -326, 0, 44)
	stockTitle.TextXAlignment = Enum.TextXAlignment.Left
	stockTitle.TextTruncate = Enum.TextTruncate.AtEnd

	local function action(name: string, text: string, color: Color3, right: number, width: number): TextButton
		local item = Ui.button(body, text, color)
		item.Name = name
		item.AnchorPoint = Vector2.new(1, 0)
		item.Position = UDim2.new(1, -right, 0, 172)
		item.Size = UDim2.fromOffset(width, 42)
		item.TextSize = 19
		return item
	end
	bestButton = action("Best", "Poner las mejores", Ui.COLORS.green, 10, 186)
	clearButton = action("Clear", "Vaciar", Ui.COLORS.red, 204, 100)
	bestButton.Activated:Connect(function()
		ask("best") -- las de más daño sin equipar: lo decide el servidor
	end)
	clearButton.Activated:Connect(function()
		if #Stats.list(player, "Bag") > 0 then
			ask("clear")
		end
	end)

	stockGrid = Instance.new("ScrollingFrame")
	stockGrid.Name = "Grid"
	stockGrid.Position = UDim2.fromOffset(8, 222)
	stockGrid.Size = UDim2.new(1, -16, 1, -230)
	stockGrid.BackgroundTransparency = 1
	stockGrid.BorderSizePixel = 0
	stockGrid.ScrollBarThickness = 8
	stockGrid.ScrollBarImageColor3 = GOLD
	stockGrid.CanvasSize = UDim2.new()
	stockGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stockGrid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(16, 16) -- los marcos gruesos y el halo ocupan parte del hueco
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stockGrid
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = stockGrid
end

-- El aviso de E y el resalte del saco: solo en el tuyo.
local function tend(pointer: Vector2?)
	local model = myBag()
	local body = model and model.PrimaryPart
	if prompt and prompt.Parent ~= body then
		prompt:Destroy()
		prompt = nil
	end
	if body and not prompt then
		local item = Instance.new("ProximityPrompt")
		item.Name = "BagPrompt"
		item.ObjectText = "Bolsa de oro"
		item.ActionText = "Elegir armas"
		item.KeyboardKeyCode = Enum.KeyCode.E
		item.GamepadKeyCode = Enum.KeyCode.ButtonX
		item.HoldDuration = 0
		item.MaxActivationDistance = PROMPT_REACH
		item.RequiresLineOfSight = false
		item.Triggered:Connect(BagMenu.open)
		item.Parent = body
		prompt = item
	end
	if prompt then
		prompt.Enabled = not Ui.anyOpen() and not ForgeScene.isActive()
	end
	-- Con el ratón encima, el saco se ilumina: dice que se puede pulsar.
	local lit = model ~= nil and pointer ~= nil and not Ui.anyOpen() and not ForgeScene.isActive() and BagMenu.pointed(pointer)
	if lit and not highlight then
		local glow = Instance.new("Highlight")
		glow.Name = "BagHover"
		glow.FillColor = GOLD
		glow.FillTransparency = 0.8
		glow.OutlineColor = WHITE
		glow.OutlineTransparency = 0.1
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight = glow
	end
	if highlight then
		-- Solo el saco (el de Blender va en su modelo "GoldSack"), sin el pedestal ni el camino.
		local sack = if lit and model then model:FindFirstChild("GoldSack") or model else nil
		highlight.Adornee = sack
		highlight.Parent = sack
	end
end

function BagMenu.start()
	build()

	for _, name in { "Swords", "Loadout", "Bag", "BagStage", "BagRate", "Pass_arsenal" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible then
			return
		end
		refresh()
		if ticking then
			return
		end
		ticking = true
		-- La barra baja sola mientras la ventana esté a la vista.
		task.spawn(function()
			while window.Visible do
				task.wait(REFRESH)
				if window.Visible then
					syncProgress(Stats.deposited(player))
				end
			end
			ticking = false
		end)
	end)

	-- Clic o toque en el saco. SwordController no ataca cuando el puntero está en el saco (BagMenu.pointed).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or Ui.anyOpen() then
			return
		end
		if BagMenu.pointed(UserInputService:GetMouseLocation()) then
			BagMenu.open()
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(position, processed)
		-- El toque llega sin el hueco de arriba de la pantalla, que la cámara sí cuenta.
		if not processed and not Ui.anyOpen() and BagMenu.pointed(position + GuiService:GetGuiInset()) then
			BagMenu.open()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(HOVER_EVERY)
			tend(if UserInputService.MouseEnabled then UserInputService:GetMouseLocation() else nil)
		end
	end)
end

return BagMenu
