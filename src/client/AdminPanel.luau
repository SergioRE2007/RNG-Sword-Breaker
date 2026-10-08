-- Menú de admin: una ventana que solo existe para los administradores del juego (atributo "Admin" del jugador, que
-- pone server/Admin: el dueño y los de Config.Admins; en Studio, con Config.Test.Admin). A los demás no se les crea
-- ni el botón ni la ventana, y aunque alguien se la fabricara, el servidor comprueba cada orden.
-- La ventana `Hud.Admin` lleva un panel por pestaña (como la mochila): `TabWeather` y `Body.Weather`, de momento. Un
-- panel nuevo = una entrada en PANELS con su función, que recibe el marco donde montarse. El botón es pequeño y va
-- arriba a la izquierda, junto al de Ajustes: `Hud.HudRoot.TopButtons.Admin`.
-- Panel del clima: una casilla por clima de Config.Weather (pulsarla lo pone ya en este servidor, para todos y con
-- su suerte), despejar el cielo y volver al calendario (`Body.Weather.Status`, `.Grid.Weather_<id>`, `.Actions.Clear`
-- y `.Auto`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)
local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)
local WeatherHud = require(script.Parent.WeatherHud)

local AdminPanel = {}

local player = Players.LocalPlayer
local cfg = Config.Weather

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local ON = Color3.fromRGB(85, 210, 70)

