-- Lo que se ve de la Bolsa de oro (server/GoldBag): las armas depositadas atacando al saco con el mismo vuelo que las
-- equipadas (client/OrbitWeapons), las monedas que saltan con cada golpe, el cartel de cada saco (por qué bolsa va su
-- dueño y las monedas que le quedan) y los avisos de bolsa vaciada y de lo ganado mientras no estabas.
-- Todo sale de los atributos del dueño: "Bag", "BagStage", "BagTaken", "BagAt" y "BagRate". Los golpes los marca
-- este cliente con su reloj (uno por arma cada Config.GoldBag.HitTime): el servidor cobra lo mismo, junto, cada segundo.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BagInfo = require(ReplicatedStorage.Shared.BagInfo)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)

local FloatText = require(script.Parent.FloatText)
local OrbitWeapons = require(script.Parent.OrbitWeapons)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Lang = require(ReplicatedStorage.Shared.Lang)

local GoldBag = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 70)

local TAG = "GoldBag"
local TICK = 0.25 -- cada cuánto se ponen al día los carteles
local RANGE = 70 -- studs: más lejos no se ve el cartel (pedido por el usuario: desde lejos mide lo mismo en pantalla y tapaba la parcela)
local FAR = 170 -- studs de la cámara desde los que las armas de un saco no se mueven
local NEAR = 75 -- y desde los que sus golpes no suenan
local TOAST_EVERY = 15 -- segundos entre avisos de bolsa vaciada (con armas muy fuertes caen seguidas)
-- El cartel mide lo mismo en píxeles a cualquier distancia (es un BillboardGui): sus medidas van en píxeles a
-- propósito y un UIScale lo encoge entero en pantallas pequeñas, como el HUD (Ui.hud).
local CARD_SIZE = Vector2.new(264, 92)
local SCREEN = Vector2.new(1100, 700)
local MIN_FACTOR = 0.6
local CARD_HEIGHT = 12 -- studs del centro del saco al cartel
-- Capas del cartel (la interfaz ordena el ZIndex globalmente).
local Z = { card = 1, bar = 2, fill = 3, text = 4 }
-- Dónde empiezan las armas depositadas: alrededor del saco, del lado de la parcela.
local SPOTS = { -0.55, 0.55, -1.5, 1.5, -1.02, 1.02, -2.05, 2.05 } -- ángulo de cada hueco (0 = hacia la parcela); los cuatro últimos, los del pase
local SACK_RADIUS = 6.2
local AIM_DROP = 4.5 -- lo que se le dice a OrbitWeapons que hay del centro del saco al suelo: así cruzan por el centro
-- El saco de Blender (modelo "GoldSack") se encoge según se vacía y da un respingo con cada golpe.
local SHRINK = 0.78 -- tamaño con la bolsa casi vacía (1 = llena)
local PULSE, PULSE_TIME = 0.04, 0.16 -- cuánto crece con un golpe y lo que tarda en volver
local COIN_IMAGE = Ui.IMAGES.monedas

local cards = {} -- [modelo del saco] = entrada (ver buildCard)
local folder: Folder
local lastToast = 0
local pendingBags = 0

local function factor(): number
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else SCREEN
	return math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), MIN_FACTOR, 1)
end

-- Monedas que saltan del saco con cada golpe: un emisor que solo suelta las que se le piden.
local function coinEmitter(body: BasePart): (Attachment, ParticleEmitter)
	local point = Instance.new("Attachment")
	point.Name = "CoinBurst"
	point.Parent = body
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Coins"
	emitter.Enabled = false
	emitter.Texture = COIN_IMAGE
	emitter.Color = ColorSequence.new(WHITE)
	emitter.LightEmission = 0.15
	emitter.LightInfluence = 0.4
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.15, 1.5), NumberSequenceKeypoint.new(1, 1.1) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.7, 1.05)
	emitter.Speed = NumberRange.new(16, 26)
	emitter.SpreadAngle = Vector2.new(34, 34)
	emitter.Acceleration = Vector3.new(0, -62, 0)
	emitter.Drag = 0.6
	emitter.Rotation = NumberRange.new(-40, 40)
	emitter.RotSpeed = NumberRange.new(-260, 260)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Parent = point
	return point, emitter
end

