-- Aspecto de los puestos de las tiendas del hub: toldo de rayas, plataforma y un vendedor
-- (NPC) detrás del mostrador. Copiado de un modelo gratis de la Creator Store (Steal A Brainrot
-- Shop, de TwinPlayzDev) y pasado a código, sin scripts. Mira hacia -Z.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local StallSkin = {}

-- Cada pieza: tamaño (3), posición (3), rotación (9, fila a fila) y color RGB (3).
local PARTS = {
	{ 13, 0.7, 1, 8.8, 8.799, 8.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 2, 0.8, 9.2, 10.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 13, 105, 172 },
	{ 6, 1, 0.2, 11.3, -1.351, 2.106, -0.999, -0.035, 0, -0.035, 0.999, 0, 0, 0, -1, 77, 52, 32 },
	{ 6, 1, 0.2, 6.3, -1.351, 2.106, -1, 0.017, 0, 0.017, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 1, 11, 1, 14.8, 2.949, 8.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 1, 11, 1, 2.8, 2.949, 8.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 2, 0.8, 9.2, 14.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 13, 105, 172 },
	{ 1, 8, 1, 2.8, 1.449, 2.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 6, 1, 0.2, 6.3, -0.151, 2.106, -1, 0.017, 0, 0.017, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 1, 8, 1, 14.8, 1.449, 2.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 77, 52, 32 },
	{ 1, 1, 7, 2.8, 6.949, 5.506, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 77, 52, 32 },
	{ 2, 0.8, 9.2, 8.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 191, 179, 184 },
	{ 13, 0.2, 2.2, 8.8, 0.349, 2.506, -1, 0, 0, 0, 1, 0, 0, 0, -1, 80, 75, 77 },
	{ 2, 0.8, 9.2, 12.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 191, 179, 184 },
	{ 6, 1, 0.2, 11.3, -0.151, 2.106, -0.999, -0.035, 0, -0.035, 0.999, 0, 0, 0, -1, 77, 52, 32 },
	{ 1, 1, 7, 14.8, 6.949, 5.506, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 77, 52, 32 },
	{ 2, 0.8, 9.2, 4.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 191, 179, 184 },
	{ 2, 0.8, 9.2, 6.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 13, 105, 172 },
	{ 2, 0.8, 9.2, 2.8, 7.254, 5.369, -1, 0, 0, 0, 0.866, -0.5, 0, -0.5, -0.866, 13, 105, 172 },
	{ 18.48, 0.4, 21.443, 8.251, -2.751, 5.8, 0, 0, 1, 0, 1, 0, -1, 0, 0, 159, 161, 172 },
	{ 20.28, 0.2, 23.443, 8.451, -2.851, 5.5, 0, 0, 1, 0, 1, 0, -1, 0, 0, 91, 93, 105 },
	{ 2.08, 0.6, 2.043, 19.151, -2.651, -3.6, 0, 0, 1, 0, 1, 0, -1, 0, 0, 91, 93, 105 },
	{ 2.08, 0.6, 2.043, -2.249, -2.651, -3.6, 0, 0, 1, 0, 1, 0, -1, 0, 0, 91, 93, 105 },
	{ 2.08, 0.6, 2.043, -2.249, -2.651, 14.6, 0, 0, 1, 0, 1, 0, -1, 0, 0, 91, 93, 105 },
	{ 2.08, 0.6, 2.043, 19.151, -2.651, 14.6, 0, 0, 1, 0, 1, 0, -1, 0, 0, 91, 93, 105 },
}

local NPC_AT = CFrame.new(8.732, 0.421, 5.595)

-- Vendedor R15 vestido como en el modelo original.
local function buildSeller(): Model?
	local description = Instance.new("HumanoidDescription")
	description.Shirt = 301809996
	description.Pants = 301811279
	description.Face = 301827199
	description.Torso = 301826032
	description.LeftArm = 301824684
	description.RightArm = 301825492
	description.LeftLeg = 301825699
	description.RightLeg = 301825891
	description.HairAccessory = "301819845"
	description.NeckAccessory = "301820684"
	local skin = Color3.fromRGB(232, 185, 149)
	description.HeadColor = skin
	description.TorsoColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.LeftLegColor = skin
	description.RightLegColor = skin
	local ok, seller = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok then
		warn("StallSkin: no se pudo crear el vendedor", seller)
		return nil
	end
	seller.Name = "Vendedor"
	CollectionService:AddTag(seller, "StationSeller") -- el cliente lo hace moverse (StationFx)
	for _, item in seller:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	-- Piezas fijas: el generador deja el cuerpo sin articulaciones y alguna pieza fuera de sitio
	-- (una pierna flotando). Cada una se coloca desde la raíz, juntando los pares de puntos de
	-- enganche (XRigAttachment) que comparten dos piezas.
	local root = seller.HumanoidRootPart
	root.CFrame = CFrame.new()
	local byName = {}
	for _, item in seller:GetDescendants() do
		if item:IsA("Attachment") and string.find(item.Name, "RigAttachment") then
			byName[item.Name] = byName[item.Name] or {}
			table.insert(byName[item.Name], item)
		end
	end
	local placed = { [root] = true }
	local queue = { root }
	while #queue > 0 do
		local part = table.remove(queue, 1)
		for _, mine in part:GetChildren() do
			local pair = if mine:IsA("Attachment") then byName[mine.Name] else nil
			if pair and #pair == 2 then
				local other = if pair[1] == mine then pair[2] else pair[1]
				local next = other.Parent :: BasePart
				if not placed[next] then
					placed[next] = true
					next.CFrame = part.CFrame * mine.CFrame * other.CFrame:Inverse()
					table.insert(queue, next)
				end
			end
		end
	end
	seller:PivotTo(NPC_AT)
	return seller
end

-- Colores originales del toldo (azul y gris claro): se cambian por los de cada tienda.
local TOLDO_A = Color3.fromRGB(13, 105, 172)
local TOLDO_B = Color3.fromRGB(191, 179, 184)

-- Devuelve el modelo con el origen (0, 0, 0) como pivote. `colorA` y `colorB` pintan las
-- rayas del toldo.
function StallSkin.build(colorA: Color3, colorB: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Puesto"
	for _, row in PARTS do
		local part = Instance.new("Part")
		part.Name = "Pieza"
		part.Anchored = true
		part.Size = Vector3.new(row[1], row[2], row[3])
		part.CFrame = CFrame.new(row[4], row[5], row[6], row[7], row[8], row[9], row[10], row[11], row[12], row[13], row[14], row[15])
		part.Color = Color3.fromRGB(row[16], row[17], row[18])
		if part.Color == TOLDO_A then
			part.Color = colorA
		elseif part.Color == TOLDO_B then
			part.Color = colorB
		end
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end
	local seller = buildSeller()
	if seller then
		seller.Parent = model
	end
	model.WorldPivot = CFrame.new()
	return model
end

return StallSkin
