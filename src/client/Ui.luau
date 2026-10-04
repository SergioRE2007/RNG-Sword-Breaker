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
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 225, 225)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(205, 205, 205)),
		ColorSequenceKeypoint.new(0.86, Color3.fromRGB(135, 135, 135)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(135, 135, 135)),
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
	Ui.round(item, 10)
	Ui.bevel(item)
	Ui.stroke(item, BLACK, 2.5)
	Ui.textStroke(item, 1.5)
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
	Ui.gradient(header, Color3.fromRGB(70, 150, 255), Color3.fromRGB(150, 90, 240), 0)

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
	Ui.gradient(body, WHITE, Color3.fromRGB(190, 190, 205), 90)

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

-- Casilla cuadrada con borde del color que se le pase (la rareza). El tamaño lo pone quien la usa.
function Ui.cell(parent: Instance, color: Color3): TextButton
	local cell = Instance.new("TextButton")
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BackgroundColor3 = color
	cell.Parent = parent
	Ui.round(cell, 10)
	Ui.stroke(cell, color, 3)
	-- Fondo oscuro teñido del color de la rareza, más claro arriba.
	Ui.gradient(cell, Color3.fromRGB(95, 95, 105), Color3.fromRGB(28, 28, 36), 90)

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
