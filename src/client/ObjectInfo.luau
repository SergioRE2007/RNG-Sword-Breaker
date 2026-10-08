-- Lo que se ve de la rareza y el tamaño de los objetos de las parcelas. Todo lo decide el servidor
-- (server/Destructibles) y lo publica en los atributos de cada pieza con la etiqueta Destructible: Quality y Size
-- (posiciones en Config.ObjectRarities y ObjectSizes), Scale, Luck, Rolls, HP, MaxHP y Owner. Aquí solo se enseña:
--  · aura: los que no son comunes llevan una base de luz del color de su rareza y chispas y, según suben, luz,
--    contorno y un rayo hacia el cielo (QUALITY_FX). Se distinguen de lejos sin leer nada;
--  · etiqueta: los notables (desde Rara, o desde Enorme) llevan encima su rareza y la suerte que dan;
--  · cartel: el objeto que acabas de golpear, al que apuntas con el ratón o el que tienes delante enseña su ficha
--    entera: nombre, rareza, tamaño, suerte de armas, tiradas y vida.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local ObjectSpec = require(ReplicatedStorage.Shared.ObjectSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)

local ObjectInfo = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local TAG = "Destructible"
local FOCUS_TICK = 0.1 -- cada cuánto se decide qué objeto enseña el cartel
local NEAR_RANGE = 14 -- studs: el objeto de delante a esta distancia (de su borde) enseña el cartel
local HOVER_RANGE = 130 -- hasta dónde llega apuntar con el ratón
local HIT_HOLD = 1.5 -- segundos que el cartel se queda en el objeto que acabas de golpear
local CARD_HEIGHT = 9 -- studs sobre el suelo, como mucho, a los que flota el borde de abajo del cartel (encima de un objeto altísimo no se vería)
local TAG_HEIGHT = 15 -- lo mismo para la etiqueta
local TAG_QUALITY = 3 -- desde esta rareza (Rara) llevan etiqueta...
local TAG_SCALE = 1.5 -- ...y desde este tamaño (Enorme)
local BEAM_HEIGHT = 150

-- El cartel y la etiqueta miden lo mismo en píxeles a cualquier distancia (son BillboardGui): sus medidas van en
-- píxeles a propósito y un UIScale los encoge enteros en pantallas pequeñas, como el HUD (Ui.hud).
local CARD_SIZE = Vector2.new(296, 176)
local TAG_SIZE = Vector2.new(172, 40)
local SCREEN = Vector2.new(1100, 700)
local MIN_FACTOR = 0.6

-- Capas del cartel (la interfaz ordena el ZIndex globalmente).
local Z = { shadow = 1, card = 2, row = 3, text = 4, bar = 5, barText = 6 }

-- Aura por rareza (posición en Config.ObjectRarities; la 1, Común, no lleva): `pad` = transparencia de la base de
-- luz, `sparks` = chispas por segundo, `light` = brillo de la luz, `outline` = contorno, `beam` = grosor del rayo.
local QUALITY_FX = {
	[2] = { pad = 0.86, sparks = 3 },
	[3] = { pad = 0.8, sparks = 6, light = 0.5 },
	[4] = { pad = 0.74, sparks = 10, light = 0.8, outline = true },
	[5] = { pad = 0.68, sparks = 16, light = 1.1, outline = true, beam = 1.1 },
	[6] = { pad = 0.62, sparks = 26, light = 1.4, outline = true, beam = 1.8 },
}

local decorated: { [BasePart]: { tag: BillboardGui? } } = {}
local factor = 1 -- escala de la interfaz en esta pantalla

-- Aura ------------------------------------------------------------------------------------

