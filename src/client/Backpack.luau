-- Mochila: ventana con pestañas (Espadas, Objetos, Equipo). Todo son casillas cuadradas con
-- el borde del color de su rareza; al pasar el ratón sale un cartel con los detalles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)

local Backpack = {}

local player = Players.LocalPlayer
local CELL = 84

local function hex(color: Color3): string
	return "#" .. color:ToHex()
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
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
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

local function swordTip(copy): (string, Color3)
	local sword = Config.Swords[copy.sword]
	local trait = Config.Traits[copy.trait]
	local tier = Rarity.tier(sword.rarity)
	local lines = { sword.name, `<font color="{hex(tier.color)}">{tier.name}</font> · {Config.WeaponKinds[sword.kind or "sword"].name}` }
	local grade = Config.Grades[copy.grade]
	if trait then
		table.insert(lines, `<font color="{hex(trait.color)}">Rasgo: {trait.name}</font> ({Modifiers.effect(trait)})`)
	end
	if grade then
		table.insert(lines, `<font color="{hex(grade.color)}">Grado: {grade.name}</font> ({Modifiers.effect(grade)})`)
	end
	table.insert(lines, `Daño {Format.multiplier(Stats.swordDamage(copy))}`)
	table.insert(lines, `<font color="{Ui.SOFT}">{if sword.rarity then "1 entre " .. Format.short(sword.rarity) else "Espada inicial"}</font>`)
	return table.concat(lines, "\n"), tier.color
end

local function artifactTip(index: number): (string, Color3)
	local artifact = Config.Artifacts[index]
	local tier = Rarity.tier(artifact.rarity)
	return `{artifact.name}\n<font color="{hex(tier.color)}">{tier.name}</font>\n{Config.StatNames[artifact.stat]} x{Format.multiplier(artifact.mult)}\n<font color="{Ui.SOFT}">1 entre {Format.short(artifact.rarity)}</font>`,
		tier.color
end

