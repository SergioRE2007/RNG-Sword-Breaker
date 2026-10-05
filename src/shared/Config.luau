-- Todos los números del juego están aquí. Para equilibrar, toca solo este archivo.
local Config = {}

-- Se anuncia a todo el servidor lo que tenía, con la suerte del jugador ya aplicada,
-- como mucho 1 entre este número de probabilidades de salir.
Config.AnnounceOdds = 500
Config.WalkSpeed = 30 -- velocidad al andar (la normal de Roblox es 16)

-- Modo de pruebas: solo actúa al darle a Jugar dentro de Studio, nunca en el juego publicado.
-- No guarda el progreso de esa partida.
Config.Test = {
	InfiniteMoney = true, -- monedas y gemas infinitas
	AllWeapons = true, -- una copia de cada arma de Config.Swords en la mochila al entrar
}
Config.BaseRange = 5 -- alcance base; se le suma el largo de la hoja
Config.MinCooldown = 0.1 -- tiempo mínimo entre golpes, por rápida que sea el arma
Config.StartCoins = 0
Config.AutosaveInterval = 60
Config.DataStoreName = "PlayerData_v1"

-- Tipos de arma. Cada arma de Config.Swords lleva "kind" (sin él es "sword").
-- cooldown = multiplica el tiempo entre golpes; arc = cuánto de frente tiene que estar el objeto
-- (1 = justo delante, 0 = medio círculo, -1 = todo alrededor). El alcance es BaseRange + bladeLength.
Config.WeaponKinds = {
	sword = { name = "Espada", cooldown = 1, arc = 0.2 },
	axe = { name = "Hacha", cooldown = 1.7, arc = -1 }, -- gira y pega a todo lo que le rodea, pero lenta
	dual = { name = "Espadas dobles", cooldown = 0.55, arc = 0.2 }, -- golpes rápidos y flojos
	spear = { name = "Lanza", cooldown = 1.1, arc = 0.8 }, -- estocada estrecha desde lejos
	hammer = { name = "Martillo", cooldown = 2.2, arc = -0.3 }, -- muy lento, golpe en área ancha por delante y a los lados
}

