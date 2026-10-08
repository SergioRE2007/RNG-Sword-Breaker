-- Clima en este cliente (Config.Weather). El servidor solo dice qué clima hay (atributos de workspace, ver
-- shared/WeatherInfo); aquí se hace todo lo que se ve: la luz se mezcla sobre la del ciclo de día y noche
-- (DayCycle.setWeather), las capas de partículas y sonido (WeatherFx, con los datos de WeatherDefs), el tinte de las
-- nubes y la tarjeta y el cartel del HUD (WeatherHud). Entra y sale poco a poco (Config.Weather.Fade).
-- La suerte que da vale en todas partes, pero el clima solo se ve en la superficie: en el lobby y en las mazmorras no
-- hay capas (DungeonFx ya pone allí su luz). Con el modo rendimiento queda la luz básica y el HUD, sin partículas.
-- El bucle de cada fotograma solo corre mientras hay un clima puesto o yéndose.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeatherInfo = require(ReplicatedStorage.Shared.WeatherInfo)
local DayCycle = require(script.Parent.DayCycle)
local DungeonFx = require(script.Parent.DungeonFx)
local ForgeScene = require(script.Parent.ForgeScene)
local JapanFx = require(script.Parent.JapanFx)
local Performance = require(script.Parent.Performance)
local WeatherDefs = require(script.Parent.WeatherDefs)
local WeatherFx = require(script.Parent.WeatherFx)
local WeatherHud = require(script.Parent.WeatherHud)

local Weather = {}

local player = Players.LocalPlayer
local cfg = Config.Weather

local SWITCH = 4 -- al pasar de un clima a otro sin despejar, el viejo se va este número de veces más rápido
local NEXT_KEY = Enum.KeyCode.K -- solo en Studio, con Config.Test.Admin: siguiente clima
local TINTED = { "Cloud", "FogBank" } -- lo que el clima tiñe del decorado (etiquetas de Scenery y SceneryJapan)
local EXTRAS = { bloom = "BloomEffect", sky = "Sky", rays = "SunRaysEffect", color = "ColorCorrectionEffect" }

-- Nubes y bancos de niebla: su color de siempre, para volver a él. Con claves débiles: las piezas vienen y van.
local tintBase: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local tintShown = 0
local tintStale = false

local function tint(def: { color: Color3, blend: number }?, amount: number)
	local strength = if def then def.blend * amount else 0
	-- Solo se repinta cuando cambia algo que se note (y siempre al volver a 0, para dejar el color exacto).
	local same = if strength > 0 then math.abs(strength - tintShown) < 0.004 else tintShown == 0
	if same and not tintStale then
		return
	end
	tintShown, tintStale = strength, false
	for _, tag in TINTED do
		for _, item in CollectionService:GetTagged(tag) do
			local part = item :: BasePart
			local base = tintBase[part]
			if not base then
				base = part.Color
				tintBase[part] = base
			end
			part.Color = if def then base:Lerp(def.color, strength) else base
		end
	end
end

-- Propiedades de Lighting que cambia un clima (WeatherDefs: `extras`): los números van de su valor de siempre al del
-- clima según el peso, y lo que no es un número (la textura del sol) cambia de golpe a media transición. Vuelven solas.
local extraBase: { [Instance]: { [string]: any } } = {}

local function setExtras(extras: { [string]: { [string]: any } }?, amount: number)
	for key, className in EXTRAS do
		local item = Lighting:FindFirstChildOfClass(className)
		local wanted = extras and extras[key]
		if item then
			local base = extraBase[item]
			if wanted and amount > 0 then
				if not base then
					base = {}
					extraBase[item] = base
				end
				for property, value in wanted do
					if base[property] == nil then
						base[property] = (item :: any)[property]
					end
					local from = base[property]
					if type(value) == "number" then
						(item :: any)[property] = from + (value - from) * amount
					else
						(item :: any)[property] = if amount >= 0.5 then value else from
					end
				end
			elseif base then
				for property, value in base do
					(item :: any)[property] = value
				end
				extraBase[item] = nil
			end
		end
	end
end

