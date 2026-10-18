-- Ejecutar desde la raíz: lune run tests/regressions.luau
-- Carga el código de producción; sustituye red, reloj y DataStore. No simula la física ni el render de Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3, Vector2, Instance = roblox.CFrame, roblox.Vector3, roblox.Vector2, roblox.Instance

local checks = 0
local function equal(actual, expected, label: string)
	assert(actual == expected, `{label}: esperado {expected}, recibido {actual}`)
	checks += 1
end
local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= math.max(1, math.abs(expected)) * 1e-6, label)
	checks += 1
end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, fn)
			table.insert(callbacks, fn)
			return { Disconnect = function() end }
		end,
		fire = function(_, ...)
			for _, fn in callbacks do fn(...) end
		end,
	}
end
local function node(path: string)
	return setmetatable({ path = path }, { __index = function(_, key)
		return node(if key == "Parent" then path:match("^(.*)/[^/]+$") else path .. "/" .. key)
	end })
end
local function remoteSet()
	return setmetatable({}, { __index = function(self, name)
		local remote = { OnServerEvent = signal(), OnClientEvent = signal(), sent = {} }
		function remote:FireClient(...) table.insert(self.sent, table.pack(...)) end
		function remote:FireAllClients(...) table.insert(self.sent, table.pack(...)) end
		self[name] = remote
		return remote
	end })
end
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return assert(self:FindFirstChild(name), "Falta " .. name)
end)

-- Lo que devuelve un DataStore de lo que se le da: una copia sin nada compartido con la partida. De paso comprueba que
-- se puede guardar (solo números, textos, booleanos y tablas que sean lista o diccionario de textos, nunca mezcla).
local function stored(value, path: string?)
	local where = path or "datos"
	if type(value) ~= "table" then
		assert(type(value) == "number" or type(value) == "string" or type(value) == "boolean", `no se puede guardar {where}: {type(value)}`)
		return value
	end
	local copy, count = {}, 0
	for key, item in value do
		count += 1
		copy[key] = stored(item, where .. "." .. tostring(key))
	end
	if count ~= #value then
		for key in value do
			assert(type(key) == "string", `no se puede guardar {where}: clave {tostring(key)} en un diccionario`)
		end
	end
	return copy
end

-- Copia tal cual (lo que devuelve un DataStore al leer): sin comprobar nada, que lo guardado puede venir roto.
local function copied(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in value do copy[key] = copied(item) end
	return copy
end

-- Un DataStore de una sola clave, como el de verdad: UpdateAsync lee y escribe de una vez, y devolver nil no escribe.
-- Varios "servidores" (fixtures) pueden compartir el mismo. `fail` = "read" o "write" para simular que no hay red.
local function dataStore(initial)
	local store = { value = initial, writes = 0, fail = nil }
	function store.GetAsync()
		assert(store.fail ~= "read" and store.fail ~= "all", "sin red")
		return copied(store.value)
	end
	function store.UpdateAsync(_, _, transform)
		assert(store.fail ~= "read" and store.fail ~= "all", "sin red")
		local current = copied(store.value)
		local out = transform(current)
		if out == nil then return nil end
		assert(store.fail ~= "write", "sin red")
		-- Lo que escribe la partida tiene que poder guardarse; lo que ya estaba (candado puesto o quitado) pasa tal cual.
		store.value = if out == current then copied(out) else stored(out)
		store.writes += 1
		return store.value
	end
	return store
end

-- Echar a un jugador solo deja apuntado el mensaje (atributo "Kicked").
roblox.implementMethod("Player", "Kick", function(self, message)
	self:SetAttribute("Kicked", message or "")
end)
local guids = 0

local function fixture(saved, customStore)
	local now = 100
	local jobs = {}
	local root = Instance.new("Folder")
	local workspace = Instance.new("Workspace")
	workspace.Parent = root
	local map = Instance.new("Folder")
	map.Name, map.Parent = "Map", workspace
	local player = Instance.new("Player")
	player.Name, player.DisplayName, player.UserId, player.Parent = "Prueba", "Prueba", 1, root
	local players = { player }
	local remotes = remoteSet()
	local tags, tagAdded, tagRemoved = {}, {}, {}
	local http = {
		JSONEncode = function(_, value) return serde.encode("json", value) end,
		JSONDecode = function(_, value) return serde.decode("json", value) end,
		GenerateGUID = function()
			guids += 1
			return "sesion-" .. guids
		end,
	}
	local warnings = {}
	local store = customStore or dataStore(saved)
	local services = {
		ReplicatedStorage = { Shared = node("src/shared") },
		Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return players end },
		RunService = { IsStudio = function() return false end, Heartbeat = signal() },
		TextService = {},
		HttpService = http,
		MessagingService = { PublishAsync = function() end, SubscribeAsync = function() end },
		DataStoreService = { GetDataStore = function() return store end },
		CollectionService = {
			AddTag = function(_, item, tag)
				tags[tag] = tags[tag] or {}
				table.insert(tags[tag], item)
				if tagAdded[tag] then tagAdded[tag]:fire(item) end
			end,
			HasTag = function(_, item, tag) return table.find(tags[tag] or {}, item) ~= nil end,
			GetTagged = function(_, tag) return tags[tag] or {} end,
			GetInstanceAddedSignal = function(_, tag)
				tagAdded[tag] = tagAdded[tag] or signal()
				return tagAdded[tag]
			end,
			GetInstanceRemovedSignal = function(_, tag)
				tagRemoved[tag] = tagRemoved[tag] or signal()
				return tagRemoved[tag]
			end,
		},
	}
	local function resume(job, ...)
		local ok, err = coroutine.resume(job, ...)
		assert(ok, tostring(err))
	end
	local fakeTask = {
		spawn = function(fn, ...)
			local job = coroutine.create(fn)
			resume(job, ...)
			if coroutine.status(job) ~= "dead" then table.insert(jobs, job) end
			return job
		end,
		wait = coroutine.yield,
		delay = function() end,
	}
	local random = {
		NextNumber = function(_, low, high) return if low then (low + high) / 2 else 0 end,
		NextInteger = function(_, low) return low end,
	}
	local overrides = {
		["src/shared/Remotes"] = remotes,
		["src/server/Missions"] = { add = function() end },
		["src/server/BestRoll"] = { submit = function() end }, -- el pedestal construye modelos (SwordModel, AssetService)
		["src/server/Policy"] = { canTrade = function() return true end }, -- las normas por país las pregunta a Roblox (PolicyService)
		["src/server/StallSkin"] = {},
		["src/server/Stations"] = {
			enchanter = function()
				local model, counter = Instance.new("Model"), Instance.new("Part")
				counter.Parent = model
				return model, counter, 10
			end,
		},
	}
	overrides["src/server/Stations"].forge = overrides["src/server/Stations"].enchanter
	local cache = {}
	local loadModule
	loadModule = function(path)
		if overrides[path] then return overrides[path] end
		if cache[path] then return cache[path] end
		local env = table.clone(roblox)
		env.script = node(path)
		env.workspace = workspace
		env.game = {
			PlaceId = 1,
			GetService = function(_, name) return assert(services[name], "Servicio sin adaptar: " .. name) end,
			BindToClose = function() end,
		}
		env.require = function(ref) return loadModule(ref.path) end
		env.Random = { new = function() return random end }
		env.task = fakeTask
		env.warn = function(message) table.insert(warnings, message) end
		env.os = table.clone(os)
		env.os.clock = function() return now end
		env.os.time = function() return 1e9 + now end -- el reloj de pared avanza con el del servidor
		cache[path] = luau.load(fs.readFile(path .. ".luau"), { debugName = path, environment = env, injectGlobals = true })()
		return cache[path]
	end
	local config = loadModule("src/shared/Config")
	local data = loadModule("src/server/PlayerData")
	data.start()
	return {
		load = loadModule, config = config, data = data, player = player, remotes = remotes, services = services,
		overrides = overrides, warnings = warnings, workspace = workspace, players = players, random = random, tags = tags, task = fakeTask,
		advance = function(seconds) now += seconds end,
		step = function(seconds)
			now += seconds
			for _, job in table.clone(jobs) do if coroutine.status(job) == "suspended" then resume(job) end end
		end,
		-- Sale el jugador: guardado de salida (en su hilo, que puede esperar para reintentar) y lo que queda guardado.
		save = function()
			fakeTask.spawn(function() services.Players.PlayerRemoving:fire(player) end)
			return store.value
		end,
		store = store, spawn = fakeTask.spawn,
	}
end

-- Compila todos los scripts, incluidos los de interfaz que necesitan el motor para ejecutarse.
local compiled = 0
local function compileTree(path: string)
	for _, name in fs.readDir(path) do
		local file = path .. "/" .. name
		if fs.isDir(file) then compileTree(file)
		elseif name:match("%.luau$") then
			local ok, err = pcall(luau.compile, fs.readFile(file))
			assert(ok, file .. ": " .. tostring(err))
			compiled += 1
		end
	end
end
compileTree("src")

