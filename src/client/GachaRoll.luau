-- Gacha en el cliente. Es gratis y se tira desde cualquier sitio (botones "Tirar" y "Auto").
-- Arriba, el panel del gacha: pasan espadas al azar, cada vez más despacio, y se para en la que
-- ha tocado con un aura según lo rara que era para su suerte (brillo, rayos, chispas, arcoíris).
-- Si la tirada es muy buena para la suerte de gacha del jugador (Config.Gacha.ShowcaseOdds), el
-- panel vuela al centro, se convierte en un orbe que se carga y la espada se destapa a pantalla
-- completa, con más efectos cuanto más rara. Lo raro para su suerte suelta además un aura en el
-- personaje que ven todos. Pulsar la pantalla durante la animación grande la salta.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)
local WeaponPreview = require(script.Parent.WeaponPreview)

local GachaRoll = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local ORB_COLOR = Color3.fromRGB(190, 110, 255)
local PANEL_SIZE = Vector2.new(430, 104)
local CARD_SIZE = Vector2.new(220, 290)

-- Efectos de cada nivel de Config.RarityTiers (misma posición): brillo alrededor del panel
-- (transparencia, nil = nada), rayos que giran, chispas por segundo, temblor y arcoíris.
local TIER_FX = {
	{}, -- Común
	{ glow = 0.7 }, -- Poco común
	{ glow = 0.55, sparkles = 2 }, -- Rara
	{ glow = 0.45, rays = 4, sparkles = 4 }, -- Épica
	{ glow = 0.35, rays = 6, sparkles = 6, shake = 2 }, -- Legendaria
	{ glow = 0.25, rays = 8, sparkles = 9, shake = 4 }, -- Mítica
	{ glow = 0.2, rays = 10, sparkles = 12, shake = 5, rainbow = true }, -- Secreta
	{ glow = 0.1, rays = 12, sparkles = 16, shake = 7, rainbow = true }, -- Divina
}

local overlay: ScreenGui
local stage: Frame -- lo de la animación grande; se mueve entero para temblar
local dim: TextButton
local footer: Frame
local summary: TextLabel
local skip = false
local auto = false
local rolling = false -- esperando a que acabe la tirada (cuenta el tiempo por tirada)
local rollStarted = 0
local spinning = false -- el panel está pasando espadas
local showcasing = false -- animación grande en pantalla

-- Utilidades ----------------------------------------------------------------------------

local function wait(seconds: number)
	if not skip and seconds > 0 then
		task.wait(seconds)
	end
end

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween?
	if skip then
		for key, value in props do
			(instance :: any)[key] = value
		end
		return nil
	end
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local created = TweenService:Create(instance, info, props)
	created:Play()
	return created
end

local function frame(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local item = Instance.new("Frame")
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function circle(item: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = item
end

-- Llama a `step(delta)` cada fotograma mientras `owner` siga en pantalla.
local function everyFrame(owner: Instance, step: (number) -> ())
	local connection
	connection = RunService.RenderStepped:Connect(function(delta)
		if not owner.Parent then
			connection:Disconnect()
			return
		end
		step(delta)
	end)
end

local function tierIndex(rarity: number?): number
	return table.find(Config.RarityTiers, Rarity.tier(rarity)) or 1
end

-- Degradado arcoíris que gira (para Secreta y Divina).
local function rainbow(parent: GuiObject)
	local gradient = Instance.new("UIGradient")
	local keys = {}
	for step = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(step / 6, Color3.fromHSV(step / 6, 0.55, 1)))
	end
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = parent
	everyFrame(gradient, function(delta)
		gradient.Rotation = (gradient.Rotation + delta * 90) % 360
	end)
end

-- Hace temblar `target` alrededor de su posición durante `seconds`.
local function shake(target: GuiObject, strength: number, seconds: number)
	if skip or strength <= 0 then
		return
	end
	local base = target.Position
	local finish = os.clock() + seconds
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if skip or os.clock() >= finish or not target.Parent then
			connection:Disconnect()
			target.Position = base
			return
		end
		target.Position = base + UDim2.fromOffset(math.random(-strength, strength), math.random(-strength, strength))
	end)
end

