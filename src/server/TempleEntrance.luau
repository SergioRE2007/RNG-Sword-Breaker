-- Entrada de las mazmorras como un templo japonés místico (Config.Theme = "japan"): un pabellón octogonal de dos
-- tejados sobre la boca del pozo, ocho columnas laqueadas en rojo, cuerda sagrada con papeles, farolillos violeta,
-- toriis alrededor y mucha magia: círculos de runas que giran flotando, un rayo de luz violeta que sube al cielo,
-- fuegos fatuos que orbitan y niebla mágica que sale del pozo. Se construye después de DungeonLobby, que es quien
-- abre el pozo y pone el borde de piedra y el cartel. El cliente (JapanFx) mueve los círculos, los fuegos fatuos y el
-- rayo con las etiquetas MagicCircle, Wisp, SpiritBeam y MagicMist. Todo es decoración: no afecta al juego.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)

local TempleEntrance = {}

local VIOLET = Color3.fromRGB(176, 124, 255)
local CYAN = Color3.fromRGB(110, 232, 255)
local PINK = Color3.fromRGB(255, 140, 222)
local GOLD = Color3.fromRGB(255, 208, 64)
local LACQUER = Color3.fromRGB(226, 48, 62)
local PILLARS = 8
local PILLAR_RADIUS = 18
local PILLAR_HEIGHT = 15

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function decor(item: BasePart): BasePart
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
	return item
end

local function glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	return decor(part(parent, name, size, cframe, color, Enum.Material.Neon))
end

local function polar(angle: number, radius: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

-- Columna laqueada: base de piedra, fuste rojo, bandas doradas arriba y abajo y capitel negro.
local function pillar(parent: Instance, position: Vector3)
	local base = CFrame.new(position)
	local stone = part(parent, "PillarBase", Vector3.new(4.2, 0.9, 4.2), base * CFrame.new(0, 0.45, 0), Color3.fromRGB(170, 166, 190), Enum.Material.Slate)
	stone.Shape = Enum.PartType.Cylinder
	stone.CFrame = base * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90))
	stone.Size = Vector3.new(0.9, 4.2, 4.2)
	local shaft = part(parent, "Pillar", Vector3.new(PILLAR_HEIGHT - 1.4, 2.3, 2.3), base * CFrame.new(0, 0.9 + (PILLAR_HEIGHT - 1.4) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), LACQUER, Enum.Material.SmoothPlastic)
	shaft.Shape = Enum.PartType.Cylinder
	for _, y in { 1.8, PILLAR_HEIGHT - 2.2 } do
		local band = part(parent, "PillarBand", Vector3.new(0.5, 2.7, 2.7), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
		band.Shape = Enum.PartType.Cylinder
	end
	part(parent, "PillarCap", Vector3.new(3.4, 0.8, 3.4), base * CFrame.new(0, PILLAR_HEIGHT - 0.4, 0), Color3.fromRGB(44, 36, 54), Enum.Material.SmoothPlastic)
end

-- Cuerda sagrada entre dos columnas: tramos blancos que cuelgan en curva, con papeles en zigzag.
local function rope(parent: Instance, from: Vector3, to: Vector3)
	local steps = 8
	local previous = from
	for step = 1, steps do
		local t = step / steps
		local sag = math.sin(t * math.pi) * 1.8
		local point = from:Lerp(to, t) - Vector3.new(0, sag, 0)
		local middle = (previous + point) / 2
		local length = (point - previous).Magnitude
		decor(part(parent, "Rope", Vector3.new(0.5, 0.5, length + 0.15), CFrame.lookAt(middle, point), Color3.fromRGB(255, 250, 240), Enum.Material.Fabric))
		if step % 2 == 0 and step < steps then
			for tag = -1, 1 do
				local shide = decor(part(parent, "Shide", Vector3.new(0.9, 1.5, 0.08), CFrame.lookAt(point + Vector3.new(tag * 0.5, -1.0 - (tag % 2) * 0.3, 0), point + Vector3.new(tag * 0.5, -1.0, 1)) * CFrame.Angles(0, 0, math.rad(tag * 14)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic))
				shide.Transparency = 0.05
			end
		end
		previous = point
	end
end

-- Círculo mágico que gira: anillo de runas, runas sueltas y una estrella de seis puntas hecha con dos triángulos.
local function magicCircle(parent: Instance, name: string, y: number, radius: number, speed: number, colorA: Color3, colorB: Color3, runes: number)
	local model = Instance.new("Model")
	model.Name = name
	local segments = 56
	for index = 1, segments do
		local angle = index / segments * math.pi * 2
		glow(model, "Ring", Vector3.new(0.35, 0.15, 2 * math.pi * radius / segments + 0.15), CFrame.new(polar(angle, radius, y)) * CFrame.Angles(0, -angle, 0), colorA)
	end
	for index = 1, runes do
		local angle = index / runes * math.pi * 2
		local color = if index % 2 == 0 then colorA else colorB
		local at = CFrame.new(polar(angle, radius + 1.5, y)) * CFrame.Angles(0, -angle, 0)
		glow(model, "Rune", Vector3.new(1.1, 0.14, 0.45), at, color)
		glow(model, "Rune", Vector3.new(0.45, 0.14, 1.1), at, color)
	end
	local inner = radius * 0.8
	for triangle = 0, 1 do
		for edge = 0, 2 do
			local angle = triangle * math.pi / 3 + edge * math.pi * 2 / 3 + math.pi / 6
			local side = inner * math.sqrt(3)
			glow(model, "Star", Vector3.new(0.3, 0.14, side), CFrame.new(polar(angle, inner / 2, y)) * CFrame.Angles(0, -angle, 0), colorB)
		end
	end
	glow(model, "Core", Vector3.new(1.4, 0.2, 1.4), CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45), 0), colorA).Shape = Enum.PartType.Block
	model.WorldPivot = CFrame.new(0, y, 0)
	model:SetAttribute("Speed", speed)
	model.Parent = parent
	CollectionService:AddTag(model, "MagicCircle")
