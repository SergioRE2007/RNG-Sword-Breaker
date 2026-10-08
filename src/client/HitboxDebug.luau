-- Enseña en el mundo la hitbox del espadazo. Se enciende y se apaga con la opción "Ver hitbox" de Ajustes (que
-- cambia el atributo local HitboxDebug del jugador) y, en Studio, también con la tecla H.
-- Hace la misma cuenta que el servidor (shared/Hitbox con el alcance y el arco de server/Combat), así que lo que
-- sale en verde es lo que el servidor daría por alcanzado si se golpeara en ese instante (salvo el retraso de red).
--   · Sector amarillo en el suelo: hasta dónde llega el arma que llevas en la mano; se queda blanco mientras el
--     espadazo sigue vivo (Config.SwingWindow) y puede golpear a lo que entre.
--   · Cajas: la hitbox de cada objeto de tu parcela y de cada enemigo; verde si el golpe la alcanzaría.
--   · Caja roja: golpe que el servidor ha contado de verdad (aviso Hit).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local SwordController = require(script.Parent.SwordController)
local Ui = require(script.Parent.Ui)

local HitboxDebug = {}

local KEY = Enum.KeyCode.H -- solo en Studio
local ATTRIBUTE = "HitboxDebug" -- atributo local del jugador: encendido o apagado (así también se enciende por código)
local NEAR = 40 -- studs más allá del alcance hasta donde se dibujan las cajas
local LIFT = 0.15 -- altura del sector sobre los pies, para que no parpadee con el suelo
local SWING_FLASH = 0.15 -- segundos que brilla el sector al dar un espadazo, como poco
local HIT_FLASH = 0.35 -- segundos que se ve en rojo una caja golpeada

local COLOR_AREA = Color3.fromRGB(255, 215, 60)
local COLOR_SWING = Color3.fromRGB(255, 255, 255)
local COLOR_OUT = Color3.fromRGB(235, 235, 235)
local COLOR_IN = Color3.fromRGB(80, 230, 110)
local COLOR_HIT = Color3.fromRGB(255, 70, 60)

local player = Players.LocalPlayer
local folder: Folder? = nil
local area: CylinderHandleAdornment? = nil
local boxes: { [BasePart]: SelectionBox } = {}
local connection: RBXScriptConnection? = nil
local activeUntil = 0 -- hasta cuándo sigue vivo el último espadazo (reloj de os.clock)

-- Alcance y arco del arma que lleva en la mano, con la cuenta de server/Combat. Sin arma en la mano no hay golpe.
local function reach(character: Model): (number, number)
	if not character:FindFirstChildWhichIsA("Tool") then
		return 0, 1
	end
	local copy = Stats.equipped(player)
	local _, kind = Stats.weapon(player)
	return Config.BaseRange + Config.Swords[copy.sword].bladeLength * Permanent.scale(copy), kind.arc
end

-- Medio ángulo del arco en radianes (el arco de Config.WeaponKinds es su coseno; -1 = todo alrededor).
local function halfAngle(arc: number): number
	return if arc <= -1 then math.pi else math.acos(math.clamp(arc, -1, 1))
end

