-- Menú de mazmorras (pedido por el usuario: bajar al lobby y buscar la sala a pie era muy poco intuitivo para un
-- jugador nuevo). Lo abre el botón "Mazmorras" de la barra de transporte (client/Hud). Ventana Hud.DungeonMenu:
--   Body.Hero            la zona elegida, en grande, con lo que suelta y sus botones Solo y Party. Al abrir es la
--                        recomendada para tu daño (la más alta cuyo daño recomendado ya tienes)
--   Body.Grid.Zone_<n>   las zonas de Config.Dungeons en orden, de la más fácil a la más difícil: pulsar una la pone en
--                        la tarjeta grande (pedido por el usuario, para ver lo de todas). Las que aún te quedan grandes
--                        salen apagadas y con el daño en rojo (se puede entrar igual, salvo las de "minDamage")
--   Body.Bar.Lobby       bajar al lobby a pie, como antes
-- "Solo" pide la partida al servidor sin pasar por la sala (PartyRequest "quick"); "Party" pide que te lleven delante del
-- altar de esa sala (Teleport "room"), y allí client/Party abre la ventana de grupo de siempre. Todo lo valida el
-- servidor: aquí solo se pide.
-- Capas: todo va en la capa por defecto (la interfaz ordena el ZIndex globalmente), así que manda el orden en que se
-- crean las piezas: fondo, retrato, apagado, textos y botones.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonInfo = require(ReplicatedStorage.Shared.DungeonInfo)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DungeonCard = require(script.Parent.DungeonCard)
local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)

local DungeonMenu = {}

local NAME = "DungeonMenu"
local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)
local SURFACE = Color3.fromRGB(46, 50, 96)
local REFRESH = 1 -- segundos entre repasos con la ventana abierta (el daño cambia al equipar o sacar armas)

-- Medidas (píxeles de diseño: la ventana entera se encoge con su UIScale).
local SIZE = Vector2.new(940, 640)
local PAD = 10
local HERO_HEIGHT = 172
local HEAD_HEIGHT = 30 -- rótulo "Todas las mazmorras"
local BAR_HEIGHT = 48
local COLUMNS = 4
local GAP = 10
local CARD = Vector2.new(212, 78) -- tres filas de cuatro: las doce zonas caben sin deslizar

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Texto que se encoge hasta `min` si no cabe.
local function fit(label: TextLabel | TextButton, max: number, min: number)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min
	limit.Parent = label
end

-- Color del retrato de una zona: el de su jefe, como en la ventana de grupo.
local function faceColor(level): Color3
	local theme = Config.DungeonThemes[level.id]
	local boss = theme and theme.enemies and theme.enemies.boss
	return (boss and boss.color) or level.color
end

-- La zona más alta cuyo daño recomendado ya tiene el jugador (la primera si aún no le llega para ninguna).
local function recommended(damage: number): number
	local best = 1
	for index, level in Config.Dungeons do
		if damage >= level.hp and not DungeonInfo.lock(index, damage) then
			best = index
		end
	end
	return best
end

local function playSolo(zone: number)
	Remotes.PartyRequest:FireServer("quick", zone)
end

local function playParty(zone: number)
	Remotes.Teleport:FireServer("room", zone)
end

-- Marco cuadrado con el retrato de la zona.
local function portrait(parent: Instance, position: UDim2, side: number, level): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Portrait"
	frame.Position = position
	frame.Size = UDim2.fromOffset(side, side)
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.gradient(frame, level.color:Lerp(BLACK, 0.45), level.color:Lerp(BLACK, 0.75), 90)
	return frame
end

