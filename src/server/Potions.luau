-- Pociones (Config.Potions): aceleradores temporales. Cada poción es un objeto normal del inventario
-- (Config.Items["potion_<familia>_<tier>"], PlayerData.items, se amontonan por cantidad) y la activa de cada familia vive
-- en data.potions[familia] = { tier, seconds }: lo que le queda, en segundos DE JUEGO. Solo baja con el jugador conectado
-- (un solo bucle para todos, una vez por segundo, y solo mira a los que tienen alguna activa), así que se guarda tal cual
-- y al volver sigue donde estaba. El efecto lo leen shared/Stats y el cliente de los atributos del Player:
-- "Potion_<familia>" = tier (se quita al caducar) y "PotionEnd_<familia>" = hora del servidor en que acaba
-- (workspace:GetServerTimeNow, para el reloj del HUD); se escriben solo cuando algo cambia, no cada segundo.
-- Aquí también salen las que caen de los objetos de la parcela (Potions.onBroken, desde Combat) y de las mazmorras
-- (Loot, kind = "potion"). El cliente solo pide usarlas (UsePotion); el servidor valida y decide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Potions = {}

local cfg = Config.Potions
local random = Random.new()
local RED = Color3.fromRGB(255, 120, 110)

local ticking = {} -- [Player] = os.clock() de la última vez que se les restó tiempo (los que tienen alguna activa)
local lastUse = {} -- [Player] = os.clock() de su última petición de uso

-- Deja en el Player lo de esa familia: su tier y la hora del servidor a la que acaba (nil = ninguna activa). El fin va
-- primero: cuando el cliente nota el tier nuevo ya tiene su reloj.
local function publish(player: Player, family: string, potion)
	player:SetAttribute("PotionEnd_" .. family, if potion then workspace:GetServerTimeNow() + potion.seconds else nil)
	player:SetAttribute("Potion_" .. family, if potion then potion.tier else nil)
end

-- Resta el tiempo jugado desde la última vez a las pociones activas del jugador y quita las que se acaban.
local function settle(player: Player, data)
	local last = ticking[player]
	if not last then
		return
	end
	local now = os.clock()
	local elapsed = now - last
	ticking[player] = now
	local anyLeft = false
	for family, potion in data.potions do
		potion.seconds -= elapsed
		if potion.seconds > 0 then
			anyLeft = true
		else
			data.potions[family] = nil
			publish(player, family, nil)
			local key = PotionInfo.key(family, potion.tier)
			Remotes.Notice:FireClient(player, `Se ha acabado: {Config.Items[key].name}`, Config.Items[key].color)
		end
	end
	if not anyLeft then
		ticking[player] = nil
	end
end

local function tick()
	for player in ticking do
		local data = PlayerData.read(player)
		if data then
			settle(player, data)
		else
			ticking[player] = nil
		end
	end
end

-- Quién gana con pesos: la posición en `weights` (los que faltan o son 0 no salen), o nil si todo vale 0.
local function weighted(weights: { number }, count: number): number?
	local total = 0
	for index = 1, count do
		total += weights[index] or 0
	end
	if total <= 0 then
		return nil
	end
	local pick = random:NextNumber() * total
	for index = 1, count do
		local weight = weights[index] or 0
		if weight > 0 then
			pick -= weight
			if pick < 0 then
				return index
			end
		end
	end
	return nil
end

