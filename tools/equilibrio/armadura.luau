-- Cómo reparte su poder la armadura con estadísticas aleatorias (Config.Armor.Generator) en una zona y una calidad.
--   lune run tools/equilibrio/armadura.luau [zona] [calidad] [piezas]
-- Enseña lo que da una pieza de una sola stat por hueco (la referencia), el reparto medio y el máximo de cada cantidad
-- de stats, cuánto poder total tiene cada una (en piezas de una stat) y unas piezas de ejemplo. Es la herramienta para
-- retocar Generator.Reference, Budget, Split y Count sin jugar: lo que sube el ritmo del juego se comprueba después con
-- informe.luau (la armadura entra en Stats.luck, Stats.damage y Stats.coins).
local process = require("@lune/process")
local Cargar = require("./cargar")

local shared = Cargar.nuevo()
local Config = shared("Config")
local Format = shared("Format")
local ArmorStats = shared("ArmorStats")

local cfg = Config.Armor
local gen = cfg.Generator
local zona = math.clamp(tonumber(process.args[1]) or #Config.Dungeons, 1, #Config.Dungeons)
local calidad = math.clamp(tonumber(process.args[2]) or #cfg.Qualities, 1, #cfg.Qualities)
local piezas = tonumber(process.args[3]) or 20000

local function valor(stat: string, value: number): string
	if cfg.Stats[stat].flat then
		return Format.short(value)
	end
	return string.format("%.1f%%", value * 100)
end

print(`== Armadura: zona {zona} ({Config.Dungeons[zona].id}), calidad {cfg.Qualities[calidad].name} ==`)
print("\n-- Referencia: una pieza de UNA sola stat por hueco (con el reparto y la tirada medios) --")
for _, slot in cfg.SlotOrder do
	local parts = {}
	for _, stat in gen.Pool do
		table.insert(parts, `{stat} {valor(stat, ArmorStats.reference(stat, slot, calidad, zona))}`)
	end
	print(`{slot} (peso {cfg.Slots[slot].weight}): {table.concat(parts, " · ")}`)
end

-- Reparte `piezas` piezas de la pechera y mide el poder (en piezas de una stat) de cada cantidad de stats.
local contador = { piezas = table.create(#gen.Count, 0), poder = table.create(#gen.Count, 0), minimo = table.create(#gen.Count, math.huge), maximo = table.create(#gen.Count, 0), parteMax = table.create(#gen.Count, 0) }
local rng = { NextNumber = function() return math.random() end }
math.randomseed(2026)
local ejemplos = {}
for _ = 1, piezas do
	local stats = ArmorStats.generate("chest", calidad, zona, rng)
	local n = #stats
	local poder, parteMax = 0, 0
	for _, entry in stats do
		local parte = entry.value / ArmorStats.reference(entry.stat, "chest", calidad, zona)
		poder += parte
		parteMax = math.max(parteMax, parte)
	end
	contador.piezas[n] += 1
	contador.poder[n] += poder
	contador.minimo[n] = math.min(contador.minimo[n], poder)
	contador.maximo[n] = math.max(contador.maximo[n], poder)
	contador.parteMax[n] = math.max(contador.parteMax[n], parteMax)
	if not ejemplos[n] then
		ejemplos[n] = stats
	end
end

print("\n-- Por cantidad de stats (poder = suma de lo que vale cada stat respecto a su referencia; 1 = una pieza de una stat) --")
for n = 1, #gen.Count do
	if contador.piezas[n] > 0 then
		print(string.format("%d stat%s: %4.1f %% de las piezas · poder medio %.2f (de %.2f a %.2f) · la stat más grande llega a %.2f de la referencia", n, if n == 1 then " " else "s", contador.piezas[n] / piezas * 100, contador.poder[n] / contador.piezas[n], contador.minimo[n], contador.maximo[n], contador.parteMax[n]))
	end
end

print("\n-- Una pieza de ejemplo de cada cantidad (pechera) --")
for n = 1, #gen.Count do
	if ejemplos[n] then
		local parts = {}
		for _, entry in ejemplos[n] do
			table.insert(parts, `+{valor(entry.stat, entry.value)} {cfg.Stats[entry.stat].name}`)
		end
		print(`{n}: {table.concat(parts, " · ")}`)
	end
end

print("\n-- Los cuatro huecos con piezas de esta calidad y zona: especializada frente a versátil --")
for _, stat in gen.Pool do
	local total = 0
	for _, slot in cfg.SlotOrder do
		total += ArmorStats.reference(stat, slot, calidad, zona)
	end
	print(`{stat}: {valor(stat, total)} con cuatro piezas de solo esa stat · {valor(stat, total * gen.Budget[#gen.Budget] / #gen.Pool)} con cuatro piezas de cuatro stats`)
end