-- Rayos que giran alrededor de `position`, del color dado. Se borran con el contenedor.
local function rays(parent: Instance, position: UDim2, length: number, width: number, color: Color3, count: number, zIndex: number): Frame
	local holder = frame(parent, UDim2.fromOffset(0, 0), position, color)
	holder.BackgroundTransparency = 1
	holder.ZIndex = zIndex
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	local pieces = {}
	for index = 1, count do
		local ray = frame(holder, UDim2.fromOffset(length * 2, width), UDim2.fromScale(0.5, 0.5), color)
		ray.Rotation = index * 180 / count
		ray.ZIndex = zIndex
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = fade
		gradient.Parent = ray
		table.insert(pieces, ray)
	end
	everyFrame(holder, function(delta)
		for _, ray in pieces do
			ray.Rotation += delta * 40
		end
	end)
	return holder
end

-- Anillo que sale de `position` y se desvanece.
local function ring(parent: Instance, position: UDim2, from: number, to: number, color: Color3, seconds: number)
	if skip then
		return
	end
	local item = frame(parent, UDim2.fromOffset(from, from), position, color)
	item.BackgroundTransparency = 1
	item.ZIndex = 3
	circle(item)
	local stroke = Ui.stroke(item, color, 6)
	tween(item, seconds, { Size = UDim2.fromOffset(to, to) })
	tween(stroke, seconds, { Transparency = 1, Thickness = 1 })
	task.delay(seconds, function()
		item:Destroy()
	end)
end

-- Destello de pantalla completa.
local function flash(color: Color3, from: number, seconds: number)
	if skip then
		return
	end
	local item = frame(overlay, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), color)
	item.BackgroundTransparency = from
	item.ZIndex = 40
	tween(item, seconds, { BackgroundTransparency = 1 })
	task.delay(seconds, function()
		item:Destroy()
	end)
end

-- Chispa (rombo blanco con borde del color) que aparece y se apaga en un punto al azar de `area`.
local function sparkle(area: GuiObject, color: Color3, size: number, zIndex: number)
	local item = frame(area, UDim2.fromOffset(0, 0), UDim2.fromScale(math.random(), math.random()), WHITE)
	item.Rotation = 45
	item.ZIndex = zIndex
	Ui.stroke(item, color, 2)
	local grow = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(item, grow, { Size = UDim2.fromOffset(size, size) }):Play()
	task.delay(0.5, function()
		item:Destroy()
	end)
end

-- Aura en el personaje (la ven todos) ---------------------------------------------------

local function effectPart(color: Color3, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 0.3
	part.Parent = workspace
	return part
end

local auras = {} -- [player] = función que borra su aura actual

-- Aura en el personaje de quien ha sacado algo raro para su suerte. El nivel (color y cuántos
-- efectos) sale de la probabilidad real, no de la rareza de la espada. Cada aura nueva borra la
-- anterior de ese jugador, para que no se amontonen con la tirada automática.
local function characterAura(who: Player?, _index: number, odds: number)
	-- Si se fue justo antes, llega sin jugador.
	if not who then
		return
	end
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if auras[who] then
		auras[who]()
	end
	local tier = tierIndex(odds)
	local color = Rarity.tier(odds).color
	local pieces: { Instance } = {}
	local function clear()
		for _, piece in pieces do
			piece:Destroy()
		end
		table.clear(pieces)
		if auras[who] == clear then
			auras[who] = nil
		end
	end
	auras[who] = clear

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(2, 3 + tier)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Drag = 2
	emitter.Rate = tier * 5
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = root
	emitter:Emit(tier * 10)
	table.insert(pieces, emitter)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0.6 + tier * 0.3
	light.Range = 6 + tier * 1.5
	light.Parent = root
	table.insert(pieces, light)

	-- Desde Épica, anillos que salen de los pies.
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	local flat = CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90))
	if tier >= 4 then
		for wave = 0, math.min(tier - 4, 2) do
			task.delay(wave * 0.25, function()
				if auras[who] ~= clear then
					return
				end
				local item = effectPart(color, Vector3.new(0.2, 2, 2), flat)
				table.insert(pieces, item)
				local wide = 10 + tier * 2
				TweenService:Create(item, TweenInfo.new(0.9), { Size = Vector3.new(0.2, wide, wide), Transparency = 1 }):Play()
			end)
		end
	end
	-- Desde Mítica, una columna de luz.
	if tier >= 6 then
		local upright = CFrame.new(feet + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local pillar = effectPart(color, Vector3.new(80, 3, 3), upright)
		pillar.Transparency = 0.5
		table.insert(pieces, pillar)
		TweenService:Create(pillar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(80, 0.5, 0.5), Transparency = 1 }):Play()
	end

	-- Se apaga sola: menos de lo que dura una tirada en las normales, más en las muy raras.
	local stay = 1 + tier * 0.25
	task.delay(stay, function()
		if auras[who] == clear then
			emitter.Enabled = false
			TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		end
	end)
	task.delay(stay + 1.2, function()
		if auras[who] == clear then
			clear()
		end
	end)
