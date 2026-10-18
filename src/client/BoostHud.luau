-- Lo que ve cada jugador de los eventos de admin (Config.AdminEvents; el estado lo publica server/AdminEvents en
-- workspace y las cuentas son de Stats.boost):
--  · `Hud.HudRoot.Boosts`: una pastilla `Boost_<stat>` por evento en marcha ("x3 Suerte de grados 29:59"), abajo en el
--    centro, encima de los botones de Click y Auto. Un solo bucle, que solo vive mientras hay algún evento.
--  · `Hud.HudRoot.AdminBanner`: el mensaje grande de un administrador (remote AdminBanner), arriba en el centro
--    durante Config.AdminEvents.BannerTime segundos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local BoostHud = {}

local cfg = Config.AdminEvents
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 70)
local PILL = 36 -- alto de cada pastilla
local STRIP = 660 -- ancho máximo de la tira: con más pastillas de las que caben, saltan de fila
-- Capas (la interfaz ordena el ZIndex globalmente): el mensaje va por encima de las ventanas y por debajo de los
-- avisos (50), como el cartel del clima.
local Z_BANNER = 40

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Pastillas de los eventos en marcha ------------------------------------------------------------

local function buildStrip()
	local root = Ui.hud()
	local strip = Instance.new("Frame")
	strip.Name = "Boosts"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Size = UDim2.fromOffset(STRIP, 0)
	strip.AutomaticSize = Enum.AutomaticSize.Y
	strip.BackgroundTransparency = 1
	strip.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Wraps = true
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip
	-- Encima de los botones de Click y Auto (client/WeaponSlot), que en vertical van más arriba.
	local function place()
		local tall = root.AbsoluteSize.X < root.AbsoluteSize.Y
		strip.Position = UDim2.new(0.5, 0, 1, if tall then -244 else -106)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	local labels: { [string]: TextLabel } = {}
	local pills: { [string]: Frame } = {}
	for order, stat in cfg.Order do
		local def = cfg.Stats[stat]
		local pill = Instance.new("Frame")
		pill.Name = "Boost_" .. stat
		pill.LayoutOrder = order
		pill.Size = UDim2.fromOffset(0, PILL)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.Visible = false
		pill.Parent = strip
		Ui.pill(pill, Color3.fromRGB(40, 38, 78):Lerp(def.color, 0.28), 12)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = pill
		local label = Ui.label(pill, 18)
		label.Name = "Text"
		label.Size = UDim2.fromOffset(0, PILL - 4)
		label.AutomaticSize = Enum.AutomaticSize.X
		labels[stat] = label
		pills[stat] = pill
	end

	local running = false
	local function paint(): boolean
		local any = false
		local now = workspace:GetServerTimeNow()
		for _, stat in cfg.Order do
			local def = cfg.Stats[stat]
			local value = Stats.boost(stat)
			pills[stat].Visible = value > 1
			if value > 1 then
				any = true
				local left = (workspace:GetAttribute("BoostEnd_" .. stat) or now) - now
				labels[stat].Text = `<font color="{hex(def.color:Lerp(WHITE, 0.4))}">x{Format.multiplier(value)} {Lang.t(nil, def.name)}</font>  {PotionInfo.clock(left)}`
			end
		end
		return any
	end
	local function refresh()
		if paint() and not running then
			running = true
			task.spawn(function()
				while paint() do
					task.wait(0.5)
				end
				running = false
			end)
		end
	end
	for _, stat in cfg.Order do
		workspace:GetAttributeChangedSignal("Boost_" .. stat):Connect(refresh)
		workspace:GetAttributeChangedSignal("BoostEnd_" .. stat):Connect(refresh)
	end
	refresh()
end

-- Mensaje grande ---------------------------------------------------------------------------------

local banner: CanvasGroup? = nil

-- tagText y seconds solo los manda el servidor en sus propios mensajes (server/CloverRefund); el de admin no los lleva.
local function showBanner(text: unknown, tagText: unknown, seconds: unknown)
	if type(text) ~= "string" or text == "" then
		return
	end
	if banner then
		banner:Destroy()
	end
	Sfx.play("rare")
	local group = Instance.new("CanvasGroup")
	group.Name = "AdminBanner"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.24)
	group.Size = UDim2.fromOffset(820, 150)
	group.BackgroundTransparency = 1
	group.ZIndex = Z_BANNER
	group.Parent = Ui.hud()
	banner = group
	local scale = Instance.new("UIScale")
	scale.Parent = group

	-- Con el estilo de las ventanas: fondo oscuro teñido de oro, borde negro grueso y dos filos de luz. Va metida
	-- dentro del grupo para que el borde no quede cortado.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, -20, 1, -20)
	plate.ZIndex = Z_BANNER
	plate.Parent = group
	Ui.round(plate, 18)
	Ui.stroke(plate, BLACK, 5)
	Ui.panel(plate, Color3.fromRGB(150, 96, 24))
	for _, edge in { { "EdgeTop", UDim2.new(0.5, 0, 0, 9) }, { "EdgeBottom", UDim2.new(0.5, 0, 1, -9) } } do
		local strip = Instance.new("Frame")
		strip.Name = edge[1]
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Position = edge[2]
		strip.Size = UDim2.new(0.8, 0, 0, 4)
		strip.BackgroundColor3 = GOLD:Lerp(WHITE, 0.35)
		strip.BorderSizePixel = 0
		strip.ZIndex = Z_BANNER
		strip.Parent = plate
		Ui.round(strip, 2)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0),
			NumberSequenceKeypoint.new(0.78, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = strip
	end
	local tag = Ui.label(plate, 18)
	tag.Name = "Tag"
	tag.Position = UDim2.fromOffset(0, 16)
	tag.Size = UDim2.new(1, 0, 0, 22)
	tag.TextColor3 = GOLD
	tag.Text = if type(tagText) == "string" then `★  {tagText}  ★` else "★  ADMIN  ★"
	tag.ZIndex = Z_BANNER + 1
	local body = Ui.label(plate, 36)
	body.Name = "Text"
	body.Position = UDim2.fromOffset(24, 40)
	body.Size = UDim2.new(1, -48, 1, -58)
	body.RichText = false -- lo ha escrito una persona: se enseña tal cual
	body.TextWrapped = true
	body.TextScaled = true
	body.Text = text
	body.ZIndex = Z_BANNER + 1
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 38
	limit.MinTextSize = 16
	limit.Parent = body

	local stay = if type(seconds) == "number" then math.clamp(seconds, 1, 30) else cfg.BannerTime
	local function leave()
		if banner == group then
			banner = nil
		end
		group:Destroy()
	end
	if Performance.get() then
		task.delay(stay, leave)
		return
	end
	scale.Scale = 0.6
	group.GroupTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(group, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	task.delay(stay, function()
		if group.Parent then
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
			local out = TweenService:Create(group, TweenInfo.new(0.3), { GroupTransparency = 1 })
			out.Completed:Connect(leave)
			out:Play()
		end
	end)
end

function BoostHud.start()
	buildStrip()
	Remotes.AdminBanner.OnClientEvent:Connect(showBanner)
end

return BoostHud
