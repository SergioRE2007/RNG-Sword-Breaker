-- Cuánto se tarda de verdad con el Config que hay: juega varias partidas simuladas del jugador tipo y enseña la
-- mediana de cada hito al lado de su objetivo.
--   lune run tools/equilibrio/informe.luau [partidas] [horas] [ritmo] [calendario]
-- `ritmo` multiplica lo rápido que rompe el jugador (0.5 = uno lento, 1.5 = uno rápido). El jugador juega también sus
-- mazmorras y lleva el rasgo, el grado y la armadura que saca de ellas; con `calendario`, los que le supone objetivo.luau.
local process = require("@lune/process")
local Cargar = require("./cargar")
local Modelo = require("./modelo")
local objetivo = require("./objetivo")
local Util = require("./util")

local shared, mundo = Cargar.nuevo()
local Config = shared("Config")
local Format = shared("Format")
local M = Modelo.nuevo(shared, mundo, objetivo)

local partidas = tonumber(process.args[1]) or 9
local horas = tonumber(process.args[2]) or 260
local ritmo = tonumber(process.args[3]) or 1
local equipo = if table.find(process.args, "calendario") then "calendario" else "mazmorras"
local tiempo, mediana = Util.tiempo, Util.mediana

print(`== INFORME: {partidas} partidas de hasta {horas} h, ritmo x{ritmo}, con el equipo {if equipo == "calendario" then "que le supone el calendario" else "que saca de las mazmorras"} ==`)
print(`Paridad del muestreo con ObjectSpec.roll: diferencia máxima {string.format("%.2f", M.paridad(60000) * 100)} %`)

-- El jugador lleva lo que saca de verdad de sus mazmorras (rasgo, grado y armadura), no lo que le supone el calendario
-- (con `calendario` al final de la orden, lo del calendario: es con lo que generar.luau saca los precios).
local runs = {}
for index = 1, partidas do
	math.randomseed(1000 + index)
	runs[index] = M.partida({ modo = "comprar", horas = horas, ritmo = ritmo, equipo = equipo, semilla = index })
end

-- Mediana de un hito entre partidas (las que no llegan cuentan como infinito).
local function med(pick): number
	local values = {}
	for _, run in runs do
		table.insert(values, pick(run) or math.huge)
	end
	return mediana(values)
end

print("\n-- Mejoras (mediana; objetivo entre paréntesis) --")
for _, name in Config.UpgradeOrder do
	local upgrade = Config.Upgrades[name]
	local parts = {}
	local step = if upgrade.maxLevel > 12 then 5 else 1
	for level = step, upgrade.maxLevel, step do
		local target = if name == "luck" then objetivo.suerte(level, upgrade.maxLevel) else objetivo.mejoras[name] and objetivo.mejoras[name][level]
		local got = med(function(run)
			return run.compras[name][level]
		end)
		table.insert(parts, `{level}: {tiempo(got)}{if target then ` ({tiempo(target)})` else ""}`)
	end
	print(`{upgrade.name}: {table.concat(parts, " · ")}`)
end

local parts = {}
for count = 1, Config.Rebirth.max do
	table.insert(parts, `{count}: {tiempo(med(function(run)
		return run.renacer[count]
	end))} ({tiempo(objetivo.renacer[count])})`)
end
print(`Renacimientos: {table.concat(parts, " · ")}`)

parts = {}
for index, artifact in Config.Artifacts do
	table.insert(parts, `{artifact.name}: {tiempo(med(function(run)
		return run.accesorios[index]
	end))} ({tiempo(objetivo.accesorios[index])})`)
end
print(`Accesorios: {table.concat(parts, " · ")}`)

print("\n-- Armas: primera de cada nivel --")
parts = {}
for _, limit in { 1e4, 1e6, 1e9, 1e12, 1e15 } do
	table.insert(parts, `1 entre {Format.short(limit)}+: {tiempo(med(function(run)
		return run.armas[limit]
	end))}`)
