-- Objetos rompibles: aparecen dentro de la parcela de cada jugador según sus mejoras. Cada uno sale con un tipo
-- (Config.Destructibles, según la suerte de parcela), una rareza y un tamaño propios (shared/ObjectSpec), que
-- deciden su vida, su premio y las tiradas de arma que da al romperse. Todo eso lo decide y lo guarda el servidor;
-- los atributos de la pieza (Quality, Size, Scale, Luck, Rolls) son solo para que el cliente lo enseñe.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ObjectModel = require(ReplicatedStorage.Shared.ObjectModel)
local ObjectSpec = require(ReplicatedStorage.Shared.ObjectSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local PlayerData = require(script.Parent.PlayerData)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Plots = require(script.Parent.Plots)

local Destructibles = {}

-- [Part] = { def, hp, maxHp, plot, localPosition, radius, quality, size, scale, luck, rolls, reward, odds }
-- (quality, size, scale, luck, rolls y reward salen de ObjectSpec.roll al aparecer).
local objects = {}
local counts = {} -- [plot] = número de objetos vivos
local pending = {} -- [plot] = objeto ya tirado que aún no ha cabido en la parcela (se vuelve a intentar)
local nextSpawn = {} -- [plot] = os.clock() en que le toca aparecer al siguiente
local rng = Random.new()
local folder

local SPAWN_TICK = 0.1 -- cada cuánto se mira si a alguna parcela le toca objeto

-- Prueba del más raro al más común; la suerte multiplica cada probabilidad.
local function rollDef(luck: number)
	for index = #Config.Destructibles, 2, -1 do
		local def = Config.Destructibles[index]
		if Chance.roll(luck / def.rarity) then
			return def
		end
	end
	return Config.Destructibles[1]
end

-- Posición libre en coordenadas de la parcela, o nil si no cabe.
local function charactersClear(plot, position: Vector3, radius: number, height: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local point = plot.cframe:PointToObjectSpace(root.Position)
			local horizontal = Vector3.new(point.X, 0, point.Z) - position
			if point.Y > -4 and point.Y < height + 4 and horizontal.Magnitude < radius + 4 then
				return false
			end
		end
	end
	return true
end

local function findPosition(plot, radius: number, height: number): Vector3?
	local limit = Config.Plot.Size / 2 - 2 - radius
	if limit <= 0 then return nil end
	for _ = 1, 15 do
		local position = Vector3.new(rng:NextNumber(-limit, limit), 0, rng:NextNumber(-limit, limit))
		local free = (position - plot.spawnOffset).Magnitude > radius + 6
		if free then
			for _, object in objects do
				if object.plot == plot and (object.localPosition - position).Magnitude < radius + object.radius + 1 then
					free = false
					break
				end
			end
		end
		if free and charactersClear(plot, position, radius, height) then
			return position
		end
	end
	return nil
end

-- "Cristal (Legendaria, Enorme)": el objeto con lo que tiene de especial.
local function describe(def, spec): string
	local parts = { ObjectSpec.rarity(spec.quality).name }
	if spec.size > 1 then
		table.insert(parts, ObjectSpec.size(spec.size).name)
	end
	return `{def.name} ({table.concat(parts, ", ")})`
end

-- Lo que le toca a un objeto nuevo de esa parcela: tipo (suerte de parcela), rareza y tamaño (ObjectSpec).
local function rollSpec(owner: Player)
	-- La poción de suerte de cajas (Stats.spawnLuck) multiplica la del tipo; la de rareza y tamaño ya la lleva objectLuck.
	local luck = Stats.luck(owner) * Stats.spawnLuck(owner)
	local def = rollDef(luck)
	local spec = ObjectSpec.roll(def, Stats.objectLuck(owner))
	spec.def = def
	spec.typeOdds = def.rarity / luck
	return spec
end

-- Sitio para ese objeto en la parcela: su tamaño, su radio y dónde va (nil si ahora no cabe).
local function place(plot, spec): (Vector3, number, Vector3?)
	local size = spec.def.size * spec.scale
	local radius = Vector2.new(size.X, size.Z).Magnitude / 2
	return size, radius, findPosition(plot, radius, size.Y)
end

local function spawnIn(plot)
	local owner = plot.owner
	-- Si no cabe o hay un personaje, espera con la misma tirada hasta tener sitio.
	-- Volver a tirar aquí perdería los objetos raros o grandes cuando la parcela está ocupada.
	local spec = pending[plot] or rollSpec(owner)
	local size, radius, position = place(plot, spec)
	if not position then
		pending[plot] = spec
		return
	end
	pending[plot] = nil
	local def = spec.def
	if not charactersClear(plot, position, radius, size.Y) then
		pending[plot] = spec
		return
	end

	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = size
	part.Color = def.color
	part.Material = def.material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = plot.cframe * CFrame.new(position + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local index = table.find(Config.Destructibles, def) :: number
	ObjectModel.attach(part, index, def, spec.scale)
	part:SetAttribute("Index", index)
	part:SetAttribute("HP", spec.hp)
	part:SetAttribute("MaxHP", spec.hp)
	part:SetAttribute("Quality", spec.quality)
	part:SetAttribute("Size", spec.size)
	part:SetAttribute("Scale", spec.scale)
	part:SetAttribute("Luck", spec.luck)
	part:SetAttribute("Rolls", spec.rolls)
	part:SetAttribute("Owner", owner.UserId)
	CollectionService:AddTag(part, "Destructible")
	objects[part] = {
		def = def,
		hp = spec.hp,
		maxHp = spec.hp,
		plot = plot,
		localPosition = position,
		radius = radius,
		quality = spec.quality,
		size = spec.size,
		scale = spec.scale,
		luck = spec.luck,
		rolls = spec.rolls,
		reward = spec.reward,
		-- "1 entre N" de que a su dueño le saliera un objeto así (tipo, rareza y tamaño): Gacha lo cuenta al medir
		-- lo difícil que era el arma que da.
		odds = math.max(spec.typeOdds, 1) * math.max(spec.odds, 1),
	}
	counts[plot] = (counts[plot] or 0) + 1
	part.Parent = folder

	if spec.typeOdds >= Config.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡A {owner.DisplayName} le ha aparecido {def.name} (1 entre {Format.short(def.rarity)})!`, def.color)
	end
	-- Rareza y tamaño fuera de lo normal: aviso al dueño y, si es muy raro, a todos.
	local rarity = ObjectSpec.rarity(spec.quality)
	if spec.odds >= Config.ObjectRolls.NoticeOdds then
		local rolls = if spec.rolls == 1 then "1 tirada" else `{spec.rolls} tiradas`
		Remotes.Notice:FireClient(owner, `¡Te ha aparecido {describe(def, spec)}!\nSuerte de armas x{Format.multiplier(spec.luck)} · {rolls}`, rarity.color)
	end
	if spec.odds >= Config.ObjectRolls.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡A {owner.DisplayName} le ha aparecido {describe(def, spec)}: suerte de armas x{Format.multiplier(spec.luck)}!`, rarity.color)
	end
end

local function remove(part: BasePart)
	local object = objects[part]
	objects[part] = nil
	counts[object.plot] -= 1
	part:Destroy()
end

-- Si un golpe dado desde `origin` llega a la pieza: a `range` de su punto más cercano y dentro del arco del
-- arma (lo usan también los enemigos de las mazmorras).
function Destructibles.reaches(part: BasePart, origin: CFrame, range: number, arc: number): boolean
	return Hitbox.reaches(part, origin, range, arc)
end

-- Si esa pieza es un objeto vivo de la parcela del jugador (lo único de aquí que puede atacar).
function Destructibles.owns(player: Player, part: Instance): boolean
	local object = objects[part]
	return object ~= nil and object.plot == Plots.get(player)
end

-- Objetos de la parcela del jugador a los que llega un golpe dado desde `origin` (ver Hitbox.reaches).
function Destructibles.getInRange(player: Player, origin: CFrame, range: number, arc: number): { BasePart }
	local found = {}
	local plot = Plots.get(player)
	for part, object in objects do
		if object.plot == plot and Destructibles.reaches(part, origin, range, arc) then
			table.insert(found, part)
		end
	end
	return found
end

-- Si el golpe rompe el objeto devuelve su definición (Config.Destructibles), las monedas y gemas que da al
-- jugador (con sus multiplicadores) y la ficha del objeto ({ quality, size, scale, luck, rolls... }: lo que
-- se decidió al aparecer); si sigue en pie, nil.
function Destructibles.damage(part: BasePart, amount: number, player: Player)
	local object = objects[part]
	if not object then
		return nil
	end

	object.hp -= amount
	-- Con una tolerancia: restar números con decimales deja a veces una pizca (1e-13) y haría falta un golpe más.
	if object.hp > object.maxHp * 1e-9 then
		part:SetAttribute("HP", object.hp)
		return nil
	end

	local def = object.def
	-- Redondeado y con un mínimo de 1: un objeto pequeño no puede dar "+0".
	local coins = if def.reward > 0 then math.max(1, math.round(def.reward * object.reward * Stats.coins(player))) else 0
	-- Gemas: probabilidad propia del objeto y cantidad con algo de azar (Config.GemDrop).
	local gems = 0
	if def.gems > 0 and Chance.roll(def.gemChance or 1) then
		gems = math.max(1, math.round(def.gems * object.reward * Stats.gems(player) * rng:NextNumber(Config.GemDrop.min, Config.GemDrop.max)))
	end
	Remotes.Broken:FireAllClients(player, part.CFrame, part.Size, part.Color, part.Material, coins, gems, table.find(Config.Destructibles, def), {
		quality = object.quality,
		scale = object.scale,
		luck = object.luck,
		rolls = object.rolls,
	})
	remove(part)
	return def, coins, gems, object
end

-- Al importar un .fbx de Blender en Studio el modelo se queda suelto en Workspace (grande y gris): las mallas buenas
-- ya vienen de Shared.ObjectMeshes / ArmorMeshes, así que se borra cualquier resto con las marcas Axis_* de Blender.
local function clearImports()
	for _, item in workspace:GetChildren() do
		if item ~= folder and (item:IsA("Model") or item:IsA("Folder")) and item:FindFirstChild("Axis_Origin", true) then
			item:Destroy()
		end
	end
end

function Destructibles.start()
	clearImports()
	folder = Instance.new("Folder")
	folder.Name = "Destructibles"
	folder.Parent = workspace

	Plots.onRelease(function(plot)
		for part, object in objects do
			if object.plot == plot then
				remove(part)
			end
		end
		pending[plot] = nil
		nextSpawn[plot] = nil
	end)

	-- Cada parcela tiene su ritmo: el de la "Velocidad de aparición" de su dueño (Stats.spawnTime).
	task.spawn(function()
		while true do
			task.wait(SPAWN_TICK)
			local now = os.clock()
			for _, plot in Plots.all() do
				local owner = plot.owner
				local due = nextSpawn[plot] or now
				if owner and now >= due then
					-- El siguiente cuenta desde cuando le tocaba a este (así el tick no le quita ritmo), salvo que vaya
					-- muy retrasada: los que no han salido no se recuperan de golpe.
					local interval = Stats.spawnTime(owner)
					nextSpawn[plot] = math.max(due, now - interval) + interval
					local capacity = Upgrades.value("capacity", PlayerData.getUpgrade(owner, "capacity"))
					if (counts[plot] or 0) < capacity then
						spawnIn(plot)
					end
				end
			end
		end
	end)
end

return Destructibles
