-- Cuentas de la Bolsa de oro (Config.GoldBag) para el servidor, el cliente y el simulador de equilibrio: qué lleva
-- cada bolsa, a qué ritmo se vacía y cuánto da un rato de golpes. Los números salen siempre de Config.
local Config = require(script.Parent.Config)

local BagInfo = {}

local MAX_STEPS = 5000 -- bolsas que como mucho se vacían de una vez (una ausencia larguísima con armas muy por encima)

-- La bolsa nº `stage`: { coins = monedas que lleva, hp = daño que hay que hacerle para vaciarla, seconds = lo que le
-- dura al jugador tipo }. Las de la tabla generada y, pasada la última, la escalera sigue con Config.GoldBag.Growth.
function BagInfo.bag(stage: number)
	local bags = Config.GoldBag.Bags
	if stage <= #bags then
		return bags[math.max(stage, 1)]
	end
	local last, growth = bags[#bags], Config.GoldBag.Growth
	local over = stage - #bags
	return { coins = last.coins * growth.coins ^ over, hp = last.hp * growth.hp ^ over, seconds = last.seconds * growth.seconds ^ over }
end

-- Daño por segundo que de verdad le entra a esa bolsa: nadie la vacía en menos de seconds / MaxSpeed (el freno que
-- impide que unas armas muy por encima de su dueño se lleven la escalera entera en un momento).
function BagInfo.speed(stage: number, dps: number): number
	local bag = BagInfo.bag(stage)
	return math.min(dps, bag.hp * Config.GoldBag.MaxSpeed / bag.seconds)
end

-- Monedas por segundo que da esa bolsa con ese daño por segundo.
function BagInfo.rate(stage: number, dps: number): number
	local bag = BagInfo.bag(stage)
	return BagInfo.speed(stage, dps) / bag.hp * bag.coins
end

-- `seconds` segundos de golpes con `dps` de daño por segundo, desde la bolsa `stage` con `damage` de daño ya hecho.
-- Devuelve la bolsa y el daño en los que queda, las monedas que han salido y las bolsas vaciadas por el camino.
function BagInfo.advance(stage: number, damage: number, dps: number, seconds: number): (number, number, number, number)
	local coins, emptied = 0, 0
	if not (dps > 0) or not (seconds > 0) then
		return stage, damage, coins, emptied
	end
	for _ = 1, MAX_STEPS do
		local bag = BagInfo.bag(stage)
		if not (bag.hp < math.huge) or not (bag.coins < math.huge) then
			break -- tan lejos los números ya no caben: ahí se queda
		end
		local speed = BagInfo.speed(stage, dps)
		local need = math.max(bag.hp - damage, 0)
		local time = need / speed
		if time > seconds then
			local dealt = speed * seconds
			damage += dealt
			coins += dealt / bag.hp * bag.coins
			break
		end
		coins += need / bag.hp * bag.coins
		seconds -= time
		stage += 1
		damage = 0
		emptied += 1
	end
	return stage, damage, coins, emptied
end

-- Lo guardado en data.bag, revisado: { stage = bolsa por la que va, damage = daño hecho a esa bolsa, slots = ids de
-- las copias depositadas (los pone quien carga las espadas, que es quien sabe cuáles existen), seen = os.time() de la
-- última vez que las armas le pegaron (nil = nunca) }.
function BagInfo.sanitize(saved: unknown)
	local bag = { stage = 1, damage = 0, slots = {}, seen = nil :: number? }
	if type(saved) ~= "table" then
		return bag
	end
	local stage = tonumber(saved.stage)
	if stage and stage == stage and stage >= 1 and stage < math.huge then
		bag.stage = math.floor(stage)
	end
	local damage = tonumber(saved.damage)
	if damage and damage == damage and damage > 0 then
		bag.damage = math.min(damage, BagInfo.bag(bag.stage).hp)
	end
	local seen = tonumber(saved.seen)
	if seen and seen == seen and seen > 0 and seen < math.huge then
		bag.seen = seen
	end
	return bag
end

return BagInfo
