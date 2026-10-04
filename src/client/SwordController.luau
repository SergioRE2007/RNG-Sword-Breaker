-- Convierte los clics con la espada equipada en espadazos: animación, sonido y aviso al servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local SwordController = {}

local player = Players.LocalPlayer
local hooked = setmetatable({}, { __mode = "k" })
local lastSwing = 0

local function swing(tool: Tool)
	local now = os.clock()
	if now - lastSwing < Upgrades.value("speed", player:GetAttribute("Upgrade_speed") or 0) then
		return
	end
	lastSwing = now

	-- El script Animate por defecto reproduce el tajo al ver este valor en la herramienta.
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool

	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Slash")
	if sound then
		sound:Play()
	end

	Remotes.Swing:FireServer()
end

local function hook(instance: Instance)
	if instance:IsA("Tool") and instance:GetAttribute("Sword") and not hooked[instance] then
		hooked[instance] = true
		instance.Activated:Connect(function()
			swing(instance)
		end)
	end
end

local function watch(container: Instance)
	container.ChildAdded:Connect(hook)
	for _, child in container:GetChildren() do
		hook(child)
	end
end

function SwordController.start()
	player.CharacterAdded:Connect(function(character)
		watch(character)
		watch(player:WaitForChild("Backpack"))
	end)
	if player.Character then
		watch(player.Character)
		watch(player:WaitForChild("Backpack"))
	end
end

return SwordController
