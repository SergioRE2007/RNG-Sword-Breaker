-- Mejor tirada de la historia: un pedestal en el hub con el arma más rara que ha sacado nadie (su "1 entre N" es
-- la rareza total: arma por metal por tamaño), el avatar de quien la sacó y un cartel encima. El récord es de todos
-- los servidores: va en un DataStore y se vuelve a leer cada minuto; si no hay DataStore (lugar sin publicar) o se
-- juega en Studio, vale solo para este servidor y no se guarda. Las tiradas llegan de Gacha (BestRoll.submit).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local BestRoll = {}

local ANGLE = 22.5 -- grados alrededor del hub: un hueco libre entre dos caminos
local REFRESH = 60 -- segundos entre lecturas del récord global
local KEY = "best"
local TOP = 3.1 -- altura de la tarima sobre el suelo del hub
local SIGN_HEIGHT = 12 -- altura del cartel sobre la tarima con un arma corriente

local LACQUER = Color3.fromRGB(176, 38, 34)
local GOLD = Color3.fromRGB(226, 182, 80)
local STONE = Color3.fromRGB(122, 126, 136)
local DARK = Color3.fromRGB(30, 28, 36)
local WHITE = Color3.new(1, 1, 1)

local best = nil -- { userId, name, sword, metal, size, rarity } o nil si aún no hay ninguna
local base: CFrame = CFrame.identity -- centro del pedestal a ras de suelo, mirando al centro del hub
local show: Folder? = nil -- lo que cambia con el récord: arma y avatar
local sign: Part? = nil -- pieza invisible que lleva el cartel
local lines = {} -- textos del cartel: odds, weapon, player
local token = 0 -- cada vez que se repinta: descarta los avatares que llegan tarde

-- Datos ---------------------------------------------------------------------------------------

local function store()
	if game.PlaceId == 0 or RunService:IsStudio() then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName .. "_BestRoll")
	end)
	return if ok then result else nil
end

-- Lo leído del DataStore, revisado: nil si no es un récord válido para las listas de ahora.
local function sanitize(value)
	if type(value) ~= "table" or type(value.userId) ~= "number" or type(value.sword) ~= "number" then
		return nil
	end
	local sword = Config.Swords[value.sword]
	if not sword or not sword.rarity then
		return nil
	end
	local metal = if type(value.metal) == "number" and Config.Metals[value.metal] then value.metal else 0
	local size = if type(value.size) == "number" and Config.Sizes[value.size] then value.size else 0
	return {
		userId = value.userId,
		name = if type(value.name) == "string" then string.sub(value.name, 1, 40) else "Jugador",
		sword = value.sword,
		metal = metal,
		size = size,
		-- La rareza se vuelve a contar: si cambia el equilibrio en Config, el cartel dice la de ahora.
		rarity = Permanent.rarity(value.sword, metal, size),
	}
end

-- Pedestal ------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		item.Shape = shape
	end
	item.Parent = parent
	return item
end

