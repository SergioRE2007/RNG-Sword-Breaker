-- Entrada de las mazmorras como un santuario místico (Config.Theme = "japan"): un templo abierto de dos tejados,
-- centrado justo encima de la boca del pozo y de su ascensor de luz (LightLift), igual por los cuatro lados, con
-- columnas rojas, tejados escalonados, farolillos y magia: dos círculos de runas que giran. Se
-- construye después de DungeonLobby, que es quien abre el pozo y pone el borde de piedra y el cartel. El cliente
-- (JapanFx) mueve los círculos con la etiqueta MagicCircle. Casi todo es decoración: solo las columnas tienen colisión.
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
local BLACK = Color3.fromRGB(44, 36, 54)
local STONE = Color3.fromRGB(170, 166, 190)
local PLASTER = Color3.fromRGB(240, 228, 214)
local WOOD = Color3.fromRGB(122, 78, 62)

local SIDE = 46 -- lado de la planta cuadrada del templo, centrada sobre la boca
local COLUMN_HEIGHT = 15

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

-- Columna laqueada: base de piedra, fuste rojo, bandas doradas y capitel negro.
local function pillar(parent: Instance, position: Vector3, height: number)
	local base = CFrame.new(position)
	local stone = part(parent, "PillarBase", Vector3.new(0.9, 3.6, 3.6), base * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Slate)
	stone.Shape = Enum.PartType.Cylinder
	local shaft = part(parent, "Pillar", Vector3.new(height - 1.2, 2.2, 2.2), base * CFrame.new(0, 0.9 + (height - 1.2) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), LACQUER, Enum.Material.SmoothPlastic)
	shaft.Shape = Enum.PartType.Cylinder
	for _, y in { 1.8, height - 1.6 } do
		local band = decor(part(parent, "PillarBand", Vector3.new(0.5, 2.6, 2.6), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal))
		band.Shape = Enum.PartType.Cylinder
	end
	part(parent, "PillarCap", Vector3.new(3.4, 0.8, 3.4), base * CFrame.new(0, height - 0.4, 0), BLACK, Enum.Material.SmoothPlastic)
end

-- Farolillo del templo: pone una luz violeta en su papel y lo marca para que el cliente la encienda de noche.
local function lampLight(model: Model?)
	local paper = model and model:FindFirstChild("Paper")
	if paper then
		local light = Instance.new("PointLight")
		light.Color = VIOLET
		light.Brightness = 0.08
		light.Range = 8
		light:SetAttribute("Base", 0.1) -- brillo casi mínimo: el cliente (JapanFx) lo escala por la noche
		light.Parent = paper
		CollectionService:AddTag(paper, "LanternGlow")
	end
end

-- Tejado escalonado de planta cuadrada, igual por los cuatro lados: `count` losas que se estrechan de `from` a `to` de
-- lado, cada una con un canto dorado. Devuelve la altura de la cara superior de la última.
local function roofTiers(parent: Instance, y0: number, from: number, to: number, count: number): number
	local rise = 1.4
	for tier = 0, count - 1 do
		local side = from + (to - from) * tier / math.max(count - 1, 1)
		local y = y0 + tier * rise
		decor(part(parent, "RoofTier", Vector3.new(side, 1.2, side), CFrame.new(0, y + 0.6, 0), BLACK, Enum.Material.SmoothPlastic))
		-- El canto dorado sobresale por abajo (0,1) para que su cara no coincida con la de la losa y parpadee.
		decor(part(parent, "RoofTrim", Vector3.new(side + 0.5, 0.3, side + 0.5), CFrame.new(0, y + 0.05, 0), GOLD, Enum.Material.Metal))
	end
	return y0 + (count - 1) * rise + 1.2
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

