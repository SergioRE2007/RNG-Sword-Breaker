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
local TextService = game:GetService("TextService")
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

-- Medidas comunes del relieve: borde negro, labio de abajo (parte del alto del botón), radios y lo que crece
-- o se encoge un botón al pasar el ratón y al pulsarlo.
Ui.STYLE = { border = 3, lip = 0.13, radius = 12, cellRadius = 10, hover = 1.07, press = 0.95 }

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
-- Piezas del relieve de un botón (Ui.bevel y Ui.pressable), por nombre.
local RELIEF = { "Rim", "Gloss", "Shine", "Base", "Hover", "Press" }

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

	-- Línea de brillo pegada al borde de arriba: el filo donde da la luz.
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 3)
	shine.Size = UDim2.new(1, -radius * 2, 0, 3) -- 3 px: con el HUD encogido a 0.55 aún se ve
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.35
	shine.BorderSizePixel = 0
	shine.Parent = instance
	Ui.round(shine, 1)

	-- Labio oscuro abajo (el "grosor" del botón): crece con el botón, entre 3 y 7 px, y se oscurece hacia abajo.
	-- Ui.pressable lo aplasta al pulsar.
	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 1)
	base.Position = UDim2.new(0.5, 0, 1, -2)
	base.Size = UDim2.new(1, -6, Ui.STYLE.lip, 0)
	base.BackgroundColor3 = BLACK
	base.BorderSizePixel = 0
	base.Parent = instance
	Ui.round(base, math.max(radius - 5, 2))
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(0, 3)
	limit.MaxSize = Vector2.new(math.huge, 7)
	limit.Parent = base
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new(0.86, 0.6)
	shade.Parent = base

	-- La interfaz ordena el ZIndex globalmente: si a un botón se le sube la capa a mano, su relieve se quedaba
	-- por debajo y se veía plano. Las piezas del relieve (y las de Ui.pressable) siguen la capa del botón.
	local function follow()
		for _, name in RELIEF do
			local part = instance:FindFirstChild(name)
			if part then
				(part :: GuiObject).ZIndex = instance.ZIndex
			end
		end
	end
	follow()
	instance:GetPropertyChangedSignal("ZIndex"):Connect(follow)
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
	-- Los estados (ratón encima, pulsado) los pinta Ui.pressable, no el oscurecido de Roblox.
	item.AutoButtonColor = false
	item.TextColor3 = WHITE
	item.Font = Ui.FONT
	item.TextSize = 17
	item.TextWrapped = true
	item.Text = text
	item.Parent = parent
	Ui.round(item, Ui.STYLE.radius)
	Ui.bevel(item)
	Ui.stroke(item, BLACK, Ui.STYLE.border)
	Ui.textStroke(item, 2)
	Ui.pressable(item)
	return item
end

-- Superficie de fila o tarjeta con profundidad (el "nada plano" del juego): degradado de `base` (más
-- claro arriba, más oscuro abajo), brillo de cristal arriba y canto claro por dentro. Con `accent`,
-- una franja de ese color a la izquierda y un resplandor suave que sale de ella: dice de un vistazo de
-- qué es la fila (su rareza, su tipo...). El borde negro lo pone quien la llama. Va antes que el
-- contenido, para quedar por debajo.
function Ui.panel(frame: GuiObject, base: Color3, accent: Color3?)
	frame.BackgroundColor3 = WHITE
	Ui.gradient(frame, base:Lerp(WHITE, 0.14), base:Lerp(BLACK, 0.38), 90)
	local corner = frame:FindFirstChildOfClass("UICorner")
	local radius = if corner then corner.CornerRadius.Offset else 10

	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Position = UDim2.fromOffset(2, 2)
	rim.Size = UDim2.new(1, -4, 1, -4)
	rim.BackgroundTransparency = 1
	rim.ZIndex = frame.ZIndex
	rim.Parent = frame
	Ui.round(rim, math.max(radius - 2, 2))
	Ui.stroke(rim, WHITE, 1.5).Transparency = 0.86

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(4, 3)
	gloss.Size = UDim2.new(1, -8, 0.45, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BorderSizePixel = 0
	gloss.ZIndex = frame.ZIndex
	gloss.Parent = frame
	Ui.round(gloss, math.max(radius - 4, 2))
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.84, 1)
	fade.Parent = gloss

	if accent then
		local glow = Instance.new("Frame")
		glow.Name = "AccentGlow"
		glow.Size = UDim2.fromScale(0.45, 1)
		glow.BackgroundColor3 = accent
		glow.BorderSizePixel = 0
		glow.ZIndex = frame.ZIndex
		glow.Parent = frame
		Ui.round(glow, radius)
		local spread = Instance.new("UIGradient")
		spread.Transparency = NumberSequence.new(0.72, 1)
		spread.Parent = glow
		local stripe = Instance.new("Frame")
		stripe.Name = "Accent"
		stripe.AnchorPoint = Vector2.new(0, 0.5)
		stripe.Position = UDim2.new(0, 5, 0.5, 0)
		stripe.Size = UDim2.new(0, 5, 1, -14)
		stripe.BackgroundColor3 = WHITE
		stripe.BorderSizePixel = 0
		stripe.ZIndex = frame.ZIndex
		stripe.Parent = frame
		Ui.round(stripe, 3)
		Ui.gradient(stripe, accent:Lerp(WHITE, 0.45), accent, 90)
	end
