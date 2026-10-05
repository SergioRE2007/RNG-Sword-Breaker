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
local function row(parent: Instance, order: number, title: string, hint: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -16, 0, 104)
	frame.BackgroundColor3 = WHITE
	frame.Parent = parent
	Ui.round(frame, 12)
	Ui.stroke(frame, BLACK, 3)
	Ui.gradient(frame, Color3.fromRGB(52, 56, 74), Color3.fromRGB(34, 36, 50), 90)
	local heading = Ui.label(frame, 24)
	heading.Position = UDim2.fromOffset(14, 8)
	heading.Size = UDim2.new(1, -170, 0, 30)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	local detail = Ui.label(frame, 17)
	detail.Position = UDim2.fromOffset(14, 38)
	detail.Size = UDim2.new(1, -170, 0, 56)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextWrapped = true
	detail.TextColor3 = Color3.fromRGB(190, 195, 215)
	detail.Text = hint
	return frame
end

function Settings.start()
	local gui = Ui.screen()
	local window, body = Ui.window("Settings", "Ajustes", Vector2.new(560, 436), Ui.gearIcon)

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
	local performanceRow = row(list, 1, "Modo rendimiento", "Quita partículas, auras, estelas, luces, hierba, nubes, sombras y las animaciones de los menús. Úsalo si el juego va lento. En móviles viene activado.")
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
	local volumeRow = row(list, 2, "Volumen de la música", "Aún no hay música, pero el volumen ya queda guardado para cuando se añada.")
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

	-- Venta automática -------------------------------------------------------------------
	local sellRow = row(list, 3, "Venta automática", "Las espadas nuevas menos raras que 1 entre N se venden solas. Admite 1000, 1.5K, 2M... Déjalo vacío para no vender.")
	local sellBox = Instance.new("TextBox")
	sellBox.Name = "AutoSell"
	sellBox.AnchorPoint = Vector2.new(1, 0.5)
	sellBox.Position = UDim2.new(1, -14, 0.5, 0)
	sellBox.Size = UDim2.fromOffset(130, 50)
	sellBox.BackgroundColor3 = Ui.COLORS.dark
	sellBox.TextColor3 = WHITE
	sellBox.PlaceholderColor3 = Color3.fromRGB(140, 145, 165)
	sellBox.PlaceholderText = "no vender"
	sellBox.Font = Ui.FONT
	sellBox.TextSize = 22
	sellBox.ClearTextOnFocus = false
	sellBox.Parent = sellRow
	Ui.round(sellBox, 8)
	Ui.stroke(sellBox, BLACK, 2)
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

	-- Botón con engranaje, arriba a la izquierda (bajo los botones de Roblox, que ocupan la esquina).
	local button = Ui.button(gui, "", Ui.COLORS.gray)
	button.Name = "SettingsButton"
	button.Position = UDim2.fromOffset(14, 66)
	button.Size = UDim2.fromOffset(56, 56)
	Ui.gearIcon(button)
	button.Activated:Connect(function()
		Ui.toggle("Settings")
	end)
end

return Settings