local function buildCard(model: Model)
	local body = model.PrimaryPart or model:WaitForChild("Body", 10)
	if not body then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GoldBag" .. (model:GetAttribute("Plot") or 0)
	gui.Adornee = body
	gui.StudsOffsetWorldSpace = Vector3.new(0, CARD_HEIGHT, 0)
	gui.MaxDistance = RANGE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	card.BorderSizePixel = 0
	card.ZIndex = Z.card
	card.Parent = gui
	Ui.round(card, 12)
	Ui.stroke(card, BLACK, 3)
	Ui.panel(card, Color3.fromRGB(58, 44, 30))
	local scale = Instance.new("UIScale")
	scale.Parent = card

	local title = Ui.label(card, 25)
	title.Name = "Title"
	title.Position = UDim2.fromScale(0.04, 0.07)
	title.Size = UDim2.fromScale(0.92, 0.38)
	title.ZIndex = Z.text
	Ui.gradient(title, WHITE, GOLD, 90)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.05, 0.5)
	bar.Size = UDim2.fromScale(0.9, 0.36)
	bar.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
	bar.BorderSizePixel = 0
	bar.ZIndex = Z.bar
	bar.Parent = card
	Ui.round(bar, 8)
	Ui.stroke(bar, BLACK, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.ZIndex = Z.fill
	fill.Parent = bar
	Ui.round(fill, 8)
	Ui.gradient(fill, Color3.fromRGB(255, 226, 110), Color3.fromRGB(240, 150, 30), 90)
	local amount = Ui.label(bar, 20)
	amount.Name = "Amount"
	amount.Size = UDim2.fromScale(1, 1)
	amount.TextScaled = true
	amount.ZIndex = Z.text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 21
	limit.MinTextSize = 11
	limit.Parent = amount

	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Model")
	holder.Name = "Bolsa" .. (model:GetAttribute("Plot") or 0)
	holder.Parent = folder
	local burst, emitter = coinEmitter(body)
	cards[model] = {
		gui = gui, scale = scale, title = title, fill = fill, amount = amount,
		body = body, radius = model:GetAttribute("Radius") or SACK_RADIUS,
		sack = model:FindFirstChild("GoldSack"), -- el saco de Blender (nil con el de piezas)
		holder = holder, weapons = {}, raw = "", key = "",
		burst = burst, emitter = emitter,
		owner = nil, mine = false, left = 1, pulse = 0, sized = 1,
	}
end

-- Las armas depositadas de ese saco: se rehacen si cambian y empiezan a pegar, repartidas a lo largo de HitTime.
local function buildWeapons(entry, owner: Player, copies)
	entry.holder:ClearAllChildren()
	entry.weapons = {}
	local center = entry.body.Position
	local toPlot = entry.body.CFrame.LookVector -- el saco está orientado como su parcela: mira hacia el hub
	local facing = math.atan2(toPlot.X, toPlot.Z)
	local now = os.clock()
	local count = math.max(#copies, 1)
	for slot, copy in copies do
		if not Config.Swords[copy.sword] or not SPOTS[slot] then
			continue
		end
		local angle = facing + SPOTS[slot]
		local at = center + Vector3.new(math.sin(angle), 0, math.cos(angle)) * (entry.radius + 5)
		local weapon = OrbitWeapons.spare(owner, slot, copy, entry.holder, at, center)
		weapon.planned = now + 0.5 + (slot - 1) * Config.GoldBag.HitTime / count
		weapon.bagSeen = weapon.crossed
		weapon.bagSlot = slot
		table.insert(entry.weapons, weapon)
	end
end

-- Un golpe de esa arma al saco: saltan monedas por donde sale, respingo del saco y, en el tuyo, el número y el sonido.
local function onStrike(entry, weapon, owner: Player, eye: Vector3, lite: boolean)
	local coins = Stats.bagCoins(owner, weapon.copy)
	local center = entry.body.Position
	local out = Vector3.new(weapon.dir.X, 0, weapon.dir.Z)
	out = if out.Magnitude > 0.1 then out.Unit else entry.body.CFrame.LookVector
	local from = center + out * (entry.radius * 0.8)
	entry.pulse = os.clock()
	if not lite then
		entry.burst.WorldCFrame = CFrame.lookAt(from, from + out + Vector3.new(0, 1.3, 0))
		-- Más monedas cuanto más saca el golpe (de 3 a 12).
		entry.emitter:Emit(math.clamp(math.floor(3 + math.log10(math.max(coins, 1)) * 1.5), 3, 12))
	end
	if not entry.mine then
		return
	end
	FloatText.spawn("coin", center + out * (entry.radius * 0.6) + Vector3.new(0, 5.5, 0), "+" .. Format.short(coins))
	if (center - eye).Magnitude < NEAR then
		Sfx.swing(weapon.key, Config.GoldBag.HitTime, weapon.handle.Position, 0.5)
		Sfx.play("coin_break", 0.45, 1 + (weapon.bagSlot - 1) * 0.06, from)
	end
end

-- El saco de Blender se encoge según se vacía y crece un momento con cada golpe.
local function sizeSack(entry, now: number)
	local sack = entry.sack
	if not sack then
		return
	end
	local size = (SHRINK + (1 - SHRINK) * entry.left) * (1 + PULSE * math.clamp(1 - (now - entry.pulse) / PULSE_TIME, 0, 1))
	size = math.round(size * 200) / 200 -- por pasos: solo se tocan las mallas cuando cambia
	if size ~= entry.sized then
		entry.sized = size
		sack:ScaleTo(size)
	end
end

local function update(model: Model, entry)
	local ownerId = model:GetAttribute("Owner") or 0
	local owner = if ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
	local mine = owner == player
	local deposited = if owner then #Stats.list(owner, "Bag") else 0
	local stage = owner and owner:GetAttribute("BagStage")
	entry.owner, entry.mine = owner, mine
	if not entry.sack then
		entry.sack = model:FindFirstChild("GoldSack") -- puede llegar después que el modelo
	end
	-- La de otro jugador sin armas dentro no enseña nada; la tuya, cómo empezar.
	if not owner or not stage or (deposited == 0 and not mine) then
		entry.gui.Enabled = false
		entry.left = 1
		if entry.key ~= "" then
			entry.raw, entry.key = "", ""
			entry.holder:ClearAllChildren()
			entry.weapons = {}
		end
		return
	end
	-- Las armas solo se rehacen si cambian las depositadas (el inventario cambia con cada objeto roto). En modo
	-- Rendimiento, solo las de tu saco.
	local shown = mine or not Performance.get()
	local raw = `{ownerId}|{shown}|{owner:GetAttribute("Bag")}|{owner:GetAttribute("Swords")}`
	if raw ~= entry.raw then
		entry.raw = raw
		local copies = if shown then Stats.deposited(owner) else {}
		local parts = { tostring(ownerId) }
		for _, copy in copies do
			table.insert(parts, `{copy.id}:{copy.sword}:{copy.metal}:{copy.size}`)
		end
		local key = table.concat(parts, ",")
		if key ~= entry.key then
			entry.key = key
			buildWeapons(entry, owner, copies)
		else
			for index, weapon in entry.weapons do
				weapon.copy = copies[index] or weapon.copy -- el rasgo o el grado pueden haber cambiado
			end
		end
	end

	local size = factor()
	entry.scale.Scale = size
	entry.gui.Size = UDim2.fromOffset(CARD_SIZE.X * size + 8, CARD_SIZE.Y * size + 8)
	entry.gui.Enabled = true

	local full = BagInfo.size(stage)
	local elapsed = math.max(workspace:GetServerTimeNow() - (owner:GetAttribute("BagAt") or 0), 0)
	local taken = math.clamp((owner:GetAttribute("BagTaken") or 0) + (owner:GetAttribute("BagPower") or 0) * elapsed, 0, full)
	entry.left = math.clamp(1 - taken / full, 0, 1)
	entry.title.Text = Lang.t(nil, "BAG #{n}", { n = stage })
	entry.fill.Size = UDim2.fromScale(entry.left, 1)
	entry.amount.Text = if deposited == 0 then `<font color="{Ui.SOFT}">{Lang.t(nil, "Click the sack to leave weapons")}</font>` else Format.short(math.ceil(full - taken))
end

-- Cada cuadro: las armas de los sacos cercanos vuelan y pegan, y el saco se encoge y da su respingo.
local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local lite = Performance.get()
	local period = Config.GoldBag.HitTime
	for _, entry in cards do
		local owner = entry.owner
		if not owner or (#entry.weapons == 0 and entry.sized == 1) then
			continue
		end
		if (entry.body.Position - eye).Magnitude > FAR then
			continue
		end
		local ground = entry.body.Position.Y - AIM_DROP
		local count = #entry.weapons
		for index, weapon in entry.weapons do
			-- Si lleva rato parada (el saco estaba lejos), vuelve a su turno en vez de salir todas a la vez.
			if weapon.planned and now > weapon.planned + period then
				weapon.planned = now + 0.15 + (index - 1) * period / count
			end
			local crossed = OrbitWeapons.strike(weapon, entry.body, ground, now, dt, lite)
			if crossed ~= weapon.bagSeen then
				weapon.bagSeen = crossed
				weapon.planned = crossed + period
				onStrike(entry, weapon, owner, eye, lite)
			end
		end
		sizeSack(entry, now)
	end
end

local function onEvent(kind: string, info)
	if type(info) ~= "table" then
		return
	end
	if kind == "emptied" then
		-- Con armas muy por encima caen varias seguidas: un aviso de vez en cuando, con las que lleve.
		pendingBags += info.bags or 1
		if os.clock() - lastToast >= TOAST_EVERY then
			lastToast = os.clock()
			Sfx.play("win")
			Ui.toast(if pendingBags > 1 then Lang.t(nil, "{n} bags emptied! +{n} bag coins", { n = pendingBags }) else Lang.t(nil, "Bag emptied! +1 bag coin"), GOLD)
			pendingBags = 0
		end
	elseif kind == "away" then
		Sfx.play("win")
		Ui.toast(Lang.t(nil, "While you were away: +{n} coins", { n = Format.short(info.coins or 0) }), GOLD)
	end
end

function GoldBag.start()
	folder = Instance.new("Folder")
	folder.Name = "GoldBagWeapons"
	folder.Parent = workspace

	for _, model in CollectionService:GetTagged(TAG) do
		task.spawn(buildCard, model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(buildCard)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		local entry = cards[model]
		if entry then
			cards[model] = nil
			entry.gui:Destroy()
			entry.holder:Destroy()
		end
	end)

	Remotes.BagEvent.OnClientEvent:Connect(onEvent)
	RunService.RenderStepped:Connect(step)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for model, entry in cards do
				update(model, entry)
			end
		end
	end)
end

return GoldBag
