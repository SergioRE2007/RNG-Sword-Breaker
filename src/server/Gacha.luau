-- Gacha de espadas: tiradas gratis desde cualquier sitio (una cada Stats.rollTime segundos)
-- e inventario (equipar, vender y venta automática). No hay nada suyo en el mapa.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local Missions = require(script.Parent.Missions)

local Gacha = {}

-- Armas que salen en el gacha, de la más rara a la más común (Config.Swords no va ordenada por rareza).
local pool = {}
for index, sword in Config.Swords do
	if sword.rarity then
		table.insert(pool, index)
	end
end
table.sort(pool, function(a, b)
	return Config.Swords[a].rarity > Config.Swords[b].rarity
end)

-- Prueba de la más rara a la más común; la suerte multiplica cada probabilidad.
local function roll(luck: number): number
	for _, index in pool do
		if Chance.roll(luck / Config.Swords[index].rarity) then
			return index
		end
	end
	return 2
end

local pendingReveals = {} -- [player] = { { index, odds } } tiradas raras que aún no ha destapado

-- Desde qué "1 entre N" real hay algo que enseñar a los demás (aura o aviso).
local function revealOdds(): number
	return math.min(Config.Gacha.AuraOdds, Config.AnnounceOdds)
end

-- Aura en su personaje y, si es muy raro, aviso en el chat con la probabilidad real.
local function broadcast(player: Player, entry)
	if not player.Parent then
		return
	end
	local sword = Config.Swords[entry.index]
	if entry.odds >= Config.Gacha.AuraOdds then
		Remotes.GachaAura:FireAllClients(player, entry.index, entry.odds)
	end
	if entry.odds >= Config.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha conseguido {Permanent.name(entry.index, entry.metal, entry.size)} (1 entre {Format.short(entry.odds)})!`, if entry.metal and entry.metal > 0 then Config.Metals[entry.metal].color else sword.color)
	end
end

-- Saca una espada con suerte `luck` y la guarda como una copia más (se equipa si pega más que
-- la actual). Se vende sola si es menos rara que el límite de venta automática del jugador o
-- el inventario está lleno. Se lo manda al jugador para que lo enseñe; si es raro para su
-- suerte, queda pendiente el aura en su personaje (y el aviso en el chat si es muy raro), que se
-- manda a todos cuando su cliente lo destapa.
local function draw(player: Player, luck: number, source: string)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	-- Empujón del principio: las primeras tiradas de cada jugador llevan mucha suerte extra.
	if source == "gacha" then
		if data.gachaRolls < Config.Gacha.BoostRolls then
			luck *= Config.Gacha.BoostLuck
		end
		data.gachaRolls += 1
	end
	local index = roll(luck)
	local sword = Config.Swords[index]
	-- Metal y tamaño se tiran a la vez que el arma y son permanentes (Config.Metals, Config.Sizes).
	local metal = Permanent.roll(Config.Metals, luck)
	local size = Permanent.roll(Config.Sizes, luck)
	local rarity = Permanent.rarity(index, metal, size)
	local odds = rarity / luck
	local kept = rarity >= data.autoSell and #data.swords < Config.MaxSwords
	if kept then
		local candidate = { sword = index, trait = 0, grade = 0, metal = metal, size = size }
		local better = Stats.swordDamage(candidate) > Stats.swordDamage(Stats.equipped(player))
		PlayerData.edit(player, function(edited)
			local id = edited.nextSwordId
			edited.nextSwordId += 1
			table.insert(edited.swords, { id = id, sword = index, metal = if metal > 0 then metal else nil, size = if size > 0 then size else nil })
			if better then
				edited.equipped = id
			end
		end)
	else
		PlayerData.addGems(player, Config.Gacha.SellValue)
	end
	Remotes.GachaRolled:FireClient(player, index, kept, luck, source, metal, size)
	if source == "gacha" then
		Missions.add(player, "gacha")
	end
	if rarity >= 1e6 then
		Missions.add(player, "rareSword")
	end
	-- Cuenta la suerte: con mucha suerte de gacha, una espada rara ya no tiene aura ni aviso.
	if odds >= revealOdds() then
		local entry = { index = index, odds = odds, metal = metal, size = size }
		local queue = pendingReveals[player] or {}
		pendingReveals[player] = queue
		table.insert(queue, entry)
		-- Si el cliente no avisa (se cuelga, lo deja abierto), se manda igual pasado un rato.
		task.delay(Config.Gacha.RevealTimeout, function()
			local current = pendingReveals[player]
			local position = current and table.find(current, entry)
			if position then
				table.remove(current, position)
				broadcast(player, entry)
			end
		end)
	end
end

-- El cliente avisa de que ha destapado su siguiente tirada rara (van en orden).
local function onRevealed(player: Player)
	local queue = pendingReveals[player]
	if queue and #queue > 0 then
		broadcast(player, table.remove(queue, 1))
	end
end

-- Espada gratis (p. ej. la roca de armas) con la suerte de gacha multiplicada por `luckMultiplier`.
function Gacha.give(player: Player, luckMultiplier: number, source: string)
	draw(player, Stats.gachaLuck(player) * luckMultiplier, source)
end

local lastRoll = {} -- [player] = os.clock() de su última tirada

local function onRoll(player: Player)
	-- Un poco de margen por el retraso de la red.
	local now = os.clock()
	if now - (lastRoll[player] or 0) < Stats.rollTime(player) * 0.85 then
		return
	end
	lastRoll[player] = now
	draw(player, Stats.gachaLuck(player), "gacha")
end

local function onEquip(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if data and PlayerData.findSword(data, id) then
		PlayerData.edit(player, function(edited)
			edited.equipped = id
		end)
	end
end

local function onSell(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if not data or id == data.equipped then
		return
	end
	local _, position = PlayerData.findSword(data, id)
	if position then
		PlayerData.edit(player, function(edited)
			table.remove(edited.swords, position)
			edited.gems += Config.Gacha.SellValue
		end)
	end
end

local function onSetAutoSell(player: Player, rarity: unknown)
	-- rarity ~= rarity descarta NaN.
	if type(rarity) ~= "number" or rarity ~= rarity or rarity < 0 then
		return
	end
	PlayerData.edit(player, function(edited)
		edited.autoSell = rarity
	end)
end

function Gacha.start()
	Remotes.RollGacha.OnServerEvent:Connect(onRoll)
	Remotes.GachaRevealed.OnServerEvent:Connect(onRevealed)
	Remotes.EquipSword.OnServerEvent:Connect(onEquip)
	Remotes.SellSword.OnServerEvent:Connect(onSell)
	Remotes.SetAutoSell.OnServerEvent:Connect(onSetAutoSell)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		pendingReveals[player] = nil
	end)
end

return Gacha
