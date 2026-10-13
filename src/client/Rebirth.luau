-- Ventana de Renacimiento: hace falta tener su precio en monedas y quita todas las monedas, las gemas y las
-- mejoras, y devuelve la Bolsa de oro a la primera; a cambio multiplica para siempre las monedas, el daño y las
-- suertes. Se abre con el botón "Renacer" del menú de la izquierda. El servidor comprueba y reinicia (Rebirth);
-- aquí se enseñan los números, se pide (con un segundo toque: ya no es gratis) y, cuando el servidor avisa con
-- Reborn, se enseña la cinemática (RollCinematic.playRebirth) o, si no puede salir, un aviso.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local RollCinematic = require(script.Parent.RollCinematic)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Rebirth = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 60)
local CONFIRM = 3 -- segundos que dura el "¿Seguro?" del botón
local NEAR = 180 -- studs: más lejos no se ve el destello de otro jugador que renace

-- Lo que sube cada renacimiento: clave de Config.Rebirth, nombre y color.
local STATS = {
	{ "coins", Lang.t(nil, "Coins"), Color3.fromRGB(255, 200, 60) },
	{ "damage", Lang.t(nil, "Damage"), Color3.fromRGB(255, 130, 90) },
	{ "luck", Lang.t(nil, "Object luck"), Color3.fromRGB(110, 225, 110) },
	{ "gachaLuck", Lang.t(nil, "Weapon luck"), Color3.fromRGB(190, 130, 255) },
}