-- El templo: abierto y centrado sobre la boca (y su ascensor), igual por los cuatro lados: columnas en el perímetro
-- (con un hueco libre en medio de cada lado), vigas, farolillos y dos tejados escalonados. Sin suelo ni muros: se
-- pisa el del hub.
local function shrine(folder: Folder, top: number)
	local edge = SIDE / 2 - 2 -- las columnas están a esta distancia del centro
	local height = COLUMN_HEIGHT

	-- Columnas: solo dos por esquina, una a cada lado de la esquina.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			pillar(folder, Vector3.new(sx * edge, top, sz * (edge - 5)), height)
			pillar(folder, Vector3.new(sx * (edge - 5), top, sz * edge), height)
		end
	end
	-- Vigas negras con friso dorado en los cuatro lados.
	for _, sign in { -1, 1 } do
		part(folder, "Beam", Vector3.new(SIDE, 1.2, 1.6), CFrame.new(0, top + height + 0.4, sign * edge), BLACK, Enum.Material.SmoothPlastic)
		decor(part(folder, "BeamTrim", Vector3.new(SIDE, 0.25, 1.9), CFrame.new(0, top + height - 0.4, sign * edge), GOLD, Enum.Material.Metal))
		part(folder, "Beam", Vector3.new(1.6, 1.2, SIDE), CFrame.new(sign * edge, top + height + 0.4, 0), BLACK, Enum.Material.SmoothPlastic)
		decor(part(folder, "BeamTrim", Vector3.new(1.9, 0.25, SIDE), CFrame.new(sign * edge, top + height - 0.4, 0), GOLD, Enum.Material.Metal))
	end

	-- Tejado bajo (el alero sobresale de las columnas), un cuerpo alto encima y el tejado alto con su remate.
	local lowTop = roofTiers(folder, top + height + 1, SIDE + 12, SIDE - 16, 5)
	local bodySide = SIDE - 22
	part(folder, "UpperBody", Vector3.new(bodySide, 7, bodySide), CFrame.new(0, lowTop + 3, 0), PLASTER, Enum.Material.SmoothPlastic)
	decor(part(folder, "UpperBeam", Vector3.new(bodySide + 0.8, 0.8, bodySide + 0.8), CFrame.new(0, lowTop + 6.6, 0), WOOD, Enum.Material.Wood))
	local highTop = roofTiers(folder, lowTop + 7, bodySide + 10, 5, 6)
	local spire = decor(part(folder, "Finial", Vector3.one * 3, CFrame.new(0, highTop + 1.2, 0), GOLD, Enum.Material.Metal))
	spire.Shape = Enum.PartType.Ball
	decor(part(folder, "FinialRod", Vector3.new(0.6, 5, 0.6), CFrame.new(0, highTop + 3, 0), GOLD, Enum.Material.Metal))

	-- Farolillos violeta colgando del alero, por los cuatro lados.
	for _, i in { -edge * 5 / 6, -edge / 2, -edge / 6, edge / 6, edge / 2, edge * 5 / 6 } do
		for _, sign in { -1, 1 } do
			lampLight(PropModel.place(folder, "Chochin", CFrame.new(i, top + height - 4.2, sign * (edge + 1.6)), 1.3, { Red = VIOLET }))
			lampLight(PropModel.place(folder, "Chochin", CFrame.new(sign * (edge + 1.6), top + height - 4.2, i), 1.3, { Red = VIOLET }))
		end
	end
end

function TempleEntrance.start()
	if Config.Theme ~= "japan" then
		return
	end
	local top = Config.Plot.FloorHeight

	-- Fuera lo que puso DungeonLobby sobre el borde (ocho pilares de piedra con farol): la boca queda libre para el
	-- ascensor. El cartel flota algo más alto sobre ella.
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
			sign.CFrame = CFrame.new(0, top + 10, 0)
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "TemploMazmorras"
	folder.Parent = workspace

	shrine(folder, top)

	-- Magia sobre la boca: dos círculos de runas que giran en sentidos contrarios (sin rayo, fuegos fatuos ni niebla,
	-- quitados porque se veían rotos).
	magicCircle(folder, "CircleLow", top + 5.5, 9.5, 0.35, VIOLET, CYAN, 12)
	magicCircle(folder, "CircleHigh", top + 8.5, 5.5, -0.55, PINK, CYAN, 8)
end

return TempleEntrance
