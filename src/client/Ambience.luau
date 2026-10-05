-- Pequeñas animaciones del decorado, solo en el cliente (no cuestan red ni servidor): las hojas
-- de las palmeras se mecen, las nubes van girando despacio alrededor de la isla, la espuma de
-- la orilla late, las espadas del expositor del hub giran y flotan, y unas gaviotas vuelan en
-- círculos. Scenery marca las piezas con etiquetas (Sway, Cloud, Foam, ShowcaseSword).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Performance = require(script.Parent.Performance)

local Ambience = {}

local SWAY_DISTANCE = 260 -- solo se mecen las palmeras cercanas a la cámara
local SWAY_ANGLE = math.rad(4)

-- Guarda la posición de partida de cada pieza etiquetada (con StreamingEnabled van llegando
-- y desapareciendo según se mueve el jugador).
local function track(tag: string, read: (Instance) -> any): { [Instance]: any }
	local items = {}
	local function add(item: Instance)
		items[item] = read(item)
	end
	for _, item in CollectionService:GetTagged(tag) do
		add(item)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(item)
		items[item] = nil
	end)
	return items
end

local function readPart(item: Instance)
	local partItem = item :: BasePart
	return { cframe = partItem.CFrame, pivot = partItem:GetAttribute("Pivot"), phase = partItem:GetAttribute("Phase") or 0, transparency = partItem.Transparency }
end

-- Gaviota: cuerpo y dos alas que aletean; vuela en círculos sobre la isla.
local function seagull(parent: Instance)
	local function piece(size: Vector3, color: Color3): Part
		local item = Instance.new("Part")
		item.Anchored = true
		item.CanCollide = false
		item.CanQuery = false
		item.CanTouch = false
		item.CastShadow = false
		item.Size = size
		item.Color = color
		item.Material = Enum.Material.SmoothPlastic
		item.Parent = parent
		return item
	end
	return {
		body = piece(Vector3.new(0.9, 0.7, 2.6), Color3.fromRGB(250, 250, 250)),
		left = piece(Vector3.new(3.2, 0.15, 1.1), Color3.fromRGB(215, 220, 230)),
		right = piece(Vector3.new(3.2, 0.15, 1.1), Color3.fromRGB(215, 220, 230)),
		radius = math.random(70, 260),
		height = math.random(45, 80),
		speed = (math.random() * 0.06 + 0.05) * (if math.random() < 0.5 then 1 else -1),
		offset = math.random() * math.pi * 2,
	}
end
-- Modo rendimiento (ver Performance): aquí se quita lo que es decorado puro. Hierba, flores, nubes y
-- bancos de niebla se sacan del mundo, desaparecen las gaviotas, las mariposas y todas las zonas de
-- partículas, se paran las animaciones del decorado y se apagan las sombras, los efectos de pantalla
-- y la atmósfera. Es reversible: las piezas quitadas se guardan con su padre y se devuelven.
local PERFORMANCE_TAGS = { "GrassDetail", "FlowerPiece", "Cloud", "FogBank" }
local removed: { [Instance]: Instance } = {} -- pieza quitada -> su padre
local ambienceFolder: Folder? = nil
local savedLighting: { [Instance]: { [string]: any } } = {}

local function remove(item: Instance)
	if item.Parent and removed[item] == nil then
		removed[item] = item.Parent
		item.Parent = nil
	end
end

function Ambience.isPerformance(): boolean
	return Performance.get()
end

function Ambience.setPerformance(on: boolean)
	Performance.set(on)
end

local function applyPerformance(on: boolean)
	if on then
		for _, tag in PERFORMANCE_TAGS do
			for _, item in CollectionService:GetTagged(tag) do
				remove(item)
			end
		end
	else
		for item, parent in removed do
			item.Parent = parent
		end
		table.clear(removed)
	end
	if ambienceFolder then
		ambienceFolder.Parent = if on then nil else workspace
	end

	Lighting.GlobalShadows = not on
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") then
			child.Enabled = not on
		elseif child:IsA("Atmosphere") then
			if on then
				savedLighting[child] = { Density = child.Density, Haze = child.Haze, Glare = child.Glare }
				child.Density, child.Haze, child.Glare = 0, 0, 0
			elseif savedLighting[child] then
				for property, value in savedLighting[child] do
					(child :: any)[property] = value
				end
			end
		end
	end
