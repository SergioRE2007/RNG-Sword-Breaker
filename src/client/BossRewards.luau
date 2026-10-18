-- Premios del Jefe del mundo a la vista (pedido por el usuario el 18-10-2026: antes eran una línea de texto en el panel
-- del jefe). Al llegar el aviso `result`, una ventana como la del botín de mazmorra con una tarjeta por premio (imagen,
-- nombre y cantidad) que van saliendo una a una. Solo enseña: el servidor ya lo ha dado todo al mandarlo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Potions = require(script.Parent.Potions)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local BossRewards = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 210, 80)
local CARD = Vector2.new(132, 176)
local CELL = 100 -- casilla cuadrada con la imagen
local COLUMNS = 5
local STAGGER = 0.12 -- segundos entre una tarjeta y la siguiente

local window: Frame
local head: TextLabel
local grid: Frame
local cards: { GuiObject } = {}
local shown = 0 -- cuenta de ventanas abiertas: una tanda vieja no sigue sacando tarjetas en la nueva

-- Lo que se ve de cada premio: { name, color, tier, amount, icon(casilla) }.
local function entries(prize)
	local list = {}
	if prize.rolls > 0 then
		table.insert(list, {
			name = Lang.t(nil, if prize.rolls == 1 then "Weapon roll" else "Weapon rolls"),
			color = GOLD,
			tier = 5,
			amount = prize.rolls,
			icon = function(cell)
				Ui.image(cell, "espada")
			end,
		})
	end
	for _, key in { "traitCrystal", "gradeCrystal" } do
		local item = Config.Items[key]
		if item and prize[key] > 0 then
			table.insert(list, {
				name = Lang.t(nil, item.name),
				color = item.color,
				tier = 4,
				amount = prize[key],
				icon = function(cell)
					Ui.crystalIcon(cell, item.color, key == "gradeCrystal")
				end,
			})
		end
	end
	if prize.potions > 0 then
		for _, family in Config.Potions.Order do
			if Config.Items[`potion_{family}_{prize.potionTier}`] then
				table.insert(list, {
					name = Lang.t(nil, Config.Potions.Families[family].name),
					color = PotionInfo.color(prize.potionTier),
					tier = prize.potionTier,
					amount = prize.potions,
					icon = function(cell)
						Potions.icon(cell, family, prize.potionTier)
						Potions.addTag(cell, prize.potionTier, true)
					end,
				})
			end
		end
	end
	if prize.tickets > 0 then
		local item = Config.Items.missionToken
		table.insert(list, {
			name = Lang.t(nil, if prize.tickets == 1 then "Ticket" else "Tickets"),
			color = item.color,
			tier = 5,
			amount = prize.tickets,
			icon = function(cell)
				Ui.ticketIcon(cell, item.color)
			end,
		})
	end
	return list
end

local function buildCard(data, order: number): GuiObject
	-- La tarjeta va dentro de un hueco del tamaño de la rejilla para que su UIScale la haga crecer sin mover a las demás.
	local slot = Instance.new("Frame")
	slot.Name = "Reward" .. order
	slot.LayoutOrder = order
	slot.BackgroundTransparency = 1
	slot.Parent = grid
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Parent = slot
	Ui.round(card, 12)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(58, 62, 108), data.color)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card

	local cell = Ui.cell(card, data.color, data.tier)
	cell.Name = "Image"
	cell.AnchorPoint = Vector2.new(0.5, 0)
	cell.Position = UDim2.new(0.5, 0, 0, 10)
	cell.Size = UDim2.fromOffset(CELL, CELL)
	cell.Active = false
	data.icon(cell)
	Ui.cellLabel(cell, "x" .. Format.short(data.amount))

	local name = Ui.label(card, 16)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(6, CELL + 16)
	name.Size = UDim2.new(1, -12, 1, -(CELL + 22))
	name.TextWrapped = true
	name.Text = data.name
	name.TextColor3 = data.color:Lerp(WHITE, 0.45)
	return slot
end

local function build()
	local body
	window, body = Ui.window("BossRewards", Lang.t(nil, "BOSS REWARDS"), Vector2.new(COLUMNS * CARD.X + (COLUMNS - 1) * 10 + 40, 610))

	head = Ui.label(body, 24)
	head.Name = "Head"
	head.Position = UDim2.fromOffset(12, 8)
	head.Size = UDim2.new(1, -24, 0, 36)

	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(8, 52)
	grid.Size = UDim2.new(1, -16, 1, -52 - 84)
	grid.BackgroundTransparency = 1
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD.X, CARD.Y)
	layout.CellPadding = UDim2.fromOffset(10, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = grid

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -10)
	bar.Size = UDim2.fromOffset(260, 64)
	bar.BackgroundTransparency = 1
	bar.Parent = body
	local collect = Ui.button(bar, Lang.t(nil, "Collect"), Ui.COLORS.green)
	collect.Name = "Collect"
	collect.Size = UDim2.fromScale(1, 1)
	collect.Activated:Connect(function()
		Ui.close(window)
	end)
end

-- `prize` = WorldBossInfo.rewards del jugador (nil si no llegó al primer tramo); `rank` y `damage`, su puesto y su daño.
function BossRewards.show(prize, rank: number?, damage: number?)
	if not prize then
		return
	end
	if not window then
		build()
	end
	for _, card in cards do
		card:Destroy()
	end
	cards = {}
	shown += 1
	local current = shown
	local damageText = Lang.t(nil, "Your damage: {n}", { n = Format.short(damage or 0) })
	head.Text = if rank then `<font color="#FFD250">#{rank}</font>  ·  {damageText}` else damageText
	local list = entries(prize)
	for order, data in list do
		table.insert(cards, buildCard(data, order))
	end
	Ui.open(window)
	Sfx.play("collect")
	-- Las tarjetas salen una a una, con un rebote.
	task.spawn(function()
		for _, slot in cards do
			task.wait(STAGGER)
			if shown ~= current or not slot.Parent then
				return
			end
			local scale = slot.Card:FindFirstChildOfClass("UIScale")
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sfx.play("tick", nil, 1 + 0.06 * slot.LayoutOrder)
		end
	end)
end

return BossRewards
