-- Efectos de sonido. Cada evento del juego tiene un nombre (`Sfx.play("coin")`) con su sonido, volumen y
-- variación de tono. El sonido puede ser un archivo de los que trae el cliente de Roblox
-- (rbxasset://sounds/..., que no necesitan red), el id de un audio subido (un número) o una lista de
-- cualquiera de los dos, de la que sale uno distinto cada vez. Todos van al SoundGroup "Sfx" de
-- SoundService, que mueve el deslizador de Ajustes (la música irá en "Music").
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local Sfx = {}

local DEFAULT_VOLUME = 0.7

-- nombre = { sonido, volumen, tono mínimo, tono máximo }
local EVENTS = {
	-- Interfaz. Una sola grabación cada uno: un botón tiene que sonar siempre igual.
	click = { 127498863959231, 0.45, 0.97, 1.05 },
	hover = { 112336389213652, 0.15, 0.97, 1.05 },
	tick = { 109272899066209, 0.35, 0.98, 1.04 },
	open = { 104050042655641, 0.3, 0.97, 1.03 },
	close = { 93262936570566, 0.25, 0.97, 1.03 },
	toast = { 116871010533956, 0.4, 1, 1 },
	error = { 81277813295867, 0.5, 1, 1 },
	buy = { 121614318104194, 0.55, 0.98, 1.03 },
	buyPing = { 100075584075241, 0.4, 1, 1.04 },
	equip = { 91947373481346, 0.45, 0.96, 1.05 },
	sell = { 89376802223171, 0.55, 0.98, 1.03 },
	teleport = { 114142918150751, 0.5, 0.98, 1.03 },
	potion = { 126924859318135, 0.5, 0.98, 1.03 },
	rebirth = { 101551001530213, 0.8, 1, 1 },
	coin = { 122751732815655, 0.35, 1.15, 1.25 }, -- la misma grabación que coin_break

	-- Tiradas: las de arma (client/RollReveal: orbe, carga y un sonido por nivel) y las de rasgo y grado.
	orb = { 125342078017629, 0.4, 0.96, 1.06 },
	charge = { 93541821621705, 0.4, 1, 1 },
	reveal_1 = { 96883121683271, 0.4, 0.95, 1.08 },
	reveal_2 = { 123562546673300, 0.5, 0.98, 1.04 },
	reveal_3 = { 126095692231161, 0.6, 1, 1 },
	reveal_4 = { 109717760520982, 0.7, 1, 1 },
	reveal_5 = { 118337535145235, 0.8, 1, 1 },
	collect = { 126460414904264, 0.45, 0.97, 1.06 },
	roll = { 108088062003601, 0.5, 0.98, 1.03 },
	rare = { 113476440126433, 0.7, 1, 1 },
	win = { 107352736766334, 0.7, 1, 1 },
	forge_hit = { { 97714408632464, 119769094792609, 107416494139217 }, 0.6, 0.95, 1.06 },
	forge_super = { 111948543913240, 0.8, 1, 1 },

	-- Mazmorras.
	wave = { 83996363538018, 0.6, 1, 1 },
	hurt = { { 70585973993176, 120343530004655, 76034653417857 }, 0.5, 0.94, 1.08 },
	dungeon_win = { 79069116956574, 0.75, 1, 1 },
	dungeon_lose = { 82008894062568, 0.7, 1, 1 },

	-- Espadazo: uno por tipo de arma (`swing_<tipo>` de Config.WeaponKinds; un tipo nuevo necesita el suyo).
	swing_sword = { { 107217231038027, 105099989032268, 101117762404360 }, 0.5, 0.94, 1.06 },
	swing_dual = { { 102562356995680, 114717881619968, 86006647086523 }, 0.4, 0.97, 1.1 },
	swing_spear = { { 132943226541296, 92141258501647, 106999256433193 }, 0.5, 0.94, 1.06 },
	swing_axe = { { 129944312741302, 87131757275622, 123403015919457 }, 0.55, 0.92, 1.04 },
	swing_hammer = { { 86718535774425, 137284315357198, 118707656482252 }, 0.6, 0.9, 1.02 },

	-- Golpe y rotura: uno por familia de material (`Sfx.family`); "enemy" son los enemigos de las mazmorras.
	hit_wood = { { 126585158630323, 100314427223809, 96991089919959 }, 0.55, 0.94, 1.08 },
	hit_stone = { { 88722266447384, 107031125232161, 88935750324382 }, 0.55, 0.94, 1.08 },
	hit_crystal = { { 131176466873530, 104737113738318, 85684119061570 }, 0.5, 0.94, 1.08 },
	hit_energy = { { 130877992406164, 121449108427921, 96184244997383 }, 0.5, 0.94, 1.08 },
	hit_enemy = { { 80414068000376, 111261644204441, 100530795623940 }, 0.55, 0.94, 1.08 },
	break_wood = { { 85544370717583, 98651879993610, 90077325436927 }, 0.75, 0.95, 1.05 },
	break_stone = { { 76632178232006, 78237163875148, 125829283125211 }, 0.8, 0.95, 1.05 },
	break_crystal = { { 119069323046508, 124381482851282, 84485501183800 }, 0.7, 0.95, 1.05 },
	break_energy = { { 79984574853273, 110014679976388, 111533369472047 }, 0.75, 0.95, 1.05 },
	break_enemy = { { 115006131003853, 84957959293785, 122984665353813 }, 0.75, 0.95, 1.05 },
	-- Monedas y gemas de un objeto roto. La moneda, una sola grabación y casi sin azar: la nota la pone la
	-- racha (client/Effects).
	coin_break = { 122751732815655, 0.4, 1, 1.02 },
	gem_break = { { 77515014943097, 98240894659000, 81665304125411 }, 0.45, 0.97, 1.05 },
}

-- A qué suena cada material de Config.Destructibles (lo que no sale aquí suena a piedra). Un objeto se lo
-- salta poniendo `sound = "<familia>"` en su entrada.
local FAMILIES = {
	[Enum.Material.Wood] = "wood",
	[Enum.Material.WoodPlanks] = "wood",
	[Enum.Material.Glass] = "crystal",
	[Enum.Material.Foil] = "crystal",
	[Enum.Material.Neon] = "energy",
	[Enum.Material.ForceField] = "energy",
}

local group: SoundGroup
local template: { [string]: { Sound } } = {}
local lastPlayed: { [string]: number } = {}
local lastVariant: { [string]: number } = {}

function Sfx.group(): SoundGroup
	return group
end

-- Familia de sonido ("wood", "stone", "crystal" o "energy") de un objeto de las parcelas, por su índice de
-- Config.Destructibles.
function Sfx.family(index: number?): string
	local def = index and Config.Destructibles[index]
	if not def then
		return "stone"
	end
	return def.sound or FAMILIES[def.material] or "stone"
end

-- Suena el evento. `quiet` (0 a 1) lo baja (por ejemplo para los golpes de otros jugadores) y `pitch`
-- multiplica el tono (más de 1, más agudo).
function Sfx.play(name: string, quiet: number?, pitch: number?)
	local info = EVENTS[name]
	local variants = template[name]
	if not info or not variants then
		return
	end
	-- Un mismo sonido no se repite en menos de 40 ms (con "Mejorar todo" o mucha rotura sonaría a ruido).
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < 0.04 then
		return
	end
	lastPlayed[name] = now
	-- Con varias grabaciones del mismo evento, nunca la misma dos veces seguidas.
	local index = math.random(#variants)
	if #variants > 1 and index == lastVariant[name] then
		index = index % #variants + 1
	end
	lastVariant[name] = index
	local sound = variants[index]:Clone()
	sound.Volume = info[2] * (quiet or 1)
	sound.PlaybackSpeed = (info[3] + (info[4] - info[3]) * math.random()) * (pitch or 1)
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Por si no llega a terminar (la cargaron mal).
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function Sfx.start()
	-- El grupo lo crea el primero que lo pida (Ajustes también lo necesita antes de que arranque Sfx).
	group = SoundService:FindFirstChild("Sfx") :: SoundGroup
	local list = {}
	for name, info in EVENTS do
		local variants = {}
		for _, source in if type(info[1]) == "table" then info[1] else { info[1] } do
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = if type(source) == "number" then string.format("rbxassetid://%d", source) else "rbxasset://sounds/" .. source
			sound.SoundGroup = group
			table.insert(variants, sound)
			table.insert(list, sound)
		end
		template[name] = variants
	end
	-- Se cargan de antemano para que el primer sonido de cada tipo no llegue tarde.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

-- Se crea ya al cargar el módulo para que Ui, Settings y compañía lo encuentren.
group = SoundService:FindFirstChild("Sfx") :: SoundGroup
if not group then
	group = Instance.new("SoundGroup")
	group.Name = "Sfx"
	group.Volume = DEFAULT_VOLUME
	group.Parent = SoundService
end

return Sfx
