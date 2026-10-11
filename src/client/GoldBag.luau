-- Lo que se ve de la Bolsa de oro (server/GoldBag): el cartel de cada saco (por qué bolsa va su dueño, las monedas
-- que le quedan y las que da por segundo), las armas que tiene depositadas, puestas alrededor, y los avisos de
-- bolsa vaciada y de lo ganado mientras no estabas. Todo sale de los atributos del dueño: "Bag", "BagStage",
-- "BagDamage", "BagAt" y "BagRate" (el daño de ahora se calcula aquí, sin que el servidor lo mande cada segundo).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagInfo = require(ReplicatedStorage.Shared.BagInfo)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local GoldBag = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 70)
local GREEN = Color3.fromRGB(140, 235, 110)

local TAG = "GoldBag"
local TICK = 0.25 -- cada cuánto se ponen al día los carteles
local RANGE = 230 -- studs: más lejos no se ve el cartel
local TOAST_EVERY = 15 -- segundos entre avisos de bolsa vaciada (con armas muy fuertes caen seguidas)
-- El cartel mide lo mismo en píxeles a cualquier distancia (es un BillboardGui): sus medidas van en píxeles a
-- propósito y un UIScale lo encoge entero en pantallas pequeñas, como el HUD (Ui.hud).
local CARD_SIZE = Vector2.new(264, 118)
local SCREEN = Vector2.new(1100, 700)
local MIN_FACTOR = 0.6
local CARD_HEIGHT = 12 -- studs del centro del saco al cartel
-- Capas del cartel (la interfaz ordena el ZIndex globalmente).
local Z = { card = 1, bar = 2, fill = 3, text = 4 }
-- Dónde se ponen las armas depositadas: alrededor del saco, del lado de la parcela, apuntándole.
local SPOTS = { -0.55, 0.55, -1.5, 1.5 } -- ángulo de cada hueco (0 = hacia la parcela)
local SPOT_HEIGHT = 0.5 -- sobre el centro del saco
local SACK_RADIUS = 6.2

local cards = {} -- [modelo del saco] = { gui, title, fill, amount, rate, weapons = carpeta, key }
local folder: Folder
local lastToast = 0
local pendingBags = 0

local function factor(): number
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else SCREEN
	return math.clamp(math.min(view.X / SCREEN.X, view.Y / SCREEN.Y), MIN_FACTOR, 1)
end

local function clock(seconds: number): string
	seconds = math.floor(seconds)
	if seconds >= 86400 then
		return `{seconds // 86400} d {seconds % 86400 // 3600} h`
	elseif seconds >= 3600 then
		return `{seconds // 3600} h {seconds % 3600 // 60} min`
	end
	return `{math.max(seconds // 60, 1)} min`
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

	local title = Ui.label(card, 24)
	title.Name = "Title"
	title.Position = UDim2.fromScale(0.04, 0.05)
	title.Size = UDim2.fromScale(0.92, 0.3)
	title.ZIndex = Z.text
	Ui.gradient(title, WHITE, GOLD, 90)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.05, 0.38)
	bar.Size = UDim2.fromScale(0.9, 0.28)
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
	amount.ZIndex = Z.text

	local rate = Ui.label(card, 18)
	rate.Name = "Rate"
	rate.Position = UDim2.fromScale(0.04, 0.67)
	rate.Size = UDim2.fromScale(0.92, 0.25)
	rate.TextWrapped = true
	rate.ZIndex = Z.text

	gui.Parent = player:WaitForChild("PlayerGui")
	local weapons = Instance.new("Folder")
	weapons.Name = "Bolsa" .. (model:GetAttribute("Plot") or 0)
	weapons.Parent = folder
	cards[model] = { gui = gui, card = card, scale = scale, title = title, fill = fill, amount = amount, rate = rate, weapons = weapons, raw = "", key = "", body = body, radius = model:GetAttribute("Radius") or SACK_RADIUS }
end

