-- Los dos botones de los lados de la casilla del arma (Hud.HudRoot.WeaponSlot):
--   AutoClick, a la izquierda: da espadazos solo con el arma en la mano. Gratis para quien esté en el grupo del
--     juego; si no, sale el cartel Hud.AutoUnlock (dale like y únete al grupo) con el botón de unirse.
--   AutoFarm, a la derecha: pase de juego (ventaja "autoFarm"). En tu parcela, el personaje va al objeto más
--     cercano y lo rompe; sin el pase, abre la Tienda.
-- El servidor (server/AutoPlay) decide si se pueden encender y lo publica en "AutoClick" y "AutoFarm". Los golpes
-- son los de un clic (SwordController.swing), así que el servidor los valida igual. Un solo bucle, que solo vive
-- mientras hay alguno encendido.
local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local SwordController = require(script.Parent.SwordController)
local Ui = require(script.Parent.Ui)

local AutoPlay = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ROBUX = Color3.fromRGB(70, 215, 120)
local CLICK_COLOR = Color3.fromRGB(70, 150, 255)
local FARM_COLOR = Color3.fromRGB(255, 180, 50)
local ON_COLOR = Color3.fromRGB(80, 215, 100)

-- Capas: los botones van con la casilla del arma, por debajo de las ventanas; el cartel, por encima de todo.
local LAYER = { button = 0, popup = 70 }
local BUTTON = 70 -- lado de cada botón, en unidades del HUD
local GAP = 14 -- separación con la casilla del arma
local SLOT = 108 -- lado de la casilla del arma (SLOT_SIZE de WeaponSlot)
local STEP = 0.1 -- segundos entre dos vueltas del bucle
local GIVE_UP = 6 -- segundos intentando llegar a un objeto antes de probar con otro

-- Bucle -----------------------------------------------------------------------------------

local function on(mode: string): boolean
	return player:GetAttribute(mode) == true
end

-- Objeto de tu parcela más cercano, sin contar los que se han dado por imposibles.
local function nearest(position: Vector3, skip: { [BasePart]: number }): BasePart?
	local best, bestDistance = nil, math.huge
	local now = os.clock()
	for _, part in CollectionService:GetTagged("Destructible") do
		if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId and (skip[part] or 0) < now then
			local distance = (part.Position - position).Magnitude - part.Size.X / 2
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

local running = false
local function run()
	if running then
		return
	end
	running = true
	local target: BasePart? = nil
	local since = 0
	local moving = false
	local skip: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
	while on("AutoClick") or on("AutoFarm") do
		task.wait(STEP)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			moving = false
			continue
		end
		-- Dentro de una mazmorra manda su propio Auto (client/Dungeons).
		local farm = on("AutoFarm") and (player:GetAttribute("Dungeon") or 0) == 0
		if farm then
			if not target or not target.Parent then
				target = nearest(root.Position, skip)
				since = os.clock()
			end
			if target then
				local copy = Stats.equipped(player)
				local _, kind = Stats.weapon(player)
				local range = Config.BaseRange + Config.Swords[copy.sword].bladeLength * Permanent.scale(copy)
				local goal = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
				-- Se acerca hasta tenerlo bien dentro del alcance (el servidor ve al personaje con algo de retraso).
				if Hitbox.reaches(target, root.CFrame, range * 0.75, -1) then
					if moving then
						moving = false
						humanoid:MoveTo(root.Position)
					end
					since = os.clock()
				else
					moving = true
					humanoid:MoveTo(goal)
					if os.clock() - since > GIVE_UP then
						-- No llega (algo en medio): se deja un rato y se va a por otro.
						skip[target] = os.clock() + GIVE_UP
						target = nil
						continue
					end
				end
				if Hitbox.reaches(target, root.CFrame, range, -1) then
					-- Quieto no gira solo: se le encara al objeto para que el golpe le dé.
					if not Hitbox.reaches(target, root.CFrame, range, kind.arc) and (goal - root.Position).Magnitude > 0.5 then
						root.CFrame = CFrame.lookAt(root.Position, goal)
					end
					SwordController.swing()
				end
			elseif moving then
				moving = false
				humanoid:MoveTo(root.Position)
			end
		else
			if moving then
				moving = false
				humanoid:MoveTo(root.Position)
			end
			target = nil
			-- El autoclicker solo pega con el arma en la mano: guardarla sigue sirviendo para parar.
			if on("AutoClick") and SwordController.isDrawn() then
				SwordController.swing()
			end
		end
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if moving and humanoid and root then
		humanoid:MoveTo(root.Position)
	end
	running = false
