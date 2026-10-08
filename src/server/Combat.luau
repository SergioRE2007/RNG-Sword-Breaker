-- Recibe los espadazos del cliente, los valida y aplica el daño.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Destructibles = require(script.Parent.Destructibles)
local Dungeons = require(script.Parent.Dungeons)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Gacha = require(script.Parent.Gacha)
local Gear = require(script.Parent.Gear)
local Potions = require(script.Parent.Potions)
local Traits = require(script.Parent.Traits)
local PlayerData = require(script.Parent.PlayerData)
local Missions = require(script.Parent.Missions)
local Permanent = require(ReplicatedStorage.Shared.Permanent)

local Combat = {}

local TICK = 0.05 -- cada cuánto se mira si un espadazo en marcha alcanza algo nuevo

local lastSwing = {} -- [Player] = os.clock()
-- Espadazos en marcha. El golpe no es solo el instante del clic: sigue vivo mientras dura la animación
-- (Config.SwingWindow) y golpea a lo que vaya entrando en su alcance, cada objeto o enemigo una sola vez.
local swings = {} -- [Player] = { tool, ends, range, arc, damage, hit = { [BasePart] = true } }
local elapsed = 0

-- Aplica un espadazo en marcha a lo que alcanza ahora mismo y aún no había golpeado. Devuelve false si ya no
-- puede seguir (el jugador ha muerto o ha soltado el arma).
local function strike(player: Player, swing): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or swing.tool.Parent ~= character then
		return false
	end
	local damage = swing.damage
	for _, part in Destructibles.getInRange(player, root.CFrame, swing.range, swing.arc) do
		if swing.hit[part] then
			continue
		end
		swing.hit[part] = true
		Remotes.Hit:FireAllClients(player, part, part.Position, damage)
		-- Dónde estaba y cuánto medía, antes de que desaparezca: de ahí sale su premio en la pantalla del jugador.
		local origin, box = part.Position, part.Size
		local broken, coins, gems, object = Destructibles.damage(part, damage, player)
		if broken then
			PlayerData.addCoins(player, coins)
			Missions.add(player, "breaks")
			if gems > 0 then
				PlayerData.addGems(player, gems)
			end
			-- Tiradas de arma del objeto: cuántas y con qué suerte se decidió al aparecer (tipo, rareza y tamaño).
			Gacha.give(player, object.luck, "object", object.rolls, { name = broken.name, quality = object.quality, origin = origin, box = box, objectOdds = object.odds })
			Traits.onBroken(player, broken)
			Gear.onBroken(player)
			Potions.onBroken(player, broken, object)
		end
	end
	-- Enemigos de la mazmorra, si está en una.
	Dungeons.strike(player, root.CFrame, swing.range, swing.arc, damage, swing.hit)
	return true
end

local function onSwing(player: Player)
	local now = os.clock()
	-- Margen del 20% para que el lag no descarte golpes legítimos.
	local cooldown = Stats.cooldown(player)
	if now - (lastSwing[player] or 0) < cooldown * 0.8 then
		return
	end
	lastSwing[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then
		return
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.SwingFx:FireClient(other, player)
		end
	end

	local sword = Config.Swords[PlayerData.getSwordLevel(player)]
	local _, kind = Stats.weapon(player)
	-- El daño y el alcance son los del momento del clic. Un espadazo nuevo sustituye al que estuviera en marcha.
	local swing = {
		tool = tool,
		ends = if Config.SwingWindow > 0 then now + cooldown * Config.SwingWindow + Config.SwingLag else now,
		-- El tamaño del arma (Permanent) alarga su hoja y con ella el alcance.
		range = Config.BaseRange + sword.bladeLength * Permanent.scale(Stats.equipped(player)),
		arc = kind.arc,
		damage = Stats.damage(player),
		hit = {},
	}
	swings[player] = swing
	if not strike(player, swing) and swings[player] == swing then
		swings[player] = nil
	end
end

-- Sigue los espadazos en marcha hasta que se les acaba el tiempo.
local function step(dt: number)
	if next(swings) == nil then
		return
	end
	elapsed += dt
	if elapsed < TICK then
		return
	end
	elapsed = 0
	local now = os.clock()
	for player, swing in swings do
		if (now > swing.ends or not strike(player, swing)) and swings[player] == swing then
			swings[player] = nil
		end
	end
end

function Combat.start()
	Remotes.Swing.OnServerEvent:Connect(onSwing)
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		swings[player] = nil
	end)
end

return Combat
