-- Casilla del arma elegida, abajo en el centro. Clic, toque o tecla 1 para sacarla o guardarla.
-- Usa la misma casilla, vista 3D y cartel que la mochila; guardar no cambia la copia elegida.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Backpack = require(script.Parent.Backpack)
local SwordController = require(script.Parent.SwordController)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local WeaponSlot = {}
local player = Players.LocalPlayer
-- Capas absolutas, iguales a las casillas de la mochila y por debajo de las ventanas.
local LAYER = { cell = 1, preview = 2, detail = 3 }
local SLOT_SIZE = 108 -- unidades del HUD: Ui.hud ya adapta su escala a la pantalla

function WeaponSlot.start()
	local root = Ui.hud()
	local dock = Instance.new("Frame")
	dock.Name = "WeaponSlot"
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE + 28)
	dock.BackgroundTransparency = 1
	dock.Parent = root
	local function fit()
		-- En vertical, deja sitio a los contadores inferiores y a los controles táctiles.
		dock.Position = UDim2.new(0.5, 0, 1, if root.AbsoluteSize.X < root.AbsoluteSize.Y then -154 else -16)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local cell, equippedTag
	local copy = Stats.equipped(player)
	local previousKey
	local function refreshHand()
		if not cell then return end
		local drawn = SwordController.isDrawn()
		cell.Select.Visible = drawn
		equippedTag.Visible = drawn
	end
	local function refresh()
		copy = Stats.equipped(player)
		local key = `{copy.id}:{copy.sword}:{copy.metal}:{copy.size}:{copy.trait}:{copy.grade}`
		if key == previousKey then
			refreshHand()
			return
		end
		previousKey = key
		if cell then cell:Destroy() end
		local tier = Rarity.tier(Stats.rarity(copy))
		cell = Ui.cell(dock, tier.color, table.find(Config.RarityTiers, tier))
		cell.Name = "Sword"
		cell.Size = UDim2.new(1, 0, 0, SLOT_SIZE)
		cell.ZIndex = LAYER.cell
		local preview = WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
		preview.ZIndex = LAYER.preview
		local damageLabel = Ui.cellLabel(cell, Format.multiplier(Stats.swordDamage(copy)))
		damageLabel.Position = UDim2.new(0.5, 3, 1, -3)
		damageLabel.Size = UDim2.new(1, -10, 0, 26)
		damageLabel.TextXAlignment = Enum.TextXAlignment.Left
		damageLabel.ZIndex = LAYER.detail
		damageLabel:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 23
		damageLabel:FindFirstChildOfClass("UIStroke").Thickness = 2.5
		Ui.gradient(damageLabel, Color3.new(1, 1, 1), tier.color:Lerp(Color3.new(1, 1, 1), 0.45), 90)
		equippedTag = Ui.cellTag(cell, "E", Ui.COLORS.green)
		equippedTag.Name = "Equipped"
		local metal, size = Permanent.metal(copy), Permanent.size(copy)
		if metal then
			local dot = Instance.new("Frame")
			dot.Name = "Metal"
			dot.Position = UDim2.fromOffset(6, 30)
			dot.Size = UDim2.fromOffset(18, 18)
			dot.BackgroundColor3 = metal.color
			dot.BorderSizePixel = 0
			dot.ZIndex = LAYER.detail
			dot.Parent = cell
			Ui.round(dot, 9)
			Ui.stroke(dot, Color3.new(0, 0, 0), 2)
		end
		if size then
			Ui.cellTag(cell, string.sub(size.name, 1, 1), size.color).Position = UDim2.fromOffset(4, if metal then 52 else 30)
		end
		local trait = Config.Traits[copy.trait]
		if trait then
			local mark = Instance.new("Frame")
			mark.Name = "Trait"
			mark.AnchorPoint = Vector2.new(1, 0)
			mark.Position = UDim2.new(1, -9, 0, 9)
			mark.Size = UDim2.fromOffset(20, 20)
			mark.Rotation = 45
			mark.BackgroundColor3 = trait.color
			mark.BorderSizePixel = 0
			mark.ZIndex = LAYER.detail
			mark.Parent = cell
			Ui.stroke(mark, Color3.new(0, 0, 0), 2)
		end
		local shortcut = Ui.cellTag(cell, "1", Ui.COLORS.dark)
		shortcut.Name = "Shortcut"
		shortcut.AnchorPoint = Vector2.new(0.5, 0)
		shortcut.Position = UDim2.new(0.5, 0, 1, 7)
		shortcut.Size = UDim2.fromOffset(24, 21)
		Ui.tip(cell, function()
			return Backpack.swordTip(copy)
		end, true)
		cell.Activated:Connect(SwordController.toggle)
		refreshHand()
	end

	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(refreshHand)
		character.ChildRemoved:Connect(refreshHand)
		refreshHand()
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then watchCharacter(player.Character) end
	for _, attribute in { "Equipped", "Swords" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.One then SwordController.toggle() end
	end)
	refresh()
end

return WeaponSlot
