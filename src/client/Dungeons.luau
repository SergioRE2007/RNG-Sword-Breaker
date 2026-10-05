-- Mazmorras en el cliente: ventana del portal (una tarjeta por dificultad de Config.Dungeons), panel de la
-- partida (oleada, enemigos, tiempo y vida), cartel con el resultado y animación del portal del hub.
-- Todo lo decide el servidor (server/Dungeons): aquí solo se pide entrar o salir y se pinta lo que publica
-- en los atributos Dungeon, DungeonWave, DungeonWaves, DungeonLeft y DungeonEnds.
-- Para dejarlo solo (AFK): "Repetir" (DungeonLoop, lo lleva el servidor: al superarla empieza otra igual) y
-- "Auto" (aquí: el personaje anda hacia el enemigo más cercano y le pega, con los mismos espadazos que un clic).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local SwordController = require(script.Parent.SwordController)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Dungeons = {}

local player = Players.LocalPlayer
local cfg = Config.Dungeon
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)
local CLOSE_DISTANCE = 34 -- la ventana se cierra al alejarse del portal
local CARD_WIDTH = 172 -- ancho de cada tarjeta de dificultad
local CARD_GAP = 10

-- Capas (la interfaz ordena el ZIndex globalmente; valores absolutos de este módulo).
local Z_HURT = 40 -- destello rojo al recibir un golpe
local Z_RESULT = 60 -- cartel del resultado, por encima del HUD

local REASONS = {
	clear = { "¡MAZMORRA SUPERADA!", GOLD },
	dead = { "HAS CAÍDO", BAD },
	time = { "SE ACABÓ EL TIEMPO", BAD },
	left = { "HAS SALIDO", Color3.fromRGB(200, 205, 225) },
}

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Daño por golpe del enemigo más flojo y del más fuerte en esa dificultad.
local function enemyHits(level): (number, number)
	local low, high = math.huge, 0
	for _, enemy in Config.Enemies do
		local hit = enemy.damage * level.power
		low, high = math.min(low, hit), math.max(high, hit)
	end
	return low, high
end

-- Cara de enemigo hecha con marcos: el "retrato" de cada tarjeta.
local function face(parent: Instance, color: Color3)
	local head = Instance.new("Frame")
	head.Name = "Face"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(0.82, 0.82)
	head.BackgroundColor3 = WHITE
	head.BorderSizePixel = 0
	head.Parent = parent
	Ui.round(head, 12)
	Ui.stroke(head, BLACK, 3)
	Ui.gradient(head, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.3), 90)
	for _, x in { 0.3, 0.7 } do
		local eye = Instance.new("Frame")
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.22, 0.28)
		eye.BackgroundColor3 = WHITE
		eye.BorderSizePixel = 0
		eye.Parent = head
		Ui.round(eye, 4)
		local pupil = Instance.new("Frame")
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.5, 0.6)
		pupil.Size = UDim2.fromScale(0.5, 0.55)
		pupil.BackgroundColor3 = BLACK
		pupil.BorderSizePixel = 0
		pupil.Parent = eye
		Ui.round(pupil, 3)
	end
	local mouth = Instance.new("Frame")
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.74)
	mouth.Size = UDim2.fromScale(0.42, 0.09)
	mouth.BackgroundColor3 = BLACK
	mouth.BorderSizePixel = 0
	mouth.Parent = head
	Ui.round(mouth, 3)
	return head
end

-- Ventana del portal ---------------------------------------------------------------------

