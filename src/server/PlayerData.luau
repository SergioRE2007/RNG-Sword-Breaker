-- Datos del jugador (monedas, gemas, espadas, objetos, artefactos, mejoras): carga, guardado y acceso.
-- El cliente los lee de los atributos del Player (ver publish). shared/Stats sabe interpretarlos.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local BalanceSnapshots = require(ReplicatedStorage.Shared.BalanceSnapshots)
local Config = require(ReplicatedStorage.Shared.Config)
local IndexInfo = require(ReplicatedStorage.Shared.IndexInfo)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)

local PlayerData = {}

local sessions = {} -- [Player] = { data = {...}, canSave = boolean }
local store = nil -- nil = sin comprobar, false = no disponible
local loadHooks = {} -- funciones a las que se avisa cuando los datos de un jugador ya están cargados (PlayerData.onLoad)

local function getStore()
	if store == nil then
		store = false
		if game.PlaceId == 0 then
			warn("[PlayerData] Lugar sin publicar: el progreso no se guardará.")
		else
			local ok, result = pcall(function()
				return DataStoreService:GetDataStore(Config.DataStoreName)
			end)
			if ok then
				store = result
			else
				warn("[PlayerData] DataStore no disponible: " .. tostring(result))
			end
		end
	end
	return store or nil
end

-- Candado de sesión (Config.SessionLock). Va dentro de lo guardado, en `lock = { id, time }`: id de la sesión que tiene
-- abierta la partida (uno por cada vez que se carga) y hora en que lo renovó. Se pone al cargar, se renueva en cada
-- guardado y se quita en el guardado de salida; todo con UpdateAsync, que lee y escribe de una vez. Sin él, quien sale y
-- entra deprisa en otro servidor podía cargar lo de antes del último guardado (por ejemplo, de antes de un trato).
local LOCK = Config.SessionLock
local BUSY_MESSAGE = "Tu partida todavía se está guardando en otro servidor. Vuelve a entrar en un par de minutos."
local STOLEN_MESSAGE = "Tu partida se ha abierto en otro servidor."
local closing = 0 -- guardados de salida en marcha (BindToClose espera a que acaben)

local function lockOf(saved)
	local lock = type(saved) == "table" and saved.lock
	if type(lock) == "table" and type(lock.id) == "string" and type(lock.time) == "number" then
		return lock
	end
	return nil
end

-- Los modos de prueba que dan cosas no guardan (ver load): tampoco cogen el candado.
local function testNoSave(): boolean
	local test = Config.Test
	if not RunService:IsStudio() then
		return false
	end
	return (test.Progress or 0) > 0 or (test.AllPotions or 0) > 0 or (test.InfiniteMoney or test.AllWeapons or test.AllGear) and true or false
end

-- Lee lo guardado y deja puesto el candado de esta sesión. Devuelve si fue bien, lo guardado (nil = partida nueva) y si
-- está cogido por otra sesión viva (entonces no se ha tocado nada).
local function claim(ds, key: string, lockId: string)
	local saved, blocked = nil, false
	local ok, err = pcall(ds.UpdateAsync, ds, key, function(current)
		local lock = lockOf(current)
		if lock and lock.id ~= lockId and os.time() - lock.time < LOCK.Expire then
			blocked = true
			return nil
		end
		blocked = false
		-- Un guardado que solo trae el candado es el de alguien cuyo servidor se cayó antes de su primer guardado.
		saved = nil
		if type(current) == "table" then
			for field in current do
				if field ~= "lock" then
					saved = current
					break
				end
			end
		end
		local out = if type(current) == "table" then current else {}
		out.lock = { id = lockId, time = os.time() }
		return out
	end)
	if not ok then
		return false, err, false
	end
	return true, saved, blocked
end

-- Suelta el candado sin tocar lo demás (el jugador se fue mientras cargaba, o la partida al final no se guarda).
local function release(ds, key: string, lockId: string)
	pcall(ds.UpdateAsync, ds, key, function(current)
		local lock = lockOf(current)
		if not lock or lock.id ~= lockId then
			return nil
		end
		current.lock = nil
		return current
	end)
end

