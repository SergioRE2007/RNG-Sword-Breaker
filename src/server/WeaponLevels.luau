-- Subir de nivel las armas pagando gemas (pedido por el usuario; números y cuentas en Config.WeaponLevel y
-- shared/WeaponLevel). El nivel va en la copia (copy.level): el cliente solo pide (LevelSword) y aquí se valida y se cobra.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeaponLevel = require(ReplicatedStorage.Shared.WeaponLevel)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local WeaponLevels = {}

local COOLDOWN = 0.1 -- segundos mínimos entre peticiones
local RED = Color3.fromRGB(255, 120, 120)
local last = {} -- [player] = os.clock() de su última petición

local function onLevel(player: Player, id: unknown, wanted: unknown)
	if type(id) ~= "number" or type(wanted) ~= "number" or wanted ~= wanted or wanted < 1 then
		return
	end
	local now = os.clock()
	if now - (last[player] or 0) < COOLDOWN then
		return
	end
	last[player] = now
	local data = PlayerData.read(player)
	local copy = data and PlayerData.findSword(data, id)
	if not copy then
		return
	end
	if WeaponLevel.sanitize(copy.level) >= Config.WeaponLevel.MaxLevel then
		Tell.notice(player, RED, "Max level")
		return
	end
	local count, cost = WeaponLevel.affordable(copy, data.gems, math.min(math.floor(wanted), Config.WeaponLevel.MaxLevel))
	if count == 0 then
		Tell.notice(player, RED, "Not enough gems")
		return
	end
	PlayerData.edit(player, function(edited)
		local same = PlayerData.findSword(edited, id)
		if same and edited.gems >= cost then
			edited.gems -= cost
			same.level = WeaponLevel.sanitize(same.level) + count
		end
	end)
end

function WeaponLevels.start()
	Remotes.LevelSword.OnServerEvent:Connect(onLevel)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return WeaponLevels
