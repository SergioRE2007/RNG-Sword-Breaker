-- Construye el modelo de un arma con piezas, según su tipo: espada, espadas dobles, hacha, lanza o martillo.
-- Lo usan el servidor (el arma en la mano) y el decorado (expositor del hub).
-- Ejes de la empuñadura: el arma sube por +Y, es ancha en Z y fina en X; -Z es hacia donde mira el jugador.
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local MeshWeapon = require(script.Parent.MeshWeapon)

local SwordModel = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local LEATHER = Color3.fromRGB(70, 45, 30)
local WOOD = Color3.fromRGB(110, 75, 45)
local STEEL = Color3.fromRGB(75, 78, 88)
local GOLD = Color3.fromRGB(235, 190, 60)

local GLOWING = { [Enum.Material.Neon] = true, [Enum.Material.ForceField] = true }

local FANCY_FROM = 10 -- rareza desde la que el arma lleva adornos dorados y gema
local SHARDS_FROM = 1e7 -- rareza desde la que flotan esquirlas junto a la hoja

local BLADE_BASE = 0.84 -- altura a la que empieza la hoja de una espada sobre el centro de la empuñadura

type Add = (className: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, template: BasePart?) -> BasePart

-- Devuelve la función que va añadiendo piezas. La primera es la raíz y las demás se sueldan a ella.
-- `anchored` = pieza de decorado: ancladas y sin soldar. Con `template` se copia esa pieza (una malla importada).
local function builder(parent: Instance, origin: CFrame, scale: number, anchored: boolean): Add
	local root: BasePart? = nil
	return function(className, name, size, offset, color, material, template)
		local part = if template then template:Clone() else Instance.new(className) :: BasePart
		part.Name = name
		part.Size = size * scale
		part.CFrame = origin * (CFrame.new(offset.Position * scale) * offset.Rotation)
		part.Color = color
		part.Material = material
		part.Anchored = anchored
		part.CanCollide = false
		part.Massless = true
		part.CastShadow = root == nil
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if root then
			part.CanTouch = false
			part.CanQuery = false
			if not anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		else
			root = part
		end
		part.Parent = parent
		return part
	end
end

local function look(def)
	local rarity = def.rarity or 0
	local starter = def.rarity == nil
	local fancy = rarity >= FANCY_FROM
	return {
		glowing = GLOWING[def.material] == true,
		fancy = fancy,
		shards = rarity >= SHARDS_FROM,
		width = 0.62 + 0.016 * math.log10(math.max(rarity, 1)),
		edgeColor = def.color:Lerp(WHITE, 0.45),
		darkColor = def.color:Lerp(BLACK, 0.35),
		trimColor = if starter then WOOD elseif fancy then GOLD else STEEL,
		trimMaterial = if starter then Enum.Material.Wood else Enum.Material.Metal,
		gripMaterial = if starter then Enum.Material.Wood else Enum.Material.Fabric,
	}
end

local function ball(add: Add, name: string, diameter: number, y: number, color: Color3, material: Enum.Material)
	local part = add("Part", name, Vector3.new(diameter, diameter, diameter), CFrame.new(0, y, 0), color, material) :: Part
	part.Shape = Enum.PartType.Ball
end

-- Empuñadura con vueltas de cuero: es la raíz del arma.
local function grip(add: Add, name: string, style): BasePart
	local handle = add("Part", name, Vector3.new(0.32, 1.2, 0.32), CFrame.identity, LEATHER, style.gripMaterial)
	for _, y in { -0.32, 0, 0.32 } do
		add("Part", "Wrap", Vector3.new(0.38, 0.1, 0.38), CFrame.new(0, y, 0), LEATHER:Lerp(BLACK, 0.4), Enum.Material.Fabric)
	end
	return handle
end

-- Punta: dos cuñas espalda con espalda que cierran una capa de la hoja.
local function tip(add: Add, name: string, baseY: number, thickness: number, width: number, height: number, color: Color3, material: Enum.Material)
	local y = baseY + height / 2
	local size = Vector3.new(thickness, height, width / 2)
	add("WedgePart", name, size, CFrame.new(0, y, -width / 4), color, material)
	add("WedgePart", name, size, CFrame.new(0, y, width / 4) * CFrame.Angles(0, math.pi, 0), color, material)
end

