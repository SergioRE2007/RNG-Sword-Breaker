-- Selección múltiple y confirmación de venta. El servidor comprueba de nuevo cada copia.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local SellMenu = {}
local player = Players.LocalPlayer
local window, refresh, paint
local selected, cells = {}, {}
local confirming = false

function SellMenu.open(id: number?)
	selected = {}
	confirming = false
	if id and id ~= player:GetAttribute("Equipped") then selected[id] = true end
	Ui.toggle("SellMenu")
end

function SellMenu.start()
	local body
	window, body = Ui.window("SellMenu", "Vender armas", Vector2.new(740, 560))
	local summary = Ui.label(body, 22)
	summary.Size = UDim2.fromScale(1, 0.09)
	summary.TextWrapped = true
	local stock = Instance.new("ScrollingFrame")
	stock.Name = "Stock"
	stock.Position = UDim2.fromScale(0.02, 0.11)
	stock.Size = UDim2.fromScale(0.96, 0.68)
	stock.BackgroundTransparency = 1
	stock.BorderSizePixel = 0
	stock.ScrollBarThickness = 6
	stock.CanvasSize = UDim2.new()
	stock.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stock.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(100, 100)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stock
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = stock
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Position = UDim2.fromScale(0.02, 0.83)
	actions.Size = UDim2.fromScale(0.96, 0.15)
	actions.BackgroundTransparency = 1
	actions.Parent = body
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0.02, 0)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = actions
	local buttons = {}
	for order, spec in { { "SelectAll", "Seleccionar todo", Ui.COLORS.blue }, { "Clear", "Deseleccionar todo", Ui.COLORS.gray }, { "Sell", "Vender selección", Ui.COLORS.red }, { "Cancel", "Volver", Ui.COLORS.gray } } do
		local button = Ui.button(actions, spec[2], spec[3])
		button.Name = spec[1]
		button.Size = UDim2.fromScale(0.235, 1)
		button.LayoutOrder = order
		button.TextWrapped = true
		button.TextSize = 20
		buttons[spec[1]] = button
	end
	paint = function()
		local count = 0
		for id, cell in cells do
			cell.Select.Visible = selected[id] == true
			if selected[id] then count += 1 end
		end
		if count == 0 then confirming = false end
		summary.Text = `{if confirming then "¿Confirmar venta? " else "Seleccionadas: "}{count} · +{Format.short(count * Config.Gacha.SellValue)} gemas`
		buttons.Sell.Text = if confirming then "Confirmar venta" else "Vender selección"
		buttons.Sell.Interactable = count > 0
	end
	refresh = function()
		if not window.Visible then return end
		confirming = false
		for _, cell in cells do cell:Destroy() end
		cells = {}
		local eligible = {}
		for _, copy in Stats.swords(player) do
			if copy.id == player:GetAttribute("Equipped") then continue end
			eligible[copy.id] = true
			local tier = Rarity.tier(Stats.rarity(copy))
			local cell = Ui.cell(stock, tier.color, table.find(Config.RarityTiers, tier))
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = copy.id
			WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
			Ui.cellLabel(cell, Format.multiplier(Stats.swordDamage(copy)))
			Ui.tip(cell, function()
				return `{Permanent.name(copy.sword, copy.metal, copy.size)}\n{Permanent.describeOdds(copy.sword, copy.metal, copy.size)}\nRasgo: {if Config.Traits[copy.trait] then Config.Traits[copy.trait].name else "ninguno"} · Grado: {if Config.Grades[copy.grade] then Config.Grades[copy.grade].name else "ninguno"}`, tier.color
			end, true)
			cell.Activated:Connect(function()
				confirming = false
				selected[copy.id] = if selected[copy.id] then nil else true
				paint()
			end)
			cells[copy.id] = cell
		end
		for id in selected do
			if not eligible[id] then selected[id] = nil end
		end
		paint()
	end
	buttons.SelectAll.Activated:Connect(function()
		confirming = false
		for id in cells do selected[id] = true end
		paint()
	end)
	buttons.Clear.Activated:Connect(function()
		selected = {}
		confirming = false
		paint()
	end)
	buttons.Cancel.Activated:Connect(function()
		if confirming then
			confirming = false
			paint()
		else
			Ui.toggle("Backpack")
		end
	end)
	buttons.Sell.Activated:Connect(function()
		if not confirming then
			confirming = true
			paint()
			return
		end
		local ids = {}
		for id in selected do table.insert(ids, id) end
		Sfx.play("sell")
		Remotes.SellSwords:FireServer(ids)
		selected = {}
		confirming = false
		paint()
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	player:GetAttributeChangedSignal("Swords"):Connect(refresh)
	player:GetAttributeChangedSignal("Equipped"):Connect(refresh)
end

return SellMenu
