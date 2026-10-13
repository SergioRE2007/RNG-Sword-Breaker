-- Bolsa de oro (Config.GoldBag, cuentas en shared/BagInfo): detrás de cada parcela hay un saco al que pegan solas
-- las armas que su dueño deposita. Cada golpe saca las monedas que tocan a su daño (BagInfo.coins): aquí se cobran
-- juntas cada segundo y el cliente enseña los golpes uno a uno. Vacía una bolsa, sigue la siguiente. Al volver al
-- juego se cobra de golpe el tiempo que las armas han estado pegando sin su dueño.
-- El estado (data.bag) solo vive aquí y en PlayerData; el cliente lo lee de los atributos del jugador:
-- "Bag" (ids depositados, lo publica PlayerData), "BagStage" (bolsa por la que va), "BagTaken" (monedas sacadas de
-- esa bolsa en el momento "BagAt", hora de GetServerTimeNow) y "BagRate" (monedas por segundo que salen).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BagInfo = require(ReplicatedStorage.Shared.BagInfo)
local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Tell = require(script.Parent.Tell)

local GoldBag = {}

local TICK = 1 -- segundos entre cobros
local DISTANCE = 27 -- del muro de atrás de la parcela al centro del saco (SACK_DISTANCE en crear_mapa_japones.py)
local SACK_SCALE = 1.1 -- tamaño en el juego del saco de Blender
local DAIS = 0.95 -- altura de su pedestal (GoldSackBase), sin escalar: encima va el saco
local RED = Color3.fromRGB(240, 65, 75)
local GRASS = 0.3 -- lo que levanta el césped (Scenery) del suelo de fuera de las parcelas: encima va el camino
local PATH_WIDTH = 9 -- ancho del camino del paso del muro al pedestal
local PEDESTAL = 12.6 -- radio del pedestal (GoldSackBase), sin escalar
local STEP = Color3.fromRGB(196, 200, 218) -- las losas del camino, como la piedra clara del pedestal
local STEP_DARK = Color3.fromRGB(124, 128, 150) -- su lecho y sus bordillos

local SACK = Color3.fromRGB(176, 132, 84)
local SACK_DARK = Color3.fromRGB(128, 92, 58)
local ROPE = Color3.fromRGB(96, 62, 40)
local GOLD = Color3.fromRGB(255, 200, 60)
local STONE = Color3.fromRGB(150, 146, 168)

local sent = {} -- [player] = { stage, rate } lo último publicado
local carry = {} -- [player] = pico de moneda que aún no se ha pagado
local models = {} -- [índice de parcela] = modelo del saco

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = material or Enum.Material.SmoothPlastic
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = parent
	return piece
end

local function cylinder(piece: Part): Part
	piece.Shape = Enum.PartType.Cylinder
	return piece
end

-- Pieza redondeada que puede ser más ancha que alta (una Ball solo puede ser una esfera).
local function blob(piece: Part): Part
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = piece
	return piece
end

-- Dónde va el saco de una parcela: detrás (del lado contrario al hub), mirando hacia ella.
function GoldBag.cframe(plot): CFrame
	return plot.cframe * CFrame.new(0, 0, Config.Plot.Size / 2 + DISTANCE)
end

