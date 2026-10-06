-- Transporte desde la barra de arriba (Hub, Casa, Tiendas): el cliente pide un destino con el
-- remote Teleport y aquí se valida y se mueve al personaje. "dungeon" es la plaza del lobby subterráneo de mazmorras
-- (DungeonLobby), "home" es la parcela del jugador (Plots), "hub" el centro junto a la boca del pozo de las mazmorras y
-- "shops" delante de los puestos de Rasgos y Grados (ModifierShops los pone entre los caminos de 112.5° y 157.5°,
-- a HubRadius - 18).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DungeonLobby = require(script.Parent.DungeonLobby)
local Plots = require(script.Parent.Plots)

local Teleport = {}

local COOLDOWN = 1 -- segundos mínimos entre viajes
local lastTravel = {} -- [player] = os.clock() del último viaje

-- Sitio (mirando hacia donde toca) de cada destino, o nil si no hay.
local function destination(player: Player, where: unknown): CFrame?
	local floor = Config.Plot.FloorHeight + 3
	if where == "hub" then
		-- En el centro, a un lado de la boca del pozo de las mazmorras, mirándola.
		return CFrame.lookAt(Vector3.new(0, floor, 38), Vector3.new(0, floor, 0))
	elseif where == "shops" then
		-- Entre los dos puestos, mirándolos.
		local angle = math.rad(135)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local stand = direction * (Config.Plot.HubRadius - 40) + Vector3.new(0, floor, 0)
		return CFrame.lookAt(stand, stand + direction)
	elseif where == "dungeon" then
		-- Abajo, en la plaza del lobby subterráneo.
		local plaza = DungeonLobby.plazaCFrame()
		if plaza then
			return plaza
		end
		-- (Si el lobby no se ha podido construir: delante del portal de siempre, que Dungeons pone a HubRadius - 18.)
		local angle = math.rad(Config.Dungeon.PortalAngle)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local stand = direction * (Config.Plot.HubRadius - 32) + Vector3.new(0, floor, 0)
		return CFrame.lookAt(stand, stand + direction)
	elseif where == "home" then
		local plot = Plots.get(player)
		return plot and plot.spawn.CFrame + Vector3.new(0, 4, 0)
	end
	return nil
end

local function onTeleport(player: Player, where: unknown)
	local now = os.clock()
	if now - (lastTravel[player] or 0) < COOLDOWN then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local target = destination(player, where)
	if not target or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastTravel[player] = now
	character:PivotTo(target)
end

function Teleport.start()
	Remotes.Teleport.OnServerEvent:Connect(onTeleport)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return Teleport
