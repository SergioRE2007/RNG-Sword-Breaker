-- Lo que se ve del clima en la interfaz: librería sin start() (la lleva client/Weather).
--  · `Hud.HudRoot.Weather`: tarjeta arriba en el centro, bajo la barra de transporte. Con clima: insignia con su
--    dibujo, nombre, lo que da y el tiempo que queda (rojo y latiendo al final). Despejado: cuánto falta para el
--    siguiente. El contenido va en `Weather.Card`: SkillTree esconde y devuelve los hijos de HudRoot, así que lo que
--    se esconde por otros motivos (mazmorra, forja) es la tarjeta de dentro.
--  · `Hud.HudRoot.WeatherBanner`: cartel grande que sale unos segundos al empezar un clima, con su nombre, su rareza
--    y lo que da. Más cargado cuanto más raro.
-- Los dibujos de las insignias son marcos (cambian de color con cada clima), como el resto de iconos de casilla.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local WeatherHud = {}

local cfg = Config.Weather

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local LUCK = "#7ee07a" -- el verde de "Suerte de destructibles" en las estadísticas
local WEAPON = "#c9a0ff" -- y el violeta de "Suerte de armas"
local LOW = Color3.fromRGB(255, 96, 96)
local CLEAR = Color3.fromRGB(92, 104, 140) -- insignia con el cielo despejado

-- Medidas de la tarjeta (en píxeles del HUD, que ya se encoge entero en pantallas pequeñas).
local TOP = 92 -- justo debajo de la barra de transporte (76 de alto a 10 del borde)
local HEIGHT = 52
local BADGE = 38
local PAD = 9
local CLOCK_WIDTH = 74
local TEXT_ROOM = 320 -- ancho máximo del nombre y de lo que da
-- Capas (la interfaz ordena el ZIndex globalmente): la tarjeta va con el resto del HUD y el cartel por encima de las
-- ventanas y por debajo de los avisos (50).
local Z_BANNER = 40

local outer: Frame? = nil
local card: Frame
local badge: Frame
local glyphBox: Frame
local title: TextLabel
local detail: TextLabel
local clock: TextLabel
local clockPulse: UIScale
local accent: Frame
local shownId: string? = nil
local shownSeconds = -1

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Mayúsculas también en las letras con tilde (string.upper las deja como están: "ELéCTRICA").
local ACCENTS = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ü"] = "Ü", ["ñ"] = "Ñ" }
local function upper(text: string): string
	return (string.gsub(string.upper(text), "\195[\128-\191]", ACCENTS))
end

-- Dibujos -------------------------------------------------------------------------------------------------

-- Trozo blanco de un dibujo: tamaño y centro en fracción de la insignia, giro y redondeo (0.5 = del todo).
local function piece(parent: Instance, width: number, height: number, x: number, y: number, rotation: number?, round: number?): Frame
	local item = Instance.new("Frame")
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(width, height)
	item.Rotation = rotation or 0
	item.BackgroundColor3 = WHITE
	item.BorderSizePixel = 0
	item.ZIndex = parent:IsA("GuiObject") and parent.ZIndex or 1
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(round or 0.5, 0)
	corner.Parent = item
	return item
end