end

-- Sombra exterior: una copia oscura del marco, caída `drop` px, una capa por debajo (la interfaz ordena el ZIndex
-- globalmente, así que un hijo con menos ZIndex que su padre se pinta detrás). Separa del fondo lo que flota
-- sobre el juego (HUD). Sigue la capa del marco si se le cambia.
function Ui.shadow(frame: GuiObject, drop: number?): Frame
	local corner = frame:FindFirstChildOfClass("UICorner")
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, drop or 5)
	shadow.Size = UDim2.new(1, Ui.STYLE.border * 2, 1, Ui.STYLE.border * 2)
	shadow.BackgroundColor3 = BLACK
	shadow.BackgroundTransparency = 0.62
	shadow.BorderSizePixel = 0
	shadow.ZIndex = frame.ZIndex - 1
	shadow.Parent = frame
	Ui.round(shadow, (if corner then corner.CornerRadius.Offset else 10) + Ui.STYLE.border)
	frame:GetPropertyChangedSignal("ZIndex"):Connect(function()
		shadow.ZIndex = frame.ZIndex - 1
	end)
	return shadow
end

-- Contador o chip con relieve: fondo del color, labio, borde negro y sombra exterior.
function Ui.pill(frame: GuiObject, color: Color3, radius: number?)
	frame.BackgroundColor3 = color
	Ui.round(frame, radius or 14)
	Ui.bevel(frame)
	Ui.stroke(frame, BLACK, Ui.STYLE.border)
	Ui.shadow(frame)
end

