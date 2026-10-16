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
local RollCinematic = require(script.Parent.RollCinematic)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponAuraDefs = require(script.Parent.WeaponAuraDefs)
local WeaponFeed = require(script.Parent.WeaponFeed)
local Lang = require(ReplicatedStorage.Shared.Lang)

local RollReveal = {}

local player = Players.LocalPlayer
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 220, 100)

local MYSTERY = Color3.fromRGB(150, 105, 255) -- color de la energía mientras no se sabe qué ha tocado (oscuro: el neón claro se quema en blanco)
local DUST = Color3.fromRGB(205, 195, 175) -- polvo que levanta del suelo una tirada buena
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX = WeaponAuraDefs.textures -- sellos, estallido y polvo de estrellas del pack de efectos
local FX = RollCinematic.fx -- columna de luz, brasas, llamaradas y anillo de polvo: los mismos de las cinemáticas
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

-- Niveles de espectáculo: 1 Normal, 2 Genial y, con cinemática (client/RollCinematic), 3 Estrella fugaz, 4 Herrero
-- celestial, 5 Supernova y 6 Supernova absoluta.
-- charge = segundos que el orbe se carga antes de destaparse, pulses = latidos en ese rato, rise = studs que sube
-- mientras tanto, hover = segundos que el arma se queda a la vista, fly = segundos de vuelo, turns = vueltas de
-- espiral en el vuelo, sparks = chispas al destaparse, aura = chispas por segundo alrededor del arma, shock = ondas
-- en el suelo, light = brillo de la luz, beam = grosor del rayo hacia el cielo, absorb = el orbe traga
-- energía de alrededor, rays = rayos que giran, flash = destello de pantalla, seal = tamaño del sello mágico del
-- suelo, nova = tamaño del estallido de puntas, pop = studs desde los que el arma sube de un bote al salir (popTime =
-- lo que tarda), grow = tamaño del cartel, sounds = lo que suena al destaparse, cinematic = tema de su cinemática.
-- Desde el nivel 2, además: columna de luz y llamaradas (beam), anillo de polvo (shock) y brasas que suben del
-- sello, con las ayudas de RollCinematic.fx. Los rayos de detrás del arma (`shine`) no: de día y en el mundo se ven
-- como tres franjas sueltas. Por debajo del nivel 3 nada toca la cámara (pedido por el usuario: el temblor
-- y el tirón del zoom molestaban al romper objetos); del 3 para arriba la coge la cinemática, también pedido por
-- él, y lo demás de su fila es lo que se ve en el mundo cuando la cinemática no puede salir (modo Rendimiento,
-- ajuste apagado, una ventana abierta...).
local LEVELS = {
	{ charge = 0.2, pulses = 1, rise = 0, hover = 0.42, fly = 0.38, turns = 0, sparks = 14, nova = 3.2, pop = 0.5, grow = 1, sounds = { "reveal_1" } },
	{ charge = 0.95, pulses = 4, rise = 1.4, hover = 1.7, fly = 0.6, turns = 0.75, sparks = 44, aura = 20, shock = 2, light = 1.1, beam = 1.6, absorb = true, seal = 9, nova = 8, pop = 1.6, popTime = 0.4, grow = 1.35, sounds = { "reveal_3" } },
	{ charge = 1.25, pulses = 5, rise = 1.8, hover = 2.1, fly = 0.7, turns = 1, sparks = 60, aura = 26, shock = 3, light = 1.3, beam = 2, absorb = true, flash = true, seal = 11, nova = 10, pop = 1.6, popTime = 0.4, grow = 1.5, sounds = { "reveal_4" }, cinematic = "star" },
	{ charge = 1.7, pulses = 6, rise = 2.2, hover = 2.5, fly = 0.8, turns = 1.25, sparks = 80, aura = 32, shock = 3, light = 1.5, beam = 2.4, absorb = true, rays = true, flash = true, seal = 13, nova = 12, pop = 1.6, popTime = 0.4, grow = 1.6, sounds = { "reveal_5" }, cinematic = "smith" },
	{ charge = 2.1, pulses = 8, rise = 2.6, hover = 2.9, fly = 0.85, turns = 1.5, sparks = 100, aura = 38, shock = 4, light = 1.6, beam = 2.8, absorb = true, rays = true, flash = true, seal = 15, nova = 14, pop = 1.6, popTime = 0.4, grow = 1.7, sounds = { "reveal_5" }, cinematic = "nova" },
	{ charge = 2.4, pulses = 9, rise = 3, hover = 3.4, fly = 0.9, turns = 2, sparks = 130, aura = 46, shock = 5, light = 1.8, beam = 3.4, absorb = true, rays = true, flash = true, seal = 17, nova = 16, pop = 1.6, popTime = 0.4, grow = 1.8, sounds = { "reveal_5", "win" }, cinematic = "nova" },
}
-- Con cinemática, lo del mundo va corto: el orbe se carga un momento y, a la vuelta, el arma se queda poco y vuela.
local AFTER = { charge = 0.4, pulses = 2, hover = 0.55 }
-- Frase encima del cartel (y arriba en la cinemática) desde el nivel 2.
local LINES = { [2] = "Great roll!", [3] = "A star falls for you!", [4] = "Forged by the heavens!", [5] = "A star dies for this weapon!", [6] = "The universe bows to you!" }

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
local function outBack(t: number, overshoot: number?): number
	local c = overshoot or 1.70158
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