function Backpack.start()
	local window, body = Ui.window("Backpack", "Mochila", Vector2.new(740, 500))

	-- Pestañas, pegadas al lado izquierdo de la ventana.
	local panes = {}
	local tabs = {}
	local current = "Swords"
	local onShow = {}
	local function show(name: string)
		current = name
		for key, frame in panes do
			frame.Visible = key == name
			tabs[key].stroke.Color = if key == name then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
		if onShow[name] then
			onShow[name]()
		end
	end
	for order, entry in { { "Swords", "Espadas", Ui.COLORS.red }, { "Items", "Objetos", Ui.COLORS.blue }, { "Gear", "Equipo", Ui.COLORS.purple } } do
		local name = entry[1]
		panes[name] = pane(body, name)
		local tab = Ui.button(window, entry[2], entry[3])
		tab.Name = "Tab" .. name
		tab.Position = UDim2.fromOffset(-108, 66 + (order - 1) * 78)
		tab.Size = UDim2.fromOffset(96, 66)
		tab.TextSize = 18
		tabs[name] = { button = tab, stroke = tab:FindFirstChildOfClass("UIStroke") }
		tab.Activated:Connect(function()
			show(name)
		end)
	end

	-- Espadas ---------------------------------------------------------------------------
	local swordsPane = panes.Swords

	local autoText = Ui.label(swordsPane, 16)
	autoText.Position = UDim2.fromOffset(12, 8)
	autoText.Size = UDim2.fromOffset(330, 34)
	autoText.TextXAlignment = Enum.TextXAlignment.Left
	autoText.Text = "Vender solas las menos raras que 1 entre:"

	local autoBox = Instance.new("TextBox")
	autoBox.Name = "AutoSell"
	autoBox.Position = UDim2.fromOffset(346, 8)
	autoBox.Size = UDim2.fromOffset(130, 34)
	autoBox.BackgroundColor3 = Ui.COLORS.dark
	autoBox.TextColor3 = Color3.new(1, 1, 1)
	autoBox.PlaceholderColor3 = Color3.fromRGB(140, 145, 165)
	autoBox.PlaceholderText = "no vender"
	autoBox.Font = Ui.FONT
	autoBox.TextSize = 17
	autoBox.ClearTextOnFocus = false
	autoBox.Parent = swordsPane
	Ui.round(autoBox, 8)
	Ui.stroke(autoBox, Color3.new(0, 0, 0), 2)
	autoBox.FocusLost:Connect(function()
		-- Vacío = no vender. Admite "1000", "1.5K", "2M"...
		local value = if autoBox.Text == "" then 0 else Format.parse(autoBox.Text)
		if value then
			Remotes.SetAutoSell:FireServer(value)
		end
		local shown = value or player:GetAttribute("AutoSell") or 0
		autoBox.Text = if shown > 0 then Format.short(shown) else ""
	end)

	local count = Ui.label(swordsPane, 18)
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -12, 0, 8)
	count.Size = UDim2.fromOffset(110, 34)
	count.BackgroundTransparency = 0
	count.BackgroundColor3 = Ui.COLORS.blue
	Ui.round(count, 8)
	Ui.bevel(count)
	Ui.stroke(count, Color3.new(0, 0, 0), 2)

	local swordGrid = grid(swordsPane, UDim2.fromOffset(8, 50), UDim2.new(1, -16, 1, -118))

	-- Barra de abajo: detalles de la espada elegida y sus acciones.
	local detail = Ui.label(swordsPane, 16)
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(0, 1)
	detail.Position = UDim2.new(0, 12, 1, -8)
	detail.Size = UDim2.fromOffset(210, 52)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextWrapped = true

	local function action(name: string, text: string, color: Color3, right: number, width: number): TextButton
		local item = Ui.button(swordsPane, text, color)
		item.Name = name
		item.AnchorPoint = Vector2.new(1, 1)
		item.Position = UDim2.new(1, -right, 1, -8)
		item.Size = UDim2.fromOffset(width, 52)
		return item
	end
	local bestButton = action("Best", "Equipar mejor", Ui.COLORS.green, 12, 140)
	local sellButton = action("Sell", `Vender\n+{Config.Gacha.SellValue} gemas`, Ui.COLORS.red, 160, 100)
	local equipButton = action("Equip", "Equipar", Ui.COLORS.blue, 268, 100)
	sellButton.TextSize = 14

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

	local function rebuildSwords(copies, equippedId: number)
		for _, cell in swordCells do
			cell:Destroy()
		end
		table.clear(swordCells)
		for _, copy in copies do
			local sword = Config.Swords[copy.sword]
			local trait = Config.Traits[copy.trait]
			local cell = Ui.cell(swordGrid, Rarity.tier(sword.rarity).color)
			cell.Name = "Sword" .. copy.id
			-- Las mejores primero: por daño del arma y, a igualdad, por rasgo.
			cell.LayoutOrder = -(damageRank[copy.sword] * 1000 + copy.trait)
			Ui.swordIcon(cell, sword.color)
			Ui.cellLabel(cell, Format.multiplier(Stats.swordDamage(copy)))
			if copy.id == equippedId then
				Ui.cellTag(cell, "E", Ui.COLORS.green)
			end
			if trait then
				-- Rombo del color del rasgo en la esquina.
				local mark = Instance.new("Frame")
				mark.Name = "Trait"
				mark.AnchorPoint = Vector2.new(1, 0)
				mark.Position = UDim2.new(1, -7, 0, 7)
				mark.Size = UDim2.fromOffset(16, 16)
				mark.Rotation = 45
				mark.BackgroundColor3 = trait.color
				mark.BorderSizePixel = 0
				mark.ZIndex = 3
				mark.Parent = cell
				Ui.stroke(mark, Color3.new(0, 0, 0), 2)
			end
			Ui.tip(cell, function()
				return swordTip(copy)
			end)
			cell.Activated:Connect(function()
				selected = copy.id
				refreshSelection(Stats.swords(player), player:GetAttribute("Equipped") or 1)
			end)
			swordCells[copy.id] = cell
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
			return `Ranura {slot}\n<font color="{Ui.SOFT}">Vacía: pulsa un artefacto para equiparlo.</font>`, Ui.COLORS.gray
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

	local function showCharacter()
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
	onShow.Gear = showCharacter

	local gearHint = Ui.label(gearPane, 15)
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
		local equippedId = player:GetAttribute("Equipped") or 1
		local copies = Stats.swords(player)

		count.Text = `{#copies}/{Config.MaxSwords}`
		local key = `{player:GetAttribute("Swords")}|{equippedId}`
		if key ~= swordsKey then
			swordsKey = key
			rebuildSwords(copies, equippedId)
		end
		refreshSelection(copies, equippedId)
		if not autoBox:IsFocused() then
			local autoSell = player:GetAttribute("AutoSell") or 0
			autoBox.Text = if autoSell > 0 then Format.short(autoSell) else ""
		end

		for name, text in itemLabels do
			text.Text = "x" .. Format.short(player:GetAttribute("Item_" .. name) or 0)
		end

		local artifacts = Stats.list(player, "Artifacts")
		local worn = Stats.list(player, "Gear")
		gearHint.Text = if #artifacts == 0
			then "Aún no tienes artefactos: caen al romper objetos."
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
	end

	player.AttributeChanged:Connect(refresh)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible and current == "Gear" then
			showCharacter()
		end
	end)
	show("Swords")
	refresh()
end

return Backpack
