-- Efectos de las pociones en el personaje (Config.Potions). Cada poción activa deja un efecto suave de partículas con el
-- estilo de su familia ("fx"), que crece con el tier (Config.Potions.Fx): más partículas y más grandes, una luz desde
-- cierto tier y, desde Exclusiva, destellos grandes en el pecho (los de Divina, los más). Depende solo de los atributos
-- del Player ("Potion_<familia>", que publica el servidor): al caducar la poción el efecto se quita y al reaparecer el
-- personaje se vuelve a poner. De los demás jugadores solo se ve su mejor poción (no llenar la pantalla); de uno mismo,
-- todas. Las partículas salen de una pieza invisible más grande que el cuerpo, soldada a la raíz (si salieran de la
-- raíz, que es pequeña, nacerían dentro del cuerpo y quedarían tapadas). El modo rendimiento (Performance) apaga las
-- partículas y luces del mundo, estas incluidas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)

local PotionFx = {}

local player = Players.LocalPlayer
local cfg = Config.Potions

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local PREFIX = "PotionFx_" -- nombre de lo que cuelga de la pieza de efectos, más la familia
local VOLUME = PREFIX .. "Volume"
local VOLUME_SIZE = Vector3.new(5, 7, 5) -- un poco más que el cuerpo
local WHITE = Color3.new(1, 1, 1)
local SHAPE = Enum.ParticleEmitterShape
local STYLE = Enum.ParticleEmitterShapeStyle
local IN_OUT = Enum.ParticleEmitterShapeInOut

-- Tamaño de una partícula: casi el inicial hasta pasada la mitad de la vida y de ahí hasta el final.
local function sizeCurve(start: number, finish: number)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, start),
		NumberSequenceKeypoint.new(0.6, start + (finish - start) * 0.25),
		NumberSequenceKeypoint.new(1, finish),
	})
end

-- Transparencia: casi igual hasta pasada la mitad de la vida y de ahí se apaga (si se apagara desde el principio, a
-- esta distancia las partículas apenas se ven).
local function fade(from: number)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(0.65, math.min(from + 0.1, 1)),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function emitter(attachment: Attachment, texture: string, color: ColorSequence, rate: number, props): ParticleEmitter
	local item = Instance.new("ParticleEmitter")
	item.Texture = texture
	item.Color = color
	item.LightEmission = 0.7 -- con 1 todo se vuelve blanco y no se distingue de qué es cada efecto
	item.Rate = rate
	item.Lifetime = NumberRange.new(0.8, 1.3)
	item.Speed = NumberRange.new(1, 2)
	item.Transparency = fade(0.05)
	for key, value in props do
		(item :: any)[key] = value
	end
	item.Parent = attachment
	return item
end

local function glow(color: Color3): ColorSequence
	return ColorSequence.new(color:Lerp(WHITE, 0.3), color)
end

