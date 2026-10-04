-- Pequeñas animaciones del decorado, solo en el cliente (no cuestan red ni servidor): las hojas
-- de las palmeras se mecen, las nubes van girando despacio alrededor de la isla, la espuma de
-- la orilla late, las espadas del expositor del hub giran y flotan, y unas gaviotas vuelan en
-- círculos. Scenery marca las piezas con etiquetas (Sway, Cloud, Foam, ShowcaseSword).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

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

function Ambience.start()
	local leaves = track("Sway", readPart)
	local clouds = track("Cloud", readPart)
	local foam = track("Foam", readPart)
	local swords = track("ShowcaseSword", function(item)
		return { pivot = (item :: Model):GetPivot(), phase = math.random() * math.pi * 2 }
	end)

	local folder = Instance.new("Folder")
	folder.Name = "Ambience"
	folder.Parent = workspace
	local birds = {}
	for _ = 1, 6 do
		table.insert(birds, seagull(folder))
	end

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local swayClock = 0

	RunService.RenderStepped:Connect(function(delta)
		local now = os.clock()
		local camera = workspace.CurrentCamera.CFrame.Position
		table.clear(parts)
		table.clear(cframes)

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
