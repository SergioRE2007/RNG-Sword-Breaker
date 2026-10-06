-- Modelo de las piezas de armadura, hecho con piezas (no hay modelos propios). El color y el material
-- los da la dificultad donde cayó (Config.Dungeons: armorColor, armorMaterial) y los remates van del color
-- de su calidad. `attach` la suelda al personaje y `build` la deja suelta para las vistas 3D de la interfaz.
local Config = require(script.Parent.Config)

local ArmorModel = {}

-- Partes del cuerpo (R15) que cubre cada hueco y su tamaño si no hay personaje (vistas 3D).
local LIMBS = {
	helmet = { { "Head", Vector3.new(1.2, 1.2, 1.2) } },
	chest = { { "UpperTorso", Vector3.new(2, 1.6, 1) } },
	legs = { { "LeftLowerLeg", Vector3.new(1, 1.4, 1) }, { "RightLowerLeg", Vector3.new(1, 1.4, 1) } },
	boots = { { "LeftFoot", Vector3.new(1, 0.4, 1.1) }, { "RightFoot", Vector3.new(1, 0.4, 1.1) } },
}

-- Formas de cada hueco sobre una parte de tamaño `s`: { tamaño, posición respecto a la parte, "base" o "trim" }.
local SHAPES = {
	helmet = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.3, s.Y * 0.62, s.Z + 0.3), CFrame.new(0, s.Y * 0.26, 0), "base" },
			{ Vector3.new(s.X + 0.42, s.Y * 0.16, s.Z + 0.42), CFrame.new(0, s.Y * 0.02, 0), "trim" },
			{ Vector3.new(0.22, s.Y * 0.5, s.Z + 0.5), CFrame.new(0, s.Y * 0.62, 0), "trim" },
			{ Vector3.new(0.2, s.Y * 0.45, 0.2), CFrame.new(-s.X * 0.38, s.Y * 0.1, -s.Z * 0.56), "base" },
			{ Vector3.new(0.2, s.Y * 0.45, 0.2), CFrame.new(s.X * 0.38, s.Y * 0.1, -s.Z * 0.56), "base" },
		}
	end,
	chest = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.25, s.Y + 0.1, s.Z + 0.3), CFrame.new(), "base" },
			{ Vector3.new(s.X * 0.26, s.Y * 0.3, 0.2), CFrame.new(0, s.Y * 0.12, -s.Z / 2 - 0.2), "trim" },
			{ Vector3.new(0.9, 0.5, s.Z + 0.5), CFrame.new(-s.X / 2 - 0.25, s.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.rad(18)), "base" },
			{ Vector3.new(0.9, 0.5, s.Z + 0.5), CFrame.new(s.X / 2 + 0.25, s.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.rad(-18)), "base" },
			{ Vector3.new(s.X + 0.35, 0.22, s.Z + 0.4), CFrame.new(0, -s.Y / 2 + 0.1, 0), "trim" },
		}
	end,
	legs = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.22, s.Y * 0.9, s.Z + 0.22), CFrame.new(), "base" },
			{ Vector3.new(s.X * 0.6, s.Y * 0.3, 0.25), CFrame.new(0, s.Y * 0.38, -s.Z / 2 - 0.15), "trim" },
			{ Vector3.new(s.X + 0.3, 0.16, s.Z + 0.3), CFrame.new(0, -s.Y * 0.4, 0), "trim" },
		}
	end,
	boots = function(s: Vector3)
		return {
			{ Vector3.new(s.X + 0.25, s.Y + 0.25, s.Z + 0.3), CFrame.new(0, 0.05, 0), "base" },
			{ Vector3.new(s.X + 0.1, s.Y * 0.8, 0.45), CFrame.new(0, -0.05, -s.Z / 2 - 0.3), "base" },
			{ Vector3.new(s.X + 0.34, 0.14, s.Z + 0.4), CFrame.new(0, s.Y / 2 + 0.12, 0), "trim" },
		}
	end,
}

-- Modelos de Blender (tools/blender/crear_armaduras.py), importados en Studio y guardados en Shared.ArmorMeshes:
-- mallas "A<mazmorra>_<hueco>_<Papel>" y "A<mazmorra>_<hueco>_Origin" (centro de la parte del cuerpo). Las marcas
-- Axis_* dan la escala y los ejes de la importación. Se leen una vez; sin el archivo (o sin ese diseño) la pieza se
-- hace con las formas de SHAPES.
local templates: { [number]: { [string]: { { part: BasePart, role: string, offset: CFrame, size: Vector3 } } } }? = nil

