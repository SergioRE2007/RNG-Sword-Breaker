-- Estadísticas finales del jugador: junta espada, rasgo, artefactos equipados y mejoras.
-- Lee los atributos del Player, así que da lo mismo en el servidor y en el cliente.
local Config = require(script.Parent.Config)
local Upgrades = require(script.Parent.Upgrades)

local Stats = {}

-- "1,4,9" -> { 1, 4, 9 }
function Stats.list(player: Player, attribute: string): { number }
	local result = {}
	for value in string.gmatch(player:GetAttribute(attribute) or "", "%d+") do
		table.insert(result, tonumber(value))
	end
	return result
end

-- Copias de espada del inventario: { id, sword = índice de Config.Swords, trait = índice de Config.Traits o 0 }.
function Stats.swords(player: Player)
	local result = {}
	for id, sword, trait in string.gmatch(player:GetAttribute("Swords") or "", "(%d+):(%d+):(%d+)") do
		table.insert(result, { id = tonumber(id), sword = tonumber(sword), trait = tonumber(trait) })
	end
	return result
end

-- Copia equipada.
function Stats.equipped(player: Player)
	local id = player:GetAttribute("Equipped")
	for _, copy in Stats.swords(player) do
		if copy.id == id then
			return copy
		end
	end
	return { id = 0, sword = 1, trait = 0 }
end

-- Daño de una copia de espada con su rasgo, sin contar artefactos.
function Stats.swordDamage(copy): number
	local trait = Config.Traits[copy.trait]
	return Config.Swords[copy.sword].damage * (if trait then trait.damage else 1)
end

local function gear(player: Player, stat: string): number
	local total = 1
	for _, index in Stats.list(player, "Gear") do
		local artifact = Config.Artifacts[index]
		if artifact and artifact.stat == stat then
			total *= artifact.mult
		end
	end
	return total
end

local function upgrade(player: Player, name: string): number
	return Upgrades.value(name, player:GetAttribute("Upgrade_" .. name) or 0)
end

function Stats.damage(player: Player): number
	return Stats.swordDamage(Stats.equipped(player)) * gear(player, "damage")
end

-- Multiplicador de suerte que dan el rasgo de la espada equipada y los artefactos.
local function luckBonus(player: Player): number
	local trait = Config.Traits[Stats.equipped(player).trait]
	return (if trait then trait.luck else 1) * gear(player, "luck")
end

function Stats.luck(player: Player): number
	return upgrade(player, "luck") * luckBonus(player)
end

function Stats.gachaLuck(player: Player): number
	return upgrade(player, "gachaLuck") * luckBonus(player)
end

function Stats.coins(player: Player): number
	return gear(player, "coins")
end

function Stats.gems(player: Player): number
	return gear(player, "gems")
end

return Stats
