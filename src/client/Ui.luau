-- Piezas comunes de la interfaz: estilo (degradados, bordes, botones con relieve), ventanas,
-- casillas cuadradas con icono, cartel flotante al pasar el ratón y avisos en pantalla.
-- No tiene start(): lo usan Hud, Backpack, GachaRoll, ModifierShops y SkillTree.
-- Notas: la pantalla "Hud" ignora la franja de arriba de Roblox (IgnoreGuiInset), así que las
-- posiciones cuentan desde el borde real de la pantalla (igual que GetMouseLocation), pero
-- AbsolutePosition sigue contando desde debajo de la franja (hay que sumar GetGuiInset). Las capas
-- se ordenan globalmente: un hijo con menos ZIndex que su padre queda tapado por él.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)

local Ui = {}

local glints = {} -- [UIGradient del brillo] = { phase, period }

local player = Players.LocalPlayer

Ui.FONT = Enum.Font.FredokaOne
Ui.SOFT = "#b9c0d6" -- texto secundario (RichText)
Ui.COLORS = {
	panel = Color3.fromRGB(30, 32, 42),
	body = Color3.fromRGB(48, 51, 66),
	cell = Color3.fromRGB(26, 27, 36),
	dark = Color3.fromRGB(16, 17, 24),
	green = Color3.fromRGB(85, 210, 70),
	blue = Color3.fromRGB(50, 150, 255),
	orange = Color3.fromRGB(255, 160, 30),
	red = Color3.fromRGB(240, 65, 75),
	gray = Color3.fromRGB(110, 114, 130),
	purple = Color3.fromRGB(170, 90, 255),
	coins = Color3.fromRGB(255, 185, 30),
}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

function Ui.round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Borde alrededor del marco.
function Ui.stroke(instance: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

-- Borde negro alrededor de las letras.
function Ui.textStroke(instance: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = instance
end

-- Degradado entre dos colores (rotation 90 = de arriba abajo).
function Ui.gradient(instance: GuiObject, from: Color3, to: Color3, rotation: number)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(from, to)
	gradient.Rotation = rotation
	gradient.Parent = instance
end

-- Relieve de botón, sobre el color de fondo que tenga: degradado suave (claro arriba, más oscuro
-- abajo), un brillo de cristal en la mitad de arriba, un canto claro por dentro del marco y una
-- franja oscura en el borde de abajo para dar grosor. Va antes que el contenido del botón.
function Ui.bevel(instance: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(232, 232, 236)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 168)),
	})
	gradient.Parent = instance

	local corner = instance:FindFirstChildOfClass("UICorner")
	local radius = if corner then corner.CornerRadius.Offset else 10

	-- Canto claro por dentro del marco.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(2, 2)
	rim.Size = UDim2.new(1, -4, 1, -4)
	rim.BackgroundTransparency = 1
	rim.Parent = instance
	Ui.round(rim, math.max(radius - 2, 2))
	local rimStroke = Ui.stroke(rim, WHITE, 1.5)
	rimStroke.Transparency = 0.72

	-- Brillo de cristal: blanco que se apaga hacia abajo.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(4, 3)
	gloss.Size = UDim2.new(1, -8, 0.46, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BorderSizePixel = 0
	gloss.Parent = instance
	Ui.round(gloss, math.max(radius - 4, 2))
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.6, 0.95)
	fade.Parent = gloss

	-- Franja oscura abajo (el "grosor" del botón).
	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 1)
	base.Position = UDim2.new(0.5, 0, 1, -3)
	base.Size = UDim2.new(1, -12, 0, 4)
	base.BackgroundColor3 = BLACK
	base.BackgroundTransparency = 0.78
	base.BorderSizePixel = 0
	base.Parent = instance
	Ui.round(base, 2)
end

