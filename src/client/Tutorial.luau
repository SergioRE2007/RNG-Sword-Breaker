-- Tutorial de los primeros minutos (Config.Tutorial; los pasos los decide server/Tutorial, que publica en el jugador
-- los atributos "Tutorial", paso por el que va o 0 = terminado, y "TutorialCount"). Aquí va lo que se ve:
--   · La tarjeta Hud.HudRoot.Tutorial, a la derecha: "Tutorial 2/7", lo que hay que hacer, la barra de los pasos que
--     cuentan y la X que lo salta (TutorialSkip).
--   · La flecha: en el mundo (workspace.TutorialPointer: una flecha que bota sobre el objetivo y una línea de luz desde el
--     personaje) o al lado de un botón del HUD (Hud.TutorialArrow), según el `point` del paso.
-- Los pasos que el servidor no cuenta solo (equipar, bolsa, lobby, abrir una ventana) se le avisan con TutorialCheck
-- cuando aquí parece que ya están; él lo comprueba. Un solo bucle, que solo vive mientras dura el tutorial.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Tutorial = {}

local player = Players.LocalPlayer
local cfg = Config.Tutorial
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 60)
local ACCENT = Color3.fromRGB(90, 200, 255)
local LOBBY_Y = -28
local CHECK_EVERY = 0.6 -- segundos entre dos avisos al servidor

local card: Frame? = nil
local refs: { [string]: any } = {}
local arrow: TextLabel? = nil -- flecha junto a un botón del HUD
local ring: Frame? = nil -- aro que late alrededor de ese botón
local world: { [string]: any }? = nil -- flecha y línea del mundo
local loop: RBXScriptConnection? = nil
local lastCheck = 0
local shown = 0 -- paso que enseña ahora la tarjeta

local function step()
	local index = player:GetAttribute("Tutorial") or 0
	return cfg.Steps[index], index
end

