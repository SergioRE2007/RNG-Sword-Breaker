-- Menú de admin: una ventana que solo existe para los administradores del juego (atributo "Admin" del jugador, que
-- pone server/Admin: el dueño y los de Config.Admins; en Studio, con Config.Test.Admin). A los demás no se les crea
-- ni el botón ni la ventana, y aunque alguien se la fabricara, el servidor comprueba cada orden.
-- De momento lleva el clima: una casilla por clima de Config.Weather (pulsarla lo pone ya en este servidor, para todos
-- y con su suerte), despejar el cielo y volver al calendario. Botón `Hud.HudRoot.Menu.Admin`, ventana `Hud.Admin`
-- (`Body.Status`, `Body.Grid.Weather_<id>`, `Body.Actions.Clear` y `.Auto`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)
local Ui = require(script.Parent.Ui)
local WeatherHud = require(script.Parent.WeatherHud)

local AdminPanel = {}

local player = Players.LocalPlayer
local cfg = Config.Weather

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local ON = Color3.fromRGB(85, 210, 70)

-- Medidas de la ventana (en su tamaño de diseño; Ui.window la encoge sola en pantallas pequeñas).
local PAD = 12
local STATUS = 62
local COLUMNS = 4
local CELL = Vector2.new(130, 120)
local GAP = 10
local ROWS = math.ceil(#cfg.Order / COLUMNS)
local GRID_HEIGHT = ROWS * CELL.Y + (ROWS - 1) * GAP
local ACTIONS = 52
local BODY_HEIGHT = PAD + STATUS + 34 + GRID_HEIGHT + PAD + ACTIONS + PAD

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local function build()
	local window, body = Ui.window("Admin", "Admin", Vector2.new(600, BODY_HEIGHT + 78), function(parent)
		Ui.starIcon(parent, GOLD)
	end)

	-- Qué clima hay ahora y si es del calendario o está puesto a mano.
	local status = Instance.new("Frame")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(PAD, PAD)
	status.Size = UDim2.new(1, -PAD * 2, 0, STATUS)
	status.Parent = body
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

	local heading = Ui.label(body, 18)
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
	grid.Parent = body
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
	actions.Parent = body
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

	-- Estado: se repinta cuando cambia el clima y, con la ventana abierta, el reloj unas veces por segundo.
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
		if elapsed >= 0.25 and window.Visible then
			elapsed = 0
			refresh()
		end
	end)

	-- Botón en el menú de la izquierda, como los demás (logo arriba y nombre debajo).
	local menu = Ui.hud():WaitForChild("Menu")
	local item = Ui.button(menu, "", Color3.fromRGB(196, 70, 86))
	item.Name = "Admin"
	item.LayoutOrder = 99
	local iconBox = Instance.new("Frame")
	iconBox.Name = "Icon"
	iconBox.AnchorPoint = Vector2.new(0.5, 0)
	iconBox.Position = UDim2.new(0.5, 0, 0, 2)
	iconBox.Size = UDim2.fromOffset(68, 68)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = item
	Ui.starIcon(iconBox, GOLD)
	local label = Ui.label(item, 18)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -5)
	label.Size = UDim2.new(1, -8, 0, 20)
	label.Text = "Admin"
	Ui.sparkle(item, 6)
	item.Activated:Connect(function()
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
