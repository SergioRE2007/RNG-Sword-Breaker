-- Todos los números del juego están aquí. Para equilibrar, toca solo este archivo.
local Config = {}

-- Se anuncia a todo el servidor lo que tenía, con la suerte del jugador ya aplicada,
-- como mucho 1 entre este número de probabilidades de salir.
Config.AnnounceOdds = 500
Config.WalkSpeed = 30 -- velocidad al andar (la normal de Roblox es 16)

-- Modo de pruebas: solo actúa al darle a Jugar dentro de Studio, nunca en el juego publicado.
-- Da monedas y gemas infinitas y no guarda el progreso de esa partida.
Config.Test = {
	InfiniteMoney = true,
}
Config.BaseRange = 5 -- alcance base; se le suma el largo de la hoja
Config.StartCoins = 0
Config.AutosaveInterval = 60
Config.DataStoreName = "PlayerData_v1"

-- Ordenadas de común a rara. La primera es la inicial y no sale en el gacha.
-- "rarity" = 1 entre N de que salga en cada tirada (se prueba de la más rara a la más común).
-- El jugador puede tener varias copias de cada una, cada copia con su propio rasgo.
-- No cambies el orden: el inventario guardado usa la posición en esta lista.
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
	RollTime = 2, -- segundos por tirada (lo que bajarán la rama "Velocidad de tirada" y los gamepass)
	ShowcaseOdds = 200, -- desde "1 entre N" real (rareza / suerte de gacha) la tirada pasa a pantalla completa
	ShowcaseTime = 4, -- segundos que dura más o menos la animación a pantalla completa
	AuraRarity = 100, -- desde esta rareza el aura se ve en el personaje (también para los demás)
	SellValue = 2, -- gemas por vender una espada (a mano o con la venta automática)
	RockLuck = 10, -- la tirada gratis de la "Roca de armas" multiplica por esto la suerte de gacha
}

-- Objetos del inventario. "dropChance" = probabilidad de que lo suelte un objeto raro
-- (los que dan gemas) al romperse.
Config.ItemOrder = { "traitCrystal" }
Config.Items = {
	traitCrystal = { name = "Cristal de rasgo", description = "Da un rasgo al azar a la espada que elijas (sustituye al que tuviera).", dropChance = 0.2, color = Color3.fromRGB(90, 230, 255) },
}

-- Rasgos de espada, de común a raro. Se tiran con un Cristal de rasgo ("rarity" = 1 entre N,
-- sin suerte). Multiplican el daño de esa espada y, mientras esté equipada, la suerte
-- (de parcela y de gacha). No cambies el orden: el guardado usa la posición en la lista.
Config.Traits = {
	{ name = "Afilada", damage = 1.5, luck = 1, rarity = 1, color = Color3.fromRGB(200, 200, 205) },
	{ name = "Afortunada", damage = 1.2, luck = 1.5, rarity = 3, color = Color3.fromRGB(110, 220, 120) },
	{ name = "Pesada", damage = 3, luck = 1, rarity = 8, color = Color3.fromRGB(120, 160, 255) },
	{ name = "Bendita", damage = 2, luck = 3, rarity = 25, color = Color3.fromRGB(255, 230, 120) },
	{ name = "Feroz", damage = 8, luck = 1.5, rarity = 100, color = Color3.fromRGB(255, 120, 60) },
	{ name = "Mística", damage = 5, luck = 10, rarity = 500, color = Color3.fromRGB(190, 110, 255) },
	{ name = "Legendaria", damage = 30, luck = 5, rarity = 4000, color = Color3.fromRGB(255, 200, 50) },
	{ name = "Divina", damage = 100, luck = 50, rarity = 50000, color = Color3.fromRGB(255, 255, 255) },
	{ name = "Cósmica", damage = 1000, luck = 500, rarity = 1e6, color = Color3.fromRGB(255, 60, 200) },
}

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
	Size = 60, -- lado de la parcela
	RingRadius = 150, -- distancia del centro del mapa al centro de cada parcela
	HubRadius = 60,
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
Config.UpgradeOrder = { "capacity", "luck", "speed", "gachaLuck" }
Config.Upgrades = {
	capacity = { name = "Más objetos", short = "Objetos", icon = "box", color = Color3.fromRGB(235, 150, 60), mode = "add", base = 6, perLevel = 2, maxLevel = 12, cost = 25, growth = 1.9, display = "%d" },
	luck = { name = "Suerte", short = "Suerte", icon = "orb", color = Color3.fromRGB(70, 200, 90), mode = "mul", base = 1, perLevel = 1.5, maxLevel = 150, cost = 40, growth = 1.55, display = "x%s" },
	speed = { name = "Velocidad de golpe", short = "Velocidad", icon = "sword", color = Color3.fromRGB(60, 170, 255), mode = "mul", base = 0.35, perLevel = 0.94, maxLevel = 15, cost = 200, growth = 2.2, display = "%.2fs" },
	gachaLuck = { name = "Suerte de gacha", short = "Gacha", icon = "gem", color = Color3.fromRGB(180, 100, 255), mode = "mul", base = 1, perLevel = 1.5, maxLevel = 150, cost = 10, growth = 1.6, currency = "gems", display = "x%s" },
}

return Config
