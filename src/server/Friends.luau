-- Bono de amigos (pedido por el usuario): cuenta cuántos amigos de Roblox tiene cada jugador en este servidor y lo
-- publica en su atributo "Friends" (como mucho Config.Friends.Max). Stats.friendBonus lo convierte en suerte y monedas.
-- Preguntar a Roblox espera, así que cada pareja se pregunta una sola vez y se guarda para las dos personas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Friends = {}

local known = {} -- [jugador] = { [userId] = true o false } de las parejas ya preguntadas

local function publish(player: Player)
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and known[player] and known[player][other.UserId] then
			count += 1
		end
	end
	if player.Parent then
		player:SetAttribute("Friends", math.min(count, Config.Friends.Max))
	end
end

local function check(a: Player, b: Player)
	local ok, friends = pcall(a.IsFriendsWith, a, b.UserId)
	-- Si Roblox falla se cuenta como que no; volverá a preguntarse si alguno de los dos vuelve a entrar.
	friends = ok and friends == true
	if known[a] then
		known[a][b.UserId] = friends
	end
	if known[b] then
		known[b][a.UserId] = friends
	end
	publish(a)
	publish(b)
end

local function onJoin(player: Player)
	known[player] = {}
	player:SetAttribute("Friends", 0)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(check, player, other)
		end
	end
end

function Friends.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		known[player] = nil
		for _, other in Players:GetPlayers() do
			if other ~= player then
				task.defer(publish, other)
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
end

return Friends
