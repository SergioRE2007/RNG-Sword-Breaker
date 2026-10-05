-- Armas con malla propia (las de Config.Swords que llevan `mesh`): la forma viene de un módulo de `Meshes`
-- exportado de Blender y se dibuja con EditableMesh. Esas piezas no se replican, así que cada cliente viste
-- la empuñadura que le llega del servidor (client/WeaponMesh) o la que construye él mismo (vistas 3D).
-- Necesita el permiso de EditableMesh en los ajustes de la experiencia (pestaña Seguridad).
local AssetService = game:GetService("AssetService")

local Config = require(script.Parent.Config)

local MeshWeapon = {}

MeshWeapon.TAG = "WeaponMesh"

local WHITE = Color3.new(1, 1, 1)

-- El color va por vértice (paleta de la malla); aquí solo el material de cada pieza.
local MATERIALS = {
	solid = { material = Enum.Material.Metal, reflectance = 0.15 },
	energy = { material = Enum.Material.Neon },
	aura = { material = Enum.Material.Neon, transparency = 0.4 },
}

local templates = {} -- [nombre de la malla] = { [índice de pieza] = { part (se clona), mesh, center } }

function MeshWeapon.data(name: string)
	return require(script.Parent.Meshes[name])
end

-- Malla de una pieza, con caras planas (estilo low-poly) y el color de cada vértice. Devuelve también el centro
-- de la pieza: los vértices van centrados en él, que es donde queda el centro del MeshPart.
local function editable(piece, palette): (EditableMesh, Vector3)
	local v, f, c = piece.v, piece.f, piece.c
	local points = {}
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for i = 1, #v / 3 do
		local point = Vector3.new(v[i * 3 - 2], v[i * 3 - 1], v[i * 3])
		points[i] = point
		low, high = low:Min(point), high:Max(point)
	end
	local middle = (low + high) / 2

	local mesh = AssetService:CreateEditableMesh()
	local vertices, colors = {}, {}
	for i, point in points do
		vertices[i] = mesh:AddVertex(point - middle)
	end
	for i, color in palette do
		colors[i] = mesh:AddColor(color, 1)
	end
	for i = 1, #f, 3 do
		local a, b, d = f[i], f[i + 1], f[i + 2]
		local face = mesh:AddTriangle(vertices[a], vertices[b], vertices[d])
		local cross = (points[b] - points[a]):Cross(points[d] - points[a])
		if cross.Magnitude > 1e-9 then
			local normal = mesh:AddNormal(cross.Unit)
			mesh:SetFaceNormals(face, { normal, normal, normal })
		end
		mesh:SetFaceColors(face, { colors[c[a]], colors[c[b]], colors[c[d]] })
	end
	return mesh, piece.center + middle
end

local function template(name: string)
	local cached = templates[name]
	if cached then
		return cached
	end
	local data = MeshWeapon.data(name)
	local parts = {}
	for index, piece in data.pieces do
		local mesh, center = editable(piece, data.palette)
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
		local look = MATERIALS[piece.mat]
		part.Name = piece.name
		part.Color = WHITE
		part.Material = look.material
		part.Reflectance = look.reflectance or 0
		part.Transparency = look.transparency or 0
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = false
		-- La malla tiene que seguir viva mientras haya piezas que la usen.
		parts[index] = { part = part, mesh = mesh, center = center }
	end
	templates[name] = parts
	return parts
end

-- Viste la empuñadura (lleva los atributos Mesh, MeshScale y MeshMetal que pone SwordModel) con las piezas
-- de su malla. Devuelve las soldaduras de las piezas que se mueven, como { weld, piece, center, scale }, para
-- que el cliente las anime (`center` = dónde va la pieza respecto a la empuñadura). Si EditableMesh no está
-- permitido, enseña las piezas de relleno y devuelve nil.
function MeshWeapon.attach(handle: BasePart, anchored: boolean)
	local name = handle:GetAttribute("Mesh")
	local scale = handle:GetAttribute("MeshScale") or 1
	local ok, parts = pcall(template, name)
	if not ok then
		warn("MeshWeapon: no se puede dibujar la malla (" .. tostring(parts) .. ")")
		if handle.Parent then
			for _, item in handle.Parent:GetChildren() do
				if item:IsA("BasePart") and item:GetAttribute("MeshProxy") then
					item.Transparency = 0
				end
			end
		end
		return nil
	end
	if not handle.Parent then
		return nil -- el arma se guardó mientras se preparaba la malla
	end

	local metal = handle:GetAttribute("MeshMetal")
	local metalDef = if metal and metal > 0 then Config.Metals[metal] else nil
	local moving = {}
	for index, piece in MeshWeapon.data(name).pieces do
		local part = parts[index].part:Clone()
		part.Size *= scale
		if metalDef and piece.mat == "solid" then
			-- Con un metal, el arma entera se tiñe de su color.
			part.Color = metalDef.color:Lerp(WHITE, 0.3)
			part.Material = metalDef.material
		end
		local center = parts[index].center * scale
		local offset = CFrame.new(center)
		part.CFrame = handle.CFrame * offset
		part.Anchored = anchored
		if not anchored then
			local weld = Instance.new("Weld")
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part
			if piece.spin then
				table.insert(moving, { weld = weld, piece = piece, center = center, scale = scale })
			end
		end
		part.Parent = handle.Parent
	end
	return moving
end

return MeshWeapon