-- Lo que el servidor mira en un espadazo: los objetos de tu parcela y los enemigos.
local function targets(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged("Destructible") do
		if part:IsA("BasePart") and part:GetAttribute("Owner") == player.UserId then
			table.insert(list, part)
		end
	end
	for _, part in CollectionService:GetTagged("Enemy") do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

local function clearBoxes()
	for part, box in boxes do
		box:Destroy()
		boxes[part] = nil
	end
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (area and folder and root and humanoid) or humanoid.Health <= 0 then
		if area then
			area.Visible = false
		end
		clearBoxes()
		return
	end

	local range, arc = reach(character)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	area.Visible = range > 0 and look.Magnitude > 1e-4
	if area.Visible then
		-- El sector del cilindro nace en su eje X y barre hacia su eje Y: se gira medio arco a la derecha de la
		-- mirada para que quede centrado delante.
		local half = halfAngle(arc)
		local first = CFrame.Angles(0, -half, 0):VectorToWorldSpace(look.Unit)
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - LIFT, 0)
		local swinging = os.clock() < activeUntil
		area.CFrame = CFrame.fromMatrix(feet, first, Vector3.yAxis:Cross(first), Vector3.yAxis)
		area.Radius = range
		area.Angle = math.deg(half) * 2
		area.Color3 = if swinging then COLOR_SWING else COLOR_AREA
		area.Transparency = if swinging then 0.2 else 0.6
	end

	local seen = {}
	for _, part in targets() do
		if (part.Position - root.Position).Magnitude > range + NEAR then
			continue
		end
		seen[part] = true
		local box = boxes[part]
		if not box then
			box = Instance.new("SelectionBox")
			box.Adornee = part
			box.Parent = folder
			boxes[part] = box
		end
		local inReach = range > 0 and Hitbox.reaches(part, root.CFrame, range, arc)
		box.Color3 = if inReach then COLOR_IN else COLOR_OUT
		box.SurfaceColor3 = COLOR_IN
		box.SurfaceTransparency = if inReach then 0.65 else 1
		box.LineThickness = if inReach then 0.12 else 0.04
	end
	for part, box in boxes do
		if not seen[part] then
			box:Destroy()
			boxes[part] = nil
		end
	end
end

-- Caja roja donde estaba lo golpeado: suelta, porque el objeto puede romperse con ese mismo golpe.
local function showHit(part: BasePart)
	local ghost = Instance.new("BoxHandleAdornment")
	ghost.Adornee = workspace.Terrain
	ghost.CFrame = part.CFrame
	ghost.Size = part.Size + Vector3.one * 0.3
	ghost.Color3 = COLOR_HIT
	ghost.Transparency = 0.45
	ghost.Parent = folder
	task.delay(HIT_FLASH, ghost.Destroy, ghost)
end

local function setEnabled(on: boolean)
	if on == (connection ~= nil) then
		return
	end
	if not on then
		(connection :: RBXScriptConnection):Disconnect()
		connection = nil
		clearBoxes()
		if folder then
			folder:Destroy()
		end
		folder, area = nil, nil
		Ui.toast("Hitbox escondida", COLOR_OUT)
		return
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = "HitboxDebug"
	newFolder.Parent = workspace
	local newArea = Instance.new("CylinderHandleAdornment")
	newArea.Name = "Area"
	newArea.Adornee = workspace.Terrain
	newArea.Height = 0.1
	newArea.Visible = false
	newArea.Parent = newFolder
	folder, area = newFolder, newArea
	connection = RunService.RenderStepped:Connect(update)

	local character = player.Character
	local range, arc = 0, 1
	if character then
		range, arc = reach(character)
	end
	local detail = if range > 0
		then string.format("Alcance %.1f · arco %d°", range, math.round(math.deg(halfAngle(arc)) * 2))
		else "Saca un arma para ver su alcance"
	Ui.toast(`Hitbox a la vista\n{detail}`, COLOR_AREA)
end

function HitboxDebug.start()
	SwordController.onSwing = function()
		activeUntil = os.clock() + math.max(Stats.cooldown(player) * Config.SwingWindow, SWING_FLASH)
	end
	Remotes.Hit.OnClientEvent:Connect(function(hitter: Player, part: BasePart?)
		if folder and hitter == player and part then
			showHit(part)
		end
	end)
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == KEY then
				player:SetAttribute(ATTRIBUTE, not player:GetAttribute(ATTRIBUTE))
			end
		end)
	end
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		setEnabled(player:GetAttribute(ATTRIBUTE) == true)
	end)
	setEnabled(player:GetAttribute(ATTRIBUTE) == true)
end

return HitboxDebug
