-- Ventana de Renacimiento: se paga solo con monedas, no quita nada y multiplica para siempre las
-- monedas, el daño y las suertes. Se abre con el botón "Renacer" del menú de la izquierda. El
-- servidor cobra y cuenta (Rebirth); aquí solo se enseñan los números y se pide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Rebirth = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 60)

-- Lo que sube cada renacimiento: clave de Config.Rebirth, nombre y color.
local STATS = {
	{ "coins", "Monedas", Color3.fromRGB(255, 200, 60) },
	{ "damage", "Daño", Color3.fromRGB(255, 130, 90) },
	{ "luck", "Suerte", Color3.fromRGB(110, 225, 110) },
	{ "gachaLuck", "Suerte de gacha", Color3.fromRGB(190, 130, 255) },
}

function Rebirth.start()
	local window, body = Ui.window("Rebirth", "Renacimiento", Vector2.new(520, 592), function(parent)
		Ui.starIcon(parent, GOLD)
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
		name.Size = UDim2.new(0.42, 0, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = entry[3]
		name.Text = entry[2]
		local value = Ui.label(row, 22)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -14, 0, 0)
		value.Size = UDim2.new(0.58, 0, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[entry[1]] = value
	end

	local cost = Ui.label(content, 24)
	cost.LayoutOrder = 4
	cost.Size = UDim2.fromScale(1, 0.06)

	local button = Ui.button(content, "Renacer", Ui.COLORS.green)
	button.Name = "Rebirth"
	button.LayoutOrder = 5
	button.Size = UDim2.fromScale(0.55, 0.12)
	button.TextSize = 30

	local note = Ui.label(content, 16)
	note.LayoutOrder = 6
	note.Size = UDim2.fromScale(1, 0.045)
	note.TextColor3 = Color3.fromRGB(190, 195, 215)
	note.Text = "No pierdes nada: solo gastas las monedas del precio."

	local function refresh()
		local current = Stats.rebirths(player)
		local price = Stats.rebirthCost(player)
		local coins = player:GetAttribute("Coins") or 0
		local affordable = coins >= price
		count.Text = `Renacimientos: <font color="#{GOLD:ToHex()}">{current}</font>`
		for _, entry in STATS do
			local key = entry[1]
			local now = Config.Rebirth[key] ^ current
			local after = now * Config.Rebirth[key]
			rows[key].Text = `x{Format.multiplier(now)} <font color="{Ui.SOFT}">→</font> <font color="#7ee07a">x{Format.multiplier(after)}</font>`
		end
		cost.Text = `Precio: <font color="{if affordable then "#ffd24a" else "#ff6a6a"}">{Format.short(price)}</font> monedas`
		button.BackgroundColor3 = if affordable then Ui.COLORS.green else Ui.COLORS.gray
	end

	button.Activated:Connect(function()
		Remotes.Rebirth:FireServer()
	end)

	-- Al subir el contador: destello dorado en la ventana, la estrella da un salto y suena.
	local last = Stats.rebirths(player)
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = GOLD
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 30
	flash.Active = false
	flash.Parent = body
	Ui.round(flash, 12)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		local now = Stats.rebirths(player)
		if now > last then
			Sfx.play("win")
			if not Performance.get() then
				flash.BackgroundTransparency = 0.35
				TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
				starScale.Scale = 1.5
				TweenService:Create(starScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
		last = now
		refresh()
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if window.Visible then
			refresh()
		end
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	refresh()
end

return Rebirth
