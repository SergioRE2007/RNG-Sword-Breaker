-- Trébol de la suerte (Config.Clover; pedido por el usuario): el jugador lo pulsa en la mochila, elige un objeto de su
-- parcela (client/Clover) y la suerte de armas de ese objeto se multiplica por Config.Clover.Luck, encima de todo lo
-- que ya tuviera. Entra una sola vez, en la suerte del objeto (Destructibles.boost), y cada objeto admite un solo trébol.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Destructibles = require(script.Parent.Destructibles)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local Clover = {}

local cfg = Config.Clover
local BAD = Color3.fromRGB(255, 110, 110)

local function onUse(player: Player, part: unknown)
	if typeof(part) ~= "Instance" or not Destructibles.owns(player, part) then
		return
	end
	local data = PlayerData.read(player)
	if not data or data.items[cfg.Item] < 1 then
		return
	end
	if part:GetAttribute("Clover") then
		Tell.notice(player, BAD, "That object already has a clover")
		return
	end
	-- Primero el objeto (puede haberse roto entre tanto) y luego el cobro.
	if not Destructibles.boost(part, cfg.Luck) then
		return
	end
	PlayerData.edit(player, function(edited)
		edited.items[cfg.Item] -= 1
	end)
	Tell.notice(player, Config.Items[cfg.Item].color, "Clover placed: x{n} weapon luck!", { n = cfg.Luck })
end

function Clover.start()
	Remotes.UseClover.OnServerEvent:Connect(onUse)
end

return Clover
