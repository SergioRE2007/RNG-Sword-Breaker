-- Gacha de espadas: tiradas gratis desde cualquier sitio (una cada Stats.rollTime segundos),
-- máquina decorativa en el centro del hub e inventario (equipar, vender y venta automática).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)

local Gacha = {}

local machinePosition = Vector3.new(0, Config.Plot.FloorHeight, 0)

-- Prueba de la más rara a la más común; la suerte multiplica cada probabilidad.
local function roll(luck: number): number
	for index = #Config.Swords, 2, -1 do
		local rarity = Config.Swords[index].rarity
		if rarity and Chance.roll(luck / rarity) then
			return index
		end
	end
	return 2
end

-- Saca una espada con suerte `luck` y la guarda como una copia más (se equipa si pega más que
-- la actual). Se vende sola si es menos rara que el límite de venta automática del jugador o
-- el inventario está lleno. Se lo manda al jugador para que lo enseñe, y si es raro, a todos
-- (aura en su personaje); si es muy raro, aviso en el chat cuando acaba la animación.
local function draw(player: Player, luck: number, source: string)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local index = roll(luck)
	local sword = Config.Swords[index]
	local odds = sword.rarity / luck
	if odds >= Config.AnnounceOdds then
		task.delay(Config.Gacha.RollTime + Config.Gacha.ShowcaseTime, function()
			Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha conseguido {sword.name} (1 entre {Format.short(sword.rarity)})!`, sword.color)
		end)
	end
	local kept = sword.rarity >= data.autoSell and #data.swords < Config.MaxSwords
	if kept then
		local better = sword.damage > Stats.swordDamage(Stats.equipped(player))
		PlayerData.edit(player, function(edited)
			local id = edited.nextSwordId
			edited.nextSwordId += 1
			table.insert(edited.swords, { id = id, sword = index })
			if better then
				edited.equipped = id
			end
		end)
	else
		PlayerData.addGems(player, Config.Gacha.SellValue)
	end
	Remotes.GachaRolled:FireClient(player, index, kept, luck, source)
	if sword.rarity >= Config.Gacha.AuraRarity then
		-- Espera a que el jugador lo destape para no destriparlo a los demás.
		task.delay(Stats.rollTime(player), function()
			Remotes.GachaAura:FireAllClients(player, index)
		end)
	end
end

-- Espada gratis (p. ej. la roca de armas) con la suerte de gacha multiplicada por `luckMultiplier`.
function Gacha.give(player: Player, luckMultiplier: number, source: string)
	draw(player, Stats.gachaLuck(player) * luckMultiplier, source)
end

local lastRoll = {} -- [player] = os.clock() de su última tirada

local function onRoll(player: Player)
	-- Un poco de margen por el retraso de la red.
	local now = os.clock()
	if now - (lastRoll[player] or 0) < Stats.rollTime(player) * 0.85 then
		return
	end
	lastRoll[player] = now
	draw(player, Stats.gachaLuck(player), "gacha")
end

local function onEquip(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if data and PlayerData.findSword(data, id) then
		PlayerData.edit(player, function(edited)
			edited.equipped = id
		end)
	end
end

local function onSell(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if not data or id == data.equipped then
		return
	end
	local _, position = PlayerData.findSword(data, id)
	if position then
		PlayerData.edit(player, function(edited)
			table.remove(edited.swords, position)
			edited.gems += Config.Gacha.SellValue
		end)
	end
end

local function onSetAutoSell(player: Player, rarity: unknown)
	-- rarity ~= rarity descarta NaN.
	if type(rarity) ~= "number" or rarity ~= rarity or rarity < 0 then
		return
	end
	PlayerData.edit(player, function(edited)
		edited.autoSell = rarity
	end)
end

local function buildMachine(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Gacha"

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Shape = Enum.PartType.Cylinder
	base.Anchored = true
	base.Size = Vector3.new(3, 7, 7)
	base.CFrame = CFrame.new(machinePosition + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(60, 50, 90)
	base.Material = Enum.Material.Metal
	base.Parent = model

	local orb = Instance.new("Part")
	orb.Name = "Orb"
	orb.Shape = Enum.PartType.Ball
	orb.Anchored = true
	orb.Size = Vector3.new(5, 5, 5)
	orb.Position = machinePosition + Vector3.new(0, 5.5, 0)
	orb.Color = Color3.fromRGB(190, 110, 255)
	orb.Material = Enum.Material.Neon
	orb.Parent = model

	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Range = 24
	light.Parent = orb

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 76)
	gui.StudsOffset = Vector3.new(0, 5.5, 0)
	gui.MaxDistance = 250
	gui.Parent = orb

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 225, 60)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 28
	label.Text = "Gacha de espadas\n¡Gratis!"
	label.Parent = gui

	model.Parent = parent
end

function Gacha.start()
	buildMachine(workspace:WaitForChild("Map"))
	Remotes.RollGacha.OnServerEvent:Connect(onRoll)
	Remotes.EquipSword.OnServerEvent:Connect(onEquip)
	Remotes.SellSword.OnServerEvent:Connect(onSell)
	Remotes.SetAutoSell.OnServerEvent:Connect(onSetAutoSell)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return Gacha