local function load()
	if templates then
		return templates
	end
	templates = {}
	local folder = script.Parent:FindFirstChild("ArmorMeshes")
	local axis = folder and folder:FindFirstChild("Axis_Origin", true) :: BasePart?
	local up = folder and folder:FindFirstChild("Axis_Up", true) :: BasePart?
	local front = folder and folder:FindFirstChild("Axis_Front", true) :: BasePart?
	if not (axis and up and front) then
		return templates
	end
	local upVector = up.Position - axis.Position
	local studs = upVector.Magnitude / 2 -- lo que mide un stud en la importación
	local back = (axis.Position - front.Position).Unit
	local frame = CFrame.fromMatrix(Vector3.zero, upVector.Unit:Cross(back), upVector.Unit, back)

	local origins = {}
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") and string.match(item.Name, "^A%d+_%a+_Origin$") then
			origins[item.Name] = item
		end
	end
	for _, item in folder:GetDescendants() do
		local level, slot, role = string.match(item.Name, "^A(%d+)_(%a+)_(%a+)$")
		local origin = level and origins[`A{level}_{slot}_Origin`]
		if item:IsA("BasePart") and origin and role ~= "Origin" then
			local byLevel = templates[tonumber(level) :: number] or {}
			templates[tonumber(level) :: number] = byLevel
			local list = byLevel[slot] or {}
			byLevel[slot] = list
			table.insert(list, {
				part = item,
				role = role,
				offset = CFrame.new(frame:VectorToObjectSpace(item.Position - origin.Position) / studs)
					* (frame.Rotation:Inverse() * item.CFrame.Rotation),
				size = item.Size / studs,
			})
		end
	end
	return templates
end

-- Cuánto se suben las mallas sobre la parte del cuerpo (en studs del modelo): el casco y las grebas se veían
-- demasiado bajos en el personaje de verdad.
local LIFT = { helmet = 0.3, legs = 0.95, boots = -0.12 }

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

-- Crea las formas del hueco sobre una parte de tamaño `size`; `place(part, offset)` las coloca.
local function shapes(parent: Instance, slot: string, quality: number, level: number, size: Vector3, place)
	local set = Config.Dungeons[level] or Config.Dungeons[1]
	local trim = Config.Armor.Qualities[quality].color
	local pieces = load()[Config.Dungeons[level] and level or 1]
	pieces = pieces and pieces[slot]
	if pieces then
		-- Las mallas están hechas para el tamaño normal de la parte del cuerpo: se estiran a la del personaje.
		local scale = size / LIMBS[slot][1][2]
		for _, piece in pieces do
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
			part.Size = piece.size * scale
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = piece.role ~= "Glow"
			part.Parent = parent
			place(part, CFrame.new(piece.offset.Position * scale + Vector3.new(0, (LIFT[slot] or 0) * scale.Y, 0)) * piece.offset.Rotation)
		end
		return
	end
	for _, shape in SHAPES[slot](size) do
		local isTrim = shape[3] == "trim"
		local part = newPart(parent, shape[1], if isTrim then trim else set.armorColor, if isTrim then Enum.Material.SmoothPlastic else set.armorMaterial)
		place(part, shape[2])
	end
end

-- Suelda la pieza al personaje (R15). Devuelve el Model que la contiene, o nil si no tiene esas partes.
function ArmorModel.attach(character: Model, slot: string, quality: number, level: number): Model?
	local model = Instance.new("Model")
	model.Name = "Armor_" .. slot
	model:SetAttribute("Quality", quality) -- para los brillos (client/ArmorAura)
	for _, limbInfo in LIMBS[slot] do
		local limb = character:FindFirstChild(limbInfo[1])
		if limb and limb:IsA("BasePart") then
			shapes(model, slot, quality, level, limb.Size, function(part, offset)
				part.CFrame = limb.CFrame * offset
				local weld = Instance.new("Weld")
				weld.Part0 = limb
				weld.Part1 = part
				weld.C0 = offset
				weld.Parent = part
			end)
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	model.Parent = character
	return model
end

-- La pieza suelta y anclada, centrada más o menos en el origen (las de dos lados, una junto a otra).
function ArmorModel.build(slot: string, quality: number, level: number, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = "Armor_" .. slot
	local limbs = LIMBS[slot]
	for index, limbInfo in limbs do
		local base = CFrame.new(if #limbs > 1 then (index - 1.5) * 1.5 else 0, 0, 0)
		shapes(model, slot, quality, level, limbInfo[2], function(part, offset)
			part.Anchored = true
			part.CFrame = base * offset
		end)
	end
	model.Parent = parent
	return model
end

return ArmorModel