-- Tarjeta grande de la zona recomendada. Devuelve su repaso (zona, daño).
local function buildHero(body: Frame): (number, number) -> ()
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.Position = UDim2.fromOffset(PAD, PAD)
	hero.Size = UDim2.new(1, -PAD * 2, 0, HERO_HEIGHT)
	hero.BackgroundColor3 = WHITE
	hero.BorderSizePixel = 0
	hero.Parent = body
	Ui.round(hero, 14)
	local border = Ui.stroke(hero, GOLD, 4)
	-- El fondo se repinta con el color de la zona: un marco propio, para no rehacer el Ui.panel.
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = WHITE
	tint.BorderSizePixel = 0
	tint.Parent = hero
	Ui.round(tint, 14)
	local tintColors = Instance.new("UIGradient")
	tintColors.Rotation = 90
	tintColors.Parent = tint
	Ui.panel(hero, SURFACE)
	hero.BackgroundTransparency = 1 -- manda el tinte; del panel se quedan el brillo y el canto

	local side = HERO_HEIGHT - 24
	local holder = Instance.new("Frame")
	holder.Name = "Portrait"
	holder.Position = UDim2.fromOffset(12, 12)
	holder.Size = UDim2.fromOffset(side, side)
	holder.BackgroundColor3 = WHITE
	holder.BorderSizePixel = 0
	holder.Parent = hero
	Ui.round(holder, 12)
	Ui.stroke(holder, BLACK, 3)
	local holderColors = Instance.new("UIGradient")
	holderColors.Rotation = 90
	holderColors.Parent = holder

	local left = side + 26
	local tag = Ui.label(hero, 20)
	tag.Name = "Tag"
	tag.Position = UDim2.fromOffset(left, 10)
	tag.Size = UDim2.fromOffset(300, 24)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.TextColor3 = GOLD
	tag.Text = Ui.upper(Lang.t(nil, "Recommended for you"))
	fit(tag, 20, 12)

	local title = Ui.label(hero, 34)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(left, 36)
	title.Size = UDim2.fromOffset(300, 66)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	fit(title, 34, 16)

	local damageText = Ui.label(hero, 20)
	damageText.Name = "Damage"
	damageText.Position = UDim2.fromOffset(left, 106)
	damageText.Size = UDim2.fromOffset(300, 26)
	damageText.TextXAlignment = Enum.TextXAlignment.Left
	fit(damageText, 20, 12)

	local hint = Ui.label(hero, 16)
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(left, 134)
	hint.Size = UDim2.fromOffset(300, 24)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	fit(hint, 16, 11)

	-- Lo que suelta una partida (DungeonInfo.rewards).
	local loot = Instance.new("Frame")
	loot.Name = "Loot"
	loot.Position = UDim2.fromOffset(left + 308, 12)
	loot.Size = UDim2.fromOffset(220, side)
	loot.BackgroundColor3 = BLACK
	loot.BackgroundTransparency = 0.72
	loot.BorderSizePixel = 0
	loot.Parent = hero
	Ui.round(loot, 10)
	local lootText = Ui.label(loot, 17)
	lootText.Name = "Text"
	lootText.Position = UDim2.fromOffset(10, 6)
	lootText.Size = UDim2.new(1, -20, 1, -12)
	lootText.TextXAlignment = Enum.TextXAlignment.Left
	lootText.TextWrapped = true
	lootText.LineHeight = 1.15
	fit(lootText, 17, 11)

	local solo = Ui.button(hero, Lang.t(nil, "Play solo"), Ui.COLORS.green)
	solo.Name = "Solo"
	solo.AnchorPoint = Vector2.new(1, 0)
	solo.Position = UDim2.new(1, -12, 0, 14)
	solo.Size = UDim2.fromOffset(190, 82)
	solo.TextSize = 28
	Ui.sparkle(solo, 4)
	local party = Ui.button(hero, Lang.t(nil, "With friends"), Ui.COLORS.blue)
	party.Name = "Party"
	party.AnchorPoint = Vector2.new(1, 1)
	party.Position = UDim2.new(1, -12, 1, -14)
	party.Size = UDim2.fromOffset(190, 50)
	party.TextSize = 20

	local shown = 0
	local face: Frame? = nil
	solo.Activated:Connect(function()
		if shown > 0 then
			playSolo(shown)
		end
	end)
	party.Activated:Connect(function()
		if shown > 0 then
			playParty(shown)
		end
	end)

	return function(zone: number, damage: number, best: boolean)
		local level = Config.Dungeons[zone]
		border.Color = if best then GOLD else BLACK
		tag.TextColor3 = if best then GOLD else WHITE
		tag.Text = Ui.upper(if best then Lang.t(nil, "Recommended for you") else Lang.t(nil, "Dungeon {n}", { n = zone }))
		if shown ~= zone then
			shown = zone
			tintColors.Color = ColorSequence.new(level.color:Lerp(SURFACE, 0.45), level.color:Lerp(BLACK, 0.72))
			holderColors.Color = ColorSequence.new(level.color:Lerp(BLACK, 0.4), level.color:Lerp(BLACK, 0.75))
			title.Text = Ui.upper(Lang.t(nil, level.name))
			if face then
				face:Destroy()
			end
			face = DungeonCard.face(holder, faceColor(level))
			if not Performance.get() then
				TweenService:Create(face :: Frame, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.44), Rotation = 4 }):Play()
			end
			local lines = { `<font color="{Ui.SOFT}">{Lang.t(nil, "Loot per run")}</font>` }
			for _, reward in DungeonInfo.rewards(zone) do
				table.insert(lines, `<font color="{hex(reward.color)}">{reward.text}</font>`)
			end
			lootText.Text = table.concat(lines, "\n")
		end
		local ready = damage >= level.hp
		damageText.Text = `<font color="{Ui.SOFT}">{Lang.t(nil, "Recommended damage")}</font>  <font color="{hex(if ready then GOOD else BAD)}">{Format.short(level.hp)}</font>`
		hint.Text = `<font color="{Ui.SOFT}">{Lang.t(nil, if ready then "You're ready for this one!" else "Get stronger weapons first")}</font>`
	end