end

-- Máquina del hub: el orbe se hincha, brilla y suelta chispas (solo lo ve quien tira) -------

local sparks: ParticleEmitter?
local orbRest -- tamaño, color y luz del orbe en reposo, para volver siempre a ellos

local function machineEffect(color: Color3)
	local map = workspace:FindFirstChild("Map")
	local machine = map and map:FindFirstChild("Gacha")
	local orb = machine and machine:FindFirstChild("Orb") :: BasePart?
	if not orb then
		return
	end
	if not sparks then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(14, 26)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 3
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
		emitter.Parent = orb
		sparks = emitter
	end
	local emitter = sparks :: ParticleEmitter
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter:Emit(30)
	local light = orb:FindFirstChildOfClass("PointLight")
	-- Se parte siempre del reposo para que dos tiradas seguidas no lo dejen hinchado.
	if not orbRest then
		orbRest = { size = orb.Size, color = orb.Color, brightness = light and light.Brightness, range = light and light.Range }
	end
	orb.Size = orbRest.size
	orb.Color = orbRest.color
	if light then
		light.Brightness = orbRest.brightness
		light.Range = orbRest.range
	end
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(orb, info, { Size = orbRest.size * 1.4, Color = color }):Play()
	if light then
		TweenService:Create(light, info, { Brightness = 6, Range = 40 }):Play()
	end
end

-- Panel del gacha (arriba) --------------------------------------------------------------

local panel: Frame -- contenedor (no tiembla)
local box: Frame -- el cuadro en sí
local glow: Frame
local glowStroke: UIStroke
local iconSlot: Frame
local title: TextLabel
local detail: TextLabel
local progress: Frame
local panelScale: UIScale
local sparkleArea: Frame
local auraId = 0

-- El arma del panel en 3D, girando despacio (la misma vista que las casillas de la mochila).
local iconView
local function setIcon(index: number)
	if not iconView then
		iconView = WeaponPreview.view(iconSlot, true, 4)
	end
	iconView.set(index)
end

local function clearAura()
	auraId += 1
	sparkleArea:ClearAllChildren()
	local oldRays = panel:FindFirstChild("AuraRays")
	if oldRays then
		oldRays:Destroy()
	end
	local oldRainbow = glow:FindFirstChildOfClass("UIGradient")
	if oldRainbow then
		oldRainbow:Destroy()
	end
	glow.BackgroundTransparency = 1
	glowStroke.Transparency = 1
end

-- Aura del panel según el nivel de rareza de lo que ha salido. Dura hasta la siguiente tirada.
local function panelAura(tier: number, color: Color3)
	clearAura()
	local fx = TIER_FX[tier] or {}
	local id = auraId
	if fx.glow then
		glow.BackgroundColor3 = color
		glowStroke.Color = color
		glowStroke.Transparency = 0.2
		TweenService:Create(glow, TweenInfo.new(0.3), { BackgroundTransparency = fx.glow }):Play()
		if fx.rainbow then
			rainbow(glow)
		end
	end
	if fx.rays then
		local holder = rays(panel, UDim2.fromScale(0.5, 0.5), PANEL_SIZE.X * 0.75, 18, color, fx.rays, 0)
		holder.Name = "AuraRays"
		for _, ray in holder:GetChildren() do
			(ray :: GuiObject).BackgroundTransparency = 0.35
		end
	end
	if fx.shake then
		shake(box, fx.shake, 0.4)
	end
	if fx.sparkles then
		task.spawn(function()
			while auraId == id do
				sparkle(sparkleArea, color, math.random(8, 14), 6)
				task.wait(1 / fx.sparkles)
			end
		end)
	end
end

-- Espada que se ve pasar mientras gira: casi siempre comunes, a veces alguna rara para picar.
-- Config.Swords no va ordenada por rareza, así que se elige sobre la lista ordenada.
local byRarity = {}
for index, sword in Config.Swords do
	if sword.rarity then
		table.insert(byRarity, index)
	end
