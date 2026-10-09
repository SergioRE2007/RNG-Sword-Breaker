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
	-- Interfaz. Pedido por el usuario: siempre iguales, una sola grabación y sin azar en el tono (mínimo = máximo).
	-- Pulsar un botón: la "burbuja 2" que eligió el usuario (salió de las opciones para pasar el ratón, que al
	-- final va sin sonido).
	click = { 139542095715371, 0.3, 1, 1 },
	tick = { 109272899066209, 0.35, 1, 1 },
	close = { 87073814038077, 0.2, 1, 1 }, -- la versión 2, elegida por el usuario
	toast = { 116871010533956, 0.3, 1, 1 },
	error = { 81277813295867, 0.35, 1, 1 },
	buy = { 121614318104194, 0.45, 1, 1 },
	buyPing = { 100075584075241, 0.3, 1, 1 },
	equip = { 91947373481346, 0.35, 1, 1 },
	sell = { 89376802223171, 0.45, 1, 1 },
	teleport = { 113376444315480, 0.5, 1, 1 }, -- el "destello 2" que eligió el usuario
	potion = { 126924859318135, 0.5, 1, 1 },
	rebirth = { 101551001530213, 0.8, 1, 1 },
	coin = { 122751732815655, 0.3, 1.2, 1.2 }, -- la misma grabación que coin_break

	-- Tiradas: las de arma (client/RollReveal: orbe, carga y un sonido por nivel) y las de rasgo y grado.
	-- También fijos: cada nivel tiene que reconocerse por su sonido.
	orb = { 125342078017629, 0.35, 1, 1 },
	charge = { 93541821621705, 0.35, 1, 1 },
	reveal_1 = { 96883121683271, 0.3, 1, 1 },
	reveal_2 = { 123562546673300, 0.45, 1, 1 },
	reveal_3 = { 126095692231161, 0.55, 1, 1 },
	reveal_4 = { 109717760520982, 0.7, 1, 1 },
	reveal_5 = { 118337535145235, 0.8, 1, 1 },
	collect = { 126460414904264, 0.4, 1, 1 },
	roll = { 108088062003601, 0.5, 1, 1 },
	rare = { 113476440126433, 0.65, 1, 1 },
	win = { 107352736766334, 0.7, 1, 1 },
	forge_hit = { { 97714408632464, 119769094792609, 107416494139217 }, 0.55, 0.95, 1.06 },
	forge_super = { 111948543913240, 0.8, 1, 1 },

	-- Detalles del mundo: el golpe épico contra el suelo (client/SwingAnim) y sacar o guardar el arma.
	slam = { { 113634930919938, 83038622346332, 116286832741715 }, 0.6, 0.92, 1.06 },
	unsheath = { 115027930187513, 0.35, 1, 1 },
	sheath = { 114581278401856, 0.35, 1, 1 },

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
	hit_wood = { { 126585158630323, 100314427223809, 96991089919959 }, 0.5, 0.94, 1.08 },
	-- Sin la segunda grabación (107031125232161): salió casi muda y subirla tanto solo saca ruido.
	hit_stone = { { 88722266447384, 88935750324382 }, 0.5, 0.94, 1.08 },
	hit_crystal = { { 131176466873530, 104737113738318, 85684119061570 }, 0.45, 0.94, 1.08 },
	hit_energy = { { 130877992406164, 121449108427921, 96184244997383 }, 0.45, 0.94, 1.08 },
	hit_enemy = { { 80414068000376, 111261644204441, 100530795623940 }, 0.5, 0.94, 1.08 },
	break_wood = { { 85544370717583, 98651879993610, 90077325436927 }, 0.75, 0.95, 1.05 },
	break_stone = { { 76632178232006, 78237163875148, 125829283125211 }, 0.8, 0.95, 1.05 },
	break_crystal = { { 119069323046508, 124381482851282, 84485501183800 }, 0.7, 0.95, 1.05 },
	break_energy = { { 79984574853273, 110014679976388, 111533369472047 }, 0.75, 0.95, 1.05 },
	break_enemy = { { 115006131003853, 84957959293785, 122984665353813 }, 0.75, 0.95, 1.05 },
	-- Monedas y gemas de un objeto roto. La moneda, una sola grabación y sin azar: la nota la pone la
	-- racha (client/Effects).
	coin_break = { 122751732815655, 0.3, 1, 1 },
	gem_break = { { 77515014943097, 98240894659000, 81665304125411 }, 0.35, 0.97, 1.05 },
}

