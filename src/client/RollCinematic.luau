-- Cinemáticas de las tiradas de arma más raras (pedido por el usuario: "al juego le falta dopamina"). Librería sin
-- start(): la llama client/RollReveal cuando una tirada llega a un nivel con `cinematic` en sus LEVELS. Coge la
-- cámara unos segundos, enseña la escena de su tema y la devuelve; el arma sale luego en el mundo y vuela al
-- jugador como siempre. Temas:
--   star  — cae una estrella fugaz sobre el sitio del objeto roto y el arma sale del cráter de luz.
--   smith — un herrero espectral gigante la forja a martillazos en un yunque; el último la templa.
--   nova  — una estrella se encoge, calla y estalla; el arma queda girando en el núcleo.
-- Al final de todas sale la tarjeta del arma (rareza, nombre y su "1 entre N"), y el número sube contando hasta el
-- suyo (`RollCinematic.countUp`, que también usa el cartel del mundo de RollReveal).
-- Solo se ve una a la vez (las demás esperan turno, MAX_WAITING como mucho) y todo lo que toca (cámara, Hud,
-- Lighting) lo deja como estaba `release`, pase lo que pase: acabar, saltarla, un viaje o un error.
-- El herrero y la supernova se ruedan en un escenario cerrado y negro, lejos por encima del mapa, para no depender
-- de la hora ni del clima; la estrella, en el sitio de verdad.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponAuraDefs = require(script.Parent.WeaponAuraDefs)

local RollCinematic = {}

local player = Players.LocalPlayer
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 220, 100)
local EMBER = Color3.fromRGB(255, 170, 70) -- el arma al rojo y las chispas del yunque antes de saber la rareza
local VOID = Color3.fromRGB(6, 5, 12) -- paredes del escenario

local TEX = WeaponAuraDefs.textures
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Solo en Studio: Config.Test.RevealSlow alarga todos los tiempos, para revisarla en capturas.
local BASE = if RunService:IsStudio() then Config.Test.RevealSlow or 1 else 1
-- Ritmo de cada tema: por cuánto se alargan todos sus tiempos (pedido por el usuario, que las vio a su velocidad
-- de partida y le parecieron rápidas: la estrella y el herrero, bastante más lentas; las supernovas, un poco).
local PACE = { star = 2.4, smith = 2.4, nova = 1.2 }
local SLOW = BASE -- lo que vale ahora mismo: BASE por el ritmo del tema en marcha
local SKIP = "RollCinematic:skip" -- lo que "lanza" una escena al saltarla: corta la secuencia donde esté
local MAX_WAITING = 2 -- cinemáticas esperando turno; las que lleguen de más se enseñan en el mundo
local GRACE = 0.6 -- segundos hasta que sale el botón de saltar
local TIMEOUT = 35 -- red de seguridad: ninguna dura tanto
local STAGE_UP = 700 -- studs por encima de la cámara a los que se monta el escenario
local STAGE_HALF = 90 -- media arista del cubo negro
local DISPLAY = 5 -- studs que mide el arma enseñada
local TILT = CFrame.Angles(0, 0, math.rad(-22))
local SCREEN = Vector2.new(1100, 700) -- por debajo de este tamaño de pantalla la tarjeta se encoge (como el HUD)
local CARD = Vector2.new(460, 176)
-- Segundos que tarda el "1 entre N" en subir hasta su número, por nivel de RollReveal.
local COUNT = { [2] = 0.5, [3] = 0.8, [4] = 1.1, [5] = 2.2, [6] = 3 }
-- Capas de la interfaz (la del juego ordena el ZIndex globalmente; aquí también).
local Z = { bars = 1, rays = 2, card = 3, rim = 4, chip = 5, text = 6, skip = 7, cover = 20 }

local current = nil -- la escena en marcha
local waiting = 0 -- las que esperan turno
local hooked = false

