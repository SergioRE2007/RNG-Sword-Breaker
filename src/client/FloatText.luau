-- Números que flotan en el mundo: daño a enemigos (impacto), daño a cajas (compacto) y premios (monedas, gemas, tiradas).
-- Solo presentación: los valores ya vienen calculados del servidor. Los carteles se reciclan (pool) y los mueve un
-- único bucle que solo corre mientras hay alguno vivo; con demasiados a la vez se recicla el más viejo.
local RunService = game:GetService("RunService")

local Performance = require(script.Parent.Performance)

local FloatText = {}

local MAX_ACTIVE = 40
local MAX_ACTIVE_LOW = 16 -- modo rendimiento
local MAX_OTHERS = 10 -- números de los golpes de otros jugadores
local OTHER_SCALE = 0.7
local OTHER_DIM = 0.45
local SCREEN_HEIGHT = 820 -- alto de pantalla al que el texto sale a su tamaño
local GUI_SIZE = UDim2.fromOffset(480, 72)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local FLASH_TIME = 0.12 -- lo que tarda el borde en pasar del destello al negro

-- Cada estilo: duración, tamaño, color en degradado (`top` arriba, `bottom` abajo), destello del borde al salir
-- (`flash`), brillo que cruza el texto (`shine` s, empezando en `shineAt`), pop (de `from` a `peak` en `popIn` s y de
-- vuelta a 1 en `popOut` s), subida (`rise` studs, alcanzada en la fracción `riseEnd` de la vida, desde `start`),
-- deriva lateral, arco, temblor y fade final.
FloatText.STYLES = {
	enemy = { life = 0.7, size = 30, stroke = 2.5, top = Color3.fromRGB(255, 238, 150), bottom = Color3.fromRGB(255, 135, 35), flash = Color3.fromRGB(255, 120, 40), shine = 0.22, shineAt = 0.04, from = 0.7, peak = 1.12, popIn = 0.06, popOut = 0.16, rise = 3.2, riseEnd = 1, drift = 0.9, rotation = 5, fade = 0.35, shrink = 0.85 },
	final = { life = 0.9, size = 40, stroke = 3, top = Color3.fromRGB(255, 240, 130), bottom = Color3.fromRGB(255, 70, 50), flash = Color3.fromRGB(255, 255, 255), shine = 0.3, shineAt = 0.05, from = 0.6, peak = 1.3, popIn = 0.07, popOut = 0.2, rise = 3.8, riseEnd = 1, drift = 0.6, rotation = 4, wobble = 4, fade = 0.35, shrink = 0.85 },
	box = { life = 0.5, size = 25, stroke = 2, top = Color3.fromRGB(220, 245, 255), bottom = Color3.fromRGB(85, 170, 255), flash = Color3.fromRGB(90, 180, 255), from = 0.8, peak = 1.06, popIn = 0.04, popOut = 0.1, rise = 1.8, riseEnd = 1, drift = 0.5, rotation = 3, fade = 0.4, shrink = 0.9 },
	coin = { life = 1.1, size = 30, stroke = 2.5, top = Color3.fromRGB(255, 242, 120), bottom = Color3.fromRGB(255, 150, 0), flash = Color3.fromRGB(255, 230, 90), shine = 0.4, shineAt = 0.2, icon = "coin", from = 0.85, peak = 1.08, popIn = 0.1, popOut = 0.25, start = -1, rise = 3.5, riseEnd = 0.6, arc = 0.6, side = 1, shift = 3.2, rotation = 3, fade = 0.25 },
	gem = { life = 1.1, size = 28, stroke = 2.5, top = Color3.fromRGB(245, 210, 255), bottom = Color3.fromRGB(165, 80, 255), flash = Color3.fromRGB(220, 150, 255), shine = 0.4, shineAt = 0.25, icon = "gem", from = 0.85, peak = 1.08, popIn = 0.1, popOut = 0.25, start = -1, rise = 3.5, riseEnd = 0.6, arc = 0.6, side = -1, shift = -3.2, rotation = 3, fade = 0.25 },
	notice = { life = 1.2, size = 24, stroke = 2.5, top = WHITE, bottom = WHITE, flash = WHITE, shine = 0.45, shineAt = 0.2, from = 0.85, peak = 1.1, popIn = 0.1, popOut = 0.25, rise = 2.5, riseEnd = 0.7, rotation = 2, fade = 0.3 },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function outQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function outCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Curvas de un número: `t` en segundos desde que sale y `v` su variación propia (life, scale, drift, rotation entre -1 y 1).
-- Devuelve escala, desplazamiento lateral y vertical (studs, relativos a la cámara), rotación y cuánto se ha apagado (0 a 1).
function FloatText.sample(style, t: number, v): (number, number, number, number, number)
	local life = style.life * v.life
	local p = math.clamp(t / life, 0, 1)

	local scale = 1
	if t < style.popIn then
		scale = lerp(style.from, style.peak, outQuad(math.max(t, 0) / style.popIn))
	elseif t < style.popOut then
		scale = lerp(style.peak, 1, (1 - math.cos((t - style.popIn) / (style.popOut - style.popIn) * math.pi)) / 2)
	end

	local fadeFrom = 1 - style.fade
	local faded = if p > fadeFrom then ((p - fadeFrom) / style.fade) ^ 2 else 0
	scale *= lerp(1, style.shrink or 1, faded) * v.scale

	local rise = outCubic(math.min(p / style.riseEnd, 1))
	local y = (style.start or 0) * (1 - rise) + style.rise * rise
	local x = (style.drift or 0) * v.drift * outQuad(p) + (style.arc or 0) * (style.side or 1) * math.sin(p * math.pi)
	-- `shift`: se aparta hacia un lado y se queda ahí (monedas y gemas, para no tapar el orbe de la tirada de arma).
	x += (style.shift or 0) * rise

	local rotation = style.rotation * v.rotation * (1 - 0.6 * p)
	if style.wobble and t < 0.2 then
		rotation += style.wobble * math.sin(t * 70) * (1 - t / 0.2)
	end
	return scale, x, y, rotation, faded
end

type Entry = {
	anchor: Attachment,
	gui: BillboardGui,
	holder: Frame,
	scaler: UIScale,
	label: TextLabel,
	stroke: UIStroke,
	gradient: UIGradient,
	shine: TextLabel,
	shineGradient: UIGradient,
	icons: { [string]: Frame },
	fades: { { any } },
	style: any,
	vary: { [string]: number },
	start: number,
	target: BasePart?,
	offset: Vector3,
	base: Vector3,
	other: boolean,
	size: number,
}

local rng = Random.new()
local pool: { Entry } = {}
local active: { Entry } = {}
local connection: RBXScriptConnection?

local function build(): Entry
	local anchor = Instance.new("Attachment")
	anchor.Name = "FloatText"
	anchor.Parent = workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = GUI_SIZE
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.ClipsDescendants = false
	gui.Enabled = false
	gui.Adornee = anchor
	gui.Parent = anchor

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	local scaler = Instance.new("UIScale")
	scaler.Parent = holder

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder

	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.LayoutOrder = 2
	label.Parent = holder

	label.TextColor3 = WHITE

	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = label

	-- Brillo: el mismo texto en blanco encima, visible solo en una franja que lo cruza (se mueve con el Offset).
	local shine = Instance.new("TextLabel")
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundTransparency = 1
	shine.Font = Enum.Font.FredokaOne
	shine.TextColor3 = WHITE
	shine.ZIndex = label.ZIndex + 1
	shine.Parent = label

	local shineGradient = Instance.new("UIGradient")
	shineGradient.Rotation = 20
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shineGradient.Parent = shine

	return {
		anchor = anchor, gui = gui, holder = holder, scaler = scaler, label = label, stroke = stroke, gradient = gradient,
		shine = shine, shineGradient = shineGradient, icons = {},
		fades = { { label, "TextTransparency", 0 }, { stroke, "Transparency", 0 }, { shine, "TextTransparency", 0 } },
		style = nil, vary = {}, start = 0, target = nil, offset = Vector3.zero, base = Vector3.zero, other = false, size = 0,
	}
end

-- Logo de `Ui.image`, creado la primera vez que esta entrada lo necesita y luego solo se enseña.
local function icon(entry: Entry, kind: string?)
	for name, frame in entry.icons do
		frame.Visible = name == kind
	end
	if not kind or entry.icons[kind] then
		return
	end
	local Ui = require(script.Parent.Ui)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(34, 34)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = 1
	frame.Parent = entry.holder
	local image = Ui.image(frame, if kind == "coin" then "monedas" else "gemas")
	table.insert(entry.fades, { image, "ImageTransparency", 0 })
	entry.icons[kind] = frame
end

local function release(index: number)
	local entry = table.remove(active, index) :: Entry
	entry.gui.Enabled = false
	entry.target = nil
	table.insert(pool, entry)
end

local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local screen = if camera then math.clamp(camera.ViewportSize.Y / SCREEN_HEIGHT, 0.72, 1.15) else 1
	for index = #active, 1, -1 do
		local entry = active[index]
		local t = now - entry.start
		if t >= entry.style.life * entry.vary.life then
			release(index)
			continue
		end
		-- Sigue al objetivo mientras exista; si desaparece, el número acaba donde lo vio por última vez.
		local target = entry.target
		if target and target.Parent then
			entry.base = target.Position + entry.offset
		end
		entry.anchor.WorldPosition = entry.base
		if t < 0 then
			continue -- todavía en su pequeño retraso
		end
		local scale, x, y, rotation, faded = FloatText.sample(entry.style, t, entry.vary)
		entry.gui.Enabled = true
		entry.gui.StudsOffset = Vector3.new(x, y, 0)
		entry.holder.Rotation = rotation
		entry.scaler.Scale = scale * screen * entry.size
		-- Destello: el borde sale del color del tipo y más gordo, y en un instante vuelve al negro.
		local style = entry.style
		local settle = outQuad(math.min(t / FLASH_TIME, 1))
		entry.stroke.Color = style.flash:Lerp(BLACK, settle)
		entry.stroke.Thickness = style.stroke * (1.7 - 0.7 * settle)
		if style.shine then
			local sweep = math.clamp((t - style.shineAt) / style.shine, 0, 1)
			entry.shineGradient.Offset = Vector2.new(lerp(-1, 1, sweep), 0)
		end
		local hidden = if entry.other then 1 - (1 - faded) * (1 - OTHER_DIM) else faded
		for _, fade in entry.fades do
			fade[1][fade[2]] = fade[3] + (1 - fade[3]) * hidden
		end
	end
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Saca un número. `kind`: "enemy", "box", "coin", "gem" o "notice". `opts`: target (pieza a la que sigue), final
-- (golpe que lo remata), other (golpe de otro jugador), color (cambia el del estilo), emphasis (agranda y alarga).
function FloatText.spawn(kind: string, position: Vector3, text: string, opts: { [string]: any }?)
	local options = opts or {}
	local other = options.other == true
	local style = if kind == "enemy" and options.final and not other then FloatText.STYLES.final else FloatText.STYLES[kind]

	-- Tope: se recicla el más viejo (de los ajenos si el nuevo es ajeno). Solo se pierde lo que se ve.
	if other then
		local others, oldest = 0, nil
		for index, entry in active do
			if entry.other then
				others += 1
				oldest = oldest or index
			end
		end
		if others >= MAX_OTHERS and oldest then
			release(oldest)
		end
	end
	if #active >= (if Performance.get() then MAX_ACTIVE_LOW else MAX_ACTIVE) then
		release(1)
	end

	local entry = table.remove(pool) or build()
	local emphasis = options.emphasis or 1
	entry.style = style
	entry.other = other
	entry.size = (if other then OTHER_SCALE else 1) * emphasis
	entry.vary = {
		life = rng:NextNumber(0.9, 1.1) * emphasis,
		scale = rng:NextNumber(0.94, 1.06),
		drift = rng:NextNumber(-1, 1),
		rotation = rng:NextNumber(-1, 1),
	}
	entry.start = os.clock() + rng:NextNumber(0, 0.04)
	entry.base = position + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.8, 0.8))
	entry.target = options.target
	entry.offset = if options.target then entry.base - options.target.Position else Vector3.zero

	entry.label.Text = text
	entry.label.TextSize = style.size
	entry.shine.Text = text
	entry.shine.TextSize = style.size
	entry.shine.Visible = style.shine ~= nil
	entry.shineGradient.Offset = Vector2.new(-1, 0)
	-- `color` (avisos de tiradas, color de la rareza) sustituye al degradado del estilo.
	local color = options.color
	entry.gradient.Color = ColorSequence.new(if color then color:Lerp(WHITE, 0.55) else style.top, color or style.bottom)
	entry.stroke.Thickness = style.stroke
	icon(entry, style.icon)
	entry.anchor.WorldPosition = entry.base
	entry.gui.Enabled = false
	table.insert(active, entry)

	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

return FloatText
