-- Modelo de las piezas de armadura. Las mallas son de Blender (tools/blender/crear_armaduras.py), un diseño por
-- mazmorra, y cada hueco cubre varias partes del cuerpo: el casco la cabeza; la pechera el torso, los brazos y las
-- manos (hombreras, brazales, guanteletes, capa o alas); las grebas los muslos y las piernas; las botas los pies.
-- El color y el material los da la mazmorra donde cayó (Config.Dungeons: armorColor, armorMaterial, color) y los
-- remates van del color de su calidad. `attach` la suelda al personaje y `build` la deja suelta para las vistas 3D.
local Config = require(script.Parent.Config)

local ArmorModel = {}

-- Centro y tamaño de cada parte del cuerpo R15 en reposo (el personaje por defecto de Roblox, con la raíz en el
-- origen; iguales a REST del script de Blender). Las mallas vienen colocadas sobre ese cuerpo y se estiran a las
-- medidas de cada personaje.
local REST = {
	Head = { Vector3.new(0, 1.586, 0), Vector3.new(1.159, 1.182, 1.161) },
	UpperTorso = { Vector3.new(0, 0.2, 0), Vector3.new(1.943, 1.698, 1.004) },
	LowerTorso = { Vector3.new(0, -0.8, 0), Vector3.new(1.991, 0.401, 1.004) },
	LeftUpperArm = { Vector3.new(-1.5, 0.369, 0), Vector3.new(1.001, 1.242, 1.002) },
	RightUpperArm = { Vector3.new(1.5, 0.369, 0), Vector3.new(1.001, 1.242, 1.002) },
	LeftLowerArm = { Vector3.new(-1.5, -0.224, 0), Vector3.new(1.001, 1.118, 1.002) },
	RightLowerArm = { Vector3.new(1.5, -0.224, 0), Vector3.new(1.001, 1.118, 1.002) },
	LeftHand = { Vector3.new(-1.5, -0.85, 0), Vector3.new(0.984, 0.316, 1.028) },
	RightHand = { Vector3.new(1.5, -0.85, 0), Vector3.new(0.984, 0.316, 1.028) },
	LeftUpperLeg = { Vector3.new(-0.5, -1.421, 0), Vector3.new(0.993, 1.363, 0.973) },
	RightUpperLeg = { Vector3.new(0.5, -1.421, 0), Vector3.new(0.993, 1.363, 0.973) },
	LeftLowerLeg = { Vector3.new(-0.5, -2.201, 0), Vector3.new(0.993, 1.301, 0.973) },
	RightLowerLeg = { Vector3.new(0.5, -2.201, 0), Vector3.new(0.993, 1.301, 0.973) },
	LeftFoot = { Vector3.new(-0.5, -2.85, 0), Vector3.new(1.009, 0.312, 1.001) },
	RightFoot = { Vector3.new(0.5, -2.85, 0), Vector3.new(1.009, 0.312, 1.001) },
}

-- Partes del cuerpo que cubre cada hueco con las mallas.
local LIMBS = {
	helmet = { "Head" },
	chest = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand" },
	legs = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" },
	boots = { "LeftFoot", "RightFoot" },
}

-- Sin mallas (falta el archivo o ese diseño): formas hechas con piezas sobre una parte del cuerpo por lado.
local FALLBACK = {
	helmet = { "Head" },
	chest = { "UpperTorso" },
	legs = { "LeftLowerLeg", "RightLowerLeg" },
	boots = { "LeftFoot", "RightFoot" },
}

-- Formas de cada hueco sobre una parte de tamaño `s`: { tamaño, posición respecto a la parte, "base" o "trim" }.
local SHAPES = {
	helmet = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.3, s.Y * 0.62, s.Z + 0.3), CFrame.new(0, s.Y * 0.26, 0), "base" },
			{ Vector3.new(s.X + 0.42, s.Y * 0.16, s.Z + 0.42), CFrame.new(0, s.Y * 0.02, 0), "trim" },
			{ Vector3.new(0.22, s.Y * 0.5, s.Z + 0.5), CFrame.new(0, s.Y * 0.62, 0), "trim" },
		}
	end,
	chest = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.25, s.Y + 0.1, s.Z + 0.3), CFrame.new(), "base" },
			{ Vector3.new(s.X * 0.26, s.Y * 0.3, 0.2), CFrame.new(0, s.Y * 0.12, -s.Z / 2 - 0.2), "trim" },
			{ Vector3.new(s.X + 0.35, 0.22, s.Z + 0.4), CFrame.new(0, -s.Y / 2 + 0.1, 0), "trim" },
		}
	end,
	legs = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.22, s.Y * 0.9, s.Z + 0.22), CFrame.new(), "base" },
			{ Vector3.new(s.X + 0.3, 0.16, s.Z + 0.3), CFrame.new(0, -s.Y * 0.4, 0), "trim" },
		}
	end,
	boots = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.25, s.Y + 0.25, s.Z + 0.3), CFrame.new(0, 0.05, 0), "base" },
			{ Vector3.new(s.X + 0.34, 0.14, s.Z + 0.4), CFrame.new(0, s.Y / 2 + 0.12, 0), "trim" },
		}
	end,
}

type Template = { part: BasePart, role: string, offset: CFrame, size: Vector3 }

