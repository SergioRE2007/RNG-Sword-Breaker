-- Entrada de las mazmorras como un templo místico (Config.Theme = "japan"): tres pisos, 82 de ancho y casi 100 de alto,
-- centrado justo encima de la boca del pozo y de su ascensor de luz (LightLift) e igual por los cuatro lados. El
-- edificio entero es un modelo de Blender (PropModel "TempleA", "TempleB" y "TempleC", uno por piso: doce columnas
-- rojas, techo de casetones, cuerdas sagradas y tres tejados curvos). Aquí se le ponen los colores, los farolillos
-- violeta, una placa con el nombre en cada lado y la magia: dos círculos de runas que giran sobre la boca. Se
-- construye después de DungeonLobby, que es quien abre el pozo y pone el borde de piedra y el cartel. El cliente
-- (JapanFx) mueve los círculos con la etiqueta MagicCircle. Solo las columnas tienen colisión (la pone PropModel).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)

local TempleEntrance = {}

local VIOLET = Color3.fromRGB(176, 124, 255)
local CYAN = Color3.fromRGB(110, 232, 255)
local PINK = Color3.fromRGB(255, 140, 222)
local GOLD = Color3.fromRGB(255, 208, 64)
local BLACK = Color3.fromRGB(44, 36, 54)

-- Medidas del modelo (tools/blender/crear_mapa_japones.py, temple): media anchura de la línea de columnas y altura
-- de la cara de abajo de la viga que une sus cabezas.
local EDGE = 26
local BEAM = 21.2

-- Colores del templo: tejados añil con las filas de tejas algo más oscuras, madera oscura y ventanas de papel. El
-- único papel de la planta baja es el sello del techo, que va en violeta como los farolillos.
local TINT = {
	Roof = Color3.fromRGB(74, 62, 138),
	StoneDark = Color3.fromRGB(52, 44, 104),
	Wood = Color3.fromRGB(70, 48, 62),
	Paper = Color3.fromRGB(255, 222, 150),
}
local TINT_GROUND = table.clone(TINT)
TINT_GROUND.Paper = VIOLET

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

-- Farolillo del templo: pone una luz violeta en su papel y lo marca para que el cliente la encienda de noche.
local function lampLight(model: Model?)
	local paper = model and model:FindFirstChild("Paper")
	if paper then
		local light = Instance.new("PointLight")
		light.Color = VIOLET
		light.Brightness = 0
		light.Enabled = false
		light.Range = 8
		light:SetAttribute("Base", 0.1) -- brillo casi mínimo: el cliente (JapanFx) lo escala por la noche
		light.Parent = paper
		CollectionService:AddTag(paper, "LanternGlow")
		CollectionService:AddTag(light, "NightLight")
	end
end

-- El papel de las ventanas y del sello se enciende solo de noche, como el de los farolillos (client/MapLights).
local function lightPaper(model: Model?)
	local paper = model and model:FindFirstChild("Paper")
	if paper then
		CollectionService:AddTag(paper, "LanternGlow")
	end
end

-- Placa con el nombre colgada sobre la entrada de un lado: tabla negra con marco dorado y el texto en su cara.
local function plaque(parent: Instance, cframe: CFrame)
	local board = decor(part(parent, "Plaque", Vector3.new(15, 4.2, 0.5), cframe, BLACK, Enum.Material.SmoothPlastic))
	for _, edge in { { 0, 2.3, 16, 0.5 }, { 0, -2.3, 16, 0.5 }, { 7.75, 0, 0.5, 5.1 }, { -7.75, 0, 0.5, 5.1 } } do
		decor(part(parent, "PlaqueFrame", Vector3.new(edge[3], edge[4], 0.8), cframe * CFrame.new(edge[1], edge[2], 0), GOLD, Enum.Material.Metal))
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "MAZMORRAS"
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 5
	outline.Parent = label
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 176, 48))
	gradient.Parent = label
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

-- El templo, centrado sobre la boca (y su ascensor): el modelo de los tres pisos y, en cada uno de sus cuatro lados,
-- cuatro farolillos colgando de la viga (dos por vano lateral) y la placa sobre la entrada del centro. Sin suelo ni
-- muros: se pisa el del hub.
local function temple(folder: Folder, top: number)
	local origin = CFrame.new(0, top, 0)
	lightPaper(PropModel.place(folder, "TempleA", origin, 1, TINT_GROUND))
	lightPaper(PropModel.place(folder, "TempleB", origin, 1, TINT))
	lightPaper(PropModel.place(folder, "TempleC", origin, 1, TINT))

	for side = 0, 3 do
		local frame = origin * CFrame.Angles(0, side * math.pi / 2, 0)
		for _, x in { -21, -15, 15, 21 } do
			lampLight(PropModel.place(folder, "Chochin", frame * CFrame.new(x, BEAM - 2.95, -EDGE), 1.4, { Red = VIOLET }))
		end
		plaque(folder, frame * CFrame.new(0, 24, -(EDGE + 1.5)) * CFrame.Angles(math.rad(-10), 0, 0))
	end

	-- Luz violeta bajo el techo, solo de noche (client/MapLights).
	local holder = decor(part(folder, "CeilingLight", Vector3.one, origin * CFrame.new(0, 22, 0), VIOLET, Enum.Material.SmoothPlastic))
	holder.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(214, 176, 255)
	light.Brightness = 0
	light.Enabled = false
	light.Range = 46
	light:SetAttribute("Base", 0.7)
	light.Parent = holder
	CollectionService:AddTag(light, "NightLight")
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
			sign.CFrame = CFrame.new(0, top, 0) -- el texto sale 13 más arriba: flota sobre la boca, bajo el techo del templo
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "TemploMazmorras"
	folder.Parent = workspace

	temple(folder, top)

	-- Magia sobre la boca: dos círculos de runas que giran en sentidos contrarios (sin rayo, fuegos fatuos ni niebla,
	-- quitados porque se veían rotos).
	magicCircle(folder, "CircleLow", top + 5.5, 9.5, 0.35, VIOLET, CYAN, 12)
	magicCircle(folder, "CircleHigh", top + 8.5, 5.5, -0.55, PINK, CYAN, 8)
end

return TempleEntrance
