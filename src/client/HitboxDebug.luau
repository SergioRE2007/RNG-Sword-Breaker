-- Enseña en el mundo con qué cuenta el ataque. Se enciende y se apaga con la opción "Ver hitbox" de Ajustes (que
-- cambia el atributo local HitboxDebug del jugador) y, en Studio, también con la tecla H.
-- Hace la misma cuenta que el servidor (shared/Hitbox, con los números de server/Combat), así que lo que sale en
-- verde es lo que el servidor dejaría elegir en ese instante (salvo el retraso de red).
--   · Disco amarillo en el suelo: tu círculo (Config.Loadout.Radius), dentro del que puedes elegir objetivo.
--   · Cajas: la hitbox de cada objeto de tu parcela y de cada enemigo; verde si está dentro del círculo y amarilla la
--     del objetivo al que van tus armas.
--   · Disco y raya naranjas en el objetivo: hasta dónde salpica la que más salpica de tus armas y hasta dónde
--     atraviesa la que más atraviesa.
--   · Caja roja: golpe que el servidor ha contado de verdad (aviso Hit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Targeting = require(script.Parent.Targeting)
local Ui = require(script.Parent.Ui)

local HitboxDebug = {}

local KEY = Enum.KeyCode.H -- solo en Studio
local ATTRIBUTE = "HitboxDebug" -- atributo local del jugador: encendido o apagado (así también se enciende por código)
local NEAR = 40 -- studs más allá del círculo hasta donde se dibujan las cajas
local LIFT = 0.2 -- altura de los discos sobre los pies, para que no parpadeen con el suelo
local HIT_FLASH = 0.35 -- segundos que se ve en rojo una caja golpeada
local FLAT = CFrame.Angles(math.rad(90), 0, 0) -- pone de pie el eje de un cilindro: discos tumbados en el suelo

local COLOR_AREA = Color3.fromRGB(255, 215, 60)
local COLOR_OUT = Color3.fromRGB(235, 235, 235)
local COLOR_IN = Color3.fromRGB(80, 230, 110)
local COLOR_TARGET = Color3.fromRGB(255, 215, 60)
local COLOR_SPREAD = Color3.fromRGB(255, 150, 50)
local COLOR_HIT = Color3.fromRGB(255, 70, 60)

local player = Players.LocalPlayer
local folder: Folder? = nil
local area: CylinderHandleAdornment? = nil
local splash: CylinderHandleAdornment? = nil
local pierce: BoxHandleAdornment? = nil
local boxes: { [BasePart]: SelectionBox } = {}
local connection: RBXScriptConnection? = nil

local function clearBoxes()
	for part, box in boxes do
		box:Destroy()
		boxes[part] = nil
	end
end

-- Hasta dónde llega el golpe más allá del objetivo: el mayor radio de las armas equipadas que salpican y el origen y
-- el largo de la que más atraviesa (ver Hitbox.spread).
local function spread(from: Vector3, target: Vector3): (number, CFrame?, number)
	local radius, line, length = 0, nil, 0
	for _, copy in Stats.loadout(player) do
		local _, kind = Stats.kind(copy)
		local origin, range, arc = Hitbox.spread(kind, Config.Swords[copy.sword].bladeLength, from, target)
		if origin and arc <= -1 then
			radius = math.max(radius, range)
		elseif origin and range > length then
			line, length = origin, range
		end
	end
	return radius, line, length
end

local function update()
	local root = Targeting.root()
	local humanoid = root and (root.Parent :: Model):FindFirstChildOfClass("Humanoid")
	if not (area and splash and pierce and folder and root and humanoid) then
		for _, item in { area, splash, pierce } do
			item.Visible = false
		end
		clearBoxes()
		return
	end

	local radius = Config.Loadout.Radius
	local feet = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2) + LIFT
	local target = Targeting.current()
	area.Visible = true
	area.CFrame = CFrame.new(root.Position.X, feet, root.Position.Z) * FLAT
	area.Radius = radius
	area.Transparency = if target then 0.75 else 0.85

	local reach, line, length = 0, nil, 0
	if target then
		reach, line, length = spread(root.Position, target.Position)
	end
	splash.Visible = reach > 0
	if target and reach > 0 then
		splash.CFrame = CFrame.new(target.Position.X, feet + 0.05, target.Position.Z) * FLAT
		splash.Radius = reach
	end
	pierce.Visible = line ~= nil
	if line then
		pierce.CFrame = line * CFrame.new(0, 0, -length / 2)
		pierce.Size = Vector3.new(0.4, 0.4, length)
	end

	local seen = {}
	for _, part in Targeting.candidates() do
		if (part.Position - root.Position).Magnitude > radius + NEAR then
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
		local inside = Hitbox.within(part, root.Position, radius)
		local chosen = part == target
		box.Color3 = if chosen then COLOR_TARGET elseif inside then COLOR_IN else COLOR_OUT
		box.SurfaceColor3 = if chosen then COLOR_TARGET else COLOR_IN
		box.SurfaceTransparency = if chosen then 0.5 elseif inside then 0.75 else 1
		box.LineThickness = if chosen then 0.16 elseif inside then 0.1 else 0.04
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

local function disc(parent: Instance, name: string, color: Color3, transparency: number): CylinderHandleAdornment
	local item = Instance.new("CylinderHandleAdornment")
	item.Name = name
	item.Adornee = workspace.Terrain
	item.Height = 0.1
	item.Color3 = color
	item.Transparency = transparency
	item.Visible = false
	item.Parent = parent
	return item
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
		folder, area, splash, pierce = nil, nil, nil, nil
		Ui.toast("Hitbox escondida", COLOR_OUT)
		return
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = "HitboxDebug"
	newFolder.Parent = workspace
	area = disc(newFolder, "Area", COLOR_AREA, 0.85)
	splash = disc(newFolder, "Splash", COLOR_SPREAD, 0.6)
	local line = Instance.new("BoxHandleAdornment")
	line.Name = "Pierce"
	line.Adornee = workspace.Terrain
	line.Color3 = COLOR_SPREAD
	line.Transparency = 0.3
	line.Visible = false
	line.Parent = newFolder
	pierce = line
	folder = newFolder
	connection = RunService.RenderStepped:Connect(update)

	Ui.toast(`Hitbox a la vista\nCírculo de {Config.Loadout.Radius} studs · {#Stats.loadout(player)} armas`, COLOR_AREA)
end

function HitboxDebug.start()
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