-- El saco hecho con piezas, para cuando no están importadas las mallas de Blender: plataforma de piedra, saco atado
-- y monedas. `origin` está a la altura del suelo de la parcela.
local function fallback(model: Model, origin: CFrame)
	local floor = Config.Plot.FloorHeight
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- un cilindro va tumbado a lo largo de X: así queda de pie
	cylinder(part(model, "Base", Vector3.new(floor + 0.6, 26, 26), origin * CFrame.new(0, 0.3 - floor / 2, 0) * upright, STONE, Enum.Material.Slate)).CastShadow = false
	blob(part(model, "Sack", Vector3.new(11.5, 11, 11.5), origin * CFrame.new(0, 6, 0), SACK, Enum.Material.Fabric))
	blob(part(model, "Belly", Vector3.new(13, 6, 13), origin * CFrame.new(0, 3.5, 0), SACK, Enum.Material.Fabric)).CanCollide = false
	cylinder(part(model, "Neck", Vector3.new(2.6, 4.4, 4.4), origin * CFrame.new(0, 11.6, 0) * upright, SACK_DARK, Enum.Material.Fabric))
	cylinder(part(model, "Rope", Vector3.new(0.9, 5.2, 5.2), origin * CFrame.new(0, 11.1, 0) * upright, ROPE, Enum.Material.Wood))
	blob(part(model, "Top", Vector3.new(6, 2.8, 6), origin * CFrame.new(0, 13.4, 0), SACK, Enum.Material.Fabric)).CanCollide = false
	-- Moneda grande en la cara que mira a la parcela, y unas cuantas tiradas por la plataforma.
	cylinder(part(model, "Coin", Vector3.new(0.7, 5.2, 5.2), origin * CFrame.new(0, 6.2, -5.6) * CFrame.Angles(0, math.pi / 2, 0), GOLD, Enum.Material.Metal)).CanCollide = false
	local rng = Random.new(71)
	for coin = 1, 9 do
		local angle = coin / 9 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local reach = rng:NextNumber(8, 11)
		local at = origin * CFrame.new(math.cos(angle) * reach, 0.6 + 0.18, math.sin(angle) * reach)
		cylinder(part(model, "Coins", Vector3.new(0.35, 1.7, 1.7), at * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0) * upright, GOLD, Enum.Material.Metal)).CanCollide = false
	end
end

-- El camino hecho con piezas: lecho oscuro, losas claras al tresbolillo y un bordillo a cada lado. `ground` es el
-- césped bajo el saco; el camino va de su pedestal al muro de la parcela (hacia -Z).
local function pathFallback(model: Model, ground: CFrame)
	local near, far = PEDESTAL * SACK_SCALE - 0.6, DISTANCE + 0.5
	local length = far - near
	local middle = -(near + far) / 2
	local function flat(name: string, size: Vector3, cframe: CFrame, color: Color3)
		local piece = part(model, name, size, cframe, color)
		piece.CastShadow = false
		piece.CanCollide = false -- tan bajo que no hace falta pisarlo: así nadie tropieza
		return piece
	end
	flat("PathBed", Vector3.new(PATH_WIDTH, 0.16, length), ground * CFrame.new(0, 0.08, middle), STEP_DARK)
	for _, side in { -1, 1 } do
		flat("PathCurb", Vector3.new(0.8, 0.5, length), ground * CFrame.new(side * (PATH_WIDTH / 2 + 0.2), 0.25, middle), STEP)
	end
	local rng = Random.new(31)
	local rows = math.floor(length / 3.2)
	for row = 1, rows do
		local z = -(near + (row - 0.5) * length / rows)
		local split = rng:NextNumber(-1.1, 1.1) -- por dónde se parte la fila en dos losas
		for _, side in { -1, 1 } do
			local from, to = if side < 0 then -PATH_WIDTH / 2 + 0.5 else split + 0.2, if side < 0 then split - 0.2 else PATH_WIDTH / 2 - 0.5
			flat("PathSlab", Vector3.new(to - from, 0.3, length / rows - 0.4), ground * CFrame.new((from + to) / 2, 0.15, z) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), STEP)
		end
	end
end