-- Las armas depositadas, quietas alrededor del saco y apuntándole (la animación de los golpes es de otra tanda).
local function buildWeapons(entry, copies)
	entry.weapons:ClearAllChildren()
	local center = entry.body.Position + Vector3.new(0, SPOT_HEIGHT, 0)
	local toPlot = entry.body.CFrame.LookVector -- el saco está orientado como su parcela: mira hacia el hub
	local facing = math.atan2(toPlot.X, toPlot.Z)
	for slot, copy in copies do
		if not Config.Swords[copy.sword] or not SPOTS[slot] then
			continue
		end
		local model = Instance.new("Model")
		model.Name = "Weapon" .. slot
		SwordModel.build(copy.sword, model, CFrame.identity, Permanent.scale(copy), true, copy.metal)
		-- La empuñadura está en el origen y la hoja sube por Y: se coloca con la punta rozando el saco. Las piezas van
		-- ancladas, así que se mueven una a una.
		local pieces, top = {}, 1
		for _, piece in model:GetDescendants() do
			if piece:IsA("BasePart") then
				piece.CanCollide = false
				piece.CanQuery = false
				piece.CanTouch = false
				table.insert(pieces, piece)
				top = math.max(top, piece.Position.Y + piece.Size.Magnitude / 2)
			end
		end
		local angle = facing + SPOTS[slot]
		local out = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local handle = center + out * (entry.radius + math.min(top, 14))
		local place = CFrame.lookAt(handle, center) * CFrame.Angles(-math.pi / 2, 0, 0)
		for _, piece in pieces do
			piece.CFrame = place * piece.CFrame
		end
		model.Parent = entry.weapons
	end
end

local function update(model: Model, entry)
	local ownerId = model:GetAttribute("Owner") or 0
	local owner = if ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
	local mine = owner == player
	local deposited = if owner then #Stats.list(owner, "Bag") else 0
	local stage = owner and owner:GetAttribute("BagStage")
	-- La de otro jugador sin armas dentro no enseña nada; la tuya, cómo empezar.
	if not owner or not stage or (deposited == 0 and not mine) then
		entry.gui.Enabled = false
		if entry.key ~= "" then
			entry.raw, entry.key = "", ""
			entry.weapons:ClearAllChildren()
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
			buildWeapons(entry, copies)
		end
	end

	local size = factor()
	entry.scale.Scale = size
	entry.gui.Size = UDim2.fromOffset(CARD_SIZE.X * size + 8, CARD_SIZE.Y * size + 8)
	entry.gui.Enabled = true

	local bag = BagInfo.bag(stage)
	local speed = owner:GetAttribute("BagRate") or 0
	local elapsed = math.max(workspace:GetServerTimeNow() - (owner:GetAttribute("BagAt") or 0), 0)
	local damage = math.clamp((owner:GetAttribute("BagDamage") or 0) + speed * elapsed, 0, bag.hp)
	local left = 1 - damage / bag.hp
	entry.title.Text = `BOLSA Nº {stage}`
	entry.fill.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
	entry.amount.Text = Format.short(math.ceil(bag.coins * left))
	if deposited == 0 then
		entry.rate.Text = `<font color="{Ui.SOFT}">Deja aquí armas: Mochila → A la bolsa</font>`
	else
		local full = speed >= BagInfo.speed(stage, math.huge) * 0.999
		local coins = speed / bag.hp * bag.coins
		entry.rate.Text = `<font color="#{GREEN:ToHex()}">+{Format.multiplier(coins)} monedas/s</font>{if full then ` <font color="#{GOLD:ToHex()}">· MÁX</font>` else ""}`
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
			local bag = BagInfo.bag(info.stage or 1)
			Sfx.play("win")
			Ui.toast(`{if pendingBags > 1 then `¡{pendingBags} bolsas vaciadas!` else "¡Bolsa vaciada!"} La nº {info.stage} lleva {Format.short(bag.coins)} monedas`, GOLD)
			pendingBags = 0
		end
	elseif kind == "away" then
		local bags = info.bags or 0
		Sfx.play("win")
		Ui.toast(`Mientras no estabas ({clock(info.seconds or 0)}) tu bolsa ha dado {Format.short(info.coins or 0)} monedas{if bags > 0 then ` · {bags} {if bags == 1 then "bolsa vaciada" else "bolsas vaciadas"}` else ""}`, GOLD)
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
			entry.weapons:Destroy()
		end
	end)

	Remotes.BagEvent.OnClientEvent:Connect(onEvent)

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
