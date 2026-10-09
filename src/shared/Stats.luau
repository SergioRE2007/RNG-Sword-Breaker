-- Estadísticas finales del jugador: junta espada, rasgo, artefactos equipados y mejoras.
-- Lee los atributos del Player, así que da lo mismo en el servidor y en el cliente.
local Config = require(script.Parent.Config)
local Permanent = require(script.Parent.Permanent)
local PotionInfo = require(script.Parent.PotionInfo)
local Upgrades = require(script.Parent.Upgrades)
local WeatherInfo = require(script.Parent.WeatherInfo)

local Stats = {}

-- "1,4,9" -> { 1, 4, 9 }
function Stats.list(player: Player, attribute: string): { number }
	local result = {}
	for value in string.gmatch(player:GetAttribute(attribute) or "", "%d+") do
		table.insert(result, tonumber(value))
	end
	return result
end

-- Copias de espada del inventario: { id, sword = índice de Config.Swords, metal y size = índices de Config.Metals y Sizes (0 = ninguno), trait = índice de
-- Config.Traits o 0, grade = índice de Config.Grades o 0 }.
function Stats.swords(player: Player)
	local result = {}
	for entry in string.gmatch(player:GetAttribute("Swords") or "", "[^,]+") do
		local id, sword, trait, grade, metal, size = string.match(entry, "^(%d+):(%d+):(%d+):?(%d*):?(%d*):?(%d*)$")
		if id then
			table.insert(result, { id = tonumber(id), sword = tonumber(sword), trait = tonumber(trait), grade = tonumber(grade) or 0, metal = tonumber(metal) or 0, size = tonumber(size) or 0 })
		end
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
	return { id = 0, sword = 1, trait = 0, grade = 0, metal = 0, size = 0 }
end

-- Daño de una copia de espada con su rasgo, su metal y su tamaño, sin contar artefactos.
function Stats.swordDamage(copy): number
	local trait = Config.Traits[copy.trait]
	return Config.Swords[copy.sword].damage * (if trait then trait.damage or 1 else 1) * Permanent.damageMult(copy)
end

-- Rareza total ("1 entre N") de una copia: la del arma por las de su metal y su tamaño.
function Stats.rarity(copy): number
	return Permanent.rarity(copy.sword, copy.metal, copy.size)
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

-- Total de un stat de la armadura equipada (el servidor lo publica en "Armor_<stat>"; ver Config.Armor.Stats).
-- La vida se suma; los demás son porcentajes: 0.25 = +25 %.
local function armor(player: Player, stat: string): number
	return player:GetAttribute("Armor_" .. stat) or 0
end

-- Vida máxima del personaje: la base más la que da la armadura, por la poción de vida si hay una activa (redondeada: 100 x 1,15
-- no puede quedarse en 114,99999999999999 y salir como 114).
function Stats.maxHealth(player: Player): number
	return math.round((Config.Armor.BaseHealth + armor(player, "health")) * Stats.potion(player, "health"))
end

-- Si el jugador tiene ese pase de juego (clave de Config.Gamepasses; el servidor lo publica en "Pass_<clave>").
function Stats.pass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

-- Valor de una ventaja de pase ("traitCount", "gradeSpeed"...): el mayor entre los pases que tiene, o nil.
function Stats.perk(player: Player, name: string): number?
	local best = nil
	for key, pass in Config.Gamepasses do
		local value = pass.perks[name]
		if value and Stats.pass(player, key) and (not best or value > best) then
			best = value
		end
	end
	return best
end

-- Tier de la poción activa de esa familia (clave de Config.Potions.Families), 0 si no hay. Lo publica el servidor
-- (server/Potions) en "Potion_<familia>" y en cuanto caduca lo quita, así que esto vale en servidor y cliente.
function Stats.potionTier(player: Player, family: string): number
	return player:GetAttribute("Potion_" .. family) or 0
end

-- Por cuánto multiplica la poción activa de esa familia (1 si no hay ninguna).
function Stats.potion(player: Player, family: string): number
	local tier = Stats.potionTier(player, family)
	return if tier > 0 then PotionInfo.multiplier(family, tier) else 1
end

-- Clima en curso (Config.Weather; server/Weather lo publica en workspace, el mismo para todos): por cuánto multiplica
-- "luck" (suerte de destructibles, en Stats.spawnLuck) o "weaponLuck" (suerte de armas, en Stats.gachaLuck). 1 si está
-- despejado o ese clima no la da.
function Stats.weather(stat: string): number
	return WeatherInfo.multiplier(stat)
end

local function upgrade(player: Player, name: string): number
	return Upgrades.value(name, player:GetAttribute("Upgrade_" .. name) or 0)
end

-- Tipo del arma equipada: su clave ("sword", "axe", "dual", "spear") y sus datos de Config.WeaponKinds.
function Stats.weapon(player: Player)
	local key = Config.Swords[Stats.equipped(player).sword].kind or "sword"
	return key, Config.WeaponKinds[key]
end

-- Segundos entre golpes: el tiempo base por lo rápida o lenta que sea el arma, entre la poción de velocidad de golpe
-- si hay una activa. No hay mejora que lo baje (la hubo, "speed": el usuario la mandó quitar).
function Stats.cooldown(player: Player): number
	local _, kind = Stats.weapon(player)
	return math.max(Config.BaseCooldown * kind.cooldown / Stats.potion(player, "attackSpeed"), Config.MinCooldown)
