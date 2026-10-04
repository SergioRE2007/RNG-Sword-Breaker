-- Piezas comunes de la interfaz: estilo (degradados, bordes, botones con relieve), ventanas,
-- casillas cuadradas con icono, cartel flotante al pasar el ratón y avisos en pantalla.
-- No tiene start(): lo usan Hud y Backpack.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

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

-- Relieve de botón: brillo arriba y una franja oscura abajo, sobre el color de fondo que tenga.
function Ui.bevel(instance: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.44, Color3.fromRGB(238, 238, 238)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(206, 206, 206)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(190, 190, 190)),
		ColorSequenceKeypoint.new(0.86, Color3.fromRGB(125, 125, 125)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(115, 115, 115)),
	})
	gradient.Parent = instance
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
	return item
end

local gui
function Ui.screen(): ScreenGui
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "Hud"
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	return gui
end

-- Ventanas ------------------------------------------------------------------------------

local windows = {} -- [nombre] = Frame

-- Ventana con cabecera degradada, título y botón de cerrar. Devuelve el marco y el cuerpo
-- (donde va el contenido). En pantallas pequeñas se encoge sola.
function Ui.window(name: string, title: string, size: Vector2)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 108)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = Ui.COLORS.panel
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = Ui.screen()
	Ui.round(frame, 14)
	Ui.stroke(frame, BLACK, 5)

	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local camera = workspace.CurrentCamera
	local function fit()
		local view = camera.ViewportSize
		-- Deja sitio a la izquierda para el menú y las pestañas.
		scale.Scale = math.clamp(math.min((view.X / 2 - 175) / (size.X / 2 + 100), (view.Y - 125) / size.Y), 0.45, 1)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundColor3 = WHITE
	header.BorderSizePixel = 0
	header.Parent = frame
	Ui.round(header, 14)
	local headerColors = Instance.new("UIGradient")
	headerColors.Rotation = 8
	headerColors.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 170, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(125, 105, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 95, 235)),
	})
	headerColors.Parent = header

	-- Brillo en la mitad de arriba de la cabecera.
	local headerGloss = Instance.new("Frame")
	headerGloss.Name = "Gloss"
	headerGloss.Position = UDim2.fromOffset(6, 5)
	headerGloss.Size = UDim2.new(1, -12, 0.45, 0)
	headerGloss.BackgroundColor3 = WHITE
	headerGloss.BorderSizePixel = 0
	headerGloss.Parent = header
	Ui.round(headerGloss, 10)
	local headerFade = Instance.new("UIGradient")
	headerFade.Rotation = 90
	headerFade.Transparency = NumberSequence.new(0.68, 0.95)
	headerFade.Parent = headerGloss

	local heading = Ui.label(header, 32)
	heading.Position = UDim2.fromOffset(20, 0)
	heading.Size = UDim2.new(1, -90, 1, 0)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title

	local close = Ui.button(header, "X", Ui.COLORS.red)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(60, 56)
	close.TextSize = 30
	close.Activated:Connect(function()
		frame.Visible = false
	end)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(10, 66)
	body.Size = UDim2.new(1, -20, 1, -76)
	body.BackgroundColor3 = Ui.COLORS.body
	body.BorderSizePixel = 0
	body.Parent = frame
	Ui.round(body, 10)
	Ui.stroke(body, Ui.COLORS.dark, 3)
	Ui.gradient(body, WHITE, Color3.fromRGB(140, 140, 170), 90)

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
-- un brillo da vueltas por el borde, más rápido cuanto más rara.
local SHINE_SPEED = { 0, 40, 70, 100, 140, 190, 250, 320 } -- grados por segundo
local PULSE_FROM = 5 -- desde aquí el marco lleva además un halo que late
local RAINBOW_FROM = 7 -- desde aquí el borde va en arcoíris

local shines = {} -- [UIGradient del borde] = { speed, halo, phase }
local shining = false

local function animateShines(dt: number)
	local now = os.clock()
	for gradient, info in shines do
		gradient.Rotation = (gradient.Rotation + info.speed * dt) % 360
		if info.halo then
			info.halo.Transparency = 0.45 + 0.35 * math.sin(now * 4 + info.phase)
		end
	end
end

local function shineColors(color: Color3, tier: number): ColorSequence
	if tier >= RAINBOW_FROM then
		local points = {}
		for step = 0, 6 do
			table.insert(points, ColorSequenceKeypoint.new(step / 6, Color3.fromHSV(step / 6 % 1, 0.7, 1)))
		end
		return ColorSequence.new(points)
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

	local level = math.clamp(tier or 1, 1, #SHINE_SPEED)
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
			halo = Ui.stroke(aura, if level >= RAINBOW_FROM then WHITE else color:Lerp(WHITE, 0.3), 2)
		end

		shines[shine] = { speed = SHINE_SPEED[level], halo = halo, phase = math.random() * 6 }
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
	limit.MaxTextSize = 18
	limit.MinTextSize = 9
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

-- Cartel flotante --------------------------------------------------------------------------

local tip, tipStroke, tipSource
local tipBeside = false

local function ensureTip()
	if tip then
		return
	end
	tip = Ui.label(Ui.screen(), 18)
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
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local view = workspace.CurrentCamera.ViewportSize
		local size = tip.AbsoluteSize
		local x = mouse.X + 18
		local top = mouse.Y + 14
		if x + size.X > view.X - 8 then
			x = mouse.X - size.X - 12
		end
		if tipBeside then
			-- Pegado al lado de la casilla, para no tapar lo que se está mirando.
			local corner, box = tipSource.AbsolutePosition, tipSource.AbsoluteSize
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
function Ui.tip(target: GuiObject, getContent: () -> (string, Color3), beside: boolean?)
	ensureTip()
	target.MouseEnter:Connect(function()
		local text, color = getContent()
		tip.Text = text
		tipStroke.Color = color
		tipSource = target
		tipBeside = beside == true
		tip.Visible = true
	end)
	target.MouseLeave:Connect(function()
		if tipSource == target then
			tip.Visible = false
		end
	end)
end

-- Avisos ----------------------------------------------------------------------------------

local toast
local toastId = 0

function Ui.toast(text: string, color: Color3)
	if not toast then
		toast = Ui.label(Ui.screen(), 24)
		toast.Name = "Toast"
		toast.AnchorPoint = Vector2.new(0.5, 1)
		toast.Position = UDim2.new(0.5, 0, 1, -24)
		toast.Size = UDim2.fromOffset(500, 70)
		toast.BackgroundTransparency = 0
		toast.BackgroundColor3 = Ui.COLORS.panel
		toast.TextWrapped = true
		toast.RichText = false
		toast.ZIndex = 50
		Ui.round(toast, 14)
		Ui.stroke(toast, BLACK, 4)
		Ui.gradient(toast, WHITE, Color3.fromRGB(170, 170, 190), 90)
	end
	toast.Text = text
	toast.TextColor3 = color
	toast.Visible = true
	toastId += 1
	local id = toastId
	task.delay(4, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end

return Ui