-- Sello mágico tumbado en el suelo, girando, durante `seconds`. Flojo y medio transparente a propósito: con más
-- brillo, a mediodía es una mancha blanca.
local function seal(parent: Instance, position: Vector3, texture: string, color: Color3, size: number, seconds: number, turn: number)
	local base = glow(Enum.PartType.Block, Vector3.one, CFrame.new(position), color, 1, parent)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.4
	emitter.Brightness = 1.1
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(seconds)
	emitter.Speed = NumberRange.new(0.01)
	emitter.SpreadAngle = Vector2.zero
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	emitter.Rotation = NumberRange.new(0)
	emitter.RotSpeed = NumberRange.new(turn)
	emitter.LockedToPart = true
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, size), NumberSequenceKeypoint.new(0.9, size), NumberSequenceKeypoint.new(1, size * 0.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.45), NumberSequenceKeypoint.new(0.85, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = base
	emitter:Emit(1)
end

-- Estallido de puntas que se abre girando, de cara a la cámara (la textura trae el fondo negro: emisión 1).
local function nova(parent: Instance, color: Color3, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEX.nova
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6)
	emitter.Speed = NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240)
	emitter.LockedToPart = true
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.15), NumberSequenceKeypoint.new(1, size) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = parent
	emitter:Emit(1)
	Debris:AddItem(emitter, 1)
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

-- Modelo del arma de verdad, anclado y con el giro en su centro, y cuánto hay que escalarlo para que mida DISPLAY.
local function buildSword(index: number, metal: number?, parent: Instance): (Model, number)
	return RollCinematic.sword(index, metal, parent, DISPLAY)
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

