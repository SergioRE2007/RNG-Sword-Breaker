-- Sala de grupo de las mazmorras en el cliente. Al pulsar el altar de una sala del lobby se abre la ventana: a la
-- izquierda la tarjeta de la zona (descripción, premios y si tu daño y tu vida van justos), a la derecha o los grupos
-- abiertos de esa sala (con "Crear grupo" y "Entrar solo") o, si ya estás en uno, sus jugadores, las opciones, "Invitar",
-- "Listo" y, para el líder, "Iniciar". También el aviso de invitación y la cuenta atrás.
-- Todo lo decide el servidor (server/Party): aquí se pide con PartyRequest y se pinta lo que llega por PartyState.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonInfo = require(ReplicatedStorage.Shared.DungeonInfo)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DungeonCard = require(script.Parent.DungeonCard)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Party = {}

local player = Players.LocalPlayer
local cfg = Config.Party
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 90)
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)

-- Capas (la interfaz ordena el ZIndex globalmente; valores absolutos de este módulo).
local Z_COUNT = 30 -- cuenta atrás, por encima de la ventana
local Z_INVITE = 70 -- aviso de invitación, por encima de todo lo demás

local state: { [string]: any }? = nil -- el último PartyState
local pendingZone: number? = nil -- sala que se acaba de pedir abrir (hasta que llega la respuesta del servidor)
local changed = Instance.new("BindableEvent")
Party.Changed = changed.Event

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- ¿Lideras tu grupo (o no tienes ninguno)? Lo usa el panel de la partida para enseñar "Repetir".
function Party.isLeader(): boolean
	local mine = state and state.mine
	return mine == nil or mine.leader == player.UserId
end

local function request(action: string, a: any?, b: any?)
	Remotes.PartyRequest:FireServer(action, a, b)
end

-- Barra de desplazamiento vertical para listas.
local function scrollList(parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- Fila con profundidad (nombre, cosas a la derecha las pone quien llama).
local function row(parent: Instance, order: number, height: number, accent: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, Color3.fromRGB(52, 56, 104), accent)
	return frame
end

local function chip(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor or Vector2.zero
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, 10)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, Color3.fromRGB(40, 42, 84):Lerp(color, 0.35))
	local label = Ui.label(frame, 20)
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color:Lerp(WHITE, 0.2)
	return label
end

-- Ventana ----------------------------------------------------------------------------------------------------------

