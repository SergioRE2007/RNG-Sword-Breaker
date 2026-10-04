-- Gacha en el cliente: botones de tirada (x1, x5, x10 y automática) junto a la máquina del hub
-- y la animación de la tirada: orbe que se carga con rayos y anillos (del color de lo mejor que
-- ha salido, para meter tensión), destello y cartas que se destapan una a una. Las cartas raras
-- tiemblan antes de girarse y las muy raras paran la pantalla con un destello de su color.
-- Pulsar la pantalla durante la animación la salta.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent.Ui)

local GachaRoll = {}

local player = Players.LocalPlayer
local MACHINE_POSITION = Vector3.new(0, Config.Plot.FloorHeight, 0)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local ORB_COLOR = Color3.fromRGB(190, 110, 255)
local RARE_ODDS = 100 -- desde aquí (probabilidad real) la carta tiembla antes de girarse
local AUTO_SPEED = 0.6 -- en automático la animación va más rápida

local overlay: ScreenGui
local stage: Frame -- todo lo de la animación; se mueve entero para temblar
local skip = false
local speed = 1
local rolling = false
local auto = false
local lastCount = Config.Gacha.Counts[1]

-- Utilidades ----------------------------------------------------------------------------

local function wait(seconds: number)
	if not skip and seconds > 0 then
		task.wait(seconds * speed)
	end
