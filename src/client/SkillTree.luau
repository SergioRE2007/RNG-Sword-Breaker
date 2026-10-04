-- Árbol de mejoras: pantalla completa con el espacio de fondo y las mejoras como una galaxia de hexágonos.
-- Cada mejora de Config.Upgrades es un brazo en espiral que sale del nodo de inicio y cada nivel es un nodo,
-- unidos por líneas como una constelación; se compran en orden. Se arrastra para moverse y se puede acercar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Ui = require(script.Parent.Ui)

local SkillTree = {}

local player = Players.LocalPlayer

local HEX = 84 -- ancho del hexágono
local BIG = 1.22 -- los nodos de cada 5 niveles y el último de cada brazo son más grandes
local AHEAD = 3 -- nodos sin comprar que se ven enteros por delante; los demás son estrellas pequeñas
local FAR_SCALE = 0.5

-- Espiral: cada brazo se aleja PITCH por vuelta, con SPACING entre un nodo y el siguiente.
local START_RADIUS = 175
local PITCH = 560
local SPACING = 120
local JITTER = 22 -- desorden de los nodos, para que parezca una constelación y no una regla

local ZOOM_MIN, ZOOM_MAX, ZOOM_START = 0.25, 1.6, 0.62

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local COLOR_BORDER = Color3.fromRGB(10, 12, 34)
local COLOR_NEXT = Color3.fromRGB(255, 205, 50)
local COLOR_LOCKED = Color3.fromRGB(48, 52, 84)
local COLOR_FAR = Color3.fromRGB(120, 135, 200)
local COLOR_LINE = Color3.fromRGB(80, 95, 160)

-- Capas (ZIndex): el fondo, las líneas y los nodos van por debajo de los contadores y el menú del juego (1);
-- los botones y carteles de esta pantalla, por encima.
local Z_BACK = -5
local Z_LINE = -4
local Z_NODE = -3
local Z_FRONT = 10

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

-- Centro de cada nodo de un brazo.
local function layout(branch: number, branches: number, count: number): { Vector2 }
	local base = (branch - 1) / branches * math.pi * 2 - math.pi * 0.75
	local points = {}
	local turn, radius = 0, START_RADIUS
	for level = 1, count do
		local angle = base + turn
		local jitter = Vector2.new(math.noise(branch * 7.31, level * 0.83), math.noise(level * 0.71, branch * 3.17)) * JITTER * 2
		points[level] = Vector2.new(math.cos(angle), math.sin(angle)) * radius + jitter
		turn += SPACING / radius
		radius = START_RADIUS + PITCH * turn / (2 * math.pi)
	end
	return points
end

local function setColor(pieces, color: Color3)
	for _, frame in pieces do
		frame.BackgroundColor3 = color
	end
end

local function setTransparency(pieces, transparency: number)
	for _, frame in pieces do
		frame.BackgroundTransparency = transparency
	end
end

-- Línea entre dos puntos del lienzo.
local function line(canvas: Instance, from: Vector2, to: Vector2): Frame
	local delta = to - from
	local frame = Instance.new("Frame")
	frame.Name = "Line"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	frame.Size = UDim2.fromOffset(delta.Magnitude, 3)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	frame.BackgroundColor3 = COLOR_LINE
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.ZIndex = Z_LINE
	frame.Parent = canvas
	return frame
end

-- Nodo hexagonal: halo, borde oscuro, relleno, centro más claro, icono y texto.
local function buildNode(canvas: Instance, name: string, point: Vector2, size: number, icon: string?, iconColor: Color3)
	local width = HEX * size
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(point.X, point.Y)
	holder.Size = UDim2.fromOffset(width + 12, width + 24)
	holder.BackgroundTransparency = 1
	holder.Parent = canvas
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local haloHolder, halo = Ui.hex(holder, width * 1.34, WHITE)
	haloHolder.Name = "Halo"
	haloHolder.Visible = false
	setTransparency(halo, 0.82)

	Ui.hex(holder, width + 12, COLOR_BORDER)
	local _, pieces = Ui.hex(holder, width, COLOR_LOCKED)
	local _, core = Ui.hex(holder, width * 0.8, COLOR_LOCKED)

	local iconFrame = nil
	if icon then
		iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconSlot"
		iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		iconFrame.Position = UDim2.fromScale(0.5, 0.36)
		iconFrame.Size = UDim2.fromOffset(46 * size, 46 * size)
		iconFrame.BackgroundTransparency = 1
		iconFrame.Parent = holder
		ICONS[icon](iconFrame, iconColor)
	end

	local label = Ui.label(holder, 14 * size)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, if icon then 0.7 else 0.5)
	label.Size = UDim2.fromOffset(width - 6, 34 * size)
	label.TextWrapped = true
	label.RichText = false

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromOffset(width - 8, width - 8)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Parent = holder

	-- Todo el nodo por debajo de los contadores y el menú, que se quedan encima de esta pantalla.
	for _, item in holder:GetDescendants() do
		if item:IsA("GuiObject") then
			item.ZIndex = Z_NODE
		end
	end
	haloHolder.ZIndex = Z_LINE
	for _, frame in halo do
		frame.ZIndex = Z_LINE
	end

	return {
		pieces = pieces,
		core = core,
		halo = halo,
		haloHolder = haloHolder,
		icon = iconFrame,
		label = label,
		button = button,
		scale = scale,
		state = nil,
	}
