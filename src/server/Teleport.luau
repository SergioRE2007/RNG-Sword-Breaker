-- Transporte desde la barra de arriba (Hub, Casa, Tiendas): el cliente pide un destino con el
-- remote Teleport y aquí se valida y se mueve al personaje. "dungeon" es la plaza del lobby subterráneo de mazmorras
-- (DungeonLobby), "home" es la parcela del jugador (Plots), "hub" (y "shops") delante de los puestos de Rasgos y Grados (ModifierShops los pone entre los caminos de 112.5° y 157.5°,
-- a HubRadius - 18).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DungeonLobby = require(script.Parent.DungeonLobby)
local Plots = require(script.Parent.Plots)

local Teleport = {}

-- Sitio (mirando hacia donde toca) de cada destino, o nil si no hay.
local function destination(player: Player, where: unknown): CFrame?
	local floor = Config.Plot.FloorHeight + 3
	if where == "hub" or where == "shops" then
		-- Entre los dos puestos de Rasgos y Grados, mirándolos.
		local angle = math.rad(135)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local stand = direction * (Config.Plot.HubRadius - 40) + Vector3.new(0, floor, 0)
		return CFrame.lookAt(stand, stand + direction)
	elseif where == "dungeon" then
		-- Abajo, en la plaza del lobby subterráneo (si no se ha podido construir, junto a la boca del pozo, en el hub).
		return DungeonLobby.plazaCFrame() or CFrame.lookAt(Vector3.new(0, floor, 38), Vector3.new(0, floor, 0))
	elseif where == "home" then
		local plot = Plots.get(player)
		return plot and plot.spawn.CFrame + Vector3.new(0, 4, 0)
	end
	return nil
end

local function onTeleport(player: Player, where: unknown)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local target = destination(player, where)
	if not target or not humanoid or humanoid.Health <= 0 then
		return
	end
	character:PivotTo(target)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	Remotes.Teleported:FireClient(player, where)
end

function Teleport.start()
	Remotes.Teleport.OnServerEvent:Connect(onTeleport)
end

return Teleport
