-- Normas por país (PolicyService). En algunos países Roblox no deja vender objetos de pago que influyen en un resultado
-- al azar (los packs de Trébol de la suerte) ni intercambiar objetos de pago entre jugadores (el comercio). Aquí se
-- pregunta a Roblox al entrar cada jugador y se publica en sus atributos "NoPaidRandom" y "NoPaidTrade": la Tienda
-- esconde los tréboles de Robux (client/PassShop) y server/Trade no abre tratos con quien lo tenga restringido.
-- Si Roblox no contesta tras varios intentos se da por restringido: mejor esconder de más que vender donde no se puede.
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Policy = {}

local TRIES = 5

local function check(player: Player)
	for try = 1, TRIES do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if not player.Parent then
			return
		end
		if ok and type(info) == "table" then
			player:SetAttribute("NoPaidRandom", info.ArePaidRandomItemsRestricted == true)
			player:SetAttribute("NoPaidTrade", info.IsPaidItemTradingAllowed ~= true)
			return
		end
		if try == TRIES then
			warn(`[Policy] Could not read the policy of {player.Name}: {info}`)
		else
			task.wait(try * 2)
		end
	end
	player:SetAttribute("NoPaidRandom", true)
	player:SetAttribute("NoPaidTrade", true)
end

-- ¿Puede comerciar ese jugador? (Mientras Roblox no ha contestado, todavía no.)
function Policy.canTrade(player: Player): boolean
	return player:GetAttribute("NoPaidTrade") == false
end

function Policy.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(check, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
end

return Policy
