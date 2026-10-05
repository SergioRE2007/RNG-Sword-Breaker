-- Mochila: ventana con pestañas (Espadas, Objetos, Accesorios y Armadura, esta última en ArmorPane).
-- "Accesorios" es el nombre para el jugador de los artefactos (Config.Artifacts; en el código siguen siendo Gear). Todo son casillas cuadradas con
-- el borde del color de su rareza; al pasar el ratón sale un cartel con los detalles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)
local Performance = require(script.Parent.Performance)
local WeaponPreview = require(script.Parent.WeaponPreview)
local ArmorPane = require(script.Parent.ArmorPane)

local Backpack = {}

local player = Players.LocalPlayer
local CELL = 100

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Casilla que aparece con rebote (crece desde pequeña), tras `delay` segundos.
local function popIn(cell: GuiObject, delay: number)
	if Performance.get() then return end -- modo rendimiento
	local scale = cell:FindFirstChild("PressScale") :: UIScale?
	if not scale then
		return
	end
	scale.Scale = 0.3
	task.delay(delay, function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
end

-- Sacudida corta de una casilla (al equiparla).
local function wiggle(cell: GuiObject)
	if Performance.get() then return end -- modo rendimiento
	task.spawn(function()
		for _, angle in { -9, 8, -5, 3, 0 } do
			local step = TweenService:Create(cell, TweenInfo.new(0.07, Enum.EasingStyle.Quad), { Rotation = angle })
			step:Play()
			step.Completed:Wait()
		end
	end)
end

-- Marca de "recién conseguida": cartelito y borde amarillo que late hasta que se pasa el ratón por encima.
local function markNew(cell: GuiObject)
	if Performance.get() then return end -- modo rendimiento
	local glow = Instance.new("Frame")
	glow.Name = "NewGlow"
	glow.Position = UDim2.fromOffset(-4, -4)
	glow.Size = UDim2.new(1, 8, 1, 8)
	glow.BackgroundTransparency = 1
	glow.ZIndex = 6
	glow.Parent = cell
	Ui.round(glow, 14)
	local ring = Ui.stroke(glow, Color3.fromRGB(255, 230, 80), 3)
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 }):Play()
	local banner = Ui.label(glow, 12)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 7)
	banner.Size = UDim2.fromOffset(52, 15)
	banner.BackgroundTransparency = 0
	banner.BackgroundColor3 = Color3.fromRGB(255, 190, 30)
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Text = "NUEVA"
	banner.ZIndex = 7
	Ui.round(banner, 6)
	Ui.stroke(banner, Color3.new(0, 0, 0), 2)
	cell.MouseEnter:Once(function()
		glow:Destroy()
	end)
end