end

-- Tarjeta pequeña de una zona de la lista: al pulsarla, la tarjeta grande pasa a enseñar esa zona. Devuelve su repaso
-- (daño, ¿es la recomendada?, ¿es la elegida?).
local function buildCard(grid: Instance, zone: number, level, onPick: (number) -> ()): (number, boolean, boolean) -> ()
	local card = Instance.new("TextButton")
	card.Name = "Zone_" .. zone
	card.LayoutOrder = zone
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Parent = grid
	Ui.round(card, 12)
	local border = Ui.stroke(card, BLACK, 3)
	Ui.panel(card, SURFACE:Lerp(level.color, 0.18), level.color)
	Ui.pressable(card, 1.03)
	card.Activated:Connect(function()
		onPick(zone)
	end)

	local frame = portrait(card, UDim2.fromOffset(14, 8), 54, level)
	DungeonCard.face(frame, faceColor(level))

	local title = Ui.label(card, 18)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(76, 6)
	title.Size = UDim2.new(1, -84, 0, 38)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	title.Text = Lang.t(nil, level.name)
	fit(title, 18, 10)

	-- Apagado de las zonas que aún te quedan grandes: tapa el retrato y el nombre, no el daño ni los botones.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = BLACK
	dim.BackgroundTransparency = 0.5
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = card
	Ui.round(dim, 12)

	-- Número de la zona, sobre la esquina del retrato: la lista es una escalera.
	local number = Instance.new("Frame")
	number.Name = "Number"
	number.Position = UDim2.fromOffset(6, 2)
	number.Size = UDim2.fromOffset(26, 24)
	number.Parent = card
	Ui.pill(number, level.color:Lerp(BLACK, 0.2), 8)
	local digits = Ui.label(number, 15)
	digits.Size = UDim2.fromScale(1, 1)
	digits.Text = tostring(zone)

	local damageText = Ui.label(card, 16)
	damageText.Name = "Damage"
	damageText.Position = UDim2.fromOffset(76, 44)
	damageText.Size = UDim2.new(1, -84, 0, 20)
	damageText.TextXAlignment = Enum.TextXAlignment.Left
	fit(damageText, 16, 10)

	return function(damage: number, best: boolean, selected: boolean)
		local lock = DungeonInfo.lock(zone, damage)
		local ready = damage >= level.hp and not lock
		dim.Visible = not ready and not selected
		border.Color = if selected then WHITE elseif best then GOLD else BLACK
		border.Thickness = if selected or best then 4 else 3
		damageText.Text = if lock
			then `<font color="{hex(BAD)}">{lock}</font>`
			else `<font color="{Ui.SOFT}">{Lang.t(nil, "Damage")}</font> <font color="{hex(if ready then GOOD else BAD)}">{Format.short(level.hp)}</font>`
	end
