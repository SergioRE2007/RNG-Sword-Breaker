-- Ventana de Misiones (el puesto "Misiones" del hub): tres misiones diarias y tres semanales con su
-- barra de progreso y su recompensa en tickets (con los que se compran pases en la Tienda). El servidor cuenta el progreso y lo publica en
-- el atributo "Missions" (JSON); las misiones del día se calculan igual aquí con shared/MissionList.
-- Dos pestañas (pedido por el usuario): "Misiones" (Body.Missions) y "Comprar" (Body.Shop), donde se gastan los tickets
-- en lo de Config.Tickets.Shop: una tarjeta Offer_<n> por objeto, con su botón Buy (BuyTicketItem; server/TicketShop).
-- La primera oferta (el Trébol de la suerte) va arriba en grande, con su escaparate (rombos, rayos que giran y el logo
-- flotando); las demás, en una fila de tarjetas del color de cada una. Un solo bucle anima el escaparate mientras la
-- pestaña está a la vista; con el ratón encima las tarjetas crecen y al comprar dan un bote.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local MissionList = require(ReplicatedStorage.Shared.MissionList)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Performance = require(script.Parent.Performance)
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
	{ "daily", Lang.t(nil, "Daily missions"), Color3.fromRGB(80, 200, 255) },
	{ "weekly", Lang.t(nil, "Weekly missions"), Color3.fromRGB(190, 120, 255) },
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
	local window, body = Ui.window("Missions", Lang.t(nil, "Missions"), Vector2.new(660, 652), function(parent)
		Ui.image(parent, "misiones")
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
	for order, entry in { { "Missions", Lang.t(nil, "Missions"), Ui.COLORS.blue }, { "Shop", Lang.t(nil, "Buy"), Ui.COLORS.orange } } do
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

	-- Comprar: lo de Config.Tickets.Shop. La primera oferta va arriba en grande y las demás en una fila debajo.
	local RunService = game:GetService("RunService")
	local ORANGE = Color3.fromRGB(255, 160, 40)
	local HERO_HEIGHT = 196
	local STRIP_HEIGHT = 34
	local offers = {}
	local function ease(target: Instance, time: number, style: Enum.EasingStyle, goal)
		TweenService:Create(target, TweenInfo.new(time, style, Enum.EasingDirection.Out), goal):Play()
	end
	-- Botón de compra con el ticket y el precio; lo que tiene en común cada tarjeta (ratón encima, bote al comprar).
	local function wire(index: number, offer, card: Frame, border: UIStroke, buy: TextButton, owned: TextLabel, color: Color3)
		local item = Config.Items[offer.item]
		local scale = Instance.new("UIScale")
		scale.Parent = card
		local ticket = Instance.new("Frame")
		ticket.Name = "Icon"
		ticket.AnchorPoint = Vector2.new(1, 0.5)
		ticket.Position = UDim2.new(0.5, -8, 0.5, 0)
		ticket.Size = UDim2.fromOffset(34, 34)
		ticket.BackgroundTransparency = 1
		ticket.Parent = buy
		Ui.ticketIcon(ticket, GOLD)
		Ui.sparkle(buy, 3)
		card.MouseEnter:Connect(function()
			if not Performance.get() then
				ease(scale, 0.18, Enum.EasingStyle.Back, { Scale = 1.04 })
			end
			ease(border, 0.15, Enum.EasingStyle.Quad, { Color = item.color:Lerp(WHITE, 0.55) })
		end)
		card.MouseLeave:Connect(function()
			ease(scale, 0.18, Enum.EasingStyle.Quad, { Scale = 1 })
			ease(border, 0.2, Enum.EasingStyle.Quad, { Color = BLACK })
		end)
		buy.Activated:Connect(function()
			local missing = offer.price - (player:GetAttribute("Item_missionToken") or 0)
			if missing > 0 then
				Sfx.play("error")
				Ui.toast(Lang.t(nil, "You need {n} more tickets", { n = missing }), Ui.COLORS.orange)
				return
			end
			Remotes.BuyTicketItem:FireServer(index)
		end)
		-- Al llegar lo comprado: la tarjeta da un bote.
		local before = player:GetAttribute("Item_" .. offer.item) or 0
		player:GetAttributeChangedSignal("Item_" .. offer.item):Connect(function()
			local now = player:GetAttribute("Item_" .. offer.item) or 0
			if now > before and window.Visible and not Performance.get() then
				scale.Scale = 1.1
				ease(scale, 0.35, Enum.EasingStyle.Back, { Scale = 1 })
			end
			before = now
		end)
		offers[index] = { offer = offer, buy = buy, owned = owned, color = color, glint = buy:FindFirstChild("Glint") }
	end
	-- Chip "x3" con lo que ya se tiene, en la esquina de arriba a la derecha.
	local function ownedChip(parent: Instance): TextLabel
		local chip = Instance.new("Frame")
		chip.Name = "Owned"
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -6, 0, 6)
		chip.Size = UDim2.fromOffset(46, 24)
		chip.Parent = parent
		Ui.pill(chip, Color3.fromRGB(26, 28, 52), 8)
		local text = Ui.label(chip, 16)
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		return text
	end

	-- Oferta grande.
	local heroArt = nil
	do
		local offer = Config.Tickets.Shop[1]
		local item = Config.Items[offer.item]
		local color = item.color
		local card = Instance.new("Frame")
		card.Name = "Offer_1"
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, 2)
		card.Size = UDim2.new(1, -24, 0, HERO_HEIGHT)
		card.BackgroundColor3 = WHITE
		card.Parent = shopPane
		Ui.round(card, 14)
		local border = Ui.stroke(card, BLACK, 4)
		Ui.gradient(card, Color3.fromRGB(50, 96, 104):Lerp(color, 0.25), Color3.fromRGB(22, 30, 54), 90)

		-- Escaparate: rombos, rayos que giran y el logo flotando.
		local art = Instance.new("Frame")
		art.Name = "Art"
		art.Position = UDim2.fromOffset(8, 8)
		art.Size = UDim2.new(0, 210, 1, -16)
		art.BackgroundColor3 = WHITE
		art.ClipsDescendants = true
		art.Parent = card
		Ui.round(art, 10)
		Ui.stroke(art, color:Lerp(WHITE, 0.6), 3)
		Ui.gradient(art, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.35), 90)
		local pattern = Instance.new("ImageLabel")
		pattern.Name = "Pattern"
		pattern.Size = UDim2.fromScale(1, 1)
		pattern.BackgroundTransparency = 1
		pattern.Image = Ui.IMAGES.boton_patron
		pattern.ImageTransparency = 0.82
		pattern.ScaleType = Enum.ScaleType.Tile
		pattern.TileSize = UDim2.fromOffset(40, 40)
		pattern.Parent = art
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromOffset(330, 330)
		rays.BackgroundTransparency = 1
		rays.Image = Ui.IMAGES.boton_rayos
		rays.ImageTransparency = 0.7
		rays.Parent = art
		local logo = Instance.new("Frame")
		logo.Name = "Logo"
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.48)
		logo.Size = UDim2.fromOffset(132, 132)
		logo.BackgroundTransparency = 1
		logo.Parent = art
		Ui.image(logo, item.image)
		local tag = Ui.label(art, 34)
		tag.Name = "Tag"
		tag.AnchorPoint = Vector2.new(1, 1)
		tag.Position = UDim2.new(1, -8, 1, -2)
		tag.Size = UDim2.fromOffset(120, 40)
		tag.TextXAlignment = Enum.TextXAlignment.Right
		tag.Rotation = -6
		tag.Text = `x{Config.Clover.Luck}`
		Ui.gradient(tag, WHITE, Color3.fromRGB(255, 225, 90), 90)
		heroArt = { rays = rays, logo = logo, time = 0 }

		local title = Ui.label(card, 30)
		title.Name = "Title"
		title.Position = UDim2.fromOffset(232, 10)
		title.Size = UDim2.new(1, -232 - 64, 0, 36)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextScaled = true
		title.Text = Lang.t(nil, item.name)
		local titleLimit = Instance.new("UITextSizeConstraint")
		titleLimit.MaxTextSize = 30
		titleLimit.MinTextSize = 16
		titleLimit.Parent = title
		Ui.gradient(title, WHITE, color:Lerp(WHITE, 0.35), 90)
		local desc = Ui.label(card, 18)
		desc.Name = "Desc"
		desc.Position = UDim2.fromOffset(232, 50)
		desc.Size = UDim2.new(1, -232 - 14, 0, 64)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.TextColor3 = Color3.fromRGB(215, 225, 240)
		desc.Text = Lang.t(nil, "Pick an object on your plot: {luck} weapon luck, on top of all the luck you already have.", { luck = `<font color="#{Color3.fromRGB(255, 225, 90):ToHex()}">x{Config.Clover.Luck}</font>` })
		local owned = ownedChip(card)

		local buy = Ui.button(card, `        {offer.price}`, Ui.COLORS.green)
		buy.Name = "Buy"
		-- Anclado por su centro (a la derecha del escaparate) para que al crecer con el ratón no se salga de la tarjeta.
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 109, 1, -12)
		buy.Size = UDim2.new(1, -232 - 14, 0, 58)
		buy.TextSize = 32
		wire(1, offer, card, border, buy, owned, Ui.COLORS.green)
	end

	-- Cinta de la fila de abajo.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, HERO_HEIGHT + 12)
	strip.Size = UDim2.new(1, -24, 0, STRIP_HEIGHT)
	strip.BackgroundColor3 = WHITE
	strip.Parent = shopPane
	Ui.round(strip, 10)
	Ui.stroke(strip, BLACK, 3)
	Ui.panel(strip, Color3.fromRGB(120, 84, 200))
	local stripText = Ui.label(strip, 20)
	stripText.Position = UDim2.fromOffset(14, 0)
	stripText.Size = UDim2.new(1, -28, 1, 0)
	stripText.TextXAlignment = Enum.TextXAlignment.Left
	stripText.Text = `{Lang.t(nil, "Max tier potions")} <font color="{Ui.SOFT}">· {math.floor(Config.Potions.Durations[#Config.Potions.Durations] / 60)} min</font>`

	-- Las demás ofertas: una tarjeta estrecha por cada una.
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, HERO_HEIGHT + STRIP_HEIGHT + 22)
	row.Size = UDim2.new(1, -24, 1, -(HERO_HEIGHT + STRIP_HEIGHT + 32))
	row.BackgroundTransparency = 1
	row.Parent = shopPane
	local small = #Config.Tickets.Shop - 1
	local rowGrid = Instance.new("UIGridLayout")
	-- Un píxel de menos por casilla: justas, el redondeo mandaba la última a otra fila.
	rowGrid.CellSize = UDim2.new(1 / small, -math.ceil(8 * (small - 1) / small) - 1, 1, 0)
	rowGrid.CellPadding = UDim2.fromOffset(8, 0)
	rowGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rowGrid.Parent = row
	for index = 2, #Config.Tickets.Shop do
		local offer = Config.Tickets.Shop[index]
		local item = Config.Items[offer.item]
		local family = item.potion and Config.Potions.Families[item.potion.family]
		local color = if family then family.color else item.color
		-- La casilla de la rejilla es un hueco; la tarjeta va dentro, centrada, para crecer desde su centro.
		local slot = Instance.new("Frame")
		slot.Name = "Offer_" .. index
		slot.LayoutOrder = index
		slot.BackgroundTransparency = 1
		slot.Parent = row
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = WHITE
		card.Parent = slot
		Ui.round(card, 12)
		local border = Ui.stroke(card, BLACK, 3)
		Ui.gradient(card, Color3.fromRGB(64, 68, 120):Lerp(color, 0.45), Color3.fromRGB(24, 26, 50):Lerp(color, 0.12), 90)
		-- Resplandor del color detrás del icono.
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0, 62)
		glow.Size = UDim2.fromOffset(150, 150)
		glow.BackgroundTransparency = 1
		glow.Image = Ui.IMAGES.boton_rayos
		glow.ImageColor3 = color:Lerp(WHITE, 0.4)
		glow.ImageTransparency = 0.72
		glow.Parent = card
		card.ClipsDescendants = true

		local cell = Ui.cell(card, item.color, if item.potion then item.potion.tier else nil)
		cell.Name = "Icon"
		cell.AnchorPoint = Vector2.new(0.5, 0)
		cell.Position = UDim2.new(0.5, 0, 0, 20)
		cell.Size = UDim2.fromOffset(84, 84)
		local value = ""
		if item.potion then
			local tier = item.potion.tier
			Potions.icon(cell, item.potion.family, tier)
			Ui.tip(cell, function()
				return Potions.tip(item.potion.family, tier, player:GetAttribute("Item_" .. offer.item) or 0), item.color
			end, true)
			local amount = family.values[tier]
			value = if family.additive then "+" .. Lang.t(nil, "{n}%", { n = math.round(amount * 100) }) else "x" .. Format.multiplier(amount)
		else
			Ui.image(cell, item.image)
			Ui.tip(cell, function()
				return `{Lang.t(nil, item.name)}\n<font color="{Ui.SOFT}">{Lang.t(nil, item.description)}</font>`, item.color
			end, true)
		end

		local name = Ui.label(card, 17)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(6, 108)
		name.Size = UDim2.new(1, -12, 0, 38)
		name.TextWrapped = true
		name.TextScaled = true
		name.Text = Lang.t(nil, if family then family.effect else item.name)
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 17
		nameLimit.MinTextSize = 11
		nameLimit.Parent = name
		local boost = Ui.label(card, 30)
		boost.Name = "Value"
		boost.Position = UDim2.fromOffset(4, 146)
		boost.Size = UDim2.new(1, -8, 0, 34)
		boost.TextScaled = true
		boost.Text = value
		local boostLimit = Instance.new("UITextSizeConstraint")
		boostLimit.MaxTextSize = 30
		boostLimit.MinTextSize = 16
		boostLimit.Parent = boost
		Ui.gradient(boost, WHITE, color:Lerp(WHITE, 0.25), 90)
		local owned = ownedChip(card)

		local buy = Ui.button(card, `      {offer.price}`, ORANGE)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -8)
		buy.Size = UDim2.new(1, -14, 0, 44)
		buy.TextSize = 24
		wire(index, offer, card, border, buy, owned, ORANGE)
		local ticket = buy:FindFirstChild("Icon") :: Frame
		ticket.Size = UDim2.fromOffset(28, 28)
		ticket.Position = UDim2.new(0.5, -4, 0.5, 0)
	end

	-- Escaparate de la oferta grande: un bucle que solo vive con la pestaña a la vista (y no en modo rendimiento).
	local artLoop: RBXScriptConnection? = nil
	local function animateArt()
		local on = window.Visible and shopPane.Visible and not Performance.get()
		if on and not artLoop then
			artLoop = RunService.RenderStepped:Connect(function(dt)
				heroArt.time += dt
				heroArt.rays.Rotation = heroArt.time * 22
				heroArt.logo.Position = UDim2.fromScale(0.5, 0.48 + math.sin(heroArt.time * 2.4) * 0.03)
				heroArt.logo.Rotation = math.sin(heroArt.time * 1.7) * 5
			end)
		elseif not on and artLoop then
			artLoop:Disconnect()
			artLoop = nil
		end
	end
	window:GetPropertyChangedSignal("Visible"):Connect(animateArt)
	shopPane:GetPropertyChangedSignal("Visible"):Connect(animateArt)
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
			Ui.ticketIcon(coin, GOLD)

			local claim = Ui.button(row, Lang.t(nil, "Claim"), Ui.COLORS.green)
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
			entry.buy.BackgroundColor3 = if enough then entry.color else Color3.fromRGB(96, 98, 118)
			entry.buy.TextColor3 = if enough then WHITE else Color3.fromRGB(190, 192, 205)
			entry.glint.Visible = enough and not Performance.get()
			entry.owned.Text = `x{Format.short(player:GetAttribute("Item_" .. entry.offer.item) or 0)}`
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
			section.countdown.Text = Lang.t(nil, "Resets in {time}", { time = timeLeft(MissionList.secondsLeft(key, now)) })
			for index, mission in MissionList.pick(key, id) do
				local row = section.rows[index]
				row.mission = mission
				local done = math.min(progress[mission.id] or 0, mission.goal)
				row.text.Text = Lang.t(nil, mission.text)
				row.reward.Text = `+{mission.reward}`
				row.fill.Size = UDim2.fromScale(done / mission.goal, 1)
				row.progress.Text = `{Format.short(math.floor(done))} / {Format.short(mission.goal)}`
				local isClaimed = claimed[mission.id] == true
				local ready = not isClaimed and done >= mission.goal
				-- Verde = se puede cobrar; gris apagado = aún no; oscuro con texto verde = ya cobrada.
				row.claim.Text = Lang.t(nil, if isClaimed then "Claimed" else "Claim")
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
