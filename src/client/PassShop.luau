-- Tienda de pases de juego (botón "Tienda" del menú): una tarjeta por pase de Config.Gamepasses con lo que
-- da y su botón de compra. La compra la hace Roblox (MarketplaceService); el servidor (server/Passes) publica
-- cuáles tiene el jugador en los atributos "Pass_<clave>".
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local PassShop = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ROBUX = Color3.fromRGB(70, 215, 120)
local CARD_HEIGHT = 168

function PassShop.start()
	local window, body = Ui.window("PassShop", "Tienda", Vector2.new(720, 470), function(parent)
		Ui.gemIcon(parent, ROBUX)
	end)

	local note = Ui.label(body, 17)
	note.Position = UDim2.fromOffset(16, 6)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Color3.fromRGB(190, 195, 215)
	note.Text = "Pases de juego: se compran una vez y son para siempre."

	local list = Instance.new("ScrollingFrame")
	list.Name = "Passes"
	list.Position = UDim2.fromOffset(10, 38)
	list.Size = UDim2.new(1, -20, 1, -48)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local cards = {}
	for order, key in Config.GamepassOrder do
		local pass = Config.Gamepasses[key]
		local card = Instance.new("Frame")
		card.Name = "Pass_" .. key
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		card.BackgroundColor3 = WHITE
		card.BorderSizePixel = 0
		card.Parent = list
		Ui.round(card, 12)
		Ui.stroke(card, BLACK, 3)
		Ui.panel(card, Color3.fromRGB(56, 60, 108):Lerp(pass.color, 0.15), pass.color)

		-- Insignia del pase: un medallón del color del pase que late despacio.
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 22, 0.5, 0)
		badge.Size = UDim2.fromOffset(104, 104)
		badge.BackgroundColor3 = WHITE
		badge.BorderSizePixel = 0
		badge.Parent = card
		Ui.round(badge, 52)
		Ui.stroke(badge, BLACK, 3)
		Ui.gradient(badge, pass.color:Lerp(WHITE, 0.35), pass.color:Lerp(BLACK, 0.45), 90)
		local iconBox = Instance.new("Frame")
		iconBox.AnchorPoint = Vector2.new(0.5, 0.5)
		iconBox.Position = UDim2.fromScale(0.5, 0.5)
		iconBox.Size = UDim2.fromScale(0.7, 0.7)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = badge
		Ui.starIcon(iconBox, Color3.fromRGB(255, 235, 150))
		local badgeScale = Instance.new("UIScale")
		badgeScale.Parent = badge
		if not Performance.get() then
			TweenService:Create(badgeScale, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
		end

		local name = Ui.label(card, 28)
		name.Position = UDim2.fromOffset(142, 10)
		name.Size = UDim2.new(1, -142 - 190, 0, 34)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextScaled = true
		name.Text = pass.name
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 28
		nameLimit.MinTextSize = 16
		nameLimit.Parent = name
		Ui.gradient(name, WHITE, pass.color:Lerp(WHITE, 0.45), 90)

		-- Lo que da, una línea por ventaja.
		local lines = {}
		for _, text in pass.perksText do
			table.insert(lines, `<font color="#{ROBUX:ToHex()}">+</font> {text}`)
		end
		local perks = Ui.label(card, 18)
		perks.Position = UDim2.fromOffset(142, 48)
		perks.Size = UDim2.new(1, -142 - 190, 1, -58)
		perks.TextXAlignment = Enum.TextXAlignment.Left
		perks.TextYAlignment = Enum.TextYAlignment.Top
		perks.TextWrapped = true
		perks.LineHeight = 1.15
		perks.Text = table.concat(lines, "\n")

		local buy = Ui.button(card, "", ROBUX)
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -16, 0.5, 0)
		buy.Size = UDim2.fromOffset(160, 74)
		buy.TextSize = 26
		Ui.sparkle(buy, 4)

		local entry = { key = key, pass = pass, buy = buy, price = pass.price }
		cards[key] = entry
		-- El precio de verdad lo dice Roblox (el de Config es solo el que se enseña mientras llega).
		if pass.id > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.id, Enum.InfoType.GamePass)
				if ok and type(info) == "table" and info.PriceInRobux then
					entry.price = info.PriceInRobux
					if buy.Parent and not Stats.pass(player, key) then
						buy.Text = `R$ {entry.price}`
					end
				end
			end)
		end
		buy.Activated:Connect(function()
			if Stats.pass(player, key) then
				return
			end
			if pass.id <= 0 then
				Sfx.play("error")
				Ui.toast("Este pase aún no está a la venta", Ui.COLORS.orange)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
	end

	local function refresh()
		for key, entry in cards do
			local owned = Stats.pass(player, key)
			entry.buy.Text = if owned then "¡Lo tienes!" elseif entry.pass.id <= 0 then "Pronto" else `R$ {entry.price}`
			entry.buy.BackgroundColor3 = if owned then Ui.COLORS.blue elseif entry.pass.id <= 0 then Ui.COLORS.gray else ROBUX
			entry.buy.TextSize = if owned then 22 else 26
		end
	end
	player.AttributeChanged:Connect(function(attribute)
		if string.sub(attribute, 1, 5) == "Pass_" then
			if player:GetAttribute(attribute) == true and window.Visible then
				Sfx.play("win")
			end
			refresh()
		end
	end)
	refresh()
end

return PassShop
