-- Tienda de pases de juego (botón "Tienda" del menú): una tarjeta por pase de Config.Gamepasses, en rejilla de
-- tres columnas. Cada tarjeta lleva arriba su "escaparate" (del color del pase, como los botones del menú: rombos
-- que se desplazan, rayos que giran, el logo grande del pase y copias pequeñas del logo cayendo por detrás, con su
-- etiqueta gorda "x2", "VIP"...), el nombre, lo que da y el botón de compra. Al pasar el ratón la tarjeta crece, el
-- logo salta y todo se acelera; al comprar, la tarjeta da un bote y suelta destellos.
-- La compra la hace Roblox (MarketplaceService); el servidor (server/Passes) publica cuáles tiene el jugador en los
-- atributos "Pass_<clave>". Al lado del botón de Robux va el de tickets de misión (Stats.ticketPrice; BuyPassTickets):
-- pide confirmar con un segundo toque, y los tickets que se tienen salen en la cabecera (Header.Tickets).
-- La ventana va por secciones, cada una con su cinta (pedido por el usuario): arriba "Tiradas x999", los packs de Trébol
-- de la suerte de Config.Products en fichas apaisadas (Passes.Clovers.Product_<clave>.Card: se compran las veces que se
-- quiera, solo con Robux, server/Products), luego "Pases de juego" (Passes.Grid.Pass_<clave>) y abajo "Códigos"
-- (Passes.Codes: caja Box y botón Redeem; RedeemCode, server/Codes).
-- Capas: todo va en la capa por defecto (la interfaz ordena el ZIndex globalmente), así que manda el orden en que
-- se crean las piezas de cada tarjeta: fondo, escaparate (rombos, lluvia, rayos, canto, logo, etiqueta, cinta),
-- textos y botón.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local PassShop = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ROBUX = Color3.fromRGB(70, 215, 120)
local GOLD = Color3.fromRGB(255, 225, 90)
local TICKET = Color3.fromRGB(255, 170, 40) -- botón y contador de tickets
local CONFIRM_TIME = 3 -- segundos que dura el "¿Seguro?" del botón de tickets
local ROBUX_SIGN = "\u{E002}" -- el símbolo de Robux: un carácter propio de Roblox, que pintan todas sus fuentes

-- Medidas de la tarjeta (píxeles de diseño: la ventana entera se encoge con su UIScale).
local COLUMNS = 3
local GAP = 12
local CARD_HEIGHT = 324
local SHOWN_ROWS = 2 -- filas de tarjetas a la vista; las demás, deslizando
local PEEK = 46 -- lo que asoma de la fila siguiente cuando hay más
local HEAD_HEIGHT = 44 -- cinta con el nombre de cada sección
local TILE_HEIGHT = 132 -- fichas de los tréboles
local CODES_HEIGHT = 222 -- panel de los códigos
local CODES_LEFT = 250 -- donde empieza su texto, a la derecha del icono
local PAD = 8 -- margen de la tarjeta
local ART_HEIGHT = 130 -- alto del escaparate
local ART_RADIUS = 10
local RIM = 3 -- canto claro del escaparate; el recorte de dentro va metido esto mismo
local ICON = 116 -- lado del logo grande
local TILE = 40 -- periodo de los rombos del escaparate
local DROPS = 7 -- logos pequeños que caen por tarjeta
local HOVER = 1.04 -- lo que crece la tarjeta con el ratón encima

-- Tickets con todas sus cifras ("2.997"): abreviado ("2.99K") no se sabe cuántos faltan.
local function count(amount: number): string
	if amount ~= amount or amount >= 1e9 then
		return Format.short(amount)
	end
	local text = tostring(math.floor(amount))
	while true do
		local grouped, changed = string.gsub(text, "^(%d+)(%d%d%d)", "%1.%2")
		text = grouped
		if changed == 0 then
			return text
		end
	end
end

local function ease(target: Instance, time: number, style: Enum.EasingStyle, goal)
	TweenService:Create(target, TweenInfo.new(time, style, Enum.EasingDirection.Out), goal):Play()
end