local GLYPHS: { [string]: (Frame) -> () } = {
	rain = function(box)
		piece(box, 0.14, 0.42, 0.28, 0.4, 20)
		piece(box, 0.14, 0.42, 0.52, 0.6, 20)
		piece(box, 0.14, 0.42, 0.76, 0.4, 20)
	end,
	petals = function(box)
		for index = 0, 4 do
			local angle = math.rad(index * 72)
			piece(box, 0.34, 0.34, 0.5 + math.sin(angle) * 0.25, 0.5 - math.cos(angle) * 0.25)
		end
		piece(box, 0.22, 0.22, 0.5, 0.5).BackgroundColor3 = Color3.fromRGB(255, 226, 110)
	end,
	fog = function(box)
		piece(box, 0.72, 0.15, 0.5, 0.28)
		piece(box, 0.5, 0.15, 0.4, 0.5)
		piece(box, 0.66, 0.15, 0.55, 0.72)
	end,
	snow = function(box)
		for _, turn in { 0, 60, 120 } do
			piece(box, 0.12, 0.84, 0.5, 0.5, turn)
		end
		piece(box, 0.26, 0.26, 0.5, 0.5)
	end,
	storm = function(box)
		piece(box, 0.2, 0.5, 0.57, 0.3, 28, 0.25)
		piece(box, 0.4, 0.16, 0.5, 0.5, 0, 0.3)
		piece(box, 0.2, 0.5, 0.43, 0.7, 28, 0.25)
	end,
	goldenRain = function(box)
		piece(box, 0.5, 0.5, 0.36, 0.36)
		piece(box, 0.13, 0.32, 0.7, 0.6, 20)
		piece(box, 0.13, 0.32, 0.46, 0.8, 20)
	end,
	volcanic = function(box)
		piece(box, 0.24, 0.17, 0.5, 0.5, 0, 0.3)
		piece(box, 0.48, 0.17, 0.5, 0.67, 0, 0.3)
		piece(box, 0.74, 0.17, 0.5, 0.84, 0, 0.3)
		piece(box, 0.15, 0.15, 0.5, 0.26)
		piece(box, 0.11, 0.11, 0.3, 0.16)
		piece(box, 0.11, 0.11, 0.7, 0.18)
	end,
	aurora = function(box)
		for index, band in { { 0.28, 0.62, -8 }, { 0.5, 0.8, 0 }, { 0.72, 0.58, 8 } } do
			local ribbon = piece(box, 0.15, band[2], band[1], 0.5 + (index % 2) * 0.03, band[3])
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new(0, 0.75)
			fade.Parent = ribbon
		end
	end,
	bloodMoon = function(box)
		local moon = piece(box, 0.76, 0.76, 0.5, 0.5)
		for _, crater in { { 0.2, 0.36, 0.38 }, { 0.14, 0.64, 0.54 }, { 0.11, 0.44, 0.68 } } do
			piece(moon, crater[1], crater[1], crater[2], crater[3]).BackgroundColor3 = Color3.fromRGB(196, 86, 92)
		end
	end,
	eclipse = function(box)
		local disc = piece(box, 0.62, 0.62, 0.5, 0.5)
		disc.BackgroundColor3 = Color3.fromRGB(22, 18, 44)
		Ui.stroke(disc, Color3.fromRGB(255, 236, 190), 3)
	end,
	cosmic = function(box)
		piece(box, 0.46, 0.46, 0.5, 0.5)
		local ring = piece(box, 0.96, 0.26, 0.5, 0.5, -22)
		ring.BackgroundTransparency = 1
		Ui.stroke(ring, WHITE, 2)
	end,
	starfall = function(box)
		piece(box, 0.1, 0.46, 0.64, 0.36, 45)
		piece(box, 0.07, 0.32, 0.78, 0.5, 45)
		piece(box, 0.07, 0.32, 0.5, 0.22, 45)
		for _, turn in { 0, 45 } do
			piece(box, 0.34, 0.34, 0.34, 0.66, turn, 0.15)
		end
	end,
}

-- Insignia redonda del color del clima con su dibujo dentro. Sin id: el interrogante del clima que viene.
local function drawBadge(holder: Frame, box: Frame, id: string?)
	local color = if id then cfg.Events[id].color else CLEAR
	local gradient = holder:FindFirstChildOfClass("UIGradient") :: UIGradient
	gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color:Lerp(BLACK, 0.3))
	box:ClearAllChildren()
	local draw = if id then GLYPHS[id] else nil
	if draw then
		draw(box)
		return
	end
	local mark = Ui.label(box, 26)
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = box.ZIndex
	mark.Text = "?"
end

