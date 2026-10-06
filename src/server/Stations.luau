-- Estaciones del hub hechas con piezas: la Forja (yunque y horno, tienda de Grados) y la Mesa de
-- encantamiento (libro flotante, cristales y runas, tienda de Rasgos). Aquí solo se coloca la
-- geometría y se etiqueta lo que se mueve o brilla (etiquetas "Station*"); las luces, las
-- partículas y las animaciones las crea y mueve el cliente (client/StationFx).
-- Cada estación mira hacia el centro del hub y devuelve su modelo, la pieza invisible "Counter"
-- (lleva el cartel y el aviso) y la altura del cartel.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Stations = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function make(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

-- Cilindro vertical: el eje de un cilindro de Roblox es X, así que se tumba.
local function disc(parent: Instance, name: string, height: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local item = make(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.pi / 2), color, material)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function ball(parent: Instance, name: string, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local item = make(parent, name, Vector3.new(diameter, diameter, diameter), cframe, color, material)
	item.Shape = Enum.PartType.Ball
	return item
end

local function tag(item: Instance, name: string, attributes: { [string]: any }?)
	CollectionService:AddTag(item, name)
	for key, value in attributes or {} do
		item:SetAttribute(key, value)
	end
end

local function decor(item: Part)
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
end

-- Pieza invisible por delante de la estación: lleva el cartel y el aviso.
local function counterPart(model: Model, cframe: CFrame): Part
	local counter = make(model, "Counter", Vector3.new(6, 1, 2), cframe, rgb(255, 255, 255))
	counter.Transparency = 1
	decor(counter)
	return counter
end

-- FORJA: horno al fondo, yunque con metal al rojo y martillo delante, barril de agua, carbón y farol.
function Stations.forge(position: Vector3): (Model, Part, number)
	local model = Instance.new("Model")
	model.Name = "Forja"
	local floor = Config.Plot.FloorHeight
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	local y0 = floor + 0.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	local stone = rgb(88, 84, 96)
	local darkStone = rgb(62, 60, 70)
	local iron = rgb(48, 50, 58)
	local wood = rgb(112, 76, 46)

	make(model, "Suelo", Vector3.new(18, 0.5, 16), at(0, floor + 0.25, 0), rgb(70, 68, 80), Enum.Material.Slate)
	make(model, "Borde", Vector3.new(18.8, 0.3, 16.8), at(0, floor + 0.15, 0), darkStone, Enum.Material.Slate)

	-- Horno: cuerpo, cornisa, chimenea y boca con el fuego dentro.
	make(model, "Horno", Vector3.new(8, 7, 5), at(0, y0 + 3.5, 5), stone, Enum.Material.Cobblestone)
	make(model, "HornoBase", Vector3.new(8.8, 1, 5.8), at(0, y0 + 0.5, 5), darkStone, Enum.Material.Cobblestone)
	make(model, "HornoCornisa", Vector3.new(8.8, 0.9, 5.8), at(0, y0 + 7.4, 5), darkStone, Enum.Material.Cobblestone)
	local chimney = make(model, "Chimenea", Vector3.new(2.6, 6, 2.6), at(0, y0 + 10.8, 5.4), stone, Enum.Material.Cobblestone)
	make(model, "ChimeneaBorde", Vector3.new(3.2, 0.7, 3.2), at(0, y0 + 14, 5.4), darkStone, Enum.Material.Cobblestone)
	tag(chimney, "StationSmoke")
	make(model, "BocaHueco", Vector3.new(4.2, 3.4, 0.4), at(0, y0 + 2.6, 2.4), rgb(20, 18, 22), Enum.Material.Slate)
	make(model, "BocaPoste", Vector3.new(0.7, 4, 0.8), at(-2.4, y0 + 2.7, 2.1), iron, Enum.Material.Metal)
	make(model, "BocaPoste", Vector3.new(0.7, 4, 0.8), at(2.4, y0 + 2.7, 2.1), iron, Enum.Material.Metal)
	make(model, "BocaDintel", Vector3.new(5.8, 0.8, 0.8), at(0, y0 + 4.9, 2.1), iron, Enum.Material.Metal)
	for _, x in { -1.8, -0.6, 0.6, 1.8 } do
		make(model, "BocaRejilla", Vector3.new(0.18, 0.18, 0.6), at(x, y0 + 0.9, 2.0), iron, Enum.Material.Metal)
	end
	local fire = make(model, "Fuego", Vector3.new(3.4, 2.4, 0.5), at(0, y0 + 2.2, 2.2), rgb(255, 130, 30), Enum.Material.Neon)
	decor(fire)
	tag(fire, "StationFire")

	-- Yunque sobre un tocón, con el metal al rojo encima.
	disc(model, "Tocon", 1.8, 3.4, at(0, y0 + 0.9, -1.2), wood, Enum.Material.Wood)
	make(model, "YunqueBase", Vector3.new(2.6, 0.8, 1.9), at(0, y0 + 2.2, -1.2), iron, Enum.Material.Metal)
	make(model, "YunqueCuello", Vector3.new(1.3, 0.9, 1.2), at(0, y0 + 3.05, -1.2), iron, Enum.Material.Metal)
	make(model, "YunqueCara", Vector3.new(4.2, 0.9, 1.9), at(0, y0 + 3.95, -1.2), rgb(70, 72, 82), Enum.Material.Metal)
	make(model, "YunqueCuerno", Vector3.new(1.6, 0.6, 1.2), at(2.8, y0 + 3.85, -1.2), rgb(70, 72, 82), Enum.Material.Metal)
	make(model, "YunqueCuerno", Vector3.new(0.9, 0.4, 0.7), at(3.7, y0 + 3.8, -1.2), rgb(70, 72, 82), Enum.Material.Metal)
	local hot = make(model, "MetalAlRojo", Vector3.new(1.8, 0.25, 0.55), at(-0.3, y0 + 4.52, -1.2), rgb(255, 120, 30), Enum.Material.Neon)
	decor(hot)
	tag(hot, "StationHotMetal")

	-- Martillo: el cliente lo levanta y lo deja caer sobre el metal; `Hit` es donde saltan las chispas.
	-- La cabeza es larga en Z (el plano del golpe): con el mango horizontal queda de pie y apoya su
	-- cara plana sobre el metal.
	local hammer = Instance.new("Model")
	hammer.Name = "Martillo"
	local handle = make(hammer, "Mango", Vector3.new(0.5, 3.4, 0.5), at(-0.3, y0 + 5.55 + 1.7, -4.6), rgb(120, 80, 48), Enum.Material.Wood)
	local head = make(hammer, "Cabeza", Vector3.new(1, 1, 1.8), at(-0.3, y0 + 5.55 + 3.4, -4.6), rgb(84, 86, 96), Enum.Material.Metal)
	decor(handle)
	decor(head)
	-- Eje invisible en el extremo del mango: es el pivote que ve el cliente (WorldPivot no llega).
	local axis = make(hammer, "Eje", Vector3.new(0.3, 0.3, 0.3), at(-0.3, y0 + 5.55, -4.6), iron, Enum.Material.Metal)
	axis.Transparency = 1
	decor(axis)
	hammer.PrimaryPart = axis
	hammer.Parent = model
	tag(hammer, "StationHammer", { Hit = (at(-0.3, y0 + 4.75, -1.2)).Position })

	-- Barril de agua para templar, con vapor.
	disc(model, "Barril", 2.8, 3.2, at(-5.8, y0 + 1.4, -2.2), rgb(96, 64, 40), Enum.Material.Wood)
	disc(model, "BarrilAro", 0.25, 3.3, at(-5.8, y0 + 0.7, -2.2), iron, Enum.Material.Metal)
	disc(model, "BarrilAro", 0.25, 3.3, at(-5.8, y0 + 2.1, -2.2), iron, Enum.Material.Metal)
	local water = disc(model, "Agua", 0.2, 2.7, at(-5.8, y0 + 2.75, -2.2), rgb(70, 150, 210), Enum.Material.SmoothPlastic)
	water.Transparency = 0.15
	tag(water, "StationSteam")

	-- Carbón, lingotes y brasas sueltas.
	for index, data in { { -3.8, 1.2, 1.4 }, { -4.6, 0.7, 2.4 }, { -3.1, 0.8, 3.1 }, { 3.9, 1, 1.8 } } do
		local rock = make(model, "Carbon", Vector3.new(data[2] + 0.5, data[2], data[2] + 0.3), at(data[1], y0 + data[2] / 2, data[3]) * CFrame.Angles(0, index, 0.2), rgb(30, 30, 36), Enum.Material.Slate)
		rock.CanCollide = false
	end
	for index, data in { { -3.9, 1.5 }, { -3.2, 3.3 }, { 4.1, 1.5 } } do
		local ember = make(model, "Brasa", Vector3.new(0.35, 0.25, 0.35), at(data[1], y0 + 1.1 + (index % 2) * 0.1, data[2]), rgb(255, 90, 20), Enum.Material.Neon)
		decor(ember)
		tag(ember, "StationPulse", { Speed = 2.5 + index })
	end
	for index = 0, 2 do
		local ingot = make(model, "Lingote", Vector3.new(1.4, 0.45, 0.7), at(4.2 + (index % 2) * 0.1, y0 + 0.22 + index * 0.45, -3.4) * CFrame.Angles(0, 0.2 * index, 0), rgb(235, 190, 60), Enum.Material.Metal)
		ingot.CanCollide = false
	end

	-- Farol de hierro con llama.
	make(model, "FarolPoste", Vector3.new(0.4, 7, 0.4), at(6.2, y0 + 3.5, -3.2), iron, Enum.Material.Metal)
	make(model, "FarolBrazo", Vector3.new(1.4, 0.3, 0.3), at(5.6, y0 + 6.9, -3.2), iron, Enum.Material.Metal)
	local lantern = make(model, "Farol", Vector3.new(1.4, 1.8, 1.4), at(5, y0 + 6, -3.2), rgb(255, 190, 90), Enum.Material.Neon)
	lantern.Transparency = 0.1
	decor(lantern)
	tag(lantern, "StationGlow", { Range = 20, Light = 1.3, Flicker = true })

	local counter = counterPart(model, at(0, floor + 2.5, -4.6))
	return model, counter, 12
end

-- MESA DE ENCANTAMIENTO: pedestal con un libro flotante, cristales que orbitan, cuatro pilares con
-- orbes y un círculo de runas en el suelo que gira.
function Stations.enchanter(position: Vector3): (Model, Part, number)
	local model = Instance.new("Model")
	model.Name = "MesaEncantamiento"
	local floor = Config.Plot.FloorHeight
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	local y0 = floor + 0.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	local violet = rgb(150, 90, 255)
	local cyan = rgb(110, 220, 255)
	local pink = rgb(255, 120, 220)
	local plate = rgb(40, 28, 68)
	local stone = rgb(62, 44, 102)

	disc(model, "Suelo", 0.5, 17, at(0, floor + 0.25, 0), plate, Enum.Material.Slate)
	local outer = disc(model, "AroRunico", 0.12, 15.6, at(0, y0 + 0.02, 0), violet, Enum.Material.Neon)
	decor(outer)
	tag(outer, "StationPulse", { Speed = 1.6 })
	decor(disc(model, "AroTapa", 0.14, 14.9, at(0, y0 + 0.03, 0), plate, Enum.Material.Slate))

	-- Disco de runas (gira): tres barras cruzadas y seis runas.
	local runes = Instance.new("Model")
	runes.Name = "Runas"
	for index = 0, 2 do
		local bar = make(runes, "Barra", Vector3.new(11.5, 0.1, 0.3), at(0, y0 + 0.14, 0) * CFrame.Angles(0, math.rad(60 * index), 0), if index == 1 then cyan else violet, Enum.Material.Neon)
		decor(bar)
	end
	for index = 0, 5 do
		local angle = math.rad(60 * index)
		local rune = make(runes, "Runa", Vector3.new(0.7, 0.12, 0.7), at(math.cos(angle) * 5.9, y0 + 0.14, math.sin(angle) * 5.9) * CFrame.Angles(0, -angle + math.rad(45), 0), if index % 2 == 0 then pink else cyan, Enum.Material.Neon)
		decor(rune)
	end
	runes.WorldPivot = at(0, y0 + 0.14, 0)
	runes.Parent = model
	tag(runes, "StationSpin", { Speed = 0.35 })

	-- Pedestal.
	disc(model, "Escalon", 0.6, 5.4, at(0, y0 + 0.3, 0), stone, Enum.Material.Slate)
	disc(model, "Pedestal", 3.4, 3.2, at(0, y0 + 1.7, 0), stone, Enum.Material.Slate)
	disc(model, "PedestalAnillo", 0.4, 3.6, at(0, y0 + 1.2, 0), rgb(36, 26, 62), Enum.Material.Slate)
	local rim = disc(model, "TableroBorde", 0.3, 6.3, at(0, y0 + 3.65, 0), violet, Enum.Material.Neon)
	decor(rim)
	tag(rim, "StationPulse", { Speed = 2 })
	disc(model, "Tablero", 0.5, 6, at(0, y0 + 3.7, 0), rgb(30, 22, 54), Enum.Material.Slate)
	local sigil = disc(model, "TableroSello", 0.06, 3.4, at(0, y0 + 3.97, 0), cyan, Enum.Material.Neon)
	decor(sigil)
	tag(sigil, "StationPulse", { Speed = 1.2 })
	decor(disc(model, "TableroSelloTapa", 0.08, 3.0, at(0, y0 + 3.97, 0), rgb(30, 22, 54), Enum.Material.Slate))

	-- Libro abierto flotando sobre la mesa.
	local book = Instance.new("Model")
	book.Name = "Libro"
	local bookAt = at(0, y0 + 6.3, 0)
	local cover = rgb(96, 40, 160)
	local paper = rgb(242, 232, 205)
	for _, side in { -1, 1 } do
		local half = bookAt * CFrame.new(side * 1.1, 0, 0) * CFrame.Angles(0, 0, side * 0.32)
		decor(make(book, "Tapa", Vector3.new(2.3, 0.2, 3.1), half, cover, Enum.Material.SmoothPlastic))
		decor(make(book, "Paginas", Vector3.new(2.05, 0.2, 2.8), half * CFrame.new(0, 0.2, 0), paper, Enum.Material.SmoothPlastic))
		for line = -2, 2 do
			local text = make(book, "Texto", Vector3.new(1.4, 0.04, 0.1), half * CFrame.new(0, 0.32, line * 0.45), rgb(190, 160, 255), Enum.Material.Neon)
			decor(text)
			if side == 1 and line == 0 then
				tag(text, "StationGlow", { Range = 10, Light = 1 })
			end
		end
	end
	local spine = make(book, "Lomo", Vector3.new(0.3, 0.3, 3.1), bookAt * CFrame.new(0, -0.12, 0), rgb(70, 28, 120), Enum.Material.SmoothPlastic)
	decor(spine)
	tag(spine, "StationMotes", { Color = Color3.fromRGB(190, 150, 255), Rate = 14 })
	book.WorldPivot = bookAt
	book.Parent = model
	tag(book, "StationFloat", { BobHeight = 0.5, BobSpeed = 1.5, SpinSpeed = 0.45 })

	-- Cristales que orbitan alrededor del libro.
	local crystals = { cyan, pink, violet, rgb(255, 245, 190) }
	for index, color in crystals do
		local crystal = make(model, "Cristal", Vector3.new(0.9, 0.9, 0.9), at(0, y0 + 6, 0), color, Enum.Material.Neon)
		decor(crystal)
		tag(crystal, "StationOrbit", {
			Center = at(0, y0 + 6, 0).Position,
			Radius = 3.8,
			Speed = 0.9 + 0.12 * index,
			Phase = (index - 1) * math.pi / 2,
			Height = y0 + 6,
		})
		if index % 2 == 1 then
			tag(crystal, "StationGlow", { Range = 9, Light = 0.5 })
		end
	end

	-- Cuatro pilares con un orbe que flota.
	for index = 0, 3 do
		local angle = math.rad(45 + 90 * index)
		local x, z = math.cos(angle) * 7, math.sin(angle) * 7
		make(model, "PilarBase", Vector3.new(1.9, 0.7, 1.9), at(x, y0 + 0.35, z) * CFrame.Angles(0, -angle, 0), stone, Enum.Material.Slate)
		make(model, "Pilar", Vector3.new(1.1, 4.4, 1.1), at(x, y0 + 2.9, z) * CFrame.Angles(0, -angle, 0), plate, Enum.Material.Slate)
		make(model, "PilarCapitel", Vector3.new(1.6, 0.5, 1.6), at(x, y0 + 5.35, z) * CFrame.Angles(0, -angle, 0), stone, Enum.Material.Slate)
		local stripe = make(model, "PilarRuna", Vector3.new(0.18, 2.6, 0.18), at(x * 0.93, y0 + 2.9, z * 0.93), if index % 2 == 0 then pink else cyan, Enum.Material.Neon)
		decor(stripe)
		tag(stripe, "StationPulse", { Speed = 2.2 + index * 0.3 })
		local orb = ball(model, "Orbe", 1.1, at(x, y0 + 6.6, z), if index % 2 == 0 then violet else cyan, Enum.Material.Neon)
		decor(orb)
		tag(orb, "StationFloat", { BobHeight = 0.35, BobSpeed = 1.3 + index * 0.2, SpinSpeed = 0, Phase = index * 1.3 })
		tag(orb, "StationGlow", { Range = 11, Light = 0.55 })
		tag(orb, "StationMotes", { Color = orb.Color, Rate = 5 })
	end

	local counter = counterPart(model, at(0, floor + 2.5, -5.2))
	return model, counter, 12
end

return Stations
