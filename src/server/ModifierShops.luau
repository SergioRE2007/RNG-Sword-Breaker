-- Tiendas de modificadores del hub: dos puestos (Rasgos y Grados) con toldo de rayas y cartel.
-- Se abren con la tecla de interacción (ProximityPrompt; la ventana la abre el cliente) y
-- aquí se validan y se hacen las tiradas: los rasgos gastan un Cristal de rasgo y los grados
-- Config.GradeCost gemas. El resultado sustituye al que tuviera la espada.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local ModifierShops = {}

local CRYSTAL = "traitCrystal"
local random = Random.new()
local lastRoll = {} -- [player] = os.clock() de su última tirada

-- Paga la tirada; devuelve false si no le llega.
local function pay(player: Player, kind: string, data): boolean
	if kind == "traits" then
		if data.items[CRYSTAL] < 1 then
			return false
		end
		PlayerData.edit(player, function(edited)
			edited.items[CRYSTAL] -= 1
		end)
		return true
	end
	return PlayerData.trySpendGems(player, Config.GradeCost)
end

local function onRoll(player: Player, kind: string, id: unknown)
	local now = os.clock()
	if now - (lastRoll[player] or 0) < Config.ModifierCooldown then
		return
	end
	local data = PlayerData.read(player)
	local copy = data and PlayerData.findSword(data, id)
	if not copy or not pay(player, kind, data) then
		return
	end
	lastRoll[player] = now

	local info = Modifiers.KINDS[kind]
	local index = Modifiers.roll(kind, random)
	PlayerData.edit(player, function()
		copy[info.field] = index
	end)
	Remotes.ModifierRolled:FireClient(player, kind, id, index)

	local entry = info.list[index]
	local odds = Modifiers.odds(kind, index)
	if odds >= Config.AnnounceOdds then
		local what = if kind == "traits" then "el rasgo" else "el grado"
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha sacado {what} {entry.name} ({Modifiers.formatPercent(Modifiers.percent(kind, index))}, 1 entre {Format.short(odds)})!`, entry.color)
	end
end

-- Puesto: mostrador, cuatro postes, toldo de rayas inclinado, cartel flotante y el aviso de
-- "pulsa E". `position` en el suelo; mira hacia el centro del hub.
local function buildStall(parent: Instance, kind: string, position: Vector3, stripes: { Color3 })
	local model = Instance.new("Model")
	model.Name = "Tienda" .. Modifiers.KINDS[kind].title
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

	-- Cartel con el nombre de la tienda.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 70)
	gui.StudsOffset = Vector3.new(0, 9.5, 0)
	gui.MaxDistance = 200
	gui.Parent = counter
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 40
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = string.upper(Modifiers.KINDS[kind].title)
	label.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(stripes[1]:Lerp(Color3.new(1, 1, 1), 0.3), stripes[2]:Lerp(Color3.new(1, 1, 1), 0.3))
	gradient.Rotation = 90
	gradient.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir"
	prompt.ObjectText = Modifiers.KINDS[kind].title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Shop", kind)
	prompt.Parent = counter

	model.Parent = parent
end

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

	Remotes.RollTrait.OnServerEvent:Connect(function(player, id)
		onRoll(player, "traits", id)
	end)
	Remotes.RollGrade.OnServerEvent:Connect(function(player, id)
		onRoll(player, "grades", id)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return ModifierShops