local function buildMenu()
	local window, body = Ui.window("Dungeons", "Mazmorras", Vector2.new(940, 560), function(parent)
		Ui.starIcon(parent, Color3.fromRGB(215, 160, 255))
	end)

	-- Tus números, para comparar con lo que pide cada dificultad.
	local mine = Ui.label(body, 20)
	mine.Name = "Mine"
	mine.Position = UDim2.fromOffset(16, 6)
	mine.Size = UDim2.new(1, -32, 0, 32)
	mine.TextXAlignment = Enum.TextXAlignment.Left
	-- Repetir en bucle: arriba a la derecha, vale para la mazmorra en la que se entre.
	local loopButton = Ui.button(body, "", Ui.COLORS.gray)
	loopButton.Name = "Loop"
	loopButton.AnchorPoint = Vector2.new(1, 0)
	loopButton.Position = UDim2.new(1, -12, 0, 3)
	loopButton.Size = UDim2.fromOffset(190, 36)
	loopButton.TextSize = 19
	local function paintLoop()
		local on = player:GetAttribute("DungeonLoop") == true
		loopButton.Text = if on then "Repetir: SÍ" else "Repetir: NO"
		loopButton.BackgroundColor3 = if on then Ui.COLORS.green else Ui.COLORS.gray
	end
	loopButton.Activated:Connect(function()
		Remotes.SetDungeonLoop:FireServer(player:GetAttribute("DungeonLoop") ~= true)
	end)
	player:GetAttributeChangedSignal("DungeonLoop"):Connect(paintLoop)
	paintLoop()

	local note = Ui.label(body, 16)
	note.AnchorPoint = Vector2.new(1, 0)
	note.Position = UDim2.new(1, -212, 0, 6)
	note.Size = UDim2.new(0.45, 0, 0, 32)
	note.TextXAlignment = Enum.TextXAlignment.Right
	note.TextColor3 = Color3.fromRGB(190, 195, 215)
	note.Text = `{#Config.Dungeons} mazmorras · {#cfg.Waves} oleadas · la última con jefe · {math.floor(cfg.TimeLimit / 60)} min`

	-- Las tarjetas van en una fila que se desliza de lado: caben CARDS_SHOWN a la vez.
	local row = Instance.new("ScrollingFrame")
	row.Name = "Cards"
	row.Position = UDim2.fromOffset(10, 44)
	row.Size = UDim2.new(1, -20, 1, -50)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.ScrollBarThickness = 10
	row.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	row.CanvasSize = UDim2.new()
	row.AutomaticCanvasSize = Enum.AutomaticSize.X
	row.Parent = body
	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, 4)
	rowPadding.PaddingRight = UDim.new(0, 4)
	rowPadding.PaddingTop = UDim.new(0, 4)
	rowPadding.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local cards = {}
	for index, level in Config.Dungeons do
		local card = Instance.new("Frame")
		card.Name = "Card" .. index
		card.LayoutOrder = index
		card.Size = UDim2.new(0, CARD_WIDTH, 1, -22) -- deja sitio a la barra de desplazamiento
		card.BackgroundColor3 = WHITE
		card.BorderSizePixel = 0
		card.Parent = row
		Ui.round(card, 12)
		Ui.stroke(card, BLACK, 3)
		Ui.panel(card, Color3.fromRGB(52, 56, 100):Lerp(level.color, 0.12))

		-- Cabecera del color de la dificultad.
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.Position = UDim2.fromOffset(6, 6)
		head.Size = UDim2.new(1, -12, 0, 44)
		head.BackgroundColor3 = WHITE
		head.BorderSizePixel = 0
		head.Parent = card
		Ui.round(head, 9)
		Ui.stroke(head, BLACK, 2.5)
		Ui.gradient(head, level.color:Lerp(WHITE, 0.25), level.color:Lerp(BLACK, 0.4), 90)
		local name = Ui.label(head, 26)
		name.Size = UDim2.fromScale(1, 1)
		name.Text = string.upper(level.name)
		name.TextScaled = true
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 26
		nameLimit.MinTextSize = 14
		nameLimit.Parent = name
		local namePad = Instance.new("UIPadding")
		namePad.PaddingLeft = UDim.new(0, 6)
		namePad.PaddingRight = UDim.new(0, 6)
		namePad.Parent = name

		-- Retrato del enemigo, flotando.
		local portrait = Instance.new("Frame")
		portrait.Name = "Portrait"
		portrait.AnchorPoint = Vector2.new(0.5, 0)
		portrait.Position = UDim2.new(0.5, 0, 0, 58)
		portrait.Size = UDim2.fromOffset(84, 84)
		portrait.BackgroundTransparency = 1
		portrait.Parent = card
		local head3 = face(portrait, level.color)
		if not Performance.get() then
			TweenService:Create(head3, TweenInfo.new(1.4 + index * 0.13, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.42), Rotation = if index % 2 == 0 then 4 else -4 }):Play()
		end

		-- Datos: una lista de líneas cortas.
		local info = Ui.label(card, 17)
		info.Name = "Info"
		info.Position = UDim2.fromOffset(12, 148)
		info.Size = UDim2.new(1, -20, 1, -148 - 70)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Top
		info.TextWrapped = true
		info.LineHeight = 1.12

		local enter = Ui.button(card, "Entrar", Ui.COLORS.green)
		enter.Name = "Enter"
		enter.AnchorPoint = Vector2.new(0.5, 1)
		enter.Position = UDim2.new(0.5, 0, 1, -10)
		enter.Size = UDim2.new(1, -20, 0, 54)
		enter.TextSize = 26
		Ui.sparkle(enter, 5 + index * 0.4)
		enter.Activated:Connect(function()
			Remotes.EnterDungeon:FireServer(index)
			window.Visible = false
		end)
		cards[index] = { info = info, enter = enter, level = level }
	end

	local function refresh()
		if not window.Visible then
			return
		end
		local damage = Stats.damage(player)
		local health = Stats.maxHealth(player)
		mine.Text = `Tu daño <font color="#ff9a6a">{Format.multiplier(damage)}</font>  ·  Tu vida <font color="#ff6e6e">{Format.short(health)}</font>`
		for _, card in cards do
			local level = card.level
			local low, high = enemyHits(level)
			local strong = damage >= level.hp
			-- "Aguantas" si el golpe más fuerte no te quita más de media vida.
			local tough = high <= health / 2
			local soft = Ui.SOFT
			card.info.Text = table.concat({
				`<font size="14" color="{soft}">Daño recomendado</font>`,
				`<font size="25" color="{hex(if strong then GOOD else BAD)}">{Format.short(level.hp)}</font>`,
				`<font size="14" color="{soft}">Golpe enemigo</font>`,
				`<font size="21" color="{hex(if tough then GOOD else BAD)}">{Format.short(low)} a {Format.short(high)}</font>`,
				`<font size="14" color="{soft}">Premios</font>`,
				`<font size="17" color="{hex(GOLD)}">Armadura {level.set}</font>`,
				`<font color="{soft}">Stats</font> x{Format.short(level.power)}`,
				`<font color="{soft}">Calidad</font> x{Format.short(level.qualityLuck)}`,
				`<font color="{soft}">Cristales</font> x{Format.short(level.loot)}`,
			}, "\n")
			-- Se puede entrar siempre; el color avisa de si vas justo.
			card.enter.BackgroundColor3 = if strong and tough then Ui.COLORS.green elseif strong or tough then Ui.COLORS.orange else Ui.COLORS.red
		end
	end
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		refresh()
		if window.Visible then
			-- Se abre enseñando la dificultad más alta para la que te llega el daño (con una más fácil a su izquierda).
			local best = 1
			for index, level in Config.Dungeons do
				if Stats.damage(player) >= level.hp then
					best = index
				end
			end
			row.CanvasPosition = Vector2.new(math.max(0, (best - 2) * (CARD_WIDTH + CARD_GAP)), 0)
		end
	end)
	player.AttributeChanged:Connect(refresh)

	-- Abrir junto al portal y cerrar al alejarse.
	local openAt: Vector3? = nil
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Shop") == "dungeons" then
			local parent = prompt.Parent
			openAt = if parent and parent:IsA("BasePart") then parent.Position else nil
			Ui.toggle("Dungeons")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if openAt and root and window.Visible and (root.Position - openAt).Magnitude > CLOSE_DISTANCE then
				window.Visible = false
				openAt = nil
			end
		end
	end)
