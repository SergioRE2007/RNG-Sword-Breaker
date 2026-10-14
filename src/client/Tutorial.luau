-- Tutorial de los primeros minutos (Config.Tutorial; los pasos los decide server/Tutorial, que publica en el jugador
-- los atributos "Tutorial", paso por el que va o 0 = terminado, y "TutorialCount"). Aquí va lo que se ve, todo dentro de
-- la capa Hud.Tutorial (suelta en el ScreenGui, no en HudRoot: así no la esconde la pantalla de Mejoras y se coloca con
-- medidas de pantalla; lo que debe encogerse con el HUD lleva su UIScale, que copia el de HudRoot):
--   · Intro: al empezar cada paso, la pantalla se oscurece y sale en grande "Paso 2/7" y lo que hay que hacer (antes,
--     "¡Muy bien!" por el paso cumplido; al final, "¡Tutorial completado!"). No bloquea el juego y se va sola.
--   · Banner: cartel grande arriba en el centro, bajo la barra de transporte: medalla con el número de paso, puntos de
--     los pasos, la frase, la barra de los pasos que cuentan y la X que lo salta (TutorialSkip, dos toques).
--   · Foco: cuando hay que pulsar un botón (del HUD o de dentro de una ventana: un arma de la mochila o de la bolsa, el
--     nodo de mejora), todo se oscurece menos ese botón, que lleva un aro que late, ondas y una flecha con "¡PULSA!"
--     que da toquecitos.
--   · Mundo (workspace.TutorialPointer): contorno brillante (Highlight) en el objetivo, flecha con cartel encima, disco
--     en el suelo y línea de luz desde el personaje; si el objetivo no se ve en pantalla, una flecha en el borde señala
--     hacia dónde está (Hud.Tutorial.EdgeArrow).
-- Los pasos que el servidor no cuenta solo (equipar, bolsa, lobby, abrir una ventana) se le avisan con TutorialCheck
-- cuando aquí parece que ya están; él lo comprueba. Un solo bucle, que solo vive mientras dura el tutorial (o su intro).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Tutorial = {}

local player = Players.LocalPlayer
local cfg = Config.Tutorial
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(90, 225, 120)
local LOBBY_Y = -28
local CHECK_EVERY = 0.6 -- segundos entre dos avisos al servidor
local BANNER = Vector2.new(640, 118) -- tamaño del cartel, en unidades del HUD
local BANNER_TOP = 100 -- debajo de la barra de transporte (10 + 76)
local DIM = 0.35 -- transparencia del oscurecido del foco (0 = negro)
local HOLE_PAD = 8 -- margen del hueco del foco alrededor del botón
local EDGE = 80 -- distancia al borde de la flecha que señala lo que no se ve
local PAGE_STEP, PAGE_PRAISE, PAGE_END = 2.6, 1.1, 3 -- segundos de cada página de la intro
-- Capas (la interfaz ordena el ZIndex globalmente): por encima de las ventanas y los avisos, por debajo de los carteles.
local Z = { dim = 60, ring = 61, banner = 64, pointer = 66, intro = 70 }

local layer: Frame
local hudScale: UIScale
local refs: { [string]: any } = {}
local world: { [string]: any }? = nil
local loop: RBXScriptConnection? = nil
local lastCheck = 0
local shown = 0 -- paso que enseña ahora el cartel
local skipped = false
local pages: { { title: string, text: string, color: Color3, duration: number, sound: string } } = {}
local pageStart = 0
local spot = { pos = Vector2.zero, size = Vector2.zero, alpha = 0 } -- hueco del foco, animado

local function step()
	local index = player:GetAttribute("Tutorial") or 0
	return cfg.Steps[index], index
end

-- Marco transparente que se encoge con el HUD (copia la escala de HudRoot).
local function follow(name: string, size: Vector2): (Frame, UIScale)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(size.X, size.Y)
	holder.BackgroundTransparency = 1
	holder.Parent = layer
	local fit = Instance.new("UIScale")
	fit.Scale = hudScale.Scale
	fit.Parent = holder
	hudScale:GetPropertyChangedSignal("Scale"):Connect(function()
		fit.Scale = hudScale.Scale
	end)
	return holder, fit
end

-- Pastilla de color con texto en mayúsculas ("¡PULSA!").
local function tag(parent: Instance, color: Color3): (Frame, TextLabel)
	local pill = Instance.new("Frame")
	pill.Name = "Tag"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Size = UDim2.fromOffset(150, 44)
	pill.BackgroundColor3 = WHITE
	pill.Parent = parent
	Ui.round(pill, 22)
	Ui.stroke(pill, BLACK, 3.5)
	Ui.gradient(pill, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.2), 90)
	local text = Ui.label(pill, 26)
	text.Size = UDim2.fromScale(1, 1)
	return pill, text
