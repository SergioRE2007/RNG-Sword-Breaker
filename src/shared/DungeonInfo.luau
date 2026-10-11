-- Lo que enseñan de cada zona de mazmorra los carteles de las salas, la ventana de grupo y el resultado: sus premios
-- principales, el daño recomendado y si está cerrada. Una sola fuente para cliente y servidor (el servidor repite la
-- comprobación de "cerrada" antes de dejar entrar).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local DungeonInfo = {}

local GOLD = Color3.fromRGB(255, 215, 90)

local POTION = Color3.fromRGB(120, 220, 255)

-- "1.5", "12", "0.4": con un decimal solo por debajo de 10.
local function short(value: number): string
	if value >= 10 then
		return tostring(math.floor(value + 0.5))
	end
	return tostring(math.floor(value * 10 + 0.5) / 10)
end

-- Lo que cae en una partida de la zona jugada en solitario, uno por línea: { text, color } (pedido por el usuario: que
-- se vea la probabilidad de cada cosa). Sale de las mismas tablas que reparte server/Loot: los "drops" de cada
-- enemigo de sus oleadas (con el "count" de la zona) y Config.Dungeon.ClearDrops. De los cristales, cuántos caen de
-- media por partida (con el "loot" de la zona); de la armadura y las pociones, la probabilidad de que caiga al menos
-- una. En grupo hay más enemigos y sale algo más; el pase de botín no va contado.
function DungeonInfo.rewards(index: number): { { text: string, color: Color3 } }
	local level = Config.Dungeons[index]
	if not level then
		return {}
	end
	local average, none = {}, {} -- [clave] = cuántos de media / probabilidad de que no caiga ninguno
	local function add(drop, times: number)
		local key = if drop.kind == "item" then drop.item else drop.kind
		local chance = math.clamp(drop.chance or 1, 0, 1)
		local amount = if drop.kind == "item" then ((drop.min or 1) + (drop.max or 1)) / 2 * level.loot else 1
		average[key] = (average[key] or 0) + chance * times * amount
		none[key] = (none[key] or 1) * (1 - chance) ^ times
	end
	local theme = Config.DungeonThemes[level.id]
	for _, wave in if theme and theme.waves then theme.waves else Config.Dungeon.Waves do
		for _, entry in wave do
			local def = Config.Enemies[entry[1]]
			if def then
				local total = if def.scaleCount == false then entry[2] else math.ceil(entry[2] * level.count)
				for _, drop in def.drops or {} do
					add(drop, total)
				end
			end
		end
	end
	for _, drop in Config.Dungeon.ClearDrops do
		add(drop, 1)
	end

	local lines = {}
	for _, key in { "traitCrystal", "gradeCrystal" } do
		if average[key] then
			table.insert(lines, { text = `{Config.Items[key].name}: ~{short(average[key])}`, color = Config.Items[key].color })
		end
	end
	local function percent(key: string): string
		return short(math.min((1 - none[key]) * 100, 99)) .. " %"
	end
	if none.armor then
		table.insert(lines, { text = `Armadura {level.set}: {percent("armor")}`, color = GOLD })
	end
	if none.potion then
		table.insert(lines, { text = `Poción: {percent("potion")}`, color = POTION })
	end
	return lines
end

-- Daño por golpe recomendado para la zona.
function DungeonInfo.recommended(index: number): number
	local level = Config.Dungeons[index]
	return if level then level.hp else 0
end

-- Por qué no se puede entrar con ese daño (texto corto), o nil si se puede. Solo cierra una zona si trae "minDamage".
function DungeonInfo.lock(index: number, damage: number): string?
	local level = Config.Dungeons[index]
	if level and level.minDamage and damage < level.minDamage then
		return `Daño mínimo {Format.short(level.minDamage)}`
	end
	return nil
end

return DungeonInfo