function Ui.label(parent: Instance, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.TextColor3 = WHITE
	text.Font = Ui.FONT
	text.TextSize = textSize
	text.RichText = true
	text.Parent = parent
	Ui.textStroke(text, if textSize >= 20 then 2.5 else 1.5)
	return text
end

function Ui.button(parent: Instance, text: string, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.TextColor3 = WHITE
	item.Font = Ui.FONT
	item.TextSize = 17
	item.TextWrapped = true
	item.Text = text
	item.Parent = parent
	Ui.round(item, 12)
	Ui.bevel(item)
	Ui.stroke(item, BLACK, 3)
	Ui.textStroke(item, 2)
	Ui.pressable(item)
	return item
end

-- Rebote al pasar el ratón (crece) y al pulsar (se hunde). Vale para cualquier botón o casilla.
function Ui.pressable(item: GuiButton, grow: number?)
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = item
	local big = grow or 1.07
	local function to(value: number, time: number, style: Enum.EasingStyle)
		if Performance.get() then
			scale.Scale = 1 -- modo rendimiento: sin rebotes
			return
		end
		TweenService:Create(scale, TweenInfo.new(time, style, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	local over = false
	item.Activated:Connect(function()
		Sfx.play("click")
	end)
	item.MouseEnter:Connect(function()
		over = true
		to(big, 0.18, Enum.EasingStyle.Back)
	end)
	item.MouseLeave:Connect(function()
		over = false
		to(1, 0.15, Enum.EasingStyle.Quad)
	end)
	item.MouseButton1Down:Connect(function()
		to(0.93, 0.07, Enum.EasingStyle.Quad)
	end)
	item.MouseButton1Up:Connect(function()
		to(if over then big else 1, 0.2, Enum.EasingStyle.Back)
	end)
end

-- Brillo blanco en diagonal que cruza el botón cada pocos segundos (la hace el bucle de `shines`).
function Ui.sparkle(item: GuiObject, period: number?)
	local glint = Instance.new("Frame")
	glint.Name = "Glint"
	glint.Size = UDim2.fromScale(1, 1)
	glint.BackgroundColor3 = WHITE
	glint.BorderSizePixel = 0
	glint.ZIndex = item.ZIndex + 1
	glint.Visible = not Performance.get()
	glint.Parent = item
	Ui.round(glint, 12)
	local sweep = Instance.new("UIGradient")
	sweep.Rotation = 20
	sweep.Color = ColorSequence.new(WHITE)
	sweep.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.65),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweep.Parent = glint
	glints[sweep] = { phase = math.random() * 4, period = period or 4 }
end

local gui
function Ui.screen(): ScreenGui
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "Hud"
		gui.ResetOnSpawn = false
		-- Usa también la franja de arriba (donde Roblox pone sus botones a la izquierda).
		gui.IgnoreGuiInset = true
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	return gui
end

-- Ventanas ------------------------------------------------------------------------------

local windows = {} -- [nombre] = Frame
local MAX_WINDOW_SCALE = 1.22 -- las ventanas crecen hasta aquí en pantallas grandes

-- Brillos que cruzan los títulos de las ventanas (los mueve un solo bucle).
local shines = {}
local glintsHidden = false
RunService.RenderStepped:Connect(function()
	-- Modo rendimiento: ni brillos en los títulos ni destellos en los botones (se esconden y se devuelven al apagarlo).
	if Performance.get() then
		if not glintsHidden then
			glintsHidden = true
			for gradient in glints do
				if gradient.Parent then
					(gradient.Parent :: GuiObject).Visible = false
				end
			end
		end
		return
	elseif glintsHidden then
		glintsHidden = false
		for gradient in glints do
			if gradient.Parent then
				(gradient.Parent :: GuiObject).Visible = true
			end
		end
	end
	local now = os.clock()
	for gradient, phase in shines do
		if gradient.Parent then
			-- Pasa de izquierda a derecha cada 3 s y espera un poco fuera.
			gradient.Offset = Vector2.new(((now + phase) % 3) / 1.5 - 1, 0)
		else
			shines[gradient] = nil
		end
	end
	for gradient, info in glints do
		if gradient:IsDescendantOf(game) then
			-- Cruza de izquierda a derecha en el primer tramo del periodo y espera el resto.
			local t = ((now + info.phase) % info.period) / info.period
			gradient.Offset = Vector2.new(math.clamp(t * 2.4 - 1.2, -1, 1), 0)
		else
			glints[gradient] = nil
		end
	end
end)

-- Rayas diagonales muy suaves sobre un marco de `size` píxeles (que no se vea plano). Son marcos
-- girados calculados para que no se salgan del rectángulo (el recorte no funciona con giros).
-- Hay que ponerlas antes que el contenido: la interfaz ordena las capas globalmente y, a igual
-- ZIndex, se pinta antes lo que se creó antes.
function Ui.stripes(parent: GuiObject, size: Vector2, spacing: number, transparency: number, zIndex: number?)
	local holder = Instance.new("Frame")
	holder.Name = "Stripes"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = zIndex or 1
	holder.Parent = parent
	local width, height = size.X, size.Y
	-- Líneas x + y = c (45°), de c = spacing a c = width + height.
	for c = spacing, width + height - spacing, spacing do
		local x1, y1 = math.max(0, c - height), math.min(height, c)
		local x2, y2 = math.min(width, c), math.max(0, c - width)
		local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		if length > 8 then
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
			line.Size = UDim2.fromOffset(length, spacing * 0.35)
			line.Rotation = -45
			line.BackgroundColor3 = WHITE
			line.BackgroundTransparency = transparency
			line.BorderSizePixel = 0
			line.ZIndex = zIndex or 1
			line.Parent = holder
		end
	end
	return holder
end

-- Cuadros claros alternos (como las cabeceras de la captura de referencia), sin salirse del marco.
local function checker(parent: GuiObject, size: Vector2, cell: number, inset: number)
	local holder = Instance.new("Frame")
	holder.Name = "Checker"
	holder.Position = UDim2.fromOffset(inset, 0)
	holder.Size = UDim2.new(1, -inset * 2, 1, 0)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.Parent = parent
	for row = 0, math.ceil(size.Y / cell) - 1 do
		for column = 0, math.ceil((size.X - inset * 2) / cell) - 1 do
			if (row + column) % 2 == 0 then
				local square = Instance.new("Frame")
				square.Position = UDim2.fromOffset(column * cell, row * cell)
				square.Size = UDim2.fromOffset(cell, cell)
				square.BackgroundColor3 = WHITE
				square.BackgroundTransparency = 0.93
				square.BorderSizePixel = 0
				square.Parent = holder
			end
		end
	end
end

-- Ventana centrada con sombra, cabecera degradada a cuadros con brillo y título que destella,
-- botón de cerrar y cuerpo con rayas diagonales suaves. Devuelve el marco y el cuerpo (donde
-- va el contenido). En pantallas pequeñas se encoge sola.
function Ui.window(name: string, title: string, size: Vector2, icon: ((Frame) -> ())?)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = Ui.screen()
	Ui.round(frame, 16)
	Ui.stroke(frame, BLACK, 5)
	Ui.gradient(frame, Color3.fromRGB(60, 66, 112), Color3.fromRGB(22, 24, 46), 90)

	-- Sombra detrás de la ventana: va aparte (los hijos se pintan encima) y la sigue.
	local shadow = Instance.new("Frame")
	shadow.Name = name .. "Shadow"
	shadow.AnchorPoint = frame.AnchorPoint
	shadow.Position = frame.Position + UDim2.fromOffset(8, 10)
	shadow.Size = frame.Size
	shadow.BackgroundColor3 = BLACK
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.Visible = false
	shadow.ZIndex = 0
	shadow.Parent = Ui.screen()
	Ui.round(shadow, 18)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		shadow.Visible = frame.Visible
	end)

	-- Bisel: una línea clara por dentro del borde.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(3, 3)
	rim.Size = UDim2.new(1, -6, 1, -6)
	rim.BackgroundTransparency = 1
	rim.Parent = frame
	Ui.round(rim, 13)
	local rimStroke = Ui.stroke(rim, WHITE, 2)
	rimStroke.Transparency = 0.82

	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local shadowScale = Instance.new("UIScale")
	shadowScale.Parent = shadow
	local camera = workspace.CurrentCamera
	local fitted = 1
	local function fit()
		local view = camera.ViewportSize
		-- Deja sitio a la izquierda para el menú y, como va centrada, arriba y abajo para los
		-- contadores (que llegan a ~100 px del borde).
		-- Hasta un 22 % más grande que su tamaño de diseño si la pantalla da para ello.
		fitted = math.clamp(math.min((view.X / 2 - 175) / (size.X / 2 + 100), (view.Y - 220) / size.Y), 0.45, MAX_WINDOW_SCALE)
		scale.Scale = fitted
		shadowScale.Scale = fitted
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
	-- Al abrirse, la ventana sale con un rebote desde un poco más pequeña.
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible and not Performance.get() then
			scale.Scale = fitted * 0.8
			shadowScale.Scale = fitted * 0.8
			local info = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(scale, info, { Scale = fitted }):Play()
			TweenService:Create(shadowScale, info, { Scale = fitted }):Play()
		end
	end)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 58)
	header.BackgroundColor3 = WHITE
	header.BorderSizePixel = 0
	header.Parent = frame
	Ui.round(header, 16)
	local headerColors = Instance.new("UIGradient")
	headerColors.Rotation = 8
	headerColors.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 165, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(140, 100, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 100, 215)),
	})
	headerColors.Parent = header
	checker(header, Vector2.new(size.X, 58), 14, 14)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(8, 3)
	gloss.Size = UDim2.new(1, -16, 0.42, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BorderSizePixel = 0
	gloss.Parent = header
	Ui.round(gloss, 10)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.68, 0.95)
	fade.Parent = gloss
	-- Franja oscura bajo la cabecera, para separarla del cuerpo.
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 1)
	edge.Size = UDim2.new(1, 0, 0, 4)
	edge.BackgroundColor3 = BLACK
	edge.BackgroundTransparency = 0.5
	edge.BorderSizePixel = 0
	edge.Parent = header

	-- Icono opcional a la izquierda del título (mochila, engranaje...), dibujado con marcos.
	if icon then
		local iconBox = Instance.new("Frame")
		iconBox.Name = "HeaderIcon"
		iconBox.Position = UDim2.fromOffset(12, 8)
		iconBox.Size = UDim2.fromOffset(44, 44)
		iconBox.BackgroundTransparency = 1
		iconBox.ZIndex = 3
		iconBox.Parent = header
		icon(iconBox)
	end

	local heading = Ui.label(header, 34)
	heading.Name = "Title"
	heading.Position = UDim2.fromOffset(if icon then 68 else 22, 0)
	heading.Size = UDim2.new(1, -90, 1, 0)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	heading.ZIndex = 3
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.42, WHITE),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 150)),
		ColorSequenceKeypoint.new(0.58, WHITE),
		ColorSequenceKeypoint.new(1, WHITE),
	})
	shine.Parent = heading
	shines[shine] = math.random() * 3

	local close = Ui.button(header, "X", Ui.COLORS.red)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(60, 58)
	close.TextSize = 30
	close.ZIndex = 3
	close.Activated:Connect(function()
		frame.Visible = false
	end)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(10, 68)
	body.Size = UDim2.new(1, -20, 1, -78)
	body.BackgroundColor3 = WHITE
	body.BorderSizePixel = 0
	body.Parent = frame
	Ui.round(body, 12)
	Ui.stroke(body, Ui.COLORS.dark, 3)
	Ui.gradient(body, Color3.fromRGB(66, 74, 124), Color3.fromRGB(30, 33, 64), 90)
	Ui.stripes(body, Vector2.new(size.X - 20, size.Y - 78), 26, 0.95)

	windows[name] = frame
	return frame, body
