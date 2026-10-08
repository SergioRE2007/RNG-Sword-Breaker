-- Administradores del juego: quién puede usar el menú de admin (client/AdminPanel) y sus órdenes. En el juego
-- publicado lo son el dueño (la cuenta que lo publica o, si es de un grupo, el dueño del grupo) y los de Config.Admins;
-- en Studio, cualquiera que le dé a Jugar con Config.Test.Admin. Se decide aquí al entrar cada jugador y se publica en
-- su atributo "Admin", que el cliente solo usa para enseñar el menú: cada orden que llega se vuelve a comprobar con
-- Admin.is, así que fabricarse el menú con trampas no sirve de nada.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Admin = {}

local admins: { [Player]: boolean } = {}

local function check(player: Player): boolean
	if RunService:IsStudio() then
		return Config.Test.Admin == true
	end
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	-- Juego de un grupo: su dueño (rango 255). La consulta puede fallar; entonces no lo es.
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank == 255
end

-- ¿Es administrador ese jugador? Lo que decide si se obedece una orden de admin.
function Admin.is(player: Player): boolean
	return admins[player] == true
end

function Admin.start()
	local function add(player: Player)
		-- En su propio hilo: mirar el rango del grupo espera a la red.
		task.spawn(function()
			if check(player) and player.Parent then
				admins[player] = true
				player:SetAttribute("Admin", true)
			end
		end)
	end
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)
end

return Admin