local f = fixture(nil)
local config, player, data = f.config, f.player, f.data
local permanent = f.load("src/shared/Permanent")
local modifiers = f.load("src/shared/Modifiers")
equal(table.concat(data.read(player).loadout, ","), "1", "espada inicial equipada")
equal(#data.read(player).gear, 0, "accesorios iniciales sin equipar")
for index, sword in config.Swords do
	near(sword.damage, 1.5 ^ math.max(math.log((sword.rarity or 2) / 2, 2), 0), "daño de arma " .. index)
end
equal(config.damageFromRarity(2), 1, "rareza inicial")
near(config.damageFromRarity(8), 2.25, "curva de daño")
local label = permanent.describeOdds(4, 1, 1)
-- Un solo número, sin desglose por metal y tamaño.
assert(label:find("^1 in ") and not label:find("·", 1, true) and not label:find(config.Metals[1].name, 1, true))
checks += 1

-- Por mucha suerte de armas que haya siguen saliendo armas sin metal y de tamaño normal (con x10 el Cobre salía siempre).
do
	local combos = permanent.combos()
	local weapons, worst, plain = 0, nil, 0
	for index, sword in config.Swords do
		if sword.rarity then
			weapons += 1
			if not worst or sword.rarity < config.Swords[worst].rarity then worst = index end
		end
	end
	equal(#combos, weapons * (#config.Metals + 1) * (#config.Sizes + 1), "un resultado por arma, metal y tamaño")
	for position = 2, #combos do
		assert(combos[position - 1].rarity >= combos[position].rarity, "resultados de más raro a más común")
	end
	equal(combos[#combos].sword, worst, "lo más común es la peor arma")
	equal(combos[#combos].metal + combos[#combos].size, 0, "lo más común va sin metal y en tamaño normal")
	-- La peor arma con el mejor metal y el mejor tamaño es rarísima: su rareza total, no la del arma.
	near(permanent.odds(worst, #config.Metals, #config.Sizes, 1) / (config.Swords[worst].rarity * config.Metals[#config.Metals].odds * config.Sizes[#config.Sizes].odds), 1, "rareza total")
	local number = f.random.NextNumber
	f.random.NextNumber = function() return 0.999 end
	local sword, metal, size = permanent.rollWeapon(1)
	equal(sword * 10000 + metal * 100 + size, worst * 10000, "sin suerte y sin acertar: la peor arma a secas")
	-- Con suerte x30 lo que sale es de alrededor de 1 entre 30 en total: no todo de Cobre.
	sword, metal, size = permanent.rollWeapon(30)
	assert(permanent.rarity(sword, metal, size) <= 30.1 and permanent.rarity(sword, metal, size) > 10, "la suerte va a la rareza total")
	f.random.NextNumber = number
	checks += 3
end

-- Pity: límite base, obtención natural, colisiones, desempate y separación de contadores.
for _, kind in { "traits", "grades" } do
	local counters = modifiers.newPity(nil)[kind]
	for index in modifiers.KINDS[kind].list do
		equal(modifiers.pityLimit(kind, index), math.ceil(100 / modifiers.percent(kind, index)), "límite " .. kind .. index)
		counters[index] = modifiers.pityLimit(kind, index) - 1
		equal(modifiers.hasPity(kind, index), modifiers.KINDS[kind].list[index].pity == true or modifiers.odds(kind, index) >= config.ModifierPity.MinOdds, "con pity " .. kind .. index)
	end
	local expected = 1
	for index in counters do
		if modifiers.better(kind, index, expected, modifiers.PRIORITY) then expected = index end
	end
	local result = modifiers.rollWithPity(kind, f.random, 1e9, counters, modifiers.PRIORITY)
	equal(result, expected, "garantía más rara " .. kind)
	equal(counters[result], 0, "reinicio " .. kind)
	for index in counters do
		if index ~= result then equal(counters[index], if modifiers.hasPity(kind, index) then modifiers.pityLimit(kind, index) else 0, "garantía pendiente " .. kind .. index) end
	end
	local nextResult = modifiers.rollWithPity(kind, f.random, 1, counters, modifiers.PRIORITY)
	assert(nextResult ~= result, "no perder las otras garantías")
	checks += 1
	local clean = modifiers.newPity(nil)[kind]
	local natural = modifiers.rollWithPity(kind, f.random, 1, clean, modifiers.PRIORITY)
	equal(natural, 1, "resultado natural controlado " .. kind)
	equal(clean[1], 0, "obtención natural reinicia " .. kind)
end
-- Solo tienen pity los resultados raros (de S+ y de Shogun para arriba) y los marcados con `pity = true` (Samurái): los
-- demás fáciles ni cuentan ni se garantizan.
equal(modifiers.hasPity("grades", 6), false, "S sin pity")
equal(modifiers.hasPity("grades", 7), true, "S+ con pity")
equal(modifiers.hasPity("traits", 9), false, "Suerte III sin pity")
equal(modifiers.hasPity("traits", 10), true, "Samurái con pity aunque es más fácil que el mínimo")
equal(modifiers.hasPity("traits", 11), true, "Shogun con pity")
local last = #config.Traits
local sanitized = modifiers.newPity({ traits = { [1] = 5, [last - 3] = -5, [last - 2] = 0 / 0, [last - 1] = math.huge, [last] = 1.9 }, grades = "inválido" })
equal(sanitized.traits[1], 0, "pity de un resultado fácil")
equal(sanitized.traits[last - 3], 0, "pity negativo")
equal(sanitized.traits[last - 2], 0, "pity NaN")
equal(sanitized.traits[last - 1], modifiers.pityLimit("traits", last - 1), "pity acotado")
equal(sanitized.traits[last], 1, "pity entero")
equal(sanitized.grades[1], 0, "pity antiguo vacío")
local easy = modifiers.newPity(nil).traits
for index = 1, 3 do easy[index] = modifiers.pityLimit("traits", index) end
equal(modifiers.rollWithPity("traits", f.random, 1, easy, modifiers.PRIORITY), 1, "los fáciles no se garantizan")
equal(easy[2], 0, "los fáciles no cuentan")
equal(modifiers.better("traits", 2, 1, { "damage", "coins", "luck" }), true, "empate respeta prioridad del jugador")

-- Venta: modifica una sola vez, no vende equipada, acepta modificadas y vuelve a validar ids.
local gacha = f.load("src/server/Gacha")
gacha.start()
data.edit(player, function(d)
	d.swords = { { id = 1, sword = 1 }, { id = 2, sword = 4, trait = 1, grade = 1, metal = 1, size = 1 }, { id = 3, sword = 5 } }
	d.nextSwordId = 4
end)
f.remotes.SellSwords.OnServerEvent:fire(player, { 1, 2, 2, 999 })
equal(#data.read(player).swords, 2, "venta deduplicada y sin equipada")
equal(data.read(player).gems, config.Gacha.SellValue, "cobro único")
f.remotes.SellSwords.OnServerEvent:fire(player, { 2, 999 })
equal(data.read(player).gems, config.Gacha.SellValue, "no repetir cobro")
for _, invalid in { "3", { 3, "2" }, { 3, 0 / 0 }, { 3, math.huge }, { 3, -1 }, { 3, 1.5 }, table.create(config.MaxSwords + 1, 3) } do
	f.remotes.SellSwords.OnServerEvent:fire(player, invalid)
	equal(#data.read(player).swords, 2, "venta inválida rechazada")
end
f.remotes.EquipSword.OnServerEvent:fire(player, 3)
f.remotes.SellSwords.OnServerEvent:fire(player, { 3 })
equal(#data.read(player).swords, 2, "equipada después de seleccionar protegida")
gacha.give(player, 1e6, "object", 1)
equal(table.concat(data.read(player).loadout, ","), "1,3", "arma nueva no se equipa")
local rolled = f.remotes.GachaRolled.sent[#f.remotes.GachaRolled.sent]
equal(rolled[8].baseOdds, config.Swords[rolled[2]].rarity, "resultado expone rareza base")

-- Índice de armas: lo guardado se limpia, se estrena con la mochila una sola vez y cada tirada apunta su
-- combinación aunque la venta automática la venda.
local indexInfo = f.load("src/shared/IndexInfo")
local code = indexInfo.code
local cleanIndex = indexInfo.sanitize({ code(4, 1, 1), code(4, 1, 1), code(1, 1, 0), code(999, 0, 0), code(4, 99, 0), code(4, 0, 99), 0 / 0, math.huge, -1, 1.5, "x" })
equal(#cleanIndex, 1, "índice guardado: solo válidos y sin repetir")
equal(cleanIndex[1], code(4, 1, 1), "índice guardado conserva lo válido")
equal(indexInfo.sanitize(nil), nil, "índice sin estrenar")
equal(#indexInfo.swords(0, 0), #config.Swords, "vista base con todas las armas")
equal(#indexInfo.swords(1, 0), #config.Swords - 1, "el arma inicial no tiene metal")
local xf = fixture(nil)
xf.load("src/server/Index").start()
equal(xf.player:GetAttribute("Index"), tostring(code(1, 0, 0)), "índice estrenado con la mochila")
xf.data.edit(xf.player, function(d) d.autoSell = math.huge end)
xf.load("src/server/Gacha").give(xf.player, 1e6, "object", 1)
local sold = xf.remotes.GachaRolled.sent[#xf.remotes.GachaRolled.sent]
equal(sold[3], false, "tirada vendida sola")
equal(indexInfo.parse(xf.player:GetAttribute("Index"))[code(sold[2], sold[6], sold[7])], true, "la tirada vendida cuenta en el índice")
equal(#xf.data.read(xf.player).index, 2, "índice sin repetidos")
xf.load("src/server/Gacha").give(xf.player, 1e6, "object", 1)
equal(#xf.data.read(xf.player).index, 2, "la misma combinación no se apunta dos veces")
local sf = fixture({ swords = { { id = 1, sword = 1 }, { id = 2, sword = 4 } }, index = { code(5, 0, 0), "x" } })
sf.load("src/server/Index").start()
equal(sf.player:GetAttribute("Index"), tostring(code(5, 0, 0)), "índice ya estrenado no vuelve a contar la mochila")
f.load("src/server/Gear").onBroken(player)
equal(#data.read(player).gear, 0, "accesorio nuevo no se equipa")
local piece, kept = f.load("src/server/Armor").give(player, 1, 1)
equal(kept, true, "armadura recibida")
equal(data.read(player).armorWorn[piece.slot], nil, "armadura nueva no se equipa")

-- Renacimiento: cinco, ningún sexto, y cada uno quita monedas, gemas, mejoras y la bolsa, pero no lo demás.
roblox.implementMethod("Workspace", "GetServerTimeNow", function() return 0 end)
f.load("src/server/Rebirth").start()
local keptSwords, keptArtifacts, keptCrystals = #data.read(player).swords, #data.read(player).artifacts, data.read(player).items.traitCrystal
for count = 1, 5 do
	data.edit(player, function(d)
		d.coins, d.gems = 1e100, 500
		d.upgrades.luck, d.upgrades.fortune, d.upgrades.bagBoost = 3, 2, 1
		d.bag.stage, d.bag.taken = 4, 10
	end)
	f.advance(3)
	f.remotes.Rebirth.OnServerEvent:fire(player)
	local d = data.read(player)
	equal(d.rebirths, count, "renacimiento " .. count)
	equal(d.coins, 0, "renacer quita las monedas")
	equal(d.gems, 0, "renacer quita las gemas")
	for name, level in d.upgrades do
		equal(level, 0, "renacer quita la mejora " .. name)
	end
	equal(d.bag.stage, 1, "renacer devuelve la bolsa a la primera")
	equal(d.bag.taken, 0, "renacer deja la bolsa entera")
	equal(player:GetAttribute("Upgrade_luck"), 0, "mejoras publicadas a cero")
	equal(player:GetAttribute("BagStage"), 1, "bolsa publicada")
	equal(#d.swords, keptSwords, "renacer no quita armas")
	equal(#d.artifacts, keptArtifacts, "renacer no quita accesorios")
	equal(d.items.traitCrystal, keptCrystals, "renacer no quita objetos")
end
equal(#f.remotes.Reborn.sent, 5, "un aviso por renacimiento")
data.edit(player, function(d) d.coins = 1e100; d.gems = 7; d.upgrades.luck = 2 end)
f.advance(3)
f.remotes.Rebirth.OnServerEvent:fire(player)
equal(data.read(player).rebirths, 5, "máximo cinco")
equal(data.read(player).coins, 1e100, "sexto sin quitar monedas")
equal(data.read(player).gems, 7, "sexto sin quitar gemas")
equal(data.read(player).upgrades.luck, 2, "sexto sin quitar mejoras")
data.edit(player, function(d) d.rebirths = 0; d.coins = 0 end)
f.advance(3)
f.remotes.Rebirth.OnServerEvent:fire(player)
equal(data.read(player).rebirths, 0, "sin dinero no renace")
equal(data.read(player).upgrades.luck, 2, "sin dinero no pierde las mejoras")
data.edit(player, function(d) d.upgrades.luck = 0; d.gems = 0 end)

-- Tiendas reales: triple cuenta tres; no avanza sin pago; descartar no deshace el Pity.
f.load("src/server/ModifierShops").start()
data.edit(player, function(d) d.items.traitCrystal = 3; d.items.gradeCrystal = config.GradeCost end)
f.remotes.RollTrait.OnServerEvent:fire(player, 3, 3)
local state = data.read(player)
equal(state.items.traitCrystal, 0, "triple cuesta tres")
equal(state.pity.traits[#config.Traits], 3, "triple avanza tres")
equal(state.pity.grades[#config.Grades], 0, "rasgos no avanzan grados")
f.advance(10)
f.remotes.RollTrait.OnServerEvent:fire(player, 3, 1)
equal(state.pity.traits[#config.Traits], 3, "sin pago no avanza")
f.advance(10)
f.remotes.RollGrade.OnServerEvent:fire(player, 3, true)
equal(state.pity.grades[#config.Grades], 1, "grado cuenta uno")
f.remotes.RevertGrade.OnServerEvent:fire(player, 3)
equal(state.pity.grades[#config.Grades], 1, "descarte conserva progreso")
equal(data.findSword(state, 3).grade, nil, "descarte restaura grado anterior")

-- Nivel de armas: cobra gemas, sube solo lo que se puede pagar, multiplica el daño de esa copia y llega al cliente.
f.load("src/server/WeaponLevels").start()
local weaponLevel = f.load("src/shared/WeaponLevel")
local levelStats = f.load("src/shared/Stats")
local leveled = data.findSword(state, 3)
data.edit(player, function(d) d.gems = weaponLevel.cost(leveled, 0) + weaponLevel.cost(leveled, 1) + 1 end)
f.advance(1)
f.remotes.LevelSword.OnServerEvent:fire(player, 3, 10)
equal(leveled.level, 2, "sube solo los niveles que puede pagar")
equal(state.gems, 1, "cobra lo que cuestan los niveles")
f.advance(1)
f.remotes.LevelSword.OnServerEvent:fire(player, 3, 1)
equal(leveled.level, 2, "sin gemas no sube de nivel")
equal(weaponLevel.cost(leveled, 5) > weaponLevel.cost(leveled, 4), true, "cada nivel cuesta más que el anterior")
equal(weaponLevel.cost({ sword = #config.Swords, metal = #config.Metals, size = #config.Sizes }, 0) > weaponLevel.cost(leveled, 0), true, "las armas más raras cuestan más")
equal(weaponLevel.sanitize(0 / 0), 0, "nivel guardado sin número")
equal(weaponLevel.sanitize(999), config.WeaponLevel.MaxLevel, "nivel guardado por encima del tope")
data.edit(player, function(d) data.findSword(d, 3).locked = true end)
local published = nil
for _, copy in levelStats.swords(player) do
	if copy.id == 3 then
		published = copy
	end
end
equal(published.level, 2, "el nivel llega al cliente")
equal(published.locked, true, "el candado sigue llegando con nivel")
local plain = { sword = published.sword, trait = published.trait, grade = published.grade, metal = published.metal, size = published.size }
near(levelStats.swordDamage(published) / levelStats.swordDamage(plain), config.WeaponLevel.PerLevel ^ 2, "el nivel multiplica el daño de su arma")
equal(levelStats.sellCoins(published), levelStats.sellCoins(plain), "el nivel no cambia lo que da vender")
data.edit(player, function(d) data.findSword(d, 3).locked = nil end)
local badLevels = fixture({ swords = { { id = 1, sword = 1, level = 0 / 0 }, { id = 2, sword = 1, level = 999 } } })
equal(badLevels.data.read(badLevels.player).swords[1].level, nil, "nivel guardado roto se queda en 0")
equal(badLevels.data.read(badLevels.player).swords[2].level, config.WeaponLevel.MaxLevel, "nivel guardado se recorta al tope")

-- Guardado real y migración de inventario: conserva elección, Pity y equipa solo lo guardado.
state.pity.traits[#config.Traits - 1] = 1
local saved = f.save()
local restored = fixture(saved)
equal(restored.data.read(restored.player).pity.traits[#config.Traits - 1], 1, "pity persiste")
equal(#restored.data.read(restored.player).loadout, 2, "las equipadas persisten")
local keptLevel = false
for _, copy in restored.data.read(restored.player).swords do
	keptLevel = keptLevel or copy.level == 2
end
equal(keptLevel, true, "el nivel de las armas persiste")
equal(restored.data.read(restored.player).swords[restored.data.read(restored.player).loadout[2]].sword, 5, "elección persiste al renumerar ids")
for _, value in { -2, 3.9, 99, 0 / 0, "4" } do
	local migrated = fixture({ rebirths = value })
	local expected = if value ~= value then 0 else math.clamp(math.floor(tonumber(value)), 0, 5)
	equal(migrated.data.read(migrated.player).rebirths, expected, "migración de renacimientos")
	equal(migrated.data.read(migrated.player).pity.traits[1], 0, "guardado antiguo sin pity")
end

-- Geometría de ataque: bordes, alturas, arcos de todas las armas y cajas rotadas.
local hitbox = f.load("src/shared/Hitbox")
local function target(x, y, z, sx, sy, sz, yaw)
	return { Size = Vector3.new(sx or 2, sy or 2, sz or 2), CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0) }
end
for _, arc in { 0.2, -1, 0.8, -0.3 } do
	equal(hitbox.reaches(target(0, 0, -5), CFrame.identity, 5, arc), true, "delante " .. arc)
	equal(hitbox.reaches(target(0, 8, -2), CFrame.identity, 5, arc), false, "fuera altura " .. arc)
	equal(hitbox.reaches(target(0, 0, -20), CFrame.identity, 5, arc), false, "fuera alcance " .. arc)
end
-- Círculo del jugador y a qué más llega cada tipo de arma: quien ataca está en el origen y su objetivo a 10 studs.
equal(hitbox.within(target(0, 0, -27), Vector3.zero, config.Loadout.Radius), true, "círculo: cuenta el borde de la caja")
equal(hitbox.within(target(0, 0, -30), Vector3.zero, config.Loadout.Radius), false, "fuera del círculo")
local aimed = Vector3.new(0, 3, -10)
for name, kind in config.WeaponKinds do
	local origin, range, arc = hitbox.spread(kind, 5, Vector3.zero, aimed)
	local reaches = function(x, z)
		return origin ~= nil and hitbox.reaches(target(x, 0, z), origin, range, arc)
	end
	if (kind.area or 0) > 0 then
		equal(reaches(kind.area * 5 - 0.5, -10), true, "salpica al lado " .. name)
		equal(reaches(0, -10 + kind.area * 5 - 0.5), true, "salpica hacia el jugador " .. name)
		equal(reaches(kind.area * 5 + 2, -10), false, "no salpica más allá " .. name)
	elseif (kind.pierce or 0) > 0 then
		equal(reaches(0, -10 - kind.pierce * 5 + 0.5), true, "atraviesa detrás " .. name)
		equal(reaches(0, -10 - kind.pierce * 5 - 2), false, "no atraviesa más allá " .. name)
		equal(reaches(0, -5), false, "no atraviesa hacia el jugador " .. name)
		equal(reaches(4, -12), false, "no atraviesa de lado " .. name)
	else
		equal(origin, nil, "un solo objetivo " .. name)
	end
end
equal(hitbox.reaches(target(0, 0, 4), CFrame.identity, 5, -1), true, "hacha detrás")
equal(hitbox.reaches(target(0, 0, 4), CFrame.identity, 5, 0.8), false, "lanza detrás")
equal(hitbox.reaches(target(5, 0, -3, 8, 2, 2), CFrame.identity, 5, 0.8), true, "caja cruza arco estrecho")
equal(hitbox.reaches(target(0, 0, -10, 12, 2, 2, math.pi / 2), CFrame.identity, 5, 0.8), true, "caja girada cerca con centro lejos")
equal(hitbox.reaches(target(10, 0, 0, 2, 2, 2), CFrame.identity, 5, -1), false, "caja lateral lejos")
equal(hitbox.reaches(target(0, 0, -6), CFrame.identity, 5, 0.8), true, "borde exacto")

-- Luces: día realmente apagado, noche, rendimiento y nuevas luces por streaming.
local map = f.workspace:FindFirstChild("Map")
local night, performance = 0, false
local changed = signal()
f.overrides["src/client/DayCycle"] = { night = function() return night end }
f.overrides["src/client/Performance"] = { get = function() return performance end, Changed = changed }
local light = Instance.new("PointLight")
light.Brightness, light.Enabled, light.Parent = 0, false, map
light:SetAttribute("Base", 2)
f.services.CollectionService:AddTag(light, "NightLight")
f.load("src/client/MapLights").start()
equal(light.Enabled, false, "luz de día apagada")
night = 0.5
f.services.RunService.Heartbeat:fire(0.1)
near(light.Brightness, 1, "atardecer gradual")
night = 1
f.services.RunService.Heartbeat:fire(0.1)
near(light.Brightness, 2, "noche encendida")
performance = true
changed:fire(true)
equal(light.Enabled, false, "rendimiento apaga")
night = 0
performance = false
changed:fire(false)
equal(light.Enabled, false, "restaurar de día no enciende")
local streamed = Instance.new("PointLight")
streamed.Parent = map
streamed:SetAttribute("Base", 3)
f.services.CollectionService:AddTag(streamed, "NightLight")
equal(streamed.Enabled, false, "luz nueva respeta día")

-- Teletransporte validado y sin espera entre destinos.
roblox.implementMethod("Model", "PivotTo", function(self, cframe) self:SetAttribute("TestPivot", cframe) end)
local function characterFor(who, position)
	local character = Instance.new("Model")
	character.Parent = f.workspace
	local root, humanoid = Instance.new("Part"), Instance.new("Humanoid")
	root.Name, root.Position, root.CFrame, root.Parent = "HumanoidRootPart", position, CFrame.new(position), character
	humanoid.Health, humanoid.Parent = 100, character
	who.Character = character
	return character, root, humanoid
end
local character, root, humanoid = characterFor(player, Vector3.new(0, 3, 0))
f.overrides["src/server/Plots"] = { get = function() return { spawn = { CFrame = CFrame.new(250, 0, 0) } } end }
f.overrides["src/server/DungeonLobby"] = { plazaCFrame = function() return CFrame.new(0, -80, 0) end }
f.load("src/server/Teleport").start()
f.remotes.Teleport.OnServerEvent:fire(player, "home")
f.remotes.Teleport.OnServerEvent:fire(player, "dungeon")
equal(#f.remotes.Teleported.sent, 2, "dos viajes inmediatos confirmados")
near(character:GetAttribute("TestPivot").Position.Y, -80, "último destino")
equal(root.AssemblyLinearVelocity, Vector3.zero, "velocidad al viajar")
for _, invalid in { "desconocido", 5, {} } do f.remotes.Teleport.OnServerEvent:fire(player, invalid) end
equal(#f.remotes.Teleported.sent, 2, "destinos inválidos sin confirmación")
humanoid.Health = 0
f.remotes.Teleport.OnServerEvent:fire(player, "home")
equal(#f.remotes.Teleported.sent, 2, "muerto no viaja")

-- Aparición real con reloj controlado: protege visitantes y no repite una tirada bloqueada.
local spawn = fixture(nil)
local visitor = Instance.new("Player")
visitor.Parent = spawn.workspace
table.insert(spawn.players, visitor)
local visitorCharacter, visitorRoot = Instance.new("Model"), Instance.new("Part")
visitorCharacter.Parent = spawn.workspace
visitorRoot.Name, visitorRoot.Position, visitorRoot.Parent = "HumanoidRootPart", Vector3.new(0, 3, 0), visitorCharacter
visitor.Character = visitorCharacter
local plot = { cframe = CFrame.identity, size = 100, spawnOffset = Vector3.new(0, 0, -44), owner = spawn.player }
spawn.overrides["src/server/Plots"] = { all = function() return { plot } end, get = function() return plot end, onRelease = function() end }
spawn.overrides["src/shared/ObjectModel"] = { attach = function() end }
spawn.overrides["src/shared/Chance"] = { roll = function() return false end }
local specs = spawn.load("src/shared/ObjectSpec")
local rolls = 0
specs.roll = function()
	rolls += 1
	return { quality = 1, size = 1, scale = 1, visual = 1, hp = 10, luck = 99, rolls = 1, reward = 1, odds = 1 }
end
spawn.load("src/server/Destructibles").start()
spawn.step(2)
equal(#spawn.workspace:FindFirstChild("Destructibles"):GetChildren(), 0, "no aparece sobre visitante")
spawn.step(2)
equal(rolls, 1, "bloqueado no vuelve a tirar")
visitorRoot.Position = Vector3.new(80, 3, 0)
spawn.step(2)
local objects = spawn.workspace:FindFirstChild("Destructibles"):GetChildren()
equal(#objects, 1, "aparece al quedar libre")
equal(objects[1]:GetAttribute("Luck"), 99, "conserva la tirada pendiente")
equal(objects[1].Anchored, true, "destructible fijo")

-- Colisiones del mapa con las mallas reales: el torii conserva el paso y la escala no se aplica dos veces.
local meshes = roblox.deserializeModel(fs.readFile("src/shared/MapMeshes.rbxm"))[1]
for _, part in meshes:GetDescendants() do
	if part:IsA("BasePart") then part.Position = part.CFrame.Position end
end
local propEnv = table.clone(roblox)
propEnv.script = { Parent = { FindFirstChild = function(_, name) return if name == "MapMeshes" then meshes else nil end } }
local props = luau.load(fs.readFile("src/shared/PropModel.luau"), { environment = propEnv, injectGlobals = true })()
local torii = assert(props.place(f.workspace, "Torii", CFrame.identity, 1))
local solid = 0
for _, part in torii:GetChildren() do
	if part.Name == "MapCollision" then
		solid += 1
		equal(hitbox.reaches(part, CFrame.new(0, 3, 0), 0.1, -1), false, "paso del torii libre")
	end
end
equal(solid, 4, "columnas y dinteles sólidos")
local rocks = assert(props.place(f.workspace, "Rocks", CFrame.new(50, 0, 20), 3))
local stone, collision = rocks:FindFirstChild("Stone"), rocks:FindFirstChild("MapCollision")
near((stone.CFrame.Position - collision.CFrame.Position).Magnitude, 0, "rocas: colisión alineada a escala tres")
near((stone.Size - collision.Size).Magnitude, 0, "rocas: tamaño de colisión")

-- Números flotantes: pop de impacto, apagado al final y cajas más cortas que enemigos.
local float = f.load("src/client/FloatText")
local still = { life = 1, scale = 1, drift = 0, rotation = 0 }
local styles = float.STYLES
near(float.sample(styles.enemy, 0, still), 0.7, "daño sale pequeño")
equal(float.sample(styles.enemy, styles.enemy.popIn, still) > 1, true, "pop de impacto")
equal(select(5, float.sample(styles.enemy, styles.enemy.life, still)), 1, "daño apagado al final")
equal(select(5, float.sample(styles.coin, 0.3, still)), 0, "moneda visible tras el pop")
equal(select(3, float.sample(styles.coin, 0, still)) < 0, true, "moneda sale por debajo")
equal(styles.box.life < styles.enemy.life, true, "caja más corta que enemigo")

-- Clima: las probabilidades de los tramos suman 1 y la suerte del clima en curso entra por Stats y se va al despejar.
local weather = f.load("src/shared/WeatherInfo")
local stats = f.load("src/shared/Stats")
local events = f.config.Weather.Events
local chances = 0
for _, id in f.config.Weather.Order do
	chances += weather.chance(id)
end
near(chances, 1, "las probabilidades del clima suman 1")
local spawnBefore, gachaBefore = stats.spawnLuck(f.player), stats.gachaLuck(f.player)
f.workspace:SetAttribute("Weather", "starfall")
near(stats.spawnLuck(f.player) / spawnBefore, events.starfall.luck, "el clima da suerte de destructibles")
near(stats.gachaLuck(f.player) / gachaBefore, events.starfall.weaponLuck, "los climas raros dan suerte de armas")
f.workspace:SetAttribute("Weather", "rain")
near(stats.spawnLuck(f.player) / spawnBefore, events.rain.luck, "la lluvia da su suerte de destructibles")
near(stats.gachaLuck(f.player) / gachaBefore, 1, "la lluvia no da suerte de armas")
f.workspace:SetAttribute("Weather", "")
near(stats.spawnLuck(f.player) / spawnBefore, 1, "despejado: la suerte vuelve a ser la de antes")

-- Eventos de admin (Stats.boost): el multiplicador entra solo en su stat y se va al caducar.
local damageBefore, coinsBefore = stats.damage(f.player), stats.coins(f.player)
f.workspace:SetAttribute("Boost_luck", 3)
f.workspace:SetAttribute("BoostEnd_luck", 60)
f.workspace:SetAttribute("Boost_damage", 2)
f.workspace:SetAttribute("BoostEnd_damage", 60)
near(stats.spawnLuck(f.player) / spawnBefore, 3, "el evento de admin da suerte de cajas")
near(stats.gachaLuck(f.player) / gachaBefore, 1, "el evento de suerte de cajas no toca la suerte de armas")
near(stats.damage(f.player) / damageBefore, 2, "el evento de admin multiplica el daño")
near(stats.coins(f.player) / coinsBefore, 1, "y no toca las monedas")
near(stats.boost("gradeLuck"), 1, "sin evento de grados, su suerte es 1")
f.workspace:SetAttribute("BoostEnd_luck", -1)
near(stats.spawnLuck(f.player) / spawnBefore, 1, "un evento caducado ya no cuenta")
for _, name in { "Boost_luck", "BoostEnd_luck", "Boost_damage", "BoostEnd_damage" } do
	f.workspace:SetAttribute(name, nil)
end
near(stats.damage(f.player) / damageBefore, 1, "sin eventos, el daño es el de antes")

-- Equilibrio de progresión (tools/equilibrio): lo que no debe romperse al tocar Config.
local upgrades = f.load("src/shared/Upgrades")
local objectSpec = f.load("src/shared/ObjectSpec")
local armorStats = f.load("src/shared/ArmorStats")
for name, upgrade in f.config.Upgrades do
	equal(upgrade.costs ~= nil and #upgrade.costs, upgrade.maxLevel, "un precio por nivel de " .. name)
	for level = 1, upgrade.maxLevel - 1 do
		equal(upgrades.cost(name, level) > upgrades.cost(name, level - 1), true, `precio creciente de {name} {level}`)
	end
end
equal(f.config.Upgrades.speed, nil, "sin mejora de velocidad de golpe")
equal(#f.config.Rebirth.costs, f.config.Rebirth.max, "un precio por renacimiento")
-- Presupuesto de suerte: la mejora al máximo con todos los renacimientos no agota los tipos de objeto.
local rarest = f.config.Destructibles[#f.config.Destructibles]
local luckMax = upgrades.value("luck", f.config.Upgrades.luck.maxLevel) * f.config.Rebirth.luck ^ f.config.Rebirth.max
equal(luckMax < rarest.rarity, true, "la mejora de suerte y los renacimientos no agotan los tipos de objeto")
-- Objetos menos gigantes: la pieza crece menos que la escala que cuenta y cabe en la huella de Config.
for _, def in f.config.Destructibles do
	local _, highest = objectSpec.scaleLimits(def)
	local visual = objectSpec.visualScale(def, highest)
	equal(visual <= highest and visual >= math.min(highest, 1), true, `escala visible acotada de {def.name}`)
	local rolls = f.config.ObjectRolls
	equal(visual <= 1 or (def.size.X * visual <= rolls.VisualMaxWidth + 0.1 and def.size.Y * visual <= rolls.VisualMaxHeight + 0.1), true, `huella visible de {def.name}`)
end
-- La parcela crece con los renacimientos en múltiplos de 20 (la valla) y sin pasar del tope.
local plotStats = f.load("src/shared/Stats")
for rebirths = 0, 30 do
	local side = plotStats.plotSize(rebirths)
	equal(side % 20 == 0 and side >= f.config.Plot.Size and side <= f.config.Plot.MaxSize, true, `medida de parcela con {rebirths} renacimientos`)
end
-- El arma más rara (con el mejor metal y el mejor tamaño, Etherio y Universal: decidido por el usuario el 18-10-2026,
-- no la mejor arma a secas) sigue siéndolo con toda la suerte al máximo, y ni el mejor objeto posible la garantiza.
local top = 0
for sword in f.config.Swords do
	top = math.max(top, permanent.rarity(sword, #f.config.Metals, #f.config.Sizes))
end
local gachaMax = f.config.Rebirth.gachaLuck ^ f.config.Rebirth.max
local _, highest = objectSpec.scaleLimits(rarest)
equal(objectSpec.luck(rarest, 1, 1) * gachaMax / top < 1e-4, true, "el arma más rara es rara con la suerte al máximo")
equal(objectSpec.luck(rarest, #f.config.ObjectRarities, highest) * gachaMax / top < 0.05, true, "ni el mejor objeto la garantiza")
-- Ni con el consumible de suerte (x1000 a la suerte de armas de un objeto) y la mejor poción de suerte de armas sale
-- de un objeto corriente del tipo más raro a la primera. Eran cientos de usos; con la suerte de más del Génesis (decidido
-- por el usuario el 17-10-2026: los objetos del endgame tienen que valer la pena) son una docena.
local weaponPotion = f.config.Potions.Families.weaponLuck.values
equal(objectSpec.luck(rarest, 1, 1) * gachaMax * weaponPotion[#weaponPotion] * 1000 / top < 0.1, true, "el consumible de suerte no regala el arma más rara")
-- Fortuna: mejora de monedas que se paga con gemas.
local fortune = f.config.Upgrades.fortune
equal(fortune.currency, "gems", "Fortuna se paga con gemas")
equal(table.find(f.config.UpgradeOrder, "fortune") ~= nil, true, "Fortuna está en el árbol")
local coinsBefore = stats.coins(f.player)
f.player:SetAttribute("Upgrade_fortune", 2)
near(stats.coins(f.player) / coinsBefore, fortune.perLevel ^ 2, "Fortuna multiplica las monedas")
f.player:SetAttribute("Upgrade_fortune", 0)
-- Monedas de bolsa: una por bolsa vaciada menos lo gastado en la mejora, que multiplica todas las monedas.
local bagBoost = f.config.Upgrades.bagBoost
equal(bagBoost.currency, "bag", "Bolsa dorada se paga con monedas de bolsa")
equal(stats.wallet(f.player, "bag"), 0, "sin bolsas vaciadas no hay monedas de bolsa")
f.player:SetAttribute("BagStage", 7)
equal(stats.wallet(f.player, "bag"), 6, "una moneda de bolsa por bolsa vaciada")
f.player:SetAttribute("Upgrade_bagBoost", 2)
equal(stats.wallet(f.player, "bag"), 6 - bagBoost.costs[1] - bagBoost.costs[2], "lo gastado sale del nivel comprado")
near(stats.coins(f.player) / coinsBefore, bagBoost.perLevel ^ 2, "Bolsa dorada multiplica las monedas")
f.player:SetAttribute("Upgrade_bagBoost", 0)
f.player:SetAttribute("BagStage", nil)
-- El tamaño y la rareza del objeto pesan de verdad en la suerte de armas.
equal(objectSpec.luck(rarest, 1, 2) / objectSpec.luck(rarest, 1, 1) >= 8, true, "el tamaño pesa en la suerte de armas")
equal(objectSpec.luck(rarest, #f.config.ObjectRarities, 1) / objectSpec.luck(rarest, 1, 1) >= 20, true, "la rareza pesa en la suerte de armas")
-- Velocidad de golpe: tiempo base por el tipo de arma, sin nada que lo baje.
local swingBefore = stats.cooldown(f.player)
local _, weaponKind = stats.weapon(f.player)
near(swingBefore, f.config.BaseCooldown * weaponKind.cooldown, "tiempo base entre golpes")
-- Armadura: la vida escala con el power de la zona, los porcentajes con su bonus, y lo guardado de antes se recorta.
local lastZone = #f.config.Dungeons
equal(armorStats.scaling("health", lastZone), f.config.Dungeons[lastZone].power, "la vida de la armadura escala con el power")
equal(armorStats.scaling("luck", lastZone), f.config.Dungeons[lastZone].bonus, "los porcentajes escalan con el bonus")
equal(armorStats.scaling("rollSpeed", lastZone), 1, "la aparición no escala")
equal(armorStats.cap("luck", #f.config.Armor.Qualities, lastZone) < 20, true, "tope de suerte de una pieza")
local oldArmor = fixture({ armor = { { id = 1, slot = "helmet", quality = 1, level = lastZone, stats = { { stat = "luck", value = 1e6 } } } } })
equal(oldArmor.data.read(oldArmor.player).armor[1].stats[1].value <= armorStats.cap("luck", 1, lastZone), true, "armadura guardada recortada")

-- Mazmorras: la escalera de zonas no tiene saltos raros y los premios no se disparan (antes: cristales x2048 y calidad x12000).
local zones = f.config.Dungeons
equal(zones[1].loot, 1, "la primera zona da los cristales de base")
equal(zones[1].qualityLuck, 1, "la primera zona da la calidad de base")
for index = 2, #zones do
	local zone, before = zones[index], zones[index - 1]
	local step = zone.hp / before.hp
	equal(step >= 3 and step <= 60, true, `salto de daño recomendado de {before.name} a {zone.name}`)
	equal(zone.loot >= before.loot and zone.loot <= 10, true, "cristales de " .. zone.name)
	equal(zone.qualityLuck >= before.qualityLuck and zone.qualityLuck <= 40, true, "calidad de " .. zone.name)
	equal(zone.bonus >= before.bonus, true, "bonus de " .. zone.name)
end
equal(f.config.Items.traitCrystal.dropChance <= 0.02, true, "cristal de rasgo de la parcela escaso")
-- La armadura Mítica de la última zona es una meta larga: ni el jefe la suelta más de 1 vez de cada 100.
local mythic = f.config.Armor.Qualities[#f.config.Armor.Qualities]
for _, enemy in f.config.Enemies do
	for _, drop in enemy.drops do
		if drop.kind == "armor" then
			equal(zones[lastZone].qualityLuck * (drop.luck or 1) / mythic.odds <= 0.01, true, "armadura Mítica rara con " .. enemy.name)
		end
	end
end
-- Cantidades con decimales: la parte decimal es la probabilidad de uno más, nunca menos de uno.
local loot = f.load("src/server/Loot")
local realNumber = f.random.NextNumber
equal(loot.amount({}, 1), 1, "un cristal con x1")
equal(loot.amount({}, 3), 3, "x3 exacto")
f.random.NextNumber = function() return 0.39 end
equal(loot.amount({}, 1.4), 2, "x1.4: uno más cuando toca")
f.random.NextNumber = function() return 0.41 end
equal(loot.amount({}, 1.4), 1, "x1.4: uno cuando no toca")
f.random.NextNumber = realNumber
-- Desmontar: solo cuenta la calidad de la pieza, y las corrientes no dan cristales.
equal(armorStats.salvage({ quality = 1, level = lastZone }), 0, "desmontar una pieza Común no da cristales")
equal(armorStats.salvage({ quality = #f.config.Armor.Qualities, level = 1 }), armorStats.salvage({ quality = #f.config.Armor.Qualities, level = lastZone }), "desmontar no depende de la zona")
equal(armorStats.salvage({ quality = #f.config.Armor.Qualities, level = 1 }) > 0, true, "desmontar una Mítica da cristales")

-- Comercio: ni monedas ni gemas, ni ofrecidas ni sugeridas; los cristales sí. (Con el bot de pruebas, que solo hay en Studio.)
equal(f.config.Trade.Allow.coins, nil, "las monedas no se comercian")
equal(f.config.Trade.Allow.gems, nil, "las gemas no se comercian")
local tf = fixture(nil)
tf.config.Test.TradeBot = true
tf.services.RunService.IsStudio = function() return true end
tf.load("src/server/Trade").start()
tf.data.edit(tf.player, function(d)
	d.coins, d.gems = 1e6, 1e6
	d.items.gradeCrystal = 3
	-- Tréboles: 2 atados a la cuenta (de códigos o del tutorial) y 1 comprado.
	d.items.luckClover = 1
	tf.data.giveBound(d, "luckClover", 2)
end)
tf.advance(10)
-- Sin renacer no se comercia (Config.Trade.MinRebirths).
tf.remotes.TradeRequest.OnServerEvent:fire(tf.player, 0)
equal(#tf.remotes.TradeState.sent, 0, "sin renacer no se abre el trato")
tf.data.edit(tf.player, function(d)
	d.rebirths = 1
end)
tf.advance(10)
tf.remotes.TradeRequest.OnServerEvent:fire(tf.player, 0)
local function tradeState()
	local sent = tf.remotes.TradeState.sent
	return sent[#sent][2]
end
equal(tradeState().state, "editing", "trato abierto con el bot")
-- Los atados no se ofrecen: de 3 tréboles solo se puede dar 1.
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "items", "luckClover", 2)
equal(tradeState().you.items.luckClover, nil, "los tréboles atados no se ofrecen")
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "items", "luckClover", 1)
equal(tradeState().you.items.luckClover, 1, "el trébol comprado sí se ofrece")
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "items", "luckClover", 0)
-- Al gastar se van antes los atados.
tf.data.edit(tf.player, function(d)
	tf.data.spendItem(d, "luckClover", 1)
end)
equal(tf.data.tradable(tf.data.read(tf.player), "luckClover"), 1, "gastar uno se lleva un atado")
tf.data.edit(tf.player, function(d)
	tf.data.spendItem(d, "luckClover", 2)
end)
equal(tf.data.read(tf.player).bound.luckClover, nil, "gastados todos, no quedan atados")
equal(tradeState().them.coins, 0, "el bot no ofrece monedas")
equal(tradeState().them.gems, 0, "el bot no ofrece gemas")
equal(tradeState().them.items.traitCrystal > 0, true, "el bot ofrece cristales")
for _, currency in { "coins", "gems" } do
	tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, currency, nil, 5)
	equal(tradeState().you[currency], 0, "oferta rechazada: " .. currency)
	tf.advance(1)
	tf.remotes.TradeSuggest.OnServerEvent:fire(tf.player, "want", currency, nil, 5)
	equal(tradeState().you.suggest, nil, "sugerencia rechazada: quiero " .. currency)
	tf.advance(1)
	tf.remotes.TradeSuggest.OnServerEvent:fire(tf.player, "give", currency, nil, 5)
	equal(tradeState().you.suggest, nil, "sugerencia rechazada: te doy " .. currency)
end
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "items", "gradeCrystal", 2)
equal(tradeState().you.items.gradeCrystal, 2, "los cristales sí se ofrecen")
-- Las equipadas no se ofrecen, estén en el hueco que estén.
tf.data.edit(tf.player, function(d)
	d.swords[2] = { id = 2, sword = 4 }
	d.swords[3] = { id = 3, sword = 5 }
	d.nextSwordId = 4
	d.loadout = { 1, 2 }
end)
tf.advance(1)
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "swords", 2, 1)
equal(next(tradeState().you.swords), nil, "una equipada en el segundo hueco no se ofrece")
-- Tampoco las depositadas en la Bolsa de oro.
tf.data.edit(tf.player, function(d) d.bag.slots = { 3 } end)
tf.advance(1)
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "swords", 3, 1)
equal(next(tradeState().you.swords), nil, "una depositada en la bolsa no se ofrece")
tf.data.edit(tf.player, function(d) d.bag.slots = {} end)
tf.advance(1)
tf.remotes.TradeOffer.OnServerEvent:fire(tf.player, "swords", 3, 1)
equal(next(tradeState().you.swords) ~= nil, true, "una sin equipar sí se ofrece")
tf.remotes.TradeCancel.OnServerEvent:fire(tf.player)
equal(tf.data.read(tf.player).coins, 1e6, "el trato cancelado no toca las monedas")
-- Con la mochila llena el trato se cierra igual: el arma del bot, mejor, echa a la peor sin equipar.
tf.data.edit(tf.player, function(d)
	d.swords = {}
	for id = 1, f.config.MaxSwords do
		d.swords[id] = { id = id, sword = 1 }
	end
	d.nextSwordId = f.config.MaxSwords + 1
	d.loadout = { 1 }
end)
tf.advance(10)
-- Lo que espera (el bot acepta al segundo, la cuenta atrás) pasa en el momento.
local realDelay = tf.task.delay
tf.task.delay = function(_, fn, ...) fn(...) end
tf.remotes.TradeRequest.OnServerEvent:fire(tf.player, 0)
tf.advance(1)
tf.remotes.TradeAccept.OnServerEvent:fire(tf.player, true)
tf.advance(1)
tf.remotes.TradeConfirm.OnServerEvent:fire(tf.player)
tf.task.delay = realDelay
local fullAfter = tf.data.read(tf.player)
equal(#fullAfter.swords, f.config.MaxSwords, "mochila llena: sigue en el tope tras el trato")
equal(fullAfter.swords[#fullAfter.swords].sword, 8, "mochila llena: el arma recibida se queda")
equal(tf.data.findSword(fullAfter, 1) ~= nil, true, "mochila llena: la equipada no se quita")
equal(fullAfter.items.traitCrystal > 0, true, "mochila llena: el trato se ha hecho")

-- Varias armas equipadas (Config.Loadout.Slots): poner, quitar, sustituir a la de menos daño y "best"; y las cuentas de
-- Stats: el daño se suma, la suerte y las monedas de los rasgos se multiplican y el grado va al daño, no a las monedas.
do
	local ef = fixture(nil)
	ef.load("src/server/Gacha").start()
	local cfg = ef.config
	local eStats = ef.load("src/shared/Stats")
	local slots = cfg.Loadout.Slots
	equal(slots, 4, "huecos de arma")
	-- Config.Swords no va por daño: la copia k lleva la k-ésima arma de menos daño, así su daño crece con el id.
	local byDamage = {}
	for index in cfg.Swords do table.insert(byDamage, index) end
	table.sort(byDamage, function(a, b) return cfg.Swords[a].damage < cfg.Swords[b].damage end)
	ef.data.edit(ef.player, function(d)
		d.swords = {}
		for id = 1, slots + 2 do d.swords[id] = { id = id, sword = byDamage[id] } end
		d.nextSwordId = slots + 3
		d.loadout = { 1 }
	end)
	local function equip(id) ef.remotes.EquipSword.OnServerEvent:fire(ef.player, id) end
	local function worn() return table.concat(ef.data.read(ef.player).loadout, ",") end
	equip(1)
	equal(worn(), "", "se pueden quitar todas")
	equal(ef.player:GetAttribute("Loadout"), "", "sin armas, huecos vacíos")
	equal(eStats.damage(ef.player), 0, "sin armas equipadas no hay daño")
	for id = 1, slots do equip(id) end
	equal(worn(), "1,2,3,4", "se equipan hasta llenar los huecos")
	equal(ef.player:GetAttribute("Loadout"), "1,2,3,4", "huecos publicados")
	equip(2)
	equal(worn(), "1,3,4", "pulsar una equipada la quita")
	equip(2)
	equal(worn(), "1,3,4,2", "y vuelve al primer hueco libre")
	equip(slots + 2)
	equal(worn(), "6,3,4,2", "sin huecos sustituye a la de menos daño")
	for _, bad in { 999, "x", 0 / 0, {}, true, -1, 1.5 } do
		equip(bad)
		equal(worn(), "6,3,4,2", "equipar algo que no existe no cambia nada")
	end
	equip("best")
	equal(worn(), "6,5,4,3", "las mejores: las de más daño, de mayor a menor")
	ef.remotes.SellSwords.OnServerEvent:fire(ef.player, { 1, 2, 3, 4, 5, 6 })
	equal(#ef.data.read(ef.player).swords, slots, "la venta respeta todas las equipadas")
	equal(worn(), "6,5,4,3", "vender no toca los huecos")

	local function sum()
		local total = 0
		for _, copy in eStats.loadout(ef.player) do total += eStats.swordDamage(copy) end
		return total
	end
	equal(#eStats.loadout(ef.player), slots, "Stats lee las equipadas")
	equal(eStats.loadout(ef.player)[1].id, 6, "Stats respeta el orden de los huecos")
	equal(eStats.isEquipped(ef.player, 3), true, "Stats: equipada")
	equal(eStats.isEquipped(ef.player, 2), false, "Stats: vendida, no equipada")
	near(eStats.damage(ef.player), sum(), "el daño es la suma de las equipadas")
	near(eStats.weaponDamage(ef.player, eStats.loadout(ef.player)[2]), cfg.Swords[byDamage[5]].damage, "cada arma pega con su daño")
	local luck, coins, damage = eStats.luck(ef.player), eStats.coins(ef.player), eStats.damage(ef.player)
	local top = cfg.Traits[#cfg.Traits]
	ef.data.edit(ef.player, function(d)
		ef.data.findSword(d, 6).trait = #cfg.Traits
		ef.data.findSword(d, 5).trait = #cfg.Traits
	end)
	near(eStats.luck(ef.player) / luck, top.luck ^ 2, "la suerte de los rasgos se multiplica entre armas")
	near(eStats.coins(ef.player) / coins, top.coins ^ 2, "las monedas de los rasgos se multiplican entre armas")
	near(eStats.damage(ef.player) - damage, (cfg.Swords[byDamage[6]].damage + cfg.Swords[byDamage[5]].damage) * (top.damage - 1), "el daño del rasgo solo sube el de su arma")
	equal(top.luck <= 2 and top.coins <= 2, true, "rasgos: suerte y monedas bajas (se multiplican entre las equipadas)")
	coins, damage = eStats.coins(ef.player), eStats.damage(ef.player)
	local best = cfg.Grades[#cfg.Grades]
	ef.data.edit(ef.player, function(d) ef.data.findSword(d, 3).grade = #cfg.Grades end)
	near(eStats.coins(ef.player), coins, "los grados ya no dan monedas")
	near(eStats.damage(ef.player) - damage, cfg.Swords[byDamage[3]].damage * (best.damage - 1), "el grado multiplica el daño de su arma")
	for _, grade in cfg.Grades do
		equal(grade.coins == nil and grade.damage > 1, true, "grado " .. grade.name .. ": daño y no monedas")
	end
	-- Una sin equipar no cuenta para nada.
	ef.data.edit(ef.player, function(d)
		table.insert(d.swords, { id = d.nextSwordId, sword = byDamage[#byDamage], trait = #cfg.Traits, grade = #cfg.Grades })
		d.nextSwordId += 1
	end)
	near(eStats.coins(ef.player), coins, "un arma sin equipar no da monedas")
	near(eStats.damage(ef.player) - damage, cfg.Swords[byDamage[3]].damage * (best.damage - 1), "un arma sin equipar no da daño")

	-- Lo guardado: sin repetidos, sin ids que no existan y como mucho los huecos que hay.
	local six = {}
	for id = 1, 6 do six[id] = { id = id * 10, sword = 3 + id } end
	local function loaded(saved) local g = fixture(saved); return table.concat(g.data.read(g.player).loadout, ",") end
	equal(loaded({ swords = six, loadout = { 30, 30, 990, "x", 20, 0 / 0, 50, 60, 10 } }), "3,2,5,6,1", "equipadas guardadas: limpias (el tope al cargar es MaxSlots, el del pase)")
	local nine = {}
	for id = 1, 9 do nine[id] = { id = id, sword = 3 + id } end
	equal(loaded({ swords = nine, loadout = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } }), "1,2,3,4,5,6,7,8", "equipadas guardadas: hasta el tope")
	equal(loaded({ swords = six, loadout = "x", equipped = 20 }), "2", "lista rota: vale la antigua")
	equal(loaded({ swords = six, loadout = {} }), "", "lista vacía: se queda sin armas equipadas")
	equal(loaded({ swords = six, loadout = { 990 }, equipped = 20 }), "", "lista sin ninguna válida: sin armas equipadas")
	equal(loaded({ swords = six, equipped = 40 }), "4", "guardado antiguo: su única equipada")
end

-- Guardado: lo que se guarda vuelve igual, lo antiguo se completa con valores por defecto y lo roto se limpia sin dar
-- error ni llevarse por delante lo válido. (El DataStore es un doble: lo que pase en Roblox de verdad solo se ve publicado.)
do
	local cfg = f.config
	local potionInfo = f.load("src/shared/PotionInfo")
	local nan, huge = 0 / 0, math.huge
	local function same(actual, expected, label: string)
		local function walk(a, b, path)
			if type(a) == "table" and type(b) == "table" then
				for key, value in b do walk(a[key], value, path .. "." .. tostring(key)) end
				for key in a do assert(b[key] ~= nil, `{label}: sobra {path}.{tostring(key)}`) end
			else
				assert(a == b, `{label}: {path} esperado {tostring(b)}, recibido {tostring(a)}`)
			end
		end
		walk(actual, expected, "datos")
		checks += 1
	end
	local function loadSaved(saved)
		local g = fixture(saved)
		return g.data.read(g.player), g
	end
	-- Lo que tiene que cumplir cualquier partida cargada, venga de donde venga.
	local function sane(d, label: string)
		local ok = d.coins >= 0 and d.gems >= 0 and d.playTime >= 0 and d.totalCoins >= 0 and d.robuxSpent >= 0 and d.autoSell >= 0
		ok = ok and d.rebirths >= 0 and d.rebirths <= cfg.Rebirth.max and d.rebirths % 1 == 0
		ok = ok and #d.swords >= 1 and #d.swords <= cfg.MaxSwords and d.nextSwordId == #d.swords + 1 and #d.loadout >= 1 and #d.loadout <= cfg.Loadout.MaxSlots
		for position, id in d.loadout do
			ok = ok and d.swords[id] ~= nil and table.find(d.loadout, id) == position
		end
		for position, copy in d.swords do
			ok = ok and copy.id == position and cfg.Swords[copy.sword] ~= nil
			ok = ok and (copy.trait == nil or cfg.Traits[copy.trait] ~= nil) and (copy.grade == nil or cfg.Grades[copy.grade] ~= nil)
			ok = ok and (copy.metal == nil or cfg.Metals[copy.metal] ~= nil) and (copy.size == nil or cfg.Sizes[copy.size] ~= nil)
		end
		for name in cfg.Items do
			ok = ok and type(d.items[name]) == "number" and d.items[name] >= 0
		end
		for name, upgrade in cfg.Upgrades do
			local level = d.upgrades[name]
			ok = ok and type(level) == "number" and level >= 0 and level <= upgrade.maxLevel and level % 1 == 0
		end
		local artifactCopies = {}
		for _, index in d.artifacts do
			artifactCopies[index] = (artifactCopies[index] or 0) + 1
			ok = ok and cfg.Artifacts[index] ~= nil and artifactCopies[index] <= cfg.ArtifactCopies
		end
		ok = ok and #d.gear <= cfg.GearSlots
		for position, index in d.gear do
			ok = ok and table.find(d.artifacts, index) ~= nil and table.find(d.gear, index) == position
		end
		ok = ok and #d.armor <= cfg.Armor.MaxPieces and d.nextArmorId == #d.armor + 1
		for position, piece in d.armor do
			ok = ok and piece.id == position and cfg.Armor.Slots[piece.slot] ~= nil and cfg.Armor.Qualities[piece.quality] ~= nil and cfg.Dungeons[piece.level] ~= nil
			for _, entry in piece.stats do
				ok = ok and cfg.Armor.Stats[entry.stat] ~= nil and entry.value >= 0 and entry.value <= armorStats.cap(entry.stat, piece.quality, piece.level)
			end
		end
		for slot, id in d.armorWorn do
			ok = ok and d.armor[id] ~= nil and d.armor[id].slot == slot
		end
		for family, potion in d.potions do
			ok = ok and cfg.Potions.Families[family].values[potion.tier] ~= nil and potion.seconds > 0 and potion.seconds <= potionInfo.cap(potion.tier)
		end
		for _, kind in { "traits", "grades" } do
			equal(#d.pity[kind], #modifiers.KINDS[kind].list, label .. ": un contador de pity por " .. kind)
			for index, count in d.pity[kind] do
				ok = ok and count >= 0 and count <= modifiers.pityLimit(kind, index) and count % 1 == 0
			end
		end
		equal(ok, true, label .. ": partida cargada coherente")
	end
	-- Cargar, guardar y volver a cargar: lo cargado es coherente, se puede guardar y vuelve igual.
	local function stable(saved, label: string)
		local first, g = loadSaved(saved)
		sane(first, label)
		local kept = stored(first)
		same(loadSaved(g.save()), kept, label .. ": guardar y volver a cargar")
		return first, g
	end

	-- Ida y vuelta de una partida con de todo (ids sin renumerar, números enormes, lo último de cada lista de Config).
	local lastSword, lastTrait, lastGrade, lastMetal, lastSize = #cfg.Swords, #cfg.Traits, #cfg.Grades, #cfg.Metals, #cfg.Sizes
	local lastArtifact, lastQuality = #cfg.Artifacts, #cfg.Armor.Qualities
	local potionKey = cfg.Potions.ItemKeys[#cfg.Potions.ItemKeys]
	local topTier = #cfg.Potions.Families.coins.values
	local pity = { traits = {}, grades = {} }
	for kind, counters in pity do
		for index in modifiers.KINDS[kind].list do counters[index] = if modifiers.hasPity(kind, index) then math.min(index, modifiers.pityLimit(kind, index)) else 0 end
	end
	local levels = {}
	for name, upgrade in cfg.Upgrades do levels[name] = if name == "luck" then upgrade.maxLevel else 1 end
	local missions = { daily = { id = 20000, progress = { romper = 3 }, claimed = {} }, weekly = { id = 2800, progress = { tirar = 50 }, claimed = { tirar = true } } }
	local helmetStats = {
		{ stat = "health", value = armorStats.cap("health", lastQuality, lastZone) / 2 },
		{ stat = "luck", value = armorStats.cap("luck", lastQuality, lastZone) / 2, bonus = true },
	}
	local bootStats = { { stat = "health", value = armorStats.cap("health", 1, 1) / 2 } }
	local full = {
		coins = 1e30, gems = 2.5e33, rebirths = 3, playTime = 12345.5, totalCoins = 1e40, robuxSpent = 499, broken = 1234, passes = { vip = true }, receipts = { "compra-1" }, codes = { HOLA = true }, tutorial = 3,
		missions = missions, autoSell = 1e24, traitPriority = "damage,coins,luck", pity = pity,
		stopAt = { traits = { 10, 8, 99, 1, 8, 2.5 }, grades = {} },
		swords = {
			{ id = 10, sword = 1 },
			{ id = 20, sword = lastSword, trait = lastTrait, grade = lastGrade, metal = lastMetal, size = lastSize },
			{ id = 30, sword = 4, trait = 1 },
			{ id = 40, sword = 5, metal = 1, size = 1 },
		},
		loadout = { 20, 40 },
		bag = { stage = 7, taken = 3, slots = { 30 }, seen = 123456 },
		index = { code(4, 1, 1), code(lastSword, lastMetal, lastSize) },
		items = { traitCrystal = 1e30, gradeCrystal = 7, [potionKey] = 3 },
		-- Atados: nunca más de los que tiene, y sin los que no tiene.
		bound = { gradeCrystal = 9, [potionKey] = 2, missionToken = 4 },
		artifacts = { 1, lastArtifact, 2 }, gear = { lastArtifact, 1 },
		armor = {
			{ id = 11, slot = "helmet", quality = lastQuality, level = lastZone, stats = helmetStats },
			{ id = 12, slot = "boots", quality = 1, level = 1, stats = bootStats },
			{ id = 13, slot = "helmet", quality = 1, level = 1, stats = {} },
		},
		armorWorn = { helmet = 11, boots = 12 }, armorHidden = true,
		potions = { damage = { tier = 3, seconds = 120 }, coins = { tier = topTier, seconds = 1.5 } },
		daily = { day = 20000, seconds = 1800.5, claimed = { 2, 1 }, streak = 4, streakDay = 19999 },
		upgrades = levels,
	}
	local items = {}
	for name in cfg.Items do items[name] = 0 end
	items.traitCrystal, items.gradeCrystal, items[potionKey] = 1e30, 7, 3
	local expected = {
		coins = 1e30, gems = 2.5e33, rebirths = 3, playTime = 12345.5, totalCoins = 1e40, robuxSpent = 499, broken = 1234, passes = { vip = true }, receipts = { "compra-1" }, codes = { HOLA = true }, tutorial = 3,
		missions = missions, autoSell = 1e24, traitPriority = "damage,coins,luck", pity = pity,
		stopAt = { traits = { 8, 10 }, grades = {} },
		swords = {
			{ id = 1, sword = 1 },
			{ id = 2, sword = lastSword, trait = lastTrait, grade = lastGrade, metal = lastMetal, size = lastSize },
			{ id = 3, sword = 4, trait = 1 },
			{ id = 4, sword = 5, metal = 1, size = 1 },
		},
		nextSwordId = 5, loadout = { 2, 4 },
		bag = { stage = 7, taken = 3, slots = { 3 }, seen = 123456 },
		index = full.index, items = items, bound = { gradeCrystal = 7, [potionKey] = 2 },
		artifacts = { 1, lastArtifact, 2 }, gear = { lastArtifact, 1 },
		armor = {
			{ id = 1, slot = "helmet", quality = lastQuality, level = lastZone, stats = helmetStats },
			{ id = 2, slot = "boots", quality = 1, level = 1, stats = bootStats },
			{ id = 3, slot = "helmet", quality = 1, level = 1, stats = {} },
		},
		nextArmorId = 4, armorWorn = { helmet = 1, boots = 2 }, armorHidden = true,
		potions = full.potions, daily = full.daily, upgrades = levels,
	}
	local loaded, lf = stable(stored(full), "partida completa")
	same(loaded, expected, "partida completa: se carga todo lo guardado")
	equal(lf.player:GetAttribute("Coins"), 1e30, "monedas enormes publicadas")
	equal(lf.player:GetAttribute("Equipped"), 2, "primera equipada publicada")
	equal(lf.player:GetAttribute("Loadout"), "2,4", "equipadas publicadas")
	equal(lf.player:GetAttribute("SwordLevel"), lastSword, "tipo de la equipada publicado")
	equal(lf.player:GetAttribute("SwordMetal"), lastMetal, "metal de la equipada publicado")
	equal(lf.player:GetAttribute("Item_traitCrystal"), 1e30, "objetos enormes publicados")
	equal(lf.player:GetAttribute("Upgrade_luck"), cfg.Upgrades.luck.maxLevel, "mejora publicada")
	equal(lf.player:GetAttribute("Gear"), `{lastArtifact},1`, "accesorios equipados publicados")
	-- Lo ganado durante la partida también se guarda, y dos vueltas seguidas no cambian nada.
	local played = fixture(stored(full))
	played.data.addCoins(played.player, 1e35)
	played.data.addGems(played.player, 1e36)
	played.data.setUpgrade(played.player, "capacity", 2)
	local second = loadSaved(played.save())
	equal(second.coins, 1e30 + 1e35, "monedas ganadas guardadas")
	equal(second.totalCoins, 1e40 + 1e35, "total de monedas guardado")
	equal(second.gems, 2.5e33 + 1e36, "gemas ganadas guardadas")
	equal(second.upgrades.capacity, 2, "mejora comprada guardada")
	-- Números enormes pasados por JSON de verdad (el de Lune redondea el último decimal: de ahí el `near`).
	local json = serde.decode("json", serde.encode("json", stored(loaded)))
	json.coins, json.gems, json.totalCoins, json.items.traitCrystal = 1e300, 1e33, 1e305, 1e30
	local big = loadSaved(json)
	near(big.coins, 1e300, "1e300 monedas sobreviven")
	near(big.gems, 1e33, "1e33 gemas sobreviven")
	near(big.totalCoins, 1e305, "1e305 sobrevive")
	near(big.items.traitCrystal, 1e30, "1e30 cristales sobreviven")
	near(big.autoSell, 1e24, "autoventa de 1e24 sobrevive")
	equal(table.concat(big.loadout, ","), "2,4", "las equipadas sobreviven al JSON")
	equal(big.pity.traits[lastTrait], pity.traits[lastTrait], "el pity sobrevive al JSON")
	equal(big.armorWorn.helmet, 1, "la armadura puesta sobrevive al JSON")
	equal(big.potions.damage.seconds, 120, "las pociones sobreviven al JSON")
	sane(big, "partida pasada por JSON")

	-- Datos antiguos: lo que falta entra con su valor por defecto y lo que había se queda.
	local fresh = stored((loadSaved(nil)))
	for _, empty in { {}, "roto", 5, true } do
		same(stable(empty, "guardado vacío"), fresh, "guardado vacío o que no es una tabla: partida nueva")
	end
	local before = stable({ coins = 50, gems = 3, swordLevel = 3 }, "guardado anterior al gacha")
	equal(before.coins, 50, "anterior al gacha: monedas")
	equal(before.gems, 3, "anterior al gacha: gemas")
	equal(#before.swords, 3, "anterior al gacha: una espada por nivel comprado")
	equal(before.swords[before.loadout[1]].sword, 3, "anterior al gacha: equipada la última")
	equal(before.index, nil, "sin índice guardado: sin estrenar")
	equal(next(before.potions), nil, "sin pociones guardadas")
	equal(#before.armor, 0, "sin armadura guardada")
	equal(next(before.armorWorn), nil, "sin armadura puesta")
	equal(before.autoSell, 0, "sin autoventa guardada")
	equal(before.traitPriority, fresh.traitPriority, "sin prioridad de rasgos guardada")
	equal(before.upgrades.luck, 0, "sin mejoras guardadas")
	equal(before.items.traitCrystal, 0, "sin objetos guardados")
	local firstGacha = stable({ swords = { 1, 4, 5, 999 }, traits = { ["4"] = 2, ["5"] = 999 }, swordLevel = 4 }, "primer gacha")
	same(firstGacha.swords, { { id = 1, sword = 1 }, { id = 2, sword = 4, trait = 2 }, { id = 3, sword = 5 } }, "primer gacha: tipos y rasgos aparte")
	equal(table.concat(firstGacha.loadout, ","), "2", "primer gacha: equipada por tipo")
	local older = stable({
		coins = 9, swords = { { id = 1, sword = 1 }, { id = 2, sword = 4, trait = 1 } }, equipped = 2,
		items = { traitCrystal = 5 }, upgrades = { luck = 2 }, artifacts = { 2 }, gear = { 2 },
	}, "guardado sin lo añadido después")
	same(older.swords, { { id = 1, sword = 1 }, { id = 2, sword = 4, trait = 1 } }, "copias sin grado, metal ni tamaño")
	equal(table.concat(older.loadout, ","), "2", "antiguo: la única equipada pasa a la lista")
	equal(older.items.traitCrystal, 5, "antiguo: objetos que había")
	equal(older.items.gradeCrystal, 0, "antiguo: objeto añadido después")
	equal(older.items[potionKey], 0, "antiguo: pociones añadidas después")
	equal(older.upgrades.luck, 2, "antiguo: mejora que había")
	equal(older.upgrades.capacity, 0, "antiguo: mejora sin guardar")
	equal(older.gear[1], 2, "antiguo: accesorio equipado")
	equal(older.pity.grades[1], 0, "antiguo: sin pity")
	equal(older.rebirths, 0, "antiguo: sin renacimientos")

	-- Datos rotos, campo a campo.
	for _, bad in { nan, -5, -huge, "abc", true, {} } do
		local d, g = stable({
			coins = bad, gems = bad, rebirths = bad, playTime = bad, totalCoins = bad, robuxSpent = bad, autoSell = bad,
			swords = { { id = 1, sword = 4 } }, equipped = bad, swordLevel = bad, traitPriority = bad, missions = bad,
		}, "números rotos")
		equal(d.coins, 0, "monedas rotas")
		equal(d.gems, 0, "gemas rotas")
		equal(d.rebirths, 0, "renacimientos rotos")
		equal(d.playTime + d.totalCoins + d.robuxSpent + d.autoSell, 0, "contadores rotos")
		equal(d.swords[d.loadout[1]].sword, 4, "equipada rota: la primera")
		equal(table.concat(modifiers.priority(d.traitPriority), ","), table.concat(modifiers.PRIORITY, ","), "prioridad de rasgos rota")
		equal(next(d.missions), nil, "misiones rotas")
		local g2 = fixture({ coins = bad, gems = bad })
		equal(g2.data.trySpend(g2.player, 1), false, "con monedas rotas no se compra gratis")
		equal(g2.data.trySpendGems(g2.player, 1), false, "con gemas rotas no se compra gratis")
		equal(g.player:GetAttribute("Coins"), 0, "monedas rotas publicadas a cero")
	end
	local numeric = stable({ coins = "1e30", gems = "12", rebirths = huge, upgrades = { luck = huge } }, "números como texto e infinitos")
	equal(numeric.coins, 1e30, "monedas guardadas como texto")
	equal(numeric.gems, 12, "gemas guardadas como texto")
	equal(numeric.rebirths, cfg.Rebirth.max, "renacimientos infinitos: el máximo")
	equal(numeric.upgrades.luck, cfg.Upgrades.luck.maxLevel, "mejora infinita: su máximo")
	for bad, level in { [1] = 1, [2.7] = 2, [-3] = 0, [1e9] = cfg.Upgrades.luck.maxLevel } do
		equal(stable({ upgrades = { luck = bad, inventada = 5 } }, "mejoras rotas").upgrades.luck, level, "nivel de mejora " .. bad)
	end
	for _, bad in { nan, "x", true, {} } do
		local d = stable({ upgrades = { luck = bad }, coins = 7 }, "mejoras rotas")
		equal(d.upgrades.luck, 0, "nivel de mejora roto")
		equal(d.upgrades.inventada, nil, "mejora que no existe")
		equal(d.coins, 7, "mejoras rotas: lo demás se queda")
	end
	equal(stable({ upgrades = { luck = "3" } }, "mejora como texto").upgrades.luck, 3, "nivel de mejora como texto")
	equal(stable({ upgrades = "x" }, "mejoras que no son tabla").upgrades.luck, 0, "mejoras que no son una tabla")

	-- Espadas rotas: se queda lo válido (también con una entrada rota la primera), sin rasgos ni metales inventados.
	local swords = stable({
		gems = 4, equipped = 99,
		swords = {
			"rota", { id = 1, sword = 999 }, { id = 7, sword = 4, trait = 999, grade = -1, metal = nan, size = "x" },
			{ id = 7, sword = 5, trait = 1.5, grade = 1, metal = 0, size = 0 }, 5, { sword = "4" }, { id = 9, sword = nan },
			{ id = 8, sword = 1.5 }, { id = 10, sword = 0 }, false, { id = 11, sword = -1 }, {},
		},
	}, "espadas rotas")
	same(swords.swords, { { id = 1, sword = 4 }, { id = 2, sword = 5, grade = 1 } }, "espadas rotas: solo las válidas")
	equal(table.concat(swords.loadout, ","), "1", "equipada que no existe: la primera")
	equal(swords.gems, 4, "espadas rotas: lo demás se queda")
	local twins = stable({ swords = { { id = 7, sword = 4 }, { id = 7, sword = 5 }, { id = 7, sword = 6 } }, equipped = 7 }, "ids repetidos")
	equal(#twins.swords, 3, "ids repetidos: no se pierde ninguna copia")
	for _, bad in { { { sword = 999 }, "x" }, {}, "x", { "x", "y" } } do
		local d = stable({ swords = bad, coins = 3 }, "sin espadas válidas")
		same(d.swords, { { id = 1, sword = 1 } }, "sin espadas válidas: la inicial")
		equal(table.concat(d.loadout, ","), "1", "sin espadas válidas: equipada la inicial")
	end
	local many = {}
	for id = 1, 5000 do many[id] = { id = id, sword = 4 + id % 3, trait = 1 } end
	local crowded = stable({ swords = many, equipped = 150 }, "mochila enorme")
	equal(#crowded.swords, cfg.MaxSwords, "mochila enorme recortada al tope")
	equal(table.concat(crowded.loadout, ","), "150", "mochila enorme: la equipada sigue")
	equal(crowded.swords[150].sword, 4 + 150 % 3, "mochila enorme: mismas copias")
	stable({ swords = many, equipped = 4000 }, "equipada fuera del tope")

	-- Objetos, accesorios, índice, pity y pociones rotos.
	local bits = stable({
		items = { traitCrystal = nan, gradeCrystal = -4, missionToken = "7", inventado = 5, [potionKey] = {} },
		artifacts = { 999, "1", 1.5, nan, 2, 2, 0, -1, 1 },
		gear = { 2, 2, 3, "1", 999, nan, 1 },
		index = { code(4, 1, 1), code(4, 1, 1), code(999, 0, 0), nan, huge, -1, "x", {} },
		pity = { traits = "x", grades = { -1, nan, 1e9, 0, 0, 0, 0, 0, 1e9 } },
		potions = {
			nada = { tier = 1, seconds = 10 }, damage = { tier = 99, seconds = 10 }, health = { tier = 1, seconds = nan },
			boxLuck = { tier = 1, seconds = -5 }, weaponLuck = { tier = 1, seconds = huge }, rankLuck = "x",
			traitLuck = { tier = 1.5, seconds = 10 }, attackSpeed = { tier = 2, seconds = 30 }, coins = { tier = 2, seconds = 30 },
		},
		missions = {
			daily = "x", otra = { id = 1, progress = {}, claimed = {} },
			weekly = { id = 2800, progress = { a = nan, b = "x", c = 3, d = -1, [1] = 5 }, claimed = { a = "sí", c = true } },
		},
		traitPriority = "luck,luck,luck",
		stopAt = { traits = "x", grades = { "a", {}, 1 } },
		passes = { vip = "sí", coins2 = true, inventado = true },
		receipts = { "a", 5, {}, "b" },
		codes = { HOLA = true, OTRO = "sí", [3] = true },
		tutorial = 999,
	}, "objetos y listas rotos")
	same(bits.passes, { coins2 = true }, "pases de tickets: solo los que existen y están a true")
	same(bits.receipts, { "a", "b" }, "compras entregadas: solo textos")
	same(bits.codes, { HOLA = true }, "códigos canjeados: solo los marcados")
	equal(bits.tutorial, 0, "paso de tutorial que no existe: terminado")
	equal(bits.items.traitCrystal, 0, "objeto NaN")
	equal(bits.items.gradeCrystal, 0, "objeto negativo")
	equal(bits.items.missionToken, 7, "objeto guardado como texto")
	equal(bits.items.inventado, nil, "objeto que no existe")
	equal(bits.items[potionKey], 0, "objeto que no es un número")
	same(bits.artifacts, { 2, 1 }, "accesorios: solo los que existen, uno de cada")
	same(bits.gear, { 2, 1 }, "equipados: solo los que se tienen, sin repetir")
	same(bits.index, { code(4, 1, 1) }, "índice roto limpio")
	equal(bits.pity.traits[1], 0, "pity que no es una tabla")
	equal(bits.pity.grades[3], 0, "pity de un grado fácil al cargar")
	equal(bits.pity.grades[9], modifiers.pityLimit("grades", 9), "pity acotado al cargar")
	same(bits.potions, { coins = { tier = 2, seconds = 30 } }, "pociones: solo las válidas")
	same(bits.missions, { weekly = { id = 2800, progress = { c = 3 }, claimed = { c = true } } }, "misiones: solo progreso y premios válidos")
	equal(table.concat(modifiers.priority(bits.traitPriority), ","), table.concat(modifiers.PRIORITY, ","), "prioridad de rasgos sin sentido: la de siempre")
	same(bits.stopAt, { traits = {}, grades = { 1 } }, "\"Parar con\" roto: solo índices que existen")
	same(modifiers.stops("traits", "10,8,1,6,8,x,99"), { 8, 10 }, "\"Parar con\" en texto: sin Rasgos I y II, repetidos ni inventados")
	equal(modifiers.stops("traits", nil), nil, "sin \"Parar con\" guardado: nada (lo de por defecto)")
	same(modifiers.stops("grades", ""), {}, "\"Parar con\" guardado vacío: ninguno marcado")
	local owned, wearing = {}, {}
	for index = 1, 10000 do owned[index] = 1 + index % math.min(5, lastArtifact) end
	for index = 1, 100 do wearing[index] = 1 + index % math.min(5, lastArtifact) end
	local codes = table.create(10000, code(4, 1, 1))
	local lists = stable({ artifacts = owned, gear = wearing, index = codes }, "listas enormes")
	equal(#lists.artifacts, math.min(5, lastArtifact) * cfg.ArtifactCopies, "accesorios repetidos miles de veces: hasta el tope de copias")
	equal(#lists.gear, math.min(cfg.GearSlots, lastArtifact), "equipados recortados a los huecos")
	equal(#lists.index, 1, "índice repetido miles de veces")
	for _, bad in { "x", 5, true } do
		local d = stable({ items = bad, artifacts = bad, gear = bad, index = bad, pity = bad, potions = bad, armor = bad, armorWorn = bad, coins = 8 }, "tablas que no lo son")
		equal(#d.artifacts + #d.gear + #d.armor, 0, "listas que no son tablas")
		equal(d.index, nil, "índice que no es una tabla")
		equal(d.coins, 8, "listas rotas: lo demás se queda")
	end

	-- Armadura rota: hueco, calidad o mazmorra que no existen, stats inválidos, ids repetidos y equipada sin pieza.
	local healthCap = armorStats.cap("health", 1, 1)
	local armor = stable({
		armor = {
			"x",
			{ id = 1, slot = "nada", quality = 1, level = 1, stats = {} },
			{ id = 2, slot = "helmet", quality = 99, level = 1, stats = {} },
			{ id = 3, slot = "helmet", quality = 1, level = 1, stats = "x" },
			{ id = 4, slot = "helmet", quality = 1, level = 999, stats = {
				{ stat = "health", value = huge }, { stat = "nada", value = 1 }, { stat = "luck", value = nan }, { stat = "luck", value = -1 },
				{ stat = "damage", value = "9" }, "x", { stat = "health", value = healthCap / 4, bonus = "sí" },
			} },
			{ id = 4, slot = "boots", quality = 1, level = 1, stats = {} },
			{ slot = "chest", quality = 1, level = nan, stats = {} },
			{ id = 6, slot = "legs", quality = 1.5, level = 1, stats = {} },
		},
		armorWorn = { helmet = 4, boots = 99, legs = 6, nada = 1 },
	}, "armadura rota")
	same(armor.armor, {
		{ id = 1, slot = "helmet", quality = 1, level = 1, stats = { { stat = "health", value = healthCap }, { stat = "health", value = healthCap / 4 } } },
		{ id = 2, slot = "boots", quality = 1, level = 1, stats = {} },
		{ id = 3, slot = "chest", quality = 1, level = 1, stats = {} },
	}, "armadura rota: solo las piezas y los stats válidos")
	same(armor.armorWorn, { helmet = 1 }, "armadura puesta: solo la que existe")
	local pieces = {}
	for id = 1, 500 do pieces[id] = { id = id, slot = "chest", quality = 1, level = 1, stats = {} } end
	local closet = stable({ armor = pieces, armorWorn = { chest = 30 } }, "armadura enorme")
	equal(#closet.armor, cfg.Armor.MaxPieces, "armadura enorme recortada al tope")
	equal(closet.armorWorn.chest, 30, "armadura enorme: la puesta sigue")

	-- Sin DataStore: si la carga falla se reintenta y, si sigue fallando, se echa al jugador (nadie juega una partida que
	-- no se va a guardar) sin tocar lo guardado; si falla el guardado, no revienta.
	local down = dataStore({ coins = 7 })
	down.fail = "read"
	local offline = fixture(nil, down)
	equal(offline.player:GetAttribute("Kicked"), nil, "carga fallida: antes de reintentar no se echa a nadie")
	for _ = 1, 4 do offline.step(cfg.SessionLock.Retry) end
	equal(offline.data.read(offline.player), nil, "carga fallida: no hay partida")
	equal(type(offline.player:GetAttribute("Kicked")), "string", "carga fallida: se echa al jugador con un aviso")
	down.fail = nil
	offline.save()
	equal(down.writes, 0, "carga fallida: no se pisa lo guardado")
	equal(down.value.coins, 7, "carga fallida: lo guardado sigue igual")
	equal(#offline.warnings, 1, "carga fallida avisada")
	-- La lectura vuelve a la segunda: entra con lo suyo y guarda con normalidad.
	local shaky = dataStore({ coins = 7 })
	shaky.fail = "read"
	local patient = fixture(nil, shaky)
	shaky.fail = nil
	patient.step(cfg.SessionLock.Retry)
	equal(patient.data.read(patient.player).coins, 7, "carga que falla una vez: entra con lo guardado")
	equal(patient.player:GetAttribute("Kicked"), nil, "carga que falla una vez: no se echa a nadie")
	patient.data.addCoins(patient.player, 5)
	equal(patient.save().coins, 12, "carga que falla una vez: guarda con normalidad")
	-- Un infinito no se puede guardar: se guarda recortado en vez de fallar el guardado entero.
	local rich = fixture({ coins = 1 })
	rich.data.addCoins(rich.player, math.huge)
	equal(rich.save().coins, 1e300, "monedas infinitas: se guardan recortadas")
	local readOnlyStore = dataStore({ coins = 5 })
	local readOnly = fixture(nil, readOnlyStore)
	readOnlyStore.fail = "write"
	readOnly.save()
	for _ = 1, cfg.SessionLock.SaveTries do readOnly.step(cfg.SessionLock.Retry) end
	equal(readOnly.data.read(readOnly.player), nil, "guardado fallido: la sesión se cierra igual")
	equal(#readOnly.warnings, cfg.SessionLock.SaveTries, "guardado fallido: un aviso por intento")
	equal(readOnlyStore.value.coins, 5, "guardado fallido: lo guardado sigue igual")
end

-- Candado de sesión del guardado: dos servidores (dos fixtures) con el mismo DataStore y el mismo jugador.
do
	local lockCfg = f.config.SessionLock
	local tries = lockCfg.Wait / lockCfg.Retry
	local function swordIds(server, player)
		local ids = {}
		for _, copy in server.data.read(player).swords do table.insert(ids, copy.id) end
		return table.concat(ids, ",")
	end
	-- Entra un jugador nuevo en un servidor que ya está en marcha.
	local function join(server, userId: number?)
		local player = Instance.new("Player")
		player.Name, player.DisplayName, player.UserId, player.Parent = "Otro", "Otro", userId or 1, server.workspace.Parent
		table.insert(server.players, player)
		server.spawn(function() server.services.Players.PlayerAdded:fire(player) end)
		return player
	end
	local function leave(server, player)
		table.remove(server.players, table.find(server.players, player))
		server.spawn(function() server.services.Players.PlayerRemoving:fire(player) end)
		player.Parent = nil
	end
	local twoSwords = { coins = 10, swords = { { id = 1, sword = 1 }, { id = 2, sword = 3 } }, nextSwordId = 3, equipped = 1 }

	-- Una sesión sola: el candado se pone al cargar, se renueva al guardar y se quita al salir.
	local solo = dataStore({ coins = 10 })
	local one = fixture(nil, solo)
	equal(type(solo.value.lock), "table", "cargar pone el candado")
	equal(solo.value.coins, 10, "poner el candado no toca lo guardado")
	local firstLock = solo.value.lock
	one.data.addCoins(one.player, 5)
	one.advance(60)
	one.data.save(one.player)
	equal(solo.value.coins, 15, "guardado normal: escribe la partida")
	equal(solo.value.lock.id, firstLock.id, "guardado normal: el candado sigue siendo el mismo")
	equal(solo.value.lock.time, firstLock.time + 60, "guardado normal: renueva la hora del candado")
	equal(one.data.read(one.player).lock, nil, "el candado no entra en los datos de la partida")
	one.step(60) -- el guardado automático
	equal(solo.value.lock.time, firstLock.time + 120, "guardado automático: renueva el candado")
	one.save()
	equal(solo.value.lock, nil, "salir suelta el candado")
	equal(solo.value.coins, 15, "salir guarda la partida")
	equal(one.player:GetAttribute("Kicked"), nil, "una sesión normal no echa a nadie")
	equal(#one.warnings, 0, "una sesión normal no avisa de nada")

	-- El truco del trato: sale del servidor A y entra en el B antes de que A guarde. B espera y carga lo último.
	local shared = dataStore(copied(twoSwords))
	local a = fixture(nil, shared)
	equal(swordIds(a, a.player), "1,2", "servidor A: carga las dos espadas")
	a.data.edit(a.player, function(data) table.remove(data.swords, 2) end) -- la da en un trato
	local b = fixture(nil, shared) -- entra en B con la partida aún abierta en A
	equal(b.data.read(b.player), nil, "servidor B: no carga una partida abierta en otro servidor")
	b.step(lockCfg.Retry)
	equal(b.data.read(b.player), nil, "servidor B: sigue esperando mientras A no guarde")
	equal(#shared.value.swords, 2, "servidor B: esperar no toca lo guardado")
	a.save() -- A termina de guardar y suelta
	b.step(lockCfg.Retry)
	equal(swordIds(b, b.player), "1", "servidor B: carga la partida ya sin la espada del trato")
	equal(b.player:GetAttribute("Kicked"), nil, "servidor B: no echa a quien solo tuvo que esperar")
	b.data.addCoins(b.player, 1)
	b.save()
	equal(shared.value.coins, 11, "servidor B: guarda con normalidad")
	equal(shared.value.lock, nil, "servidor B: suelta al salir")

	-- La partida sigue abierta y viva en otro servidor pasado el tiempo de espera: se echa al jugador sin tocar nada.
	local held = dataStore(copied(twoSwords))
	local owner = fixture(nil, held)
	local ownerLock = held.value.lock.id
	local late = fixture(nil, held)
	for _ = 1, tries + 2 do late.step(lockCfg.Retry) end
	equal(late.data.read(late.player), nil, "candado vivo: no hay partida")
	equal(type(late.player:GetAttribute("Kicked")), "string", "candado vivo: se echa al jugador con un aviso")
	equal(held.value.lock.id, ownerLock, "candado vivo: sigue siendo del primer servidor")
	owner.data.addCoins(owner.player, 3)
	owner.save()
	equal(held.value.coins, 13, "candado vivo: el primer servidor sigue guardando")
	equal(owner.player:GetAttribute("Kicked"), nil, "candado vivo: al dueño no se le echa")

	-- Quien se va mientras espera no coge nada ni recibe aviso.
	local gone = dataStore(copied(twoSwords))
	local keeper = fixture(nil, gone)
	local keeperLock = gone.value.lock.id
	local impatient = fixture(nil, gone)
	impatient.player.Parent = nil
	impatient.step(lockCfg.Retry)
	equal(impatient.data.read(impatient.player), nil, "se va esperando: sin partida")
	equal(impatient.player:GetAttribute("Kicked"), nil, "se va esperando: sin aviso")
	equal(gone.value.lock.id, keeperLock, "se va esperando: el candado sigue siendo del primero")
	keeper.save()

	-- Servidor caído: nunca suelta. Antes de caducar no se entra; al caducar el candado, otro servidor se queda la partida.
	local crashed = dataStore(copied(twoSwords))
	local dead = fixture(nil, crashed)
	dead.data.addCoins(dead.player, 100) -- lo que no llegó a guardar se pierde
	local early = fixture(nil, crashed)
	early.advance(lockCfg.Expire - lockCfg.Wait - lockCfg.Retry * 3)
	for _ = 1, tries + 2 do early.step(lockCfg.Retry) end
	equal(type(early.player:GetAttribute("Kicked")), "string", "servidor caído: antes de caducar no se entra")
	local heir = fixture(nil, crashed)
	equal(heir.data.read(heir.player), nil, "servidor caído: el candado sigue puesto")
	heir.advance(lockCfg.Expire)
	heir.step(lockCfg.Retry)
	equal(heir.data.read(heir.player).coins, 10, "servidor caído: al caducar se carga lo último guardado")
	equal(heir.player:GetAttribute("Kicked"), nil, "servidor caído: quien hereda la partida no es echado")
	heir.data.addCoins(heir.player, 1)
	heir.data.save(heir.player)
	equal(crashed.value.coins, 11, "servidor caído: el nuevo servidor guarda")
	-- El servidor "caído" vuelve a dar señales: su partida está vieja y no puede pisar la nueva.
	local writes = crashed.writes
	dead.step(60) -- su guardado automático
	equal(crashed.writes, writes, "candado robado: el servidor viejo no escribe")
	equal(crashed.value.coins, 11, "candado robado: lo guardado es lo del servidor nuevo")
	equal(type(dead.player:GetAttribute("Kicked")), "string", "candado robado: el servidor viejo echa al jugador")
	dead.data.addCoins(dead.player, 1)
	dead.data.save(dead.player)
	dead.save()
	equal(crashed.writes, writes, "candado robado: tampoco escribe al salir")
	heir.save()
	equal(crashed.value.coins, 11, "candado robado: el servidor nuevo cierra bien")
	equal(crashed.value.lock, nil, "candado robado: y suelta")
	-- También si el servidor nuevo ya soltó: el viejo sigue sin poder escribir.
	local staleStore = dataStore({ coins = 1 })
	local stale = fixture(nil, staleStore)
	staleStore.value = { coins = 50 } -- otro servidor se la quedó, jugó y salió
	stale.data.addCoins(stale.player, 5)
	stale.save()
	equal(staleStore.value.coins, 50, "partida ya cerrada en otro servidor: no se pisa")

	-- Mismo servidor: sale, el guardado tarda (falla el primer intento) y vuelve a entrar antes de que acabe.
	local slow = dataStore(copied(twoSwords))
	local same1 = fixture(nil, slow)
	same1.data.addCoins(same1.player, 7)
	slow.fail = "write"
	leave(same1, same1.player) -- el primer intento falla y queda esperando para reintentar
	slow.fail = nil
	local back = join(same1)
	equal(same1.data.read(back), nil, "mismo servidor: la vuelta espera al guardado de la salida")
	same1.step(lockCfg.Retry) -- reintenta el guardado; la carga, que va detrás, puede necesitar otro intento
	same1.step(lockCfg.Retry)
	equal(same1.data.read(back).coins, 17, "mismo servidor: la vuelta carga lo que guardó la salida")
	equal(back:GetAttribute("Kicked"), nil, "mismo servidor: sin aviso")

	-- Se va justo mientras se carga: se suelta el candado recién cogido y no queda sesión.
	local quick = dataStore({ coins = 4 })
	local quickServer = fixture(nil, quick)
	quickServer.save()
	local inner, leaver = quick.UpdateAsync, nil
	local first = true
	quick.UpdateAsync = function(...)
		local result = inner(...)
		if first then
			first = false
			leaver.Parent = nil
		end
		return result
	end
	leaver = Instance.new("Player")
	leaver.Name, leaver.DisplayName, leaver.UserId, leaver.Parent = "Fugaz", "Fugaz", 1, quickServer.workspace.Parent
	quickServer.spawn(function() quickServer.services.Players.PlayerAdded:fire(leaver) end)
	equal(quickServer.data.read(leaver), nil, "se va cargando: sin sesión")
	equal(quick.value.lock, nil, "se va cargando: el candado se suelta")
	equal(quick.value.coins, 4, "se va cargando: lo guardado sigue igual")

	-- Guardados raros: solo el candado (servidor caído antes del primer guardado) y candados mal formados.
	local onlyLock = fixture(nil, dataStore({ lock = { id = "viejo", time = 5 } }))
	equal(onlyLock.data.read(onlyLock.player).coins, f.config.StartCoins, "solo el candado: partida nueva")
	equal(swordIds(onlyLock, onlyLock.player), "1", "solo el candado: con la espada inicial")
	for label, bad in { texto = "x", numero = 5, sinHora = { id = "x" }, sinId = { time = 1e12 }, idNumero = { id = 7, time = 1e12 } } do
		local odd = fixture(nil, dataStore({ coins = 9, lock = bad }))
		equal(odd.data.read(odd.player).coins, 9, "candado mal formado (" .. label .. "): se carga igual")
		odd.save()
		equal(odd.store.value.lock, nil, "candado mal formado (" .. label .. "): se limpia al salir")
	end

	-- Fallo de red al cargar: no se guarda después y no queda ningún candado puesto.
	local flaky = dataStore({ coins = 3 })
	flaky.fail = "read"
	local blind = fixture(nil, flaky)
	flaky.fail = nil
	blind.save()
	equal(flaky.value.lock, nil, "carga fallida: no deja candado")
	equal(flaky.writes, 0, "carga fallida: no escribe")

	-- Modos de prueba de Studio que no guardan: ni cogen el candado ni esperan al de otro.
	local studio = dataStore(copied(twoSwords))
	local live = fixture(nil, studio)
	local liveLock = studio.value.lock.id
	local tester = fixture(nil, dataStore(nil))
	tester.services.RunService.IsStudio = function() return true end
	tester.services.DataStoreService.GetDataStore = function() return studio end
	tester.config.Test.InfiniteMoney = true
	local testWrites = studio.writes
	local testPlayer = join(tester, 1)
	equal(tester.data.read(testPlayer) ~= nil, true, "modo de pruebas: carga sin esperar al candado")
	leave(tester, testPlayer)
	equal(studio.writes, testWrites, "modo de pruebas: no escribe")
	equal(studio.value.lock.id, liveLock, "modo de pruebas: no toca el candado de la partida de verdad")
	live.save()

	-- Config.Test.Progress: el jugador tipo de shared/BalanceSnapshots entra con todas sus armas equipadas (hasta el tope
	-- de huecos), cada una con su metal, su rasgo y su grado.
	local staged = fixture(nil, dataStore({ coins = 777, gems = 9, swords = { { id = 1, sword = 1 }, { id = 2, sword = 9 } }, nextSwordId = 3, loadout = { 2 }, artifacts = { 2 } }))
	staged.services.RunService.IsStudio = function() return true end
	staged.config.Test.Progress = 1
	local slots = staged.config.Loadout.Slots
	local stagedSwords = {}
	for index = 1, slots + 1 do
		stagedSwords[index] = { sword = index + 1, metal = if index == 1 then 2 else 0, size = 0, trait = index, grade = if index == 2 then 3 else 0 }
	end
	local snapshots = staged.load("src/shared/BalanceSnapshots")
	table.clear(snapshots)
	table.insert(snapshots, { hours = 1, upgrades = { luck = 3 }, rebirths = 1, swords = stagedSwords, artifacts = { 1 }, gear = { 1 }, dungeon = 1, armor = { 0.1, 0, 0 } })
	local stagedPlayer = join(staged, 1)
	local stagedData = staged.data.read(stagedPlayer)
	equal(#stagedData.loadout, slots, "Progress: equipa las armas de la foto, hasta el tope de huecos")
	local firstCopy = staged.data.findSword(stagedData, stagedData.loadout[1])
	local secondCopy = staged.data.findSword(stagedData, stagedData.loadout[2])
	equal(firstCopy.sword, 2, "Progress: la primera arma de la foto va en el primer hueco")
	equal(firstCopy.metal, 2, "Progress: con su metal")
	equal(firstCopy.trait, 1, "Progress: con su rasgo")
	equal(secondCopy.grade, 3, "Progress: cada arma con su grado")
	equal(#staged.load("src/shared/Stats").loadout(stagedPlayer), slots, "Progress: equipadas publicadas")
	equal(stagedData.rebirths, 1, "Progress: renacimientos de la foto")
	equal(stagedData.coins, staged.config.StartCoins, "Progress: no trae las monedas guardadas")
	equal(stagedData.gems, 0, "Progress: no trae las gemas guardadas")
	equal(#stagedData.swords, 1 + slots + 1, "Progress: no trae las armas guardadas")
	equal(#stagedData.bag.slots, 1, "Progress: las armas de la foto que no caben en los huecos van a la Bolsa de oro")
	equal(staged.data.isEquipped(stagedData, stagedData.bag.slots[1]), false, "Progress: y no están equipadas")
	equal(table.concat(stagedData.artifacts, ","), "1", "Progress: solo los accesorios de la foto")
	leave(staged, stagedPlayer)
end

-- Bolsa de oro (server/GoldBag, shared/BagInfo): las cuentas de las bolsas, depositar y sacar armas, que una
-- depositada no se venda ni se equipe a la vez, el cobro de cada segundo, lo ganado mientras no estaba y lo guardado.
do
	local store = dataStore(nil)
	local bf = fixture(nil, store)
	local cfg, who = bf.config, bf.player
	local function table3(c, first)
		c.GoldBag.Coins, c.GoldBag.Damage, c.GoldBag.Double = 50, 100, 1.5
		c.GoldBag.First, c.GoldBag.Growth = first or 100, 4
		c.GoldBag.HitTime, c.GoldBag.MinAway, c.GoldBag.Slots, c.GoldBag.StageBoost = 1, 60, 4, 2
	end
	local info = bf.load("src/shared/BagInfo")
	-- Con los números de Config: Coins con Damage de daño y Double veces más cada vez que el daño se dobla (equilibrados
	-- para que la bolsa vaya a la par con los destructibles), y al menos una moneda.
	local bag = cfg.GoldBag
	equal(info.coins(1), math.max(1, math.round(bag.Coins * (1 / bag.Damage) ^ (math.log(bag.Double) / math.log(2)))), "bolsa: un golpe de 1 de daño")
	near(info.coins(2e12) / info.coins(1e12), bag.Double, "bolsa: el doble de daño, Double veces más monedas")
	near(info.coins(3.2e17), bag.Coins * (3.2e17 / bag.Damage) ^ (math.log(bag.Double) / math.log(2)), "bolsa: y con números enormes, la misma regla")
	-- La cuenta, con otros números: 100 de daño = 50 monedas y cada x2 de daño, x1,5.
	table3(cfg)
	equal(info.coins(100), 50, "bolsa: 100 de daño sacan 50 monedas")
	equal(info.coins(200), 75, "bolsa: el doble de daño, x1,5")
	equal(info.coins(400), 113, "bolsa: y otra vez x1,5 (112,5, redondeado)")
	equal(info.coins(50), 33, "bolsa: la mitad de daño, entre 1,5")
	equal(info.coins(0.0001), 1, "bolsa: un golpe saca al menos una moneda")
	equal(info.coins(0), 0, "bolsa: sin daño no saca nada")
	near(info.coins(1e30) / info.coins(5e29), 1.5, "bolsa: la regla vale con números enormes")
	equal(info.size(1), 100, "bolsa: la primera lleva First")
	equal(info.size(3), 1600, "bolsa: cada una, Growth veces la anterior")
	local stage, taken, emptied = info.advance(1, 0, 40)
	equal(stage == 1 and taken == 40 and emptied == 0, true, "bolsa: sin vaciarla sigue en la misma")
	stage, taken, emptied = info.advance(1, 40, 100)
	equal(stage == 2 and taken == 40 and emptied == 1, true, "bolsa: lo que sobra sale de la siguiente")
	stage, taken, emptied = info.advance(1, 0, 100 + 400 + 1600 + 50)
	equal(stage == 4 and taken == 50 and emptied == 3, true, "bolsa: varias vaciadas de una vez")
	local got
	stage, taken, emptied, got = info.collect(1, 0, 100 + 250)
	equal(stage == 2 and taken == 250 and emptied == 1 and got == 100 + 500, true, "bolsa: su tamaño es vida, y cada vaciada dobla lo que pagan los golpes")
	stage, taken, emptied, got = info.collect(1, 0, 50, 10)
	equal(stage == 1 and taken == 50 and got == 500, true, "bolsa: los multiplicadores de monedas no le quitan más vida")
	equal(info.boost(1) == 1 and info.boost(4) == 8, true, "bolsa: x2 por bolsa vaciada")
	stage, taken, emptied = info.advance(1, 30, 0)
	equal(stage == 1 and taken == 30 and emptied == 0, true, "bolsa: sin monedas no pasa nada")
	local clean = info.sanitize({ stage = "x", taken = -5, seen = 0 / 0, slots = { 1 } })
	equal(clean.stage == 1 and clean.taken == 0 and clean.seen == nil and #clean.slots == 0, true, "bolsa guardada rota: se limpia")
	clean = info.sanitize({ stage = 2.7, taken = 1e9, seen = 50 })
	equal(clean.stage == 2 and clean.taken == 400 and clean.seen == 50, true, "bolsa guardada: bolsa entera y lo sacado dentro de lo que lleva")

	-- Depositar: copias 1..6, la k con la k-ésima arma de menos daño.
	bf.overrides["src/server/Plots"] = { all = function() return {} end, onResize = function() end }
	bf.load("src/server/Gacha").start()
	bf.load("src/server/GoldBag").start()
	local stats = bf.load("src/shared/Stats")
	local byDamage = {}
	for index in cfg.Swords do table.insert(byDamage, index) end
	table.sort(byDamage, function(a, b) return cfg.Swords[a].damage < cfg.Swords[b].damage end)
	bf.data.edit(who, function(d)
		d.swords = {}
		for id = 1, 8 do d.swords[id] = { id = id, sword = byDamage[id] } end
		d.nextSwordId = 9
		d.loadout = { 8 }
		d.coins = 0
	end)
	local function deposit(id) bf.remotes.SetBag.OnServerEvent:fire(who, id) end
	local function inBag() return table.concat(bf.data.read(who).bag.slots, ",") end
	local function worn() return table.concat(bf.data.read(who).loadout, ",") end
	deposit(8)
	equal(inBag() == "8" and worn() == "", true, "la única equipada también se deposita (se puede ir sin armas)")
	deposit(8)
	bf.remotes.EquipSword.OnServerEvent:fire(who, 8)
	equal(inBag() == "" and worn() == "8", true, "y se saca y se vuelve a equipar")
	for _, bad in { 999, "x", 0 / 0, {}, true, -1, 1.5 } do deposit(bad) end
	equal(inBag(), "", "depositar algo que no existe no cambia nada")
	deposit(2)
	equal(inBag(), "2", "una copia sin equipar se deposita")
	equal(who:GetAttribute("Bag"), "2", "depositadas publicadas")
	equal(stats.isDeposited(who, 2), true, "Stats lee las depositadas")
	local secondHit = stats.swordDamage({ sword = byDamage[2], trait = 0, grade = 0, metal = 0, size = 0 })
	near(stats.bagHit(who, stats.deposited(who)[1]), secondHit, "golpe a la bolsa: el daño de la depositada")
	equal(stats.bagRate(who), info.coins(secondHit), "monedas por segundo: un golpe por segundo de cada depositada")
	deposit(2)
	equal(inBag(), "", "pulsar una depositada la saca")
	bf.remotes.EquipSword.OnServerEvent:fire(who, 7)
	deposit(7)
	equal(inBag() == "7" and worn() == "8", true, "depositar una equipada la quita del equipo")
	bf.remotes.EquipSword.OnServerEvent:fire(who, 7)
	equal(inBag() == "" and worn() == "8,7", true, "equipar una depositada la saca de la bolsa")
	for id = 2, 5 do deposit(id) end
	equal(inBag(), "2,3,4,5", "caben Config.GoldBag.Slots")
	deposit(6)
	equal(inBag(), "6,3,4,5", "llena, sustituye a la de menos daño")
	bf.remotes.EquipSword.OnServerEvent:fire(who, "best")
	equal(worn(), "8,7,2,1", "las mejores: no cuenta con las depositadas")
	-- El menú del saco: vaciarla y llenarla con las de más daño de las que no están equipadas.
	deposit("clear")
	equal(inBag(), "", "\"clear\" vacía la bolsa")
	deposit("best")
	equal(inBag() == "6,5,4,3" and worn() == "8,7,2,1", true, "\"best\": las mejores sin equipar, sin tocar el equipo")
	bf.remotes.SellSwords.OnServerEvent:fire(who, { 1, 2, 3, 4, 5, 6, 7, 8 })
	equal(#bf.data.read(who).swords, 8, "ni las equipadas ni las depositadas se venden")
	bf.remotes.EquipSword.OnServerEvent:fire(who, 1)
	bf.remotes.EquipSword.OnServerEvent:fire(who, 2)
	bf.remotes.SellSwords.OnServerEvent:fire(who, { 1, 2 })
	equal(#bf.data.read(who).swords, 6, "las que no están en uso sí se venden")

	-- Cobro: cada segundo salen las monedas de un golpe de cada depositada, y se avisa al vaciar una bolsa.
	local rate = stats.bagRate(who)
	local perHit = 0
	for _, copy in stats.deposited(who) do perHit += info.coins(stats.bagHit(who, copy)) end
	equal(rate == perHit and rate >= 4, true, "las cuatro depositadas sacan al menos una moneda por golpe")
	bf.data.edit(who, function(d) d.coins = 0 end)
	bf.step(1)
	equal(bf.data.read(who).coins, rate, "un segundo: un golpe de cada una")
	equal(who:GetAttribute("BagStage"), 1, "bolsa publicada")
	equal(who:GetAttribute("BagRate"), rate, "monedas por segundo publicadas")
	equal(bf.data.read(who).bag.taken, rate, "lo sacado sale de la bolsa")
	-- Con bolsas pequeñas (la primera de 2 monedas) el siguiente segundo vacía alguna.
	table3(cfg, 2)
	bf.data.edit(who, function(d) d.bag.taken = 0 end)
	bf.step(1)
	local wantStage, wantTaken, wantEmptied, wantCoins = info.collect(1, 0, rate)
	equal(wantEmptied >= 1, true, "con bolsas pequeñas cae alguna")
	equal(bf.data.read(who).bag.stage, wantStage, "pasa a la bolsa que toca")
	equal(bf.data.read(who).bag.taken, wantTaken, "con lo que sobra sacado de ella")
	local events = bf.remotes.BagEvent.sent
	equal(events[#events][2] == "emptied" and events[#events][3].stage == wantStage and events[#events][3].bags == wantEmptied, true, "aviso de bolsa vaciada")
	equal(wantCoins > rate, true, "cada bolsa vaciada sube lo que saca cada golpe")
	equal(bf.data.read(who).coins, rate + math.floor(wantCoins), "se cobra lo que sale, con la subida de cada bolsa")
	equal(who:GetAttribute("BagRate"), rate * info.boost(wantStage), "y el ritmo publicado es el de la bolsa nueva")
	equal(bf.data.read(who).coins % 1, 0, "se pagan monedas enteras")

	-- Lo ganado fuera: sale, vuelve una hora después y se cobra de golpe (sin tope de tiempo).
	local leftStage = bf.data.read(who).bag.stage
	local leftCoins = bf.data.read(who).coins
	bf.data.edit(who, function(d) d.bag.seen -= 3600 end)
	local saved = bf.save()
	equal(#saved.bag.slots, 4, "se guardan las depositadas")
	equal(saved.bag.stage, leftStage, "y la bolsa por la que va")
	local back = fixture(nil, store)
	table3(back.config, 2)
	back.overrides["src/server/Plots"] = { all = function() return {} end, onResize = function() end }
	back.load("src/server/GoldBag").start()
	local returned = back.data.read(back.player)
	equal(#returned.bag.slots, 4, "al volver siguen depositadas")
	equal(returned.bag.stage > leftStage, true, "fuera: han seguido vaciando bolsas")
	equal(returned.coins > leftCoins, true, "fuera: se cobra al volver")
	local awayEvent = back.remotes.BagEvent.sent[1]
	equal(awayEvent[2] == "away" and awayEvent[3].coins > 0 and awayEvent[3].seconds >= 3500, true, "fuera: se le avisa con lo ganado")
	local awayBase = back.load("src/shared/Stats").bagPower(back.player, true) * awayEvent[3].seconds
	local expectedStage, _, _, expectedCoins = back.load("src/shared/BagInfo").collect(leftStage, saved.bag.taken, awayBase)
	expectedCoins = math.floor(expectedCoins)
	equal(awayEvent[3].coins, expectedCoins, "fuera: lo de un golpe por segundo de cada arma")
	equal(returned.coins, leftCoins + expectedCoins, "fuera: eso es lo que se cobra")
	equal(returned.bag.stage, expectedStage, "fuera: la misma cuenta de bolsas que conectado")
	back.save()

	-- Lo guardado roto: ids repetidos, que no existen o de un arma equipada, y números imposibles.
	local broken = fixture({ coins = 1, swords = { { id = 5, sword = 1 }, { id = 9, sword = 3 }, { id = 4, sword = 4 } }, loadout = { 5 }, bag = { stage = -3, taken = "mucho", seen = "ayer", slots = { 9, 9, 5, 77, "a", 4, {} } } })
	local brokenBag = broken.data.read(broken.player).bag
	equal(table.concat(brokenBag.slots, ","), "2,3", "bolsa guardada: ids renumerados, sin repetir, sin la equipada ni las que no existen")
	equal(brokenBag.stage == 1 and brokenBag.taken == 0 and brokenBag.seen == nil, true, "bolsa guardada: números imposibles fuera")
	equal(broken.data.isLocked(broken.data.read(broken.player), 2), true, "una depositada está en uso")
	equal(broken.data.isLocked(broken.data.read(broken.player), 99), false, "una que no existe, no")
end

-- Jefe del mundo (shared/WorldBossInfo): el premio va por tramos de cantidad de daño, con su tope.
do
	local info = f.load("src/shared/WorldBossInfo")
	local boss = config.WorldBoss
	near(info.minorHp(1e6, 3), 3e6, "jefe: un esbirro aguanta unos segundos de un jugador medio")
	local tiers = boss.Rewards.Tiers
	equal(info.rewards(tiers[1].damage / 2, 8), nil, "jefe: sin llegar al primer tramo no hay premio")
	local low, high = info.rewards(tiers[2].damage * 5, 6), info.rewards(tiers[#tiers].damage * 10, 1)
	equal(low.tier, 2, "jefe: el tramo más alto al que llega")
	equal(low.traitCrystal, tiers[2].crystals, "jefe: los cristales de su tramo")
	equal(low.potions, tiers[2].potions or 0, "jefe: las pociones de su tramo")
	assert(high.rolls > low.rolls and high.potionTier >= low.potionTier, "jefe: más daño, más premio")
	checks += 1
	equal(high.rolls <= boss.Rewards.MaxRolls, true, "jefe: tiradas con su tope")
	equal(high.tickets, boss.Rewards.Tickets[1], "jefe: tickets para el primero")
	equal(low.tickets, 0, "jefe: sin tickets fuera del podio")
	for index = 2, #tiers do
		assert(tiers[index].damage > tiers[index - 1].damage, "jefe: los tramos, de menos a más daño")
		checks += 1
	end
	equal(info.nextFall(1000, 1000), 1000 + boss.First, "jefe: el primero, a los First segundos de abrir")
	equal(info.nextFall(1000 + boss.First, 1000), 1000 + boss.First + boss.Interval, "jefe: luego cada Interval")
	equal(info.nextFall(1000 + boss.First + boss.Interval * 2.5, 1000), 1000 + boss.First + boss.Interval * 3, "jefe: el siguiente que toque")
	equal(info.count(boss.Summon, 100), boss.Summon.Max, "jefe: esbirros con tope")
	equal(info.clock(65), "1:05", "jefe: reloj")
end

-- Idioma (shared/Lang): el código lleva los textos en inglés y LangEs los pasa a español para quien tiene Roblox en
-- español. En el servidor el idioma es el de la cuenta del jugador; sin jugador, inglés.
do
	local lang = f.load("src/shared/Lang")
	local format = f.load("src/shared/Format")
	local spanish, english = { LocaleId = "es-mx" }, { LocaleId = "en-us" }
	equal(lang.code(spanish), "es", "idioma: cualquier español")
	equal(lang.code(english), "en", "idioma: inglés")
	equal(lang.code({ LocaleId = "fr-fr" }), "en", "idioma: los demás, inglés")
	equal(lang.code(nil), "en", "idioma: sin jugador, inglés")
	equal(lang.t(spanish, "Minimum damage {n}", { n = 5 }), "Daño mínimo 5", "texto en español con huecos")
	equal(lang.t(english, "Minimum damage {n}", { n = 5 }), "Minimum damage 5", "texto en inglés con huecos")
	equal(lang.t(spanish, "Texto sin traducir {n}", { n = 1 }), "Texto sin traducir 1", "sin entrada sale el inglés")
	equal(format.short(1500, spanish), "1,5K", "números con coma en español")
	equal(format.short(1500, english), "1.5K", "números con punto en inglés")
	equal(format.multiplier(2.25, spanish), "2,25", "multiplicador con coma en español")
	equal(format.parse("1,5k"), 1500, "leer un número con coma")
	equal(format.parse("1.5K"), 1500, "leer un número con punto")
	equal(permanent.describeOdds(4, 1, 1, spanish):find("^1 entre ") ~= nil, true, "probabilidad en español")
	equal(permanent.name(4, 2, 2, spanish), "Espada de acero (Hierro, Gigante)", "nombre de arma en español")
	equal(permanent.name(4, 2, 2, english), "Steel Sword (Iron, Giant)", "nombre de arma en inglés")
	local armorStats = f.load("src/shared/ArmorStats")
	equal(armorStats.name({ slot = "helmet", level = 1 }, spanish), "Casco de cuero", "armadura en español")
	equal(armorStats.name({ slot = "helmet", level = 1 }, english), "Leather Helmet", "armadura en inglés")
	equal(modifiers.effect(config.Traits[#config.Traits], spanish), "x2 Monedas · x57,5 Daño · x2 Suerte", "efecto de rasgo en español")
	equal(modifiers.effect(config.Traits[#config.Traits], english), "x2 Coins · x57.5 Damage · x2 Luck", "efecto de rasgo en inglés")
	local potionInfo = f.load("src/shared/PotionInfo")
	equal(potionInfo.name("damage", 3, spanish), "Poción de daño III", "poción en español")
	equal(potionInfo.effect("health", 3, spanish), "Vida máxima +50 %", "efecto de poción en español")
	equal(potionInfo.effect("health", 3, english), "Max Health +50%", "efecto de poción en inglés")

	-- Cada frase de LangEs lleva los mismos huecos que su clave.
	local function holes(text: string): string
		local list = {}
		for hole in text:gmatch("{%w+}") do table.insert(list, hole) end
		table.sort(list)
		return table.concat(list)
	end
	for key, value in lang.es do
		equal(holes(value), holes(key), "huecos de LangEs: " .. key)
	end

	-- Todo texto de Config que se enseña tiene su español.
	local function known(text: unknown, label: string)
		if type(text) == "string" then equal(lang.es[text] ~= nil, true, "falta en LangEs: " .. label .. " = " .. text) end
	end
	local function each(list, label: string, fields: { string })
		for key, entry in list do
			for _, field in fields do known(entry[field], `{label}.{key}.{field}`) end
			for _, perk in entry.perksText or {} do known(perk, `{label}.{key}.perksText`) end
		end
	end
	each(config.Swords, "Swords", { "name" })
	each(config.WeaponKinds, "WeaponKinds", { "name" })
	each(config.RarityTiers, "RarityTiers", { "name" })
	each(config.Metals, "Metals", { "name" })
	each(config.Sizes, "Sizes", { "name" })
	each(config.Items, "Items", { "name", "description" })
	each(config.Traits, "Traits", { "name" })
	each(config.Grades, "Grades", { "name" })
	each(config.Artifacts, "Artifacts", { "name" })
	each(config.StatNames, "StatNames", {})
	for stat, name in config.StatNames do known(name, "StatNames." .. stat) end
	each(config.Weather.Events, "Weather", { "name", "desc" })
	each(config.Destructibles, "Destructibles", { "name" })
	each(config.ObjectRarities, "ObjectRarities", { "name" })
	each(config.ObjectSizes, "ObjectSizes", { "name" })
	each(config.Upgrades, "Upgrades", { "name", "short", "desc" })
	each(config.Armor.Slots, "Armor.Slots", { "name" })
	each(config.Armor.Stats, "Armor.Stats", { "name" })
	each(config.Armor.Qualities, "Armor.Qualities", { "name" })
	each(config.Dungeons, "Dungeons", { "name", "tagline", "set" })
	each(config.Enemies, "Enemies", { "name" })
	known(config.WorldBoss.Name, "WorldBoss.Name")
	for id, theme in config.DungeonThemes do each(theme.enemies, "DungeonThemes." .. id, { "name" }) end
	each(config.Tutorial.Steps, "Tutorial", { "text" })
	each(config.Products, "Products", { "name", "tag", "ribbon" })
	each(config.Gamepasses, "Gamepasses", { "name", "tag", "ribbon" })
	each(config.Potions.Families, "Potions", { "name", "effect", "desc" })
	for _, tier in config.Potions.Tiers do known(tier, "Potions.Tiers") end
	local missions = f.load("src/shared/MissionList")
	each(missions.pool.daily, "Misiones", { "text" })
	each(missions.pool.weekly, "Misiones", { "text" })

	-- Ningún texto entre comillas del código lleva letras del español (fuera de LangEs y de los comentarios): todo
	-- texto va en inglés y su español en LangEs (docs/plan-ingles.md). Una letra suelta sí vale: son las tablas que
	-- pasan las tildes a mayúsculas.
	local DONE = { "src" }
	local SKIP = { ["src/shared/LangEs.luau"] = true }
	local SPANISH = { "á", "é", "í", "ó", "ú", "ñ", "Á", "É", "Í", "Ó", "Ú", "Ñ", "¿", "¡" }
	local function strings(source: string): { string }
		local found, position, length = {}, 1, #source
		while position <= length do
			local char = source:sub(position, position)
			if char == "-" and source:sub(position, position + 1) == "--" then
				local long = source:match("^%-%-%[(=*)%[", position)
				local stop = if long then source:find("]" .. long .. "]", position, true) else source:find("\n", position, true)
				position = (stop or length) + 1
			elseif char == '"' or char == "'" or char == "`" then
				local start = position
				position += 1
				while position <= length and source:sub(position, position) ~= char do
					position += if source:sub(position, position) == "\\" then 2 else 1
				end
				table.insert(found, source:sub(start + 1, position - 1))
				position += 1
			else
				position += 1
			end
		end
		return found
	end
	local function scan(path: string)
		for _, name in fs.readDir(path) do
			local file = path .. "/" .. name
			if fs.isDir(file) then
				scan(file)
			elseif name:match("%.luau$") and not SKIP[file] then
				for _, text in strings(fs.readFile(file)) do
					for _, letter in SPANISH do
						assert(utf8.len(text) == 1 or not text:find(letter, 1, true), `texto en español en {file}: {text}`)
					end
				end
				checks += 1
			end
		end
	end
	for _, path in DONE do scan(path) end
end

-- Recompensas diarias (server/DailyRewards, shared/DailyInfo): racha de un premio por día que no se pierde al faltar,
-- premios por tiempo jugado solo al llegar al tiempo y una vez, el día nuevo lo reinicia y lo guardado roto se limpia.
do
	local df = fixture(nil)
	local cfg = df.config
	local dailyInfo = df.load("src/shared/DailyInfo")
	df.load("src/server/DailyRewards").start()
	local function state() return df.data.read(df.player).daily end
	local function owned(name) return df.data.read(df.player).items[name] end
	local function claim(...)
		df.advance(1)
		df.remotes.ClaimDaily.OnServerEvent:fire(df.player, ...)
	end
	local first = cfg.DailyRewards.Streak[1][1]
	local before = owned(first.item)
	claim("streak")
	equal(owned(first.item) - before, first.amount, "racha: el día 1 da su premio")
	equal(df.data.read(df.player).bound[first.item], first.amount, "racha: lo que da va atado a la cuenta")
	equal(state().streak, 2, "racha: pasa a la casilla 2")
	claim("streak")
	equal(state().streak, 2, "racha: una sola casilla por día")
	df.advance(86400 * 3)
	claim("streak")
	equal(state().streak, 3, "racha: faltar días no la reinicia")

	local goal = cfg.DailyRewards.Playtime[1].minutes * 60
	claim("playtime", 1)
	equal(#state().claimed, 0, "tiempo: sin jugar no se recoge")
	for _ = 1, goal do df.step(1) end
	equal(state().seconds >= goal, true, "tiempo: se cuenta cada segundo")
	local reward = cfg.DailyRewards.Playtime[1].rewards[1]
	before = owned(reward.item)
	claim("playtime", 1)
	equal(owned(reward.item) - before, reward.amount, "tiempo: da su premio")
	claim("playtime", 1)
	equal(owned(reward.item) - before, reward.amount, "tiempo: una sola vez al día")
	for _, bad in { 2, 0, 99, "x", 0 / 0, {}, true } do
		claim("playtime", bad)
	end
	equal(table.concat(state().claimed, ","), "1", "tiempo: lo que no está listo o no existe no se recoge")
	equal(type(df.player:GetAttribute("Daily")), "string", "estado publicado")
	df.advance(86400)
	df.step(1)
	equal(#state().claimed, 0, "día nuevo: lo recogido vuelve a cero")
	equal(state().seconds <= 2, true, "día nuevo: el tiempo vuelve a cero")
	equal(state().streak, 3, "día nuevo: la racha sigue")

	local broken = dailyInfo.sanitize({ day = 0 / 0, seconds = -5, claimed = { 1, 1, 99, "x", 2 }, streak = 50, streakDay = math.huge })
	equal(broken.day, 0, "guardado roto: día")
	equal(broken.seconds, 0, "guardado roto: segundos")
	equal(table.concat(broken.claimed, ","), "1,2", "guardado roto: recogidos sin repetir ni inventar")
	equal(broken.streak, 1, "guardado roto: casilla de la racha")
	equal(broken.streakDay, 0, "guardado roto: día de la racha")
	equal(dailyInfo.sanitize("x").streak, 1, "guardado que no es tabla")
end

print(`OK: {checks} comprobaciones; {compiled} scripts Luau compilados.`)