-- Estilo de cada familia ("fx" de Config.Potions.Families): `at` = dónde se cuelga (relativo a la raíz del personaje) y
-- qué partículas saca, con `rate` y `size` ya escalados por el tier.
local STYLES = {
	-- Daño: brasas que se despegan del cuerpo y suben.
	embers = {
		at = Vector3.new(0, -0.5, 0),
		build = function(att, color, rate, size)
			emitter(att, FIRE, ColorSequence.new(Color3.fromRGB(255, 205, 90), color), rate, {
				Lifetime = NumberRange.new(0.7, 1.1),
				Speed = NumberRange.new(0.5, 1.5),
				Shape = SHAPE.Cylinder,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				Acceleration = Vector3.new(0, 4, 0),
				Size = sizeCurve(1 * size, 0),
				Transparency = fade(0.2),
			})
		end,
	},
	-- Velocidad de golpe: rachas finas que suben muy rápido pegadas al cuerpo, como si cortara el aire.
	gale = {
		at = Vector3.new(0, -1, 0),
		build = function(att, color, rate, size)
			emitter(att, SPARKLE, glow(color), rate * 1.2, {
				Lifetime = NumberRange.new(0.45, 0.7),
				Speed = NumberRange.new(0.5, 1),
				Shape = SHAPE.Cylinder,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				Acceleration = Vector3.new(0, 22, 0),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Squash = NumberSequence.new(2.5), -- alargadas en el sentido en que suben
				Size = sizeCurve(0.45 * size, 0.05),
				Transparency = fade(0.15),
			})
		end,
	},
	-- Vida: destellos verdes que suben despacio por todo el cuerpo.
	vitality = {
		at = Vector3.new(0, 0, 0),
		build = function(att, color, rate, size)
			emitter(att, SPARKLE, glow(color), rate * 0.9, {
				Lifetime = NumberRange.new(1.4, 2),
				Speed = NumberRange.new(0.3, 1),
				Shape = SHAPE.Cylinder,
				Acceleration = Vector3.new(0, 2.5, 0),
				RotSpeed = NumberRange.new(-40, 40),
				Size = sizeCurve(0.7 * size, 0.1),
			})
		end,
	},
	-- Suerte de cajas: lluvia de polvo dorado que cae desde encima de la cabeza.
	fortune = {
		at = Vector3.new(0, 4, 0),
		build = function(att, color, rate, size)
			emitter(att, SPARKLE, glow(color), rate, {
				Lifetime = NumberRange.new(1.6, 2.2),
				Speed = NumberRange.new(1, 2),
				Shape = SHAPE.Disc,
				EmissionDirection = Enum.NormalId.Bottom,
				SpreadAngle = Vector2.new(15, 15),
				RotSpeed = NumberRange.new(-90, 90),
				Size = sizeCurve(0.7 * size, 0.15),
			})
		end,
	},
	-- Suerte de armas: motas de luz que se quedan flotando alrededor del cuerpo, como un campo de estrellas.
	stars = {
		at = Vector3.new(0, 0, 0),
		build = function(att, color, rate, size)
			emitter(att, SPARKLE, glow(color), rate, {
				Lifetime = NumberRange.new(1.2, 1.8),
				Speed = NumberRange.new(0.2, 0.6),
				Shape = SHAPE.Sphere,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				RotSpeed = NumberRange.new(-120, 120),
				LockedToPart = true,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1 * size), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = fade(0),
			})
		end,
	},
	-- Suerte de grado: columna de destellos rosas que sube por el contorno del cuerpo.
	rank = {
		at = Vector3.new(0, 0, 0),
		build = function(att, color, rate, size)
			emitter(att, SPARKLE, glow(color), rate, {
				Lifetime = NumberRange.new(1, 1.5),
				Speed = NumberRange.new(0.2, 0.5),
				Shape = SHAPE.Cylinder,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				Acceleration = Vector3.new(0, 3, 0),
				Size = sizeCurve(0.7 * size, 0.05),
			})
		end,
	},
	-- Suerte de rasgo: bruma arcana violeta con destellos, alrededor del cuerpo.
	arcane = {
		at = Vector3.new(0, 0, 0),
		build = function(att, color, rate, size)
			emitter(att, SMOKE, ColorSequence.new(color), rate * 0.5, {
				Lifetime = NumberRange.new(1.2, 1.8),
				Speed = NumberRange.new(0.3, 0.8),
				Shape = SHAPE.Sphere,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				RotSpeed = NumberRange.new(-60, 60),
				LockedToPart = true,
				LightEmission = 0.6,
				Size = sizeCurve(0.6 * size, 1.4 * size),
				Transparency = fade(0.5),
			})
			emitter(att, SPARKLE, glow(color), rate * 0.6, {
				Lifetime = NumberRange.new(0.8, 1.4),
				Speed = NumberRange.new(0.5, 1.2),
				Shape = SHAPE.Sphere,
				ShapeStyle = STYLE.Surface,
				ShapeInOut = IN_OUT.Outward,
				LockedToPart = true,
				Size = sizeCurve(0.7 * size, 0),
			})
		end,
	},
}

-- Pieza invisible de la que salen las partículas: soldada a la raíz, sin colisión ni consultas, y solo existe en este
-- cliente. Se crea cuando hace falta y se quita cuando ya no hay ningún efecto.
local function volumeOf(root: BasePart): BasePart
	local existing = root:FindFirstChild(VOLUME) :: BasePart?
	if existing then
		return existing
	end
	local volume = Instance.new("Part")
	volume.Name = VOLUME
	volume.Size = VOLUME_SIZE
	volume.Transparency = 1
	volume.CanCollide = false
	volume.CanQuery = false
	volume.CanTouch = false
	volume.CastShadow = false
	volume.Massless = true
	volume.CFrame = root.CFrame
	volume.Parent = root
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = volume
	weld.Parent = volume
	return volume
end

