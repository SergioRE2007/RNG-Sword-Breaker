-- Qué puede atacar el jugador y qué tiene a mano (librería sin start()): los objetos de su parcela y, en una mazmorra,
-- los enemigos, siempre dentro de su círculo (Config.Loadout.Radius). La comparten el clic (SwordController), los
-- automáticos (AutoPlay, Dungeons), las armas que giran (OrbitWeapons) y la vista de pruebas (HitboxDebug). Hace la
-- misma cuenta que server/Combat, que es quien decide.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)

local Targeting = {}

local player = Players.LocalPlayer

-- Raíz del personaje, solo si está vivo.
function Targeting.root(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

-- Si esa pieza es algo que el jugador puede atacar: un objeto suyo o un enemigo, y sigue en el mundo.
function Targeting.valid(part: Instance?): boolean
	if not part or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
		return false
	end
	if CollectionService:HasTag(part, "Destructible") then
		return part:GetAttribute("Owner") == player.UserId
	end
	return CollectionService:HasTag(part, "Enemy")
end

-- Todo lo que puede atacar ahora mismo, esté o no a mano.
function Targeting.candidates(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged("Destructible") do
		if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId and part:IsDescendantOf(workspace) then
			table.insert(list, part)
		end
	end
	if (player:GetAttribute("Dungeon") or 0) > 0 then
		for _, part in CollectionService:GetTagged("Enemy") do
			if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
				table.insert(list, part)
			end
		end
	end
	return list
end

-- Si la pieza está dentro del círculo del jugador. `radius` = otro radio (para acercarse más, o con margen).
function Targeting.inCircle(part: BasePart, radius: number?): boolean
	local root = Targeting.root()
	return root ~= nil and Hitbox.within(part, root.Position, radius or Config.Loadout.Radius)
end

-- Lo más cercano al jugador de lo que puede atacar. Con `radius`, solo lo que esté dentro de ese círculo; `skip` =
-- piezas que no cuentan hasta la hora (os.clock) que llevan apuntada.
function Targeting.nearest(radius: number?, skip: { [BasePart]: number }?): BasePart?
	local root = Targeting.root()
	if not root then
		return nil
	end
	local now = os.clock()
	local best, bestDistance = nil, math.huge
	for _, part in Targeting.candidates() do
		if skip and (skip[part] or 0) > now then
			continue
		end
		local distance = (part.Position - root.Position).Magnitude - math.max(part.Size.X, part.Size.Z) / 2
		if distance < bestDistance and (not radius or Hitbox.within(part, root.Position, radius)) then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- Objetivo al que el servidor tiene mandadas las armas de ese jugador (el suyo, sin argumento), o nil.
function Targeting.current(other: Player?): BasePart?
	local holder = (other or player):FindFirstChild("AttackTarget")
	local target = holder and holder:IsA("ObjectValue") and holder.Value
	if target and target:IsA("BasePart") and target:IsDescendantOf(workspace) then
		return target
	end
	return nil
end

return Targeting