end

function TempleEntrance.start()
	if Config.Theme ~= "japan" then
		return
	end
	local top = Config.Plot.FloorHeight

	-- Fuera lo que puso DungeonLobby sobre el borde (ocho pilares de piedra con farol): el templo ocupa su lugar. El
	-- cartel sube al interior del pabellón.
	local lobby = workspace:FindFirstChild("Lobby")
	local entrance = lobby and lobby:FindFirstChild("EntradaMazmorras")
	if entrance then
		for _, item in entrance:GetChildren() do
			if item.Name == "Pillar" or item.Name == "Cap" or item.Name == "Torch" then
				item:Destroy()
			end
		end
		local sign = entrance:FindFirstChild("Sign")
		if sign and sign:IsA("BasePart") then
			sign.CFrame = CFrame.new(0, top + 12.3, 0)
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "TemploMazmorras"
	folder.Parent = workspace

	-- Columnas en los vértices del octógono, vigas negras entre ellas, cuerda sagrada y farolillos violeta.
	for index = 1, PILLARS do
		local angle = (index - 1) / PILLARS * math.pi * 2
		local nextAngle = index / PILLARS * math.pi * 2
		local here = polar(angle, PILLAR_RADIUS, top)
		local next = polar(nextAngle, PILLAR_RADIUS, top)
		pillar(folder, here)
		local beamMiddle = (here + next) / 2 + Vector3.new(0, PILLAR_HEIGHT - 2.6, 0)
		part(folder, "Beam", Vector3.new(1.0, 1.2, (next - here).Magnitude), CFrame.lookAt(beamMiddle, beamMiddle + (next - here)), Color3.fromRGB(44, 36, 54), Enum.Material.SmoothPlastic)
		part(folder, "BeamTrim", Vector3.new(1.2, 0.25, (next - here).Magnitude + 0.2), CFrame.lookAt(beamMiddle + Vector3.new(0, -0.7, 0), beamMiddle + Vector3.new(0, -0.7, 0) + (next - here)), GOLD, Enum.Material.Metal)
		rope(folder, here + Vector3.new(0, PILLAR_HEIGHT - 4.4, 0), next + Vector3.new(0, PILLAR_HEIGHT - 4.4, 0))
		local lampAt = (here + next) / 2 + Vector3.new(0, PILLAR_HEIGHT - 3.2 - 2.3 - 0.2, 0)
		PropModel.place(folder, "Chochin", CFrame.new(lampAt), 1.2, { Red = VIOLET })
	end

	-- Tejado octogonal de dos pisos (modelo de Blender).
	PropModel.place(folder, "TempleRoof", CFrame.new(0, top + PILLAR_HEIGHT, 0), 1.0)

	-- Magia: dos círculos de runas que giran en sentidos contrarios, un rayo de luz y fuegos fatuos.
	magicCircle(folder, "CircleLow", top + 5.5, 9.5, 0.35, VIOLET, CYAN, 12)
	magicCircle(folder, "CircleHigh", top + 8.5, 5.5, -0.55, PINK, CYAN, 8)

	local beam = decor(part(folder, "SpiritBeam", Vector3.new(80, 11, 11), CFrame.new(0, top + 40, 0) * CFrame.Angles(0, 0, math.rad(90)), VIOLET, Enum.Material.Neon))
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.84
	CollectionService:AddTag(beam, "SpiritBeam")
	local core = decor(part(folder, "SpiritCore", Vector3.new(80, 3, 3), CFrame.new(0, top + 40, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 210, 255), Enum.Material.Neon))
	core.Shape = Enum.PartType.Cylinder
	core.Transparency = 0.55
	CollectionService:AddTag(core, "SpiritBeam")

	for index = 1, 10 do
		local wisp = decor(part(folder, "Wisp", Vector3.one * 0.9, CFrame.new(0, top + 6, 0), if index % 3 == 0 then PINK elseif index % 3 == 1 then CYAN else VIOLET, Enum.Material.Neon))
		wisp.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = wisp.Color
		light.Range = 11
		light.Brightness = 0.9
		light.Parent = wisp
		wisp:SetAttribute("Radius", 12 + (index % 4) * 3.5)
		wisp:SetAttribute("Height", top + 3 + (index % 5) * 2.6)
		wisp:SetAttribute("Speed", (0.35 + (index % 3) * 0.15) * (if index % 2 == 0 then 1 else -1))
		wisp:SetAttribute("Phase", index * 0.63)
		CollectionService:AddTag(wisp, "Wisp")
	end

	local mist = decor(part(folder, "MagicMist", Vector3.new(24, 1, 24), CFrame.new(0, top + 1, 0), VIOLET, Enum.Material.SmoothPlastic))
	mist.Transparency = 1
	CollectionService:AddTag(mist, "MagicMist")

	-- Toriis alrededor, mirando al templo, con farolillos violeta, y linternas de piedra entre ellos.
	for index = 1, 4 do
		local angle = math.rad(22.5 + (index - 1) * 90)
		local spot = polar(angle, 44, top)
		PropModel.place(folder, "Torii", CFrame.lookAt(spot, Vector3.new(0, top, 0)), 0.9)
		for _, sign in { 1, -1 } do
			local hang = CFrame.lookAt(spot, Vector3.new(0, top, 0)) * CFrame.new(sign * 4.0, 7.1, 0)
			PropModel.place(folder, "Chochin", hang, 0.95, { Red = VIOLET })
		end
	end
end

return TempleEntrance