local function pane(body: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = body
	return frame
end

local function grid(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Position = position
	scroll.Size = size
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(16, 16) -- los marcos gruesos y el halo ocupan parte del hueco
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	-- Hueco para el halo de las casillas raras, que sobresale del borde.
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = scroll
	return scroll
end

-- Puesto de cada arma de Config.Swords por daño (1 = la más floja), para ordenar el inventario.
local damageRank = {}
do
	local order = {}
	for index in Config.Swords do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		return Config.Swords[a].damage < Config.Swords[b].damage
	end)
	for rank, index in order do
		damageRank[index] = rank
	end
end

-- Cartel de una copia de espada (nombre, rareza, tipo, rasgo, grado, daño). También lo usan
-- las tiendas de Rasgos y Grados (Backpack.swordTip).
-- Nombre de un rasgo o grado con letras animadas, como en las tiendas: el arcoíris corre por las
-- letras y los demás llevan un destello blanco que las cruza. Hay que volver a pedirlo cada
-- fotograma (el cartel lo hace solo si swordTip devuelve `true` como tercer valor).
local function animatedName(entry): string
	local now = os.clock()
	local count = utf8.len(entry.name) or #entry.name
	local shine = (now * 7) % (count + 10) - 5
	local letters = {}
	local index = 0
	for _, code in utf8.codes(entry.name) do
		index += 1
		local color
		if entry.rainbow then
			color = Color3.fromHSV((now * 0.6 + index * 0.09) % 1, 0.6, 1)
		else
			color = entry.color:Lerp(Color3.new(1, 1, 1), math.max(0, 1 - math.abs(index - shine) / 2.5) * 0.85)
		end
		table.insert(letters, `<font color="{hex(color)}">{utf8.char(code)}</font>`)
	end
	return table.concat(letters)
end

local function swordTip(copy): (string, Color3, boolean)
	local sword = Config.Swords[copy.sword]
	local trait = Config.Traits[copy.trait]
	local rarity = Stats.rarity(copy)
	local tier = Rarity.tier(rarity)
	local lines = { sword.name, `<font color="{hex(tier.color)}">{tier.name}</font> · {Config.WeaponKinds[sword.kind or "sword"].name}` }
	local grade = Config.Grades[copy.grade]
	local border = tier.color
	-- Metal y tamaño (permanentes, salen con el arma): lo que son y lo que multiplican.
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	if metal then
		table.insert(lines, `<font color="{hex(metal.color)}">Metal: {metal.name}</font> (x{Format.multiplier(Permanent.damage(metal.odds))} daño · 1 entre {Format.short(metal.odds)})`)
	end
	if size then
		table.insert(lines, `<font color="{hex(size.color)}">Tamaño: {size.name}</font> (x{Format.multiplier(Permanent.damage(size.odds))} daño, x{size.scale} de largo · 1 entre {Format.short(size.odds)})`)
	end
	if trait or grade then
		table.insert(lines, "") -- aparte: rasgo y grado forman su propio bloque
	end
	if trait then
		table.insert(lines, `<font color="{hex(trait.color)}">Rasgo:</font> {animatedName(trait)} ({Modifiers.effect(trait)})`)
		if trait.rainbow then
			border = Color3.fromHSV(os.clock() * 0.5 % 1, 0.55, 1)
		end
	end
	if grade then
		table.insert(lines, `<font color="{hex(grade.color)}">Grado:</font> {animatedName(grade)} ({Modifiers.effect(grade)})`)
		if grade.rainbow then
			border = Color3.fromHSV(os.clock() * 0.5 % 1, 0.55, 1)
		end
	end
	if trait or grade then
		table.insert(lines, "")
	end
	table.insert(lines, `Daño {Format.multiplier(Stats.swordDamage(copy))}`)
	table.insert(lines, `<font color="{Ui.SOFT}">{if sword.rarity then "1 entre " .. Format.short(rarity) else "Espada inicial"}</font>`)
	return table.concat(lines, "\n"), border, trait ~= nil or grade ~= nil
end

local function artifactTip(index: number): (string, Color3)
	local artifact = Config.Artifacts[index]
	local tier = Rarity.tier(artifact.rarity)
	return `{artifact.name}\n<font color="{hex(tier.color)}">{tier.name}</font>\n{Config.StatNames[artifact.stat]} x{Format.multiplier(artifact.mult)}\n<font color="{Ui.SOFT}">1 entre {Format.short(artifact.rarity)}</font>`,
		tier.color
end

function Backpack.start()
	local window, body = Ui.window("Backpack", "Mochila", Vector2.new(740, 560), function(parent)
		Ui.backpackIcon(parent, Color3.fromRGB(240, 150, 60))
	end)

	-- Pestañas, pegadas al lado izquierdo de la ventana.
	local panes = {}
	local tabs = {}
	local current = "Swords"
	local onShow = {}
	local function show(name: string)
		current = name
		for key, frame in panes do
			local opening = key == name and not frame.Visible
			frame.Visible = key == name
			tabs[key].stroke.Color = if key == name then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			-- La pestaña elegida se asoma un poco más y el contenido entra deslizándose.
			TweenService:Create(tabs[key].button, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(if key == name then -118 else -108, tabs[key].y),
			}):Play()
			if opening then
				frame.Position = UDim2.fromOffset(24, 0)
				TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }):Play()
			end
		end
		if onShow[name] then
			onShow[name]()
		end
	end
	-- Cada pestaña lleva su icono (dibujado con marcos) encima del nombre.
	local tabIcons = {
		Swords = function(parent)
			Ui.swordIcon(parent, Color3.fromRGB(235, 240, 250))
		end,
		Items = function(parent)
			Ui.boxIcon(parent, Color3.fromRGB(255, 210, 90))
		end,
		Gear = function(parent)
			Ui.gemIcon(parent, Color3.fromRGB(230, 170, 255))
		end,
		Armor = function(parent)
			ArmorPane.icon(parent, Color3.fromRGB(200, 210, 230))
		end,
	}
	for order, entry in { { "Swords", "Espadas", Ui.COLORS.red }, { "Items", "Objetos", Ui.COLORS.blue }, { "Gear", "Accesorios", Ui.COLORS.purple }, { "Armor", "Armadura", Ui.COLORS.orange } } do
		local name = entry[1]
		panes[name] = pane(body, name)
		local tab = Ui.button(window, "", entry[3])
		tab.Name = "Tab" .. name
		tab.Position = UDim2.fromOffset(-108, 66 + (order - 1) * 78)
		tab.Size = UDim2.fromOffset(96, 66)
		local iconBox = Instance.new("Frame")
		iconBox.Name = "Icon"
		iconBox.AnchorPoint = Vector2.new(0.5, 0)
		iconBox.Position = UDim2.new(0.5, 0, 0, 3)
		iconBox.Size = UDim2.fromOffset(36, 36)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = tab
		tabIcons[name](iconBox)
		local label = Ui.label(tab, 17)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -4)
		label.Size = UDim2.new(1, -6, 0, 20)
		label.Text = entry[2]
		-- Los nombres largos ("Accesorios") se encogen para caber en la pestaña.
		label.TextScaled = true
		local labelLimit = Instance.new("UITextSizeConstraint")
		labelLimit.MaxTextSize = 17
		labelLimit.MinTextSize = 11
		labelLimit.Parent = label
		tabs[name] = { button = tab, stroke = tab:FindFirstChildOfClass("UIStroke"), y = 66 + (order - 1) * 78 }
		tab.Activated:Connect(function()
			show(name)
		end)
	end

	-- Espadas ---------------------------------------------------------------------------
	local swordsPane = panes.Swords

	-- (La venta automática se cambia ahora en Ajustes.)
	local title = Ui.label(swordsPane, 24)
	title.Position = UDim2.fromOffset(14, 6)
	title.Size = UDim2.fromOffset(300, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Tus espadas"

	local count = Ui.label(swordsPane, 24)
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -12, 0, 6)
	count.Size = UDim2.fromOffset(130, 40)
	count.BackgroundTransparency = 0
	count.BackgroundColor3 = Ui.COLORS.blue
	Ui.round(count, 8)
	Ui.bevel(count)
	Ui.stroke(count, Color3.new(0, 0, 0), 2)

	local swordGrid = grid(swordsPane, UDim2.fromOffset(8, 52), UDim2.new(1, -16, 1, -134))

	-- Barra de abajo: detalles de la espada elegida y sus acciones, sobre una franja oscura.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 4, 1, -2)
	bar.Size = UDim2.new(1, -8, 0, 74)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = swordsPane
	Ui.round(bar, 10)
	Ui.stroke(bar, Color3.new(0, 0, 0), 2)
	Ui.gradient(bar, Color3.fromRGB(58, 52, 96), Color3.fromRGB(20, 20, 34), 90)

	local detail = Ui.label(swordsPane, 19)
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(0, 1)
	detail.Position = UDim2.new(0, 12, 1, -8)
	detail.Size = UDim2.fromOffset(172, 62)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextWrapped = true

	local function action(name: string, text: string, color: Color3, right: number, width: number): TextButton
		local item = Ui.button(swordsPane, text, color)
		item.Name = name
		item.AnchorPoint = Vector2.new(1, 1)
		item.Position = UDim2.new(1, -right, 1, -8)
		item.Size = UDim2.fromOffset(width, 62)
		return item
	end
	local bestButton = action("Best", "Equipar mejor", Ui.COLORS.green, 12, 176)
	local sellButton = action("Sell", if Config.Gacha.SellValue > 0 then `Vender\n+{Config.Gacha.SellValue} gemas` else "Vender", Ui.COLORS.red, 198, 100)
	local equipButton = action("Equip", "Equipar", Ui.COLORS.blue, 308, 104)
	bestButton.TextSize = 23
	equipButton.TextSize = 20
	sellButton.TextSize = 17

	local selected = nil -- id de la copia elegida
	local swordCells = {} -- [id] = casilla
	local swordsKey = nil

	equipButton.Activated:Connect(function()
		if selected then
			Remotes.EquipSword:FireServer(selected)
		end
	end)
	sellButton.Activated:Connect(function()
		if selected then
			Remotes.SellSword:FireServer(selected)
		end
	end)
	bestButton.Activated:Connect(function()
		local best, bestDamage = nil, -1
		for _, copy in Stats.swords(player) do
			local damage = Stats.swordDamage(copy)
			if damage > bestDamage then
				best, bestDamage = copy, damage
			end
		end
		if best then
			selected = best.id
			Remotes.EquipSword:FireServer(best.id)
		end
	end)

	local function refreshSelection(copies, equippedId: number)
		local chosen = nil
		for _, copy in copies do
			if copy.id == selected then
				chosen = copy
			end
		end
		if not chosen then
			selected = equippedId
			for _, copy in copies do
				if copy.id == equippedId then
					chosen = copy
				end
			end
		end
		for id, cell in swordCells do
			cell.Select.Visible = id == selected
		end
		if chosen then
			local sword = Config.Swords[chosen.sword]
			local trait = Config.Traits[chosen.trait]
			local grade = Config.Grades[chosen.grade]
			detail.Text = `{sword.name}{if trait then ` <font color="{hex(trait.color)}">[{trait.name}]</font>` else ""}{if grade then ` <font color="{hex(grade.color)}">[{grade.name}]</font>` else ""}\n<font color="{Ui.SOFT}">Daño {Format.multiplier(Stats.swordDamage(chosen))}</font>`
		end
		local isEquipped = selected == equippedId
		equipButton.Text = if isEquipped then "Equipada" else "Equipar"
		equipButton.BackgroundColor3 = if isEquipped then Ui.COLORS.gray else Ui.COLORS.blue
		sellButton.BackgroundColor3 = if isEquipped then Ui.COLORS.gray else Ui.COLORS.red
	end

	-- Deja las casillas como el inventario tocando solo las que han cambiado. Rehacerlas todas en cada
	-- tirada del gacha daba un tirón, porque cada casilla lleva su vista 3D.
	local cellKeys = {} -- [id] = de qué depende lo que enseña su casilla
	local loaded = false -- pasada la primera carga del inventario, lo que llega es nuevo
	local function syncSwords(copies, equippedId: number)
		local seen = {}
		for _, copy in copies do
			seen[copy.id] = true
			local key = `{copy.sword}:{copy.trait}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}:{copy.id == equippedId}`
			if cellKeys[copy.id] == key then
				continue
			end
			local known = cellKeys[copy.id] ~= nil
			if swordCells[copy.id] then
				swordCells[copy.id]:Destroy()
			end
			cellKeys[copy.id] = key

			local sword = Config.Swords[copy.sword]
			local trait = Config.Traits[copy.trait]
			local tier = Rarity.tier(Stats.rarity(copy))
			local cell = Ui.cell(swordGrid, tier.color, table.find(Config.RarityTiers, tier))
			cell.Name = "Sword" .. copy.id
			-- (El orden de las casillas, de más a menos daño, se pone al final de syncSwords.)
			WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
			-- Daño grande abajo a la izquierda.
			local damage = Ui.cellLabel(cell, Format.multiplier(Stats.swordDamage(copy)))
			damage.Position = UDim2.new(0.5, 3, 1, -3)
			damage.Size = UDim2.new(1, -10, 0, 26)
			damage.TextXAlignment = Enum.TextXAlignment.Left
			damage:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 23
			damage:FindFirstChildOfClass("UIStroke").Thickness = 2.5
			Ui.gradient(damage, Color3.new(1, 1, 1), tier.color:Lerp(Color3.new(1, 1, 1), 0.45), 90)
			if copy.id == equippedId then
				Ui.cellTag(cell, "E", Ui.COLORS.green)
			end
			-- Metal (círculo de su color) y tamaño (cartelito con su inicial) en el lado izquierdo, bajo la "E".
			local metalDef, sizeDef = Permanent.metal(copy), Permanent.size(copy)
			if metalDef then
				local dot = Instance.new("Frame")
				dot.Name = "Metal"
				dot.Position = UDim2.fromOffset(6, 30)
				dot.Size = UDim2.fromOffset(18, 18)
				dot.BackgroundColor3 = metalDef.color
				dot.BorderSizePixel = 0
				dot.ZIndex = 3
				dot.Parent = cell
				Ui.round(dot, 9)
				Ui.stroke(dot, Color3.new(0, 0, 0), 2)
			end
			if sizeDef then
				Ui.cellTag(cell, string.sub(sizeDef.name, 1, 1), sizeDef.color).Position = UDim2.fromOffset(4, if metalDef then 52 else 30)
			end
			if trait then
				-- Rombo del color del rasgo en la esquina.
				local mark = Instance.new("Frame")
				mark.Name = "Trait"
				mark.AnchorPoint = Vector2.new(1, 0)
				mark.Position = UDim2.new(1, -9, 0, 9)
				mark.Size = UDim2.fromOffset(20, 20)
				mark.Rotation = 45
				mark.BackgroundColor3 = trait.color
				mark.BorderSizePixel = 0
				mark.ZIndex = 3
				mark.Parent = cell
				Ui.stroke(mark, Color3.new(0, 0, 0), 2)
			end
			Ui.tip(cell, function()
				return swordTip(copy)
			end, true)
			cell.Activated:Connect(function()
				selected = copy.id
				refreshSelection(Stats.swords(player), player:GetAttribute("Equipped") or 1)
			end)
			swordCells[copy.id] = cell
			-- Las casillas que llegan después de la carga inicial entran con rebote y, si son una copia nueva, con marca.
			if loaded then
				if known then
					wiggle(cell)
				else
					popIn(cell, 0)
					markNew(cell)
				end
			end
		end
		loaded = true
		for id, cell in swordCells do
			if not seen[id] then
				cell:Destroy()
				swordCells[id] = nil
				cellKeys[id] = nil
			end
		end
		-- Las de más daño primero (con metal, tamaño y rasgo incluidos).
		local ordered = table.clone(copies)
		table.sort(ordered, function(a, b)
			return Stats.swordDamage(a) > Stats.swordDamage(b)
		end)
		for position, copy in ordered do
			local cell = swordCells[copy.id]
			if cell then
				cell.LayoutOrder = position
			end
		end
	end

	-- Al abrir la pestaña de espadas, las primeras casillas entran una tras otra.
	onShow.Swords = function()
		local cells = {}
		for _, child in swordGrid:GetChildren() do
			if child:IsA("GuiButton") then
				table.insert(cells, child)
			end
		end
		table.sort(cells, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, math.min(#cells, 30) do
			popIn(cells[index], index * 0.018)
		end
	end

	-- Objetos ---------------------------------------------------------------------------
	local itemGrid = grid(panes.Items, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 1, -16))
	local itemLabels = {}
	for order, name in Config.ItemOrder do
		local item = Config.Items[name]
		local cell = Ui.cell(itemGrid, item.color)
		cell.Name = name
		cell.LayoutOrder = order
		Ui.gemIcon(cell, item.color)
		itemLabels[name] = Ui.cellLabel(cell, "x0")
		Ui.tip(cell, function()
			return `{item.name}\n<font color="{Ui.SOFT}">{item.description}</font>\n<font color="{Ui.SOFT}">Se usa en la pestaña Espadas.</font>`, item.color
		end)
	end

	-- Equipo ----------------------------------------------------------------------------
	local gearPane = panes.Gear

	-- Ranuras a la izquierda.
	local slots = {}
	for slot = 1, Config.GearSlots do
		local cell = Ui.cell(gearPane, Ui.COLORS.gray)
		cell.Name = "Slot" .. slot
		cell.Position = UDim2.fromOffset(16, 16 + (slot - 1) * 128)
		cell.Size = UDim2.fromOffset(112, 112)
		slots[slot] = { cell = cell, stroke = cell:FindFirstChildOfClass("UIStroke"), label = Ui.cellLabel(cell, "Ranura " .. slot), index = nil }
		Ui.tip(cell, function()
			local index = slots[slot].index
			if index then
				return artifactTip(index)
			end
			return `Ranura {slot}\n<font color="{Ui.SOFT}">Vacía: pulsa un accesorio para equiparlo.</font>`, Ui.COLORS.gray
		end)
		cell.Activated:Connect(function()
			if slots[slot].index then
				Remotes.ToggleGear:FireServer(slots[slot].index)
			end
		end)
	end

	-- El personaje en el centro.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Character"
	viewport.Position = UDim2.fromOffset(140, 8)
	viewport.Size = UDim2.new(0, 250, 1, -16)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.Parent = gearPane

	local function renderCharacter(viewport: ViewportFrame)
		viewport:ClearAllChildren()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		character.Archivable = true
		local ok, clone = pcall(character.Clone, character)
		if not ok or not clone then
			return
		end
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end
		local world = Instance.new("WorldModel")
		clone.Parent = world
		world.Parent = viewport
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		local focus = root.Position + Vector3.new(0, 0.3, 0)
		camera.CFrame = CFrame.lookAt(focus + root.CFrame.LookVector * 11 + Vector3.new(0, 1, 0), focus)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end
	local function showCharacter()
		renderCharacter(viewport)
	end
	onShow.Gear = showCharacter

	-- Armadura (ver ArmorPane) ------------------------------------------------------------
	local armorPane = ArmorPane.build(panes.Armor, { grid = grid, character = renderCharacter, popIn = popIn })
	onShow.Armor = armorPane.show

	local gearHint = Ui.label(gearPane, 18)
	gearHint.Position = UDim2.fromOffset(400, 8)
	gearHint.Size = UDim2.new(1, -412, 0, 34)
	gearHint.TextXAlignment = Enum.TextXAlignment.Left
	gearHint.TextWrapped = true

	local gearGrid = grid(gearPane, UDim2.fromOffset(398, 46), UDim2.new(1, -406, 1, -54))
	local gearCells = {}
	for index, artifact in Config.Artifacts do
		local cell = Ui.cell(gearGrid, Rarity.tier(artifact.rarity).color)
		cell.Name = "Artifact" .. index
		cell.LayoutOrder = -index
		Ui.orbIcon(cell, artifact.color)
		Ui.cellLabel(cell, `{Config.StatNames[artifact.stat]} x{Format.multiplier(artifact.mult)}`)
		Ui.tip(cell, function()
			return artifactTip(index)
		end)
		cell.Activated:Connect(function()
			Remotes.ToggleGear:FireServer(index)
		end)
		gearCells[index] = cell
	end

	-- Refresco --------------------------------------------------------------------------
	local function refresh()
		-- Con la ventana cerrada no se toca nada: se pone al día al abrirla.
		if not window.Visible then
			return
		end
		local equippedId = player:GetAttribute("Equipped") or 1
		local copies = Stats.swords(player)

		count.Text = `{#copies}/{Config.MaxSwords}`
		local key = `{player:GetAttribute("Swords")}|{equippedId}`
		if key ~= swordsKey then
			swordsKey = key
			syncSwords(copies, equippedId)
		end
		refreshSelection(copies, equippedId)
		for name, text in itemLabels do
			text.Text = "x" .. Format.short(player:GetAttribute("Item_" .. name) or 0)
		end

		local artifacts = Stats.list(player, "Artifacts")
		local worn = Stats.list(player, "Gear")
		gearHint.Text = if #artifacts == 0
			then "Aún no tienes accesorios: caen al romper objetos."
			else `Equipados {#worn}/{Config.GearSlots}. Pulsa para equipar o quitar.`
		for index, cell in gearCells do
			cell.Visible = table.find(artifacts, index) ~= nil
			cell.Select.Visible = table.find(worn, index) ~= nil
		end
		for slot, entry in slots do
			local index = worn[slot]
			local artifact = index and Config.Artifacts[index]
			if entry.index ~= index then
				entry.index = index
				local icon = entry.cell:FindFirstChild("Icon")
				if icon then
					icon:Destroy()
				end
				if artifact then
					Ui.orbIcon(entry.cell, artifact.color)
				end
			end
			local color = if artifact then Rarity.tier(artifact.rarity).color else Ui.COLORS.gray
			entry.cell.BackgroundColor3 = color
			entry.stroke.Color = color
			entry.label.Text = if artifact then artifact.name else "Ranura " .. slot
		end
		armorPane.refresh()
	end

	player.AttributeChanged:Connect(refresh)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		refresh()
		if window.Visible and current == "Gear" then
			showCharacter()
		elseif window.Visible and current == "Armor" then
			armorPane.show()
		elseif window.Visible and current == "Swords" then
			onShow.Swords()
		end
	end)
	show("Swords")
	refresh()
end

Backpack.swordTip = swordTip

return Backpack