end
print(table.concat(parts, " · "))
parts = {}
for position = 6, 1, -1 do
	local index = M.pool[position]
	local total = 0
	for _, run in runs do
		total += run.cuenta[index] or 0
	end
	table.insert(parts, `{Config.Swords[index].name} (1 entre {Format.short(Config.Swords[index].rarity)}): 1.ª a {tiempo(med(function(run)
		return run.armas[index]
	end))}, {string.format("%.1f", total / partidas)} por partida`)
end
print(table.concat(parts, "\n"))

print("\n-- Tipos de objeto: cuándo pasan a ser los habituales --")
parts = {}
for index = 2, #Config.Destructibles do
	table.insert(parts, `{Config.Destructibles[index].name}: {tiempo(med(function(run)
		return run.horaTipo[index] and run.horaTipo[index] * 3600
	end))}`)
end
print(table.concat(parts, " · "))

-- Tramo más largo sin ningún hito (compra, renacimiento, accesorio, tipo nuevo o arma de un nivel nuevo).
local huecos, donde = {}, {}
for _, run in runs do
	local hitos = { 0 }
	for _, times in run.compras do
		for _, at in times do
			table.insert(hitos, at)
		end
	end
	for _, at in run.renacer do
		table.insert(hitos, at)
	end
	for _, at in run.accesorios do
		table.insert(hitos, at)
	end
	for _, at in run.armas do
		table.insert(hitos, at)
	end
	for _, hour in run.horaTipo do
		table.insert(hitos, hour * 3600)
	end
	table.sort(hitos)
	local limit = math.min(run.completo or math.huge, horas * 3600)
	local worst, start = 0, 0
	for position = 2, #hitos do
		if hitos[position] <= limit and hitos[position] - hitos[position - 1] > worst then
			worst, start = hitos[position] - hitos[position - 1], hitos[position - 1]
		end
	end
	table.insert(huecos, worst)
	table.insert(donde, start)
end
print(`\nTodo completado (mejoras, renacimientos y accesorios): {tiempo(med(function(run)
	return run.completo
end))}`)
print(`Tramo más largo sin ningún hito: {tiempo(mediana(huecos))} (empieza hacia {tiempo(mediana(donde))})`)

print("\n-- Ritmo --")
parts = {}
for _, hour in { 1, 5, 15, 40, 80, 120, 170, 200 } do
	if hour <= horas then
		local values, coins = {}, {}
		for _, run in runs do
			local now, before = run.ritmo[hour], run.ritmo[hour - 1]
			if now then
				table.insert(values, now.objetos - (if before then before.objetos else 0))
				table.insert(coins, now.monedas - (if before then before.monedas else 0))
			end
		end
		if #values > 0 then
			table.insert(parts, `hora {hour}: {math.round(mediana(values))} objetos y {Format.short(mediana(coins))} monedas`)
		end
	end
end
print(table.concat(parts, "\n"))
local objetos, saltados = 0, 0
for _, run in runs do
	objetos += run.objetos
	saltados += run.saltados
end
print(`Objetos por partida: {Format.short(objetos / partidas)} · dejados por duros: {string.format("%.2f", saltados / math.max(objetos + saltados, 1) * 100)} %`)

-- MAZMORRAS: lo que saca de ellas (y de los cristales de la parcela) frente a lo que le supone el calendario.
local Modifiers = shared("Modifiers")
local maz = objetivo.mazmorra
print(`\n-- Mazmorras y cristales ({maz.parte * 100} % de la sesión en mazmorras; mediana, objetivo entre paréntesis) --`)
-- Las tiradas objetivo de cada hora son las que aseguran (por pity) el rasgo o el grado que el calendario le supone
-- al jugador a esa hora: con el pity que hay, casi todo lo raro sale por pity y no por suerte.
local metas = {} -- [hora] = { rasgo = tiradas, grado = tiradas, armadura = { suerte, ataque, aparición } }
local function meta(hour: number)
	metas[hour] = metas[hour] or {}
	return metas[hour]
end
for _, entry in objetivo.rasgo do
	meta(entry[1]).rasgo = Modifiers.pityLimit("traits", entry[2])