-- Disco tumbado de `height` de alto con el centro a `y` del suelo.
local function disc(parent: Instance, name: string, diameter: number, height: number, y: number, color: Color3, material: Enum.Material?): Part
	return part(parent, name, Vector3.new(height, diameter, diameter), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
end

local function line(parent: Instance, top: number, height: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0, top)
	text.Size = UDim2.fromScale(1, height)
	text.Font = Enum.Font.FredokaOne
	text.Text = ""
	text.TextScaled = true
	text.TextColor3 = color
	text.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = text
	return text
end

local function build(map: Instance)
	local radius = Config.Plot.HubRadius - 18
	local angle = math.rad(ANGLE)
	local floor = Config.Plot.FloorHeight
	local position = Vector3.new(math.cos(angle) * radius, floor, math.sin(angle) * radius)
	base = CFrame.lookAt(position, Vector3.new(0, floor, 0))

	local model = Instance.new("Model")
	model.Name = "MejorTirada"

	-- Dos peldaños de piedra y, encima, un tambor de laca roja con aros dorados y la tarima oscura.
	disc(model, "Step", 17, 0.8, 0.4, STONE, Enum.Material.Slate)
	disc(model, "StepTop", 14, 0.6, 1.1, STONE:Lerp(WHITE, 0.2), Enum.Material.Slate)
	disc(model, "Drum", 11, 1.4, 2.1, LACQUER)
	disc(model, "RingLow", 11.5, 0.3, 1.55, GOLD, Enum.Material.Metal)
	disc(model, "RingHigh", 11.5, 0.3, 2.65, GOLD, Enum.Material.Metal)
	disc(model, "Top", 10.4, 0.3, TOP - 0.15, DARK)
	disc(model, "TopInlay", 7, 0.32, TOP - 0.15, GOLD:Lerp(DARK, 0.35), Enum.Material.Metal)

	-- Cartel encima: se ve desde todo el hub y gira hacia quien mira.
	local board = part(model, "Sign", Vector3.one, base * CFrame.new(0, TOP + SIGN_HEIGHT, 0), WHITE)
	board.Transparency = 1
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	sign = board
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(30, 9)
	gui.LightInfluence = 0
	gui.MaxDistance = 320
	gui.Parent = board
	local title = line(gui, 0, 0.36, WHITE)
	title.Text = "MEJOR TIRADA"
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(WHITE, Color3.fromRGB(196, 170, 255))
	shine.Parent = title
	lines.odds = line(gui, 0.36, 0.22, Color3.fromRGB(255, 226, 70))
	lines.weapon = line(gui, 0.58, 0.22, WHITE)
	lines.player = line(gui, 0.8, 0.2, WHITE)

	local folder = Instance.new("Folder")
	folder.Name = "Show"
	folder.Parent = model
	show = folder

	model.Parent = map
end

-- El arma de verdad, a su tamaño de la mano (con lo que le agranda su tamaño), de pie con la punta hacia arriba y
-- a un lado del avatar. No se escala el modelo: client/WeaponAura no pone aura a las armas escaladas.
local function placeWeapon(parent: Instance, record): number
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local scale = if record.size > 0 then Config.Sizes[record.size].scale else 1
	local handle, blade = SwordModel.build(record.sword, model, CFrame.identity, scale, true, if record.metal > 0 then record.metal else nil)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
		end
	end
	local toTip = blade.Position - handle.Position
	local box, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	local long = math.max(size.X, size.Y, size.Z)
	-- Giro que pone la dirección empuñadura → hoja mirando arriba.
	local upright = CFrame.identity
	if toTip.Magnitude > 0.05 then
		local direction = toTip.Unit
		if math.abs(direction.Y) > 0.98 then
			upright = if direction.Y < 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.identity
		else
			upright = CFrame.Angles(math.rad(90), 0, 0) * CFrame.lookAt(Vector3.zero, direction):Inverse()
		end
	end
	model:PivotTo(base * CFrame.new(2.9, TOP + 1 + long / 2, 0) * CFrame.Angles(0, 0, math.rad(-10)) * upright)
	model.Parent = parent
	return long
end

-- El avatar de quien la sacó, quieto sobre la tarima. Tarda en llegar (y puede fallar): va aparte.
local function placeAvatar(parent: Instance, record, mine: number)
	local ok, rig = pcall(Players.CreateHumanoidModelFromUserIdAsync, Players, record.userId)
	if not ok or typeof(rig) ~= "Instance" then
		return
	end
	if mine ~= token then
		rig:Destroy()
		return
	end
	rig.Name = "Roller"
	-- Solo se ancla la raíz: el resto del cuerpo lo sujetan sus articulaciones (anclando cada pieza donde venía,
	-- el pecho se quedaba descolocado).
	for _, item in rig:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = item.Name == "HumanoidRootPart"
			item.CanTouch = false
			item.CanQuery = false
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	local lift = 3
	if humanoid and root and root:IsA("BasePart") then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		lift = humanoid.HipHeight + root.Size.Y / 2
	end
	rig:PivotTo(base * CFrame.new(-1.8, TOP + lift, 0))
	rig.Parent = parent
end

local function render()
	local folder = show
	if not folder then
		return
	end
	token += 1
	local mine = token
	folder:ClearAllChildren()
	local record = best
	if not record then
		lines.odds.Text = "Nadie todavía"
		lines.weapon.Text = "¡Rompe objetos y sé el primero!"
		lines.weapon.TextColor3 = WHITE
		lines.player.Text = ""
		return
	end
	local sword = Config.Swords[record.sword]
	lines.odds.Text = `1 entre {Format.short(record.rarity)}`
	lines.weapon.Text = Permanent.name(record.sword, record.metal, record.size)
	lines.weapon.TextColor3 = if record.metal > 0 then Config.Metals[record.metal].color else sword.color
	lines.player.Text = "@" .. record.name
	-- El cartel sube con las armas muy largas (una Titánica mide más del doble) para no taparlas.
	local long = placeWeapon(folder, record)
	if sign then
		sign.CFrame = base * CFrame.new(0, TOP + math.max(SIGN_HEIGHT, long + 6.5), 0)
	end
	task.spawn(placeAvatar, folder, record, mine)
end

-- Récord -------------------------------------------------------------------------------------

-- Se queda con `record` si mejora al de ahora. Devuelve si lo ha cambiado.
local function adopt(record): boolean
	if not record or record.rarity ~= record.rarity or record.rarity == math.huge then
		return false
	end
	if best and best.rarity >= record.rarity then
		return false
	end
	best = record
	render()
	return true
end

local function load()
	local data = store()
	if not data then
		return
	end
	local ok, value = pcall(data.GetAsync, data, KEY)
	if ok then
		adopt(sanitize(value))
	end
end

local function save(record)
	local data = store()
	if not data then
		return
	end
	pcall(data.UpdateAsync, data, KEY, function(old)
		local current = sanitize(old)
		if current and current.rarity >= record.rarity then
			return nil
		end
		return record
	end)
end

-- Un arma que un jugador acaba de sacar y se ha quedado (desde Gacha): si es la más rara de la historia, sube al
-- pedestal y se avisa a todos.
function BestRoll.submit(player: Player, sword: number, metal: number?, size: number?)
	local record = {
		userId = player.UserId,
		name = player.DisplayName,
		sword = sword,
		metal = metal or 0,
		size = size or 0,
		rarity = Permanent.rarity(sword, metal, size),
	}
	if not adopt(record) then
		return
	end
	task.spawn(save, record)
	-- Al principio cualquier arma bate el récord: solo es noticia si de verdad es rara.
	if record.rarity >= Config.Gacha.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} tiene la MEJOR TIRADA de la historia! {Permanent.name(sword, metal, size)} · 1 entre {Format.short(record.rarity)}`, Color3.fromRGB(255, 226, 70))
	end
end

function BestRoll.start()
	build(workspace:WaitForChild("Map"))
	render()
	task.spawn(function()
		while true do
			load()
			task.wait(REFRESH)
		end
	end)
end

return BestRoll
