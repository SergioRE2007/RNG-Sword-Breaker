-- Panel "Eventos" del menú de admin (client/AdminPanel lo monta en su pestaña; librería sin start()): el mensaje
-- grande y los eventos de admin (Config.AdminEvents: un multiplicador para todos durante un rato). Solo pide: las
-- órdenes van por AdminCommand ("banner", "boost", "stopBoost") y server/AdminCommands las comprueba. Van a este
-- servidor o a todos según client/AdminScope.
--   `Body.Events.Card.Content`: `MessageRow.Message` y `.Send`; `Stats.Stat_<stat>` (qué se multiplica), `Inputs.Mult`,
--     `Inputs.Minutes` e `Inputs.Start`; `Active.Row_<stat>` (los que hay en marcha, con su `Stop`).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Stats = require(ReplicatedStorage.Shared.Stats)
local AdminScope = require(script.Parent.AdminScope)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local AdminEvents = {}

local cfg = Config.AdminEvents
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(40, 38, 80)
local PAD = 12
local GAP = 8
local ROW = 44 -- alto de botones y cajas
local STAT = 40 -- alto de los botones de stat
local ACTIVE = 36 -- alto de cada evento en marcha

local function heading(parent: Instance, name: string, text: string, y: number): TextLabel
	local label = Ui.label(parent, 18)
	label.Name = name
	label.Position = UDim2.fromOffset(4, y)
	label.Size = UDim2.new(1, -8, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	return label
end

local function field(parent: Instance, name: string, placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.TextSize = 22
	box.ClearTextOnFocus = false
	box.PlaceholderText = placeholder
	box.Text = ""
	box.Parent = parent
	Ui.field(box)
	return box
end

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

function AdminEvents.build(pane: Frame, window: Frame)
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Position = UDim2.fromOffset(PAD, PAD)
	frame.Size = UDim2.new(1, -PAD * 2, 1, -PAD * 2)
	frame.Parent = pane
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, PANEL)
	-- Ui.panel mete sus piezas como hijos: el contenido va en un marco de dentro.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(10, 8)
	content.Size = UDim2.new(1, -20, 1, -16)
	content.BackgroundTransparency = 1
	content.Parent = frame

	-- Mensaje grande ------------------------------------------------------------------------------
	local messageTitle = heading(content, "MessageTitle", "", 0)
	local messageRow = Instance.new("Frame")
	messageRow.Name = "MessageRow"
	messageRow.Position = UDim2.fromOffset(0, 28)
	messageRow.Size = UDim2.new(1, 0, 0, ROW)
	messageRow.BackgroundTransparency = 1
	messageRow.Parent = content
	local message = field(messageRow, "Message", Lang.t(nil, "Write a message for everyone"))
	message.Size = UDim2.new(1, -(120 + GAP), 1, 0)
	message.TextSize = 18
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.ClipsDescendants = true
	local messagePad = Instance.new("UIPadding")
	messagePad.PaddingLeft = UDim.new(0, 10)
	messagePad.PaddingRight = UDim.new(0, 10)
	messagePad.Parent = message
	local send = Ui.button(messageRow, Lang.t(nil, "Send"), Ui.COLORS.green)
	send.Name = "Send"
	send.AnchorPoint = Vector2.new(1, 0)
	send.Position = UDim2.fromScale(1, 0)
	send.Size = UDim2.new(0, 120, 1, 0)
	send.TextSize = 18
	send.Activated:Connect(function()
		if string.match(message.Text, "^%s*$") then
			Sfx.play("error")
			return
		end
		AdminScope.command("banner", string.sub(message.Text, 1, cfg.MaxMessage))
		message.Text = ""
	end)

	-- Evento nuevo --------------------------------------------------------------------------------
	local top = 28 + ROW + 14
	local eventTitle = heading(content, "EventTitle", "", top)
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Position = UDim2.fromOffset(0, top + 28)
	stats.Size = UDim2.new(1, 0, 0, STAT * 2 + GAP)
	stats.BackgroundTransparency = 1
	stats.Parent = content
	local statLayout = Instance.new("UIGridLayout")
	statLayout.CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3) - 1, 0, STAT)
	statLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Parent = stats
	local chosen = cfg.Order[1]
	local statButtons: { [string]: TextButton } = {}
	for order, stat in cfg.Order do
		local def = cfg.Stats[stat]
		local button = Ui.button(stats, Lang.t(nil, def.name), def.color:Lerp(BLACK, 0.35))
		button.Name = "Stat_" .. stat
		button.LayoutOrder = order
		button.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 17
		limit.MinTextSize = 11
		limit.Parent = button
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 9)
		pad.Parent = button
		statButtons[stat] = button
		button.Activated:Connect(function()
			chosen = stat
			for other, item in statButtons do
				Ui.setSelected(item, other == chosen)
			end
		end)
	end
	for other, item in statButtons do
		Ui.setSelected(item, other == chosen)
	end

	-- Multiplicador ("x" delante), minutos ("min" detrás) y empezar.
	local inputs = Instance.new("Frame")
	inputs.Name = "Inputs"
	inputs.Position = UDim2.fromOffset(0, top + 28 + STAT * 2 + GAP * 2)
	inputs.Size = UDim2.new(1, 0, 0, ROW)
	inputs.BackgroundTransparency = 1
	inputs.Parent = content
	local times = Ui.label(inputs, 24)
	times.Name = "Times"
	times.Size = UDim2.new(0, 22, 1, 0)
	times.Text = "x"
	local mult = field(inputs, "Mult", "3")
	mult.Position = UDim2.fromOffset(24, 0)
	mult.Size = UDim2.new(0, 84, 1, 0)
	mult.Text = "3"
	local minutes = field(inputs, "Minutes", "30")
	minutes.Position = UDim2.fromOffset(24 + 84 + GAP * 2, 0)
	minutes.Size = UDim2.new(0, 84, 1, 0)
	minutes.Text = "30"
	local unit = Ui.label(inputs, 18)
	unit.Name = "Unit"
	unit.Position = UDim2.fromOffset(24 + 84 * 2 + GAP * 2 + 6, 0)
	unit.Size = UDim2.new(0, 40, 1, 0)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Text = "min"
	local left = 24 + 84 * 2 + GAP * 2 + 6 + 40 + GAP
	local start = Ui.button(inputs, Lang.t(nil, "Start event"), Ui.COLORS.green)
	start.Name = "Start"
	start.Position = UDim2.fromOffset(left, 0)
	start.Size = UDim2.new(1, -left, 1, 0)
	start.TextSize = 20
	start.Activated:Connect(function()
		-- Con coma o con punto: "2,5" vale.
		local value = tonumber((string.gsub(mult.Text, ",", ".")))
		local time = tonumber(minutes.Text)
		if not value or value <= 1 or value == math.huge or not time or time < 1 or time > cfg.MaxMinutes then
			Sfx.play("error")
			Ui.toast(Lang.t(nil, "That event isn't valid: more than x1 and up to {minutes} min", { minutes = cfg.MaxMinutes }), Ui.COLORS.orange)
			return
		end
		AdminScope.command("boost", chosen, value, math.floor(time))
	end)

	-- Eventos en marcha ---------------------------------------------------------------------------
	local listTop = top + 28 + STAT * 2 + GAP * 2 + ROW + 14
	heading(content, "ActiveTitle", Lang.t(nil, "Events running on this server"), listTop)
	local active = Instance.new("ScrollingFrame")
	active.Name = "Active"
	active.Position = UDim2.fromOffset(0, listTop + 28)
	active.Size = UDim2.new(1, 0, 1, -(listTop + 28))
	active.BackgroundTransparency = 1
	active.BorderSizePixel = 0
	active.ScrollBarThickness = 6
	active.CanvasSize = UDim2.new()
	active.AutomaticCanvasSize = Enum.AutomaticSize.Y
	active.ScrollingDirection = Enum.ScrollingDirection.Y
	active.Parent = content
	local activeLayout = Instance.new("UIListLayout")
	activeLayout.Padding = UDim.new(0, 6)
	activeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	activeLayout.Parent = active
	local activePad = Instance.new("UIPadding")
	activePad.PaddingTop = UDim.new(0, 3)
	activePad.PaddingLeft = UDim.new(0, 3)
	activePad.PaddingRight = UDim.new(0, 10)
	activePad.PaddingBottom = UDim.new(0, 6)
	activePad.Parent = active
	local none = Ui.label(active, 16)
	none.Name = "None"
	none.LayoutOrder = 0
	none.Size = UDim2.new(1, 0, 0, ACTIVE)
	none.TextXAlignment = Enum.TextXAlignment.Left
	none.TextColor3 = Color3.fromRGB(185, 192, 214)
	none.Text = Lang.t(nil, "No events right now")

	local rows: { [string]: { frame: Frame, text: TextLabel } } = {}
	for order, stat in cfg.Order do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. stat
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ACTIVE)
		row.BackgroundTransparency = 1
		row.Visible = false
		row.Parent = active
		local text = Ui.label(row, 18)
		text.Name = "Text"
		text.Position = UDim2.fromOffset(4, 0)
		text.Size = UDim2.new(1, -(104 + GAP), 1, 0)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		local stop = Ui.button(row, Lang.t(nil, "Stop"), Ui.COLORS.red)
		stop.Name = "Stop"
		stop.AnchorPoint = Vector2.new(1, 0)
		stop.Position = UDim2.fromScale(1, 0)
		stop.Size = UDim2.new(0, 100, 1, 0)
		stop.TextSize = 16
		stop.Activated:Connect(function()
			AdminScope.command("stopBoost", stat)
		end)
		rows[stat] = { frame = row, text = text }
		local function changed()
			if window.Visible and pane.Visible then
				AdminEvents.refresh()
			end
		end
		workspace:GetAttributeChangedSignal("Boost_" .. stat):Connect(changed)
		workspace:GetAttributeChangedSignal("BoostEnd_" .. stat):Connect(changed)
	end

	function AdminEvents.refresh()
		local any = false
		local now = workspace:GetServerTimeNow()
		for _, stat in cfg.Order do
			local def = cfg.Stats[stat]
			local value = Stats.boost(stat)
			local row = rows[stat]
			row.frame.Visible = value > 1
			if value > 1 then
				any = true
				local leftover = (workspace:GetAttribute("BoostEnd_" .. stat) or now) - now
				row.text.Text = `<font color="{hex(def.color:Lerp(WHITE, 0.3))}">x{Format.multiplier(value)} {Lang.t(nil, def.name)}</font>  <font color="{Ui.SOFT}">·  {PotionInfo.clock(leftover)}</font>`
			end
		end
		none.Visible = not any
	end

	-- Los textos que dependen de a qué servidores va la orden.
	local function paintScope()
		messageTitle.Text = Lang.t(nil, if AdminScope.all then "Big message on all servers" else "Big message on this server")
		eventTitle.Text = Lang.t(nil, if AdminScope.all then "New event on all servers" else "New event on this server")
	end
	AdminScope.Changed:Connect(paintScope)
	paintScope()

	-- Los relojes: se repintan con el panel a la vista.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if window.Visible and pane.Visible then
				AdminEvents.refresh()
			end
		end
	end)
	pane:GetPropertyChangedSignal("Visible"):Connect(AdminEvents.refresh)
	AdminEvents.refresh()
end

return AdminEvents
