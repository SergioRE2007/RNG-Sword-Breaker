-- Ambiente por zona, solo en este cliente: al entrar en una mazmorra (atributo Dungeon > 0) o bajar al lobby
-- subterráneo cambia la luz (hora, ambiente, atmósfera, tinte) y suelta partículas alrededor de la cámara según el
-- tema de la zona (Config.DungeonThemes[id].light y .fx); al volver a la superficie devuelve lo que había.
-- Con el modo rendimiento (Performance) solo toca la luz básica: ni atmósfera, ni efectos de pantalla ni partículas.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Performance = require(script.Parent.Performance)
local DayCycle = require(script.Parent.DayCycle)

local DungeonFx = {}

local player = Players.LocalPlayer

local FADE = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Partículas por clase de efecto. rate = por segundo en toda la caja; speed/lifetime/size = {mín, máx}; lift = aceleración
-- vertical (positiva sube); glow = LightEmission; fade = cómo aparecen y se van.
local FX = {
	fireflies = { rate = 12, lifetime = { 5, 9 }, size = { 0.3, 0.5 }, speed = { 0.4, 1.4 }, lift = 0.15, glow = 1, spin = false },
	dust = { rate = 22, lifetime = { 6, 10 }, size = { 0.2, 0.4 }, speed = { 0.2, 0.8 }, lift = 0, glow = 0.1, spin = false },
	wisps = { rate = 7, lifetime = { 7, 11 }, size = { 1, 1.8 }, speed = { 0.3, 0.9 }, lift = 0.35, glow = 0.6, spin = true },
	ash = { rate = 30, lifetime = { 8, 12 }, size = { 0.2, 0.45 }, speed = { 0.6, 1.4 }, lift = -0.5, glow = 0, spin = true },
	bubbles = { rate = 18, lifetime = { 6, 10 }, size = { 0.35, 0.8 }, speed = { 0.4, 1 }, lift = 1.2, glow = 0.3, spin = false },
	embers = { rate = 24, lifetime = { 4, 8 }, size = { 0.2, 0.45 }, speed = { 1, 2.5 }, lift = 2, glow = 1, spin = true },
	motes = { rate = 14, lifetime = { 7, 12 }, size = { 0.25, 0.5 }, speed = { 0.2, 0.7 }, lift = 0.1, glow = 0.8, spin = false },
	sparkles = { rate = 16, lifetime = { 3, 6 }, size = { 0.35, 0.7 }, speed = { 0.3, 1 }, lift = 0.2, glow = 1, spin = true },
	stars = { rate = 20, lifetime = { 4, 8 }, size = { 0.25, 0.5 }, speed = { 0.2, 0.6 }, lift = 0, glow = 1, spin = false },
}

local surface: { [string]: any }? = nil -- la luz de la isla, tomada al empezar
local zone = "surface"
local emitterPart: Part? = nil
local emitter: ParticleEmitter? = nil

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function colorCorrection(): ColorCorrectionEffect?
	return Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
end

-- La luz de ahora mismo, con los mismos campos que Config.DungeonThemes[id].light.
local function snapshot(): { [string]: any }
	local air = atmosphere()
	local tint = colorCorrection()
	return {
		clock = Lighting.ClockTime,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		brightness = Lighting.Brightness,
		atmosphere = if air then { color = air.Color, decay = air.Decay, density = air.Density, haze = air.Haze, glare = air.Glare } else nil,
		tint = if tint then tint.TintColor else nil,
		saturation = if tint then tint.Saturation else nil,
	}
end

local function fade(item: Instance?, goal: { [string]: any })
	if item then
		TweenService:Create(item, FADE, goal):Play()
	end
end

local function applyLight(profile: { [string]: any })
	fade(Lighting, { ClockTime = profile.clock, Ambient = profile.ambient, OutdoorAmbient = profile.outdoor, Brightness = profile.brightness })
	-- La atmósfera y los efectos de pantalla los apaga el modo rendimiento (Ambience): no se tocan.
	if Performance.get() then
		return
	end
	local air = profile.atmosphere
	if air then
		fade(atmosphere(), { Color = air.color, Decay = air.decay, Density = air.density, Haze = air.haze, Glare = air.glare })
	end
	if profile.tint then
		fade(colorCorrection(), { TintColor = profile.tint, Saturation = profile.saturation })
	end