end
for _, entry in objetivo.grado do
	meta(entry[1]).grado = Modifiers.pityLimit("grades", entry[2])
end
for _, entry in objetivo.armadura do
	meta(entry[1]).armadura = { entry[2], entry[3], entry[4] }
end
local horasMeta = {}
for hour in metas do
	if hour < horas then
		table.insert(horasMeta, hour)
	end
end
table.sort(horasMeta)
local function foto(hour: number, pick): number
	return med(function(run)
		local entry = run.maz.fotos[hour]
		return entry and pick(entry)
	end)
end
local function con(value: number, target: number?, format: string): string
	return string.format(format, value) .. (if target then " (" .. string.format(format, target) .. ")" else "")
end
local calidades = Config.Armor.Qualities
for _, hour in horasMeta do
	local target = metas[hour]
	local armor = target.armadura
	local calidad = foto(hour, function(entry)
		return entry.calidad
	end)
	print(`{hour} h: zona {foto(hour, function(entry)
		return entry.zona
	end)} ({string.format("%.0f", foto(hour, function(entry)
		return if entry.segundos == math.huge then 0 else entry.segundos
	end))} s, {foto(hour, function(entry)
		return entry.partidas
	end)} partidas) · rasgo {con(foto(hour, function(entry)
		return entry.rasgo
	end), target.rasgo, "%.0f")} · grado {con(foto(hour, function(entry)
		return entry.grado
	end), target.grado, "%.0f")} · armadura {if calidad >= 1 then calidades[math.round(calidad)].name else "sin"}: suerte +{con(foto(hour, function(entry)
		return entry.armadura[1]
	end), armor and armor[1], "%.2f")}, ataque +{con(foto(hour, function(entry)
		return entry.armadura[2]
	end), armor and armor[2], "%.2f")}, aparición +{con(foto(hour, function(entry)
		return entry.armadura[3]
	end), armor and armor[3], "%.2f")}`)
end