-- El saco de una parcela y su pedestal: las piezas de Blender GoldSack y GoldSackBase (gold_sack() de
-- tools/blender/crear_mapa_japones.py, en shared/MapMeshesPatch) o, sin ellas, el de piezas. En los dos casos el
-- modelo lleva una pieza invisible "Body" en el centro del saco (de ella cuelga el cartel del cliente y a ella apuntan
-- las armas depositadas) y el atributo "Radius" con lo ancho que es.
local function build(plot, parent: Instance)
	local origin = GoldBag.cframe(plot)
	local ground = origin * CFrame.new(0, -Config.Plot.FloorHeight, 0) -- fuera de la parcela el suelo queda más bajo
	local model = Instance.new("Model")
	model.Name = "Bolsa" .. plot.index
	model:SetAttribute("Plot", plot.index)
	model:SetAttribute("Owner", 0)

	local center, radius = origin * CFrame.new(0, 6, 0), 6.2
	if PropModel.place(model, "GoldSackBase", ground, SACK_SCALE) and PropModel.place(model, "GoldSack", ground * CFrame.new(0, DAIS * SACK_SCALE, 0), SACK_SCALE) then
		center, radius = ground * CFrame.new(0, (DAIS + 6) * SACK_SCALE, 0), 6.5 * SACK_SCALE
	else
		fallback(model, origin)
	end
	-- Camino del paso del muro al pedestal: la pieza de Blender GoldSackPath (misma función, mismo origen que el saco,
	-- pero en studs del juego: va sin escalar) o, sin ella, un lecho de piedra con losas y bordillos hechos con piezas.
	local lawn = ground * CFrame.new(0, GRASS, 0)
	if not PropModel.place(model, "GoldSackPath", lawn) then
		pathFallback(model, lawn)
	end

	-- Mide lo que el saco: de su tamaño sacan las armas la distancia a la que lo rondan.
	local body = part(model, "Body", Vector3.new(radius * 2, 10, radius * 2), center, STONE)
	body.Transparency = 1
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	model:SetAttribute("Radius", radius)
	model.PrimaryPart = body
	CollectionService:AddTag(model, "GoldBag")
	model.Parent = parent
	models[plot.index] = model
end

-- Publica cómo va la bolsa si la bolsa o el ritmo han cambiado (o siempre con `force`).
local function publish(player: Player, data, force: boolean?)
	local bag = data.bag
	local rate = Stats.bagRate(player, false, bag.stage)
	local last = sent[player]
	if not force and last and last.stage == bag.stage and math.abs(last.rate - rate) <= math.abs(rate) * 1e-6 then
		return
	end
	sent[player] = { stage = bag.stage, rate = rate }
	player:SetAttribute("BagStage", bag.stage)
	player:SetAttribute("BagTaken", bag.taken)
	player:SetAttribute("BagAt", workspace:GetServerTimeNow())
	player:SetAttribute("BagRate", rate)
end

-- `seconds` segundos de golpes de sus armas depositadas. Devuelve las monedas que han salido y las bolsas vaciadas.
local function hit(player: Player, data, seconds: number, noPotion: boolean?): (number, number)
	local bag = data.bag
	-- Se pagan monedas enteras: el pico se guarda para el siguiente cobro (con números enormes ya no hay pico).
	-- Cada bolsa vaciada por el camino sube lo que saca cada golpe: lo cuenta BagInfo.collect.
	local emptied, coins
	bag.stage, bag.taken, emptied, coins = BagInfo.collect(bag.stage, bag.taken, Stats.bagRate(player, noPotion, 1) * seconds)
	local total = coins + (carry[player] or 0)
	local whole = if total < 1e15 then math.floor(total) else total
	carry[player] = if total < 1e15 then total - whole else 0
	if whole > 0 then
		PlayerData.addCoins(player, whole)
	end
	return whole, emptied
end

-- Lo que han sacado sus armas mientras no estaba (`seconds` segundos): se cobra de golpe y se le avisa.
local function away(player: Player, data, seconds: number)
	if #data.bag.slots == 0 or seconds < Config.GoldBag.MinAway then
		return
	end
	local coins, emptied = hit(player, data, seconds, true)
	publish(player, data, true)
	if coins > 0 then
		Remotes.BagEvent:FireClient(player, "away", { seconds = seconds, coins = coins, bags = emptied })
	end
end

