-- Entrada del ataque: el clic, el toque o el gatillo del mando eligen un objetivo (un objeto de tu parcela o un enemigo
-- de tu mazmorra, dentro de tu círculo) y se le pide al servidor que mande allí las armas equipadas (Attack). El
-- servidor valida y decide (server/Combat); aquí solo se elige y se adelanta el vuelo de las armas (OrbitWeapons).
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local BagMenu = require(script.Parent.BagMenu)
local Clover = require(script.Parent.Clover)
local ForgeScene = require(script.Parent.ForgeScene)
local RollCinematic = require(script.Parent.RollCinematic)
local OrbitWeapons = require(script.Parent.OrbitWeapons)
local Targeting = require(script.Parent.Targeting)
local Ui = require(script.Parent.Ui)

local SwordController = {}

local AIM_ASSIST = 60 -- píxeles alrededor de un objetivo en los que el clic o el toque cuentan como darle
local REPEAT = 0.5 -- segundos sin volver a pedir el mismo objetivo mientras el servidor contesta
local FACING = 10 -- con el mando: studs que "acerca" a un objetivo tenerlo delante de la cámara
local WALK_TIME = 8 -- segundos como mucho andando solo hacia un objeto lejano
local WALK_MARGIN = 6 -- studs que se mete dentro del círculo antes de atacar (el servidor ve la posición con retraso)
local WALK_RETRY = 2 -- segundos pidiendo el ataque al llegar, hasta que el servidor lo acepta

local player = Players.LocalPlayer
local walking: {}? = nil -- la caminata en curso (cada una es una tabla nueva: al empezar otra, la vieja se para)

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

-- Si el jugador está llevando el personaje hacia otro lado (teclas, joystick o mando mandan sobre MoveTo).
local function steering(humanoid: Humanoid, part: BasePart): boolean
	local root = Targeting.root()
	local move = humanoid.MoveDirection
	if not root or move.Magnitude < 0.1 then
		return false
	end
	local toward = (part.Position - root.Position) * Vector3.new(1, 0, 1)
	return toward.Magnitude > 1 and move.Unit:Dot(toward.Unit) < 0.8
end

-- Clic en un objeto de tu parcela que queda fuera del círculo: el personaje va andando hasta él y lo ataca al llegar
-- (los jugadores nuevos hacían clic en uno lejano, no pasaba nada y se iban). Se para si mueves tú el personaje, si
-- pides otra cosa o a los WALK_TIME segundos.
local function walkTo(part: BasePart)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local this = {}
	walking = this
	task.spawn(function()
		local started = os.clock()
		while walking == this and os.clock() - started < WALK_TIME and humanoid.Health > 0 and Targeting.valid(part) and not steering(humanoid, part) do
			if Targeting.inCircle(part, Stats.reach(player) - WALK_MARGIN) then
				local root = Targeting.root()
				if root then
					humanoid:MoveTo(root.Position)
				end
				-- El servidor ve la posición con retraso y puede rechazar el primer intento: se repite hasta que acepta.
				local arrived = os.clock()
				while walking == this and os.clock() - arrived < WALK_RETRY and Targeting.valid(part) and Targeting.current() ~= part do
					SwordController.attack(part)
					task.wait(0.1)
				end
				if walking == this then
					walking = nil
				end
				return
			end
			humanoid:MoveTo(part.Position)
			task.wait(0.15)
		end
		if walking == this then
			walking = nil
			local root = Targeting.root()
			if root and not steering(humanoid, part) then
				humanoid:MoveTo(root.Position)
			end
		end
	end)
end

-- Lo que hace un clic o un toque sobre esa pieza.
local function clickOn(part: BasePart?)
	walking = nil
	if part and not ForgeScene.isActive() and Targeting.valid(part) and CollectionService:HasTag(part, "Destructible") and not Targeting.inCircle(part) then
		walkTo(part)
	else
		SwordController.attack(part)
	end
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
	return ForgeScene.isActive() or RollCinematic.isActive() or Clover.isActive() or Ui.anyOpen() or UserInputService:GetFocusedTextBox() ~= nil
end

function SwordController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or busy() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local point = UserInputService:GetMouseLocation()
			if not BagMenu.pointed(point) then -- el clic en tu Bolsa de oro abre su menú
				clickOn(pick(point))
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			SwordController.attack(pickNear())
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(position, processed)
		if not processed and not busy() then
			-- El toque llega sin el hueco de arriba de la pantalla, que la cámara sí cuenta.
			local point = position + GuiService:GetGuiInset()
			if not BagMenu.pointed(point) then
				clickOn(pick(point))
			end
		end
	end)
end

return SwordController
