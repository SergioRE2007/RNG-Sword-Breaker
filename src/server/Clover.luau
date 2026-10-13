-- Trébol de la suerte (Config.Clover; pedido por el usuario): el jugador lo pulsa en la mochila, elige un objeto de su
-- parcela (client/Clover) y la suerte de armas de ese objeto se multiplica por Config.Clover.Luck, encima de todo lo
-- que ya tuviera. Entra una sola vez, en la suerte del objeto (Destructibles.boost), y cada objeto admite un solo trébol.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Destructibles = require(script.Parent.Destructibles)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local Clover = {}

-- Trébol de prueba de los administradores (menú de admin, server/AdminCommands): [jugador] = suerte a medida. Mientras
-- lo tiene puesto, sus tréboles dan esa suerte en vez de Config.Clover.Luck y no gastan ninguno. No se guarda.
local custom: { [Player]: number } = {}
local MAX_CUSTOM = 1e15

local cfg = Config.Clover
local BAD = Color3.fromRGB(255, 110, 110)

local function onUse(player: Player, part: unknown)
	if typeof(part) ~= "Instance" or not Destructibles.owns(player, part) then
		return
	end
	local data = PlayerData.read(player)
	local test = custom[player]
	if not data or (not test and data.items[cfg.Item] < 1) then
		return
	end
	if part:GetAttribute("Clover") then
		Tell.notice(player, BAD, "That object already has a clover")
		return
	end
	-- Primero el objeto (puede haberse roto entre tanto) y luego el cobro.
	local luck = test or cfg.Luck
	if not Destructibles.boost(part, luck) then
		return
	end
	if not test then
		PlayerData.edit(player, function(edited)
			edited.items[cfg.Item] -= 1
		end)
	end
	Tell.notice(player, Config.Items[cfg.Item].color, "Clover placed: x{n} weapon luck!", { n = Format.short(luck, player) })
end

-- Pone (o quita, con 0) el trébol de prueba de ese jugador. Quien llama ya ha comprobado que es administrador.
-- Devuelve la suerte que queda puesta (0 = ninguna), o nil si el número no vale.
function Clover.setCustom(player: Player, luck: unknown): number?
	if type(luck) ~= "number" or luck ~= luck or luck < 0 or luck > MAX_CUSTOM then
		return nil
	end
	custom[player] = if luck >= 1 then luck else nil
	player:SetAttribute("CloverTest", custom[player])
	return custom[player] or 0
end

function Clover.start()
	Remotes.UseClover.OnServerEvent:Connect(onUse)
	Players.PlayerRemoving:Connect(function(player)
		custom[player] = nil
	end)
end

return Clover