end

-- Pelea automática ------------------------------------------------------------------------

local autoFight = false -- lo enciende el botón "Auto" del panel; se queda puesto entre partidas

-- Mientras está encendido y hay partida: va hacia el enemigo más cercano, lo encara y le pega. Es el mismo
-- espadazo que un clic (SwordController.swing), así que el servidor lo valida igual.
local function runAutoFight()
	local moving = false
	while true do
		task.wait(0.1)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local active = autoFight and (player:GetAttribute("Dungeon") or 0) > 0
		if not active or not root or not humanoid or humanoid.Health <= 0 then
			if moving and root and humanoid then
				humanoid:MoveTo(root.Position)
			end
			moving = false
			continue
		end
		local nearest: BasePart? = nil
		local best = math.huge
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("BasePart") and enemy.Parent then
				local distance = (enemy.Position - root.Position).Magnitude - enemy.Size.X / 2
				if distance < best then
					nearest, best = enemy, distance
				end
			end
		end
		if not nearest then
			continue
		end
		local copy = Stats.equipped(player)
		local reach = Config.BaseRange + Config.Swords[copy.sword].bladeLength * Permanent.scale(copy)
		local target = Vector3.new(nearest.Position.X, root.Position.Y, nearest.Position.Z)
		if best > reach * 0.7 then
			moving = true
			humanoid:MoveTo(target)
		elseif moving then
			moving = false
			humanoid:MoveTo(root.Position)
		end
		if best <= reach then
			-- Quieto no gira solo: se le encara al enemigo para que el golpe le dé.
			if (target - root.Position).Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, target)
			end
			SwordController.swing()
		end
	end
