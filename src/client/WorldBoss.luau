-- Jefe del mundo en el cliente: el panel `Hud.HudRoot.WorldBoss` (arriba en el centro, como el de las mazmorras) y los
-- avisos del servidor (remote WorldBoss) que pasan a client/WorldBossFx. El estado sale de los atributos de workspace
-- (WorldBossState, WorldBossFall, WorldBossEnds) y del atributo "WorldBoss" del jugador (está en la arena).
--   · Portal abierto o pelea en marcha, fuera de la arena: tarjeta pequeña con la cuenta atrás y el botón `Go`, que
--     lleva delante del portal (Teleport "portal").
--   · En la arena: tu daño y el del siguiente tramo de premios (el rey no tiene vida; la barra se pone azul con escudo y
--     amarilla aturdido), barra de carga
--     del súper golpe, los LIVE_ROWS que más daño llevan y tu puesto, y `Leave`.
--   · Al irse: la tabla con el daño de cada uno (hasta ROWS) y lo que te ha tocado, durante RESULT_TIME s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WorldBossInfo = require(ReplicatedStorage.Shared.WorldBossInfo)
local Ui = require(script.Parent.Ui)
local WorldBossFx = require(script.Parent.WorldBossFx)

local WorldBoss = {}

local cfg = Config.WorldBoss
local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BASE = Color3.fromRGB(58, 40, 96)
local ACCENT = Color3.fromRGB(150, 220, 110)
local HP_COLORS = { normal = Color3.fromRGB(110, 220, 90), shield = Color3.fromRGB(90, 170, 255), stun = Color3.fromRGB(255, 215, 70) }
local GOLD = Color3.fromRGB(255, 210, 80)
local WIDTH = 470
local ROWS = 8 -- filas de la tabla final (los servidores son de 8)
local LIVE_ROWS = 5 -- filas durante la pelea
local RESULT_TIME = 12

local panel: Frame
local title: TextLabel
local detail: TextLabel
local action: TextButton
local hpTrack: Frame
local hpFill: Frame
local hpText: TextLabel
local chargeTrack: Frame
local chargeFill: Frame
local chargeText: TextLabel
local list: Frame
local rows: { Frame } = {}
local youText: TextLabel
local prizeText: TextLabel

local lastRank = nil -- último "rank" del servidor
local result = nil -- { data, until }
local charge = nil -- { from, to } (hora del servidor)

local function inside(): boolean
	return player:GetAttribute("WorldBoss") == true
end

local function bossBody(): BasePart?
	local folder = workspace:FindFirstChild("WorldBoss")
	if not folder then
		return nil
	end
	for _, item in folder:GetChildren() do
		if item:IsA("BasePart") and item:GetAttribute("Kind") == "king" then
			return item
		end
	end
	return nil
end

local function bar(name: string, height: number, color: Color3): (Frame, Frame, TextLabel)
	local track = Instance.new("Frame")
	track.Name = name
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = Ui.COLORS.dark
	track.BorderSizePixel = 0
	Ui.round(track, height // 2)
	Ui.stroke(track, BLACK, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Ui.round(fill, height // 2)
	Ui.gradient(fill, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.2), 90)
	local text = Ui.label(track, math.max(height - 8, 12))
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = fill.ZIndex + 1
	return track, fill, text
end

local function setFill(fill: Frame, k: number, color: Color3?)
	fill.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
	fill.Visible = k > 0.001
	if color then
		local gradient = fill:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.2))
		end
	end
end

