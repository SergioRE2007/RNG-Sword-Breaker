-- Ajustes: botón con engranaje arriba a la izquierda (bajo los botones de Roblox) y una ventana con
-- el modo rendimiento, los volúmenes (música, efectos y ambiente) y la venta automática de espadas. Cada ajuste vive
-- en el cliente (el modo rendimiento y el volumen solo duran la sesión; la venta automática la
-- guarda el servidor). La música todavía no existe: cuando se añada, sus Sound deben ir en el
-- SoundGroup "Music" de SoundService, que es el que mueve el deslizador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
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
	local window, body = Ui.window("Settings", Lang.t(nil, "Settings"), Vector2.new(560, 660), function(parent) -- las filas (104 + 10 cada una) no caben todas: la lista desliza
		Ui.image(parent, "ajustes")
	end)

	-- Lista que desliza (pedido por el usuario: con siete filas ya no cabían en la ventana).
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(190, 195, 215)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = list

	-- Modo rendimiento -------------------------------------------------------------------
	local performanceRow = row(list, 1, Lang.t(nil, "Performance mode"), Lang.t(nil, "Removes particles, auras, lights, clouds, shadows and menu animations. Use it if the game runs slow (on by default on mobile)."), false, Ui.COLORS.orange)
	local performanceButton = Ui.button(performanceRow, "", Ui.COLORS.gray)
	performanceButton.AnchorPoint = Vector2.new(1, 0.5)
	performanceButton.Position = UDim2.new(1, -14, 0.5, 0)
	performanceButton.Size = UDim2.fromOffset(130, 60)
	performanceButton.TextSize = 26
	local function paintPerformance()
		local on = Performance.get()
		performanceButton.Text = Lang.t(nil, if on then "YES" else "NO")
		performanceButton.BackgroundColor3 = if on then Ui.COLORS.green else Ui.COLORS.gray
	end
	performanceButton.Activated:Connect(function()
		Performance.set(not Performance.get())
		paintPerformance()
	end)
	paintPerformance()

	-- Volumen de la música ---------------------------------------------------------------
	local volumeRow = row(list, 2, Lang.t(nil, "Music volume"), Lang.t(nil, "There is no music yet; the volume is saved for when it arrives."), true, Color3.fromRGB(190, 120, 255))
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
	local effectsRow = row(list, 3, Lang.t(nil, "Effects volume"), Lang.t(nil, "Hits, coins, rolls, upgrades and buttons."), true, Ui.COLORS.blue)
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

	-- Volumen del ambiente ---------------------------------------------------------------
	local ambienceRow = row(list, 4, Lang.t(nil, "Ambience volume"), Lang.t(nil, "The background sound of each zone, the stations and the weather."), true, Color3.fromRGB(60, 200, 190))
	local ambience = Sfx.ambience()
	local ambiencePercent = Ui.label(ambienceRow, 22)
	ambiencePercent.AnchorPoint = Vector2.new(1, 0)
	ambiencePercent.Position = UDim2.new(1, -14, 0, 8)
	ambiencePercent.Size = UDim2.fromOffset(110, 30)
	ambiencePercent.TextXAlignment = Enum.TextXAlignment.Right
	local function paintAmbience(value: number)
		ambiencePercent.Text = `{math.floor(value * 100 + 0.5)}%`
	end
	local ambienceSlider = Ui.slider(ambienceRow, ambience.Volume, function(value)
		ambience.Volume = value
		paintAmbience(value)
	end)
	ambienceSlider.AnchorPoint = Vector2.new(0, 1)
	ambienceSlider.Position = UDim2.new(0, 24, 1, -10)
	ambienceSlider.Size = UDim2.new(1, -60, 0, 22)
	paintAmbience(ambience.Volume)

	-- Venta automática -------------------------------------------------------------------
	local sellRow = row(list, 5,Lang.t(nil, "Auto-sell"), Lang.t(nil, "New swords less rare than 1 in N are sold automatically. Accepts 1000, 1.5K, 2M... Leave it empty to sell nothing."), false, Ui.COLORS.green)
	local sellBox = Instance.new("TextBox")
	sellBox.Name = "AutoSell"
	sellBox.AnchorPoint = Vector2.new(1, 0.5)
	sellBox.Position = UDim2.new(1, -14, 0.5, 0)
	sellBox.Size = UDim2.fromOffset(130, 50)
	sellBox.PlaceholderText = Lang.t(nil, "don't sell")
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

	-- Ver hitbox -------------------------------------------------------------------------
	-- Solo cambia el atributo local "HitboxDebug" del jugador: quien dibuja es client/HitboxDebug.
	local hitboxRow = row(list, 6, Lang.t(nil, "Show hitbox"), Lang.t(nil, "Draws your attack circle on the ground, marks in green what you can target and shows how far your weapons splash."), false, Ui.COLORS.red)
	local hitboxButton = Ui.button(hitboxRow, "", Ui.COLORS.gray)
	hitboxButton.Name = "Hitbox"
	hitboxButton.AnchorPoint = Vector2.new(1, 0.5)
	hitboxButton.Position = UDim2.new(1, -14, 0.5, 0)
	hitboxButton.Size = UDim2.fromOffset(130, 60)
	hitboxButton.TextSize = 26
	local function paintHitbox()
		local on = player:GetAttribute("HitboxDebug") == true
		hitboxButton.Text = Lang.t(nil, if on then "YES" else "NO")
		hitboxButton.BackgroundColor3 = if on then Ui.COLORS.green else Ui.COLORS.gray
	end
	hitboxButton.Activated:Connect(function()
		player:SetAttribute("HitboxDebug", player:GetAttribute("HitboxDebug") ~= true)
	end)
	player:GetAttributeChangedSignal("HitboxDebug"):Connect(paintHitbox)
	paintHitbox()

	-- Cinemáticas de tirada ----------------------------------------------------------------
	-- Solo cambia atributos locales del jugador (sin guardar): "RollCinematics" (false = apagadas, lo mira
	-- client/RollCinematic) y "CinematicFrom" (desde qué "1 entre N" salen; sin poner = todas, lo mira client/RollReveal).
	-- El botón va pasando por: todas, desde cada escalón de Config.Gacha.RevealOdds con cinemática, y apagadas.
	local cineSteps: { number } = { 0 }
	for index = 3, #Config.Gacha.RevealOdds do
		table.insert(cineSteps, Config.Gacha.RevealOdds[index])
	end
	table.insert(cineSteps, -1)
	local cineRow = row(list, 7, Lang.t(nil, "Roll cinematics"), Lang.t(nil, "Plays a short cinematic when you roll a very rare weapon. Choose from which rarity, or turn them off to farm without cuts."), false, Ui.COLORS.purple)
	local cineButton = Ui.button(cineRow, "", Ui.COLORS.gray)
	cineButton.Name = "Cinematics"
	cineButton.AnchorPoint = Vector2.new(1, 0.5)
	cineButton.Position = UDim2.new(1, -14, 0.5, 0)
	cineButton.Size = UDim2.fromOffset(130, 60)
	cineButton.TextSize = 26
	local function cineStep(): number
		if player:GetAttribute("RollCinematics") == false then
			return -1
		end
		local from = player:GetAttribute("CinematicFrom")
		return if typeof(from) == "number" then from else 0
	end
	local function paintCine()
		local step = cineStep()
		cineButton.Text = if step == -1 then Lang.t(nil, "NO")
			elseif step == 0 then Lang.t(nil, "ALL")
			else Lang.t(nil, "{odds}+", { odds = Format.short(step) })
		cineButton.BackgroundColor3 = if step == -1 then Ui.COLORS.gray
			elseif step == 0 then Ui.COLORS.green
			else Ui.COLORS.purple
	end
	cineButton.Activated:Connect(function()
		local current = table.find(cineSteps, cineStep()) or 1
		local step = cineSteps[current % #cineSteps + 1]
		player:SetAttribute("RollCinematics", step ~= -1)
		player:SetAttribute("CinematicFrom", if step > 0 then step else nil)
	end)
	player:GetAttributeChangedSignal("RollCinematics"):Connect(paintCine)
	player:GetAttributeChangedSignal("CinematicFrom"):Connect(paintCine)
	paintCine()

	-- Botón con engranaje, arriba a la derecha: el último de la fila de botones pequeños (pedido por el usuario; a la
	-- izquierda, en el móvil lo pisaban los botones de Roblox).
	local button = Ui.button(Ui.topButtons(), "", Ui.COLORS.gray)
	button.Name = "SettingsButton"
	button.LayoutOrder = 1000
	button.Size = UDim2.fromOffset(44, 44)
	Ui.image(button, "ajustes")
	button.Activated:Connect(function()
		Ui.toggle("Settings")
	end)
end

return Settings