end
table.sort(byRarity, function(a, b)
	return Config.Swords[a].rarity < Config.Swords[b].rarity
end)

local function teaseIndex(): number
	return byRarity[math.min(1 + math.floor(math.random() ^ 3 * #byRarity), #byRarity)]
end

local panelShown = false -- el panel de arriba solo se ve mientras se tira (y un par de segundos después)
local resultId = 0 -- cuenta las tiradas, para que el cartel solo se apague si no hay una nueva
local RESULT_STAY = 2 -- segundos que el panel enseña el resultado antes de esconderse

local function showSword(index: number)
	local sword = Config.Swords[index]
	title.Text = sword.name
	title.TextColor3 = sword.color:Lerp(WHITE, 0.35)
	setIcon(index)
	iconSlot.BackgroundColor3 = Rarity.tier(sword.rarity).color:Lerp(Ui.COLORS.cell, 0.6)
end

-- Animación grande ----------------------------------------------------------------------

local function clearStage()
	for _, child in stage:GetChildren() do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
end

local function makeCard(parent: Instance, index: number, kept: boolean, odds: number)
	local sword = Config.Swords[index]
	local tier = Rarity.tier(sword.rarity)

	local card = frame(parent, UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.45), WHITE)
	card.BackgroundTransparency = 1
	card.ZIndex = 5

	local back = frame(card, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), ORB_COLOR)
	back.ZIndex = 5
	Ui.round(back, 16)
	Ui.gradient(back, WHITE, Color3.fromRGB(90, 70, 140), 90)
	local backStroke = Ui.stroke(back, BLACK, 4)
	local mark = Ui.label(back, 110)
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "?"
	mark.ZIndex = 6

	local front = frame(card, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE)
	front.Visible = false
	front.ClipsDescendants = true
	front.ZIndex = 5
	Ui.round(front, 16)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(tier.color:Lerp(WHITE, 0.15), Ui.COLORS.dark)
	gradient.Parent = front
	Ui.stroke(front, tier.color:Lerp(WHITE, 0.3), 5)

	local iconBox = frame(front, UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.5, 0.32), WHITE)
	iconBox.BackgroundTransparency = 1
	iconBox.ZIndex = 6
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = iconBox
	WeaponPreview.view(iconBox, true, 7).set(index)

	local name = Ui.label(front, 26)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.6)
	name.Size = UDim2.new(1, -10, 0.18, 0)
	name.TextWrapped = true
	name.Text = sword.name
	name.TextColor3 = sword.color:Lerp(WHITE, 0.35)
	name.ZIndex = 8

	local info = Ui.label(front, 18)
	info.AnchorPoint = Vector2.new(0.5, 1)
	info.Position = UDim2.new(0.5, 0, 1, -8)
	info.Size = UDim2.new(1, -8, 0.2, 0)
	info.TextWrapped = true
	info.Text = `<font color="#{tier.color:ToHex()}">{tier.name}</font>\n1 entre {Format.short(math.max(odds, 1))}`
	info.ZIndex = 8

	if not kept then
		local sold = frame(front, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BLACK)
		sold.BackgroundTransparency = 0.45
		sold.ZIndex = 9
		local tag = Ui.label(sold, 22)
		tag.Size = UDim2.new(1, 0, 0, 30)
		tag.Position = UDim2.fromScale(0.5, 0.32)
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Rotation = -12
		tag.Text = `Vendida\n+{Config.Gacha.SellValue} gemas`
		tag.TextColor3 = Ui.COLORS.orange
		tag.ZIndex = 10
	end

	local shine = frame(front, UDim2.new(0, 40, 1.6, 0), UDim2.fromScale(-0.3, 0.5), WHITE)
	shine.Rotation = 20
	shine.BackgroundTransparency = 0.45
	shine.ZIndex = 11

	return { card = card, back = back, backStroke = backStroke, front = front, shine = shine }
end