-- Hoja recta desde baseY: cuerpo grueso, filo más ancho y fino, nervio central y punta.
local function straightBlade(add: Add, def, style, baseY: number, length: number, width: number): BasePart
	local center = CFrame.new(0, baseY + length / 2, 0)
	local coreWidth = width * 0.62
	local blade = add("Part", "Blade", Vector3.new(0.2, length, coreWidth), center, def.color, def.material)
	add("Part", "Edge", Vector3.new(0.08, length, width), center, style.edgeColor, def.material)
	add("Part", "Fuller", Vector3.new(0.27, length * 0.7, width * 0.16), CFrame.new(0, baseY + length * 0.38, 0), if style.glowing then style.edgeColor else style.darkColor, def.material)
	tip(add, "Tip", baseY + length, 0.2, coreWidth, coreWidth * 1.3, def.color, def.material)
	tip(add, "EdgeTip", baseY + length, 0.08, width, width * 1.3, style.edgeColor, def.material)
	return blade
end

local function sword(add: Add, def, style, rootName: string): (BasePart, BasePart)
	local handle = grip(add, rootName, style)
	ball(add, "Pommel", 0.5, -0.78, style.trimColor, style.trimMaterial)

	local guardLength = if style.fancy then 1.9 else 1.5
	add("Part", "Guard", Vector3.new(0.34, 0.24, guardLength), CFrame.new(0, 0.72, 0), style.trimColor, style.trimMaterial)
	for _, side in { -1, 1 } do
		add("Part", "GuardCap", Vector3.new(0.42, 0.36, 0.25), CFrame.new(0, 0.72, side * guardLength / 2), style.trimColor, style.trimMaterial)
		if style.fancy then
			add("Part", "GuardHorn", Vector3.new(0.3, 0.6, 0.2), CFrame.new(0, 1.02, side * (guardLength / 2 + 0.06)) * CFrame.Angles(side * math.rad(25), 0, 0), style.trimColor, style.trimMaterial)
		end
	end
	if style.fancy then
		ball(add, "Gem", 0.46, 0.72, def.color, if style.glowing then Enum.Material.Neon else Enum.Material.Glass)
	end

	local length = def.bladeLength
	local blade = straightBlade(add, def, style, BLADE_BASE, length, style.width)
	if style.shards then
		for index, height in { 0.22, 0.42 } do
			for _, side in { -1, 1 } do
				local offset = CFrame.new(0, BLADE_BASE + length * height, side * (style.width / 2 + 0.4)) * CFrame.Angles(side * math.rad(-18), 0, 0)
				add("Part", "Shard", Vector3.new(0.1, 1 - index * 0.25, 0.22), offset, style.edgeColor, Enum.Material.Neon)
			end
		end
	end
	return handle, blade
end

-- Hacha: mango largo y cabeza arriba con el filo hacia delante. Las que brillan tienen doble filo.
local function axe(add: Add, def, style): (BasePart, BasePart)
	local handle = grip(add, "Handle", style)
	local shaft = def.bladeLength + 1.2
	local bottom = -0.9
	local top = bottom + shaft
	add("Part", "Shaft", Vector3.new(0.24, shaft, 0.24), CFrame.new(0, bottom + shaft / 2, 0), WOOD, Enum.Material.Wood)
	ball(add, "Pommel", 0.42, bottom, style.trimColor, style.trimMaterial)

	local k = 0.9 + shaft * 0.06 -- tamaño de la cabeza
	local y = top - 0.8 * k
	add("Part", "Socket", Vector3.new(0.42, 1.0 * k, 0.42), CFrame.new(0, y, 0), style.trimColor, style.trimMaterial)
	tip(add, "Spike", top, 0.2, 0.3, 0.6 * k, style.trimColor, style.trimMaterial)

	local blade: BasePart
	local function head(side: number, name: string): BasePart
		add("Part", "Cheek", Vector3.new(0.22, 0.9 * k, 0.7 * k), CFrame.new(0, y, side * (0.2 + 0.35 * k)), def.color, def.material)
		local body = add("Part", name, Vector3.new(0.16, 1.5 * k, 0.45 * k), CFrame.new(0, y, side * (0.2 + 0.9 * k)), def.color, def.material)
		add("Part", "Edge", Vector3.new(0.07, 1.9 * k, 0.3 * k), CFrame.new(0, y, side * (0.2 + 1.23 * k)), style.edgeColor, def.material)
		return body
	end
	blade = head(-1, "Blade")
	if style.glowing then
		head(1, "BackBlade")
	else
		add("Part", "BackSpike", Vector3.new(0.2, 0.35 * k, 0.4 * k), CFrame.new(0, y, 0.2 + 0.2 * k), style.trimColor, style.trimMaterial)
	end
	return handle, blade
