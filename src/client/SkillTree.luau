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
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)

local SkillTree = {}

local player = Players.LocalPlayer

local HEX = 84 -- ancho del hexágono
local BIG = 1.22 -- los nodos de cada 5 niveles y el último de cada brazo son más grandes
local AHEAD = 3 -- nodos sin comprar que se ven enteros por delante; los demás son estrellas pequeñas
local FAR_SCALE = 0.5

-- Espiral: los brazos van entrelazados, así que entre un brazo y el de al lado hay ARM_GAP (centro a
-- centro): cada brazo se aleja ARM_GAP × número de brazos por vuelta. SPACING es lo que hay entre un
-- nodo y el siguiente del mismo brazo. Los dos dejan aire de sobra para el hexágono grande (HEX × BIG)
-- y el desorden (JITTER), así que ningún nodo pisa a otro.
local START_RADIUS = 175
local ARM_GAP = 150
local SPACING = 140
local JITTER = 10 -- desorden de los nodos, para que parezca una constelación y no una regla

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

-- Parte un texto en líneas de como mucho `width` letras, sin cortar palabras.
local function wrap(text: string, width: number): string
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		if line ~= "" and (utf8.len(line .. " " .. word) or 0) > width then
			table.insert(lines, line)
			line = word
		else
			line = if line == "" then word else line .. " " .. word
		end
	end
	table.insert(lines, line)
	return table.concat(lines, "\n")
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
		radius = START_RADIUS + ARM_GAP * branches * turn / (2 * math.pi)
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
	-- Fondo oscuro detrás del título y la ayuda: sin él, los hexágonos de detrás no dejan leerlos.
	local titleBack = Instance.new("Frame")
	titleBack.Name = "TitleBack"
	titleBack.AnchorPoint = Vector2.new(0.5, 0)
	titleBack.Position = UDim2.new(0.5, 0, 0, 94)
	titleBack.Size = UDim2.new(0.9, 0, 0, 68)
	local titleLimit = Instance.new("UISizeConstraint")
	titleLimit.MaxSize = Vector2.new(600, 68)
	titleLimit.Parent = titleBack
	titleBack.BackgroundColor3 = WHITE
	titleBack.BackgroundTransparency = 0.25
	titleBack.ZIndex = Z_FRONT - 1
	titleBack.Parent = overlay
	Ui.round(titleBack, 14)
	Ui.stroke(titleBack, Color3.new(0, 0, 0), 3)
	Ui.panel(titleBack, Color3.fromRGB(34, 38, 70))
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Parent = titleBack
	heading.Position = UDim2.new(0.5, 0, 0, 6)
	heading.Size = UDim2.new(1, -24, 0, 34)
	heading.Text = "Árbol de mejoras"
	heading.ZIndex = Z_FRONT
	Ui.gradient(heading, WHITE, Color3.fromRGB(170, 190, 255), 90)
	local hint = Ui.label(titleBack, 16)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 40)
	hint.Size = UDim2.new(1, -16, 0, 22)
	hint.TextScaled = true
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 16
	hintLimit.Parent = hint
	hint.Text = `<font color="{Ui.SOFT}">Arrastra para moverte · rueda o botones para acercar</font>`
	hint.ZIndex = Z_FRONT

	-- Una columna del HUD reserva espacio para resumen, zoom y acciones.
	local actions = Instance.new("Frame")
	actions.Name = "UpgradeActions"
	actions.AnchorPoint = Vector2.new(1, 1)
	actions.Position = UDim2.new(1, -14, 1, -14)
	actions.Size = UDim2.fromOffset(300, 58)
	actions.BackgroundTransparency = 1
	actions.Visible = false
	actions.Parent = Ui.hud()
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0.02, 0)
	actionLayout.Parent = actions
	local buyAll = Ui.button(actions, "Mejorar todo", Ui.COLORS.green)
	buyAll.Name = "BuyAll"
	buyAll.LayoutOrder = 1
	buyAll.Size = UDim2.fromScale(0.62, 1)
	buyAll.TextSize = 22
	buyAll.ZIndex = Z_FRONT
	buyAll.Activated:Connect(function()
		Remotes.BuyAllUpgrades:FireServer()
	end)

	local close = Ui.button(actions, "Cerrar", Ui.COLORS.red)
	close.Name = "Close"
	close.LayoutOrder = 2
	close.Size = UDim2.fromScale(0.36, 1)
	close.TextSize = 22
	close.ZIndex = Z_FRONT
	close.Activated:Connect(function()
		Ui.close(overlay)
	end)

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

	-- El HUD escala este contenedor igual que las estadísticas.
	local zoomControls = Instance.new("Frame")
	zoomControls.Name = "UpgradeControls"
	zoomControls.AnchorPoint = Vector2.new(1, 1)
	zoomControls.Position = UDim2.new(1, -14, 1, -86)
	zoomControls.Size = UDim2.fromOffset(300, 58)
	zoomControls.BackgroundTransparency = 1
	zoomControls.Visible = false
	zoomControls.Parent = Ui.hud()
	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Horizontal
	controlLayout.Padding = UDim.new(0.02, 0)
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Parent = zoomControls

	local function zoomButton(text: string, order: number, action: () -> ())
		local item = Ui.button(zoomControls, text, Ui.COLORS.blue)
		item.LayoutOrder = order
		item.Size = UDim2.fromScale(0.235, 1)
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
			-- Desplazar el resumen no debe cambiar también el zoom del árbol.
			local dock = Ui.hud():FindFirstChild("StatsDock")
			if dock and dock.Visible then
				local point, size = dock.AbsolutePosition, dock.AbsoluteSize
				if input.Position.X >= point.X and input.Position.X <= point.X + size.X and input.Position.Y >= point.Y and input.Position.Y <= point.Y + size.Y then return end
			end
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
	local ends = {} -- [mejora] = { [nivel] = { from, to } }: extremos de la línea que llega a ese nodo
	local flowing = {} -- [línea comprada] = { gradient, phase }: un destello recorre la línea
	local bursting = 0 -- explosiones en marcha (con "Mejorar todo" salen muchas a la vez: se recortan)
	local built = false

	-- Compra de un nodo: onda expansiva, chispas, el nodo da un salto y un destello viaja por la línea.
	local function burst(name: string, level: number)
		if Performance.get() then return end -- modo rendimiento
		local node = nodes[name][level]
		local link = lines[name][level]
		local point = ends[name][level]
		local color = Config.Upgrades[name].color
		Sfx.play("buy")
		Sfx.play("buyPing")

		node.scale.Scale = 1.5
		TweenService:Create(node.scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		link.BackgroundColor3 = WHITE
		TweenService:Create(link, TweenInfo.new(0.7), { BackgroundColor3 = color:Lerp(WHITE, 0.25) }):Play()
		if bursting >= 8 then
			return
		end
		bursting += 1
		task.delay(0.7, function()
			bursting -= 1
		end)

		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromOffset(point.to.X, point.to.Y)
		ring.Size = UDim2.fromOffset(40, 40)
		ring.BackgroundTransparency = 1
		ring.ZIndex = Z_NODE + 1
		ring.Parent = canvas
		Ui.round(ring, 200)
		local stroke = Ui.stroke(ring, color:Lerp(WHITE, 0.4), 7)
		TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(320, 320) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1, Thickness = 1 }):Play()
		task.delay(0.65, function()
			ring:Destroy()
		end)

		for index = 1, 10 do
			local angle = index / 10 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
			local distance = random:NextNumber(90, 160)
			local spark = Instance.new("Frame")
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.Position = UDim2.fromOffset(point.to.X, point.to.Y)
			spark.Size = UDim2.fromOffset(12, 12)
			spark.Rotation = 45
			spark.BackgroundColor3 = color:Lerp(WHITE, 0.6)
			spark.BorderSizePixel = 0
			spark.ZIndex = Z_NODE + 2
			spark.Parent = canvas
			Ui.stroke(spark, BLACK, 1.5)
			local fly = TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(spark, fly, {
				Position = UDim2.fromOffset(point.to.X + math.cos(angle) * distance, point.to.Y + math.sin(angle) * distance),
				Size = UDim2.fromOffset(2, 2),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.7, function()
				spark:Destroy()
			end)
		end

		-- El destello que va por la línea, del nodo anterior a este.
		local traveler = Instance.new("Frame")
		traveler.AnchorPoint = Vector2.new(0.5, 0.5)
		traveler.Position = UDim2.fromOffset(point.from.X, point.from.Y)
		traveler.Size = UDim2.fromOffset(16, 16)
		traveler.BackgroundColor3 = WHITE
		traveler.BorderSizePixel = 0
		traveler.ZIndex = Z_NODE + 2
		traveler.Parent = canvas
		Ui.round(traveler, 8)
		Ui.stroke(traveler, color, 3)
		local run = TweenService:Create(traveler, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Position = UDim2.fromOffset(point.to.X, point.to.Y) })
		run.Completed:Connect(function()
			traveler:Destroy()
		end)
		run:Play()
	end

	-- Deja el nodo y la línea que llega a él con el aspecto de ese estado. Solo toca lo que cambia.
	local function apply(name: string, level: number, state: string)
		local node = nodes[name][level]
		if node.state == state then
			return
		end
		local previous = node.state
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

		-- Las líneas compradas llevan un destello que las recorre sin parar.
		local flow = link:FindFirstChild("Flow") :: UIGradient?
		if state == "owned" then
			if not flow then
				flow = Instance.new("UIGradient")
				flow.Name = "Flow"
				flow.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.4),
					NumberSequenceKeypoint.new(0.4, 0.4),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.6, 0.4),
					NumberSequenceKeypoint.new(1, 0.4),
				})
				flow.Parent = link
			end
			flowing[link] = { gradient = flow, phase = random:NextNumber() }
		else
			flowing[link] = nil
			if flow then
				flow:Destroy()
			end
		end
		if previous ~= nil and previous ~= "owned" and state == "owned" then
			burst(name, level)
		end
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
			nodes[name], lines[name], ends[name] = {}, {}, {}
			for level = 1, upgrade.maxLevel do
				local milestone = level % 5 == 0 or level == upgrade.maxLevel
				extent = math.max(extent, points[level].Magnitude + HEX)
				local fromPoint = if level == 1 then Vector2.zero else points[level - 1]
				ends[name][level] = { from = fromPoint, to = points[level] }
				lines[name][level] = line(canvas, fromPoint, points[level])
				local node = buildNode(canvas, `{name}{level}`, points[level], if milestone then BIG else 1, upgrade.icon, upgrade.color)
				node.label.Text = `{upgrade.short} {roman(level)}`
				nodes[name][level] = node

				Ui.tip(node.button, function()
					local owned = (player:GetAttribute("Upgrade_" .. name) or 0) >= level
					local currency = if upgrade.currency == "gems" then "gemas" else "monedas"
					local state = if owned
						then `<font color="#6fe07a">Comprada</font>`
						else `Precio: {Format.short(Upgrades.cost(name, level - 1))} {currency}`
					-- "desc" (si la mejora lo trae) explica para qué sirve, partido en líneas cortas: el cartel mide lo que
					-- su línea más larga y uno ancho se sale de la pantalla.
					local about = if upgrade.desc then `\n<font color="{Ui.SOFT}">{wrap(upgrade.desc, 44)}</font>` else ""
					return `{upgrade.name} {roman(level)}{about}\n<font color="{Ui.SOFT}">{Upgrades.display(name, level - 1)} → {Upgrades.display(name, level)}</font>\n{state}`,
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

		end
		buyAll.BackgroundColor3 = if canBuy then Ui.COLORS.green else Ui.COLORS.gray
	end

	-- Animación: solo corre con la pantalla abierta.
	local animation: RBXScriptConnection? = nil
	local nextMeteor = 0
	local function animate()
		if Performance.get() then return end -- modo rendimiento
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

		for link, flow in flowing do
			if link.Parent then
				flow.gradient.Offset = Vector2.new((now * 0.6 + flow.phase) % 1 * 2 - 1, 0)
			else
				flowing[link] = nil
			end
		end

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
		-- Las estadísticas de abajo a la derecha solo se ven mientras esta pantalla está abierta.
		local dock = Ui.hud():FindFirstChild("StatsDock")
		if dock then
			dock.Visible = overlay.Visible
		end
		zoomControls.Visible = overlay.Visible
		actions.Visible = overlay.Visible
		-- Las pociones activas ocupan ese mismo rincón: se esconden mientras las estadísticas están a la vista.
		local potions = Ui.hud():FindFirstChild("Potions")
		if potions then
			potions.Visible = not overlay.Visible
		end
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