-- Utilidades ----------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local created = TweenService:Create(instance, TweenInfo.new(seconds * SLOW, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	created:Play()
	return created
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function outCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Pasa del final y vuelve: lo que aparece "salta" un poco.
local function outBack(t: number): number
	local c = 1.70158
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function seq(points: { { number } }): NumberSequence
	local list = {}
	for _, point in points do
		table.insert(list, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(list)
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Corta la secuencia si la han saltado o ya no hay escena.
local function check(s)
	if s.skipped or s.released then
		error(SKIP, 0)
	end
end

local function wait(s, seconds: number)
	local elapsed = 0
	while elapsed < seconds * SLOW do
		elapsed += RunService.RenderStepped:Wait()
		check(s)
	end
end

-- Llama a `step(avance de 0 a 1)` cada fotograma durante `seconds` (espera a que acabe).
local function animate(s, seconds: number, step: (number) -> ())
	local total = seconds * SLOW
	local elapsed = 0
	while elapsed < total do
		elapsed += RunService.RenderStepped:Wait()
		check(s)
		step(math.min(elapsed / total, 1))
	end
end

-- Pieza de efecto: anclada, sin sombra ni colisiones.
local function piece(s, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = s.folder
	return part
end

-- Pieza invisible de la que cuelgan partículas y luces.
local function point(s, position: Vector3, size: number?): Part
	return piece(s, Enum.PartType.Block, Vector3.one * (size or 1), CFrame.new(position), WHITE, 1)
end

-- Pieza de luz que crece hasta `to` mientras se apaga, y se borra.
local function fading(s, shape: Enum.PartType, cframe: CFrame, from: Vector3, to: Vector3, color: Color3, transparency: number, seconds: number)
	local part = piece(s, shape, from, cframe, color, transparency)
	tween(part, seconds, { Size = to, Transparency = 1 })
	Debris:AddItem(part, seconds * SLOW + 0.1)
end

-- Onda plana que se abre; `tilt` la saca del suelo (para las explosiones en el aire).
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
local function ring(s, position: Vector3, from: number, to: number, color: Color3, seconds: number, tilt: CFrame?)
	fading(s, Enum.PartType.Cylinder, CFrame.new(position) * (tilt or CFrame.identity) * FLAT, Vector3.new(0.15, from, from), Vector3.new(0.15, to, to), color, 0.3, seconds)
end

local function emitter(parent: Instance, props: { [string]: any }, count: number?): ParticleEmitter
	local created = Instance.new("ParticleEmitter")
	created.Rate = 0
	created.LightInfluence = 0
	for name, value in props do
		(created :: any)[name] = value
	end
	created.Parent = parent
	if count then
		created:Emit(count)
	end
	return created
end

-- Chispas que saltan de golpe.
local function sparks(parent: Instance, color: Color3, count: number, speed: number, size: number)
	emitter(parent, {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.4 * SLOW, 1 * SLOW),
		Speed = NumberRange.new(speed * 0.4 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2.5,
		Size = seq({ { 0, size }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 1, 1 } }),
	}, count)
end

-- Polvo de estrellas que sale hacia fuera.
local function stardust(parent: Instance, color: Color3, count: number, speed: number, size: number)
	emitter(parent, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 0.8,
		Brightness = 1.6,
		Lifetime = NumberRange.new(0.8 * SLOW, 1.6 * SLOW),
		Speed = NumberRange.new(speed * 0.3 / SLOW, speed / SLOW),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		RotSpeed = NumberRange.new(-60, 60),
		Size = seq({ { 0, 0 }, { 0.2, size }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
	}, count)
end

-- Textura de cara a la cámara que aparece, se queda y se va (estallidos, destellos, remolinos). Las de fondo
-- negro (nova, vortex, portal) van con `emission` 1 o se ven como cuadrados negros.
local function sprite(parent: Instance, texture: string, color: Color3, size: number, seconds: number, turn: number, emission: number, grow: boolean?)
	emitter(parent, {
		Texture = texture,
		Color = ColorSequence.new(color),
		LightEmission = emission,
		Brightness = 1.4,
		Lifetime = NumberRange.new(seconds * SLOW),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(turn / SLOW),
		LockedToPart = true,
		Size = if grow then seq({ { 0, size * 0.15 }, { 1, size } }) else seq({ { 0, 0 }, { 0.15, size }, { 0.8, size }, { 1, size * 0.7 } }),
		Transparency = seq({ { 0, 1 }, { 0.12, 0.3 }, { 0.6, 0.45 }, { 1, 1 } }),
	}, 1)
end

-- Sello tumbado en el suelo, girando. Flojo y medio transparente a propósito: a mediodía se quema a blanco.
local function sealOn(s, position: Vector3, texture: string, color: Color3, size: number, seconds: number, turn: number): Part
	local base = point(s, position)
	emitter(base, {
		Texture = texture,
		Color = ColorSequence.new(color),
		LightEmission = 0.4,
		Brightness = 1.1,
		Lifetime = NumberRange.new(seconds * SLOW),
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0),
		RotSpeed = NumberRange.new(turn / SLOW),
		LockedToPart = true,
		Size = seq({ { 0, 0 }, { 0.08, size }, { 0.9, size }, { 1, size * 0.6 } }),
		Transparency = seq({ { 0, 1 }, { 0.1, 0.45 }, { 0.85, 0.5 }, { 1, 1 } }),
	}, 1)
	return base
end

-- El arma ---------------------------------------------------------------------------------

-- Modelo del arma de verdad, anclado y con el giro en su centro, encogido al mínimo. Devuelve también cuánto hay
-- que escalarlo para que mida `display` studs (lo usa también RollReveal).
function RollCinematic.sword(index: number, metal: number?, parent: Instance, display: number?): (Model, number)
	local model = Instance.new("Model")
	model.Name = "Sword"
	SwordModel.build(index, model, CFrame.identity, 1, true, metal)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CastShadow = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	local box, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	-- Todas se enseñan del mismo largo, salvo las muy finas (lanzas), que a ese largo casi no se verían: algo más.
	local long = math.max(size.X, size.Y, size.Z, 0.1)
	local wide = math.max(size.X + size.Y + size.Z - long - math.min(size.X, size.Y, size.Z), 0.1)
	local fit = (display or DISPLAY) / long * math.clamp(math.sqrt(long / wide / 4), 1, 1.5)
	model:ScaleTo(fit * 0.02)
	model.Parent = parent
	return model, fit
end

-- Pone el arma en la escena: la mueve el bucle de la escena con lo que diga `s.weapon` (sitio, giro, tamaño).
local function weapon(s, info, position: Vector3, display: number)
	local model, fit = RollCinematic.sword(info.roll.index, info.roll.metal, s.folder, display)
	local outline = Instance.new("Highlight")
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.OutlineColor = info.bright
	outline.FillColor = WHITE
	outline.FillTransparency = 0.85
	outline.Parent = model
	s.weapon = { model = model, fit = fit, outline = outline, position = position, yaw = 0, spin = 0, scale = 0.02, shown = 0, tilt = TILT, bob = 0 }
	return s.weapon
end

-- El contador ---------------------------------------------------------------------------

-- El número sube de 1 a `target` en `seconds`, por multiplicación (vale igual con 150 que con 1 Sp): arranca
-- deprisa y frena al llegar. `paint(texto abreviado, llegó)` lo escribe; cada tramo suena un tic más agudo.
-- `step`, opcional, se llama cada fotograma (para cortar: puede lanzar).
function RollCinematic.countUp(target: number, seconds: number, paint: (string, boolean) -> (), step: (() -> ())?)
	local total = seconds * SLOW
	local elapsed = 0
	local note = -1
	while elapsed < total do
		elapsed += RunService.RenderStepped:Wait()
		if step then
			step()
		end
		local eased = 1 - (1 - math.min(elapsed / total, 1)) ^ 2
		paint(Format.short(math.max(1, math.floor(target ^ eased))), false)
		local now = math.floor(eased * 14)
		if now ~= note then
			note = now
			Sfx.play("tick", 0.7, 2 ^ (now / 12))
		end
	end
	paint(Format.short(target), true)
end

function RollCinematic.countTime(level: number): number?
	return COUNT[level]
end

-- La interfaz ---------------------------------------------------------------------------

local function buildGui(s, info)
	local view = workspace.CurrentCamera.ViewportSize
	local factor = math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), 0.6, 1)
	local color, bright = info.color, info.bright

	local gui = Instance.new("ScreenGui")
	gui.Name = "RollCinematic"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	-- Tapa a pantalla completa: fundidos a negro y destellos.
	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = BLACK
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.ZIndex = Z.cover
	cover.Parent = gui

	-- Barras de cine.
	local bars = {}
	for index, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = if index == 1 then "BarTop" else "BarBottom"
		bar.AnchorPoint = Vector2.new(0, 1 - anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, 0.085)
		bar.BackgroundColor3 = BLACK
		bar.BorderSizePixel = 0
		bar.ZIndex = Z.bars
		bar.Parent = gui
		tween(bar, 0.3, { AnchorPoint = Vector2.new(0, anchor) })
		bars[index] = bar
	end

	-- Frase del nivel, arriba.
	local line = Ui.label(gui, math.round(30 * factor))
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(0.5, 0.115)
	line.Size = UDim2.fromScale(0.9, 0.07)
	line.Text = Ui.upper(Lang.t(nil, info.line))
	line.TextColor3 = if info.level >= 6 then GOLD else bright
	line.TextTransparency = 1
	line.ZIndex = Z.text
	local lineStroke = line:FindFirstChildOfClass("UIStroke")
	if lineStroke then
		lineStroke.Transparency = 1
	end

	-- Tarjeta del arma, abajo en el centro: rayos girando detrás, chapa de rareza, nombre y el "1 entre N" en grande.
	local holder = Instance.new("Frame")
	holder.Name = "Card"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.fromScale(0.5, 0.88)
	holder.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder

	local rays = Ui.image(holder, "boton_rayos")
	rays.Name = "Rays"
	rays.Size = UDim2.fromOffset(CARD.X * 1.25, CARD.X * 1.25)
	rays.ImageColor3 = if info.level >= 6 then GOLD else bright
	rays.ImageTransparency = 1
	rays.ZIndex = Z.rays

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = WHITE
	plate.BorderSizePixel = 0
	plate.ZIndex = Z.card
	plate.Parent = holder
	Ui.round(plate, 18)
	Ui.gradient(plate, Color3.fromRGB(52, 46, 84):Lerp(color, 0.18), Color3.fromRGB(18, 16, 32), 90)
	Ui.stroke(plate, BLACK, 5)
	-- Canto del color de la rareza por dentro del borde negro.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.BackgroundTransparency = 1
	rim.ZIndex = Z.rim
	rim.Parent = holder
	Ui.round(rim, 14)
	Ui.stroke(rim, if info.level >= 6 then GOLD else bright, 3)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(10, 8)
	gloss.Size = UDim2.new(1, -20, 0.3, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.9
	gloss.BorderSizePixel = 0
	gloss.ZIndex = Z.rim
	gloss.Parent = holder
	Ui.round(gloss, 12)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = content

	local rarityText = Ui.upper(Lang.t(nil, info.tier.name))
	local chip = Instance.new("Frame")
	chip.Name = "Rarity"
	chip.LayoutOrder = 1
	chip.Size = UDim2.fromOffset(TextService:GetTextSize(rarityText, 22, Ui.FONT, Vector2.new(1000, 34)).X + 40, 34)
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.ZIndex = Z.chip
	chip.Parent = content
	Ui.round(chip, 11)
	Ui.gradient(chip, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.4), 90)
	Ui.stroke(chip, BLACK, 3)
	local chipText = Ui.label(chip, 22)
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.Text = rarityText
	chipText.ZIndex = Z.text
	local chipScale = Instance.new("UIScale")
	chipScale.Scale = 0
	chipScale.Parent = chip

	local roll = info.roll
	local sword = Config.Swords[roll.index]
	local nameColor = if roll.metal and roll.metal > 0 then Config.Metals[roll.metal].color else sword.color
	local name = Ui.label(content, 27)
	name.Name = "Title"
	name.LayoutOrder = 2
	name.Size = UDim2.new(1, -28, 0, 34)
	name.TextScaled = true
	name.Text = Permanent.name(roll.index, roll.metal, roll.size)
	name.TextColor3 = nameColor:Lerp(WHITE, 0.4)
	name.TextTransparency = 1
	name.ZIndex = Z.text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 27
	limit.MinTextSize = 14
	limit.Parent = name

	local odds = Ui.label(content, 44)
	odds.Name = "Odds"
	odds.LayoutOrder = 3
	odds.Size = UDim2.new(1, -28, 0, 54)
	odds.Text = ""
	odds.TextColor3 = WHITE
	odds.ZIndex = Z.text
	local oddsScale = Instance.new("UIScale")
	oddsScale.Parent = odds

	if not roll.kept then
		local sold = Ui.label(content, 16)
		sold.Name = "Sold"
		sold.LayoutOrder = 4
		sold.Size = UDim2.new(1, -28, 0, 18)
		sold.Text = Lang.t(nil, "sold")
		sold.TextColor3 = Ui.COLORS.orange
		sold.ZIndex = Z.text
		chip.Size = UDim2.fromOffset(chip.Size.X.Offset, 30)
	end

	-- Saltar: solo con su botón (un clic cualquiera no vale: el jugador va haciendo clic para atacar y se la saltaría
	-- sin querer).
	local skip = Ui.button(gui, Lang.t(nil, "Skip"), Ui.COLORS.gray)
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 0.9, 0)
	skip.Size = UDim2.fromOffset(150, 52)
	skip.TextSize = 22
	skip.ZIndex = Z.skip
	skip.Visible = false
	local skipScale = Instance.new("UIScale")
	skipScale.Scale = factor
	skipScale.Parent = skip
	skip.Activated:Connect(function()
		s.skipped = true
	end)
	task.delay(GRACE, function()
		if gui.Parent then
			skip.Visible = true
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	s.gui = gui
	s.ui = { cover = cover, line = line, lineStroke = lineStroke, holder = holder, scale = scale, factor = factor, rays = rays, lineSize = line.TextSize, chipScale = chipScale, name = name, odds = odds, oddsScale = oddsScale }
end

-- Fundido de la tapa: a `transparency` en `seconds`.
local function cover(s, color: Color3, from: number, to: number, seconds: number)
	local frame = s.ui.cover
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = from
	tween(frame, seconds, { BackgroundTransparency = to })
end

local function showLine(s)
	local ui = s.ui
	tween(ui.line, 0.25, { TextTransparency = 0 })
	if ui.lineStroke then
		tween(ui.lineStroke, 0.25, { Transparency = 0 })
	end
end

-- Cambia la frase de arriba de golpe (la escalera de rarezas de la supernova), con un salto.
local function setLine(s, text: string, color: Color3)
	local ui = s.ui
	ui.line.Text = Ui.upper(text)
	ui.line.TextColor3 = color
	ui.line.TextTransparency = 0
	if ui.lineStroke then
		ui.lineStroke.Transparency = 0
	end
	local size = ui.lineSize
	ui.line.TextSize = math.round(size * 1.5)
	tween(ui.line, 0.22, { TextSize = size }, Enum.EasingStyle.Back)
end

-- La tarjeta: salta la rareza, luego el nombre y, lo último, el "1 entre N" subiendo hasta su número.
local function card(s, info)
	local ui = s.ui
	local roll = info.roll
	ui.line.Text = Ui.upper(Lang.t(nil, info.line))
	ui.line.TextColor3 = if info.level >= 6 then GOLD else info.bright
	showLine(s)
	tween(ui.scale, 0.28, { Scale = ui.factor }, Enum.EasingStyle.Back)
	wait(s, 0.12)
	tween(ui.chipScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	Sfx.play("tick", 1, 1)
	wait(s, 0.2)
	tween(ui.name, 0.18, { TextTransparency = 0 })
	local nameStroke = ui.name:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Transparency = 1
		tween(nameStroke, 0.18, { Transparency = 0 })
	end
	wait(s, 0.22)
	RollCinematic.countUp(Permanent.rarity(roll.index, roll.metal, roll.size), COUNT[info.level] or 1, function(text, arrived)
		ui.odds.Text = if arrived then Permanent.describeOdds(roll.index, roll.metal, roll.size) else Lang.t(nil, "1 in {n}", { n = text })
	end, function()
		check(s)
	end)
	-- Llegó: golpe del número, rayos detrás y destello del color de la rareza.
	ui.odds.TextColor3 = if info.level >= 6 then GOLD else info.bright:Lerp(WHITE, 0.25)
	ui.oddsScale.Scale = 1.45
	tween(ui.oddsScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.rays, 0.3, { ImageTransparency = 0.55 })
	cover(s, info.bright, 0.7, 1, 0.45)
	Sfx.play(if info.level >= 4 then "win" else "rare")
	s.shake = math.max(s.shake, 0.25)
end

-- La escena -----------------------------------------------------------------------------

local function hud(): ScreenGui?
	local gui = player:FindFirstChild("PlayerGui")
	return gui and gui:FindFirstChild("Hud") :: ScreenGui?
end

-- Esconde toda la interfaz mientras dura (pedido por el usuario, "para que sea más cinemático"): las capas de
-- PlayerGui, los carteles del mundo (los de las parcelas, los objetos, los sacos...; los que van siempre a la
-- vista se verían hasta a través del escenario) y lo de Roblox (chat, lista de jugadores). Devuelve lo escondido,
-- para volver a enseñarlo. Los números flotantes (en Terrain) no se tocan: son de un fondo común que se reutiliza.
local function hideUi(): { Instance }
	local hidden = {}
	local function hide(item: Instance)
		if (item:IsA("ScreenGui") or item:IsA("BillboardGui")) and item.Enabled and item.Name ~= "RollCinematic" then
			item.Enabled = false
			table.insert(hidden, item)
		end
	end
	local gui = player:FindFirstChild("PlayerGui")
	if gui then
		for _, item in gui:GetChildren() do
			hide(item)
		end
	end
	for _, child in workspace:GetChildren() do
		if child ~= workspace.Terrain then
			hide(child)
			for _, item in child:GetDescendants() do
				hide(item)
			end
		end
	end
	return hidden
end

local function setCore(on: boolean)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, on)
end

-- Devuelve la cámara, el Hud y Lighting, y borra el escenario. Se puede llamar varias veces.
local function release(s)
	if s.released then
		return
	end
	s.released = true
	s.loop:Disconnect()
	local camera = workspace.CurrentCamera
	camera.FieldOfView = s.saved.fov
	camera.CameraType = s.saved.type
	for _, item in s.hidden do
		if item.Parent then
			(item :: any).Enabled = true
		end
	end
	setCore(true)
	if s.haze then
		s.haze.Density = s.hazeWas
	end
	s.correction:Destroy()
	s.folder:Destroy()
end

local function newScene(info)
	local camera = workspace.CurrentCamera
	local s = {
		skipped = false,
		released = false,
		saved = { type = camera.CameraType, fov = camera.FieldOfView, cframe = camera.CFrame },
		cam = camera.CFrame,
		fov = camera.FieldOfView,
		shake = 0,
		clock = 0,
		spinning = {},
		hidden = hideUi(),
	}
	setCore(false)
	local folder = Instance.new("Folder")
	folder.Name = "RollCinematic"
	folder.Parent = workspace
	s.folder = folder
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "RollCinematic"
	correction.Parent = Lighting
	s.correction = correction
	buildGui(s, info)
	camera.CameraType = Enum.CameraType.Scriptable

	-- Un solo bucle: cámara (con su temblor), arma, rayos y los rayos de la tarjeta.
	s.loop = RunService.RenderStepped:Connect(function(dt)
		s.clock += dt
		local jolt = CFrame.identity
		if s.shake > 0.01 then
			jolt = CFrame.new(rng:NextNumber(-1, 1) * s.shake, rng:NextNumber(-1, 1) * s.shake, 0)
			s.shake *= math.exp(-dt * 7 / SLOW)
		end
		camera.CFrame = s.cam * jolt
		camera.FieldOfView = s.fov
		if s.haze then
			s.haze.Density = 0 -- cada fotograma: el ciclo de día y el clima la van cambiando
		end
		local held = s.weapon
		if held and held.model.Parent then
			held.yaw += held.spin * dt
			held.bob += dt
			if held.scale ~= held.shown then
				held.shown = held.scale
				held.model:ScaleTo(held.fit * math.max(held.scale, 0.02))
			end
			held.model:PivotTo(CFrame.new(held.position + Vector3.new(0, math.sin(held.bob * 2.6) * 0.12 * held.spin / 2.5, 0)) * CFrame.Angles(0, held.yaw, 0) * held.tilt)
		end
		for _, ray in s.spinning do
			ray.part.CFrame = CFrame.new(ray.centre) * CFrame.Angles(0, 0, s.clock * ray.speed) * ray.tilt
		end
		s.ui.rays.Rotation = s.clock * 40
	end)
	return s
end

-- Escenario cerrado y negro, lejos por encima del mapa. Devuelve su centro.
local function stage(s): Vector3
	local centre = workspace.CurrentCamera.CFrame.Position + Vector3.new(0, STAGE_UP, 0)
	local side = STAGE_HALF * 2
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		for _, sign in { -1, 1 } do
			piece(s, Enum.PartType.Block, Vector3.one * side - axis * (side - 2), CFrame.new(centre + axis * sign * STAGE_HALF), VOID, 0, Enum.Material.SmoothPlastic)
		end
	end
	s.correction.Contrast = 0.12
	s.correction.Saturation = 0.1
	s.staged = true
	-- Sin bruma: a esa distancia teñía las paredes del color del cielo (un lado naranja al atardecer).
	local haze = Lighting:FindFirstChildOfClass("Atmosphere")
	if haze then
		s.hazeWas = haze.Density
		s.haze = haze
	end
	return centre
end

-- Rayos largos que giran detrás del arma.
local function rays(s, centre: Vector3, count: number, length: number, color: Color3)
	for index = 1, count do
		local part = piece(s, Enum.PartType.Block, Vector3.new(1.3, length, 0.05), CFrame.new(centre), color, 1)
		tween(part, 0.5, { Transparency = 0.86 })
		table.insert(s.spinning, { part = part, centre = centre, speed = 0.35, tilt = CFrame.Angles(0, 0, index * math.pi / count) })
	end
end

-- Dónde poner la cámara para ver `focus` desde `eye` sin nada del mapa en medio (vallas, árboles): si algo tapa, se
-- acerca hasta delante de ello. El personaje y lo de la escena no cuentan.
local function clearView(s, focus: Vector3, eye: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { s.folder, player.Character :: Instance }
	params.RespectCanCollide = true
	local found = workspace:Raycast(focus, eye - focus, params)
	if found then
		local reach = math.max((found.Position - focus).Magnitude - 1.5, 6)
		return focus + (eye - focus).Unit * reach
	end
	return eye
end

-- Temas ---------------------------------------------------------------------------------

local THEMES = {}

-- Estrella fugaz: en el sitio de verdad. La cámara mira al cielo, la estrella cae sobre donde estaba el objeto y
-- el arma sale del cráter de luz.
function THEMES.star(s, info)
	local color, bright = info.color, info.bright
	local floor = Vector3.new(info.origin.X, info.ground + 0.2, info.origin.Z)
	local root = rootPart()
	local toward = ((if root then root.Position else s.saved.cframe.Position) - floor) * Vector3.new(1, 0, 1)
	toward = if toward.Magnitude > 0.5 then toward.Unit else Vector3.zAxis
	local side = Vector3.yAxis:Cross(toward)
	local hit = floor + Vector3.new(0, 0.8, 0)
	local sky = floor + side * 60 - toward * 35 + Vector3.new(0, 150, 0)
	-- La cámara, a un lado del jugador (no detrás de él, que lo taparía todo) y sin vallas en medio.
	local eye = clearView(s, floor + Vector3.new(0, 3, 0), floor + toward * 8 - side * 19 + Vector3.new(0, 3, 0))

	-- 1. El cielo se oscurece y la cámara baja a mirar hacia arriba.
	tween(s.correction, 0.5, { Brightness = -0.2, Contrast = 0.2, TintColor = Color3.fromRGB(175, 185, 255) })
	Sfx.play("charge", 0.8, 0.8)
	local from = s.saved.cframe
	local up = CFrame.lookAt(eye, floor:Lerp(sky, 0.7))
	animate(s, 0.55, function(t)
		s.cam = from:Lerp(up, smooth(t))
		s.fov = lerp(s.saved.fov, 64, t)
	end)

	-- 2. Un destello en lo alto, y cae.
	local star = piece(s, Enum.PartType.Ball, Vector3.one * 3.2, CFrame.new(sky), bright, 0)
	local lamp = Instance.new("PointLight")
	lamp.Color = bright
	lamp.Brightness = 2
	lamp.Range = 30
	lamp.Parent = star
	sprite(star, TEX.star, WHITE, 26, 0.9, 25, 0.8)
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Position, b.Position = Vector3.new(0, 1.5, 0), Vector3.new(0, -1.5, 0)
	a.Parent, b.Parent = star, star
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a, b
	trail.Color = ColorSequence.new(WHITE, color)
	trail.Transparency = seq({ { 0, 0 }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 1 }, { 1, 0 } })
	trail.Lifetime = 0.5 * SLOW
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = star
	local dust = emitter(star, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 0.8,
		Rate = 70 / SLOW,
		Lifetime = NumberRange.new(0.5 * SLOW, 0.9 * SLOW),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Size = seq({ { 0, 1.6 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	})
	Sfx.play("cine_fall")
	wait(s, 0.4)
	animate(s, 0.7, function(t)
		local at = sky:Lerp(hit, t ^ 2.2)
		star.Position = at
		s.cam = CFrame.lookAt(eye, at:Lerp(hit + Vector3.new(0, 3, 0), t ^ 3))
	end)

	-- 3. Impacto: destello, ondas, sello en el suelo, columna de luz y polvo de estrellas.
	dust.Enabled = false
	trail.Enabled = false
	star.Transparency = 1
	lamp.Range = 22
	tween(lamp, 1.2, { Brightness = 0.9 })
	cover(s, bright:Lerp(WHITE, 0.6), 0.25, 1, 0.5)
	s.shake = 0.9
	Sfx.play("cine_impact")
	Sfx.play("reveal_4")
	for wave = 1, 3 do
		task.delay((wave - 1) * 0.12 * SLOW, function()
			if not s.released then
				ring(s, floor, 3, 26 + wave * 10, bright, 0.7)
			end
		end)
	end
	sealOn(s, floor, TEX.seal, color, 15, 6, 35)
	sealOn(s, floor + Vector3.new(0, 0.05, 0), TEX.seal2, bright, 11, 6, -50)
	fading(s, Enum.PartType.Cylinder, CFrame.new(hit + Vector3.new(0, 60, 0)) * FLAT, Vector3.new(120, 5, 5), Vector3.new(120, 0.3, 0.3), bright, 0.4, 1.3)
	fading(s, Enum.PartType.Ball, CFrame.new(hit), Vector3.one * 2, Vector3.one * 16, bright, 0.35, 0.45)
	local burst = point(s, hit)
	stardust(burst, color, 70, 34, 2.2)
	sparks(burst, color, 60, 30, 1.1)
	sprite(burst, TEX.nova, bright, 20, 0.7, -220, 1, true)

	-- 4. El arma sale del cráter y la cámara se acerca.
	local held = weapon(s, info, hit, DISPLAY)
	held.spin = 12
	local impact = s.cam
	local close = CFrame.lookAt(clearView(s, floor + Vector3.new(0, 4.4, 0), floor + toward * 4 - side * 10 + Vector3.new(0, 4.4, 0)), floor + Vector3.new(0, 4.3, 0))
	local top = floor + Vector3.new(0, 5.4, 0)
	animate(s, 0.75, function(t)
		held.position = hit:Lerp(top, outCubic(t))
		held.scale = outBack(math.min(t * 1.6, 1))
		held.spin = lerp(12, 2.5, t)
		s.cam = impact:Lerp(close, smooth(t))
		s.fov = lerp(64, 54, t)
	end)
	local halo = point(s, top)
	sprite(halo, TEX.shine, bright, 11, 5, 14, 1)
	card(s, info)
	animate(s, 1, function(t)
		s.cam = close * CFrame.new(0, 0, -1.2 * t)
	end)
	-- 5. Vuelta a la cámara del jugador.
	tween(s.correction, 0.3, { Brightness = 0, Contrast = 0, TintColor = WHITE })
	local back = s.cam
	animate(s, 0.3, function(t)
		s.cam = back:Lerp(s.saved.cframe, smooth(t))
		s.fov = lerp(54, s.saved.fov, t)
	end)
end

-- Herrero celestial: un gigante espectral forja el arma a martillazos; con el último se templa y se ve cuál es.
function THEMES.smith(s, info)
	local color, bright = info.color, info.bright
	local spirit = color:Lerp(BLACK, 0.7) -- cuerpo oscuro: lo dibujan el contorno de luz y las dos luces
	cover(s, BLACK, 1, 0, 0.18)
	wait(s, 0.18)
	local centre = stage(s)
	local function at(x: number, y: number, z: number): Vector3
		return centre + Vector3.new(x, y, z)
	end
	local camWide = CFrame.lookAt(at(-6, 7, 32), at(1, 9.5, -2))
	local camNear = CFrame.lookAt(at(-2, 6, 25), at(1.2, 9, -1))
	s.cam, s.fov = camWide, 58

	-- Suelo, yunque y luz de fragua.
	piece(s, Enum.PartType.Cylinder, Vector3.new(0.6, 44, 44), CFrame.new(at(0, -0.3, 0)) * FLAT, Color3.fromRGB(20, 18, 30), 0, Enum.Material.Slate)
	sealOn(s, at(0, 0.1, 0), TEX.seal, color, 26, 14, 14)
	sealOn(s, at(0, 0.15, 0), TEX.seal2, bright, 17, 14, -22)
	local iron = Color3.fromRGB(96, 98, 116)
	piece(s, Enum.PartType.Block, Vector3.new(7, 1.2, 3.4), CFrame.new(at(1.5, 0.6, 0)), iron, 0, Enum.Material.Metal)
	piece(s, Enum.PartType.Block, Vector3.new(4.4, 1.6, 2.2), CFrame.new(at(1.5, 2, 0)), iron, 0, Enum.Material.Metal)
	local anvilTop = piece(s, Enum.PartType.Block, Vector3.new(9, 1.2, 3.2), CFrame.new(at(1.5, 3.4, 0)), iron:Lerp(WHITE, 0.08), 0, Enum.Material.Metal)
	piece(s, Enum.PartType.Block, Vector3.new(2.6, 0.8, 2), CFrame.new(at(-4, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(-8)), iron, 0, Enum.Material.Metal)
	local fire = Instance.new("PointLight")
	fire.Color = EMBER
	fire.Brightness = 3
	fire.Range = 30
	fire.Parent = point(s, at(1.5, 6, 3))
	local fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(190, 205, 255)
	fill.Brightness = 1.1
	fill.Range = 46
	fill.Parent = point(s, at(-9, 17, 8))

	-- El herrero: torso, cabeza con cuernos y ojos, hombros y dos brazos. Sale de una nube; sin piernas.
	local ghost = {}
	local figure = Instance.new("Model")
	figure.Name = "Smith"
	figure.Parent = s.folder
	local aura = Instance.new("Highlight")
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.OutlineColor = bright
	aura.FillColor = color
	aura.FillTransparency = 1
	aura.OutlineTransparency = 1
	aura.Parent = figure
	local function body(shape: Enum.PartType, size: Vector3, cframe: CFrame, tone: Color3?): Part
		local part = piece(s, shape, size, cframe, tone or spirit, 1, Enum.Material.Slate)
		part.Parent = figure
		table.insert(ghost, part)
		return part
	end
	body(Enum.PartType.Block, Vector3.new(7, 6.4, 3.6), CFrame.new(at(0, 9.6, -6.4)) * CFrame.Angles(math.rad(10), 0, 0))
	body(Enum.PartType.Block, Vector3.new(5.2, 3.4, 3), CFrame.new(at(0, 5.2, -6.9)))
	body(Enum.PartType.Ball, Vector3.one * 3.7, CFrame.new(at(0, 14.6, -5.7)))
	body(Enum.PartType.Block, Vector3.new(0.7, 2.6, 0.7), CFrame.new(at(-1.7, 16.7, -5.7)) * CFrame.Angles(0, 0, math.rad(24)))
	body(Enum.PartType.Block, Vector3.new(0.7, 2.6, 0.7), CFrame.new(at(1.7, 16.7, -5.7)) * CFrame.Angles(0, 0, math.rad(-24)))
	body(Enum.PartType.Ball, Vector3.one * 3, CFrame.new(at(-4.3, 12, -5.9)))
	body(Enum.PartType.Ball, Vector3.one * 3, CFrame.new(at(4.3, 12, -5.9)))
	-- Delantal, cinturón y hombreras, para que no sea un muñeco de cajas.
	body(Enum.PartType.Block, Vector3.new(5.6, 5.4, 0.5), CFrame.new(at(0, 7.4, -4.7)) * CFrame.Angles(math.rad(10), 0, 0), spirit:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(7.4, 1, 4), CFrame.new(at(0, 7, -6.6)), iron:Lerp(BLACK, 0.5))
	body(Enum.PartType.Block, Vector3.new(3.8, 1, 3.8), CFrame.new(at(-4.5, 13.3, -5.9)) * CFrame.Angles(0, 0, math.rad(18)), iron:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(3.8, 1, 3.8), CFrame.new(at(4.5, 13.3, -5.9)) * CFrame.Angles(0, 0, math.rad(-18)), iron:Lerp(BLACK, 0.4))
	body(Enum.PartType.Block, Vector3.new(4.2, 1.5, 4.2), CFrame.new(at(0, 15.9, -5.7)), iron:Lerp(BLACK, 0.4))
	-- Ojos y un núcleo de luz en el pecho.
	local eyes = {
		piece(s, Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(at(-0.8, 14.7, -4)), WHITE, 1),
		piece(s, Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(at(0.8, 14.7, -4)), WHITE, 1),
		piece(s, Enum.PartType.Ball, Vector3.one * 1.5, CFrame.new(at(0, 11, -4.3)), bright, 1),
	}
	-- Brazo izquierdo: quieto, sujetando el arma por el mango.
	local grip = at(-2.4, 4.4, -0.4)
	local leftShoulder = at(-4.3, 11.6, -5.6)
	body(Enum.PartType.Block, Vector3.new(1.9, 1.9, (grip - leftShoulder).Magnitude), CFrame.lookAt(leftShoulder:Lerp(grip, 0.5), grip))
	-- Brazo derecho con el martillo: gira en el hombro. 150° = arriba y atrás; 322° = sobre el yunque.
	local shoulder = CFrame.new(at(4.3, 11.6, -5.6))
	local arm = {
		{ part = body(Enum.PartType.Block, Vector3.new(1.9, 7.4, 1.9), shoulder), offset = CFrame.new(0, -3.5, 0) },
		{ part = body(Enum.PartType.Block, Vector3.new(0.8, 3.4, 0.8), shoulder, iron:Lerp(WHITE, 0.2)), offset = CFrame.new(0, -7, 0) },
		{ part = body(Enum.PartType.Block, Vector3.new(3.2, 2.5, 2.5), shoulder, iron:Lerp(WHITE, 0.3)), offset = CFrame.new(0, -8.5, 0) },
	}
	local function swing(degrees: number)
		local turn = shoulder * CFrame.Angles(math.rad(degrees), 0, 0)
		for _, link in arm do
			link.part.CFrame = turn * link.offset
		end
	end
	swing(322)
	local mist = point(s, at(0, 2.5, -7), 9)
	emitter(mist, {
		Texture = SMOKE,
		Color = ColorSequence.new(spirit),
		LightEmission = 0.5,
		Rate = 14,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(60, 60),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-12, 12),
		Size = seq({ { 0, 4 }, { 1, 9 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.7 }, { 1, 1 } }),
	})
	for _, part in ghost do
		tween(part, 0.45, { Transparency = 0 })
	end
	tween(aura, 0.45, { OutlineTransparency = 0 })
	for _, eye in eyes do
		tween(eye, 0.45, { Transparency = 0 })
	end

	-- El arma, tumbada en el yunque y al rojo: se ve la forma, no los colores.
	local held = weapon(s, info, at(1.5, 4.25, 0), 6)
	held.tilt = CFrame.Angles(0, 0, -math.pi / 2)
	held.scale = 1
	held.outline.FillColor = EMBER
	held.outline.FillTransparency = 0
	held.outline.OutlineColor = WHITE

	cover(s, BLACK, 0, 1, 0.3)
	Sfx.play("cine_smith")
	wait(s, 0.3)

	-- 1. Tres martillazos, cada uno más fuerte; la cámara se va acercando.
	local strikePoint = at(4.3, 4.6, -0.4)
	local hits = 3
	local progress = 0
	local function push(amount: number)
		progress = math.min(progress + amount, 1)
		s.cam = camWide:Lerp(camNear, smooth(progress))
	end
	for hit = 1, hits do
		local last = hit == hits
		animate(s, if last then 0.6 else 0.4, function(t)
			swing(lerp(322, if last then 135 else 150, outCubic(t)))
			push(0.004)
		end)
		wait(s, if last then 0.22 else 0.06)
		animate(s, 0.1, function(t)
			swing(lerp(if last then 135 else 150, 322, t * t))
		end)
		local spot = point(s, strikePoint)
		s.shake = if last then 1.3 else 0.35 + hit * 0.15
		fire.Brightness = 7
		tween(fire, 0.3, { Brightness = 3 })
		if last then
			break
		end
		Sfx.play("cine_hammer", 1, 0.9 + hit * 0.1)
		sparks(spot, EMBER, 30 + hit * 20, 26, 0.9)
		ring(s, strikePoint - Vector3.new(0, 0.5, 0), 2, 12, EMBER, 0.35)
		animate(s, 0.12, function(t)
			swing(lerp(322, 304, outCubic(t)))
		end)
	end

	-- 2. El último la templa: estalla en el color de la rareza y el arma se enfría a sus colores de verdad.
	Sfx.play("cine_quench")
	Sfx.play("reveal_5")
	cover(s, bright:Lerp(WHITE, 0.5), 0.15, 1, 0.55)
	local spot = point(s, strikePoint)
	sparks(spot, color, 120, 40, 1.3)
	stardust(spot, color, 50, 26, 1.8)
	sprite(spot, TEX.nova, bright, 22, 0.7, -240, 1, true)
	for wave = 1, 3 do
		task.delay((wave - 1) * 0.12 * SLOW, function()
			if not s.released then
				ring(s, at(1.5, 0.3, 0), 4, 34 + wave * 8, bright, 0.7)
			end
		end)
	end
	emitter(point(s, at(1.5, 4.4, 0), 5), {
		Texture = SMOKE,
		Color = ColorSequence.new(WHITE),
		Lifetime = NumberRange.new(0.8 * SLOW, 1.4 * SLOW),
		Speed = NumberRange.new(4 / SLOW, 9 / SLOW),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 1.5 }, { 1, 6 } }),
		Transparency = seq({ { 0, 0.5 }, { 1, 1 } }),
	}, 16)
	tween(held.outline, 0.6, { FillTransparency = 0.88, OutlineColor = bright, FillColor = WHITE })
	tween(fire, 0.5, { Color = color, Brightness = 1.3 })
	tween(fill, 0.5, { Brightness = 1.6, Color = bright })

	-- 3. El herrero se aparta y el arma se levanta del yunque, girando.
	for _, part in ghost do
		tween(part, 0.8, { Transparency = 0.75 })
	end
	for _, eye in eyes do
		tween(eye, 0.8, { Transparency = 0.6 })
	end
	tween(aura, 0.8, { OutlineTransparency = 0.6, FillTransparency = 1 })
	local camShow = CFrame.lookAt(at(1.5, 7.8, 15), at(1.5, 6.4, 0))
	local lifted = at(1.5, 8.6, 1.5)
	local lying = held.position
	local struck = s.cam
	animate(s, 0.85, function(t)
		local e = smooth(t)
		swing(lerp(322, 230, e))
		held.position = lying:Lerp(lifted, e)
		held.tilt = CFrame.Angles(0, 0, math.rad(lerp(-90, -22, e)))
		held.spin = 2.5 * e
		s.cam = struck:Lerp(camShow, e)
		s.fov = lerp(58, 50, e)
	end)
	rays(s, lifted - Vector3.new(0, 0, 3), 5, 30, bright)
	card(s, info)
	animate(s, 1.1, function(t)
		s.cam = camShow * CFrame.new(0, 0, -1.2 * t)
	end)
