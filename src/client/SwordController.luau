-- Entrada del ataque: el clic, el toque o el gatillo del mando eligen un objetivo (un objeto de tu parcela o un enemigo
-- de tu mazmorra, dentro de tu círculo) y se le pide al servidor que mande allí las armas equipadas (Attack). El
-- servidor valida y decide (server/Combat); aquí solo se elige y se adelanta el vuelo de las armas (OrbitWeapons).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ForgeScene = require(script.Parent.ForgeScene)
local OrbitWeapons = require(script.Parent.OrbitWeapons)
local Targeting = require(script.Parent.Targeting)
local Ui = require(script.Parent.Ui)

local SwordController = {}

local AIM_ASSIST = 60 -- píxeles alrededor de un objetivo en los que el clic o el toque cuentan como darle
local REPEAT = 0.5 -- segundos sin volver a pedir el mismo objetivo mientras el servidor contesta
local FACING = 10 -- con el mando: studs que "acerca" a un objetivo tenerlo delante de la cámara

local asked: BasePart? = nil
local askedAt = 0
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

-- Manda las armas a por esa pieza. Devuelve true si se ha pedido (o ya iban a por ella): no vale lo que no es tuyo, lo
-- que queda fuera del círculo (el aro avisa en rojo) ni nada mientras estás en la forja, donde el clic es el martillazo.
function SwordController.attack(part: BasePart?): boolean
	if ForgeScene.isActive() or not part or not Targeting.valid(part) then
		return false
	end
	if not Targeting.inCircle(part) then
		OrbitWeapons.deny()
		return false
	end
	local now = os.clock()
	if Targeting.current() == part or (asked == part and now - askedAt < REPEAT) then
		return true
	end
	asked, askedAt = part, now
	OrbitWeapons.aim(part)
	Remotes.Attack:FireServer(part)
	return true
end

-- Hace volver las armas.
function SwordController.recall()
	asked = nil
	OrbitWeapons.aim(nil)
	if Targeting.current() then
		Remotes.Attack:FireServer(nil)
	end
end

-- Lo que señala ese punto de la pantalla: la pieza que tiene debajo o, si no hay ninguna, la más cercana al puntero
-- de las que le quedan a menos de AIM_ASSIST píxeles (ayuda de puntería: en el móvil el dedo tapa lo que toca).
local function pick(point: Vector2): BasePart?
	local camera = workspace.CurrentCamera
	local candidates = Targeting.candidates()
	if not camera or #candidates == 0 then
		return nil
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	params.FilterDescendantsInstances = candidates
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit and hit.Instance:IsA("BasePart") and Targeting.valid(hit.Instance) then
		return hit.Instance
	end
	-- Lo que mide un stud en pantalla a un stud de la cámara, para saber cuánto ocupa cada pieza.
	local focal = camera.ViewportSize.Y / (2 * math.tan(math.rad(camera.FieldOfView) / 2))
	local best, bestGap = nil, AIM_ASSIST
	for _, part in candidates do
		local screen, visible = camera:WorldToViewportPoint(part.Position)
		if visible and Targeting.inCircle(part) then
			local gap = (Vector2.new(screen.X, screen.Y) - point).Magnitude - part.Size.Magnitude / 2 / screen.Z * focal
			if gap < bestGap then
				best, bestGap = part, gap
			end
		end
	end
	return best
end

-- Sin puntero (mando): lo más cercano del círculo, con ventaja para lo que la cámara tiene delante.
local function pickNear(): BasePart?
	local root = Targeting.root()
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local best, bestScore = nil, math.huge
	for _, part in Targeting.candidates() do
		if Targeting.inCircle(part) then
			local offset = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
			local facing = if offset.Magnitude > 0.5 then offset.Unit:Dot(look) else 1
			local score = offset.Magnitude + (1 - facing) * FACING
			if score < bestScore then
				best, bestScore = part, score
			end
		end
	end
	return best
end

local function busy(): boolean
	return ForgeScene.isActive() or Ui.anyOpen() or UserInputService:GetFocusedTextBox() ~= nil
end

function SwordController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or busy() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			SwordController.attack(pick(UserInputService:GetMouseLocation()))
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			SwordController.attack(pickNear())
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(position, processed)
		if not processed and not busy() then
			-- El toque llega sin el hueco de arriba de la pantalla, que la cámara sí cuenta.
			local inset = GuiService:GetGuiInset()
			SwordController.attack(pick(position + inset))
		end
	end)
end

return SwordController
