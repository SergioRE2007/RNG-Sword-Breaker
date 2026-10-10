-- Tienda de pases de juego (botón "Tienda" del menú): una tarjeta por pase de Config.Gamepasses, en rejilla de
-- tres columnas. Cada tarjeta lleva arriba su "escaparate" (del color del pase, como los botones del menú: rombos
-- que se desplazan, rayos que giran, el logo grande del pase y copias pequeñas del logo cayendo por detrás, con su
-- etiqueta gorda "x2", "VIP"...), el nombre, lo que da y el botón de compra. Al pasar el ratón la tarjeta crece, el
-- logo salta y todo se acelera; al comprar, la tarjeta da un bote y suelta destellos.
-- La compra la hace Roblox (MarketplaceService); el servidor (server/Passes) publica cuáles tiene el jugador en los
-- atributos "Pass_<clave>".
-- Capas: todo va en la capa por defecto (la interfaz ordena el ZIndex globalmente), así que manda el orden en que
-- se crean las piezas de cada tarjeta: fondo, escaparate (rombos, lluvia, rayos, canto, logo, etiqueta, cinta),
-- textos y botón.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
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

-- Medidas de la tarjeta (píxeles de diseño: la ventana entera se encoge con su UIScale).
local COLUMNS = 3
local GAP = 12
local CARD_HEIGHT = 306
local PAD = 8 -- margen de la tarjeta
local ART_HEIGHT = 116 -- alto del escaparate
local ART_RADIUS = 10
local RIM = 3 -- canto claro del escaparate; el recorte de dentro va metido esto mismo
local ICON = 104 -- lado del logo grande
local TILE = 40 -- periodo de los rombos del escaparate
local DROPS = 7 -- logos pequeños que caen por tarjeta
local HOVER = 1.04 -- lo que crece la tarjeta con el ratón encima

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
	tag.Text = pass.tag
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
		text.Text = pass.ribbon
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
	-- Alto justo para ver todas las filas sin arrastrar: cabecera y márgenes de Ui.window (78), la nota (34) y la rejilla.
	local window, body = Ui.window("PassShop", "Tienda", Vector2.new(900, 78 + 34 + rows * (CARD_HEIGHT + GAP) + 16), function(parent)
		Ui.image(parent, "tienda_robux")
	end)

	local note = Ui.label(body, 17)
	note.Name = "Note"
	note.Position = UDim2.fromOffset(16, 4)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Color3.fromRGB(190, 195, 215)
	note.Text = "Pases de juego: se compran una vez y son para siempre."

	local list = Instance.new("ScrollingFrame")
	list.Name = "Passes"
	list.Position = UDim2.fromOffset(8, 34)
	list.Size = UDim2.new(1, -16, 1, -40)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	local padding = Instance.new("UIPadding")
	-- Margen para que la tarjeta que crece con el ratón no se corte contra el borde de la lista.
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / COLUMNS, -GAP * (COLUMNS - 1) / COLUMNS, 0, CARD_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	local cards = {}
	for order, key in Config.GamepassOrder do
		local pass = Config.Gamepasses[key]
		-- La casilla de la rejilla es un hueco; la tarjeta va dentro, centrada, para poder crecer desde su centro.
		local slot = Instance.new("Frame")
		slot.Name = "Pass_" .. key
		slot.LayoutOrder = order
		slot.BackgroundTransparency = 1
		slot.Parent = list
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

		local name = Ui.label(card, 24)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(PAD, PAD + ART_HEIGHT + 6)
		name.Size = UDim2.new(1, -PAD * 2, 0, 28)
		name.TextScaled = true
		name.Text = pass.name
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 24
		nameLimit.MinTextSize = 14
		nameLimit.Parent = name
		Ui.gradient(name, WHITE, pass.color:Lerp(WHITE, 0.4), 90)

		-- Lo que da, una línea por ventaja. El texto se encoge si un pase trae muchas.
		local lines = {}
		for _, text in pass.perksText do
			table.insert(lines, `<font color="#{ROBUX:ToHex()}">+</font> {text}`)
		end
		local buyHeight = 50
		local perksTop = PAD + ART_HEIGHT + 38
		local perks = Ui.label(card, 16)
		perks.Name = "Perks"
		perks.Position = UDim2.fromOffset(PAD + 4, perksTop)
		perks.Size = UDim2.new(1, -PAD * 2 - 8, 1, -perksTop - buyHeight - PAD - 8)
		perks.TextXAlignment = Enum.TextXAlignment.Left
		perks.TextYAlignment = Enum.TextYAlignment.Top
		perks.TextWrapped = true
		perks.TextScaled = true
		perks.Text = table.concat(lines, "\n")
		local perksLimit = Instance.new("UITextSizeConstraint")
		perksLimit.MaxTextSize = 16
		perksLimit.MinTextSize = 10
		perksLimit.Parent = perks

		local buy = Ui.button(card, "", ROBUX)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -PAD - 2)
		buy.Size = UDim2.new(1, -PAD * 2 - 4, 0, buyHeight)
		buy.TextSize = 26
		Ui.sparkle(buy, 3)

		local entry = { key = key, pass = pass, card = card, scale = scale, border = border, art = art, buy = buy, price = pass.price }
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
						buy.Text = `R$ {entry.price}`
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
				Ui.toast("Este pase aún no está a la venta", Ui.COLORS.orange)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
	end

	local function refresh()
		for key, entry in cards do
			local owned = Stats.pass(player, key)
			entry.buy.Text = if owned then "¡Lo tienes!" elseif entry.pass.id <= 0 then "Pronto" else `R$ {entry.price}`
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
