-- Aviso de arma recogida (librería sin start(), la llama client/RollReveal cuando un arma llega al jugador). Pedido
-- por el usuario: con la presentación en el mundo no se sabía qué había tocado. A la derecha, a media altura, sale
-- una tarjeta por arma con su casilla (modelo 3D y borde de su rareza), la rareza, el nombre y el "1 entre N"; la nueva
-- entra arriba empujando a las demás y cada una se va sola a los pocos segundos (más rato cuanto más rara). Si llega
-- otra igual mientras sigue a la vista, la tarjeta no se repite: suma un "x2", "x3"...
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local WeaponFeed = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Medidas en unidades del HUD (Ui.hud ya lo encoge entero en pantallas pequeñas).
local CARD = Vector2.new(250, 64)
local CELL = 54
local MARGIN = 14 -- al borde derecho
local TOP = 0.44 -- a qué altura de la pantalla empieza la columna (0 = arriba del todo)
local GAP = 6
local MAX_CARDS = 4
local STAY = 3.5 -- segundos a la vista de un arma Común
local STAY_PER_TIER = 0.6 -- y cuánto más por cada nivel de rareza
-- Capas (la interfaz ordena el ZIndex globalmente): las de la casilla (Ui.cell, WeaponPreview) van de 0 a 3.
local Z = { card = 1, text = 3 }

local list: Frame? = nil
local cards = {} -- [clave "arma:metal:tamaño"] = { slot, count, badge, scale, until }

local function tween(instance: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local created = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	created:Play()
	return created
end

-- La columna de tarjetas, pegada a la derecha.
local function column(): Frame
	if list then
		return list
	end
	local root = Ui.hud()
	local frame = Instance.new("Frame")
	frame.Name = "WeaponFeed"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Size = UDim2.fromOffset(CARD.X, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = frame

	-- A media altura (pedido por el usuario: arriba tapaba la lista de jugadores de Roblox, Ajustes y los demás
	-- botones de esa esquina). Abajo quedan la tira de pociones y los avisos.
	frame.Position = UDim2.new(1, -MARGIN, TOP, 0)
	list = frame
	return frame
end

local function remove(key: string, quick: boolean?)
	local entry = cards[key]
	if not entry then
		return
	end
	cards[key] = nil
	local slot, card = entry.slot, entry.card
	if quick then
		slot:Destroy()
		return
	end
	tween(card, 0.25, { Position = UDim2.fromOffset(CARD.X + MARGIN + 10, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.26, function()
		slot:Destroy()
	end)
end

-- Se va sola cuando pasa su rato (que vuelve a empezar si se suma otra igual).
local function schedule(key: string, entry)
	local deadline = entry.deadline
	task.delay(deadline - os.clock(), function()
		if cards[key] == entry and entry.deadline == deadline then
			remove(key)
		end
	end)
end

local function textRow(parent: Instance, name: string, y: number, height: number, size: number): TextLabel
	local label = Ui.label(parent, size)
	label.Name = name
	label.Position = UDim2.fromOffset(CELL + 16, y)
	label.Size = UDim2.new(1, -(CELL + 24), 0, height)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.RichText = true
	label.ZIndex = Z.text
	return label
end

-- Un arma recogida: `roll` = { index, metal, size } (la tirada de client/RollReveal).
function WeaponFeed.push(roll)
	local key = `{roll.index}:{roll.metal or 0}:{roll.size or 0}`
	local tier = Rarity.tier(Permanent.rarity(roll.index, roll.metal, roll.size))
	local level = table.find(Config.RarityTiers, tier) or 1
	local stay = STAY + STAY_PER_TIER * (level - 1)

	local existing = cards[key]
	if existing then
		existing.count += 1
		existing.badge.Text = `x{existing.count}`
		existing.badge.Visible = true
		existing.slot.LayoutOrder = -os.clock() * 1000 -- vuelve arriba
		existing.scale.Scale = 1.08
		tween(existing.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		existing.deadline = os.clock() + stay
		schedule(key, existing)
		return
	end

	local holder = column()
	local count = 0
	local oldest, oldestKey = math.huge, nil
	for otherKey, other in cards do
		count += 1
		if other.born < oldest then
			oldest, oldestKey = other.born, otherKey
		end
	end
	if count >= MAX_CARDS and oldestKey then
		remove(oldestKey, true)
	end

	-- El hueco en la columna no se mueve; la tarjeta de dentro entra deslizándose desde la derecha.
	local slot = Instance.new("Frame")
	slot.Name = "Weapon"
	slot.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = -os.clock() * 1000 -- la nueva, arriba
	slot.Parent = holder

	local color = tier.color
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.Position = UDim2.fromOffset(CARD.X + MARGIN + 10, 0)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ZIndex = Z.card
	card.Parent = slot
	Ui.round(card, 12)
	Ui.stroke(card, BLACK, 3)
	-- Fondo oscuro como los avisos, teñido del color de la rareza por el lado de la casilla.
	Ui.gradient(card, Color3.fromRGB(70, 74, 98), Color3.fromRGB(28, 29, 40), 90)
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = color
	tint.BorderSizePixel = 0
	tint.ZIndex = Z.card
	tint.Parent = card
	Ui.round(tint, 12)
	local tintFade = Instance.new("UIGradient")
	tintFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.95),
		NumberSequenceKeypoint.new(1, 1),
	})
	tintFade.Parent = tint
	local scale = Instance.new("UIScale")
	scale.Parent = card

	local cell = Ui.cell(card, color, level)
	cell.Name = "Cell"
	cell.Active = false
	cell.AnchorPoint = Vector2.new(0, 0.5)
	cell.Position = UDim2.new(0, 6, 0.5, 0)
	cell.Size = UDim2.fromOffset(CELL, CELL)
	WeaponPreview.attach(cell, roll.index, color, roll.metal)

	local rarityText = textRow(card, "Rarity", 6, 16, 15)
	rarityText.Text = Ui.rarityText(Ui.upper(Lang.t(nil, tier.name)), color:Lerp(WHITE, 0.2), level)
	local sword = Config.Swords[roll.index]
	local nameColor = if roll.metal and roll.metal > 0 then Config.Metals[roll.metal].color else sword.color
	local nameText = textRow(card, "WeaponName", 22, 22, 18)
	nameText.Text = Permanent.name(roll.index, roll.metal, roll.size)
	nameText.TextColor3 = nameColor:Lerp(WHITE, 0.4)
	local oddsText = textRow(card, "Odds", 43, 15, 13)
	oddsText.Text = `<font color="{Ui.SOFT}">{Permanent.describeOdds(roll.index, roll.metal, roll.size)}</font>`

	local badge = Ui.label(card, 16)
	badge.Name = "Count"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -6, 0, 5)
	badge.Size = UDim2.fromOffset(40, 18)
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.Text = ""
	badge.TextColor3 = Ui.COLORS.coins
	badge.ZIndex = Z.text
	badge.Visible = false

	local entry = { slot = slot, card = card, badge = badge, scale = scale, count = 1, born = os.clock(), deadline = os.clock() + stay }
	cards[key] = entry
	tween(card, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	schedule(key, entry)
end

return WeaponFeed
