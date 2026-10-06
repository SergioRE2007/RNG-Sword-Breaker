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
	Admin = true, -- botón "Admin" en las tiendas de Rasgos y Grados: eliges a mano el rasgo o grado de la espada, sin tirar ni gastar
	TradeBot = true, -- "Bot de pruebas" en la lista de Comercio: acepta y confirma solo, para probar un trato sin otro jugador
	AllGamepasses = true, -- todos los pases de juego de Config.Gamepasses (para probar sus ventajas sin comprarlos)
	AllGear = true, -- todos los accesorios (Config.Artifacts) y una pieza de armadura de cada hueco y cada mazmorra al entrar
	PartyBots = 0, -- compañeros "fantasma" que se unen a tu grupo de mazmorra (cuentan para el tamaño y el escalado, no pelean): para probar con un solo jugador
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

-- REGLA DE EQUILIBRIO (rareza -> daño): cada vez que la rareza se multiplica por 2, el daño sube un 50 %
-- (rareza 2 = daño 1, rareza 4 = 1,5, rareza 8 = 2,25...), o sea daño = 1.5 ^ log2(rareza / 2), multiplicado
-- por la cadencia del tipo de arma (hacha x1.7, dobles x0.55, lanza x1.1, martillo x2.2) para que el daño por
-- segundo sea parecido entre tipos. Las 40 armas del gacha van en una escalera que se va abriendo (curva de
-- dificultad pedida: muy rápida al principio para enganchar y cada vez más cuesta): la primera es solo ~x1.6 más
-- rara que la anterior (una nueva cada pocas tiradas) y la última ~x4.9. Va de 3 a 6e17, sin saltos grandes.
-- Los objetos (Config.Destructibles) tienen la vida
-- reescalada a esta curva (vida = vida anterior ^ 0.47). Al añadir un arma, calcula su daño con la regla.
-- La primera es la inicial y no sale en el gacha.
-- "rarity" = 1 entre N de que salga en cada tirada (se prueba de la más rara a la más común).
-- "bladeLength" = largo del arma: en la lanza es el asta entera y en el hacha el mango.
-- El jugador puede tener varias copias de cada una, cada copia con su propio rasgo.
-- No cambies el orden: el inventario guardado usa la posición en esta lista. Lo nuevo va al final.
Config.Swords = {
	{ name = "Espada de madera", damage = 1, bladeLength = 3, color = Color3.fromRGB(150, 105, 60), material = Enum.Material.Wood },
	{ name = "Espada de piedra", damage = 1.27, rarity = 3, bladeLength = 3.4, color = Color3.fromRGB(130, 130, 135), material = Enum.Material.Slate },
	{ name = "Espada de hierro", damage = 1.65, rarity = 4.7, bladeLength = 3.8, color = Color3.fromRGB(200, 205, 210), material = Enum.Material.Metal },
	{ name = "Espada de acero", damage = 4.03, rarity = 21.7, bladeLength = 4.3, color = Color3.fromRGB(120, 160, 200), material = Enum.Material.Metal },
	{ name = "Espada de oro", damage = 11.5, rarity = 131, bladeLength = 4.8, color = Color3.fromRGB(255, 200, 50), material = Enum.Material.Foil },
	{ name = "Espada de diamante", damage = 17, rarity = 254, bladeLength = 5.4, color = Color3.fromRGB(90, 230, 255), material = Enum.Material.Glass },
	{ name = "Espada de plasma", damage = 60.3, rarity = 2210, bladeLength = 6.2, color = Color3.fromRGB(255, 70, 220), material = Enum.Material.Neon },
	{ name = "Espada del vacío", damage = 249, rarity = 25000, bladeLength = 7.5, color = Color3.fromRGB(120, 60, 255), material = Enum.Material.Neon },
	{ name = "Espada solar", damage = 415, rarity = 59800, bladeLength = 7.8, color = Color3.fromRGB(255, 150, 30), material = Enum.Material.Neon },
	{ name = "Espada de cometa", damage = 3790, rarity = 2.62e6, bladeLength = 8, color = Color3.fromRGB(170, 240, 255), material = Enum.Material.Ice },
	{ name = "Espada nebulosa", damage = 23900, rarity = 6.11e7, bladeLength = 8.2, color = Color3.fromRGB(230, 90, 160), material = Enum.Material.ForceField },
	{ name = "Espada galáctica", damage = 732000, rarity = 2.12e10, bladeLength = 8.4, color = Color3.fromRGB(60, 90, 255), material = Enum.Material.Neon },
	{ name = "Espada cuántica", damage = 1.53e6, rarity = 7.48e10, bladeLength = 8.6, color = Color3.fromRGB(60, 255, 170), material = Enum.Material.ForceField },
	{ name = "Espada del cosmos", damage = 7.94e7, rarity = 6.39e13, bladeLength = 8.8, color = Color3.fromRGB(20, 20, 40), material = Enum.Material.Glass },
	{ name = "Espada del origen", damage = 1.84e8, rarity = 2.7e14, bladeLength = 9, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Espada del infinito", damage = 1.62e10, rarity = 5.67e17, bladeLength = 9.5, color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas (añadidas después: por eso no van ordenadas por rareza).
	{ name = "Hacha de leñador", kind = "axe", damage = 3.71, rarity = 7.6, bladeLength = 3.5, color = Color3.fromRGB(170, 175, 185), material = Enum.Material.Metal },
	{ name = "Dagas gemelas", kind = "dual", damage = 1.62, rarity = 12.7, bladeLength = 2.4, color = Color3.fromRGB(190, 200, 215), material = Enum.Material.Metal },
	{ name = "Lanza de caza", kind = "spear", damage = 6.2, rarity = 38.4, bladeLength = 9, color = Color3.fromRGB(205, 210, 220), material = Enum.Material.Metal },
	{ name = "Hacha de guerra", kind = "axe", damage = 43.3, rarity = 507, bladeLength = 4.5, color = Color3.fromRGB(200, 70, 60), material = Enum.Material.Metal },
	{ name = "Sables gemelos", kind = "dual", damage = 21.3, rarity = 1040, bladeLength = 3.6, color = Color3.fromRGB(80, 210, 160), material = Enum.Material.Foil },
	{ name = "Lanza de jade", kind = "spear", damage = 168, rarity = 10800, bladeLength = 11, color = Color3.fromRGB(70, 200, 130), material = Enum.Material.Glass },
	{ name = "Hacha volcánica", kind = "axe", damage = 2060, rarity = 373000, bladeLength = 5.5, color = Color3.fromRGB(255, 110, 30), material = Enum.Material.Neon },
	{ name = "Hojas del eclipse", kind = "dual", damage = 1170, rarity = 973000, bladeLength = 5, color = Color3.fromRGB(150, 80, 255), material = Enum.Material.Neon },
	{ name = "Lanza del rayo", kind = "spear", damage = 7570, rarity = 7.27e6, bladeLength = 13, color = Color3.fromRGB(255, 240, 90), material = Enum.Material.Neon },
	-- Martillos (tipo nuevo: lentos, golpe en área; daño por golpe ~2,5 veces el de una espada de su rareza).
	{ name = "Mazo de piedra", kind = "hammer", damage = 17.6, rarity = 70, bladeLength = 3.2, color = Color3.fromRGB(135, 138, 145), material = Enum.Material.Slate },
	{ name = "Martillo de guerra", kind = "hammer", damage = 209, rarity = 4810, bladeLength = 3.8, color = Color3.fromRGB(120, 150, 190), material = Enum.Material.Metal },
	{ name = "Martillo del trueno", kind = "hammer", damage = 1550, rarity = 147000, bladeLength = 4.4, color = Color3.fromRGB(255, 225, 70), material = Enum.Material.Neon },
	{ name = "Martillo magmático", kind = "hammer", damage = 28000, rarity = 2.08e7, bladeLength = 5, color = Color3.fromRGB(255, 90, 30), material = Enum.Material.Neon },
	{ name = "Martillo glacial", kind = "hammer", damage = 784000, rarity = 6.2e9, bladeLength = 5.4, color = Color3.fromRGB(150, 225, 255), material = Enum.Material.Ice },
	{ name = "Martillo cósmico", kind = "hammer", damage = 7.16e6, rarity = 2.72e11, bladeLength = 5.8, color = Color3.fromRGB(150, 70, 255), material = Enum.Material.ForceField },
	{ name = "Martillo del fin del mundo", kind = "hammer", damage = 9.56e8, rarity = 1.17e15, bladeLength = 6.2, color = Color3.fromRGB(230, 255, 255), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas de las rarezas altas (Mítica, Secreta y Divina).
	{ name = "Hacha del abismo", kind = "axe", damage = 152000, rarity = 5.8e8, bladeLength = 6, color = Color3.fromRGB(70, 60, 200), material = Enum.Material.Neon },
	{ name = "Colmillos de sombra", kind = "dual", damage = 25200, rarity = 1.86e8, bladeLength = 5.4, color = Color3.fromRGB(110, 40, 160), material = Enum.Material.Glass },
	{ name = "Lanza abisal", kind = "spear", damage = 195000, rarity = 1.87e9, bladeLength = 14, color = Color3.fromRGB(40, 90, 230), material = Enum.Material.Neon },
	{ name = "Hacha estelar", kind = "axe", damage = 2.64e7, rarity = 3.93e12, bladeLength = 6.4, color = Color3.fromRGB(255, 110, 200), material = Enum.Material.Neon },
	{ name = "Sables de aurora", kind = "dual", damage = 3.88e6, rarity = 1.02e12, bladeLength = 5.8, color = Color3.fromRGB(90, 255, 210), material = Enum.Material.ForceField },
	{ name = "Lanza de nova", kind = "spear", damage = 3.83e7, rarity = 1.56e13, bladeLength = 15, color = Color3.fromRGB(255, 130, 220), material = Enum.Material.Neon },
	{ name = "Hacha del amanecer", kind = "axe", damage = 4.36e9, rarity = 2.43e16, bladeLength = 6.8, color = Color3.fromRGB(255, 235, 170), material = Enum.Material.Neon },
	{ name = "Hojas del alba eterna", kind = "dual", damage = 5.76e8, rarity = 5.26e15, bladeLength = 6.2, color = Color3.fromRGB(250, 255, 255), material = Enum.Material.Neon },
	{ name = "Lanza del big bang", kind = "spear", damage = 7.04e9, rarity = 1.16e17, bladeLength = 16, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	-- La más rara: mandoble modelado en Blender (colmillo con muescas, canal de energía y aura turquesa y magenta).
	-- `mesh` = módulo de shared/Meshes con su forma (la dibuja shared/MeshWeapon en vez de las piezas de SwordModel).
	{ name = "Colmillo astral", mesh = "ColmilloAstral", damage = 4.29e10, rarity = 3e18, bladeLength = 10, color = Color3.fromRGB(60, 230, 215), material = Enum.Material.Neon },
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

-- Modificadores permanentes: cada arma que sale del gacha puede llevar además UN metal y UN tamaño, tirados
-- a la vez que ella y que ya no cambian. "odds" = 1 entre N de que salgan (la suerte de gacha divide N, como
-- con las armas). Cada uno multiplica el daño con la misma regla que las armas (rareza x2 = +50 % de daño,
-- ver Permanent.damage) y suma su rareza a la del arma (los N se multiplican). El metal cambia el color y el
-- material del arma; el tamaño la agranda (scale) y con ella su alcance. No cambies el orden: lo guardado usa
-- la posición. Lo nuevo va al final.
Config.Metals = {
	{ name = "Cobre", odds = 10, color = Color3.fromRGB(205, 118, 72), material = Enum.Material.Metal },
	{ name = "Hierro", odds = 100, color = Color3.fromRGB(150, 156, 168), material = Enum.Material.Metal },
	{ name = "Oro", odds = 1e3, color = Color3.fromRGB(255, 205, 60), material = Enum.Material.Foil },
	{ name = "Lunarita", odds = 1e4, color = Color3.fromRGB(190, 215, 255), material = Enum.Material.Glass },
	{ name = "Solarium", odds = 1e5, color = Color3.fromRGB(255, 140, 70), material = Enum.Material.Neon },
	{ name = "Etherio", odds = 1e6, color = Color3.fromRGB(130, 255, 225), material = Enum.Material.ForceField },
}
Config.Sizes = {
	{ name = "Grande", odds = 1e2, scale = 1.25, color = Color3.fromRGB(120, 200, 120) },
	{ name = "Gigante", odds = 1e5, scale = 1.6, color = Color3.fromRGB(90, 160, 255) },
	{ name = "Titánica", odds = 1e8, scale = 2.1, color = Color3.fromRGB(200, 100, 255) },
	{ name = "Universal", odds = 1e12, scale = 3, color = Color3.fromRGB(255, 90, 90) },
}

-- Máximo de espadas en el inventario; con el inventario lleno las nuevas se venden solas.
Config.MaxSwords = 200

-- Gacha de espadas: el motor de las tiradas de arma. Las tiradas las dan los objetos de la parcela al romperse
-- (Config.ObjectRolls, más abajo); el gacha decide qué arma sale con la suerte que le llega.
Config.Gacha = {
	FreeRoll = false, -- true: vuelven los botones "Tirar" y "Auto" y la tirada gratis cada RollTime segundos de antes de que las armas salieran de los objetos
	RollTime = 2, -- (sin uso: con FreeRoll el tiempo por tirada es el de la mejora "Velocidad de aparición", Stats.rollTime)
	MinRollTime = 0.5, -- (solo con FreeRoll) nunca se tira más rápido que esto
	-- Lo difícil que era un arma para el jugador ("1 entre N", Permanent.odds: arma, metal y tamaño, con su suerte de
	-- armas y sin la del objeto) decide cuánto se celebra. Como son tres tiradas a la vez, llegar a un N es más fácil
	-- de lo que suena. Medido con 120 000 tiradas: llega a 500 una de cada ~70-160, a 2000 una de cada ~180-490 y a
	-- 25 000 una de cada ~1600-4300 (menos cuanta más suerte).
	ShowcaseOdds = 2000, -- desde aquí la tirada pasa a pantalla completa (antes 200: salía cada 30 tiradas, demasiado ahora que llegan solas mientras juegas)
	RevealTimeout = 30, -- si el cliente no avisa de que ha destapado una tirada rara, su aura y aviso salen igual a los N segundos
	AuraOdds = 500, -- desde aquí el aura se ve en el personaje (también para los demás)
	AnnounceOdds = 25000, -- desde aquí se anuncia el arma a todo el servidor
	SellValue = 0, -- gemas por vender una espada (a mano o con la venta automática). 0: las gemas salen de la parcela
	ShowcaseStay = 3, -- segundos que se queda la animación grande de una tirada de objeto antes de cerrarse sola (con FreeRoll espera a "Continuar")
	-- Empujón del principio (para enganchar): las primeras BoostRolls tiradas de cada jugador tienen la suerte multiplicada por BoostLuck.
	BoostRolls = 15,
	BoostLuck = 30,
}

-- Objetos del inventario. "dropChance" = probabilidad de que lo suelte un objeto raro
-- (los que dan gemas) al romperse.
Config.ItemOrder = { "traitCrystal", "missionToken", "gradeCrystal" }
Config.Items = {
	traitCrystal = { name = "Cristal de rasgo", description = "Se gasta en la tienda de Rasgos del hub: da un rasgo al azar a la espada que elijas (sustituye al que tuviera).", dropChance = 0.05, color = Color3.fromRGB(90, 230, 255) },
	-- Moneda gratuita (f2p) que dan las misiones diarias y semanales. De momento no se gasta en nada: en el futuro servirá para comprar cosas difíciles o pases. No cae de los objetos (sin dropChance).
	missionToken = { name = "Ficha de misión", description = "La dan las misiones diarias y semanales. Más adelante servirá para comprar cosas difíciles de conseguir.", color = Color3.fromRGB(255, 190, 60) },
	-- Lo sueltan los enemigos de las mazmorras y se saca al desmontar armadura. No cae de los objetos (sin dropChance).
	gradeCrystal = { name = "Cristal de grado", description = "Se gasta en la tienda de Grados del hub: da un grado al azar a la espada que elijas. Lo sueltan los enemigos de las mazmorras.", color = Color3.fromRGB(200, 120, 255) },
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

-- Grados de espada (tienda de Grados del hub). Se tiran con Cristales de grado (GradeCost cada vez) y
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
Config.GradeCost = 1 -- Cristales de grado por tirada de grado
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

-- Decorado del mapa: "japan" (bosque japonés de atardecer, server/SceneryJapan) o "tropical" (la isla de siempre, server/Scenery).
Config.Theme = "japan"

-- Ciclo de día y noche de la superficie (client/DayCycle): `Length` = segundos reales de un día entero, `Start` = hora
-- del reloj a la que arranca. Es el mismo para todos (sigue la hora del servidor).
Config.DayCycle = { Length = 480, Start = 17.4 }

-- Mapa: un hub circular en el centro y las parcelas en círculo a su alrededor.
Config.Plot = {
	Count = 8,
	Size = 100, -- lado de la parcela (múltiplo de 20: la valla va en tramos de 10 con la entrada en el centro)
	RingRadius = 250, -- distancia del centro del mapa al centro de cada parcela
	HubRadius = 90,
	FloorHeight = 0.4,
	SpawnInterval = 1.5, -- segundos entre apariciones de objetos en una parcela (sin mejoras: la rama "Velocidad de aparición" lo baja)
	MinSpawnInterval = 0.3, -- nunca aparecen más rápido que esto
}

-- Ordenados de común a raro. "rarity" = 1 entre N de que salga en cada aparición;
-- la suerte del jugador multiplica esa probabilidad. El primero es el de relleno.
-- "gems" = gemas que suelta (solo los raros). Todos dan tiradas de arma al romperse (Config.ObjectRolls, debajo,
-- que explica también lo que puede llevar de más un objeto especial: luck, rolls, minScale...).
Config.Destructibles = {
	{ name = "Caja", rarity = 1, hp = 2, reward = 2, gems = 0, size = Vector3.new(3, 3, 3), color = Color3.fromRGB(170, 125, 75), material = Enum.Material.WoodPlanks },
	{ name = "Barril", rarity = 4, hp = 3, reward = 10, gems = 0, size = Vector3.new(3, 4.5, 3), color = Color3.fromRGB(120, 75, 45), material = Enum.Material.Wood },
	{ name = "Roca", rarity = 20, hp = 7, reward = 60, gems = 1, size = Vector3.new(5, 4, 5), color = Color3.fromRGB(110, 110, 115), material = Enum.Material.Slate },
	{ name = "Pilar", rarity = 120, hp = 17, reward = 500, gems = 8, size = Vector3.new(4, 12, 4), color = Color3.fromRGB(225, 220, 205), material = Enum.Material.Marble },
	{ name = "Cristal", rarity = 800, hp = 43, reward = 5000, gems = 60, size = Vector3.new(7, 11, 7), color = Color3.fromRGB(110, 220, 255), material = Enum.Material.Glass },
	{ name = "Roca de armas", rarity = 2000, hp = 23, reward = 0, gems = 0, luck = 10, rolls = 1, size = Vector3.new(6, 6, 6), color = Color3.fromRGB(255, 120, 40), material = Enum.Material.Neon },
	{ name = "Monolito", rarity = 5000, hp = 130, reward = 60000, gems = 500, size = Vector3.new(11, 20, 11), color = Color3.fromRGB(45, 40, 60), material = Enum.Material.Basalt },
	{ name = "Obelisco", rarity = 5e4, hp = 430, reward = 8e5, gems = 4000, size = Vector3.new(6, 22, 6), color = Color3.fromRGB(230, 190, 70), material = Enum.Material.Foil },
	{ name = "Meteorito", rarity = 1e6, hp = 1800, reward = 2e7, gems = 5e4, size = Vector3.new(12, 10, 12), color = Color3.fromRGB(200, 70, 30), material = Enum.Material.CrackedLava },
	{ name = "Núcleo", rarity = 5e7, hp = 11000, reward = 1e9, gems = 1.5e6, size = Vector3.new(9, 9, 9), color = Color3.fromRGB(60, 255, 140), material = Enum.Material.Neon },
	{ name = "Estrella", rarity = 5e9, hp = 96000, reward = 1e11, gems = 1e8, size = Vector3.new(12, 12, 12), color = Color3.fromRGB(255, 240, 150), material = Enum.Material.Neon },
	{ name = "Agujero negro", rarity = 1e12, hp = 1.3e6, reward = 2.5e13, gems = 1e10, size = Vector3.new(13, 13, 13), color = Color3.fromRGB(5, 5, 10), material = Enum.Material.Glass },
	{ name = "Fragmento del vacío", rarity = 1e15, hp = 3.3e7, reward = 3e16, gems = 5e12, size = Vector3.new(8, 24, 8), color = Color3.fromRGB(130, 50, 255), material = Enum.Material.ForceField },
	{ name = "Singularidad", rarity = 1e18, hp = 8.5e8, reward = 4e19, gems = 3e15, size = Vector3.new(10, 10, 10), color = Color3.fromRGB(255, 60, 200), material = Enum.Material.Neon },
	{ name = "Origen", rarity = 1e21, hp = 2.2e10, reward = 5e22, gems = 1e18, size = Vector3.new(14, 18, 14), color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Infinito", rarity = 1e24, hp = 5.6e11, reward = 6e25, gems = 5e20, size = Vector3.new(14, 26, 14), color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
}

-- Gemas de los objetos de la parcela: cada objeto con "gems" las suelta con probabilidad "gemChance" (1 si no
-- lo pone) y la cantidad es gems * azar entre min y max (con el multiplicador de gemas del jugador).
Config.GemDrop = { min = 0.7, max = 1.3 }

-- ARMAS DESDE LOS OBJETOS. Cada objeto que aparece en una parcela lleva, además de su tipo (la lista de arriba, que
-- sale según la suerte de parcela), una RAREZA y un TAMAÑO propios, tirados al aparecer. Al romperlo da tiradas de
-- arma (server/Gacha) con la suerte de armas del jugador multiplicada por la SUERTE DEL OBJETO:
--   suerte del objeto = "luck" de su rareza * escala ^ SizeLuckPower * "luck" del tipo      (como mucho MaxLuck)
-- El "luck" del tipo es 1 salvo en los objetos especiales (la Roca de armas, x10). Un objeto común de tamaño
-- normal da x1: lo de siempre. La suerte solo multiplica probabilidades, como toda la del juego: un objeto enorme
-- no garantiza ningún arma.
-- Tiradas = "rolls" de la rareza + "rolls" del tamaño + "rolls" del tipo; la parte decimal es la probabilidad de
-- una más (1.5 = una, y otra la mitad de las veces), con el tope MaxRolls.
-- El tamaño multiplica también la vida (escala ^ SizeHpPower) y las monedas y gemas (escala ^ SizeRewardPower).
-- OBJETOS ESPECIALES: un tipo de Config.Destructibles puede llevar además "luck" (su suerte), "rolls" (tiradas de
-- más), "minScale" y "maxScale" (límites de su escala), "rarityLuck" y "sizeLuck" (multiplican la probabilidad de
-- sus rarezas y de sus tamaños grandes) y "minRarity" (rareza mínima, posición en ObjectRarities). Con eso se hace
-- un objeto nuevo sin tocar código. Las cuentas están en shared/ObjectSpec.
Config.ObjectRolls = {
	SizeLuckPower = 1.5, -- al 70 % x0.59, al 150 % x1.84, al 200 % x2.83, al 250 % x3.95
	SizeHpPower = 2,
	SizeRewardPower = 2,
	MaxLuck = 1000, -- tope de la suerte de un objeto (una Roca de armas mítica y colosal llega a x790)
	MaxRolls = 5, -- tope de tiradas de arma de un solo objeto
	MaxWidth = 30, -- studs: ningún objeto se agranda más que esto de ancho...
	MaxHeight = 56, -- ...ni de alto (los tipos más grandes llegan a menos escala que los pequeños)
	NoticeOdds = 250, -- aviso al dueño cuando le aparece un objeto de "1 entre N" o más (rareza por tamaño)
	AnnounceOdds = 2000, -- y a todo el servidor desde este
}

-- Rarezas de los objetos, de peor a mejor. Son suyas (no son las de las espadas ni las de la armadura), pero con
-- los mismos nombres y colores para que se entiendan de un vistazo. "odds" = 1 entre N de que un objeto salga así
-- (se prueba de la más rara a la más común; Stats.objectLuck multiplica la probabilidad, no la suerte de parcela),
-- "luck" = multiplica la suerte de sus tiradas de arma, "rolls" = tiradas que da, "hp" y "reward" = multiplican su
-- vida y sus monedas y gemas, "sizeLuck" = multiplica la probabilidad de que además salga grande.
Config.ObjectRarities = {
	{ name = "Común", odds = 1, luck = 1, rolls = 1, hp = 1, reward = 1, sizeLuck = 1, color = Config.RarityTiers[1].color },
	{ name = "Poco común", odds = 4, luck = 1.5, rolls = 1, hp = 1.5, reward = 2, sizeLuck = 1, color = Config.RarityTiers[2].color },
	{ name = "Rara", odds = 15, luck = 2.5, rolls = 1, hp = 2.5, reward = 4, sizeLuck = 1.2, color = Config.RarityTiers[3].color },
	{ name = "Épica", odds = 60, luck = 4, rolls = 1.5, hp = 4, reward = 8, sizeLuck = 1.5, color = Config.RarityTiers[4].color },
	{ name = "Legendaria", odds = 300, luck = 8, rolls = 2, hp = 7, reward = 20, sizeLuck = 2, color = Config.RarityTiers[5].color },
	{ name = "Mítica", odds = 2000, luck = 20, rolls = 3, hp = 12, reward = 60, sizeLuck = 3, color = Config.RarityTiers[6].color },
}

-- Tamaños de los objetos: el primero es el normal y los demás salen 1 entre "odds" (como las rarezas). La escala
-- exacta se tira al azar entre "min" y "max" (1 = el tamaño de Config.Destructibles) y es la que cuenta para la
-- suerte, la vida y el premio; "rolls" = tiradas de arma de más.
Config.ObjectSizes = {
	{ name = "Normal", odds = 1, min = 0.9, max = 1.15, rolls = 0 },
	{ name = "Pequeño", odds = 4, min = 0.7, max = 0.9, rolls = 0 },
	{ name = "Grande", odds = 5, min = 1.15, max = 1.5, rolls = 0 },
	{ name = "Enorme", odds = 25, min = 1.5, max = 2, rolls = 0.5 },
	{ name = "Colosal", odds = 150, min = 2, max = 2.5, rolls = 1 },
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
	gachaLuck = { name = "Suerte de armas", short = "Armas", icon = "gem", color = Color3.fromRGB(180, 100, 255), mode = "mul", base = 1, perLevel = 3, maxLevel = 50, cost = 10, growth = 4.1, currency = "gems", display = "x%s" },
	-- Segundos entre apariciones de objetos en la parcela (lo lee Stats.spawnTime): cada objeto trae tiradas de arma, así
	-- que es la antigua "Velocidad de tirada" (misma clave, para no perder lo comprado). 1,5 s al principio, -12 % por
	-- nivel, ~0,42 s al final. Con Config.Gacha.FreeRoll también acorta la tirada gratis (Stats.rollTime).
	rollSpeed = { name = "Velocidad de aparición", short = "Aparición", icon = "orb", color = Color3.fromRGB(255, 190, 40), mode = "mul", base = Config.Plot.SpawnInterval, perLevel = 0.88, maxLevel = 10, cost = 300, growth = 3.4, display = "%.2fs" },
}

-- ARMADURA (cae en las mazmorras). Cuatro huecos, una pieza equipada por hueco. Números a ojo, sin equilibrar.
-- Cada pieza guarda sus valores ya tirados, así que cambiar esto no toca las piezas que ya tiene la gente.
-- Valor de un stat = base del hueco * azar (Roll) * mult de la calidad * power de la dificultad (Config.Dungeons)
-- (los stats con scales = false no se multiplican por power). "health" es vida que se suma; el resto son
-- porcentajes (0.05 = +5 %) que se suman entre piezas y luego multiplican el stat final (ver shared/Stats).
Config.Armor = {
	MaxPieces = 60, -- con el inventario lleno, las piezas nuevas se desmontan solas
	BaseHealth = 100, -- vida del personaje sin armadura
	Roll = { min = 0.8, max = 1.2 },
	SlotOrder = { "helmet", "chest", "legs", "boots" },
	Slots = {
		helmet = { name = "Casco", stats = { health = 40, luck = 0.05 } },
		chest = { name = "Pechera", stats = { health = 100 } },
		legs = { name = "Grebas", stats = { health = 60, rollSpeed = 0.04 } },
		boots = { name = "Botas", stats = { health = 30, damage = 0.03, luck = 0.03 } },
	},
	StatOrder = { "health", "damage", "luck", "rollSpeed" },
	Stats = {
		health = { name = "Vida máxima", flat = true, color = Color3.fromRGB(255, 110, 110) },
		damage = { name = "Ataque", color = Color3.fromRGB(255, 154, 106) },
		luck = { name = "Suerte", color = Color3.fromRGB(126, 224, 122) },
		rollSpeed = { name = "Velocidad de aparición", scales = false, color = Color3.fromRGB(255, 200, 90) },
	},
	-- Calidades, de peor a mejor: "odds" = 1 entre N de que salga (la suerte de la dificultad y del enemigo divide N),
	-- "mods" = modificadores extra que trae, "value" = Cristales de grado al desmontarla (por el loot de su dificultad).
	-- Son propias de la armadura (no las rarezas de las espadas). No cambies el orden: lo nuevo, al final.
	Qualities = {
		{ name = "Común", odds = 1, mult = 1, mods = 0, value = 1, color = Color3.fromRGB(190, 195, 205) },
		{ name = "Poco común", odds = 4, mult = 1.4, mods = 0, value = 2, color = Color3.fromRGB(90, 220, 100) },
		{ name = "Rara", odds = 20, mult = 2, mods = 1, value = 4, color = Color3.fromRGB(70, 150, 255) },
		{ name = "Épica", odds = 150, mult = 3, mods = 1, value = 10, color = Color3.fromRGB(180, 90, 255) },
		{ name = "Legendaria", odds = 2000, mult = 5, mods = 2, value = 30, color = Color3.fromRGB(255, 190, 40) },
		{ name = "Mítica", odds = 50000, mult = 8, mods = 3, value = 100, color = Color3.fromRGB(255, 70, 70) },
	},
	-- Modificadores extra: "chance" = peso de salir, "value" = base (se escala como los stats del hueco).
	Mods = {
		{ stat = "health", value = 30, chance = 40 },
		{ stat = "luck", value = 0.04, chance = 25 },
		{ stat = "damage", value = 0.04, chance = 25 },
		{ stat = "rollSpeed", value = 0.03, chance = 10 },
	},
}

-- MAZMORRAS (partida): cada grupo juega en su arena. Números a ojo, sin equilibrar.
Config.Dungeon = {
	TimeLimit = 300, -- segundos para terminar la mazmorra
	WaveDelay = 2, -- pausa entre oleadas
	ExitDelay = 4, -- segundos en la arena tras ganar, antes de volver al hub
	Origin = Vector3.new(0, 200, 3000), -- centro de la primera arena, lejos de la isla
	Spacing = 400, -- separación entre las arenas de cada partida
	MaxRuns = 10, -- partidas a la vez (cada una ocupa un hueco de arena; con "repetir" se necesita uno de sobra un momento)
	ArenaRadius = 60,
	-- Oleadas: lista de { enemigo (clave de Config.Enemies), cantidad }. La cantidad se multiplica por "count" de la dificultad.
	Waves = {
		{ { "grunt", 4 } },
		{ { "grunt", 4 }, { "brute", 1 } },
		{ { "grunt", 5 }, { "brute", 2 } },
		{ { "boss", 1 }, { "grunt", 3 } },
	},
	-- Premio por terminar la última oleada (mismo formato que los drops de los enemigos).
	ClearDrops = {
		{ kind = "item", item = "traitCrystal", chance = 1, min = 1, max = 2 },
		{ kind = "item", item = "gradeCrystal", chance = 1, min = 1, max = 2 },
	},
}

-- GRUPOS de mazmorra (server/Dungeons, server/Party). MaxSize = jugadores por grupo (se puede subir sin tocar código);
-- StartCountdown = segundos de cuenta atrás tras "Iniciar"; WaitTimeout = segundos que un grupo puede esperar sin empezar
-- antes de deshacerse; InviteTime = lo que dura una invitación; ActionCooldown = espera mínima entre peticiones de un
-- jugador; RoomDistance = a qué distancia del altar de una sala hay que estar. Scaling = por cada jugador de más, la vida
-- de los enemigos sube hp (0,75 = +75 %) y su cantidad count (los jefes no suben de cantidad).
Config.Party = {
	MaxSize = 4,
	MinSize = 1,
	StartCountdown = 3,
	WaitTimeout = 600,
	InviteTime = 30,
	ActionCooldown = 0.25,
	RoomDistance = 22,
	Scaling = { hp = 0.75, count = 0.5 },
}

-- LOBBY SUBTERRÁNEO de mazmorras (server/DungeonLobby): una boca en el centro del hub, una escalera de caracol que baja
-- hasta una caverna con una sala por zona de Config.Dungeons. Alturas Y: el suelo de la isla está en 0,4 y el mar y la
-- base debajo; el lobby va por debajo de todo. HoleRadius/RimRadius = boca y borde de piedra; Floor/Ceiling = suelo y
-- techo del lobby; ZoneY = por debajo de esta altura el cliente pone la luz del lobby (client/DungeonFx);
-- StepsPerTurn/StepRise = peldaños por vuelta y lo que baja cada uno; ExitAngle = hacia dónde sale la escalera (grados);
-- Rooms = las salas en anillo (la primera en FirstAngle; Radius/Width/Depth/Height en studs; crecen solas si hay más zonas).
-- "light" y "fx" = ambiente del lobby (mismo formato que Config.DungeonThemes).
Config.DungeonLobby = {
	HoleRadius = 13.5,
	RimRadius = 19.5,
	Floor = -80,
	Ceiling = -22,
	CavernRadius = 122,
	PlazaRadius = 46,
	ZoneY = -28,
	PillarRadius = 4.5,
	StairOuter = 13.6,
	StepsPerTurn = 24,
	StepRise = 1,
	ExitAngle = 270,
	Rooms = { FirstAngle = 285, Radius = 90, Width = 30, Depth = 30, Height = 22 },
	light = {
		clock = 0,
		ambient = Color3.fromRGB(96, 104, 144),
		outdoor = Color3.fromRGB(84, 92, 130),
		brightness = 1.2,
		atmosphere = { color = Color3.fromRGB(62, 72, 112), decay = Color3.fromRGB(40, 50, 92), density = 0.32, haze = 2, glare = 0 },
		tint = Color3.fromRGB(228, 234, 255),
		saturation = 0.08,
	},
	fx = { kind = "motes", color = Color3.fromRGB(170, 200, 255) },
}

-- Mazmorras (zonas), de menor a mayor. El jugador solo ve "name" (la zona) y "tagline"; "difficulty" es la etiqueta
-- interna del equilibrio (Fácil … Infinito) y no se enseña. "id" = clave estable (la usa Config.DungeonThemes).
-- "hp" = daño por golpe recomendado: la vida de un enemigo es su hp (en golpes) por
-- este número. "power" multiplica el daño de los enemigos Y los stats de la armadura que cae: cada dificultad pide
-- la armadura de la anterior. "count" = más enemigos, "loot" = más cristales, "qualityLuck" = mejor calidad de armadura.
-- "set", "armorColor" y "armorMaterial" = nombre y aspecto de la armadura que cae ahí ("Casco de cuero").
-- "color" = acento de la zona. "minDamage" (opcional) = daño mínimo para entrar (si no llega, la sala sale cerrada).
-- No cambies el orden: las piezas de armadura guardan la posición. Lo nuevo, al final.
Config.Dungeons = {
	{ id = "forest", name = "Bosque de los Susurros", difficulty = "Fácil", tagline = "Raíces viejas que murmuran tu nombre.", hp = 10, power = 1, count = 1, loot = 1, qualityLuck = 1, color = Color3.fromRGB(90, 210, 110), set = "de cuero", armorColor = Color3.fromRGB(150, 105, 65), armorMaterial = Enum.Material.Leather },
	{ id = "mines", name = "Minas Abandonadas", difficulty = "Normal", tagline = "Galerías olvidadas donde algo sigue picando.", hp = 1e3, power = 4, count = 1.25, loot = 2, qualityLuck = 3, color = Color3.fromRGB(240, 170, 70), set = "de hierro", armorColor = Color3.fromRGB(175, 180, 192), armorMaterial = Enum.Material.Metal },
	{ id = "crypt", name = "Cripta del Rey Caído", difficulty = "Difícil", tagline = "Un rey sin descanso y su corte de huesos.", hp = 1e5, power = 16, count = 1.5, loot = 4, qualityLuck = 10, color = Color3.fromRGB(160, 125, 225), set = "de obsidiana", armorColor = Color3.fromRGB(58, 50, 82), armorMaterial = Enum.Material.Slate },
	{ id = "temple", name = "Templo de las Cenizas", difficulty = "Pesadilla", tagline = "Brasas, incienso y fieles que no se rinden.", hp = 1e7, power = 64, count = 1.75, loot = 8, qualityLuck = 30, color = Color3.fromRGB(235, 70, 80), set = "carmesí", armorColor = Color3.fromRGB(165, 40, 52), armorMaterial = Enum.Material.Metal },
	{ id = "abyss", name = "Abismo Sumergido", difficulty = "Abismo", tagline = "Aguas hundidas donde la luz ya no llega.", hp = 1e9, power = 256, count = 2, loot = 16, qualityLuck = 100, color = Color3.fromRGB(50, 200, 210), set = "abisal", armorColor = Color3.fromRGB(88, 62, 200), armorMaterial = Enum.Material.Foil },
	-- Endgame. La mejor arma posible sin renacer pega ~7e30 por golpe: Espada del infinito (1,6e10) x Paradoja (57,5)
	-- x Etherio (~2,2e3) x Universal (~7e6) x los tres mejores artefactos de daño (5e8); renacer y la armadura suben más.
	-- Por eso la escalera sigue de 1e12 a 1e30, de 1000 en 1000.
	{ id = "inferno", name = "Caldera del Infierno", difficulty = "Infierno", tagline = "Una caldera viva: todo arde, todo golpea.", hp = 1e12, power = 1024, count = 2, loot = 32, qualityLuck = 200, color = Color3.fromRGB(255, 110, 40), set = "infernal", armorColor = Color3.fromRGB(200, 70, 30), armorMaterial = Enum.Material.CrackedLava },
	{ id = "void", name = "Páramo del Vacío", difficulty = "Vacío", tagline = "El suelo se acaba. El silencio, no.", hp = 1e15, power = 4096, count = 2, loot = 64, qualityLuck = 400, color = Color3.fromRGB(130, 70, 255), set = "del vacío", armorColor = Color3.fromRGB(60, 40, 110), armorMaterial = Enum.Material.Metal },
	{ id = "nebula", name = "Jardín de la Nebulosa", difficulty = "Nebulosa", tagline = "Un jardín de polvo de estrellas… con dientes.", hp = 1e18, power = 16384, count = 2.25, loot = 128, qualityLuck = 800, color = Color3.fromRGB(230, 90, 160), set = "de nebulosa", armorColor = Color3.fromRGB(205, 85, 150), armorMaterial = Enum.Material.Foil },
	{ id = "galaxy", name = "Observatorio Galáctico", difficulty = "Galaxia", tagline = "Mira las estrellas. Ellas te miran a ti.", hp = 1e21, power = 65536, count = 2.25, loot = 256, qualityLuck = 1500, color = Color3.fromRGB(60, 110, 255), set = "de galaxia", armorColor = Color3.fromRGB(45, 70, 190), armorMaterial = Enum.Material.Metal },
	{ id = "cosmos", name = "Bastión del Cosmos", difficulty = "Cosmos", tagline = "Torres de cristal que giran con el cosmos.", hp = 1e24, power = 262144, count = 2.5, loot = 512, qualityLuck = 3000, color = Color3.fromRGB(60, 255, 170), set = "del cosmos", armorColor = Color3.fromRGB(30, 60, 80), armorMaterial = Enum.Material.Slate },
	{ id = "origin", name = "Santuario del Origen", difficulty = "Origen", tagline = "Donde todo empezó, y donde todo se mide.", hp = 1e27, power = 1048576, count = 2.5, loot = 1024, qualityLuck = 6000, color = Color3.fromRGB(240, 245, 255), set = "del origen", armorColor = Color3.fromRGB(240, 240, 250), armorMaterial = Enum.Material.Marble },
	{ id = "infinity", name = "Trono del Infinito", difficulty = "Infinito", tagline = "El último trono. Nadie ha vuelto a sentarse.", hp = 1e30, power = 4194304, count = 3, loot = 2048, qualityLuck = 12000, color = Color3.fromRGB(255, 40, 60), set = "del infinito", armorColor = Color3.fromRGB(215, 35, 55), armorMaterial = Enum.Material.Foil },
}

-- Aspecto de cada zona de Config.Dungeons, por su "id" (lo construye server/DungeonThemes y lo viste client/DungeonFx):
-- "floor" = suelo y anillo; "wall" = estilo del muro ("stone", "trees", "rock", "crystal", "pillars" o "shards"), sus dos
-- colores y su material; "props" = decorado { kind, count, color? } (los kinds están en server/DungeonThemes); "ceiling" =
-- techo opcional con estalactitas ("hang"); "torch" = color de faroles y luces; "light" = iluminación del cliente mientras
-- estás dentro (hora, ambiente, niebla, atmósfera, tinte); "fx" = partículas del cliente (client/DungeonFx);
-- "enemies" = cómo se ven el Esbirro (grunt), el Bruto (brute) y el Guardián (boss) en esa zona: nombre, color, adornos
-- ("look", uno o varios) y escala, sin tocar sus números; "room" = decorado extra de su sala en el lobby subterráneo.
-- "waves" (opcional) cambia las oleadas de Config.Dungeon.Waves solo en esa zona (así se añaden jefes propios).
-- Una zona nueva = una entrada aquí y otra en Config.Dungeons.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Config.DungeonThemes = {
	forest = {
		floor = { color = rgb(66, 104, 58), material = Enum.Material.Grass, ring = rgb(112, 90, 60), ringMaterial = Enum.Material.Ground },
		wall = { style = "trees", colors = { rgb(92, 64, 44), rgb(52, 132, 66) }, material = Enum.Material.Wood },
		props = { { kind = "bush", count = 18 }, { kind = "mushroom", count = 16 }, { kind = "stump", count = 8 } },
		torch = rgb(170, 255, 170),
		light = { clock = 17.4, ambient = rgb(78, 104, 82), outdoor = rgb(120, 150, 120), brightness = 1.6, atmosphere = { color = rgb(150, 205, 150), decay = rgb(90, 150, 100), density = 0.42, haze = 2.4, glare = 0 }, tint = rgb(232, 255, 232), saturation = 0.12 },
		fx = { kind = "fireflies", color = rgb(200, 255, 150) },
		enemies = {
			grunt = { name = "Brote Susurrante", color = rgb(104, 176, 78), look = "leaf" },
			brute = { name = "Ent Joven", color = rgb(112, 86, 60), look = { "antlers", "leaf" }, scale = 1.05 },
			boss = { name = "Ent Anciano", color = rgb(76, 112, 64), look = { "antlers", "crown" } },
		},
		room = { { kind = "bush", count = 5 }, { kind = "mushroom", count = 6 } },
	},
	mines = {
		floor = { color = rgb(92, 84, 76), material = Enum.Material.Slate, ring = rgb(120, 106, 90), ringMaterial = Enum.Material.Cobblestone },
		wall = { style = "rock", colors = { rgb(86, 80, 74), rgb(70, 65, 62) }, material = Enum.Material.Rock },
		props = { { kind = "beam", count = 8 }, { kind = "cart", count = 3 }, { kind = "rails", count = 2 }, { kind = "crystal", count = 6, color = rgb(100, 180, 255) } },
		ceiling = { height = 40, color = rgb(60, 56, 54), material = Enum.Material.Rock, hang = 16 },
		torch = rgb(255, 176, 84),
		light = { clock = 0, ambient = rgb(104, 92, 80), outdoor = rgb(80, 76, 84), brightness = 1.2, atmosphere = { color = rgb(70, 58, 46), decay = rgb(60, 48, 40), density = 0.5, haze = 3, glare = 0 }, tint = rgb(255, 232, 206), saturation = 0.05 },
		fx = { kind = "dust", color = rgb(220, 190, 140) },
		enemies = {
			grunt = { name = "Topo de Cueva", color = rgb(146, 112, 86), look = "helmet" },
			brute = { name = "Capataz de Hierro", color = rgb(150, 152, 164), look = { "helmet", "spikes" }, scale = 1.05 },
			boss = { name = "Gólem de Mena", color = rgb(126, 102, 84), look = { "spikes", "crown" } },
		},
		room = { { kind = "beam", count = 2 }, { kind = "cart", count = 1 }, { kind = "crystal", count = 3, color = rgb(100, 180, 255) } },
	},
	crypt = {
		floor = { color = rgb(72, 68, 88), material = Enum.Material.Slate, ring = rgb(96, 88, 120), ringMaterial = Enum.Material.Marble },
		wall = { style = "stone", colors = { rgb(86, 82, 104), rgb(68, 64, 86) }, material = Enum.Material.Slate },
		props = { { kind = "coffin", count = 6 }, { kind = "column", count = 8 }, { kind = "bones", count = 16 }, { kind = "brazier", count = 6 } },
		ceiling = { height = 42, color = rgb(52, 48, 66), material = Enum.Material.Slate, hang = 12 },
		torch = rgb(170, 140, 255),
		light = { clock = 0, ambient = rgb(92, 82, 124), outdoor = rgb(80, 72, 110), brightness = 1.2, atmosphere = { color = rgb(70, 56, 100), decay = rgb(50, 40, 80), density = 0.55, haze = 3.2, glare = 0 }, tint = rgb(235, 225, 255), saturation = 0.02 },
		fx = { kind = "wisps", color = rgb(190, 200, 255) },
		enemies = {
			grunt = { name = "Esqueleto", color = rgb(226, 222, 204), look = "skull" },
			brute = { name = "Caballero Caído", color = rgb(122, 120, 144), look = { "skull", "horns" }, scale = 1.05 },
			boss = { name = "Rey Caído", color = rgb(204, 198, 178), look = { "skull", "crown" } },
		},
		room = { { kind = "column", count = 2 }, { kind = "bones", count = 6 }, { kind = "brazier", count = 2 } },
	},
	temple = {
		floor = { color = rgb(68, 52, 54), material = Enum.Material.Basalt, ring = rgb(150, 62, 62), ringMaterial = Enum.Material.Brick },
		wall = { style = "pillars", colors = { rgb(128, 74, 68), rgb(96, 54, 54) }, material = Enum.Material.Brick },
		props = { { kind = "banner", count = 8, color = rgb(190, 48, 58) }, { kind = "brazier", count = 8 }, { kind = "column", count = 4 } },
		torch = rgb(255, 120, 72),
		light = { clock = 18.6, ambient = rgb(120, 70, 66), outdoor = rgb(150, 86, 78), brightness = 1.4, atmosphere = { color = rgb(190, 90, 76), decay = rgb(140, 60, 56), density = 0.5, haze = 2.6, glare = 0.1 }, tint = rgb(255, 224, 214), saturation = 0.1 },
		fx = { kind = "ash", color = rgb(214, 200, 196) },
		enemies = {
			grunt = { name = "Acólito Ceniciento", color = rgb(132, 72, 68), look = "hood" },
			brute = { name = "Verdugo", color = rgb(92, 62, 62), look = { "hood", "horns" }, scale = 1.05 },
			boss = { name = "Sumo Sacerdote", color = rgb(176, 52, 62), look = { "hood", "flame", "crown" } },
		},
		room = { { kind = "banner", count = 3, color = rgb(190, 48, 58) }, { kind = "brazier", count = 3 } },
	},
	abyss = {
		floor = { color = rgb(44, 74, 94), material = Enum.Material.Slate, ring = rgb(64, 110, 130), ringMaterial = Enum.Material.Sand },
		wall = { style = "rock", colors = { rgb(38, 76, 100), rgb(30, 60, 84) }, material = Enum.Material.Slate },
		props = { { kind = "kelp", count = 20 }, { kind = "crystal", count = 6, color = rgb(90, 230, 255) }, { kind = "boulder", count = 8 } },
		torch = rgb(100, 230, 255),
		light = { clock = 12, ambient = rgb(52, 98, 126), outdoor = rgb(60, 110, 140), brightness = 1.3, atmosphere = { color = rgb(30, 100, 130), decay = rgb(20, 70, 100), density = 0.6, haze = 3.4, glare = 0 }, tint = rgb(200, 238, 255), saturation = 0.15 },
		fx = { kind = "bubbles", color = rgb(200, 240, 255) },
		enemies = {
			grunt = { name = "Pez Linterna", color = rgb(64, 150, 190), look = "halo" },
			brute = { name = "Cangrejo Coralino", color = rgb(216, 104, 92), look = "spikes", scale = 1.05 },
			boss = { name = "Leviatán", color = rgb(52, 92, 172), look = { "spikes", "crown" } },
		},
		room = { { kind = "kelp", count = 6 }, { kind = "crystal", count = 3, color = rgb(90, 230, 255) } },
	},
	inferno = {
		floor = { color = rgb(52, 40, 38), material = Enum.Material.Basalt, ring = rgb(255, 120, 40), ringMaterial = Enum.Material.CrackedLava },
		wall = { style = "rock", colors = { rgb(64, 46, 42), rgb(46, 34, 32) }, material = Enum.Material.Basalt },
		props = { { kind = "lavaPool", count = 8 }, { kind = "boulder", count = 10 }, { kind = "brazier", count = 6 } },
		torch = rgb(255, 140, 52),
		light = { clock = 0, ambient = rgb(138, 70, 44), outdoor = rgb(120, 62, 44), brightness = 1.4, atmosphere = { color = rgb(140, 60, 30), decay = rgb(110, 40, 20), density = 0.55, haze = 3, glare = 0 }, tint = rgb(255, 214, 190), saturation = 0.15 },
		fx = { kind = "embers", color = rgb(255, 150, 60) },
		enemies = {
			grunt = { name = "Imp de Ceniza", color = rgb(232, 104, 52), look = "flame" },
			brute = { name = "Demonio de Magma", color = rgb(192, 74, 42), look = { "horns", "flame" }, scale = 1.05 },
			boss = { name = "Señor de la Caldera", color = rgb(152, 42, 32), look = { "horns", "crown", "flame" } },
		},
		room = { { kind = "lavaPool", count = 3 }, { kind = "boulder", count = 3 }, { kind = "brazier", count = 2 } },
	},
	void = {
		floor = { color = rgb(32, 28, 46), material = Enum.Material.Slate, ring = rgb(120, 76, 240), ringMaterial = Enum.Material.Glass },
		wall = { style = "shards", colors = { rgb(62, 50, 94), rgb(42, 34, 72) }, material = Enum.Material.Basalt },
		props = { { kind = "floatRock", count = 12 }, { kind = "star", count = 30 }, { kind = "crystal", count = 5, color = rgb(160, 110, 255) } },
		torch = rgb(172, 112, 255),
		light = { clock = 0, ambient = rgb(84, 62, 128), outdoor = rgb(70, 52, 110), brightness = 1.2, atmosphere = { color = rgb(60, 30, 110), decay = rgb(40, 20, 80), density = 0.45, haze = 2.4, glare = 0 }, tint = rgb(236, 224, 255), saturation = 0.1 },
		fx = { kind = "motes", color = rgb(190, 140, 255) },
		enemies = {
			grunt = { name = "Sombra Errante", color = rgb(62, 42, 104), look = "hood" },
			brute = { name = "Acechador del Vacío", color = rgb(94, 62, 154), look = { "hood", "halo" }, scale = 1.05 },
			boss = { name = "Heraldo del Vacío", color = rgb(42, 22, 84), look = { "halo", "crown" } },
		},
		room = { { kind = "floatRock", count = 4 }, { kind = "star", count = 10 }, { kind = "crystal", count = 3, color = rgb(160, 110, 255) } },
	},
	nebula = {
		floor = { color = rgb(84, 54, 104), material = Enum.Material.Marble, ring = rgb(214, 116, 188), ringMaterial = Enum.Material.Glass },
		wall = { style = "crystal", colors = { rgb(236, 116, 196), rgb(176, 96, 226) }, material = Enum.Material.Glass },
		props = { { kind = "crystal", count = 10, color = rgb(244, 130, 210) }, { kind = "floatRock", count = 6 }, { kind = "star", count = 24 } },
		torch = rgb(255, 144, 224),
		light = { clock = 20, ambient = rgb(132, 84, 146), outdoor = rgb(120, 78, 140), brightness = 1.4, atmosphere = { color = rgb(226, 112, 184), decay = rgb(160, 70, 150), density = 0.45, haze = 2.2, glare = 0.2 }, tint = rgb(255, 228, 250), saturation = 0.2 },
		fx = { kind = "sparkles", color = rgb(255, 170, 230) },
		enemies = {
			grunt = { name = "Espora Estelar", color = rgb(242, 134, 192), look = "leaf" },
			brute = { name = "Guardián Floral", color = rgb(204, 94, 172), look = { "leaf", "horns" }, scale = 1.05 },
			boss = { name = "Reina de la Nebulosa", color = rgb(174, 84, 204), look = { "leaf", "crown", "halo" } },
		},
		room = { { kind = "crystal", count = 4, color = rgb(244, 130, 210) }, { kind = "star", count = 10 } },
	},
	galaxy = {
		floor = { color = rgb(30, 40, 82), material = Enum.Material.Metal, ring = rgb(96, 136, 255), ringMaterial = Enum.Material.Glass },
		wall = { style = "pillars", colors = { rgb(62, 84, 154), rgb(42, 58, 112) }, material = Enum.Material.Metal },
		props = { { kind = "orbitRing", count = 2, color = rgb(130, 170, 255) }, { kind = "star", count = 30 }, { kind = "column", count = 6 } },
		torch = rgb(124, 172, 255),
		light = { clock = 0, ambient = rgb(70, 92, 156), outdoor = rgb(64, 84, 144), brightness = 1.2, atmosphere = { color = rgb(50, 80, 170), decay = rgb(30, 50, 120), density = 0.4, haze = 2, glare = 0 }, tint = rgb(226, 234, 255), saturation = 0.12 },
		fx = { kind = "stars", color = rgb(200, 220, 255) },
		enemies = {
			grunt = { name = "Satélite Rebelde", color = rgb(124, 144, 204), look = "spikes" },
			brute = { name = "Astrónomo Errante", color = rgb(84, 104, 194), look = { "hood", "halo" }, scale = 1.05 },
			boss = { name = "Titán Estelar", color = rgb(60, 92, 232), look = { "halo", "spikes" } },
		},
		room = { { kind = "orbitRing", count = 1, color = rgb(130, 170, 255) }, { kind = "star", count = 10 }, { kind = "column", count = 2 } },
	},
	cosmos = {
		floor = { color = rgb(26, 58, 66), material = Enum.Material.Slate, ring = rgb(64, 240, 170), ringMaterial = Enum.Material.Glass },
		wall = { style = "crystal", colors = { rgb(70, 232, 176), rgb(44, 176, 156) }, material = Enum.Material.Glass },
		props = { { kind = "crystal", count = 12, color = rgb(90, 255, 190) }, { kind = "orbitRing", count = 1, color = rgb(90, 255, 190) }, { kind = "column", count = 6 } },
		torch = rgb(112, 255, 204),
		light = { clock = 0, ambient = rgb(66, 132, 122), outdoor = rgb(58, 120, 112), brightness = 1.3, atmosphere = { color = rgb(40, 150, 130), decay = rgb(20, 100, 90), density = 0.42, haze = 2.2, glare = 0 }, tint = rgb(220, 255, 244), saturation = 0.15 },
		fx = { kind = "motes", color = rgb(130, 255, 210) },
		enemies = {
			grunt = { name = "Fragmento Cósmico", color = rgb(84, 232, 184), look = "spikes" },
			brute = { name = "Centinela de Cristal", color = rgb(62, 192, 172), look = { "helmet", "spikes" }, scale = 1.05 },
			boss = { name = "Arconte del Cosmos", color = rgb(42, 162, 152), look = { "halo", "crown" } },
		},
		room = { { kind = "crystal", count = 5, color = rgb(90, 255, 190) }, { kind = "column", count = 2 } },
	},
	origin = {
		floor = { color = rgb(232, 232, 244), material = Enum.Material.Marble, ring = rgb(205, 214, 238), ringMaterial = Enum.Material.Marble },
		wall = { style = "pillars", colors = { rgb(246, 246, 255), rgb(222, 226, 242) }, material = Enum.Material.Marble },
		props = { { kind = "column", count = 10 }, { kind = "banner", count = 6, color = rgb(240, 214, 120) }, { kind = "brazier", count = 6 }, { kind = "star", count = 16 } },
		torch = rgb(255, 248, 224),
		light = { clock = 12.5, ambient = rgb(176, 182, 202), outdoor = rgb(176, 182, 204), brightness = 2.2, atmosphere = { color = rgb(235, 240, 255), decay = rgb(200, 210, 245), density = 0.35, haze = 1.6, glare = 0.3 }, tint = rgb(255, 252, 244), saturation = 0.02 },
		fx = { kind = "motes", color = rgb(255, 250, 230) },
		enemies = {
			grunt = { name = "Eco del Origen", color = rgb(236, 238, 250), look = "halo" },
			brute = { name = "Guardián de Mármol", color = rgb(214, 218, 236), look = { "horns", "halo" }, scale = 1.05 },
			boss = { name = "Primer Testigo", color = rgb(255, 246, 222), look = { "halo", "crown" } },
		},
		room = { { kind = "column", count = 3 }, { kind = "banner", count = 2, color = rgb(240, 214, 120) }, { kind = "star", count = 8 } },
	},
	infinity = {
		floor = { color = rgb(22, 16, 20), material = Enum.Material.Basalt, ring = rgb(176, 32, 48), ringMaterial = Enum.Material.Metal },
		wall = { style = "pillars", colors = { rgb(44, 30, 38), rgb(64, 36, 46) }, material = Enum.Material.Basalt },
		props = { { kind = "column", count = 8 }, { kind = "banner", count = 8, color = rgb(190, 30, 50) }, { kind = "brazier", count = 10 }, { kind = "lavaPool", count = 4 } },
		torch = rgb(255, 72, 84),
		light = { clock = 0, ambient = rgb(124, 46, 58), outdoor = rgb(104, 40, 52), brightness = 1.3, atmosphere = { color = rgb(130, 24, 40), decay = rgb(90, 14, 30), density = 0.5, haze = 2.8, glare = 0 }, tint = rgb(255, 224, 224), saturation = 0.12 },
		fx = { kind = "embers", color = rgb(255, 80, 90) },
		enemies = {
			grunt = { name = "Sombra Infinita", color = rgb(74, 32, 54), look = "hood" },
			brute = { name = "Verdugo del Trono", color = rgb(112, 32, 44), look = { "horns", "spikes" }, scale = 1.05 },
			boss = { name = "Rey del Infinito", color = rgb(212, 32, 58), look = { "crown", "horns", "flame" } },
		},
		room = { { kind = "column", count = 3 }, { kind = "banner", count = 3, color = rgb(190, 30, 50) }, { kind = "brazier", count = 3 } },
	},
}

-- Daños pensados para que, con el set común de la dificultad anterior, el jefe necesite unos 5 golpes para matarte.
-- Enemigos. "hp" en golpes (por el hp de la dificultad), "damage" por golpe (por el power de la dificultad),
-- "speed" al andar, "attackRange" desde su borde, "attackTime" segundos entre golpes. scaleCount = false: su
-- cantidad no crece con la dificultad. "look" = adornos ("horns", "crown"). "drops" = tabla de premios al morir (ver server/Loot): cada entrada lleva
-- "kind" ("item" con item, min y max; "armor" con luck que multiplica la suerte de calidad) y "chance".
Config.Enemies = {
	grunt = { name = "Esbirro", hp = 6, damage = 3, speed = 17, attackRange = 3.5, attackTime = 1.2, size = Vector3.new(4, 4, 4), color = Color3.fromRGB(120, 200, 90), drops = {
		{ kind = "item", item = "traitCrystal", chance = 0.12 },
		{ kind = "item", item = "gradeCrystal", chance = 0.12 },
		{ kind = "armor", chance = 0.06 },
	} },
	brute = { name = "Bruto", hp = 20, damage = 7, speed = 11, attackRange = 4, attackTime = 1.8, look = "horns", size = Vector3.new(6.5, 6.5, 6.5), color = Color3.fromRGB(200, 110, 70), drops = {
		{ kind = "item", item = "traitCrystal", chance = 0.35 },
		{ kind = "item", item = "gradeCrystal", chance = 0.35 },
		{ kind = "armor", chance = 0.2, luck = 2 },
	} },
	boss = { name = "Guardián", hp = 120, damage = 12, speed = 13, attackRange = 5, attackTime = 2, scaleCount = false, look = "crown", size = Vector3.new(11, 11, 11), color = Color3.fromRGB(150, 80, 220), drops = {
		{ kind = "item", item = "traitCrystal", chance = 1, min = 2, max = 4 },
		{ kind = "item", item = "gradeCrystal", chance = 1, min = 2, max = 4 },
		{ kind = "armor", chance = 1, luck = 5 },
	} },
}

-- COMERCIO entre jugadores (server/Trade). Countdown = segundos de la cuenta atrás final, en los que aún se puede
-- cancelar; InviteTime = lo que dura una invitación; RequestCooldown = espera entre invitaciones.
-- Sugerencias dentro del trato ("Quiero" / "Te doy"): SuggestCooldown = espera entre sugerencias, SuggestTime = lo
-- que dura una sin respuesta, SuggestMaxAmount = tope de la cantidad de un "Quiero", SuggestWant = qué se puede pedir.
Config.Trade = {
	Countdown = 3,
	InviteTime = 20,
	RequestCooldown = 3,
	SuggestCooldown = 0.4,
	SuggestTime = 20,
	SuggestMaxAmount = 1e36,
	SuggestWant = { coins = true, gems = true, items = true },
}

-- PASES DE JUEGO (gamepass; tienda del menú, client/PassShop y server/Passes). "id" = id del pase en Roblox
-- (se crea en la página del juego; con 0 aún no está a la venta y el botón dice "Pronto"). "price" = Robux que se
-- enseñan hasta que Roblox dice el precio real. "perksText" = lo que se lee en la tienda. "perks" = ventajas que
-- lee Stats.perk (si varios pases dan la misma, vale la mayor): traitCount = rasgos que se pueden tirar de golpe;
-- gradeSpeed = por cuánto se multiplica la velocidad de las tiradas de grado (4 = 400 %).
Config.GamepassOrder = { "forge" }
Config.Gamepasses = {
	forge = {
		id = 0,
		name = "Maestro de la forja",
		price = 199,
		color = Color3.fromRGB(255, 150, 60),
		perksText = { "Tira 10 rasgos a la vez (se queda el mejor)", "Tiradas de grado al 400 % de velocidad" },
		perks = { traitCount = 10, gradeSpeed = 4 },
	},
}

return Config