-- Marca un botón (pestaña, opción) como elegido: borde blanco. El primer UIStroke directo del botón es su borde.
function Ui.setSelected(button: GuiObject, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then WHITE else BLACK
	end
end

-- Caja de texto con el estilo del juego: hueco oscuro, borde negro, sombra por dentro arriba y filo claro abajo.
-- Sin degradado en la propia caja: teñiría también lo que se escribe.
function Ui.field(box: TextBox)
	box.BackgroundColor3 = Ui.COLORS.dark
	box.TextColor3 = WHITE
	box.PlaceholderColor3 = Color3.fromRGB(120, 124, 140)
	box.Font = Ui.FONT
	Ui.round(box, 8)
	Ui.stroke(box, BLACK, 2)
	for _, edge in { { 0, BLACK, 0.55, 5 }, { 1, WHITE, 0.8, 2 } } do
		local line = Instance.new("Frame")
		line.Name = if edge[1] == 0 then "Shade" else "Edge"
		line.AnchorPoint = Vector2.new(0.5, edge[1])
		line.Position = UDim2.new(0.5, 0, edge[1], if edge[1] == 0 then 1 else -1)
		line.Size = UDim2.new(1, -8, 0, edge[4])
		line.BackgroundColor3 = edge[2]
		line.BackgroundTransparency = edge[3]
		line.BorderSizePixel = 0
		line.ZIndex = box.ZIndex
		line.Parent = box
		Ui.round(line, 3)
	end
end

-- Pone `root` y todo lo suyo en la capa `z`. La interfaz ordena el ZIndex globalmente: un botón con
-- relieve (Ui.button) subido de capa dejaba su brillo, su canto y su icono por debajo, y se veía plano.
-- Con todo en la misma capa manda el orden del árbol y el relieve vuelve a quedar encima.
function Ui.layer(root: GuiObject, z: number)
	root.ZIndex = z
	for _, part in root:GetDescendants() do
		if part:IsA("GuiObject") then
			part.ZIndex = z
		end
	end
end

-- Estados de un botón o casilla. Al pasar el ratón crece y se aclara; al pulsar se hunde: encoge, el labio de
-- abajo (el `Base` de Ui.bevel, si lo tiene) se aplasta y le cae una sombra por arriba. En modo rendimiento
-- no hay rebotes, pero el aclarado y el hundido se siguen viendo (sin animar).
function Ui.pressable(item: GuiButton, grow: number?)
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = item
	local big = grow or Ui.STYLE.hover
	local corner = item:FindFirstChildOfClass("UICorner")
	local radius = if corner then corner.CornerRadius.Offset else 10
	local function overlay(name: string, color: Color3): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = item.ZIndex
		frame.Parent = item
		Ui.round(frame, radius)
		return frame
	end
	-- Solo los botones con relieve (los de Ui.bevel) llevan aclarado y sombra de pulsado. Las casillas se quedan
	-- con el rebote: hay rejillas de cientos y serían muchas piezas de más.
	local base = item:FindFirstChild("Base")
	local hover: Frame? = nil
	local press: Frame? = nil
	if base then
		hover = overlay("Hover", WHITE)
		press = overlay("Press", BLACK)
		-- La sombra de pulsado cae desde arriba y se apaga hacia abajo.
		local fall = Instance.new("UIGradient")
		fall.Rotation = 90
		fall.Transparency = NumberSequence.new(0, 0.7)
		fall.Parent = press
	end

	local function tween(target: Instance, goal, time: number, style: Enum.EasingStyle?)
		if Performance.get() then
			for property, value in goal do
				(target :: any)[property] = value
			end
			return
		end
		TweenService:Create(target, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end
	local function to(value: number, time: number, style: Enum.EasingStyle)
		-- Modo rendimiento: sin rebotes.
		tween(scale, { Scale = if Performance.get() then 1 else value }, time, style)
	end
	local over = false
	local function pressed(down: boolean)
		if press and base then
			tween(press, { BackgroundTransparency = if down then 0.72 else 1 }, 0.07)
			tween(base, { Size = UDim2.new(1, -6, if down then 0.02 else Ui.STYLE.lip, 0) }, if down then 0.07 else 0.16)
		end
	end
	local function lit(on: boolean)
		if hover then
			tween(hover, { BackgroundTransparency = if on then 0.86 else 1 }, 0.12)
		end
	end
	local held: RBXScriptConnection? = nil
	local function release()
		if held then
			held:Disconnect()
			held = nil
		end
		to(if over then big else 1, 0.2, Enum.EasingStyle.Back)
		pressed(false)
	end
	item.Activated:Connect(function()
		Sfx.play("click")
	end)
	item.MouseEnter:Connect(function()
		over = true
		to(big, 0.18, Enum.EasingStyle.Back)
		lit(true)
		-- Solo los botones (los que tienen labio): en una rejilla de casillas sería un repiqueteo.
		if base then
			Sfx.play("tick", 0.3)
		end
	end)
	item.MouseLeave:Connect(function()
		over = false
		lit(false)
		release()
	end)
	item.MouseButton1Down:Connect(function()
		to(Ui.STYLE.press, 0.07, Enum.EasingStyle.Quad)
		pressed(true)
		-- Se suelta aunque el dedo o el ratón se levanten fuera del botón (al arrastrar una lista en táctil no
		-- llegan ni MouseButton1Up ni MouseLeave, y se quedaba hundido).
		if not held then
			held = UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					release()
				end
			end)
		end
	end)
	item.MouseButton1Up:Connect(release)
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

-- Capa del HUD (contadores, barra de transporte, menú, estadísticas, gacha, avisos). Ocupa toda la
-- pantalla y lleva un solo UIScale: en pantallas pequeñas (móvil apaisado, 4:3 pequeño) todo el HUD
-- se encoge a la vez en vez de pisarse, y cada pieza sigue pegada a su borde. Para que eso pase, la
-- capa mide pantalla / escala. Desde HUD_SIZE para arriba la escala es 1 y no cambia nada. Las
-- ventanas no van aquí: Ui.window ya se escala sola.
local HUD_SIZE = Vector2.new(1100, 700)
local HUD_MIN_SCALE = 0.55
local hudRoot: Frame? = nil
function Ui.hud(): Frame
	if not hudRoot then
		local root = Instance.new("Frame")
		root.Name = "HudRoot"
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.BackgroundTransparency = 1
		root.Parent = Ui.screen()
		local scale = Instance.new("UIScale")
		scale.Parent = root
		local camera = workspace.CurrentCamera
		local function fit()
			local view = camera.ViewportSize
			local factor = math.clamp(math.min(view.X / HUD_SIZE.X, view.Y / HUD_SIZE.Y), HUD_MIN_SCALE, 1)
			scale.Scale = factor
			root.Size = UDim2.fromOffset(view.X / factor, view.Y / factor)
		end
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		fit()
		hudRoot = root
	end
	return hudRoot :: Frame
end

-- Ventanas ------------------------------------------------------------------------------

local windows = {} -- [nombre] = Frame
local MAX_WINDOW_SCALE = 1.22 -- las ventanas crecen hasta aquí en pantallas grandes

-- Transiciones: las ventanas entran desde abajo y salen hacia abajo. `Visible` sigue siendo el estado lógico (los
-- menús lo escuchan para limpiar al cerrarse), así que al cerrar se pone a false cuando la ventana ya ha bajado.
-- Las ventanas pequeñas (`popup`) hacen lo mismo con un recorrido corto. Abrir y cerrar con Ui.open / Ui.close.
local MOTION = {
	window = { open = 0.34, close = 0.22 }, -- sin `travel`: baja hasta salir entera de la pantalla
	popup = { open = 0.22, close = 0.16, travel = 0.06 }, -- `travel` en fracción del alto de la pantalla
}
local OPEN_SCALE = 0.97 -- escala desde la que entra (y a la que sale)

type Motion = {
	frame: GuiObject,
	kind: { open: number, close: number, travel: number? },
	state: string, -- "closed", "opening", "open" o "closing"
	home: UDim2,
	travel: number,
	scale: UIScale?,
	size: () -> number,
	shadow: GuiObject?,
	shadowScale: UIScale?,
	gap: UDim2,
	tweens: { Tween },
}
local motions: { [GuiObject]: Motion } = {}

local function stopMotion(m: Motion)
	for _, tween in m.tweens do
		tween:Cancel()
	end
	table.clear(m.tweens)
end

-- Deja el marco en su sitio y a su escala.
local function settle(m: Motion)
	m.frame.Position = m.home
	if m.shadow then
		m.shadow.Position = m.home + m.gap
	end
	if m.scale then
		m.scale.Scale = m.size()
	end
	if m.shadowScale then
		m.shadowScale.Scale = m.size()
	end
end

-- Cuánto hay que bajar el marco (en fracción del alto de su pantalla) para que quede entero por debajo del borde.
-- Sale de su posición y tamaño de casa, no de los Absolute (que en un marco invisible pueden no estar al día).
local function travelOf(m: Motion): number
	if m.kind.travel then
		return m.kind.travel
	end
	local parent = m.frame.Parent
	local height = if parent and parent:IsA("GuiBase2d") then parent.AbsoluteSize.Y else workspace.CurrentCamera.ViewportSize.Y
	height = math.max(height, 1)
	local size = m.frame.Size
	local tall = (size.Y.Scale * height + size.Y.Offset) * (if m.scale then m.size() else 1)
	local top = m.home.Y.Scale * height + m.home.Y.Offset - m.frame.AnchorPoint.Y * tall
	return math.max(height - top, 0) / height + 0.02
end

local function animate(m: Motion, opening: boolean)
	stopMotion(m)
	local time = if opening then m.kind.open else m.kind.close
	local move = if opening
		then TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		else TweenInfo.new(time, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	-- El pop: la escala llega con un poco de rebote al abrir.
	local pop = if opening then TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out) else move
	local target = if opening then m.home else m.home + UDim2.fromScale(0, m.travel)
	local size = m.size() * (if opening then 1 else OPEN_SCALE)

	local main = TweenService:Create(m.frame, move, { Position = target })
	table.insert(m.tweens, main)
	if m.shadow then
		table.insert(m.tweens, TweenService:Create(m.shadow, move, { Position = target + m.gap }))
	end
	if m.scale then
		table.insert(m.tweens, TweenService:Create(m.scale, pop, { Scale = size }))
	end
	if m.shadowScale then
		table.insert(m.tweens, TweenService:Create(m.shadowScale, pop, { Scale = size }))
	end
	main.Completed:Connect(function(status)
		if status ~= Enum.PlaybackState.Completed then
			return -- cancelada: ya manda la transición nueva
		end
		if not table.find(m.tweens, main) then
			return -- llegó tarde (señales diferidas) y ya hay otra transición en marcha
		end
		-- Las demás (escala, sombra) acaban en el mismo frame: se cortan ya para que no pisen el ajuste final.
		stopMotion(m)
		settle(m)
		if opening then
			m.state = "open"
		else
			m.state = "closed"
			m.frame.Visible = false
		end
	end)
	for _, tween in m.tweens do
		tween:Play()
	end
end

-- Abre con su transición. Si ya está abierta o abriéndose no hace nada; si se estaba cerrando, vuelve a subir desde ahí.
function Ui.open(frame: GuiObject)
	local m = motions[frame]
	if not m then
		frame.Visible = true
		return
	end
	if m.state == "open" or m.state == "opening" then
		return
	end
	if m.state == "closed" then
		m.home = frame.Position
		m.travel = travelOf(m)
	end
	if Performance.get() then
		stopMotion(m)
		m.state = "open"
		settle(m)
		frame.Visible = true
		return
	end
	if m.state == "closed" then
		m.frame.Position = m.home + UDim2.fromScale(0, m.travel)
		if m.shadow then
			m.shadow.Position = m.frame.Position + m.gap
		end
		if m.scale then
			m.scale.Scale = m.size() * OPEN_SCALE
		end
		if m.shadowScale then
			m.shadowScale.Scale = m.size() * OPEN_SCALE
		end
	end
	m.state = "opening"
	frame.Visible = true
	animate(m, true)
end

-- Cierra con su transición y pone Visible = false al acabar. Si ya está cerrada o cerrándose no hace nada.
function Ui.close(frame: GuiObject)
	local m = motions[frame]
	if not m then
		frame.Visible = false
		return
	end
	if m.state == "closed" or m.state == "closing" then
		return
	end
	if Performance.get() or not frame.Visible then
		stopMotion(m)
		m.state = "closed"
		settle(m)
		frame.Visible = false
		return
	end
	m.state = "closing"
	animate(m, false)
end

-- Abierta o abriéndose (la que se está cerrando ya cuenta como cerrada).
function Ui.isOpen(frame: GuiObject): boolean
	local m = motions[frame]
	if m then
		return m.state == "open" or m.state == "opening"
	end
	return frame.Visible
end

local function addMotion(frame: GuiObject, kind, scale: UIScale?, size: (() -> number)?, shadow: GuiObject?, shadowScale: UIScale?)
	local m: Motion = {
		frame = frame, kind = kind, state = if frame.Visible then "open" else "closed", home = frame.Position, travel = 0,
		scale = scale, size = size or function() return 1 end, shadow = shadow, shadowScale = shadowScale,
		gap = if shadow then shadow.Position - frame.Position else UDim2.new(), tweens = {},
	}
	motions[frame] = m
	-- Quien toque Visible a pelo también queda bien: al mostrarse entra animada; al esconderse a media
	-- transición, se corta y vuelve a su sitio.
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			if m.state == "closed" then
				Ui.open(frame)
			end
		elseif m.state ~= "closed" then
			stopMotion(m)
			m.state = "closed"
			settle(m)
		end
	end)
