-- Ascensor de luz del pozo de las mazmorras (sustituye a la escalera de caracol de DungeonLobby). Arriba, una tapa de
-- cristal violeta cierra la boca del hub (así nadie cae por accidente); abajo, una plataforma en el centro del pozo. En
-- cada una hay un aviso: quien lo usa queda en el aire y baja o sube por una columna de luz en unos segundos. El
-- servidor mueve al personaje y valida todo; el cliente no manda nada. Solo decoración y transporte.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local LightLift = {}

local cfg = Config.DungeonLobby
local TOP = Config.Plot.FloorHeight
local FLOOR = cfg.Floor
local RIDE_TIME = 3
local STAND = 3.6 -- altura del centro del personaje sobre la plataforma
local VIOLET = Color3.fromRGB(176, 124, 255)
local CYAN = Color3.fromRGB(110, 232, 255)
local DARK = Color3.fromRGB(42, 40, 56)

local riding: { [Player]: boolean } = {}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.Transparency = transparency or 0
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function disc(parent: Instance, name: string, center: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material, transparency: number?): Part
	local item = part(parent, name, Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, transparency)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function decor(item: BasePart): BasePart
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
	return item
end

-- Lleva al personaje de `fromY` a `toY` por el eje del pozo, sujeto en el aire, con arranque y parada suaves.
local function ride(player: Player, toY: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if riding[player] or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	riding[player] = true
	local fromY = root.Position.Y
	local yaw = select(2, root.CFrame:ToEulerAnglesYXZ())
	root.Anchored = true
	local started = os.clock()
	while true do
		local alpha = math.clamp((os.clock() - started) / RIDE_TIME, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		if not root.Parent or humanoid.Health <= 0 then
			break
		end
		root.CFrame = CFrame.new(0, fromY + (toY - fromY) * eased, 0) * CFrame.Angles(0, yaw, 0)
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = false
	end
	riding[player] = nil
end

local function platform(parent: Instance, name: string, y: number, text: string, goTo: number)
	local pad = disc(parent, name, Vector3.new(0, y - 0.5, 0), 6, 1, DARK, Enum.Material.Slate)
	disc(parent, name .. "Glass", Vector3.new(0, y + 0.06, 0), 5.2, 0.12, VIOLET, Enum.Material.Glass, 0.78).CanCollide = false
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		decor(part(parent, name .. "Rune", Vector3.new(0.6, 0.12, 1.3), CFrame.new(math.cos(angle) * 4.3, y + 0.14, math.sin(angle) * 4.3) * CFrame.Angles(0, -angle, 0), CYAN, Enum.Material.Glass, 0.72))
	end
	local light = Instance.new("PointLight")
	light.Color = VIOLET
	light.Range = 14
	light.Brightness = 0.2
	light.Parent = pad
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = text
	prompt.ObjectText = "Ascensor de luz"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		-- Solo desde la propia plataforma (el aviso llega a 9 studs: se exige estar en el centro).
		if root and root:IsA("BasePart") and Vector2.new(root.Position.X, root.Position.Z).Magnitude < 9 and math.abs(root.Position.Y - (y + STAND)) < 8 then
			ride(player, goTo)
		end
	end)
end

function LightLift.start()
	local folder = Instance.new("Folder")
	folder.Name = "AscensorLuz"
	local topY, bottomY = TOP, FLOOR

	-- Tapa de cristal sobre la boca: sólida (no se cae por ella) y translúcida, con un anillo de runas al borde.
	disc(folder, "Lid", Vector3.new(0, topY - 0.25, 0), cfg.HoleRadius + 0.4, 0.5, VIOLET:Lerp(DARK, 0.6), Enum.Material.Glass, 0.7)
	platform(folder, "LiftTop", topY, "Bajar", bottomY + STAND)
	platform(folder, "LiftBottom", bottomY, "Subir", topY + STAND)

	-- Columna de luz de arriba a abajo del pozo (cristal translúcido, sin Neon).
	local column = decor(part(folder, "LightColumn", Vector3.new(topY - bottomY, 9, 9), CFrame.new(0, (topY + bottomY) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), CYAN, Enum.Material.Glass, 0.97))
	column.Shape = Enum.PartType.Cylinder
	CollectionService:AddTag(column, "LightColumn")
	folder.Parent = workspace

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		riding[player] = nil
	end)
end

return LightLift