local function build()
	local frame = Instance.new("Frame")
	frame.Name = "Tutorial"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -12, 0, 96)
	frame.Size = UDim2.fromOffset(340, 124)
	frame.BackgroundColor3 = WHITE
	frame.Visible = false
	frame.Parent = Ui.hud()
	Ui.round(frame, 14)
	Ui.stroke(frame, BLACK, 4)
	Ui.gradient(frame, Color3.fromRGB(58, 64, 118), Color3.fromRGB(24, 26, 52), 90)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	refs.scale = scale

	-- Cabecera de color con el número de paso y la X.
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.Position = UDim2.fromOffset(6, 6)
	head.Size = UDim2.new(1, -12, 0, 32)
	head.BackgroundColor3 = WHITE
	head.Parent = frame
	Ui.round(head, 9)
	Ui.gradient(head, ACCENT, Color3.fromRGB(130, 100, 255), 0)
	local title = Ui.label(head, 20)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 0)
	title.Size = UDim2.new(1, -52, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	refs.title = title
	local skip = Ui.button(head, "X", Ui.COLORS.red)
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -3, 0.5, 0)
	skip.Size = UDim2.fromOffset(30, 26)
	skip.TextSize = 16
	Ui.tip(skip, function()
		return Lang.t(nil, "Skip the tutorial (no reward)"), Ui.COLORS.red
	end, true)
	-- Dos toques: el primero avisa.
	local asked = 0
	skip.Activated:Connect(function()
		if os.clock() - asked < 3 then
			Remotes.TutorialSkip:FireServer()
		else
			asked = os.clock()
			Ui.toast(Lang.t(nil, "Press the X again to skip the tutorial (no reward)"), Ui.COLORS.orange)
		end
	end)

	local text = Ui.label(frame, 20)
	text.Name = "Text"
	text.Position = UDim2.fromOffset(14, 42)
	text.Size = UDim2.new(1, -28, 0, 50)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextWrapped = true
	text.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.MinTextSize = 13
	limit.Parent = text
	refs.text = text

	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -10)
	track.Size = UDim2.new(1, -28, 0, 18)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.Parent = frame
	Ui.round(track, 9)
	Ui.stroke(track, BLACK, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Ui.round(fill, 9)
	Ui.gradient(fill, GOLD:Lerp(WHITE, 0.35), GOLD:Lerp(BLACK, 0.15), 90)
	local amount = Ui.label(track, 14)
	amount.Name = "Amount"
	amount.Size = UDim2.fromScale(1, 1)
	amount.ZIndex = 3
	refs.track, refs.fill, refs.amount = track, fill, amount
	card = frame

	-- Flecha del HUD: va suelta en la pantalla (no dentro de HudRoot) para colocarla con medidas de pantalla.
	local pointer = Instance.new("TextLabel")
	pointer.Name = "TutorialArrow"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(96, 96)
	pointer.BackgroundTransparency = 1
	pointer.Font = Enum.Font.GothamBlack
	pointer.Text = "◀"
	pointer.TextScaled = true
	pointer.TextColor3 = GOLD
	pointer.ZIndex = 50
	pointer.Visible = false
	pointer.Parent = Ui.screen()
	Ui.textStroke(pointer, 4)
	arrow = pointer
	-- Aro dorado que late alrededor del botón señalado.
	local halo = Instance.new("Frame")
	halo.Name = "TutorialRing"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.BackgroundTransparency = 1
	halo.ZIndex = 50
	halo.Visible = false
	halo.Parent = Ui.screen()
	Ui.round(halo, 16)
	refs.ringStroke = Ui.stroke(halo, GOLD, 5)
	ring = halo
end

local function buildWorld()
	local folder = Instance.new("Folder")
	folder.Name = "TutorialPointer"
	folder.Parent = workspace
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder
	local to = Instance.new("Attachment")
	to.Name = "To"
	to.Parent = anchor
	local from = Instance.new("Attachment")
	from.Name = "From"
	from.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(GOLD)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
	beam.Width0 = 0.8
	beam.Width1 = 1.6
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureLength = 6
	beam.TextureSpeed = 1.5
	beam.Parent = anchor
	local board = Instance.new("BillboardGui")
	board.Name = "Arrow"
	board.Size = UDim2.fromOffset(70, 70)
	board.AlwaysOnTop = true
	board.MaxDistance = 600
	board.Adornee = anchor
	board.Parent = folder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "▼"
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Parent = board
	Ui.textStroke(label, 4)
	world = { folder = folder, anchor = anchor, from = from, to = to, beam = beam, board = board }
end

-- Dónde está en el mundo lo que señala ese paso (o nil si ahora no lo hay): posición y altura de la flecha sobre ella.
local function worldTarget(point: string): (Vector3?, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if point == "object" then
		local best, bestDistance = nil, math.huge
		for _, part in CollectionService:GetTagged("Destructible") do
			if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId and part:IsDescendantOf(workspace) then
				local distance = if root then (part.Position - root.Position).Magnitude else 0
				if distance < bestDistance then
					best, bestDistance = part, distance
				end
			end
		end
		if best then
			return best.Position, best.Size.Y / 2 + 3
		end
	elseif point == "bag" then
		for _, bag in CollectionService:GetTagged("GoldBag") do
			if bag:GetAttribute("Owner") == player.UserId then
				local body = bag:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					return body.Position, body.Size.Y / 2 + 4
				end
			end
		end
	elseif string.sub(point, 1, 6) == "stall:" then
		local shop = string.sub(point, 7)
		for _, station in CollectionService:GetTagged("ShopStation") do
			if station:GetAttribute("Shop") == shop then
				local part = if station:IsA("BasePart") then station else station.Parent
				if part and part:IsA("BasePart") then
					return part.Position, 9
				end
			end
		end
	end
	return nil, 0
end

-- El botón del HUD que señala ese paso (o nil).
local function buttonTarget(point: string): GuiObject?
	if string.sub(point, 1, 7) ~= "button:" then
		return nil
	end
	local at: Instance? = Ui.hud()
	for _, name in string.split(string.sub(point, 8), ".") do
		at = at and at:FindFirstChild(name)
	end
	return if at and at:IsA("GuiObject") then at else nil
end

-- Si aquí parece que el paso ya está cumplido (los que el servidor no cuenta solo).
local function looksDone(info): boolean
	if info.kind == "equip" then
		return #Stats.loadout(player) >= 2
	elseif info.kind == "bag" then
		return (player:GetAttribute("Bag") or "") ~= ""
	elseif info.kind == "lobby" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root ~= nil and root.Position.Y < LOBBY_Y
	elseif info.kind == "seen" then
		local window = Ui.screen():FindFirstChild(info.window)
		return window ~= nil and window:IsA("GuiObject") and window.Visible
	end
	return false
end

local function refresh()
	local info, index = step()
	local frame = card :: Frame
	if not info then
		frame.Visible = false
		return
	end
	frame.Visible = true
	refs.title.Text = `Tutorial {index}/{#cfg.Steps}`
	refs.text.Text = Lang.t(nil, info.text)
	local goal = info.goal or 1
	local counted = goal > 1
	refs.track.Visible = counted
	frame.Size = UDim2.fromOffset(340, if counted then 124 else 100)
	if counted then
		local done = math.min(player:GetAttribute("TutorialCount") or 0, goal)
		refs.amount.Text = `{done} / {goal}`
		TweenService:Create(refs.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(done / goal, 1) }):Play()
	end
	-- Paso nuevo: la tarjeta da un bote y suena.
	if index ~= shown then
		if shown ~= 0 then
			Sfx.play("buyPing")
		end
		shown = index
		if not Performance.get() then
			refs.scale.Scale = 1.12
			TweenService:Create(refs.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

local function tick()
	local info = step()
	local pointer = arrow :: TextLabel
	if not info then
		return
	end
	local now = os.clock()
	local bounce = math.sin(now * 6)

	-- Flecha junto a un botón del HUD.
	local button = buttonTarget(info.point)
	local showButton = button ~= nil and button.Visible and (card :: Frame).Visible and not Ui.anyOpen()
	local halo = ring :: Frame
	pointer.Visible = showButton
	halo.Visible = showButton
	if showButton and button then
		local origin = Ui.screen().AbsolutePosition
		local position, size = button.AbsolutePosition - origin, button.AbsoluteSize
		local centre = position + size / 2
		local pulse = 0.5 + 0.5 * math.sin(now * 5)
		halo.Position = UDim2.fromOffset(centre.X, centre.Y)
		halo.Size = UDim2.fromOffset(size.X + 10 + pulse * 10, size.Y + 10 + pulse * 10)
		refs.ringStroke.Transparency = pulse * 0.45
		-- Los botones de arriba del todo se señalan desde abajo; los demás, desde arriba (a los lados hay otros botones).
		if position.Y < 150 then
			pointer.Text = "▲"
			pointer.Position = UDim2.fromOffset(centre.X, position.Y + size.Y + 46 + bounce * 7)
		else
			pointer.Text = "▼"
			pointer.Position = UDim2.fromOffset(centre.X, position.Y - 46 + bounce * 7)
		end
	end

	-- Flecha y línea en el mundo.
	local spot, height = worldTarget(info.point)
	if spot and not world then
		buildWorld()
	end
	if world then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local on = spot ~= nil and root ~= nil and root.Position.Y > LOBBY_Y
		world.board.Enabled = on
		world.beam.Enabled = false
		if on and spot and root then
			-- La línea solo de lejos: pegado al objetivo estorba.
			world.beam.Enabled = (spot - root.Position).Magnitude > 12
			world.anchor.CFrame = CFrame.new(spot + Vector3.new(0, height + bounce * 0.6, 0))
			world.to.WorldPosition = spot
			world.from.WorldPosition = root.Position - Vector3.new(0, 2, 0)
		end
	end

	-- Avisar al servidor cuando parece cumplido.
	if now - lastCheck > CHECK_EVERY and looksDone(info) then
		lastCheck = now
		Remotes.TutorialCheck:FireServer(info.id)
	end
end

local function update()
	local info = step()
	refresh()
	if info and not loop then
		loop = RunService.RenderStepped:Connect(tick)
	elseif not info and loop then
		loop:Disconnect()
		loop = nil
		if arrow then
			arrow.Visible = false
		end
		if ring then
			ring.Visible = false
		end
		if world then
			world.folder:Destroy()
			world = nil
		end
	end
end

function Tutorial.start()
	build()
	player:GetAttributeChangedSignal("Tutorial"):Connect(update)
	player:GetAttributeChangedSignal("TutorialCount"):Connect(refresh)
	update()
end

return Tutorial
