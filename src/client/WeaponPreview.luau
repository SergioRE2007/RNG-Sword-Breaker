-- Vista 3D de un arma dentro de la interfaz (librería sin start()): un ViewportFrame con el modelo de
-- shared/SwordModel, quieto y en diagonal, que gira sobre sí mismo y se acerca al pasar el ratón por su casilla.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SwordModel = require(ReplicatedStorage.Shared.SwordModel)

local WeaponPreview = {}

local FOV = 30
local REST = math.rad(35) -- giro en reposo: un poco de lado para que se vea el grosor
local SPIN = math.rad(220) -- giro por segundo con el ratón encima
local ZOOM = 0.9 -- la cámara se acerca a esta fracción de la distancia con el ratón encima
local ROLL = CFrame.Angles(0, 0, math.rad(45)) -- inclina la imagen: la punta arriba a la derecha

-- En un ViewportFrame no se ven ni el campo de fuerza ni el cristal: se cambian por algo parecido.
local SWAP = {
	[Enum.Material.ForceField] = Enum.Material.Neon,
	[Enum.Material.Glass] = Enum.Material.SmoothPlastic,
}

local templates = {} -- [nivel] = { model, distance }
local active = {} -- vistas que se están moviendo: [vista] = true
local connected = false

-- Modelo del arma centrado en el origen y sin luces, partículas ni estelas (no se ven en un ViewportFrame).
-- Se construye una vez por tipo de arma y luego se clona.
local function template(level: number)
	local cached = templates[level]
	if cached then
		return cached
	end
	local model = Instance.new("Model")
	SwordModel.build(level, model, CFrame.identity, 1, true)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item:RemoveTag("WeaponAura")
			item.Material = SWAP[item.Material] or item.Material
		elseif not item:IsA("Model") then
			item:Destroy()
		end
	end

	local center, size = model:GetBoundingBox()
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CFrame = center:ToObjectSpace(item.CFrame)
		end
	end
	-- En diagonal, el largo y el ancho se reparten entre los dos lados de la casilla.
	local extent = (size.Y + math.max(size.X, size.Z)) * 0.7071 / 2
	cached = { model = model, distance = extent / math.tan(math.rad(FOV / 2)) * 0.96 }
	templates[level] = cached
	return cached
end

local function place(view)
	view.camera.CFrame = CFrame.Angles(0, view.angle, 0) * CFrame.lookAt(Vector3.new(view.distance * view.zoom, 0, 0), Vector3.zero) * ROLL
end

local function step(dt: number)
	for view in active do
		if view.hovered then
			view.angle += SPIN * dt
			view.zoom += (ZOOM - view.zoom) * math.min(dt * 12, 1)
		else
			-- Vuelve a la postura de reposo por el camino corto.
			local diff = (view.angle - REST + math.pi) % (2 * math.pi) - math.pi
			diff *= math.exp(-10 * dt)
			view.angle = REST + diff
			view.zoom += (1 - view.zoom) * math.min(dt * 12, 1)
			if math.abs(diff) < 0.01 and view.zoom > 0.995 then
				view.angle, view.zoom = REST, 1
				active[view] = nil
			end
		end
		place(view)
	end
end

-- Pone la vista 3D del arma de ese nivel (índice de Config.Swords) dentro de la casilla, con un brillo del color
-- que se le pase detrás. Gira mientras el ratón esté sobre la casilla.
function WeaponPreview.attach(cell: GuiObject, level: number, glowColor: Color3): ViewportFrame
	local info = template(level)

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromScale(0.72, 0.72)
	glow.BackgroundColor3 = glowColor
	glow.BackgroundTransparency = 0.8
	glow.BorderSizePixel = 0
	glow.Parent = cell
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = glow

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.45)
	viewport.Size = UDim2.fromScale(0.94, 0.94)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(165, 165, 180)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.6)
	viewport.ZIndex = 2

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	info.model:Clone().Parent = viewport

	local view = { camera = camera, distance = info.distance, angle = REST, zoom = 1, hovered = false }
	place(view)

	cell.MouseEnter:Connect(function()
		view.hovered = true
		active[view] = true
	end)
	cell.MouseLeave:Connect(function()
		view.hovered = false
	end)
	viewport.Destroying:Connect(function()
		active[view] = nil
	end)

	if not connected then
		connected = true
		RunService.RenderStepped:Connect(step)
	end
	viewport.Parent = cell
	return viewport
end

return WeaponPreview
