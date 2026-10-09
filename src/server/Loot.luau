-- Premios por tabla: recorre una lista de drops (Config.Enemies[...].drops, Config.Dungeon.ClearDrops) y
-- entrega lo que toque. Cada drop lleva "kind" y "chance"; lo que hace cada kind está en `handlers`, así
-- que un premio nuevo es una entrada más aquí (o Loot.register desde otro módulo), sin tocar a quien llama.
-- `context` = { level = índice de Config.Dungeons, loot = multiplicador de cantidades, qualityLuck = suerte de
-- calidad de la armadura }. `summary` (opcional) va acumulando lo entregado: { items = { [nombre] = cantidad },
-- armor = { { name, quality, kept } } }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Armor = require(script.Parent.Armor)
local PlayerData = require(script.Parent.PlayerData)
local Potions = require(script.Parent.Potions)

local Loot = {}

local random = Random.new()
local handlers = {}

-- Cantidad de un drop: entre min y max (1 si no lo pone), por el multiplicador de la dificultad. La parte decimal es
-- la probabilidad de uno más (x1.4 = uno, y otro 4 de cada 10 veces): redondeando, un x1.4 no daba nada de más.
function Loot.amount(drop, loot: number?): number
	local amount = random:NextInteger(drop.min or 1, drop.max or 1) * (loot or 1)
	local whole = math.floor(amount)
	if random:NextNumber() < amount - whole then
		whole += 1
	end
	return math.max(1, whole)
end

-- Objeto de Config.Items.
function handlers.item(player: Player, drop, context, summary)
	local item = Config.Items[drop.item]
	if not item then
		return
	end
	local amount = Loot.amount(drop, context.loot)
	PlayerData.edit(player, function(data)
		data.items[drop.item] += amount
	end)
	Remotes.Notice:FireClient(player, `+{Format.short(amount)} {item.name}`, item.color)
	if summary then
		summary.items[drop.item] = (summary.items[drop.item] or 0) + amount
	end
end

-- Pieza de armadura de la dificultad; "luck" del drop multiplica la suerte de calidad.
function handlers.armor(player: Player, drop, context, summary)
	local piece, kept = Armor.give(player, context.level, (context.qualityLuck or 1) * (drop.luck or 1))
	if piece and summary then
		table.insert(summary.armor, { name = ArmorStats.name(piece), quality = piece.quality, kept = kept })
	end
end

-- Poción (Config.Potions): cuál sale lo deciden los pesos del nivel de contenido de la mazmorra (Config.Potions.Pools).
function handlers.potion(player: Player, _drop, context, summary)
	local cfg = Config.Potions
	local key = Potions.drop(player, "dungeon", cfg.DungeonLevel[context.level] or #cfg.Pools.dungeon)
	if key and summary then
		summary.items[key] = (summary.items[key] or 0) + 1
	end
end

function Loot.register(kind: string, handler)
	handlers[kind] = handler
end

function Loot.summary()
	return { items = {}, armor = {} }
end

function Loot.roll(player: Player, drops, context, summary)
	for _, drop in drops do
		local handler = handlers[drop.kind]
		if handler and Chance.roll(drop.chance or 1) then
			handler(player, drop, context, summary)
		end
	end
end

return Loot