local ultima = horasMeta[#horasMeta]
local function parte(pick): number
	return foto(ultima, pick) * 100
end
print(`De dónde salen (hasta la hora {ultima}): cristales de rasgo, {string.format("%.0f", parte(function(entry)
	return entry.parcela / math.max(entry.rasgo, 1)
end))} % de la parcela y el resto de mazmorras; de grado, {string.format("%.0f", parte(function(entry)
	return entry.desmontar / math.max(entry.grado, 1)
end))} % de desmontar armadura y el resto de los enemigos`)
parts = {}
for quality, info in calidades do
	local total = 0
	for _, run in runs do
		total += run.maz.piezas[quality]
	end
	table.insert(parts, `{info.name} {Format.short(total / partidas)}`)
end
print(`Piezas de armadura por partida: {table.concat(parts, " · ")}`)

-- Cuándo saca por primera vez cada rasgo y cada grado (ese o uno más raro).
local function primero(kind: string, index: number): number
	local list = Modifiers.KINDS[kind].list
	return med(function(run)
		local best = nil
		for other, at in run.maz.primero[kind] do
			if list[other].chance <= list[index].chance and (not best or at < best) then
				best = at
			end
		end
		return best
	end)
end
for _, info in { { kind = "traits", title = "Rasgos", tabla = objetivo.rasgo }, { kind = "grades", title = "Grados", tabla = objetivo.grado } } do
	local list = Modifiers.KINDS[info.kind].list
	local cuando = {}
	for _, entry in info.tabla do
		cuando[entry[2]] = entry[1]
	end
	parts = {}
	for index, entry in list do
		if cuando[index] or index > info.tabla[#info.tabla][2] then
			table.insert(parts, `{entry.name}: {tiempo(primero(info.kind, index))}{if cuando[index] then ` ({tiempo(cuando[index] * 3600)})` else ""}`)
		end
	end
	print(`{info.title} (ese o uno más raro, por primera vez): {table.concat(parts, " · ")}`)
end

-- La escalera de zonas: daño recomendado, cuánto sube de una a la siguiente y cuándo la juega por primera vez.
parts = {}
for index, zona in Config.Dungeons do
	local salto = if index > 1 then ` (x{string.format("%.0f", zona.hp / Config.Dungeons[index - 1].hp)})` else ""
	table.insert(parts, `{zona.name}: daño {Format.short(zona.hp)}{salto}, cristales x{zona.loot}, calidad x{zona.qualityLuck}, 1.ª partida a {tiempo(med(function(run)
		return run.maz.zonas[index]
	end))} ({tiempo(objetivo.mazmorras[index])})`)
end
print("Zonas:\n" .. table.concat(parts, "\n"))

-- Quien deja el personaje en "Auto" y "Repetir" sin parar en la mejor zona que juega al final de la partida: lo que
-- saca en objetivo.bucle.horas (los cristales de grado, contando los de desmontar toda la armadura que cae).
do
	local bucle = objetivo.bucle
	local rasgos, grados, duraciones, zonasFinal = {}, {}, {}, {}
	for _, run in runs do
		local zona, segundos = M.zonaMazmorra(run.dano, run.cooldown, run.area)
		if zona and segundos then
			local botin = M.botinMazmorra(zona)
			local veces = bucle.horas * 3600 / segundos
			table.insert(rasgos, botin.rasgo * veces)
			table.insert(grados, (botin.grado + botin.desmontar) * veces)
			table.insert(duraciones, segundos)
			table.insert(zonasFinal, zona)
		end
	end
	if #rasgos > 0 then
		local rasgo, grado = mediana(rasgos), mediana(grados)
		local ultimoRasgo = Modifiers.pityLimit("traits", #Config.Traits)
		local ultimoGrado = Modifiers.pityLimit("grades", #Config.Grades)
		print(`En bucle sin parar {bucle.horas} h (en {Config.Dungeons[math.round(mediana(zonasFinal))].name}, {string.format("%.0f", mediana(duraciones))} s por partida): {string.format("%.0f", rasgo)} cristales de rasgo ({bucle.rasgo}) y {string.format("%.0f", grado)} de grado ({bucle.grado}) → {Config.Traits[#Config.Traits].name} asegurado en {string.format("%.1f", ultimoRasgo / rasgo * bucle.horas / 24)} días de bucle y {Config.Grades[#Config.Grades].name} en {string.format("%.1f", ultimoGrado / grado * bucle.horas / 24)}`)
	end
end

print("\n-- Con TODA la suerte al máximo (solo sale el tipo más raro y todo cae de un golpe; sin pociones, con el clima que toque): horas por cada arma --")
local dano = med(function(run)
	return run.dano
end)
local hours = M.horasPorArma(math.huge, 6, 40000)
local sinClima = M.horasPorArma(math.huge, 1, 100000, false)[1]
parts = {}
for position = 1, 6 do
	local sword = Config.Swords[M.pool[position]]
	table.insert(parts, `{sword.name} (1 entre {Format.short(sword.rarity)}): {tiempo(hours[position] * 3600)}`)
end
print(table.concat(parts, "\n"))
print(`(objetivo de la más rara: {objetivo.horasArmaTope} h; sin clima saldría cada {string.format("%.0f", sinClima)} h; daño por golpe al final de la partida: {Format.short(dano)})`)

-- Cuántas armas tope toca esperar en una partida entera, y cuánto de eso lo da cada clima.
local top = Config.Swords[M.pool[1]]
local esperado, porClima = 0, {}
for _, run in runs do
	esperado += run.esperadoTope / partidas
	for id, value in run.esperadoClima do
		porClima[id] = (porClima[id] or 0) + value / partidas
	end
end
local climas = {}
for _, id in Config.Weather.Order do
	if (porClima[id] or 0) > esperado * 0.02 then
		table.insert(climas, `{Config.Weather.Events[id].name} {string.format("%.0f", porClima[id] / esperado * 100)} %`)
	end
end
print(`\n{top.name} en una partida de {horas} h: {string.format("%.2f", esperado)} de media. De eso, con clima: {if #climas > 0 then table.concat(climas, ", ") else "nada"}`)