-- Colgado de la pieza de efectos: el de esa familia con ese tier (guarda el tier para saber si hay que rehacerlo).
local function build(volume: BasePart, family: string, tier: number)
	local info = cfg.Families[family]
	local style = STYLES[info.fx]
	if not style then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = PREFIX .. family
	attachment.Position = style.at
	attachment:SetAttribute("Tier", tier)
	style.build(attachment, info.color, cfg.Fx.rate[tier], cfg.Fx.size[tier])
	attachment.Parent = volume
end

-- Luz suave y destellos grandes del pecho: los de la mejor poción que se ve.
local function accent(volume: BasePart, family: string, tier: number)
	local light = volume:FindFirstChild(PREFIX .. "Light") :: PointLight?
	local halo = volume:FindFirstChild(PREFIX .. "Halo") :: Attachment?
	local brightness = cfg.Fx.light[tier]
	if brightness > 0 then
		if not light then
			light = Instance.new("PointLight")
			light.Name = PREFIX .. "Light"
			light.Parent = volume
		end
		light.Color = cfg.Families[family].color:Lerp(WHITE, 0.25)
		light.Brightness = brightness
		light.Range = 8 + tier
	elseif light then
		light:Destroy()
	end
	if tier >= cfg.Fx.halo then
		if halo and halo:GetAttribute("Tier") ~= tier then
			halo:Destroy()
			halo = nil
		end
		if not halo then
			local attachment = Instance.new("Attachment")
			attachment.Name = PREFIX .. "Halo"
			attachment.Position = Vector3.new(0, 0.8, 0)
			attachment:SetAttribute("Tier", tier)
			-- Pocos destellos y no demasiado grandes: se suman unos sobre otros y, si no, tapan al personaje.
			local step = tier - cfg.Fx.halo
			emitter(attachment, SPARKLE, glow(PotionInfo.color(tier)), 1.5 + step * 1.5, {
				Lifetime = NumberRange.new(0.9, 1.2),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 2.4 + step * 1.4), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = fade(0.35),
			})
			attachment.Parent = volume
		end
	elseif halo then
		halo:Destroy()
	end
end

-- Deja el personaje de ese jugador como dicen sus atributos: quita lo que sobra o cambió de tier y pone lo que falta.
local function refresh(target: Player)
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local list = {}
	for _, family in cfg.Order do
		local tier = target:GetAttribute("Potion_" .. family)
		if type(tier) == "number" and cfg.Families[family].values[tier] then
			table.insert(list, { family = family, tier = tier })
		end
	end
	if target ~= player and #list > 1 then
		table.sort(list, function(a, b)
			return a.tier > b.tier
		end)
		list = { list[1] }
	end

	-- Sin ninguna poción que enseñar, se quita todo (incluida la pieza).
	if #list == 0 then
		local old = root:FindFirstChild(VOLUME)
		if old then
			old:Destroy()
		end
		return
	end

	local wanted = {}
	local best = list[1]
	for _, entry in list do
		wanted[entry.family] = entry.tier
		if entry.tier > best.tier then
			best = entry
		end
	end
	local volume = volumeOf(root)
	for _, child in volume:GetChildren() do
		local family = if child:IsA("Attachment") then string.match(child.Name, "^" .. PREFIX .. "(.+)$") else nil
		if family and family ~= "Halo" and wanted[family] ~= child:GetAttribute("Tier") then
			child:Destroy()
		end
	end
	for family, tier in wanted do
		if not volume:FindFirstChild(PREFIX .. family) then
			build(volume, family, tier)
		end
	end
	accent(volume, best.family, best.tier)
end

local scheduled = {} -- [Player] = true: ya hay un refresco pendiente (varios atributos cambian a la vez)

local function schedule(target: Player)
	if scheduled[target] then
		return
	end
	scheduled[target] = true
	task.defer(function()
		scheduled[target] = nil
		refresh(target)
	end)
end

local function watch(target: Player)
	target.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 7) == "Potion_" then
			schedule(target)
		end
	end)
	target.CharacterAdded:Connect(function(character: Model)
		-- Hasta que no llega la raíz no hay dónde colgar nada.
		character:WaitForChild("HumanoidRootPart", 10)
		schedule(target)
	end)
	schedule(target)
end

function PotionFx.start()
	Players.PlayerAdded:Connect(watch)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerRemoving:Connect(function(other)
		scheduled[other] = nil
	end)
end

return PotionFx