end

-- Martillo: mango largo y cabeza de bloque con remates (el golpe lo da el extremo de la cabeza, hacia -Z).
-- Los que brillan llevan una veta de energía; los raros, pinchos y una gema encima.
local function hammer(add: Add, def, style): (BasePart, BasePart)
	local handle = grip(add, "Handle", style)
	local shaft = def.bladeLength + 1.4
	local bottom = -0.9
	local top = bottom + shaft
	add("Part", "Shaft", Vector3.new(0.26, shaft, 0.26), CFrame.new(0, bottom + shaft / 2, 0), WOOD, Enum.Material.Wood)
	ball(add, "Pommel", 0.46, bottom, style.trimColor, style.trimMaterial)

	local k = 0.85 + shaft * 0.08 -- tamaño de la cabeza
	local y = top - 0.35 * k
	add("Part", "Socket", Vector3.new(0.5, 0.9 * k, 0.5), CFrame.new(0, y, 0), style.trimColor, style.trimMaterial)
	local head = add("Part", "Blade", Vector3.new(1.0 * k, 1.1 * k, 2.2 * k), CFrame.new(0, y, 0), def.color, def.material)
	for _, side in { -1, 1 } do
		add("Part", "Cap", Vector3.new(1.12 * k, 1.22 * k, 0.32 * k), CFrame.new(0, y, side * 1.1 * k), style.trimColor, style.trimMaterial)
	end
	add("Part", "Band", Vector3.new(1.06 * k, 0.2 * k, 1.5 * k), CFrame.new(0, y + 0.3 * k, 0), if style.glowing then style.edgeColor else style.darkColor, def.material)
	if style.fancy then
		tip(add, "Spike", y + 0.55 * k, 0.4, 0.5, 0.9 * k, style.trimColor, style.trimMaterial)
		ball(add, "Gem", 0.4 * k, y, def.color, if style.glowing then Enum.Material.Neon else Enum.Material.Glass)
	end
	return handle, head
end

-- Lanza: asta larga agarrada a un tercio, con punta corta arriba.
local function spear(add: Add, def, style): (BasePart, BasePart)
	local handle = grip(add, "Handle", style)
	local shaft = def.bladeLength
	local bottom = -0.3 * shaft
	local top = bottom + shaft
	add("Part", "Shaft", Vector3.new(0.24, shaft, 0.24), CFrame.new(0, bottom + shaft / 2, 0), WOOD, Enum.Material.Wood)
	ball(add, "Butt", 0.4, bottom, style.trimColor, style.trimMaterial)
	add("Part", "Tassel", Vector3.new(0.36, 0.5, 0.36), CFrame.new(0, top - 0.55, 0), def.color, Enum.Material.Fabric)
	add("Part", "Collar", Vector3.new(0.42, 0.35, 0.42), CFrame.new(0, top, 0), style.trimColor, style.trimMaterial)
	local blade = straightBlade(add, def, style, top + 0.15, 1.5, style.width * 1.15)
	return handle, blade
end

-- Arma con malla propia (`mesh` en Config.Swords): aquí solo van la empuñadura y un bloque del tamaño de la hoja,
-- invisibles (sirven para agarrarla, la estela y el aura). La malla la pone MeshWeapon en cada cliente.
local function meshed(add: Add, def, scale: number, anchored: boolean, metal: number?): (BasePart, BasePart)
	local proxy = MeshWeapon.data(def.mesh).proxy
	local handle = add("Part", "Handle", proxy.grip, CFrame.identity, LEATHER, Enum.Material.Fabric)
	local blade = add("Part", "Blade", proxy.blade, CFrame.new(0, proxy.bladeY, 0), def.color, def.material)
	for _, part in { handle, blade } do
		part.Transparency = 1
		part.CastShadow = false
		part:SetAttribute("MeshProxy", true)
	end
	handle:SetAttribute("Mesh", def.mesh)
	handle:SetAttribute("MeshScale", scale)
	handle:SetAttribute("MeshMetal", metal or 0)
	-- Las de adorno (vistas 3D, tiradas) se visten aquí mismo. Las que se mueven (las que giran alrededor del jugador)
	-- llevan la etiqueta, y client/WeaponMesh las viste y anima sus piezas sueltas.
	if RunService:IsClient() and anchored then
		MeshWeapon.attach(handle, anchored)
	else
		handle:AddTag(MeshWeapon.TAG)
	end
	return handle, blade
