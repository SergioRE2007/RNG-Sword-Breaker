-- Combate: las armas equipadas del jugador (hasta Config.Loadout.Slots) vuelan al objetivo que elige con un clic y le
-- pegan, cada una a su ritmo, hasta romperlo. El cliente solo pide el objetivo (Attack); aquí se valida (un objeto de su
-- parcela o un enemigo de su partida, vivo y dentro de su círculo), se lleva el reloj de cada arma y se reparte el daño.
--   · Objeto roto: fin del ataque (con el autoclicker o el Auto encendidos, saltan al siguiente objeto del círculo).
--     Enemigo muerto: las armas saltan al más cercano del círculo.
--   · Hachas y martillos salpican alrededor del objetivo y las lanzas atraviesan lo que hay detrás (Hitbox.spread).
--   · El objetivo se publica en el ObjectValue "AttackTarget" del jugador, para que todos vean adónde vuelan sus armas
--     (client/OrbitWeapons); cada golpe avisa con Hit y el hueco del arma que lo ha dado.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
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

local Combat = {}

local TICK = 0.05 -- cada cuánto se mira si a algún arma le toca pegar
local LAG = 3 -- studs de más al elegir objetivo: el servidor ve moverse al jugador con algo de retraso
local MIN_GAP = 0.05 -- segundos mínimos entre dos peticiones de un mismo jugador
local PROFILE_LIFE = 0.5 -- segundos que vale la ficha de armas de un jugador antes de volver a calcularla

-- Ataques en marcha: `enemy` = el objetivo es un enemigo de mazmorra (si no, un objeto de su parcela), `arrive` = cuándo
-- llegan las armas (antes no pega ninguna) y `at` = dónde estaba el objetivo la última vez que se miró.
local attacks = {} -- [Player] = { target: BasePart, enemy: boolean, arrive: number, at: Vector3 }
-- Cuándo puede volver a pegar cada arma. No se reinicia al cambiar de objetivo: hacer clic deprisa no da más daño.
local clocks = {} -- [Player] = { [hueco] = os.clock() }
local profiles = {} -- [Player] = { at = os.clock(), weapons = { { damage, cooldown, kind, length } } }
local holders = {} -- [Player] = su ObjectValue "AttackTarget"
local lastAsk = {} -- [Player] = os.clock() de su última petición
local elapsed = 0

-- Raíz del personaje, solo si está vivo.
local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

-- Sus armas equipadas, por hueco, con lo que hace falta para pegar: daño, tiempo entre golpes, tipo y largo. Se guarda
-- un momento para no leer el inventario entero en cada vuelta.
local function weapons(player: Player)
	local now = os.clock()
	local profile = profiles[player]
	if profile and now - profile.at < PROFILE_LIFE then
		return profile.weapons
	end
	local list = {}
	for slot, copy in Stats.loadout(player) do
		local _, kind = Stats.kind(copy)
		list[slot] = {
			damage = Stats.weaponDamage(player, copy),
			cooldown = Stats.weaponCooldown(player, copy),
			kind = kind,
			-- El tamaño del arma (Permanent) ya no alarga nada: da daño y aspecto.
			length = Config.Swords[copy.sword].bladeLength,
		}
	end
	profiles[player] = { at = now, weapons = list }
	return list
end

-- Pone (o quita, sin pieza) el objetivo del jugador. `travel` = segundos que tardan las armas en llegar.
local function setTarget(player: Player, target: BasePart?, enemy: boolean?, travel: number?)
	if target then
		attacks[player] = { target = target, enemy = enemy == true, arrive = os.clock() + (travel or Config.Loadout.Travel), at = target.Position }
	else
		attacks[player] = nil
	end
	local holder = holders[player]
	if holder then
		holder.Value = target
	end
end

-- Golpe de un arma a un objeto de la parcela. Si lo rompe, reparte lo que da y devuelve true.
local function hitObject(player: Player, part: BasePart, damage: number, slot: number): boolean
	Remotes.Hit:FireAllClients(player, part, part.Position, damage, slot)
	-- Dónde estaba y cuánto medía, antes de que desaparezca: de ahí sale su premio en la pantalla del jugador.
	local origin, box = part.Position, part.Size
	local broken, coins, gems, object = Destructibles.damage(part, damage, player)
	if not broken then
		return false
	end
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
	return true
end

