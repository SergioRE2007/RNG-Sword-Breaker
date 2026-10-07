-- Tiendas de modificadores del hub: dos puestos (Rasgos y Grados) con toldo de rayas y cartel.
-- Se abren con la tecla de interacción (ProximityPrompt; la ventana la abre el cliente) y
-- aquí se validan y se hacen las tiradas: los rasgos gastan un Cristal de rasgo y los grados
-- Config.GradeCost Cristales de grado. El resultado sustituye al que tuviera la espada.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local StallSkin = require(script.Parent.StallSkin)
local Stations = require(script.Parent.Stations)

local ModifierShops = {}

local random = Random.new()
local lastRoll = {} -- [player] = os.clock() de su última tirada

-- Paga la tirada; devuelve false si no le llega.
local function pay(player: Player, kind: string, data, tries: number): boolean
	local info = Modifiers.KINDS[kind]
	local cost = info.cost * tries
	if data.items[info.item] < cost then
		return false
	end
	PlayerData.edit(player, function(edited)
		edited.items[info.item] -= cost
	end)
	return true
end

-- `count` = cuántas veces tira el rasgo de golpe (1, 3 o las del pase de juego, un cristal cada una): se queda con el más raro
-- y, si empatan en rareza, con el tipo que va antes en `priority` (el orden que ha puesto el jugador en
-- la tienda; se guarda en sus datos).
-- Forja, tirada a mano: el grado nuevo ya está puesto, pero el jugador puede descartarlo y volver al
-- que tenía (RevertGrade). Solo vale para la última tirada y mientras la espada siga igual.
local pendingGrade = {} -- [player] = { id, previous (0 = sin grado), rolled }

