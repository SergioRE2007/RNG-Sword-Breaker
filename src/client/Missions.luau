-- Ventana de Misiones (el puesto "Misiones" del hub): tres misiones diarias y tres semanales con su
-- barra de progreso y su recompensa en tickets (con los que se compran pases en la Tienda). El servidor cuenta el progreso y lo publica en
-- el atributo "Missions" (JSON); las misiones del día se calculan igual aquí con shared/MissionList.
-- Dos pestañas (pedido por el usuario): "Misiones" (Body.Missions) y "Comprar" (Body.Shop), donde se gastan los tickets
-- en lo de Config.Tickets.Shop: una tarjeta Offer_<n> por objeto, con su botón Buy (BuyTicketItem; server/TicketShop).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local MissionList = require(ReplicatedStorage.Shared.MissionList)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Potions = require(script.Parent.Potions)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Missions = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 200, 60)
local CLOSE_DISTANCE = 30 -- se cierra al alejarse del puesto

local PERIODS = {
	{ "daily", "Misiones diarias", Color3.fromRGB(80, 200, 255) },
	{ "weekly", "Misiones semanales", Color3.fromRGB(190, 120, 255) },
}

local function timeLeft(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours >= 24 then
		return `{math.floor(hours / 24)} d {hours % 24} h`
	end
	return `{hours} h {minutes} min`
end

-- Estado publicado por el servidor, o uno vacío si aún no ha llegado.
local function readState()
	local raw = player:GetAttribute("Missions")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(decoded) == "table" then decoded else nil
end

function Missions.start()
	local window, body = Ui.window("Missions", "Misiones", Vector2.new(660, 652), function(parent)
		Ui.orbIcon(parent, GOLD)
	end)

	-- Fichas que tiene el jugador, arriba a la derecha de la cabecera del cuerpo.
	local tokens = Ui.label(body, 24)
	tokens.AnchorPoint = Vector2.new(1, 0)
	tokens.Position = UDim2.new(1, -16, 0, 6)
	tokens.Size = UDim2.fromOffset(280, 34)
	tokens.TextXAlignment = Enum.TextXAlignment.Right

	-- Pestañas, arriba a la izquierda, y un panel por cada una debajo.
	local panes = {}
	local tabs = {}
	local function show(name: string)
		for key, pane in panes do
			pane.Visible = key == name
			Ui.setSelected(tabs[key], key == name)
		end
	end
	for order, entry in { { "Missions", "Misiones", Ui.COLORS.blue }, { "Shop", "Comprar", Ui.COLORS.orange } } do
		local name = entry[1]
		local tab = Ui.button(body, entry[2], entry[3])
		tab.Name = "Tab" .. name
		tab.Position = UDim2.fromOffset(12 + (order - 1) * 150, 4)
		tab.Size = UDim2.fromOffset(142, 38)
		tab.TextSize = 20
		tabs[name] = tab
		local pane = Instance.new("Frame")
		pane.Name = name
		pane.Position = UDim2.fromOffset(0, 46)
		pane.Size = UDim2.new(1, 0, 1, -46)
		pane.BackgroundTransparency = 1
		pane.Parent = body
		panes[name] = pane
		tab.Activated:Connect(function()
			show(name)
		end)
	end
	local missionPane, shopPane = panes.Missions, panes.Shop

	-- Comprar: una tarjeta por objeto de Config.Tickets.Shop.
	local shopPadding = Instance.new("UIPadding")
	shopPadding.PaddingLeft = UDim.new(0, 12)
	shopPadding.PaddingRight = UDim.new(0, 12)
	shopPadding.PaddingTop = UDim.new(0, 4)
	shopPadding.PaddingBottom = UDim.new(0, 8)
	shopPadding.Parent = shopPane
	local shopGrid = Instance.new("UIGridLayout")
	shopGrid.CellSize = UDim2.new(1 / 3, -8, 0.5, -6)
	shopGrid.CellPadding = UDim2.fromOffset(12, 12)
	shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
	shopGrid.Parent = shopPane
	local offers = {}
	for index, offer in Config.Tickets.Shop do
		local item = Config.Items[offer.item]
		local card = Instance.new("Frame")
		card.Name = "Offer_" .. index
		card.LayoutOrder = index
		card.BackgroundColor3 = WHITE
		card.Parent = shopPane
		Ui.round(card, 12)
		Ui.stroke(card, BLACK, 3)
		Ui.panel(card, Color3.fromRGB(58, 62, 110):Lerp(item.color, 0.18))

		local cell = Ui.cell(card, item.color, if item.potion then item.potion.tier else nil)
		cell.Name = "Icon"
		cell.AnchorPoint = Vector2.new(0.5, 0)
		cell.Position = UDim2.new(0.5, 0, 0, 12)
		cell.Size = UDim2.fromOffset(96, 96)
		if item.potion then
			Potions.icon(cell, item.potion.family, item.potion.tier)
			Potions.addTag(cell, item.potion.tier, true)
			Ui.tip(cell, function()
				return Potions.tip(item.potion.family, item.potion.tier, player:GetAttribute("Item_" .. offer.item) or 0), item.color
			end, true)
		else
			Ui.image(cell, item.image)
			Ui.tip(cell, function()
				return `{item.name}\n<font color="{Ui.SOFT}">{item.description}</font>`, item.color
			end, true)
		end

		local name = Ui.label(card, 20)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(8, 112)
		name.Size = UDim2.new(1, -16, 0, 44)
		name.TextWrapped = true
		name.TextScaled = true
		name.Text = item.name
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 20
		nameLimit.MinTextSize = 12
		nameLimit.Parent = name
		local owned = Ui.label(card, 16)
		owned.Name = "Owned"
		owned.Position = UDim2.fromOffset(8, 156)
		owned.Size = UDim2.new(1, -16, 0, 20)
		owned.TextColor3 = Color3.fromRGB(190, 195, 215)

		local buy = Ui.button(card, `      {offer.price}`, GOLD)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -10)
		buy.Size = UDim2.new(1, -20, 0, 46)
		buy.TextSize = 26
		local coin = Instance.new("Frame")
		coin.Name = "Icon"
		coin.AnchorPoint = Vector2.new(0, 0.5)
		coin.Position = UDim2.new(0.5, -46, 0.5, 0)
		coin.Size = UDim2.fromOffset(30, 30)
		coin.BackgroundTransparency = 1
		coin.Parent = buy
		Ui.orbIcon(coin, GOLD)
		buy.Activated:Connect(function()
			local missing = offer.price - (player:GetAttribute("Item_missionToken") or 0)
			if missing > 0 then
				Sfx.play("error")
				Ui.toast(`Te faltan {missing} tickets`, Ui.COLORS.orange)
				return
			end
			Remotes.BuyTicketItem:FireServer(index)
		end)
		offers[index] = { offer = offer, buy = buy, owned = owned }
	end
	show("Missions")

	local sections = {} -- [periodo] = { header, countdown, rows = { [n] = fila } }
	local y = 0
	for _, period in PERIODS do
		local key, title, color = period[1], period[2], period[3]
		local header = Instance.new("Frame")
		header.Position = UDim2.fromOffset(12, y)
		header.Size = UDim2.new(1, -24, 0, 38)
		header.BackgroundColor3 = WHITE
		header.Parent = missionPane
		Ui.round(header, 10)
		Ui.stroke(header, BLACK, 3)
		Ui.panel(header, color:Lerp(BLACK, 0.12))
		local name = Ui.label(header, 24)
		name.Position = UDim2.fromOffset(14, 0)
		name.Size = UDim2.new(0.5, 0, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = title
		local countdown = Ui.label(header, 18)
		countdown.AnchorPoint = Vector2.new(1, 0)
		countdown.Position = UDim2.new(1, -14, 0, 0)
		countdown.Size = UDim2.new(0.5, 0, 1, 0)
		countdown.TextXAlignment = Enum.TextXAlignment.Right
		y += 44

		local rows = {}
		for index = 1, MissionList.PER_PERIOD do
			local row = Instance.new("Frame")
			row.Position = UDim2.fromOffset(12, y)
			row.Size = UDim2.new(1, -24, 0, 66)
			row.BackgroundColor3 = WHITE
			row.Parent = missionPane
			Ui.round(row, 10)
			Ui.stroke(row, BLACK, 3)
			Ui.panel(row, Color3.fromRGB(62, 68, 118), color)

			local text = Ui.label(row, 21)
			text.Position = UDim2.fromOffset(20, 4)
			text.Size = UDim2.new(1, -250, 0, 28)
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextTruncate = Enum.TextTruncate.AtEnd

			local track = Instance.new("Frame")
			track.Position = UDim2.fromOffset(20, 38)
			track.Size = UDim2.new(1, -262, 0, 18)
			track.BackgroundColor3 = Ui.COLORS.dark
			track.Parent = row
			Ui.round(track, 9)
			Ui.stroke(track, BLACK, 2)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(0, 1)
			fill.BackgroundColor3 = WHITE
			fill.BorderSizePixel = 0
			fill.Parent = track
			Ui.round(fill, 9)
			Ui.gradient(fill, color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.2), 90)
			local progress = Ui.label(track, 14)
			progress.Size = UDim2.fromScale(1, 1)
			progress.ZIndex = 3

			local reward = Ui.label(row, 24)
			reward.AnchorPoint = Vector2.new(1, 0.5)
			reward.Position = UDim2.new(1, -140, 0.5, 0)
			reward.Size = UDim2.fromOffset(80, 40)
			reward.TextXAlignment = Enum.TextXAlignment.Right
			reward.TextColor3 = GOLD
			local coin = Instance.new("Frame")
			coin.AnchorPoint = Vector2.new(1, 0.5)
			coin.Position = UDim2.new(1, -96, 0.5, 0)
			coin.Size = UDim2.fromOffset(34, 34)
			coin.BackgroundTransparency = 1
			coin.Parent = row
			Ui.orbIcon(coin, GOLD)

			local claim = Ui.button(row, "Cobrar", Ui.COLORS.green)
			claim.AnchorPoint = Vector2.new(1, 0.5)
			claim.Position = UDim2.new(1, -8, 0.5, 0)
			claim.Size = UDim2.fromOffset(86, 46)
			claim.TextSize = 20

			rows[index] = { text = text, fill = fill, progress = progress, reward = reward, claim = claim, mission = nil }
			claim.Activated:Connect(function()
				local mission = rows[index].mission
				if mission then
					Remotes.ClaimMission:FireServer(key, mission.id)
				end
			end)
			y += 70
		end
		sections[key] = { countdown = countdown, rows = rows }
		y += 6
	end

	local function refresh()
		tokens.Text = `Tickets: <font color="#{GOLD:ToHex()}">{Format.short(player:GetAttribute("Item_missionToken") or 0)}</font>`
		local tickets = player:GetAttribute("Item_missionToken") or 0
		for _, entry in offers do
			local enough = tickets >= entry.offer.price
			entry.buy.BackgroundColor3 = if enough then GOLD else GOLD:Lerp(Color3.fromRGB(70, 72, 90), 0.7)
			entry.buy.TextColor3 = if enough then WHITE else Color3.fromRGB(190, 192, 205)
			entry.owned.Text = `Tienes: {Format.short(player:GetAttribute("Item_" .. entry.offer.item) or 0)}`
		end
		local state = readState()
		local now = os.time()
		for _, period in PERIODS do
			local key = period[1]
			local section = sections[key]
			local id = MissionList.periodId(key, now)
			local current = state and state[key]
			-- Si el servidor aún no ha cambiado de día, el progreso que llega es del periodo anterior: se ignora.
			local valid = current ~= nil and current.id == id
			local progress = if valid then current.progress or {} else {}
			local claimed = if valid then current.claimed or {} else {}
			section.countdown.Text = `Se reinicia en {timeLeft(MissionList.secondsLeft(key, now))}`
			for index, mission in MissionList.pick(key, id) do
				local row = section.rows[index]
				row.mission = mission
				local done = math.min(progress[mission.id] or 0, mission.goal)
				row.text.Text = mission.text
				row.reward.Text = `+{mission.reward}`
				row.fill.Size = UDim2.fromScale(done / mission.goal, 1)
				row.progress.Text = `{Format.short(math.floor(done))} / {Format.short(mission.goal)}`
				local isClaimed = claimed[mission.id] == true
				local ready = not isClaimed and done >= mission.goal
				-- Verde = se puede cobrar; gris apagado = aún no; oscuro con texto verde = ya cobrada.
				row.claim.Text = if isClaimed then "Cobrada" else "Cobrar"
				row.claim.BackgroundColor3 = if ready then Ui.COLORS.green elseif isClaimed then Ui.COLORS.dark else Ui.COLORS.gray
				row.claim.TextColor3 = if isClaimed then Ui.COLORS.green:Lerp(WHITE, 0.3) elseif ready then WHITE else Color3.fromRGB(175, 178, 190)
				row.claim.AutoButtonColor = ready
			end
		end
	end

	player:GetAttributeChangedSignal("Missions"):Connect(refresh)
	player:GetAttributeChangedSignal("Item_missionToken"):Connect(function()
		Sfx.play("coin")
		refresh()
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	for _, offer in Config.Tickets.Shop do
		player:GetAttributeChangedSignal("Item_" .. offer.item):Connect(refresh)
	end
	task.spawn(function()
		-- La cuenta atrás se actualiza cada segundo mientras la ventana está abierta.
		while true do
			task.wait(1)
			if window.Visible then
				refresh()
			end
		end
	end)
	refresh()

	-- Abrir junto al puesto y cerrar al alejarse.
	local openAt: Vector3? = nil
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Shop") == "missions" then
			local parent = prompt.Parent
			openAt = if parent and parent:IsA("BasePart") then parent.Position else nil
			Ui.toggle("Missions")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if openAt and root and window.Visible and (root.Position - openAt).Magnitude > CLOSE_DISTANCE then
				Ui.close(window)
				openAt = nil
			end
		end
	end)
end

return Missions