-- Golpe de un arma: a su objetivo y, si salpica o atraviesa, a lo que tenga alrededor o detrás (con todo su daño).
local function blow(player: Player, attack, weapon, slot: number, root: BasePart)
	local target: BasePart = attack.target
	local origin, range, arc = Hitbox.spread(weapon.kind, weapon.length, root.Position, target.Position)
	if attack.enemy then
		Dungeons.hit(player, target, weapon.damage, root.Position, slot)
		if origin then
			Dungeons.strike(player, origin, range, arc, weapon.damage, { [target] = true }, slot)
		end
	else
		-- Los de alrededor se miran antes de pegar al objetivo, que puede desaparecer con el golpe.
		local others = if origin then Destructibles.getInRange(player, origin, range, arc) else {}
		hitObject(player, target, weapon.damage, slot)
		for _, part in others do
			if part ~= target then
				hitObject(player, part, weapon.damage, slot)
			end
		end
	end
end

local function alive(player: Player, attack): boolean
	if attack.enemy then
		return Dungeons.isEnemy(player, attack.target)
	end
	return Destructibles.owns(player, attack.target)
end

-- El objetivo ya no vale (roto, muerto o demasiado lejos). De un enemigo se salta al más cercano del círculo, si queda
-- alguno. Un objeto acaba el ataque, salvo con el autoclicker o el Auto encendidos (los decide server/AutoPlay): entonces
-- las armas siguen solas con el objeto más cercano del círculo, sin esperar a que el cliente lo pida (pedido por el
-- usuario: se quedaban un momento paradas entre objeto y objeto).
local function release(player: Player, attack, root: BasePart)
	local radius = Config.Loadout.Radius
	local nextTarget: BasePart? = nil
	if attack.enemy then
		nextTarget = Dungeons.nearest(player, attack.at, root.Position, radius)
	elseif player:GetAttribute("AutoClick") == true or player:GetAttribute("AutoFarm") == true then
		nextTarget = Destructibles.nearest(player, attack.at, root.Position, radius)
	end
	setTarget(player, nextTarget, attack.enemy, Config.Loadout.Chain)
end

local function onAttack(player: Player, part: unknown)
	local now = os.clock()
	if now - (lastAsk[player] or 0) < MIN_GAP then
		return
	end
	lastAsk[player] = now
	if part == nil then
		setTarget(player, nil)
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	-- Si ya van a por él, el vuelo no empieza otra vez.
	local current = attacks[player]
	if current and current.target == part then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local enemy = Dungeons.isEnemy(player, part)
	if not enemy and not Destructibles.owns(player, part) then
		return
	end
	if not Hitbox.within(part, root.Position, Config.Loadout.Radius + LAG) then
		return
	end
	setTarget(player, part, enemy)
end

local function step(dt: number)
	if next(attacks) == nil then
		return
	end
	elapsed += dt
	if elapsed < TICK then
		return
	end
	elapsed = 0
	local now = os.clock()
	local reach = Config.Loadout.Radius + Config.Loadout.Leash
	for player, attack in attacks do
		local root = rootOf(player)
		if not root then
			setTarget(player, nil)
			continue
		end
		if not alive(player, attack) or not Hitbox.within(attack.target, root.Position, reach) then
			release(player, attack, root)
			continue
		end
		attack.at = attack.target.Position
		if now < attack.arrive then
			continue
		end
		local clock = clocks[player]
		for slot, weapon in weapons(player) do
			local due = clock[slot] or 0
			if now < due then
				continue
			end
			-- Si viene pegando, el siguiente golpe cuenta desde cuando le tocaba a este (así la vuelta no le quita
			-- ritmo); si llevaba un rato parada, desde ahora.
			clock[slot] = (if now - due > TICK * 2 then now else due) + weapon.cooldown
			blow(player, attack, weapon, slot, root)
			if not alive(player, attack) then
				release(player, attack, root)
				break
			end
		end
	end
end

local function onPlayer(player: Player)
	clocks[player] = {}
	local holder = Instance.new("ObjectValue")
	holder.Name = "AttackTarget"
	holder.Parent = player
	holders[player] = holder
	-- Al cambiar de armas, la ficha se rehace en el siguiente golpe.
	for _, attribute in { "Loadout", "Swords" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			profiles[player] = nil
		end)
	end
end

function Combat.start()
	Remotes.Attack.OnServerEvent:Connect(onAttack)
	RunService.Heartbeat:Connect(step)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		attacks[player] = nil
		clocks[player] = nil
		profiles[player] = nil
		holders[player] = nil
		lastAsk[player] = nil
	end)
end

return Combat