local function newBadge(parent: Instance, size: number, z: number): (Frame, Frame)
	local holder = Instance.new("Frame")
	holder.Name = "Badge"
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundColor3 = WHITE
	holder.ZIndex = z
	holder.Parent = parent
	Ui.round(holder, size)
	Ui.stroke(holder, BLACK, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = holder
	-- Brillo de cristal arriba, como en los botones.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, 0.07)
	gloss.Size = UDim2.fromScale(0.7, 0.38)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = z
	gloss.Parent = holder
	Ui.round(gloss, size)
	local box = Instance.new("Frame")
	box.Name = "Glyph"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(0.66, 0.66)
	box.BackgroundTransparency = 1
	box.ZIndex = z
	box.Parent = holder
	return holder, box
end

-- Insignia suelta de un clima, de `size` píxeles (para otras ventanas: el menú de admin).
function WeatherHud.badge(parent: Instance, size: number, id: string?, z: number?): Frame
	local holder, box = newBadge(parent, size, z or 1)
	drawBadge(holder, box, id)
	return holder
end

-- Textos --------------------------------------------------------------------------------------------------

-- "Suerte x2 · Armas x1.5", cada una con su color de las estadísticas. `long` = con el nombre entero.
local function buffLine(def: { [string]: any }, long: boolean?): string
	local parts = {}
	for _, buff in WeatherInfo.buffs(def) do
		local color = if buff.short == "Armas" then WEAPON else LUCK
		table.insert(parts, `<font color="{color}">{if long then buff.name else buff.short} x{Format.multiplier(buff.value)}</font>`)
	end
	return table.concat(parts, `<font color="{Ui.SOFT}">  ·  </font>`)
end

-- Tarjeta --------------------------------------------------------------------------------------------------

-- Ancho de la tarjeta según el texto más largo: el reloj tiene su hueco fijo, así que no baila con los segundos.
local function fit()
	if outer then
		local text = math.min(math.max(title.TextBounds.X, detail.TextBounds.X), TEXT_ROOM)
		outer.Size = UDim2.fromOffset(PAD + BADGE + 8 + math.ceil(text) + 14 + CLOCK_WIDTH + PAD, HEIGHT)
	end
end