end

-- Ventana pequeña (invitaciones, avisos con botones): entra y sale con un recorrido corto. `scale` es su UIScale, si tiene.
function Ui.popup(frame: GuiObject, scale: UIScale?)
	addMotion(frame, MOTION.popup, scale)
end

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
	-- Al abrirse entra desde abajo y al cerrarse baja (Ui.open / Ui.close).
	addMotion(frame, MOTION.window, scale, function()
		return fitted
	end, shadow, shadowScale)

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
		Ui.close(frame)
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
	-- Sombra de la cabecera sobre el cuerpo: da la sensación de capas (la cabecera "encima").
	local shade = Instance.new("Frame")
	shade.Name = "HeaderShade"
	shade.Size = UDim2.new(1, 0, 0, 26)
	shade.BackgroundColor3 = BLACK
	shade.BorderSizePixel = 0
	shade.Parent = body
	Ui.round(shade, 12)
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Rotation = 90
	shadeFade.Transparency = NumberSequence.new(0.55, 1)
	shadeFade.Parent = shade

	windows[name] = frame
	return frame, body
end

-- Para pantallas que no usan Ui.window pero deben abrirse y cerrarse como las demás.
function Ui.register(name: string, frame: GuiObject)
	windows[name] = frame
	addMotion(frame, MOTION.window)