end

-- Rayos que giran (detrás de la medalla y de la intro).
local function rays(parent: Instance, name: string, size: number, count: number, color: Color3, transparency: number): Frame
	local burst = Instance.new("Frame")
	burst.Name = name
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Size = UDim2.fromOffset(size, size)
	burst.BackgroundTransparency = 1
	burst.Parent = parent
	for index = 1, count do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, math.max(6, size * 0.07), 1, 0)
		ray.Rotation = (index - 1) * 180 / count
		ray.BackgroundColor3 = color
		ray.BackgroundTransparency = transparency
		ray.BorderSizePixel = 0
		ray.Parent = burst
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = ray
	end
	return burst
end

local function buildBanner()
	local holder = follow("Banner", BANNER)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Visible = false
	refs.banner = holder

	local burst = rays(holder, "Burst", 170, 6, GOLD, 0.35)
	burst.Position = UDim2.new(0, 18, 0.5, 0)
	refs.burst = burst

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = WHITE
	card.Parent = holder
	Ui.round(card, 16)
	Ui.stroke(card, BLACK, 4)
	Ui.gradient(card, Color3.fromRGB(78, 66, 160), Color3.fromRGB(26, 24, 62), 90)
	local pop = Instance.new("UIScale")
	pop.Parent = card
	refs.pop = pop

	-- Brillo que cruza el cartel de vez en cuando.
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundColor3 = WHITE
	shine.Parent = card
	Ui.round(shine, 16)
	local sweep = Instance.new("UIGradient")
	sweep.Rotation = 20
	sweep.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.72),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweep.Offset = Vector2.new(-1, 0)
	sweep.Parent = shine
	refs.sweep = sweep

	-- Medalla con el número de paso, medio fuera del cartel por la izquierda.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0, 18, 0.5, 0)
	badge.Size = UDim2.fromOffset(104, 104)
	badge.BackgroundColor3 = WHITE
	badge.Parent = card
	Ui.round(badge, 52)
	Ui.stroke(badge, BLACK, 4)
	Ui.gradient(badge, GOLD:Lerp(WHITE, 0.35), Color3.fromRGB(235, 140, 30), 90)
	local number = Ui.label(badge, 52)
	number.Name = "Number"
	number.AnchorPoint = Vector2.new(0.5, 0.5)
	number.Position = UDim2.fromScale(0.5, 0.42)
	number.Size = UDim2.fromScale(1, 0.6)
	local of = Ui.label(badge, 20)
	of.Name = "Of"
	of.AnchorPoint = Vector2.new(0.5, 0.5)
	of.Position = UDim2.fromScale(0.5, 0.78)
	of.Size = UDim2.fromScale(1, 0.25)
	refs.badge, refs.number, refs.of = badge, number, of

	local left = 84 -- donde empieza el texto, pasada la medalla
	local kicker = Ui.label(card, 18)
	kicker.Name = "Kicker"
	kicker.Position = UDim2.fromOffset(left, 8)
	kicker.Size = UDim2.fromOffset(200, 22)
	kicker.TextXAlignment = Enum.TextXAlignment.Left
	kicker.TextColor3 = GOLD
	kicker.Text = Ui.upper(Lang.t(nil, "Tutorial"))

	-- Un punto por paso: hechos en verde, el de ahora en dorado y latiendo.
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.AnchorPoint = Vector2.new(1, 0)
	dots.Position = UDim2.new(1, -54, 0, 12)
	dots.Size = UDim2.fromOffset(#cfg.Steps * 20, 16)
	dots.BackgroundTransparency = 1
	dots.Parent = card
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 5)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = dots
	refs.dots = {}
	for index = 1, #cfg.Steps do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. index
		dot.LayoutOrder = index
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = Ui.COLORS.dark
		dot.Parent = dots
		Ui.round(dot, 7)
		Ui.stroke(dot, BLACK, 2)
		refs.dots[index] = dot
	end

	local text = Ui.label(card, 30)
	text.Name = "Text"
	text.Position = UDim2.fromOffset(left, 32)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextWrapped = true
	text.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.MinTextSize = 16
	limit.Parent = text
	refs.text = text

	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, left, 1, -12)
	track.Size = UDim2.new(1, -left - 18, 0, 20)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.Parent = card
	Ui.round(track, 10)
	Ui.stroke(track, BLACK, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Ui.round(fill, 10)
	Ui.gradient(fill, GREEN:Lerp(WHITE, 0.35), GREEN:Lerp(BLACK, 0.2), 90)
	local amount = Ui.label(track, 16)
	amount.Name = "Amount"
	amount.Size = UDim2.fromScale(1, 1)
	local bump = Instance.new("UIScale")
	bump.Parent = track
	refs.track, refs.fill, refs.amount, refs.bump = track, fill, amount, bump

	local skip = Ui.button(card, "X", Ui.COLORS.red)
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -8, 0, 8)
	skip.Size = UDim2.fromOffset(34, 30)
	skip.TextSize = 16
	Ui.tip(skip, function()
		return Lang.t(nil, "Skip the tutorial (no reward)"), Ui.COLORS.red
	end, true)
	-- Dos toques: el primero avisa.
	local asked = 0
	skip.Activated:Connect(function()
		if os.clock() - asked < 3 then
			skipped = true
			table.clear(pages)
			Remotes.TutorialSkip:FireServer()
		else
			asked = os.clock()
			Ui.toast(Lang.t(nil, "Press the X again to skip the tutorial (no reward)"), Ui.COLORS.orange)
		end
	end)

	Ui.layer(holder, Z.banner)
	-- Los rayos, por detrás del cartel: solo asoman alrededor de la medalla.
	Ui.layer(burst, Z.banner - 1)
