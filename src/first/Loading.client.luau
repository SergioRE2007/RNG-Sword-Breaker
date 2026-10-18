-- Pantalla de carga (pedida por el usuario): tapa el juego mientras entra y se quita sola cuando todo está listo.
-- Va en ReplicatedFirst, que es lo primero que llega al cliente: por eso no puede usar client/Ui ni nada de
-- ReplicatedStorage al arrancar, y se hace sus propias piezas con el mismo estilo (FredokaOne, borde negro, degradado).
-- Dos fases: primero lo imprescindible (el juego replicado, los datos del jugador y el HUD montado) y después las
-- imágenes y los sonidos, que se pueden esperar jugando: en cuanto acaba la primera sale el botón "Saltar".
-- Se cierra sola (se funde con un destello) al acabar la segunda o a los MAX_WAIT segundos, para no dejar parado a quien vuelve de una
-- reconexión por inactividad sin estar delante.
-- Rehecha porque al usuario le parecía sosa: ruleta de casillas de rareza que gira mientras carga y cae en una al
-- terminar, objetos que suben flotando por el fondo, rayos que cambian de color y brillos en el título y la barra.
local ContentProvider = game:GetService("ContentProvider")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MIN_TIME = 2 -- segundos como mínimo a la vista, para que no sea un parpadeo
local MAX_WAIT = 10 -- segundos como mucho precargando imágenes y sonidos una vez que ya se puede jugar (lo que falte carga jugando)
local TIP_TIME = 4 -- segundos que dura cada consejo
local BATCH = 12 -- piezas por tanda de precarga (cada tanda mueve la barra)
local ESSENTIAL = 0.5 -- parte de la barra que ocupa la primera fase

-- Ruleta: casillas de CELL px separadas STEP, a SPEED px/s; al cerrar frena en LAND_TIME s y la elegida late POP_TIME s.
local CELL = 72
local STEP = 86
local SPEED = 420
local LAND_TIME = 0.8
local POP_TIME = 0.4
local EXIT_TIME = 0.45 -- segundos que tarda en fundirse al irse
local FLOATERS = 14 -- objetos que suben por el fondo

-- Imágenes de Ui.IMAGES (Ui aún no ha llegado): espada, rayos y rombos, y las de las casillas y el fondo.
local SWORD = "rbxassetid://100527116629167"
local RAYS = "rbxassetid://123487236385810"
local PATTERN = "rbxassetid://127373214598364"
local ICONS = {
	"rbxassetid://100527116629167", -- espada
	"rbxassetid://134320261318517", -- monedas
	"rbxassetid://86307416552518", -- gemas
	"rbxassetid://83278150749876", -- cristal_rasgo
	"rbxassetid://127096179789432", -- cristal_grado
	"rbxassetid://108469951057641", -- potion_weaponLuck_3
	"rbxassetid://121532166515323", -- potion_damage_3
	"rbxassetid://91743584320580", -- objetos
	"rbxassetid://79526781719923", -- acc_trebol
	"rbxassetid://117216600465188", -- acc_corona_dorada
}

-- Colores de las ocho primeras rarezas de Config.RarityTiers (Común … Divina) y cuánto sale cada una en la ruleta.
local TIERS = {
	{ color = Color3.fromRGB(190, 195, 205), weight = 30 },
	{ color = Color3.fromRGB(90, 220, 100), weight = 24 },
	{ color = Color3.fromRGB(70, 150, 255), weight = 18 },
	{ color = Color3.fromRGB(180, 90, 255), weight = 12 },
	{ color = Color3.fromRGB(255, 190, 40), weight = 7 },
	{ color = Color3.fromRGB(255, 70, 70), weight = 4 },
	{ color = Color3.fromRGB(255, 90, 210), weight = 3 },
	{ color = Color3.fromRGB(120, 255, 240), weight = 2 },
}
local LAND_FROM = 4 -- la casilla en la que cae es de esta rareza o mejor