-- Qué poción cae de esa fuente ("object" o "dungeon") con ese nivel de contenido (1 bajo ... 5 excepcional): la familia
-- por su peso en el nivel y luego el tier por los pesos de esa familia (Config.Potions.Pools).
local function pick(source: string, level: number): (string?, number?)
	local pools = cfg.Pools[source]
	local pool = pools[math.clamp(level, 1, #pools)]
	local familyWeights = {}
	for index, family in cfg.Order do
		familyWeights[index] = if pool[family] then pool[family].weight else 0
	end
	local familyIndex = weighted(familyWeights, #cfg.Order)
	if not familyIndex then
		return nil, nil
	end
	local family = cfg.Order[familyIndex]
	local tier = weighted(pool[family].tiers, #cfg.Families[family].values)
	return family, tier
end

-- Entrega una poción (un objeto más del inventario) y se lo avisa; las más raras, a todo el servidor. Devuelve la clave
-- del objeto, o nil si algo no cuadra.
function Potions.give(player: Player, family: string, tier: number): string?
	if not PotionInfo.valid(family, tier) or not PlayerData.read(player) then
		return nil
	end
	local key = PotionInfo.key(family, tier)
	local item = Config.Items[key]
	PlayerData.edit(player, function(data)
		data.items[key] += 1
	end)
	Remotes.Notice:FireClient(player, `+1 {item.name}`, item.color)
	if tier >= cfg.AnnounceFrom then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha conseguido {item.name}!`, item.color)
	end
	return key
end

-- Tira una poción de esa fuente y nivel de contenido y se la da al jugador. Devuelve la clave del objeto, o nil.
function Potions.drop(player: Player, source: string, level: number): string?
	local family, tier = pick(source, level)
	if family and tier then
		return Potions.give(player, family, tier)
	end
	return nil
end

-- Se llama cuando el jugador rompe un objeto de su parcela (def = entrada de Config.Destructibles, object = su ficha):
-- la probabilidad depende de su tipo (nivel de contenido) y de la rareza que le tocó al aparecer.
function Potions.onBroken(player: Player, def, object)
	local level = cfg.ObjectLevel[table.find(Config.Destructibles, def) or 0] or #cfg.Pools.object
	local chance = (cfg.ObjectChance[level] or 0) * (cfg.QualityChance[object.quality] or 1)
	if Chance.roll(chance) then
		Potions.drop(player, "object", level)
	end
end

-- El jugador pide usar una poción. Reglas: sin ninguna activa de esa familia, se activa; si la nueva es de un tier
-- superior, sustituye a la activa con su duración entera; si es del mismo tier, suma su duración (hasta MaxStack veces
-- la del tier); si es inferior, no se gasta. Todo se comprueba aquí: lo único que manda el cliente es qué quiere usar.
local function onUse(player: Player, requestedFamily: unknown, requestedTier: unknown)
	local now = os.clock()
	if now - (lastUse[player] or 0) < cfg.UseCooldown then
		return
	end
	lastUse[player] = now
	if not PotionInfo.valid(requestedFamily, requestedTier) then
		return
	end
	local family, tier = requestedFamily :: string, requestedTier :: number
	local data = PlayerData.read(player)
	local key = PotionInfo.key(family, tier)
	if not data or (data.items[key] or 0) < 1 then
		return
	end

	settle(player, data)
	local name = Config.Items[key].name
	local color = Config.Items[key].color
	local active = data.potions[family]
	local base = PotionInfo.duration(tier)
	local seconds = base
	local message
	if not active then
		message = `Poción activada: {name}`
	elseif tier > active.tier then
		message = `¡Poción mejorada! {name}`
	elseif tier == active.tier then
		local cap = PotionInfo.cap(tier)
		if active.seconds >= cap - 0.5 then
			Remotes.Notice:FireClient(player, `{name} ya está al máximo de tiempo ({PotionInfo.minutes(cap)}).\nNo se ha gastado.`, RED)
			return
		end
		seconds = math.min(active.seconds + base, cap)
		message = `{name}: +{PotionInfo.minutes(base)}`
	else
		Remotes.Notice:FireClient(player, `Ya tienes una poción mejor activa: {PotionInfo.name(family, active.tier)}.\nNo se ha gastado la {name}.`, RED)
		return
	end

	PlayerData.edit(player, function(edited)
		edited.items[key] -= 1
		edited.potions[family] = { tier = tier, seconds = seconds }
	end)
	publish(player, family, data.potions[family])
	ticking[player] = ticking[player] or os.clock()
	Remotes.Notice:FireClient(player, `{message}\n{PotionInfo.effect(family, tier)} · quedan {PotionInfo.clock(seconds)}`, color)
end

function Potions.start()
	Remotes.UsePotion.OnServerEvent:Connect(onUse)

	-- Al cargar sus datos: publica sus pociones activas (si las tiene) y empieza a contarles el tiempo.
	PlayerData.onLoad(function(player)
		local data = PlayerData.read(player)
		if not data then
			return
		end
		for family in cfg.Families do
			publish(player, family, data.potions[family])
		end
		if next(data.potions) then
			ticking[player] = os.clock()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ticking[player] = nil
		lastUse[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return Potions
