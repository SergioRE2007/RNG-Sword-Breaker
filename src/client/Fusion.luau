-- Máquina de fusión del hub (server/Fusion): la ventana `Hud.Fusion`, que se abre sola al acercarse a la máquina, y la
-- animación de la máquina al fusionar (las armas metidas vuelan al núcleo y estallan; el arma que sale la enseña
-- client/RollReveal, que la recibe por GachaRolled con el núcleo como origen).
-- Ventana: arriba los cinco huecos (`Body.Slots.Slot<n>`, pulsar un arma la devuelve a la lista), debajo lo que sale y lo
-- que cuesta (`Body.Info`), el aviso de rasgos y grados (`Body.Warning`), la lista de armas libres
-- (`Body.Stock.Sword<id>`, pulsar una la mete) y los botones `Body.Actions.Fill` y `Body.Actions.Fuse`.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local FusionInfo = require(ReplicatedStorage.Shared.FusionInfo)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)
local RollCinematic = require(script.Parent.RollCinematic)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local WeaponCell = require(script.Parent.WeaponCell)

local Fusion = {}

local player = Players.LocalPlayer
local cfg = Config.Fusion
local SIZE = Vector2.new(760, 640)
local CLOSE_DISTANCE = 30 -- se cierra al alejarse de la máquina
local REOPEN_AFTER = 4.5 -- segundos tras fusionar en los que la ventana no se vuelve a abrir sola (se ve el arma que sale)

local window: Frame
local chosen: { number } = {} -- ids de las copias metidas, por orden de hueco
local confirming = false -- con rasgos o grados metidos, el primer clic en Fusionar pide confirmar
local refresh: () -> ()

-- Copias que se pueden meter: ni equipadas, ni en la Bolsa de oro, ni con el candado (lo mismo que valida el servidor).
local function free(copy): boolean
	return not copy.locked and not Stats.isEquipped(player, copy.id) and not Stats.isDeposited(player, copy.id)
end

local function copiesById(): { [number]: any }
	local map = {}
	for _, copy in Stats.swords(player) do
		map[copy.id] = copy
	end
	return map
end

-- Pieza de la máquina que lleva el cartel (etiqueta ShopStation, Shop = "fusion").
local function station(): BasePart?
	for _, item in CollectionService:GetTagged("ShopStation") do
		if item:GetAttribute("Shop") == "fusion" and item:IsA("BasePart") then
			return item
		end
	end
	return nil
end

-- Las armas metidas aparecen en corro alrededor del núcleo, giran y vuelan a él una tras otra; al llegar la última,
-- un destello. El arma nueva sale del núcleo (client/RollReveal).
local function playMachine(swords)
	local counter = station()
	local core = counter and counter:GetAttribute("Core")
	if typeof(core) ~= "Vector3" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "FusionFx"
	folder.Parent = workspace
	local flights = {}
	for index, entry in swords do
		if type(entry) ~= "table" or not Config.Swords[entry.sword] then
			continue
		end
		local angle = (index - 1) / #swords * math.pi * 2
		local start = core + Vector3.new(math.cos(angle) * 6, 1.5, math.sin(angle) * 6)
		local holder = Instance.new("Model")
		holder.Name = "Sword" .. index
		local ok = pcall(SwordModel.build, entry.sword, holder, CFrame.new(start), 0.8, true, entry.metal)
		if not ok then
			holder:Destroy()
			continue
		end
		for _, part in holder:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CastShadow = false
			end
		end
		holder.Parent = folder
		table.insert(flights, { model = holder, start = start, delay = (index - 1) * 0.12 })
	end
	Sfx.play("charge")
	local began = os.clock()
	local FLIGHT = 0.75
	local last = 0
	for _, flight in flights do
		last = math.max(last, flight.delay + FLIGHT)
	end
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock() - began
		for _, flight in flights do
			if not flight.model.Parent then
				continue
			end
			local t = math.clamp((now - flight.delay) / FLIGHT, 0, 1)
			if t >= 1 then
				flight.model:Destroy()
				continue
			end
			-- Sube un poco, gira cada vez más deprisa y cae en espiral al núcleo.
			local ease = t * t
			local position = flight.start:Lerp(core, ease) + Vector3.new(0, math.sin(t * math.pi) * 2, 0)
			flight.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, now * (4 + 14 * t), math.rad(90)))
		end
		if now >= last then
			connection:Disconnect()
			-- Destello en el núcleo.
			local flash = Instance.new("Part")
			flash.Name = "Flash"
			flash.Shape = Enum.PartType.Ball
			flash.Material = Enum.Material.Neon
			flash.Color = Color3.fromRGB(255, 150, 230)
			flash.Anchored = true
			flash.CanCollide = false
			flash.CanQuery = false
			flash.CastShadow = false
			flash.Size = Vector3.one
			flash.CFrame = CFrame.new(core)
			flash.Parent = folder
			game:GetService("TweenService"):Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 9, Transparency = 1 }):Play()
			Sfx.play("orb")
			task.delay(0.6, function()
				folder:Destroy()
			end)
		end
	end)
