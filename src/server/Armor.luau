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
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Armor = {}

local cfg = Config.Armor
local CRYSTAL = "gradeCrystal"
local random = Random.new()

-- La vida se redondea a enteros y los porcentajes a décimas de punto.
local function rolled(stat: string, base: number, quality, level: number): number
	local info = cfg.Stats[stat]
	local value = base * random:NextNumber(cfg.Roll.min, cfg.Roll.max) * quality.mult * ArmorStats.scaling(stat, level)
	return if info.flat then math.max(1, math.round(value)) else math.round(value * 1000) / 1000
end

-- Pieza nueva (sin id) de la dificultad `level`; `luck` divide el "1 entre N" de las calidades.
-- Con `forcedSlot` y `forcedQuality` no se tiran el hueco ni la calidad (modo de pruebas).
function Armor.roll(level: number, luck: number, forcedSlot: string?, forcedQuality: number?)
	local slot = forcedSlot or cfg.SlotOrder[random:NextInteger(1, #cfg.SlotOrder)]
	local qualityIndex = forcedQuality or math.max(Permanent.roll(cfg.Qualities, luck), 1)
	local quality = cfg.Qualities[qualityIndex]
	local stats = {}
	for _, stat in cfg.StatOrder do
		local base = cfg.Slots[slot].stats[stat]
		if base then
			table.insert(stats, { stat = stat, value = rolled(stat, base, quality, level) })
		end
	end
	for _ = 1, quality.mods do
		local mod = cfg.Mods[Modifiers.roll("armorMods", random)]
		if mod.stat == "health" and #stats + 1 == cfg.NoHealthAt then
			-- Se vuelve a tirar unas pocas veces (así sigue mandando el peso de cada modificador) y, si aun así
			-- sale vida, se coge el primero que no lo sea: nunca queda en un bucle.
			for _ = 1, 20 do
				mod = cfg.Mods[Modifiers.roll("armorMods", random)]
				if mod.stat ~= "health" then
					break
				end
			end
			if mod.stat == "health" then
				for _, other in cfg.Mods do
					if other.stat ~= "health" then
						mod = other
						break
					end
				end
			end
		end
		table.insert(stats,{ stat = mod.stat, value = rolled(mod.stat, mod.value, quality, level), bonus = true })
	end
	return { slot = slot, quality = qualityIndex, level = level, stats = stats }
end

-- Tira una pieza y la guarda sin equiparla. Con el inventario lleno
-- se desmonta sola. Devuelve la pieza y si se la ha quedado.
function Armor.give(player: Player, level: number, luck: number)
	if not PlayerData.read(player) or not Config.Dungeons[level] then
		return nil, false
	end
	local piece = Armor.roll(level, luck)
	return piece, Armor.store(player, piece, luck)
end

-- Guarda una pieza ya tirada (sin equiparla): con el inventario lleno se desmonta sola. Devuelve si se la ha quedado.
-- `luck` es la suerte con la que se tiró (para el aviso a todo el servidor de las muy raras).
function Armor.store(player: Player, piece, luck: number): boolean
	local data = PlayerData.read(player)
	if not data then
		return false
	end
	local quality = cfg.Qualities[piece.quality]
	local kept = #data.armor < cfg.MaxPieces
	if kept then
		PlayerData.editArmor(player, function(edited)
			piece.id = edited.nextArmorId
			edited.nextArmorId += 1
			table.insert(edited.armor, piece)
		end)
		Tell.notice(player, quality.color, "{name} ({quality})!", { name = ArmorStats.name(piece, player), quality = Lang.t(player, quality.name) })
	else
		local crystals = ArmorStats.salvage(piece)
		PlayerData.edit(player, function(edited)
			edited.items[CRYSTAL] += crystals
		end)
		Tell.notice(
			player,
			quality.color,
			if crystals > 0 then "Armor full: {name} salvaged (+{n} crystals)" else "Armor full: {name} salvaged",
			{ name = ArmorStats.name(piece, player), n = Format.short(crystals, player) }
		)
	end
	return kept
end

local function find(data, id: unknown)
	for position, piece in data.armor do
		if piece.id == id then
			return piece, position
		end
	end
	return nil
end

-- "Equipar mejores": en cada hueco, la pieza de más nota (ArmorStats.score) de las que tiene.
local function equipBest(player: Player)
	PlayerData.editArmor(player, function(edited)
		local best = {} -- [hueco] = { id, nota }
		for _, piece in edited.armor do
			local score = ArmorStats.score(piece)
			local current = best[piece.slot]
			if not current or score > current.score or (score == current.score and piece.id < current.id) then
				best[piece.slot] = { id = piece.id, score = score }
			end
		end
		for slot, entry in best do
			edited.armorWorn[slot] = entry.id
		end
	end)
end

-- Pone la pieza en su hueco (sustituye a la que hubiera) o la quita si ya estaba puesta.
local function onEquip(player: Player, id: unknown)
	if id == "best" then
		equipBest(player)
		return
	end
	local data = PlayerData.read(player)
	local piece = data and find(data, id)
	if not piece then
		return
	end
	PlayerData.editArmor(player, function(edited)
		edited.armorWorn[piece.slot] = if edited.armorWorn[piece.slot] == piece.id then nil else piece.id
	end)
end

-- Desmonta una pieza (id) o varias de una vez (lista de ids; pedido por el usuario: de una en una era muy lento).
-- De la lista solo cuentan los ids enteros de piezas que tiene y que NO lleva puestas: lo equipado se desmonta
-- solo de una en una, a propósito.
local function onSalvage(player: Player, ids: unknown)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local many = type(ids) == "table"
	local wanted, count = {}, 0
	for _, id in if many then ids :: { unknown } else { ids } do
		count += 1
		if count > cfg.MaxPieces then
			return
		end
		if type(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 then
			return
		end
		wanted[id] = true
	end
	-- Sin esperas entre validar y retirar: todo dentro del mismo cambio.
	PlayerData.editArmor(player, function(edited)
		local crystals = 0
		for position = #edited.armor, 1, -1 do
			local piece = edited.armor[position]
			local worn = edited.armorWorn[piece.slot] == piece.id
			if wanted[piece.id] and not (many and worn) then
				crystals += ArmorStats.salvage(piece)
				table.remove(edited.armor, position)
				if worn then
					edited.armorWorn[piece.slot] = nil
				end
			end
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

-- Con casco se esconden los sombreros, el pelo y lo de la cara del avatar, que lo atravesaban.
local HEADWEAR_TYPES = { [Enum.AccessoryType.Hat] = true, [Enum.AccessoryType.Hair] = true, [Enum.AccessoryType.Face] = true }
local HEADWEAR_ATTACHMENTS = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }

-- Pedido por el usuario: al ponerse un casco perdía la cabeza de su avatar (un sombrero enorme con forma de cabeza,
-- como el "Nerd"). Un sombrero que mide al menos el doble de ancho que la cabeza hace de cabeza: no se esconde.
local HEAD_REPLACEMENT_RATIO = 2
local function replacesHead(character: Model, handle: BasePart): boolean
	local head = character:FindFirstChild("Head")
	return head ~= nil and head:IsA("BasePart") and handle.Size.X >= head.Size.X * HEAD_REPLACEMENT_RATIO
end

local function hideHeadwear(character: Model, hidden: boolean)
	for _, item in character:GetChildren() do
		local handle = item:IsA("Accessory") and item:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") and not (item.AccessoryType == Enum.AccessoryType.Hat and replacesHead(character, handle)) then
			local attachment = handle:FindFirstChildWhichIsA("Attachment")
			if HEADWEAR_TYPES[item.AccessoryType] or (attachment and HEADWEAR_ATTACHMENTS[attachment.Name]) then
				local original = handle:GetAttribute("ArmorTransparency")
				if hidden and original == nil then
					handle:SetAttribute("ArmorTransparency", handle.Transparency)
					handle.Transparency = 1
				elseif not hidden and original ~= nil then
					handle.Transparency = original
					handle:SetAttribute("ArmorTransparency", nil)
				end
			end
		end
	end
end

-- El pelo y los sombreros pueden llegar después que el casco.
local function watchHeadwear(character: Model)
	character.ChildAdded:Connect(function(item)
		if item:IsA("Accessory") and character:FindFirstChild("Armor_helmet") then
			task.defer(hideHeadwear, character, true)
		end
	end)
end

-- Modelos de las piezas equipadas sobre el personaje. Con la armadura escondida (pedido por el usuario: que no se vea
-- lo que llevas) no se pone ninguno; sus estadísticas siguen contando.
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
		local piece = not data.armorHidden and find(data, data.armorWorn[slot])
		if piece then
			ArmorModel.attach(character, slot, piece.quality, piece.level)
		end
	end
	hideHeadwear(character, character:FindFirstChild("Armor_helmet") ~= nil)
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
	-- (Con Config.Test.Progress no: ese modo ya pone la armadura que tocaría a esa hora, ver PlayerData.)
	if RunService:IsStudio() and Config.Test.AllGear and (Config.Test.Progress or 0) <= 0 then
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
		watchHeadwear(character)
	end)
	player:GetAttributeChangedSignal("Armor_health"):Connect(function()
		applyHealth(player, false)
	end)
	-- La poción de vida entra y sale por Stats.maxHealth: al activarla o caducar se vuelve a poner la vida máxima.
	player:GetAttributeChangedSignal("Potion_health"):Connect(function()
		applyHealth(player, false)
	end)
	player:GetAttributeChangedSignal("Armor"):Connect(function()
		dress(player)
	end)
	player:GetAttributeChangedSignal("ArmorHidden"):Connect(function()
		dress(player)
	end)
	if player.Character then
		applyHealth(player, true)
		dress(player)
		watchHeadwear(player.Character)
	end
end

function Armor.start()
	Remotes.EquipArmor.OnServerEvent:Connect(onEquip)
	Remotes.SalvageArmor.OnServerEvent:Connect(onSalvage)
	Remotes.SetArmorHidden.OnServerEvent:Connect(function(player: Player, hidden: unknown)
		if type(hidden) == "boolean" then
			PlayerData.edit(player, function(edited)
				edited.armorHidden = hidden
			end)
		end
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Armor
