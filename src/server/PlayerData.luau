-- Datos del jugador (monedas, gemas, espadas, objetos, artefactos, mejoras): carga, guardado y acceso.
-- El cliente los lee de los atributos del Player (ver publish). shared/Stats sabe interpretarlos.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
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
	local first = type(saved.swords) == "table" and saved.swords[1]

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
			local stats = {}
			for _, entry in piece.stats do
				-- value == value descarta NaN.
				if type(entry) == "table" and Config.Armor.Stats[entry.stat] and type(entry.value) == "number" and entry.value == entry.value and entry.value >= 0 then
					table.insert(stats, { stat = entry.stat, value = entry.value, bonus = if entry.bonus == true then true else nil })
				end
			end
			local id = #data.armor + 1
			table.insert(data.armor, { id = id, slot = piece.slot, quality = piece.quality, level = if Config.Dungeons[piece.level] then piece.level else 1, stats = stats })
			if piece.id ~= nil and worn[piece.slot] == piece.id then
				data.armorWorn[piece.slot] = id
			end
		end
	end
	data.nextArmorId = #data.armor + 1
end

local function load(player: Player)
	-- swords = copias { id, sword = índice de Config.Swords, trait = índice de Config.Traits o nil,
	-- grade = índice de Config.Grades o nil };
	-- equipped = id de la copia equipada; autoSell = se venden solas las espadas de rareza menor (0 = no);
	-- items = { [nombre] = cantidad } (las pociones también son objetos); artifacts = índices de Config.Artifacts que tiene; gear = los equipados.
	-- armor = piezas de armadura (ver shared/ArmorStats); armorWorn = { [hueco] = id de la pieza equipada }.
	-- potions = pociones activas { [familia de Config.Potions.Families] = { tier, seconds = tiempo de juego que queda } }.
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

	local ds = getStore()
	if ds then
		local ok, saved = pcall(ds.GetAsync, ds, "p_" .. player.UserId)
		if ok then
			canSave = true
			if type(saved) == "table" then
				data.coins = tonumber(saved.coins) or data.coins
				data.gems = tonumber(saved.gems) or 0
				local rebirths = tonumber(saved.rebirths) or 0
				data.rebirths = if rebirths == rebirths then math.clamp(math.floor(rebirths), 0, Config.Rebirth.max) else 0
				data.playTime = math.max(0, tonumber(saved.playTime) or 0)
				data.totalCoins = math.max(0, tonumber(saved.totalCoins) or 0)
				data.robuxSpent = math.max(0, math.floor(tonumber(saved.robuxSpent) or 0))
				if type(saved.missions) == "table" then
					data.missions = saved.missions
				end
				data.autoSell = math.max(0, tonumber(saved.autoSell) or 0)
				data.pity = Modifiers.newPity(saved.pity)
				if type(saved.traitPriority) == "string" then
					data.traitPriority = saved.traitPriority
				end
				loadSwords(data, saved)
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
						data.upgrades[name] = math.clamp(tonumber(saved.upgrades[name]) or 0, 0, upgrade.maxLevel)
					end
				end
			end
		else
			-- Si la carga falla no guardamos después, para no pisar el progreso real.
			warn(`[PlayerData] No se pudo cargar a {player.Name}: {saved}`)
		end
	end

	if not player.Parent then
		return
	end

	-- Modo de pruebas (solo en Studio): dinero y objetos infinitos (cristales para la tienda de
	-- Rasgos) y sin guardar, para no pisar el progreso real.
	if RunService:IsStudio() and Config.Test.InfiniteMoney then
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
	if RunService:IsStudio() and (Config.Test.AllPotions or 0) > 0 then
		for _, key in Config.Potions.ItemKeys do
			data.items[key] = math.max(data.items[key], Config.Test.AllPotions)
		end
		canSave = false
	end

	-- Modo de pruebas (solo en Studio): una copia de cada arma que aún no tenga, también sin guardar.
	if RunService:IsStudio() and Config.Test.AllWeapons then
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
	if RunService:IsStudio() and Config.Test.AllGear then
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

	sessions[player] = { data = data, canSave = canSave, armorDirty = true, itemsSent = {} }
	publish(player)
	for _, hook in loadHooks do
		task.spawn(hook, player)
	end
end

local function save(player: Player)
	local session = sessions[player]
	local ds = getStore()
	if not session or not session.canSave or not ds then
		return
	end
	local ok, err = pcall(ds.SetAsync, ds, "p_" .. player.UserId, session.data)
	if not ok then
		warn(`[PlayerData] No se pudo guardar a {player.Name}: {err}`)
	end
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
		save(player)
		sessions[player] = nil
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
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