end

-- Fondo -----------------------------------------------------------------------------------

-- Capa de estrellas del tamaño de la pantalla. Se crean dos seguidas para que al desplazarse no se vea el corte.
local function starLayer(parent: Instance, random: Random, count: number, size: number, transparency: number): { Frame }
	local copies = {}
	local stars = {}
	for _ = 1, count do
		table.insert(stars, { random:NextNumber(), random:NextNumber(), random:NextNumber(0.6, 1.4), random:NextNumber() })
	end
	for copy = 1, 2 do
		local layer = Instance.new("Frame")
		layer.Name = "Stars"
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.ZIndex = Z_BACK
		layer.Parent = parent
		for _, star in stars do
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(star[1], star[2])
			dot.Size = UDim2.fromOffset(size * star[3], size * star[3])
			dot.Rotation = 45
			dot.BackgroundColor3 = Color3.fromHSV(0.55 + star[4] * 0.2, star[4] * 0.35, 1)
			dot.BackgroundTransparency = transparency + star[4] * 0.3
			dot.BorderSizePixel = 0
			dot.ZIndex = Z_BACK
			dot.Parent = layer
		end
		copies[copy] = layer
	end
	return copies
end

-- Nube de color grande y muy transparente, que se apaga hacia un lado.
local function nebula(parent: Instance, color: Color3, size: number, position: UDim2, rotation: number): Frame
	local cloud = Instance.new("Frame")
	cloud.Name = "Nebula"
	cloud.AnchorPoint = Vector2.new(0.5, 0.5)
	cloud.Position = position
	cloud.Size = UDim2.fromOffset(size, size * 0.7)
	cloud.Rotation = rotation
	cloud.BackgroundColor3 = color
	cloud.BackgroundTransparency = 0.55
	cloud.BorderSizePixel = 0
	cloud.ZIndex = Z_BACK
	cloud.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = cloud
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = cloud
	return cloud
end

