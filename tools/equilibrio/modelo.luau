-- Partida simulada del "jugador tipo" de tools/equilibrio/objetivo con los números y las cuentas de verdad del juego
-- (Config, ObjectSpec, Permanent, Upgrades y Stats, cargados por `cargar`). Rompe objetos uno a uno: tipo, rareza y
-- tamaño, golpes, monedas, tiradas de arma, accesorios y compras, con el reloj avanzando lo que tarda en romper cada uno.
-- Las tiradas repiten las del servidor (Destructibles.rollDef, ObjectSpec.roll, Gacha y Gear) con un solo número al azar
-- por tirada en vez de una cadena de Chance.roll, que es lo mismo y mucho más rápido; `paridad` lo comprueba.
local Modelo = {}

local H = 3600
local random = math.random

function Modelo.nuevo(shared, mundo, objetivo)
	local Config = shared("Config")
	local ObjectSpec = shared("ObjectSpec")
	local Permanent = shared("Permanent")
	local Stats = shared("Stats")
	local Upgrades = shared("Upgrades")
	local WeatherInfo = shared("WeatherInfo")
	local Modifiers = shared("Modifiers")
	local ArmorStats = shared("ArmorStats")

	local M = {}

	local tipos = Config.Destructibles
	local rarezas = Config.ObjectRarities
	local tamanos = Config.ObjectSizes
	local LOWEST, HIGHEST = math.huge, 0
	for _, size in tamanos do
		LOWEST = math.min(LOWEST, size.min)
		HIGHEST = math.max(HIGHEST, size.max)
	end

	-- Armas del gacha, de la más rara a la más común (como server/Gacha).
	local pool = {}
	for index, sword in Config.Swords do
		if sword.rarity then
			table.insert(pool, index)
		end
	end
	table.sort(pool, function(a, b)
		return Config.Swords[a].rarity > Config.Swords[b].rarity
	end)
	M.pool = pool

	-- Posición en `list` de lo que toca con probabilidad suerte / odds, probando del final al principio; `first` si nada.
	local function cascada(list, luck: number, first: number, dado: number?): number
		local u = dado or random()
		for index = #list, first + 1, -1 do
			local p = luck / list[index].odds
			if p >= 1 or u < p then
				return index
			end
			u = (u - p) / (1 - p)
		end
		return first
	end

	-- Lo que le toca a un objeto de ese tipo (igual que ObjectSpec.roll): rareza, tamaño, escala y tiradas.
	local function tirarObjeto(def, luck: number): (number, number, number, number)
		local quality = cascada(rarezas, luck * (def.rarityLuck or 1), 1)
		if def.minRarity and quality < def.minRarity then
			quality = def.minRarity
		end
		local rarity = rarezas[quality]
		local sizeLuck = luck * rarity.sizeLuck * (def.sizeLuck or 1)
		local size = 1
		local u = random()
		for index = #tamanos, 2, -1 do
			local entry = tamanos[index]
			local p = (if entry.min >= 1 then sizeLuck else 1) / entry.odds
			if p >= 1 or u < p then
				size = index
				break
			end
			u = (u - p) / (1 - p)
		end
		local class = tamanos[size]
		local scale = class.min + random() * (class.max - class.min)
		local lowest, highest = ObjectSpec.scaleLimits(def)
		if scale > 1 then
			scale = 1 + (scale - 1) * (highest - 1) / (HIGHEST - 1)
		elseif LOWEST < 1 then
			scale = 1 - (1 - scale) * (1 - lowest) / (1 - LOWEST)
		end
		scale = math.round(scale * 100) / 100
		local amount = rarity.rolls + class.rolls + (def.rolls or 0)
		local rolls = math.floor(amount)
		if amount > rolls and random() < amount - rolls then
			rolls += 1
		end
		return quality, size, scale, math.clamp(rolls, 0, Config.ObjectRolls.MaxRolls)
	end

	-- Compara las medias del muestreo rápido con las de ObjectSpec.roll de verdad. Devuelve la mayor diferencia (0.01 = 1 %).
	function M.paridad(samples: number): number
		local worst = 0
		for _, index in { 1, math.ceil(#tipos / 2), #tipos } do
			local def = tipos[index]
			local a, b = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
			for _ = 1, samples do
				local spec = ObjectSpec.roll(def, 1)
				a[1] += math.log(spec.luck)
				a[2] += math.log(spec.hp)
				a[3] += spec.rolls
				a[4] += spec.quality
				local quality, _, scale, rolls = tirarObjeto(def, 1)
				b[1] += math.log(ObjectSpec.luck(def, quality, scale))
				b[2] += math.log(ObjectSpec.hp(def, quality, scale))
				b[3] += rolls
				b[4] += quality
			end
			for field = 1, 4 do
				worst = math.max(worst, math.abs(a[field] - b[field]) / math.max(math.abs(a[field]), samples))
			end
		end
		return worst
	end

	-- Golpes que pide un objeto corriente del tipo `index` cuando empieza a salir a menudo (objetivo.golpes).
	function M.golpes(index: number): number
		return objetivo.golpes.inicio + (objetivo.golpes.final - objetivo.golpes.inicio) * (index - 1) / (#tipos - 1)
	end

	-- Objetos que se lleva por delante cada espadazo con la parcela llena: más cuantos más quepan en ella.
	function M.porGolpe(capacity: number): number
		return 1 + objetivo.jugador.densidad * (capacity - 1)
	end

	-- MAZMORRAS (server/Dungeons, server/Loot y server/Armor). Enemigos de cada oleada de cada zona, ya con su "count".
	local zonas = Config.Dungeons
	local armadura = Config.Armor
	local maz = objetivo.mazmorra
	local oleadas = {}
	for index, zona in zonas do
		local theme = Config.DungeonThemes[zona.id]
		oleadas[index] = {}
		for _, wave in (theme and theme.waves) or Config.Dungeon.Waves do
			local entries = {}
			for _, entry in wave do
				local def = Config.Enemies[entry[1]]
				if def then
					table.insert(entries, { def = def, n = if def.scaleCount == false then entry[2] else math.ceil(entry[2] * zona.count) })
				end
			end
			table.insert(oleadas[index], entries)
		end
	end
	local pesoMods = 0
	for _, mod in armadura.Mods do
		pesoMods += mod.chance
	end

	-- Segundos que tarda en una partida de la zona `index` (de una a la siguiente) pegando `dano` cada `cooldown`
	-- segundos, o nil si no le da tiempo a acabarla. `area` = lleva un arma que pega alrededor (martillo, hacha).
	-- Medido en Studio con el personaje en Auto (ver objetivo.mazmorra): los enemigos se le echan encima en piña, así
	-- que cada espadazo se lleva a todos los de un tipo a la vez. Con un arma de área caen todos los tipos juntos (la
	-- oleada dura los golpes del más duro); con una de frente va un tipo detrás de otro (se suman).
	function M.duracionMazmorra(index: number, dano: number, cooldown: number, area: boolean?): number?
		local zona = zonas[index]
		local pelea = 0
		for _, wave in oleadas[index] do
			local suma, mayor = 0, 0
			for _, entry in wave do
				local hits = math.max(1, math.ceil(entry.def.hp * zona.hp / dano - 1e-9))
				suma += hits
				mayor = math.max(mayor, hits)
			end
			pelea += Config.Dungeon.WaveDelay + maz.oleada + (if area then mayor else suma) * cooldown
		end
		if pelea > Config.Dungeon.TimeLimit then
			return nil
		end
		return pelea + maz.entrada
	end

	-- Zona que juega y lo que tarda en cada partida: la más alta que termina en `comoda` segundos (la primera, en lo
	-- que tarde). nil si aún no puede con ninguna.
	function M.zonaMazmorra(dano: number, cooldown: number, area: boolean?): (number?, number?)
		local zona, segundos = nil, nil
		for index = 1, #zonas do
			local d = M.duracionMazmorra(index, dano, cooldown, area)
			if d and (d <= maz.comoda or index == 1) then
				zona, segundos = index, d
			end
		end
		return zona, segundos
	end

	-- Lo que da de media una partida de esa zona: cristales de rasgo y de grado que sueltan los enemigos y el final,
	-- piezas de armadura que caen y cristales de grado que salen de desmontarlas todas.
	function M.botinMazmorra(index: number): { rasgo: number, grado: number, piezas: number, desmontar: number }
		local sum = { rasgo = 0, grado = 0, piezas = 0, desmontar = 0 }
		-- Cristales que da de media desmontar una pieza que cae con esa suerte de calidad.
		local function valorPieza(luck: number): number
			local left, total = 1, 0
			for quality = #armadura.Qualities, 1, -1 do
				local p = math.min(1, luck / armadura.Qualities[quality].odds)
				total += left * p * armadura.Qualities[quality].value
				left *= 1 - p
			end
			return total
		end
		local function cuenta(drops, veces: number)
			for _, drop in drops do
				local chance = math.min(drop.chance or 1, 1) * veces
				if drop.kind == "armor" then
					sum.piezas += chance
					sum.desmontar += chance * valorPieza(zonas[index].qualityLuck * (drop.luck or 1))
				elseif drop.kind == "item" then
					local amount = chance * math.max(((drop.min or 1) + (drop.max or 1)) / 2 * zonas[index].loot, 1)
					if drop.item == "traitCrystal" then
						sum.rasgo += amount
					elseif drop.item == "gradeCrystal" then
						sum.grado += amount
					end
				end
			end
		end
		for _, wave in oleadas[index] do
			for _, entry in wave do
				cuenta(entry.def.drops, entry.n)
			end
		end
		cuenta(Config.Dungeon.ClearDrops, 1)
		return sum
	end

	-- Climas con su probabilidad real por tramo.
	local climas = {}
	for _, id in Config.Weather.Order do
		table.insert(climas, { id = id, chance = WeatherInfo.chance(id) })
	end
	local function tirarClima(): string
		local u = random()
		for _, entry in climas do
			u -= entry.chance
			if u < 0 then
				return entry.id
			end
		end
		return climas[1].id
	end

	-- opts: modo = "comprar" (compra con los precios de Config en cuanto puede y los accesorios le caen al azar) o
	-- "forzado" (recibe cada compra y cada accesorio en su hora de `objetivo`, gratis: es el jugador que va justo al
	-- ritmo del calendario, y de lo que gana entre compra y compra salen los precios); horas; clima (false = sin clima);
	-- calibrar = { [tipo] = potencia } (las vidas no salen de Config: cada tipo vale sus golpes de `objetivo` por el
	-- daño del jugador en el momento en que empieza a salirle a menudo (objetivo.golpes.parte de sus objetos), y antes
	-- de eso se estima con daño de ahora * (lo que le falta a la suerte) ^ potencia; así se sacan las vidas de Config);
	-- ritmo (multiplica su eficiencia); equipo = "calendario" (lleva el rasgo, el grado y la armadura que le suponen las
	-- tablas de `objetivo` a cada hora; es lo que hay si no se pone) o "mazmorras" (lleva lo que saca de verdad de sus
	-- partidas de mazmorra y de los cristales); semilla (del azar de las mazmorras);
	-- sinSuerte (no compra la mejora de suerte); rasgo y grado (los lleva desde el principio); parar (acaba en cuanto
	-- lo tiene todo: mejoras, renacimientos y accesorios).
	function M.partida(opts)
		local forzado = opts.modo == "forzado"
		local fin = opts.horas * H
		local jugador = objetivo.jugador
		local eficiencia = jugador.eficiencia * (opts.ritmo or 1)
		local paseo, paciencia = jugador.paseo, jugador.paciencia
		local calibrar = opts.calibrar

		local attrs = {}
		local player = {
			GetAttribute = function(_, name)
				return attrs[name]
			end,
		}
		local estado = {
			coins = 0,
			upgrades = {},
			rebirths = 0,
			artifacts = {},
			gear = {},
			sword = 1,
			metal = 0,
			size = 0,
			trait = opts.rasgo or 0,
			grade = opts.grado or 0,
			armadura = { 0, 0, 0 },
		}
		for _, name in Config.UpgradeOrder do
			estado.upgrades[name] = 0
		end

		-- MAZMORRAS Y CRISTALES. Azar aparte: no gasta números del de la parcela, así que una partida con el equipo del
		-- calendario sale igual se cuenten o no las mazmorras.
		local semilla = 20261009 + (opts.semilla or 0) * 7919
		local function azar(): number
			semilla = (semilla * 48271) % 2147483647
			return semilla / 2147483647
		end
		local dado = {
			NextNumber = function()
				return azar()
			end,
		}
		local equipoReal = opts.equipo == "mazmorras"
		local pity = Modifiers.newPity(nil)
		local prioridad = Modifiers.PRIORITY
		local mejor = { traits = 0, grades = 0 } -- lo más raro que ha sacado de cada cosa
		local puesto = {} -- [hueco] = pieza de armadura que lleva
		local mazZona, mazDur, presupuesto, mazSucio = nil, math.huge, 0, false
		local area = false -- lleva un arma de área (martillo o hacha)
		local mazParte = maz.parte * maz.atencion * (opts.ritmo or 1)
		local cristalParcela = Config.Items.traitCrystal.dropChance or 0

		local res = {
			-- Mazmorras: partidas jugadas, tiradas hechas de rasgo y de grado, cristales de rasgo que salieron de la
			-- parcela y de grado que salieron de desmontar, piezas caídas por calidad, segundo en que sacó por primera
			-- vez cada rasgo y cada grado, segundo de la primera partida de cada zona y cómo iba a cada hora.
			maz = { partidas = 0, tiradas = { traits = 0, grades = 0 }, parcela = 0, desmontar = 0, piezas = table.create(#armadura.Qualities, 0), primero = { traits = {}, grades = {} }, zonas = {}, fotos = {} },
			compras = {}, -- [mejora] = { segundo de cada nivel }
			renacer = {},
			accesorios = {}, -- [índice] = segundo
			armas = {}, -- [umbral de rareza] = segundo de la primera
			cuenta = {}, -- [índice de arma] = cuántas (solo las de 1 entre 1e15 o más)
			eventos = {}, -- (forzado) { t, pista, monedas ganadas hasta entonces }
			danoTipo = {}, -- [tipo] = daño por golpe cuando empieza a salir a menudo (objetivo.golpes.parte)
			horaTipo = {},
			lambda = {}, -- (forzado) [accesorio] = suma de suerte de los objetos rotos hasta su hora
			danoMazmorra = {},
			fotos = {},
			ritmo = {}, -- { hora, objetos, monedas } cada hora en punto
		}
		for _, name in Config.UpgradeOrder do
			res.compras[name] = {}
		end

		-- Estadísticas del jugador, con Stats de verdad sobre sus atributos.
		local luck, typeLuck, objectLuck, damage, coinMult, gacha, spawnTime, cooldown, porGolpe
		local bestDamage = Config.Swords[1].damage
		local parte = objetivo.golpes.parte
		local nextTipo, habitual = 2, 2
		local t = 0
		local function equipar()
			-- El mejor de suerte, el mejor de daño y el mejor de monedas; si sobra hueco, lo que más multiplique.
			local chosen, used = {}, {}
			local function best(stat: string?)
				local pick = nil
				for _, index in estado.artifacts do
					local artifact = Config.Artifacts[index]
					if not used[index] and artifact.stat ~= "gems" and (not stat or artifact.stat == stat) then
						if not pick or artifact.mult > Config.Artifacts[pick].mult then
							pick = index
						end
					end
				end
				if pick and #chosen < Config.GearSlots then
					used[pick] = true
					table.insert(chosen, pick)
				end
			end
			best("luck")
			best("damage")
			best("coins")
			while #chosen < Config.GearSlots and #chosen < #estado.artifacts do
				local before = #chosen
				best(nil)
				if #chosen == before then
					break
				end
			end
			estado.gear = chosen
		end
		local function recalcular()
			attrs.Swords = `1:{estado.sword}:{estado.trait}:{estado.grade}:{estado.metal}:{estado.size}`
			attrs.Equipped = 1
			attrs.Gear = table.concat(estado.gear, ",")
			attrs.Rebirths = estado.rebirths
			for name, level in estado.upgrades do
				attrs["Upgrade_" .. name] = level
			end
			attrs.Armor_luck, attrs.Armor_damage, attrs.Armor_rollSpeed = estado.armadura[1], estado.armadura[2], estado.armadura[3]
			luck = Stats.luck(player)
			typeLuck = luck * Stats.spawnLuck(player)
			objectLuck = Stats.objectLuck(player)
			damage = Stats.damage(player)
			coinMult = Stats.coins(player)
			gacha = Stats.gachaLuck(player)
			spawnTime = Stats.spawnTime(player)
			cooldown = Stats.cooldown(player)
			porGolpe = M.porGolpe(Upgrades.value("capacity", estado.upgrades.capacity or 0))
			local _, kind = Stats.weapon(player)
			area = kind.arc <= 0
			local zona, segundos = M.zonaMazmorra(damage, cooldown, area)
			mazZona, mazDur, mazSucio = zona, segundos or math.huge, false
			if not zona then
				presupuesto = 0
			end
			-- Tipos que empiezan a salir a menudo (la suerte llega a `parte` de su rareza): se apunta el daño de ese
			-- momento, que es con el que se mide su vida. Y cuándo pasan a ser los habituales (la suerte llega a su rareza).
			while nextTipo <= #tipos and luck >= tipos[nextTipo].rarity * parte do
				res.danoTipo[nextTipo] = damage
				nextTipo += 1
			end
			while habitual <= #tipos and luck >= tipos[habitual].rarity do
				res.horaTipo[habitual] = t / H
				habitual += 1
			end
		end

		-- Agenda: lo que pasa a una hora fija (lo que lleva puesto y, en modo forzado, compras y accesorios).
		local agenda = {}
		local function a(at: number, fn)
			table.insert(agenda, { t = at, fn = fn })
		end
		if not equipoReal then
			for _, entry in objetivo.rasgo do
				a(entry[1] * H, function()
					estado.trait = math.max(estado.trait, entry[2])
				end)
			end
			for _, entry in objetivo.grado do
				a(entry[1] * H, function()
					estado.grade = math.max(estado.grade, entry[2])
				end)
			end
			for _, entry in objetivo.armadura do
				a(entry[1] * H, function()
					estado.armadura = { entry[2], entry[3], entry[4] }
				end)
			end
		end

		-- Tiradas de rasgo o de grado con los cristales que le llegan (los gasta según caen), con el pity de verdad.
		local function tirar(kind: string, cristales: number)
			local info = Modifiers.KINDS[kind]
			local mz = res.maz
			local veces = math.floor(cristales / info.cost)
			if mz.tiradas[kind] > 300000 then
				-- Con tantas ya lo ha sacado todo (el pity más largo no llega a 70 000): solo se cuentan.
				mz.tiradas[kind] += veces
				return
			end
			for _ = 1, veces do
				local result = Modifiers.rollWithPity(kind, dado, 1, pity[kind], prioridad)
				mz.tiradas[kind] += 1
				if not mz.primero[kind][result] then
					mz.primero[kind][result] = t
				end
				if mejor[kind] == 0 or Modifiers.better(kind, result, mejor[kind], prioridad) then
					mejor[kind] = result
					if equipoReal then
						estado[info.field] = result
						mazSucio = true
					end
				end
			end
		end
		local function totales(): { number }
			local sum = { 0, 0, 0 }
			for _, piece in puesto do
				sum[1] += piece.luck
				sum[2] += piece.damage
				sum[3] += piece.rollSpeed
			end
			return sum
		end
		local function desmontar(piece)
			local cristales = ArmorStats.salvage(piece)
			res.maz.desmontar += cristales
			tirar("grades", cristales)
		end
		-- Pieza de armadura (server/Armor.roll). Se pone en cada hueco la que más le vale (abajo) y desmonta todas las demás.
		local function pieza(index: number, luck: number)
			local slot = armadura.SlotOrder[1 + math.floor(azar() * #armadura.SlotOrder)]
			local q = cascada(armadura.Qualities, luck, 1, azar())
			local quality = armadura.Qualities[q]
			res.maz.piezas[q] += 1
			local piece = { quality = q, level = index, luck = 0, damage = 0, rollSpeed = 0 }
			local function suma(stat: string, base: number)
				if stat ~= "health" then
					piece[stat] += base * (armadura.Roll.min + azar() * (armadura.Roll.max - armadura.Roll.min)) * quality.mult * ArmorStats.scaling(stat, index)
				end
			end
			for _, stat in armadura.StatOrder do
				local base = armadura.Slots[slot].stats[stat]
				if base then
					suma(stat, base)
				end
			end
			for _ = 1, quality.mods do
				local pick = azar() * pesoMods
				for _, mod in armadura.Mods do
					pick -= mod.chance
					if pick < 0 then
						suma(mod.stat, mod.value)
						break
					end
				end
			end
			-- Lo que le vale una pieza: lo que sube cada cosa en proporción a lo que ya suman los otros huecos (un 10 % más
			-- de objetos le cunde más que un 10 % más de suerte o de daño).
			local luckNow, damageNow, speedNow = 1, 1, 1
			for other, wornPiece in puesto do
				if other ~= slot then
					luckNow += wornPiece.luck
					damageNow += wornPiece.damage
					speedNow += wornPiece.rollSpeed
				end
			end
			local function valor(candidate): number
				return candidate.rollSpeed / speedNow + 0.75 * (candidate.luck / luckNow + candidate.damage / damageNow)
			end
			local worn = puesto[slot]
			if worn and valor(piece) <= valor(worn) then
				desmontar(piece)
				return
			end
			puesto[slot] = piece
			if worn then
				desmontar(worn)
			end
			if equipoReal then
				estado.armadura = totales()
				mazSucio = true
			end
		end
		-- Una tabla de premios (server/Loot): las cantidades van por el "loot" de la zona, y su parte decimal es la
		-- probabilidad de uno más.
		local function soltar(drops, index: number)
			local zona = zonas[index]
			for _, drop in drops do
				local chance = drop.chance or 1
				if chance >= 1 or azar() < chance then
					if drop.kind == "item" then
						local low, high = drop.min or 1, drop.max or 1
						local amount = (low + math.floor(azar() * (high - low + 1))) * zona.loot
						local whole = math.floor(amount)
						if azar() < amount - whole then
							whole += 1
						end
						whole = math.max(whole, 1)
						if drop.item == "traitCrystal" then
							tirar("traits", whole)
						elseif drop.item == "gradeCrystal" then
							tirar("grades", whole)
						end
					elseif drop.kind == "armor" then
						pieza(index, zona.qualityLuck * (drop.luck or 1))
					end
				end
			end
		end
		local function jugarMazmorra()
			local index = mazZona :: number
			local mz = res.maz
			mz.partidas += 1
			mz.zonas[index] = mz.zonas[index] or t
			for _, wave in oleadas[index] do
				for _, entry in wave do
					for _ = 1, entry.n do
						soltar(entry.def.drops, index)
					end
				end
			end
			soltar(Config.Dungeon.ClearDrops, index)
		end
		-- Pasa el tiempo: por cada segundo de sesión, su parte de mazmorra; cuando junta lo que dura una partida, la juega.
		local function pasa(dt: number)
			t += dt
			if mazZona then
				presupuesto += dt * mazParte
				while presupuesto >= mazDur do
					presupuesto -= mazDur
					jugarMazmorra()
				end
			end
		end
		local horasFoto = {}
		for hour = 1, opts.horas do
			horasFoto[hour] = true
		end
		for _, list in { objetivo.armadura, objetivo.rasgo, objetivo.grado } do
			for _, entry in list do
				horasFoto[entry[1]] = true
			end
		end
		for hour in horasFoto do
			a(hour * H, function()
				local mz = res.maz
				local calidad, piezas = 0, 0
				for _, piece in puesto do
					calidad += piece.quality
					piezas += 1
				end
				mz.fotos[hour] = { zona = mazZona or 0, segundos = mazDur, partidas = mz.partidas, rasgo = mz.tiradas.traits, grado = mz.tiradas.grades, parcela = mz.parcela, desmontar = mz.desmontar, armadura = totales(), calidad = if piezas > 0 then calidad / piezas else 0, dano = damage }
			end)
		end
		for index, at in objetivo.mazmorras do
			a(at, function()
				res.danoMazmorra[index] = damage
			end)
		end
		for _, hour in objetivo.fotos do
			a(hour * H, function()
				res.fotos[hour] = {
					upgrades = table.clone(estado.upgrades),
					rebirths = estado.rebirths,
					sword = estado.sword,
					metal = estado.metal,
					size = estado.size,
					trait = estado.trait,
					grade = estado.grade,
					artifacts = table.clone(estado.artifacts),
					gear = table.clone(estado.gear),
					armadura = table.clone(estado.armadura),
					coins = estado.coins,
					damage = damage,
					luck = luck,
				}
			end)
		end
		for hour = 1, opts.horas do
			a(hour * H, function()
				table.insert(res.ritmo, { hora = hour, objetos = res.objetos, monedas = res.ganado })
			end)
		end
		if forzado then
			local function compra(at: number, pista: string, apply)
				a(at, function()
					table.insert(res.eventos, { t = at, pista = pista, monedas = res.ganado })
					apply()
				end)
			end
			local suerte = Config.Upgrades.luck
			for level = 1, suerte.maxLevel do
				compra(objetivo.suerte(level, suerte.maxLevel), "luck", function()
					estado.upgrades.luck = level
					res.compras.luck[level] = t
				end)
			end
			for name, times in objetivo.mejoras do
				if Config.Upgrades[name] then
					for level, at in times do
						compra(at, name, function()
							estado.upgrades[name] = level
							res.compras[name][level] = t
						end)
					end
				end
			end
			for count, at in objetivo.renacer do
				compra(at, "rebirth", function()
					estado.rebirths = count
					res.renacer[count] = t
				end)
			end
			for index, at in objetivo.accesorios do
				if Config.Artifacts[index] then
					a(at, function()
						res.lambda[index] = res.sumaSuerte
						res.accesorios[index] = t
						table.insert(estado.artifacts, index)
						equipar()
					end)
				end
			end
		end
		table.sort(agenda, function(x, y)
			return x.t < y.t
		end)
		local cita = 1

		-- Clima: en cada tramo, uno al azar durante lo que dura.
		local weather = Config.Weather
		local climaHasta, climaSiguiente = 0, if opts.clima == false then math.huge else 0
		mundo.Weather = nil

		res.objetos, res.saltados, res.tiradas, res.ganado, res.sumaSuerte = 0, 0, 0, 0, 0
		res.esperadoTope, res.esperadoClima = 0, {} -- armas tope esperadas en toda la partida y con cada clima puesto
		local topRarity = Config.Swords[pool[1]].rarity
		local umbrales = { 1e4, 1e6, 1e9, 1e12, 1e15 }
		local minCost = 0
		local function precioMinimo()
			minCost = math.huge
			for _, name in Config.UpgradeOrder do
				local level = estado.upgrades[name]
				if level < Config.Upgrades[name].maxLevel and not (opts.sinSuerte and name == "luck") then
					minCost = math.min(minCost, Upgrades.cost(name, level))
				end
			end
			if estado.rebirths < Config.Rebirth.max then
				minCost = math.min(minCost, Stats.rebirthCost(player))
			end
		end
		recalcular()
		precioMinimo()

		while t < fin do
			local sucio = false
			while cita <= #agenda and agenda[cita].t <= t do
				agenda[cita].fn()
				cita += 1
				sucio = true
			end
			if t >= climaSiguiente then
				local id = tirarClima()
				mundo.Weather = id
				climaHasta = climaSiguiente + WeatherInfo.duration(id)
				climaSiguiente += weather.Interval
				sucio = true
			elseif mundo.Weather and t >= climaHasta then
				mundo.Weather = nil
				sucio = true
			end
			if sucio or mazSucio then
				recalcular()
			end

			-- Tipo del objeto (server/Destructibles).
			local ti = 1
			local u = random()
			for index = #tipos, 2, -1 do
				local p = typeLuck / tipos[index].rarity
				if p >= 1 or u < p then
					ti = index
					break
				end
				u = (u - p) / (1 - p)
			end
			local def = tipos[ti]
			local quality, _, scale, rolls = tirarObjeto(def, objectLuck)
			local hp = ObjectSpec.hp(def, quality, scale)
			if calibrar and ti > 1 then
				local base = M.golpes(ti) * (if ti < nextTipo then res.danoTipo[ti] else damage * (def.rarity * parte / luck) ^ calibrar[ti])
				hp *= base / def.hp
			end
			local hits = math.max(1, math.ceil(hp / damage - 1e-9))
			if hits > paciencia then
				-- Demasiado duro: lo deja. Cuenta el hueco de aparición.
				res.saltados += 1
				pasa(spawnTime / eficiencia)
				continue
			end
			pasa(math.max(spawnTime, paseo + hits * cooldown / porGolpe) / eficiencia)
			res.objetos += 1
			-- Cristal de rasgo de los objetos que dan gemas (server/Traits).
			if def.gems > 0 and azar() < cristalParcela then
				res.maz.parcela += 1
				tirar("traits", 1)
			end
			res.sumaSuerte += luck
			if def.reward > 0 then
				local coins = math.max(1, math.round(def.reward * ObjectSpec.reward(quality, scale) * coinMult))
				estado.coins += coins
				res.ganado += coins
			end

			-- Tiradas de arma (server/Gacha): la suerte del objeto solo cuenta para el arma.
			local objLuck = gacha * ObjectSpec.luck(def, quality, scale)
			-- Armas tope que tocaría esperar de este objeto (la cuenta exacta, sin depender de la suerte de la partida).
			local esperado = rolls * math.min(1, objLuck / topRarity)
			res.esperadoTope += esperado
			if mundo.Weather then
				res.esperadoClima[mundo.Weather] = (res.esperadoClima[mundo.Weather] or 0) + esperado
			end
			for _ = 1, rolls do
				res.tiradas += 1
				local sword = 2
				u = random()
				for _, index in pool do
					local p = objLuck / Config.Swords[index].rarity
					if p >= 1 or u < p then
						sword = index
						break
					end
					u = (u - p) / (1 - p)
				end
				local metal = cascada(Config.Metals, gacha, 0)
				local size = cascada(Config.Sizes, gacha, 0)
				local rarity = Config.Swords[sword].rarity
				local total = Config.Swords[sword].damage * Permanent.damageMult({ metal = metal, size = size })
				if total > bestDamage then
					bestDamage = total
					estado.sword, estado.metal, estado.size = sword, metal, size
					recalcular()
				end
				for _, limit in umbrales do
					if rarity >= limit and not res.armas[limit] then
						res.armas[limit] = t
					end
				end
				if rarity >= 1e15 then
					res.cuenta[sword] = (res.cuenta[sword] or 0) + 1
					if not res.armas[sword] then
						res.armas[sword] = t
					end
				end
			end

			if not forzado then
				-- Accesorios (server/Gear): del más raro al más común, saltando los que ya tiene.
				if #estado.artifacts < #Config.Artifacts then
					for index = #Config.Artifacts, 1, -1 do
						if not res.accesorios[index] then
							local p = luck / Config.Artifacts[index].rarity
							if p >= 1 or random() < p then
								res.accesorios[index] = t
								table.insert(estado.artifacts, index)
								equipar()
								recalcular()
								break
							end
						end
					end
				end
				-- Compras ("Mejorar todo" de server/Shop, y renacer en cuanto llega).
				if estado.coins >= minCost then
					local bought = true
					while bought do
						bought = false
						for _, name in Config.UpgradeOrder do
							local level = estado.upgrades[name]
							if level < Config.Upgrades[name].maxLevel and not (opts.sinSuerte and name == "luck") then
								local cost = Upgrades.cost(name, level)
								if estado.coins >= cost then
									estado.coins -= cost
									estado.upgrades[name] = level + 1
									res.compras[name][level + 1] = t
									bought = true
								end
							end
						end
						if estado.rebirths < Config.Rebirth.max then
							local cost = Stats.rebirthCost(player)
							if estado.coins >= cost then
								estado.coins -= cost
								estado.rebirths += 1
								attrs.Rebirths = estado.rebirths
								res.renacer[estado.rebirths] = t
								bought = true
							end
						end
					end
					recalcular()
					precioMinimo()
				end
				-- Completado: todas las mejoras, todos los renacimientos y todos los accesorios.
				if not res.completo and minCost == math.huge and #estado.artifacts >= #Config.Artifacts then
					res.completo = t
					if opts.parar then
						break
					end
				end
			end
		end
		res.maz.mejor = mejor
		res.estado = estado
		res.dano = damage
		res.cooldown, res.area = cooldown, area
		res.suerte = luck
		mundo.Weather = nil
		return res
	end

	-- Con TODA la suerte al máximo (todos los objetos del tipo más raro y todos los renacimientos, sin pociones y con el
	-- clima que vaya tocando, o sin él con conClima = false): horas de romper objetos por cada arma de las `count` más
	-- raras. `dano` = daño por golpe del jugador; `samples` = objetos de muestra por cada clima.
	function M.horasPorArma(dano: number, count: number, samples: number, conClima: boolean?): { number }
		-- (dano = math.huge: todo le cae de un golpe, que es el jugador que más objetos rompe.)
		local def = tipos[#tipos]
		local gacha = Config.Rebirth.gachaLuck ^ Config.Rebirth.max
		local attrs = {}
		for _, name in Config.UpgradeOrder do
			attrs["Upgrade_" .. name] = Config.Upgrades[name].maxLevel
		end
		local last = objetivo.armadura[#objetivo.armadura]
		attrs.Armor_rollSpeed = last[4]
		local player = {
			GetAttribute = function(_, name)
				return attrs[name]
			end,
		}
		mundo.Weather = nil
		local spawnTime, cooldown = Stats.spawnTime(player), Stats.cooldown(player)
		local porGolpe = M.porGolpe(Upgrades.value("capacity", Config.Upgrades.capacity.maxLevel))
		local jugador = objetivo.jugador
		-- Armas por segundo con una suerte de rareza y tamaño de los objetos y una suerte de armas dadas.
		local function ritmo(objectLuck: number, weaponLuck: number): { number }
			local expected = table.create(count, 0)
			local seconds = 0
			for _ = 1, samples do
				local quality, _, scale, rolls = tirarObjeto(def, objectLuck)
				local hits = math.max(1, math.ceil(ObjectSpec.hp(def, quality, scale) / dano - 1e-9))
				if hits > jugador.paciencia then
					seconds += spawnTime / jugador.eficiencia
					continue
				end
				seconds += math.max(spawnTime, jugador.paseo + hits * cooldown / porGolpe) / jugador.eficiencia
				local objLuck = gacha * weaponLuck * ObjectSpec.luck(def, quality, scale)
				local left = 1
				for position = 1, count do
					local p = math.min(1, objLuck / Config.Swords[pool[position]].rarity)
					expected[position] += rolls * left * p
					left *= 1 - p
				end
			end
			for position = 1, count do
				expected[position] /= seconds
			end
			return expected
		end
		-- El tiempo se reparte entre el cielo despejado y cada clima, según lo que sale y lo que dura (la suerte de
		-- destructibles del clima no cambia el tipo, que ya es el más raro, pero sí la rareza y el tamaño del objeto).
		local total = ritmo(1, 1)
		if conClima ~= false then
			local despejado = 1
			local mezcla = table.create(count, 0)
			for _, entry in climas do
				local event = Config.Weather.Events[entry.id]
				local share = entry.chance * WeatherInfo.duration(entry.id) / Config.Weather.Interval
				despejado -= share
				local rates = ritmo(event.luck or 1, event.weaponLuck or 1)
				for position = 1, count do
					mezcla[position] += share * rates[position]
				end
			end
			for position = 1, count do
				total[position] = total[position] * despejado + mezcla[position]
			end
		end
		local hours = {}
		for position = 1, count do
			hours[position] = 1 / total[position] / H
		end
		return hours
	end

	return M
end

return Modelo