local function step(player: Player, seconds: number)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	if RunService:IsStudio() then
		-- Prueba (solo en Studio): como si volviera tras esos segundos fuera.
		local test = player:GetAttribute("BagOfflineTest")
		if type(test) == "number" then
			player:SetAttribute("BagOfflineTest", nil)
			away(player, data, test)
		end
	end
	local bag = data.bag
	if #bag.slots > 0 then
		local _, emptied = hit(player, data, seconds)
		bag.seen = os.time()
		if emptied > 0 then
			Remotes.BagEvent:FireClient(player, "emptied", { stage = bag.stage, bags = emptied })
		end
		publish(player, data, emptied > 0)
	else
		publish(player, data)
	end
end

local function copyDamage(copy): number
	return Stats.swordDamage({ sword = copy.sword, trait = copy.trait or 0, grade = copy.grade or 0, metal = copy.metal or 0, size = copy.size or 0 })
end

-- Dejar una copia en la bolsa, o sacarla si ya estaba (o, con "best" / "clear", llenarla con las mejores o vaciarla). Llena, sustituye a la depositada de menos daño; una equipada
-- deja de estarlo.
local function onSet(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	if id == "best" or id == "clear" then
		-- "clear" la vacía; "best" deja las de más daño de las que no están equipadas (lo pide el menú del saco).
		PlayerData.edit(player, function(edited)
			local slots = {}
			if id == "best" then
				local spare = {}
				for _, copy in edited.swords do
					if not table.find(edited.loadout, copy.id) then
						table.insert(spare, { id = copy.id, damage = copyDamage(copy) })
					end
				end
				table.sort(spare, function(a, b)
					return if a.damage ~= b.damage then a.damage > b.damage else a.id < b.id
				end)
				for position = 1, math.min(#spare, Stats.bagSlots(player)) do
					slots[position] = spare[position].id
				end
			end
			edited.bag.slots = slots
			edited.bag.seen = os.time()
		end)
		publish(player, data, true)
		return
	end
	if not PlayerData.findSword(data, id) then
		return
	end
	local message = nil
	PlayerData.edit(player, function(edited)
		local slots = edited.bag.slots
		local at = table.find(slots, id)
		if at then
			table.remove(slots, at)
			return
		end
		local equipped = table.find(edited.loadout, id)
		if equipped then
			table.remove(edited.loadout, equipped)
		end
		if #slots < Stats.bagSlots(player) then
			table.insert(slots, id)
		else
			local weakest, weakestDamage = 1, math.huge
			for position, deposited in slots do
				local copy = PlayerData.findSword(edited, deposited)
				local damage = if copy then copyDamage(copy) else 0
				if damage < weakestDamage then
					weakest, weakestDamage = position, damage
				end
			end
			slots[weakest] = id
		end
		edited.bag.seen = os.time()
	end)
	if message then
		Tell.notice(player, RED, message)
	end
	publish(player, data, true)
end

local function owners()
	for _, plot in Plots.all() do
		local model = models[plot.index]
		if model then
			model:SetAttribute("Owner", if plot.owner then plot.owner.UserId else 0)
		end
	end
end

function GoldBag.start()
	local folder = Instance.new("Folder")
	folder.Name = "Bolsas"
	folder.Parent = workspace:WaitForChild("Map")
	for _, plot in Plots.all() do
		build(plot, folder)
	end

	Remotes.SetBag.OnServerEvent:Connect(onSet)

	-- Al cargar: lo ganado fuera desde la última vez que sus armas pegaron (sin tope de tiempo).
	PlayerData.onLoad(function(player)
		local data = PlayerData.read(player)
		if not data then
			return
		end
		local seen = data.bag.seen
		data.bag.seen = os.time()
		if seen then
			away(player, data, os.time() - seen)
		end
		publish(player, data, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
		carry[player] = nil
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local seconds = now - last
			last = now
			owners()
			for _, player in Players:GetPlayers() do
				step(player, seconds)
			end
		end
	end)
end

return GoldBag