local function buildWindow()
	local window, body = Ui.window("Party", "Sala de grupo", Vector2.new(940, 600), function(parent)
		Ui.starIcon(parent, Color3.fromRGB(215, 160, 255))
	end)

	-- Tarjeta de la zona (izquierda).
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Position = UDim2.fromOffset(12, 12)
	card.Size = UDim2.new(0, 340, 1, -24)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Parent = body
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(52, 56, 100))

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.Position = UDim2.fromOffset(8, 8)
	head.Size = UDim2.new(1, -16, 0, 58)
	head.BackgroundColor3 = WHITE
	head.BorderSizePixel = 0
	head.Parent = card
	Ui.round(head, 10)
	Ui.stroke(head, BLACK, 3)
	local headGradient = Instance.new("UIGradient")
	headGradient.Rotation = 90
	headGradient.Parent = head
	local zoneName = Ui.label(head, 26)
	zoneName.Position = UDim2.fromOffset(46, 0)
	zoneName.Size = UDim2.new(1, -92, 1, 0)
	zoneName.TextScaled = true
	zoneName.TextWrapped = true
	local zoneLimit = Instance.new("UITextSizeConstraint")
	zoneLimit.MaxTextSize = 26
	zoneLimit.MinTextSize = 14
	zoneLimit.Parent = zoneName
	local previous = Ui.button(head, "<", Ui.COLORS.blue)
	previous.AnchorPoint = Vector2.new(0, 0.5)
	previous.Position = UDim2.new(0, 6, 0.5, 0)
	previous.Size = UDim2.fromOffset(38, 38)
	previous.TextSize = 24
	local following = Ui.button(head, ">", Ui.COLORS.blue)
	following.AnchorPoint = Vector2.new(1, 0.5)
	following.Position = UDim2.new(1, -6, 0.5, 0)
	following.Size = UDim2.fromOffset(38, 38)
	following.TextSize = 24

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 76)
	portrait.Size = UDim2.fromOffset(130, 130)
	portrait.BackgroundTransparency = 1
	portrait.Parent = card
	local portraitFace: Frame? = nil

	local tagline = Ui.label(card, 20)
	tagline.Position = UDim2.fromOffset(14, 212)
	tagline.Size = UDim2.new(1, -28, 0, 50)
	tagline.TextWrapped = true
	tagline.TextYAlignment = Enum.TextYAlignment.Top
	tagline.TextColor3 = Color3.fromRGB(190, 195, 215)

	local info = Ui.label(card, 22)
	info.Position = UDim2.fromOffset(18, 266)
	info.Size = UDim2.new(1, -36, 1, -278)
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.LineHeight = 1.1

	-- Derecha: o los grupos de la sala, o tu grupo.
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(364, 12)
	right.Size = UDim2.new(1, -376, 1, -24)
	right.Parent = body

	local heading = Ui.label(right, 24)
	heading.Size = UDim2.new(1, 0, 0, 30)
	heading.TextXAlignment = Enum.TextXAlignment.Left

	-- Vista de la sala: grupos abiertos.
	local roomView = Instance.new("Frame")
	roomView.Name = "RoomView"
	roomView.BackgroundTransparency = 1
	roomView.Position = UDim2.fromOffset(0, 38)
	roomView.Size = UDim2.new(1, 0, 1, -38)
	roomView.Parent = right
	local roomList = scrollList(roomView)
	roomList.Size = UDim2.new(1, 0, 1, -92)
	local emptyRoom = Ui.label(roomView, 20)
	emptyRoom.Position = UDim2.fromOffset(0, 80)
	emptyRoom.Size = UDim2.new(1, 0, 0, 60)
	emptyRoom.TextWrapped = true
	emptyRoom.TextColor3 = Color3.fromRGB(190, 195, 215)
	emptyRoom.Text = "No hay grupos abiertos en esta sala.\nCrea uno o entra tú solo."
	local solo = Ui.button(roomView, "Entrar solo", Ui.COLORS.blue)
	solo.AnchorPoint = Vector2.new(0, 1)
	solo.Position = UDim2.new(0, 0, 1, 0)
	solo.Size = UDim2.new(0.42, -6, 0, 66)
	solo.TextSize = 26
	local create = Ui.button(roomView, "Crear grupo", Ui.COLORS.green)
	create.AnchorPoint = Vector2.new(1, 1)
	create.Position = UDim2.new(1, 0, 1, 0)
	create.Size = UDim2.new(0.58, -6, 0, 66)
	create.TextSize = 28
	Ui.sparkle(create, 5)

	-- Vista del grupo: jugadores, opciones y botones.
	local partyView = Instance.new("Frame")
	partyView.Name = "PartyView"
	partyView.BackgroundTransparency = 1
	partyView.Position = UDim2.fromOffset(0, 38)
	partyView.Size = UDim2.new(1, 0, 1, -38)
	partyView.Parent = right
	local slots = Instance.new("Frame")
	slots.Name = "Slots"
	slots.BackgroundTransparency = 1
	slots.Size = UDim2.new(1, 0, 0, 0)
	slots.AutomaticSize = Enum.AutomaticSize.Y
	slots.Parent = partyView
	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.Padding = UDim.new(0, 6)
	slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotsLayout.Parent = slots

	local options = Instance.new("Frame")
	options.Name = "Options"
	options.BackgroundTransparency = 1
	options.AnchorPoint = Vector2.new(0, 1)
	options.Position = UDim2.new(0, 0, 1, -82)
	options.Size = UDim2.new(1, 0, 0, 42)
	options.Parent = partyView
	local loopButton = Ui.button(options, "", Ui.COLORS.gray)
	loopButton.Size = UDim2.new(0.5, -4, 1, 0)
	loopButton.TextSize = 19
	local publicButton = Ui.button(options, "", Ui.COLORS.gray)
	publicButton.AnchorPoint = Vector2.new(1, 0)
	publicButton.Position = UDim2.fromScale(1, 0)
	publicButton.Size = UDim2.new(0.5, -4, 1, 0)
	publicButton.TextSize = 19

	local invite = Ui.button(partyView, "Invitar", Ui.COLORS.blue)
	invite.AnchorPoint = Vector2.new(0, 1)
	invite.Position = UDim2.fromScale(0, 1)
	invite.Size = UDim2.fromOffset(130, 66)
	invite.TextSize = 24
	local leave = Ui.button(partyView, "Salir", Ui.COLORS.red)
	leave.AnchorPoint = Vector2.new(0, 1)
	leave.Position = UDim2.new(0, 140, 1, 0)
	leave.Size = UDim2.fromOffset(110, 66)
	leave.TextSize = 24
	local main = Ui.button(partyView, "", Ui.COLORS.green)
	main.AnchorPoint = Vector2.new(1, 1)
	main.Position = UDim2.fromScale(1, 1)
	main.Size = UDim2.new(1, -262, 0, 66)
	main.TextSize = 28
	Ui.sparkle(main, 5)

	-- Selector de jugadores para invitar (cubre la columna derecha).
	local picker = Instance.new("Frame")
	picker.Name = "InvitePicker"
	picker.Position = UDim2.fromOffset(0, 38)
	picker.Size = UDim2.new(1, 0, 1, -38)
	picker.BackgroundColor3 = WHITE
	picker.BorderSizePixel = 0
	picker.Visible = false
	picker.ZIndex = 10
	picker.Parent = right
	Ui.round(picker, 12)
	Ui.stroke(picker, BLACK, 4)
	Ui.panel(picker, Color3.fromRGB(34, 36, 76))
	local pickerTitle = Ui.label(picker, 22)
	pickerTitle.Position = UDim2.fromOffset(14, 8)
	pickerTitle.Size = UDim2.new(1, -28, 0, 30)
	pickerTitle.TextXAlignment = Enum.TextXAlignment.Left
	pickerTitle.Text = "Invitar a un jugador"
	local pickerList = scrollList(picker)
	pickerList.Position = UDim2.fromOffset(6, 44)
	pickerList.Size = UDim2.new(1, -12, 1, -118)
	local pickerEmpty = Ui.label(picker, 19)
	pickerEmpty.Position = UDim2.fromOffset(0, 90)
	pickerEmpty.Size = UDim2.new(1, 0, 0, 30)
	pickerEmpty.TextColor3 = Color3.fromRGB(190, 195, 215)
	pickerEmpty.Text = "No hay nadie más en el servidor."
	local pickerBack = Ui.button(picker, "Volver", Ui.COLORS.gray)
	pickerBack.AnchorPoint = Vector2.new(0.5, 1)
	pickerBack.Position = UDim2.new(0.5, 0, 1, -10)
	pickerBack.Size = UDim2.fromOffset(180, 50)
	pickerBack.TextSize = 22
	Ui.layer(picker, 10)

	-- Cuenta atrás grande, por encima de todo lo de la ventana.
	local count = Ui.label(body, 140)
	count.AnchorPoint = Vector2.new(0.5, 0.5)
	count.Position = UDim2.fromScale(0.5, 0.5)
	count.Size = UDim2.fromOffset(300, 200)
	count.Visible = false
	count.ZIndex = Z_COUNT
	local countBack = Instance.new("Frame")
	countBack.AnchorPoint = Vector2.new(0.5, 0.5)
	countBack.Position = UDim2.fromScale(0.5, 0.5)
	countBack.Size = UDim2.fromOffset(250, 210)
	countBack.BackgroundColor3 = BLACK
	countBack.BackgroundTransparency = 0.35
	countBack.BorderSizePixel = 0
	countBack.Visible = false
	countBack.ZIndex = Z_COUNT - 1
	countBack.Parent = body
	Ui.round(countBack, 24)

	local zoneShown = 0
	local lastCount = -1

	local function zoneOf(): number?
		local mine = state and state.mine
		if mine then
			return mine.dungeon
		end
		return pendingZone or (state and state.room)
	end

	local function paintCard(zone: number)
		local level = Config.Dungeons[zone]
		if not level then
			return
		end
		headGradient.Color = ColorSequence.new(level.color:Lerp(WHITE, 0.25), level.color:Lerp(BLACK, 0.4))
		zoneName.Text = string.upper(level.name)
		tagline.Text = level.tagline or ""
		local theme = Config.DungeonThemes[level.id]
		if zoneShown ~= zone then
			zoneShown = zone
			if portraitFace then
				portraitFace:Destroy()
			end
			local bossLook = theme and theme.enemies and theme.enemies.boss
			portraitFace = DungeonCard.face(portrait, (bossLook and bossLook.color) or level.color)
			if not Performance.get() and portraitFace then
				TweenService:Create(portraitFace, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.42), Rotation = 4 }):Play()
			end
		end
		local damage = Stats.damage(player)
		local health = Stats.maxHealth(player)
		local low, high = DungeonCard.enemyHits(level)
		local strong = damage >= level.hp
		local tough = high <= health / 2
		local soft = Ui.SOFT
		local lines = {
			`<font color="{soft}">Daño recomendado</font>  <font color="{hex(if strong then GOOD else BAD)}">{Format.short(level.hp)}</font>`,
			`<font color="{soft}">Golpe enemigo</font>  <font color="{hex(if tough then GOOD else BAD)}">{Format.short(low)} a {Format.short(high)}</font>`,
			`<font color="{soft}">Premios</font>`,
		}
		for _, reward in DungeonInfo.rewards(zone) do
			table.insert(lines, `<font color="{hex(reward.color)}">{reward.text}</font>`)
		end
		local waves = if theme and theme.waves then theme.waves else Config.Dungeon.Waves
		table.insert(lines, `<font color="{soft}">{#waves} oleadas · la última con jefe · {math.floor(Config.Dungeon.TimeLimit / 60)} min</font>`)
		info.Text = table.concat(lines, "\n")
		local lock = DungeonInfo.lock(zone, damage)
		if lock then
			info.Text ..= `\n<font color="{hex(BAD)}">{lock}</font>`
		end
	end

	local function paintRoom()
		heading.Text = "Grupos de la sala"
		for _, child in roomList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local parties = state and state.parties or {}
		emptyRoom.Visible = #parties == 0
		for order, other in parties do
			local frame = row(roomList, order, 64, Ui.COLORS.green)
			local label = Ui.label(frame, 22)
			label.Position = UDim2.fromOffset(22, 0)
			label.Size = UDim2.new(1, -190, 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Text = `{other.leader}  <font color="{Ui.SOFT}">{other.size}/{other.max}</font>`
			local join = Ui.button(frame, "Unirse", Ui.COLORS.green)
			join.AnchorPoint = Vector2.new(1, 0.5)
			join.Position = UDim2.new(1, -10, 0.5, 0)
			join.Size = UDim2.fromOffset(140, 46)
			join.TextSize = 22
			join.Activated:Connect(function()
				request("join", other.id)
			end)
		end
		previous.Visible = false
		following.Visible = false
	end

	local function paintParty(mine)
		local isLeader = mine.leader == player.UserId
		heading.Text = `Jugadores  <font color="{Ui.SOFT}">{#mine.members}/{mine.max}</font>`
		previous.Visible = isLeader and mine.state == "lobby"
		following.Visible = isLeader and mine.state == "lobby"
		for _, child in slots:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local allReady = true
		for number = 1, mine.max do
			local member = mine.members[number]
			local frame = row(slots, number, 56, if member and member.userId == mine.leader then GOLD else nil)
			if member then
				if not member.ready then
					allReady = false
				end
				local avatar = Instance.new("ImageLabel")
				avatar.Position = UDim2.fromOffset(16, 6)
				avatar.Size = UDim2.fromOffset(44, 44)
				avatar.BackgroundColor3 = Ui.COLORS.dark
				avatar.BorderSizePixel = 0
				avatar.Image = if member.bot then "" else `rbxthumb://type=AvatarHeadShot&id={member.userId}&w=150&h=150`
				avatar.Parent = frame
				Ui.round(avatar, 22)
				Ui.stroke(avatar, BLACK, 2.5)
				local name = Ui.label(frame, 22)
				name.Position = UDim2.fromOffset(70, 0)
				name.Size = UDim2.new(1, -250, 1, 0)
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.TextTruncate = Enum.TextTruncate.AtEnd
				name.Text = if member.userId == mine.leader then `<font color="{hex(GOLD)}">{member.name}</font>` else member.name
				chip(frame, if member.userId == mine.leader then "LÍDER" else (if member.ready then "LISTO" else "..."), if member.userId == mine.leader then GOLD elseif member.ready then GOOD else Ui.COLORS.gray, UDim2.fromOffset(92, 36), UDim2.new(1, if isLeader and member.userId ~= mine.leader then -56 else -10, 0.5, 0), Vector2.new(1, 0.5))
				if isLeader and member.userId ~= mine.leader and mine.state == "lobby" then
					local kick = Ui.button(frame, "X", Ui.COLORS.red)
					kick.AnchorPoint = Vector2.new(1, 0.5)
					kick.Position = UDim2.new(1, -8, 0.5, 0)
					kick.Size = UDim2.fromOffset(40, 36)
					kick.TextSize = 20
					kick.Activated:Connect(function()
						request("kick", member.userId)
					end)
				end
			else
				local free = Ui.label(frame, 20)
				free.Position = UDim2.fromOffset(22, 0)
				free.Size = UDim2.new(1, -44, 1, 0)
				free.TextXAlignment = Enum.TextXAlignment.Left
				free.TextColor3 = Color3.fromRGB(150, 156, 184)
				free.Text = "Libre"
			end
		end

		-- Opciones (las cambia el líder).
		local function paintOption(button: TextButton, text: string, on: boolean)
			button.Text = text
			button.BackgroundColor3 = if on then Ui.COLORS.green else Ui.COLORS.gray
			button.Interactable = isLeader
		end
		paintOption(loopButton, `Repetir: {if mine.options.loop then "SÍ" else "NO"}`, mine.options.loop)
		paintOption(publicButton, if mine.options.public then "Grupo abierto" else "Solo invitados", mine.options.public)

		-- Botón principal.
		local starting = mine.state == "starting"
		if isLeader then
			main.Text = if starting then "CANCELAR" else "INICIAR"
			main.BackgroundColor3 = if starting then Ui.COLORS.red elseif allReady then Ui.COLORS.green else Ui.COLORS.orange
		else
			local me
			for _, member in mine.members do
				if member.userId == player.UserId then
					me = member
				end
			end
			local ready = me and me.ready
			main.Text = if ready then "QUITAR LISTO" else "¡LISTO!"
			main.BackgroundColor3 = if ready then Ui.COLORS.gray else Ui.COLORS.green
		end
		invite.Visible = isLeader and mine.state == "lobby" and #mine.members < mine.max
	end

	local function render()
		local zone = zoneOf()
		if not zone then
			if window.Visible then
				window.Visible = false
			end
			return
		end
		paintCard(zone)
		local mine = if state then state.mine else nil
		roomView.Visible = mine == nil
		partyView.Visible = mine ~= nil
		if mine then
			paintParty(mine)
		else
			paintRoom()
		end
		-- Cuenta atrás.
		local left = if mine and mine.state == "starting" then math.ceil(mine.countdownEnds - workspace:GetServerTimeNow()) else 0
		count.Visible = left > 0
		countBack.Visible = left > 0
		if left > 0 then
			count.Text = tostring(left)
			if left ~= lastCount then
				lastCount = left
				Sfx.play("tick")
			end
		else
			lastCount = -1
		end
		-- Si ya ha empezado la partida, la ventana sobra.
		if mine and mine.state == "running" and window.Visible then
			window.Visible = false
		end
	end
	-- La cuenta atrás se repinta sola cada poco.
	task.spawn(function()
		while true do
			task.wait(0.2)
			if window.Visible and state and state.mine and state.mine.state == "starting" then
				render()
			end
		end
	end)

	-- Botones.
	previous.Activated:Connect(function()
		local mine = state and state.mine
		if mine then
			request("dungeon", ((mine.dungeon - 2) % #Config.Dungeons) + 1)
		end
	end)
	following.Activated:Connect(function()
		local mine = state and state.mine
		if mine then
			request("dungeon", (mine.dungeon % #Config.Dungeons) + 1)
		end
	end)
	create.Activated:Connect(function()
		local zone = zoneOf()
		if zone then
			request("create", zone)
		end
	end)
	solo.Activated:Connect(function()
		local zone = zoneOf()
		if zone then
			request("solo", zone)
		end
	end)
	leave.Activated:Connect(function()
		request("leave")
		window.Visible = false
	end)
	main.Activated:Connect(function()
		local mine = state and state.mine
		if not mine then
			return
		end
		if mine.leader == player.UserId then
			if mine.state == "starting" then
				request("ready", false)
			else
				request("start")
			end
		else
			local ready = false
			for _, member in mine.members do
				if member.userId == player.UserId then
					ready = member.ready
				end
			end
			request("ready", not ready)
		end
	end)
	loopButton.Activated:Connect(function()
		local mine = state and state.mine
		if mine and mine.leader == player.UserId then
			request("option", "loop", not mine.options.loop)
		end
	end)
	publicButton.Activated:Connect(function()
		local mine = state and state.mine
		if mine and mine.leader == player.UserId then
			request("option", "public", not mine.options.public)
		end
	end)

	-- Invitar: lista de jugadores del servidor, los amigos primero.
	local friends: { [number]: boolean } = {}
	local function rebuildPicker()
		for _, child in pickerList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local others = {}
		for _, other in Players:GetPlayers() do
			if other ~= player then
				table.insert(others, other)
			end
		end
		table.sort(others, function(a, b)
			local fa, fb = friends[a.UserId] == true, friends[b.UserId] == true
			if fa ~= fb then
				return fa
			end
			return a.DisplayName < b.DisplayName
		end)
		pickerEmpty.Visible = #others == 0
		for order, other in others do
			local frame = row(pickerList, order, 58, if friends[other.UserId] then GOLD else Ui.COLORS.blue)
			local name = Ui.label(frame, 22)
			name.Position = UDim2.fromOffset(22, 0)
			name.Size = UDim2.new(1, -180, 1, 0)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = if friends[other.UserId] then `{other.DisplayName}  <font color="{hex(GOLD)}">amigo</font>` else other.DisplayName
			local send = Ui.button(frame, "Invitar", Ui.COLORS.green)
			send.AnchorPoint = Vector2.new(1, 0.5)
			send.Position = UDim2.new(1, -10, 0.5, 0)
			send.Size = UDim2.fromOffset(130, 42)
			send.TextSize = 20
			send.Activated:Connect(function()
				request("invite", other.UserId)
				send.Text = "Enviada"
			end)
		end
		Ui.layer(pickerList, 11) -- por encima del fondo del selector (que va en la capa 10)
	end
	invite.Activated:Connect(function()
		picker.Visible = true
		rebuildPicker()
		-- Los amigos se averiguan aparte (la consulta puede tardar) y la lista se reordena al llegar.
		task.spawn(function()
			for _, other in Players:GetPlayers() do
				if other ~= player and friends[other.UserId] == nil then
					local ok, isFriend = pcall(function()
						return player:IsFriendsWith(other.UserId)
					end)
					friends[other.UserId] = ok and isFriend == true
				end
			end
			if picker.Visible then
				rebuildPicker()
			end
		end)
	end)
	pickerBack.Activated:Connect(function()
		picker.Visible = false
	end)

	-- Estado del servidor.
	Remotes.PartyState.OnClientEvent:Connect(function(payload)
		local hadParty = state ~= nil and state.mine ~= nil
		state = payload
		pendingZone = nil -- el servidor ya ha contestado: si no hay sala ni grupo, la ventana se cierra sola
		local mine = payload and payload.mine
		-- Te han metido en un grupo (invitación aceptada): se abre la ventana.
		if mine and not hadParty and mine.state == "lobby" and not window.Visible then
			Ui.toggle("Party")
		end
		picker.Visible = picker.Visible and mine ~= nil and mine.leader == player.UserId
		render()
		changed:Fire()
	end)

	-- Abrir en el altar y avisar al cerrar.
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			render()
		else
			pendingZone = nil
			picker.Visible = false
			request("close")
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Shop") == "party" then
			local zone = prompt:GetAttribute("Dungeon")
			if type(zone) == "number" then
				-- Se abre ya (con la zona pedida) y el servidor contesta con el estado de la sala o de tu grupo.
				pendingZone = zone
				request("open", zone)
				if not window.Visible then
					Ui.toggle("Party")
				end
			end
		end
	end)
	-- Se cierra sola al alejarte de la sala.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local zone = zoneOf()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if window.Visible and zone and root then
				for _, board in CollectionService:GetTagged("DungeonRoom") do
					if board:GetAttribute("Index") == zone then
						-- El cartel está sobre el arco de la sala: si te alejas mucho de él, la ventana se cierra.
						local distance = (root.Position - Vector3.new(board.Position.X, root.Position.Y, board.Position.Z)).Magnitude
						if distance > cfg.RoomDistance + 60 then
							window.Visible = false
						end
					end
				end
			end
		end
	end)
end

-- Invitación ------------------------------------------------------------------------------------------------------

local function buildInvite()
	local card = Instance.new("Frame")
	card.Name = "PartyInvite"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 150)
	card.Size = UDim2.fromOffset(470, 130)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = Z_INVITE
	card.Parent = Ui.screen()
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(56, 50, 108))
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local text = Ui.label(card, 22)
	text.Position = UDim2.fromOffset(12, 8)
	text.Size = UDim2.new(1, -24, 0, 56)
	text.TextWrapped = true
	local accept = Ui.button(card, "Aceptar", Ui.COLORS.green)
	accept.AnchorPoint = Vector2.new(1, 1)
	accept.Position = UDim2.new(0.5, -6, 1, -12)
	accept.Size = UDim2.fromOffset(180, 48)
	accept.TextSize = 22
	local decline = Ui.button(card, "Rechazar", Ui.COLORS.red)
	decline.AnchorPoint = Vector2.new(0, 1)
	decline.Position = UDim2.new(0.5, 6, 1, -12)
	decline.Size = UDim2.fromOffset(180, 48)
	decline.TextSize = 22
	Ui.layer(card, Z_INVITE)

	local from: number? = nil
	local token = 0
	local function answer(yes: boolean)
		if from then
			request("respond", from, yes)
		end
		from = nil
		card.Visible = false
	end
	accept.Activated:Connect(function()
		answer(true)
	end)
	decline.Activated:Connect(function()
		answer(false)
	end)
	Remotes.PartyInvite.OnClientEvent:Connect(function(userId: number, name: string, zone: number)
		local level = Config.Dungeons[zone]
		from = userId
		text.Text = `<font color="{hex(GOLD)}">{name}</font> te invita a su grupo\n<font color="{hex(if level then level.color:Lerp(WHITE, 0.25) else WHITE)}">{if level then level.name else "una mazmorra"}</font>`
		card.Visible = true
		Sfx.play("toast")
		if not Performance.get() then
			scale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		token += 1
		local current = token
		task.delay(cfg.InviteTime, function()
			if current == token and card.Visible then
				card.Visible = false
				from = nil
			end
		end)
	end)
end

function Party.start()
	buildWindow()
	buildInvite()
end

return Party