end

-- Para pantallas que no usan Ui.window pero deben abrirse y cerrarse como las demás.
function Ui.register(name: string, frame: GuiObject)
	windows[name] = frame
end

-- Abre la ventana (cerrando las demás) o la cierra si ya estaba abierta.
function Ui.toggle(name: string)
	local frame = windows[name]
	local open = not frame.Visible
	for _, other in windows do
		other.Visible = false
	end
	frame.Visible = open
end

function Ui.anyOpen(): boolean
	for _, frame in windows do
		if frame.Visible then
			return true
		end
	end
	return false
end

-- Casillas ------------------------------------------------------------------------------

-- Marcos animados de las casillas según el nivel de rareza (posición en Config.RarityTiers):
-- un brillo da vueltas por el borde, a la misma velocidad en todas (pedido por el usuario).
local SHINE_SPEED = 90 -- grados por segundo
local PULSE_FROM = 5 -- desde aquí el marco lleva además un halo que late
-- Las más raras llevan el borde de dos tonos (su color y este otro) con destellos blancos.
local DUO_TONES = {
	[7] = Color3.fromRGB(110, 60, 255), -- Secreta: rosa y violeta
	[8] = Color3.fromRGB(110, 175, 255), -- Divina: celeste y azul claro
}

local shines = {} -- [UIGradient del borde] = { speed, halo, phase }
local shining = false