end

-- Modelos de Blender (tools/blender/crear_armas.py), importados en Studio y guardados en Shared.WeaponMeshes:
-- piezas "W<índice>_<Papel>" y "W<índice>_Origin" (centro de la empuñadura). Las marcas Axis_* dan la escala y
-- los ejes con los que se importaron. Se leen una vez; sin el archivo, las armas se siguen haciendo con piezas.
local meshTemplates: { [number]: { { part: BasePart, role: string, offset: CFrame, size: Vector3 } } }? = nil

local function loadMeshes()
	if meshTemplates then
		return meshTemplates
	end
	meshTemplates = {}
	local folder = script.Parent:FindFirstChild("WeaponMeshes")
	local axis = folder and folder:FindFirstChild("Axis_Origin", true) :: BasePart?
	local up = folder and folder:FindFirstChild("Axis_Up", true) :: BasePart?
	local front = folder and folder:FindFirstChild("Axis_Front", true) :: BasePart?
	if not (axis and up and front) then
		return meshTemplates
	end
	local upVector = up.Position - axis.Position
	local studs = upVector.Magnitude / 2 -- lo que mide un stud en la importación
	local back = (axis.Position - front.Position).Unit
	local frame = CFrame.fromMatrix(Vector3.zero, upVector.Unit:Cross(back), upVector.Unit, back)

	local origins = {}
	for _, item in folder:GetDescendants() do
		local index = item:IsA("BasePart") and tonumber(string.match(item.Name, "^W(%d+)_Origin$"))
		if index then
			origins[index] = item
		end
	end
	for _, item in folder:GetDescendants() do
		local index, role = string.match(item.Name, "^W(%d+)_(%a+)$")
		index = tonumber(index)
		if item:IsA("BasePart") and index and role ~= "Origin" and origins[index] then
			local list = meshTemplates[index] or {}
			meshTemplates[index] = list
			table.insert(list, {
				part = item,
				role = role,
				offset = CFrame.new(frame:VectorToObjectSpace(item.Position - origins[index].Position) / studs)
					* (frame.Rotation:Inverse() * item.CFrame.Rotation),
				size = item.Size / studs,
			})
		end
	end
	-- La hoja va primero: la pieza "Blade" es la que lleva aura y estela.
	for _, list in meshTemplates do
		table.sort(list, function(a, b)
			return (a.role == "Blade") and not (b.role == "Blade")
		end)
	end
	return meshTemplates
end

-- Las mallas tienen mucha más superficie que las piezas: en neón deslumbran (pedido por el usuario bajarlo),
-- así que solo brilla el filo y los adornos de luz van medio transparentes.
local GLOW_TRANSPARENCY = 0.4

local function calm(material: Enum.Material): Enum.Material
	return if material == Enum.Material.Neon then Enum.Material.SmoothPlastic else material
end

-- Color y material de cada papel de las mallas, con el mismo estilo que las armas hechas con piezas.
local function roleLook(role: string, def, style): (Color3, Enum.Material)
	if role == "Blade" then
		return def.color, calm(def.material)
	elseif role == "Edge" then
		return style.edgeColor, def.material
	elseif role == "Dark" then
		return if style.glowing then style.edgeColor else style.darkColor, calm(def.material)
	elseif role == "Trim" then
		return style.trimColor, style.trimMaterial
	elseif role == "Grip" then
		return LEATHER, style.gripMaterial
	elseif role == "Wood" then
		return WOOD, Enum.Material.Wood
	elseif role == "Gem" then
		return def.color, Enum.Material.Glass
	elseif role == "Glow" then
		return style.edgeColor, Enum.Material.Neon
	elseif role == "Cloth" then
		return def.color, Enum.Material.Fabric
	end
	return def.color, def.material
end

