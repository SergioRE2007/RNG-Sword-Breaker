-- Modelos de Blender de los objetos de las parcelas (tools/blender/crear_objetos.py), importados en Studio y
-- guardados en Shared.ObjectMeshes: mallas "O<índice>_<Papel>" (índice de Config.Destructibles) y "O<índice>_Origin"
-- (centro de la caja del objeto). Las marcas Axis_* dan la escala y los ejes con los que se importaron. Se leen una
-- vez; sin el archivo, los objetos se quedan en la caja de siempre.
local ObjectModel = {}

local GOLD = Color3.fromRGB(235, 195, 90)

local templates: { [number]: { { part: BasePart, role: string, offset: CFrame, size: Vector3 } } }? = nil

local function load()
	if templates then
		return templates
	end
	templates = {}
	local folder = script.Parent:FindFirstChild("ObjectMeshes")
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
		local index = item:IsA("BasePart") and tonumber(string.match(item.Name, "^O(%d+)_Origin$"))
		if index then
			origins[index] = item
		end
	end
	for _, item in folder:GetDescendants() do
		local index, role = string.match(item.Name, "^O(%d+)_(%a+)$")
		index = tonumber(index)
		if item:IsA("BasePart") and index and role ~= "Origin" and origins[index] then
			local list = templates[index] or {}
			templates[index] = list
			table.insert(list, {
				part = item,
				role = role,
				offset = CFrame.new(frame:VectorToObjectSpace(item.Position - origins[index].Position) / studs)
					* (frame.Rotation:Inverse() * item.CFrame.Rotation),
				size = item.Size / studs,
			})
		end
	end
	return templates
end

-- Las mallas tienen mucha superficie: el neón del objeto solo se queda en la luz (Glow), el resto va liso.
local function calm(material: Enum.Material): Enum.Material
	return if material == Enum.Material.Neon then Enum.Material.SmoothPlastic else material
end

-- Color, material y transparencia de cada papel de las mallas.
local function roleLook(role: string, def): (Color3, Enum.Material, number)
	if role == "Dark" then
		return def.color:Lerp(Color3.new(0, 0, 0), 0.5), calm(def.material), 0
	elseif role == "Trim" then
		return def.color:Lerp(GOLD, 0.65), Enum.Material.Metal, 0
	elseif role == "Gem" then
		return def.color, Enum.Material.Glass, 0.15
	elseif role == "Glow" then
		return def.color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Neon, 0.2
	end
	return def.color, calm(def.material), 0
end

-- Viste la pieza del objeto `index` de Config.Destructibles con su modelo: la pieza se queda como caja invisible
-- (es la que se golpea) y las mallas van dentro de ella, quietas. Devuelve false si no hay modelo de ese objeto.
function ObjectModel.attach(part: BasePart, index: number, def): boolean
	local pieces = load()[index]
	if not pieces then
		return false
	end
	for _, piece in pieces do
		local mesh = piece.part:Clone() :: BasePart
		for _, child in mesh:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		local color, material, transparency = roleLook(piece.role, def)
		if mesh:IsA("MeshPart") then
			mesh.TextureID = ""
		end
		mesh.Name = piece.role
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Massless = true
		mesh.CastShadow = piece.role ~= "Glow"
		mesh.Color = color
		mesh.Material = material
		mesh.Transparency = transparency
		mesh.Size = piece.size
		mesh.CFrame = part.CFrame * piece.offset
		mesh.Parent = part
	end
	part.Transparency = 1
	return true
end

return ObjectModel
