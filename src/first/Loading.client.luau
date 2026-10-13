-- Pantalla de carga (pedida por el usuario): tapa el juego mientras entra y se quita sola cuando todo está listo.
-- Va en ReplicatedFirst, que es lo primero que llega al cliente: por eso no puede usar client/Ui ni nada de
-- ReplicatedStorage al arrancar, y se hace sus propias piezas con el mismo estilo (FredokaOne, borde negro, degradado).
-- Dos fases: primero lo imprescindible (el juego replicado, los datos del jugador y el HUD montado) y después las
-- imágenes y los sonidos, que se pueden esperar jugando: en cuanto acaba la primera sale el botón "Saltar".
-- Se cierra sola (se va hacia arriba) al acabar la segunda o a los MAX_WAIT segundos, para no dejar parado a quien vuelve de una
-- reconexión por inactividad sin estar delante.
local ContentProvider = game:GetService("ContentProvider")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MIN_TIME = 2 -- segundos como mínimo a la vista, para que no sea un parpadeo
local MAX_WAIT = 20 -- segundos como mucho precargando imágenes y sonidos una vez que ya se puede jugar
local TIP_TIME = 4 -- segundos que dura cada consejo
local BATCH = 12 -- piezas por tanda de precarga (cada tanda mueve la barra)
local ESSENTIAL = 0.5 -- parte de la barra que ocupa la primera fase

-- Las mismas imágenes que Ui.IMAGES (espada, boton_rayos y patron_rombos): Ui aún no ha llegado.
local SWORD = "rbxassetid://100527116629167"
local RAYS = "rbxassetid://123487236385810"
local PATTERN = "rbxassetid://127373214598364"

local TOP = Color3.fromRGB(74, 48, 140)
local BOTTOM = Color3.fromRGB(22, 16, 48)
local GOLD = Color3.fromRGB(255, 205, 60)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- Consejos, en inglés: pasan por Lang.t cuando llega (su español, en shared/LangEs).
local TIPS = {
	"Break the objects in your plot to get weapons!",
	"Rarer objects drop rarer weapons.",
	"Leave your spare weapons in the Gold Bag to earn coins.",
	"Dungeons drop armor and crystals.",
	"Daily missions give tickets for the Shop.",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local function text(parent: Instance, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = WHITE
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = math.clamp(size / 10, 2, 5)
	stroke.Parent = label
	return label
end

local function round(item: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = item
end

local function gradient(item: Instance, top: Color3, bottom: Color3)
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(top, bottom)
	fill.Rotation = 90
	fill.Parent = item
end

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000 -- por encima del Hud y de la pantalla de Mejoras
gui.AutoLocalize = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Un Frame y no un CanvasGroup: allí el degradado del fondo teñía de morado todo lo de dentro y no llegaba a tapar
-- la pantalla entera (lo vio el usuario). Al cerrar, la pantalla se va hacia arriba en vez de fundirse.
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = WHITE
root.BorderSizePixel = 0
root.Active = true -- los clics no llegan al juego de debajo
root.Parent = gui
gradient(root, TOP, BOTTOM)

local pattern = Instance.new("ImageLabel")
pattern.Name = "Pattern"
pattern.Size = UDim2.fromScale(1, 1)
pattern.BackgroundTransparency = 1
pattern.Image = PATTERN
pattern.ImageTransparency = 0.94
pattern.ScaleType = Enum.ScaleType.Tile
pattern.TileSize = UDim2.fromOffset(96, 96)
pattern.Parent = root

-- El contenido va en una caja centrada de tamaño fijo que un UIScale encoge en pantallas pequeñas.
local box = Instance.new("Frame")
box.Name = "Box"
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.fromScale(0.5, 0.5)
box.Size = UDim2.fromOffset(640, 520)
box.BackgroundTransparency = 1
box.Parent = root
local scale = Instance.new("UIScale")
scale.Parent = box
local function fit()
	local size = root.AbsoluteSize
	scale.Scale = math.clamp(math.min(size.X / 700, size.Y / 580), 0.4, 1.4)
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local rays = Instance.new("ImageLabel")
rays.Name = "Rays"
rays.AnchorPoint = Vector2.new(0.5, 0.5)
rays.Position = UDim2.new(0.5, 0, 0, 130)
rays.Size = UDim2.fromOffset(440, 440)
rays.BackgroundTransparency = 1
rays.Image = RAYS
rays.ImageColor3 = GOLD
rays.ImageTransparency = 0.72
rays.Parent = box

local sword = Instance.new("ImageLabel")
sword.Name = "Logo"
sword.AnchorPoint = Vector2.new(0.5, 0.5)
sword.Position = UDim2.new(0.5, 0, 0, 130)
sword.Size = UDim2.fromOffset(210, 210)
sword.BackgroundTransparency = 1
sword.Image = SWORD
sword.ZIndex = 2
sword.Parent = box

local title = text(box, 62)
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 250)
title.Size = UDim2.new(1, 0, 0, 70)
title.Text = "RNG: SWORD BREAKER" -- el nombre del juego, igual en todos los idiomas
title.ZIndex = 3
gradient(title, WHITE, GOLD)

-- Barra de progreso: canal oscuro con borde negro y relleno dorado.
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 348)
bar.Size = UDim2.fromOffset(460, 30)
bar.BackgroundColor3 = Color3.fromRGB(18, 14, 36)
bar.BorderSizePixel = 0
bar.Parent = box
round(bar, 15)
local barStroke = Instance.new("UIStroke")
barStroke.Color = BLACK
barStroke.Thickness = 4
barStroke.Parent = bar
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0.04, 1)
fill.BackgroundColor3 = WHITE
fill.BorderSizePixel = 0
fill.Parent = bar
round(fill, 15)
gradient(fill, Color3.fromRGB(255, 232, 120), Color3.fromRGB(255, 150, 40))
local percent = text(bar, 20)
percent.Name = "Percent"
percent.Size = UDim2.fromScale(1, 1)
percent.Text = "0%"
percent.ZIndex = 2