-- Cuánto hay que subir cada grabación para que su pico llegue a 1 (lo calcula tools/sonidos/medir.mjs). Las
-- grabaciones salen de ElevenLabs a volúmenes muy distintos: de tres versiones de un mismo golpe, una se oía
-- diez veces más que otra. Con esto todas suenan igual de fuertes y el volumen de `EVENTS` es el de verdad.
-- Las que no están aquí ya venían bien.
local GAIN = {
	[119069323046508] = 1.20, -- break_crystal_1
	[124381482851282] = 1.36, -- break_crystal_2
	[84485501183800] = 1.61, -- break_crystal_3
	[84957959293785] = 1.23, -- break_enemy_2
	[122984665353813] = 3.76, -- break_enemy_3
	[85544370717583] = 0.89, -- break_wood_1
	[98651879993610] = 0.90, -- break_wood_2
	[90077325436927] = 0.88, -- break_wood_3
	[122751732815655] = 14.19, -- coin_break_1
	[77515014943097] = 3.71, -- gem_break_1
	[98240894659000] = 4.26, -- gem_break_2
	[81665304125411] = 5.14, -- gem_break_3
	[104737113738318] = 1.67, -- hit_crystal_2
	[100530795623940] = 0.80, -- hit_enemy_3
	[130877992406164] = 1.19, -- hit_energy_1
	[121449108427921] = 1.40, -- hit_energy_2
	[88722266447384] = 26.80, -- hit_stone_1
	[126585158630323] = 8.05, -- hit_wood_1
	[100314427223809] = 0.88, -- hit_wood_2
	[96991089919959] = 4.46, -- hit_wood_3
	[114717881619968] = 0.88, -- swing_dual_2
	[100075584075241] = 6.04, -- buyPing_1
	[121614318104194] = 1.27, -- buy_1
	[87073814038077] = 1.21, -- close_2
	[91947373481346] = 11.78, -- equip_1
	[81277813295867] = 4.22, -- error_1
	[89376802223171] = 1.37, -- sell_1
	[113376444315480] = 2.94, -- teleport_destello_2
	[116871010533956] = 2.47, -- toast_1
	[139542095715371] = 13.88, -- hover_burbuja_2 (click)
	[93541821621705] = 1.14, -- charge_1
	[97714408632464] = 10.21, -- forge_hit_1
	[119769094792609] = 7.83, -- forge_hit_2
	[107416494139217] = 3.28, -- forge_hit_3
	[111948543913240] = 1.23, -- forge_super_1
	[125342078017629] = 1.28, -- orb_1
	[113476440126433] = 1.28, -- rare_1
	[96883121683271] = 12.66, -- reveal_1_1
	[123562546673300] = 2.62, -- reveal_2_1
	[126095692231161] = 2.66, -- reveal_3_1
}
local MAX_VOLUME = 10 -- el tope de Sound.Volume
-- Sonidos del mundo (los que se lanzan con `at`): a pleno volumen hasta ROLLOFF_MIN studs de la cámara y de ahí
-- bajando hasta callar del todo en ROLLOFF_MAX.
local ROLLOFF_MIN = 40
local ROLLOFF_MAX = 200
local SWING_QUIET = 0.35 -- con menos segundos que estos entre golpes, el espadazo va bajando de volumen

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
-- multiplica el tono (más de 1, más agudo). Con `at` (un punto del mundo o una pieza) el sonido sale de ahí:
-- se oye por su lado y más flojo cuanto más lejos de la cámara. Sin él suena igual por los dos oídos, que es
-- lo suyo para la interfaz, los avisos y los premios.
function Sfx.play(name: string, quiet: number?, pitch: number?, at: (Vector3 | Instance)?)
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
	sound.Volume = math.min(sound.Volume * (quiet or 1), MAX_VOLUME) -- la plantilla ya lleva el volumen del evento
	sound.PlaybackSpeed = (info[3] + (info[4] - info[3]) * math.random()) * (pitch or 1)
	-- Lo que se borra al acabar: el sonido o, si sale de un punto del mundo, el enganche que se le pone ahí.
	local holder: Instance = sound
	if typeof(at) == "Vector3" then
		local anchor = Instance.new("Attachment")
		anchor.Name = "Sfx"
		anchor.Position = at
		anchor.Parent = workspace.Terrain
		sound.Parent = anchor
		holder = anchor
	else
		sound.Parent = if typeof(at) == "Instance" then at else SoundService
	end
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	-- Por si no llega a terminar (la cargaron mal).
	task.delay(8, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

-- Cuánto se baja lo que suena en cada espadazo según lo rápido que se golpea (con la velocidad al máximo salen
-- varios por segundo).
function Sfx.cadence(cooldown: number): number
	return math.clamp((cooldown / SWING_QUIET) ^ 0.5, 0.4, 1)
end

-- El silbido de un espadazo, que sale del personaje que lo da.
function Sfx.swing(kind: string, cooldown: number, character: Model?, quiet: number?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	Sfx.play("swing_" .. kind, Sfx.cadence(cooldown) * (quiet or 1), nil, root)
end

function Sfx.start()
	-- El grupo lo crea el primero que lo pida (Ajustes también lo necesita antes de que arranque Sfx).
	group = SoundService:FindFirstChild("Sfx") :: SoundGroup
	-- Las plantillas se quedan colgadas de SoundService: solo así Roblox mantiene el audio cargado y cada sonido
	-- arranca al momento. Sueltas, la primera copia de cada uno tardaba de 0,3 a 0,5 s en oírse (medido), y en
	-- un botón eso se nota mucho.
	local bank = Instance.new("Folder")
	bank.Name = "SfxBank"
	bank.Parent = SoundService
	local list = {}
	for name, info in EVENTS do
		local variants = {}
		for _, source in if type(info[1]) == "table" then info[1] else { info[1] } do
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = if type(source) == "number" then string.format("rbxassetid://%d", source) else "rbxasset://sounds/" .. source
			sound.Volume = math.min(info[2] * (GAIN[source] or 1), MAX_VOLUME)
			sound.RollOffMode = Enum.RollOffMode.Linear
			sound.RollOffMinDistance = ROLLOFF_MIN
			sound.RollOffMaxDistance = ROLLOFF_MAX
			sound.SoundGroup = group
			sound.Parent = bank
			table.insert(variants, sound)
			table.insert(list, sound)
		end
		template[name] = variants
	end
	-- Y se piden cuanto antes, para que estén ya al entrar.
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
