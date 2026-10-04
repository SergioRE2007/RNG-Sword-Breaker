-- Árbol de mejoras: pantalla completa con nodos hexagonales. Cada mejora de Config.Upgrades
-- es una rama que sale del nodo de inicio y cada nivel es un nodo; se compran en orden.
-- Solo se dibujan los nodos comprados y los siguientes, así que el árbol crece al avanzar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Ui = require(script.Parent.Ui)

local SkillTree = {}

local player = Players.LocalPlayer

local HEX = 84 -- ancho del hexágono
local STEP = 98 -- distancia entre centros de nodos vecinos
local AHEAD = 3 -- nodos sin comprar que se ven por delante
local COLOR_BORDER = Color3.fromRGB(14, 20, 46)
local COLOR_NEXT = Color3.fromRGB(255, 205, 50)
local COLOR_EXPENSIVE = Color3.fromRGB(125, 130, 150)
local COLOR_LOCKED = Color3.fromRGB(62, 65, 82)

-- Vecinos en la rejilla de hexágonos.
local E = Vector2.new(STEP, 0)
local W = Vector2.new(-STEP, 0)
local NE = Vector2.new(STEP / 2, -STEP * 0.866)
local NW = Vector2.new(-STEP / 2, -STEP * 0.866)
local SE = Vector2.new(STEP / 2, STEP * 0.866)
local SW = Vector2.new(-STEP / 2, STEP * 0.866)

-- Cada rama avanza alternando dos direcciones, en escalera, hacia una esquina distinta.
local BRANCHES = { { NW, W }, { NE, E }, { SE, E }, { SW, W } }

local ICONS = { box = Ui.boxIcon, orb = Ui.orbIcon, sword = Ui.swordIcon, gem = Ui.gemIcon }

