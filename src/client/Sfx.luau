-- Efectos de sonido. No hay audio propio (el lugar no está publicado), así que se usan los sonidos
-- que trae el cliente de Roblox (rbxasset://sounds/...), que no necesitan red. Cada evento del juego
-- tiene un nombre (`Sfx.play("coin")`) con su sonido, volumen y variación de tono. Todos van al
-- SoundGroup "Sfx" de SoundService, que mueve el deslizador de Ajustes (la música irá en "Music").
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Sfx = {}

local DEFAULT_VOLUME = 0.7

-- nombre = { sonido, volumen, tono mínimo, tono máximo }
local EVENTS = {
	click = { "clickfast.wav", 0.45, 0.95, 1.1 },
	hit = { "snap.mp3", 0.5, 0.85, 1.15 },
	break_ = { "kerplunk.wav", 0.8, 0.65, 0.85 },
	coin = { "electronicpingshort.wav", 0.28, 1.5, 1.9 },
	gem = { "electronicpingshort.wav", 0.35, 2.1, 2.4 },
	buy = { "switch.wav", 0.7, 0.95, 1.05 },
	buyPing = { "electronicpingshort.wav", 0.4, 1.3, 1.3 },
	toast = { "electronicpingshort.wav", 0.35, 1.1, 1.2 },
	error = { "bass.wav", 0.55, 0.7, 0.7 },
	tick = { "clickfast.wav", 0.3, 1.5, 1.8 },
	roll = { "button.wav", 0.5, 1.0, 1.0 },
	rare = { "bass.wav", 0.8, 1.0, 1.0 },
	win = { "victory.wav", 0.8, 1.0, 1.0 },
	open = { "switch.wav", 0.4, 1.2, 1.2 },
}

local group: SoundGroup
local template: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

function Sfx.group(): SoundGroup
	return group
end

-- Suena el evento. `quiet` (0 a 1) lo baja (por ejemplo para los golpes de otros jugadores).
function Sfx.play(name: string, quiet: number?)
	local info = EVENTS[name]
	local base = template[name]
	if not info or not base then
		return
	end
	-- Un mismo sonido no se repite en menos de 40 ms (con "Mejorar todo" o mucha rotura sonaría a ruido).
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < 0.04 then
		return
	end
	lastPlayed[name] = now
	local sound = base:Clone()
	sound.Volume = info[2] * (quiet or 1)
	sound.PlaybackSpeed = info[3] + (info[4] - info[3]) * math.random()
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Por si no llega a terminar (la cargaron mal).
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function Sfx.start()
	-- El grupo lo crea el primero que lo pida (Ajustes también lo necesita antes de que arranque Sfx).
	group = SoundService:FindFirstChild("Sfx") :: SoundGroup
	for name, info in EVENTS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxasset://sounds/" .. info[1]
		sound.SoundGroup = group
		template[name] = sound
	end
	-- Se cargan de antemano para que el primer sonido de cada tipo no llegue tarde.
	task.spawn(function()
		local list = {}
		for _, sound in template do
			table.insert(list, sound)
		end
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