end

local function build()
	local body
	window, body = Ui.window("Fusion", Lang.t(nil, "Fusion Machine"), SIZE)

	-- Huecos ---------------------------------------------------------------------------------
	local slots = Instance.new("Frame")
	slots.Name = "Slots"
	slots.Position = UDim2.fromScale(0.02, 0.025)
	slots.Size = UDim2.fromScale(0.96, 0.23)
	slots.BackgroundTransparency = 1
	slots.Parent = body
	local slotRow = Instance.new("UIListLayout")
	slotRow.FillDirection = Enum.FillDirection.Horizontal
	slotRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotRow.VerticalAlignment = Enum.VerticalAlignment.Center
	slotRow.Padding = UDim.new(0.025, 0)
	slotRow.SortOrder = Enum.SortOrder.LayoutOrder
	slotRow.Parent = slots
	local slotFrames = {}
	for index = 1, cfg.Count do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. index
		slot.Size = UDim2.fromScale(0.17, 0.92)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = index
		slot.Parent = slots
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = slot
		slotFrames[index] = slot
	end

	-- Lo que sale y lo que cuesta ------------------------------------------------------------
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Position = UDim2.fromScale(0.02, 0.28)
	info.Size = UDim2.fromScale(0.96, 0.12)
	info.Parent = body
	Ui.round(info, 12)
	Ui.panel(info, Color3.fromRGB(40, 44, 82), Color3.fromRGB(255, 110, 210))
	Ui.stroke(info, Color3.new(0, 0, 0), 3)
	local result = Ui.label(info, 26)
	result.Name = "Result"
	result.Position = UDim2.fromScale(0.04, 0)
	result.Size = UDim2.fromScale(0.64, 1)
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextScaled = true
	result.ZIndex = 3
	local resultSize = Instance.new("UITextSizeConstraint")
	resultSize.MaxTextSize = 26
	resultSize.MinTextSize = 12
	resultSize.Parent = result
	local price = Instance.new("Frame")
	price.Name = "Cost"
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.new(1, -10, 0.5, 0)
	price.Size = UDim2.fromScale(0.28, 0.72)
	price.ZIndex = 3
	price.Parent = info
	Ui.pill(price, Color3.fromRGB(140, 70, 220))
	Ui.stroke(price, Color3.new(0, 0, 0), 3)
	local gemBox = Instance.new("Frame")
	gemBox.Name = "Gem"
	gemBox.AnchorPoint = Vector2.new(0, 0.5)
	gemBox.Position = UDim2.fromScale(0.03, 0.5)
	gemBox.Size = UDim2.fromScale(0.3, 1.25)
	gemBox.BackgroundTransparency = 1
	gemBox.ZIndex = 4
	gemBox.Parent = price
	local gemAspect = Instance.new("UIAspectRatioConstraint")
	gemAspect.AspectRatio = 1
	gemAspect.Parent = gemBox
	Ui.image(gemBox, "gemas").ZIndex = 4
	local cost = Ui.label(price, 24)
	cost.Name = "Amount"
	cost.Position = UDim2.fromScale(0.36, 0)
	cost.Size = UDim2.fromScale(0.6, 1)
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.TextScaled = true
	cost.ZIndex = 4
	local costSize = Instance.new("UITextSizeConstraint")
	costSize.MaxTextSize = 24
	costSize.MinTextSize = 10
	costSize.Parent = cost

	local warning = Ui.label(body, 18)
	warning.Name = "Warning"
	warning.Position = UDim2.fromScale(0.02, 0.405)
	warning.Size = UDim2.fromScale(0.96, 0.045)
	warning.TextColor3 = Color3.fromRGB(255, 170, 90)
	warning.Text = Lang.t(nil, "Their traits, grades and levels will be lost")
	warning.Visible = false

	-- Armas libres ---------------------------------------------------------------------------
	local stock = Instance.new("ScrollingFrame")
	stock.Name = "Stock"
	stock.Position = UDim2.fromScale(0.02, 0.455)
	stock.Size = UDim2.fromScale(0.96, 0.4)
	stock.BackgroundColor3 = Ui.COLORS.dark
	stock.BackgroundTransparency = 0.55
	stock.BorderSizePixel = 0
	stock.ScrollBarThickness = 6
	stock.CanvasSize = UDim2.new()
	stock.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stock.Parent = body
	Ui.round(stock, 10)
	local STOCK_COLUMNS = 7
	local STOCK_GAP = 10
	local STOCK_PAD = 12
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(88, 88)
	grid.CellPadding = UDim2.fromOffset(STOCK_GAP, STOCK_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = stock
	local padding = Instance.new("UIPadding")
	-- Margen para lo que sobresale de las casillas (crecen con el ratón y las raras llevan halo); a la derecha, también
	-- la barra de deslizar.
	padding.PaddingTop = UDim.new(0, STOCK_PAD)
	padding.PaddingLeft = UDim.new(0, STOCK_PAD)
	padding.PaddingRight = UDim.new(0, STOCK_PAD + stock.ScrollBarThickness)
	padding.PaddingBottom = UDim.new(0, STOCK_PAD)
	padding.Parent = stock
	-- Casillas cuadradas que llenan el ancho justo (con un lado fijo sobraba un trozo a la derecha). El lado va en
	-- píxeles de la ventana: AbsoluteSize ya lleva el UIScale de la ventana y CellSize no, así que se deshace.
	local function sizeStock()
		local scale = math.max(window.AbsoluteSize.X / SIZE.X, 0.01)
		local inner = stock.AbsoluteSize.X / scale - STOCK_PAD * 2 - stock.ScrollBarThickness
		local side = math.floor((inner - STOCK_GAP * (STOCK_COLUMNS - 1)) / STOCK_COLUMNS)
		grid.CellSize = UDim2.fromOffset(math.max(side, 40), math.max(side, 40))
	end
	stock:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeStock)
	sizeStock()
	local empty = Ui.label(stock, 20)
	empty.Name = "Empty"
	empty.Size = UDim2.fromOffset(600, 60)
	empty.TextColor3 = Color3.fromRGB(185, 192, 214)
	empty.Text = Lang.t(nil, "No free weapons: unequip or unlock some first")
	empty.Visible = false

	-- Botones --------------------------------------------------------------------------------
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Position = UDim2.fromScale(0.02, 0.875)
	actions.Size = UDim2.fromScale(0.96, 0.11)
	actions.BackgroundTransparency = 1
	actions.Parent = body
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0.03, 0)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = actions
	local fill = Ui.button(actions, Lang.t(nil, "Auto fill"), Ui.COLORS.blue)
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.36, 1)
	fill.TextSize = 22
	fill.LayoutOrder = 1
	local fuse = Ui.button(actions, Lang.t(nil, "Fuse"), Ui.COLORS.purple)
	fuse.Name = "Fuse"
	fuse.Size = UDim2.fromScale(0.5, 1)
	fuse.TextSize = 26
	fuse.LayoutOrder = 2
	Ui.sparkle(fuse)

	local stockCells = {}

	local function paintInfo(selection)
		local count = #selection
		local hasMods = false
		for _, copy in selection do
			if (copy.trait or 0) ~= 0 or (copy.grade or 0) ~= 0 or (copy.level or 0) ~= 0 then
				hasMods = true
			end
		end
		warning.Visible = hasMods
		if count < cfg.Count then
			confirming = false
			local left = cfg.Count - count
			result.Text = if count == 0 then Lang.t(nil, "Put in {n} weapons", { n = left })
				elseif left == 1 then Lang.t(nil, "Put in 1 more weapon")
				else Lang.t(nil, "Put in {n} more weapons", { n = left })
			result.TextColor3 = Color3.new(1, 1, 1)
		else
			local luck = FusionInfo.luck(selection)
			local tier = Rarity.tier(luck)
			result.Text = Lang.t(nil, "Result: 1 in {n} or rarer", { n = Format.short(luck) })
			result.TextColor3 = tier.color:Lerp(Color3.new(1, 1, 1), 0.25)
		end
		local luck = FusionInfo.luck(selection)
		local price = if count == cfg.Count then FusionInfo.cost(luck) else nil
		cost.Text = if price then Format.short(price) else "-"
		local gems = player:GetAttribute("Gems") or 0
		local ready = price ~= nil and gems >= price
		fuse.Interactable = ready
		fuse.BackgroundColor3 = if ready then Ui.COLORS.purple else Ui.COLORS.gray
		cost.TextColor3 = if price and gems < price then Color3.fromRGB(255, 120, 120) else Color3.new(1, 1, 1)
		fuse.Text = Lang.t(nil, if confirming then "Confirm fusion" else "Fuse")
	end

	refresh = function()
		if not window.Visible then
			return
		end
		local copies = copiesById()
		-- Fuera lo que ya no se tiene o ya no está libre.
		for index = #chosen, 1, -1 do
			local copy = copies[chosen[index]]
			if not copy or not free(copy) then
				table.remove(chosen, index)
			end
		end
		local selection = {}
		for _, id in chosen do
			table.insert(selection, copies[id])
		end
		-- Huecos.
		for index, slot in slotFrames do
			slot:ClearAllChildren()
			local square = Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.Parent = slot
			local copy = selection[index]
			if copy then
				local cell = WeaponCell.create(slot, copy)
				cell.Name = "Sword"
				cell.Size = UDim2.fromScale(1, 1)
				cell.Activated:Connect(function()
					local position = table.find(chosen, copy.id)
					if position then
						table.remove(chosen, position)
						confirming = false
						Sfx.play("click", 0.5)
						refresh()
					end
				end)
			else
				local cell = Ui.cell(slot, Ui.COLORS.gray)
				cell.Name = "Empty"
				cell.Size = UDim2.fromScale(1, 1)
				cell.Active = false
				cell.Interactable = false
				cell.BackgroundTransparency = 0.45
				local plus = Ui.label(cell, 46)
				plus.Size = UDim2.fromScale(1, 1)
				plus.Text = "+"
				plus.TextColor3 = Color3.fromRGB(200, 205, 225)
				plus.TextTransparency = 0.3
				plus.ZIndex = 3
			end
		end
		-- Lista: las libres que no están metidas, de más rara a menos.
		for _, cell in stockCells do
			cell:Destroy()
		end
		stockCells = {}
		local list = {}
		for _, copy in copies do
			if free(copy) and not table.find(chosen, copy.id) then
				table.insert(list, copy)
			end
		end
		table.sort(list, function(a, b)
			local left, right = Stats.rarity(a), Stats.rarity(b)
			if left ~= right then
				return left > right
			end
			return a.id < b.id
		end)
		empty.Visible = #list == 0 and #chosen == 0
		for position, copy in list do
			local cell = WeaponCell.create(stock, copy)
			cell.Name = "Sword" .. copy.id
			cell.LayoutOrder = position
			cell.Activated:Connect(function()
				if #chosen >= cfg.Count or table.find(chosen, copy.id) then
					return
				end
				table.insert(chosen, copy.id)
				confirming = false
				Sfx.play("click", 0.5)
				refresh()
			end)
			table.insert(stockCells, cell)
		end
		paintInfo(selection)
	end

	-- Rellenar: los huecos libres con las armas libres más raras que no llevan rasgo ni grado (las que no se ha
	-- trabajado el jugador); si no hay bastantes, con las que sí.
	fill.Activated:Connect(function()
		local copies = copiesById()
		local list = {}
		for _, copy in copies do
			if free(copy) and not table.find(chosen, copy.id) then
				table.insert(list, copy)
			end
		end
		table.sort(list, function(a, b)
			local plainA = (a.trait or 0) == 0 and (a.grade or 0) == 0
			local plainB = (b.trait or 0) == 0 and (b.grade or 0) == 0
			if plainA ~= plainB then
				return plainA
			end
			local left, right = Stats.rarity(a), Stats.rarity(b)
			if left ~= right then
				return left > right
			end
			return a.id < b.id
		end)
		for _, copy in list do
			if #chosen >= cfg.Count then
				break
			end
			table.insert(chosen, copy.id)
		end
		confirming = false
		Sfx.play("click", 0.5)
		refresh()
	end)

	fuse.Activated:Connect(function()
		if #chosen ~= cfg.Count then
			return
		end
		if warning.Visible and not confirming then
			confirming = true
			refresh()
			return
		end
		Remotes.FuseSwords:FireServer(table.clone(chosen))
		confirming = false
	end)

	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible then
			chosen = {}
			confirming = false
		end
		refresh()
	end)
	player:GetAttributeChangedSignal("Swords"):Connect(refresh)
	player:GetAttributeChangedSignal("Loadout"):Connect(refresh)
	player:GetAttributeChangedSignal("Gems"):Connect(refresh)
end

function Fusion.start()
	build()

	-- Abrir junto a la máquina y cerrar al alejarse (como las tiendas de Rasgos y Grados).
	local inside = false
	local holdUntil = 0 -- tras fusionar, no se vuelve a abrir sola hasta entonces
	Remotes.FusionDone.OnClientEvent:Connect(function(data)
		chosen = {}
		Ui.close(window)
		holdUntil = os.clock() + REOPEN_AFTER
		inside = false
		if type(data) == "table" and type(data.swords) == "table" then
			playMachine(data.swords)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local counter = station()
			if not root or not counter then
				continue
			end
			local distance = (root.Position - counter.Position).Magnitude
			if distance < cfg.OpenDistance then
				if not inside and os.clock() >= holdUntil and not RollCinematic.isActive() then
					inside = true
					if not Ui.isOpen(window) then
						Ui.toggle("Fusion") -- cierra las demás ventanas
					end
				end
			elseif distance > cfg.OpenDistance + 4 then
				inside = false
			end
			if distance > CLOSE_DISTANCE and Ui.isOpen(window) then
				Ui.close(window)
			end
		end
	end)
end

return Fusion
