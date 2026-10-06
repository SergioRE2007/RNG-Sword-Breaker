-- Ciclo de día y noche de la superficie. La luz que puso el servidor al arrancar (DungeonFx la guarda como "base" de
-- la isla) es la del día; de noche se mezcla con un azul oscuro y el reloj de Lighting avanza solo, sincronizado con la
-- hora del servidor para que todos vean lo mismo. Solo actúa en la superficie: DungeonFx lo apaga dentro del lobby y de
-- las mazmorras (que llevan su propia luz) y lo reactiva al volver. Librería con start().
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Performance = require(script.Parent.Performance)

local DayCycle = {}

local NIGHT = {
	ambient = Color3.fromRGB(34, 40, 78),
	outdoor = Color3.fromRGB(44, 52, 98),
	brightness = 0.35, -- fracción del brillo de día
	atmosphere = Color3.fromRGB(56, 66, 118),
	decay = Color3.fromRGB(34, 40, 84),
	tint = Color3.fromRGB(176, 192, 255),
	saturation = -0.1,
	fogDensity = 0.3, -- niebla de noche: densidad y bruma que se suman a las del día
	fogHaze = 1.8,
	sunBoost = 0.3, -- de día, más claro al mediodía (solo la luz del sol y el ambiente, no las luces del mapa)
}

local base: { [string]: any }? = nil
local active = false

-- Hora del reloj (0-24) según la hora del servidor.
local function clockNow(): number
	local cfg = Config.DayCycle
	return (cfg.Start + 24 * (workspace:GetServerTimeNow() % cfg.Length) / cfg.Length) % 24
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

-- La luz de ahora, con los mismos campos que Config.DungeonThemes[id].light (nil si aún no hay base).
function DayCycle.profile(): { [string]: any }?
	if not base then
		return nil
	end
	local clock = clockNow()
	local night = 1 - daylight(clock)
	local air = base.atmosphere
	return {
		clock = clock,
		ambient = base.ambient:Lerp(NIGHT.ambient, night),
		outdoor = base.outdoor:Lerp(NIGHT.outdoor, night),
		brightness = base.brightness * (1 - night * (1 - NIGHT.brightness)) * (1 + NIGHT.sunBoost * math.max(0, math.sin(math.pi * (clock - 6) / 12))),
		atmosphere = if air then { color = air.color:Lerp(NIGHT.atmosphere, night), decay = air.decay:Lerp(NIGHT.decay, night), density = air.density + NIGHT.fogDensity * night, haze = air.haze + NIGHT.fogHaze * night, glare = air.glare } else nil,
		tint = if base.tint then base.tint:Lerp(NIGHT.tint, night) else nil,
		saturation = if base.saturation then base.saturation + (NIGHT.saturation - base.saturation) * night else nil,
	}
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