function Weather.start()
	WeatherHud.build()

	local shown: string? = nil -- el clima que se ve (sigue un momento después de acabar, mientras se va)
	local look: { [string]: any }? = nil -- su entrada de WeatherDefs
	local weight = 0
	local layers = nil -- mando de WeatherFx
	local loop: RBXScriptConnection? = nil

	-- Altura del suelo bajo el personaje (para lo que va a ras de suelo), mirada unas pocas veces por segundo.
	local ground = 0
	local groundClock = 0
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function view(dt: number)
		local camera = workspace.CurrentCamera
		local eye = camera.CFrame.Position
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- Las cajas de partículas van por delante de la cámara, mire a donde mire y esté a la distancia que esté del
		-- personaje (con el zoom lejos, centradas en él no llegaban a verse).
		local ahead = camera.CFrame.LookVector
		local center = eye + Vector3.new(ahead.X, 0, ahead.Z) * 40
		groundClock -= dt
		if groundClock <= 0 and rootPart then
			groundClock = 0.2
			rayParams.FilterDescendantsInstances = { character :: Instance }
			local hit = workspace:Raycast(rootPart.Position, Vector3.new(0, -80, 0), rayParams)
			if hit then
				ground = hit.Position.Y
			end
		end
		local started = workspace:GetAttribute("WeatherStart")
		return {
			eye = eye, center = center, ground = ground, now = os.clock(),
			clock = workspace:GetServerTimeNow(), started = if type(started) == "number" then started else 0,
			active = shown ~= nil and shown == (WeatherInfo.current()),
		}
	end

	local function dropLayers()
		if layers then
			layers.destroy()
			layers = nil
		end
	end

	local function step(dt: number)
		local want = (WeatherInfo.current())
		-- El que se ve ya no es el que hay: se va (deprisa si viene otro detrás) y, al acabar, entra el nuevo.
		if shown and shown ~= want then
			weight = math.max(0, weight - dt / cfg.Fade * (if want then SWITCH else 1))
			if weight <= 0 then
				dropLayers()
				shown, look = nil, nil
			end
		end
		if not shown and want then
			shown = want
			look = WeatherDefs.events[want] or WeatherDefs.fallback
			weight = 0
		end
		if shown and shown == want then
			weight = math.min(1, weight + dt / cfg.Fade)
		end
		local eased = weight * weight * (3 - 2 * weight)
		local outside = DungeonFx.zone() == "surface"
		local presence = if outside then eased else 0

		DayCycle.setWeather(look and look.light, eased, shown ~= nil and shown == want)
		tint(look and look.clouds, presence)
		setExtras(look and look.extras, if Performance.get() then 0 else presence)
		JapanFx.setCalm((if look then look.calm or 0 else 0) * eased)

		if look and outside and not Performance.get() then
			if not layers then
				layers = WeatherFx.build(look.layers or {})
			end
			layers.step(dt, eased, view(dt))
		else
			dropLayers()
		end

		-- Ya no queda nada que mover: se para hasta el siguiente clima.
		if not shown and not want and loop then
			loop:Disconnect()
			loop = nil
		end
	end

	local function wake()
		if not loop then
			loop = RunService.RenderStepped:Connect(step)
		end
	end
	workspace:GetAttributeChangedSignal("Weather"):Connect(wake)
	if WeatherInfo.current() then
		wake()
	end
	for _, tag in TINTED do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function()
			-- Una nube que llega con el clima puesto también se tiñe; y si vuelve teñida cuando ya no hay clima (el
			-- modo rendimiento las saca del mundo y las devuelve), el bucle arranca un momento para dejarla como era.
			tintStale = true
			wake()
		end)
	end

	-- HUD: tarjeta con el reloj (unas pocas veces por segundo basta) y cartel al empezar un clima.
	local hudId: string? = nil
	local first = true
	local elapsed = 1
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local id = (WeatherInfo.current())
		if id ~= hudId or first then
			hudId, first = id, false
			WeatherHud.show(id)
			if id then
				WeatherHud.announce(id)
			end
		end
		local now = workspace:GetServerTimeNow()
		local goal = workspace:GetAttribute(if id then "WeatherEnds" else "WeatherNext")
		WeatherHud.tick(if type(goal) == "number" then goal - now else 0, now)
		local dungeon = player:GetAttribute("Dungeon")
		WeatherHud.setHidden((type(dungeon) == "number" and dungeon > 0) or ForgeScene.isActive())
	end)

	if RunService:IsStudio() and Config.Test.Admin then
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == NEXT_KEY then
				Remotes.AdminWeather:FireServer("next")
			end
		end)
	end
end

return Weather