end

function DungeonMenu.start()
	local window, body = Ui.window(NAME, Lang.t(nil, "Dungeons"), SIZE, function(parent)
		Ui.image(parent, "mazmorras")
	end)

	local paintHero = buildHero(body)

	local heading = Ui.label(body, 20)
	heading.Name = "Heading"
	heading.Position = UDim2.fromOffset(PAD + 4, PAD + HERO_HEIGHT + 6)
	heading.Size = UDim2.new(1, -PAD * 2 - 8, 0, HEAD_HEIGHT)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = Ui.upper(Lang.t(nil, "All dungeons"))

	local top = PAD + HERO_HEIGHT + 6 + HEAD_HEIGHT + 4
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(PAD, top)
	grid.Size = UDim2.new(1, -PAD * 2, 1, -top - BAR_HEIGHT - PAD * 2)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = body
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD.X, CARD.Y)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.FillDirectionMaxCells = COLUMNS
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local cards = {}
	local selected = 0 -- zona que enseña la tarjeta grande (0 = la recomendada)
	local refresh
	for zone, level in Config.Dungeons do
		cards[zone] = buildCard(grid, zone, level, function(picked)
			selected = picked
			refresh()
		end)
	end

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, PAD, 1, -PAD)
	bar.Size = UDim2.new(1, -PAD * 2, 0, BAR_HEIGHT)
	bar.BackgroundTransparency = 1
	bar.Parent = body
	local tip = Ui.label(bar, 18)
	tip.Name = "Tip"
	tip.Position = UDim2.fromOffset(4, 0)
	tip.Size = UDim2.new(1, -250, 1, 0)
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.Text = `<font color="{Ui.SOFT}">{Lang.t(nil, "Green damage: you're ready. Red: too hard for now.")}</font>`
	fit(tip, 18, 11)
	local lobby = Ui.button(bar, Lang.t(nil, "Go to the lobby"), Ui.COLORS.purple)
	lobby.Name = "Lobby"
	lobby.AnchorPoint = Vector2.new(1, 0.5)
	lobby.Position = UDim2.fromScale(1, 0.5)
	lobby.Size = UDim2.fromOffset(230, BAR_HEIGHT - 4)
	lobby.TextSize = 18
	fit(lobby, 18, 11)
	lobby.Activated:Connect(function()
		Remotes.Teleport:FireServer("dungeon")
	end)

	refresh = function()
		local damage = Stats.damage(player)
		local best = recommended(damage)
		local shown = if selected > 0 then selected else best
		paintHero(shown, damage, shown == best)
		for zone, paint in cards do
			paint(damage, zone == best, zone == shown)
		end
	end

	-- Con la ventana abierta se repasa cada segundo; al abrirla, vuelve a enseñar la zona recomendada.
	local token = 0
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		token += 1
		if not window.Visible then
			return
		end
		local mine = token
		selected = 0
		refresh()
		task.spawn(function()
			while token == mine do
				task.wait(REFRESH)
				if token == mine then
					refresh()
				end
			end
		end)
	end)

	-- Al entrar en una partida (Solo), la ventana se quita.
	player:GetAttributeChangedSignal("Dungeon"):Connect(function()
		if (player:GetAttribute("Dungeon") or 0) ~= 0 then
			Ui.close(window)
		end
	end)
end

return DungeonMenu