end

-- Renacimientos que lleva el jugador (el servidor los publica en el atributo "Rebirths").
function Stats.rebirths(player: Player): number
	return player:GetAttribute("Rebirths") or 0
end

-- Multiplicador permanente de un renacimiento para esa estadística ("coins", "damage", "luck" o "gachaLuck").
function Stats.rebirthBonus(player: Player, stat: string): number
	return Config.Rebirth[stat] ^ Stats.rebirths(player)
end

-- Precio en monedas del siguiente renacimiento: el de la lista Config.Rebirth.costs (uno por renacimiento) o, si no
-- la hay, cost * growth ^ renacimientos.
function Stats.rebirthCost(player: Player): number
	local costs = Config.Rebirth.costs
	if costs then
		return costs[math.clamp(Stats.rebirths(player) + 1, 1, #costs)]
	end
	return math.floor(Config.Rebirth.cost * Config.Rebirth.growth ^ Stats.rebirths(player))
end

function Stats.damage(player: Player): number
	return Stats.swordDamage(Stats.equipped(player)) * gear(player, "damage") * Stats.rebirthBonus(player, "damage") * (1 + armor(player, "damage")) * Stats.potion(player, "damage")
end

-- Multiplicador de suerte que dan el rasgo de la espada equipada, los artefactos y la armadura.
local function luckBonus(player: Player): number
	local trait = Config.Traits[Stats.equipped(player).trait]
	return (if trait then trait.luck or 1 else 1) * gear(player, "luck") * (1 + armor(player, "luck"))
end

-- Suerte de destructibles: multiplica la probabilidad de los tipos raros de objeto en su parcela (y la de los
-- artefactos). Es la que sube la mejora "Suerte de destructibles", y con ella el rasgo, los artefactos y la armadura.
function Stats.luck(player: Player): number
	return upgrade(player, "luck") * luckBonus(player) * Stats.rebirthBonus(player, "luck")
end

-- Suerte de armas propia del jugador: multiplica la del objeto que da la tirada (ObjectSpec.luck), que es de donde
-- sale casi toda, y es la única que mejora el metal y el tamaño. No hay mejora que la compre (la de suerte es solo
-- para los destructibles: decidido por el usuario), y el rasgo, los artefactos y la armadura tampoco entran aquí:
-- cuentan en Stats.luck. Aquí van solo las fuentes directas: los renacimientos, la poción de suerte de armas y los
-- climas más raros.
function Stats.gachaLuck(player: Player): number
	return Stats.rebirthBonus(player, "gachaLuck") * Stats.potion(player, "weaponLuck") * Stats.weather("weaponLuck")
end

-- Segundos por tirada gratis del gacha (solo con Config.Gacha.FreeRoll): la mejora "Velocidad de aparición"
-- entre la de la armadura, con un mínimo.
function Stats.rollTime(player: Player): number
	return math.max(upgrade(player, "rollSpeed") / (1 + armor(player, "rollSpeed")), Config.Gacha.MinRollTime)
end

-- Segundos entre apariciones de objetos en la parcela del jugador: la mejora "Velocidad de aparición" (que parte
-- de Config.Plot.SpawnInterval) entre la de la armadura, con un mínimo. Aquí se multiplicarán también los gamepass.
function Stats.spawnTime(player: Player): number
	return math.max(upgrade(player, "rollSpeed") / (1 + armor(player, "rollSpeed")), Config.Plot.MinSpawnInterval)
end

-- Suerte de la rareza y del tamaño de los objetos de la parcela (multiplica sus probabilidades: Config.ObjectRarities
-- y ObjectSizes). No es la suerte de destructibles (Stats.luck), que decide el tipo de objeto. De base 1: aquí se sumarán las mejoras
-- de parcela o los pases que la suban (ventaja "objectLuck"), y la poción de suerte de cajas.
function Stats.objectLuck(player: Player): number
	return (Stats.perk(player, "objectLuck") or 1) * Stats.spawnLuck(player)
end

-- Poción de suerte de cajas: multiplica la probabilidad con la que aparecen los objetos de la parcela, tanto la de su tipo
-- (server/Destructibles la suma a Stats.luck al elegirlo) como la de su rareza y su tamaño (en Stats.objectLuck). No toca
-- la suerte de las armas (Stats.gachaLuck), los accesorios ni los rasgos y grados: las armas solo ganan de rebote, porque
-- salen objetos mejores. El clima (Stats.weather) da esta misma suerte a todos mientras dura.
function Stats.spawnLuck(player: Player): number
	return Stats.potion(player, "boxLuck") * Stats.weather("luck")
end

-- Monedas: artefactos, y el rasgo y el grado de la espada equipada.
function Stats.coins(player: Player): number
	local copy = Stats.equipped(player)
	local trait = Config.Traits[copy.trait]
	local grade = Config.Grades[copy.grade]
	return gear(player, "coins") * (if trait then trait.coins or 1 else 1) * (if grade then grade.coins else 1) * Stats.rebirthBonus(player, "coins")
end

function Stats.gems(player: Player): number
	return gear(player, "gems")
end

return Stats
