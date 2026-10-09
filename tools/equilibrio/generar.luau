-- Saca los números de Config del calendario de tools/equilibrio/objetivo:
--   lune run tools/equilibrio/generar.luau [partidas]            enseña lo que saldría
--   lune run tools/equilibrio/generar.luau [partidas] aplicar    y además lo escribe en src/shared/Config.luau y en
--                                                                src/shared/BalanceSnapshots.luau
--   lune run tools/equilibrio/generar.luau [partidas] mazmorras [aplicar]
--                                                                solo el daño recomendado de las zonas de mazmorra, con
--                                                                el Config que hay (no recalcula vidas ni precios)
-- Calcula: Config.ObjectRolls.TypeLuckPower (para que el arma más rara salga cada `horasArmaTope` con la suerte al
-- máximo), "reward" y "hp" de Config.Destructibles, los "costs" de Config.Upgrades y de Config.Rebirth, "rarity" de
-- Config.Artifacts y el daño recomendado ("hp") de Config.Dungeons.
-- Cómo: juega partidas del jugador tipo que recibe cada compra justo a su hora (modo forzado) y mira cuánto pega
-- cuando cada tipo de objeto pasa a ser el habitual (de ahí las vidas) y cuánto gana entre compra y compra (de ahí los
-- precios). Luego juega partidas comprando de verdad con esos precios y los corrige hasta que cuadran con el calendario.
local fs = require("@lune/fs")
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
local aplicar = table.find(process.args, "aplicar") ~= nil
local soloMazmorras = table.find(process.args, "mazmorras") ~= nil
local horas = objetivo.fotos[#objetivo.fotos]
local mediana, redondo, tiempo = Util.mediana, Util.redondo, Util.tiempo
local tipos = Config.Destructibles

local function med(runs, pick): number
	local values = {}
	for _, run in runs do
		table.insert(values, pick(run) or math.huge)
	end
	return mediana(values)
end

local function jugar(modo: string, semilla: number, opts)
	local runs = {}
	for index = 1, partidas do
		math.randomseed(semilla + index)
		local o = table.clone(opts or {})
		o.modo, o.horas = modo, horas
		runs[index] = M.partida(o)
	end
	return runs
end

-- Números como se escriben en Config: 1200, 3.5e7...
local function numero(value: number): string
	if value < 1e6 then
		return if value % 1 == 0 then string.format("%d", value) else string.format("%.1f", value)
	end
	local exp = math.floor(math.log10(value) + 1e-9)
	local mant = math.round(value / 10 ^ exp * 10) / 10
	if mant >= 10 then
		mant, exp = mant / 10, exp + 1
	end
	return if mant % 1 == 0 then string.format("%de%d", mant, exp) else string.format("%.1fe%d", mant, exp)
end
local function lista(values: { number }): string
	local parts = {}
	for _, value in values do
		table.insert(parts, numero(value))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Mazmorras: daño recomendado de cada zona = el del jugador tipo a su hora, suavizado con el de las zonas vecinas (en
-- escala logarítmica, como los precios). El jugador tipo sube de daño a escalones (un rasgo, un accesorio o un
-- renacimiento a una hora en punto) y sin suavizar la escalera salía a trompicones: un salto de x200 y, detrás, dos
-- zonas casi iguales (x2), que se abrían a la vez. `runs` = partidas del jugador que va justo al ritmo del calendario.
local function escalera(runs): { number }
	local crudo = {}
	for index in Config.Dungeons do
		crudo[index] = med(runs, function(run)
			return run.danoMazmorra[index]
		end)
	end
	local zonas = {}
	for index in Config.Dungeons do
		local value = crudo[index]
		if index > 1 and index < #crudo then
			value = math.exp(0.25 * math.log(crudo[index - 1]) + 0.5 * math.log(value) + 0.25 * math.log(crudo[index + 1]))
		end
		zonas[index] = redondo(value, 1)
		if index > 1 then
			zonas[index] = math.max(zonas[index], zonas[index - 1] * 3)
		end
	end
	return zonas
end
-- La línea de Config de una zona con su daño recomendado nuevo (nil si la línea no es de una zona).
local function lineaZona(line: string, zonas: { number }): string?
	local head, id, tail = string.match(line, '^(%s*{ id = "(%a+)", .-, )hp = [^,]+,(.*)$')
	for index, dungeon in Config.Dungeons do
		if dungeon.id == id then
			return `{head}hp = {numero(zonas[index])},{tail}`
		end
	end
	return nil
end

if soloMazmorras then
	local zonas = escalera(jugar("forzado", 5000))
	for index, dungeon in Config.Dungeons do
		print(`{dungeon.name}: hp = {numero(zonas[index])}{if index > 1 then ` (x{string.format("%.0f", zonas[index] / zonas[index - 1])})` else ""}`)
	end
	if not aplicar then
		print("\n(No se ha escrito nada. Añade `aplicar` para escribirlo en Config.)")
		return
	end
	local path = "src/shared/Config.luau"
	local lines = string.split(fs.readFile(path), "\n")
	local changed = 0
	for position, line in lines do
		local new = lineaZona(line, zonas)
		if new then
			lines[position] = new
			changed += 1
		end
	end
	assert(changed == #Config.Dungeons, `esperaba cambiar {#Config.Dungeons} líneas de Config y han sido {changed}`)
	fs.writeFile(path, table.concat(lines, "\n"))
	print(`\nEscrito: {changed} líneas de {path}.`)
	return
end

-- Pistas de compra: cada mejora de Config.UpgradeOrder con calendario y los renacimientos.
local pistas = {} -- [pista] = { segundos objetivo de cada nivel }
pistas.luck = {}
for level = 1, Config.Upgrades.luck.maxLevel do
	pistas.luck[level] = objetivo.suerte(level, Config.Upgrades.luck.maxLevel)
end
for name, times in objetivo.mejoras do
	assert(Config.Upgrades[name], "objetivo.mejoras habla de una mejora que no existe: " .. name)
	assert(#times == Config.Upgrades[name].maxLevel, "objetivo.mejoras." .. name .. " no tiene un tiempo por nivel")
	pistas[name] = times
end
for _, name in Config.UpgradeOrder do
	assert(pistas[name], "falta el calendario de la mejora " .. name .. " en objetivo.mejoras")
end
assert(#objetivo.renacer == Config.Rebirth.max, "objetivo.renacer no tiene un tiempo por renacimiento")
pistas.rebirth = objetivo.renacer

local costes = {}
local function ponerCostes()
	for pista, list in costes do
		-- En las pistas largas se suaviza cada precio con sus vecinos (en escala logarítmica): los escalones del
		-- jugador tipo (el rasgo o la armadura que le cambian a una hora en punto) no tienen por qué verse en los precios.
		local smooth = table.clone(list)
		if #list > 12 then
			for level = 2, #list - 1 do
				smooth[level] = math.exp(0.25 * math.log(list[level - 1]) + 0.5 * math.log(list[level]) + 0.25 * math.log(list[level + 1]))
			end
		end
		local rounded = {}
		for level, cost in smooth do
			-- Siempre crecientes y con dos cifras.
			local value = math.max(redondo(cost, 2), 1)
			if level > 1 then
				value = math.max(value, redondo(rounded[level - 1] * 1.15, 2))
			end
			rounded[level] = value
		end
		if pista == "rebirth" then
			Config.Rebirth.costs = rounded
		else
			Config.Upgrades[pista].costs = rounded
		end
	end
end

-- 0. Premios: base * rareza ^ potencia.
for _, def in tipos do
	if def.reward > 0 then
		def.reward = math.max(redondo(objetivo.premio.base * def.rarity ^ objetivo.premio.potencia, 2), 1)
	end
end

-- 1. Suerte del tipo. "Con toda la suerte al máximo" es el caso más favorable: un jugador al que solo le sale el tipo
-- más raro y que lo tumba todo de un golpe (rompe todo lo que aparece), con los cinco renacimientos, sin pociones y con
-- el clima que vaya tocando. No depende de lo que valgan las vidas, así que se resuelve primero: las horas van con 1 / rareza ^ TypeLuckPower.
local function horasTope(): number
	return M.horasPorArma(math.huge, 1, 40000)[1]
end
local rarest = tipos[#tipos].rarity
for _ = 1, 4 do
	local power = Config.ObjectRolls.TypeLuckPower - math.log(objetivo.horasArmaTope / horasTope()) / math.log(rarest)
	Config.ObjectRolls.TypeLuckPower = math.round(power * 1000) / 1000
end
print(`TypeLuckPower {Config.ObjectRolls.TypeLuckPower}: arma tope cada {string.format("%.0f", horasTope())} h con toda la suerte al máximo`)

-- 2. Vidas, con el jugador que va justo al ritmo del calendario: cada tipo vale sus golpes por lo que pega el jugador
-- cuando ese tipo empieza a salirle a menudo (objetivo.golpes.parte). Mientras un tipo aún es más raro que eso, en las
-- pasadas de calibrar su vida se estima con la potencia con la que crece el daño frente a la suerte (`potencias`).
local potencias = table.create(#tipos, 0.6)
local function ponerVidas(runs, mezcla: boolean?)
	local final = med(runs, function(run)
		return run.dano
	end)
	local suerte = med(runs, function(run)
		return run.suerte
	end)
	local danos = { 1 } -- daño cuando cada tipo empieza a salir a menudo (el primero, con la espada inicial)
	for index = 2, #tipos do
		local dano = med(runs, function(run)
			return run.danoTipo[index]
		end)
		if dano == math.huge then
			-- Al jugador tipo no llega a salirle a menudo: desde el final de la partida, con la última potencia medida.
			local desde = math.max(index - 2, 1)
			potencias[index] = potencias[index - 1]
			if danos[index - 1] ~= final and suerte > tipos[desde].rarity * 10 then
				potencias[index] = math.clamp(math.log(final / danos[desde]) / math.log(suerte / tipos[desde].rarity), 0.3, 1.2)
			end
			dano = final * math.max(tipos[index].rarity * objetivo.golpes.parte / suerte, 1) ^ potencias[index]
		else
			local desde = math.max(index - 2, 1)
			potencias[index] = math.clamp(math.log(dano / danos[desde]) / math.log(tipos[index].rarity / tipos[desde].rarity), 0.3, 1.2)
		end
		danos[index] = dano
		local hp = M.golpes(index) * dano
		if mezcla then
			hp = math.sqrt(hp * tipos[index].hp) -- a medio camino de la vida anterior, para que no oscile
		end
		tipos[index].hp = math.max(redondo(hp, 2), redondo(tipos[index - 1].hp * 1.2, 2))
	end
end
-- Dos pasadas con las vidas calibradas sobre la marcha (la primera mide las potencias) y dos con las vidas ya de la
-- tabla, que es lo que se va a encontrar el jugador: de la última salen también precios, accesorios y mazmorras.
local runs
for pasada = 1, 4 do
	runs = jugar("forzado", 5000, if pasada <= 2 then { calibrar = table.clone(potencias) } else nil)
	if pasada < 4 then
		ponerVidas(runs, pasada == 3)
	end
	print(`pasada {pasada}: daño al final {Format.short(med(runs, function(run)
		return run.dano
	end))}, objetos {Format.short(med(runs, function(run)
		return run.objetos
	end))}, dejados {Format.short(med(runs, function(run)
		return run.saltados
	end))}`)
end

-- 3. Precios: lo que gana el jugador tipo entre compra y compra, repartido entre las pistas que le quedan abiertas.
do
	local eventos = runs[1].eventos
	local quedan, botes = {}, {}
	for pista, list in pistas do
		quedan[pista] = #list
		botes[pista] = 0
		costes[pista] = {}
	end
	local antes = 0
	for position, evento in eventos do
		local ganado = med(runs, function(run)
			return run.eventos[position].monedas
		end)
		local peso = 0
		for pista, left in quedan do
			if left > 0 then
				peso += objetivo.reparto[pista]
			end
		end
		for pista, left in quedan do
			if left > 0 then
				botes[pista] += (ganado - antes) * objetivo.reparto[pista] / peso
			end
		end
		antes = ganado
		table.insert(costes[evento.pista], botes[evento.pista])
		botes[evento.pista] = 0
		quedan[evento.pista] -= 1
	end
end
ponerCostes()

-- 4. Accesorios: rareza para que la mitad de los jugadores lo tenga a su hora (le caen con suerte / rareza por objeto).
for index, artifact in Config.Artifacts do
	local suma = med(runs, function(run)
		return run.lambda[index]
	end)
	artifact.rarity = redondo(suma / math.log(2), 2)
	if index > 1 then
		artifact.rarity = math.max(artifact.rarity, redondo(Config.Artifacts[index - 1].rarity * 1.5, 2))
	end
end

-- 5. Mazmorras: daño recomendado (ver `escalera`).
local mazmorras = escalera(runs)
local forzadas = runs

-- 6. Comprobación comprando de verdad, y corrección de los precios tramo a tramo.
local function comprado(run, pista: string, level: number): number?
	return (if pista == "rebirth" then run.renacer else run.compras[pista])[level]
end
local VUELTAS = 10
for vuelta = 1, VUELTAS do
	runs = jugar("comprar", 9000)
	local peor, cual = 0, ""
	local nuevos = {}
	for pista, list in costes do
		nuevos[pista] = table.clone(list)
		list = nuevos[pista]
		local antesT, antesS = 0, 0
		for level, cost in list do
			local T = pistas[pista][level]
			local S = med(runs, function(run)
				return comprado(run, pista, level)
			end)
			if S == math.huge then
				list[level] = cost * 0.5
				S = antesS + (T - antesT) * 2
				peor, cual = math.huge, `{pista} {level}`
			else
				list[level] = cost * math.clamp((T - antesT) / math.max(S - antesS, 1e-6), 0.5, 2) ^ 0.8
				if T > 600 and math.abs(math.log(S / T)) > peor then
					peor, cual = math.abs(math.log(S / T)), `{pista} {level}`
				end
			end
			antesT, antesS = T, S
		end
	end
	print(`vuelta {vuelta}: mayor desvío {if peor == math.huge then "no llega" else string.format("%.0f %%", (math.exp(peor) - 1) * 100)} ({cual})`)
	if peor < 0.12 or vuelta == VUELTAS then
		break
	end
	costes = nuevos
	ponerCostes()
end

-- 7. Resultado.
print(`\nTypeLuckPower = {Config.ObjectRolls.TypeLuckPower}`)
for _, def in tipos do
	print(`{def.name}: hp = {numero(def.hp)}, reward = {numero(def.reward)}`)
end
for _, name in Config.UpgradeOrder do
	print(`{name}.costs = {lista(Config.Upgrades[name].costs)}`)
end
print(`Rebirth.costs = {lista(Config.Rebirth.costs)}`)
for _, artifact in Config.Artifacts do
	print(`{artifact.name}: rarity = {numero(artifact.rarity)}`)
end
for index, dungeon in Config.Dungeons do
	print(`{dungeon.name}: hp = {numero(mazmorras[index])}`)
end
print("\nCompras con estos precios (mediana; objetivo entre paréntesis):")
for pista, list in pistas do
	local parts = {}
	local step = if #list > 12 then 5 else 1
	for level = step, #list, step do
		table.insert(parts, `{level}: {tiempo(med(runs, function(run)
			return comprado(run, pista, level)
		end))} ({tiempo(list[level])})`)
	end
	print(`{pista}: {table.concat(parts, " · ")}`)
end

if not aplicar then
	print("\n(No se ha escrito nada. Añade `aplicar` para escribirlo en Config y en BalanceSnapshots.)")
	return
end

-- 8. Escribir en Config.luau: solo cambian los números de las líneas que tocan.
local path = "src/shared/Config.luau"
local lines = string.split(fs.readFile(path), "\n")
local byName, artifactByName = {}, {}
for _, def in tipos do
	byName[def.name] = def
end
for _, artifact in Config.Artifacts do
	artifactByName[artifact.name] = artifact
end
local changed = 0
local function costsField(text: string, costs: { number }): string
	local value = "costs = " .. lista(costs) .. ","
	local replaced, count = string.gsub(text, "costs = %b{},", function()
		return value
	end, 1)
	if count == 0 then
		replaced, count = string.gsub(text, "cost = [^,]+, growth = [^,]+,", function()
			return value
		end, 1)
	end
	assert(count == 1, "no encuentro el precio en: " .. string.sub(text, 1, 60))
	return replaced
end
for position, line in lines do
	local head, name, tail = string.match(line, '^(%s*{ name = "(.-)", rarity = [^,]+, )hp = [^,]+, reward = [^,]+,(.*)$')
	if name and byName[name] then
		lines[position] = `{head}hp = {numero(byName[name].hp)}, reward = {numero(byName[name].reward)},{tail}`
		changed += 1
	end
	head, name, tail = string.match(line, '^(%s*{ name = "(.-)", stat = "%a+", mult = [^,]+, )rarity = [^,]+,(.*)$')
	if name and artifactByName[name] then
		lines[position] = `{head}rarity = {numero(artifactByName[name].rarity)},{tail}`
		changed += 1
	end
	local key = string.match(line, '^%s*(%a+) = { name = "')
	-- (Solo las líneas de Config.Upgrades: "luck" es también un stat de la armadura.)
	if key and Config.Upgrades[key] and Config.Upgrades[key].costs and string.find(line, "maxLevel = ", 1, true) then
		lines[position] = costsField(line, Config.Upgrades[key].costs)
		changed += 1
	end
	if string.match(line, "^Config%.Rebirth = {") then
		lines[position] = costsField(line, Config.Rebirth.costs)
		changed += 1
	end
	head, tail = string.match(line, "^(%s*TypeLuckPower = )[^,]+,(.*)$")
	if head then
		lines[position] = `{head}{Config.ObjectRolls.TypeLuckPower},{tail}`
		changed += 1
	end
	local zona = lineaZona(line, mazmorras)
	if zona then
		lines[position] = zona
		changed += 1
	end
end
local expected = #tipos + #Config.Artifacts + #Config.UpgradeOrder + 1 + 1 + #Config.Dungeons
assert(changed == expected, `esperaba cambiar {expected} líneas de Config y han sido {changed}`)
fs.writeFile(path, table.concat(lines, "\n"))

-- 9. Estados del jugador tipo a cada hora (Config.Test.Progress): los de la partida forzada de daño mediano.
table.sort(forzadas, function(x, y)
	return x.dano < y.dano
end)
local tipo = forzadas[math.ceil(#forzadas / 2)]
local out = {
	"-- ARCHIVO GENERADO por tools/equilibrio/generar.luau: no lo edites a mano.",
	"-- Cómo va el jugador tipo del calendario de progreso a cada hora de juego: lo usa Config.Test.Progress (solo en",
	"-- Studio) para empezar una partida en esa etapa. `armor` = { suerte, ataque, aparición } que suma su armadura.",
	"return {",
}
for _, hour in objetivo.fotos do
	local foto = tipo.fotos[hour]
	if foto then
		local upgrades = {}
		for _, name in Config.UpgradeOrder do
			table.insert(upgrades, `{name} = {foto.upgrades[name]}`)
		end
		local zona = 0
		for _, at in objetivo.mazmorras do
			if at <= hour * 3600 then
				zona += 1
			end
		end
		table.insert(out, `	\{ hours = {hour}, upgrades = \{ {table.concat(upgrades, ", ")} }, rebirths = {foto.rebirths}, sword = {foto.sword}, metal = {foto.metal}, size = {foto.size}, trait = {foto.trait}, grade = {foto.grade}, artifacts = \{ {table.concat(foto.artifacts, ", ")} }, gear = \{ {table.concat(foto.gear, ", ")} }, dungeon = {math.max(zona, 1)}, armor = \{ {foto.armadura[1]}, {foto.armadura[2]}, {foto.armadura[3]} } },`)
	end
end
table.insert(out, "}")
fs.writeFile("src/shared/BalanceSnapshots.luau", table.concat(out, "\n") .. "\n")
print(`\nEscrito: {changed} líneas de {path} y src/shared/BalanceSnapshots.luau. Daño del jugador tipo al final: {Format.short(tipo.dano)}`)