local ROMAN = { { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local function roman(n: number): string
	local text = ""
	for _, pair in ROMAN do
		while n >= pair[1] do
			text ..= pair[2]
			n -= pair[1]
		end
	end
	return text
end

local function position(branch: number, level: number): Vector2
	local steps = BRANCHES[branch]
	local point = Vector2.zero
	for index = 1, level do
		point += steps[(index - 1) % 2 + 1]
	end
	return point
end

local function setColor(pieces, color: Color3)
	for _, frame in pieces do
		frame.BackgroundColor3 = color
	end
end

-- Nodo hexagonal con icono y texto. Devuelve { pieces, label, button }.
local function buildNode(canvas: Instance, name: string, point: Vector2, icon: string?, iconColor: Color3)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(point.X, point.Y)
	holder.Size = UDim2.fromOffset(HEX + 12, HEX + 24)
	holder.BackgroundTransparency = 1
	holder.Parent = canvas

	Ui.hex(holder, HEX + 12, COLOR_BORDER)
	local _, pieces = Ui.hex(holder, HEX, COLOR_LOCKED)

	if icon then
		local iconFrame = Instance.new("Frame")
		iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		iconFrame.Position = UDim2.fromScale(0.5, 0.36)
		iconFrame.Size = UDim2.fromOffset(46, 46)
		iconFrame.BackgroundTransparency = 1
		iconFrame.Parent = holder
		ICONS[icon](iconFrame, iconColor)
	end

	local label = Ui.label(holder, 14)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, if icon then 0.7 else 0.5)
	label.Size = UDim2.fromOffset(HEX - 6, 34)
	label.TextWrapped = true
	label.RichText = false

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromOffset(HEX - 8, HEX - 8)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 5
	button.Parent = holder

	return { pieces = pieces, label = label, button = button }
end

function SkillTree.start()
	local overlay = Instance.new("TextButton")
	overlay.Name = "Upgrades"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1) -- el color lo pone el degradado
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.AutoButtonColor = false
	overlay.Text = ""
	overlay.ClipsDescendants = true
	overlay.Visible = false
	overlay.ZIndex = -1 -- por debajo de contadores y menú
	overlay.Parent = Ui.screen()
	Ui.register("Upgrades", overlay)
	-- Fondo con degradado y rayas suaves (que no se vea plano), por debajo de contadores y menú.
	Ui.gradient(overlay, Color3.fromRGB(40, 60, 130), Color3.fromRGB(14, 10, 40), 90)
	local stripes
	local function drawStripes()
		if stripes then
			stripes:Destroy()
		end
		stripes = Ui.stripes(overlay, workspace.CurrentCamera.ViewportSize, 34, 0.94, -1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(drawStripes)
	drawStripes()

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(0, 0)
	canvas.BackgroundTransparency = 1
	canvas.Parent = overlay
	-- Zoom: la escala del lienzo (rueda del ratón, pellizco o los botones + y -).
	local zoom = Instance.new("UIScale")
	zoom.Scale = 0.8
	zoom.Parent = canvas

	local hint = Ui.label(overlay, 18)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 106)
	hint.Size = UDim2.fromOffset(720, 26)
	hint.Text = "Árbol de mejoras · arrastra para moverte · rueda o + y - para acercar y alejar"

	local close = Ui.button(overlay, "Cerrar", Ui.COLORS.red)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -28)
	close.Size = UDim2.fromOffset(260, 66)
	close.TextSize = 34
	close.ZIndex = 10
	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	-- Arrastrar el fondo mueve el árbol.
	local offset = Vector2.zero
	local MIN_ZOOM, MAX_ZOOM = 0.3, 1.6

	-- Cambia el zoom dejando quieto el punto `focus` de la pantalla (el ratón o el centro).
	local function setZoom(target: number, focus: Vector2?)
		local old = zoom.Scale
		local new = math.clamp(target, MIN_ZOOM, MAX_ZOOM)
		local center = overlay.AbsolutePosition + overlay.AbsoluteSize / 2
		local point = (focus or center) - center
		offset = point - (point - offset) * (new / old)
		zoom.Scale = new
		canvas.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	end

	for index, entry in { { "ZoomOut", "-", 1 / 1.25, -150 }, { "ZoomIn", "+", 1.25, 150 } } do
		local button = Ui.button(overlay, entry[2], Ui.COLORS.blue)
		button.Name = entry[1]
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, entry[4] + (if index == 1 then -40 else 40), 1, -28)
		button.Size = UDim2.fromOffset(66, 66)
		button.TextSize = 40
		button.ZIndex = 10
		button.Activated:Connect(function()
			setZoom(zoom.Scale * entry[3])
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		if overlay.Visible and input.UserInputType == Enum.UserInputType.MouseWheel then
			setZoom(zoom.Scale * 1.12 ^ input.Position.Z, Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	local pinchStart = 1
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if not overlay.Visible then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = zoom.Scale
		end
		setZoom(pinchStart * scale)
	end)
	local dragging = false
	local last = Vector3.zero
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			last = input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - last
			last = input.Position
			offset += Vector2.new(delta.X, delta.Y)
			canvas.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local start = buildNode(canvas, "Start", Vector2.zero, nil, Color3.new())
	setColor(start.pieces, Ui.COLORS.green)
	start.label.Text = "Inicio"
	start.label.TextSize = 20

	local nodes = {} -- [mejora] = { [nivel] = nodo }

	local function addNode(branch: number, name: string, level: number)
		local upgrade = Config.Upgrades[name]
		local node = buildNode(canvas, `{name}{level}`, position(branch, level), upgrade.icon, upgrade.color)
		node.label.Text = `{upgrade.short} {roman(level)}`
		nodes[name][level] = node

		Ui.tip(node.button, function()
			local owned = (player:GetAttribute("Upgrade_" .. name) or 0) >= level
			local currency = if upgrade.currency == "gems" then "gemas" else "monedas"
			local state = if owned
				then `<font color="#6fe07a">Comprada</font>`
				else `Precio: {Format.short(Upgrades.cost(name, level - 1))} {currency}`
			return `{upgrade.name} {roman(level)}\n<font color="{Ui.SOFT}">{Upgrades.display(name, level - 1)} → {Upgrades.display(name, level)}</font>\n{state}`,
				upgrade.color
		end)
		node.button.Activated:Connect(function()
			if (player:GetAttribute("Upgrade_" .. name) or 0) == level - 1 then
				Remotes.BuyUpgrade:FireServer(name)
			end
		end)
	end

	local function refresh()
		local coins = player:GetAttribute("Coins") or 0
		local gems = player:GetAttribute("Gems") or 0
		for branch, name in Config.UpgradeOrder do
			local upgrade = Config.Upgrades[name]
			local level = player:GetAttribute("Upgrade_" .. name) or 0
			nodes[name] = nodes[name] or {}
			for index = 1, math.min(level + AHEAD, upgrade.maxLevel) do
				if not nodes[name][index] then
					addNode(branch, name, index)
				end
				local node = nodes[name][index]
				if index <= level then
					setColor(node.pieces, upgrade.color)
				elseif index == level + 1 then
					local balance = if upgrade.currency == "gems" then gems else coins
					setColor(node.pieces, if balance >= Upgrades.cost(name, level) then COLOR_NEXT else COLOR_EXPENSIVE)
				else
					setColor(node.pieces, COLOR_LOCKED)
				end
			end
		end
	end

	player.AttributeChanged:Connect(refresh)
	refresh()
end

return SkillTree
