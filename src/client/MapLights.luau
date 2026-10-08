-- Solo las luces etiquetadas del mapa: las armas y mazmorras conservan sus propios efectos.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local DayCycle = require(script.Parent.DayCycle)
local Performance = require(script.Parent.Performance)

local MapLights = {}

function MapLights.start()
	local lights = {}
	local lamps = {}
	-- Apagar la luz no quita el brillo del material Neon: el papel también se apaga de día.
	local function updateLamp(part, state, night: number)
		local on = night > 0 and not Performance.get()
		part.Material = if on then state.material else Enum.Material.SmoothPlastic
		if state.paper then
			local wave = 0.5 + 0.5 * math.sin(os.clock() * 2.2 + part.Position.X * 0.37 + part.Position.Z * 0.21)
			part.Transparency = state.transparency + ((0.05 + 0.2 * wave) - state.transparency) * (if on then night else 0)
		end
	end
	for _, tag in { "LanternGlow", "StationGlow" } do
		local function addLamp(part)
			if not part:IsA("BasePart") then return end
			local state = { material = part.Material, transparency = part.Transparency, paper = tag == "LanternGlow" }
			lamps[part] = state
			updateLamp(part, state, DayCycle.night())
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(addLamp)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(part)
			local state = lamps[part]
			if state then
				part.Material = state.material
				part.Transparency = state.transparency
				lamps[part] = nil
			end
		end)
		for _, part in CollectionService:GetTagged(tag) do addLamp(part) end
	end
	local function update(light, base, night: number)
		local enabled = night > 0 and not Performance.get()
		local pulse = 1
		local parent = light.Parent
		if parent and parent:IsA("BasePart") and CollectionService:HasTag(parent, "LanternGlow") then
			local wave = 0.5 + 0.5 * math.sin(os.clock() * 2.2 + parent.Position.X * 0.37 + parent.Position.Z * 0.21)
			pulse = 0.7 + 0.5 * wave
		end
		light.Brightness = if enabled then base * night * pulse else 0
		light.Enabled = enabled
	end
	local function add(light)
		if not light:IsA("Light") then return end
		local base = light:GetAttribute("Base") or light.Brightness
		lights[light] = base
		update(light, base, DayCycle.night())
	end
	CollectionService:GetInstanceAddedSignal("NightLight"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("NightLight"):Connect(function(light)
		lights[light] = nil
	end)
	for _, light in CollectionService:GetTagged("NightLight") do add(light) end
	local function refresh()
		local night = DayCycle.night()
		for light, base in lights do update(light, base, night) end
		for part, state in lamps do updateLamp(part, state, night) end
	end
	Performance.Changed:Connect(refresh)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		refresh()
	end)
end

return MapLights
