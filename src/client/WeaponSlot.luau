-- Las armas equipadas, abajo en el centro: una casilla por hueco de Config.Loadout.Slots, con la misma casilla, vista
-- 3D y cartel que la mochila. Pulsar cualquiera abre la mochila, que es donde se cambian. La casilla de un arma da
-- un latido cada vez que esa arma pega (aviso Hit con su hueco): se ve que cada una lleva su ritmo.
--   Hud.HudRoot.WeaponSlot.Row.Slot<n>.Sword (hueco con arma) o .Empty (libre)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Backpack = require(script.Parent.Backpack)
local Performance = require(script.Parent.Performance)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local WeaponSlot = {}
-- Lado de cada casilla, en unidades del HUD (Ui.hud ya adapta su escala); AutoPlay pone sus botones a los lados. Con
-- 76 la fila entera (4 casillas y los dos botones) cabe entre las monedas y las pociones en la pantalla más estrecha.
WeaponSlot.SIZE = 76

local player = Players.LocalPlayer
local SIZE = WeaponSlot.SIZE
local GAP = 12 -- entre casillas: caben justos sus marcos (6 por lado)
-- Todo el acceso rápido va en la capa 0; las ventanas empiezan en 1. Dentro manda el orden del árbol.
local LAYER = { cell = 0, preview = 0, detail = 0 }
local BEAT = 1.07 -- lo que crece la casilla con cada golpe de su arma
local BEAT_GAP = 0.12 -- segundos mínimos entre dos latidos de una casilla
local BEAT_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FULL = UDim2.fromScale(1, 1)

local function open()
	local window = Ui.screen():FindFirstChild("Backpack")
	if window and not Ui.isOpen(window :: GuiObject) then
		Ui.toggle("Backpack")
	end
end

-- Casilla de un hueco con arma.
local function sword(holder: Frame, copy): TextButton
	local tier = Rarity.tier(Stats.rarity(copy))
	local cell = Ui.cell(holder, tier.color, table.find(Config.RarityTiers, tier))
	cell.Name = "Sword"
	local preview = WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
	preview.ZIndex = LAYER.preview
	local damage = Ui.cellLabel(cell, Format.multiplier(Stats.swordDamage(copy)))
	damage.Position = UDim2.new(0.5, 3, 1, -3)
	damage.Size = UDim2.new(1, -10, 0, 22)
	damage.TextXAlignment = Enum.TextXAlignment.Left
	damage.ZIndex = LAYER.detail
	damage:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 19
	damage:FindFirstChildOfClass("UIStroke").Thickness = 2.5
	Ui.gradient(damage, Color3.new(1, 1, 1), tier.color:Lerp(Color3.new(1, 1, 1), 0.45), 90)
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	if metal then
		local dot = Instance.new("Frame")
		dot.Name = "Metal"
		dot.Position = UDim2.fromOffset(6, 6)
		dot.Size = UDim2.fromOffset(16, 16)
		dot.BackgroundColor3 = metal.color
		dot.BorderSizePixel = 0
		dot.ZIndex = LAYER.detail
		dot.Parent = cell
		Ui.round(dot, 8)
		Ui.stroke(dot, Color3.new(0, 0, 0), 2)
	end
	if size then
		local tag = Ui.cellTag(cell, string.sub(size.name, 1, 1), size.color)
		tag.Position = UDim2.fromOffset(4, if metal then 26 else 4)
		tag.Size = UDim2.fromOffset(20, 20)
	end
	local trait = Config.Traits[copy.trait]
	if trait then
		local mark = Instance.new("Frame")
		mark.Name = "Trait"
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -8, 0, 8)
		mark.Size = UDim2.fromOffset(16, 16)
		mark.Rotation = 45
		mark.BackgroundColor3 = trait.color
		mark.BorderSizePixel = 0
		mark.ZIndex = LAYER.detail
		mark.Parent = cell
		Ui.stroke(mark, Color3.new(0, 0, 0), 2)
	end
	Ui.tip(cell, function()
		return Backpack.swordTip(copy)
	end, true)
	return cell
end

-- Casilla de un hueco libre.
local function empty(holder: Frame): TextButton
	local cell = Ui.cell(holder, Ui.COLORS.gray)
	cell.Name = "Empty"
	local plus = Ui.label(cell, 40)
	plus.Name = "Plus"
	plus.Size = FULL
	plus.Text = "+"
	plus.TextTransparency = 0.35
	plus.ZIndex = LAYER.detail
	Ui.tip(cell, function()
		return "<b>Hueco libre</b>\nAbre la mochila y equipa otra arma:\ntodas las equipadas atacan a la vez.", Ui.COLORS.gray
	end, true)
	return cell
end

function WeaponSlot.start()
	local root = Ui.hud()
	local slots = Config.Loadout.Slots
	local dock = Instance.new("Frame")
	dock.Name = "WeaponSlot"
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Size = UDim2.fromOffset(slots * SIZE + (slots - 1) * GAP, SIZE)
	dock.BackgroundTransparency = 1
	dock.Parent = root
	local function fit()
		-- En vertical, deja sitio a los contadores inferiores y a los controles táctiles.
		dock.Position = UDim2.new(0.5, 0, 1, if root.AbsoluteSize.X < root.AbsoluteSize.Y then -154 else -16)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	-- Las casillas van en su propia fila: del dock cuelgan también los botones de AutoPlay.
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = FULL
	row.BackgroundTransparency = 1
	row.Parent = dock
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, GAP)
	list.Parent = row

	-- Cada hueco es un marco fijo de la fila, y la casilla va dentro centrada: así crece al pasar el ratón o al latir
	-- sin mover a las de al lado.
	local holders, cells, keys, beats = {}, {}, {}, {}
	for index = 1, slots do
		local holder = Instance.new("Frame")
		holder.Name = "Slot" .. index
		holder.LayoutOrder = index
		holder.Size = UDim2.fromOffset(SIZE, SIZE)
		holder.BackgroundTransparency = 1
		holder.Parent = row
		holders[index] = holder
	end

	local function refresh()
		local copies = Stats.loadout(player)
		for index, holder in holders do
			local copy = copies[index]
			local key = if copy then `{copy.id}:{copy.sword}:{copy.metal}:{copy.size}:{copy.trait}:{copy.grade}` else ""
			if key == keys[index] then
				continue
			end
			keys[index] = key
			if cells[index] then
				cells[index]:Destroy()
			end
			local cell = if copy then sword(holder, copy) else empty(holder)
			cell.AnchorPoint = Vector2.new(0.5, 0.5)
			cell.Position = UDim2.fromScale(0.5, 0.5)
			cell.Size = FULL
			cell.ZIndex = LAYER.cell
			-- Los helpers de inventario crean adornos en 1-3: baja también sus fondos, brillos y etiquetas.
			Ui.layer(cell, LAYER.cell)
			cell.Activated:Connect(open)
			cells[index] = cell
		end
	end
	for _, attribute in { "Loadout", "Equipped", "Swords" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()

	Remotes.Hit.OnClientEvent:Connect(function(hitter: Player, _part, _position, _damage, slot: number?)
		local cell = hitter == player and slot and cells[slot]
		local now = os.clock()
		if not cell or Performance.get() or now - (beats[slot] or 0) < BEAT_GAP then
			return
		end
		beats[slot] = now
		cell.Size = UDim2.fromScale(BEAT, BEAT)
		TweenService:Create(cell, BEAT_OUT, { Size = FULL }):Play()
	end)
end

return WeaponSlot