function WeatherHud.build()
	if outer then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "Weather"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, TOP)
	frame.Size = UDim2.fromOffset(240, HEIGHT)
	frame.BackgroundTransparency = 1
	frame.Parent = Ui.hud()
	outer = frame

	card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = frame
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, Ui.STYLE.border)
	Ui.panel(card, Color3.fromRGB(46, 44, 86))

	-- Resplandor del color del clima que sale de la insignia.
	accent = Instance.new("Frame")
	accent.Name = "AccentGlow"
	accent.Size = UDim2.fromScale(0.6, 1)
	accent.BorderSizePixel = 0
	accent.Parent = card
	Ui.round(accent, 14)
	local spread = Instance.new("UIGradient")
	spread.Transparency = NumberSequence.new(0.55, 1)
	spread.Parent = accent

	badge, glyphBox = newBadge(card, BADGE, 1)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, PAD, 0.5, 0)

	-- Los dos textos miden lo que ocupe su letra (TEXT_ROOM de sitio, sin cortar) y la tarjeta se ajusta a ellos.
	title = Ui.label(card, 19)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(PAD + BADGE + 8, 5)
	title.Size = UDim2.fromOffset(TEXT_ROOM, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left

	detail = Ui.label(card, 14)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(PAD + BADGE + 8, 27)
	detail.Size = UDim2.fromOffset(TEXT_ROOM, 18)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	-- El ancho de la letra llega cuando la fuente está cargada: la tarjeta se vuelve a ajustar si cambia.
	title:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	detail:GetPropertyChangedSignal("TextBounds"):Connect(fit)

	clock = Ui.label(card, 22)
	clock.Name = "Clock"
	clock.AnchorPoint = Vector2.new(1, 0.5)
	clock.Position = UDim2.new(1, -PAD - 2, 0.5, 0)
	clock.Size = UDim2.fromOffset(CLOCK_WIDTH, 28)
	clock.TextXAlignment = Enum.TextXAlignment.Right
	clockPulse = Instance.new("UIScale")
	clockPulse.Parent = clock

	Ui.tip(card, function()
		local id, def = WeatherInfo.current()
		if not (id and def) then
			local every = math.floor(cfg.Interval / 60 + 0.5)
			return `<b>Cielo despejado</b>\n<font color="{Ui.SOFT}">Cada {every} min llega un clima distinto.\nTodos dan suerte de destructibles;\nlos más raros, también suerte de armas.</font>`, CLEAR
		end
		local tier = WeatherInfo.tier(def)
		local lines = {
			`<font color="{hex(def.color:Lerp(WHITE, 0.3))}"><b>{def.name}</b></font>`,
			`<font color="{hex(tier.color)}">{tier.name}  ·  {WeatherInfo.oddsText(id)}</font>`,
			`<font color="{Ui.SOFT}">{def.desc}</font>`,
			buffLine(def, true),
		}
		return table.concat(lines, "\n"), def.color
	end, true)

	WeatherHud.show(nil)
end

-- Pone en la tarjeta ese clima (nil = despejado: cuenta atrás del siguiente).
function WeatherHud.show(id: string?)
	if not outer then
		return
	end
	shownId = id
	shownSeconds = -1
	local def = if id then cfg.Events[id] else nil
	local color = if def then def.color else CLEAR
	drawBadge(badge, glyphBox, id)
	accent.BackgroundColor3 = color
	if def then
		title.Text = `<font color="{hex(def.color:Lerp(WHITE, 0.45))}">{def.name}</font>`
		detail.Text = buffLine(def)
	else
		title.Text = "Próximo clima"
		detail.Text = `<font color="{Ui.SOFT}">Cielo despejado</font>`
	end
	fit()
	-- Salto al cambiar (sin animaciones en modo rendimiento).
	if not Performance.get() then
		local scale = card:FindFirstChild("Pop") :: UIScale?
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "Pop"
			scale.Parent = card
		end
		(scale :: UIScale).Scale = 0.8
		TweenService:Create(scale :: UIScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Reloj de la tarjeta: lo que queda del clima o lo que falta para el siguiente. `now` es para el latido.
function WeatherHud.tick(seconds: number, now: number)
	if not outer then
		return
	end
	local whole = math.ceil(math.max(seconds, 0))
	if whole ~= shownSeconds then
		shownSeconds = whole
		clock.Text = PotionInfo.clock(whole)
	end
	local low = shownId ~= nil and seconds <= cfg.LowTime
	clock.TextColor3 = if low then LOW else WHITE
	clockPulse.Scale = if low and not Performance.get() then 1 + 0.1 * (0.5 + 0.5 * math.sin(now * 6)) else 1
end

-- Esconde la tarjeta mientras ese hueco es de otro panel (mazmorra, forja).
function WeatherHud.setHidden(hidden: boolean)
	if outer and card.Visible == hidden then
		card.Visible = not hidden
	end
end

-- Cartel ---------------------------------------------------------------------------------------------------

local banner: CanvasGroup? = nil

-- Cartel grande del clima que empieza: entra con rebote, se queda unos segundos y se va hacia la tarjeta.
function WeatherHud.announce(id: string)
	local def = cfg.Events[id]
	if not (outer and def) then
		return
	end
	if banner then
		banner:Destroy()
	end
	local tier = WeatherInfo.tier(def)
	local grand = def.tier >= 4 -- de Épica para arriba: más grande, con destello y otro sonido
	Sfx.play(if def.tier >= 6 then "win" elseif grand then "rare" else "toast")

	local group = Instance.new("CanvasGroup")
	group.Name = "WeatherBanner"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.36)
	group.Size = UDim2.fromOffset(690, 190)
	group.BackgroundTransparency = 1
	group.ZIndex = Z_BANNER
	group.Parent = Ui.hud()
	banner = group
	local scale = Instance.new("UIScale")
	scale.Parent = group

	-- La tarjeta, con el estilo de las ventanas: fondo oscuro en degradado teñido del color del clima, borde negro
	-- grueso y dos filos de su color. Va metida dentro del grupo para que el borde no quede cortado.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, -20, 1, -20)
	plate.ZIndex = Z_BANNER
	plate.Parent = group
	Ui.round(plate, 18)
	Ui.stroke(plate, BLACK, 5)
	Ui.panel(plate, Color3.fromRGB(40, 38, 78):Lerp(def.color, 0.2))
	local function band(name: string, position: UDim2, size: UDim2, color: Color3, solid: number): Frame
		local strip = Instance.new("Frame")
		strip.Name = name
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Position = position
		strip.Size = size
		strip.BackgroundColor3 = color
		strip.BorderSizePixel = 0
		strip.ZIndex = Z_BANNER
		strip.Parent = plate
		Ui.round(strip, 16)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, solid),
			NumberSequenceKeypoint.new(0.78, solid),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = strip
		return strip
	end
	band("EdgeTop", UDim2.new(0.5, 0, 0, 9), UDim2.new(0.8, 0, 0, 4), def.color:Lerp(WHITE, 0.35), 0)
	band("EdgeBottom", UDim2.new(0.5, 0, 1, -9), UDim2.new(0.8, 0, 0, 4), def.color:Lerp(WHITE, 0.35), 0)

	local function line(name: string, y: number, height: number, size: number, text: string): TextLabel
		local label = Ui.label(plate, size)
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, y)
		label.Size = UDim2.new(0.9, 0, 0, height)
		label.ZIndex = Z_BANNER + 1
		label.Text = text
		return label
	end
	line("Kicker", 18, 20, 17, `<font color="{Ui.SOFT}">EVENTO DE CLIMA</font>`)
	local name = line("Name", 38, 54, 46, upper(def.name))
	name.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = if grand then 50 else 44
	limit.MinTextSize = 22
	limit.Parent = name
	-- El nombre, del color del clima, más claro arriba.
	local paint = Instance.new("UIGradient")
	paint.Rotation = 90
	paint.Color = ColorSequence.new(def.color:Lerp(WHITE, 0.7), def.color:Lerp(WHITE, 0.15))
	paint.Parent = name
	line("Rarity", 94, 24, 20, `<font color="{hex(tier.color)}">{tier.name}  ·  {WeatherInfo.oddsText(id)}</font>`)
	line("Buffs", 120, 26, 21, buffLine(def, true))

	if Performance.get() then
		task.delay(4, function()
			if banner == group then
				banner = nil
			end
			group:Destroy()
		end)
		return
	end

	-- Destello que cruza el nombre de los climas raros.
	if grand then
		local glint = band("Glint", UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 1, -16), WHITE, 1)
		local sweep = glint:FindFirstChildOfClass("UIGradient") :: UIGradient
		sweep.Rotation = 20
		sweep.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sweep.Offset = Vector2.new(-1, 0)
		TweenService:Create(sweep, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, false, 0.5), { Offset = Vector2.new(1, 0) }):Play()
	end

	scale.Scale = 0.55
	group.GroupTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if grand then 1.08 else 1 }):Play()
	TweenService:Create(group, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	task.delay(if grand then 5 else 3.6, function()
		if not group.Parent then
			return
		end
		-- Se recoge hacia la tarjeta de arriba.
		local out = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(scale, out, { Scale = 0.4 }):Play()
		TweenService:Create(group, out, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, TOP + HEIGHT / 2) }):Play()
		task.delay(0.42, function()
			if banner == group then
				banner = nil
			end
			group:Destroy()
		end)
	end)
end

return WeatherHud