function Rebirth.start()
	local window, body = Ui.window("Rebirth", Lang.t(nil, "Rebirth"), Vector2.new(520, 592), function(parent)
		Ui.image(parent, "rebirth")
	end)

	-- Contenido apilado de arriba abajo por un UIListLayout (alturas en Scale del cuerpo). Va en su
	-- propio marco: el cuerpo tiene además las rayas de fondo y el destello, que no se apilan.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = body
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0.012, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	-- Estrella grande (cuadrada: manda el alto) y contador de renacimientos.
	local star = Instance.new("Frame")
	star.Name = "Star"
	star.LayoutOrder = 1
	star.Size = UDim2.fromScale(1, 0.16)
	star.BackgroundTransparency = 1
	star.Parent = content
	local square = Instance.new("UIAspectRatioConstraint")
	square.DominantAxis = Enum.DominantAxis.Height
	square.Parent = star
	Ui.starIcon(star, GOLD)
	local starScale = Instance.new("UIScale")
	starScale.Parent = star

	local count = Ui.label(content, 30)
	count.LayoutOrder = 2
	count.Size = UDim2.fromScale(1, 0.07)

	-- Una fila por estadística: nombre, lo que multiplica ahora y lo que multiplicará.
	local list = Instance.new("Frame")
	list.Name = "Stats"
	list.LayoutOrder = 3
	list.Size = UDim2.fromScale(1, 0.42)
	list.BackgroundTransparency = 1
	list.Parent = content
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0.04, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local rows = {}
	for index, entry in STATS do
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.fromScale(1, 0.22)
		row.BackgroundColor3 = WHITE
		row.Parent = list
		Ui.round(row, 10)
		Ui.stroke(row, BLACK, 3)
		Ui.panel(row, Color3.fromRGB(62, 68, 118), entry[3])
		local name = Ui.label(row, 22)
		name.Position = UDim2.fromOffset(18, 0)
		name.Size = UDim2.new(0.54, -18, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = entry[3]
		name.Text = entry[2]
		-- (El nombre se lleva algo más de la mitad: "Suerte de destructibles" es el más largo y cabe sin encoger.)
		local value = Ui.label(row, 22)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -14, 0, 0)
		value.Size = UDim2.new(0.46, -14, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[entry[1]] = value
	end

	local cost = Ui.label(content, 24)
	cost.LayoutOrder = 4
	cost.Size = UDim2.fromScale(1, 0.06)

	local button = Ui.button(content, Lang.t(nil, "Rebirth now"), Ui.COLORS.green)
	button.Name = "Rebirth"
	button.LayoutOrder = 5
	button.Size = UDim2.fromScale(0.55, 0.12)
	button.TextSize = 30

	local note = Ui.label(content, 16)
	note.LayoutOrder = 6
	note.Size = UDim2.fromScale(1, 0.045)
	note.TextColor3 = Color3.fromRGB(255, 150, 150)
	note.TextScaled = true
	note.Text = Lang.t(nil, "You lose your coins, gems, upgrades and Gold Bag. Weapons and gear stay.")
	local noteLimit = Instance.new("UITextSizeConstraint")
	noteLimit.MaxTextSize = 16
	noteLimit.MinTextSize = 10
	noteLimit.Parent = note

	local asking = 0 -- hasta cuándo (os.clock) el botón pregunta "¿Seguro?"

	local function refresh()
		local current = Stats.rebirths(player)
		local price = Stats.rebirthCost(player)
		local coins = player:GetAttribute("Coins") or 0
		local capped = current >= Config.Rebirth.max
		local affordable = not capped and coins >= price
		count.Text = Lang.t(nil, "Rebirths: {n}", { n = `<font color="#{GOLD:ToHex()}">{current}/{Config.Rebirth.max}</font>` })
		for _, entry in STATS do
			local key = entry[1]
			local now = Config.Rebirth[key] ^ current
			local after = now * Config.Rebirth[key]
			rows[key].Text = if capped then `x{Format.multiplier(now)}` else `x{Format.multiplier(now)} <font color="{Ui.SOFT}">→</font> <font color="#7ee07a">x{Format.multiplier(after)}</font>`
		end
		cost.Text = if capped then Lang.t(nil, "Max reached") else Lang.t(nil, "Price: {n} coins", { n = `<font color="{if affordable then "#ffd24a" else "#ff6a6a"}">{Format.short(price)}</font>` })
		local sure = affordable and os.clock() < asking
		button.Text = if capped then Lang.t(nil, "Max reached") elseif sure then Lang.t(nil, "Sure?") else Lang.t(nil, "Rebirth now")
		button.Interactable = affordable
		button.BackgroundColor3 = if sure then Ui.COLORS.red elseif affordable then Ui.COLORS.green else Ui.COLORS.gray
	end

	-- El primer toque pregunta; el segundo, antes de CONFIRM segundos, renace.
	button.Activated:Connect(function()
		if os.clock() < asking then
			asking = 0
			Remotes.Rebirth:FireServer()
		else
			asking = os.clock() + CONFIRM
			local mine = asking
			starScale.Scale = 1.3
			TweenService:Create(starScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			task.delay(CONFIRM, function()
				if asking == mine then
					refresh()
				end
			end)
		end
		refresh()
	end)

	-- Alguien ha renacido. Si soy yo: se cierran las ventanas y sale la cinemática; al volver (o si no pudo salir,
	-- con un aviso), el destello en el mundo, que es lo único que ven los demás.
	local function burst(who: Player)
		local character = who.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not Performance.get() and (root.Position - workspace.CurrentCamera.CFrame.Position).Magnitude < NEAR then
			RollCinematic.rebirthBurst(root.Position)
		end
		return root
	end
	Remotes.Reborn.OnClientEvent:Connect(function(who: Player, count: number, coins: number, gems: number)
		if who ~= player then
			local root = burst(who)
			if root then
				Sfx.play("rebirth", nil, nil, root)
			end
			return
		end
		Ui.closeAll()
		local waited = 0
		while Ui.anyOpen() and waited < 1.5 do
			waited += task.wait()
		end
		local rows = {}
		for _, entry in STATS do
			local mult = Config.Rebirth[entry[1]]
			table.insert(rows, { name = entry[2], color = entry[3], before = mult ^ (count - 1), after = mult ^ count })
		end
		if not RollCinematic.playRebirth({ count = count, coins = coins or 0, gems = gems or 0, rows = rows }) then
			Sfx.play("rebirth")
			Ui.toast(Lang.t(nil, "Rebirth {count}! Coins x{n} and more forever", { count = count, n = Format.multiplier(Config.Rebirth.coins ^ count) }), GOLD)
		end
		burst(player)
	end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if window.Visible then
			refresh()
		end
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	refresh()
end

return Rebirth