end

local function buildIntro()
	local intro = Instance.new("Frame")
	intro.Name = "Intro"
	intro.Size = UDim2.fromScale(1, 1)
	intro.BackgroundColor3 = BLACK
	intro.BackgroundTransparency = 1
	intro.BorderSizePixel = 0
	intro.Visible = false
	intro.Parent = layer
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.45)
	box.Size = UDim2.fromOffset(900, 360)
	box.BackgroundTransparency = 1
	box.Parent = intro
	local fit = Instance.new("UIScale")
	fit.Parent = box
	refs.introFit = fit
	local burst = rays(box, "Rays", 620, 12, GOLD, 0.55)
	burst.Position = UDim2.fromScale(0.5, 0.32)
	local title = Ui.label(box, 84)
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.3)
	title.Size = UDim2.new(1, 0, 0, 100)
	local text = Ui.label(box, 42)
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromScale(0.5, 0.52)
	text.Size = UDim2.new(1, 0, 0, 150)
	text.TextWrapped = true
	text.TextYAlignment = Enum.TextYAlignment.Top
	for _, label in { title, text } do
		local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Thickness = if label == title then 6 else 4
	end
	Ui.layer(intro, Z.intro)
	refs.intro, refs.introRays, refs.introTitle, refs.introText = intro, burst, title, text
end

local function buildPointer()
	-- Oscurecido del foco: cuatro bandas alrededor del hueco del botón. No son Active: no tapan los clics.
	refs.dims = {}
	for _, name in { "Top", "Bottom", "Left", "Right" } do
		local dim = Instance.new("Frame")
		dim.Name = "Dim" .. name
		dim.BackgroundColor3 = BLACK
		dim.BackgroundTransparency = 1
		dim.BorderSizePixel = 0
		dim.ZIndex = Z.dim
		dim.Visible = false
		dim.Parent = layer
		table.insert(refs.dims, dim)
	end
	-- Aro dorado que late alrededor del botón y dos ondas que salen de él.
	local function ring(name: string, thickness: number): (Frame, UIStroke)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 1
		frame.ZIndex = Z.ring
		frame.Visible = false
		frame.Parent = layer
		Ui.round(frame, 16)
		return frame, Ui.stroke(frame, GOLD, thickness)
	end
	refs.ring, refs.ringStroke = ring("TutorialRing", 5)
	refs.ripples = {}
	for index = 1, 2 do
		local frame, stroke = ring("Ripple" .. index, 3)
		refs.ripples[index] = { frame = frame, stroke = stroke }
	end

	-- Flecha con "¡PULSA!" que da toquecitos sobre el botón.
	local holder = follow("TutorialArrow", Vector2.new(170, 170))
	holder.Visible = false
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(110, 110)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▼"
	arrow.TextScaled = true
	arrow.TextColor3 = GOLD
	arrow.Parent = holder
	Ui.textStroke(arrow, 5)
	local pill, label = tag(holder, GREEN)
	label.Text = Ui.upper(Lang.t(nil, "Click!"))
	Ui.layer(holder, Z.pointer)
	refs.pointer, refs.arrow, refs.pill = holder, arrow, pill

	-- Flecha en el borde de la pantalla hacia lo que no se ve.
	local edge = follow("EdgeArrow", Vector2.new(96, 96))
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Visible = false
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.62)
	dot.Size = UDim2.fromOffset(46, 46)
	dot.BackgroundColor3 = WHITE
	dot.Parent = edge
	Ui.round(dot, 23)
	Ui.stroke(dot, BLACK, 3.5)
	Ui.gradient(dot, GOLD:Lerp(WHITE, 0.35), Color3.fromRGB(235, 140, 30), 90)
	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.2)
	tip.Size = UDim2.fromOffset(56, 56)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.GothamBlack
	tip.Text = "▲"
	tip.TextScaled = true
	tip.TextColor3 = GOLD
	tip.Parent = edge
	Ui.textStroke(tip, 4)
	Ui.layer(edge, Z.pointer)
	refs.edge = edge