end

-- Supernova: lo más raro del juego, así que va despacio y sube por pasos (pedido por el usuario: la primera versión
-- le pareció muy rápida). La estrella late y va subiendo de rareza, un color detrás de otro y cada vez más deprisa,
-- hasta la del arma; se encoge tragando luz, calla un instante y estalla. El arma sale como una silueta blanca,
-- revienta en sus colores y el "1 entre N" sube contando; al llegar, otra explosión (dos y lluvia de estrellas en
-- la absoluta).
function THEMES.nova(s, info)
	local color, bright = info.color, info.bright
	local jackpot = info.level >= 6
	cover(s, BLACK, 1, 0, 0.18)
	wait(s, 0.18)
	local centre = stage(s)
	local function camAt(distance: number, height: number): CFrame
		return CFrame.lookAt(centre + Vector3.new(distance * 0.18, height, distance), centre)
	end
	s.cam, s.fov = camAt(52, 3), 70

	-- Campo de estrellas y la estrella.
	local field = point(s, centre, 110)
	emitter(field, {
		Texture = TEX.stardust,
		Color = ColorSequence.new(WHITE, bright),
		LightEmission = 0.8,
		Rate = 60,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(0, 0.5),
		Size = seq({ { 0, 0 }, { 0.5, 1.3 }, { 1, 0 } }),
		Transparency = seq({ { 0, 1 }, { 0.5, 0.2 }, { 1, 1 } }),
	}, 60)
	-- Escalera de rarezas: de unas cuantas por debajo hasta la del arma.
	local last = 1
	for index, tier in Config.RarityTiers do
		if tier.name == info.tier.name then
			last = index
		end
	end
	local steps = {}
	for index = math.max(1, last - (if jackpot then 7 else 5)), last do
		table.insert(steps, Config.RarityTiers[index])
	end
	local tone = steps[1].color
	local star = piece(s, Enum.PartType.Ball, Vector3.one * 7, CFrame.new(centre), tone:Lerp(WHITE, 0.3), 0)
	local lamp = Instance.new("PointLight")
	lamp.Color = tone
	lamp.Brightness = 3
	lamp.Range = 60
	lamp.Parent = star
	local core = point(s, centre)
	local corona = emitter(core, {
		Texture = TEX.shine,
		Color = ColorSequence.new(tone),
		LightEmission = 1,
		Rate = 12,
		Lifetime = NumberRange.new(0.9, 1.2),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(20),
		LockedToPart = true,
		Size = seq({ { 0, 16 }, { 0.5, 26 }, { 1, 16 } }),
		Transparency = seq({ { 0, 1 }, { 0.5, 0.35 }, { 1, 1 } }),
	})
	cover(s, BLACK, 0, 1, 0.4)
	Sfx.play("cine_star")

	-- 1. Late y sube de rareza, cada paso más deprisa, más grande y más agudo; la cámara se va acercando.
	local distance = 52
	local size = 7
	local function beat(seconds: number, grow: number)
		local from, to = size, size + grow
		local near = distance - 1.4
		local far = distance
		animate(s, seconds, function(t)
			-- Salta de tamaño y se asienta.
			star.Size = Vector3.one * (lerp(from, to, outCubic(t)) + math.sin(t * math.pi) * 1.6)
			distance = lerp(far, near, t)
			s.cam = camAt(distance, 3)
		end)
		size = to
	end
	setLine(s, Lang.t(nil, steps[1].name), steps[1].color:Lerp(WHITE, 0.3))
	beat(0.9, 0)
	for index = 2, #steps do
		local tier = steps[index]
		local final = index == #steps
		tone = tier.color
		local light = tone:Lerp(WHITE, 0.3)
		star.Color = light
		lamp.Color = tone
		corona.Color = ColorSequence.new(tone)
		setLine(s, Lang.t(nil, tier.name), light)
		cover(s, light, 0.72, 1, 0.3)
		s.shake = 0.25 + index * 0.1
		ring(s, centre, 6, 60 + index * 8, light, 0.6, CFrame.Angles(math.rad(14), 0, math.rad(index * 23 - 60)))
		sparks(core, tone, 20 + index * 8, 40, 1.4)
		Sfx.play("charge", 1, 2 ^ ((index - 1) * 2 / 12))
		if final then
			-- Es esta: se queda, con su estallido.
			Sfx.play("rare")
			sprite(core, TEX.nova, light, 40, 0.8, -200, 1, true)
			stardust(core, tone, 60, 50, 2.6)
			beat(1.1, 2.5)
		else
			beat(lerp(0.62, 0.3, (index - 2) / math.max(#steps - 2, 1)), 0.7)
		end
	end
	local hot = bright:Lerp(WHITE, 0.3)

	-- 2. Se encoge: traga luz de alrededor, cada vez más deprisa, y todo se oscurece.
	local whirl = emitter(core, {
		Texture = TEX.vortex,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 3 / SLOW,
		Lifetime = NumberRange.new(1 * SLOW),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(260 / SLOW),
		LockedToPart = true,
		Size = seq({ { 0, 30 }, { 1, 2 } }),
		Transparency = seq({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }),
	})
	local collapse = if jackpot then 3 else 2.4
	tween(s.correction, collapse, { Brightness = -0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(s.ui.line, collapse * 0.6, { TextTransparency = 1 })
	if s.ui.lineStroke then
		tween(s.ui.lineStroke, collapse * 0.6, { Transparency = 1 })
	end
	local note = -1
	local full, wide = size, distance
	Sfx.play("cine_collapse")
	animate(s, collapse, function(t)
		local e = t * t
		star.Size = Vector3.one * lerp(full, 0.6, e)
		star.Color = hot
		lamp.Range = lerp(60, 14, e)
		s.cam = camAt(lerp(wide, 28, e), 3 - 2 * e)
		s.fov = lerp(70, 42, e)
		s.shake = math.max(s.shake, 0.22 * e)
		for _ = 1, 2 do
			if rng:NextNumber() < 0.2 + 0.7 * t then
				local streak = piece(s, Enum.PartType.Ball, Vector3.one * 0.45, CFrame.new(centre + rng:NextUnitVector() * rng:NextNumber(22, 40)), bright, 0.2)
				tween(streak, 0.32, { Position = centre, Size = Vector3.one * 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(streak, 0.32 * SLOW + 0.05)
			end
		end
		-- Latidos que se van juntando.
		local now = math.floor(e * 16)
		if now ~= note then
			note = now
			Sfx.play("charge", 0.5, 2 ^ (now / 12))
			ring(s, centre, 44 - now * 2, 2, bright, 0.3, CFrame.Angles(math.rad(14), 0, math.rad(now * 31)))
		end
	end)

	-- 3. Silencio: un punto en la oscuridad.
	whirl.Enabled = false
	corona.Enabled = false
	star.Size = Vector3.one * 0.3
	lamp.Brightness = 0.4
	wait(s, 0.8)

	-- 4. Estalla.
	local function explode(shade: Color3, power: number, sound: string?)
		cover(s, shade:Lerp(WHITE, 0.75), 0, 1, 0.6)
		s.shake = 1.6 * power
		Sfx.play(sound or "cine_boom", math.min(power, 1))
		fading(s, Enum.PartType.Ball, CFrame.new(centre), Vector3.one, Vector3.one * 90 * power, shade, 0.3, 0.9)
		fading(s, Enum.PartType.Ball, CFrame.new(centre), Vector3.one, Vector3.one * 40 * power, WHITE, 0.2, 0.45)
		ring(s, centre, 2, 110 * power, shade, 0.9, CFrame.Angles(math.rad(10), 0, math.rad(18)))
		ring(s, centre, 2, 90 * power, WHITE, 0.75, CFrame.Angles(math.rad(-16), 0, math.rad(-35)))
		ring(s, centre, 2, 70 * power, shade, 1.1, CFrame.Angles(math.rad(22), 0, math.rad(60)))
		local burst = point(s, centre)
		sprite(burst, TEX.nova, shade, 46 * power, 0.9, -200, 1, true)
		stardust(burst, shade, 140, 70, 3)
		sparks(burst, shade, 110, 60, 1.8)
	end
	star:Destroy()
	explode(bright, 1)
	Sfx.play("reveal_5")
	tween(s.correction, 0.4, { Brightness = 0.05 })
	local glow = Instance.new("PointLight")
	glow.Color = bright
	glow.Brightness = 2.2
	glow.Range = 50
	glow.Parent = core

	-- 5. El arma sale del núcleo como una silueta de luz, girando deprisa, mientras la cámara se acerca...
	local held = weapon(s, info, centre, 6)
	held.spin = 22
	held.outline.FillTransparency = 0
	held.outline.OutlineColor = WHITE
	local back = camAt(28, 1)
	local near = CFrame.lookAt(centre + Vector3.new(0, -0.6, 15.5), centre + Vector3.new(0, -2.6, 0))
	s.fov = 92
	animate(s, 1.5, function(t)
		local e = outCubic(t)
		held.scale = outBack(math.min(t * 1.8, 1))
		held.spin = lerp(22, 7, e)
		s.cam = back:Lerp(near, e)
		s.fov = lerp(92, 52, e)
	end)
	wait(s, 0.25)
	-- ...y revienta en sus colores.
	tween(held.outline, 0.35, { FillTransparency = 0.88, OutlineColor = bright })
	cover(s, bright:Lerp(WHITE, 0.6), 0.2, 1, 0.5)
	s.shake = 0.8
	Sfx.play("reveal_4")
	sprite(core, TEX.nova, bright, 26, 0.7, 220, 1, true)
	stardust(core, color, 80, 40, 2.4)
	ring(s, centre, 2, 60, bright, 0.7, CFrame.Angles(math.rad(12), 0, 0))
	rays(s, centre - Vector3.new(0, 0, 4), if jackpot then 9 else 6, 60, bright)
	sprite(core, TEX.shine, bright, 16, 12, 16, 1)
	animate(s, 0.5, function(t)
		held.spin = lerp(7, 2.5, t)
	end)

	-- 6. La tarjeta, con el número subiendo; al llegar, otra explosión.
	card(s, info)
	explode(if jackpot then GOLD else bright, if jackpot then 0.8 else 0.55, if jackpot then "cine_gold" else nil)
	if jackpot then
		-- Premio gordo: lluvia de estrellas y una explosión más.
		emitter(point(s, centre + Vector3.new(0, 26, 0), 50), {
			Texture = TEX.star,
			Color = ColorSequence.new(WHITE, GOLD),
			LightEmission = 0.8,
			Rate = 26 / SLOW,
			Lifetime = NumberRange.new(1.6 * SLOW, 2.4 * SLOW),
			Speed = NumberRange.new(16 / SLOW, 26 / SLOW),
			EmissionDirection = Enum.NormalId.Bottom,
			RotSpeed = NumberRange.new(-90, 90),
			Size = seq({ { 0, 1.8 }, { 1, 0.4 } }),
			Transparency = seq({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
		})
		wait(s, 0.7)
		explode(bright, 0.7)
		Sfx.play("win")
	end
	local hold = if jackpot then 3 else 2.2
	animate(s, hold, function(t)
		s.cam = near * CFrame.Angles(0, math.rad(lerp(-5, 5, smooth(t))), 0) * CFrame.new(0, 0, -1.4 * t)
	end)
end

-- Entrada -------------------------------------------------------------------------------

local function free(): boolean
	if Performance.get() or player:GetAttribute("RollCinematics") == false or Ui.anyOpen() or not rootPart() then
		return false
	end
	local gui = player:FindFirstChild("PlayerGui")
	local layer = hud()
	-- Eligiendo objeto para el trébol o con la pantalla de Mejoras abierta, no.
	local picking = layer and layer:FindFirstChild("CloverPick", true) :: GuiObject?
	local upgrades = gui and gui:FindFirstChild("UpgradesScreen") :: ScreenGui?
	local tree = upgrades and upgrades:FindFirstChild("Upgrades") :: GuiObject?
	return not (picking and picking.Visible) and not (tree and tree.Visible)
end

-- ¿Hay una cinemática en marcha? Mientras tanto SwordController no ataca con el clic.
function RollCinematic.isActive(): boolean
	return current ~= nil
end

-- Pide turno para una cinemática: false si ahora no toca (modo Rendimiento, ajuste apagado, una ventana abierta,
-- otra escena con la cámara, como la forja, o demasiadas esperando). Quien recibe true tiene que llamar a `play`.
function RollCinematic.reserve(): boolean
	if not free() or waiting >= MAX_WAITING then
		return false
	end
	if not current and workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	waiting += 1
	return true
end

-- Enseña la cinemática del tema `theme` y espera a que acabe o la salten. `info` = { roll, tier, level, line,
-- origin (dónde estaba el orbe), ground (Y del suelo) }. Devuelve false si al final no se pudo enseñar.
function RollCinematic.play(theme: string, info): boolean
	while current do
		task.wait(0.1)
	end
	waiting -= 1
	if not THEMES[theme] or not free() or workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	if not hooked then
		hooked = true
		-- Un viaje (barra de transporte, mazmorra) corta la que haya.
		Remotes.Teleported.OnClientEvent:Connect(function()
			if current then
				current.skipped = true
			end
		end)
	end
	info.color = info.tier.color
	info.bright = info.color:Lerp(WHITE, 0.35)
	SLOW = BASE * (PACE[theme] or 1)
	local s = newScene(info)
	current = s
	task.delay(TIMEOUT * SLOW, function()
		s.skipped = true
	end)
	local ok, problem = pcall(THEMES[theme], s, info)
	if not ok and problem ~= SKIP then
		warn(`[RollCinematic] {problem}`)
	end
	if ok and s.staged and not s.skipped then
		-- De vuelta del escenario: fundido a negro, se devuelve la cámara y se abre.
		pcall(function()
			cover(s, BLACK, 1, 0, 0.2)
			wait(s, 0.22)
		end)
		release(s)
		s.ui.holder.Visible = false
		s.ui.line.Visible = false
		tween(s.ui.cover, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.3 * SLOW)
	else
		release(s)
	end
	s.gui:Destroy()
	SLOW = BASE
	current = nil
	return true
end

return RollCinematic
