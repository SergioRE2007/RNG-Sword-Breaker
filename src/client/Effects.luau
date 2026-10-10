-- Efectos visuales locales: números de daño (los anima client/FloatText), barra de vida, temblor y escombros con físicas.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local ObjectModel = require(ReplicatedStorage.Shared.ObjectModel)
local ObjectSpec = require(ReplicatedStorage.Shared.ObjectSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FloatText = require(script.Parent.FloatText)
local ObjectBreak = require(script.Parent.ObjectBreak)
local Performance = require(script.Parent.Performance)
local Sfx = require(script.Parent.Sfx)

local Effects = {}

local FRAGMENT_LIFETIME = 2.5
local FRAGMENT_FADE = 0.5
local HEALTH_BAR_TIMEOUT = 2
local POPUP_HEIGHT = 12 -- altura máxima sobre el suelo a la que salen los premios de un objeto roto
local ROLL_POPUP_SCALE = 1.5 -- desde este tamaño (escala) se anuncian las tiradas de un objeto aunque sea común y dé una sola
local BREAK_SIZE = 6 -- diagonal (studs) del objeto que rompe con el tono normal: los mayores suenan más graves
local COIN_CHAIN = 1.2 -- segundos: las monedas que caen más seguidas que esto van cambiando de nota
local COIN_NOTES = { 0, 2, 4, 7, 9, 12 } -- semitonos de la racha de monedas: sube por la escala y vuelve a bajar
local COIN_GAP = 0.07 -- segundos entre dos monedas que caen a la vez
local COIN_QUEUE = 0.5 -- con más espera que esta, las monedas de más ya no suenan

local player = Players.LocalPlayer
local rng = Random.new()

local healthBar, healthFill, healthLabel
local healthConnection
local healthToken = 0

local function createHealthBar()
	healthBar = Instance.new("BillboardGui")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.fromOffset(150, 36)
	healthBar.AlwaysOnTop = true
	healthBar.Enabled = false
	healthBar.ResetOnSpawn = false
	healthBar.Parent = player:WaitForChild("PlayerGui")

	healthLabel = Instance.new("TextLabel")
	healthLabel.Size = UDim2.new(1, 0, 0, 18)
	healthLabel.BackgroundTransparency = 1
	healthLabel.TextColor3 = Color3.new(1, 1, 1)
	healthLabel.TextStrokeTransparency = 0.3
	healthLabel.Font = Enum.Font.FredokaOne
	healthLabel.TextSize = 14
	healthLabel.Parent = healthBar

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 20)
	back.Size = UDim2.new(1, 0, 0, 12)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	back.BorderSizePixel = 0
	back.Parent = healthBar

	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = back
end

local function showHealth(part: BasePart)
	local function refresh()
		local hp = part:GetAttribute("HP") or 0
		local maxHp = part:GetAttribute("MaxHP") or 1
		healthFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		healthLabel.Text = `{part.Name}  {Format.multiplier(hp)}/{Format.multiplier(maxHp)}`
	end

	if healthBar.Adornee ~= part then
		if healthConnection then
			healthConnection:Disconnect()
		end
		healthBar.Adornee = part
		healthBar.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0)
		healthConnection = part:GetAttributeChangedSignal("HP"):Connect(refresh)
	end
	refresh()
	healthBar.Enabled = true

	healthToken += 1
	local token = healthToken
	task.delay(HEALTH_BAR_TIMEOUT, function()
		if token == healthToken then
			healthBar.Enabled = false
		end
	end)
end

local function shake(part: BasePart)
	-- La caja sólida permanece inmóvil: sacudirla podía empujar al jugador hacia el suelo.
	if part.CanCollide then
		for _, child in part:GetDescendants() do
			if child:IsA("BasePart") and not child.CanCollide then shake(child) end
		end
		return
	end
	local origin = part.CFrame
	local nudge = Vector3.new(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	local tween = TweenService:Create(part, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { CFrame = origin + nudge })
	tween.Completed:Connect(function()
		if part.Parent then
			part.CFrame = origin
		end
	end)
	tween:Play()
end

local function shatter(cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material)
	if Performance.get() then return end -- modo rendimiento
	-- Entre 2 y 3 trozos por eje: máximo 27 piezas por objeto.
	local cell = math.max(size.X, size.Y, size.Z) / 3
	local nx = math.clamp(math.round(size.X / cell), 2, 3)
	local ny = math.clamp(math.round(size.Y / cell), 2, 3)
	local nz = math.clamp(math.round(size.Z / cell), 2, 3)
	local pieceSize = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local force = 12 + math.sqrt(size.Magnitude) * 4

	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local offset = Vector3.new(
					(ix - 0.5) / nx * size.X - size.X / 2,
					(iy - 0.5) / ny * size.Y - size.Y / 2,
					(iz - 0.5) / nz * size.Z - size.Z / 2
				)
				local piece = Instance.new("Part")
				piece.Size = pieceSize
				piece.Color = color
				piece.Material = material
				piece.TopSurface = Enum.SurfaceType.Smooth
				piece.BottomSurface = Enum.SurfaceType.Smooth
				piece.CollisionGroup = "Debris"
				piece.CFrame = cframe * CFrame.new(offset)
				piece.Parent = workspace

				local outward = cframe:VectorToWorldSpace(offset)
				outward = Vector3.new(outward.X, 0, outward.Z)
				local direction = if outward.Magnitude > 0.01 then outward.Unit else Vector3.zero
				piece.AssemblyLinearVelocity = direction * force * rng:NextNumber(0.5, 1.2)
					+ Vector3.new(0, force * rng:NextNumber(0.6, 1.4), 0)
				piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))

				task.delay(FRAGMENT_LIFETIME, function()
					TweenService:Create(piece, TweenInfo.new(FRAGMENT_FADE), { Transparency = 1 }):Play()
				end)
				Debris:AddItem(piece, FRAGMENT_LIFETIME + FRAGMENT_FADE)
			end
		end
	end