end

local function buildWorld()
	local folder = Instance.new("Folder")
	folder.Name = "TutorialPointer"
	folder.Parent = workspace
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder
	local to = Instance.new("Attachment")
	to.Name = "To"
	to.Parent = anchor
	local from = Instance.new("Attachment")
	from.Name = "From"
	from.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(GOLD)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
	beam.Width0 = 1.2
	beam.Width1 = 2.4
	beam.FaceCamera = true
	beam.LightEmission = 0.7
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureLength = 6
	beam.TextureSpeed = 2
	beam.Parent = anchor

	-- Disco que se abre en el suelo bajo el objetivo.
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = GOLD
	disc.Transparency = 1
	disc.Parent = folder

	local glow = Instance.new("Highlight")
	glow.Name = "Glow"
	glow.FillColor = GOLD
	glow.OutlineColor = Color3.fromRGB(255, 245, 200)
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Enabled = false
	glow.Parent = folder

	local board = Instance.new("BillboardGui")
	board.Name = "Arrow"
	board.Size = UDim2.fromOffset(170, 170)
	board.AlwaysOnTop = true
	board.MaxDistance = 600
	board.Adornee = anchor
	board.Parent = folder
	local pill, label = tag(board, GREEN)
	pill.Position = UDim2.fromScale(0.5, 0.15)
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.62)
	arrow.Size = UDim2.fromOffset(110, 110)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▼"
	arrow.TextScaled = true
	arrow.TextColor3 = GOLD
	arrow.Parent = board
	Ui.textStroke(arrow, 5)
	local pulse = Instance.new("UIScale")
	pulse.Parent = arrow
	world = { folder = folder, anchor = anchor, from = from, to = to, beam = beam, disc = disc, glow = glow, board = board, label = label, arrow = arrow, pulse = pulse }
end