-- Medidas del panel del clima, que es el que da el tamaño a la ventana (en su tamaño de diseño; Ui.window la encoge
-- sola en pantallas pequeñas).
local PAD = 12
local STATUS = 62
local COLUMNS = 4
local CELL = Vector2.new(130, 120)
local GAP = 10
local ROWS = math.ceil(#cfg.Order / COLUMNS)
local GRID_HEIGHT = ROWS * CELL.Y + (ROWS - 1) * GAP
local ACTIONS = 52
local BODY_HEIGHT = PAD + STATUS + 34 + GRID_HEIGHT + PAD + ACTIONS + PAD
-- Pestañas: asoman por la izquierda de la ventana, como las de la mochila.
local TAB = Vector2.new(96, 66)
local TAB_X, TAB_OUT = -108, -118
local TAB_STEP = 78

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Panel del clima. `pane` es su marco dentro de la ventana y `window`, la ventana (para saber si está abierta).
local function weatherPanel(pane: Frame, window: Frame)
	-- Qué clima hay ahora y si es del calendario o está puesto a mano.
	local status = Instance.new("Frame")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(PAD, PAD)
	status.Size = UDim2.new(1, -PAD * 2, 0, STATUS)
	status.Parent = pane
	Ui.round(status, 12)
	Ui.stroke(status, BLACK, 3)
	Ui.panel(status, Color3.fromRGB(40, 38, 80))
	local badgeBox = Instance.new("Frame")
	badgeBox.Name = "BadgeBox"
	badgeBox.AnchorPoint = Vector2.new(0, 0.5)
	badgeBox.Position = UDim2.new(0, 10, 0.5, 0)
	badgeBox.Size = UDim2.fromOffset(44, 44)
	badgeBox.BackgroundTransparency = 1
	badgeBox.Parent = status
	local now = Ui.label(status, 21)
	now.Name = "Now"
	now.Position = UDim2.fromOffset(64, 7)
	now.Size = UDim2.new(1, -74, 0, 26)
	now.TextXAlignment = Enum.TextXAlignment.Left
	local detail = Ui.label(status, 15)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(64, 33)
	detail.Size = UDim2.new(1, -74, 0, 20)
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local heading = Ui.label(pane, 18)
	heading.Name = "Heading"
	heading.Position = UDim2.fromOffset(PAD + 4, PAD + STATUS + 6)
	heading.Size = UDim2.new(1, -PAD * 2 - 8, 0, 24)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = `Clima de este servidor  <font color="{Ui.SOFT}" size="14">·  lo ve y lo nota todo el que esté dentro</font>`

	-- Una casilla por clima, con el borde del color de su rareza.
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(PAD, PAD + STATUS + 34)
	grid.Size = UDim2.new(1, -PAD * 2, 0, GRID_HEIGHT)
	grid.BackgroundTransparency = 1
	grid.Parent = pane
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local tags: { [string]: TextLabel } = {}
	for order, id in cfg.Order do
		local def = cfg.Events[id]
		local tier = WeatherInfo.tier(def)
		local cell = Ui.cell(grid, tier.color, def.tier)
		cell.Name = "Weather_" .. id
		cell.LayoutOrder = order
		local badge = WeatherHud.badge(cell, 56, id)
		badge.AnchorPoint = Vector2.new(0.5, 0)
		badge.Position = UDim2.new(0.5, 0, 0, 10)
		local name = Ui.label(cell, 15)
		name.Name = "Label"
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -5)
		name.Size = UDim2.new(1, -8, 0, 42)
		name.TextWrapped = true
		name.Text = def.name
		name.ZIndex = 3
		-- Marca del clima que hay puesto.
		local tag = Ui.cellTag(cell, "ON", ON)
		tag.Size = UDim2.fromOffset(34, 22)
		tag.Visible = false
		tags[id] = tag
		Ui.tip(cell, function()
			local minutes = math.floor(WeatherInfo.duration(id) / 60 + 0.5)
			local lines = {
				`<font color="{hex(def.color:Lerp(WHITE, 0.3))}"><b>{def.name}</b></font>`,
				`<font color="{hex(tier.color)}">{tier.name}  ·  {WeatherInfo.oddsText(id)}</font>`,
				WeatherInfo.buffText(def),
				`<font color="{Ui.SOFT}">Pulsa para ponerlo ya: dura {minutes} min.</font>`,
			}
			return table.concat(lines, "\n"), def.color
		end, true)
		cell.Activated:Connect(function()
			Remotes.AdminWeather:FireServer(id)
		end)
	end

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Position = UDim2.fromOffset(PAD, PAD + STATUS + 34 + GRID_HEIGHT + PAD)
	actions.Size = UDim2.new(1, -PAD * 2, 0, ACTIONS)
	actions.BackgroundTransparency = 1
	actions.Parent = pane
	local function action(name: string, text: string, color: Color3, order: number, send: string)
		local button = Ui.button(actions, text, color)
		button.Name = name
		button.AnchorPoint = Vector2.new(order, 0)
		button.Position = UDim2.fromScale(order, 0)
		button.Size = UDim2.new(0.5, -GAP / 2, 1, 0)
		button.TextSize = 20
		button.Activated:Connect(function()
			Remotes.AdminWeather:FireServer(send)
		end)
	end
	action("Clear", "Despejar el cielo", Ui.COLORS.blue, 0, "none")
	action("Auto", "Volver al calendario", Ui.COLORS.green, 1, "auto")

	-- Estado: se repinta cuando cambia el clima y, con el panel a la vista, el reloj unas veces por segundo.
	local shownId: string? = "?"
	local function refresh()
		local id, def = WeatherInfo.current()
		if id ~= shownId then
			shownId = id
			badgeBox:ClearAllChildren()
			WeatherHud.badge(badgeBox, 44, id)
			for other, tag in tags do
				tag.Visible = other == id
			end
		end
		local forced = workspace:GetAttribute("WeatherForced") == true
		local origin = if forced then `<font color="{hex(GOLD)}">Puesto a mano</font>` else "Del calendario"
		local clock = workspace:GetServerTimeNow()
		local goal = workspace:GetAttribute(if id then "WeatherEnds" else "WeatherNext")
		local left = PotionInfo.clock(math.max(0, if type(goal) == "number" then goal - clock else 0))
		if id and def then
			now.Text = `<font color="{hex(def.color:Lerp(WHITE, 0.45))}">{def.name}</font>  <font color="{Ui.SOFT}" size="15">x{Format.multiplier(def.luck)} de suerte</font>`
			detail.Text = `{origin}  <font color="{Ui.SOFT}">·  quedan {left}</font>`
		else
			now.Text = "Cielo despejado"
			detail.Text = `{origin}  <font color="{Ui.SOFT}">·  siguiente clima en {left}</font>`
		end
	end
	for _, attribute in { "Weather", "WeatherEnds", "WeatherNext", "WeatherForced" } do
		workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.25 and window.Visible and pane.Visible then
			elapsed = 0
			refresh()
		end
	end)
