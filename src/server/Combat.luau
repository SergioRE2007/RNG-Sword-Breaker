-- Recibe los espadazos del cliente, los valida y aplica el daño.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Destructibles = require(script.Parent.Destructibles)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Gacha = require(script.Parent.Gacha)
local Gear = require(script.Parent.Gear)
local Traits = require(script.Parent.Traits)
local PlayerData = require(script.Parent.PlayerData)

local Combat = {}

local lastSwing = {} -- [Player] = os.clock()

local function onSwing(player: Player)
	local now = os.clock()
	-- Margen del 20% para que el lag no descarte golpes legítimos.
	local cooldown = Upgrades.value("speed", PlayerData.getUpgrade(player, "speed"))
	if now - (lastSwing[player] or 0) < cooldown * 0.8 then
		return
	end
	lastSwing[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if not character:FindFirstChildWhichIsA("Tool") then
		return
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.SwingFx:FireClient(other, player)
		end
	end

	local sword = Config.Swords[PlayerData.getSwordLevel(player)]
	local range = Config.BaseRange + sword.bladeLength
	local damage = Stats.damage(player)
	for _, part in Destructibles.getInRange(player, root.CFrame, range) do
		Remotes.Hit:FireAllClients(player, part, part.Position, damage)
		local broken, coins, gems = Destructibles.damage(part, damage, player)
		if broken then
			PlayerData.addCoins(player, coins)
			if gems > 0 then
				PlayerData.addGems(player, gems)
			end
			if broken.dropsSword then
				Gacha.give(player, Config.Gacha.RockLuck, "roca")
			end
			Traits.onBroken(player, broken)
			Gear.onBroken(player)
		end
	end
end

function Combat.start()
	Remotes.Swing.OnServerEvent:Connect(onSwing)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return Combat
