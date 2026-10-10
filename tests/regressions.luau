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

local function fixture(saved)
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
	}
	local store = {
		GetAsync = function() return saved end,
		SetAsync = function(_, _, data) saved = data end,
	}
	local services = {
		ReplicatedStorage = { Shared = node("src/shared") },
		Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return players end },
		RunService = { IsStudio = function() return false end, Heartbeat = signal() },
		TextService = {},
		HttpService = http,
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
		env.os = table.clone(os)
		env.os.clock = function() return now end
		cache[path] = luau.load(fs.readFile(path .. ".luau"), { debugName = path, environment = env, injectGlobals = true })()
		return cache[path]
	end
	local config = loadModule("src/shared/Config")
	local data = loadModule("src/server/PlayerData")
	data.start()
	return {
		load = loadModule, config = config, data = data, player = player, remotes = remotes, services = services,
		overrides = overrides, workspace = workspace, players = players, random = random, tags = tags,
		advance = function(seconds) now += seconds end,
		step = function(seconds)
			now += seconds
			for _, job in table.clone(jobs) do if coroutine.status(job) == "suspended" then resume(job) end end
		end,
		save = function() services.Players.PlayerRemoving:fire(player); return saved end,
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
equal(data.read(player).equipped, 1, "espada inicial equipada")
equal(#data.read(player).gear, 0, "accesorios iniciales sin equipar")
for index, sword in config.Swords do
	near(sword.damage, 1.5 ^ math.max(math.log((sword.rarity or 2) / 2, 2), 0), "daño de arma " .. index)
end
equal(config.damageFromRarity(2), 1, "rareza inicial")
near(config.damageFromRarity(8), 2.25, "curva de daño")
local label = permanent.describeOdds(4, 1, 1)
assert(label:find("Arma: 1 entre", 1, true) and label:find(config.Metals[1].name, 1, true) and label:find(config.Sizes[1].name, 1, true))
checks += 1

-- Pity: límite base, obtención natural, colisiones, desempate y separación de contadores.
for _, kind in { "traits", "grades" } do
	local counters = modifiers.newPity(nil)[kind]
	for index in modifiers.KINDS[kind].list do
		equal(modifiers.pityLimit(kind, index), math.ceil(100 / modifiers.percent(kind, index)), "límite " .. kind .. index)
		counters[index] = modifiers.pityLimit(kind, index) - 1
	end
	local expected = 1
	for index in counters do
		if modifiers.better(kind, index, expected, modifiers.PRIORITY) then expected = index end
	end
	local result = modifiers.rollWithPity(kind, f.random, 1e9, counters, modifiers.PRIORITY)
	equal(result, expected, "garantía más rara " .. kind)
	equal(counters[result], 0, "reinicio " .. kind)
	for index in counters do
		if index ~= result then equal(counters[index], modifiers.pityLimit(kind, index), "garantía pendiente " .. kind .. index) end
	end
	local nextResult = modifiers.rollWithPity(kind, f.random, 1, counters, modifiers.PRIORITY)
	assert(nextResult ~= result, "no perder las otras garantías")
	checks += 1
	local clean = modifiers.newPity(nil)[kind]
	local natural = modifiers.rollWithPity(kind, f.random, 1, clean, modifiers.PRIORITY)
	equal(natural, 1, "resultado natural controlado " .. kind)
	equal(clean[1], 0, "obtención natural reinicia " .. kind)
end
local sanitized = modifiers.newPity({ traits = { -5, 0 / 0, math.huge, 1.9 }, grades = "inválido" })
equal(sanitized.traits[1], 0, "pity negativo")
equal(sanitized.traits[2], 0, "pity NaN")
equal(sanitized.traits[3], modifiers.pityLimit("traits", 3), "pity acotado")
equal(sanitized.traits[4], 1, "pity entero")
equal(sanitized.grades[1], 0, "pity antiguo vacío")
local tied = modifiers.newPity(nil).traits
for index = 1, 3 do tied[index] = modifiers.pityLimit("traits", index) - 1 end
equal(modifiers.rollWithPity("traits", f.random, 1, tied, { "damage", "coins", "luck" }), 2, "empate respeta prioridad del jugador")
equal(tied[1], modifiers.pityLimit("traits", 1), "empate no pierde garantía pendiente")

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
equal(data.read(player).equipped, 3, "arma nueva no se equipa")
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

-- Renacimiento: cinco compras, ninguna sexta, ni cobro por intento fallido.
f.load("src/server/Rebirth").start()
data.edit(player, function(d) d.coins = 1e100 end)
for count = 1, 5 do
	f.advance(1)
	f.remotes.Rebirth.OnServerEvent:fire(player)
	equal(data.read(player).rebirths, count, "renacimiento " .. count)
end
local coins = data.read(player).coins
f.advance(1)
f.remotes.Rebirth.OnServerEvent:fire(player)
equal(data.read(player).rebirths, 5, "máximo cinco")
equal(data.read(player).coins, coins, "sexto sin cobro")
data.edit(player, function(d) d.rebirths = 0; d.coins = 0 end)
f.advance(1)
f.remotes.Rebirth.OnServerEvent:fire(player)
equal(data.read(player).rebirths, 0, "sin dinero no renace")

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

-- Guardado real y migración de inventario: conserva elección, Pity y equipa solo lo guardado.
state.pity.traits[2] = 1
local saved = f.save()
local restored = fixture(saved)
equal(restored.data.read(restored.player).pity.traits[2], 1, "pity persiste")
equal(restored.data.read(restored.player).swords[restored.data.read(restored.player).equipped].sword, 5, "elección persiste al renumerar ids")
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
for name, kind in config.WeaponKinds do
	equal(hitbox.reaches(target(0, 0, -5), CFrame.identity, 5, kind.arc), true, "delante " .. name)
	equal(hitbox.reaches(target(0, 8, -2), CFrame.identity, 5, kind.arc), false, "fuera altura " .. name)
	equal(hitbox.reaches(target(0, 0, -20), CFrame.identity, 5, kind.arc), false, "fuera alcance " .. name)
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
local plot = { cframe = CFrame.identity, spawnOffset = Vector3.new(0, 0, -44), owner = spawn.player }
spawn.overrides["src/server/Plots"] = { all = function() return { plot } end, get = function() return plot end, onRelease = function() end }
spawn.overrides["src/shared/ObjectModel"] = { attach = function() end }
spawn.overrides["src/shared/Chance"] = { roll = function() return false end }
local specs = spawn.load("src/shared/ObjectSpec")
local rolls = 0
specs.roll = function()
	rolls += 1
	return { quality = 1, size = 1, scale = 1, hp = 10, luck = 99, rolls = 1, reward = 1, odds = 1 }
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
-- El arma más rara sigue siéndolo con toda la suerte al máximo, y ni el mejor objeto posible la garantiza.
local top = 0
for _, sword in f.config.Swords do
	top = math.max(top, sword.rarity or 0)
end
local gachaMax = f.config.Rebirth.gachaLuck ^ f.config.Rebirth.max
local _, highest = objectSpec.scaleLimits(rarest)
equal(objectSpec.luck(rarest, 1, 1) * gachaMax / top < 1e-4, true, "el arma más rara es rara con la suerte al máximo")
equal(objectSpec.luck(rarest, #f.config.ObjectRarities, highest) * gachaMax / top < 0.05, true, "ni el mejor objeto la garantiza")
-- El tamaño y la rareza del objeto pesan de verdad en la suerte de armas.
equal(objectSpec.luck(rarest, 1, 2) / objectSpec.luck(rarest, 1, 1) >= 8, true, "el tamaño pesa en la suerte de armas")
equal(objectSpec.luck(rarest, #f.config.ObjectRarities, 1) / objectSpec.luck(rarest, 1, 1) >= 20, true, "la rareza pesa en la suerte de armas")
-- Velocidad de golpe: tiempo base por el tipo de arma, y solo su poción lo baja.
local swingBefore = stats.cooldown(f.player)
local _, weaponKind = stats.weapon(f.player)
near(swingBefore, f.config.BaseCooldown * weaponKind.cooldown, "tiempo base entre golpes")
f.player:SetAttribute("Potion_attackSpeed", 3)
near(stats.cooldown(f.player), swingBefore / f.config.Potions.Families.attackSpeed.values[3], "la poción acelera el golpe")
f.player:SetAttribute("Potion_attackSpeed", nil)
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
end)
tf.advance(10)
tf.remotes.TradeRequest.OnServerEvent:fire(tf.player, 0)
local function tradeState()
	local sent = tf.remotes.TradeState.sent
	return sent[#sent][2]
end
equal(tradeState().state, "editing", "trato abierto con el bot")
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
tf.remotes.TradeCancel.OnServerEvent:fire(tf.player)
equal(tf.data.read(tf.player).coins, 1e6, "el trato cancelado no toca las monedas")

print(`OK: {checks} comprobaciones; {compiled} scripts Luau compilados.`)
