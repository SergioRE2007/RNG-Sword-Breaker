-- Cuánto se tarda de verdad con el Config que hay: juega varias partidas simuladas del jugador tipo y enseña la
-- mediana de cada hito al lado de su objetivo.
--   lune run tools/equilibrio/informe.luau [partidas] [horas] [ritmo]
-- `ritmo` multiplica lo rápido que rompe el jugador (0.5 = uno lento, 1.5 = uno rápido).
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
local tiempo, mediana = Util.tiempo, Util.mediana

print(`== INFORME: {partidas} partidas de hasta {horas} h, ritmo x{ritmo} ==`)
print(`Paridad del muestreo con ObjectSpec.roll: diferencia máxima {string.format("%.2f", M.paridad(60000) * 100)} %`)

local runs = {}
for index = 1, partidas do
	math.randomseed(1000 + index)
	runs[index] = M.partida({ modo = "comprar", horas = horas, ritmo = ritmo })
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
