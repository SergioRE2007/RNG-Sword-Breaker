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
