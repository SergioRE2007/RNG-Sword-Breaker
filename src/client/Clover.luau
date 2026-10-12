-- Trébol de la suerte (Config.Clover): al pulsarlo en la mochila se entra en el modo de elegir (Clover.pick): un cartel
-- arriba dice qué hacer, el objeto de tu parcela que señalas se ilumina y un clic o un toque en él pide al servidor
-- gastar el trébol ahí (UseClover). Mientras dura (Clover.isActive) SwordController no ataca. También pone el brillo
-- verde y los tréboles de los objetos que ya llevan uno (atributo "Clover" del objeto), para todos los jugadores.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Clover = {}

local player = Players.LocalPlayer
local cfg = Config.Clover
local GREEN = Config.Items[cfg.Item].color
local WHITE = Color3.new(1, 1, 1)
local AIM_ASSIST = 70 -- píxeles alrededor del dedo o del ratón en los que vale el objeto más cercano

local active = false
local banner: Frame? = nil
local hover: Highlight? = nil
local connections: { RBXScriptConnection } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local closedAt = 0

-- Sigue contando un instante después de cerrarse: el clic que elige el objeto no debe ser también un ataque.
function Clover.isActive(): boolean
	return active or os.clock() - closedAt < 0.2
end

-- Objetos de tu parcela que aún no llevan trébol.
local function candidates(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged("Destructible") do
		if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId and not part:GetAttribute("Clover") and part:IsDescendantOf(workspace) then
			table.insert(list, part)
		end
	end
	return list
end

-- El objeto que señala ese punto de la pantalla: el que tiene debajo o el más cercano a menos de AIM_ASSIST píxeles.
local function pointed(point: Vector2): BasePart?
	local camera = workspace.CurrentCamera
	local list = candidates()
	if not camera or #list == 0 then
		return nil
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit and hit.Instance:IsA("BasePart") then
		return hit.Instance
	end
	local best, bestDistance = nil, AIM_ASSIST
	for _, part in list do
		local screen, visible = camera:WorldToViewportPoint(part.Position)
		local distance = (Vector2.new(screen.X, screen.Y) - point).Magnitude
		if visible and distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best
end

local function stop()
	if not active then
		return
	end
	active = false
	closedAt = os.clock()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if banner then
		banner.Visible = false
	end
	if hover then
		hover.Adornee = nil
		hover.Enabled = false
	end
end

local function choose(point: Vector2)
	local part = pointed(point)
	if not part then
		Sfx.play("error")
		return
	end
	Remotes.UseClover:FireServer(part)
	Sfx.play("buy")
	stop()
end

local function build()
	local frame = Instance.new("Frame")
	frame.Name = "CloverPick"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 104)
	frame.Size = UDim2.fromOffset(560, 60)
	frame.Visible = false
	frame.Parent = Ui.hud()
	Ui.pill(frame, Color3.fromRGB(30, 60, 46), 14)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Size = UDim2.fromOffset(46, 46)
	icon.BackgroundTransparency = 1
	icon.Parent = frame
	Ui.image(icon, Config.Items[cfg.Item].image)
	local text = Ui.label(frame, 24)
	text.Name = "Text"
	text.Position = UDim2.fromOffset(62, 0)
	text.Size = UDim2.new(1, -62 - 136, 1, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextScaled = true
	text.Text = Lang.t(nil, "Pick an object on your plot")
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 14
	limit.Parent = text
	local cancel = Ui.button(frame, Lang.t(nil, "Cancel"), Ui.COLORS.red)
	cancel.Name = "Cancel"
	cancel.AnchorPoint = Vector2.new(1, 0.5)
	cancel.Position = UDim2.new(1, -8, 0.5, 0)
	cancel.Size = UDim2.fromOffset(120, 44)
	cancel.TextSize = 20
	cancel.Activated:Connect(stop)
	banner = frame

	local light = Instance.new("Highlight")
	light.Name = "CloverHover"
	light.FillColor = GREEN
	light.FillTransparency = 0.55
	light.OutlineColor = WHITE
	light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	light.Enabled = false
	light.Parent = workspace
	hover = light
end

-- Entra en el modo de elegir objeto. No hace nada sin tréboles.
function Clover.pick()
	if active then
		return
	end
	if (player:GetAttribute("Item_" .. cfg.Item) or 0) < 1 then
		Sfx.play("error")
		Ui.toast(Lang.t(nil, "You have no clovers: get them in the Shop or with tickets"), Ui.COLORS.orange)
		return
	end
	if not banner then
		build()
	end
	active = true;
	(banner :: Frame).Visible = true
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local part = if UserInputService.MouseEnabled then pointed(UserInputService:GetMouseLocation()) else nil
		local light = hover :: Highlight
		light.Adornee = part
		light.Enabled = part ~= nil
	end))
	-- El primer clic puede ser el mismo que pulsó la casilla de la mochila: se empieza a escuchar un momento después.
	task.delay(0.15, function()
		if not active then
			return
		end
		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				stop()
			elseif not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				choose(UserInputService:GetMouseLocation())
			end
		end))
		table.insert(connections, UserInputService.TouchTapInWorld:Connect(function(position, processed)
			if not processed then
				choose(position + GuiService:GetGuiInset())
			end
		end))
	end)
end

-- Brillo de un objeto que ya lleva trébol.
local function decorate(part: BasePart)
	if part:FindFirstChild("CloverGlow") then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Name = "CloverGlow"
	glow.FillColor = GREEN
	glow.FillTransparency = 0.8
	glow.OutlineColor = GREEN:Lerp(WHITE, 0.3)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = part
	if Performance.get() then
		return
	end
	local leaves = Instance.new("ParticleEmitter")
	leaves.Name = "CloverLeaves"
	leaves.Texture = Ui.IMAGES[Config.Items[cfg.Item].image]
	leaves.Rate = 5
	leaves.Lifetime = NumberRange.new(1.2, 1.8)
	leaves.Speed = NumberRange.new(2, 4)
	leaves.SpreadAngle = Vector2.new(180, 180)
	leaves.Rotation = NumberRange.new(-30, 30)
	leaves.RotSpeed = NumberRange.new(-60, 60)
	leaves.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 1.1), NumberSequenceKeypoint.new(1, 0.6) })
	leaves.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) })
	leaves.LightEmission = 0.3
	leaves.Parent = part
	leaves:Emit(14)
end

local function watch(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	if part:GetAttribute("Clover") then
		decorate(part)
	end
	part:GetAttributeChangedSignal("Clover"):Connect(function()
		if part:GetAttribute("Clover") then
			decorate(part)
		end
	end)
end

function Clover.start()
	CollectionService:GetInstanceAddedSignal("Destructible"):Connect(watch)
	for _, part in CollectionService:GetTagged("Destructible") do
		watch(part)
	end
	-- Si se queda sin tréboles (o cambia de sitio) con el modo abierto, se cierra.
	player:GetAttributeChangedSignal("Dungeon"):Connect(stop)
end

return Clover