-- Arma hecha con las mallas de Blender: una empuñadura invisible como raíz y las mallas soldadas a ella.
local function imported(add: Add, def, style, pieces, rootName: string): (BasePart, BasePart)
	local handle = add("Part", rootName, Vector3.new(0.32, 1.2, 0.32), CFrame.identity, LEATHER, Enum.Material.Fabric)
	handle.Transparency = 1
	local blade: BasePart? = nil
	for _, piece in pieces do
		local color, material = roleLook(piece.role, def, style)
		local name = if piece.role == "Blade" and not blade then "Blade" else piece.role
		local part = add("MeshPart", name, piece.size, piece.offset, color, material, piece.part) :: MeshPart
		-- Lo que traiga de la importación (texturas, apariencia) taparía el color del arma.
		part.TextureID = ""
		if piece.role == "Glow" then
			part.Transparency = GLOW_TRANSPARENCY
		end
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		blade = blade or part
	end
	return handle, blade or handle
end

-- Luz y chispas en las armas que brillan, y la estela del tajo (el cliente la enciende mientras dura el golpe).
local function effects(blade: BasePart, level: number, def, style, scale: number, anchored: boolean)
	-- El aura la pone cada cliente (client/WeaponAura) en las hojas con la etiqueta "WeaponAura": allí se decide
	-- qué armas la llevan (de Épica para arriba) y cómo es la de cada una (client/WeaponAuraDefs).
	blade:SetAttribute("Level", level)
	blade:SetAttribute("Scale", scale)
	blade:AddTag("WeaponAura")

	if style.glowing then
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Range = 7 * scale
		light.Brightness = 0.7
		light.Parent = blade

		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Color = ColorSequence.new(style.edgeColor)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.18 * scale, 0)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(0.5, 0.9)
		sparks.Speed = NumberRange.new(0.3, 1)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 8
		sparks.Parent = blade
	end

	if not anchored then
		local half = blade.Size.Y / 2
		local base = Instance.new("Attachment")
		base.Name = "TrailBase"
		base.Position = Vector3.new(0, -half * 0.8, 0)
		base.Parent = blade
		local point = Instance.new("Attachment")
		point.Name = "TrailTip"
		point.Position = Vector3.new(0, half + style.width * scale, 0)
		point.Parent = blade

		local trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = base
		trail.Attachment1 = point
		trail.Color = ColorSequence.new(style.edgeColor, def.color)
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.Lifetime = 0.16
		trail.LightEmission = 0.6
		trail.Enabled = false
		trail.Parent = blade
	end
end

-- Devuelve la empuñadura ("Handle") y la hoja principal ("Blade").
-- Las espadas dobles llevan la segunda en un Model "OffHand" con raíz "OffHandle", para soldarla a la mano izquierda.
function SwordModel.build(level: number, parent: Instance, origin: CFrame, scale: number, anchored: boolean, metal: number?): (BasePart, BasePart)
	local def = Config.Swords[level]
	-- Con un metal (Config.Metals) el arma toma su color y su material.
	local metalDef = if metal and metal > 0 then Config.Metals[metal] else nil
	if metalDef then
		def = table.clone(def)
		def.color = metalDef.color
		def.material = metalDef.material
	end
	local kind = def.kind or "sword"
	local style = look(def)
	local add = builder(parent, origin, scale, anchored)

	local pieces = loadMeshes()[level]
	local handle, blade
	if def.mesh then
		handle, blade = meshed(add, def, scale, anchored, metal)
	elseif pieces then
		handle, blade = imported(add, def, style, pieces, "Handle")
	elseif kind == "axe" then
		handle, blade = axe(add, def, style)
	elseif kind == "spear" then
		handle, blade = spear(add, def, style)
	elseif kind == "hammer" then
		handle, blade = hammer(add, def, style)
	else
		handle, blade = sword(add, def, style, "Handle")
	end
	effects(blade, level, def, style, scale, anchored)

	if kind == "dual" then
		local offHand = Instance.new("Model")
		offHand.Name = "OffHand"
		offHand.Parent = parent
		-- En el expositor se enseña al lado de la primera; en la mano la coloca la soldadura.
		local offOrigin = origin * CFrame.new(0, 0, 2.2 * scale) * CFrame.Angles(math.rad(12), 0, 0)
		local offAdd = builder(offHand, offOrigin, scale, anchored)
		local _, offBlade
		if pieces then
			_, offBlade = imported(offAdd, def, style, pieces, "OffHandle")
		else
			_, offBlade = sword(offAdd, def, style, "OffHandle")
		end
		effects(offBlade, level, def, style, scale, anchored)
	end

	return handle, blade
end

return SwordModel