end

-- Abre la ventana (cerrando las demás) o la cierra si ya estaba abierta.
function Ui.toggle(name: string)
	local frame = windows[name]
	local open = not Ui.isOpen(frame)
	for _, other in windows do
		if other ~= frame then
			Ui.close(other)
		end
	end
	if open then
		Ui.open(frame)
	else
		Ui.close(frame)
	end
end

function Ui.anyOpen(): boolean
	for _, frame in windows do
		if Ui.isOpen(frame) then
			return true
		end
	end
	return false
end

-- Acaba en Visible = false, que ejecuta la limpieza propia de cada ventana (comercio, tiradas, etc.).
function Ui.closeAll()
	for _, frame in windows do
		Ui.close(frame)
	end
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
function Ui.cellTag(cell: Instance, text: string, color: Color3): TextLabel
	local tag = Ui.label(cell, 14)
	tag.Position = UDim2.fromOffset(4, 4)
	tag.Size = UDim2.fromOffset(22, 22)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = color
	tag.Text = text
	tag.ZIndex = 3
	Ui.round(tag, 6)
	Ui.stroke(tag, BLACK, 2)
	return tag
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

-- Logos en imagen (PNG en assets/logos, subidos a Roblox a 512 px y recortados al dibujo). Uno nuevo: subirlo y
-- añadir aquí su id.
Ui.IMAGES = {
	accesorios = "rbxassetid://100488682771428",
	ajustes = "rbxassetid://81188398748574",
	armadura = "rbxassetid://106264890410101",
	casa = "rbxassetid://118337847160649",
	espada = "rbxassetid://100527116629167",
	gemas = "rbxassetid://86307416552518",
	hub = "rbxassetid://74343969763454",
	mazmorras = "rbxassetid://137297255530089",
	mejora = "rbxassetid://112320049421954",
	mochila = "rbxassetid://95507779119186",
	monedas = "rbxassetid://134320261318517",
	objetos = "rbxassetid://91743584320580",
	rebirth = "rbxassetid://90522539620973",
	suerte = "rbxassetid://114098318122458",
	tienda_robux = "rbxassetid://93004325604664",
	trade = "rbxassetid://118234202800810",
}