local status = text(box, 24)
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0, 388)
status.Size = UDim2.new(1, 0, 0, 30)

local tip = text(box, 20)
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 0)
tip.Position = UDim2.new(0.5, 0, 0, 422)
tip.Size = UDim2.new(1, 0, 0, 26)
tip.TextColor3 = Color3.fromRGB(205, 200, 235)
tip.Text = ""

-- Botón "Saltar": sale cuando ya se puede jugar. Con labio oscuro abajo, como los de Ui.button.
local skip = Instance.new("TextButton")
skip.Name = "Skip"
skip.AnchorPoint = Vector2.new(0.5, 0)
skip.Position = UDim2.new(0.5, 0, 0, 458)
skip.Size = UDim2.fromOffset(200, 52)
skip.BackgroundColor3 = WHITE
skip.BorderSizePixel = 0
skip.AutoButtonColor = false
skip.Text = ""
skip.Visible = false
skip.Parent = box
round(skip, 12)
gradient(skip, Color3.fromRGB(110, 225, 95), Color3.fromRGB(40, 160, 60))
local skipStroke = Instance.new("UIStroke")
skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
skipStroke.Color = BLACK
skipStroke.Thickness = 4
skipStroke.Parent = skip
-- El texto va en una etiqueta aparte: escrito en el botón, su degradado verde lo teñía.
local skipText = text(skip, 28)
skipText.Name = "Label"
skipText.Size = UDim2.fromScale(1, 1)
local skipScale = Instance.new("UIScale")
skipScale.Parent = skip

fit()
gui.Parent = playerGui

-- Textos: hasta que llega Lang solo se sabe el idioma de la cuenta, y solo hace falta una palabra.
local Lang = nil
local function say(phrase: string): string
	if Lang then
		return Lang.t(nil, phrase)
	end
	return if phrase == "Loading" and string.sub(LocalizationService.RobloxLocaleId, 1, 2) == "es" then "Cargando" else phrase
end

local started = os.clock()
local progress, shown = 0.04, 0.04
local closing = false
local skipped = false
local tipAt, tipIndex = 0, 0

-- Un solo bucle mientras la pantalla existe: rayos, logo, barra, puntos de "Cargando" y consejos.
local loop
loop = RunService.RenderStepped:Connect(function(dt)
	local now = os.clock() - started
	rays.Rotation = now * 24
	sword.Rotation = math.sin(now * 2.2) * 6
	sword.Position = UDim2.new(0.5, 0, 0, 130 + math.sin(now * 3) * 6)
	shown += (progress - shown) * math.min(dt * 6, 1)
	fill.Size = UDim2.fromScale(math.max(shown, 0.04), 1)
	percent.Text = `{math.floor(shown * 100 + 0.5)}%`
	if not closing then
		status.Text = say("Loading") .. string.rep(".", math.floor(now * 2.5) % 4)
	end
	if Lang and now >= tipAt then
		tipAt = now + TIP_TIME
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = Lang.t(nil, TIPS[tipIndex])
	end
	if skip.Visible then
		skipScale.Scale = 1 + math.sin(now * 5) * 0.03
	end
end)

local function close()
	if closing then
		return
	end
	closing = true
	progress = 1
	skip.Visible = false
	local wait = MIN_TIME - (os.clock() - started)
	if wait > 0 and not skipped then
		task.wait(wait)
	end
	local fade = TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0, -1.1) })
	fade:Play()
	fade.Completed:Wait()
	loop:Disconnect()
	gui:Destroy()
end

skip.Activated:Connect(function()
	skipped = true
	close()
end)

-- Fase 1: lo imprescindible para jugar.
if not game:IsLoaded() then
	game.Loaded:Wait()
end
progress = 0.2
Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
tipIndex = math.random(#TIPS) -- empieza por un consejo cualquiera
while player:GetAttribute("Coins") == nil do -- los datos del jugador ya están cargados y publicados
	task.wait(0.1)
end
progress = 0.35
local hud = playerGui:WaitForChild("Hud")
hud:WaitForChild("HudRoot")
progress = ESSENTIAL

skipText.Text = string.upper(Lang.t(nil, "Skip"))
skip.Visible = true

-- Fase 2: imágenes de la interfaz y sonidos, por tandas. Se deja a medias si el jugador salta o tarda demasiado.
local assets = {}
for _, item in hud:GetDescendants() do
	if item:IsA("ImageLabel") or item:IsA("ImageButton") then
		table.insert(assets, item)
	end
end
local bank = SoundService:FindFirstChild("SfxBank")
if bank then
	for _, sound in bank:GetChildren() do
		table.insert(assets, sound)
	end
end
local readyAt = os.clock()
for first = 1, #assets, BATCH do
	if closing or os.clock() - readyAt > MAX_WAIT then
		break
	end
	local batch = table.move(assets, first, math.min(first + BATCH - 1, #assets), 1, {})
	pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	progress = ESSENTIAL + (1 - ESSENTIAL) * math.min((first + BATCH - 1) / #assets, 1)
end
close()
