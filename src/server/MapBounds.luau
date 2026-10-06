-- Límite del mapa: un muro invisible alrededor de la isla (Config.Plot.LimitRadius), para que nadie se aleje
-- andando por el agua, y una red de seguridad por si alguien acaba fuera de todos modos (o cayendo por debajo del
-- mundo): vuelve a su parcela. Las arenas de las mazmorras quedan lejos, fuera del muro, y tienen su propia
-- barrera: quien está en una no cuenta.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Plots = require(script.Parent.Plots)

local MapBounds = {}

local SEGMENTS = 72 -- tramos del muro
local THICKNESS = 6
local BOTTOM, TOP = -120, 600 -- de dónde a dónde llega el muro (no se salta ni se pasa por debajo)
local SLACK = 25 -- studs por fuera del muro a partir de los que se da a alguien por perdido
local CHECK = 1 -- segundos entre repasos
local STRIKES = 2 -- repasos seguidos fuera antes de devolverlo (un viaje a medias no cuenta)

local function buildWall(radius: number)
	local folder = Instance.new("Folder")
	folder.Name = "MapBounds"
	-- Cada tramo es tangente al círculo; un poco de más de largo para que no queden rendijas entre ellos.
	local length = 2 * radius * math.tan(math.pi / SEGMENTS) + 1
	for index = 1, SEGMENTS do
		local angle = index / SEGMENTS * math.pi * 2
		local center = Vector3.new(math.cos(angle) * (radius + THICKNESS / 2), (BOTTOM + TOP) / 2, math.sin(angle) * (radius + THICKNESS / 2))
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanTouch = false
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Size = Vector3.new(THICKNESS, TOP - BOTTOM, length)
		wall.CFrame = CFrame.new(center) * CFrame.Angles(0, -angle, 0)
		wall.Parent = folder
	end
	folder.Parent = workspace
end

-- Si el personaje está donde no debería: más allá del muro o por debajo del lobby de mazmorras.
local function isLost(player: Player, radius: number): boolean
	if (player:GetAttribute("Dungeon") or 0) ~= 0 then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local position = root.Position
	return Vector2.new(position.X, position.Z).Magnitude > radius + SLACK or position.Y < Config.DungeonLobby.Floor - 80
end

local function sendHome(player: Player)
	local plot = Plots.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plot or not character or not root or not root:IsA("BasePart") then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
end

function MapBounds.start()
	local radius = Config.Plot.LimitRadius
	buildWall(radius)

	local strikes: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		strikes[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK)
			for _, player in Players:GetPlayers() do
				if isLost(player, radius) then
					strikes[player] = (strikes[player] or 0) + 1
					if strikes[player] >= STRIKES then
						strikes[player] = nil
						sendHome(player)
					end
				else
					strikes[player] = nil
				end
			end
		end
	end)
end

return MapBounds