-- El panel de arriba vuela al centro de la pantalla, se convierte en el orbe, se carga con el
-- color de la rareza, estalla y destapa la carta. Acaba cuando el jugador pulsa "Continuar"
-- (o sola en automático).
local function showcase(index: number, kept: boolean, odds: number)
	local sword = Config.Swords[index]
	local tierInfo = Rarity.tier(sword.rarity)
	-- La carta y el cartel son de la rareza de la espada; cuántos efectos, de la probabilidad real.
	local tier = tierIndex(odds)
	local fx = TIER_FX[tier] or {}
	local color = tierInfo.color

	showcasing = true
	skip = false
	clearStage()
	footer.Visible = false
	overlay.Enabled = true
	dim.BackgroundTransparency = 1
	tween(dim, 0.4, { BackgroundTransparency = 0.12 })
	machineEffect(color)

	-- 1. El panel pasa a primer plano: una copia vuela de arriba al centro y se hace orbe.
	local scale = stage:FindFirstChildOfClass("UIScale")
	local factor = if scale then scale.Scale else 1
	local viewport = workspace.CurrentCamera.ViewportSize
	-- AbsolutePosition cuenta desde debajo de la franja de arriba; esta pantalla, desde el borde.
	local from = box.AbsolutePosition + box.AbsoluteSize / 2 + GuiService:GetGuiInset()
	-- El escenario se encoge desde el centro: se deshace para que la copia salga de su sitio.
	local start = (from - viewport / 2) / factor + viewport / 2
	local center = UDim2.fromScale(0.5, 0.45)
	local ghost = frame(stage, UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y), UDim2.fromOffset(start.X, start.Y), Ui.COLORS.panel)
	ghost.ZIndex = 3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = ghost
	Ui.stroke(ghost, BLACK, 4)
	local flight = 0.5
	tween(ghost, flight, { Position = center, Size = UDim2.fromOffset(170, 170), BackgroundColor3 = ORB_COLOR }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	tween(corner, flight, { CornerRadius = UDim.new(0, 85) }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	wait(flight)
	ghost:Destroy()

	-- 2. El orbe se carga: anillos, rayos y temblor, y al final cambia al color de la rareza.
	local glowRays = rays(stage, center, 460, 26, WHITE, math.max(fx.rays or 0, 6), 1)
	for _, ray in glowRays:GetChildren() do
		(ray :: GuiObject).BackgroundTransparency = 0.6
	end
	local orb = frame(stage, UDim2.fromOffset(170, 170), center, ORB_COLOR)
	orb.ZIndex = 3
	circle(orb)
	Ui.gradient(orb, WHITE, Color3.fromRGB(110, 60, 170), 60)
	Ui.stroke(orb, BLACK, 5)
	local orbMark = Ui.label(orb, 70)
	orbMark.Size = UDim2.fromScale(1, 1)
	orbMark.Text = "?"
	orbMark.ZIndex = 4

	local pulses = 4 + math.floor(tier / 2)
	local charge = 0.9 + tier * 0.15
	for pulse = 1, pulses do
		if skip then
			break
		end
		local pulseColor = if pulse > pulses - 2 then color else ORB_COLOR
		ring(stage, center, 170, 460, pulseColor, 0.5)
		tween(orb, charge / pulses, { Size = UDim2.fromOffset(170 + pulse * 10, 170 + pulse * 10), BackgroundColor3 = pulseColor })
		for _, ray in glowRays:GetChildren() do
			tween(ray, charge / pulses, { BackgroundColor3 = pulseColor, BackgroundTransparency = 0.6 - pulse * 0.06 })
		end
		shake(orb, pulse * 2, charge / pulses)
		wait(charge / pulses)
	end

	-- 3. Estalla y sale la carta.
	flash(WHITE, 0, 0.45)
	tween(orb, 0.2, { Size = UDim2.fromOffset(340, 340), BackgroundTransparency = 1 })
	glowRays:Destroy()
	wait(0.1)
	orb:Destroy()

	local layer = frame(stage, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BLACK)
	layer.BackgroundTransparency = 1
	local entry = makeCard(layer, index, kept, odds)
	entry.card.Rotation = -25
	tween(entry.card, 0.35, { Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y), Rotation = 0 }, Enum.EasingStyle.Back)
	wait(0.4)

	-- 4. La carta se carga (más rato cuanto más rara), tiembla y se gira.
	local build = 0.4 + tier * 0.12
	local grown = CARD_SIZE * 1.12
	entry.backStroke.Color = color
	tween(entry.backStroke, build, { Thickness = 9 })
	tween(entry.card, build, { Size = UDim2.fromOffset(grown.X, grown.Y) }, Enum.EasingStyle.Sine)
	shake(entry.card, 3 + tier, build)
	for wave = 0, math.clamp(tier - 2, 0, 3) do
		task.delay(wave * build / 4, ring, layer, center, grown.X, grown.X * 3, color, 0.5)
	end
	wait(build)
	local closing = tween(entry.card, 0.1, { Size = UDim2.fromOffset(0, grown.Y * 1.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if closing then
		closing.Completed:Wait()
	end
	entry.back.Visible = false
	entry.front.Visible = true
	tween(entry.card, 0.25, { Size = UDim2.fromOffset(grown.X, grown.Y) }, Enum.EasingStyle.Back)
	tween(entry.shine, 0.5, { Position = UDim2.fromScale(1.8, 0.5) })

	-- 5. Destapada: rayos, anillo, destello, temblor y cartel del nivel de rareza.
	rays(layer, center, grown.Y * 1.7, 30, color, (fx.rays or 4) + 4, 4)
	if fx.rainbow then
		local halo = frame(layer, UDim2.fromOffset(grown.X + 40, grown.Y + 40), center, WHITE)
		halo.ZIndex = 4
		halo.BackgroundTransparency = 0.3
		Ui.round(halo, 28)
		rainbow(halo)
	end
	ring(layer, center, grown.X, grown.X * 2.6, color, 0.45)
	flash(color, 0.1, 0.8)
	shake(stage, 6 + (fx.shake or 0) * 2, 0.5)

	local banner = Ui.label(layer, 64)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0, 64)
	banner.Size = UDim2.fromOffset(760, 80)
	banner.Text = `¡{string.upper(tierInfo.name)}!`
	banner.TextColor3 = if fx.rainbow then WHITE else color:Lerp(WHITE, 0.2)
	banner.ZIndex = 30
	if fx.rainbow then
		rainbow(banner)
	end
	local bannerScale = Instance.new("UIScale")
	bannerScale.Scale = 3
	bannerScale.Parent = banner
	tween(bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	if fx.sparkles then
		task.spawn(function()
			while layer.Parent do
				sparkle(layer, color, math.random(12, 26), 31)
				task.wait(0.5 / fx.sparkles)
			end
		end)
	end

	-- Si se saltó, deja la carta destapada.
	if skip then
		entry.back.Visible = false
		entry.front.Visible = true
		entry.card.Size = UDim2.fromOffset(grown.X, grown.Y)
		entry.shine.Visible = false
	end

	summary.Text = `¡1 entre {Format.short(math.max(odds, 1))} con tu suerte de gacha!`
	footer.Visible = true

	-- Espera a "Continuar" (en automático sigue sola).
	local shown = os.clock()
	while overlay.Enabled do
		if auto and os.clock() - shown >= 3 then
			break
		end
		task.wait(0.1)
	end
	overlay.Enabled = false
	footer.Visible = false
	clearStage()
	skip = false
	showcasing = false
end

-- Tirada --------------------------------------------------------------------------------

-- Pasa espadas en el panel y se para en la que ha tocado. Si es muy buena para la suerte del
-- jugador, antes de pararse la enseña en grande.
local function spin(index: number, kept: boolean, luck: number, source: string)
	while spinning or showcasing do
		task.wait(0.1)
	end
	spinning = true
	Sfx.play("roll")
	clearAura()
	panelScale.Scale = 1
	panelShown = true
	local sword = Config.Swords[index]
	local odds = (sword.rarity or 1) / luck
	local big = odds >= Config.Gacha.ShowcaseOdds
	local tierInfo = Rarity.tier(sword.rarity)
	local color = tierInfo.color

	-- Pasan espadas, cada vez más despacio (deja un poco de tiempo para ver el resultado).
	detail.Text = if source == "roca" then "¡La roca de armas suelta una espada!" else "Tirando..."
	local total = Stats.rollTime(player) * 0.65
	local steps = 12
	for step = 1, steps do
		showSword(teaseIndex())
		Sfx.play("tick")
		panelScale.Scale = 1.04
		TweenService:Create(panelScale, TweenInfo.new(0.08), { Scale = 1 }):Play()
		task.wait(total * 2 * step / (steps * (steps + 1)))
	end

	if big then
		showcase(index, kept, odds)
	end

	-- Se para en la que ha tocado.
	showSword(index)
	local text = `<font color="#{color:ToHex()}">{tierInfo.name}</font>  ·  1 entre {Format.short(math.max(odds, 1))}`
	if not kept then
		text ..= `  ·  <font color="#{Ui.COLORS.orange:ToHex()}">vendida +{Config.Gacha.SellValue}</font>`
	elseif source == "roca" then
		text ..= "  ·  roca de armas"
	end
	detail.Text = text
	panelScale.Scale = 1.25
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- El aura cuenta la suerte: lo que para este jugador es fácil no brilla.
	local luckTier = tierIndex(odds)
	if luckTier >= 5 then
		Sfx.play("win")
	elseif luckTier >= 3 then
		Sfx.play("rare")
	end
	panelAura(luckTier, Rarity.tier(odds).color)
	if luckTier >= 3 and not big then
		machineEffect(Rarity.tier(odds).color)
	end
	spinning = false

	-- Pasado un rato, el panel vuelve a su estado de reposo.
	resultId += 1
	local mine = resultId
	task.delay(RESULT_STAY, function()
		if resultId == mine and not spinning then
			clearAura()
			local shrink = TweenService:Create(panelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			shrink:Play()
			shrink.Completed:Wait()
			if resultId == mine and not spinning then
				panelShown = false
			end
			panelScale.Scale = 1
		end
	end)
end

local function request()
	if rolling or showcasing then
		return
	end
	rolling = true
	rollStarted = os.clock()
	Remotes.RollGacha:FireServer()
end

-- Construcción --------------------------------------------------------------------------

local function buildPanel()
	panel = Instance.new("Frame")
	panel.Name = "GachaBar"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 84) -- bajo la barra de transporte
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundTransparency = 1
	panel.Parent = Ui.screen()
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	glow = frame(panel, UDim2.new(1, 16, 1, 16), UDim2.fromScale(0.5, 0.5), WHITE)
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.ZIndex = 1
	Ui.round(glow, 20)
	glowStroke = Ui.stroke(glow, WHITE, 4)
	glowStroke.Transparency = 1

	box = frame(panel, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE)
	box.Name = "Box"
	box.ZIndex = 2
	Ui.round(box, 14)
	Ui.gradient(box, Color3.fromRGB(70, 60, 100), Ui.COLORS.panel, 90)
	Ui.stroke(box, BLACK, 3)

	iconSlot = Instance.new("Frame")
	iconSlot.Name = "Slot"
	iconSlot.AnchorPoint = Vector2.new(0, 0.5)
	iconSlot.Position = UDim2.new(0, 9, 0.5, 0)
	iconSlot.Size = UDim2.fromOffset(86, 86) -- grande: el arma en 3D es lo que más se mira del panel
	iconSlot.BackgroundColor3 = Ui.COLORS.cell
	iconSlot.ZIndex = 3
	iconSlot.Parent = box
	Ui.round(iconSlot, 10)
	Ui.stroke(iconSlot, BLACK, 2)

	title = Ui.label(box, 24)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(106, 14)
	title.Size = UDim2.new(1, -116, 0, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 4

	detail = Ui.label(box, 16)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(106, 48)
	detail.Size = UDim2.new(1, -116, 0, 24)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.Text = "¡Gratis! Pulsa Tirar"
	detail.ZIndex = 4

	-- Barra del tiempo que falta para la siguiente tirada.
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 106, 1, -12)
	track.Size = UDim2.new(1, -118, 0, 8)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.ZIndex = 4
	track.Parent = box
	Ui.round(track, 4)
	progress = Instance.new("Frame")
	progress.Size = UDim2.fromScale(1, 1)
	progress.BackgroundColor3 = ORB_COLOR
	progress.ZIndex = 5
	progress.Parent = track
	Ui.round(progress, 4)

	sparkleArea = frame(panel, UDim2.new(1, 30, 1, 30), UDim2.fromScale(0.5, 0.5), WHITE)
	sparkleArea.Name = "Sparkles"
	sparkleArea.BackgroundTransparency = 1
	sparkleArea.ZIndex = 6

	showSword(2)
	title.Text = "Gacha de espadas"
	title.TextColor3 = WHITE
end

local function buildOverlay()
	overlay = Instance.new("ScreenGui")
	overlay.Name = "GachaRoll"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder = 10
	overlay.Enabled = false
	overlay.Parent = player:WaitForChild("PlayerGui")

	dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 6, 20)
	dim.BorderSizePixel = 0
	dim.Parent = overlay
	dim.Activated:Connect(function()
		skip = true
	end)

	stage = frame(overlay, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BLACK)
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.ZIndex = 2

	footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -30)
	footer.Size = UDim2.fromOffset(460, 110)
	footer.BackgroundTransparency = 1
	footer.Visible = false
	footer.ZIndex = 20
	footer.Parent = overlay

	summary = Ui.label(footer, 24)
	summary.Size = UDim2.new(1, 0, 0, 36)
	summary.ZIndex = 21

	local continueButton = Ui.button(footer, "Continuar", Ui.COLORS.green)
	continueButton.Name = "Continue"
	continueButton.AnchorPoint = Vector2.new(0.5, 0)
	continueButton.Position = UDim2.new(0.5, 0, 0, 46)
	continueButton.Size = UDim2.fromOffset(300, 62)
	continueButton.TextSize = 24
	continueButton.ZIndex = 21
	continueButton.Activated:Connect(function()
		overlay.Enabled = false
	end)

	-- En pantallas pequeñas se encoge todo.
	local stageScale = Instance.new("UIScale")
	stageScale.Parent = stage
	local footerScale = Instance.new("UIScale")
	footerScale.Parent = footer
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		stageScale.Scale = math.min(1, view.X / 960, view.Y / 680)
		footerScale.Scale = stageScale.Scale
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end

function GachaRoll.start()
	buildPanel()
	buildOverlay()

	-- Botones de abajo.
	local bar = Instance.new("Frame")
	bar.Name = "Roll"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -20) -- abajo del todo: ya no hay barra de armas de Roblox
	bar.Size = UDim2.fromOffset(0, 64)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = Ui.screen()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local rollButton = Ui.button(bar, "Tirar", Ui.COLORS.green)
	rollButton.Name = "RollOnce"
	rollButton.LayoutOrder = 1
	rollButton.Size = UDim2.fromOffset(170, 64)
	rollButton.TextSize = 26
	rollButton.Activated:Connect(request)

	local autoButton = Ui.button(bar, "", Ui.COLORS.blue)
	autoButton.Name = "Auto"
	autoButton.LayoutOrder = 2
	autoButton.Size = UDim2.fromOffset(170, 64)
	autoButton.TextSize = 22
	local function refreshAuto()
		autoButton.Text = if auto then "Auto: SÍ" else "Auto: NO"
		autoButton.BackgroundColor3 = if auto then Ui.COLORS.orange else Ui.COLORS.blue
	end
	autoButton.Activated:Connect(function()
		auto = not auto
		refreshAuto()
	end)
	refreshAuto()

	Remotes.GachaRolled.OnClientEvent:Connect(function(index: number, kept: boolean, luck: number, source: string)
		task.spawn(function()
			-- Si algo falla a mitad, que no se quede atascado el gacha (ni la tirada automática).
			local ok, problem = pcall(spin, index, kept, luck, source)
			if not ok then
				warn(`[GachaRoll] {problem}`)
				overlay.Enabled = false
				clearStage()
				skip = false
				showcasing = false
				spinning = false
			end
			-- Destapada: el servidor ya puede enseñar su aura y aviso a los demás.
			if (Config.Swords[index].rarity or 1) / luck >= math.min(Config.Gacha.AuraOdds, Config.AnnounceOdds) then
				Remotes.GachaRevealed:FireServer()
			end
			if source == "gacha" then
				-- La siguiente se puede pedir cuando pase el tiempo por tirada.
				local left = Stats.rollTime(player) - (os.clock() - rollStarted)
				if left > 0 then
					task.wait(left)
				end
				rolling = false
			end
		end)
	end)
	Remotes.GachaAura.OnClientEvent:Connect(characterAura)
	Players.PlayerRemoving:Connect(function(who)
		if auras[who] then
			auras[who]()
		end
	end)

	-- Barra de progreso, botones y tirada automática.
	RunService.RenderStepped:Connect(function()
		local fill = if rolling then math.clamp((os.clock() - rollStarted) / Stats.rollTime(player), 0, 1) else 1
		progress.Size = UDim2.fromScale(fill, 1)
		rollButton.BackgroundColor3 = if rolling then Ui.COLORS.gray else Ui.COLORS.green
		local hidden = Ui.anyOpen() or showcasing
		bar.Visible = not hidden
		panel.Visible = panelShown and not hidden
		if auto and not rolling and not showcasing then
			request()
		end
	end)
	-- Si el servidor no contesta (p. ej. por pedir demasiado pronto), se puede volver a tirar.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if rolling and not spinning and not showcasing and os.clock() - rollStarted > Stats.rollTime(player) + 2 then
				rolling = false
			end
		end
	end)
end

return GachaRoll