local function onRoll(player: Player, kind: string, id: unknown, count: unknown, priority: unknown, manual: unknown)
	local now = os.clock()
	-- Pase de juego: los grados se tiran más rápido (con un 20 % de margen para el retraso de la red).
	local speed = if kind == "grades" then Stats.perk(player, "gradeSpeed") or 1 else 1
	local cooldown = Config.ModifierCooldown / speed * (if speed > 1 then 0.8 else 1)
	if now - (lastRoll[player] or 0) < cooldown then
		return
	end
	-- De golpe se pueden tirar 1 o 3 rasgos, o los que dé el pase de juego (traitCount).
	local tries = 1
	if kind == "traits" and (count == 3 or (count ~= 1 and count == Stats.perk(player, "traitCount"))) then
		tries = count :: number
	end
	local data = PlayerData.read(player)
	local copy = data and PlayerData.findSword(data, id)
	if not copy or not pay(player, kind, data, tries) then
		return
	end
	lastRoll[player] = now
	if kind == "traits" then
		-- Se pide aquí y no arriba: Missions usa ModifierShops para construir su puesto.
		require(script.Parent.Missions).add(player, "traitRolls", tries)
	end

	local order = Modifiers.priority(data.traitPriority)
	if kind == "traits" and type(priority) == "string" then
		order = Modifiers.priority(priority)
		local text = table.concat(order, ",")
		if text ~= data.traitPriority then
			PlayerData.edit(player, function(edited)
				edited.traitPriority = text
			end)
		end
	end

	local info = Modifiers.KINDS[kind]
	local rolls = {}
	local index = nil
	-- Poción de suerte de rasgo (en la Mesa) o de grado (en la Forja): sube el peso de lo raro, no el de todo por igual.
	local luck = Stats.potion(player, if kind == "traits" then "traitLuck" else "rankLuck")
	for _ = 1, tries do
		local rolled = Modifiers.rollWithPity(kind, random, luck, data.pity[kind], order)
		table.insert(rolls, rolled)
		if not index or Modifiers.better(kind, rolled, index, order) then
			index = rolled
		end
	end
	local previous = copy[info.field] or 0
	PlayerData.edit(player, function()
		copy[info.field] = index
	end)
	if kind == "grades" then
		pendingGrade[player] = if manual == true then { id = id, previous = previous, rolled = index } else nil
	end
	-- `rolls` = todas las tiradas, en orden, para que el cliente las enseñe en la ruleta.
	Remotes.ModifierRolled:FireClient(player, kind, id, index, rolls, previous)

	local entry = info.list[index]
	-- El aviso cuenta la probabilidad real, con la suerte de la poción.
	local odds = Modifiers.odds(kind, index, luck)
	if odds >= Config.AnnounceOdds then
		local what = if kind == "traits" then "el rasgo" else "el grado"
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha sacado {what} {entry.name} ({Modifiers.formatPercent(Modifiers.percent(kind, index, luck))}, 1 entre {Format.short(odds)})!`, entry.color)
	end
end

-- Modo admin de pruebas (Config.Test.Admin): solo existe al darle a Jugar en Studio, nunca en el juego publicado.
local function isAdmin(): boolean
	return RunService:IsStudio() and Config.Test.Admin == true
end

-- Admin: pone a mano el rasgo o grado `index` (0 = quitarlo) en esa copia, sin tirar ni gastar nada.
local function onAdminSet(player: Player, kind: unknown, id: unknown, index: unknown)
	local info = if kind == "traits" or kind == "grades" then Modifiers.KINDS[kind] else nil
	if not isAdmin() or not info or type(index) ~= "number" or (index ~= 0 and not info.list[index]) then
		return
	end
	local data = PlayerData.read(player)
	local copy = data and PlayerData.findSword(data, id)
	if not copy then
		return
	end
	PlayerData.edit(player, function()
		copy[info.field] = if index == 0 then nil else index
	end)
end

-- Cartel con el nombre de la tienda y el aviso "pulsa E" (el cliente además abre la ventana al
-- acercarse). Van en `counter`, una pieza por delante del puesto.
local function addSignAndPrompt(counter: Part, kind: string, shopTitle: string, stripes: { Color3 }, signHeight: number, withPrompt: boolean)
	-- Cartel con el nombre de la tienda, por encima del toldo y con borde negro grueso.
	local gui = Instance.new("BillboardGui")
	gui:SetAttribute("SignHeight", signHeight)
	gui.Size = UDim2.fromOffset(340, 80)
	gui:SetAttribute("TextMax", 40) -- el cliente (ModifierShops) encoge la fuente con la distancia entre estos dos topes
	gui:SetAttribute("TextMin", 18)
	gui.StudsOffset = Vector3.new(0, signHeight, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.Parent = counter
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 40
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = string.upper(shopTitle)
	label.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 3.5
	outline.Parent = label
	local keys = {}
	for index, color in stripes do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / math.max(#stripes - 1, 1), color))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = label
	-- El cliente (ModifierShops) lo hace girar, latir y flotar.
	CollectionService:AddTag(gui, "ShopSign")

	if not withPrompt then
		-- Las estaciones (Rasgos, Grados) se abren solas al acercarse y se cierran al alejarse: sin botón.
		-- El cliente busca esta pieza (etiqueta ShopStation) para saber dónde está la estación.
		counter:SetAttribute("Shop", kind)
		CollectionService:AddTag(counter, "ShopStation")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir"
	prompt.ObjectText = shopTitle
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Shop", kind)
	prompt.Parent = counter
	CollectionService:AddTag(prompt, "ShopStation")
end

-- Puesto: mostrador, cuatro postes, toldo de rayas inclinado, cartel flotante y el aviso de
-- "pulsa E". `position` en el suelo; mira hacia el centro del hub. Con `skinned` usa el
-- aspecto de `StallSkin` (toldo azul y vendedor) en vez de las piezas sueltas.
local function buildStall(parent: Instance, kind: string, position: Vector3, stripes: { Color3 }, title: string?, skinned: boolean?)
	local shopTitle = title or Modifiers.KINDS[kind].title
	local model = Instance.new("Model")
	model.Name = "Tienda" .. shopTitle
	local floor = Config.Plot.FloorHeight
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	local skin = if skinned then StallSkin.build(stripes[1], stripes[2] or stripes[1]) else nil

	local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Anchored = true
		item.Size = size
		item.CFrame = cframe
		item.Color = color
		item.Material = material or Enum.Material.SmoothPlastic
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		item.Parent = model
		return item
	end

	local counter: Part
	local signHeight = 13
	if skin then
		-- El modelo mira hacia -Z; se centra sobre `position` y se apoya en el suelo del hub.
		local pivot = skin:GetPivot()
		local boxCFrame, boxSize = skin:GetBoundingBox()
		local centre = pivot:ToObjectSpace(boxCFrame).Position
		skin:PivotTo(base * CFrame.new(-centre.X, floor + boxSize.Y / 2 - centre.Y, -centre.Z))
		for _, item in skin:GetChildren() do
			item.Parent = model
		end
		signHeight = boxSize.Y - 1
		-- Pieza invisible por delante del mostrador que lleva el cartel y el aviso.
		counter = block("Counter", Vector3.new(6, 1, 2), base * CFrame.new(0, floor + 3, -boxSize.Z / 2 + 3), Color3.new(1, 1, 1))
		counter.Transparency = 1
		counter.CanCollide = false
		counter.CanQuery = false
		counter.CastShadow = false
	else
		local wood = Color3.fromRGB(40, 50, 110)
		local width, depth = 16, 9
		counter = block("Counter", Vector3.new(width, 3.6, 3), base * CFrame.new(0, floor + 1.8, -depth / 2 + 1.5), Color3.fromRGB(245, 245, 250))
		block("CounterTop", Vector3.new(width + 0.6, 0.5, 3.6), base * CFrame.new(0, floor + 3.85, -depth / 2 + 1.5), wood)
		for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
			for _, z in { -depth / 2 + 0.6, depth / 2 - 0.6 } do
				local height = if z < 0 then 9 else 11
				block("Post", Vector3.new(0.9, height, 0.9), base * CFrame.new(x, floor + height / 2, z), wood)
			end
		end
		-- Toldo: tiras alternas, más alto por detrás.
		local slope = math.atan2(2, depth)
		local count = 8
		for index = 1, count do
			local x = -width / 2 + (index - 0.5) * width / count
			local strip = block("Awning", Vector3.new(width / count + 0.05, 0.4, depth / math.cos(slope) + 1.6), base * CFrame.new(x, floor + 10.2, 0) * CFrame.Angles(-slope, 0, 0), stripes[(index - 1) % #stripes + 1])
			strip.CastShadow = true
		end
	end

	addSignAndPrompt(counter, kind, shopTitle, stripes, signHeight, true)

	model.Parent = parent
end

-- Estación hecha con piezas (Forja, Mesa de encantamiento): `build` es Stations.forge o enchanter.
local function buildStation(parent: Instance, kind: string, position: Vector3, stripes: { Color3 }, build: (Vector3) -> (Model, Part, number))
	local model, counter, signHeight = build(position)
	addSignAndPrompt(counter, kind, Modifiers.KINDS[kind].title, stripes, signHeight, false)
	model.Parent = parent
end

-- Para que otras tiendas del hub (Misiones) usen el mismo puesto.
ModifierShops.buildStall = buildStall

function ModifierShops.start()
	local map = workspace:WaitForChild("Map")
	local radius = Config.Plot.HubRadius - 18
	-- Entre dos caminos, uno junto al otro.
	local function at(degrees: number): Vector3
		local angle = math.rad(degrees)
		return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	buildStation(map, "traits", at(112.5), { Color3.fromRGB(255, 90, 140), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 220, 80), Color3.fromRGB(150, 110, 255) }, Stations.enchanter)
	buildStation(map, "grades", at(157.5), { Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 80, 40), Color3.fromRGB(255, 220, 90) }, Stations.forge)

	Remotes.RollTrait.OnServerEvent:Connect(function(player, id, count, priority)
		onRoll(player, "traits", id, count, priority)
	end)
	Remotes.RollGrade.OnServerEvent:Connect(function(player, id, manual)
		onRoll(player, "grades", id, nil, nil, manual)
	end)
	Remotes.RevertGrade.OnServerEvent:Connect(function(player, id)
		local pending = pendingGrade[player]
		pendingGrade[player] = nil
		local data = PlayerData.read(player)
		local copy = data and PlayerData.findSword(data, id)
		if not pending or pending.id ~= id or not copy or copy.grade ~= pending.rolled then
			return
		end
		PlayerData.edit(player, function()
			copy.grade = if pending.previous == 0 then nil else pending.previous
		end)
	end)
	Remotes.AdminSetModifier.OnServerEvent:Connect(onAdminSet)
	-- El cliente enseña el botón "Admin" de las tiendas si lleva este atributo.
	local function onPlayer(player: Player)
		player:SetAttribute("Admin", isAdmin())
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		pendingGrade[player] = nil
	end)
end

return ModifierShops