local function glowPart(name: string, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	return part
end

local function aura(part: BasePart, color: Color3, fx)
	local size = part.Size
	local wide = math.max(size.X, size.Z)
	local ground = part.Position - Vector3.new(0, size.Y / 2, 0)
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- los cilindros salen tumbados

	-- Base de luz: un disco fino en el suelo, algo más ancho que el objeto.
	local pad = glowPart("RarityPad", color, fx.pad)
	pad.Size = Vector3.new(0.2, wide * 1.35 + 1.5, wide * 1.35 + 1.5)
	pad.CFrame = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * upright
	pad.Parent = part

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "RaritySparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
	sparks.LightEmission = 0.8
	sparks.Rate = fx.sparks
	sparks.Lifetime = NumberRange.new(1, 1.8)
	sparks.Speed = NumberRange.new(1.5, 4)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.45 + wide * 0.03),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparks.Parent = part

	if fx.light then
		local lamp = Instance.new("PointLight")
		lamp.Name = "RarityLight"
		lamp.Color = color
		lamp.Brightness = fx.light
		lamp.Range = 8 + wide * 0.8
		lamp.Parent = part
	end
	-- En modo rendimiento se quedan la base y poco más (las chispas y la luz las apaga Performance).
	if Performance.get() then
		return
	end
	if fx.outline then
		local outline = Instance.new("Highlight")
		outline.Name = "RarityOutline"
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.OutlineColor = color
		outline.FillColor = color
		outline.FillTransparency = 1 -- solo el contorno: el objeto conserva sus colores
		outline.Parent = part
	end
	if fx.beam then
		local beam = glowPart("RarityBeam", color:Lerp(WHITE, 0.3), 0.65)
		beam.Size = Vector3.new(BEAM_HEIGHT, fx.beam, fx.beam)
		beam.CFrame = CFrame.new(ground + Vector3.new(0, BEAM_HEIGHT / 2, 0)) * upright
		beam.Parent = part
		TweenService:Create(beam, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.88 }):Play()
	end
end

-- Etiqueta --------------------------------------------------------------------------------

-- Cuánto hay que subir desde el centro de la pieza para quedar a `gap` de su tope, sin pasar de `ceiling` studs
-- sobre el suelo (encima de un objeto enorme se saldría de la pantalla).
local function lift(part: BasePart, gap: number, ceiling: number): Vector3
	return Vector3.new(0, math.min(part.Size.Y / 2 + gap, ceiling - part.Size.Y / 2), 0)
end

-- Cartelito con la rareza (o el tamaño, si es común) y la suerte que da, encima de los objetos notables.
local function buildTag(part: BasePart, quality: number, class): BillboardGui
	local rarity = ObjectSpec.rarity(quality)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RarityTag"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(TAG_SIZE.X * factor, TAG_SIZE.Y * factor)
	gui.StudsOffsetWorldSpace = lift(part, 0.8, TAG_HEIGHT)
	gui.SizeOffset = Vector2.new(0, 0.5) -- se apoya en ese punto en vez de centrarse en él
	gui.AlwaysOnTop = true
	gui.MaxDistance = 260
	gui.LightInfluence = 0
	gui.Parent = part

	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.new(0.5, 0, 0.5, -2)
	chip.Size = UDim2.fromOffset(TAG_SIZE.X - 10, TAG_SIZE.Y - 14) -- margen para el borde y la sombra
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.ZIndex = Z.card
	chip.Parent = gui
	Ui.round(chip, 11)
	Ui.panel(chip, rarity.color:Lerp(Ui.COLORS.dark, 0.5))
	Ui.stroke(chip, BLACK, 3)
	Ui.shadow(chip, 3)
	local scale = Instance.new("UIScale")
	scale.Scale = factor
	scale.Parent = chip

	local name = if quality > 1 then rarity.name else class.name
	local text = Ui.label(chip, 17)
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = Z.text
	text.Text = `<font color="#{rarity.color:Lerp(WHITE, 0.35):ToHex()}">{string.upper(name)}</font>  x{Format.multiplier(part:GetAttribute("Luck") or 1)}`
	return gui
end

local function decorate(part: BasePart)
	if decorated[part] or not part.Parent then
		return
	end
	local quality = part:GetAttribute("Quality")
	if type(quality) ~= "number" then
		return -- aún no han llegado los atributos
	end
	local entry = {}
	decorated[part] = entry
	local class = ObjectSpec.size(part:GetAttribute("Size"))
	local fx = QUALITY_FX[quality]
	if fx then
		aura(part, ObjectSpec.rarity(quality).color, fx)
	end
	if quality >= TAG_QUALITY or class.min >= TAG_SCALE then
		entry.tag = buildTag(part, quality, class)
	end
end

-- Cartel ----------------------------------------------------------------------------------

