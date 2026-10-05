-- Tiendas de modificadores del hub: dos puestos (Rasgos y Grados) con toldo de rayas y cartel.
-- Se abren con la tecla de interacción (ProximityPrompt; la ventana la abre el cliente) y
-- aquí se validan y se hacen las tiradas: los rasgos gastan un Cristal de rasgo y los grados
-- Config.GradeCost Cristales de grado. El resultado sustituye al que tuviera la espada.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

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

-- `count` = cuántas veces tira el rasgo de golpe (1 o 3, un cristal cada una): se queda con el más raro
-- y, si empatan en rareza, con el tipo que va antes en `priority` (el orden que ha puesto el jugador en
-- la tienda; se guarda en sus datos).
local function onRoll(player: Player, kind: string, id: unknown, count: unknown, priority: unknown)
	local now = os.clock()
	if now - (lastRoll[player] or 0) < Config.ModifierCooldown then
		return
	end
	local tries = if kind == "traits" and count == 3 then 3 else 1
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
	for _ = 1, tries do
		local rolled = Modifiers.roll(kind, random)
		table.insert(rolls, rolled)
		if not index or Modifiers.better(kind, rolled, index, order) then
			index = rolled
		end
	end
	PlayerData.edit(player, function()
		copy[info.field] = index
	end)
	-- `rolls` = todas las tiradas, en orden, para que el cliente las enseñe en la ruleta.
	Remotes.ModifierRolled:FireClient(player, kind, id, index, rolls)

	local entry = info.list[index]
	local odds = Modifiers.odds(kind, index)
	if odds >= Config.AnnounceOdds then
		local what = if kind == "traits" then "el rasgo" else "el grado"
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha sacado {what} {entry.name} ({Modifiers.formatPercent(Modifiers.percent(kind, index))}, 1 entre {Format.short(odds)})!`, entry.color)
	end
end

-- Puesto: mostrador, cuatro postes, toldo de rayas inclinado, cartel flotante y el aviso de
-- "pulsa E". `position` en el suelo; mira hacia el centro del hub.
local function buildStall(parent: Instance, kind: string, position: Vector3, stripes: { Color3 }, title: string?)
	local shopTitle = title or Modifiers.KINDS[kind].title
	local model = Instance.new("Model")
	model.Name = "Tienda" .. shopTitle
	local floor = Config.Plot.FloorHeight
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))

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

	local wood = Color3.fromRGB(40, 50, 110)
	local width, depth = 16, 9
	local counter = block("Counter", Vector3.new(width, 3.6, 3), base * CFrame.new(0, floor + 1.8, -depth / 2 + 1.5), Color3.fromRGB(245, 245, 250))
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

	-- Cartel con el nombre de la tienda, por encima del toldo y con borde negro grueso.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(340, 80)
	gui.StudsOffset = Vector3.new(0, 13, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = counter
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 48
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

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir"
	prompt.ObjectText = shopTitle
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Shop", kind)
	prompt.Parent = counter

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
	buildStall(map, "traits", at(112.5), { Color3.fromRGB(255, 90, 140), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 220, 80), Color3.fromRGB(150, 110, 255) })
	buildStall(map, "grades", at(157.5), { Color3.fromRGB(170, 90, 255), Color3.fromRGB(245, 245, 250) })

	Remotes.RollTrait.OnServerEvent:Connect(function(player, id, count, priority)
		onRoll(player, "traits", id, count, priority)
	end)
	Remotes.RollGrade.OnServerEvent:Connect(function(player, id)
		onRoll(player, "grades", id)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return ModifierShops
