-- Adornos de los slimes de las mazmorras (librería, sin start()): uno por "look" de Config.Enemies y de los skins de
-- Config.DungeonThemes (un enemigo puede llevar varios), para que cada zona siga teniendo sus enemigos distintos. Los
-- pone client/Slimes, que los mueve con el cuerpo. Un look nuevo es una función más aquí.
-- Cada función recibe:
--   add(nombre, tamaño, cframe, color, material?, forma?) pone una pieza y la devuelve. El cframe va en coordenadas
--     del slime: el origen es el suelo bajo su centro, Y arriba y la cara mirando a -Z. forma: "ball" (elipsoide,
--     el tamaño es el de la pieza), "cylinder" (el eje es X) o nada (bloque).
--   size: el tamaño de la caja del enemigo (lo que mide su hitbox).
--   color: su color.
--   s: la forma del cuerpo: s.top(x, z) = altura de la superficie de arriba; s.on(x, y, z) = CFrame en ese punto de la
--     superficie con su Y hacia fuera (para lo que sale del cuerpo); s.face(x, y, fuera) = CFrame en la cara con -Z
--     hacia fuera; s.eye = { x, y, w, h } (dónde van los ojos); s.yc y s.b = altura del centro y semieje vertical.
local SlimeLooks = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local BONE = Color3.fromRGB(240, 235, 215)

type Add = (string, Vector3, CFrame, Color3, Enum.Material?, string?) -> BasePart
local LOOKS: { [string]: (add: Add, size: Vector3, color: Color3, s: any) -> () } = {}

-- Cuernos de hueso: base gruesa casi vertical y punta fina que se curva hacia dentro (redondos y abiertos parecían
-- orejas de conejo).
LOOKS.horns = function(add, size, _, s)
	for _, side in { -1, 1 } do
		local x = side * size.X * 0.27
		local p = Vector3.new(x, s.top(x, 0), 0)
		local base = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(-side * 14))
		local horn = Vector3.new(size.X * 0.15, size.Y * 0.26, size.X * 0.15)
		add("Horn", horn, base * CFrame.new(0, horn.Y * 0.3, 0), BONE, nil, "ball")
		local mid = Vector3.new(size.X * 0.1, size.Y * 0.2, size.X * 0.1)
		local bend = base * CFrame.new(0, horn.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(side * 22))
		add("HornMid", mid, bend * CFrame.new(0, mid.Y * 0.25, 0), BONE, nil, "ball")
		local tip = Vector3.new(size.X * 0.05, size.Y * 0.16, size.X * 0.05)
		add("HornTip", tip, bend * CFrame.new(0, mid.Y * 0.55, 0) * CFrame.Angles(0, 0, math.rad(side * 24)) * CFrame.new(0, tip.Y * 0.35, 0), BONE:Lerp(Color3.fromRGB(120, 100, 80), 0.35), nil, "ball")
	end
end

-- Corona de oro: aro, puntas y una gema delante.
LOOKS.crown = function(add, size, _, s)
	local radius = size.X * 0.24
	local y = s.top(radius, 0) + size.Y * 0.03
	local band = size.Y * 0.12
	add("Crown", Vector3.new(band, radius * 2.1, radius * 2.1), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Foil, "cylinder")
	for index = 1, 5 do
		local turn = index / 5 * math.pi * 2
		add("Spike", Vector3.new(size.X * 0.09, size.Y * 0.2, size.X * 0.09), CFrame.new(math.cos(turn) * radius * 0.95, y + band * 0.5 + size.Y * 0.06, math.sin(turn) * radius * 0.95), GOLD, Enum.Material.Foil, "ball")
	end
	add("Gem", Vector3.new(size.X * 0.09, size.X * 0.09, size.X * 0.05), CFrame.new(0, y, -radius * 1.05), Color3.fromRGB(230, 50, 70), Enum.Material.SmoothPlastic, "ball")
end

-- Brote en la cabeza (bosque, nebulosa): tallo y dos hojas abiertas.
LOOKS.leaf = function(add, size, color, s)
	local green = color:Lerp(Color3.fromRGB(70, 190, 80), 0.6)
	local base = s.on(0, nil, 0)
	local stem = Vector3.new(size.X * 0.05, size.Y * 0.2, size.X * 0.05)
	add("Stem", stem, base * CFrame.new(0, stem.Y * 0.4, 0), green:Lerp(Color3.new(0, 0, 0), 0.2))
	for _, side in { -1, 1 } do
		local leaf = Vector3.new(size.X * 0.24, size.X * 0.03, size.X * 0.13)
		add("Leaf", leaf, base * CFrame.new(0, stem.Y * 0.8, 0) * CFrame.Angles(0, 0, math.rad(side * 32)) * CFrame.new(side * leaf.X * 0.48, 0, 0), green, nil, "ball")
	end
end

-- Cuernas de ciervo: un tronco por lado y una punta.
LOOKS.antlers = function(add, size, _, s)
	local wood = Color3.fromRGB(128, 96, 64)
	for _, side in { -1, 1 } do
		local base = s.on(side * size.X * 0.22, nil, 0)
		local beam = Vector3.new(size.X * 0.07, size.Y * 0.5, size.X * 0.07)
		local trunk = base * CFrame.Angles(0, 0, math.rad(-side * 24))
		add("Antler", beam, trunk * CFrame.new(0, beam.Y * 0.42, 0), wood, Enum.Material.Wood, "ball")
		local prong = Vector3.new(size.X * 0.06, size.Y * 0.26, size.X * 0.06)
		add("Prong", prong, trunk * CFrame.new(0, beam.Y * 0.55, 0) * CFrame.Angles(0, 0, math.rad(-side * 42)) * CFrame.new(0, prong.Y * 0.42, 0), wood, Enum.Material.Wood, "ball")
	end