local function build()
	panel = Instance.new("Frame")
	panel.Name = "WorldBoss"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 90)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = WHITE
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = Ui.hud()
	Ui.round(panel, 14)
	Ui.stroke(panel, BLACK, 4)
	Ui.panel(panel, BASE, ACCENT)

	-- Ui.panel mete sus piezas como hijos: el contenido va en un marco de dentro.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	-- Cabecera: nombre y estado a la izquierda, botón a la derecha.
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.LayoutOrder = 1
	head.Size = UDim2.new(1, 0, 0, 52)
	head.BackgroundTransparency = 1
	head.Parent = content
	title = Ui.label(head, 26)
	title.Name = "Title"
	title.Size = UDim2.new(1, -124, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = Color3.fromRGB(215, 255, 190)
	detail = Ui.label(head, 18)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(0, 30)
	detail.Size = UDim2.new(1, -124, 0, 22)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	action = Ui.button(head, "", Ui.COLORS.green)
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.fromScale(1, 0.5)
	action.Size = UDim2.fromOffset(110, 46)
	action.TextSize = 22
	action.Activated:Connect(function()
		if inside() then
			Remotes.WorldBossRequest:FireServer("leave")
		else
			Remotes.Teleport:FireServer("portal")
		end
	end)

	hpTrack, hpFill, hpText = bar("Damage", 30, HP_COLORS.normal)
	hpTrack.LayoutOrder = 2
	hpTrack.Parent = content
	chargeTrack, chargeFill, chargeText = bar("Charge", 26, Color3.fromRGB(255, 150, 40))
	chargeTrack.LayoutOrder = 3
	chargeTrack.Parent = content

	list = Instance.new("Frame")
	list.Name = "Ranking"
	list.LayoutOrder = 4
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = content
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = list
	for index = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.Parent = list
		local name = Ui.label(row, 17)
		name.Name = "Name"
		name.Size = UDim2.new(1, -120, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = Ui.label(row, 17)
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.new(0, 120, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = row
	end
	youText = Ui.label(content, 17)
	youText.Name = "You"
	youText.LayoutOrder = 5
	youText.Size = UDim2.new(1, 0, 0, 22)
	youText.TextXAlignment = Enum.TextXAlignment.Left
	youText.TextColor3 = GOLD
	prizeText = Ui.label(content, 18)
	prizeText.Name = "Prize"
	prizeText.LayoutOrder = 6
	prizeText.Size = UDim2.new(1, 0, 0, 0)
	prizeText.AutomaticSize = Enum.AutomaticSize.Y
	prizeText.TextWrapped = true
	prizeText.TextXAlignment = Enum.TextXAlignment.Left
	prizeText.TextColor3 = Color3.fromRGB(190, 255, 170)
end

-- Rellena la lista con las filas que llegan del servidor ({ userId, name, amount }) y la parte de cada uno.
local function fillRanking(entries, total: number, rank: number?, mine: number?, limit: number)
	local shown = false
	for index, row in rows do
		local entry = if entries and index <= limit then entries[index] else nil
		row.Visible = entry ~= nil
		if entry then
			local me = entry.userId == player.UserId
			shown = shown or me
			local name = row:FindFirstChild("Name") :: TextLabel
			local value = row:FindFirstChild("Value") :: TextLabel
			name.Text = `{index}. {entry.name}`
			value.Text = Format.short(entry.amount)
			local color = if me then GOLD else WHITE
			name.TextColor3 = color
			value.TextColor3 = color
		end
	end
	youText.Visible = not shown and rank ~= nil and (mine or 0) > 0
	if youText.Visible then
		youText.Text = Lang.t(nil, "You: #{rank} · {n}", { rank = rank, n = Format.short(mine or 0) })
	end
end

local function prizeLine(prize): string
	local parts = {
		Lang.t(nil, if prize.rolls == 1 then "+{n} weapon roll" else "+{n} weapon rolls", { n = prize.rolls }),
		Lang.t(nil, "+{n} Trait Crystals", { n = prize.traitCrystal }),
		Lang.t(nil, "+{n} Grade Crystals", { n = prize.gradeCrystal }),
	}
	if prize.potions > 0 then
		table.insert(parts, Lang.t(nil, "+{n} of each potion ({tier})", { n = prize.potions, tier = Config.Potions.Tiers[prize.potionTier] or "" }))
	end
	if prize.tickets > 0 then
		table.insert(parts, Lang.t(nil, if prize.tickets == 1 then "+{n} Ticket" else "+{n} Tickets", { n = prize.tickets }))
	end
	return table.concat(parts, " · ")
end

local function refresh()
	local serverNow = workspace:GetServerTimeNow()
	local state = workspace:GetAttribute("WorldBossState") or "idle"
	local inDungeon = (player:GetAttribute("Dungeon") or 0) ~= 0
	local here = inside()
	local name = Lang.t(nil, cfg.Name)

	if result and serverNow >= result.ends then
		result = nil
	end
	if result then
		local data = result.data
		panel.Visible = not inDungeon
		title.Text = Lang.t(nil, "The {boss} has left!", { boss = name })
		detail.Text = Lang.t(nil, "Damage by player")
		action.Visible = here
		action.Text = Lang.t(nil, "Leave")
		action.BackgroundColor3 = Ui.COLORS.red
		hpTrack.Visible = false
		chargeTrack.Visible = false
		list.Visible = true
		local total = 0
		for _, entry in data.list do
			total += entry.amount
		end
		local mine = nil
		for _, entry in data.list do
			if entry.userId == player.UserId then
				mine = entry.amount
			end
		end
		fillRanking(data.list, total, data.rank, mine, ROWS)
		prizeText.Visible = data.rewards ~= nil
		if data.rewards then
			prizeText.Text = prizeLine(data.rewards)
		end
		return
	end

	prizeText.Visible = false
	if inDungeon or (state ~= "open" and state ~= "fight") then
		panel.Visible = false
		return
	end
	panel.Visible = true
	title.Text = name
	action.Visible = true
	action.Text = Lang.t(nil, if here then "Leave" else "Go")
	action.BackgroundColor3 = if here then Ui.COLORS.red else Ui.COLORS.green

	if state == "open" then
		detail.Text = Lang.t(nil, "Arrives in {time}", { time = WorldBossInfo.clock((workspace:GetAttribute("WorldBossFall") or serverNow) - serverNow) })
		hpTrack.Visible = false
		chargeTrack.Visible = false
		list.Visible = false
		youText.Visible = false
		return
	end

	-- Pelea.
	local left = (workspace:GetAttribute("WorldBossEnds") or serverNow) - serverNow
	local body = bossBody()
	if not here then
		detail.Text = Lang.t(nil, "Fighting now! Leaves in {time}", { time = WorldBossInfo.clock(left) })
		hpTrack.Visible = false
		chargeTrack.Visible = false
		list.Visible = false
		youText.Visible = false
	else
		detail.Text = Lang.t(nil, "Leaves in {time}", { time = WorldBossInfo.clock(left) })
		hpTrack.Visible = body ~= nil
		list.Visible = lastRank ~= nil
		if lastRank then
			fillRanking(lastRank.list, lastRank.total, lastRank.rank, lastRank.mine, LIVE_ROWS)
		else
			youText.Visible = false
		end
		chargeTrack.Visible = charge ~= nil and serverNow < charge.to
		if chargeTrack.Visible then
			setFill(chargeFill, (serverNow - charge.from) / math.max(charge.to - charge.from, 0.1))
			chargeText.Text = Lang.t(nil, "Charging! Break barrels or hide in green")
		end
	end
	-- Arriba, tu daño (el rey no tiene vida); con escudo o aturdido, el aviso en su lugar.
	if body and here then
		local shielded = body:GetAttribute("Shield") == true
		local stunned = (body:GetAttribute("Stunned") or 0) > serverNow
		-- La barra se llena hacia el siguiente tramo de premios (en escala de potencias: los tramos van de 1.000 en 1.000).
		local mine = lastRank and lastRank.mine or 0
		local tiers = cfg.Rewards.Tiers
		local index = WorldBossInfo.tier(mine) or 0
		local goal = tiers[index + 1]
		local from = if index > 0 then tiers[index].damage else 1
		local k = if goal then math.log(math.max(mine, 1) / from) / math.log(goal.damage / from) else 1
		setFill(hpFill, if shielded or stunned then 1 else k, if shielded then HP_COLORS.shield elseif stunned then HP_COLORS.stun else HP_COLORS.normal)
		hpText.Text = if shielded then Lang.t(nil, "Shield! Break the crystals")
			elseif stunned then Lang.t(nil, "Stunned! Extra damage")
			elseif goal then Lang.t(nil, "Your damage: {n} / {goal}", { n = Format.short(mine), goal = Format.short(goal.damage) })
			else Lang.t(nil, "Your damage: {n}", { n = Format.short(mine) })
	end
end

local function onEvent(kind: string, data)
	if kind == "barrage" then
		WorldBossFx.barrage(data)
	elseif kind == "fall" then
		WorldBossFx.waiting(nil)
		WorldBossFx.fall(data.at)
	elseif kind == "charge" then
		charge = { from = workspace:GetServerTimeNow(), to = data.at }
		WorldBossFx.charge(data)
		Ui.toast(Lang.t(nil, "The {boss} is charging a huge slam!", { boss = Lang.t(nil, cfg.Name) }), Color3.fromRGB(255, 150, 40))
	elseif kind == "mega" then
		charge = nil
		WorldBossFx.mega()
	elseif kind == "stun" then
		charge = nil
		WorldBossFx.clearCharge()
		Ui.toast(Lang.t(nil, "Stunned! Hit it now!"), HP_COLORS.stun)
	elseif kind == "shield" then
		if data == true then
			Ui.toast(Lang.t(nil, "Shield up! Break the crystals"), HP_COLORS.shield)
		end
	elseif kind == "launch" then
		WorldBossFx.launch(data)
	elseif kind == "boom" then
		WorldBossFx.boom(data)
	elseif kind == "rank" then
		lastRank = data
	elseif kind == "result" then
		charge = nil
		lastRank = nil
		WorldBossFx.clearCharge()
		result = { data = data, ends = workspace:GetServerTimeNow() + RESULT_TIME }
	end
	refresh()
end

-- Sombra del rey para quien espera en la arena con el portal abierto.
local function updateWaiting()
	local state = workspace:GetAttribute("WorldBossState")
	if state == "open" and inside() then
		WorldBossFx.waiting(workspace:GetAttribute("WorldBossFall"))
	else
		WorldBossFx.waiting(nil)
	end
end

function WorldBoss.start()
	build()
	WorldBossFx.start()
	Remotes.WorldBoss.OnClientEvent:Connect(onEvent)
	for _, attribute in { "WorldBossState", "WorldBossFall" } do
		workspace:GetAttributeChangedSignal(attribute):Connect(function()
			if workspace:GetAttribute("WorldBossState") ~= "fight" then
				charge = nil
			end
			updateWaiting()
			refresh()
		end)
	end
	player:GetAttributeChangedSignal("WorldBoss"):Connect(function()
		updateWaiting()
		refresh()
	end)
	updateWaiting()
	-- Relojes y barras: unas pocas veces por segundo, solo con el panel a la vista o algo en marcha.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		if panel.Visible or result or workspace:GetAttribute("WorldBossState") == "open" or workspace:GetAttribute("WorldBossState") == "fight" then
			refresh()
		end
	end)
	refresh()
end

return WorldBoss
