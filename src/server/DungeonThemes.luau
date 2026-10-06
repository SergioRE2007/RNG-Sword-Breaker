-- Decorado de las mazmorras (librería, sin start()): construye la arena de una zona (suelo, muro, techo y adornos)
-- a partir de su tema de Config.DungeonThemes, y adorna con los mismos adornos las salas del lobby subterráneo.
-- Solo hay piezas: las partículas y la luz de ambiente las pone el cliente (client/DungeonFx), y las luces
-- puntuales son pocas y pequeñas. Sin Neon grande (solo faroles, brasas y estrellas diminutas).
-- Un adorno nuevo = una función en PROPS (y, si su sitio no es el borde, su zona en ZONES); un muro nuevo = una
-- función en WALLS. Un tema nuevo no necesita código: solo su entrada en Config.DungeonThemes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DungeonThemes = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BONE = Color3.fromRGB(232, 228, 212)
local WOOD = Color3.fromRGB(112, 82, 54)
local DARK_METAL = Color3.fromRGB(58, 60, 68)

-- Tema de reserva para una zona que aún no tenga el suyo: piedra gris.
local FALLBACK = {
	floor = { color = Color3.fromRGB(58, 56, 72), material = Enum.Material.Slate, ring = Color3.fromRGB(72, 70, 88), ringMaterial = Enum.Material.Cobblestone },
	wall = { style = "stone", colors = { Color3.fromRGB(72, 70, 88), Color3.fromRGB(58, 56, 72) }, material = Enum.Material.Slate },
	props = {},
	torch = Color3.fromRGB(255, 160, 60),
	enemies = {},
	room = {},
}

-- Piezas -------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material or Enum.Material.Slate
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

-- Pieza que solo se mira: sin choque ni consultas (el adorno del suelo no estorba a los enemigos).
local function deco(item: BasePart): BasePart
	item.CanCollide = false
	item.CanQuery = false
	return item
end

local function small(item: BasePart): BasePart
	deco(item)
	item.CastShadow = false
	return item
end