end

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween?
	if skip then
		for key, value in props do
			(instance :: any)[key] = value
		end
		return nil
	end
	local info = TweenInfo.new(seconds * speed, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
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

-- Hace temblar `target` alrededor de su posición durante `seconds`.
local function shake(target: GuiObject, strength: number, seconds: number)
	if skip then
		return
	end
	local base = target.Position
	local finish = os.clock() + seconds * speed
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

-- Rayos que giran detrás de algo, del color dado. Devuelve el contenedor (se borra con él).
local function rays(parent: Instance, position: UDim2, length: number, color: Color3, count: number): Frame
	local holder = frame(parent, UDim2.fromOffset(0, 0), position, color)
	holder.BackgroundTransparency = 1
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	local pieces = {}
	for index = 1, count do
		local ray = frame(holder, UDim2.fromOffset(length * 2, 26), UDim2.fromScale(0.5, 0.5), color)
		ray.Rotation = index * 180 / count
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = fade
		gradient.Parent = ray
		table.insert(pieces, ray)
	end
	local connection
	connection = RunService.RenderStepped:Connect(function(delta)
		if not holder.Parent then
			connection:Disconnect()
			return
		end
		for _, ray in pieces do
			ray.Rotation += delta * 40
		end
	end)
	return holder
end

-- Anillo que sale del centro y se desvanece.
local function ring(parent: Instance, position: UDim2, from: number, to: number, color: Color3, seconds: number)
	if skip then
		return
	end
	local item = frame(parent, UDim2.fromOffset(from, from), position, color)
	item.BackgroundTransparency = 1
	circle(item)
	local stroke = Ui.stroke(item, color, 6)
	tween(item, seconds, { Size = UDim2.fromOffset(to, to) })
	tween(stroke, seconds, { Transparency = 1, Thickness = 1 })
	task.delay(seconds * speed, function()
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
	task.delay(seconds * speed, function()
		item:Destroy()
	end)
end

-- Máquina del hub ------------------------------------------------------------------------

local sparks: ParticleEmitter?
local orbRest -- tamaño, color y luz del orbe en reposo, para volver siempre a ellos

-- El orbe de la máquina se hincha, brilla y suelta chispas (solo lo ve quien tira).
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
	emitter:Emit(60)
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
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(orb, info, { Size = Vector3.new(7.5, 7.5, 7.5), Color = color }):Play()
	if light then
		TweenService:Create(light, info, { Brightness = 6, Range = 40 }):Play()
	end
end

-- Cartas ----------------------------------------------------------------------------------

local function oddsOf(result, luck: number): number
	return (Config.Swords[result.index].rarity or 1) / luck
end

local function makeCard(parent: Instance, result, size: Vector2, luck: number)
	local sword = Config.Swords[result.index]
	local tier = Rarity.tier(sword.rarity)

	local card = frame(parent, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), WHITE)
	card.BackgroundTransparency = 1
	card.ZIndex = 5

	-- Dorso
	local back = frame(card, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), ORB_COLOR)
	back.ZIndex = 5
	Ui.round(back, 14)
	Ui.gradient(back, WHITE, Color3.fromRGB(90, 70, 140), 90)
	local backStroke = Ui.stroke(back, BLACK, 4)
	local mark = Ui.label(back, math.floor(size.Y * 0.4))
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "?"
	mark.ZIndex = 6

	-- Cara: degradado del color de la rareza, icono, nombre, nivel y probabilidad.
	local front = frame(card, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE)
	front.Visible = false
	front.ClipsDescendants = true
	front.ZIndex = 5
	Ui.round(front, 14)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(tier.color:Lerp(WHITE, 0.15), Ui.COLORS.dark)
	gradient.Parent = front
	Ui.stroke(front, tier.color:Lerp(WHITE, 0.3), 4)

	local iconBox = frame(front, UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.5, 0.32), WHITE)
	iconBox.BackgroundTransparency = 1
	iconBox.ZIndex = 6
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = iconBox
	Ui.swordIcon(iconBox, sword.color)
	for _, descendant in iconBox:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 7
		end
	end

	local big = size.Y > 220
	local name = Ui.label(front, if big then 24 else 16)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.6)
	name.Size = UDim2.new(1, -10, 0.2, 0)
	name.TextWrapped = true
	name.Text = sword.name
	name.TextColor3 = sword.color:Lerp(WHITE, 0.35)
	name.ZIndex = 8

	local info = Ui.label(front, if big then 18 else 13)
	info.AnchorPoint = Vector2.new(0.5, 1)
	info.Position = UDim2.new(0.5, 0, 1, -6)
	info.Size = UDim2.new(1, -8, 0.2, 0)
	info.TextWrapped = true
	info.Text = `<font color="#{tier.color:ToHex()}">{tier.name}</font>\n1 entre {Format.short(oddsOf(result, luck))}`
	info.ZIndex = 8

	if not result.kept then
		local sold = frame(front, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BLACK)
		sold.BackgroundTransparency = 0.45
		sold.ZIndex = 9
		local tag = Ui.label(sold, if big then 22 else 15)
		tag.Size = UDim2.new(1, 0, 0, 30)
		tag.Position = UDim2.fromScale(0.5, 0.32)
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Rotation = -12
		tag.Text = `Vendida\n+{Config.Gacha.SellValue} gemas`
		tag.TextColor3 = Ui.COLORS.orange
		tag.ZIndex = 10
	end

	-- Brillo que cruza la carta al destaparla.
	local shine = frame(front, UDim2.new(0, 36, 1.6, 0), UDim2.fromScale(-0.3, 0.5), WHITE)
	shine.Rotation = 20
	shine.BackgroundTransparency = 0.45
	shine.ZIndex = 11
	shine.Visible = oddsOf(result, luck) >= 10

	return {
		card = card,
		back = back,
		backStroke = backStroke,
		front = front,
		shine = shine,
		size = size,
		tier = tier,
		sword = sword,
		odds = oddsOf(result, luck),
	}
end