-- Escaparate de un pase. Devuelve lo que anima el bucle de la tienda.
local function buildArt(card: Frame, pass)
	local color = pass.color
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.Position = UDim2.fromOffset(PAD, PAD)
	art.Size = UDim2.new(1, -PAD * 2, 0, ART_HEIGHT)
	art.BackgroundColor3 = WHITE
	art.BorderSizePixel = 0
	art.Parent = card
	Ui.round(art, ART_RADIUS)
	Ui.stroke(art, BLACK, 3)
	Ui.gradient(art, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.3), 90)

	-- Recorte rectangular (ClipsDescendants no entiende de esquinas redondas) metido lo que mide el canto claro,
	-- que tapa sus picos: dentro van los rombos, la lluvia de logos y los rayos.
	local clip = Instance.new("Frame")
	clip.Name = "Clip"
	clip.Position = UDim2.fromOffset(RIM, RIM)
	clip.Size = UDim2.new(1, -RIM * 2, 1, -RIM * 2)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = art
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Tiles"
	pattern.Size = UDim2.new(1, TILE, 1, TILE)
	pattern.BackgroundTransparency = 1
	pattern.Image = Ui.IMAGES.boton_patron
	pattern.ImageTransparency = 0.6
	pattern.ScaleType = Enum.ScaleType.Tile
	pattern.TileSize = UDim2.fromOffset(TILE * 2, TILE * 2)
	pattern.Parent = clip

	-- Lluvia: copias pequeñas del logo que caen, cada una a su ritmo. En modo rendimiento se quedan quietas.
	local drops = {}
	local height = ART_HEIGHT - RIM * 2
	for index = 1, DROPS do
		local size = math.random(20, 34)
		local image = Instance.new("ImageLabel")
		image.Name = "Drop" .. index
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Size = UDim2.fromOffset(size, size)
		image.BackgroundTransparency = 1
		image.Image = Ui.IMAGES[pass.icon]
		image.ImageTransparency = 0.3
		image.Rotation = math.random(-25, 25)
		image.Parent = clip
		local drop = {
			image = image,
			size = size,
			x = (index - 0.5) / DROPS + (math.random() - 0.5) * 0.08, -- repartidas a lo ancho, no amontonadas
			y = math.random() * (height + size * 2) - size,
			speed = 22 + math.random() * 30,
			spin = (math.random() - 0.5) * 120,
			phase = math.random() * 6,
		}
		image.Position = UDim2.new(drop.x, 0, 0, drop.y)
		drops[index] = drop
	end

	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(ART_HEIGHT * 1.9, ART_HEIGHT * 1.9)
	rays.BackgroundTransparency = 1
	rays.Image = Ui.IMAGES.boton_rayos
	rays.ImageColor3 = color:Lerp(WHITE, 0.8)
	rays.ImageTransparency = 0.5
	rays.Parent = clip

	-- Canto claro por dentro del borde negro, más luminoso arriba.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(RIM, RIM)
	rim.Size = UDim2.new(1, -RIM * 2, 1, -RIM * 2)
	rim.BackgroundTransparency = 1
	rim.Parent = art
	Ui.round(rim, ART_RADIUS - RIM)
	local rimStroke = Ui.stroke(rim, WHITE, RIM)
	Ui.gradient(rimStroke :: any, color:Lerp(WHITE, 0.75), color:Lerp(WHITE, 0.25), 90)

	local iconRest = UDim2.fromScale(0.5, 0.5)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = iconRest
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.BackgroundTransparency = 1
	icon.Parent = art
	Ui.image(icon, pass.icon)
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon

	-- Destellos alrededor del logo: laten por turnos.
	local twinkles = {}
	for index, spot in { { 0.14, 0.24, 20 }, { 0.87, 0.2, 16 }, { 0.2, 0.8, 14 }, { 0.72, 0.5, 12 } } do
		local star = Instance.new("ImageLabel")
		star.Name = "Twinkle" .. index
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(spot[1], spot[2])
		star.Size = UDim2.fromOffset(spot[3], spot[3])
		star.BackgroundTransparency = 1
		star.Image = Ui.IMAGES.boton_destello
		star.Parent = art
		twinkles[index] = { image = star, size = spot[3], phase = index * 1.7 }
	end

	-- Etiqueta gorda ("x2", "VIP"...), abajo a la derecha y algo torcida, pisando el logo.
	local tag = Ui.label(art, 40)
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(1, 1)
	tag.Position = UDim2.new(1, -8, 1, -2)
	tag.Size = UDim2.fromOffset(110, 44)
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.Rotation = -7
	tag.Text = Lang.t(nil, pass.tag)
	Ui.gradient(tag, WHITE, GOLD, 90)
	local tagStroke = tag:FindFirstChildOfClass("UIStroke")
	if tagStroke then
		tagStroke.Thickness = 4
	end
	local tagScale = Instance.new("UIScale")
	tagScale.Parent = tag

	-- Cinta opcional ("POPULAR"), arriba a la izquierda, asomando por fuera del escaparate.
	if pass.ribbon then
		local ribbon = Instance.new("Frame")
		ribbon.Name = "Ribbon"
		ribbon.AnchorPoint = Vector2.new(0, 0.5)
		ribbon.Position = UDim2.fromOffset(-6, 12)
		ribbon.Size = UDim2.fromOffset(0, 24)
		ribbon.AutomaticSize = Enum.AutomaticSize.X
		ribbon.BackgroundColor3 = WHITE
		ribbon.BorderSizePixel = 0
		ribbon.Rotation = -5
		ribbon.Parent = art
		Ui.round(ribbon, 7)
		Ui.stroke(ribbon, BLACK, 3)
		Ui.gradient(ribbon, Color3.fromRGB(255, 110, 110), Color3.fromRGB(215, 40, 70), 90)
		local text = Ui.label(ribbon, 15)
		text.Name = "Text"
		text.Size = UDim2.fromOffset(0, 24)
		text.AutomaticSize = Enum.AutomaticSize.X
		text.Text = Lang.t(nil, pass.ribbon)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 9)
		padding.PaddingRight = UDim.new(0, 9)
		padding.Parent = ribbon
	end

	return {
		pattern = pattern,
		drops = drops,
		height = height,
		rays = rays,
		icon = icon,
		iconRest = iconRest,
		iconScale = iconScale,
		twinkles = twinkles,
		tagScale = tagScale,
		phase = math.random() * 6,
		time = 0,
		scroll = 0,
		boost = 0, -- 0 en reposo, 1 con el ratón encima (va y vuelve suave)
		over = false,
		kick = 0, -- segundos desde que entró el ratón: el meneo del logo
	}
