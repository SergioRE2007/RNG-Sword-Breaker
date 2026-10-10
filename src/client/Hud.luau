-- Interfaz fija: barra de transporte arriba (Hub, Casa, Mazmorras), monedas y gemas abajo a la
-- izquierda, cuadro de estadísticas abajo a la derecha (daño, suertes y el nivel de cada mejora,
-- como el resumen de la pantalla de Mejoras), menú a la izquierda (Mochila, Renacer, Mejoras, Tienda y Trades) y avisos.
-- La mochila está en Backpack, las mejoras en SkillTree, el gacha en GachaRoll y el estilo en Ui.
-- El transporte lo hace el servidor (Teleport); aquí solo se pide y se pone un destello.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Ui = require(script.Parent.Ui)
local MenuTile = require(script.Parent.MenuTile)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local ForgeScene = require(script.Parent.ForgeScene)

local Hud = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local MARGIN = 14

-- Contador grande (monedas o gemas) con su icono, abajo a la izquierda.
local function counter(gui: Instance, name: string, row: number, color: Color3, icon: (Instance, Color3) -> ()): (TextLabel, (number) -> ())
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0, 1)
	box.Position = UDim2.new(0, MARGIN, 1, -MARGIN - (row - 1) * 64)
	box.Size = UDim2.fromOffset(270, 56)
	box.Parent = gui
	Ui.pill(box, color)
	-- El logo, tan alto como la barra y dentro de ella (un poco más arriba que el centro, por el labio de abajo).
	local iconBox = Instance.new("Frame")
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, 2, 0.5, -2)
	iconBox.Size = UDim2.fromOffset(58, 58)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = box
	icon(iconBox, color)
	local text = Ui.label(box, 28)
	text.Name = "Amount"
	text.Position = UDim2.fromOffset(60, 0)
	text.Size = UDim2.new(1, -68, 1, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	Ui.sparkle(box, 5)

	-- Al cambiar la cantidad el cuadro late, el número sube (o baja) rodando hasta el valor nuevo y
	-- sale un "+N" (o "-N") flotando. Las ganancias seguidas se juntan en un solo número cada 0,4 s.
	local pulse = Instance.new("UIScale")
	pulse.Parent = box
	local shown: number? = nil
	local target: number? = nil
	local pending = 0
	local lastFloat = 0
	local function show(value: number)
		text.Text = Format.short(if math.abs(value) < 2 ^ 52 then math.floor(value + 0.5) else value)
	end
	local function floatText(delta: number)
		local float = Ui.label(box, 26)
		float.AnchorPoint = Vector2.new(0, 0.5)
		float.Position = UDim2.new(1, 10, 0.5, 0)
		float.Size = UDim2.fromOffset(150, 30)
		float.TextXAlignment = Enum.TextXAlignment.Left
		float.Text = (if delta > 0 then "+" else "-") .. Format.short(math.abs(delta))
		float.TextColor3 = if delta > 0 then Color3.fromRGB(130, 255, 140) else Ui.COLORS.red
		float.ZIndex = 20
		local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(float, rise, { Position = UDim2.new(1, 10, 0.5, if delta > 0 then -38 else 38), TextTransparency = 1 }):Play()
		local stroke = float:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, rise, { Transparency = 1 }):Play()
		end
		task.delay(1, function()
			float:Destroy()
		end)
	end
	local function setAmount(value: number)
		if Performance.get() then
			-- Modo rendimiento: el número cambia de golpe, sin rodar, sin latido y sin "+N".
			shown, target = value, value
			show(value)
			return
		end
		if target == nil or value == target then
			if target == nil then
				shown, target = value, value
				show(value)
			end
			return
		end
		local delta = value - target
		target = value
		-- Con números infinitos (modo de pruebas) o que se salen de la escala, sin animación.
		if delta ~= delta or math.abs(delta) == math.huge or math.abs(value) == math.huge then
			shown = value
			show(value)
			return
		end
		pending += delta
		pulse.Scale = 1.1
		TweenService:Create(pulse, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	RunService.RenderStepped:Connect(function(dt)
		local goal, current = target, shown
		if goal and current and current ~= goal then
			current += (goal - current) * math.min(1, dt * 9)
			if math.abs(goal - current) <= math.max(0.5, math.abs(goal) * 1e-4) then
				current = goal
			end
			shown = current
			show(current)
		end
		if pending ~= 0 and os.clock() - lastFloat > 0.4 then
			floatText(pending)
			pending = 0
			lastFloat = os.clock()
		end
	end)
	return text, setAmount
end

function Hud.start()
	local gui = Ui.hud()

	-- La casilla de WeaponSlot sustituye la barra de objetos de Roblox y maneja su tecla 1.
	-- SetCoreGuiEnabled puede fallar si el sistema aún no está listo, así que se reintenta.
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
				break
			end
			task.wait(0.5)
		end
	end)

	-- Monedas y gemas, abajo a la izquierda.
	local _, setCoins = counter(gui, "Coins", 1, Ui.COLORS.coins, function(parent)
		Ui.image(parent, "monedas")
	end)
	local _, setGems = counter(gui, "Gems", 2, Ui.COLORS.purple, function(parent)
		Ui.image(parent, "gemas")
	end)

	-- Transporte, arriba en el centro.
	local travel = Instance.new("Frame")
	travel.Name = "Travel"
	travel.AnchorPoint = Vector2.new(0.5, 0)
	travel.Position = UDim2.new(0.5, 0, 0, 10)
	travel.Size = UDim2.fromOffset(0, 76)
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
	Remotes.Teleported.OnClientEvent:Connect(function()
		Sfx.play("teleport")
		ForgeScene.exit()
		Ui.closeAll()
		flash.BackgroundTransparency = 0.2
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	end)

	local destinations = {
		{ "hub", "Hub", Color3.fromRGB(255, 175, 40), "hub" },
		{ "home", "Casa", Color3.fromRGB(50, 190, 240), "casa" },
		{ "dungeon", "Mazmorras", Ui.COLORS.purple, "mazmorras" },
	}
	for order, entry in destinations do
		-- Botón alargado de client/MenuTile, los tres igual de anchos. La barra mide 76 de alto: lo que va debajo
		-- (paneles de mazmorra, forja, gacha) empieza en Y = 90.
		local button = MenuTile.new(travel, entry[2], entry[3], entry[4], true)
		button.Name = "Travel_" .. entry[1]
		button.LayoutOrder = order
		Ui.sparkle(button, 5)
		button.Activated:Connect(function()
			Remotes.Teleport:FireServer(entry[1])
		end)
	end

	-- Estadísticas, abajo a la derecha: daño y suertes, y el nivel de cada mejora.
	-- Va dentro de un "dock" pegado abajo a la derecha, escondido salvo en la pantalla de Mejoras.
	local dock = Instance.new("Frame")
	dock.Name = "StatsDock"
	dock.AnchorPoint = Vector2.new(1, 1)
	dock.Position = UDim2.new(1, -MARGIN, 1, -86)
	dock.Size = UDim2.new(0, 300, 0.65, -86)
	dock.BackgroundTransparency = 1
	dock.Parent = gui

	local statsBox = Instance.new("ScrollingFrame")
	statsBox.Name = "Stats"
	statsBox.Size = UDim2.fromScale(1, 1)
	statsBox.CanvasSize = UDim2.new()
	statsBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
	statsBox.ScrollBarThickness = 6
	statsBox.BorderSizePixel = 0
	statsBox.BackgroundColor3 = WHITE
	statsBox.Parent = dock

	-- Solo se ve en la pantalla de Mejoras (la enseña y la esconde SkillTree), en este mismo sitio.
	dock.Visible = false
	Ui.round(statsBox, 12)
	Ui.stroke(statsBox, BLACK, 3)
	Ui.panel(statsBox, Color3.fromRGB(46, 40, 96))
	-- Las filas van en un marco de dentro: el relleno y la lista no deben mover el brillo ni el canto del panel.
	local statsContent = Instance.new("Frame")
	statsContent.Name = "Content"
	statsContent.Size = UDim2.new(1, -8, 0, 0)
	statsContent.AutomaticSize = Enum.AutomaticSize.Y
	statsContent.BackgroundTransparency = 1
	statsContent.Parent = statsBox
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = statsContent
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsContent

	local function statsRow(order: number, height: number, size: number, dotColor: Color3?): TextLabel
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.Parent = statsContent
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
	-- Algo por encima del centro: en un móvil apaisado (HUD al mínimo) el menú llegaba a tocar las gemas.
	menu.Position = UDim2.new(0, 14, 0.47, 0)
	local menuGap = 12 -- el borde negro va por fuera del botón: con menos se pisan al crecer
	menu.Size = UDim2.fromOffset(MenuTile.SIZE * 2 + menuGap, 0) -- dos botones por fila
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundTransparency = 1
	menu.Parent = gui
	local menuLayout = Instance.new("UIGridLayout")
	menuLayout.CellSize = UDim2.fromOffset(MenuTile.SIZE, MenuTile.SIZE)
	menuLayout.CellPadding = UDim2.fromOffset(menuGap, menuGap)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menu

	-- Botones cuadrados con el logo grande y el nombre abajo (client/MenuTile): ventana, nombre, color y logo.
	local menuItems = {
		{ "Backpack", "Mochila", Ui.COLORS.blue, "mochila" },
		{ "Rebirth", "Renacer", Ui.COLORS.orange, "rebirth" },
		{ "Upgrades", "Mejoras", Ui.COLORS.green, "mejora" },
		{ "PassShop", "Tienda", Color3.fromRGB(40, 185, 110), "tienda_robux" },
		-- Abre la lista de Comercio (antes iba arriba, con los botones de transporte: pedido por el usuario).
		{ "TradeList", "Trades", Color3.fromRGB(40, 170, 200), "trade" },
		-- Índice de armas (client/Index). Logo provisional: el usuario pondrá el suyo.
		{ "Index", "Índice", Ui.COLORS.purple, "espada" },
	}
	for order, entry in menuItems do
		local item = MenuTile.new(menu, entry[2], entry[3], entry[4])
		item.Name = entry[1]
		item.LayoutOrder = order
		Ui.sparkle(item, 6)
		item.Activated:Connect(function()
			Ui.toggle(entry[1])
		end)
	end

	local function refresh()
		local amount = player:GetAttribute("Coins") or 0
		local gemAmount = player:GetAttribute("Gems") or 0

		setCoins(amount)
		setGems(gemAmount)
		damageText.Text = `Daño <font color="#ff9a6a">{Format.multiplier(Stats.damage(player))}</font>  ·  Vida <font color="#ff6e6e">{Format.short(Stats.maxHealth(player))}</font>`
		luckText.Text = `Suerte de destructibles <font color="#7ee07a">x{Format.multiplier(Stats.luck(player) * Stats.spawnLuck(player))}</font>`
		gachaText.Text = `Suerte de armas <font color="#c9a0ff">x{Format.multiplier(Stats.gachaLuck(player))}</font>`
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