end

-- Panel de la partida --------------------------------------------------------------------

local function buildRunPanel()
	local panel = Instance.new("Frame")
	panel.Name = "DungeonRun"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 84)
	panel.Size = UDim2.fromOffset(640, 104)
	panel.BackgroundColor3 = WHITE
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = Ui.hud()
	Ui.round(panel, 14)
	Ui.stroke(panel, BLACK, 4)
	Ui.panel(panel, Color3.fromRGB(48, 44, 92), Ui.COLORS.purple)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = Ui.label(panel, 26)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(20, 6)
	title.Size = UDim2.new(1, -370, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local detail = Ui.label(panel, 18)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(20, 38)
	detail.Size = UDim2.new(1, -370, 0, 24)
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local leave = Ui.button(panel, "Salir", Ui.COLORS.red)
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -12, 0, 10)
	leave.Size = UDim2.fromOffset(104, 48)
	leave.TextSize = 22
	leave.Activated:Connect(function()
		Remotes.LeaveDungeon:FireServer()
	end)

	-- Auto (el personaje pelea solo) y Repetir (al superarla empieza otra): para dejarlo sin tocar.
	local autoButton = Ui.button(panel, "", Ui.COLORS.gray)
	autoButton.Name = "Auto"
	autoButton.AnchorPoint = Vector2.new(1, 0)
	autoButton.Position = UDim2.new(1, -124, 0, 10)
	autoButton.Size = UDim2.fromOffset(108, 48)
	autoButton.TextSize = 19
	local loopButton = Ui.button(panel, "", Ui.COLORS.gray)
	loopButton.Name = "Loop"
	loopButton.AnchorPoint = Vector2.new(1, 0)
	loopButton.Position = UDim2.new(1, -240, 0, 10)
	loopButton.Size = UDim2.fromOffset(118, 48)
	loopButton.TextSize = 19
	local function paintToggles()
		local loop = player:GetAttribute("DungeonLoop") == true
		autoButton.Text = if autoFight then "Auto: SÍ" else "Auto: NO"
		autoButton.BackgroundColor3 = if autoFight then Ui.COLORS.green else Ui.COLORS.gray
		loopButton.Text = if loop then "Repetir: SÍ" else "Repetir: NO"
		loopButton.BackgroundColor3 = if loop then Ui.COLORS.green else Ui.COLORS.gray
	end
	autoButton.Activated:Connect(function()
		autoFight = not autoFight
		paintToggles()
	end)
	loopButton.Activated:Connect(function()
		Remotes.SetDungeonLoop:FireServer(player:GetAttribute("DungeonLoop") ~= true)
	end)
	player:GetAttributeChangedSignal("DungeonLoop"):Connect(paintToggles)
	paintToggles()

	-- Tu vida.
	local track = Instance.new("Frame")
	track.Name = "Health"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 4, 1, -10)
	track.Size = UDim2.new(1, -36, 0, 24)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.BorderSizePixel = 0
	track.Parent = panel
	Ui.round(track, 10)
	Ui.stroke(track, BLACK, 2.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Ui.round(fill, 10)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90
	fillGradient.Parent = fill
	local healthText = Ui.label(track, 16)
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.ZIndex = 3

	local function paintHealth()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local health = if humanoid then math.max(humanoid.Health, 0) else 0
		local maxHealth = if humanoid then math.max(humanoid.MaxHealth, 1) else 1
		local ratio = math.clamp(health / maxHealth, 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()
		-- De verde a rojo según baja.
		local color = BAD:Lerp(GOOD, ratio)
		fillGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.25))
		healthText.Text = `{Format.short(math.ceil(health))} / {Format.short(maxHealth)}`
	end
	local healthConnections = {}
	local function watch(character: Model?)
		for _, connection in healthConnections do
			connection:Disconnect()
		end
		table.clear(healthConnections)
		local humanoid = character and character:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			table.insert(healthConnections, humanoid.HealthChanged:Connect(paintHealth))
			table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(paintHealth))
		end
		paintHealth()
	end
	player.CharacterAdded:Connect(watch)
	task.spawn(watch, player.Character)

	local shownWave = -1
	local function refresh()
		local index = player:GetAttribute("Dungeon") or 0
		local level = Config.Dungeons[index]
		local inside = level ~= nil
		if inside and not panel.Visible then
			-- Entra con un rebote.
			panel.Visible = true
			shownWave = -1
			if not Performance.get() then
				scale.Scale = 0.7
				TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			paintHealth()
		elseif not inside then
			panel.Visible = false
			return
		end
		local wave = player:GetAttribute("DungeonWave") or 0
		local waves = player:GetAttribute("DungeonWaves") or #cfg.Waves
		title.Text = `<font color="{hex(level.color:Lerp(WHITE, 0.25))}">{level.name}</font>  ·  Oleada {math.max(wave, 1)}/{waves}`
		local left = math.max(0, (player:GetAttribute("DungeonEnds") or 0) - workspace:GetServerTimeNow())
		local enemies = player:GetAttribute("DungeonLeft") or 0
		detail.Text = `<font color="{Ui.SOFT}">Enemigos</font> {if wave == 0 then "..." else tostring(enemies)}  <font color="{Ui.SOFT}">·  Tiempo</font> <font color="{hex(if left < 30 then BAD else WHITE)}">{math.floor(left / 60)}:{string.format("%02d", math.floor(left % 60))}</font>`
		if wave ~= shownWave and wave > 0 then
			shownWave = wave
			Sfx.play("roll")
			Ui.toast(if wave >= waves then "¡Oleada final: el jefe!" else `Oleada {wave} de {waves}`, level.color)
		end
	end
	for _, attribute in { "Dungeon", "DungeonWave", "DungeonLeft", "DungeonEnds" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	task.spawn(function()
		-- El reloj se actualiza cada medio segundo mientras dura la partida.
		while true do
			task.wait(0.5)
			if panel.Visible then
				refresh()
			end
		end
	end)
	refresh()
end

-- Golpes recibidos y resultado -----------------------------------------------------------

local function buildFeedback()
	local gui = Ui.screen()

	local hurt = Instance.new("Frame")
	hurt.Name = "DungeonHurt"
	hurt.Size = UDim2.fromScale(1, 1)
	hurt.BackgroundColor3 = Color3.fromRGB(255, 40, 50)
	hurt.BackgroundTransparency = 1
	hurt.BorderSizePixel = 0
	hurt.Active = false
	hurt.ZIndex = Z_HURT
	hurt.Parent = gui
	-- Más rojo en los bordes que en el centro.
	local vignette = Instance.new("UIGradient")
	vignette.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.85), NumberSequenceKeypoint.new(1, 0) })
	vignette.Parent = hurt

	local card = Instance.new("Frame")
	card.Name = "DungeonResult"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.4)
	card.Size = UDim2.fromOffset(460, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = Z_RESULT
	card.Parent = gui
	Ui.round(card, 16)
	Ui.stroke(card, BLACK, 5)
	Ui.gradient(card, Color3.fromRGB(66, 62, 124), Color3.fromRGB(24, 24, 50), 90)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
	local title = Ui.label(card, 34)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 42)
	title.ZIndex = Z_RESULT
	local subtitle = Ui.label(card, 20)
	subtitle.LayoutOrder = 2
	subtitle.Size = UDim2.new(1, 0, 0, 26)
	subtitle.ZIndex = Z_RESULT
	local loot = Ui.label(card, 20)
	loot.LayoutOrder = 3
	loot.Size = UDim2.new(1, 0, 0, 0)
	loot.AutomaticSize = Enum.AutomaticSize.Y
	loot.TextWrapped = true
	loot.LineHeight = 1.15
	loot.ZIndex = Z_RESULT

	local token = 0
	Remotes.DungeonEvent.OnClientEvent:Connect(function(kind: string, data)
		if kind == "hurt" then
			Sfx.play("hit", 0.9)
			if not Performance.get() then
				hurt.BackgroundTransparency = 0.55
				TweenService:Create(hurt, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			end
		elseif kind == "result" and type(data) == "table" then
			local reason = REASONS[data.reason] or REASONS.left
			local level = Config.Dungeons[data.level]
			title.Text = reason[1]
			title.TextColor3 = reason[2]
			subtitle.Text = if level then `<font color="{Ui.SOFT}">Mazmorra</font> <font color="{hex(level.color:Lerp(WHITE, 0.25))}">{level.name}</font>` else ""
			local lines = {}
			local summary = if type(data.loot) == "table" then data.loot else {}
			for _, name in Config.ItemOrder do
				local amount = summary.items and summary.items[name]
				if amount then
					table.insert(lines, `<font color="{hex(Config.Items[name].color)}">+{Format.short(amount)} {Config.Items[name].name}</font>`)
				end
			end
			for _, piece in summary.armor or {} do
				local quality = Config.Armor.Qualities[piece.quality]
				if quality then
					table.insert(lines, `<font color="{hex(quality.color)}">{piece.name} · {quality.name}</font>{if piece.kept then "" else ` <font color="{Ui.SOFT}">(desmontada)</font>`}`)
				end
			end
			loot.Text = if #lines > 0 then table.concat(lines, "\n") else `<font color="{Ui.SOFT}">Sin premios esta vez.</font>`
			Sfx.play(if data.won then "win" else "error")
			card.Visible = true
			if not Performance.get() then
				cardScale.Scale = 0.6
				TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			token += 1
			local current = token
			task.delay(6, function()
				if current == token then
					card.Visible = false
				end
			end)
		end
	end)
end

-- Portal del hub -------------------------------------------------------------------------

-- Esquirlas que dan vueltas delante del disco y chispas que salen de él (solo en este cliente).
local function animatePortal(swirl: BasePart)
	local shards = {}
	local folder = Instance.new("Folder")
	folder.Name = "PortalFx"
	folder.Parent = workspace
	for index = 1, 8 do
		local shard = Instance.new("Part")
		shard.Name = "Shard"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Size = Vector3.one * (0.5 + (index % 3) * 0.25)
		shard.Color = swirl.Color:Lerp(WHITE, 0.25 + (index % 2) * 0.3)
		shard.Material = Enum.Material.Neon -- piezas pequeñas
		shard.Parent = folder
		shards[index] = shard
	end
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(swirl.Color:Lerp(WHITE, 0.4))
	sparks.LightEmission = 0.7
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(1, 1.8)
	sparks.Rate = 10
	sparks.Speed = NumberRange.new(1.5, 3)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = swirl
	swirl.Destroying:Connect(function()
		folder:Destroy()
	end)

	local radius = swirl.Size.Y / 2 * 0.72
	RunService.RenderStepped:Connect(function()
		if Performance.get() or not swirl.Parent then
			return
		end
		local now = os.clock()
		for index, shard in shards do
			-- El eje del cilindro es X: se gira alrededor de él, en dos anillos que van en sentidos contrarios.
			local inner = index % 2 == 0
			local turn = now * (if inner then -1.3 else 0.9) + index * math.pi / 4
			local arm = radius * (if inner then 0.55 else 1) + math.sin(now * 2 + index) * 0.25
			shard.CFrame = swirl.CFrame * CFrame.Angles(turn, 0, 0) * CFrame.new(0.6, arm, 0) * CFrame.Angles(now * 2, now * 1.3, 0)
		end
	end)
end

function Dungeons.start()
	buildMenu()
	buildRunPanel()
	buildFeedback()
	task.spawn(runAutoFight)
	for _, swirl in CollectionService:GetTagged("PortalSwirl") do
		task.spawn(animatePortal, swirl)
	end
	CollectionService:GetInstanceAddedSignal("PortalSwirl"):Connect(animatePortal)
end

return Dungeons
