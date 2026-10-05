-- Interfaz fija: barra de transporte arriba (Hub, Casa, Tiendas), monedas y gemas abajo a la
-- izquierda, cuadro de estadísticas abajo a la derecha (daño, suertes y el nivel de cada mejora,
-- como el resumen de la pantalla de Mejoras), menú a la izquierda y avisos.
-- La mochila está en Backpack, las mejoras en SkillTree, el gacha en GachaRoll y el estilo en Ui.
-- El transporte lo hace el servidor (Teleport); aquí solo se pide y se pone un destello.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Ui = require(script.Parent.Ui)

local Hud = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local MARGIN = 14

-- Contador grande (monedas o gemas) con su icono, abajo a la izquierda.
local function counter(gui: Instance, name: string, row: number, color: Color3, icon: (Instance, Color3) -> ()): TextLabel
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0, 1)
	box.Position = UDim2.new(0, MARGIN, 1, -MARGIN - (row - 1) * 64)
	box.Size = UDim2.fromOffset(270, 56)
	box.BackgroundColor3 = color
	box.Parent = gui
	Ui.round(box, 14)
	Ui.bevel(box)
	Ui.stroke(box, BLACK, 3)
	local iconBox = Instance.new("Frame")
	iconBox.Position = UDim2.fromOffset(6, 4)
	iconBox.Size = UDim2.fromOffset(48, 48)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = box
	icon(iconBox, color)
	local text = Ui.label(box, 28)
	text.Name = "Amount"
	text.Position = UDim2.fromOffset(58, 0)
	text.Size = UDim2.new(1, -66, 1, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	Ui.sparkle(box, 5)
	-- Latido del cuadro cada vez que cambia la cantidad, y el icono flota despacio.
	local pulse = Instance.new("UIScale")
	pulse.Parent = box
	local last = ""
	text:GetPropertyChangedSignal("Text"):Connect(function()
		if last ~= "" and last ~= text.Text then
			pulse.Scale = 1.1
			TweenService:Create(pulse, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		last = text.Text
	end)
	TweenService:Create(iconBox, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(6, 1) }):Play()
	return text
end

-- Casita hecha con marcos para el botón de Casa: tejado (cuadrado girado) y paredes con puerta.
local function houseIcon(parent: Instance, color: Color3)
	local roof = Instance.new("Frame")
	roof.AnchorPoint = Vector2.new(0.5, 0.5)
	roof.Position = UDim2.fromScale(0.5, 0.42)
	roof.Size = UDim2.fromScale(0.52, 0.52)
	roof.Rotation = 45
	roof.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
	roof.Parent = parent
	Ui.round(roof, 4)
	Ui.stroke(roof, BLACK, 2)
	local wall = Instance.new("Frame")
	wall.AnchorPoint = Vector2.new(0.5, 1)
	wall.Position = UDim2.fromScale(0.5, 0.92)
	wall.Size = UDim2.fromScale(0.6, 0.42)
	wall.BackgroundColor3 = WHITE
	wall.Parent = parent
	Ui.round(wall, 3)
	Ui.stroke(wall, BLACK, 2)
	local door = Instance.new("Frame")
	door.AnchorPoint = Vector2.new(0.5, 1)
	door.Position = UDim2.fromScale(0.5, 1)
	door.Size = UDim2.fromScale(0.3, 0.6)
	door.BackgroundColor3 = color
	door.BorderSizePixel = 0
	door.Parent = wall
end

function Hud.start()
	local gui = Ui.screen()

	-- Monedas y gemas, abajo a la izquierda.
	local coins = counter(gui, "Coins", 1, Ui.COLORS.coins, function(parent)
		Ui.orbIcon(parent, Color3.fromRGB(255, 220, 90))
	end)
	local gems = counter(gui, "Gems", 2, Ui.COLORS.purple, function(parent)
		Ui.gemIcon(parent, Color3.fromRGB(220, 160, 255))
	end)

	-- Transporte, arriba en el centro.
	local travel = Instance.new("Frame")
	travel.Name = "Travel"
	travel.AnchorPoint = Vector2.new(0.5, 0)
	travel.Position = UDim2.new(0.5, 0, 0, 10)
	travel.Size = UDim2.fromOffset(0, 62)
	travel.AutomaticSize = Enum.AutomaticSize.X
	travel.BackgroundTransparency = 1
	travel.Parent = gui
	local travelLayout = Instance.new("UIListLayout")
	travelLayout.FillDirection = Enum.FillDirection.Horizontal
	travelLayout.Padding = UDim.new(0, 12)
	travelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	travelLayout.Parent = travel

	-- Destello blanco al transportarse.
	local flash = Instance.new("Frame")
	flash.Name = "TravelFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 50
	flash.Parent = gui

	local destinations = {
		{ "hub", "Hub", Color3.fromRGB(255, 175, 40), function(parent)
			Ui.orbIcon(parent, Color3.fromRGB(255, 120, 60))
		end },
		{ "home", "Casa", Color3.fromRGB(50, 190, 240), houseIcon },
		{ "shops", "Tiendas", Color3.fromRGB(70, 200, 90), function(parent)
			Ui.boxIcon(parent, Color3.fromRGB(255, 210, 90))
		end },
	}
	for order, entry in destinations do
		local button = Ui.button(travel, "", entry[3])
		button.Name = "Travel_" .. entry[1]
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(if order == 2 then 200 else 186, 62)
		local iconBox = Instance.new("Frame")
		iconBox.Position = UDim2.fromOffset(10, 7)
		iconBox.Size = UDim2.fromOffset(48, 48)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = button
		entry[4](iconBox, entry[3])
		local label = Ui.label(button, 30)
		label.Position = UDim2.fromOffset(62, 0)
		label.Size = UDim2.new(1, -70, 1, 0)
		label.Text = entry[2]
		Ui.sparkle(button, 5)
		button.Activated:Connect(function()
			Remotes.Teleport:FireServer(entry[1])
			flash.BackgroundTransparency = 0.2
			TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		end)
	end

	-- Estadísticas, abajo a la derecha: daño y suertes, y el nivel de cada mejora.
	local statsBox = Instance.new("Frame")
	statsBox.Name = "Stats"
	statsBox.AnchorPoint = Vector2.new(1, 1)
	statsBox.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	statsBox.Size = UDim2.fromOffset(300, 0)
	statsBox.AutomaticSize = Enum.AutomaticSize.Y
	statsBox.BackgroundColor3 = WHITE
	statsBox.Parent = gui
	Ui.round(statsBox, 12)
	Ui.stroke(statsBox, BLACK, 3)
	Ui.gradient(statsBox, Color3.fromRGB(58, 48, 110), Color3.fromRGB(18, 18, 40), 90)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = statsBox
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsBox

	local function statsRow(order: number, height: number, size: number, dotColor: Color3?): TextLabel
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.Parent = statsBox
		local indent = 0
		if dotColor then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0, 0.5)
			dot.Position = UDim2.new(0, 3, 0.5, 0)
			dot.Size = UDim2.fromOffset(15, 15)
			dot.Rotation = 45
			dot.BackgroundColor3 = dotColor
			dot.BorderSizePixel = 0
			dot.Parent = row
			Ui.stroke(dot, BLACK, 2)
			indent = 28
		end
		local text = Ui.label(row, size)
		text.Position = UDim2.fromOffset(indent, 0)
		text.Size = UDim2.new(1, -indent, 1, 0)
		text.TextXAlignment = Enum.TextXAlignment.Left
		return text
	end
	local damageText = statsRow(1, 26, 20)
	local luckText = statsRow(2, 26, 20)
	local gachaText = statsRow(3, 26, 20)
	local upgradeRows = {}
	for index, name in Config.UpgradeOrder do
		upgradeRows[name] = statsRow(10 + index, 38, 15, Config.Upgrades[name].color)
	end

	-- Menú
	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.AnchorPoint = Vector2.new(0, 0.5)
	menu.Position = UDim2.new(0, 14, 0.5, 0)
	menu.Size = UDim2.fromOffset(140, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundTransparency = 1
	menu.Parent = gui
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.Padding = UDim.new(0, 12)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menu

	for order, entry in { { "Backpack", "Mochila", Ui.COLORS.blue }, { "Upgrades", "Mejoras", Ui.COLORS.green } } do
		local item = Ui.button(menu, entry[2], entry[3])
		item.Name = entry[1]
		item.LayoutOrder = order
		item.Size = UDim2.new(1, 0, 0, 60)
		item.TextSize = 24
		Ui.sparkle(item, 6)
		item.Activated:Connect(function()
			Ui.toggle(entry[1])
		end)
	end

	local function refresh()
		local amount = player:GetAttribute("Coins") or 0
		local gemAmount = player:GetAttribute("Gems") or 0

		coins.Text = Format.short(amount)
		gems.Text = Format.short(gemAmount)
		damageText.Text = `Daño <font color="#ff9a6a">{Format.multiplier(Stats.damage(player))}</font>`
		luckText.Text = `Suerte <font color="#7ee07a">x{Format.multiplier(Stats.luck(player))}</font>`
		gachaText.Text = `Suerte de gacha <font color="#c9a0ff">x{Format.multiplier(Stats.gachaLuck(player))}</font>`
		for name, text in upgradeRows do
			local upgrade = Config.Upgrades[name]
			local level = player:GetAttribute("Upgrade_" .. name) or 0
			local balance = if upgrade.currency == "gems" then gemAmount else amount
			local price = if level >= upgrade.maxLevel
				then `<font color="#6fe07a">al máximo</font>`
				else `<font color="{if balance >= Upgrades.cost(name, level) then "#ffd24a" else Ui.SOFT}">sig. {Format.short(Upgrades.cost(name, level))}</font>`
			text.Text = `{upgrade.short} <font color="{Ui.SOFT}">{level}/{upgrade.maxLevel}</font> · {Upgrades.display(name, level)}\n{price}`
		end
	end

	player.AttributeChanged:Connect(refresh)
	refresh()

	Remotes.Notice.OnClientEvent:Connect(Ui.toast)

	-- Avisos de cosas muy raras: al chat, o al aviso de pantalla si no hay chat.
	Remotes.Announce.OnClientEvent:Connect(function(text: string, color: Color3)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild("RBXGeneral")
		if channel then
			channel:DisplaySystemMessage(`<font color="#{color:ToHex()}"><b>{text}</b></font>`)
		else
			Ui.toast(text, color)
		end
	end)
end

return Hud
