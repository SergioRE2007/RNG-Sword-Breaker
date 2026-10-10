-- Botones grandes del HUD (librería sin start(); la usa Hud): fondo del color del botón con rombos, canto
-- claro por dentro del borde negro, el logo grande y el nombre con borde grueso. Hay dos formas: la cuadrada
-- del menú (nombre abajo, pisando el borde) y la alargada de la barra de transporte (logo a la izquierda).
-- Al pasar el ratón se animan por dentro: el logo salta y se balancea, los rombos del fondo se desplazan,
-- detrás del logo giran unos rayos y saltan destellos. Las imágenes del fondo las dibuja tools/ui/botones.mjs.
-- Capas: todo va en la capa del botón (la interfaz ordena el ZIndex globalmente), así que manda el orden en
-- que se crean las piezas: fondo, rombos, rayos, canto, logo, destellos y nombre.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)

local MenuTile = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

MenuTile.SIZE = 120 -- lado del botón cuadrado
MenuTile.WIDE = Vector2.new(220, 76) -- el alargado: cabe "Mazmorras"
-- El recorte de los rombos es un rectángulo (ClipsDescendants no entiende de esquinas redondas) metido RIM
-- píxeles: sus picos quedan bajo el canto claro mientras RIM no baje de 0,3 x RADIUS.
local RADIUS = 13
local RIM = 4 -- grosor del canto claro
local PATTERN_TILE = 44 -- lo que mide en pantalla un periodo de rombos (la imagen trae dos por lado)
local PATTERN_SPEED = 26 -- píxeles por segundo a los que se desplazan con el ratón encima
local PATTERN_REST = 0.62 -- transparencia de los rombos en reposo: se notan sin competir con el logo
local GROW = 1.04 -- lo que crece el botón entero: poco, que lo que se mueve es lo de dentro

-- Dónde va cada cosa en cada forma. Los rayos caben enteros dentro del botón (giran sin recorte). Destellos:
-- sitio (en fracción del botón), tamaño en píxeles y desfase del parpadeo.
local SQUARE = {
	size = UDim2.fromOffset(MenuTile.SIZE, MenuTile.SIZE),
	-- El logo, algo por encima del centro: abajo va el nombre.
	icon = { position = UDim2.fromScale(0.5, 0.42), size = UDim2.fromScale(0.84, 0.84) },
	rays = { position = UDim2.fromScale(0.5, 0.46), size = UDim2.fromScale(0.96, 0.96) },
	label = { anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, 5), size = UDim2.new(1, -6, 0, 30), text = 25 },
	twinkles = {
		{ x = 0.15, y = 0.2, size = 20, phase = 0 },
		{ x = 0.86, y = 0.3, size = 15, phase = 2.1 },
		{ x = 0.82, y = 0.7, size = 18, phase = 4.2 },
		{ x = 0.13, y = 0.62, size = 13, phase = 5.5 },
	},
}
local WIDE = {
	size = UDim2.fromOffset(MenuTile.WIDE.X, MenuTile.WIDE.Y),
	icon = { position = UDim2.new(0, 44, 0.5, 0), size = UDim2.fromOffset(80, 80) },
	rays = { position = UDim2.new(0, 44, 0.5, 0), size = UDim2.fromOffset(72, 72) },
	-- El nombre, centrado en lo que queda a la derecha del logo.
	label = { anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 40, 0.5, 0), size = UDim2.new(1, -96, 0, 38), text = 28 },
	twinkles = {
		{ x = 0.06, y = 0.26, size = 15, phase = 0 },
		{ x = 0.36, y = 0.22, size = 17, phase = 2.1 },
		{ x = 0.34, y = 0.8, size = 13, phase = 4.2 },
		{ x = 0.94, y = 0.28, size = 14, phase = 5.5 },
	},
}

-- ¿Se ve el botón? Si el HUD se esconde con el ratón encima (al abrir Mejoras) nadie avisa de que el ratón
-- ha salido, y la animación seguiría para siempre.
local function shown(item: GuiObject): boolean
	local at: Instance? = item
	while at and at:IsA("GuiObject") do
		if not at.Visible then
			return false
		end
		at = at.Parent
	end
	return at ~= nil