end

-- Partículas ------------------------------------------------------------------------------------------

local function stopFx()
	if emitterPart then
		emitterPart:Destroy()
	end
	emitterPart, emitter = nil, nil
end

local function startFx(fx: { kind: string, color: Color3 }?)
	stopFx()
	if not fx or Performance.get() then
		return
	end
	local preset = FX[fx.kind]
	if not preset then
		return
	end
	local box = Instance.new("Part")
	box.Name = "DungeonFx"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.new(110, 48, 110)

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(fx.color)
	particles.Rate = preset.rate
	particles.Lifetime = NumberRange.new(preset.lifetime[1], preset.lifetime[2])
	particles.Speed = NumberRange.new(preset.speed[1], preset.speed[2])
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, preset.size[2]), NumberSequenceKeypoint.new(0.8, preset.size[1]), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1) })
	particles.LightEmission = preset.glow
	particles.LightInfluence = 0
	particles.Acceleration = Vector3.new(0, preset.lift, 0)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Shape = Enum.ParticleEmitterShape.Box
	particles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	particles.LockedToPart = false
	particles.RotSpeed = if preset.spin then NumberRange.new(-60, 60) else NumberRange.new(0)
	particles.Parent = box
	box.Parent = workspace
	emitterPart, emitter = box, particles
end

-- Zonas --------------------------------------------------------------------------------------------------

-- Zona en la que está el jugador: "surface", "lobby" o "dungeon:<id>".
local function currentZone(): string
	local index = player:GetAttribute("Dungeon")
	if type(index) == "number" and index > 0 then
		local level = Config.Dungeons[index]
		if level then
			return "dungeon:" .. level.id
		end
	end
	local lobby = Config.DungeonLobby
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if lobby and root and root.Position.Y < lobby.ZoneY and root.Position.Magnitude < lobby.CavernRadius + 40 then
		return "lobby"
	end
	return "surface"
end

local function profileOf(name: string): ({ [string]: any }?, { kind: string, color: Color3 }?)
	if name == "lobby" then
		local lobby = Config.DungeonLobby
		return lobby.light, lobby.fx
	end
	local id = string.match(name, "^dungeon:(.+)$")
	if id then
		local theme = Config.DungeonThemes[id]
		if theme then
			return theme.light, theme.fx
		end
	end
	return surface, nil
end

-- Menos brillo en el lobby y las mazmorras (pedido por el usuario): la superficie no se toca.
local function dimLook(light: { [string]: any }, name: string): { [string]: any }
	if name == "surface" then
		return light
	end
	local look = table.clone(light)
	look.brightness = (light.brightness or 1) * (if name == "lobby" then 0.8 else 0.6)
	return look
end

local function enter(name: string)
	zone = name
	local light, fx = profileOf(name)
	-- En la superficie manda el ciclo de día y noche: se funde hacia la luz de ahora y, al acabar, él toma el relevo.
	DayCycle.setActive(false)
	if name == "surface" then
		light = DayCycle.profile() or light
	end
	if light then
		applyLight(dimLook(light, name))
	end
	startFx(fx)
	if name == "surface" then
		task.delay(FADE.Time + 0.1, function()
			if zone == "surface" then
				DayCycle.setActive(true)
			end
		end)
	end
end

function DungeonFx.start()
	-- La luz de la isla la pone el servidor al arrancar: se espera a tenerla para guardarla como "superficie".
	task.spawn(function()
		local waited = 0
		while not (atmosphere() and colorCorrection()) and waited < 15 do
			task.wait(0.25)
			waited += 0.25
		end
		surface = snapshot()
		DayCycle.setBase(surface)
		local name = currentZone()
		if name ~= "surface" then
			enter(name)
		else
			DayCycle.setActive(true)
		end
		while true do
			task.wait(0.25)
			local now = currentZone()
			if now ~= zone then
				enter(now)
			end
		end
	end)

	-- Las partículas siguen a la cámara (la caja es grande y no hace falta llenar toda la arena de emisores).
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if emitterPart and camera then
			emitterPart.Position = camera.CFrame.Position
		end
	end)

	Performance.Changed:Connect(function(on)
		if on then
			stopFx()
		elseif zone ~= "surface" then
			enter(zone)
		end
	end)
end

return DungeonFx
