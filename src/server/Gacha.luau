-- Gacha de espadas: el motor de las tiradas de arma ("con esta suerte, ¿qué arma ha salido?") y la única puerta
-- por la que una tirada entrega una espada. Las tiradas las piden los objetos de la parcela al romperse
-- (Gacha.give, desde Combat) y, solo con Config.Gacha.FreeRoll, el botón de tirada gratis de antes. Lleva también
-- el inventario (equipar, vender y venta automática). No hay nada suyo en el mapa.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ObjectSpec = require(ReplicatedStorage.Shared.ObjectSpec)
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
	return math.min(Config.Gacha.AuraOdds, Config.Gacha.AnnounceOdds)
end

-- Aura en su personaje y, si es muy raro, aviso en el chat con la probabilidad real.
local function broadcast(player: Player, entry)
	if not player.Parent or not entry.kept then
		return
	end
	local sword = Config.Swords[entry.index]
	if entry.odds >= Config.Gacha.AuraOdds then
		Remotes.GachaAura:FireAllClients(player, entry.index, entry.odds)
	end
	if entry.odds >= Config.Gacha.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha conseguido {Permanent.name(entry.index, entry.metal, entry.size)}! {Permanent.describeOdds(entry.index, entry.metal, entry.size)}`, if entry.metal and entry.metal > 0 then Config.Metals[entry.metal].color else sword.color)
	end
end

-- Con la mochila llena: posición de la copia menos rara de las que el jugador no ha tocado (ni equipada, ni con
-- rasgo, ni con grado), si es menos rara que `rarity`. Las armas llegan solas al romper objetos y la mochila se
-- llena de las del montón: así una buena no se pierde por falta de sitio. nil si no hay ninguna peor.
local function worstSpare(data, rarity: number): number?
	local worst, worstRarity = nil, rarity
	for position, copy in data.swords do
		if copy.id ~= data.equipped and (copy.trait or 0) == 0 and (copy.grade or 0) == 0 then
			local copyRarity = Permanent.rarity(copy.sword, copy.metal, copy.size)
			if copyRarity < worstRarity then
				worst, worstRarity = position, copyRarity
			end
		end
	end
	return worst
end

local FULL_NOTICE_EVERY = 600 -- segundos entre avisos de mochila llena a un mismo jugador
local fullNotice = {} -- [player] = os.clock() de su último aviso

-- Con la mochila llena las armas menos raras van saliendo solas para hacer sitio (un arma recién llegada puede irse
-- al momento si la siguiente es mejor): se avisa de tarde en tarde, para que no parezca que desaparecen.
local function warnFull(player: Player)
	local now = os.clock()
	if now - (fullNotice[player] or -math.huge) < FULL_NOTICE_EVERY then
		return
	end
	fullNotice[player] = now
	Remotes.Notice:FireClient(player, `Mochila llena ({Config.MaxSwords}/{Config.MaxSwords}): las armas nuevas ocupan el sitio de las menos raras.\nLas que no mejoran ninguna se venden solas.`, Color3.fromRGB(255, 170, 60))
end

-- Saca una espada con la suerte `boost` del objeto que da la tirada (1 si no hay) por la suerte de armas propia
-- del jugador (Stats.gachaLuck) y la guarda sin equiparla. Ninguna otra
-- cosa multiplica esa suerte, y solo decide el arma: el metal y el tamaño se tiran con su probabilidad de siempre
-- (por la suerte propia). Se vende sola si es menos rara que el límite de venta automática del jugador o el
-- inventario está lleno de armas mejores que ella. Primero se guarda y después se le manda al jugador para que lo
-- enseñe: lo que ve es lo que ya tiene (`kept` solo es true si la copia ha quedado en sus datos). Si es raro para
-- su suerte, queda pendiente el aura en su personaje (y el aviso en el chat si es muy raro), que se manda a todos
-- cuando su cliente lo destapa. `info` (opcional) = de dónde viene, para enseñarlo:
-- { name, quality (del objeto), roll, rolls (esta tirada de cuántas) }.
local function draw(player: Player, boost: number, source: string, info)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local base = Stats.gachaLuck(player)
	-- La suerte del objeto se aplica UNA vez, al arma. El metal y el tamaño (permanentes, Config.Metals y Sizes) se
	-- tiran a la vez, pero con su probabilidad de siempre (solo la suerte de armas propia del jugador la sube): ni el
	-- objeto ni la mejora de suerte los abaratan. Con la suerte del objeto en las tres tiradas, un objeto de x4 sacaba
	-- armas con metal y tamaño 4 x 4 x 4 veces más, y uno de x7T daba armas de "1 entre decillones".
	local luck = base * boost
	local index = roll(luck)
	local metal = Permanent.roll(Config.Metals, base)
	local size = Permanent.roll(Config.Sizes, base)
	local rarity = Permanent.rarity(index, metal, size)
	-- Lo difícil que era para el jugador ("1 entre N"): es lo que mide el espectáculo, el aura y el aviso. La menor
	-- de dos cuentas, porque las dos se pasan de largo por un lado:
	--  · contra la suerte de sus objetos de siempre: un objeto mejor de lo normal da armas que para él son difíciles,
	--    y con mucha suerte de destructibles un arma rara deja de ser noticia;
	--  · lo raro que era el objeto por lo difícil que era el arma con la suerte de ese objeto: un objeto rarísimo da
	--    armas buenas casi siempre, y eso es tan probable como que salga el objeto, no más.
	-- (`usual` solo mide: no cambia lo que sale.)
	local usual = if source == "object" then base * ObjectSpec.usualLuck(Stats.luck(player)) else base
	local objectOdds = if info and type(info.objectOdds) == "number" then math.max(info.objectOdds, 1) else 1
	local odds = math.min(Permanent.odds(index, metal, size, usual, base), Permanent.odds(index, metal, size, luck, base) * objectOdds)
	-- Con la mochila llena, un arma más rara que la peor copia que el jugador no ha tocado se queda con su sitio.
	local full = #data.swords >= Config.MaxSwords
	local spare = if full and rarity >= data.autoSell then worstSpare(data, rarity) else nil
	if full and rarity >= data.autoSell then
		warnFull(player)
	end
	local stored: number? = nil -- id de la copia guardada: solo lo pone quien de verdad la mete en sus datos
	if rarity >= data.autoSell and (not full or spare ~= nil) then
		PlayerData.edit(player, function(edited)
			if spare then
				table.remove(edited.swords, spare)
				edited.gems += Config.Gacha.SellValue
			end
			local id = edited.nextSwordId
			edited.nextSwordId += 1
			table.insert(edited.swords, { id = id, sword = index, metal = if metal > 0 then metal else nil, size = if size > 0 then size else nil })
			stored = id
		end)
	end
	local kept = stored ~= nil
	if not kept then
		PlayerData.addGems(player, Config.Gacha.SellValue)
	end
	local extra = if info then table.clone(info) else {}
	extra.boost = boost
	extra.odds = odds
	extra.baseOdds = Config.Swords[index].rarity or 1
	extra.modifierOdds = { metal = if metal > 0 then Config.Metals[metal].odds else 1, size = if size > 0 then Config.Sizes[size].odds else 1 }
	extra.id = stored
	Remotes.GachaRolled:FireClient(player, index, kept, luck, source, metal, size, extra)
	Missions.add(player, "gacha")
	if rarity >= 1e6 then
		Missions.add(player, "rareSword")
	end
	-- Solo se presume de lo que se tiene: un arma vendida sola no lleva aura ni aviso (entra en la cola igual, para
	-- que no se descuadre con los avisos del cliente).
	if odds >= revealOdds() then
		local entry = { index = index, odds = odds, metal = metal, size = size, kept = kept }
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

local batches = 0 -- tandas de tiradas dadas (para numerarlas)

-- Tiradas de arma para el jugador con su suerte de armas multiplicada por `boost`. Es la puerta para cualquier
-- fuente de tiradas: hoy los objetos de la parcela (source = "object", con `rolls` y `boost` decididos por el
-- servidor al aparecer el objeto: nada de esto llega del cliente). `info` = { name, quality } de quien las da.
function Gacha.give(player: Player, boost: number, source: string, rolls: number?, info)
	-- Por si una fuente mal configurada pide de más (x ~= x descarta NaN).
	local count = rolls or 1
	if count ~= count or boost ~= boost or boost <= 0 then
		return
	end
	count = math.clamp(math.floor(count), 0, Config.ObjectRolls.MaxRolls)
	batches += 1
	for index = 1, count do
		local extra = if info then table.clone(info) else {}
		extra.roll = index
		extra.rolls = count
		extra.batch = batches -- las tiradas de una misma tanda: el cliente solo enseña en grande la mejor
		draw(player, boost, source, extra)
	end
end

local lastRoll = {} -- [player] = os.clock() de su última tirada

-- Tirada gratis del botón: solo existe con Config.Gacha.FreeRoll (si no, las tiradas salen de los objetos y una
-- petición del cliente no da nada).
local function onRoll(player: Player)
	if not Config.Gacha.FreeRoll then
		return
	end
	-- Un poco de margen por el retraso de la red.
	local now = os.clock()
	if now - (lastRoll[player] or 0) < Stats.rollTime(player) * 0.85 then
		return
	end
	lastRoll[player] = now
	draw(player, 1, "gacha")
end

local function onEquip(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if data and PlayerData.findSword(data, id) then
		PlayerData.edit(player, function(edited)
			edited.equipped = id
		end)
	end
end

local function onSellMany(player: Player, ids: unknown)
	local data = PlayerData.read(player)
	if not data or type(ids) ~= "table" then
		return
	end
	local wanted, count = {}, 0
	for _, id in ids do
		count += 1
		if count > Config.MaxSwords then return end
		if type(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 then return end
		wanted[id] = true
	end
	local sold = 0
	-- Sin esperas entre validar y retirar. El equipo se vuelve a comprobar en el estado real.
	PlayerData.edit(player, function(edited)
		for index = #edited.swords, 1, -1 do
			local copy = edited.swords[index]
			if wanted[copy.id] and copy.id ~= edited.equipped then
				table.remove(edited.swords, index)
				sold += 1
			end
		end
		edited.gems += sold * Config.Gacha.SellValue
	end)
	if sold > 0 then
		Remotes.Notice:FireClient(player, `Vendidas {sold} armas · +{Format.short(sold * Config.Gacha.SellValue)} gemas`, Config.RarityTiers[1].color)
	end
end

local function onSell(player: Player, id: unknown)
	onSellMany(player, { id })
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
	Remotes.SellSwords.OnServerEvent:Connect(onSellMany)
	Remotes.SetAutoSell.OnServerEvent:Connect(onSetAutoSell)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		pendingReveals[player] = nil
		fullNotice[player] = nil
	end)
end

return Gacha
