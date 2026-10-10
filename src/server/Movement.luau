-- Velocidad al andar de los personajes (Stats.walkSpeed: Config.WalkSpeed por lo que den los pases).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stats = require(ReplicatedStorage.Shared.Stats)

local Movement = {}

local function apply(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Stats.walkSpeed(player)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		apply(player)
	end)
	-- Un pase recién comprado (o recién comprobado al entrar) cambia la velocidad en el momento.
	player.AttributeChanged:Connect(function(attribute)
		if string.sub(attribute, 1, 5) == "Pass_" then
			apply(player)
		end
	end)
	apply(player)
end

function Movement.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

return Movement