local function animateShines(dt: number)
	if Performance.get() then
		return -- modo rendimiento: los marcos de las casillas se quedan quietos
	end
	local now = os.clock()
	for gradient, info in shines do
		gradient.Rotation = (gradient.Rotation + info.speed * dt) % 360
		if info.halo then
			info.halo.Transparency = 0.45 + 0.35 * math.sin(now * 4 + info.phase)
		end
	end
end

local function shineColors(color: Color3, tier: number): ColorSequence
	local tone = DUO_TONES[tier]
	if tone then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, tone),
			ColorSequenceKeypoint.new(0.22, color),
			ColorSequenceKeypoint.new(0.3, WHITE),
			ColorSequenceKeypoint.new(0.38, color),
			ColorSequenceKeypoint.new(0.5, tone),
			ColorSequenceKeypoint.new(0.72, color),
			ColorSequenceKeypoint.new(0.8, WHITE),
			ColorSequenceKeypoint.new(0.88, color),
			ColorSequenceKeypoint.new(1, tone),
		})
	end
	local dark = color:Lerp(BLACK, 0.45)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, dark),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(0.5, color:Lerp(WHITE, 0.8)),
		ColorSequenceKeypoint.new(0.65, color),
		ColorSequenceKeypoint.new(1, dark),
	})
end

