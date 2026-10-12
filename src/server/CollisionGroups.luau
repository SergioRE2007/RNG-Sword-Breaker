-- Los escombros (grupo "Debris") no chocan con los personajes, para que no estorben ni empujen.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local CollisionGroups = {}

local function setGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = "Characters"
	end
end

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant)
	end
	character.DescendantAdded:Connect(setGroup)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function CollisionGroups.start()
	PhysicsService:RegisterCollisionGroup("Debris")
	PhysicsService:RegisterCollisionGroup("Characters")
	PhysicsService:CollisionGroupSetCollidable("Debris", "Characters", false)
	-- Enemigos de mazmorra y decorado de la arena (rocas, columnas, troncos): no chocan entre sí, para que los
	-- enemigos grandes no se queden atascados (server/Dungeons y server/DungeonThemes ponen los grupos).
	PhysicsService:RegisterCollisionGroup("Enemies")
	PhysicsService:RegisterCollisionGroup("DungeonDecor")
	PhysicsService:CollisionGroupSetCollidable("Enemies", "DungeonDecor", false)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return CollisionGroups
