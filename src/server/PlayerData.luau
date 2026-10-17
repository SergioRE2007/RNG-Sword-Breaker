-- Datos del jugador (monedas, gemas, espadas, objetos, artefactos, mejoras): carga, guardado y acceso.
-- El cliente los lee de los atributos del Player (ver publish). shared/Stats sabe interpretarlos.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local BagInfo = require(ReplicatedStorage.Shared.BagInfo)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local BalanceSnapshots = require(ReplicatedStorage.Shared.BalanceSnapshots)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local IndexInfo = require(ReplicatedStorage.Shared.IndexInfo)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Lang = require(ReplicatedStorage.Shared.Lang)
local WeaponLevel = require(ReplicatedStorage.Shared.WeaponLevel)

local PlayerData = {}

local sessions = {} -- [Player] = { data = {...}, canSave = boolean }
local store = nil -- nil = sin comprobar, false = no disponible
local loadHooks = {} -- funciones a las que se avisa cuando los datos de un jugador ya están cargados (PlayerData.onLoad)

local function getStore()
	if store == nil then
		store = false
		if game.PlaceId == 0 then
			warn("[PlayerData] Unpublished place: progress will not be saved.")
		else
			local ok, result = pcall(function()
				return DataStoreService:GetDataStore(Config.DataStoreName)
			end)
			if ok then
				store = result
			else
				warn("[PlayerData] DataStore not available: " .. tostring(result))
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
local BUSY_MESSAGE = "Your game is still being saved on another server. Come back in a couple of minutes."
local STOLEN_MESSAGE = "Your game has been opened on another server."
local FAILED_MESSAGE = "Your game couldn't be loaded. Come back in a couple of minutes."
local LOAD_TRIES = 3 -- intentos de cargar una partida cuando la lectura falla, antes de echar al jugador
local MAX_AMOUNT = 1e300 -- tope de lo que se guarda en monedas y gemas: un infinito no se puede guardar
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
	return (test.Progress or 0) > 0 or (test.AllPotions or 0) > 0 or (test.Tickets or 0) > 0 or (test.BestWeapons or 0) > 0 or test.Tutorial == true or (test.InfiniteMoney or test.AllWeapons or test.AllGear) and true or false
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
				warn(`[PlayerData] The save of {player.Name} is still open on another server: not loaded.`)
				player:Kick(Lang.t(player, BUSY_MESSAGE))
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

	-- "Swords" = copias del inventario como "id:espada:rasgo:grado:metal:tamaño" (0 = ninguno) separadas por comas; las
	-- bloqueadas por el jugador llevan ":1" detrás y, las que tienen nivel (Config.WeaponLevel), "candado:nivel" (":0:12").
	-- "Loadout" = ids de las copias equipadas, por orden de hueco ("3,7,1"); "Equipped" = el de la primera y
	-- "SwordLevel" = su tipo (índice de Config.Swords).
	local swords = {}
	local first = data.loadout[1]
	local equippedType = 1
	local equippedMetal, equippedSize = 0, 0
	for _, copy in data.swords do
		table.insert(swords, `{copy.id}:{copy.sword}:{copy.trait or 0}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}{if (copy.level or 0) > 0 then `:{if copy.locked then 1 else 0}:{copy.level}` elseif copy.locked then ":1" else ""}`)
		if copy.id == first then
			equippedType = copy.sword
			equippedMetal, equippedSize = copy.metal or 0, copy.size or 0
		end
	end
	player:SetAttribute("Swords", table.concat(swords, ","))
	player:SetAttribute("Loadout", table.concat(data.loadout, ","))
	player:SetAttribute("Bag", table.concat(data.bag.slots, ",")) -- ids de las depositadas en la Bolsa de oro
	player:SetAttribute("Equipped", first)
	player:SetAttribute("SwordLevel", equippedType)
	-- Metal y tamaño de la espada equipada (Swords los usa para construir la que lleva en la mano).
	player:SetAttribute("SwordMetal", equippedMetal)
	player:SetAttribute("SwordSize", equippedSize)
	player:SetAttribute("AutoSell", data.autoSell)
	player:SetAttribute("ArmorHidden", data.armorHidden)
	player:SetAttribute("TraitPriority", data.traitPriority)
	for _, kind in { "traits", "grades" } do
		local stops = data.stopAt[kind]
		player:SetAttribute("StopAt_" .. kind, if stops then table.concat(stops, ",") else nil)
	end
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
		-- "Bound_<nombre>" = cuántos de esos están atados a la cuenta (no se comercian; ver PlayerData.tradable).
		local bound = data.bound[name] or 0
		if sent["bound_" .. name] ~= bound then
			sent["bound_" .. name] = bound
			player:SetAttribute("Bound_" .. name, if bound > 0 then bound else nil)
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
		leaderstats.Coins.Value = Format.short(data.coins)
		leaderstats.Broken.Value = Format.short(data.broken)
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
	local function add(sword: number, trait: number?, grade: number?, metal: number?, size: number?, locked: boolean?, level: number?): number
		local id = #swords + 1
		local clean = WeaponLevel.sanitize(level)
		table.insert(swords, { id = id, sword = sword, trait = trait, grade = grade, metal = metal, size = size, locked = locked or nil, level = if clean > 0 then clean else nil })
		return id
	end

	local oldLevel = math.clamp(math.floor(tonumber(saved.swordLevel) or 1), 1, #Config.Swords)
	local equipped = nil -- (formatos antiguos) la única que se podía equipar
	-- Copias equipadas, ya con su id nuevo y por orden de hueco: sin repetir y hasta Config.Loadout.MaxSlots (al cargar
	-- aún no se sabe qué pases tiene: más de Slots solo las pudo equipar con el pase, que valida server/Gacha).
	local loadout = {}
	local function equip(id: number?)
		if id and not table.find(loadout, id) and #loadout < Config.Loadout.MaxSlots then
			table.insert(loadout, id)
		end
	end
	local deposited = {} -- copias que estaban en la Bolsa de oro, ya con su id nuevo
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
		local renumbered = {} -- [id guardado] = id nuevo (con ids repetidos, la última copia)
		for _, copy in saved.swords do
			if #swords >= Config.MaxSwords then
				break
			end
			if type(copy) == "table" and type(copy.sword) == "number" and Config.Swords[copy.sword] then
				local id = add(copy.sword, validTrait(copy.trait), validGrade(copy.grade), validMetal(copy.metal), validSize(copy.size), copy.locked == true, copy.level)
				if type(copy.id) == "number" and copy.id == copy.id then
					renumbered[copy.id] = id
				end
			end
		end
		-- Equipadas: la lista "loadout" o, en lo guardado cuando solo se equipaba una, la de "equipped".
		for _, old in if type(saved.loadout) == "table" then saved.loadout else { saved.equipped } do
			equip(renumbered[old])
		end
		-- Depositadas en la Bolsa de oro, con su id nuevo: sin repetir y hasta Config.GoldBag.MaxSlots.
		if type(saved.bag) == "table" and type(saved.bag.slots) == "table" then
			for _, old in saved.bag.slots do
				local id = if type(old) == "number" then renumbered[old] else nil
				if id and not table.find(deposited, id) and #deposited < Config.GoldBag.MaxSlots then
					table.insert(deposited, id)
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
	equip(equipped)
	-- Sin ninguna equipada solo se queda quien las quitó todas (su "loadout" guardado va vacío); lo antiguo, con la primera.
	if #loadout == 0 and type(saved.loadout) ~= "table" then
		loadout[1] = swords[1].id
	end
	data.swords = swords
	data.nextSwordId = #swords + 1
	data.loadout = loadout
	-- Bolsa de oro: por dónde iba y qué armas tenía dentro (una equipada no puede estar también en la bolsa).
	data.bag = BagInfo.sanitize(saved.bag)
	for _, id in deposited do
		if not table.find(loadout, id) then
			table.insert(data.bag.slots, id)
		end
	end
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
-- hora de juego (shared/BalanceSnapshots, generado por tools/equilibrio): mejoras, renacimientos, sus armas equipadas,
-- cada una con su rasgo y su grado, accesorios y una armadura puesta que suma lo que llevaría. Con menos horas que el primer estado
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
	-- Las primeras armas son las equipadas y las demás, las que deja en su Bolsa de oro.
	local loadout, deposited = {}, {}
	for _, entry in snapshot.swords do
		if Config.Swords[entry.sword] and #loadout + #deposited < Config.Loadout.Slots + Config.GoldBag.Slots then
			local id = data.nextSwordId
			data.nextSwordId += 1
			table.insert(data.swords, {
				id = id,
				sword = entry.sword,
				metal = if entry.metal > 0 then entry.metal else nil,
				size = if entry.size > 0 then entry.size else nil,
				trait = if entry.trait > 0 then entry.trait else nil,
				grade = if entry.grade > 0 then entry.grade else nil,
				level = if (entry.level or 0) > 0 then entry.level else nil,
			})
			table.insert(if #loadout < Config.Loadout.Slots then loadout else deposited, id)
		end
	end
	if #loadout > 0 then
		data.loadout = loadout
	end
	data.bag = BagInfo.sanitize({ stage = snapshot.bag })
	data.bag.slots = deposited
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
	-- grade = índice de Config.Grades o nil, level = nivel de Config.WeaponLevel o nil };
	-- loadout = ids de las copias equipadas, por orden de hueco (de 1 a Config.Loadout.Slots, sin repetir; lo guardado
	-- cuando solo se equipaba una trae "equipped", un solo id); autoSell = se venden solas las espadas de rareza menor (0 = no);
	-- items = { [nombre] = cantidad } (las pociones también son objetos); artifacts = índices de Config.Artifacts que tiene; gear = los equipados.
	-- armor = piezas de armadura (ver shared/ArmorStats); armorWorn = { [hueco] = id de la pieza equipada }.
	-- potions = pociones activas { [familia de Config.Potions.Families] = { tier, seconds = tiempo de juego que queda } }.
	-- index = Índice de armas: códigos de shared/IndexInfo de lo que le ha salido (nil hasta que server/Index lo estrena).
	-- bag = Bolsa de oro: { stage, taken, slots = ids de las copias depositadas, seen } (ver shared/BagInfo).
	local data = {
		coins = Config.StartCoins,
		gems = 0,
		rebirths = 0,
		playTime = 0, -- segundos jugados (clasificaciones)
		totalCoins = 0, -- monedas ganadas en total, sin descontar lo gastado (clasificaciones)
		robuxSpent = 0, -- Robux gastados en el juego (clasificaciones)
		broken = 0, -- objetos de la parcela rotos en total (marcador de la lista de jugadores)
		receipts = {}, -- últimas compras de productos ya entregadas (PurchaseId), para no dar una dos veces (server/Products)
		tutorial = 1, -- paso del tutorial por el que va (0 = terminado; server/Tutorial)
		codes = {}, -- códigos de regalo ya canjeados: { [código] = true } (server/Codes)
		passes = {}, -- pases comprados con tickets de misión: { [clave de Config.Gamepasses] = true } (ver server/Passes)
		missions = {}, -- misiones: { daily = { id, progress, claimed }, weekly = { ... } } (ver server/Missions)
		daily = DailyInfo.sanitize(nil), -- recompensas por tiempo jugado y por días (ver shared/DailyInfo)
		swords = { { id = 1, sword = 1 } },
		nextSwordId = 2,
		loadout = { 1 },
		bag = BagInfo.sanitize(nil),
		autoSell = 0,
		traitPriority = "luck,coins,damage", -- desempate de rasgos igual de raros (ver Modifiers.priority)
		stopAt = {}, -- "Parar con" de las tiendas: [traits o grades] = índices marcados; sin clave = lo de por defecto (ver Modifiers.stops)
		pity = Modifiers.newPity(nil),
		upgrades = {},
		items = {},
		bound = {}, -- { [nombre] = cuántos de items[nombre] están atados a la cuenta y no se comercian } (PlayerData.tradable)
		artifacts = {},
		gear = {},
		armor = {},
		nextArmorId = 1,
		armorWorn = {},
		armorHidden = false, -- armadura escondida: no se ve en el personaje pero sigue contando (server/Armor)
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
	-- Modo de pruebas (solo en Studio): empezar en una hora del calendario de progreso, sin guardar y sin lo que hubiera
	-- guardado (se parte de una partida vacía: si no, las monedas y las armas de la partida de verdad se mezclaban).
	local progress = RunService:IsStudio() and (Config.Test.Progress or 0) > 0

	local ds = getStore()
	-- En el juego publicado nadie juega una partida que no se va a guardar (perdería lo jugado, y lo comprado o lo
	-- recibido en un trato): si no se puede leer lo guardado, se reintenta y, si sigue sin poderse, se le echa con un aviso.
	local strict = game.PlaceId ~= 0 and not RunService:IsStudio()
	if not ds and strict then
		player:Kick(Lang.t(player, FAILED_MESSAGE))
		return
	end
	if ds then
		local ok, saved, lock = fetch(player, ds)
		for _ = 2, if strict then LOAD_TRIES else 1 do
			if ok ~= false or not player.Parent then
				break
			end
			task.wait(LOCK.Retry)
			ok, saved, lock = fetch(player, ds)
		end
		if ok == nil then
			return -- su partida sigue abierta en otro servidor: se le ha echado
		end
		if not ok and strict then
			warn(`[PlayerData] Could not load {player.Name}: {saved}`)
			if player.Parent then
				player:Kick(Lang.t(player, FAILED_MESSAGE))
			end
			return
		end
		lockId = lock
		if ok then
			canSave = true
			if type(saved) == "table" and not progress then
				data.coins = amount(saved.coins, data.coins)
				data.gems = amount(saved.gems, 0)
				local rebirths = tonumber(saved.rebirths) or 0
				data.rebirths = if rebirths == rebirths then math.clamp(math.floor(rebirths), 0, Config.Rebirth.max) else 0
				data.playTime = math.max(0, tonumber(saved.playTime) or 0)
				data.totalCoins = math.max(0, tonumber(saved.totalCoins) or 0)
				data.robuxSpent = math.max(0, math.floor(tonumber(saved.robuxSpent) or 0))
				data.broken = math.max(0, math.floor(tonumber(saved.broken) or 0))
				if type(saved.receipts) == "table" then
					for _, id in saved.receipts do
						if type(id) == "string" and #data.receipts < 100 then
							table.insert(data.receipts, id)
						end
					end
				end
				-- Quien ya tenía partida antes de existir el tutorial (sin el dato) no lo ve.
				local step = if type(saved.tutorial) == "number" then math.floor(saved.tutorial) else 0
				data.tutorial = if step >= 1 and step <= #Config.Tutorial.Steps then step else 0
				if type(saved.codes) == "table" then
					local kept = 0
					for key, value in saved.codes do
						if type(key) == "string" and value == true and kept < 500 then
							data.codes[key] = true
							kept += 1
						end
					end
				end
				if type(saved.passes) == "table" then
					for key in Config.Gamepasses do
						if saved.passes[key] == true then
							data.passes[key] = true
						end
					end
				end
				if type(saved.missions) == "table" then
					data.missions = loadMissions(saved.missions)
				end
				data.daily = DailyInfo.sanitize(saved.daily)
				data.autoSell = math.max(0, tonumber(saved.autoSell) or 0)
				data.armorHidden = saved.armorHidden == true
				data.pity = Modifiers.newPity(saved.pity)
				if type(saved.stopAt) == "table" then
					for _, kind in { "traits", "grades" } do
						data.stopAt[kind] = Modifiers.stops(kind, saved.stopAt[kind])
					end
				end
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
				if type(saved.bound) == "table" then
					for name in Config.Items do
						local bound = tonumber(saved.bound[name]) or 0
						bound = if bound == bound then math.clamp(math.floor(bound), 0, data.items[name]) else 0
						data.bound[name] = if bound > 0 then bound else nil
					end
				end
				if type(saved.artifacts) == "table" then
					for _, index in saved.artifacts do
						-- Repetidos sí, hasta el tope de copias de cada uno.
						local copies = 0
						for _, owned in data.artifacts do
							copies += if owned == index then 1 else 0
						end
						if type(index) == "number" and Config.Artifacts[index] and copies < Config.ArtifactCopies then
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
			warn(`[PlayerData] Could not load {player.Name}: {saved}`)
		end
	end

	if not player.Parent then
		if lockId then
			release(ds, "p_" .. player.UserId, lockId)
		end
		return
	end

	-- Config.Test.Progress manda sobre los demás modos de prueba de esta función (dinero infinito, todas las armas...),
	-- que con él no actúan: lo que se quiere ver es cómo va un jugador de verdad a esas alturas.
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

	-- Modo de pruebas (solo en Studio): copias del arma de más daño que existe (mejor arma, metal, tamaño, rasgo y
	-- grado), con las primeras ya equipadas. También sin guardar.
	local best = if RunService:IsStudio() and not progress then Config.Test.BestWeapons or 0 else 0
	if best > 0 then
		-- Índice de la entrada de más `field` de una lista de Config.
		local function top(list, field: string): number?
			local pick = nil
			for index, entry in list do
				if entry[field] and (not pick or entry[field] > list[pick][field]) then
					pick = index
				end
			end
			return pick
		end
		local sword, metal, size = top(Config.Swords, "damage"), top(Config.Metals, "odds"), top(Config.Sizes, "odds")
		local trait, grade = top(Config.Traits, "damage"), top(Config.Grades, "damage")
		local loadout = {}
		for _ = 1, best do
			local id = data.nextSwordId
			data.nextSwordId += 1
			table.insert(data.swords, { id = id, sword = sword, metal = metal, size = size, trait = trait, grade = grade, level = Config.WeaponLevel.MaxLevel })
			if #loadout < Config.Loadout.Slots then
				table.insert(loadout, id)
			end
		end
		data.loadout = loadout
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
	-- Marcador de Roblox (la lista de jugadores): monedas y objetos rotos, como texto ya abreviado con Format. Con un
	-- número, la lista de Roblox pone sus propias abreviaturas, que se acaban mucho antes que las del juego.
	for _, name in { "Coins", "Broken" } do
		local value = Instance.new("StringValue")
		value.Name = name
		value.Parent = leaderstats
	end
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
		-- Un infinito o un NaN no se pueden guardar, y un guardado que falla siempre es perderlo todo.
		for _, field in { "coins", "gems", "totalCoins" } do
			local value = out[field]
			if type(value) ~= "number" or value ~= value then
				out[field] = 0
			elseif value > MAX_AMOUNT then
				out[field] = MAX_AMOUNT
			end
		end
		out.lock = if final then nil else { id = session.lockId, time = os.time() }
		return out
	end)
	return ok and not lost, if ok then nil else err, lost
end

-- final = guardado de salida: suelta el candado, reintenta si falla y deja la sesión cerrada (ya no se guarda más).
-- Devuelve si la partida ha quedado escrita.
local function save(player: Player, final: boolean?): boolean
	local session = sessions[player]
	if not session or session.closing or not session.canSave or not getStore() then
		return false
	end
	local written = false
	local key = "p_" .. player.UserId
	if final then
		session.closing = true
		closing += 1
	end
	for try = 1, if final then LOCK.SaveTries else 1 do
		local done, err, lost = write(session, key, final == true)
		if done then
			written = true
			break
		end
		if lost then
			-- Un guardado normal que llega cuando el de salida ya ha soltado el candado no es un robo: se ignora.
			if not session.closing or final then
				session.canSave = false
				warn(`[PlayerData] The save of {player.Name} was opened on another server: this one is not saved.`)
				if player.Parent then
					player:Kick(Lang.t(player, STOLEN_MESSAGE))
				end
			end
			break
		end
		warn(`[PlayerData] Could not save {player.Name}: {err}`)
		if final and try < LOCK.SaveTries then
			task.wait(LOCK.Retry)
		end
	end
	if final then
		closing -= 1
	end
	return written
end

-- Guarda ya los datos del jugador (server/Rejoin, justo antes de reconectarlo: que el servidor al que va los lea al día).
-- Devuelve si ha quedado escrita (una compra de Robux solo se da por entregada cuando lo está: server/Products).
function PlayerData.save(player: Player): boolean
	return save(player)
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

-- Si esa copia está equipada (en cualquiera de los huecos de data.loadout).
function PlayerData.isEquipped(data, id: unknown): boolean
	return table.find(data.loadout, id) ~= nil
end

-- Si esa copia está depositada en la Bolsa de oro.
function PlayerData.inBag(data, id: unknown): boolean
	return table.find(data.bag.slots, id) ~= nil
end

-- Si esa copia está en uso (equipada o en la Bolsa de oro) o bloqueada por el jugador (candado de la mochila): no se
-- vende, no se va sola con la mochila llena y no se comercia.
function PlayerData.isLocked(data, id: unknown): boolean
	if PlayerData.isEquipped(data, id) or PlayerData.inBag(data, id) then
		return true
	end
	local copy = PlayerData.findSword(data, id)
	return copy ~= nil and copy.locked == true
end

-- Objetos atados a la cuenta (pedido por el usuario): los de los códigos y el tutorial no se comercian, porque con
-- cuentas nuevas se juntaban en una sola (tréboles y pociones de monedas). data.bound[nombre] = cuántos de
-- data.items[nombre] están atados; al gastar se gastan antes los atados.
function PlayerData.tradable(data, name: string): number
	local owned = data.items[name] or 0
	return math.max(0, owned - math.min(data.bound[name] or 0, owned))
end

-- Da `amount` de un objeto atado a la cuenta (dentro de PlayerData.edit).
function PlayerData.giveBound(data, name: string, amount: number)
	data.items[name] += amount
	data.bound[name] = (data.bound[name] or 0) + amount
end

-- Gasta `amount` de un objeto (dentro de PlayerData.edit; quien llama ya ha comprobado que los tiene).
function PlayerData.spendItem(data, name: string, amount: number)
	data.items[name] -= amount
	local bound = data.bound[name]
	if bound then
		bound = math.min(math.max(bound - amount, 0), data.items[name])
		data.bound[name] = if bound > 0 then bound else nil
	end
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

-- Un objeto de la parcela roto: cuenta para el marcador. Va antes de addCoins, que es quien publica.
function PlayerData.addBroken(player: Player)
	local session = sessions[player]
	if session then
		session.data.broken += 1
	end
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

-- Renacer (pedido por el usuario: ahora sí quita cosas): hace falta tener `cost` monedas y, de una sola vez, se
-- pierden todas las monedas, todas las gemas y todas las mejoras, la Bolsa de oro vuelve a la primera (con ella se
-- van las monedas de bolsa, que se cuentan por bolsas vaciadas) y se suma un renacimiento. Armas, accesorios,
-- armadura, objetos y las armas dejadas en la bolsa se quedan. Devuelve false, sin tocar nada, si no puede.
function PlayerData.rebirth(player: Player, cost: number): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	local data = session.data
	if data.rebirths >= Config.Rebirth.max or not (data.coins >= cost) then
		return false
	end
	-- Con dinero infinito (modo de pruebas) las monedas y las gemas no se tocan.
	if data.coins ~= math.huge then
		data.coins = 0
	end
	if data.gems ~= math.huge then
		data.gems = 0
	end
	for name in data.upgrades do
		data.upgrades[name] = 0
	end
	data.bag.stage = 1
	data.bag.taken = 0
	data.bag.seen = os.time()
	data.rebirths += 1
	publish(player)
	return true
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
