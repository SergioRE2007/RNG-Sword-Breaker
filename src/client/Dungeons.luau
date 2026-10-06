-- Mazmorras en el cliente, durante la partida: panel (zona, oleada, enemigos, tiempo y vida), tira con la vida de
-- los compañeros de grupo y cartel con el resultado. Se entra por las salas del lobby (client/Party).
-- Todo lo decide el servidor (server/Dungeons): aquí solo se pide salir y se pinta lo que publica en los atributos
-- Dungeon, DungeonRun (los del mismo grupo comparten partida), DungeonWave, DungeonWaves, DungeonLeft y DungeonEnds.
-- Para dejarlo solo (AFK): "Repetir" (DungeonLoop, lo lleva el servidor si lideras: al superarla empieza otra igual) y
-- "Auto" (aquí: el personaje anda hacia el enemigo más cercano y le pega, con los mismos espadazos que un clic).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Party = require(script.Parent.Party)
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
local PANEL_WIDTH = 720 -- panel de la partida

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
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 104)
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
	title.Size = UDim2.new(1, -390, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local detail = Ui.label(panel, 18)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(20, 38)
	detail.Size = UDim2.new(1, -390, 0, 24)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextTruncate = Enum.TextTruncate.AtEnd

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
		-- Repetir lo decide el líder del grupo.
		loopButton.Visible = Party.isLeader()
	end
	Party.Changed:Connect(paintToggles)
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
		title.Text = `<font color="{hex(level.color:Lerp(WHITE, 0.25))}">{level.name}</font>`
		local left = math.max(0, (player:GetAttribute("DungeonEnds") or 0) - workspace:GetServerTimeNow())
		local enemies = player:GetAttribute("DungeonLeft") or 0
		detail.Text = `<font color="{Ui.SOFT}">Oleada</font> {math.max(wave, 1)}/{waves}  <font color="{Ui.SOFT}">·  Enemigos</font> {if wave == 0 then "..." else tostring(enemies)}  <font color="{Ui.SOFT}">·</font> <font color="{hex(if left < 30 then BAD else WHITE)}">{math.floor(left / 60)}:{string.format("%02d", math.floor(left % 60))}</font>`
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

-- Equipo ---------------------------------------------------------------------------------

-- Los compañeros de la partida (los que llevan el mismo DungeonRun): su nombre y su vida, bajo el panel.
local function buildTeam()
	local list = Instance.new("Frame")
	list.Name = "DungeonTeam"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.new(0.5, 0, 0, 84 + 104 + 8)
	list.Size = UDim2.fromOffset(300, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Visible = false
	list.Parent = Ui.hud()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = list

	local rows: { [Player]: { frame: Frame, fill: Frame, gradient: UIGradient } } = {}
	local function makeRow(mate: Player)
		local row = Instance.new("Frame")
		row.Name = mate.Name
		row.Size = UDim2.fromOffset(300, 30)
		row.BackgroundColor3 = WHITE
		row.BorderSizePixel = 0
		row.Parent = list
		Ui.round(row, 9)
		Ui.stroke(row, BLACK, 3)
		Ui.panel(row, Color3.fromRGB(44, 46, 92))
		local name = Ui.label(row, 16)
		name.Position = UDim2.fromOffset(8, 0)
		name.Size = UDim2.new(0.42, -8, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = mate.DisplayName
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -8, 0.5, 0)
		track.Size = UDim2.new(0.58, -12, 0, 14)
		track.BackgroundColor3 = Ui.COLORS.dark
		track.BorderSizePixel = 0
		track.Parent = row
		Ui.round(track, 7)
		Ui.stroke(track, BLACK, 2)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = WHITE
		fill.BorderSizePixel = 0
		fill.Parent = track
		Ui.round(fill, 7)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Parent = fill
		return { frame = row, fill = fill, gradient = gradient }
	end

	local function update()
		local run = player:GetAttribute("DungeonRun") or 0
		local present: { [Player]: boolean } = {}
		if run > 0 and (player:GetAttribute("Dungeon") or 0) > 0 then
			for _, mate in Players:GetPlayers() do
				if mate ~= player and mate:GetAttribute("DungeonRun") == run then
					present[mate] = true
					local row = rows[mate]
					if not row then
						row = makeRow(mate)
						rows[mate] = row
					end
					local humanoid = mate.Character and mate.Character:FindFirstChildOfClass("Humanoid")
					local ratio = if humanoid then math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1) else 0
					row.fill.Size = UDim2.fromScale(ratio, 1)
					local color = BAD:Lerp(GOOD, ratio)
					row.gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.25))
				end
			end
		end
		for mate, row in rows do
			if not present[mate] then
				row.frame:Destroy()
				rows[mate] = nil
			end
		end
		list.Visible = next(rows) ~= nil
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			update()
		end
	end)
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

function Dungeons.start()
	buildRunPanel()
	buildTeam()
	buildFeedback()
	task.spawn(runAutoFight)
end

return Dungeons