-- Mallas de Shared.ArmorMeshes: "A<mazmorra>_<hueco>_<Parte>_<Papel>", colocadas con el cuerpo en reposo (REST).
-- Se leen una vez: templates[mazmorra][hueco][parte] = lista de mallas con su posición respecto a esa parte.
local templates: { [number]: { [string]: { [string]: { Template } } } }? = nil

local function load()
	if templates then
		return templates
	end
	templates = {}
	local folder = script.Parent:FindFirstChild("ArmorMeshes")
	if not folder then
		return templates
	end
	for _, item in folder:GetDescendants() do
		local level, slot, limb, role = string.match(item.Name, "^A(%d+)_(%a+)_(%a+)_(%a+)$")
		local rest = limb and REST[limb]
		if item:IsA("BasePart") and rest then
			local byLevel = templates[tonumber(level) :: number] or {}
			templates[tonumber(level) :: number] = byLevel
			local bySlot = byLevel[slot] or {}
			byLevel[slot] = bySlot
			local list = bySlot[limb] or {}
			bySlot[limb] = list
			table.insert(list, { part = item, role = role, offset = CFrame.new(-rest[1]) * item.CFrame, size = item.Size })
		end
	end
	return templates
end

-- Color, material y transparencia de cada papel de las mallas.
local function roleLook(role: string, set, trim: Color3): (Color3, Enum.Material, number)
	if role == "Dark" then
		return set.armorColor:Lerp(Color3.new(0, 0, 0), 0.5), set.armorMaterial, 0
	elseif role == "Trim" then
		return trim, Enum.Material.SmoothPlastic, 0
	elseif role == "Gem" then
		return set.color, Enum.Material.Glass, 0.15
	elseif role == "Glow" then
		return set.color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Neon, 0.2
	elseif role == "Cloth" then
		return set.color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric, 0
	end
	return set.armorColor, set.armorMaterial, 0
end

local function newPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Crea las piezas del hueco; `place(part, limb, offset)` las coloca respecto a la parte del cuerpo `limb`, y
-- `sizeOf(limb)` da su tamaño (el del personaje, o el de REST si es una vista suelta).
local function shapes(parent: Instance, slot: string, quality: number, level: number, sizeOf, place)
	local set = Config.Dungeons[level] or Config.Dungeons[1]
	local trim = Config.Armor.Qualities[quality].color
	local design = load()[Config.Dungeons[level] and level or 1]
	local pieces = design and design[slot]
	if pieces then
		for _, limb in LIMBS[slot] do
			local size = sizeOf(limb)
			if size and pieces[limb] then
				-- Las mallas están hechas para la parte del cuerpo normal: se estiran a la del personaje.
				local scale = size / REST[limb][2]
				for _, piece in pieces[limb] do
					local rotation = piece.offset.Rotation
					local localScale = rotation:VectorToObjectSpace(scale)
					localScale = Vector3.new(math.abs(localScale.X), math.abs(localScale.Y), math.abs(localScale.Z))
					local color, material, transparency = roleLook(piece.role, set, trim)
					local part = piece.part:Clone() :: BasePart
					for _, child in part:GetChildren() do
						if child:IsA("SurfaceAppearance") then
							child:Destroy()
						end
					end
					if part:IsA("MeshPart") then
						part.TextureID = ""
					end
					part.Name = piece.role
					part.Color = color
					part.Material = material
					part.Transparency = transparency
					part.Size = piece.size * localScale
					part.Anchored = false
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.Massless = true
					part.CastShadow = piece.role ~= "Glow"
					part.Parent = parent
					place(part, limb, CFrame.new(piece.offset.Position * scale) * rotation)
				end
			end
		end
		return
	end
	for _, limb in FALLBACK[slot] do
		local size = sizeOf(limb)
		if size then
			for _, shape in SHAPES[slot](size) do
				local isTrim = shape[3] == "trim"
				local part = newPart(parent, shape[1], if isTrim then trim else set.armorColor, if isTrim then Enum.Material.SmoothPlastic else set.armorMaterial)
				place(part, limb, shape[2])
			end
		end
	end
end

-- Suelda la pieza al personaje (R15). Devuelve el Model que la contiene, o nil si no tiene esas partes.
function ArmorModel.attach(character: Model, slot: string, quality: number, level: number): Model?
	local model = Instance.new("Model")
	model.Name = "Armor_" .. slot
	model:SetAttribute("Quality", quality) -- para los brillos (client/ArmorAura)
	local function limbOf(name: string): BasePart?
		local limb = character:FindFirstChild(name)
		return if limb and limb:IsA("BasePart") then limb else nil
	end
	shapes(model, slot, quality, level, function(name)
		local limb = limbOf(name)
		return limb and limb.Size
	end, function(part, name, offset)
		local limb = limbOf(name) :: BasePart
		part.CFrame = limb.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = limb
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
	end)
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	model.Parent = character
	return model
end

-- La pieza suelta y anclada, montada como sobre el cuerpo en reposo (centrada en la raíz del personaje).
function ArmorModel.build(slot: string, quality: number, level: number, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = "Armor_" .. slot
	shapes(model, slot, quality, level, function(name)
		return REST[name][2]
	end, function(part, name, offset)
		part.Anchored = true
		part.CFrame = CFrame.new(REST[name][1]) * offset
	end)
	model.Parent = parent
	return model
end

return ArmorModel