-- Cartel sobre el arma: primero salta la rareza y enseguida el nombre y lo difícil que era. Con `count`, el
-- "1 entre N" sube contando hasta su número en esos segundos (pedido por el usuario). Devuelve cómo quitarlo.
local function buildLabel(folder: Instance, anchor: BasePart, roll, level: number, tier, odds: number, count: number?): () -> ()
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
		table.insert(texts, textLine(root, 1, 17, 20, Lang.t(nil, LINES[level]), GOLD))
	end

	-- Rareza: una chapa con el color de la rareza, que es lo primero que se lee.
	local rarityText = Ui.upper(Lang.t(nil, tier.name))
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
	local function detail(chance: string, tone: string): string
		local text = `<font color="{tone}">{chance}</font>`
		if not roll.kept then
			text ..= `  ·  <font color="#{Ui.COLORS.orange:ToHex()}">{Lang.t(nil, "sold")}</font>`
		end
		return text
	end
	local final = Permanent.describeOdds(roll.index, roll.metal, roll.size)
	local big = level >= 2
	local oddsLine = textLine(root, 4, if big then 20 else 15, if big then 24 else 18, detail(if count then Lang.t(nil, "1 in {n}", { n = "1" }) else final, Ui.SOFT), WHITE)
	table.insert(texts, oddsLine)
	if count then
		task.delay(0.3, function()
			local size = oddsLine.TextSize
			RollCinematic.countUp(Permanent.rarity(roll.index, roll.metal, roll.size), count, function(text, arrived)
				if not oddsLine.Parent then
					return
				end
				if arrived then
					-- Llegó: el número da un golpe y se queda del color de la rareza.
					oddsLine.Text = detail(final, "#" .. color:Lerp(WHITE, 0.45):ToHex())
					oddsLine.TextSize = math.round(size * 1.4)
					tween(oddsLine, 0.3, { TextSize = size }, Enum.EasingStyle.Back)
					Sfx.play("rare", 0.7)
				else
					oddsLine.Text = detail(Lang.t(nil, "1 in {n}", { n = text }), Ui.SOFT)
				end
			end)
		end)
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
	WeaponFeed.push(roll) -- y su tarjeta a la derecha de la pantalla, para saber qué ha tocado
	local root = rootPart()
	Sfx.play("collect", if level >= 2 then 0.8 else 0.45, nil, root)
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
		if level >= 3 then
			nova(point, color:Lerp(WHITE, 0.35), 5 + level)
		end
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
	-- ¿Le toca cinemática? Se pide turno ya, para cargar el orbe solo un momento.
	-- Ajustes puede dejar solo las de "1 entre N" para arriba (atributo local CinematicFrom; las demás, en el mundo).
	local from = player:GetAttribute("CinematicFrom")
	local wanted = typeof(from) ~= "number" or (odds or 0) >= from
	local cinematic = fx.cinematic ~= nil and not lite and wanted and RollCinematic.reserve()
	local pulses = if cinematic then AFTER.pulses else fx.pulses

	-- 1. Carga: el orbe late, sube y, si la tirada es buena, traga energía y acaba tomando el color de la rareza.
	local charge = (if cinematic then AFTER.charge else fx.charge) * pace
	local top = slot + Vector3.new(0, fx.rise, 0)
	tween(orb, charge, { Position = top }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if level >= 2 then
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
	local floor = Vector3.new(slot.X, ground + 0.2, slot.Z)
	local sealed = fx.seal ~= nil and not lite and not cinematic
	if sealed then
		-- Sello mágico en el suelo, debajo, mientras se carga y se enseña, con brasas que suben de él.
		local seconds = charge + (fx.hover + 0.4) * SLOW
		seal(folder, floor, TEX.seal, color, fx.seal, seconds, 35)
		seal(folder, floor + Vector3.new(0, 0.05, 0), TEX.seal2, color, fx.seal * 0.6, seconds, -50)
		local hearth = glow(Enum.PartType.Block, Vector3.new(fx.seal * 0.55, 0.2, fx.seal * 0.55), CFrame.new(floor), color, 1, folder)
		FX.embers(hearth, color, 16, seconds / SLOW)
	end
	local beat = charge / pulses
	local clock = 0
	for pulse = 1, pulses do
		if not orb.Parent then
			break
		end
		local big = ORB * (1.25 + pulse * 0.05)
		TweenService:Create(orb, TweenInfo.new(beat / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Size = Vector3.one * big }):Play()
		if not lite then
			ring(folder, orb.Position, ORB, ORB * (2.4 + level * 0.5), if pulse > pulses - 2 and level >= 2 then bright else MYSTERY, beat * 0.9)
		end
		if sealed then
			-- Con cada latido el sello suelta una onda, cada vez más grande.
			seal(folder, floor + Vector3.new(0, 0.1, 0), TEX.wave, bright, fx.seal * (0.9 + pulse * 0.12), beat * 1.2, 0)
		end
		if level >= 2 then
			Sfx.play("charge", 0.6, 2 ^ ((pulse - 1) / 12), orb.Position) -- cada pulso suena una nota más arriba
		end
		animate(beat, function()
			clock += 1 / 60
			if fx.absorb and not lite and rng:NextNumber() < 0.45 then
				local from = orb.Position + randomUnit() * rng:NextNumber(8, 14)
				local streak = glow(Enum.PartType.Ball, Vector3.one * 0.55, CFrame.new(from), if pulse > pulses - 2 then bright else MYSTERY, 0.25, folder)
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

	-- 2. Se destapa: el orbe estalla en el color de la rareza y sale el arma. Con cinemática, antes se ve entera
	-- (espera a que acabe o la salten) y aquí el arma ya solo aparece un momento y vuela al jugador.
	local position = if orb.Parent then orb.Position else top
	if cinematic then
		orb.Transparency = 1
		cinematic = RollCinematic.play(fx.cinematic, { roll = roll, tier = tier, level = level, line = LINES[level], origin = position, ground = ground })
		if not folder.Parent then
			-- La tanda se ha borrado mientras tanto: el arma, directa a la recogida.
			if roll.kept then
				collect(roll, level, color)
			end
			done()
			return
		end
	end
	local quiet = lite or cinematic -- sin estallido: en modo Rendimiento, o porque ya lo ha puesto la cinemática
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

	if not cinematic then
		for delay, name in fx.sounds do
			task.delay((delay - 1) * 0.12, Sfx.play, name, if level == 1 then 0.6 else 1, nil, position) -- las normales suenan flojo: salen a todas horas
		end
	end
	local lamp: PointLight? = nil
	if not quiet then
		fading(Enum.PartType.Ball, CFrame.new(position), Vector3.one * ORB, Vector3.one * (ORB * 2 + level * 0.8), color, 0.45, 0.28, folder)
		ring(folder, position, ORB, 3.5 + level * 2.5, bright, 0.4)
		sparks(follow, color, fx.sparks, 12 + level * 4, 0.5 + level * 0.12)
		if fx.nova then
			nova(follow, bright, fx.nova)
		end
		for wave = 1, fx.shock or 0 do
			task.delay((wave - 1) * 0.13, function()
				if folder.Parent then
					ring(folder, Vector3.new(position.X, ground + 0.2, position.Z), 3, 14 + level * 7, bright, 0.5 + level * 0.05)
				end
			end)
		end
		local scene = { folder = folder }
		if fx.beam then
			FX.pillar(scene, floor, 30 + level * 5, fx.beam * 2.6, color, 0.9 + level * 0.1)
			FX.flames(follow, color, 4 + level, 9, 2.6)
		end
		if fx.shock then
			FX.dustRing(scene, floor, DUST:Lerp(color, 0.25), 10, 15)
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
	local hideLabel = buildLabel(folder, follow, roll, level, tier, odds, if cinematic then nil else RollCinematic.countTime(level))
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
		-- Aparece de golpe, pasándose un poco de tamaño, y el giro se calma. Sale de un poco más abajo y sube de un
		-- bote (más alto y con más rebote en las buenas).
		local pop = if quiet then 0 else fx.pop or 0
		local fast = if pop > 1 then 15 else 9
		animate((if pop > 1 then fx.popTime else 0.16) * SLOW, function(t)
			local bounce = outBack(t, if pop > 1 then 3.2 else nil)
			state.scale = math.max(bounce, 0.02)
			state.position = position - Vector3.new(0, pop * (1 - bounce), 0)
			state.spin = fast - (fast - 2.5) * t
		end)
		state.position = position
		-- 3. Se queda a la vista lo justo para leerla (más cuanto mejor es; las vendidas, menos).
		task.wait((if cinematic then AFTER.hover else fx.hover) * pace * (if roll.kept then 1 else 0.6))
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
	if level >= 2 then
		Ui.toast(Lang.t(nil, "{name}!", { name = Permanent.name(roll.index, roll.metal, roll.size) }), tier.color)
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
	Debris:AddItem(folder, 90) -- red de seguridad: ninguna tanda dura tanto, ni esperando turno de cinemática

	-- Sale un orbe por tirada, en abanico de cara al jugador.
	Sfx.play("orb", 0.6, nil, heart)
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
	while pending > 0 and waited < 40 do -- una cinemática en cola puede tardar
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