end

-- Un fotograma de la animación de un escaparate.
local function stepArt(art, dt: number)
	art.boost += ((if art.over then 1 else 0) - art.boost) * math.min(1, dt * 9)
	art.time += dt
	art.kick += dt
	local boost, time = art.boost, art.time
	art.scroll = (art.scroll + dt * (12 + 46 * boost)) % TILE
	art.pattern.Position = UDim2.fromOffset(-art.scroll, -art.scroll)
	art.rays.Rotation = (art.rays.Rotation + dt * (22 + 80 * boost)) % 360
	art.rays.ImageTransparency = 0.5 - 0.22 * boost
	-- El logo flota; con el ratón encima da un meneo que se apaga, crece y bota.
	local shake = math.exp(-5 * art.kick) * math.sin(art.kick * 24) * 12 * boost
	art.icon.Rotation = math.sin(time * 1.9 + art.phase) * 4 + shake
	art.icon.Position = art.iconRest + UDim2.fromOffset(0, math.sin(time * 2.6 + art.phase) * 3 - math.abs(math.sin(time * 5)) * 5 * boost)
	art.iconScale.Scale = 1 + 0.14 * boost
	art.tagScale.Scale = 1 + 0.05 * math.sin(time * 4 + art.phase) + 0.12 * boost
	for _, drop in art.drops do
		drop.y += drop.speed * (1 + 2.2 * boost) * dt
		if drop.y > art.height + drop.size then
			drop.y = -drop.size
			drop.x = math.clamp(drop.x + (math.random() - 0.5) * 0.2, 0.04, 0.96)
		end
		drop.image.Position = UDim2.new(drop.x, math.sin(time * 1.6 + drop.phase) * 7, 0, drop.y)
		drop.image.Rotation += drop.spin * dt
	end
	for _, twinkle in art.twinkles do
		local size = math.max(math.sin(time * (3 + 2 * boost) + twinkle.phase), 0) * twinkle.size * (1 + 0.5 * boost)
		twinkle.image.Size = UDim2.fromOffset(size, size)
		twinkle.image.Rotation = time * 50 + twinkle.phase * 40
	end
end

-- Celebración al conseguir un pase: la tarjeta da un bote y suelta destellos hacia fuera.
local function celebrate(entry)
	if Performance.get() then
		return
	end
	entry.scale.Scale = 1.14
	ease(entry.scale, 0.5, Enum.EasingStyle.Elastic, { Scale = 1 })
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2 + math.random() * 0.4
		local reach = 0.45 + math.random() * 0.3
		local size = math.random(22, 40)
		local star = Instance.new("ImageLabel")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(0.5, 0.35)
		star.Size = UDim2.fromOffset(size, size)
		star.BackgroundTransparency = 1
		star.Image = Ui.IMAGES.boton_destello
		star.ImageColor3 = GOLD:Lerp(WHITE, math.random())
		star.Parent = entry.card
		ease(star, 0.7, Enum.EasingStyle.Quad, {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * reach, 0.35 + math.sin(angle) * reach),
			Size = UDim2.fromOffset(0, 0),
			Rotation = math.random(-180, 180),
		})
		task.delay(0.75, star.Destroy, star)
	end
end

