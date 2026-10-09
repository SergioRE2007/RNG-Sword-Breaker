-- Sonido de fondo del mundo: el ambiente del sitio donde está el jugador (la superficie de día y de noche, el
-- lobby de las mazmorras y las mazmorras) y el de las estaciones del hub, que solo se oye de cerca. Son bucles
-- hechos con tools/sonidos. El ambiente de cada clima lo pone client/WeatherFx; mientras suena, este baja.
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local DayCycle = require(script.Parent.DayCycle)
local DungeonFx = require(script.Parent.DungeonFx)
local Sfx = require(script.Parent.Sfx)

local Soundscape = {}

local FADE = 3 -- segundos que tarda un ambiente en entrar o en irse
local STEP = 0.1 -- cada cuánto se revisa
local DUCK = 0.35 -- lo que queda del ambiente de la superficie mientras hay un clima, que trae el suyo

-- nombre = { id, volumen }. El volumen ya compensa lo fuerte o flojo que salió grabado cada bucle (el de día,
-- diez veces más flojo que los demás).
local AMBIENTS = {
	day = { 124805672014218, 2.3 },
	-- La noche está compuesta con tools/sonidos/componer.mjs (grillos, agua, bambú y búho sueltos sobre una brisa
	-- hecha por código): el ambiente pedido de una vez le sonaba saturado al usuario. Muy bajo, pedido por él.
	night = { 137642913626647, 0.3 },
	lobby = { 103233526142547, 0.4 },
	dungeon = { 116580300543207, 0.31 },
}

-- Estaciones del hub, por el atributo `Shop` de su pieza con la etiqueta ShopStation:
-- { id, volumen, studs a pleno volumen, studs a los que deja de oírse, trozo del audio que se repite (opcional) }.
local STATIONS = {
	traits = { 87871666926837, 0.9, 10, 55 }, -- Mesa de encantamiento
	grades = { 108562201462062, 0.42, 10, 55, NumberRange.new(0.2, 9.6) }, -- Forja; sin el silencio del principio
}

local function asset(id: number): string
	return string.format("rbxassetid://%d", id)
end

-- Cuánto tiene que sonar cada ambiente ahora mismo (de 0 a 1).
local function targets(): { [string]: number }
	local zone = DungeonFx.zone()
	if zone == "lobby" then
		return { lobby = 1 }
	elseif zone ~= "surface" then
		return { dungeon = 1 }
	end
	local night = math.clamp(DayCycle.night(), 0, 1)
	local level = if (workspace:GetAttribute("Weather") or "") ~= "" then DUCK else 1
	return { day = (1 - night) * level, night = night * level }
end

local function station(part: Instance)
	local info = STATIONS[part:GetAttribute("Shop")]
	if not info or not part:IsA("BasePart") or part:FindFirstChild("StationLoop") then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "StationLoop"
	sound.SoundId = asset(info[1])
	sound.Volume = info[2]
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = info[3]
	sound.RollOffMaxDistance = info[4]
	if info[5] then
		sound.PlaybackRegionsEnabled = true
		sound.LoopRegion = info[5]
	end
	sound.SoundGroup = Sfx.ambience()
	sound.Parent = part
	sound:Play()
end

function Soundscape.start()
	local sounds: { [string]: Sound } = {}
	local weights: { [string]: number } = {}
	for name, info in AMBIENTS do
		local sound = Instance.new("Sound")
		sound.Name = "Ambient_" .. name
		sound.SoundId = asset(info[1])
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = Sfx.ambience()
		sound.Parent = SoundService
		sounds[name] = sound
		weights[name] = 0
	end

	-- Un solo bucle: acerca cada ambiente a lo que le toca y solo deja corriendo los que se oyen.
	task.spawn(function()
		while true do
			local want = targets()
			for name, sound in sounds do
				local goal = want[name] or 0
				local weight = weights[name]
				if weight ~= goal then
					weight = if goal > weight then math.min(goal, weight + STEP / FADE) else math.max(goal, weight - STEP / FADE)
					weights[name] = weight
					sound.Volume = AMBIENTS[name][2] * weight
				end
				if weight > 0 and not sound.IsPlaying then
					sound:Play()
				elseif weight <= 0 and sound.IsPlaying then
					sound:Stop()
				end
			end
			task.wait(STEP)
		end
	end)

	for _, part in CollectionService:GetTagged("ShopStation") do
		station(part)
	end
	CollectionService:GetInstanceAddedSignal("ShopStation"):Connect(station)
end

return Soundscape