-- Lo guardado del jugador, con su candado puesto. Devuelve ok (nil = sigue cogido y se le ha echado: no hay partida),
-- lo guardado o el error, y el id del candado (nil si no se ha cogido).
local function fetch(player: Player, ds)
	local key = "p_" .. player.UserId
	if testNoSave() then
		local ok, saved = pcall(ds.GetAsync, ds, key)
		return ok, saved, nil
	end
	local lockId = HttpService:GenerateGUID(false)
	local waited = 0
	while true do
		local ok, saved, blocked = claim(ds, key, lockId)
		if not ok then
			return false, saved, nil
		end
		if not blocked then
			return true, saved, lockId
		end
		if waited >= LOCK.Wait or not player.Parent then
			if player.Parent then
				warn(`[PlayerData] La partida de {player.Name} sigue abierta en otro servidor: no se carga.`)
				player:Kick(BUSY_MESSAGE)
			end
			return nil, nil, nil
		end
		task.wait(LOCK.Retry)
		waited += LOCK.Retry
	end
end

local function publish(player: Player)
	local session = sessions[player]
	local data = session.data
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Gems", data.gems)
	player:SetAttribute("Rebirths", data.rebirths)

	-- "Swords" = copias del inventario como "id:espada:rasgo:grado:metal:tamaño" (0 = ninguno) separadas por comas.
	-- "Equipped" = id de la copia equipada; "SwordLevel" = su tipo (índice de Config.Swords).
	local swords = {}
	local equippedType = 1
	local equippedMetal, equippedSize = 0, 0
	for _, copy in data.swords do
		table.insert(swords, `{copy.id}:{copy.sword}:{copy.trait or 0}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}`)
		if copy.id == data.equipped then
			equippedType = copy.sword
			equippedMetal, equippedSize = copy.metal or 0, copy.size or 0
		end
	end
	player:SetAttribute("Swords", table.concat(swords, ","))
	player:SetAttribute("Equipped", data.equipped)
	player:SetAttribute("SwordLevel", equippedType)
	-- Metal y tamaño de la espada equipada (Swords los usa para construir la que lleva en la mano).
	player:SetAttribute("SwordMetal", equippedMetal)
	player:SetAttribute("SwordSize", equippedSize)
	player:SetAttribute("AutoSell", data.autoSell)
	player:SetAttribute("TraitPriority", data.traitPriority)
	for _, kind in { "traits", "grades" } do
		player:SetAttribute("Pity_" .. kind, HttpService:JSONEncode(data.pity[kind]))
	end

	-- Los objetos (con las pociones son unos cuantos) solo se escriben si han cambiado: esto corre con cada moneda.
	local sent = session.itemsSent
	for name, count in data.items do
		if sent[name] ~= count then
			sent[name] = count
			player:SetAttribute("Item_" .. name, count)
		end
	end
	player:SetAttribute("Artifacts", table.concat(data.artifacts, ","))
	player:SetAttribute("Gear", table.concat(data.gear, ","))
	-- Armadura: "Armor" = inventario en JSON (ver ArmorStats.encode) y "Armor_<stat>" = total de lo equipado.
	-- Solo se vuelve a escribir cuando cambia (editArmor), no en cada moneda.
	if session.armorDirty then
		session.armorDirty = false
		player:SetAttribute("Armor", ArmorStats.encode(data.armor, data.armorWorn))
		for stat, total in ArmorStats.total(data.armor, data.armorWorn) do
			player:SetAttribute("Armor_" .. stat, total)
		end
	end
	for name, level in data.upgrades do
		player:SetAttribute("Upgrade_" .. name, level)
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Monedas.Value = math.floor(data.coins)
	end
end

local function validTrait(trait: unknown): number?
	return if type(trait) == "number" and Config.Traits[trait] then trait else nil
end

local function validMetal(metal: unknown): number?
	return if type(metal) == "number" and Config.Metals[metal] then metal else nil
end

local function validSize(size: unknown): number?
	return if type(size) == "number" and Config.Sizes[size] then size else nil
end

local function validGrade(grade: unknown): number?
	return if type(grade) == "number" and Config.Grades[grade] then grade else nil
end