end

-- Capucha: casquete oscuro echado hacia atrás (la cara asoma por delante) con la punta caída.
LOOKS.hood = function(add, size, color, s)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.55)
	local cap = Vector3.new(size.X * 1.08, s.b * 1.3, size.Z * 1.06)
	add("Hood", cap, CFrame.new(0, s.yc + s.b * 0.55, size.Z * 0.17), dark, Enum.Material.Fabric, "ball")
	local tip = Vector3.new(size.X * 0.24, size.Y * 0.42, size.X * 0.24)
	add("HoodTip", tip, CFrame.new(0, s.yc + s.b * 1.12, size.Z * 0.3) * CFrame.Angles(math.rad(-40), 0, 0), dark, Enum.Material.Fabric, "ball")
end

-- Pinchos que salen de la piel, cada uno hacia fuera.
LOOKS.spikes = function(add, size, color, s)
	local tint = color:Lerp(Color3.new(1, 1, 1), 0.45)
	for index = 1, 5 do
		local turn = index / 5 * math.pi * 2 + math.pi / 2
		local spike = Vector3.new(size.X * 0.1, size.Y * 0.28, size.X * 0.1)
		add("Spike", spike, s.on(math.cos(turn) * size.X * 0.3, nil, math.sin(turn) * size.Z * 0.3) * CFrame.new(0, spike.Y * 0.32, 0), tint, nil, "ball")
	end
end

-- Llamitas en la cabeza (brillan, pero son pequeñas).
LOOKS.flame = function(add, size, _, s)
	for index, lean in { -16, 0, 16 } do
		local x = (index - 2) * size.X * 0.15
		local flame = Vector3.new(size.X * 0.13, size.Y * (if index == 2 then 0.36 else 0.26), size.X * 0.13)
		local base = s.on(x, nil, 0) * CFrame.Angles(0, 0, math.rad(lean))
		add("Flame", flame, base * CFrame.new(0, flame.Y * 0.4, 0), Color3.fromRGB(255, 140, 45), Enum.Material.Neon, "ball")
		add("FlameCore", flame * Vector3.new(0.5, 0.55, 0.5), base * CFrame.new(0, flame.Y * 0.28, 0), Color3.fromRGB(255, 225, 120), Enum.Material.Neon, "ball")
	end
end

-- Aureola: un aro de cuentas de luz que flota sobre la cabeza.
LOOKS.halo = function(add, size, _, s)
	local y = s.top(0, 0) + size.Y * 0.22
	local radius = size.X * 0.3
	for index = 1, 12 do
		local turn = index / 12 * math.pi * 2
		local bead = add("Halo", Vector3.new(size.X * 0.09, size.X * 0.06, size.X * 0.09), CFrame.new(math.cos(turn) * radius, y, math.sin(turn) * radius), Color3.fromRGB(255, 245, 190), Enum.Material.Neon, "ball")
		bead.Transparency = 0.1
	end
end

-- Casco de minero: media cúpula de metal por encima de los ojos y la lámpara delante.
LOOKS.helmet = function(add, size, _, s)
	local metal = Color3.fromRGB(235, 190, 60)
	add("Helmet", Vector3.new(size.X * 1.06, s.b * 0.95, size.Z * 1.06), CFrame.new(0, s.yc + s.b * 0.86, size.Z * 0.02), metal, Enum.Material.Metal, "ball")
	add("Brim", Vector3.new(size.Y * 0.04, size.X * 0.95, size.Z * 0.95), CFrame.new(0, s.yc + s.b * 0.5, size.Z * 0.02) * CFrame.Angles(0, 0, math.rad(90)), metal:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal, "cylinder")
	local lamp = s.face(0, s.yc + s.b * 0.7, size.Z * 0.06)
	add("LampRim", Vector3.new(size.X * 0.22, size.X * 0.22, size.X * 0.08), lamp, Color3.fromRGB(70, 70, 76), Enum.Material.Metal, "ball")
	add("Lamp", Vector3.new(size.X * 0.15, size.X * 0.15, size.X * 0.08), lamp * CFrame.new(0, 0, -size.X * 0.03), Color3.fromRGB(255, 244, 190), Enum.Material.Neon, "ball")
end

-- Calavera: cuencas negras alrededor de los ojos y dientes bajo la boca.
LOOKS.skull = function(add, size, _, s)
	local eye = s.eye
	for _, side in { -1, 1 } do
		add("Socket", Vector3.new(eye.w * 1.5, eye.h * 1.4, 0.12), s.face(side * eye.x, eye.y, -0.02), Color3.new(0.05, 0.04, 0.06), nil, "ball")
	end
	for index = -1.5, 1.5 do
		local x = index * size.X * 0.085
		add("Tooth", Vector3.new(size.X * 0.07, size.Y * 0.09, 0.12), s.face(x, s.yc - s.b * 0.08, 0.03), Color3.new(1, 1, 1))
	end
end

-- Pone los adornos de `look` ("horns" o "skull,horns") con esas herramientas.
function SlimeLooks.build(look: string?, add: Add, size: Vector3, color: Color3, s)
	for name in string.gmatch(look or "", "[^,%s]+") do
		local make = LOOKS[name]
		if make then
			make(add, size, color, s)
		end
	end
end

return SlimeLooks