-- Lo que señala en el mundo ese paso (o nil si ahora no lo hay): la pieza o modelo, su centro, media altura y radio.
local function worldTarget(point: string): (Instance?, Vector3, number, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if point == "object" then
		local best, bestDistance = nil, math.huge
		for _, part in CollectionService:GetTagged("Destructible") do
			if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId and part:IsDescendantOf(workspace) then
				local distance = if root then (part.Position - root.Position).Magnitude else 0
				if distance < bestDistance then
					best, bestDistance = part, distance
				end
			end
		end
		if best then
			return best, best.Position, best.Size.Y / 2, math.max(best.Size.X, best.Size.Z) / 2
		end
	elseif point == "bag" then
		for _, bag in CollectionService:GetTagged("GoldBag") do
			if bag:GetAttribute("Owner") == player.UserId then
				local body = bag:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					return bag, body.Position, body.Size.Y / 2, math.max(body.Size.X, body.Size.Z) / 2 + 1
				end
			end
		end
	elseif string.sub(point, 1, 6) == "stall:" then
		local shop = string.sub(point, 7)
		for _, station in CollectionService:GetTagged("ShopStation") do
			if station:GetAttribute("Shop") == shop then
				local part = if station:IsA("BasePart") then station else station.Parent
				if part and part:IsA("BasePart") then
					local model = part:FindFirstAncestorOfClass("Model") or part
					return model, part.Position, 6, 8
				end
			end
		end
	end
	return nil, Vector3.zero, 0, 0
end

-- Si se ve de verdad: él y todos sus padres visibles, con tamaño.
local function onScreen(item: GuiObject): boolean
	if item.AbsoluteSize.X < 2 or item.AbsoluteSize.Y < 2 then
		return false
	end
	local at: Instance? = item
	while at and at:IsA("GuiObject") do
		if not at.Visible then
			return false
		end
		at = at.Parent
	end
	return true
end

-- El botón del HUD que señala ese paso (o nil).
local function buttonTarget(point: string): GuiObject?
	if string.sub(point, 1, 7) ~= "button:" then
		return nil
	end
	local at: Instance? = Ui.hud()
	for _, name in string.split(string.sub(point, 8), ".") do
		at = at and at:FindFirstChild(name)
	end
	return if at and at:IsA("GuiObject") then at else nil
end

-- La primera casilla de arma ("Sword<id>") que se ve entera en una rejilla con scroll, de las que cumplen `wanted`
-- (si no cumple ninguna, cualquiera).
local function firstCell(grid: Instance?, wanted: (number) -> boolean): GuiObject?
	if not (grid and grid:IsA("GuiObject")) then
		return nil
	end
	local top, bottom = grid.AbsolutePosition.Y, grid.AbsolutePosition.Y + grid.AbsoluteSize.Y
	local best, fallback = nil, nil
	local function before(a: GuiObject, b: GuiObject?): boolean
		if not b then
			return true
		end
		local pa, pb = a.AbsolutePosition, b.AbsolutePosition
		return pa.Y < pb.Y - 2 or (math.abs(pa.Y - pb.Y) <= 2 and pa.X < pb.X)
	end
	for _, cell in grid:GetChildren() do
		local id = tonumber(string.match(cell.Name, "^Sword(%d+)$"))
		if id and cell:IsA("GuiObject") and cell.Visible and cell.AbsolutePosition.Y >= top - 1 and cell.AbsolutePosition.Y + cell.AbsoluteSize.Y <= bottom + 1 then
			if wanted(id) and before(cell, best) then
				best = cell
			end
			if before(cell, fallback) then
				fallback = cell
			end
		end
	end
	return best or fallback
end

local function notEquipped(id: number): boolean
	return not Stats.isEquipped(player, id)
end

-- Lo que hay que pulsar dentro de la ventana del paso, si está abierta (o nil).
local function insideTarget(info): GuiObject?
	local gui = Ui.screen()
	if info.kind == "equip" then
		local window = gui:FindFirstChild("Backpack")
		if not (window and window:IsA("GuiObject") and Ui.isOpen(window)) then
			return nil
		end
		local body = window:FindFirstChild("Body")
		local swords = body and body:FindFirstChild("Swords")
		if swords and swords:IsA("GuiObject") and not swords.Visible then
			return window:FindFirstChild("TabSwords") :: GuiObject?
		end
		return firstCell(swords and swords:FindFirstChild("Grid"), notEquipped)
	elseif info.kind == "bag" then
		local window = gui:FindFirstChild("BagMenu")
		if not (window and window:IsA("GuiObject") and Ui.isOpen(window)) then
			return nil
		end
		local body = window:FindFirstChild("Body")
		return firstCell(body and body:FindFirstChild("Grid"), notEquipped)
	elseif info.kind == "upgrades" then
		local screen = player.PlayerGui:FindFirstChild("UpgradesScreen")
		local overlay = screen and screen:FindFirstChild("Upgrades")
		local canvas = overlay and overlay:FindFirstChild("Canvas")
		if not (canvas and overlay:IsA("GuiObject") and overlay.Visible) then
			return nil
		end
		-- El siguiente nivel de la primera mejora que se puede pagar (o de la primera).
		local chosen = nil
		for _, name in Config.UpgradeOrder do
			local upgrade = Config.Upgrades[name]
			local level = player:GetAttribute("Upgrade_" .. name) or 0
			if level < upgrade.maxLevel then
				local node = canvas:FindFirstChild(name .. (level + 1))
				local button = node and node:FindFirstChild("Button")
				if button and button:IsA("GuiObject") then
					chosen = chosen or button
					if Stats.wallet(player, upgrade.currency) >= Upgrades.cost(name, level) then
						chosen = button
						break
					end
				end
			end
		end
		if chosen then
			local view = layer.AbsoluteSize
			local centre = chosen.AbsolutePosition + chosen.AbsoluteSize / 2 - layer.AbsolutePosition
			if centre.X > 0 and centre.Y > 0 and centre.X < view.X and centre.Y < view.Y then
				return chosen
			end
		end
	end
	return nil
end

local function guiTarget(info): GuiObject?
	local inner = insideTarget(info)
	if inner then
		return if onScreen(inner) then inner else nil
	end
	if Ui.anyOpen() then
		return nil
	end
	local button = buttonTarget(info.point)
	return if button and onScreen(button) then button else nil
end

-- Si aquí parece que el paso ya está cumplido (los que el servidor no cuenta solo).
local function looksDone(info): boolean
	if info.kind == "equip" then
		return #Stats.loadout(player) >= 2
	elseif info.kind == "bag" then
		return (player:GetAttribute("Bag") or "") ~= ""
	elseif info.kind == "lobby" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root ~= nil and root.Position.Y < LOBBY_Y
	elseif info.kind == "seen" then
		local window = Ui.screen():FindFirstChild(info.window)
		return window ~= nil and window:IsA("GuiObject") and window.Visible
	end
	return false
end

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, direction)
end

