-- Aviso de pantalla vertical (pedido por el usuario: hay jugadores de móvil que juegan en vertical y el juego está
-- hecho para horizontal). Al entrar con la pantalla más alta que ancha sale la tarjeta Hud.Portrait con un móvil que
-- gira; "Girar" fija la pantalla en horizontal (PlayerGui.ScreenOrientation) y "Ahora no" la cierra hasta la próxima
-- partida. Solo en pantallas táctiles sin teclado; en Studio, LocalPlayer:SetAttribute("PortraitTest", true) desde
-- Client la saca como si la pantalla estuviera en vertical.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Orientation = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ACCENT = Color3.fromRGB(90, 200, 255)
local LAYER = 80 -- aviso, por encima de las ventanas y del de reconexión
local WIDTH = 380 -- ancho máximo de la tarjeta (en un móvil en vertical se queda en el 92 % de la pantalla)

local function isPortrait(): boolean
	local view = workspace.CurrentCamera.ViewportSize
	return view.Y > view.X or player:GetAttribute("PortraitTest") == true
end

-- El móvil del dibujo: un rectángulo redondeado con pantalla, que gira de vertical a horizontal.
local function phoneIcon(parent: Instance): Frame
	local phone = Instance.new("Frame")
	phone.Name = "Phone"
	phone.AnchorPoint = Vector2.new(0.5, 0.5)
	phone.Position = UDim2.fromScale(0.5, 0.5)
	phone.Size = UDim2.fromOffset(34, 58)
	phone.BackgroundColor3 = Color3.fromRGB(40, 44, 70)
	phone.BorderSizePixel = 0
	phone.Parent = parent
	Ui.round(phone, 8)
	Ui.stroke(phone, BLACK, 3)
	local screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Position = UDim2.fromOffset(4, 6)
	screen.Size = UDim2.new(1, -8, 1, -14)
	screen.BackgroundColor3 = WHITE
	screen.BorderSizePixel = 0
	screen.Parent = phone
	Ui.round(screen, 4)
	Ui.gradient(screen, ACCENT:Lerp(WHITE, 0.4), Color3.fromRGB(40, 120, 220), 90)
	return phone
end

function Orientation.start()
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if not mobile and not RunService:IsStudio() then
		return
	end

	local card = Instance.new("Frame")
	card.Name = "Portrait"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.92, 0, 0, 236)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = Ui.screen()
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(44, 62, 108), ACCENT)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(WIDTH, math.huge)
	limit.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	Ui.popup(card, scale)

	-- Círculo con el móvil, arriba en el centro.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 12)
	badge.Size = UDim2.fromOffset(72, 72)
	badge.BackgroundColor3 = WHITE
	badge.BorderSizePixel = 0
	badge.Parent = card
	Ui.round(badge, 36)
	Ui.stroke(badge, BLACK, 3)
	Ui.gradient(badge, Color3.fromRGB(255, 200, 70), Color3.fromRGB(240, 120, 30), 90)
	local phone = phoneIcon(badge)

	local title = Ui.label(card, 22)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(14, 90)
	title.Size = UDim2.new(1, -28, 0, 30)
	title.TextWrapped = true
	title.Text = Lang.t(nil, "You're playing in portrait!")
	Ui.gradient(title, WHITE, ACCENT:Lerp(WHITE, 0.45), 90)
	local detail = Ui.label(card, 16)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(14, 120)
	detail.Size = UDim2.new(1, -28, 0, 44)
	detail.TextWrapped = true
	detail.TextColor3 = Color3.fromRGB(205, 212, 235)
	detail.Text = Lang.t(nil, "The game is made for landscape. Turn your screen for the best experience.")

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(0.5, 1)
	buttons.Position = UDim2.new(0.5, 0, 1, -14)
	buttons.Size = UDim2.new(1, -28, 0, 48)
	buttons.BackgroundTransparency = 1
	buttons.Parent = card
	local rotate = Ui.button(buttons, Lang.t(nil, "Rotate"), Ui.COLORS.green)
	rotate.Name = "Rotate"
	rotate.Size = UDim2.new(0.6, -6, 1, 0)
	rotate.TextSize = 20
	local later = Ui.button(buttons, Lang.t(nil, "Not now"), Ui.COLORS.gray)
	later.Name = "Later"
	later.AnchorPoint = Vector2.new(1, 0)
	later.Position = UDim2.fromScale(1, 0)
	later.Size = UDim2.new(0.4, -6, 1, 0)
	Ui.layer(card, LAYER)

	-- El móvil gira a horizontal, espera y vuelve, mientras la tarjeta está a la vista.
	local spin = TweenService:Create(phone, TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, -1, true, 0.5), { Rotation = 90 })

	local dismissed = false
	local function close()
		dismissed = true
		spin:Cancel()
		Ui.close(card)
	end
	rotate.Activated:Connect(function()
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			gui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
		end
		close()
	end)
	later.Activated:Connect(close)

	local function check()
		if dismissed then
			return
		end
		if isPortrait() and not Ui.isOpen(card) then
			phone.Rotation = 0
			Ui.open(card)
			spin:Play()
			Sfx.play("toast")
		elseif not isPortrait() and Ui.isOpen(card) then
			-- Ya ha girado él solo: no hace falta el aviso.
			close()
		end
	end

	player:GetAttributeChangedSignal("PortraitTest"):Connect(function()
		dismissed = false
		check()
	end)
	task.spawn(function()
		-- Después de la pantalla de carga, que lo taparía.
		local gui = player:WaitForChild("PlayerGui")
		while gui:FindFirstChild("Loading") do
			task.wait(0.5)
		end
		task.wait(1)
		if not mobile then
			return
		end
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(check)
		check()
	end)
end

return Orientation
