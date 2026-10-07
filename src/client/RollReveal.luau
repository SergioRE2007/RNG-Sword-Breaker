-- Las tiradas de arma, enseñadas en el mundo. El servidor decide el arma y la entrega (server/Gacha); aquí solo
-- se ve: al romperse un objeto, la energía sale de donde estaba y se junta en un orbe por cada tirada; cada orbe
-- se carga, se destapa (sale el arma de verdad, con shared/SwordModel, y su cartel: rareza, nombre y lo difícil
-- que era), se queda un momento girando y vuela al jugador, que la recoge. Las armas vendidas solas se deshacen
-- en el sitio. No hay ventana ni se para el juego: el jugador sigue rompiendo mientras tanto.
-- Cuánto espectáculo lleva cada tirada (LEVELS) sale de lo difícil que era para el jugador con su suerte
-- ("1 entre N" que manda el servidor, Config.Gacha.RevealOdds), no de la rareza a secas: la rareza pone el color.
-- Varias tiradas de un mismo objeto salen juntas en abanico y se destapan una detrás de otra.
-- Todo lo que crea va en una carpeta por tanda dentro de workspace.RollReveals y se borra al acabar.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local RollReveal = {}

local player = Players.LocalPlayer
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 220, 100)

local MYSTERY = Color3.fromRGB(150, 105, 255) -- color de la energía mientras no se sabe qué ha tocado (oscuro: el neón claro se quema en blanco)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local DISPLAY = 5 -- studs que mide el arma enseñada, sea una daga o una lanza
local TILT = CFrame.Angles(0, 0, math.rad(-22)) -- un poco ladeada, con la punta hacia arriba
local SPACING = 3.6 -- studs entre las tiradas de un mismo objeto
-- Solo en Studio: Config.Test.RevealSlow alarga todos los tiempos, para revisar la presentación en capturas.
local SLOW = if RunService:IsStudio() then Config.Test.RevealSlow or 1 else 1
local EMERGE = 0.18 * SLOW -- segundos que tarda la energía en salir del objeto y hacerse orbe
local ORB = 1.15 -- diámetro del orbe
local FAR = 220 -- más lejos que esto del jugador no se enseña nada en el mundo
local MAX_BATCHES = 10 -- tandas a la vez; las que lleguen de más van directas a la recogida
local CROWDED = 4 -- con más tandas que estas a la vez, las tiradas normales se dan prisa
local HURRY = 0.55 -- por cuánto se multiplican entonces sus tiempos
local SCREEN = Vector2.new(1100, 700) -- por debajo de este tamaño de pantalla los carteles se encogen (como el HUD)
local LABEL = Vector2.new(300, 108) -- tamaño del cartel en píxeles, sin escalar

-- Niveles de espectáculo: 1 Normal, 2 Buena, 3 Genial, 4 Increíble y 5 Premio gordo.
-- charge = segundos que el orbe se carga antes de destaparse, pulses = latidos en ese rato, rise = studs que sube
-- mientras tanto, hover = segundos que el arma se queda a la vista, fly = segundos de vuelo, turns = vueltas de
-- espiral en el vuelo, sparks = chispas al destaparse, aura = chispas por segundo alrededor del arma, shock = ondas
-- en el suelo, light = brillo de la luz, beam = grosor del rayo hacia el cielo, punch = grados que se abre la
-- cámara, shake = fuerza del temblor, absorb = el orbe traga energía de alrededor, rays = rayos que giran,
-- flash = destello de pantalla, grow = tamaño del cartel, sounds = lo que suena al destaparse.
local LEVELS = {
	{ charge = 0.2, pulses = 1, rise = 0, hover = 0.42, fly = 0.38, turns = 0, sparks = 8, grow = 1, sounds = { "coin" } },
	{ charge = 0.36, pulses = 2, rise = 0.4, hover = 0.7, fly = 0.44, turns = 0, sparks = 16, aura = 8, grow = 1.1, sounds = { "gem" } },
	{ charge = 0.7, pulses = 3, rise = 0.9, hover = 1.1, fly = 0.52, turns = 0.5, sparks = 28, aura = 14, shock = 1, light = 0.8, grow = 1.25, sounds = { "rare", "gem" } },
	{ charge = 1.25, pulses = 5, rise = 1.8, hover = 1.6, fly = 0.7, turns = 1, sparks = 46, aura = 22, shock = 2, light = 1.2, beam = 1.4, punch = 5, shake = 0.4, absorb = true, grow = 1.45, sounds = { "rare", "win" } },
	{ charge = 2.1, pulses = 8, rise = 2.6, hover = 2.2, fly = 0.85, turns = 1.5, sparks = 80, aura = 34, shock = 3, light = 1.6, beam = 2.6, punch = 9, shake = 0.7, absorb = true, rays = true, flash = true, grow = 1.7, sounds = { "win", "rare" } },
}
-- Frase encima del cartel en los niveles altos.
local LINES = { [3] = "¡Buena tirada!", [4] = "¡El destino te ha elegido!", [5] = "¡Los cielos se abren ante ti!" }