-- Intro: una página tras otra, cada una entra, se queda y se va. Devuelve si sigue.
local function updateIntro(now: number): boolean
	local intro = refs.intro :: Frame
	local page = pages[1]
	while page and now - pageStart > page.duration do
		table.remove(pages, 1)
		pageStart = now
		page = pages[1]
		if page then
			Sfx.play(page.sound)
		elseif step() and refs.banner then
			-- Al acabar la intro, el cartel aparece de un bote.
			refs.pop.Scale = 0.6
			TweenService:Create(refs.pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	if not page then
		intro.Visible = false
		return false
	end
	local elapsed = now - pageStart
	local visible = math.min(elapsed / 0.2, 1, (page.duration - elapsed) / 0.3)
	visible = math.clamp(visible, 0, 1)
	intro.Visible = true
	intro.BackgroundTransparency = 1 - 0.55 * visible
	local title, text = refs.introTitle :: TextLabel, refs.introText :: TextLabel
	local heading = Ui.upper(page.title)
	if title.Text ~= heading then
		title.Text = heading
		text.Text = page.text
	end
	title.TextColor3 = page.color
	for _, label in { title, text } do
		label.TextTransparency = 1 - visible
		local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Transparency = 1 - visible
	end
	refs.introFit.Scale = hudScale.Scale * (0.4 + 0.6 * ease(elapsed / 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	local burst = refs.introRays :: Frame
	burst.Rotation = elapsed * 25
	for _, ray in burst:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = page.color
			ray.BackgroundTransparency = 1 - 0.45 * visible
		end
	end
	return true
end

local function hideSpotlight()
	spot.alpha = 0
	for _, dim in refs.dims do
		dim.Visible = false
	end
	refs.ring.Visible = false
	for _, ripple in refs.ripples do
		ripple.frame.Visible = false
	end
	refs.pointer.Visible = false
end

local function updateSpotlight(target: GuiObject?, now: number, dt: number)
	local origin, view = layer.AbsolutePosition, layer.AbsoluteSize
	if target then
		local pos = target.AbsolutePosition - origin - Vector2.one * HOLE_PAD
		local size = target.AbsoluteSize + Vector2.one * HOLE_PAD * 2
		if spot.alpha < 0.05 then
			spot.pos, spot.size = pos, size
		else
			local k = 1 - math.exp(-dt * 16)
			spot.pos = spot.pos:Lerp(pos, k)
			spot.size = spot.size:Lerp(size, k)
		end
	end
	spot.alpha += ((if target then 1 else 0) - spot.alpha) * (1 - math.exp(-dt * 8))
	if spot.alpha < 0.02 then
		hideSpotlight()
		return
	end
	local p, s = spot.pos, spot.size
	local rects = {
		{ Vector2.zero, Vector2.new(view.X, p.Y) },
		{ Vector2.new(0, p.Y + s.Y), Vector2.new(view.X, view.Y - p.Y - s.Y) },
		{ Vector2.new(0, p.Y), Vector2.new(p.X, s.Y) },
		{ Vector2.new(p.X + s.X, p.Y), Vector2.new(view.X - p.X - s.X, s.Y) },
	}
	for index, dim in refs.dims do
		local at, size = rects[index][1], rects[index][2]
		dim.Visible = true
		dim.Position = UDim2.fromOffset(at.X, at.Y)
		dim.Size = UDim2.fromOffset(math.max(size.X, 0), math.max(size.Y, 0))
		dim.BackgroundTransparency = 1 - (1 - DIM) * spot.alpha
	end
	local centre = p + s / 2
	local pulse = 0.5 + 0.5 * math.sin(now * 6)
	local ring = refs.ring :: Frame
	ring.Visible = true
	ring.Position = UDim2.fromOffset(centre.X, centre.Y)
	ring.Size = UDim2.fromOffset(s.X + pulse * 8, s.Y + pulse * 8)
	refs.ringStroke.Transparency = 1 - spot.alpha * (1 - pulse * 0.3)
	for index, ripple in refs.ripples do
		local phase = (now * 0.9 + (index - 1) * 0.5) % 1
		ripple.frame.Visible = not Performance.get()
		ripple.frame.Position = ring.Position
		ripple.frame.Size = UDim2.fromOffset(s.X + phase * 70, s.Y + phase * 70)
		ripple.stroke.Transparency = 1 - spot.alpha * (1 - phase)
	end

	-- La flecha da toquecitos desde el lado con sitio: los botones de los lados (el menú de la izquierda, una columna
	-- de botones) se señalan de costado, para no tapar el de al lado; los demás, desde arriba o desde abajo.
	local scale = hudScale.Scale
	local pointer = refs.pointer :: Frame
	local arrow, pill = refs.arrow :: TextLabel, refs.pill :: Frame
	local tap = math.abs(math.sin(now * 4.5)) * 18 * scale
	local half = 80 * scale
	pointer.Visible = spot.alpha > 0.3
	if centre.X < view.X * 0.25 or centre.X > view.X * 0.75 then
		local left = centre.X < view.X * 0.25 -- el botón está a la izquierda: la flecha va a su derecha
		local y = math.clamp(centre.Y, half, view.Y - half)
		local shift = (centre.Y - y) / scale
		pointer.AnchorPoint = Vector2.new(if left then 0 else 1, 0.5)
		pointer.Position = UDim2.fromOffset(if left then p.X + s.X + 4 + tap else p.X - 4 - tap, y)
		arrow.Text = if left then "◀" else "▶"
		arrow.Position = UDim2.new(if left then 0 else 1, if left then 55 else -55, 0.36, shift)
		pill.Position = UDim2.fromScale(0.5, 0.86)
	else
		-- Junto al borde el cartel se queda dentro de la pantalla y solo la punta se desvía hacia el botón.
		local x = math.clamp(centre.X, half, view.X - half)
		local shift = (centre.X - x) / scale
		local below = p.Y < view.Y * 0.28
		pointer.AnchorPoint = Vector2.new(0.5, if below then 0 else 1)
		pointer.Position = UDim2.fromOffset(x, if below then p.Y + s.Y + 4 + tap else p.Y - 4 - tap)
		arrow.Text = if below then "▲" else "▼"
		arrow.Position = if below then UDim2.new(0.5, shift, 0, 55) else UDim2.new(0.5, shift, 1, -55)
		pill.Position = UDim2.fromScale(0.5, if below then 0.86 else 0.15)
	end
end

local function hideWorld()
	if world then
		world.board.Enabled = false
		world.beam.Enabled = false
		world.glow.Enabled = false
		world.disc.Transparency = 1
	end
	refs.edge.Visible = false
end

local function updateWorld(info, now: number)
	local target, centre, halfHeight, radius = worldTarget(info.point)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (target and root and root.Position.Y > LOBBY_Y and not Ui.anyOpen()) then
		hideWorld()
		return
	end
	if not world then
		buildWorld()
	end
	local w = world :: { [string]: any }
	local bounce = math.sin(now * 6)
	w.board.Enabled = true
	local call = Ui.upper(Lang.t(nil, if string.sub(info.point, 1, 6) == "stall:" then "Go here!" else "Click!"))
	if w.label.Text ~= call then
		w.label.Text = call
	end
	w.anchor.CFrame = CFrame.new(centre + Vector3.new(0, halfHeight + 4 + bounce * 0.8, 0))
	w.pulse.Scale = 1 + 0.12 * math.abs(bounce)
	w.arrow.TextColor3 = GOLD:Lerp(WHITE, 0.5 + 0.5 * bounce)
	if w.glow.Adornee ~= target then
		w.glow.Adornee = target
	end
	w.glow.Enabled = true
	local pulse = 0.5 + 0.5 * math.sin(now * 5)
	w.glow.FillTransparency = 0.55 + 0.3 * pulse
	w.glow.OutlineTransparency = 0.1 * pulse
	-- Disco en el suelo que se abre y se desvanece.
	local phase = (now * 0.8) % 1
	local size = radius * 2 * (1 + phase * 0.8) + 2
	w.disc.Size = Vector3.new(0.2, size, size)
	w.disc.CFrame = CFrame.new(centre - Vector3.new(0, halfHeight - 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	w.disc.Transparency = 0.35 + 0.65 * phase
	-- La línea solo de lejos: pegado al objetivo estorba.
	w.beam.Enabled = (centre - root.Position).Magnitude > 12
	w.to.WorldPosition = centre
	w.from.WorldPosition = root.Position - Vector3.new(0, 2, 0)

	-- Flecha del borde si el objetivo no se ve.
	local camera = workspace.CurrentCamera
	local edge = refs.edge :: Frame
	local point, inFront = camera:WorldToViewportPoint(centre)
	local view = camera.ViewportSize
	local visible = inFront and point.X >= 0 and point.Y >= 0 and point.X <= view.X and point.Y <= view.Y
	edge.Visible = not visible
	if not visible then
		local middle = view / 2
		local direction = Vector2.new(point.X, point.Y) - middle
		if not inFront then
			direction = -direction
		end
		direction = if direction.Magnitude > 1 then direction.Unit else Vector2.new(0, 1)
		local margin = EDGE * hudScale.Scale
		local reach = math.huge
		if math.abs(direction.X) > 1e-3 then
			reach = math.min(reach, (middle.X - margin) / math.abs(direction.X))
		end
		if math.abs(direction.Y) > 1e-3 then
			reach = math.min(reach, (middle.Y - margin) / math.abs(direction.Y))
		end
		local at = middle + direction * (reach - math.abs(bounce) * 10)
		edge.Position = UDim2.fromOffset(at.X, at.Y)
		edge.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	end
end

local function stop()
	if loop then
		loop:Disconnect()
		loop = nil
	end
	hideSpotlight()
	hideWorld()
	refs.intro.Visible = false
	if world then
		world.folder:Destroy()
		world = nil
	end
end

local function tick(dt: number)
	local now = os.clock()
	local introOn = updateIntro(now)
	local info = step()
	if not info then
		hideSpotlight()
		hideWorld()
		if not introOn then
			stop()
		end
		return
	end
	local banner = refs.banner :: Frame
	-- Con una ventana abierta el cartel taparía su cabecera: se va, y dentro de la ventana guían el foco y la flecha.
	banner.Visible = not introOn and not Ui.anyOpen()
	banner.Position = UDim2.new(0.5, 0, 0, BANNER_TOP * hudScale.Scale)
	if not Performance.get() then
		refs.sweep.Offset = Vector2.new(-1 + 2 * math.clamp((now % 3.5) / 0.9, 0, 1), 0)
		refs.burst.Rotation = now * 30
		refs.badge.Rotation = math.sin(now * 2) * 6
	end
	local _, index = step()
	local current = refs.dots[index]
	if current then
		current.Size = UDim2.fromOffset(14, 14):Lerp(UDim2.fromOffset(18, 18), 0.5 + 0.5 * math.sin(now * 6))
	end

	if introOn then
		hideSpotlight()
		hideWorld()
	else
		updateSpotlight(guiTarget(info), now, dt)
		updateWorld(info, now)
	end

	-- Avisar al servidor cuando parece cumplido.
	if now - lastCheck > CHECK_EVERY and looksDone(info) then
		lastCheck = now
		Remotes.TutorialCheck:FireServer(info.id)
	end
end

local function play(list)
	pages = list
	pageStart = os.clock()
	if pages[1] then
		Sfx.play(pages[1].sound)
	end
	if not loop then
		loop = RunService.RenderStepped:Connect(tick)
	end
end

local function refresh()
	local info, index = step()
	local banner = refs.banner :: Frame
	if not info then
		banner.Visible = false
		if shown > 0 and not skipped then
			play({ { title = Lang.t(nil, "Tutorial complete!"), text = "", color = GREEN, duration = PAGE_END, sound = "collect" } })
		elseif loop and #pages == 0 then
			stop()
		end
		shown = 0
		return
	end
	refs.number.Text = tostring(index)
	refs.of.Text = `/{#cfg.Steps}`
	refs.text.Text = Lang.t(nil, info.text)
	for at, dot in refs.dots do
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = if at < index then GREEN elseif at == index then GOLD else Ui.COLORS.dark
	end
	local goal = info.goal or 1
	local counted = goal > 1
	refs.track.Visible = counted
	refs.text.Size = if counted then UDim2.new(1, -84 - 18, 0, 50) else UDim2.new(1, -84 - 18, 1, -40)
	if counted then
		local done = math.min(player:GetAttribute("TutorialCount") or 0, goal)
		local before = refs.amount.Text
		refs.amount.Text = `{done} / {goal}`
		TweenService:Create(refs.fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(done / goal, 1) }):Play()
		if before ~= refs.amount.Text and index == shown and not Performance.get() then
			refs.bump.Scale = 1.12
			TweenService:Create(refs.bump, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	-- Paso nuevo: intro a pantalla completa ("¡Muy bien!" si viene de cumplir otro).
	if index ~= shown then
		local list = {}
		if shown ~= 0 then
			table.insert(list, { title = Lang.t(nil, "Well done!"), text = "", color = GREEN, duration = PAGE_PRAISE, sound = "buyPing" })
		end
		table.insert(list, {
			title = Lang.t(nil, "Step {n}/{total}", { n = index, total = #cfg.Steps }),
			text = Lang.t(nil, info.text),
			color = GOLD,
			duration = PAGE_STEP,
			sound = "toast",
		})
		shown = index
		skipped = false
		play(list)
	end
end

function Tutorial.start()
	hudScale = Ui.hud():FindFirstChildOfClass("UIScale") :: UIScale
	layer = Instance.new("Frame")
	layer.Name = "Tutorial"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.Parent = Ui.screen()
	buildBanner()
	buildPointer()
	buildIntro()
	player:GetAttributeChangedSignal("Tutorial"):Connect(refresh)
	player:GetAttributeChangedSignal("TutorialCount"):Connect(refresh)
	refresh()
end

return Tutorial