end

-- Botones ---------------------------------------------------------------------------------

-- Icono del autoclicker: un ratón con el botón izquierdo encendido.
local function mouseIcon(parent: Instance): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.4)
	holder.Size = UDim2.fromScale(0.42, 0.56)
	holder.BackgroundColor3 = WHITE
	holder.BorderSizePixel = 0
	holder.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = holder
	Ui.stroke(holder, BLACK, 2.5)
	Ui.gradient(holder, WHITE, Color3.fromRGB(200, 208, 230), 90)
	local key = Instance.new("Frame")
	key.Name = "Key"
	key.Position = UDim2.fromScale(0.08, 0.06)
	key.Size = UDim2.fromScale(0.38, 0.36)
	key.BackgroundColor3 = Color3.fromRGB(255, 90, 80)
	key.BorderSizePixel = 0
	key.Parent = holder
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0.5, 0)
	keyCorner.Parent = key
	local split = Instance.new("Frame")
	split.Name = "Split"
	split.AnchorPoint = Vector2.new(0.5, 0)
	split.Position = UDim2.fromScale(0.5, 0)
	split.Size = UDim2.new(0, 2, 0.46, 0)
	split.BackgroundColor3 = BLACK
	split.BorderSizePixel = 0
	split.Parent = holder
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.Position = UDim2.fromScale(0, 0.46)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.BackgroundColor3 = BLACK
	line.BorderSizePixel = 0
	line.Parent = holder
	return holder
end

-- Un botón al lado de la casilla del arma. `side` = -1 a su izquierda, 1 a su derecha.
local function build(dock: Instance, name: string, text: string, color: Color3, side: number)
	local button = Ui.button(dock, "", color)
	button.Name = name
	button.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 1)
	button.Position = UDim2.new(if side < 0 then 0 else 1, side * GAP, 0, SLOT)
	button.Size = UDim2.fromOffset(BUTTON, BUTTON)
	local icon: GuiObject
	if name == "AutoClick" then
		icon = mouseIcon(button)
	else
		icon = Ui.image(button, "espada")
		icon.Position = UDim2.fromScale(0.5, 0.4)
		icon.Size = UDim2.fromScale(0.66, 0.66)
	end
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon
	local label = Ui.label(button, 15)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -3)
	label.Size = UDim2.new(1, -4, 0, 20)
	label.Text = text
	local state = Ui.cellTag(button, "", ON_COLOR)
	state.Name = "State"
	state.AnchorPoint = Vector2.new(1, 0)
	state.Position = UDim2.new(1, 5, 0, -6)
	state.Size = UDim2.fromOffset(34, 20)
	state.TextSize = 13
	Ui.layer(button, LAYER.button)
	return button, state, iconScale
end