function SkillTree.start()
	local overlay = Instance.new("TextButton")
	overlay.Name = "Upgrades"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = WHITE
	overlay.BorderSizePixel = 0
	overlay.AutoButtonColor = false
	overlay.Text = ""
	overlay.ClipsDescendants = true
	overlay.Visible = false
	overlay.ZIndex = Z_BACK

	-- Va en su propia pantalla, por debajo de la del Hud: así queda entera detrás de los contadores y el menú.
	-- Como la del Hud, ocupa también la franja de arriba de Roblox.
	local screen = Instance.new("ScreenGui")
	screen.Name = "UpgradesScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = -1
	screen.Parent = player:WaitForChild("PlayerGui")
	overlay.Parent = screen
	Ui.register("Upgrades", overlay)

	local space = Instance.new("UIGradient")
	space.Rotation = 55
	space.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 8, 30)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(34, 14, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 16, 38)),
	})
	space.Parent = overlay

	local random = Random.new(7)
	local nebulas = {
		nebula(overlay, Color3.fromRGB(150, 70, 255), 900, UDim2.fromScale(0.2, 0.3), 25),
		nebula(overlay, Color3.fromRGB(40, 140, 255), 1000, UDim2.fromScale(0.8, 0.7), -20),
		nebula(overlay, Color3.fromRGB(255, 80, 180), 700, UDim2.fromScale(0.75, 0.2), 60),
		nebula(overlay, Color3.fromRGB(40, 210, 190), 650, UDim2.fromScale(0.25, 0.8), -50),
	}
	-- Tres capas de estrellas: las del fondo, pequeñas y lentas; las de delante, grandes y rápidas.
	local layers = {
		{ copies = starLayer(overlay, random, 70, 3, 0.45), speed = 0.004, parallax = 0.03 },
		{ copies = starLayer(overlay, random, 45, 5, 0.3), speed = 0.009, parallax = 0.07 },
		{ copies = starLayer(overlay, random, 18, 8, 0.1), speed = 0.018, parallax = 0.14 },
	}

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(0, 0)
	canvas.BackgroundTransparency = 1
	canvas.Parent = overlay
	local canvasScale = Instance.new("UIScale")
	canvasScale.Scale = ZOOM_START
	canvasScale.Parent = canvas

	local heading = Ui.label(overlay, 30)
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Position = UDim2.new(0.5, 0, 0, 100)
	heading.Size = UDim2.fromOffset(520, 34)
	heading.Text = "Árbol de mejoras"
	heading.ZIndex = Z_FRONT
	Ui.gradient(heading, WHITE, Color3.fromRGB(170, 190, 255), 90)
	local hint = Ui.label(overlay, 16)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 134)
	hint.Size = UDim2.fromOffset(620, 22)
	hint.Text = `<font color="{Ui.SOFT}">Arrastra para moverte · rueda o botones para acercar</font>`
	hint.ZIndex = Z_FRONT

	-- Botones de abajo.
	local buyAll = Ui.button(overlay, "Mejorar todo", Ui.COLORS.green)
	buyAll.Name = "BuyAll"
	buyAll.AnchorPoint = Vector2.new(1, 1)
	buyAll.Position = UDim2.new(0.5, 70, 1, -28)
	buyAll.Size = UDim2.fromOffset(300, 66)
	buyAll.TextSize = 30
	buyAll.ZIndex = Z_FRONT
	buyAll.Activated:Connect(function()
		Remotes.BuyAllUpgrades:FireServer()
	end)

	local close = Ui.button(overlay, "Cerrar", Ui.COLORS.red)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0, 1)
	close.Position = UDim2.new(0.5, 84, 1, -28)
	close.Size = UDim2.fromOffset(170, 66)
	close.TextSize = 28
	close.ZIndex = Z_FRONT
	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	-- Resumen de cada mejora, arriba a la derecha.
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	summary.AnchorPoint = Vector2.new(1, 0)
	summary.Position = UDim2.new(1, -16, 0, 100)
	summary.Size = UDim2.fromOffset(290, 16 + #Config.UpgradeOrder * 40)
	summary.BackgroundColor3 = WHITE
	summary.BorderSizePixel = 0
	summary.ZIndex = Z_FRONT - 1
	summary.Parent = overlay
	Ui.round(summary, 12)
	Ui.stroke(summary, BLACK, 3)
	Ui.gradient(summary, Color3.fromRGB(58, 48, 110), Color3.fromRGB(18, 18, 40), 90)
	local summaryRows = {}
	for row, name in Config.UpgradeOrder do
		local upgrade = Config.Upgrades[name]
		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(14, 8 + (row - 1) * 40 + 11)
		dot.Size = UDim2.fromOffset(18, 18)
		dot.Rotation = 45
		dot.BackgroundColor3 = upgrade.color
		dot.BorderSizePixel = 0
		dot.ZIndex = Z_FRONT
		dot.Parent = summary
		Ui.stroke(dot, BLACK, 2)
		local text = Ui.label(summary, 15)
		text.Position = UDim2.fromOffset(44, 8 + (row - 1) * 40)
		text.Size = UDim2.new(1, -52, 0, 40)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.ZIndex = Z_FRONT
		summaryRows[name] = text
	end

	-- Mover y acercar -----------------------------------------------------------------------
	local offset = Vector2.zero
	local zoom = ZOOM_START
	local extent = START_RADIUS -- distancia del centro al nodo más lejano; se mide al crear los nodos

	local function place()
		canvas.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		canvasScale.Scale = zoom
	end

	-- Cambia el zoom dejando quieto el punto de la pantalla `anchor` (medido desde el centro).
	local function setZoom(target: number, anchor: Vector2)
		target = math.clamp(target, ZOOM_MIN, ZOOM_MAX)
		offset = anchor - (anchor - offset) * (target / zoom)
		zoom = target
		place()
	end

	local function zoomButton(text: string, order: number, action: () -> ())
		local item = Ui.button(overlay, text, Ui.COLORS.blue)
		item.AnchorPoint = Vector2.new(1, 1)
		item.Position = UDim2.new(1, -16, 1, -28 - (order - 1) * 66)
		item.Size = UDim2.fromOffset(if #text > 1 then 110 else 58, 58)
		item.TextSize = if #text > 1 then 20 else 34
		item.ZIndex = Z_FRONT
		item.Activated:Connect(action)
		return item
	end
	zoomButton("Centrar", 1, function()
		offset = Vector2.zero
		zoom = ZOOM_START
		place()
	end).Name = "Center"
	-- Aleja lo justo para que quepa la galaxia entera, dejando sitio a los contadores y a los botones.
	zoomButton("Ver todo", 4, function()
		local view = overlay.AbsoluteSize
		offset = Vector2.new(0, 30)
		zoom = math.clamp(math.min(view.X - 620, view.Y - 250) / (2 * extent), ZOOM_MIN, ZOOM_MAX)
		place()
	end).Name = "Fit"
	zoomButton("-", 2, function()
		setZoom(zoom / 1.3, Vector2.zero)
	end).Name = "ZoomOut"
	zoomButton("+", 3, function()
		setZoom(zoom * 1.3, Vector2.zero)
	end).Name = "ZoomIn"

	local dragging = false
	local last = Vector3.zero
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			last = input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not overlay.Visible then
			return
		end
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - last
			last = input.Position
			offset += Vector2.new(delta.X, delta.Y)
			place()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			local center = overlay.AbsolutePosition + overlay.AbsoluteSize / 2
			setZoom(zoom * 1.15 ^ input.Position.Z, Vector2.new(input.Position.X, input.Position.Y) - center)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	-- Pellizco en pantallas táctiles.
	local pinchStart = zoom
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if not overlay.Visible then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = zoom
		end
		dragging = false
		setZoom(pinchStart * scale, Vector2.zero)
	end)

	-- Nodos ---------------------------------------------------------------------------------
	local nodes = {} -- [mejora] = { [nivel] = nodo }
	local lines = {} -- [mejora] = { [nivel] = línea que llega a ese nodo }
	local pulsing = {} -- nodos que se pueden comprar ya: laten
	local built = false

	-- Deja el nodo y la línea que llega a él con el aspecto de ese estado. Solo toca lo que cambia.
	local function apply(name: string, level: number, state: string)
		local node = nodes[name][level]
		if node.state == state then
			return
		end
		node.state = state
		local upgrade = Config.Upgrades[name]
		local link = lines[name][level]
		pulsing[node] = if state == "ready" then true else nil

		local fill, lineColor, lineWidth, lineTransparency = COLOR_LOCKED, COLOR_LINE, 3, 0.5
		if state == "owned" then
			fill, lineColor, lineWidth, lineTransparency = upgrade.color, upgrade.color:Lerp(WHITE, 0.25), 7, 0
		elseif state == "ready" then
			fill, lineColor, lineWidth, lineTransparency = COLOR_NEXT, COLOR_NEXT, 5, 0.1
		elseif state == "poor" then
			fill, lineColor, lineWidth, lineTransparency = upgrade.color:Lerp(COLOR_LOCKED, 0.65), upgrade.color:Lerp(COLOR_LINE, 0.5), 5, 0.3
		elseif state == "far" then
			fill = COLOR_FAR:Lerp(upgrade.color, 0.35)
		end

		setColor(node.pieces, fill)
		setColor(node.core, fill:Lerp(WHITE, if state == "owned" or state == "ready" then 0.28 else 0.1))
		node.haloHolder.Visible = state == "owned" or state == "ready"
		setColor(node.halo, fill)
		setTransparency(node.halo, 0.82)
		node.scale.Scale = if state == "far" then FAR_SCALE else 1
		node.label.Visible = state ~= "far"
		node.label.TextTransparency = if state == "near" then 0.45 else 0
		if node.icon then
			node.icon.Visible = state ~= "far"
		end
		link.BackgroundColor3 = lineColor
		link.BackgroundTransparency = lineTransparency
		link.Size = UDim2.fromOffset(link.Size.X.Offset, lineWidth)
	end

	-- Crea todos los nodos y sus líneas. Se hace la primera vez que se abre la pantalla, no al entrar al juego.
	local function build()
		built = true
		local start = buildNode(canvas, "Start", Vector2.zero, BIG, nil, BLACK)
		setColor(start.pieces, Ui.COLORS.green)
		setColor(start.core, Ui.COLORS.green:Lerp(WHITE, 0.28))
		setColor(start.halo, Ui.COLORS.green)
		start.haloHolder.Visible = true
		start.label.Text = "Inicio"
		start.label.TextSize = 22

		for branch, name in Config.UpgradeOrder do
			local upgrade = Config.Upgrades[name]
			local points = layout(branch, #Config.UpgradeOrder, upgrade.maxLevel)
			nodes[name], lines[name] = {}, {}
			for level = 1, upgrade.maxLevel do
				local milestone = level % 5 == 0 or level == upgrade.maxLevel
				extent = math.max(extent, points[level].Magnitude + HEX)
				lines[name][level] = line(canvas, if level == 1 then Vector2.zero else points[level - 1], points[level])
				local node = buildNode(canvas, `{name}{level}`, points[level], if milestone then BIG else 1, upgrade.icon, upgrade.color)
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
		end
	end

	local function refresh()
		if not overlay.Visible then
			return
		end
		if not built then
			build()
		end
		local coins = player:GetAttribute("Coins") or 0
		local gems = player:GetAttribute("Gems") or 0
		local canBuy = false
		for _, name in Config.UpgradeOrder do
			local upgrade = Config.Upgrades[name]
			local level = player:GetAttribute("Upgrade_" .. name) or 0
			local balance = if upgrade.currency == "gems" then gems else coins
			local affordable = level < upgrade.maxLevel and balance >= Upgrades.cost(name, level)
			canBuy = canBuy or affordable
			for index = 1, upgrade.maxLevel do
				local state = "far"
				if index <= level then
					state = "owned"
				elseif index == level + 1 then
					state = if affordable then "ready" else "poor"
				elseif index <= level + AHEAD then
					state = "near"
				end
				apply(name, index, state)
			end

			local price = if level >= upgrade.maxLevel
				then `<font color="#6fe07a">al máximo</font>`
				else `<font color="{if affordable then "#ffd24a" else Ui.SOFT}">sig. {Format.short(Upgrades.cost(name, level))}</font>`
			summaryRows[name].Text = `{upgrade.short} <font color="{Ui.SOFT}">{level}/{upgrade.maxLevel}</font> · {Upgrades.display(name, level)}\n{price}`
		end
		buyAll.BackgroundColor3 = if canBuy then Ui.COLORS.green else Ui.COLORS.gray
	end

	-- Animación: solo corre con la pantalla abierta.
	local animation: RBXScriptConnection? = nil
	local nextMeteor = 0
	local function animate()
		local now = os.clock()
		local view = overlay.AbsoluteSize
		for _, layer in layers do
			-- Deriva continua más un desplazamiento según lo que se haya movido el árbol.
			local shift = (now * layer.speed + offset.X * layer.parallax / math.max(view.X, 1)) % 1
			local vertical = offset.Y * layer.parallax
			layer.copies[1].Position = UDim2.new(-shift, 0, 0, vertical)
			layer.copies[2].Position = UDim2.new(1 - shift, 0, 0, vertical)
		end
		for index, cloud in nebulas do
			cloud.Rotation += 0.02 * (if index % 2 == 0 then 1 else -1)
			cloud.BackgroundTransparency = 0.55 + 0.12 * math.sin(now * 0.3 + index * 1.7)
		end
		space.Rotation = 55 + 12 * math.sin(now * 0.07)

		local beat = 0.5 + 0.5 * math.sin(now * 4)
		for node in pulsing do
			node.scale.Scale = 1 + 0.06 * beat
			setTransparency(node.halo, 0.55 + 0.35 * beat)
		end

		if now >= nextMeteor then
			nextMeteor = now + random:NextNumber(2.5, 6)
			local meteor = Instance.new("Frame")
			meteor.Name = "Meteor"
			meteor.AnchorPoint = Vector2.new(1, 0.5)
			meteor.Size = UDim2.fromOffset(random:NextInteger(90, 180), 2)
			meteor.Rotation = random:NextNumber(18, 34)
			meteor.BackgroundColor3 = WHITE
			meteor.BorderSizePixel = 0
			meteor.ZIndex = Z_BACK
			local tail = Instance.new("UIGradient")
			tail.Transparency = NumberSequence.new(1, 0.1)
			tail.Parent = meteor
			local from = Vector2.new(random:NextNumber(-0.1, 0.8), random:NextNumber(-0.1, 0.5))
			meteor.Position = UDim2.fromScale(from.X, from.Y)
			meteor.Parent = overlay
			local travel = TweenService:Create(meteor, TweenInfo.new(0.9, Enum.EasingStyle.Linear), {
				Position = UDim2.fromScale(from.X + 0.35, from.Y + 0.35 * math.tan(math.rad(meteor.Rotation))),
				BackgroundTransparency = 1,
			})
			travel.Completed:Connect(function()
				meteor:Destroy()
			end)
			travel:Play()
		end
	end

	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		if overlay.Visible then
			refresh()
			if not animation then
				animation = RunService.RenderStepped:Connect(animate)
			end
		elseif animation then
			animation:Disconnect()
			animation = nil
			dragging = false
		end
	end)
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Coins" or attribute == "Gems" or string.sub(attribute, 1, 8) == "Upgrade_" then
			refresh()
		end
	end)
	place()
end

return SkillTree
