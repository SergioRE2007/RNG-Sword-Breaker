-- Piezas del mapa del bosque japonés hechas en Blender (tools/blender/crear_mapa_japones.py), importadas en Studio y
-- guardadas en Shared.MapMeshes: mallas "<Pieza>_<Papel>" y "<Pieza>_Origin" (centro del suelo de la pieza). Las
-- marcas Axis_* dan la escala y los ejes de la importación. Se leen una vez; sin el archivo `place` devuelve nil y el
-- mapa se queda sin esas piezas (suelo, luz y agua siguen).
local PropModel = {}

type Piece = { part: BasePart, role: string, offset: CFrame, size: Vector3 }
local templates: { [string]: { Piece } }? = nil

local function load()
	if templates then
		return templates
	end
	templates = {}
	local folder = script.Parent:FindFirstChild("MapMeshes")
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
		local name = item:IsA("BasePart") and string.match(item.Name, "^(%a+)_Origin$")
		if name and name ~= "Axis" then
			origins[name] = item
		end
	end
	for _, item in folder:GetDescendants() do
		local name, role = string.match(item.Name, "^(%a+)_(%a+)$")
		if item:IsA("BasePart") and name and role ~= "Origin" and origins[name] then
			local list = templates[name] or {}
			templates[name] = list
			table.insert(list, {
				part = item,
				role = role,
				offset = CFrame.new(frame:VectorToObjectSpace(item.Position - origins[name].Position) / studs)
					* (frame.Rotation:Inverse() * item.CFrame.Rotation),
				size = item.Size / studs,
			})
		end
	end
	return templates
end

-- Color y material de cada papel: colores vivos y de dibujo animado, sin neón salvo en el papel de las linternas.
local LOOKS = {
	Wood = { Color3.fromRGB(150, 98, 62), Enum.Material.SmoothPlastic, 0 },
	Red = { Color3.fromRGB(238, 52, 62), Enum.Material.SmoothPlastic, 0 },
	Pink = { Color3.fromRGB(255, 132, 190), Enum.Material.SmoothPlastic, 0 },
	PinkLight = { Color3.fromRGB(255, 205, 228), Enum.Material.SmoothPlastic, 0 },
	Orange = { Color3.fromRGB(255, 145, 40), Enum.Material.SmoothPlastic, 0 },
	Leaf = { Color3.fromRGB(86, 218, 112), Enum.Material.SmoothPlastic, 0 },
	LeafDark = { Color3.fromRGB(46, 168, 104), Enum.Material.SmoothPlastic, 0 },
	Stone = { Color3.fromRGB(196, 200, 218), Enum.Material.SmoothPlastic, 0 },
	StoneDark = { Color3.fromRGB(124, 128, 150), Enum.Material.SmoothPlastic, 0 },
	Gold = { Color3.fromRGB(255, 208, 64), Enum.Material.Metal, 0 },
	Paper = { Color3.fromRGB(255, 226, 150), Enum.Material.Neon, 0.1 },
	Roof = { Color3.fromRGB(58, 84, 148), Enum.Material.SmoothPlastic, 0 },
	White = { Color3.fromRGB(255, 250, 242), Enum.Material.SmoothPlastic, 0 },
	Black = { Color3.fromRGB(42, 34, 52), Enum.Material.SmoothPlastic, 0 },
	Water = { Color3.fromRGB(80, 205, 225), Enum.Material.Glass, 0.2 },
	Fur = { Color3.fromRGB(214, 96, 44), Enum.Material.SmoothPlastic, 0 },
	Cream = { Color3.fromRGB(255, 240, 222), Enum.Material.SmoothPlastic, 0 },
	Tan = { Color3.fromRGB(216, 164, 104), Enum.Material.SmoothPlastic, 0 },
}

function PropModel.has(name: string): boolean
	return load()[name] ~= nil
end

-- Pone la pieza `name` en `cframe` (con el suelo en su origen) a la escala dada y la mete en `parent`. `tint`
-- cambia el color de los papeles indicados ({ Red = color }). Devuelve el Model, o nil si no hay esa pieza.
function PropModel.place(parent: Instance, name: string, cframe: CFrame, scale: number?, tint: { [string]: Color3 }?): Model?
	local pieces = load()[name]
	if not pieces then
		return nil
	end
	local factor = scale or 1
	local model = Instance.new("Model")
	model.Name = name
	for _, piece in pieces do
		local mesh = piece.part:Clone() :: BasePart
		for _, child in mesh:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		if mesh:IsA("MeshPart") then
			mesh.TextureID = ""
		end
		local look = LOOKS[piece.role] or LOOKS.Stone
		mesh.Name = piece.role
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Color = if tint and tint[piece.role] then tint[piece.role] else look[1]
		mesh.Material = look[2]
		mesh.Transparency = look[3]
		mesh.CastShadow = piece.role ~= "Paper"
		mesh.Size = piece.size * factor
		mesh.CFrame = cframe * CFrame.new(piece.offset.Position * factor) * piece.offset.Rotation
		mesh.Parent = model
	end
	model.WorldPivot = cframe -- el pivote es el suelo de la pieza: así PivotTo la mueve por los pies
	model.Parent = parent
	return model
end

return PropModel