-- Pone el logo `name` de Ui.IMAGES en el mismo hueco que ocupan los iconos hechos con marcos.
function Ui.image(parent: Instance, name: string): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0.9, 0.9)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = Ui.IMAGES[name]
	image.Parent = parent
	return image
end

-- Iconos hechos con marcos, para lo que cambia de color con cada casilla (gemas de objetos, accesorios, pociones...).
function Ui.gemIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 45)
	local gem = piece(holder, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), color, 6)
	Ui.gradient(gem, WHITE, Color3.fromRGB(150, 150, 170), 45)
	local shine = piece(gem, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.32, 0.32), WHITE, 3)
	shine.BackgroundTransparency = 0.35
end

-- Cristal: esquirlas alargadas e inclinadas (una, o dos con `double`), para que no se confunda con la gema.
function Ui.crystalIcon(parent: Instance, color: Color3, double: boolean?)
	local holder = iconHolder(parent, 0)
	for _, tilt in if double then { -20, 20 } else { 14 } do
		local shard = piece(holder, UDim2.fromScale(0.3, 0.8), UDim2.fromScale(0.5 + tilt / 110, 0.5), color, 5)
		shard.Rotation = tilt
		Ui.gradient(shard, WHITE, Color3.fromRGB(150, 150, 170), 30)
		local shine = piece(shard, UDim2.fromScale(0.3, 0.5), UDim2.fromScale(0.34, 0.32), WHITE, 2)
		shine.BackgroundTransparency = 0.35
	end
end

function Ui.orbIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	local ring = piece(holder, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(235, 190, 60), 100)
	Ui.gradient(ring, WHITE, Color3.fromRGB(170, 150, 120), 90)
	local orb = piece(ring, UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.5, 0.5), color, 100)
	Ui.gradient(orb, WHITE, Color3.fromRGB(150, 150, 170), 60)
end

-- Estrella dorada de ocho puntas (dos cuadrados, uno girado) con brillo: icono del renacimiento.
function Ui.starIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	holder.Size = UDim2.fromScale(0.92, 0.92)
	for _, turn in { 0, 45 } do
		local square = piece(holder, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), color, 6)
		square.Rotation = turn
		Ui.gradient(square, WHITE, Color3.fromRGB(190, 170, 120), 90)
	end
	local core = piece(holder, UDim2.fromScale(0.34, 0.34), UDim2.fromScale(0.5, 0.5), color:Lerp(WHITE, 0.55), 100)
	core.ZIndex = 3
end

local GOLD = Color3.fromRGB(240, 192, 60)

-- Círculo con borde negro (sin relleno si `color` es nil): base de varios iconos.
local function disc(parent: Instance, size: number, position: UDim2, color: Color3): Frame
	return piece(parent, UDim2.fromScale(size, size), position, color, 100)
end

local function shine(parent: Instance, size: UDim2, position: UDim2)
	local spot = piece(parent, size, position, WHITE, 100)
	spot.BackgroundTransparency = 0.4
	local line = spot:FindFirstChildOfClass("UIStroke")
	if line then
		line:Destroy()
	end
	return spot
end

-- Accesorio: colgante dorado con una gema tallada abajo.
function Ui.amuletIcon(parent: Instance, color: Color3)
	local holder = iconHolder(parent, 0)
	holder.Size = UDim2.fromScale(0.92, 0.92)
	local chain = disc(holder, 0.62, UDim2.fromScale(0.5, 0.38), GOLD)
	chain.BackgroundTransparency = 1
	local line = chain:FindFirstChildOfClass("UIStroke")
	if line then
		line.Color = GOLD
		line.Thickness = 5
	end
	piece(holder, UDim2.fromScale(0.2, 0.12), UDim2.fromScale(0.5, 0.68), GOLD, 3)
	local stone = piece(holder, UDim2.fromScale(0.34, 0.34), UDim2.fromScale(0.5, 0.82), color, 4)
	stone.Rotation = 45
	Ui.gradient(stone, WHITE, Color3.fromRGB(150, 150, 170), 45)
	shine(stone, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.3, 0.3))
end