-- Casilla cuadrada con borde del color que se le pase (la rareza). El tamaño lo pone quien la usa.
-- Con `tier` (nivel de rareza, 2 o más) el marco se anima.
function Ui.cell(parent: Instance, color: Color3, tier: number?): TextButton
	local cell = Instance.new("TextButton")
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BackgroundColor3 = color
	cell.Parent = parent
	Ui.round(cell, 10)
	Ui.pressable(cell, 1.08)
	-- Fondo teñido del color de la rareza: claro en la esquina de arriba y casi negro abajo.
	local back = Instance.new("UIGradient")
	back.Rotation = 115
	back.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 170, 180)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(80, 80, 92)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 26)),
	})
	back.Parent = cell

	-- Canto negro por dentro del marco, para que el borde de color destaque.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(2, 2)
	rim.Size = UDim2.new(1, -4, 1, -4)
	rim.BackgroundTransparency = 1
	rim.Parent = cell
	Ui.round(rim, 8)
	Ui.stroke(rim, BLACK, 2)

	-- Brillo de cristal en la mitad de arriba.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(4, 4)
	gloss.Size = UDim2.new(1, -8, 0.42, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BorderSizePixel = 0
	gloss.Parent = cell
	Ui.round(gloss, 7)
	local glossFade = Instance.new("UIGradient")
	glossFade.Rotation = 90
	glossFade.Transparency = NumberSequence.new(0.8, 1)
	glossFade.Parent = gloss

	-- Sombra abajo, detrás del texto de la casilla.
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.new(0, 4, 1, -4)
	shade.Size = UDim2.new(1, -8, 0.42, 0)
	shade.BackgroundColor3 = BLACK
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Parent = cell
	Ui.round(shade, 7)
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Rotation = 90
	shadeFade.Transparency = NumberSequence.new(1, 0.4)
	shadeFade.Parent = shade

	local level = tier or 1
	if level < 2 then
		Ui.stroke(cell, color, 4)
	else
		-- El degradado tiñe el borde, así que el borde va en blanco.
		local border = Ui.stroke(cell, WHITE, 6)
		local shine = Instance.new("UIGradient")
		shine.Color = shineColors(color, level)
		shine.Rotation = math.random(0, 359)
		shine.Parent = border

		local halo = nil
		if level >= PULSE_FROM then
			local aura = Instance.new("Frame")
			aura.Name = "Halo"
			-- Por fuera del borde (6 px), sin llegar a la casilla de al lado.
			aura.Position = UDim2.fromOffset(-6, -6)
			aura.Size = UDim2.new(1, 12, 1, 12)
			aura.BackgroundTransparency = 1
			aura.ZIndex = 0
			aura.Parent = cell
			Ui.round(aura, 15)
			halo = Ui.stroke(aura, color:Lerp(WHITE, 0.3), 2)
		end

		shines[shine] = { speed = SHINE_SPEED, halo = halo, phase = math.random() * 6 }
		cell.Destroying:Connect(function()
			shines[shine] = nil
		end)
		if not shining then
			shining = true
			RunService.RenderStepped:Connect(animateShines)
		end
	end

	local glow = Instance.new("Frame")
	glow.Name = "Select"
	glow.Position = UDim2.fromOffset(3, 3)
	glow.Size = UDim2.new(1, -6, 1, -6)
	glow.BackgroundTransparency = 1
	glow.Visible = false
	glow.Parent = cell
	Ui.round(glow, 8)
	Ui.stroke(glow, WHITE, 3)
	return cell
end

-- Texto en la parte de abajo de la casilla (cantidad, daño...).
function Ui.cellLabel(cell: Instance, text: string): TextLabel
	local label = Ui.label(cell, 18)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -2)
	label.Size = UDim2.new(1, -4, 0, 22)
	label.TextScaled = true
	label.Text = text
	label.ZIndex = 3
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 21
	limit.MinTextSize = 10
	limit.Parent = label
	return label
end

-- Etiqueta pequeña en una esquina de la casilla (la "E" de equipada).
function Ui.cellTag(cell: Instance, text: string, color: Color3)
	local tag = Ui.label(cell, 14)
	tag.Position = UDim2.fromOffset(4, 4)
	tag.Size = UDim2.fromOffset(22, 22)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = color
	tag.Text = text
	tag.ZIndex = 3
	Ui.round(tag, 6)
	Ui.stroke(tag, BLACK, 2)
end

local function piece(parent: Instance, size: UDim2, position: UDim2, color: Color3, radius: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, radius)
	Ui.stroke(frame, BLACK, 2)
	return frame
end

local function iconHolder(parent: Instance, rotation: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.44)
	holder.Size = UDim2.fromScale(0.8, 0.8)
	holder.BackgroundTransparency = 1
	holder.Rotation = rotation
	holder.Parent = parent
	return holder
end

-- Iconos hechos con marcos (no hay imágenes propias).
function Ui.swordIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 45)
	local blade = piece(holder, UDim2.fromScale(0.2, 0.66), UDim2.fromScale(0.5, 0.36), color, 4)
	Ui.gradient(blade, WHITE, Color3.fromRGB(170, 170, 180), 0)
	piece(holder, UDim2.fromScale(0.14, 0.22), UDim2.fromScale(0.5, 0.86), Color3.fromRGB(120, 75, 45), 3)
	piece(holder, UDim2.fromScale(0.52, 0.1), UDim2.fromScale(0.5, 0.72), Color3.fromRGB(235, 190, 60), 3)
end

function Ui.gemIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 45)
	local gem = piece(holder, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), color, 6)
	Ui.gradient(gem, WHITE, Color3.fromRGB(150, 150, 170), 45)
	local shine = piece(gem, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.32, 0.32), WHITE, 3)
	shine.BackgroundTransparency = 0.35
end