local card: BillboardGui
local cardScale: UIScale
local refs = {}

local function row(parent: Instance, order: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundTransparency = 1
	frame.ZIndex = Z.row
	frame.Parent = parent
	return frame
end

-- Hueco oscuro con un dato dentro ("Suerte x18.4").
local function chip(parent: Instance, order: number, size: UDim2): TextLabel
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = size
	frame.BackgroundColor3 = Ui.COLORS.dark
	frame.BorderSizePixel = 0
	frame.ZIndex = Z.row
	frame.Parent = parent
	Ui.round(frame, 8)
	Ui.stroke(frame, BLACK, 2)
	local text = Ui.label(frame, 17)
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = Z.text
	return text
end

local function buildCard()
	card = Instance.new("BillboardGui")
	card.Name = "ObjectInfo"
	card.SizeOffset = Vector2.new(0, 0.5) -- se apoya en su punto en vez de centrarse en él
	card.AlwaysOnTop = true
	card.LightInfluence = 0
	card.ResetOnSpawn = false
	card.Enabled = false
	card.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Card"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, -2)
	root.Size = UDim2.fromOffset(CARD_SIZE.X - 12, CARD_SIZE.Y - 18) -- margen para el borde y la sombra
	root.BackgroundColor3 = WHITE
	root.BorderSizePixel = 0
	root.ZIndex = Z.card
	root.Parent = card
	Ui.round(root, 14)
	Ui.panel(root, Color3.fromRGB(46, 48, 70))
	Ui.stroke(root, BLACK, 4)
	Ui.shadow(root, 4)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = root

	-- El contenido va en un marco de dentro: las piezas de Ui.panel son hijas de la tarjeta y un layout las movería.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = Z.row
	content.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	-- Cabecera: banda del color de la rareza con el nombre del objeto y, a la derecha, su tamaño.
	local header = row(content, 1, 38)
	header.Name = "Header"
	header.BackgroundTransparency = 0
	header.BackgroundColor3 = WHITE
	Ui.round(header, 9)
	Ui.stroke(header, BLACK, 2)
	refs.headerGradient = Instance.new("UIGradient")
	refs.headerGradient.Rotation = 90
	refs.headerGradient.Parent = header
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(3, 2)
	gloss.Size = UDim2.new(1, -6, 0.42, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.ZIndex = Z.row
	gloss.Parent = header
	Ui.round(gloss, 7)

	refs.name = Ui.label(header, 24)
	refs.name.Name = "Name"
	refs.name.Position = UDim2.fromOffset(10, 0)
	refs.name.Size = UDim2.new(1, -118, 1, 0)
	refs.name.TextXAlignment = Enum.TextXAlignment.Left
	refs.name.TextTruncate = Enum.TextTruncate.AtEnd
	refs.name.ZIndex = Z.text

	local sizeChip = Instance.new("Frame")
	sizeChip.Name = "Size"
	sizeChip.AnchorPoint = Vector2.new(1, 0.5)
	sizeChip.Position = UDim2.new(1, -5, 0.5, 0)
	sizeChip.Size = UDim2.fromOffset(98, 26)
	sizeChip.BackgroundColor3 = BLACK
	sizeChip.BackgroundTransparency = 0.5
	sizeChip.BorderSizePixel = 0
	sizeChip.ZIndex = Z.row
	sizeChip.Parent = header
	Ui.round(sizeChip, 8)
	refs.sizeName = Ui.label(sizeChip, 15)
	refs.sizeName.Size = UDim2.fromScale(1, 1)
	refs.sizeName.ZIndex = Z.text

	-- Rareza a la izquierda y tamaño exacto a la derecha.
	local line = row(content, 2, 26)
	refs.rarity = Ui.label(line, 21)
	refs.rarity.Name = "Rarity"
	refs.rarity.Size = UDim2.fromScale(0.58, 1)
	refs.rarity.TextXAlignment = Enum.TextXAlignment.Left
	refs.rarity.ZIndex = Z.text
	refs.scale = Ui.label(line, 17)
	refs.scale.Name = "Scale"
	refs.scale.AnchorPoint = Vector2.new(1, 0)
	refs.scale.Position = UDim2.fromScale(1, 0)
	refs.scale.Size = UDim2.fromScale(0.42, 1)
	refs.scale.TextXAlignment = Enum.TextXAlignment.Right
	refs.scale.ZIndex = Z.text

	-- Lo que da al romperse: suerte de armas y tiradas.
	local stats = row(content, 3, 31)
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.Padding = UDim.new(0, 6)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = stats
	refs.luck = chip(stats, 1, UDim2.new(0.58, -3, 1, 0))
	refs.luck.Name = "Luck"
	-- Espada a la izquierda: es suerte de armas, no la de la parcela.
	local sword = Instance.new("Frame")
	sword.Name = "Sword"
	sword.AnchorPoint = Vector2.new(0, 0.5)
	sword.Position = UDim2.new(0, 3, 0.5, 1)
	sword.Size = UDim2.fromOffset(26, 26)
	sword.BackgroundTransparency = 1
	sword.Parent = refs.luck.Parent
	Ui.image(sword, "espada")
	Ui.layer(sword, Z.text)
	refs.luck.Position = UDim2.fromOffset(24, 0)
	refs.luck.Size = UDim2.new(1, -28, 1, 0)
	refs.rolls = chip(stats, 2, UDim2.new(0.42, -3, 1, 0))
	refs.rolls.Name = "Rolls"

	-- Vida.
	local health = row(content, 4, 26)
	health.Name = "Health"
	health.BackgroundTransparency = 0
	health.BackgroundColor3 = Ui.COLORS.dark
	Ui.round(health, 8)
	Ui.stroke(health, BLACK, 2)
	refs.hpFill = Instance.new("Frame")
	refs.hpFill.Name = "Fill"
	refs.hpFill.Size = UDim2.fromScale(1, 1)
	refs.hpFill.BackgroundColor3 = WHITE
	refs.hpFill.BorderSizePixel = 0
	refs.hpFill.ZIndex = Z.bar
	refs.hpFill.Parent = health
	Ui.round(refs.hpFill, 8)
	Ui.gradient(refs.hpFill, Color3.fromRGB(255, 120, 110), Color3.fromRGB(200, 45, 60), 90)
	refs.hpText = Ui.label(health, 16)
	refs.hpText.Size = UDim2.fromScale(1, 1)
	refs.hpText.ZIndex = Z.barText
end

local function hpGoal(part: BasePart): (UDim2, string)
	local hp = part:GetAttribute("HP") or 0
	local maxHp = part:GetAttribute("MaxHP") or 1
	return UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1), `{Format.short(math.ceil(hp))} / {Format.short(math.ceil(maxHp))}`
end

local function fill(part: BasePart)
	local quality = part:GetAttribute("Quality") or 1
	local rarity = ObjectSpec.rarity(quality)
	local class = ObjectSpec.size(part:GetAttribute("Size"))
	local rolls = part:GetAttribute("Rolls") or 1
	local color = rarity.color
	refs.name.Text = string.upper(part.Name)
	refs.headerGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.5))
	refs.sizeName.Text = string.upper(class.name)
	refs.rarity.Text = string.upper(rarity.name)
	refs.rarity.TextColor3 = color:Lerp(WHITE, 0.25)
	refs.scale.Text = `<font color="{Ui.SOFT}">Tamaño</font> {math.round((part:GetAttribute("Scale") or 1) * 100)} %`
	refs.luck.Text = `<font color="{Ui.SOFT}">Suerte</font> x{Format.multiplier(part:GetAttribute("Luck") or 1)}`
	refs.rolls.Text = `<font color="{Ui.SOFT}">Tiradas</font> <font color="#{(if rolls > 1 then Ui.COLORS.coins else WHITE):ToHex()}">{rolls}</font>`
	refs.hpFill.Size, refs.hpText.Text = hpGoal(part)
