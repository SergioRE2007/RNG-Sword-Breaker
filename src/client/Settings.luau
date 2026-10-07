-- Ajustes: botón con engranaje arriba a la izquierda (bajo los botones de Roblox) y una ventana con
-- el modo rendimiento, el volumen de la música y la venta automática de espadas. Cada ajuste vive
-- en el cliente (el modo rendimiento y el volumen solo duran la sesión; la venta automática la
-- guarda el servidor). La música todavía no existe: cuando se añada, sus Sound deben ir en el
-- SoundGroup "Music" de SoundService, que es el que mueve el deslizador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local Settings = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DEFAULT_VOLUME = 0.5

local function musicGroup(): SoundGroup
	local group = SoundService:FindFirstChild("Music") :: SoundGroup?
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "Music"
		group.Volume = DEFAULT_VOLUME
		group.Parent = SoundService
	end
	return group :: SoundGroup
end

-- Fila de un ajuste: marco con título y una línea de explicación; devuelve el marco.
-- `withSlider`: la fila lleva una barra abajo y nada a la derecha, así que la descripción usa todo el
-- ancho en una línea (con el margen de un botón a la derecha bajaría hasta la barra).
-- `accent`: color de la franja de la izquierda (cada ajuste el suyo, para distinguirlos de un vistazo).
local function row(parent: Instance, order: number, title: string, hint: string, withSlider: boolean?, accent: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -16, 0, 104)
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.panel(frame, Color3.fromRGB(50, 54, 78), accent)
	local heading = Ui.label(frame, 24)
	heading.Position = UDim2.fromOffset(18, 8)
	heading.Size = UDim2.new(1, -170, 0, 30)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	local detail = Ui.label(frame, 17)
	detail.Position = UDim2.fromOffset(18, 38)
	detail.Size = if withSlider then UDim2.new(1, -28, 0, 24) else UDim2.new(1, -170, 0, 56)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextWrapped = true
	detail.TextColor3 = Color3.fromRGB(190, 195, 215)
	detail.Text = hint
	return frame
end

function Settings.start()
	local gui = Ui.hud()
	local window, body = Ui.window("Settings", "Ajustes", Vector2.new(560, 544), Ui.gearIcon)

	local list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.Parent = list

	-- Modo rendimiento -------------------------------------------------------------------
	local performanceRow = row(list, 1, "Modo rendimiento", "Quita partículas, auras, luces, nubes, sombras y animaciones de los menús. Úsalo si el juego va lento (en móvil viene activado).", false, Ui.COLORS.orange)
	local performanceButton = Ui.button(performanceRow, "", Ui.COLORS.gray)
	performanceButton.AnchorPoint = Vector2.new(1, 0.5)
	performanceButton.Position = UDim2.new(1, -14, 0.5, 0)
	performanceButton.Size = UDim2.fromOffset(130, 60)
	performanceButton.TextSize = 26
	local function paintPerformance()
		local on = Performance.get()
		performanceButton.Text = if on then "SÍ" else "NO"
		performanceButton.BackgroundColor3 = if on then Ui.COLORS.green else Ui.COLORS.gray
	end
	performanceButton.Activated:Connect(function()
		Performance.set(not Performance.get())
		paintPerformance()
	end)
	paintPerformance()

	-- Volumen de la música ---------------------------------------------------------------
	local volumeRow = row(list, 2, "Volumen de la música", "Aún no hay música; el volumen queda guardado para cuando llegue.", true, Color3.fromRGB(190, 120, 255))
	local group = musicGroup()
	local percent = Ui.label(volumeRow, 22)
	percent.AnchorPoint = Vector2.new(1, 0)
	percent.Position = UDim2.new(1, -14, 0, 8)
	percent.Size = UDim2.fromOffset(110, 30)
	percent.TextXAlignment = Enum.TextXAlignment.Right
	local function paintVolume(value: number)
		percent.Text = `{math.floor(value * 100 + 0.5)}%`
	end
	local slider = Ui.slider(volumeRow, group.Volume, function(value)
		group.Volume = value
		paintVolume(value)
	end)
	slider.AnchorPoint = Vector2.new(0, 1)
	slider.Position = UDim2.new(0, 24, 1, -10)
	slider.Size = UDim2.new(1, -60, 0, 22)
	paintVolume(group.Volume)

	-- Volumen de los efectos ---------------------------------------------------------------
	local effectsRow = row(list, 3, "Volumen de efectos", "Golpes, monedas, tiradas, mejoras y botones.", true, Ui.COLORS.blue)
	local effects = Sfx.group()
	local effectsPercent = Ui.label(effectsRow, 22)
	effectsPercent.AnchorPoint = Vector2.new(1, 0)
	effectsPercent.Position = UDim2.new(1, -14, 0, 8)
	effectsPercent.Size = UDim2.fromOffset(110, 30)
	effectsPercent.TextXAlignment = Enum.TextXAlignment.Right
	local function paintEffects(value: number)
		effectsPercent.Text = `{math.floor(value * 100 + 0.5)}%`
	end
	local effectsSlider = Ui.slider(effectsRow, effects.Volume, function(value)
		effects.Volume = value
		paintEffects(value)
	end)
	effectsSlider.AnchorPoint = Vector2.new(0, 1)
	effectsSlider.Position = UDim2.new(0, 24, 1, -10)
	effectsSlider.Size = UDim2.new(1, -60, 0, 22)
	paintEffects(effects.Volume)

	-- Venta automática -------------------------------------------------------------------
	local sellRow = row(list, 4,"Venta automática", "Las espadas nuevas menos raras que 1 entre N se venden solas. Admite 1000, 1.5K, 2M... Déjalo vacío para no vender.", false, Ui.COLORS.green)
	local sellBox = Instance.new("TextBox")
	sellBox.Name = "AutoSell"
	sellBox.AnchorPoint = Vector2.new(1, 0.5)
	sellBox.Position = UDim2.new(1, -14, 0.5, 0)
	sellBox.Size = UDim2.fromOffset(130, 50)
	sellBox.PlaceholderText = "no vender"
	sellBox.TextSize = 22
	sellBox.ClearTextOnFocus = false
	sellBox.Parent = sellRow
	Ui.field(sellBox)
	local function paintSell()
		if not sellBox:IsFocused() then
			local autoSell = player:GetAttribute("AutoSell") or 0
			sellBox.Text = if autoSell > 0 then Format.short(autoSell) else ""
		end
	end
	sellBox.FocusLost:Connect(function()
		-- Vacío = no vender. Admite "1000", "1.5K", "2M"...
		local value = if sellBox.Text == "" then 0 else Format.parse(sellBox.Text)
		if value then
			Remotes.SetAutoSell:FireServer(value)
		end
		local shown = value or player:GetAttribute("AutoSell") or 0
		sellBox.Text = if shown > 0 then Format.short(shown) else ""
	end)
	player:GetAttributeChangedSignal("AutoSell"):Connect(paintSell)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		paintPerformance()
		paintSell()
	end)
	paintSell()

	-- Botón con engranaje, en la esquina de arriba a la derecha (pedido por el usuario).
	local button = Ui.button(gui, "", Ui.COLORS.gray)
	button.Name = "SettingsButton"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -14, 0, 14)
	button.Size = UDim2.fromOffset(44, 44)
	Ui.gearIcon(button)
	Ui.shadow(button)
	button.Activated:Connect(function()
		Ui.toggle("Settings")
	end)
end

return Settings
