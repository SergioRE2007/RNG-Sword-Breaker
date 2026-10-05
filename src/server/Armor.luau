-- Armadura: piezas que caen en las mazmorras (Config.Armor). Aquí se tiran (hueco, calidad, stats y
-- modificadores), se equipan (una por hueco), se desmontan a cambio de Cristales de grado, y se aplican
-- al personaje: la vida máxima y el modelo de cada pieza equipada. Los demás stats los suma shared/Stats.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmorModel = require(ReplicatedStorage.Shared.ArmorModel)
local ArmorStats = require(ReplicatedStorage.Shared.ArmorStats)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)

local Armor = {}

local cfg = Config.Armor
local CRYSTAL = "gradeCrystal"
local random = Random.new()

-- La vida se redondea a enteros y los porcentajes a décimas de punto.
local function rolled(stat: string, base: number, quality, power: number): number
	local info = cfg.Stats[stat]
	local value = base * random:NextNumber(cfg.Roll.min, cfg.Roll.max) * quality.mult * (if info.scales == false then 1 else power)
	return if info.flat then math.max(1, math.round(value)) else math.round(value * 1000) / 1000
end

-- Pieza nueva (sin id) de la dificultad `level`; `luck` divide el "1 entre N" de las calidades.
-- Con `forcedSlot` y `forcedQuality` no se tiran el hueco ni la calidad (modo de pruebas).
function Armor.roll(level: number, luck: number, forcedSlot: string?, forcedQuality: number?)
	local slot = forcedSlot or cfg.SlotOrder[random:NextInteger(1, #cfg.SlotOrder)]
	local qualityIndex = forcedQuality or math.max(Permanent.roll(cfg.Qualities, luck), 1)
	local quality = cfg.Qualities[qualityIndex]
	local power = Config.Dungeons[level].power
	local stats = {}
	for _, stat in cfg.StatOrder do
		local base = cfg.Slots[slot].stats[stat]
		if base then
			table.insert(stats, { stat = stat, value = rolled(stat, base, quality, power) })
		end
	end
	for _ = 1, quality.mods do
		local mod = cfg.Mods[Modifiers.roll("armorMods", random)]
		table.insert(stats, { stat = mod.stat, value = rolled(mod.stat, mod.value, quality, power), bonus = true })
	end
	return { slot = slot, quality = qualityIndex, level = level, stats = stats }
end

-- Tira una pieza y se la da al jugador (se equipa sola si el hueco está libre). Con el inventario lleno
-- se desmonta sola. Devuelve la pieza y si se la ha quedado.
function Armor.give(player: Player, level: number, luck: number)
	local data = PlayerData.read(player)
	if not data or not Config.Dungeons[level] then
		return nil, false
	end
	local piece = Armor.roll(level, luck)
	local quality = cfg.Qualities[piece.quality]
	local kept = #data.armor < cfg.MaxPieces
	if kept then
		PlayerData.editArmor(player, function(edited)
			piece.id = edited.nextArmorId
			edited.nextArmorId += 1
			table.insert(edited.armor, piece)
			if not edited.armorWorn[piece.slot] then
				edited.armorWorn[piece.slot] = piece.id
			end
		end)
		Remotes.Notice:FireClient(player, `¡{ArmorStats.name(piece)}!\n{quality.name}`, quality.color)
	else
		local crystals = ArmorStats.salvage(piece)
		PlayerData.edit(player, function(edited)
			edited.items[CRYSTAL] += crystals
		end)
		Remotes.Notice:FireClient(player, `Armadura llena: {ArmorStats.name(piece)} desmontada\n+{Format.short(crystals)} {Config.Items[CRYSTAL].name}`, quality.color)
	end
	local odds = quality.odds / luck
	if odds >= Config.AnnounceOdds then
		Remotes.Announce:FireAllClients(`¡{player.DisplayName} ha conseguido {ArmorStats.name(piece)} de calidad {quality.name} (1 entre {Format.short(odds)})!`, quality.color)
	end
	return piece, kept
end

local function find(data, id: unknown)
	for position, piece in data.armor do
		if piece.id == id then
			return piece, position
		end
	end
	return nil
end

-- Pone la pieza en su hueco (sustituye a la que hubiera) o la quita si ya estaba puesta.
local function onEquip(player: Player, id: unknown)
	local data = PlayerData.read(player)
	local piece = data and find(data, id)
	if not piece then
		return
	end
	PlayerData.editArmor(player, function(edited)
		edited.armorWorn[piece.slot] = if edited.armorWorn[piece.slot] == piece.id then nil else piece.id
	end)
end

local function onSalvage(player: Player, id: unknown)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local piece, position = find(data, id)
	if not piece then
		return
	end
	local crystals = ArmorStats.salvage(piece)
	PlayerData.editArmor(player, function(edited)
		table.remove(edited.armor, position)
		if edited.armorWorn[piece.slot] == piece.id then
			edited.armorWorn[piece.slot] = nil
		end
		edited.items[CRYSTAL] += crystals
	end)
end

-- Vida máxima según la armadura; la vida actual conserva su proporción (ponerse y quitarse piezas no cura).
local function applyHealth(player: Player, full: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local maxHealth = Stats.maxHealth(player)
	local ratio = if full then 1 else math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = math.max(1, maxHealth * ratio)
end

-- Modelos de las piezas equipadas sobre el personaje.
local function dress(player: Player)
	local character = player.Character
	local data = PlayerData.read(player)
	if not character or not data then
		return
	end
	for _, slot in cfg.SlotOrder do
		local old = character:FindFirstChild("Armor_" .. slot)
		if old then
			old:Destroy()
		end
		local piece = find(data, data.armorWorn[slot])
		if piece then
			ArmorModel.attach(character, slot, piece.quality, piece.level)
		end
	end
end

-- Modo de pruebas (Config.Test.AllGear, solo en Studio; esa partida no se guarda, ver PlayerData): una pieza de
-- cada hueco de cada mazmorra, con la calidad subiendo de la primera mazmorra (Común) a la última (la mejor).
local function giveAll(player: Player)
	local data = PlayerData.read(player)
	for _ = 1, 100 do
		if data or not player.Parent then
			break
		end
		task.wait(0.1)
		data = PlayerData.read(player)
	end
	if not data then
		return
	end
	PlayerData.editArmor(player, function(edited)
		local levels = #Config.Dungeons
		for level = 1, levels do
			local quality = math.clamp(math.ceil(level / levels * #cfg.Qualities), 1, #cfg.Qualities)
			for _, slot in cfg.SlotOrder do
				if #edited.armor >= cfg.MaxPieces then
					return
				end
				local piece = Armor.roll(level, 1, slot, quality)
				piece.id = edited.nextArmorId
				edited.nextArmorId += 1
				table.insert(edited.armor, piece)
			end
		end
	end)
end

local function onPlayer(player: Player)
	if RunService:IsStudio() and Config.Test.AllGear then
		task.spawn(giveAll, player)
	end
	player.CharacterAdded:Connect(function(character)
		-- Espera a que el personaje esté montado (las partes del cuerpo llegan después que el Model).
		character:WaitForChild("Humanoid", 10)
		character:WaitForChild("LeftFoot", 3)
		task.wait(0.1)
		if player.Character == character then
			applyHealth(player, true)
			dress(player)
		end
	end)
	player:GetAttributeChangedSignal("Armor_health"):Connect(function()
		applyHealth(player, false)
	end)
	player:GetAttributeChangedSignal("Armor"):Connect(function()
		dress(player)
	end)
	if player.Character then
		applyHealth(player, true)
		dress(player)
	end
end

function Armor.start()
	Remotes.EquipArmor.OnServerEvent:Connect(onEquip)
	Remotes.SalvageArmor.OnServerEvent:Connect(onSalvage)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Armor