-- Reconstruye el inventario de espadas a partir de lo guardado, en cualquiera de sus formatos.
local function loadSwords(data, saved)
	local swords = {}
	local function add(sword: number, trait: number?, grade: number?, metal: number?, size: number?): number
		local id = #swords + 1
		table.insert(swords, { id = id, sword = sword, trait = trait, grade = grade, metal = metal, size = size })
		return id
	end

	local oldLevel = math.clamp(math.floor(tonumber(saved.swordLevel) or 1), 1, #Config.Swords)
	local equipped = nil
	-- El formato lo dice la primera entrada que sea una copia o un tipo: con una entrada rota delante no se pierde el resto.
	local first = nil
	if type(saved.swords) == "table" then
		for _, entry in saved.swords do
			if type(entry) == "table" or type(entry) == "number" then
				first = entry
				break
			end
		end
	end

	if type(first) == "table" then
		-- Formato actual: copias { id, sword, trait, grade }. Los ids se renumeran.
		for _, copy in saved.swords do
			if #swords >= Config.MaxSwords then
				break
			end
			if type(copy) == "table" and type(copy.sword) == "number" and Config.Swords[copy.sword] then
				local id = add(copy.sword, validTrait(copy.trait), validGrade(copy.grade), validMetal(copy.metal), validSize(copy.size))
				if copy.id == saved.equipped then
					equipped = id
				end
			end
		end
	elseif type(first) == "number" then
		-- Formato del primer gacha: lista de tipos, una espada por tipo, rasgos aparte.
		local traits = if type(saved.traits) == "table" then saved.traits else {}
		for _, sword in saved.swords do
			if type(sword) == "number" and Config.Swords[sword] then
				local id = add(sword, validTrait(traits[tostring(sword)]))
				if sword == oldLevel then
					equipped = id
				end
			end
		end
	else
		-- Guardado anterior al gacha: las espadas se compraban en orden.
		for sword = 1, oldLevel do
			equipped = add(sword, nil)
		end
	end

	if #swords == 0 then
		add(1, nil)
	end
	data.swords = swords
	data.nextSwordId = #swords + 1
	data.equipped = equipped or swords[1].id
end

-- Cantidad guardada (monedas, gemas): ni NaN ni negativa. Con NaN toda comparación falla y trySpend dejaría comprar gratis.
local function amount(value: unknown, default: number): number
	local number = tonumber(value)
	return if number and number == number then math.max(0, number) else default
end

-- Misiones guardadas: solo el progreso que sea un número de verdad y los premios marcados como recogidos (del periodo
-- que toca se encarga server/Missions). Un progreso que no fuera un número daba error al sumarle.
local function loadMissions(saved)
	local missions = {}
	for _, period in { "daily", "weekly" } do
		local state = saved[period]
		if type(state) == "table" and type(state.progress) == "table" and type(state.claimed) == "table" then
			local progress, claimed = {}, {}
			for id, value in state.progress do
				if type(id) == "string" and type(value) == "number" and value == value and value >= 0 then
					progress[id] = value
				end
			end
			for id, value in state.claimed do
				if type(id) == "string" and value == true then
					claimed[id] = true
				end
			end
			missions[period] = { id = state.id, progress = progress, claimed = claimed }
		end
	end
	return missions
end

-- Armadura guardada: se revisa cada pieza (hueco, calidad y stats que existan) y los ids se renumeran.
local function loadArmor(data, saved)
	if type(saved.armor) ~= "table" then
		return
	end
	local worn = if type(saved.armorWorn) == "table" then saved.armorWorn else {}
	for _, piece in saved.armor do
		if #data.armor >= Config.Armor.MaxPieces then
			break
		end
		if type(piece) == "table" and Config.Armor.Slots[piece.slot] and Config.Armor.Qualities[piece.quality] and type(piece.stats) == "table" then
			local level = if Config.Dungeons[piece.level] then piece.level else 1
			local stats = {}
			for _, entry in piece.stats do
				-- value == value descarta NaN. El tope recorta las piezas guardadas cuando los porcentajes escalaban con el
				-- "power" de la zona (ahora con su "bonus", ver ArmorStats.scaling).
				if type(entry) == "table" and Config.Armor.Stats[entry.stat] and type(entry.value) == "number" and entry.value == entry.value and entry.value >= 0 then
					local value = math.min(entry.value, ArmorStats.cap(entry.stat, piece.quality, level))
					table.insert(stats, { stat = entry.stat, value = value, bonus = if entry.bonus == true then true else nil })
				end
			end
			local id = #data.armor + 1
			table.insert(data.armor, { id = id, slot = piece.slot, quality = piece.quality, level = level, stats = stats })
			if piece.id ~= nil and worn[piece.slot] == piece.id then
				data.armorWorn[piece.slot] = id
			end
		end
	end
	data.nextArmorId = #data.armor + 1
end

-- Modo de pruebas Config.Test.Progress: deja `data` como estaría el jugador tipo del calendario de progreso a esa
-- hora de juego (shared/BalanceSnapshots, generado por tools/equilibrio): mejoras, renacimientos, su arma equipada con
-- rasgo y grado, accesorios y una armadura puesta que suma lo que llevaría. Con menos horas que el primer estado
-- guardado, es una partida nueva.
local function applyProgress(data, hours: number)
	local snapshot = nil
	for _, entry in BalanceSnapshots do
		if entry.hours <= hours and (not snapshot or entry.hours > snapshot.hours) then
			snapshot = entry
		end
	end
	if not snapshot then
		return
	end
	for name, upgrade in Config.Upgrades do
		data.upgrades[name] = math.clamp(snapshot.upgrades[name] or 0, 0, upgrade.maxLevel)
	end
	data.rebirths = math.clamp(snapshot.rebirths, 0, Config.Rebirth.max)
	if Config.Swords[snapshot.sword] then
		local id = data.nextSwordId
		data.nextSwordId += 1
		table.insert(data.swords, {
			id = id,
			sword = snapshot.sword,
			metal = if snapshot.metal > 0 then snapshot.metal else nil,
			size = if snapshot.size > 0 then snapshot.size else nil,
			trait = if snapshot.trait > 0 then snapshot.trait else nil,
			grade = if snapshot.grade > 0 then snapshot.grade else nil,
		})
		data.equipped = id
	end
	data.artifacts, data.gear = {}, {}
	for _, index in snapshot.artifacts do
		if Config.Artifacts[index] then
			table.insert(data.artifacts, index)
		end
	end
	table.sort(data.artifacts)
	for _, index in snapshot.gear do
		if table.find(data.artifacts, index) and #data.gear < Config.GearSlots then
			table.insert(data.gear, index)
		end
	end
	-- Armadura: una pieza Rara por hueco de la mazmorra que le toca, con la vida de siempre y los porcentajes que
	-- sumaría la suya (suerte en el casco, ataque en las botas y aparición en las grebas).
	local level = math.clamp(snapshot.dungeon, 1, #Config.Dungeons)
	local quality = math.min(3, #Config.Armor.Qualities)
	local extra = { helmet = { "luck", snapshot.armor[1] }, boots = { "damage", snapshot.armor[2] }, legs = { "rollSpeed", snapshot.armor[3] } }
	for _, slot in Config.Armor.SlotOrder do
		local health = Config.Armor.Slots[slot].stats.health * Config.Armor.Qualities[quality].mult * Config.Dungeons[level].power
		local stats = { { stat = "health", value = math.round(health) } }
		if extra[slot] and extra[slot][2] > 0 then
			table.insert(stats, { stat = extra[slot][1], value = extra[slot][2] })
		end
		local id = data.nextArmorId
		data.nextArmorId += 1
		table.insert(data.armor, { id = id, slot = slot, quality = quality, level = level, stats = stats })
		data.armorWorn[slot] = id
	end
end

local function load(player: Player)
	-- swords = copias { id, sword = índice de Config.Swords, trait = índice de Config.Traits o nil,
	-- grade = índice de Config.Grades o nil };
	-- equipped = id de la copia equipada; autoSell = se venden solas las espadas de rareza menor (0 = no);
	-- items = { [nombre] = cantidad } (las pociones también son objetos); artifacts = índices de Config.Artifacts que tiene; gear = los equipados.
	-- armor = piezas de armadura (ver shared/ArmorStats); armorWorn = { [hueco] = id de la pieza equipada }.
	-- potions = pociones activas { [familia de Config.Potions.Families] = { tier, seconds = tiempo de juego que queda } }.
	-- index = Índice de armas: códigos de shared/IndexInfo de lo que le ha salido (nil hasta que server/Index lo estrena).
	local data = {
		coins = Config.StartCoins,
		gems = 0,
		rebirths = 0,
		playTime = 0, -- segundos jugados (clasificaciones)
		totalCoins = 0, -- monedas ganadas en total, sin descontar lo gastado (clasificaciones)
		robuxSpent = 0, -- Robux gastados en el juego (clasificaciones)
		missions = {}, -- misiones: { daily = { id, progress, claimed }, weekly = { ... } } (ver server/Missions)
		swords = { { id = 1, sword = 1 } },
		nextSwordId = 2,
		equipped = 1,
		autoSell = 0,
		traitPriority = "luck,coins,damage", -- desempate de rasgos igual de raros (ver Modifiers.priority)
		pity = Modifiers.newPity(nil),
		upgrades = {},
		items = {},
		artifacts = {},
		gear = {},
		armor = {},
		nextArmorId = 1,
		armorWorn = {},
		potions = {},
	}
	for name in Config.Upgrades do
		data.upgrades[name] = 0
	end
	for name in Config.Items do
		data.items[name] = 0
	end
	local canSave = false
	local lockId = nil -- candado de sesión que tiene cogido esta carga (nil = ninguno)

	local ds = getStore()
	if ds then
		local ok, saved, lock = fetch(player, ds)
		if ok == nil then
			return -- su partida sigue abierta en otro servidor: se le ha echado
		end
		lockId = lock
		if ok then
			canSave = true
			if type(saved) == "table" then
				data.coins = amount(saved.coins, data.coins)
				data.gems = amount(saved.gems, 0)
				local rebirths = tonumber(saved.rebirths) or 0
				data.rebirths = if rebirths == rebirths then math.clamp(math.floor(rebirths), 0, Config.Rebirth.max) else 0
				data.playTime = math.max(0, tonumber(saved.playTime) or 0)
				data.totalCoins = math.max(0, tonumber(saved.totalCoins) or 0)
				data.robuxSpent = math.max(0, math.floor(tonumber(saved.robuxSpent) or 0))
				if type(saved.missions) == "table" then
					data.missions = loadMissions(saved.missions)
				end
				data.autoSell = math.max(0, tonumber(saved.autoSell) or 0)
				data.pity = Modifiers.newPity(saved.pity)
				if type(saved.traitPriority) == "string" then
					data.traitPriority = saved.traitPriority
				end
				loadSwords(data, saved)
				data.index = IndexInfo.sanitize(saved.index)
				if type(saved.items) == "table" then
					for name in Config.Items do
						data.items[name] = math.max(0, tonumber(saved.items[name]) or 0)
					end
				end
				if type(saved.artifacts) == "table" then
					for _, index in saved.artifacts do
						if type(index) == "number" and Config.Artifacts[index] and not table.find(data.artifacts, index) then
							table.insert(data.artifacts, index)
						end
					end
				end
				if type(saved.gear) == "table" then
					for _, index in saved.gear do
						if table.find(data.artifacts, index) and not table.find(data.gear, index) and #data.gear < Config.GearSlots then
							table.insert(data.gear, index)
						end
					end
				end
				loadArmor(data, saved)
				-- Pociones activas: el tiempo es de juego, así que lo que quedó al salir es lo que queda al volver.
				data.potions = PotionInfo.sanitize(saved.potions)
				if type(saved.upgrades) == "table" then
					for name, upgrade in Config.Upgrades do
						local level = tonumber(saved.upgrades[name]) or 0 -- entero y sin NaN (math.clamp deja pasar el NaN)
						data.upgrades[name] = if level == level then math.clamp(math.floor(level), 0, upgrade.maxLevel) else 0
					end
				end
			end
		else
			-- Si la carga falla no guardamos después, para no pisar el progreso real.
			warn(`[PlayerData] No se pudo cargar a {player.Name}: {saved}`)
		end
	end

	if not player.Parent then
		if lockId then
			release(ds, "p_" .. player.UserId, lockId)
		end
		return
	end

	-- Modo de pruebas (solo en Studio): empezar en una hora del calendario de progreso, sin guardar. Manda sobre los
	-- demás modos de prueba de esta función (dinero infinito, todas las armas...), que con él no actúan: lo que se
	-- quiere ver es cómo va un jugador de verdad a esas alturas.
	local progress = RunService:IsStudio() and (Config.Test.Progress or 0) > 0
	if progress then
		applyProgress(data, Config.Test.Progress)
		canSave = false
	end

	-- Modo de pruebas (solo en Studio): dinero y objetos infinitos (cristales para la tienda de
	-- Rasgos) y sin guardar, para no pisar el progreso real.
	if RunService:IsStudio() and Config.Test.InfiniteMoney and not progress then
		data.coins = math.huge
		data.gems = math.huge
		for name in data.items do
			-- Las pociones no: se gastan, y así se puede probar que se acaban (las da Config.Test.AllPotions).
			if not Config.Items[name].potion then
				data.items[name] = math.huge
			end
		end
		canSave = false
	end

	-- Modo de pruebas (solo en Studio): AllPotions copias de cada poción, también sin guardar.
	if RunService:IsStudio() and (Config.Test.AllPotions or 0) > 0 and not progress then
		for _, key in Config.Potions.ItemKeys do
			data.items[key] = math.max(data.items[key], Config.Test.AllPotions)
		end
		canSave = false
	end

	-- Modo de pruebas (solo en Studio): una copia de cada arma que aún no tenga, también sin guardar.
	if RunService:IsStudio() and Config.Test.AllWeapons and not progress then
		local owned = {}
		for _, copy in data.swords do
			owned[copy.sword] = true
		end
		for index in Config.Swords do
			if not owned[index] then
				table.insert(data.swords, { id = data.nextSwordId, sword = index })
				data.nextSwordId += 1
			end
		end
		canSave = false
	end

	-- Modo de pruebas (solo en Studio): todos los accesorios, también sin guardar. La armadura de pruebas la da
	-- server/Armor (con el mismo interruptor), que es quien sabe tirar piezas.
	if RunService:IsStudio() and Config.Test.AllGear and not progress then
		for index in Config.Artifacts do
			if not table.find(data.artifacts, index) then
				table.insert(data.artifacts, index)
			end
		end
		table.sort(data.artifacts)
		canSave = false
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("NumberValue") -- un IntValue se desborda con cantidades enormes
	coins.Name = "Monedas"
	coins.Parent = leaderstats
	leaderstats.Parent = player

	-- Una partida que no se va a guardar no retiene el candado.
	if lockId and not canSave then
		task.spawn(release, ds, "p_" .. player.UserId, lockId)
		lockId = nil
	end
	sessions[player] = { data = data, canSave = canSave, lockId = lockId, armorDirty = true, itemsSent = {} }
	publish(player)
	for _, hook in loadHooks do
		task.spawn(hook, player)
	end
end

-- Escribe la partida si el candado sigue siendo de esta sesión. Devuelve si se escribió, si hubo un error y si el
-- candado ya no es suyo (otro servidor ha abierto la partida: lo de aquí está viejo y no se guarda).
local function write(session, key: string, final: boolean)
	local ds = getStore()
	local lost = false
	local ok, err = pcall(ds.UpdateAsync, ds, key, function(current)
		local lock = lockOf(current)
		if not lock or lock.id ~= session.lockId then
			lost = true
			return nil
		end
		lost = false
		local out = table.clone(session.data)
		out.lock = if final then nil else { id = session.lockId, time = os.time() }
		return out
	end)
	return ok and not lost, if ok then nil else err, lost
end

-- final = guardado de salida: suelta el candado, reintenta si falla y deja la sesión cerrada (ya no se guarda más).
local function save(player: Player, final: boolean?)
	local session = sessions[player]
	if not session or session.closing or not session.canSave or not getStore() then
		return
	end
	local key = "p_" .. player.UserId
	if final then
		session.closing = true
		closing += 1
	end
	for try = 1, if final then LOCK.SaveTries else 1 do
		local done, err, lost = write(session, key, final == true)
		if done then
			break
		end
		if lost then
			-- Un guardado normal que llega cuando el de salida ya ha soltado el candado no es un robo: se ignora.
			if not session.closing or final then
				session.canSave = false
				warn(`[PlayerData] La partida de {player.Name} se abrió en otro servidor: no se guarda la de este.`)
				if player.Parent then
					player:Kick(STOLEN_MESSAGE)
				end
			end
			break
		end
		warn(`[PlayerData] No se pudo guardar a {player.Name}: {err}`)
		if final and try < LOCK.SaveTries then
			task.wait(LOCK.Retry)
		end
	end
	if final then
		closing -= 1
	end
end

-- Guarda ya los datos del jugador (server/Rejoin, justo antes de reconectarlo: que el servidor al que va los lea al día).
function PlayerData.save(player: Player)
	save(player)
end

-- Avisa con callback(player) cuando los datos de un jugador ya están cargados (y ahora mismo, de los que ya lo estén).
function PlayerData.onLoad(callback: (Player) -> ())
	table.insert(loadHooks, callback)
	for player in sessions do
		task.spawn(callback, player)
	end
end

-- Datos en bruto del jugador (solo lectura), o nil si aún no han cargado.
function PlayerData.read(player: Player)
	local session = sessions[player]
	return session and session.data
end

-- Para cambiar espadas, objetos y artefactos: callback(data) modifica y luego se publica.
function PlayerData.edit(player: Player, callback)
	local session = sessions[player]
	if session then
		callback(session.data)
		publish(player)
	end
end

-- Como edit, para cambios que tocan la armadura (data.armor o data.armorWorn): vuelve a publicarla.
function PlayerData.editArmor(player: Player, callback)
	local session = sessions[player]
	if session then
		session.armorDirty = true
		callback(session.data)
		publish(player)
	end
end

-- Copia de espada con ese id y su posición en data.swords, o nil.
function PlayerData.findSword(data, id: unknown)
	for position, copy in data.swords do
		if copy.id == id then
			return copy, position
		end
	end
	return nil
end

function PlayerData.getCoins(player: Player): number
	local session = sessions[player]
	return session and session.data.coins or 0
end

function PlayerData.addCoins(player: Player, amount: number)
	local session = sessions[player]
	if session then
		session.data.coins += amount
		if amount > 0 then
			session.data.totalCoins += amount
		end
		publish(player)
	end
end

function PlayerData.trySpend(player: Player, cost: number): boolean
	local session = sessions[player]
	if not session or session.data.coins < cost then
		return false
	end
	session.data.coins -= cost
	publish(player)
	return true
end

function PlayerData.addGems(player: Player, amount: number)
	local session = sessions[player]
	if session then
		session.data.gems += amount
		publish(player)
	end
end

function PlayerData.trySpendGems(player: Player, cost: number): boolean
	local session = sessions[player]
	if not session or session.data.gems < cost then
		return false
	end
	session.data.gems -= cost
	publish(player)
	return true
end

-- Para las clasificaciones: segundos jugados y Robux gastados (el resto de números van en data).
function PlayerData.addPlayTime(player: Player, seconds: number)
	local session = sessions[player]
	if session then
		session.data.playTime += seconds
	end
end

function PlayerData.addRobuxSpent(player: Player, robux: number)
	local session = sessions[player]
	if session and robux > 0 then
		session.data.robuxSpent += math.floor(robux)
	end
end

-- Suma un renacimiento (el cobro lo hace quien llama, con trySpend).
function PlayerData.addRebirth(player: Player)
	local session = sessions[player]
	if session and session.data.rebirths < Config.Rebirth.max then
		session.data.rebirths += 1
		publish(player)
	end
end

-- Tipo (índice de Config.Swords) de la espada equipada.
function PlayerData.getSwordLevel(player: Player): number
	return player:GetAttribute("SwordLevel") or 1
end

function PlayerData.getUpgrade(player: Player, name: string): number
	local session = sessions[player]
	return session and session.data.upgrades[name] or 0
end

function PlayerData.setUpgrade(player: Player, name: string, level: number)
	local session = sessions[player]
	if session then
		session.data.upgrades[name] = level
		publish(player)
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		sessions[player] = nil
	end)

	-- Al cerrarse el servidor: todos a la vez (uno detrás de otro no daría tiempo) y esperar también a los guardados de
	-- salida que ya estuvieran en marcha.
	game:BindToClose(function()
		for player in sessions do
			task.spawn(save, player, true)
		end
		while closing > 0 do
			task.wait()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				save(player)
			end
		end
	end)
end

return PlayerData