end

-- Los paneles del menú, en el orden de sus pestañas: clave (nombres `Tab<clave>` y `Body.<clave>`), nombre de la
-- pestaña, su color, su icono y la función que lo monta.
local PANELS = {
	{
		key = "Weather", name = "Clima", color = Color3.fromRGB(60, 150, 235),
		icon = function(parent: Frame)
			local badge = WeatherHud.badge(parent, 44, "rain")
			badge.AnchorPoint = Vector2.new(0.5, 0.5)
			badge.Position = UDim2.fromScale(0.5, 0.5)
		end,
		build = weatherPanel,
	},
}

local function build()
	local window, body = Ui.window("Admin", "Admin", Vector2.new(600, BODY_HEIGHT + 78), function(parent)
		Ui.starIcon(parent, GOLD)
	end)

	local panes: { [string]: Frame } = {}
	local tabs: { [string]: { button: TextButton, y: number } } = {}
	local function show(key: string)
		for other, pane in panes do
			local opening = other == key and not pane.Visible
			pane.Visible = other == key
			local tab = tabs[other]
			Ui.setSelected(tab.button, other == key)
			-- La pestaña elegida se asoma un poco más y su panel entra deslizándose (sin animar en modo rendimiento).
			local out = UDim2.fromOffset(if other == key then TAB_OUT else TAB_X, tab.y)
			if Performance.get() then
				tab.button.Position = out
			else
				TweenService:Create(tab.button, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = out }):Play()
				if opening then
					pane.Position = UDim2.fromOffset(24, 0)
					TweenService:Create(pane, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }):Play()
				end
			end
		end
	end
	for order, panel in PANELS do
		local pane = Instance.new("Frame")
		pane.Name = panel.key
		pane.Size = UDim2.fromScale(1, 1)
		pane.BackgroundTransparency = 1
		pane.Visible = false
		pane.Parent = body
		panes[panel.key] = pane
		panel.build(pane, window)

		local y = TAB.Y + (order - 1) * TAB_STEP
		local tab = Ui.button(window, "", panel.color)
		tab.Name = "Tab" .. panel.key
		tab.Position = UDim2.fromOffset(TAB_X, y)
		tab.Size = UDim2.fromOffset(TAB.X, TAB.Y)
		local iconBox = Instance.new("Frame")
		iconBox.Name = "Icon"
		iconBox.AnchorPoint = Vector2.new(0.5, 0)
		iconBox.Position = UDim2.new(0.5, 0, 0, -1)
		iconBox.Size = UDim2.fromOffset(50, 50)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = tab
		panel.icon(iconBox)
		local label = Ui.label(tab, 15)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -3)
		label.Size = UDim2.new(1, -6, 0, 17)
		label.Text = panel.name
		label.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 15
		limit.MinTextSize = 11
		limit.Parent = label
		tabs[panel.key] = { button = tab, y = y }
		tab.Activated:Connect(function()
			show(panel.key)
		end)
	end
	show(PANELS[1].key)

	-- Botón pequeño arriba a la izquierda, junto al de Ajustes y del mismo tamaño.
	local button = Ui.button(Ui.topButtons(), "", Color3.fromRGB(196, 70, 86))
	button.Name = "Admin"
	button.LayoutOrder = 100
	button.Size = UDim2.fromOffset(44, 44)
	Ui.starIcon(button, GOLD)
	Ui.tip(button, function()
		return "<b>Admin</b>", GOLD
	end, true)
	button.Activated:Connect(function()
		Ui.toggle("Admin")
	end)
end

function AdminPanel.start()
	-- El atributo puede llegar después de arrancar (el servidor lo decide al entrar): se monta una sola vez.
	local built = false
	local function check()
		if not built and player:GetAttribute("Admin") == true then
			built = true
			build()
		end
	end
	player:GetAttributeChangedSignal("Admin"):Connect(check)
	check()
end

return AdminPanel