end

-- Piezas que llegan después (con StreamingEnabled) también se quitan.
for _, tag in PERFORMANCE_TAGS do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(item)
		if Performance.get() then
			remove(item)
		end
	end)
end
Performance.Changed:Connect(applyPerformance)

function Ambience.start()
	local leaves = track("Sway", readPart)
	local clouds = track("Cloud", readPart)
	local foam = track("Foam", readPart)
	local swords = track("ShowcaseSword", function(item)
		return { pivot = (item :: Model):GetPivot(), phase = math.random() * math.pi * 2 }
	end)

	-- Mar: cada baldosa cambia de tono despacio, como reflejos que se mueven.
	local sea = track("SeaTile", function(item)
		return { color = (item :: BasePart).Color, phase = item:GetAttribute("Phase") or 0 }
	end)
	local seaClock = 0

	local folder = Instance.new("Folder")
	folder.Name = "Ambience"
	folder.Parent = workspace
	local birds = {}
	for _ = 1, 6 do
		table.insert(birds, seagull(folder))
	end

	-- Polen y luciérnagas: una nube de motas que flota alrededor de la cámara (un solo emisor).
	local drift = Instance.new("Part")
	drift.Name = "Drift"
	drift.Anchored = true
	drift.CanCollide = false
	drift.CanQuery = false
	drift.CanTouch = false
	drift.Transparency = 1
	drift.Size = Vector3.new(90, 26, 90)
	drift.Parent = folder
	local motes = Instance.new("ParticleEmitter")
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	motes.Rate = 14
	motes.Lifetime = NumberRange.new(6, 10)
	motes.Speed = NumberRange.new(0.5, 1.6)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 0.25, 0)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 244, 170), Color3.fromRGB(190, 255, 190))
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.25), NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1) })
	motes.Parent = drift

	-- Zona de emisión que sigue a la cámara (invisible) con un emisor dentro.
	local function zone(name: string, size: Vector3): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Anchored = true
		item.CanCollide = false
		item.CanQuery = false
		item.CanTouch = false
		item.CastShadow = false
		item.Transparency = 1
		item.Size = size
		item.Parent = folder
		return item
	end

	-- Aire: polvillo blanco que el viento arrastra de lado, como motas a contraluz.
	local airZone = zone("Air", Vector3.new(110, 30, 110))
	local air = Instance.new("ParticleEmitter")
	air.Shape = Enum.ParticleEmitterShape.Box
	air.Rate = 26
	air.Lifetime = NumberRange.new(5, 9)
	air.Speed = NumberRange.new(0.3, 1)
	air.Acceleration = Vector3.new(5, 0.2, 2)
	air.SpreadAngle = Vector2.new(180, 180)
	air.LightEmission = 0.6
	air.LightInfluence = 0
	air.Color = ColorSequence.new(Color3.new(1, 1, 1))
	air.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.28), NumberSequenceKeypoint.new(1, 0) })
	air.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 1) })
	air.Parent = airZone

	-- Neblina baja: bancos de bruma suave pegados al suelo que se arrastran despacio.
	local mistZone = zone("Mist", Vector3.new(200, 3, 200))
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dp"
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.Rate = 2.5
	mist.Lifetime = NumberRange.new(14, 20)
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.Acceleration = Vector3.new(1.5, 0, 0.6)
	mist.SpreadAngle = Vector2.new(0, 180)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.LightEmission = 0.25
	mist.LightInfluence = 0.6
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-4, 4)
	mist.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255))
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 16), NumberSequenceKeypoint.new(1, 34) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.86), NumberSequenceKeypoint.new(0.75, 0.9), NumberSequenceKeypoint.new(1, 1) })
	mist.Parent = mistZone

	-- Pétalos y hojas que caen de arriba y se van con el viento.
	local fallZone = zone("Fall", Vector3.new(120, 2, 120))
	local petals = Instance.new("ParticleEmitter")
	petals.Shape = Enum.ParticleEmitterShape.Box
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.Rate = 3
	petals.Lifetime = NumberRange.new(9, 13)
	petals.Speed = NumberRange.new(0.5, 1.5)
	petals.Acceleration = Vector3.new(3, -0.6, 1)
	petals.SpreadAngle = Vector2.new(35, 35)
	petals.LightInfluence = 0.4
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-90, 90)
	petals.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 215)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 235, 140)),
	})
	petals.Size = NumberSequence.new(0.55)
	petals.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.9, 0.2), NumberSequenceKeypoint.new(1, 1) })
	petals.Parent = fallZone

	-- Destellos del sol sobre el agua y la hierba: chispas que aparecen y se apagan rápido.
	local glintZone = zone("Glints", Vector3.new(220, 1, 220))
	local glints = Instance.new("ParticleEmitter")
	glints.Shape = Enum.ParticleEmitterShape.Box
	glints.EmissionDirection = Enum.NormalId.Top
	glints.Rate = 18
	glints.Lifetime = NumberRange.new(1, 2)
	glints.Speed = NumberRange.new(0, 0.3)
	glints.LightEmission = 1
	glints.LightInfluence = 0
	glints.Color = ColorSequence.new(Color3.new(1, 1, 1))
	glints.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.3), NumberSequenceKeypoint.new(1, 0) })
	glints.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1) })
	glints.Parent = glintZone

	-- Mariposas: revolotean bajas por el césped cerca de la cámara, cada una de un color.
	local butterflies = {}
	local wingColors = { Color3.fromRGB(255, 150, 60), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 230, 90), Color3.fromRGB(190, 140, 255) }
	for index = 1, 28 do
		local function wing(): Part
			local item = zone("Wing", Vector3.new(0.6, 0.04, 0.5))
			item.Transparency = 0
			item.Color = wingColors[index % #wingColors + 1]
			item.Material = Enum.Material.SmoothPlastic
			return item
		end
		local leftWing, rightWing = wing(), wing()
		table.insert(butterflies, {
			left = leftWing,
			right = rightWing,
			-- Cada una tiene su rincón fijo de la isla (no sigue a la cámara).
			home = Vector3.new(math.cos(index * 2.4) * (60 + index * 9), 0, math.sin(index * 2.4) * (60 + index * 9)),
			radius = math.random(6, 14),
			speed = (math.random() * 0.4 + 0.3) * (if math.random() < 0.5 then 1 else -1),
			offset = math.random() * math.pi * 2,
			height = math.random() * 3 + 3,
		})
	end

	ambienceFolder = folder
	-- Si el modo rendimiento ya estaba activo (móvil), se aplica ahora que existe todo.
	if Performance.get() then
		applyPerformance(true)
	end

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local swayClock = 0

	RunService.RenderStepped:Connect(function(delta)
		-- Modo rendimiento: ninguna animación del decorado (hojas, nubes, gaviotas, mar, espadas del expositor).
		if Performance.get() then
			return
		end
		local now = os.clock()
		local camera = workspace.CurrentCamera.CFrame.Position
		table.clear(parts)
		table.clear(cframes)
		drift.Position = Vector3.new(camera.X, math.max(camera.Y - 4, 10), camera.Z)
		airZone.Position = Vector3.new(camera.X, math.max(camera.Y, 12), camera.Z)
		mistZone.Position = Vector3.new(camera.X, 3, camera.Z)
		fallZone.Position = Vector3.new(camera.X, camera.Y + 24, camera.Z)
		glintZone.Position = Vector3.new(camera.X, 0.6, camera.Z)

		-- Mariposas: cada una da vueltas lentas alrededor de su rincón.
		for _, fly in butterflies do
			local angle = now * fly.speed + fly.offset
			local position = fly.home + Vector3.new(math.cos(angle) * fly.radius, fly.height + math.sin(now * 2.3 + fly.offset) * 1.2, math.sin(angle * 1.3) * fly.radius)
			local ahead = Vector3.new(-math.sin(angle), 0, math.cos(angle * 1.3)) * math.sign(fly.speed)
			local body = CFrame.lookAt(position, position + ahead)
			local flap = math.rad(55) * math.abs(math.sin(now * 14 + fly.offset))
			table.insert(parts, fly.left)
			table.insert(cframes, body * CFrame.new(-0.5, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.3, 0, 0))
			table.insert(parts, fly.right)
			table.insert(cframes, body * CFrame.new(0.5, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.3, 0, 0))
		end

		-- Hojas: giran un poco alrededor de la copa, cada palmera a su ritmo (a 30 fps basta).
		swayClock += delta
		if swayClock >= 1 / 30 then
			swayClock = 0
			for leaf, base in leaves do
				local pivot = base.pivot
				if pivot and (pivot - camera).Magnitude < SWAY_DISTANCE then
					local angle = math.sin(now * 1.3 + base.phase) * SWAY_ANGLE
					local twist = math.sin(now * 0.7 + base.phase * 2) * SWAY_ANGLE * 0.5
					local around = CFrame.new(pivot) * CFrame.Angles(angle, 0, twist) * CFrame.new(-pivot)
					table.insert(parts, leaf :: BasePart)
					table.insert(cframes, around * base.cframe)
				end
			end
		end

		-- Nubes: dan una vuelta a la isla cada ~25 minutos.
		local turn = CFrame.Angles(0, now * 0.004, 0)
		for cloud, base in clouds do
			table.insert(parts, cloud :: BasePart)
			table.insert(cframes, turn * base.cframe)
		end

		-- Gaviotas.
		for _, bird in birds do
			local angle = now * bird.speed + bird.offset
			local position = Vector3.new(math.cos(angle) * bird.radius, bird.height + math.sin(now * 0.8 + bird.offset) * 3, math.sin(angle) * bird.radius)
			local ahead = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(bird.speed)
			local body = CFrame.lookAt(position, position + ahead) * CFrame.Angles(0, 0, math.rad(-12) * math.sign(bird.speed))
			local flap = math.sin(now * 7 + bird.offset) * math.rad(28)
			table.insert(parts, bird.body)
			table.insert(cframes, body)
			table.insert(parts, bird.left)
			table.insert(cframes, body * CFrame.new(-0.4, 0.1, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-1.5, 0, 0))
			table.insert(parts, bird.right)
			table.insert(cframes, body * CFrame.new(0.4, 0.1, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(1.5, 0, 0))
		end

		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end

		seaClock += delta
		if seaClock >= 1 / 15 then
			seaClock = 0
			for tile, base in sea do
				local glint = (math.sin(now * 0.9 + base.phase) + 1) / 2
				local water = tile :: BasePart
				water.Color = base.color:Lerp(Color3.fromRGB(150, 240, 245), glint * 0.4)
			end
		end

		-- Espuma de la orilla: aparece y se desvanece como olas.
		for piece, base in foam do
			local wave = piece :: BasePart
			wave.Transparency = 0.25 + (math.sin(now * 1.6 + base.phase) + 1) * 0.3
		end

		-- Espadas del expositor: giran despacio y suben y bajan.
		for model, base in swords do
			local position = base.pivot.Position + Vector3.new(0, math.sin(now * 1.2 + base.phase) * 0.8, 0)
			local spin = CFrame.Angles(0, now * 0.5 + base.phase, 0)
			local holder = model :: Model
			holder:PivotTo(CFrame.new(position) * spin * base.pivot.Rotation)
		end
	end)
end

return Ambience