-- Capas del cartel (la interfaz ordena el ZIndex globalmente).
local Z = { chip = 2, text = 3 }

local container: Folder
local batches = {} -- [id de tanda] = { id, count, origin, box, skip, folder, rolls = { [n] = tirada } }
local running = 0 -- tandas enseñándose ahora mismo
local loose = 0 -- para numerar las tiradas que llegan sin tanda
local factor = 1 -- escala de la interfaz en esta pantalla

-- Utilidades ----------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local created = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	created:Play()
	return created
end

-- Llama a `step(avance de 0 a 1)` cada fotograma durante `seconds` (espera a que acabe).
local function animate(seconds: number, step: (number) -> ())
	local elapsed = 0
	while elapsed < seconds do
		elapsed += RunService.RenderStepped:Wait()
		step(math.min(elapsed / seconds, 1))
	end
end

-- Pasa del final y vuelve: lo que aparece "salta" un poco.
local function outBack(t: number): number
	local c = 1.70158
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

-- Pieza de efecto: anclada, sin sombra ni colisiones, de luz.
local function glow(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Pieza de efecto que crece hasta `to` mientras se apaga, y se borra.
local function fading(shape: Enum.PartType, cframe: CFrame, from: Vector3, to: Vector3, color: Color3, transparency: number, seconds: number, parent: Instance)
	local part = glow(shape, from, cframe, color, transparency, parent)
	tween(part, seconds, { Size = to, Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
end

local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- los cilindros salen tumbados: así quedan de pie (o planos, como discos)

-- Onda plana que se abre en ese punto.
local function ring(parent: Instance, position: Vector3, from: number, to: number, color: Color3, seconds: number)
	fading(Enum.PartType.Cylinder, CFrame.new(position) * FLAT, Vector3.new(0.12, from, from), Vector3.new(0.12, to, to), color, 0.35, seconds, parent)
end

-- Chispas que saltan de golpe desde `parent` (una pieza o un Attachment).
local function sparks(parent: Instance, color: Color3, count: number, speed: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.85)
	emitter.Speed = NumberRange.new(speed * 0.45, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, 1.2)
end

local function randomUnit(): Vector3
	return rng:NextUnitVector()
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Nivel de espectáculo de un "1 entre N".
local function levelOf(odds: number): number
	local level = 1
	for index, limit in Config.Gacha.RevealOdds do
		if odds >= limit then
			level = index + 1
		end
	end
	return math.min(level, #LEVELS)
end

-- Cámara: solo reacciona a lo muy bueno, y sin quitarle el mando al jugador.
local punching = false
local function punch(degrees: number)
	local camera = workspace.CurrentCamera
	if punching or not camera then
		return
	end
	punching = true
	local base = camera.FieldOfView
	camera.FieldOfView = base + degrees
	local back = tween(camera, 0.55, { FieldOfView = base }, Enum.EasingStyle.Back)
	back.Completed:Once(function()
		camera.FieldOfView = base
		punching = false
	end)
end

local function shake(strength: number, seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < seconds and humanoid.Parent do
			local fade = 1 - (os.clock() - began) / seconds
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength * fade
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- Destello de pantalla, corto y suave.
local function screenFlash(color: Color3)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RollFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ResetOnSpawn = false
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = color:Lerp(WHITE, 0.6)
	cover.BackgroundTransparency = 0.45
	cover.BorderSizePixel = 0
	cover.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	tween(cover, 0.55, { BackgroundTransparency = 1 })
	Debris:AddItem(gui, 0.7)
end

-- El arma ---------------------------------------------------------------------------------

-- Modelo del arma de verdad (el mismo que lleva en la mano), anclado y con el giro en su centro. Devuelve también
-- cuánto hay que escalarlo para que mida DISPLAY.
local function buildSword(index: number, metal: number?, parent: Instance): (Model, number)
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
	local fit = DISPLAY / long * math.clamp(math.sqrt(long / wide / 4), 1, 1.5)
	model:ScaleTo(fit * 0.02)
	model.Parent = parent
	return model, fit
end

-- El cartel ---------------------------------------------------------------------------------

local function textLine(parent: Instance, order: number, textSize: number, height: number, text: string, color: Color3): TextLabel
	local line = Ui.label(parent, textSize)
	line.LayoutOrder = order
	line.Size = UDim2.new(1, 0, 0, height)
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.Text = text
	line.TextColor3 = color
	line.ZIndex = Z.text
	return line
end

-- Cartel sobre el arma: primero salta la rareza y enseguida el nombre y lo difícil que era. Devuelve cómo quitarlo.
local function buildLabel(folder: Instance, anchor: BasePart, roll, level: number, tier, odds: number): () -> ()
	local fx = LEVELS[level]
	local size = fx.grow * factor
	local gui = Instance.new("BillboardGui")
	gui.Name = "RollLabel"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(LABEL.X * size, LABEL.Y * size)
	gui.SizeOffset = Vector2.new(0, 0.5) -- se apoya en su punto en vez de centrarse en él
	gui.StudsOffsetWorldSpace = Vector3.new(0, DISPLAY / 2 + 0.1, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Parent = folder

	-- Medidas en píxeles a propósito: el cartel mide lo mismo a cualquier distancia y lo encoge entero un UIScale.
	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromOffset(LABEL.X, LABEL.Y)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local rootScale = Instance.new("UIScale")
	rootScale.Scale = size
	rootScale.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = root

	local color = tier.color
	local texts = {}
	if LINES[level] then
		table.insert(texts, textLine(root, 1, 17, 20, LINES[level], GOLD))
	end

	-- Rareza: una chapa con el color de la rareza, que es lo primero que se lee.
	local rarityText = string.upper(tier.name)
	local chip = Instance.new("Frame")
	chip.Name = "Rarity"
	chip.LayoutOrder = 2
	chip.Size = UDim2.fromOffset(TextService:GetTextSize(rarityText, 19, Ui.FONT, Vector2.new(1000, 30)).X + 34, 30)
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.ZIndex = Z.chip
	chip.Parent = root
	Ui.round(chip, 10)
	Ui.gradient(chip, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.4), 90)
	Ui.stroke(chip, BLACK, 3)
	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.fromOffset(3, 2)
	gloss.Size = UDim2.new(1, -6, 0.42, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = Z.chip
	gloss.Parent = chip
	Ui.round(gloss, 8)
	local chipText = Ui.label(chip, 19)
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.Text = rarityText
	chipText.ZIndex = Z.text
	local chipScale = Instance.new("UIScale")
	chipScale.Scale = 0
	chipScale.Parent = chip

	local sword = Config.Swords[roll.index]
	local nameColor = if roll.metal and roll.metal > 0 then Config.Metals[roll.metal].color else sword.color
	table.insert(texts, textLine(root, 3, 21, 26, Permanent.name(roll.index, roll.metal, roll.size), nameColor:Lerp(WHITE, 0.4)))

	-- La etiqueta usa la probabilidad base; la dificultad efectiva solo decide el espectáculo.
	local detail = {}
	table.insert(detail, `<font color="{Ui.SOFT}">{Permanent.describeOdds(roll.index, roll.metal, roll.size)}</font>`)
	if not roll.kept then
		table.insert(detail, `<font color="#{Ui.COLORS.orange:ToHex()}">vendida</font>`)
	end
	if #detail > 0 then
		table.insert(texts, textLine(root, 4, if level >= 4 then 19 else 15, if level >= 4 then 22 else 18, table.concat(detail, "  ·  "), WHITE))
	end

	-- Salta la rareza y, un instante después, aparecen los textos.
	tween(chipScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	for _, line in texts do
		local stroke = line:FindFirstChildOfClass("UIStroke")
		line.TextTransparency = 1
		if stroke then
			stroke.Transparency = 1
		end
		task.delay(0.13, function()
			if line.Parent then
				tween(line, 0.16, { TextTransparency = 0 })
				if stroke then
					tween(stroke, 0.16, { Transparency = 0 })
				end
			end
		end)
	end

	return function()
		if gui.Parent then
			tween(rootScale, 0.14, { Scale = 0.01 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Debris:AddItem(gui, 0.16)
		end
	end
end

-- Recogida ----------------------------------------------------------------------------------

-- El arma llega al jugador: chispas, sonido y, si era buena, su nombre subiendo junto a él.
local function collect(roll, level: number, color: Color3)
	local root = rootPart()
	Sfx.play("buyPing", if level >= 2 then 0.8 else 0.45)
	if not root then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "RollCollect"
	point.Position = Vector3.new(0, 0.6, 0)
	point.Parent = root
	Debris:AddItem(point, 1.6)
	if not Performance.get() then
		sparks(point, color, 6 + level * 4, 9 + level * 2, 0.45 + level * 0.08)
	end
	if level < 2 then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RollGot"
	gui.Adornee = point
	gui.Size = UDim2.fromOffset(280 * factor, 30 * factor)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = point
	local text = Ui.label(gui, math.round(19 * factor))
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "+ " .. Permanent.name(roll.index, roll.metal, roll.size)
	text.TextColor3 = color:Lerp(WHITE, 0.35)
	local stroke = text:FindFirstChildOfClass("UIStroke")
	tween(gui, 1.1, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) })
	local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7)
	TweenService:Create(text, fade, { TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end
end

-- Una tirada --------------------------------------------------------------------------------

-- La energía sale del objeto (`heart`) y se junta en un orbe en `slot`.
local function emerge(folder: Instance, heart: Vector3, slot: Vector3, lite: boolean): Part
	local orb = glow(Enum.PartType.Ball, Vector3.one * 0.2, CFrame.new(heart), MYSTERY, 0.1, folder)
	orb.Name = "Orb"
	tween(orb, EMERGE, { Position = slot, Size = Vector3.one * ORB }, Enum.EasingStyle.Back)
	if lite then
		return orb
	end
	local lamp = Instance.new("PointLight")
	lamp.Color = MYSTERY
	lamp.Brightness = 0.9
	lamp.Range = 9
	lamp.Parent = orb
	for _ = 1, 5 do
		local wisp = glow(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(heart + randomUnit() * rng:NextNumber(1.5, 4)), MYSTERY:Lerp(WHITE, 0.15), 0.25, folder)
		local seconds = EMERGE * rng:NextNumber(0.7, 1.15)
		tween(wisp, seconds, { Position = slot, Size = Vector3.one * 0.12, Transparency = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(wisp, seconds + 0.05)
	end
	return orb
end

-- Carga el orbe, lo destapa y deja el arma girando. Vuelve en cuanto se ha destapado; lo demás (quedarse a la
-- vista, volar al jugador y la recogida) sigue por su cuenta y avisa con `done()` al acabar.
local function present(folder: Instance, roll, orb: Part, slot: Vector3, ground: number, lite: boolean, done: () -> ())
	local odds = roll.odds
	local level = levelOf(odds)
	local fx = LEVELS[level]
	local tier = Rarity.tier(Permanent.rarity(roll.index, roll.metal, roll.size))
	local color = tier.color
	local bright = color:Lerp(WHITE, 0.35)
	-- Con muchas a la vez, las normales se dan prisa.
	local pace = (if level == 1 and running > CROWDED then HURRY else 1) * SLOW

	-- 1. Carga: el orbe late, sube y, si la tirada es buena, traga energía y acaba tomando el color de la rareza.
	local charge = fx.charge * pace
	local top = slot + Vector3.new(0, fx.rise, 0)
	tween(orb, charge, { Position = top }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if level >= 3 then
		task.delay(charge * 0.6, function()
			if orb.Parent then
				tween(orb, charge * 0.4, { Color = bright })
			end
		end)
	end
	local spinning = {}
	if fx.rays and not lite then
		for index = 1, 6 do
			local ray = glow(Enum.PartType.Block, Vector3.new(0.14, 0.14, 15), orb.CFrame, MYSTERY, 0.7, folder)
			table.insert(spinning, { part = ray, tilt = CFrame.Angles(0, index * math.pi / 3, 0) * CFrame.Angles(math.rad(rng:NextNumber(-28, 28)), 0, 0) })
		end
	end
	local beat = charge / fx.pulses
	local clock = 0
	for pulse = 1, fx.pulses do
		if not orb.Parent then
			break
		end
		local big = ORB * (1.25 + pulse * 0.05)
		TweenService:Create(orb, TweenInfo.new(beat / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Size = Vector3.one * big }):Play()
		if not lite then
			ring(folder, orb.Position, ORB, ORB * (2.4 + level * 0.5), if pulse > fx.pulses - 2 and level >= 3 then bright else MYSTERY, beat * 0.9)
		end
		if level >= 2 then
			Sfx.play("tick", 0.6)
		end
		if fx.rays then
			shake(0.1 + pulse * 0.04, beat)
		end
		animate(beat, function()
			clock += 1 / 60
			if fx.absorb and not lite and rng:NextNumber() < 0.45 then
				local from = orb.Position + randomUnit() * rng:NextNumber(8, 14)
				local streak = glow(Enum.PartType.Ball, Vector3.one * 0.55, CFrame.new(from), if pulse > fx.pulses - 2 then bright else MYSTERY, 0.25, folder)
				tween(streak, 0.26, { Position = orb.Position, Size = Vector3.one * 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(streak, 0.3)
			end
			for _, ray in spinning do
				ray.part.CFrame = CFrame.new(orb.Position) * CFrame.Angles(0, clock * 1.6, 0) * ray.tilt
				ray.part.Color = orb.Color
			end
		end)
	end
	for _, ray in spinning do
		ray.part:Destroy()
	end
	if not folder.Parent then
		done()
		return
	end

	-- 2. Se destapa: el orbe estalla en el color de la rareza y sale el arma.
	local position = if orb.Parent then orb.Position else top
	orb:Destroy()
	-- Pieza invisible que acompaña al arma: lleva el cartel, la luz, las chispas y la estela.
	local follow = Instance.new("Part")
	follow.Name = "Follow"
	follow.Anchored = true
	follow.CanCollide = false
	follow.CanQuery = false
	follow.CanTouch = false
	follow.Transparency = 1
	follow.Size = Vector3.one
	follow.CFrame = CFrame.new(position)
	follow.Parent = folder

	for delay, name in fx.sounds do
		task.delay((delay - 1) * 0.12, Sfx.play, name, if level == 1 then 0.6 else 1) -- las normales suenan flojo: salen a todas horas
	end
	local lamp: PointLight? = nil
	if not lite then
		fading(Enum.PartType.Ball, CFrame.new(position), Vector3.one * ORB, Vector3.one * (ORB * 2 + level * 0.8), color, 0.45, 0.28, folder)
		ring(folder, position, ORB, 3.5 + level * 2.5, bright, 0.4)
		sparks(follow, color, fx.sparks, 12 + level * 4, 0.5 + level * 0.12)
		for wave = 1, fx.shock or 0 do
			task.delay((wave - 1) * 0.13, function()
				if folder.Parent then
					ring(folder, Vector3.new(position.X, ground + 0.2, position.Z), 3, 14 + level * 7, bright, 0.5 + level * 0.05)
				end
			end)
		end
		if fx.beam then
			fading(Enum.PartType.Cylinder, CFrame.new(position + Vector3.new(0, 55, 0)) * FLAT, Vector3.new(120, fx.beam * 1.6, fx.beam * 1.6), Vector3.new(120, 0.2, 0.2), color, 0.45, 1 + level * 0.1, folder)
		end
		if fx.light then
			-- Luz corta y de poco alcance: una luz fuerte teñía toda la escena del color de la rareza.
			local created = Instance.new("PointLight")
			created.Color = color
			created.Brightness = fx.light
			created.Range = 9 + level * 1.5
			created.Parent = follow
			tween(created, 0.6, { Brightness = fx.light * 0.35 })
			lamp = created
		end
		if fx.punch then
			punch(fx.punch)
		end
		if fx.shake then
			shake(fx.shake, 0.4)
		end
		if fx.flash then
			screenFlash(color)
		end
	end

	local ok, model, fit = pcall(buildSword, roll.index, roll.metal, folder)
	if not ok then
		warn(`[RollReveal] {model}`)
		done()
		return
	end
	-- Para que se vea bien de noche y contra cualquier fondo: contorno del color de la rareza, un halo suave detrás
	-- y una luz pequeña.
	local outline = Instance.new("Highlight")
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.OutlineColor = bright
	outline.FillColor = WHITE
	outline.FillTransparency = 0.82
	outline.Parent = model
	local halo = glow(Enum.PartType.Ball, Vector3.one * 0.1, CFrame.new(position), color, 0.9, folder)
	halo.Name = "Halo"
	if not lite then
		local shine = Instance.new("PointLight")
		shine.Color = WHITE:Lerp(color, 0.3)
		shine.Brightness = 0.7
		shine.Range = 8
		shine.Parent = follow
	end
	local hideLabel = buildLabel(folder, follow, roll, level, tier, odds)
	-- Destapada: el servidor ya puede enseñar su aura y su aviso a los demás (misma cuenta que hace él).
	if odds >= math.min(Config.Gacha.AuraOdds, Config.Gacha.AnnounceOdds) then
		Remotes.GachaRevealed:FireServer()
	end

	-- Chispas alrededor del arma mientras está a la vista (desde Buena).
	local aura: ParticleEmitter? = nil
	if fx.aura and not lite then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SPARKLE
		emitter.Color = ColorSequence.new(bright, color)
		emitter.LightEmission = 0.9
		emitter.Rate = fx.aura
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(1.5, 4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.4 + level * 0.07), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.Parent = follow
		follow.Size = Vector3.one * DISPLAY * 0.7
		aura = emitter
	end

	-- El arma gira y flota; `state` lo mueve quien lleva la tirada (aparecer, quedarse, volar).
	local state = { position = position, yaw = rng:NextNumber(0, math.pi * 2), spin = 9, scale = 0.02, bob = 0 }
	local shown = 0
	local alive = true
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not alive or not model.Parent then
			connection:Disconnect()
			return
		end
		state.yaw += state.spin * dt
		state.bob += dt
		local at = state.position + Vector3.new(0, math.sin(state.bob * 3.2) * 0.16, 0)
		if state.scale ~= shown then
			shown = state.scale
			model:ScaleTo(fit * state.scale)
		end
		model:PivotTo(CFrame.new(at) * CFrame.Angles(0, state.yaw, 0) * TILT)
		halo.CFrame = CFrame.new(at)
		halo.Size = Vector3.one * DISPLAY * 0.75 * state.scale
		follow.CFrame = CFrame.new(at)
	end)

	task.spawn(function()
		-- Aparece de golpe, pasándose un poco de tamaño, y el giro se calma.
		animate(0.16 * SLOW, function(t)
			state.scale = math.max(outBack(t), 0.02)
			state.spin = 9 - 6.5 * t
		end)
		-- 3. Se queda a la vista lo justo para leerla (más cuanto mejor es; las vendidas, menos).
		task.wait(fx.hover * pace * (if roll.kept then 1 else 0.6))
		hideLabel()
		if aura then
			aura.Enabled = false
		end
		if lamp then
			tween(lamp, 0.25, { Brightness = 0 })
		end

		local target = rootPart()
		if not roll.kept or not target or not folder.Parent then
			-- Vendida sola (o sin jugador a quien ir): se deshace en el sitio.
			if not lite and folder.Parent then
				sparks(follow, color, 10, 8, 0.4)
			end
			animate(0.22 * SLOW, function(t)
				state.scale = math.max(1 - t, 0.02)
				state.spin = 2.5 + 12 * t
			end)
		else
			-- 4. Vuela al jugador: arranca despacio, se acelera y encoge, por una curva (con espiral en las mejores).
			local trail: Trail? = nil
			if not lite then
				local a = Instance.new("Attachment")
				a.Position = Vector3.new(0, 0.9, 0)
				a.Parent = follow
				local b = Instance.new("Attachment")
				b.Position = Vector3.new(0, -0.9, 0)
				b.Parent = follow
				local created = Instance.new("Trail")
				created.Attachment0 = a
				created.Attachment1 = b
				created.Color = ColorSequence.new(bright, color)
				created.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
				created.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
				created.Lifetime = 0.22 + level * 0.06
				created.LightEmission = 0.7
				created.FaceCamera = true
				created.Parent = follow
				trail = created
			end
			local start = state.position
			local side = (target.Position - start):Cross(Vector3.yAxis)
			side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
			local swerve = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(1.5, 3.5)
			local lift = 1.2 + level * 0.6
			animate(fx.fly * SLOW, function(t)
				local goal = if target.Parent then target.Position + Vector3.new(0, 0.6, 0) else start
				local eased = t ^ 2.3
				local middle = (start + goal) / 2 + Vector3.new(0, lift, 0) + side * swerve
				local along = start * (1 - eased) ^ 2 + middle * (2 * (1 - eased) * eased) + goal * eased ^ 2
				if fx.turns > 0 then
					-- Espiral alrededor del camino, que se cierra al llegar.
					local angle = eased * fx.turns * math.pi * 2
					along += (side * math.cos(angle) + Vector3.yAxis * math.sin(angle)) * (1.1 + level * 0.25) * math.sin(eased * math.pi)
				end
				state.position = along
				state.scale = 1 - 0.65 * eased
				state.spin = 2.5 + 16 * eased
			end)
			if trail then
				trail.Enabled = false
			end
			collect(roll, level, color)
			if level >= 4 then
		Ui.toast(`¡{Permanent.name(roll.index, roll.metal, roll.size)}!\n{Permanent.describeOdds(roll.index, roll.metal, roll.size)}`, color)
			end
		end
		alive = false
		connection:Disconnect()
		model:Destroy()
		halo:Destroy()
		-- La estela y las últimas chispas se apagan solas antes de borrarse.
		Debris:AddItem(follow, 0.9)
		done()
	end)
end

-- Una tanda (las tiradas de un objeto) ------------------------------------------------------

-- De dónde sale la energía, dónde se abre el abanico de tiradas, hacia qué lado y a qué altura está el suelo.
local function anchors(batch): (Vector3?, Vector3, Vector3, number)
	local root = rootPart()
	local origin, box = batch.origin, batch.box
	if batch.skip then
		return nil, Vector3.zero, Vector3.xAxis, 0
	end
	if not origin or not box then
		-- Sin objeto (una tirada de prueba, u otra fuente): como si saliera de una caja delante del jugador.
		if not root then
			return nil, Vector3.zero, Vector3.xAxis, 0
		end
		box = Vector3.new(3, 3, 3)
		origin = root.Position + root.CFrame.LookVector * 7 - Vector3.new(0, 1.2, 0)
	end
	if root and (root.Position - origin).Magnitude > FAR then
		return nil, Vector3.zero, Vector3.xAxis, 0
	end
	local ground = origin.Y - box.Y / 2
	-- La energía nace en el centro del objeto, pero no más alto de lo que se ve cómodamente.
	local heart = Vector3.new(origin.X, ground + math.min(box.Y / 2, 9), origin.Z)
	local toward = if root then (root.Position - origin) * Vector3.new(1, 0, 1) else Vector3.zAxis
	local distance = toward.Magnitude
	toward = if distance > 0.5 then toward.Unit else Vector3.zAxis
	-- El abanico se abre por encima de los escombros y algo hacia el jugador (un objeto enorme lo taparía).
	local half = math.max(box.X, box.Z) / 2
	local centre = Vector3.new(origin.X, ground + math.clamp(box.Y * 0.5 + 2.5, 4.5, 8), origin.Z) + toward * math.min(half * 0.6, distance * 0.5)
	return heart, centre, Vector3.yAxis:Cross(toward), ground -- derecha del jugador: se destapan de izquierda a derecha
end

local function finish(batch)
	batches[batch.id] = nil
	running -= 1
	if batch.folder then
		batch.folder:Destroy()
	end
end

-- Sin sitio para enseñarla (demasiadas a la vez, o muy lejos): directa a la recogida.
local function shortcut(roll)
	local level = levelOf(roll.odds)
	local tier = Rarity.tier(Permanent.rarity(roll.index, roll.metal, roll.size))
	if roll.odds >= math.min(Config.Gacha.AuraOdds, Config.Gacha.AnnounceOdds) then
		Remotes.GachaRevealed:FireServer()
	end
	if roll.kept then
		collect(roll, level, tier.color)
	end
	if level >= 3 then
		Ui.toast(`¡{Permanent.name(roll.index, roll.metal, roll.size)}!\n{Permanent.describeOdds(roll.index, roll.metal, roll.size)}`, tier.color)
	end
end

local function play(batch)
	local heart, centre, right, ground = anchors(batch)
	if not heart then
		-- Las tiradas de la tanda llegan en el mismo instante: se espera un momento a tenerlas todas.
		task.wait(0.1)
		for _, roll in batch.rolls do
			shortcut(roll)
		end
		finish(batch)
		return
	end
	local lite = Performance.get()
	local folder = Instance.new("Folder")
	folder.Name = "Batch"
	folder.Parent = container
	batch.folder = folder
	Debris:AddItem(folder, 45) -- red de seguridad: ninguna tanda dura tanto

	-- Sale un orbe por tirada, en abanico de cara al jugador.
	Sfx.play("tick", 0.6)
	local count = batch.count
	local slots, orbs = {}, {}
	for index = 1, count do
		local offset = index - (count + 1) / 2
		slots[index] = centre + right * (offset * SPACING) - Vector3.new(0, math.abs(offset) * 0.35, 0)
		orbs[index] = emerge(folder, heart, slots[index], lite)
		if index < count then
			task.wait(0.05 * SLOW)
		end
	end
	task.wait(EMERGE)

	-- Se destapan una detrás de otra; cada una vuela por su cuenta mientras se destapa la siguiente.
	local pending = count
	local function done()
		pending -= 1
	end
	for index = 1, count do
		local waited = 0
		while not batch.rolls[index] and waited < 2 do
			waited += task.wait()
		end
		local roll = batch.rolls[index]
		if roll and folder.Parent then
			present(folder, roll, orbs[index], slots[index], ground, lite, done)
			if index < count then
				task.wait(0.22 * SLOW)
			end
		else
			orbs[index]:Destroy()
			done()
		end
	end
	local waited = 0
	while pending > 0 and waited < 12 do
		waited += task.wait(0.1)
	end
	task.wait(0.9) -- las últimas chispas
	finish(batch)
end

local function onRolled(index: number, kept: boolean, luck: number, source: string, metal: number?, size: number?, extra)
	-- Con la tirada gratis encendida, sus tiradas las enseña el panel de siempre (client/GachaRoll).
	if Config.Gacha.FreeRoll and source == "gacha" then
		return
	end
	extra = if type(extra) == "table" then extra else {}
	local roll = {
		index = index,
		kept = kept,
		metal = metal,
		size = size,
		odds = if type(extra.odds) == "number" then extra.odds else Permanent.odds(index, metal, size, luck),
	}
	local id = extra.batch
	if id == nil then
		loose += 1
		id = "suelta" .. loose
	end
	local batch = batches[id]
	if not batch then
		batch = {
			id = id,
			count = math.max(1, extra.rolls or 1),
			origin = if typeof(extra.origin) == "Vector3" then extra.origin else nil,
			box = if typeof(extra.box) == "Vector3" then extra.box else nil,
			rolls = {},
		}
		batches[id] = batch
		running += 1
		batch.rolls[extra.roll or 1] = roll
		batch.skip = running > MAX_BATCHES
		task.spawn(function()
			local ok, problem = pcall(play, batch)
			if not ok then
				warn(`[RollReveal] {problem}`)
				if batches[id] then
					finish(batch)
				end
			end
		end)
	else
		batch.rolls[extra.roll or (#batch.rolls + 1)] = roll
	end
end

function RollReveal.start()
	container = Instance.new("Folder")
	container.Name = "RollReveals"
	container.Parent = workspace

	local camera = workspace.CurrentCamera
	local function fit()
		local view = camera.ViewportSize
		factor = math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), 0.6, 1)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()

	Remotes.GachaRolled.OnClientEvent:Connect(onRolled)
end

return RollReveal
