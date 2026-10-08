-- Convierte los clics con la espada equipada en espadazos: animación, sonido y aviso al servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ForgeScene = require(script.Parent.ForgeScene)
local SwingAnim = require(script.Parent.SwingAnim)

local SwordController = {}

-- Si se le pone una función, se llama en cada espadazo que sale (la usa HitboxDebug, el modo de pruebas).
SwordController.onSwing = nil :: (() -> ())?

local player = Players.LocalPlayer
local hooked = setmetatable({}, { __mode = "k" })
local lastSwing = 0

local function swing(tool: Tool)
	-- En la forja el clic es el martillazo: ni animación de ataque ni espadazo (el servidor tampoco se entera).
	if ForgeScene.isActive() then
		return
	end
	local now = os.clock()
	local cooldown = Stats.cooldown(player)
	if now - lastSwing < cooldown then
		return
	end
	lastSwing = now

	if not SwingAnim.play(player.Character, cooldown, (Stats.weapon(player))) then
		-- Sin esqueleto R15: el script Animate por defecto reproduce el tajo al ver este valor en la herramienta.
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
	end

	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Slash")
	if sound then
		sound:Play()
	end

	Remotes.Swing:FireServer()
	if SwordController.onSwing then
		SwordController.onSwing()
	end
end

local function hook(instance: Instance)
	if instance:IsA("Tool") and instance:GetAttribute("Sword") and not hooked[instance] then
		hooked[instance] = true
		instance.Activated:Connect(function()
			swing(instance)
		end)
	end
end

-- Al entrar en la partida, el servidor pone la espada en la mano antes de que este cliente esté listo: se ve en la
-- mano, pero Roblox no la da por equipada y los clics no hacían nada hasta cambiar de arma. Si un arma está en la
-- mano y no llega su aviso de equipada, se suelta: el servidor (Swords) la vuelve a poner, y esa vez llega bien.
local RETRIES = 5 -- intentos por partida, por si algo raro la dejara soltándose sin parar
local retries = 0

local function ensureEquipped(instance: Instance)
	if not (instance:IsA("Tool") and instance:GetAttribute("Sword")) then
		return
	end
	local equipped = false
	local connection = instance.Equipped:Connect(function()
		equipped = true
	end)
	task.delay(0.6, function()
		connection:Disconnect()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not equipped and humanoid and instance.Parent == character and retries < RETRIES then
			retries += 1
			humanoid:UnequipTools()
		end
	end)
end

local function watch(container: Instance)
	local inHand = container == player.Character
	container.ChildAdded:Connect(function(child)
		hook(child)
		if inHand then
			ensureEquipped(child)
		end
	end)
	for _, child in container:GetChildren() do
		hook(child)
		if inHand then
			ensureEquipped(child)
		end
	end
end

-- Da un espadazo con la espada que lleva en la mano, como si hubiera hecho clic (lo usa el modo automático de
-- las mazmorras). Pasa por el mismo tiempo de espera que los clics.
function SwordController.swing()
	local character = player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if tool and tool:GetAttribute("Sword") then
		swing(tool)
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