-- Símbolos de las pociones (dentro del líquido): cada uno se dibuja en un cuadrado de lado 1 con piezas sin borde grueso.
local POTION_GLYPHS = {
	sword = function(mark) -- espada en diagonal: hoja y guarda
		mark(UDim2.fromScale(0.18, 0.86), UDim2.fromScale(0.5, 0.46), 3).Rotation = 45
		mark(UDim2.fromScale(0.58, 0.16), UDim2.fromScale(0.5, 0.64), 3).Rotation = -45
	end,
	heart = function(mark) -- cruz de vida
		mark(UDim2.fromScale(0.7, 0.24), UDim2.fromScale(0.5, 0.5), 4)
		mark(UDim2.fromScale(0.24, 0.7), UDim2.fromScale(0.5, 0.5), 4)
	end,
	box = function(mark) -- cubo con tapa
		mark(UDim2.fromScale(0.6, 0.6), UDim2.fromScale(0.5, 0.55), 4)
		mark(UDim2.fromScale(0.72, 0.18), UDim2.fromScale(0.5, 0.26), 3)
	end,
	star = function(mark) -- estrella de ocho puntas: dos cuadrados, uno girado
		mark(UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), 3)
		mark(UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), 3).Rotation = 45
	end,
	chevron = function(mark) -- dos rombos apilados, como las insignias de rango
		mark(UDim2.fromScale(0.4, 0.4), UDim2.fromScale(0.5, 0.3), 3).Rotation = 45
		mark(UDim2.fromScale(0.4, 0.4), UDim2.fromScale(0.5, 0.68), 3).Rotation = 45
	end,
	spark = function(mark) -- destello arcano de cuatro puntas
		mark(UDim2.fromScale(0.16, 0.9), UDim2.fromScale(0.5, 0.5), 4)
		mark(UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.5, 0.5), 4)
		mark(UDim2.fromScale(0.34, 0.34), UDim2.fromScale(0.5, 0.5), 3).Rotation = 45
	end,
}

-- Poción: frasco de cristal con corcho, el líquido del color de la familia y un símbolo encima (`glyph`: sword = daño,
-- heart = vida, box = suerte de cajas, star = suerte de armas, chevron = grado, spark = rasgo; sin él, solo el frasco).
function Ui.potionIcon(parent: Instance, color: Color3, glyph: string?)
	-- El frasco ocupa todo su hueco y siempre es cuadrado (si el hueco no lo es, se ajusta al lado menor).
	local holder = iconHolder(parent, 0)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	local square = Instance.new("UIAspectRatioConstraint")
	square.Parent = holder
	local glass = Color3.fromRGB(205, 226, 242)
	piece(holder, UDim2.fromScale(0.3, 0.12), UDim2.fromScale(0.5, 0.06), Color3.fromRGB(160, 105, 60), 2)
	local neck = piece(holder, UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.5, 0.19), glass, 2)
	neck.BackgroundTransparency = 0.15
	-- Cuerpo redondo de cristal y, dentro, el líquido (un círculo un poco menor) con su degradado.
	local body = piece(holder, UDim2.fromScale(0.82, 0.82), UDim2.fromScale(0.5, 0.58), glass, 100)
	body.BackgroundTransparency = 0.15
	local liquid = piece(body, UDim2.new(1, -7, 1, -7), UDim2.fromScale(0.5, 0.5), color, 100)
	Ui.gradient(liquid, color:Lerp(WHITE, 0.5), color:Lerp(BLACK, 0.3), 90)
	local liquidLine = liquid:FindFirstChildOfClass("UIStroke")
	if liquidLine then
		liquidLine.Thickness = 1
	end
	shine(body, UDim2.fromScale(0.16, 0.1), UDim2.fromScale(0.26, 0.2)).Rotation = -40
	local draw = if glyph then POTION_GLYPHS[glyph] else nil
	if draw then
		-- El símbolo va en un cuadrado centrado en el líquido, para que no se estire con su forma.
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.52)
		box.Size = UDim2.fromScale(0.64, 0.64)
		box.BackgroundTransparency = 1
		box.Parent = liquid
		local light = color:Lerp(WHITE, 0.85)
		draw(function(size: UDim2, position: UDim2, radius: number): Frame
			local item = piece(box, size, position, light, radius)
			local line = item:FindFirstChildOfClass("UIStroke")
			if line then
				line.Thickness = 1
			end
			return item
		end)
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

-- ¿Tapa algo a `target` donde está el ratón? Pasa cuando una capa opaca se pone encima (como
-- "Elige una espada" o los ajustes de las tiendas): la casilla sigue debajo y, sin esto, su cartel
-- saltaba al pasar el ratón por donde estaba. Se recorre lo que hay en ese punto de arriba abajo: si
-- antes de llegar a `target` (o a algo suyo) aparece algo con fondo que no lo contiene, está tapado.
local function covered(target: GuiObject): boolean
	local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	for _, object in player:WaitForChild("PlayerGui"):GetGuiObjectsAtPosition(point.X, point.Y) do
		if object == target or object:IsDescendantOf(target) then
			return false
		end
		if object ~= tip and object.BackgroundTransparency < 1 and not target:IsDescendantOf(object) then
			return true
		end
	end
	return false