-- Gira la carta (se estrecha, cambia de cara y vuelve con rebote).
local function flip(entry)
	local width, height = entry.size.X, entry.size.Y
	local closing = tween(entry.card, 0.1, { Size = UDim2.fromOffset(0, height * 1.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if closing then
		closing.Completed:Wait()
	end
	entry.back.Visible = false
	entry.front.Visible = true
	tween(entry.card, 0.22, { Size = UDim2.fromOffset(width, height) }, Enum.EasingStyle.Back)
	tween(entry.shine, 0.5, { Position = UDim2.fromScale(1.8, 0.5) })
end

-- Destapa una carta. Las raras se cargan antes (tiemblan y brillan del color de su rareza).
local function reveal(entry, layer: Frame)
	local rare = entry.odds >= RARE_ODDS
	local epic = entry.odds >= Config.AnnounceOdds
	if rare then
		local build = if epic then 1.1 else 0.55
		entry.backStroke.Color = entry.tier.color
		tween(entry.backStroke, build, { Thickness = 8 })
		tween(entry.card, build, { Size = UDim2.fromOffset(entry.size.X * 1.12, entry.size.Y * 1.12) }, Enum.EasingStyle.Sine)
		shake(entry.card, if epic then 7 else 4, build)
		if epic then
			for step = 0, 2 do
				task.delay(step * build / 3 * speed, ring, layer, entry.card.Position, entry.size.X, entry.size.X * 3, entry.tier.color, 0.5)
			end
		end
		wait(build)
		entry.size = entry.size * 1.12
	end
	flip(entry)
	if rare then
		local glow = rays(layer, entry.card.Position, entry.size.Y * (if epic then 1.6 else 1.0), entry.tier.color, if epic then 10 else 6)
		glow.ZIndex = 4
		for _, ray in glow:GetChildren() do
			(ray :: GuiObject).ZIndex = 4
		end
		ring(layer, entry.card.Position, entry.size.X, entry.size.X * 2.5, entry.tier.color, 0.45)
		flash(entry.tier.color, if epic then 0.1 else 0.55, if epic then 0.8 else 0.35)
		if epic then
			shake(stage, 12, 0.5)
			local banner = Ui.label(layer, 64)
			banner.AnchorPoint = Vector2.new(0.5, 0.5)
			banner.Position = UDim2.new(0.5, 0, 0, 70)
			banner.Size = UDim2.fromOffset(700, 80)
			banner.Text = `¡{string.upper(entry.tier.name)}!`
			banner.TextColor3 = entry.tier.color:Lerp(WHITE, 0.2)
			banner.ZIndex = 30
			local scale = Instance.new("UIScale")
			scale.Scale = 3
			scale.Parent = banner
			tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			wait(0.9)
		end
	end
end

-- Animación completa --------------------------------------------------------------------

local function clearStage()
	for _, child in stage:GetChildren() do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
end

local footer: Frame
local summary: TextLabel
local againButton: TextButton
local dim: TextButton

local function canAfford(count: number): boolean
	return (player:GetAttribute("Gems") or 0) >= Config.Gacha.Cost * count
end

local function isNear(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - MACHINE_POSITION).Magnitude <= Config.Gacha.UseDistance
end

local request: (count: number) -> ()

local function close()
	overlay.Enabled = false
	footer.Visible = false
	clearStage()
	rolling = false
end

local function play(results, luck: number)
	skip = false
	speed = if auto then AUTO_SPEED else 1
	clearStage()
	footer.Visible = false
	overlay.Enabled = true
	dim.BackgroundTransparency = 1
	tween(dim, 0.3, { BackgroundTransparency = 0.12 })

	-- Lo mejor que ha salido marca el color de la carga.
	local best = results[1]
	for _, result in results do
		if oddsOf(result, luck) > oddsOf(best, luck) then
			best = result
		end
	end
	local bestOdds = oddsOf(best, luck)
	local bestColor = Rarity.tier(Config.Swords[best.index].rarity).color
	machineEffect(if bestOdds >= RARE_ODDS then bestColor else ORB_COLOR)

	-- 1. El orbe se carga.
	local center = UDim2.fromScale(0.5, 0.45)
	local glow = rays(stage, center, 420, WHITE, 8)
	for _, ray in glow:GetChildren() do
		(ray :: GuiObject).BackgroundTransparency = 0.6
	end
	local orb = frame(stage, UDim2.fromOffset(0, 0), center, ORB_COLOR)
	orb.ZIndex = 3
	circle(orb)
	Ui.gradient(orb, WHITE, Color3.fromRGB(110, 60, 170), 60)
	Ui.stroke(orb, BLACK, 5)
	local orbMark = Ui.label(orb, 70)
	orbMark.Size = UDim2.fromScale(1, 1)
	orbMark.Text = "?"
	orbMark.ZIndex = 4
	tween(orb, 0.35, { Size = UDim2.fromOffset(170, 170) }, Enum.EasingStyle.Back)
	wait(0.3)

	local charge = Config.Gacha.RollTime - 0.3
	local pulses = 5
	for pulse = 1, pulses do
		if skip then
			break
		end
		-- Al final cambia al color de lo mejor si es raro (aviso de que viene algo bueno).
		local color = if pulse > pulses - 2 and bestOdds >= RARE_ODDS then bestColor else ORB_COLOR
		ring(stage, center, 170, 420, color, 0.5)
		tween(orb, charge / pulses, { Size = UDim2.fromOffset(170 + pulse * 10, 170 + pulse * 10), BackgroundColor3 = color })
		for _, ray in glow:GetChildren() do
			tween(ray, charge / pulses, { BackgroundColor3 = color, BackgroundTransparency = 0.6 - pulse * 0.08 })
		end
		shake(orb, pulse * 2, charge / pulses)
		wait(charge / pulses)
	end

	-- 2. Estalla.
	flash(WHITE, 0, 0.45)
	tween(orb, 0.2, { Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1 })
	glow:Destroy()
	wait(0.1)
	orb:Destroy()

	-- 3. Las cartas salen del centro a su sitio.
	local count = #results
	local perRow = math.min(count, 5)
	local rows = math.ceil(count / 5)
	local size = if count == 1 then Vector2.new(210, 280) else Vector2.new(140, 190)
	local gap = 18
	local layer = frame(stage, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BLACK)
	layer.BackgroundTransparency = 1
	local entries = {}
	for position, result in results do
		local entry = makeCard(layer, result, size, luck)
		local column = (position - 1) % perRow
		local row = math.floor((position - 1) / perRow)
		local x = (column - (perRow - 1) / 2) * (size.X + gap)
		local y = (row - (rows - 1) / 2) * (size.Y + gap)
		entry.card.Position = center
		entry.card.Size = UDim2.fromOffset(0, 0)
		entry.card.Rotation = math.random(-40, 40)
		local target = UDim2.new(0.5, x, 0.45, y)
		tween(entry.card, 0.35, { Position = target, Size = UDim2.fromOffset(size.X, size.Y), Rotation = 0 }, Enum.EasingStyle.Back)
		task.delay(0.36 * speed, function()
			entry.card.Position = target
		end)
		table.insert(entries, entry)
		wait(0.04)
	end
	wait(0.4)

	-- 4. Se destapan una a una (la carga de las raras alarga la espera).
	for _, entry in entries do
		reveal(entry, layer)
		wait(Config.Gacha.RevealStep)
	end

	-- Si se saltó, deja todas destapadas.
	if skip then
		for _, entry in entries do
			entry.back.Visible = false
			entry.front.Visible = true
			entry.card.Size = UDim2.fromOffset(entry.size.X, entry.size.Y)
			entry.shine.Visible = false
		end
	end

	-- 5. Resumen y botones.
	local keptCount, soldCount = 0, 0
	for _, result in results do
		if result.kept then
			keptCount += 1
		else
			soldCount += 1
		end
	end
	local text = `{keptCount} espada{if keptCount == 1 then "" else "s"} nueva{if keptCount == 1 then "" else "s"}`
	if soldCount > 0 then
		text ..= `  ·  {soldCount} vendida{if soldCount == 1 then "" else "s"} (+{soldCount * Config.Gacha.SellValue} gemas)`
	end
	summary.Text = text
	againButton.Text = `Otra vez x{count}  ·  {Config.Gacha.Cost * count} gemas`
	againButton.BackgroundColor3 = if canAfford(count) then Ui.COLORS.green else Ui.COLORS.gray
	footer.Visible = true
	rolling = false

	if auto then
		task.wait(if skip then 0.3 else 1.1 * speed)
		if not auto or not overlay.Enabled then
			return
		end
		if canAfford(lastCount) and isNear() then
			request(lastCount)
		else
			auto = false
			close()
			Ui.toast(if isNear() then "Tirada automática parada: no te quedan gemas" else "Tirada automática parada", Ui.COLORS.orange)
		end
	end
end

-- Botones ------------------------------------------------------------------------------

local autoButton: TextButton
local refreshButtons: () -> ()

request = function(count: number)
	if rolling then
		return
	end
	if not canAfford(count) then
		Ui.toast(`Te faltan gemas: x{count} cuesta {Config.Gacha.Cost * count}`, Ui.COLORS.red)
		if auto then
			auto = false
			refreshButtons()
		end
		return
	end
	lastCount = count
	rolling = true
	Remotes.RollGacha:FireServer(count)
	-- Si el servidor la rechaza (demasiado pronto, lejos de la máquina), se puede volver a pedir.
	task.delay(3, function()
		if rolling and not overlay.Enabled then
			rolling = false
		end
	end)
end

function GachaRoll.start()
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
	-- En pantallas pequeñas se encoge todo.
	local scale = Instance.new("UIScale")
	scale.Parent = stage
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, view.X / 960, view.Y / 680)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()

	footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -30)
	footer.Size = UDim2.fromOffset(620, 120)
	footer.BackgroundTransparency = 1
	footer.Visible = false
	footer.ZIndex = 20
	footer.Parent = overlay
	local footerScale = Instance.new("UIScale")
	footerScale.Parent = footer
	scale:GetPropertyChangedSignal("Scale"):Connect(function()
		footerScale.Scale = scale.Scale
	end)
	footerScale.Scale = scale.Scale

	summary = Ui.label(footer, 22)
	summary.Size = UDim2.new(1, 0, 0, 36)
	summary.ZIndex = 21

	againButton = Ui.button(footer, "", Ui.COLORS.green)
	againButton.Name = "Again"
	againButton.Position = UDim2.fromOffset(0, 48)
	againButton.Size = UDim2.fromOffset(300, 64)
	againButton.TextSize = 22
	againButton.ZIndex = 21
	againButton.Activated:Connect(function()
		request(lastCount)
	end)

	local closeButton = Ui.button(footer, "Cerrar", Ui.COLORS.red)
	closeButton.Name = "Close"
	closeButton.Position = UDim2.fromOffset(320, 48)
	closeButton.Size = UDim2.fromOffset(300, 64)
	closeButton.TextSize = 22
	closeButton.ZIndex = 21
	closeButton.Activated:Connect(function()
		auto = false
		refreshButtons()
		close()
	end)

	-- Barra de tirada: solo junto a la máquina del hub.
	local bar = Instance.new("Frame")
	bar.Name = "Roll"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -104)
	bar.Size = UDim2.fromOffset(0, 72)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = Ui.screen()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local countButtons = {}
	for order, count in Config.Gacha.Counts do
		local item = Ui.button(bar, `Tirar x{count}\n{Config.Gacha.Cost * count} gemas`, Ui.COLORS.gray)
		item.Name = `Roll{count}`
		item.LayoutOrder = order
		item.Size = UDim2.fromOffset(150, 72)
		item.TextSize = 21
		item.Activated:Connect(function()
			request(count)
		end)
		countButtons[count] = item
	end

	autoButton = Ui.button(bar, "", Ui.COLORS.gray)
	autoButton.Name = "Auto"
	autoButton.LayoutOrder = #Config.Gacha.Counts + 1
	autoButton.Size = UDim2.fromOffset(150, 72)
	autoButton.TextSize = 21
	autoButton.Activated:Connect(function()
		auto = not auto
		refreshButtons()
		if auto then
			-- Tira las más grandes que se pueda pagar.
			local chosen
			for _, count in Config.Gacha.Counts do
				if canAfford(count) then
					chosen = count
				end
			end
			if chosen then
				request(chosen)
			else
				request(Config.Gacha.Counts[1])
			end
		end
	end)

	refreshButtons = function()
		for count, item in countButtons do
			item.BackgroundColor3 = if canAfford(count) then Ui.COLORS.green else Ui.COLORS.gray
		end
		autoButton.Text = if auto then "Automática\nSÍ" else "Automática\nNO"
		autoButton.BackgroundColor3 = if auto then Ui.COLORS.orange else Ui.COLORS.blue
	end
	player:GetAttributeChangedSignal("Gems"):Connect(refreshButtons)
	refreshButtons()

	Remotes.GachaRolled.OnClientEvent:Connect(function(results, luck: number)
		task.spawn(play, results, luck)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local near = isNear()
			-- Con una ventana abierta o durante la animación se esconde.
			bar.Visible = near and not Ui.anyOpen() and not overlay.Enabled
			if auto and not near and not overlay.Enabled then
				auto = false
				refreshButtons()
			end
		end
	end)
end

return GachaRoll
