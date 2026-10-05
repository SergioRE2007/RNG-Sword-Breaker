-- Pases de juego (gamepass, Config.Gamepasses): mira cuáles tiene cada jugador y lo publica en el atributo
-- "Pass_<clave>" (true o false), que es lo que leen servidor y cliente con Stats.pass y Stats.perk. La compra
-- la abre el cliente (tienda del menú) y Roblox avisa aquí cuando se completa. El atributo solo lo pone el
-- servidor: lo que el cliente se cambie a sí mismo no llega aquí, así que no puede regalarse un pase.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Passes = {}

local function grant(player: Player, key: string, owned: boolean)
	player:SetAttribute("Pass_" .. key, owned)
end

local function onPlayer(player: Player)
	-- Modo de pruebas (solo en Studio): todos los pases.
	local test = RunService:IsStudio() and Config.Test.AllGamepasses
	for key, pass in Config.Gamepasses do
		grant(player, key, test)
		if not test and pass.id > 0 then
			task.spawn(function()
				local ok, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
				if ok and owned and player.Parent then
					grant(player, key, true)
				elseif not ok then
					warn(`[Passes] No se pudo comprobar el pase {key} de {player.Name}: {owned}`)
				end
			end)
		end
	end
end

function Passes.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.Gamepasses do
			if pass.id == gamePassId then
				grant(player, key, true)
			end
		end
	end)
end

return Passes