end

-- Moneda de un objeto roto: con una racha, cada una suena una nota más arriba (y al llegar al final, de vuelta).
-- Las que caen a la vez (un golpe que rompe varios objetos) suenan una detrás de otra.
local coinStep, lastCoin = 0, 0
local function coinSound(where: Vector3)
	local now = os.clock()
	local at = math.max(now + 0.06, lastCoin + COIN_GAP) -- un pelín después de la rotura, para que no la tape
	if at - now > COIN_QUEUE then
		return
	end
	coinStep = if at - lastCoin < COIN_CHAIN then coinStep + 1 else 0
	lastCoin = at
	local phase = coinStep % (2 * #COIN_NOTES - 2)
	local note = COIN_NOTES[if phase < #COIN_NOTES then phase + 1 else 2 * #COIN_NOTES - 1 - phase]
	task.delay(at - now, Sfx.play, "coin_break", 1, 2 ^ (note / 12), where)
end

function Effects.start()
	createHealthBar()

	Remotes.Hit.OnClientEvent:Connect(function(hitter: Player, part: BasePart?, position: Vector3, damage: number)
		-- Cajas: número compacto; enemigos: de impacto, más grande si es el golpe que lo remata (vida que le quedaba).
		local box = part ~= nil and CollectionService:HasTag(part, "Destructible")
		FloatText.spawn(if box then "box" else "enemy", position, Format.short(damage), {
			target = if part and part.Parent then part else nil,
			final = part ~= nil and damage >= (part:GetAttribute("HP") or math.huge),
			other = hitter ~= player,
		})
		local sound = if box then "hit_" .. Sfx.family((part :: BasePart):GetAttribute("Index")) else "hit_enemy"
		-- Sale del sitio del golpe; los de los demás, algo más flojos (y con la distancia se van apagando).
		Sfx.play(sound, if hitter == player then 1 else 0.7, nil, position)
		if part and part.Parent then
			-- Los enemigos de las mazmorras se mueven solos (no anclados): no se sacuden.
			if part.Anchored then
				shake(part)
			end
			-- La vida de los objetos de la parcela ya la enseña su cartel (client/ObjectInfo); la barra es para los enemigos.
			if hitter == player and not CollectionService:HasTag(part, "Destructible") then
				showHealth(part)
			end
		end
	end)

	-- `info` = { quality, scale, luck, rolls } del objeto roto (sin él, un enemigo de mazmorra).
	Remotes.Broken.OnClientEvent:Connect(function(breaker: Player, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material, reward: number, gems: number, objectIndex: number?, info)
		if objectIndex and ObjectModel.has(objectIndex) then
			if not Performance.get() then
				ObjectBreak.play(cframe, size, objectIndex)
			end
		elseif objectIndex then
			shatter(cframe, size, color, material)
		end
		-- Los enemigos de mazmorra (sin objectIndex) no sueltan trozos al morir: solo sonido.
		-- Cuanto mejor era el objeto (su rareza), más espectáculo al romperse.
		local quality = if info then info.quality or 1 else 1
		if quality > 1 and not Performance.get() then
			ObjectBreak.burst(cframe, size, quality)
		end
		-- Cada material rompe con su sonido y, cuanto más grande el objeto, más grave y más fuerte.
		local big = math.clamp(size.Magnitude / BREAK_SIZE, 0.5, 6)
		local family = if objectIndex then Sfx.family(objectIndex) else "enemy"
		Sfx.play("break_" .. family, (if breaker == player then 1 else 0.7) * math.min(big ^ 0.2, 1.3), big ^ -0.25, cframe.Position)
		if breaker == player then
			healthBar.Enabled = false
			-- Los números salen a la altura de los ojos aunque el objeto sea altísimo.
			local top = cframe.Position + Vector3.new(0, math.min(size.Y / 2 + 1, POPUP_HEIGHT - size.Y / 2), 0)
			if reward > 0 then
				FloatText.spawn("coin", top, "+" .. Format.short(reward))
				coinSound(top)
			end
			if gems > 0 then
				FloatText.spawn("gem", top + Vector3.new(0, 2, 0), `+{Format.short(gems)} gemas`)
				task.delay(0.13, Sfx.play, "gem_break", nil, nil, top)
			end
			-- Tiradas de arma que ha dado: se anuncian cuando el objeto tenía algo de especial (varias tiradas, rareza
			-- o buen tamaño); las de un objeto corriente ya se ven en el panel de arriba.
			if info and info.rolls > 0 and (info.rolls > 1 or info.scale >= ROLL_POPUP_SCALE or quality > 1) then
				local rolls = if info.rolls == 1 then "1 tirada" else `¡{info.rolls} tiradas!`
				FloatText.spawn("notice", top + Vector3.new(0, 4.5, 0), `{rolls}  ·  suerte x{Format.multiplier(info.luck)}`, {
					color = ObjectSpec.rarity(quality).color:Lerp(Color3.new(1, 1, 1), 0.25),
					emphasis = if quality >= 4 or info.rolls > 1 then 1.5 else 1.15,
				})
			end
			if quality >= 5 then
				Sfx.play("win")
			elseif quality >= 3 then
				Sfx.play("rare")
			end
		end
	end)
end

return Effects
