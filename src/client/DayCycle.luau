-- Ciclo de día y noche de la superficie. La luz sale de unas horas clave (KEYS: noche, alba, mañana, mediodía, tarde,
-- atardecer, anochecer) mezcladas entre la anterior y la siguiente; el reloj de Lighting avanza solo, sincronizado con
-- la hora del servidor para que todos vean lo mismo, y va más lento de día (Config.DayCycle.DayShare). El sol y la luna
-- son los del Sky de SceneryJapan. Solo actúa en la superficie: DungeonFx lo apaga dentro del lobby y de las mazmorras
-- (que llevan su propia luz) y lo reactiva al volver. Librería con start().
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Performance = require(script.Parent.Performance)

local DayCycle = {}

local rgb = Color3.fromRGB

-- Horas clave, en orden; la última repite la primera para cerrar el día. `sun` es el color de la luz del sol (o de la
-- luna de noche, Lighting.ColorShift_Top). Poca bruma (`haze`) de día y de noche deja ver el sol, la luna y las estrellas.
local NIGHT = {
	ambient = rgb(52, 62, 98), outdoor = rgb(66, 80, 130), brightness = 1.2, sun = rgb(150, 170, 230),
	air = rgb(24, 36, 72), decay = rgb(14, 20, 46), density = 0.3, haze = 0.3, tint = rgb(210, 222, 255), saturation = -0.05,
}
local KEYS = {
	{ hour = 0, look = NIGHT },
	{ hour = 5, look = { -- antes del alba
		ambient = rgb(70, 70, 110), outdoor = rgb(90, 90, 140), brightness = 1.2, sun = rgb(170, 160, 220),
		air = rgb(60, 62, 110), decay = rgb(90, 70, 120), density = 0.32, haze = 0.8, tint = rgb(225, 225, 255), saturation = 0,
	} },
	{ hour = 6.5, look = { -- amanecer
		ambient = rgb(130, 100, 120), outdoor = rgb(190, 140, 150), brightness = 1.8, sun = rgb(255, 170, 120),
		air = rgb(255, 190, 170), decay = rgb(255, 140, 120), density = 0.34, haze = 1.6, tint = rgb(255, 236, 232), saturation = 0.15,
	} },
	{ hour = 9, look = { -- mañana
		ambient = rgb(130, 130, 140), outdoor = rgb(170, 175, 190), brightness = 2.4, sun = rgb(255, 232, 200),
		air = rgb(199, 215, 240), decay = rgb(150, 180, 220), density = 0.3, haze = 0.6, tint = rgb(250, 248, 250), saturation = 0.18,
	} },
	{ hour = 12, look = { -- mediodía
		ambient = rgb(138, 138, 145), outdoor = rgb(180, 185, 195), brightness = 2.8, sun = rgb(255, 248, 235),
		air = rgb(190, 215, 245), decay = rgb(120, 165, 225), density = 0.28, haze = 0.3, tint = rgb(255, 255, 255), saturation = 0.2,
	} },
	{ hour = 16, look = { -- tarde
		ambient = rgb(136, 128, 130), outdoor = rgb(185, 175, 175), brightness = 2.5, sun = rgb(255, 225, 185),
		air = rgb(220, 215, 230), decay = rgb(200, 175, 190), density = 0.3, haze = 0.8, tint = rgb(255, 246, 240), saturation = 0.2,
	} },
	{ hour = 18, look = { -- atardecer dorado (la luz de siempre de la isla)
		ambient = rgb(128, 100, 136), outdoor = rgb(178, 136, 160), brightness = 2.1, sun = rgb(255, 176, 130),
		air = rgb(255, 196, 218), decay = rgb(255, 150, 140), density = 0.36, haze = 1.9, tint = rgb(255, 236, 238), saturation = 0.22,
	} },
	{ hour = 19.5, look = { -- anochecer
		ambient = rgb(80, 64, 110), outdoor = rgb(110, 86, 145), brightness = 1.4, sun = rgb(190, 150, 220),
		air = rgb(90, 60, 120), decay = rgb(120, 70, 120), density = 0.34, haze = 1, tint = rgb(225, 215, 255), saturation = 0.05,
	} },
	{ hour = 24, look = NIGHT },
}

local base: { [string]: any }? = nil
local active = false

-- Hora del reloj (0-24) según la hora del servidor: la parte de día (6 a 18) dura DayShare de la vuelta y la noche el resto.
local function clockNow(): number
	local cfg = Config.DayCycle
	local f = (workspace:GetServerTimeNow() / cfg.Length) % 1
	if f < cfg.DayShare then
		return 6 + 12 * f / cfg.DayShare
	end
	return (18 + 12 * (f - cfg.DayShare) / (1 - cfg.DayShare)) % 24
end

-- Mezcla de las dos horas clave que rodean a `clock`.
local function lookAt(clock: number)
	for i = 2, #KEYS do
		local b = KEYS[i]
		if clock <= b.hour then
			local a = KEYS[i - 1]
			local t = (clock - a.hour) / (b.hour - a.hour)
			local mixed = {}
			for key, value in a.look do
				mixed[key] = if typeof(value) == "Color3" then value:Lerp(b.look[key], t) else value + (b.look[key] - value) * t
			end
			return mixed
		end
	end
	return NIGHT
end

-- 1 = pleno día, 0 = noche cerrada; amanece y atardece sin saltos.
local function daylight(clock: number): number
	local sun = math.sin(math.pi * (clock - 6) / 12)
	return math.clamp((sun + 0.2) / 0.5, 0, 1)
end

-- 0 de día, 1 de noche cerrada: lo usan las luces del mapa (farolillos, linternas) para encenderse al anochecer.
function DayCycle.night(): number
	return 1 - daylight(clockNow())
end

-- La luz de una hora, con los mismos campos que Config.DungeonThemes[id].light más `sun` (nil si aún no hay base).
function DayCycle.profileAt(clock: number): { [string]: any }?
	if not base then
		return nil
	end
	local look = lookAt(clock)
	local air = base.atmosphere
	return {
		clock = clock,
		ambient = look.ambient,
		outdoor = look.outdoor,
		brightness = look.brightness,
		sun = look.sun,
		atmosphere = if air then { color = look.air, decay = look.decay, density = look.density, haze = look.haze, glare = air.glare } else nil,
		tint = if base.tint then look.tint else nil,
		saturation = if base.tint then look.saturation else nil,
	}
end

-- La luz de ahora.
function DayCycle.profile(): { [string]: any }?
	return DayCycle.profileAt(clockNow())
end

function DayCycle.setBase(snapshot: { [string]: any })
	base = snapshot
end

function DayCycle.setActive(on: boolean)
	active = on
end

function DayCycle.start()
	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local profile = DayCycle.profile()
		if not profile then
			return
		end
		Lighting.ClockTime = profile.clock
		Lighting.Ambient = profile.ambient
		Lighting.OutdoorAmbient = profile.outdoor
		Lighting.Brightness = profile.brightness
		Lighting.ColorShift_Top = profile.sun
		-- La atmósfera y los efectos de pantalla los apaga el modo rendimiento (Ambience): no se tocan.
		if Performance.get() then
			return
		end
		local air = Lighting:FindFirstChildOfClass("Atmosphere")
		if air and profile.atmosphere then
			air.Color = profile.atmosphere.color
			air.Decay = profile.atmosphere.decay
			air.Density = profile.atmosphere.density
			air.Haze = profile.atmosphere.haze
		end
		local tint = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if tint and profile.tint then
			tint.TintColor = profile.tint
			tint.Saturation = profile.saturation
		end
	end)
end

return DayCycle