end

local focus: BasePart? = nil
local hpConnection: RBXScriptConnection? = nil

local function setFocus(part: BasePart?)
	if part == focus then
		return
	end
	if hpConnection then
		hpConnection:Disconnect()
		hpConnection = nil
	end
	-- La etiqueta del objeto se esconde mientras lleva el cartel entero.
	local before = focus and decorated[focus]
	if before and before.tag then
		before.tag.Enabled = true
	end
	focus = part
	if not part then
		card.Enabled = false
		card.Adornee = nil
		return
	end
	local now = decorated[part]
	if now and now.tag then
		now.tag.Enabled = false
	end
	fill(part)
	hpConnection = part:GetAttributeChangedSignal("HP"):Connect(function()
		local size, text = hpGoal(part)
		refs.hpText.Text = text
		TweenService:Create(refs.hpFill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size }):Play()
	end)
	card.Adornee = part
	card.StudsOffsetWorldSpace = lift(part, 1, CARD_HEIGHT)
	card.Enabled = true
	-- Entra con un pequeño rebote.
	if Performance.get() then
		cardScale.Scale = factor
	else
		cardScale.Scale = factor * 0.8
		TweenService:Create(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = factor }):Play()
	end
end

-- Elegir objeto --------------------------------------------------------------------------

local lastHit: BasePart? = nil
local lastHitAt = 0
local hoverParams = RaycastParams.new()
hoverParams.FilterType = Enum.RaycastFilterType.Include

