-- Piezas de interfaz de las zonas de mazmorra que comparten la ventana del grupo (client/Party) y otros módulos
-- (librería sin start()): el "retrato" de un enemigo hecho con marcos y el daño por golpe de los enemigos de una zona.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Ui)

local DungeonCard = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Daño por golpe del enemigo más flojo y del más fuerte en esa zona.
function DungeonCard.enemyHits(level): (number, number)
	local low, high = math.huge, 0
	for _, enemy in Config.Enemies do
		local hit = enemy.damage * level.power
		low, high = math.min(low, hit), math.max(high, hit)
	end
	return low, high
end

-- Cara de enemigo hecha con marcos: el "retrato" de la tarjeta de una zona.
function DungeonCard.face(parent: Instance, color: Color3): Frame
	local head = Instance.new("Frame")
	head.Name = "Face"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(0.82, 0.82)
	head.BackgroundColor3 = WHITE
	head.BorderSizePixel = 0
	head.Parent = parent
	Ui.round(head, 12)
	Ui.stroke(head, BLACK, 3)
	Ui.gradient(head, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.3), 90)
	for _, x in { 0.3, 0.7 } do
		local eye = Instance.new("Frame")
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.22, 0.28)
		eye.BackgroundColor3 = WHITE
		eye.BorderSizePixel = 0
		eye.Parent = head
		Ui.round(eye, 4)
		local pupil = Instance.new("Frame")
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.5, 0.6)
		pupil.Size = UDim2.fromScale(0.5, 0.55)
		pupil.BackgroundColor3 = BLACK
		pupil.BorderSizePixel = 0
		pupil.Parent = eye
		Ui.round(pupil, 3)
	end
	local mouth = Instance.new("Frame")
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.74)
	mouth.Size = UDim2.fromScale(0.42, 0.09)
	mouth.BackgroundColor3 = BLACK
	mouth.BorderSizePixel = 0
	mouth.Parent = head
	Ui.round(mouth, 3)
	return head
end

return DungeonCard