-- Cilindro vertical con la base en `base` (su Y local 0).
local function cylinder(parent: Instance, name: string, height: number, diameter: number, base: CFrame, color: Color3, material: Enum.Material?): Part
	local item = part(parent, name, Vector3.new(height, diameter, diameter), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function ball(parent: Instance, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	local item = part(parent, name, Vector3.one * diameter, CFrame.new(position), color, material)
	item.Shape = Enum.PartType.Ball
	return item
end

-- Disco tumbado centrado en `center`.
local function disc(parent: Instance, name: string, center: Vector3, radius: number, height: number, color: Color3, material: Enum.Material?): Part
	local item = part(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	return item
end

-- Farol: cubito de neón (el color oscurecido, para que el brillo del juego no lo deje blanco) y una luz puntual.
local function lantern(parent: Instance, cframe: CFrame, color: Color3, range: number?, brightness: number?): Part
	local lamp = small(part(parent, "Torch", Vector3.new(1.2, 1.2, 1.2), cframe, color:Lerp(BLACK, 0.35), Enum.Material.Neon))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 36
	light.Brightness = brightness or 1.6
	light.Parent = lamp
	return lamp
end

-- Contexto de construcción -------------------------------------------------------------------
-- { model, rng, theme, level, leaf = color de hoja, wall = {c1, c2, material}, torch, spot(zona, i, n) -> CFrame,
--   sky(min, max) -> posición alta, ringCenter, ringRadii }

local function wallLook(theme)
	local wall = theme.wall or FALLBACK.wall
	local colors = wall.colors or FALLBACK.wall.colors
	return colors[1], colors[2] or colors[1], wall.material or Enum.Material.Slate
end

-- Arena: círculo de `radius` centrado en `origin` (la Y de origin es la del suelo).
local function arenaContext(model: Instance, origin: Vector3, radius: number, theme, level)
	local rng = Random.new()
	local ctx
	ctx = {
		model = model,
		origin = origin,
		radius = radius,
		rng = rng,
		theme = theme,
		level = level,
		torch = theme.torch or level.color,
		segments = 28,
		ringCenter = origin + Vector3.new(0, 30, 0),
		ringRadii = { radius * 0.65, radius * 0.9 },
	}
	ctx.width = 2 * math.pi * (radius + 2) / ctx.segments + 0.6
	ctx.c1, ctx.c2, ctx.material = wallLook(theme)
	ctx.leaf = ctx.c2

	-- Sitio de un adorno: "edge" junto al muro (mirando al centro), "floor" por el suelo (giro al azar).
	function ctx.spot(zone: string, index: number, count: number): CFrame
		if zone == "edge" then
			local phase = ctx.phase
			local turn = ((index - 1 + rng:NextNumber(-0.35, 0.35)) / count) * math.pi * 2 + phase
			local distance = radius - rng:NextNumber(1.8, 6)
			local position = origin + Vector3.new(math.cos(turn) * distance, 0, math.sin(turn) * distance)
			return CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
		end
		local distance = math.sqrt(rng:NextNumber(10 ^ 2, (radius - 10) ^ 2))
		local turn = rng:NextNumber(0, math.pi * 2)
		return CFrame.new(origin + Vector3.new(math.cos(turn) * distance, 0, math.sin(turn) * distance)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	end

	-- Posición en el aire dentro de la zona de la mazmorra.
	function ctx.sky(minHeight: number, maxHeight: number, spread: number?): Vector3
		local distance = math.sqrt(rng:NextNumber(0, 1)) * (radius + (spread or 12))
		local turn = rng:NextNumber(0, math.pi * 2)
		return origin + Vector3.new(math.cos(turn) * distance, rng:NextNumber(minHeight, maxHeight), math.sin(turn) * distance)
	end
	ctx.phase = 0
	return ctx
end

-- Sala del lobby: rectángulo `width` x `depth` con el centro en `roomCF` (-Z = hacia la entrada, +Z = al fondo).
local function roomContext(model: Instance, roomCF: CFrame, width: number, depth: number, theme, level)
	local rng = Random.new()
	local ctx
	ctx = {
		model = model,
		rng = rng,
		theme = theme,
		level = level,
		torch = theme.torch or level.color,
		ringCenter = roomCF.Position + Vector3.new(0, 11, 0),
		ringRadii = { 5, 7.5 },
		edge = true,
	}
	ctx.c1, ctx.c2, ctx.material = wallLook(theme)
	ctx.leaf = ctx.c2
	local sideLength = depth - 10
	local total = width + 2 * sideLength

	function ctx.spot(zone: string, index: number, count: number): CFrame
		if zone == "edge" then
			-- Se reparten por el muro de un lado, el del fondo y el del otro lado.
			local along = ((index - 0.5) / count) * total
			local local_
			if along < sideLength then
				local_ = CFrame.lookAt(Vector3.new(-(width / 2 - 2), 0, depth / 2 - 6 - along), Vector3.new(0, 0, depth / 2 - 6 - along))
			elseif along < sideLength + width then
				local_ = CFrame.lookAt(Vector3.new(-width / 2 + (along - sideLength), 0, depth / 2 - 2.5), Vector3.new(-width / 2 + (along - sideLength), 0, 0))
			else
				local_ = CFrame.lookAt(Vector3.new(width / 2 - 2, 0, -depth / 2 + 4 + (total - along)), Vector3.new(0, 0, -depth / 2 + 4 + (total - along)))
			end
			return roomCF * local_
		end
		-- Suelo: al azar, sin pisar el altar del centro.
		for _ = 1, 8 do
			local x = rng:NextNumber(-width / 2 + 4, width / 2 - 4)
			local z = rng:NextNumber(-depth / 2 + 5, depth / 2 - 5)
			if x * x + z * z > 8 * 8 then
				return roomCF * CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			end
		end
		return roomCF * CFrame.new(width / 2 - 5, 0, depth / 2 - 5)
	end

	function ctx.sky(minHeight: number, maxHeight: number): Vector3
		return (roomCF * CFrame.new(rng:NextNumber(-width / 2 + 3, width / 2 - 3), rng:NextNumber(minHeight, maxHeight) * 0.5 + 3, rng:NextNumber(-depth / 2 + 4, depth / 2 - 4))).Position
	end
	return ctx
end

-- Adornos -------------------------------------------------------------------------------------
-- PROPS[kind](ctx, cf, spec, edge, index): `cf` = sitio en el suelo (-Z mira al centro si es del borde); `edge` = si
-- puede chocar; `index` = cuál de los `count` es.

local function solid(item: BasePart, edge: boolean)
	if not edge then
		deco(item)
	end
	return item
end

local PROPS: { [string]: (any, CFrame, any, boolean, number?) -> () } = {}

PROPS.bush = function(ctx, cf, spec, edge)
	local color = spec.color or ctx.leaf
	local size = ctx.rng:NextNumber(5, 8)
	solid(ball(ctx.model, "Bush", size, cf.Position + Vector3.new(0, size * 0.35, 0), color, Enum.Material.Grass), edge)
	deco(ball(ctx.model, "Bush", size * 0.65, cf.Position + cf:VectorToWorldSpace(Vector3.new(size * 0.5, size * 0.2, 0)), color:Lerp(WHITE, 0.08), Enum.Material.Grass))
end

PROPS.mushroom = function(ctx, cf, spec, edge)
	local height = ctx.rng:NextNumber(2.4, 4.6)
	small(cylinder(ctx.model, "Stem", height, 1.1, cf, Color3.fromRGB(236, 228, 208), Enum.Material.SmoothPlastic))
	local caps = { Color3.fromRGB(205, 76, 76), Color3.fromRGB(172, 116, 74), Color3.fromRGB(236, 214, 170) }
	local size = ctx.rng:NextNumber(3, 4.6)
	small(ball(ctx.model, "Cap", size, cf.Position + Vector3.new(0, height, 0), spec.color or caps[ctx.rng:NextInteger(1, #caps)], Enum.Material.SmoothPlastic))
end

PROPS.stump = function(ctx, cf, spec, edge)
	local height = ctx.rng:NextNumber(1.5, 2.6)
	solid(cylinder(ctx.model, "Stump", height, ctx.rng:NextNumber(3.2, 4.6), cf, spec.color or Color3.fromRGB(96, 68, 46), Enum.Material.Wood), edge)
end

PROPS.beam = function(ctx, cf, spec, edge)
	for _, side in { -1, 1 } do
		solid(part(ctx.model, "Post", Vector3.new(1.3, 15, 1.3), cf * CFrame.new(side * 5, 7.5, 0), WOOD, Enum.Material.Wood), edge)
	end
	solid(part(ctx.model, "Beam", Vector3.new(12.6, 1.3, 1.3), cf * CFrame.new(0, 15, 0), WOOD:Lerp(BLACK, 0.12), Enum.Material.Wood), edge)
	for _, side in { -1, 1 } do
		deco(part(ctx.model, "Brace", Vector3.new(0.9, 4.6, 0.9), cf * CFrame.new(side * 3.4, 13, 0) * CFrame.Angles(0, 0, math.rad(side * 38)), WOOD, Enum.Material.Wood))
	end
end

PROPS.cart = function(ctx, cf, spec, edge)
	small(part(ctx.model, "Cart", Vector3.new(5.6, 2.2, 3.4), cf * CFrame.new(0, 2.2, 0), DARK_METAL, Enum.Material.Metal))
	for _, x in { -1.8, 1.8 } do
		for _, z in { -1.8, 1.8 } do
			local wheel = part(ctx.model, "Wheel", Vector3.new(0.4, 1.8, 1.8), cf * CFrame.new(x, 0.9, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(34, 34, 40), Enum.Material.Metal)
			wheel.Shape = Enum.PartType.Cylinder
			small(wheel)
		end
	end
	for index = 1, 4 do
		small(part(ctx.model, "Ore", Vector3.one * ctx.rng:NextNumber(1, 1.7), cf * CFrame.new(ctx.rng:NextNumber(-1.8, 1.8), 3.6, ctx.rng:NextNumber(-0.9, 0.9)) * CFrame.Angles(ctx.rng:NextNumber(0, 3), ctx.rng:NextNumber(0, 3), 0), Color3.fromRGB(214, 170, 70), Enum.Material.Metal))
	end
end

PROPS.rails = function(ctx, cf, spec, edge)
	local length = 24
	for _, x in { -1.1, 1.1 } do
		small(part(ctx.model, "Rail", Vector3.new(0.35, 0.3, length), cf * CFrame.new(x, 0.35, 0), Color3.fromRGB(110, 108, 112), Enum.Material.Metal))
	end
	for index = 0, 10 do
		small(part(ctx.model, "Sleeper", Vector3.new(3.4, 0.25, 0.55), cf * CFrame.new(0, 0.15, -length / 2 + 1 + index * 2.2), WOOD, Enum.Material.Wood))
	end
end

PROPS.crystal = function(ctx, cf, spec, edge)
	local color = spec.color or ctx.torch
	for index = 1, 3 do
		local height = ctx.rng:NextNumber(4, 9) * (if index == 1 then 1.4 else 1)
		local crystal = part(
			ctx.model,
			"Crystal",
			Vector3.new(1.6, height, 1.6),
			cf * CFrame.new(ctx.rng:NextNumber(-1.6, 1.6), height / 2 - 0.4, ctx.rng:NextNumber(-1.6, 1.6)) * CFrame.Angles(math.rad(ctx.rng:NextNumber(-14, 14)), ctx.rng:NextNumber(0, 3), math.rad(ctx.rng:NextNumber(-14, 14))),
			color:Lerp(WHITE, ctx.rng:NextNumber(0, 0.25)),
			Enum.Material.Glass
		)
		crystal.Transparency = 0.12
		small(crystal)
	end
end

PROPS.coffin = function(ctx, cf, spec, edge)
	local turn = cf * CFrame.Angles(0, ctx.rng:NextNumber(-0.4, 0.4), 0)
	solid(part(ctx.model, "Coffin", Vector3.new(3, 2, 6.8), turn * CFrame.new(0, 1, 0), ctx.c2, ctx.material), edge)
	solid(part(ctx.model, "Lid", Vector3.new(3.5, 0.6, 7.3), turn * CFrame.new(0, 2.3, 0), ctx.c1:Lerp(WHITE, 0.1), ctx.material), edge)
end

PROPS.column = function(ctx, cf, spec, edge)
	local height = ctx.rng:NextNumber(9, 18)
	local color = spec.color or ctx.c1
	solid(part(ctx.model, "Base", Vector3.new(5.6, 1, 5.6), cf * CFrame.new(0, 0.5, 0), color:Lerp(BLACK, 0.12), ctx.material), edge)
	solid(cylinder(ctx.model, "Column", height, 4, cf * CFrame.new(0, 1, 0), color, ctx.material), edge)
	if height > 12 then
		solid(part(ctx.model, "Capital", Vector3.new(5.6, 1, 5.6), cf * CFrame.new(0, 1 + height + 0.5, 0), color:Lerp(BLACK, 0.12), ctx.material), edge)
	end
end

PROPS.brazier = function(ctx, cf, spec, edge)
	local color = ctx.torch
	solid(part(ctx.model, "Pedestal", Vector3.new(2, 3, 2), cf * CFrame.new(0, 1.5, 0), ctx.c2, ctx.material), edge)
	small(cylinder(ctx.model, "Bowl", 0.9, 3.4, cf * CFrame.new(0, 3, 0), DARK_METAL, Enum.Material.Metal))
	local ember = small(ball(ctx.model, "Ember", 1.5, cf.Position + Vector3.new(0, 4.3, 0), color, Enum.Material.Neon))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 28
	light.Brightness = 1.4
	light.Parent = ember
end

PROPS.bones = function(ctx, cf, spec, edge)
	for _ = 1, ctx.rng:NextInteger(3, 5) do
		small(part(ctx.model, "Bone", Vector3.new(0.5, 0.5, ctx.rng:NextNumber(1.6, 3)), cf * CFrame.new(ctx.rng:NextNumber(-3, 3), 0.3, ctx.rng:NextNumber(-3, 3)) * CFrame.Angles(0, ctx.rng:NextNumber(0, 3), 0), BONE, Enum.Material.SmoothPlastic))
	end
	small(ball(ctx.model, "Skull", 1.5, cf.Position + Vector3.new(ctx.rng:NextNumber(-1.5, 1.5), 0.75, ctx.rng:NextNumber(-1.5, 1.5)), BONE, Enum.Material.SmoothPlastic))
end

PROPS.banner = function(ctx, cf, spec, edge)
	local color = spec.color or ctx.torch
	solid(cylinder(ctx.model, "Pole", 11.6, 0.5, cf, DARK_METAL, Enum.Material.Metal), edge)
	small(part(ctx.model, "Bar", Vector3.new(4.6, 0.4, 0.4), cf * CFrame.new(0, 11, 0), DARK_METAL, Enum.Material.Metal))
	small(part(ctx.model, "Cloth", Vector3.new(3.8, 7, 0.15), cf * CFrame.new(0, 7.4, -0.3), color, Enum.Material.Fabric))
end

PROPS.lavaPool = function(ctx, cf, spec, edge)
	small(disc(ctx.model, "Lava", cf.Position + Vector3.new(0, 0.1, 0), ctx.rng:NextNumber(3.5, 6.5), 0.16, Color3.fromRGB(255, 112, 40), Enum.Material.CrackedLava))
end

PROPS.kelp = function(ctx, cf, spec, edge)
	for _ = 1, 3 do
		small(cylinder(ctx.model, "Kelp", ctx.rng:NextNumber(9, 18), 0.9, cf * CFrame.new(ctx.rng:NextNumber(-1.4, 1.4), 0, ctx.rng:NextNumber(-1.4, 1.4)) * CFrame.Angles(math.rad(ctx.rng:NextNumber(-9, 9)), 0, math.rad(ctx.rng:NextNumber(-9, 9))), spec.color or Color3.fromRGB(40, 150, 120), Enum.Material.SmoothPlastic))
	end
end

-- Roca suelta: del material del muro, salvo que sea cristal (entonces piedra oscura).
local function rock(ctx): (Color3, Enum.Material)
	local color = ctx.c1:Lerp(ctx.c2, ctx.rng:NextNumber(0, 1))
	if ctx.material == Enum.Material.Glass then
		return color:Lerp(BLACK, 0.5), Enum.Material.Slate
	end
	return color, ctx.material
end

PROPS.boulder = function(ctx, cf, spec, edge)
	local size = ctx.rng:NextNumber(4, 8)
	local color, material = rock(ctx)
	solid(part(ctx.model, "Boulder", Vector3.new(size, size * 0.8, size * 1.1), cf * CFrame.new(0, size * 0.3, 0) * CFrame.Angles(ctx.rng:NextNumber(-0.3, 0.3), ctx.rng:NextNumber(0, 3), ctx.rng:NextNumber(-0.3, 0.3)), color, material), edge)
end

PROPS.floatRock = function(ctx, cf, spec, edge)
	local size = Vector3.new(ctx.rng:NextNumber(3, 8), ctx.rng:NextNumber(2, 6), ctx.rng:NextNumber(3, 8))
	local color, material = rock(ctx)
	small(part(ctx.model, "FloatRock", size, CFrame.new(ctx.sky(8, 34)) * CFrame.Angles(ctx.rng:NextNumber(0, 3), ctx.rng:NextNumber(0, 3), ctx.rng:NextNumber(0, 3)), color, material))
end

PROPS.star = function(ctx, cf, spec, edge)
	local size = ctx.rng:NextNumber(0.5, 1.1)
	small(ball(ctx.model, "Star", size, ctx.sky(14, 50, 25), if ctx.rng:NextNumber() < 0.6 then WHITE else ctx.torch, Enum.Material.Neon))
end

-- Un anillo por adorno: con count 2 salen dos, de distinto radio y con su propia inclinación.
PROPS.orbitRing = function(ctx, cf, spec, edge, ringIndex)
	local color = spec.color or ctx.torch
	local tilt = CFrame.Angles(math.rad(ctx.rng:NextNumber(14, 30)), ctx.rng:NextNumber(0, math.pi), math.rad(ctx.rng:NextNumber(-12, 12)))
	local radius = ctx.ringRadii[ringIndex] or ctx.ringRadii[1]
	local pieces = 28
	for index = 1, pieces do
		local turn = index / pieces * math.pi * 2
		local arc = 2 * math.pi * radius / pieces
		small(part(ctx.model, "Orbit", Vector3.new(0.7, 0.7, arc + 0.3), CFrame.new(ctx.ringCenter) * tilt * CFrame.Angles(0, -turn, 0) * CFrame.new(radius, 0, 0), color, Enum.Material.Metal))
	end
end

-- Dónde van por defecto: "edge" (junto al muro), "floor" (por el suelo) o "sky" (ellos eligen su sitio en el aire).
local ZONES = {
	bush = "edge", mushroom = "floor", stump = "floor", beam = "edge", cart = "floor", rails = "floor", crystal = "edge",
	coffin = "edge", column = "edge", brazier = "edge", bones = "floor", banner = "edge", lavaPool = "floor",
	kelp = "floor", boulder = "edge", floatRock = "sky", star = "sky", orbitRing = "sky",
}

local function addProps(ctx, list)
	for _, spec in list or {} do
		local make = PROPS[spec.kind]
		if not make then
			warn(`DungeonThemes: adorno desconocido "{spec.kind}"`)
			continue
		end
		local zone = spec.zone or ZONES[spec.kind] or "edge"
		ctx.phase = ctx.rng:NextNumber(0, math.pi * 2)
		for index = 1, spec.count or 1 do
			local cf = if zone == "sky" then CFrame.new() else ctx.spot(zone, index, spec.count or 1)
			make(ctx, cf, spec, zone == "edge", index)
		end
	end
end

-- Muros ----------------------------------------------------------------------------------------
-- WALLS[estilo](ctx): una pieza o varias por cada uno de los 28 tramos del círculo; facing(i) mira al centro.

local function facing(ctx, index: number): CFrame
	local turn = (index - 1) / ctx.segments * math.pi * 2
	local outward = Vector3.new(math.cos(turn), 0, math.sin(turn))
	return CFrame.lookAt(ctx.origin + outward * (ctx.radius + 2), ctx.origin)
end

local WALLS: { [string]: (any) -> () } = {}

WALLS.stone = function(ctx)
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		local tall = index % 4 == 1
		local height = if tall then 22 else 15
		part(ctx.model, "Wall", Vector3.new(ctx.width, height, 4), at * CFrame.new(0, height / 2, 0), if index % 2 == 0 then ctx.c1 else ctx.c2, ctx.material)
		if tall then
			lantern(ctx.model, at * CFrame.new(0, 12, -3), ctx.torch, 40)
		end
	end
end

WALLS.trees = function(ctx)
	local rng = ctx.rng
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		local tall = index % 4 == 1
		local height = (if tall then 34 else 24) + rng:NextNumber(-3, 3)
		part(ctx.model, "Hedge", Vector3.new(ctx.width, 10, 5), at * CFrame.new(0, 5, 0), ctx.c2:Lerp(BLACK, 0.15), Enum.Material.Grass)
		cylinder(ctx.model, "Trunk", height, if tall then 6.6 else 5, at * CFrame.new(rng:NextNumber(-2, 2), 0, -1.5), ctx.c1, ctx.material)
		for _ = 1, 3 do
			local size = rng:NextNumber(15, 22)
			deco(ball(ctx.model, "Leaves", size, (at * CFrame.new(rng:NextNumber(-6, 6), height + rng:NextNumber(-2, 5), rng:NextNumber(-6, 4))).Position, ctx.c2:Lerp(WHITE, rng:NextNumber(0, 0.18)), Enum.Material.Grass))
		end
		if tall then
			lantern(ctx.model, at * CFrame.new(0, 7, -5), ctx.torch, 38)
		end
	end
end

WALLS.rock = function(ctx)
	local rng = ctx.rng
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		local tall = index % 4 == 1
		local height = rng:NextNumber(15, 22) + (if tall then 6 else 0)
		part(ctx.model, "Wall", Vector3.new(ctx.width + 1, height, rng:NextNumber(4, 7)), at * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), math.rad(rng:NextNumber(-2, 2))), if index % 2 == 0 then ctx.c1 else ctx.c2, ctx.material)
		if index % 3 == 0 then
			part(ctx.model, "Spire", Vector3.new(5, height + 9, 5), at * CFrame.new(rng:NextNumber(-3, 3), (height + 9) / 2, -2) * CFrame.Angles(math.rad(rng:NextNumber(-7, 7)), rng:NextNumber(0, 3), math.rad(rng:NextNumber(-7, 7))), ctx.c2, ctx.material)
		end
		if tall then
			lantern(ctx.model, at * CFrame.new(0, 11, -4), ctx.torch, 40)
		end
	end
end

WALLS.crystal = function(ctx)
	local rng = ctx.rng
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		part(ctx.model, "Base", Vector3.new(ctx.width, 7, 5), at * CFrame.new(0, 3.5, 0), ctx.c2:Lerp(BLACK, 0.55), Enum.Material.Slate)
		for k = 1, 3 do
			local height = rng:NextNumber(14, 28)
			local crystal = part(
				ctx.model,
				"Crystal",
				Vector3.new(3.4, height, 3.4),
				at * CFrame.new(rng:NextNumber(-6, 6), height / 2 + 3, rng:NextNumber(-1, 2)) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, 3), math.rad(rng:NextNumber(-12, 12))),
				if (index + k) % 2 == 0 then ctx.c1 else ctx.c2,
				Enum.Material.Glass
			)
			crystal.Transparency = 0.12
			crystal.CanCollide = false
		end
		if index % 4 == 1 then
			lantern(ctx.model, at * CFrame.new(0, 8, -3), ctx.torch, 40)
		end
	end
end

WALLS.pillars = function(ctx)
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		part(ctx.model, "Wall", Vector3.new(ctx.width, 8, 3.6), at * CFrame.new(0, 4, 0.3), if index % 2 == 0 then ctx.c1 else ctx.c2, ctx.material)
		part(ctx.model, "Rail", Vector3.new(ctx.width, 0.9, 4.4), at * CFrame.new(0, 8.4, 0.3), ctx.c1:Lerp(WHITE, 0.08), ctx.material)
		if index % 2 == 1 then
			local tall = index % 4 == 1
			local height = if tall then 30 else 24
			part(ctx.model, "Base", Vector3.new(7, 1.4, 7), at * CFrame.new(0, 0.7, -1.5), ctx.c2, ctx.material)
			cylinder(ctx.model, "Column", height, 5.2, at * CFrame.new(0, 1.4, -1.5), ctx.c1, ctx.material)
			part(ctx.model, "Capital", Vector3.new(7.4, 1.6, 7.4), at * CFrame.new(0, height + 2.2, -1.5), ctx.c2, ctx.material)
			if tall then
				lantern(ctx.model, at * CFrame.new(0, 12, -5), ctx.torch, 40)
			end
		end
	end
end

WALLS.shards = function(ctx)
	local rng = ctx.rng
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		part(ctx.model, "Curb", Vector3.new(ctx.width, 1.8, 3), at * CFrame.new(0, 0.9, 0), ctx.c2, ctx.material)
		for _ = 1, 2 do
			local size = Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(8, 20), rng:NextNumber(3, 6))
			small(part(ctx.model, "Shard", size, at * CFrame.new(rng:NextNumber(-6, 6), rng:NextNumber(5, 30), rng:NextNumber(-3, 4)) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, 3), math.rad(rng:NextNumber(-25, 25))), ctx.c1:Lerp(ctx.c2, rng:NextNumber(0, 1)), ctx.material))
		end
		if index % 4 == 1 then
			lantern(ctx.model, at * CFrame.new(0, 3, -2), ctx.torch, 38)
		end
	end
end

-- Estalactita: dos tramos que se estrechan, colgando de `from`.
local function stalactite(parent: Instance, from: Vector3, length: number, color: Color3, material: Enum.Material?)
	small(part(parent, "Stalactite", Vector3.new(3.4, length * 0.6, 3.4), CFrame.new(from - Vector3.new(0, length * 0.3, 0)), color, material))
	small(part(parent, "Stalactite", Vector3.new(1.7, length * 0.5, 1.7), CFrame.new(from - Vector3.new(0, length * 0.6 + length * 0.25, 0)), color, material))
end

-- API ------------------------------------------------------------------------------------------

function DungeonThemes.get(level)
	return Config.DungeonThemes[level.id] or FALLBACK
end

-- Apariencia de un enemigo (grunt, brute, boss) en esa zona: { name, color, look, scale }; nil campos = los de Config.Enemies.
function DungeonThemes.skin(theme, key: string)
	return if theme.enemies then theme.enemies[key] else nil
end

-- Construye la arena dentro de `model`: suelo, muro (estilo del tema), barrera invisible, techo y adornos.
function DungeonThemes.build(model: Model, origin: Vector3, radius: number, level, theme)
	theme = theme or FALLBACK
	local ctx = arenaContext(model, origin, radius, theme, level)
	local floor = theme.floor or FALLBACK.floor

	disc(model, "Floor", origin - Vector3.new(0, 2, 0), radius + 4, 4, floor.color, floor.material)
	deco(disc(model, "Ring", origin + Vector3.new(0, 0.05, 0), radius * 0.7, 0.1, floor.ring or floor.color, floor.ringMaterial or floor.material))
	deco(disc(model, "Emblem", origin + Vector3.new(0, 0.1, 0), 7, 0.1, level.color:Lerp(BLACK, 0.6), Enum.Material.Slate))

	local style = (theme.wall and theme.wall.style) or "stone"
	;(WALLS[style] or WALLS.stone)(ctx)

	-- Muro invisible desde el suelo: no se puede salir saltando ni pasar entre árboles o pilares.
	for index = 1, ctx.segments do
		local at = facing(ctx, index)
		local barrier = part(model, "Barrier", Vector3.new(ctx.width, 60, 2), at * CFrame.new(0, 30, 0), ctx.c1, ctx.material)
		barrier.Transparency = 1
		barrier.CanQuery = false
		barrier.CastShadow = false
	end

	if theme.ceiling then
		local ceiling = theme.ceiling
		local top = origin + Vector3.new(0, ceiling.height, 0)
		small(disc(model, "Ceiling", top, radius + 8, 3, ceiling.color, ceiling.material))
		for index = 1, ceiling.hang or 0 do
			local turn = ctx.rng:NextNumber(0, math.pi * 2)
			local distance = math.sqrt(ctx.rng:NextNumber(4 ^ 2, (radius - 2) ^ 2))
			stalactite(model, top + Vector3.new(math.cos(turn) * distance, -1.5, math.sin(turn) * distance), ctx.rng:NextNumber(6, 14), ceiling.color, ceiling.material)
		end
	end

	addProps(ctx, theme.props)
end

-- Adorna una sala del lobby con los adornos "room" del tema. `roomCF`: centro del suelo, -Z hacia la entrada.
function DungeonThemes.dressRoom(model: Instance, roomCF: CFrame, width: number, depth: number, level, theme)
	theme = theme or FALLBACK
	local ctx = roomContext(model, roomCF, width, depth, theme, level)
	addProps(ctx, theme.room)
end

DungeonThemes.part = part
DungeonThemes.stalactite = stalactite
DungeonThemes.disc = disc
DungeonThemes.cylinder = cylinder
DungeonThemes.ball = ball
DungeonThemes.deco = deco
DungeonThemes.small = small
DungeonThemes.lantern = lantern

return DungeonThemes