end

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
		if not ancestor or not tipSource:IsDescendantOf(game) or covered(tipSource) then
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
		if not covered(target) then
			open(false)
		end
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

-- Transparencias de todo lo que se ve en `root` (él incluido): fondos, textos, imágenes y bordes.
-- Sirve para desvanecer el aviso entero a la vez: su GroupTransparency solo apagaba el fondo y dejaba
-- los textos, los bordes y el icono hasta el final.
local function transparencies(root: Instance)
	local list = {}
	for _, part in { root, table.unpack(root:GetDescendants()) } do
		local props = {}
		if part:IsA("GuiObject") then
			props.BackgroundTransparency = part.BackgroundTransparency
		end
		if part:IsA("TextLabel") or part:IsA("TextButton") or part:IsA("TextBox") then
			props.TextTransparency = part.TextTransparency
		elseif part:IsA("ImageLabel") or part:IsA("ImageButton") then
			props.ImageTransparency = part.ImageTransparency
		elseif part:IsA("UIStroke") then
			props.Transparency = part.Transparency
		end
		if next(props) then
			table.insert(list, { part = part, props = props })
		end
	end
	return list
end

-- Lleva cada pieza de `list` a transparente (`shown` = false) o a como estaba, todas con el mismo
-- tween. Devuelve uno de ellos para esperar a que acabe.
local function fadeAll(list, info: TweenInfo, shown: boolean): Tween?
	local last = nil
	for _, entry in list do
		local goal = {}
		for prop, value in entry.props do
			goal[prop] = if shown then value else 1
		end
		last = TweenService:Create(entry.part, info, goal)
		last:Play()
	end
	return last
end
local TOAST_WIDTH = 520

-- Icono según de qué habla el aviso. Los rojos llevan "!".
local function toastIcon(parent: Frame, text: string, color: Color3)
	local lower = string.lower(text)
	if string.find(lower, "poci", 1, true) then
		-- Antes que "arma": la poción de suerte de armas también la lleva.
		Ui.potionIcon(parent, color, "spark")
	elseif string.find(lower, "cristal", 1, true) then
		Ui.gemIcon(parent, color)
	elseif string.find(lower, "gema", 1, true) then
		Ui.image(parent, "gemas")
	elseif string.find(lower, "moneda", 1, true) then
		Ui.image(parent, "monedas")
	elseif string.find(lower, "espada", 1, true) or string.find(lower, "hacha", 1, true) or string.find(lower, "lanza", 1, true) or string.find(lower, "martillo", 1, true) or string.find(lower, "arma", 1, true) then
		Ui.image(parent, "espada")
	elseif color.R > 0.7 and color.G < 0.5 and color.B < 0.5 then
		local mark = Ui.label(parent, 34)
		mark.Size = UDim2.fromScale(1, 1)
		mark.Text = "!"
		mark.TextColor3 = color
	else
		Ui.image(parent, "objetos")
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
		list.Size = UDim2.fromOffset(TOAST_WIDTH, 0)
		list.AutomaticSize = Enum.AutomaticSize.Y
		list.BackgroundTransparency = 1
		list.ZIndex = 50
		list.Parent = Ui.hud()
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
	-- Alto según el texto, para que los avisos largos no se corten.
	local textHeight = TextService:GetTextSize(text, 23, Ui.FONT, Vector2.new(TOAST_WIDTH - 82, 1000)).Y
	item.Size = UDim2.new(1, 0, 0, math.max(58, textHeight + 18))
	item.BackgroundColor3 = WHITE
	item.ZIndex = 50
	item.Parent = list
	Ui.round(item, 14)
	Ui.stroke(item, BLACK, 4)
	Ui.gradient(item, Color3.fromRGB(70, 74, 98), Color3.fromRGB(28, 29, 40), 90)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = item

	-- Barra de color a la izquierda y brillo arriba. La barra va metida hacia dentro y redondeada:
	-- pegada al borde, sus esquinas cuadradas asomaban por fuera de las esquinas redondas del aviso.
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 6, 0.5, 0)
	bar.Size = UDim2.new(0, 6, 1, -16)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = 51
	bar.Parent = item
	Ui.round(bar, 3)
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
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, 16, 0.5, 0)
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

	-- Aparece y se va entero a la vez: fondo, textos, bordes, icono y barra.
	local parts = transparencies(item)
	for _, entry in parts do
		for prop in entry.props do
			(entry.part :: any)[prop] = 1
		end
	end
	local pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	fadeAll(parts, TweenInfo.new(0.2), true)
	TweenService:Create(scale, pop, { Scale = 1 }):Play()
	task.delay(3.8, function()
		if item.Parent then
			local fade = fadeAll(parts, TweenInfo.new(0.4), false)
			if fade then
				fade.Completed:Connect(function()
					item:Destroy()
				end)
			else
				item:Destroy()
			end
		end
	end)
end

return Ui