-- La primera es la inicial y no sale en el gacha.
-- "rarity" = 1 entre N de que salga en cada tirada (se prueba de la más rara a la más común).
-- "bladeLength" = largo del arma: en la lanza es el asta entera y en el hacha el mango.
-- El jugador puede tener varias copias de cada una, cada copia con su propio rasgo.
-- No cambies el orden: el inventario guardado usa la posición en esta lista. Lo nuevo va al final.
Config.Swords = {
	{ name = "Espada de madera", damage = 1, bladeLength = 3, color = Color3.fromRGB(150, 105, 60), material = Enum.Material.Wood },
	{ name = "Espada de piedra", damage = 3, rarity = 1, bladeLength = 3.4, color = Color3.fromRGB(130, 130, 135), material = Enum.Material.Slate },
	{ name = "Espada de hierro", damage = 8, rarity = 3, bladeLength = 3.8, color = Color3.fromRGB(200, 205, 210), material = Enum.Material.Metal },
	{ name = "Espada de acero", damage = 25, rarity = 12, bladeLength = 4.3, color = Color3.fromRGB(120, 160, 200), material = Enum.Material.Metal },
	{ name = "Espada de oro", damage = 80, rarity = 50, bladeLength = 4.8, color = Color3.fromRGB(255, 200, 50), material = Enum.Material.Foil },
	{ name = "Espada de diamante", damage = 300, rarity = 250, bladeLength = 5.4, color = Color3.fromRGB(90, 230, 255), material = Enum.Material.Glass },
	{ name = "Espada de plasma", damage = 1200, rarity = 1500, bladeLength = 6.2, color = Color3.fromRGB(255, 70, 220), material = Enum.Material.Neon },
	{ name = "Espada del vacío", damage = 6000, rarity = 10000, bladeLength = 7.5, color = Color3.fromRGB(120, 60, 255), material = Enum.Material.Neon },
	{ name = "Espada solar", damage = 4e4, rarity = 1e5, bladeLength = 7.8, color = Color3.fromRGB(255, 150, 30), material = Enum.Material.Neon },
	{ name = "Espada de cometa", damage = 2e6, rarity = 1e7, bladeLength = 8, color = Color3.fromRGB(170, 240, 255), material = Enum.Material.Ice },
	{ name = "Espada nebulosa", damage = 1e8, rarity = 1e9, bladeLength = 8.2, color = Color3.fromRGB(230, 90, 160), material = Enum.Material.ForceField },
	{ name = "Espada galáctica", damage = 5e10, rarity = 1e12, bladeLength = 8.4, color = Color3.fromRGB(60, 90, 255), material = Enum.Material.Neon },
	{ name = "Espada cuántica", damage = 3e13, rarity = 1e15, bladeLength = 8.6, color = Color3.fromRGB(60, 255, 170), material = Enum.Material.ForceField },
	{ name = "Espada del cosmos", damage = 2e16, rarity = 1e18, bladeLength = 8.8, color = Color3.fromRGB(20, 20, 40), material = Enum.Material.Glass },
	{ name = "Espada del origen", damage = 1e19, rarity = 1e21, bladeLength = 9, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Espada del infinito", damage = 1e22, rarity = 1e24, bladeLength = 9.5, color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas (añadidas después: por eso no van ordenadas por rareza).
	{ name = "Hacha de leñador", kind = "axe", damage = 12, rarity = 6, bladeLength = 3.5, color = Color3.fromRGB(170, 175, 185), material = Enum.Material.Metal },
	{ name = "Dagas gemelas", kind = "dual", damage = 9, rarity = 8, bladeLength = 2.4, color = Color3.fromRGB(190, 200, 215), material = Enum.Material.Metal },
	{ name = "Lanza de caza", kind = "spear", damage = 45, rarity = 25, bladeLength = 9, color = Color3.fromRGB(205, 210, 220), material = Enum.Material.Metal },
	{ name = "Hacha de guerra", kind = "axe", damage = 650, rarity = 600, bladeLength = 4.5, color = Color3.fromRGB(200, 70, 60), material = Enum.Material.Metal },
	{ name = "Sables gemelos", kind = "dual", damage = 450, rarity = 900, bladeLength = 3.6, color = Color3.fromRGB(80, 210, 160), material = Enum.Material.Foil },
	{ name = "Lanza de jade", kind = "spear", damage = 3000, rarity = 4000, bladeLength = 11, color = Color3.fromRGB(70, 200, 130), material = Enum.Material.Glass },
	{ name = "Hacha volcánica", kind = "axe", damage = 1.2e5, rarity = 4e5, bladeLength = 5.5, color = Color3.fromRGB(255, 110, 30), material = Enum.Material.Neon },
	{ name = "Hojas del eclipse", kind = "dual", damage = 2.5e5, rarity = 2e6, bladeLength = 5, color = Color3.fromRGB(150, 80, 255), material = Enum.Material.Neon },
	{ name = "Lanza del rayo", kind = "spear", damage = 6e6, rarity = 3e7, bladeLength = 13, color = Color3.fromRGB(255, 240, 90), material = Enum.Material.Neon },
	-- Martillos (tipo nuevo: lentos, golpe en área; daño por golpe ~2,5 veces el de una espada de su rareza).
	{ name = "Mazo de piedra", kind = "hammer", damage = 150, rarity = 40, bladeLength = 3.2, color = Color3.fromRGB(135, 138, 145), material = Enum.Material.Slate },
	{ name = "Martillo de guerra", kind = "hammer", damage = 4500, rarity = 2500, bladeLength = 3.8, color = Color3.fromRGB(120, 150, 190), material = Enum.Material.Metal },
	{ name = "Martillo del trueno", kind = "hammer", damage = 2.5e5, rarity = 3e5, bladeLength = 4.4, color = Color3.fromRGB(255, 225, 70), material = Enum.Material.Neon },
	{ name = "Martillo magmático", kind = "hammer", damage = 1.4e8, rarity = 5e8, bladeLength = 5, color = Color3.fromRGB(255, 90, 30), material = Enum.Material.Neon },
	{ name = "Martillo glacial", kind = "hammer", damage = 6.5e10, rarity = 5e11, bladeLength = 5.4, color = Color3.fromRGB(150, 225, 255), material = Enum.Material.Ice },
	{ name = "Martillo cósmico", kind = "hammer", damage = 3e15, rarity = 5e16, bladeLength = 5.8, color = Color3.fromRGB(150, 70, 255), material = Enum.Material.ForceField },
	{ name = "Martillo del fin del mundo", kind = "hammer", damage = 1.2e21, rarity = 5e22, bladeLength = 6.2, color = Color3.fromRGB(230, 255, 255), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas de las rarezas altas (Mítica, Secreta y Divina).
	{ name = "Hacha del abismo", kind = "axe", damage = 1e10, rarity = 5e10, bladeLength = 6, color = Color3.fromRGB(70, 60, 200), material = Enum.Material.Neon },
	{ name = "Colmillos de sombra", kind = "dual", damage = 4e8, rarity = 1e10, bladeLength = 5.4, color = Color3.fromRGB(110, 40, 160), material = Enum.Material.Glass },
	{ name = "Lanza abisal", kind = "spear", damage = 1.4e10, rarity = 2e11, bladeLength = 14, color = Color3.fromRGB(40, 90, 230), material = Enum.Material.Neon },
	{ name = "Hacha estelar", kind = "axe", damage = 7e15, rarity = 1e17, bladeLength = 6.4, color = Color3.fromRGB(255, 110, 200), material = Enum.Material.Neon },
	{ name = "Sables de aurora", kind = "dual", damage = 6e14, rarity = 5e16, bladeLength = 5.8, color = Color3.fromRGB(90, 255, 210), material = Enum.Material.ForceField },
	{ name = "Lanza de nova", kind = "spear", damage = 5e15, rarity = 2e17, bladeLength = 15, color = Color3.fromRGB(255, 130, 220), material = Enum.Material.Neon },
	{ name = "Hacha del amanecer", kind = "axe", damage = 3e21, rarity = 1e23, bladeLength = 6.8, color = Color3.fromRGB(255, 235, 170), material = Enum.Material.Neon },
	{ name = "Hojas del alba eterna", kind = "dual", damage = 2.5e20, rarity = 5e22, bladeLength = 6.2, color = Color3.fromRGB(250, 255, 255), material = Enum.Material.Neon },
	{ name = "Lanza del big bang", kind = "spear", damage = 2.4e21, rarity = 2e23, bladeLength = 16, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
}

-- Niveles de rareza, de menor a mayor: a partir de "1 entre min" se usa ese nombre y color
-- (borde de las casillas del inventario, carteles).
Config.RarityTiers = {
	{ min = 0, name = "Común", color = Color3.fromRGB(190, 195, 205) },
	{ min = 10, name = "Poco común", color = Color3.fromRGB(90, 220, 100) },
	{ min = 100, name = "Rara", color = Color3.fromRGB(70, 150, 255) },
	{ min = 1e4, name = "Épica", color = Color3.fromRGB(180, 90, 255) },
	{ min = 1e6, name = "Legendaria", color = Color3.fromRGB(255, 190, 40) },
	{ min = 1e9, name = "Mítica", color = Color3.fromRGB(255, 70, 70) },
	{ min = 1e15, name = "Secreta", color = Color3.fromRGB(255, 90, 210) },
	{ min = 1e21, name = "Divina", color = Color3.fromRGB(120, 255, 240) },
}

-- Máximo de espadas en el inventario; con el inventario lleno las nuevas se venden solas.
Config.MaxSwords = 200

-- Gacha de espadas: gratis, se tira desde cualquier sitio, una tirada cada RollTime segundos.
Config.Gacha = {
	RollTime = 2, -- segundos por tirada sin mejoras (la rama "Velocidad de tirada" lo baja; un gamepass lo bajará más)
	MinRollTime = 0.5, -- nunca se tira más rápido que esto
	ShowcaseOdds = 200, -- desde "1 entre N" real (rareza / suerte de gacha) la tirada pasa a pantalla completa
	RevealTimeout = 30, -- si el cliente no avisa de que ha destapado una tirada rara, su aura y aviso salen igual a los N segundos
	AuraOdds = 100, -- desde "1 entre N" real (rareza / suerte de gacha) el aura se ve en el personaje (también para los demás)
	SellValue = 2, -- gemas por vender una espada (a mano o con la venta automática)
	RockLuck = 10, -- la tirada gratis de la "Roca de armas" multiplica por esto la suerte de gacha
}

-- Objetos del inventario. "dropChance" = probabilidad de que lo suelte un objeto raro
-- (los que dan gemas) al romperse.
Config.ItemOrder = { "traitCrystal" }
Config.Items = {
	traitCrystal = { name = "Cristal de rasgo", description = "Se gasta en la tienda de Rasgos del hub: da un rasgo al azar a la espada que elijas (sustituye al que tuviera).", dropChance = 0.2, color = Color3.fromRGB(90, 230, 255) },
}

-- Rasgos de espada (tienda de Rasgos del hub). Se tiran con un Cristal de rasgo; "chance" = peso
-- de salir (el % se calcula sobre el total, sin suerte). Mientras la espada está equipada
-- multiplican sus monedas, su daño y la suerte (de parcela y de gacha); lo que no se pone vale 1.
-- "icon" = coins, damage, luck o all (los que lo suben todo salen con arcoíris).
-- No cambies el orden: el guardado usa la posición en la lista; lo nuevo, al final.
Config.Traits = {
	{ name = "Monedas I", coins = 1.2, chance = 24.76, icon = "coins", color = Color3.fromRGB(110, 220, 120) },
	{ name = "Daño I", damage = 1.2, chance = 24.76, icon = "damage", color = Color3.fromRGB(90, 210, 230) },
	{ name = "Suerte I", luck = 1.2, chance = 24.76, icon = "luck", color = Color3.fromRGB(150, 230, 90) },
	{ name = "Monedas II", coins = 1.5, chance = 6.7, icon = "coins", color = Color3.fromRGB(60, 200, 90) },
	{ name = "Daño II", damage = 1.5, chance = 6.7, icon = "damage", color = Color3.fromRGB(50, 170, 240) },
	{ name = "Suerte II", luck = 1.5, chance = 6.7, icon = "luck", color = Color3.fromRGB(120, 210, 50) },
	{ name = "Monedas III", coins = 2, chance = 1.5, icon = "coins", color = Color3.fromRGB(30, 180, 70) },
	{ name = "Daño III", damage = 2, chance = 1.5, icon = "damage", color = Color3.fromRGB(40, 120, 255) },
	{ name = "Suerte III", luck = 2, chance = 1.5, icon = "luck", color = Color3.fromRGB(90, 190, 30) },
	{ name = "Samurái", coins = 3, damage = 3, luck = 3, chance = 0.9, icon = "all", color = Color3.fromRGB(255, 120, 200), rainbow = true },
	{ name = "Shogun", coins = 5, damage = 5, luck = 5, chance = 0.17, icon = "all", color = Color3.fromRGB(120, 230, 160), rainbow = true },
	{ name = "Monarca", coins = 8, damage = 8, luck = 8, chance = 0.039, icon = "all", color = Color3.fromRGB(180, 120, 255), rainbow = true },
	{ name = "Trascendente", coins = 15, damage = 15, luck = 15, chance = 0.01, icon = "all", color = Color3.fromRGB(255, 80, 60) },
	{ name = "Eterno", coins = 30, damage = 30, luck = 30, chance = 0.0045, icon = "all", color = Color3.fromRGB(220, 40, 40) },
	{ name = "Paradoja", coins = 57.5, damage = 57.5, luck = 57.5, chance = 0.0019, icon = "all", color = Color3.fromRGB(235, 235, 245) },
}

-- Grados de espada (tienda de Grados del hub). Se tiran con gemas (GradeCost cada vez) y
-- multiplican las monedas mientras la espada está equipada. "chance" como en los rasgos.
-- No cambies el orden: el guardado usa la posición en la lista.
Config.Grades = {
	{ name = "D", coins = 1.1, chance = 50.21, color = Color3.fromRGB(200, 200, 205) },
	{ name = "C", coins = 1.25, chance = 25, color = Color3.fromRGB(80, 210, 80) },
	{ name = "B", coins = 1.5, chance = 12, color = Color3.fromRGB(60, 140, 255) },
	{ name = "A", coins = 2, chance = 7.4, color = Color3.fromRGB(160, 80, 255) },
	{ name = "A+", coins = 3, chance = 3.8, color = Color3.fromRGB(255, 190, 40) },
	{ name = "S", coins = 5, chance = 1.3, color = Color3.fromRGB(240, 50, 60) },
	{ name = "S+", coins = 8, chance = 0.2, color = Color3.fromRGB(50, 80, 255) },
	{ name = "Z", coins = 12, chance = 0.063, color = Color3.fromRGB(40, 210, 190) },
	{ name = "Z+", coins = 20, chance = 0.019, color = Color3.fromRGB(200, 90, 255), rainbow = true },
	{ name = "X", coins = 40, chance = 0.0057, color = Color3.fromRGB(230, 40, 40), rainbow = true },
	{ name = "∞", coins = 100, chance = 0.0016, color = Color3.fromRGB(190, 150, 255), rainbow = true },
}
Config.GradeCost = 25 -- gemas por tirada de grado
Config.ModifierCooldown = 0.3 -- segundos mínimos entre tiradas de rasgo o grado

-- Renacimiento: solo cuesta monedas y no quita nada (ni monedas ganadas, ni espadas, ni mejoras). Cada uno
-- multiplica para siempre (por cada renacimiento, ese número elevado a los renacimientos que lleve).
-- El precio del siguiente = cost * growth ^ renacimientos. Números puestos a ojo, sin equilibrar.
Config.Rebirth = { cost = 2e5, growth = 12, coins = 2, damage = 2, luck = 1.5, gachaLuck = 1.5 }

-- Artefactos (equipo). Pueden caer al romper cualquier objeto ("rarity" = 1 entre N, la
-- suerte de parcela multiplica la probabilidad). "stat": damage, luck (parcela y gacha),
-- coins o gems. No cambies el orden: el guardado usa la posición en la lista.
Config.GearSlots = 3
Config.Artifacts = {
	{ name = "Amuleto de cobre", stat = "coins", mult = 1.5, rarity = 150, color = Color3.fromRGB(200, 120, 70) },
	{ name = "Anillo afilado", stat = "damage", mult = 2, rarity = 400, color = Color3.fromRGB(200, 205, 210) },
	{ name = "Trébol", stat = "luck", mult = 2, rarity = 1000, color = Color3.fromRGB(90, 200, 100) },
	{ name = "Colgante de gemas", stat = "gems", mult = 2, rarity = 3000, color = Color3.fromRGB(190, 110, 255) },
	{ name = "Guantelete", stat = "damage", mult = 5, rarity = 2e4, color = Color3.fromRGB(120, 160, 200) },
	{ name = "Corona dorada", stat = "coins", mult = 10, rarity = 2e5, color = Color3.fromRGB(255, 200, 50) },
	{ name = "Ojo de la fortuna", stat = "luck", mult = 10, rarity = 5e6, color = Color3.fromRGB(60, 255, 170) },
	{ name = "Corazón estelar", stat = "damage", mult = 100, rarity = 1e9, color = Color3.fromRGB(255, 240, 150) },
	{ name = "Reliquia del vacío", stat = "luck", mult = 1000, rarity = 1e13, color = Color3.fromRGB(130, 50, 255) },
	{ name = "Núcleo del infinito", stat = "damage", mult = 1e6, rarity = 1e18, color = Color3.fromRGB(255, 40, 60) },
}
Config.StatNames = { damage = "daño", luck = "suerte", coins = "monedas", gems = "gemas" }

-- Mapa: un hub circular en el centro y las parcelas en círculo a su alrededor.
Config.Plot = {
	Count = 8,
	Size = 100, -- lado de la parcela (múltiplo de 20: la valla va en tramos de 10 con la entrada en el centro)
	RingRadius = 250, -- distancia del centro del mapa al centro de cada parcela
	HubRadius = 90,
	FloorHeight = 0.4,
	SpawnInterval = 1.5, -- segundos entre apariciones de objetos en una parcela
}

-- Ordenados de común a raro. "rarity" = 1 entre N de que salga en cada aparición;
-- la suerte del jugador multiplica esa probabilidad. El primero es el de relleno.
-- "gems" = gemas que suelta (solo los raros). "dropsSword" = al romperse da una espada.
Config.Destructibles = {
	{ name = "Caja", rarity = 1, hp = 3, reward = 2, gems = 0, size = Vector3.new(3, 3, 3), color = Color3.fromRGB(170, 125, 75), material = Enum.Material.WoodPlanks },
	{ name = "Barril", rarity = 4, hp = 12, reward = 10, gems = 0, size = Vector3.new(3, 4.5, 3), color = Color3.fromRGB(120, 75, 45), material = Enum.Material.Wood },
	{ name = "Roca", rarity = 20, hp = 60, reward = 60, gems = 1, size = Vector3.new(5, 4, 5), color = Color3.fromRGB(110, 110, 115), material = Enum.Material.Slate },
	{ name = "Pilar", rarity = 120, hp = 400, reward = 500, gems = 8, size = Vector3.new(4, 12, 4), color = Color3.fromRGB(225, 220, 205), material = Enum.Material.Marble },
	{ name = "Cristal", rarity = 800, hp = 3000, reward = 5000, gems = 60, size = Vector3.new(7, 11, 7), color = Color3.fromRGB(110, 220, 255), material = Enum.Material.Glass },
	{ name = "Roca de armas", rarity = 2000, hp = 800, reward = 0, gems = 0, dropsSword = true, size = Vector3.new(6, 6, 6), color = Color3.fromRGB(255, 120, 40), material = Enum.Material.Neon },
	{ name = "Monolito", rarity = 5000, hp = 30000, reward = 60000, gems = 500, size = Vector3.new(11, 20, 11), color = Color3.fromRGB(45, 40, 60), material = Enum.Material.Basalt },
	{ name = "Obelisco", rarity = 5e4, hp = 4e5, reward = 8e5, gems = 4000, size = Vector3.new(6, 22, 6), color = Color3.fromRGB(230, 190, 70), material = Enum.Material.Foil },
	{ name = "Meteorito", rarity = 1e6, hp = 8e6, reward = 2e7, gems = 5e4, size = Vector3.new(12, 10, 12), color = Color3.fromRGB(200, 70, 30), material = Enum.Material.CrackedLava },
	{ name = "Núcleo", rarity = 5e7, hp = 4e8, reward = 1e9, gems = 1.5e6, size = Vector3.new(9, 9, 9), color = Color3.fromRGB(60, 255, 140), material = Enum.Material.Neon },
	{ name = "Estrella", rarity = 5e9, hp = 4e10, reward = 1e11, gems = 1e8, size = Vector3.new(12, 12, 12), color = Color3.fromRGB(255, 240, 150), material = Enum.Material.Neon },
	{ name = "Agujero negro", rarity = 1e12, hp = 1e13, reward = 2.5e13, gems = 1e10, size = Vector3.new(13, 13, 13), color = Color3.fromRGB(5, 5, 10), material = Enum.Material.Glass },
	{ name = "Fragmento del vacío", rarity = 1e15, hp = 1e16, reward = 3e16, gems = 5e12, size = Vector3.new(8, 24, 8), color = Color3.fromRGB(130, 50, 255), material = Enum.Material.ForceField },
	{ name = "Singularidad", rarity = 1e18, hp = 1e19, reward = 4e19, gems = 3e15, size = Vector3.new(10, 10, 10), color = Color3.fromRGB(255, 60, 200), material = Enum.Material.Neon },
	{ name = "Origen", rarity = 1e21, hp = 1e22, reward = 5e22, gems = 1e18, size = Vector3.new(14, 18, 14), color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Infinito", rarity = 1e24, hp = 1e25, reward = 6e25, gems = 5e20, size = Vector3.new(14, 26, 14), color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
}

-- Mejoras. Valor: "add" = base + perLevel * nivel; "mul" = base * perLevel ^ nivel (exponencial).
-- Precio: cost * growth ^ nivel, en monedas o en gemas (currency = "gems").
-- Los cálculos están en shared/Upgrades.
-- En el árbol de mejoras cada mejora es una rama y cada nivel un nodo: "short" es el nombre
-- del nodo, "icon" su dibujo (box, orb, sword, gem) y "color" el de la rama.
Config.UpgradeOrder = { "capacity", "luck", "speed", "gachaLuck", "rollSpeed" }
Config.Upgrades = {
	-- Menos niveles y cada uno da más (pedido por el usuario: el árbol era demasiado largo). Llegan al mismo
	-- tope que antes: la suerte a ~x7e23 (antes 150 niveles de x1.5) y el golpe a 0,14 s.
	capacity = { name = "Más objetos", short = "Objetos", icon = "box", color = Color3.fromRGB(235, 150, 60), mode = "add", base = 6, perLevel = 3, maxLevel = 8, cost = 25, growth = 2.6, display = "%d" },
	luck = { name = "Suerte", short = "Suerte", icon = "orb", color = Color3.fromRGB(70, 200, 90), mode = "mul", base = 1, perLevel = 3, maxLevel = 50, cost = 40, growth = 3.7, display = "x%s" },
	speed = { name = "Velocidad de golpe", short = "Velocidad", icon = "sword", color = Color3.fromRGB(60, 170, 255), mode = "mul", base = 0.35, perLevel = 0.912, maxLevel = 10, cost = 200, growth = 3.3, display = "%.2fs" },
	gachaLuck = { name = "Suerte de gacha", short = "Gacha", icon = "gem", color = Color3.fromRGB(180, 100, 255), mode = "mul", base = 1, perLevel = 3, maxLevel = 50, cost = 10, growth = 4.1, currency = "gems", display = "x%s" },
	-- Segundos por tirada del gacha (lo lee Stats.rollTime): 2 s al principio, -12 % por nivel, ~0,56 s al final. Base = Config.Gacha.RollTime.
	rollSpeed = { name = "Velocidad de tirada", short = "Tirada", icon = "orb", color = Color3.fromRGB(255, 190, 40), mode = "mul", base = 2, perLevel = 0.88, maxLevel = 10, cost = 300, growth = 3.4, display = "%.2fs" },
}

return Config
