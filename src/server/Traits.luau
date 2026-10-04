-- Rasgos de espada: los objetos raros sueltan Cristales de rasgo y con ellos se tira un
-- rasgo al azar para la copia de espada que elija el jugador.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Traits = {}

local ITEM = "traitCrystal"

local function roll(): number
	for index = #Config.Traits, 2, -1 do
		if Chance.roll(1 / Config.Traits[index].rarity) then
			return index
		end
	end
	return 1
end

-- Se llama cuando el jugador rompe un objeto (def = entrada de Config.Destructibles).
function Traits.onBroken(player: Player, def)
	local item = Config.Items[ITEM]
	if def.gems > 0 and Chance.roll(item.dropChance) then
		PlayerData.edit(player, function(data)
			data.items[ITEM] += 1
		end)
		Remotes.Notice:FireClient(player, `+1 {item.name}`, item.color)
	end
end

local function onRollTrait(player: Player, id: unknown)
	local data = PlayerData.read(player)
	local copy = data and PlayerData.findSword(data, id)
	if not copy or data.items[ITEM] < 1 then
		return
	end

	local index = roll()
	PlayerData.edit(player, function(edited)
		edited.items[ITEM] -= 1
		copy.trait = index
	end)

	local trait = Config.Traits[index]
	local sword = Config.Swords[copy.sword]
	Remotes.Notice:FireClient(
		player,
		`{sword.name}: rasgo {trait.name}\nDaño x{Format.multiplier(trait.damage)} · Suerte x{Format.multiplier(trait.luck)}`,
		trait.color
	)
	if trait.rarity >= Config.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha sacado el rasgo {trait.name} (1 entre {Format.short(trait.rarity)})!`, trait.color)
	end
end

function Traits.start()
	Remotes.RollTrait.OnServerEvent:Connect(onRollTrait)
end

return Traits