local TOP = Color3.fromRGB(74, 48, 140)
local BOTTOM = Color3.fromRGB(22, 16, 48)
local DARK = Color3.fromRGB(18, 14, 36)
local GOLD = Color3.fromRGB(255, 205, 60)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- Consejos, en inglés: pasan por Lang.t cuando llega (su español, en shared/LangEs).
local TIPS = {
	"Break the objects in your plot to get weapons!",
	"Rarer objects drop rarer weapons.",
	"Leave your spare weapons in the Gold Bag to earn coins.",
	"Dungeons drop armor and crystals.",
	"Daily missions give tickets for the Shop.",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local random = Random.new()

ReplicatedFirst:RemoveDefaultLoadingScreen()

local function text(parent: Instance, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = WHITE
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = math.clamp(size / 10, 2, 5)
	stroke.Parent = label
	return label
end

local function round(item: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = item
end

local function gradient(item: Instance, top: Color3, bottom: Color3): UIGradient
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(top, bottom)
	fill.Rotation = 90
	fill.Parent = item
	return fill
end

local function outline(item: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = item
	return stroke
end

local function image(parent: Instance, name: string, id: string, size: number): ImageLabel
	local item = Instance.new("ImageLabel")
	item.Name = name
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Size = UDim2.fromOffset(size, size)
	item.BackgroundTransparency = 1
	item.Image = id
	item.Parent = parent
	return item
end

-- Banda de brillo que cruza algo de lado a lado (se mueve con Offset): transparente salvo en el centro.
local function shine(item: Instance, rotation: number): UIGradient
	local band = Instance.new("UIGradient")
	band.Rotation = rotation
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = item
	return band
end

local function pickTier(from: number?): number
	local total = 0
	for index = from or 1, #TIERS do
		total += TIERS[index].weight
	end
	local roll = random:NextNumber() * total
	for index = from or 1, #TIERS do
		roll -= TIERS[index].weight
		if roll <= 0 then
			return index
		end
	end
	return #TIERS
end

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000 -- por encima del Hud y de la pantalla de Mejoras
gui.AutoLocalize = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Un Frame y no un CanvasGroup: allí el degradado del fondo teñía de morado todo lo de dentro y no llegaba a tapar
-- la pantalla entera (lo vio el usuario).
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = WHITE
root.BorderSizePixel = 0
root.Active = true -- los clics no llegan al juego de debajo
root.ClipsDescendants = true
root.Parent = gui
gradient(root, TOP, BOTTOM)

-- Rombos que se deslizan en diagonal (un poco más grande que la pantalla para que no se vea el borde al moverse).
local pattern = Instance.new("ImageLabel")
pattern.Name = "Pattern"
pattern.Size = UDim2.new(1, 96, 1, 96)
pattern.BackgroundTransparency = 1
pattern.Image = PATTERN
pattern.ImageTransparency = 0.93
pattern.ScaleType = Enum.ScaleType.Tile
pattern.TileSize = UDim2.fromOffset(96, 96)
pattern.Parent = root

-- Objetos del juego que suben despacio por el fondo, girando un poco.
local floaters = Instance.new("Frame")
floaters.Name = "Floaters"
floaters.Size = UDim2.fromScale(1, 1)
floaters.BackgroundTransparency = 1
floaters.Parent = root
local floating = {}
for index = 1, FLOATERS do
	local item = image(floaters, "Floater", ICONS[(index - 1) % #ICONS + 1], random:NextInteger(44, 78))
	item.ImageTransparency = 0.55
	table.insert(floating, {
		item = item,
		x = random:NextNumber(0.03, 0.97),
		y = random:NextNumber(0, 1.2), -- repartidos por toda la pantalla desde el principio
		speed = random:NextNumber(0.045, 0.085), -- pantallas por segundo
		spin = random:NextNumber(-25, 25),
		sway = random:NextNumber(0, math.pi * 2),
	})
end

-- Viñeta: arriba y abajo más oscuros, para que el centro destaque.
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = BLACK
vignette.BorderSizePixel = 0
vignette.Parent = root
local shade = Instance.new("UIGradient")
shade.Rotation = 90
shade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(0.3, 1),
	NumberSequenceKeypoint.new(0.7, 1),
	NumberSequenceKeypoint.new(1, 0.35),
})
shade.Parent = vignette

-- El contenido va en una caja centrada de tamaño fijo que un UIScale encoge en pantallas pequeñas.
local box = Instance.new("Frame")
box.Name = "Box"
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.fromScale(0.5, 0.5)
box.Size = UDim2.fromOffset(640, 566)
box.BackgroundTransparency = 1
box.Parent = root
local scale = Instance.new("UIScale")
scale.Parent = box
local function fit()
	local size = root.AbsoluteSize
	scale.Scale = math.clamp(math.min(size.X / 700, size.Y / 630), 0.4, 1.4)
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local LOGO_Y = 108
local rays = image(box, "Rays", RAYS, 420)
rays.Position = UDim2.new(0.5, 0, 0, LOGO_Y)
rays.ImageColor3 = GOLD
rays.ImageTransparency = 0.7
local raysBack = image(box, "RaysBack", RAYS, 330)
raysBack.Position = rays.Position
raysBack.ImageTransparency = 0.78

local sword = image(box, "Logo", SWORD, 190)
sword.Position = UDim2.new(0.5, 0, 0, LOGO_Y)
sword.ZIndex = 2

local title = text(box, 62)
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 198)
title.Size = UDim2.new(1, 0, 0, 70)
title.Text = "RNG: SWORD BREAKER" -- el nombre del juego, igual en todos los idiomas
title.ZIndex = 3
gradient(title, WHITE, GOLD)
-- El brillo va en una copia blanca del título encima (sin borde): un degradado en el propio título le quitaría el dorado.
local titleShine = Instance.new("TextLabel")
titleShine.Name = "Shine"
titleShine.BackgroundTransparency = 1
titleShine.Font = title.Font
titleShine.TextSize = title.TextSize
titleShine.TextColor3 = WHITE
titleShine.Text = title.Text
titleShine.Size = UDim2.fromScale(1, 1)
titleShine.ZIndex = 4
titleShine.Parent = title
local titleBand = shine(titleShine, 20)

-- Ruleta: ventana oscura con las casillas pasando y un marco dorado en el centro.
local ROULETTE_W = 500
local ROULETTE_H = 96
local roulette = Instance.new("Frame")
roulette.Name = "Roulette"
roulette.AnchorPoint = Vector2.new(0.5, 0)
roulette.Position = UDim2.new(0.5, 0, 0, 284)
roulette.Size = UDim2.fromOffset(ROULETTE_W, ROULETTE_H)
roulette.BackgroundColor3 = DARK
roulette.BorderSizePixel = 0
roulette.ClipsDescendants = true
roulette.ZIndex = 5
roulette.Parent = box
round(roulette, 16)
outline(roulette, BLACK, 4)

local cells = {}
local count = math.ceil(ROULETTE_W / STEP) + 2
local function paint(cell, tier: number)
	cell.tier = tier
	cell.fill.Color = ColorSequence.new(TIERS[tier].color:Lerp(WHITE, 0.25), TIERS[tier].color:Lerp(BLACK, 0.35))
	cell.icon.Image = ICONS[random:NextInteger(1, #ICONS)]
end
for index = 0, count - 1 do
	local frame = Instance.new("Frame")
	frame.Name = "Cell"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(CELL, CELL)
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.ZIndex = 6
	frame.Parent = roulette
	round(frame, 12)
	outline(frame, BLACK, 3)
	local gloss = Instance.new("Frame") -- brillo de arriba, como en Ui.cell
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(5, 4)
	gloss.Size = UDim2.new(1, -10, 0.36, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 7
	gloss.Parent = frame
	round(gloss, 8)
	local icon = image(frame, "Icon", ICONS[1], CELL - 18)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 8
	local pop = Instance.new("UIScale")
	pop.Parent = frame
	local cell = { frame = frame, fill = gradient(frame, WHITE, WHITE), icon = icon, pop = pop, slot = index, tier = 1 }
	paint(cell, pickTier())
	table.insert(cells, cell)
end

-- Bordes de la ventana que se funden con el fondo, para que las casillas entren y salgan suaves.
for _, side in { 0, 1 } do
	local edge = Instance.new("Frame")
	edge.Name = if side == 0 then "FadeLeft" else "FadeRight"
	edge.AnchorPoint = Vector2.new(side, 0)
	edge.Position = UDim2.fromScale(side, 0)
	edge.Size = UDim2.new(0, 90, 1, 0)
	edge.BackgroundColor3 = DARK
	edge.BorderSizePixel = 0
	edge.ZIndex = 9
	edge.Parent = roulette
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new(side, 1 - side)
	fade.Parent = edge
end

-- Marco del centro (fuera de la ventana, para que no lo recorte) con una flecha arriba y otra abajo.
local selector = Instance.new("Frame")
selector.Name = "Selector"
selector.AnchorPoint = Vector2.new(0.5, 0.5)
selector.Position = UDim2.new(0.5, 0, 0, 284 + ROULETTE_H / 2)
selector.Size = UDim2.fromOffset(CELL + 12, CELL + 12)
selector.BackgroundTransparency = 1
selector.ZIndex = 10
selector.Parent = box
round(selector, 14)
local selectorStroke = outline(selector, GOLD, 4)
local selectorScale = Instance.new("UIScale")
selectorScale.Parent = selector
for _, up in { true, false } do
	local arrow = text(selector, 30)
	arrow.Name = if up then "ArrowTop" else "ArrowBottom"
	arrow.AnchorPoint = Vector2.new(0.5, if up then 1 else 0)
	arrow.Position = UDim2.fromScale(0.5, if up then 0.06 else 0.94)
	arrow.Size = UDim2.fromOffset(30, 26)
	arrow.Text = if up then "▼" else "▲"
	arrow.TextColor3 = GOLD
	arrow.ZIndex = 11
end

-- Destello de la casilla en la que cae la ruleta.
local burst = image(box, "Burst", RAYS, 150)
burst.Position = selector.Position
burst.ImageTransparency = 1
burst.ZIndex = 9

-- Barra de progreso: canal oscuro con borde negro y relleno dorado, con un brillo que la recorre y una chispa en la punta.
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 404)
bar.Size = UDim2.fromOffset(460, 30)
bar.BackgroundColor3 = DARK
bar.BorderSizePixel = 0
bar.Parent = box
round(bar, 15)
outline(bar, BLACK, 4)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0.04, 1)
fill.BackgroundColor3 = WHITE
fill.BorderSizePixel = 0
fill.ClipsDescendants = true
fill.Parent = bar
round(fill, 15)
gradient(fill, Color3.fromRGB(255, 232, 120), Color3.fromRGB(255, 150, 40))
local fillShine = Instance.new("Frame")
fillShine.Name = "Shine"
fillShine.Size = UDim2.fromScale(1, 1)
fillShine.BackgroundColor3 = WHITE
fillShine.BorderSizePixel = 0
fillShine.Parent = fill
local fillBand = shine(fillShine, 0)
local spark = Instance.new("Frame")
spark.Name = "Spark"
spark.AnchorPoint = Vector2.new(0.5, 0.5)
spark.Size = UDim2.fromOffset(16, 16)
spark.BackgroundColor3 = Color3.fromRGB(255, 250, 220)
spark.BorderSizePixel = 0
spark.ZIndex = 3
spark.Parent = bar
outline(spark, BLACK, 2)
local percent = text(bar, 20)
percent.Name = "Percent"
percent.Size = UDim2.fromScale(1, 1)
percent.Text = "0%"
percent.ZIndex = 4

local status = text(box, 24)
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0, 442)
status.Size = UDim2.new(1, 0, 0, 30)

local tip = text(box, 20)
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 0)
tip.Position = UDim2.new(0.5, 0, 0, 476)
tip.Size = UDim2.new(1, 0, 0, 26)
tip.TextColor3 = Color3.fromRGB(205, 200, 235)
tip.Text = ""

-- Botón "Saltar": sale cuando ya se puede jugar. Con labio oscuro abajo, como los de Ui.button.
local skip = Instance.new("TextButton")
skip.Name = "Skip"
skip.AnchorPoint = Vector2.new(0.5, 0)
skip.Position = UDim2.new(0.5, 0, 0, 512)
skip.Size = UDim2.fromOffset(200, 52)
skip.BackgroundColor3 = WHITE
skip.BorderSizePixel = 0
skip.AutoButtonColor = false
skip.Text = ""
skip.Visible = false
skip.Parent = box
round(skip, 12)
gradient(skip, Color3.fromRGB(110, 225, 95), Color3.fromRGB(40, 160, 60))
outline(skip, BLACK, 4)
-- El texto va en una etiqueta aparte: escrito en el botón, su degradado verde lo teñía.
local skipText = text(skip, 28)
skipText.Name = "Label"
skipText.Size = UDim2.fromScale(1, 1)
local skipScale = Instance.new("UIScale")
skipScale.Parent = skip

fit()
gui.Parent = playerGui

-- Textos: hasta que llega Lang solo se sabe el idioma de la cuenta, y solo hace falta una palabra.
local Lang = nil
local function say(phrase: string): string
	if Lang then
		return Lang.t(nil, phrase)
	end
	return if phrase == "Loading" and string.sub(LocalizationService.RobloxLocaleId, 1, 2) == "es" then "Cargando" else phrase
end

local started = os.clock()
local progress, shown = 0.04, 0.04
local closing = false
local skipped = false
local tipAt, tipIndex = 0, 0
local offset = 0 -- cuánto ha avanzado la ruleta, en px
local landing = nil -- { from, to, at }: la ruleta frenando hasta dejar una casilla en el centro

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Color de los rayos: pasa despacio por las rarezas.
local function tierColor(now: number): Color3
	local at = now * 0.35
	local index = math.floor(at) % #TIERS + 1
	return TIERS[index].color:Lerp(TIERS[index % #TIERS + 1].color, at % 1)
end

-- Un solo bucle mientras la pantalla existe: fondo, rayos, logo, ruleta, barra, puntos de "Cargando" y consejos.
local loop
loop = RunService.RenderStepped:Connect(function(dt)
	local now = os.clock() - started

	pattern.Position = UDim2.fromOffset(-(now * 14) % 96, -(now * 14) % 96)
	for _, floater in floating do
		floater.y -= floater.speed * dt
		if floater.y < -0.12 then
			floater.y, floater.x = 1.12, random:NextNumber(0.03, 0.97)
		end
		floater.item.Position = UDim2.new(floater.x, math.sin(now * 0.8 + floater.sway) * 18, floater.y, 0)
		floater.item.Rotation = math.sin(now * 0.6 + floater.sway) * floater.spin
	end

	rays.Rotation = now * 24
	raysBack.Rotation = -now * 16
	raysBack.ImageColor3 = tierColor(now)
	sword.Rotation = math.sin(now * 2.2) * 6
	sword.Position = UDim2.new(0.5, 0, 0, LOGO_Y + math.sin(now * 3) * 6)
	titleBand.Offset = Vector2.new((now % 3.2) / 3.2 * 2.6 - 1.3, 0)

	-- Ruleta: cada casilla tiene su hueco (slot); al salir por la izquierda pasa al final con otra rareza.
	if landing then
		local t = math.min((os.clock() - landing.at) / LAND_TIME, 1)
		offset = landing.from + (landing.to - landing.from) * easeOut(t)
	else
		offset += SPEED * dt
	end
	for _, cell in cells do
		local x = cell.slot * STEP - offset + ROULETTE_W / 2
		if x < -STEP then
			cell.slot += count
			x += count * STEP
			paint(cell, pickTier())
		end
		cell.frame.Position = UDim2.new(0, x, 0.5, 0)
	end
	if not landing then
		selectorScale.Scale = 1 + math.sin(now * 6) * 0.03
	end

	shown += (progress - shown) * math.min(dt * 6, 1)
	fill.Size = UDim2.fromScale(math.max(shown, 0.04), 1)
	fillBand.Offset = Vector2.new((now % 1.6) / 1.6 * 2.6 - 1.3, 0)
	spark.Position = UDim2.fromScale(math.max(shown, 0.04), 0.5)
	spark.Rotation = 45 + now * 180
	percent.Text = `{math.floor(shown * 100 + 0.5)}%`
	if not closing then
		status.Text = say("Loading") .. string.rep(".", math.floor(now * 2.5) % 4)
	end
	if Lang and now >= tipAt then
		tipAt = now + TIP_TIME
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = Lang.t(nil, TIPS[tipIndex])
	end
	if skip.Visible then
		skipScale.Scale = 1 + math.sin(now * 5) * 0.03
	end
end)

-- La ruleta frena y cae en una casilla buena, que late con un destello de su color.
local function land()
	local target = (math.ceil(offset / STEP) + 3) * STEP
	local slot = target / STEP
	local chosen = nil
	for _, cell in cells do
		if cell.slot == slot then
			chosen = cell
		end
	end
	if chosen then
		paint(chosen, pickTier(LAND_FROM))
	end
	landing = { from = offset, to = target, at = os.clock() }
	task.wait(LAND_TIME)
	if not chosen then
		return
	end
	local color = TIERS[chosen.tier].color
	selectorStroke.Color = color
	burst.ImageColor3 = color
	burst.ImageTransparency = 0.15
	burst.Size = UDim2.fromOffset(110, 110)
	local quick = TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(chosen.pop, quick, { Scale = 1.22 }):Play()
	TweenService:Create(selectorScale, quick, { Scale = 1.2 }):Play()
	TweenService:Create(burst, TweenInfo.new(POP_TIME + 0.2), { ImageTransparency = 1, Size = UDim2.fromOffset(260, 260), Rotation = 60 }):Play()
	task.wait(POP_TIME)
end

-- Salida (pedida por el usuario: irse hacia arriba quedaba feísimo): destello blanco, el contenido se acerca un poco y
-- todo se funde a transparente. Como Root es un Frame y no un CanvasGroup, se funde pieza a pieza desde su valor.
local function exit()
	root.Active = false -- se puede jugar mientras se funde
	local faded = {}
	local function remember(item: Instance, property: string)
		local value = (item :: any)[property]
		if value < 1 then
			table.insert(faded, { item = item, property = property, from = value })
		end
	end
	for _, item in { root, unpack(root:GetDescendants()) } do
		if item:IsA("GuiObject") then
			remember(item, "BackgroundTransparency")
		end
		if item:IsA("ImageLabel") then
			remember(item, "ImageTransparency")
		elseif item:IsA("TextLabel") or item:IsA("TextButton") then
			remember(item, "TextTransparency")
		elseif item:IsA("UIStroke") then
			remember(item, "Transparency")
		end
	end
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 0.35
	flash.BorderSizePixel = 0
	flash.ZIndex = 20
	flash.Parent = root
	local fitted = scale.Scale
	local begin = os.clock()
	while true do
		local t = math.min((os.clock() - begin) / EXIT_TIME, 1)
		local alpha = t * t
		for _, entry in faded do
			(entry.item :: any)[entry.property] = entry.from + (1 - entry.from) * alpha
		end
		flash.BackgroundTransparency = 0.35 + 0.65 * math.min(t * 2, 1)
		scale.Scale = fitted * (1 + 0.15 * easeOut(t))
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function close()
	if closing then
		return
	end
	closing = true
	progress = 1
	skip.Visible = false
	local wait = MIN_TIME - (os.clock() - started)
	if wait > 0 and not skipped then
		task.wait(wait)
	end
	if not skipped then
		status.Text = say("Let's go!")
		land()
	end
	exit()
	loop:Disconnect()
	gui:Destroy()
end

skip.Activated:Connect(function()
	skipped = true
	close()
end)

-- Fase 1: lo imprescindible para jugar.
if not game:IsLoaded() then
	game.Loaded:Wait()
end
progress = 0.2
Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
tipIndex = math.random(#TIPS) -- empieza por un consejo cualquiera
while player:GetAttribute("Coins") == nil do -- los datos del jugador ya están cargados y publicados
	task.wait(0.1)
end
progress = 0.35
local hud = playerGui:WaitForChild("Hud")
hud:WaitForChild("HudRoot")
progress = ESSENTIAL

skipText.Text = string.upper(Lang.t(nil, "Skip"))
skip.Visible = true

-- Fase 2: imágenes de la interfaz y sonidos, por tandas. Se deja a medias si el jugador salta o tarda demasiado.
local assets = {}
for _, item in hud:GetDescendants() do
	if item:IsA("ImageLabel") or item:IsA("ImageButton") then
		table.insert(assets, item)
	end
end
local bank = SoundService:FindFirstChild("SfxBank")
if bank then
	for _, sound in bank:GetChildren() do
		table.insert(assets, sound)
	end
end
local readyAt = os.clock()
for first = 1, #assets, BATCH do
	if closing or os.clock() - readyAt > MAX_WAIT then
		break
	end
	local batch = table.move(assets, first, math.min(first + BATCH - 1, #assets), 1, {})
	pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	progress = ESSENTIAL + (1 - ESSENTIAL) * math.min((first + BATCH - 1) / #assets, 1)
end
close()
