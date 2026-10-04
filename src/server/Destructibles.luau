-- Objetos rompibles: aparecen dentro de la parcela de cada jugador según sus mejoras.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

local Destructibles = {}

local objects = {} -- [Part] = { def, hp, plot, localPosition, radius }
local counts = {} -- [plot] = número de objetos vivos
local rng = Random.new()
local folder

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
local function findPosition(plot, radius: number): Vector3?
	local limit = Config.Plot.Size / 2 - 2 - radius
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
		if free then
			return position
		end
	end
	return nil
end

local function spawnIn(plot)
	local luck = Stats.luck(plot.owner)
	local def = rollDef(luck)
	local radius = math.max(def.size.X, def.size.Z) * 0.7
	local position = findPosition(plot, radius)
	if not position then
		return
	end

	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = def.size
	part.Color = def.color
	part.Material = def.material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = plot.cframe * CFrame.new(position + Vector3.new(0, def.size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part:SetAttribute("HP", def.hp)
	part:SetAttribute("MaxHP", def.hp)
	CollectionService:AddTag(part, "Destructible")
	objects[part] = { def = def, hp = def.hp, plot = plot, localPosition = position, radius = radius }
	counts[plot] = (counts[plot] or 0) + 1
	part.Parent = folder

	if def.rarity / luck >= Config.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡A {plot.owner.DisplayName} le ha aparecido {def.name} (1 entre {Format.short(def.rarity)})!`, def.color)
	end
end

local function remove(part: BasePart)
	local object = objects[part]
	objects[part] = nil
	counts[object.plot] -= 1
	part:Destroy()
end

-- Objetos de la parcela del jugador que están a su alcance y delante de él.
function Destructibles.getInRange(player: Player, origin: CFrame, range: number, arc: number): { BasePart }
	local found = {}
	local plot = Plots.get(player)
	local position = origin.Position
	local look = origin.LookVector
	for part, object in objects do
		if object.plot ~= plot then
			continue
		end
		local half = part.Size / 2
		local localPoint = part.CFrame:PointToObjectSpace(position)
		local closest = part.CFrame * Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
		local offset = closest - position
		if offset.Magnitude <= range then
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if arc <= -1 or flat.Magnitude < 2 or flat.Unit:Dot(look) >= arc then
				table.insert(found, part)
			end
		end
	end
	return found
end

-- Si el golpe rompe el objeto devuelve su definición (Config.Destructibles) y las monedas y
-- gemas que da al jugador (con sus multiplicadores); si sigue en pie, nil.
function Destructibles.damage(part: BasePart, amount: number, player: Player)
	local object = objects[part]
	if not object then
		return nil
	end

	object.hp -= amount
	if object.hp > 0 then
		part:SetAttribute("HP", object.hp)
		return nil
	end

	local def = object.def
	local coins = def.reward * Stats.coins(player)
	local gems = def.gems * Stats.gems(player)
	Remotes.Broken:FireAllClients(player, part.CFrame, part.Size, part.Color, part.Material, coins, gems)
	remove(part)
	return def, coins, gems
end

function Destructibles.start()
	folder = Instance.new("Folder")
	folder.Name = "Destructibles"
	folder.Parent = workspace

	Plots.onRelease(function(plot)
		for part, object in objects do
			if object.plot == plot then
				remove(part)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Plot.SpawnInterval)
			for _, plot in Plots.all() do
				if plot.owner then
					local capacity = Upgrades.value("capacity", PlayerData.getUpgrade(plot.owner, "capacity"))
					if (counts[plot] or 0) < capacity then
						spawnIn(plot)
					end
				end
			end
		end
	end)
end

return Destructibles