function PassShop.start()
	local rows = math.ceil(#Config.GamepassOrder / COLUMNS)
	-- Como mucho se ven SHOWN_ROWS filas y el resto se alcanza deslizando (pedido por el usuario: con una tercera fila
	-- la ventana entera se encogía para caber y quedaba diminuta); si hay más, asoma un trozo de la siguiente para que
	-- se vea que sigue. Alto: cabecera y márgenes de Ui.window (78) y la rejilla. Ancha y baja a propósito (pedido por
	-- el usuario: se veía muy pequeña): Ui.window la escala hasta que toca el alto o el ancho de la pantalla, y con
	-- una ventana casi cuadrada mandaba el alto y las tarjetas quedaban diminutas.
	local shown = math.min(rows, SHOWN_ROWS)
	local window, body = Ui.window("PassShop", Lang.t(nil, "Shop"), Vector2.new(1200, 78 + 4 + shown * (CARD_HEIGHT + GAP) + 16 + (if rows > shown then PEEK else 0)), function(parent)
		Ui.image(parent, "tienda_robux")
	end)

	-- Tickets que tiene el jugador, en la cabecera, a la izquierda de la X.
	local wallet = Instance.new("Frame")
	wallet.Name = "Tickets"
	wallet.Visible = Config.Tickets.Passes == true
	wallet.AnchorPoint = Vector2.new(1, 0.5)
	wallet.Position = UDim2.new(1, -72, 0.5, 0)
	wallet.Size = UDim2.fromOffset(190, 42)
	wallet.Parent = window.Header
	Ui.pill(wallet, Color3.fromRGB(34, 36, 66), 12)
	local walletIcon = Instance.new("Frame")
	walletIcon.Name = "Icon"
	walletIcon.AnchorPoint = Vector2.new(0, 0.5)
	walletIcon.Position = UDim2.new(0, 6, 0.5, 0)
	walletIcon.Size = UDim2.fromOffset(34, 34)
	walletIcon.BackgroundTransparency = 1
	walletIcon.Parent = wallet
	Ui.ticketIcon(walletIcon, TICKET)
	local walletText = Ui.label(wallet, 24)
	walletText.Name = "Amount"
	walletText.Position = UDim2.fromOffset(44, 0)
	walletText.Size = UDim2.new(1, -54, 1, 0)
	walletText.TextXAlignment = Enum.TextXAlignment.Right
	walletText.TextColor3 = GOLD
	Ui.tip(wallet, function()
		return Lang.t(nil, "Tickets: earned from daily and weekly missions"), TICKET
	end, true)

	-- Lo que se mueve fuera de los escaparates de los pases (pedido por el usuario: quieto se veía tieso): los rayos de
	-- cada medallón de trébol y del panel de códigos giran, y su logo flota y se balancea. Lo mueve el bucle de abajo.
	local movers = {} -- { rays, logo, base = posición del logo, phase, over }
	-- Todo va en una lista que se desliza, por secciones: los tréboles, los pases y los códigos.
	local list = Instance.new("ScrollingFrame")
	list.Name = "Passes"
	list.Position = UDim2.fromOffset(8, 4)
	list.Size = UDim2.new(1, -16, 1, -10)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 10
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	local padding = Instance.new("UIPadding")
	-- Margen para que la tarjeta que crece con el ratón no se corte contra el borde de la lista.
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 14) -- y sitio para la barra de deslizar
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = list
	local sections = Instance.new("UIListLayout")
	sections.SortOrder = Enum.SortOrder.LayoutOrder
	sections.Padding = UDim.new(0, GAP)
	sections.Parent = list

	-- Cinta con el nombre de una sección.
	local function heading(order: number, name: string, text: string, color: Color3)
		local bar = Instance.new("Frame")
		bar.Name = name
		bar.LayoutOrder = order
		bar.Size = UDim2.new(1, 0, 0, HEAD_HEIGHT)
		bar.BackgroundColor3 = WHITE
		bar.Parent = list
		Ui.round(bar, 10)
		Ui.stroke(bar, BLACK, 3)
		Ui.panel(bar, color:Lerp(BLACK, 0.15))
		local label = Ui.label(bar, 26)
		label.Position = UDim2.fromOffset(16, 0)
		label.Size = UDim2.new(1, -32, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = text
	end

	-- 1. Tréboles (Config.Products): tres fichas apaisadas, con otro aspecto que los pases.
	heading(1, "HeadClovers", Lang.t(nil, "x{n} Rolls", { n = Config.Clover.Luck }), Color3.fromRGB(60, 190, 110))
	local clovers = Instance.new("Frame")
	clovers.Name = "Clovers"
	clovers.LayoutOrder = 2
	clovers.Size = UDim2.new(1, 0, 0, TILE_HEIGHT)
	clovers.BackgroundTransparency = 1
	clovers.Parent = list
	local cloverGrid = Instance.new("UIGridLayout")
	cloverGrid.CellSize = UDim2.new(1 / COLUMNS, -math.ceil(GAP * (COLUMNS - 1) / COLUMNS) - 1, 1, 0)
	cloverGrid.CellPadding = UDim2.fromOffset(GAP, 0)
	cloverGrid.SortOrder = Enum.SortOrder.LayoutOrder
	cloverGrid.Parent = clovers
	-- Países donde Roblox no deja vender objetos de pago que influyen en un resultado al azar (atributo "NoPaidRandom",
	-- de server/Policy): la sección no se enseña. Mientras el servidor no lo ha dicho, tampoco.
	local function showClovers()
		local allowed = player:GetAttribute("NoPaidRandom") == false
		clovers.Visible = allowed
		local head = list:FindFirstChild("HeadClovers")
		if head then
			head.Visible = allowed
		end
	end
	player:GetAttributeChangedSignal("NoPaidRandom"):Connect(showClovers)
	showClovers()
	for order, key in Config.ProductOrder do
		local product = Config.Products[key]
		local color = product.color
		local slot = Instance.new("Frame")
		slot.Name = "Product_" .. key
		slot.LayoutOrder = order
		slot.BackgroundTransparency = 1
		slot.Parent = clovers
		local tile = Instance.new("Frame")
		tile.Name = "Card"
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromScale(0.5, 0.5)
		tile.Size = UDim2.fromScale(1, 1)
		tile.BackgroundColor3 = WHITE
		tile.Parent = slot
		Ui.round(tile, 14)
		local border = Ui.stroke(tile, BLACK, 4)
		Ui.gradient(tile, color:Lerp(BLACK, 0.25), Color3.fromRGB(20, 44, 40), 0)
		local scale = Instance.new("UIScale")
		scale.Parent = tile

		-- Medallón del trébol a la izquierda, con sus rayos.
		local medal = Instance.new("Frame")
		medal.Name = "Medal"
		medal.AnchorPoint = Vector2.new(0, 0.5)
		medal.Position = UDim2.new(0, 10, 0.5, 0)
		medal.Size = UDim2.fromOffset(TILE_HEIGHT - 20, TILE_HEIGHT - 20)
		medal.BackgroundColor3 = WHITE
		medal.Parent = tile
		Ui.round(medal, 100)
		Ui.stroke(medal, color:Lerp(WHITE, 0.6), 3)
		Ui.gradient(medal, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.4), 90)
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		-- Del tamaño del medallón y con su propia esquina redonda: ClipsDescendants recorta en rectángulo y las
		-- esquinas de la imagen asomaban fuera del círculo.
		rays.Size = UDim2.fromScale(1, 1)
		rays.BackgroundTransparency = 1
		rays.Image = Ui.IMAGES.boton_rayos
		rays.ImageTransparency = 0.7
		rays.Parent = medal
		Ui.round(rays, 100)
		local logo = Instance.new("Frame")
		logo.Name = "Logo"
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.5)
		logo.Size = UDim2.fromScale(0.78, 0.78)
		logo.BackgroundTransparency = 1
		logo.Parent = medal
		Ui.image(logo, product.icon)
		-- Cuántos trae, a caballo del medallón.
		local amount = Ui.label(tile, 34)
		amount.Name = "Amount"
		amount.AnchorPoint = Vector2.new(0.5, 1)
		amount.Position = UDim2.new(0, TILE_HEIGHT - 16, 1, -4)
		amount.Size = UDim2.fromOffset(80, 40)
		amount.Rotation = -6
		amount.Text = "x" .. product.amount
		Ui.gradient(amount, WHITE, GOLD, 90)

		local left = TILE_HEIGHT + 22
		local name = Ui.label(tile, 26)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(left, 8)
		name.Size = UDim2.new(1, -left - 12, 0, 30)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextScaled = true
		name.Text = if product.amount == 1 then Lang.t(nil, "1 clover") else Lang.t(nil, "{n} clovers", { n = product.amount })
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 26
		nameLimit.MinTextSize = 14
		nameLimit.Parent = name
		local note = Ui.label(tile, 16)
		note.Name = "Note"
		note.Position = UDim2.fromOffset(left, 38)
		note.Size = UDim2.new(1, -left - 12, 0, 20)
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.TextColor3 = Color3.fromRGB(205, 230, 215)
		note.Text = Lang.t(nil, "x{n} weapon luck", { n = Config.Clover.Luck })
		if product.ribbon then
			local ribbon = Instance.new("Frame")
			ribbon.Name = "Ribbon"
			ribbon.AnchorPoint = Vector2.new(1, 0)
			ribbon.Position = UDim2.new(1, -8, 0, 8)
			ribbon.Size = UDim2.fromOffset(74, 28)
			ribbon.Rotation = 4
			ribbon.Parent = tile
			Ui.pill(ribbon, Ui.COLORS.red, 8)
			local ribbonText = Ui.label(ribbon, 18)
			ribbonText.Size = UDim2.fromScale(1, 1)
			ribbonText.Text = Lang.t(nil, product.ribbon)
			name.Size = UDim2.new(1, -left - 90, 0, 30)
		end

		local buy = Ui.button(tile, "", ROBUX)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, left / 2 - 2, 1, -10)
		buy.Size = UDim2.new(1, -left - 12, 0, 46)
		buy.TextSize = 26
		Ui.sparkle(buy, 3)
		local price = product.price
		local function show()
			buy.Text = if product.id <= 0 then Lang.t(nil, "Soon") else `{ROBUX_SIGN} {price}`
			buy.BackgroundColor3 = if product.id <= 0 then Ui.COLORS.gray else ROBUX
		end
		show()
		-- El precio de verdad lo dice Roblox (el de Config es solo el que se enseña mientras llega).
		if product.id > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.id, Enum.InfoType.Product)
				if ok and type(info) == "table" and info.PriceInRobux then
					price = info.PriceInRobux
					show()
				end
			end)
		end
		buy.Activated:Connect(function()
			if product.id <= 0 then
				Sfx.play("error")
				Ui.toast(Lang.t(nil, "Not for sale yet"), Ui.COLORS.orange)
				return
			end
			if player:GetAttribute("NoPaidRandom") == false then
				MarketplaceService:PromptProductPurchase(player, product.id)
			end
		end)
		local mover = { rays = rays, logo = logo, base = logo.Position, phase = order * 1.7, over = false }
		table.insert(movers, mover)
		tile.MouseEnter:Connect(function()
			mover.over = true
			if not Performance.get() then
				ease(scale, 0.2, Enum.EasingStyle.Back, { Scale = HOVER })
			end
			ease(border, 0.15, Enum.EasingStyle.Quad, { Color = color:Lerp(WHITE, 0.55) })
		end)
		tile.MouseLeave:Connect(function()
			mover.over = false
			ease(scale, 0.2, Enum.EasingStyle.Quad, { Scale = 1 })
			ease(border, 0.2, Enum.EasingStyle.Quad, { Color = BLACK })
		end)
	end

	-- 2. Pases de juego: la rejilla de tarjetas.
	heading(3, "HeadPasses", Lang.t(nil, "Game passes"), Color3.fromRGB(110, 90, 230))
	local passGrid = Instance.new("Frame")
	passGrid.Name = "Grid"
	passGrid.LayoutOrder = 4
	passGrid.Size = UDim2.new(1, 0, 0, rows * (CARD_HEIGHT + GAP) - GAP)
	passGrid.BackgroundTransparency = 1
	passGrid.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / COLUMNS, -math.ceil(GAP * (COLUMNS - 1) / COLUMNS) - 1, 0, CARD_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = passGrid

	-- 3. Códigos de regalo (Config.Codes, server/Codes): una caja para escribirlo y el botón; la respuesta llega en un aviso.
	heading(5, "HeadCodes", Lang.t(nil, "Codes"), Color3.fromRGB(235, 150, 50))
	local CODE = Color3.fromRGB(120, 124, 255)
	local codes = Instance.new("Frame")
	codes.Name = "Codes"
	codes.LayoutOrder = 6
	codes.Size = UDim2.new(1, 0, 0, CODES_HEIGHT)
	codes.BackgroundColor3 = WHITE
	codes.Parent = list
	Ui.round(codes, 14)
	Ui.stroke(codes, BLACK, 4)
	Ui.gradient(codes, Color3.fromRGB(16, 18, 38), Color3.fromRGB(44, 46, 100), 90)
	-- Rombos al fondo y canto de color por dentro del borde negro.
	local codePattern = Instance.new("ImageLabel")
	codePattern.Name = "Pattern"
	codePattern.Size = UDim2.fromScale(1, 1)
	codePattern.BackgroundTransparency = 1
	codePattern.Image = Ui.IMAGES.boton_patron
	codePattern.ImageColor3 = CODE
	codePattern.ImageTransparency = 0.9
	codePattern.ScaleType = Enum.ScaleType.Tile
	codePattern.TileSize = UDim2.fromOffset(44, 44)
	codePattern.Parent = codes
	Ui.round(codePattern, 14)
	local codeRim = Instance.new("Frame")
	codeRim.Name = "Rim"
	codeRim.Position = UDim2.fromOffset(3, 3)
	codeRim.Size = UDim2.new(1, -6, 1, -6)
	codeRim.BackgroundTransparency = 1
	codeRim.Parent = codes
	Ui.round(codeRim, 11)
	Ui.stroke(codeRim, CODE, 3)
	-- Ticket grande a la izquierda, sobre un resplandor.
	local codeGlow = Instance.new("ImageLabel")
	codeGlow.Name = "Glow"
	codeGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	codeGlow.Position = UDim2.new(0, CODES_LEFT / 2 + 6, 0.5, 0)
	codeGlow.Size = UDim2.fromOffset(CODES_HEIGHT - 24, CODES_HEIGHT - 24)
	codeGlow.BackgroundTransparency = 1
	codeGlow.Image = Ui.IMAGES.boton_rayos
	codeGlow.ImageColor3 = CODE
	codeGlow.ImageTransparency = 0.55
	codeGlow.Parent = codes
	Ui.round(codeGlow, 100)
	local codeIcon = Instance.new("Frame")
	codeIcon.Name = "Icon"
	codeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	codeIcon.Position = codeGlow.Position
	codeIcon.Size = UDim2.fromOffset(150, 150)
	codeIcon.BackgroundTransparency = 1
	codeIcon.Parent = codes
	Ui.image(codeIcon, "codigos")
	table.insert(movers, { rays = codeGlow, logo = codeIcon, base = codeIcon.Position, phase = 0, over = false })

	local codeTitle = Ui.label(codes, 52)
	codeTitle.Name = "Title"
	codeTitle.Position = UDim2.fromOffset(CODES_LEFT, 12)
	codeTitle.Size = UDim2.new(1, -CODES_LEFT - 20, 0, 54)
	codeTitle.TextXAlignment = Enum.TextXAlignment.Left
	codeTitle.Text = Lang.t(nil, "Codes")
	Ui.gradient(codeTitle, WHITE, CODE:Lerp(WHITE, 0.25), 90)
	local codeNote = Ui.label(codes, 22)
	codeNote.Name = "Note"
	codeNote.Position = UDim2.fromOffset(CODES_LEFT, 66)
	codeNote.Size = UDim2.new(1, -CODES_LEFT - 20, 0, 24)
	codeNote.TextXAlignment = Enum.TextXAlignment.Left
	codeNote.Text = Lang.t(nil, "Join our group to get exclusive codes!")
	local codeBox = Instance.new("TextBox")
	codeBox.Name = "Box"
	codeBox.Position = UDim2.fromOffset(CODES_LEFT, 98)
	codeBox.Size = UDim2.new(1, -CODES_LEFT - 24, 0, 48)
	codeBox.ClearTextOnFocus = false
	codeBox.PlaceholderText = Lang.t(nil, "Type your code...")
	codeBox.Text = ""
	codeBox.TextSize = 24
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.Parent = codes
	Ui.field(codeBox)
	local codeEdge = codeBox:FindFirstChildOfClass("UIStroke")
	if codeEdge then
		codeEdge.Color = CODE:Lerp(WHITE, 0.35)
	end
	local codeInset = Instance.new("UIPadding")
	codeInset.PaddingLeft = UDim.new(0, 14)
	codeInset.PaddingRight = UDim.new(0, 14)
	codeInset.Parent = codeBox
	local redeem = Ui.button(codes, Lang.t(nil, "Redeem"), Ui.COLORS.green)
	redeem.Name = "Redeem"
	redeem.Position = UDim2.fromOffset(CODES_LEFT, 156)
	redeem.Size = UDim2.fromOffset(230, 52)
	redeem.TextSize = 28
	Ui.sparkle(redeem, 3)
	local function sendCode()
		local text = string.gsub(codeBox.Text, "%s+", "")
		if text == "" then
			Sfx.play("error")
			return
		end
		Remotes.RedeemCode:FireServer(text)
		codeBox.Text = ""
	end
	redeem.Activated:Connect(sendCode)
	codeBox.FocusLost:Connect(function(enter)
		if enter then
			sendCode()
		end
	end)

	local cards = {}
	for order, key in Config.GamepassOrder do
		local pass = Config.Gamepasses[key]
		-- La casilla de la rejilla es un hueco; la tarjeta va dentro, centrada, para poder crecer desde su centro.
		local slot = Instance.new("Frame")
		slot.Name = "Pass_" .. key
		slot.LayoutOrder = order
		slot.BackgroundTransparency = 1
		slot.Parent = passGrid
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = WHITE
		card.BorderSizePixel = 0
		card.Parent = slot
		Ui.round(card, 14)
		local border = Ui.stroke(card, BLACK, 4)
		Ui.gradient(card, Color3.fromRGB(62, 66, 118):Lerp(pass.color, 0.3), Color3.fromRGB(24, 26, 50):Lerp(pass.color, 0.12), 90)
		local scale = Instance.new("UIScale")
		scale.Parent = card

		local art = buildArt(card, pass)

		local name = Ui.label(card, 30)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(PAD, PAD + ART_HEIGHT + 6)
		name.Size = UDim2.new(1, -PAD * 2, 0, 34)
		name.TextScaled = true
		name.Text = Lang.t(nil, pass.name)
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 30
		nameLimit.MinTextSize = 14
		nameLimit.Parent = name
		Ui.gradient(name, WHITE, pass.color:Lerp(WHITE, 0.4), 90)

		-- Lo que da, una línea por ventaja (perksText). El texto se encoge si un pase trae muchas.
		local lines = {}
		for _, text in pass.perksText do
			table.insert(lines, `<font color="#{ROBUX:ToHex()}">+</font> {Lang.t(nil, text)}`)
		end
		local buyHeight = 54
		local perksTop = PAD + ART_HEIGHT + 44
		local perks = Ui.label(card, 20)
		perks.Name = "Perks"
		perks.Position = UDim2.fromOffset(PAD + 4, perksTop)
		perks.Size = UDim2.new(1, -PAD * 2 - 8, 1, -perksTop - buyHeight - PAD - 8)
		perks.TextXAlignment = Enum.TextXAlignment.Left
		perks.TextYAlignment = Enum.TextYAlignment.Top
		perks.TextWrapped = true
		perks.TextScaled = true
		perks.Text = table.concat(lines, "\n")
		local perksLimit = Instance.new("UITextSizeConstraint")
		perksLimit.MaxTextSize = 20
		perksLimit.MinTextSize = 10
		perksLimit.Parent = perks

		local buy = Ui.button(card, "", ROBUX)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.new(0, PAD + 2, 1, -PAD - 2)
		buy.Size = UDim2.new(0.5, -PAD - 5, 0, buyHeight)
		buy.TextSize = 30
		Ui.sparkle(buy, 3)

		-- Lo mismo con tickets de misión, a la derecha: el icono y el precio.
		local tickets = Ui.button(card, "", TICKET)
		tickets.Name = "Tickets"
		tickets.AnchorPoint = Vector2.new(1, 1)
		tickets.Position = UDim2.new(1, -PAD - 2, 1, -PAD - 2)
		tickets.Size = buy.Size
		tickets.TextSize = 26
		local ticketIcon = Instance.new("Frame")
		ticketIcon.Name = "Icon"
		ticketIcon.AnchorPoint = Vector2.new(0, 0.5)
		ticketIcon.Position = UDim2.new(0, 8, 0.5, 0)
		ticketIcon.Size = UDim2.fromOffset(32, 32)
		ticketIcon.BackgroundTransparency = 1
		ticketIcon.Parent = tickets
		Ui.ticketIcon(ticketIcon, TICKET)

		local entry = { key = key, pass = pass, card = card, scale = scale, border = border, art = art, buy = buy, price = pass.price, tickets = tickets, ticketIcon = ticketIcon, confirm = 0 }
		cards[key] = entry

		-- Ratón encima: la tarjeta crece, el borde se enciende del color del pase y el escaparate se acelera.
		card.MouseEnter:Connect(function()
			art.over = true
			art.kick = 0
			if not Performance.get() then
				ease(scale, 0.2, Enum.EasingStyle.Back, { Scale = HOVER })
			end
			ease(border, 0.15, Enum.EasingStyle.Quad, { Color = pass.color:Lerp(WHITE, 0.55) })
		end)
		card.MouseLeave:Connect(function()
			art.over = false
			ease(scale, 0.2, Enum.EasingStyle.Quad, { Scale = 1 })
			ease(border, 0.2, Enum.EasingStyle.Quad, { Color = BLACK })
		end)

		-- El precio de verdad lo dice Roblox (el de Config es solo el que se enseña mientras llega).
		if pass.id > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.id, Enum.InfoType.GamePass)
				if ok and type(info) == "table" and info.PriceInRobux then
					entry.price = info.PriceInRobux
					if buy.Parent and not Stats.pass(player, key) then
						buy.Text = `{ROBUX_SIGN} {entry.price}`
					end
				end
			end)
		end
		buy.Activated:Connect(function()
			if Stats.pass(player, key) then
				return
			end
			if pass.id <= 0 then
				Sfx.play("error")
				Ui.toast(Lang.t(nil, "Not for sale yet"), Ui.COLORS.orange)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
	end

	local refresh
	for key, entry in cards do
		entry.tickets.Activated:Connect(function()
			if Stats.pass(player, key) then
				return
			end
			local missing = Stats.ticketPrice(key) - (player:GetAttribute("Item_missionToken") or 0)
			if missing > 0 then
				Sfx.play("error")
				Ui.toast(Lang.t(nil, "You need {n} more tickets: missions give them", { n = count(missing) }), Ui.COLORS.orange)
				return
			end
			-- Primer toque: pregunta. El segundo, antes de CONFIRM_TIME s, compra.
			local now = os.clock()
			if now - entry.confirm <= CONFIRM_TIME then
				entry.confirm = 0
				Remotes.BuyPassTickets:FireServer(key)
			else
				entry.confirm = now
				task.delay(CONFIRM_TIME + 0.05, refresh)
			end
			refresh()
		end)
	end

	function refresh()
		local owns = player:GetAttribute("Item_missionToken") or 0
		walletText.Text = count(owns)
		for key, entry in cards do
			local owned = Stats.pass(player, key)
			local asking = os.clock() - entry.confirm <= CONFIRM_TIME
			local cost = Stats.ticketPrice(key)
			local enough = owns >= cost
			local single = owned or not Config.Tickets.Passes -- un solo botón, a todo lo ancho
			entry.buy.Size = if single then UDim2.new(1, -PAD * 2 - 4, 0, entry.buy.Size.Y.Offset) else entry.tickets.Size
			entry.tickets.Visible = not single
			entry.ticketIcon.Visible = not asking
			entry.tickets.Text = if asking then Lang.t(nil, "Sure?") else `      {count(cost)}`
			entry.tickets.TextSize = if asking then 22 else 26
			entry.tickets.BackgroundColor3 = if asking then Ui.COLORS.green elseif enough then TICKET else TICKET:Lerp(Color3.fromRGB(70, 72, 90), 0.7)
			entry.tickets.TextColor3 = if enough then WHITE else Color3.fromRGB(190, 192, 205)
			entry.buy.Text = if owned then Lang.t(nil, "You own it!") elseif entry.pass.id <= 0 then Lang.t(nil, "Soon") else `{ROBUX_SIGN} {entry.price}`
			entry.buy.BackgroundColor3 = if owned then Ui.COLORS.blue elseif entry.pass.id <= 0 then Ui.COLORS.gray else ROBUX
			entry.buy.TextSize = if owned then 22 else 26
		end
	end
	player.AttributeChanged:Connect(function(attribute)
		if string.sub(attribute, 1, 5) == "Pass_" then
			local entry = cards[string.sub(attribute, 6)]
			if player:GetAttribute(attribute) == true and window.Visible then
				Sfx.play("win")
				if entry then
					celebrate(entry)
				end
			end
			refresh()
		elseif attribute == "Item_missionToken" then
			refresh()
		end
	end)
	refresh()

	-- Un solo bucle para todos los escaparates, que solo vive con la ventana a la vista (y no en modo rendimiento).
	local loop: RBXScriptConnection? = nil
	local function animate()
		local on = window.Visible and not Performance.get()
		if on and not loop then
			loop = RunService.RenderStepped:Connect(function(dt)
				if Performance.get() then
					animate()
					return
				end
				for _, entry in cards do
					stepArt(entry.art, dt)
				end
				for _, mover in movers do
					-- Con el ratón encima, todo más deprisa.
					mover.phase += dt * (if mover.over then 2.4 else 1)
					mover.rays.Rotation = mover.phase * 26
					mover.logo.Position = mover.base + UDim2.fromOffset(0, math.sin(mover.phase * 2.6) * 3)
					mover.logo.Rotation = math.sin(mover.phase * 1.9) * 6
				end
			end)
		elseif not on and loop then
			loop:Disconnect()
			loop = nil
		end
	end
	window:GetPropertyChangedSignal("Visible"):Connect(animate)
	animate()
end

return PassShop
