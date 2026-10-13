-- Cuentas de la Bolsa de oro (Config.GoldBag) para el servidor, el cliente y el simulador de equilibrio: cuántas
-- monedas saca un golpe según su daño, cuántas lleva cada bolsa y por cuál se va tras sacar unas cuantas. Los números
-- salen siempre de Config.
local Config = require(script.Parent.Config)

local BagInfo = {}

local MAX_STEPS = 5000 -- bolsas que como mucho se vacían de una vez

-- Monedas que saca de la bolsa un golpe de ese daño: Coins con Damage de daño y, cada vez que el daño se dobla,
-- Double veces más. Con los números de Config (1, 1 y 2, decididos por el usuario) es una moneda por punto de daño.
-- Al menos 1.
function BagInfo.coins(damage: number): number
	if not (damage > 0) then
		return 0
	end
	local cfg = Config.GoldBag
	return math.max(1, math.round(cfg.Coins * (damage / cfg.Damage) ^ (math.log(cfg.Double) / math.log(2))))
end

-- Monedas que lleva la bolsa nº `stage`: la primera, First; cada una, Growth veces la anterior, sin fin.
function BagInfo.size(stage: number): number
	return Config.GoldBag.First * Config.GoldBag.Growth ^ (math.max(stage, 1) - 1)
end

-- Por cuánto se multiplica lo que saca cada golpe yendo por la bolsa nº `stage`: StageBoost por cada bolsa vaciada.
function BagInfo.boost(stage: number): number
	return (Config.GoldBag.StageBoost or 1) ^ (math.max(stage, 1) - 1)
end

-- Sacar `coins` monedas yendo por la bolsa `stage`, de la que ya se habían sacado `taken`. Devuelve la bolsa y lo
-- sacado en las que queda, y las bolsas vaciadas por el camino.
function BagInfo.advance(stage: number, taken: number, coins: number): (number, number, number)
	local emptied = 0
	if not (coins > 0) then
		return stage, taken, emptied
	end
	for _ = 1, MAX_STEPS do
		local size = BagInfo.size(stage)
		local left = math.max(size - taken, 0)
		if coins < left or not (size < math.huge) then
			taken += coins -- (tan lejos que los números ya no caben, ahí se queda)
			break
		end
		coins -= left
		stage += 1
		taken = 0
		emptied += 1
	end
	return stage, taken, emptied
end

-- Golpes a la bolsa: su tamaño es VIDA (pedido por el usuario), no monedas. `damage` es lo que le quitan los golpes
-- (BagInfo.coins de su daño, sin multiplicadores) y cada punto quitado paga `mult` monedas por lo que sube la bolsa
-- por la que va (BagInfo.boost): los multiplicadores de monedas no la vacían antes. Devuelve la bolsa, la vida quitada
-- en ella, las bolsas vaciadas y las monedas que han salido.
function BagInfo.collect(stage: number, taken: number, damage: number, mult: number?): (number, number, number, number)
	local emptied, coins = 0, 0
	if not (damage > 0) then
		return stage, taken, emptied, coins
	end
	for _ = 1, MAX_STEPS do
		local size = BagInfo.size(stage)
		local pay = BagInfo.boost(stage) * (mult or 1)
		local left = math.max(size - taken, 0)
		if damage < left or not (size < math.huge) then
			taken += damage
			coins += damage * pay
			break
		end
		coins += left * pay
		damage -= left
		stage += 1
		taken = 0
		emptied += 1
	end
	return stage, taken, emptied, coins
end

-- Lo guardado en data.bag, revisado: { stage = bolsa por la que va, taken = monedas ya sacadas de esa bolsa, slots =
-- ids de las copias depositadas (los pone quien carga las espadas, que es quien sabe cuáles existen), seen = os.time()
-- de la última vez que las armas le pegaron (nil = nunca) }.
function BagInfo.sanitize(saved: unknown)
	local bag = { stage = 1, taken = 0, slots = {}, seen = nil :: number? }
	if type(saved) ~= "table" then
		return bag
	end
	local stage = tonumber(saved.stage)
	if stage and stage == stage and stage >= 1 and stage < math.huge then
		bag.stage = math.floor(stage)
	end
	local taken = tonumber(saved.taken)
	if taken and taken == taken and taken > 0 then
		bag.taken = math.min(taken, BagInfo.size(bag.stage))
	end
	local seen = tonumber(saved.seen)
	if seen and seen == seen and seen > 0 and seen < math.huge then
		bag.seen = seen
	end
	return bag
end

return BagInfo