end

local function ease(target: Instance, time: number, style: Enum.EasingStyle, goal)
	TweenService:Create(target, TweenInfo.new(time, style, Enum.EasingDirection.Out), goal):Play()
end

-- Arcoíris de los rayos del botón de la Tienda: una vuelta entera al color, para que al girar no se note el corte.
local RAINBOW_STEPS = 12
local RAINBOW_SPIN = -140 -- grados por segundo a los que el arcoíris recorre los rayos (al revés que ellos)
local RAINBOW_HUE = 0.35 -- vueltas de color por segundo de los destellos
local function rainbow(): ColorSequence
	local points = {}
	for step = 0, RAINBOW_STEPS do
		local at = step / RAINBOW_STEPS
		points[step + 1] = ColorSequenceKeypoint.new(at, Color3.fromHSV(at % 1, 0.85, 1))
	end
	return ColorSequence.new(points)
end

-- `logo` es un nombre de Ui.IMAGES. Con `wide`, el botón alargado de la barra de transporte. Con `exotic`
-- (el de la Tienda), los rayos y los destellos que salen al pasar el ratón van en arcoíris.
function MenuTile.new(
	parent: Instance,
	text: string,
	color: Color3,
	logo: string,
	wide: boolean?,
	exotic: boolean?
): TextButton
	local layout = if wide then WIDE else SQUARE
	local item = Instance.new("TextButton")
	item.Text = ""
	item.AutoButtonColor = false
	item.BackgroundColor3 = WHITE
	item.Size = layout.size
	item.Parent = parent
	Ui.round(item, RADIUS)
	Ui.gradient(item, color:Lerp(WHITE, 0.22), color:Lerp(BLACK, 0.18), 90)
	Ui.stroke(item, BLACK, Ui.STYLE.border + 1)

	-- Rombos en mosaico. Para desplazarlos se mueve la imagen, que sobresale un periodo, dentro de un recorte.
	-- (Con ImageRectSize el mosaico no funciona: Roblox estira ese trozo por toda la pieza.)
	local clip = Instance.new("Frame")
	clip.Name = "Pattern"
	clip.Position = UDim2.fromOffset(RIM, RIM)
	clip.Size = UDim2.new(1, -RIM * 2, 1, -RIM * 2)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = item
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Tiles"
	pattern.Size = UDim2.new(1, PATTERN_TILE, 1, PATTERN_TILE)
	pattern.BackgroundTransparency = 1
	pattern.Image = Ui.IMAGES.boton_patron
	pattern.ImageTransparency = PATTERN_REST
	pattern.ScaleType = Enum.ScaleType.Tile
	pattern.TileSize = UDim2.fromOffset(PATTERN_TILE * 2, PATTERN_TILE * 2)
	pattern.Parent = clip

	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = layout.rays.position
	rays.Size = layout.rays.size
	rays.BackgroundTransparency = 1
	rays.Image = Ui.IMAGES.boton_rayos
	rays.ImageColor3 = color:Lerp(WHITE, 0.75)
	rays.ImageTransparency = 1
	rays.Parent = item
	local raysShown = 0.38 -- transparencia de los rayos con el ratón encima
	local rayColors: UIGradient? = nil
	if exotic then
		-- El degradado tiñe la imagen (blanca) y gira con ella; además da vueltas por su cuenta.
		rays.ImageColor3 = WHITE
		raysShown = 0.08
		local colors = Instance.new("UIGradient")
		colors.Color = rainbow()
		colors.Parent = rays
		rayColors = colors
	end

	-- Canto claro por dentro del borde negro, más luminoso arriba que abajo.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(RIM, RIM)
	rim.Size = UDim2.new(1, -RIM * 2, 1, -RIM * 2)
	rim.BackgroundTransparency = 1
	rim.Parent = item
	Ui.round(rim, RADIUS - RIM)
	local rimStroke = Ui.stroke(rim, WHITE, RIM)
	Ui.gradient(rimStroke :: any, color:Lerp(WHITE, 0.72), color:Lerp(WHITE, 0.25), 90)

	local iconRest = layout.icon.position
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = iconRest
	icon.Size = layout.icon.size
	icon.BackgroundTransparency = 1
	icon.Parent = item
	Ui.image(icon, logo)
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon

	local twinkles = {}
	for index, spot in layout.twinkles do
		local star = Instance.new("ImageLabel")
		star.Name = "Twinkle" .. index
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(spot.x, spot.y)
		star.Size = UDim2.fromOffset(0, 0)
		star.BackgroundTransparency = 1
		star.Image = Ui.IMAGES.boton_destello
		star.Parent = item
		twinkles[index] = star
	end

	-- El nombre, grande y con borde negro grueso.
	local label = Ui.label(item, layout.label.text)
	label.Name = "Label"
	label.AnchorPoint = layout.label.anchor
	label.Position = layout.label.position
	label.Size = layout.label.size
	label.TextScaled = true
	label.Text = text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = layout.label.text
	limit.MinTextSize = 12
	limit.Parent = label
	local labelStroke = label:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Thickness = 3
	end
	local labelScale = Instance.new("UIScale")
	labelScale.Parent = label

	Ui.pressable(item, GROW)

	-- Animación de dentro: un solo bucle por botón, que solo vive mientras el ratón está encima.
	local loop: RBXScriptConnection? = nil
	local scroll = 0
	local function rest()
		if loop then
			loop:Disconnect()
			loop = nil
		end
		ease(iconScale, 0.2, Enum.EasingStyle.Quad, { Scale = 1 })
		ease(labelScale, 0.2, Enum.EasingStyle.Quad, { Scale = 1 })
		ease(icon, 0.3, Enum.EasingStyle.Back, { Rotation = 0, Position = iconRest })
		ease(rays, 0.2, Enum.EasingStyle.Quad, { ImageTransparency = 1 })
		ease(pattern, 0.2, Enum.EasingStyle.Quad, { ImageTransparency = PATTERN_REST })
		for _, star in twinkles do
			ease(star, 0.15, Enum.EasingStyle.Quad, { Size = UDim2.fromOffset(0, 0) })
		end
	end
	local function wake()
		if loop or Performance.get() then
			return
		end
		ease(iconScale, 0.25, Enum.EasingStyle.Back, { Scale = 1.12 })
		ease(labelScale, 0.25, Enum.EasingStyle.Back, { Scale = 1.06 })
		ease(rays, 0.25, Enum.EasingStyle.Quad, { ImageTransparency = raysShown })
		ease(pattern, 0.25, Enum.EasingStyle.Quad, { ImageTransparency = 0.52 })
		local time = 0
		loop = RunService.RenderStepped:Connect(function(dt)
			if not shown(item) then
				rest()
				return
			end
			time += dt
			-- El logo da un meneo fuerte al entrar el ratón, que se apaga, y luego se queda balanceándose y botando.
			local shake = math.exp(-5 * time) * math.sin(time * 24) * 13
			local settled = 1 - math.exp(-3 * time)
			icon.Rotation = shake + math.sin(time * 3.2) * 3.5 * settled
			icon.Position = iconRest + UDim2.fromOffset(0, -math.abs(math.sin(time * 3.2)) * 3 * settled)
			rays.Rotation = time * 55
			if rayColors then
				rayColors.Rotation = (time * RAINBOW_SPIN) % 360
			end
			scroll = (scroll + dt * PATTERN_SPEED) % PATTERN_TILE
			pattern.Position = UDim2.fromOffset(-scroll, -scroll)
			for index, star in twinkles do
				local spot = layout.twinkles[index]
				local size = math.max(math.sin(time * 5 + spot.phase), 0) * spot.size
				star.Size = UDim2.fromOffset(size, size)
				star.Rotation = time * 60 + spot.phase * 40
				if exotic then
					star.ImageColor3 = Color3.fromHSV((time * RAINBOW_HUE + index / #twinkles) % 1, 0.45, 1)
				end
			end
		end)
	end
	-- Solo el ratón: con el dedo no hay "encima", y MouseEnter se quedaba encendido tras un toque.
	item.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			wake()
		end
	end)
	item.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and loop then
			rest()
		end
	end)

	return item
end

return MenuTile