-- Cartel del autoclicker: lo que hay que hacer para tenerlo y el botón de unirse al grupo.
local function buildUnlock()
	local card = Instance.new("Frame")
	card.Name = "AutoUnlock"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.45)
	card.Size = UDim2.fromOffset(460, 236)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = Ui.screen()
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(46, 62, 112), CLICK_COLOR)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	Ui.popup(card, scale)

	local title = Ui.label(card, 28)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 36)
	title.Text = "AUTOCLICKER GRATIS"
	Ui.gradient(title, WHITE, CLICK_COLOR:Lerp(WHITE, 0.5), 90)
	local steps = Ui.label(card, 21)
	steps.Name = "Steps"
	steps.Position = UDim2.fromOffset(24, 54)
	steps.Size = UDim2.new(1, -48, 0, 92)
	steps.TextWrapped = true
	steps.LineHeight = 1.2
	steps.Text = `<font color="#{ROBUX:ToHex()}">1.</font> Dale <font color="#ffd84a">ME GUSTA</font> al juego\n<font color="#{ROBUX:ToHex()}">2.</font> Únete al <font color="#ffd84a">GRUPO</font>\ny el Autoclicker es tuyo para siempre`

	local join = Ui.button(card, "Unirme al grupo", ROBUX)
	join.Name = "Join"
	join.AnchorPoint = Vector2.new(1, 1)
	join.Position = UDim2.new(0.5, -6, 1, -14)
	join.Size = UDim2.fromOffset(206, 56)
	join.TextSize = 21
	Ui.sparkle(join, 4)
	local check = Ui.button(card, "¡Ya lo hice!", CLICK_COLOR)
	check.Name = "Check"
	check.AnchorPoint = Vector2.new(0, 1)
	check.Position = UDim2.new(0.5, 6, 1, -14)
	check.Size = UDim2.fromOffset(206, 56)
	check.TextSize = 21
	local close = Ui.button(card, "X", Ui.COLORS.red)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 10, 0, -10)
	close.Size = UDim2.fromOffset(40, 40)
	close.TextSize = 20
	Ui.layer(card, LAYER.popup)

	local group = 0
	local asked = false -- lo último pedido ha salido de este cartel: si lo niegan, se dice en un aviso
	local function retry()
		asked = true
		Remotes.SetAuto:FireServer("click", true)
	end
	join.Activated:Connect(function()
		-- La ventana de unirse es de Roblox; si no sale (versión antigua, grupo cerrado), queda el botón de al lado.
		local ok = group > 0 and pcall(function()
			GroupService:PromptJoinAsync(group)
		end)
		if ok then
			retry()
		else
			Ui.toast("Únete al grupo desde la página del juego", Ui.COLORS.orange)
		end
	end)
	check.Activated:Connect(retry)
	close.Activated:Connect(function()
		Ui.close(card)
	end)
	player:GetAttributeChangedSignal("AutoClick"):Connect(function()
		if on("AutoClick") and Ui.isOpen(card) then
			Ui.close(card)
			Sfx.play("win")
			Ui.toast("¡Autoclicker desbloqueado!", ON_COLOR)
		end
	end)
	return function(id: number?)
		group = id or 0
		if Ui.isOpen(card) then
			if asked then
				Sfx.play("error")
				Ui.toast("Aún no estás en el grupo", Ui.COLORS.orange)
			end
		else
			Ui.open(card)
			Sfx.play("toast")
		end
		asked = false
	end
end

function AutoPlay.start()
	local dock = Ui.hud():WaitForChild("WeaponSlot")
	local showUnlock = buildUnlock()

	local function wire(mode: string, name: string, text: string, color: Color3, side: number)
		local button, state, iconScale = build(dock, name, text, color, side)
		local pulse: Tween? = nil
		local function paint()
			local active = on(name)
			local locked = mode == "farm" and not Stats.perk(player, "autoFarm")
			button.BackgroundColor3 = if active then ON_COLOR else color
			state.Text = if locked then "R$" elseif active then "ON" else "OFF"
			state.BackgroundColor3 = if locked then ROBUX elseif active then ON_COLOR else Ui.COLORS.dark
			-- Encendido, el icono late: se ve de un vistazo que está trabajando.
			if pulse then
				pulse:Cancel()
				pulse = nil
			end
			iconScale.Scale = 1
			if active and not Performance.get() then
				pulse = TweenService:Create(iconScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 })
				pulse:Play()
			end
			if active then
				task.spawn(run)
			end
		end
		button.Activated:Connect(function()
			Remotes.SetAuto:FireServer(mode, not on(name))
		end)
		player:GetAttributeChangedSignal(name):Connect(paint)
		if mode == "farm" then
			player.AttributeChanged:Connect(function(attribute)
				if string.sub(attribute, 1, 5) == "Pass_" then
					paint()
				end
			end)
		end
		Ui.tip(button, function()
			if mode == "click" then
				return "<b>Autoclicker</b>\nDa espadazos solo mientras llevas el arma en la mano.\nGratis: dale me gusta al juego y únete al grupo.", CLICK_COLOR
			end
			return "<b>Auto</b>\nEn tu parcela, tu personaje va solo a por los objetos y los rompe.\nPase de juego.", FARM_COLOR
		end, true)
		paint()
	end
	wire("click", "AutoClick", "CLICK", CLICK_COLOR, -1)
	wire("farm", "AutoFarm", "AUTO", FARM_COLOR, 1)

	Remotes.AutoDenied.OnClientEvent:Connect(function(mode: string, group: number?)
		if mode == "click" then
			showUnlock(group)
		else
			Sfx.play("error")
			Ui.toast("El Auto es un pase de juego", FARM_COLOR)
			if not Ui.isOpen(Ui.screen():FindFirstChild("PassShop") :: GuiObject) then
				Ui.toggle("PassShop")
			end
		end
	end)
end

return AutoPlay