function Ui.orbIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	local ring = piece(holder, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(235, 190, 60), 100)
	Ui.gradient(ring, WHITE, Color3.fromRGB(170, 150, 120), 90)
	local orb = piece(ring, UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.5, 0.5), color, 100)
	Ui.gradient(orb, WHITE, Color3.fromRGB(150, 150, 170), 60)
end

function Ui.boxIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	local box = piece(holder, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), color, 5)
	Ui.gradient(box, WHITE, Color3.fromRGB(170, 160, 150), 90)
	piece(box, UDim2.fromScale(1, 0.16), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(90, 60, 35), 0)
end

-- Mochila: asa arriba, cuerpo con solapa, bolsillo, hebilla dorada y correas a los lados. `color` es el
-- del cuerpo.
function Ui.backpackIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	holder.Size = UDim2.fromScale(0.92, 0.92)
	local dark = color:Lerp(BLACK, 0.45)
	local light = color:Lerp(WHITE, 0.35)
	local handle = piece(holder, UDim2.fromScale(0.34, 0.3), UDim2.fromScale(0.5, 0.15), dark, 100)
	handle.BackgroundTransparency = 1
	Ui.stroke(handle, dark, 4)
	for _, side in { 0.1, 0.9 } do
		local strap = piece(holder, UDim2.fromScale(0.13, 0.36), UDim2.fromScale(side, 0.64), dark, 4)
		Ui.gradient(strap, WHITE, Color3.fromRGB(150, 150, 160), 90)
	end
	local body = piece(holder, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.6), color, 12)
	Ui.gradient(body, WHITE, Color3.fromRGB(160, 160, 175), 90)
	local flap = piece(body, UDim2.fromScale(1, 0.4), UDim2.fromScale(0.5, 0.2), light, 12)
	Ui.gradient(flap, WHITE, Color3.fromRGB(190, 190, 200), 90)
	local pocket = piece(body, UDim2.fromScale(0.62, 0.3), UDim2.fromScale(0.5, 0.76), dark:Lerp(color, 0.5), 8)
	Ui.gradient(pocket, WHITE, Color3.fromRGB(170, 170, 185), 90)
	piece(body, UDim2.fromScale(0.22, 0.16), UDim2.fromScale(0.5, 0.42), Color3.fromRGB(245, 200, 60), 4)
end

-- Mejoras: hexágono (como los nodos del árbol) con una flecha doble hacia arriba.
function Ui.upgradeIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	holder.Size = UDim2.fromScale(0.92, 0.92)
	local _, outer = Ui.hex(holder, 46, BLACK)
	local _, middle = Ui.hex(holder, 40, color)
	local _, inner = Ui.hex(holder, 32, color:Lerp(WHITE, 0.3))
	for _, group in { outer, middle, inner } do
		for _, frame in group do
			frame.ZIndex = 1
		end
	end
	for _, y in { 0.6, 0.38 } do
		for _, side in { -1, 1 } do
			local bar = piece(holder, UDim2.fromScale(0.34, 0.12), UDim2.fromScale(0.5 + side * 0.11, y), WHITE, 3)
			bar.Rotation = side * 38
			bar.ZIndex = 3
		end
	end
end

-- Hexágono (punta arriba) de `width` de ancho, hecho con tres rectángulos girados.
-- Devuelve el contenedor y sus tres piezas, para poder cambiarles el color.
function Ui.hex(parent: Instance, width: number, color: Color3)
	local side = width / math.sqrt(3)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(width, side * 2)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local pieces = {}
	for index = 0, 2 do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(width, side)
		frame.Rotation = index * 60
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Parent = holder
		table.insert(pieces, frame)
	end
	return holder, pieces
end

-- Engranaje hecho con marcos (la fuente no tiene el icono): dientes, aro y agujero.
function Ui.gearIcon(parent: GuiObject)
	local holder = Instance.new("Frame")
	holder.Name = "Gear"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(40, 40)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local metal = Color3.fromRGB(230, 233, 240)
	for tooth = 0, 3 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(44, 9)
		bar.Rotation = tooth * 45
		bar.BackgroundColor3 = metal
		bar.BorderSizePixel = 0
		bar.Parent = holder
		Ui.round(bar, 3)
	end
	local wheel = Instance.new("Frame")
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(28, 28)
	wheel.BackgroundColor3 = metal
	wheel.Parent = holder
	Ui.round(wheel, 14)
	Ui.stroke(wheel, BLACK, 2)
	local hole = Instance.new("Frame")
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromOffset(12, 12)
	hole.BackgroundColor3 = Color3.fromRGB(80, 84, 98)
	hole.Parent = wheel
	Ui.round(hole, 6)
	Ui.stroke(hole, BLACK, 2)
	return holder
end


