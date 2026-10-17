-- Aspecto de la parcela según los renacimientos de su dueño (Config.PlotLooks; pedido por el usuario: cambia poco a
-- poco, y habrá 20 o más). Librería sin start(): server/Plots pide el aspecto con PlotLooks.get y, cada vez que monta
-- la parcela, le pone sus piezas con PlotLooks.build. Lo que va en el suelo ("border") y en el muro ("gold") lo pinta
-- Plots al montarlos con los colores de aquí; lo demás son piezas de BUILDERS, siempre en el muro o por fuera de él
-- para no quitar sitio a los objetos.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropModel = require(ReplicatedStorage.Shared.PropModel)

local PlotLooks = {}

PlotLooks.BORDER = { Color3.fromRGB(182, 176, 198), Color3.fromRGB(166, 160, 184) } -- marco de losas del "border"
PlotLooks.GOLD = Color3.fromRGB(255, 200, 70) -- remates del muro con "gold"

local POLE = Color3.fromRGB(70, 48, 40)

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function decor(part: Part): Part
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Aspecto con esos renacimientos: { level, floor (dos tonos o nil = el de siempre), has = { [pieza] = true } }.
function PlotLooks.get(rebirths: number)
	local level = math.clamp(rebirths, 0, #Config.PlotLooks)
	local look = { level = level, has = {} }
	for index = 1, level do
		local entry = Config.PlotLooks[index]
		look.floor = entry.floor or look.floor
		for _, name in entry.add or {} do
			look.has[name] = true
		end
	end
	return look
end

-- Cada pieza recibe ctx = { model, cframe (centro de la parcela, -Z mira al hub), half, color (el de la parcela), post
-- (altura de lo alto de los pilares del muro) }.
local BUILDERS = {}

-- Estandartes (nobori) del color de la parcela, uno junto a cada esquina, sobre el pilar de al lado de la linterna.
function BUILDERS.banners(ctx)
	local half = ctx.half
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local base = ctx.cframe * CFrame.new(corner.X * (half - 10), ctx.post, corner.Y * half)
		-- La tela mira hacia fuera, en diagonal.
		local facing = CFrame.lookAt(base.Position, (ctx.cframe * CFrame.new(corner.X * (half + 10), ctx.post, corner.Y * (half + 10))).Position)
		decor(block(ctx.model, "BannerPole", Vector3.new(0.35, 11, 0.35), base * CFrame.new(0, 5.5, 0), POLE))
		decor(block(ctx.model, "BannerTip", Vector3.new(0.7, 0.7, 0.7), base * CFrame.new(0, 11.2, 0), PlotLooks.GOLD, Enum.Material.Metal)).Shape = Enum.PartType.Ball
		local cloth = facing.Rotation + (base * CFrame.new(0, 7.4, 0)).Position
		decor(block(ctx.model, "BannerArm", Vector3.new(0.2, 0.2, 2.6), cloth * CFrame.new(0, 3.1, 1.3), POLE))
		decor(block(ctx.model, "Banner", Vector3.new(0.12, 6, 2.4), cloth * CFrame.new(0, 0, 1.4), ctx.color, Enum.Material.Fabric))
		decor(block(ctx.model, "BannerBand", Vector3.new(0.16, 0.6, 2.4), cloth * CFrame.new(0, 2.2, 1.4), Color3.fromRGB(255, 250, 242), Enum.Material.Fabric))
	end
end

-- Jardín: bambú por fuera de las dos esquinas de atrás y dos bonsáis a los lados de la entrada.
function BUILDERS.garden(ctx)
	local half = ctx.half
	for _, side in { -1, 1 } do
		PropModel.place(ctx.model, "Bamboo", ctx.cframe * CFrame.new(side * (half + 4), -Config.Plot.FloorHeight, half + 4) * CFrame.Angles(0, side, 0), 1.1)
		PropModel.place(ctx.model, "Bonsai", ctx.cframe * CFrame.new(side * 14, -Config.Plot.FloorHeight, -half - 3), 1.2)
	end
end

-- Torii en la entrada, con farolillos del color de la parcela.
function BUILDERS.torii(ctx)
	local scale = 10 / 6.55 -- columnas a 10 del centro: por fuera de los pilares de la entrada
	local gate = ctx.cframe * CFrame.new(0, -Config.Plot.FloorHeight, -ctx.half - 4) * CFrame.Angles(0, math.pi, 0)
	if PropModel.place(ctx.model, "Torii", gate, scale) then
		for _, sign in { 1, -1 } do
			PropModel.place(ctx.model, "Chochin", gate * CFrame.new(sign * 6.3, 9.15 * scale - 2.73, 0), 1.3, { Red = ctx.color })
		end
	end
end

-- Pone las piezas de `look` en ctx.model.
function PlotLooks.build(ctx, look)
	for name, builder in BUILDERS do
		if look.has[name] then
			builder(ctx)
		end
	end
end

-- Linterna de piedra encendida de noche (como las del decorado: la luz la pone el cliente con NightLight).
function PlotLooks.lantern(parent: Instance, cframe: CFrame, scale: number, brightness: number, range: number)
	local model = PropModel.place(parent, "StoneLantern", cframe, scale)
	local paper = model and model:FindFirstChild("Paper")
	if paper then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light:SetAttribute("Base", brightness)
		light.Brightness = 0
		light.Enabled = false
		light.Range = range
		light.Parent = paper
		CollectionService:AddTag(paper, "LanternGlow")
		CollectionService:AddTag(light, "NightLight")
	end
end

PlotLooks.BUILDERS = BUILDERS

return PlotLooks