-- Distancia del punto a la caja de la pieza (0 si está dentro) y hacia dónde queda.
local function reach(part: BasePart, from: Vector3): (number, Vector3)
	local half = part.Size / 2
	local point = part.CFrame:PointToObjectSpace(from)
	local closest = part.CFrame * Vector3.new(math.clamp(point.X, -half.X, half.X), math.clamp(point.Y, -half.Y, half.Y), math.clamp(point.Z, -half.Z, half.Z))
	local offset = closest - from
	return offset.Magnitude, offset
end

-- El objeto que enseña el cartel: el que acabas de golpear, si no el que señala el ratón, y si no el más cercano
-- de los tuyos que tengas delante.
local function pickFocus(): BasePart?
	if Ui.anyOpen() then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	if lastHit and lastHit.Parent and os.clock() - lastHitAt < HIT_HOLD then
		return lastHit
	end

	local camera = workspace.CurrentCamera
	local folder = workspace:FindFirstChild("Destructibles")
	if UserInputService.MouseEnabled and camera and folder then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		hoverParams.FilterDescendantsInstances = { folder }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, hoverParams)
		local target = hit and hit.Instance
		if target and target:IsA("BasePart") and CollectionService:HasTag(target, TAG) and (hit.Position - root.Position).Magnitude <= HOVER_RANGE then
			return target
		end
	end

	local best, bestScore = nil, math.huge
	local look = root.CFrame.LookVector
	for _, part in CollectionService:GetTagged(TAG) do
		if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId then
			local distance, offset = reach(part, root.Position)
			if distance <= NEAR_RANGE then
				-- A igual distancia gana el que tienes de frente.
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local facing = if flat.Magnitude > 0.5 then flat.Unit:Dot(look) else 1
				local score = distance + (1 - facing) * 4
				if score < bestScore then
					best, bestScore = part, score
				end
			end
		end
	end
	return best
end

function ObjectInfo.start()
	local camera = workspace.CurrentCamera
	local function fit()
		local view = camera.ViewportSize
		factor = math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), MIN_FACTOR, 1)
		if card then
			card.Size = UDim2.fromOffset(CARD_SIZE.X * factor, CARD_SIZE.Y * factor)
			cardScale.Scale = factor
		end
	end
	fit()
	buildCard()
	fit()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local function watch(part: Instance)
		if part:IsA("BasePart") then
			-- La pieza llega antes que sus atributos: si aún no están, se vuelve a mirar al momento.
			task.defer(decorate, part)
			task.delay(0.3, decorate, part)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	for _, part in CollectionService:GetTagged(TAG) do
		watch(part)
	end
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		decorated[part :: BasePart] = nil
	end)

	Remotes.Hit.OnClientEvent:Connect(function(hitter: Player, part: BasePart?)
		if hitter == player and part and CollectionService:HasTag(part, TAG) then
			lastHit = part
			lastHitAt = os.clock()
		end
	end)

	local waited = 0
	RunService.Heartbeat:Connect(function(delta)
		waited += delta
		if waited < FOCUS_TICK and not (focus and not focus.Parent) then
			return
		end
		waited = 0
		setFocus(pickFocus())
	end)
end

return ObjectInfo