-- Deslizador horizontal (0 a 1): barra con relleno en degradado y un botón redondo que se arrastra
-- con el ratón o el dedo. `onChange` recibe el valor al moverlo. Devuelve el marco y una función
-- para ponerle un valor sin avisar.
function Ui.slider(parent: Instance, initial: number, onChange: (number) -> ()): (Frame, (number) -> ())
	local track = Instance.new("Frame")
	track.Name = "Slider"
	track.Size = UDim2.fromOffset(300, 22)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.Parent = parent
	Ui.round(track, 11)
	Ui.stroke(track, BLACK, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(initial, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Ui.round(fill, 11)
	Ui.gradient(fill, Color3.fromRGB(120, 235, 110), Color3.fromRGB(40, 170, 70), 90)
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(initial, 0.5)
	knob.Size = UDim2.fromOffset(34, 34)
	knob.BackgroundColor3 = WHITE
	knob.ZIndex = 3
	knob.Parent = track
	Ui.round(knob, 17)
	Ui.stroke(knob, BLACK, 3)
	Ui.gradient(knob, WHITE, Color3.fromRGB(190, 195, 215), 90)
	-- Zona de agarre más alta que la barra (cómoda para el dedo).
	local grab = Instance.new("TextButton")
	grab.Text = ""
	grab.AutoButtonColor = false
	grab.BackgroundTransparency = 1
	grab.AnchorPoint = Vector2.new(0.5, 0.5)
	grab.Position = UDim2.fromScale(0.5, 0.5)
	grab.Size = UDim2.new(1, 40, 0, 48)
	grab.ZIndex = 4
	grab.Parent = track

	local function set(value: number)
		value = math.clamp(value, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
	end
	local dragging = false
	local function drag(x: number)
		local value = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(value)
		onChange(value)
	end
	grab.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			drag(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			drag(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return track, set
end

-- Cartel flotante --------------------------------------------------------------------------

local tip, tipStroke, tipSource
local tipBeside = false
local tipLive: (() -> (string, Color3, boolean?))? = nil

local function ensureTip()
	if tip then
		return
	end
	tip = Ui.label(Ui.screen(), 21)
	tip.Name = "Tip"
	tip.BackgroundTransparency = 0.04
	tip.BackgroundColor3 = Ui.COLORS.dark
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Size = UDim2.fromOffset(0, 0)
	tip.Visible = false
	tip.ZIndex = 100
	tip.Active = false
	Ui.round(tip, 10)
	tipStroke = Ui.stroke(tip, WHITE, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = tip

	RunService.RenderStepped:Connect(function()
		if not tip.Visible then
			return
		end
		-- Si la casilla desaparece o se cierra su ventana, el cartel se quita.
		local ancestor = tipSource
		while ancestor and ancestor:IsA("GuiObject") do
			if not ancestor.Visible then
				ancestor = nil
				break
			end
			ancestor = ancestor.Parent
		end
		if not ancestor or not tipSource:IsDescendantOf(game) then
			tip.Visible = false
			return
		end
		if tipLive and not Performance.get() then
			local text, color = tipLive()
			tip.Text = text
			tipStroke.Color = color
		end
		local mouse = UserInputService:GetMouseLocation() -- la pantalla Hud ignora la franja de arriba
		local view = workspace.CurrentCamera.ViewportSize
		local size = tip.AbsoluteSize
		local x = mouse.X + 18
		local top = mouse.Y + 14
		if x + size.X > view.X - 8 then
			x = mouse.X - size.X - 12
		end
		if tipBeside then
			-- Pegado al lado de la casilla, para no tapar lo que se está mirando.
			local corner, box = tipSource.AbsolutePosition + GuiService:GetGuiInset(), tipSource.AbsoluteSize
			x = corner.X + box.X + 10
			if x + size.X > view.X - 8 then
				x = corner.X - size.X - 10
			end
			top = corner.Y
		end
		local y = math.clamp(top, 0, math.max(0, view.Y - size.Y - 50))
		tip.Position = UDim2.fromOffset(x, y)
	end)
end

-- Al pasar el ratón por `target` muestra un cartel con lo que devuelva getContent(): texto
-- (RichText, varias líneas) y color del borde. Con `beside` el cartel se pega al lado de `target`
-- en vez de seguir al ratón.
-- En pantallas táctiles no hay "pasar el ratón": se enseña con una pulsación larga (0,35 s) y se
-- quita solo a los 2,5 s de soltar.
function Ui.tip(target: GuiObject, getContent: () -> (string, Color3), beside: boolean?)
	ensureTip()
	local function open(forceBeside: boolean)
		local text, color, live = getContent()
		tip.Text = text
		tipStroke.Color = color
		-- Con un tercer valor `true`, el cartel se vuelve a pedir cada fotograma (texto animado).
		tipLive = if live then getContent else nil
		tipSource = target
		tipBeside = forceBeside or beside == true
		tip.Visible = true
	end
	target.MouseEnter:Connect(function()
		open(false)
	end)
	target.MouseLeave:Connect(function()
		if tipSource == target then
			tip.Visible = false
		end
	end)
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pressing = true
		local watch
		watch = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				pressing = false
				watch:Disconnect()
				task.delay(2.5, function()
					if tipSource == target and not pressing then
						tip.Visible = false
					end
				end)
			end
		end)
		task.delay(0.35, function()
			if pressing then
				open(true)
			end
		end)
	end)
end

-- Avisos ----------------------------------------------------------------------------------

local toasts: Frame? = nil
local MAX_TOASTS = 4

-- Icono según de qué habla el aviso (no hay imágenes: se dibuja con marcos). Los rojos llevan "!".
local function toastIcon(parent: Frame, text: string, color: Color3)
	local lower = string.lower(text)
	if string.find(lower, "gema", 1, true) or string.find(lower, "cristal", 1, true) then
		Ui.gemIcon(parent, color)
	elseif string.find(lower, "moneda", 1, true) then
		Ui.orbIcon(parent, color)
	elseif string.find(lower, "espada", 1, true) or string.find(lower, "hacha", 1, true) or string.find(lower, "lanza", 1, true) or string.find(lower, "martillo", 1, true) or string.find(lower, "arma", 1, true) then
		Ui.swordIcon(parent, color)
	elseif color.R > 0.7 and color.G < 0.5 and color.B < 0.5 then
		local mark = Ui.label(parent, 34)
		mark.Size = UDim2.fromScale(1, 1)
		mark.Text = "!"
		mark.TextColor3 = color
	else
		Ui.boxIcon(parent, color)
	end
end

-- Aviso en pantalla: se apilan hasta MAX_TOASTS (los nuevos entran por abajo con rebote, los viejos
-- suben), con el icono de lo que cuentan, una barra de su color y desvanecido al final.
function Ui.toast(text: string, color: Color3)
	if not toasts then
		local list = Instance.new("Frame")
		list.Name = "Toasts"
		list.AnchorPoint = Vector2.new(0.5, 1)
		list.Position = UDim2.new(0.5, 0, 1, -96) -- por encima de los botones de tirar
		list.Size = UDim2.fromOffset(470, 0)
		list.AutomaticSize = Enum.AutomaticSize.Y
		list.BackgroundTransparency = 1
		list.ZIndex = 50
		list.Parent = Ui.screen()
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = list
		toasts = list
	end
	local list = toasts :: Frame
	Sfx.play(if color.R > 0.7 and color.G < 0.5 and color.B < 0.5 then "error" else "toast")
	local existing = {}
	for _, child in list:GetChildren() do
		if child:IsA("CanvasGroup") then
			table.insert(existing, child)
		end
	end
	if #existing >= MAX_TOASTS then
		existing[1]:Destroy()
	end

	local item = Instance.new("CanvasGroup")
	item.Name = "Toast"
	item.LayoutOrder = os.clock() * 1000
	item.Size = UDim2.new(1, 0, 0, 58)
	item.BackgroundColor3 = WHITE
	item.GroupTransparency = 1
	item.ZIndex = 50
	item.Parent = list
	Ui.round(item, 14)
	Ui.stroke(item, BLACK, 4)
	Ui.gradient(item, Color3.fromRGB(70, 74, 98), Color3.fromRGB(28, 29, 40), 90)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = item

	-- Barra de color a la izquierda y brillo arriba.
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 8, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = 51
	bar.Parent = item
	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.fromOffset(10, 3)
	gloss.Size = UDim2.new(1, -16, 0.4, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.88
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 51
	gloss.Parent = item
	Ui.round(gloss, 8)
	local iconBox = Instance.new("Frame")
	iconBox.Position = UDim2.fromOffset(16, 5)
	iconBox.Size = UDim2.fromOffset(48, 48)
	iconBox.BackgroundTransparency = 1
	iconBox.ZIndex = 52
	iconBox.Parent = item
	toastIcon(iconBox, text, color)
	local label = Ui.label(item, 23)
	label.Position = UDim2.fromOffset(72, 0)
	label.Size = UDim2.new(1, -82, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.RichText = false
	label.TextColor3 = color:Lerp(WHITE, 0.35)
	label.Text = text
	label.ZIndex = 52
	for _, descendant in item:GetDescendants() do
		if descendant:IsA("GuiObject") and descendant.ZIndex < 52 and descendant ~= bar and descendant ~= gloss then
			descendant.ZIndex = 52
		end
	end

	local pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(item, pop, { GroupTransparency = 0 }):Play()
	TweenService:Create(scale, pop, { Scale = 1 }):Play()
	task.delay(3.8, function()
		if item.Parent then
			local fade = TweenService:Create(item, TweenInfo.new(0.4), { GroupTransparency = 1 })
			fade.Completed:Connect(function()
				item:Destroy()
			end)
			fade:Play()
		end
	end)
end

return Ui
