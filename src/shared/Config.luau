-- Todos los números del juego están aquí. Para equilibrar, toca solo este archivo.
local Config = {}

Config.WalkSpeed = 30 -- velocidad al andar (la normal de Roblox es 16)

-- Modo de pruebas: solo actúa al darle a Jugar dentro de Studio, nunca en el juego publicado.
-- No guarda el progreso de esa partida.
Config.Test = {
	InfiniteMoney = true, -- monedas y gemas infinitas
	AllWeapons = true, -- una copia de cada arma de Config.Swords en la mochila al entrar
	BestWeapons = 0, -- copias del arma de más daño que existe (mejor arma, metal, tamaño, rasgo y grado) en la mochila al entrar, con las primeras equipadas; 0 = ninguna
	Admin = true, -- botón "Admin" en las tiendas de Rasgos y Grados: eliges a mano el rasgo o grado de la espada, sin tirar ni gastar. También te hace administrador en Studio (menú "Admin" del clima: server/Admin)
	TradeBot = true, -- "Bot de pruebas" en la lista de Comercio: acepta y confirma solo, para probar un trato sin otro jugador
	AllGamepasses = true, -- todos los pases de juego de Config.Gamepasses (para probar sus ventajas sin comprarlos)
	AllGear = true, -- todos los accesorios (Config.Artifacts) y una pieza de armadura de cada hueco y cada mazmorra al entrar
	AllPotions = 2, -- copias de cada poción (Config.Potions) en la mochila al entrar; 0 = ninguna. InfiniteMoney no las hace infinitas, para poder probar que se gastan
	RevealSlow = 1, -- por cuánto se alargan los tiempos de la presentación de las tiradas (client/RollReveal): con 4 se ve a cámara lenta para revisarla en capturas
	PartyBots = 0, -- compañeros "fantasma" que se unen a tu grupo de mazmorra (cuentan para el tamaño y el escalado, no pelean): para probar con un solo jugador
	Progress = 0, -- horas de juego con las que se empieza (0 = partida nueva): deja al jugador como estaría a esa hora según el calendario de tools/equilibrio (mejoras, renacimientos, armas equipadas, accesorios y armadura de shared/BalanceSnapshots), para probar cada etapa sin jugarla entera. Mientras vale más de 0 los demás modos de arriba que dan cosas (dinero, armas, accesorios, pociones) no actúan; con 0.01 es una partida nueva de verdad
	Tickets = 0, -- tickets (Config.Items.missionToken) que se dan al entrar, para probar la compra de pases con tickets (con AllGamepasses en false); 0 = ninguno
	Tutorial = false, -- el tutorial de los primeros minutos (Config.Tutorial) desde el paso 1 al entrar; en Studio no sale sin esto
	Lang = "", -- "en" o "es": idioma forzado de los textos (shared/Lang); "" = el de la cuenta de Roblox
	Weather = "", -- id de un clima de Config.Weather.Events para tenerlo puesto al entrar ("" = el que toque por la hora)
	WorldBoss = 0, -- segundos hasta el primer Jefe del mundo al darle a Jugar (0 = el calendario normal, cada Config.WorldBoss.Interval)
	WorldBossPhase = "", -- "barrage", "summon", "shield" o "charge": el jefe solo hace esa fase, una y otra vez, para probarla ("" = todas)
}
-- Administradores en el juego publicado: solo estas cuentas (ni el dueño del grupo); UserId de Roblox de cada uno (server/Admin). Ven el menú
-- "Admin" y pueden, de momento, cambiar el clima de su servidor. 4490621018 = Lotozno. Solo Sergio decide quién entra aquí
-- (ver "Administradores" en CLAUDE.md).
Config.Admins = { 4490621018 }
-- Jugadores que van aparte (pedido por el usuario, para su propia cuenta): juegan y guardan como todos, pero no salen en
-- las clasificaciones globales ni pueden tener la "Mejor tirada" del hub (server/Leaderboards y server/BestRoll).
Config.Unranked = { 4490621018 }
Config.BaseCooldown = 0.35 -- segundos entre golpes de una espada (cada tipo de arma lo multiplica por su "cooldown"). No hay mejora ni poción que lo baje
Config.MinCooldown = 0.1 -- tiempo mínimo entre golpes, por rápida que sea el arma
Config.StartCoins = 0
Config.AutosaveInterval = 60
Config.DataStoreName = "PlayerData_v4" -- v4 = todo el progreso borrado otra vez, con el equilibrio de 100 h (v1, v2 y v3 eran partidas anteriores)
-- Candado de sesión del guardado (server/PlayerData): mientras un servidor tiene abierta la partida de un jugador, otro no la
-- carga (así no se lee lo de antes del último guardado al cambiar de servidor deprisa, que duplicaría lo de un trato).
-- Retry = segundos entre intentos de cargar una partida cogida; Wait = cuánto se espera antes de echar al jugador con un aviso;
-- Expire = segundos sin renovarse tras los que el candado se da por muerto (servidor caído; tiene que ser bastante más que
-- AutosaveInterval, que es cada cuánto se renueva); SaveTries = intentos del guardado al salir.
Config.SessionLock = { Retry = 3, Wait = 30, Expire = 180, SaveTries = 3 }

-- Tipos de arma. Cada arma de Config.Swords lleva "kind" (sin él es "sword").
-- cooldown = multiplica el tiempo entre golpes. Cada arma equipada vuela a su objetivo y le pega a su ritmo; además:
-- area = salpica: pega también a lo que haya alrededor del objetivo, hasta esa distancia en veces el largo del arma (0 = no);
-- pierce = atraviesa: pega también a lo que haya detrás del objetivo, en línea desde el jugador, hasta esa distancia en
-- veces su largo. La cuenta es de shared/Hitbox (Hitbox.spread).
Config.WeaponKinds = {
	sword = { name = "Sword", cooldown = 1, area = 0 },
	axe = { name = "Axe", cooldown = 1.7, area = 1.6 }, -- lenta, pero salpica alrededor del objetivo
	dual = { name = "Dual Swords", cooldown = 0.55, area = 0 }, -- golpes rápidos
	spear = { name = "Spear", cooldown = 1.1, area = 0, pierce = 1 }, -- atraviesa lo que hay detrás
	hammer = { name = "Hammer", cooldown = 2.2, area = 2.2 }, -- muy lento, salpica en un área ancha
}

-- REGLA DE EQUILIBRIO (rareza -> daño): cada vez que la rareza se multiplica por 2, el daño sube un 50 %
-- (rareza 2 = daño 1, rareza 4 = 1,5, rareza 8 = 2,25...). Solo depende de la rareza base, nunca del tipo ni la suerte.
-- Las armas del gacha van en una escalera que se va abriendo (curva de
-- dificultad pedida: muy rápida al principio para enganchar y cada vez más cuesta): la primera es solo ~x1.6 más
-- rara que la anterior (una nueva cada pocas tiradas) y la última ~x4.9. Va de 3 a 6e17, sin saltos grandes.
-- La vida de los objetos (Config.Destructibles) sale del daño que van dando estas armas (tools/equilibrio). Al añadir
-- un arma, su daño lo calcula la regla; si es más rara que todas, regenera el equilibrio (cambia TypeLuckPower).
-- La primera es la inicial y no sale en el gacha.
-- "rarity" = 1 entre N de que salga en cada tirada (se prueba de la más rara a la más común).
-- "bladeLength" = largo del arma: en la lanza es el asta entera y en el hacha el mango.
-- El jugador puede tener varias copias de cada una, cada copia con su propio rasgo.
-- No cambies el orden: el inventario guardado usa la posición en esta lista. Lo nuevo va al final.
Config.Swords = {
	{ name = "Wooden Sword", bladeLength = 3, color = Color3.fromRGB(150, 105, 60), material = Enum.Material.Wood },
	{ name = "Stone Sword", rarity = 3, bladeLength = 3.4, color = Color3.fromRGB(130, 130, 135), material = Enum.Material.Slate },
	{ name = "Iron Sword", rarity = 4.7, bladeLength = 3.8, color = Color3.fromRGB(200, 205, 210), material = Enum.Material.Metal },
	{ name = "Steel Sword", rarity = 21.7, bladeLength = 4.3, color = Color3.fromRGB(120, 160, 200), material = Enum.Material.Metal },
	{ name = "Golden Sword", rarity = 131, bladeLength = 4.8, color = Color3.fromRGB(255, 200, 50), material = Enum.Material.Foil },
	{ name = "Diamond Sword", rarity = 254, bladeLength = 5.4, color = Color3.fromRGB(90, 230, 255), material = Enum.Material.Glass },
	{ name = "Plasma Sword", rarity = 2210, bladeLength = 6.2, color = Color3.fromRGB(255, 70, 220), material = Enum.Material.Neon },
	{ name = "Void Sword", rarity = 25000, bladeLength = 7.5, color = Color3.fromRGB(120, 60, 255), material = Enum.Material.Neon },
	{ name = "Solar Sword", rarity = 59800, bladeLength = 7.8, color = Color3.fromRGB(255, 150, 30), material = Enum.Material.Neon },
	{ name = "Comet Sword", rarity = 2.62e6, bladeLength = 8, color = Color3.fromRGB(170, 240, 255), material = Enum.Material.Ice },
	{ name = "Nebula Sword", rarity = 6.11e7, bladeLength = 8.2, color = Color3.fromRGB(230, 90, 160), material = Enum.Material.ForceField },
	{ name = "Galactic Sword", rarity = 2.12e10, bladeLength = 8.4, color = Color3.fromRGB(60, 90, 255), material = Enum.Material.Neon },
	{ name = "Quantum Sword", rarity = 7.48e10, bladeLength = 8.6, color = Color3.fromRGB(60, 255, 170), material = Enum.Material.ForceField },
	{ name = "Cosmos Sword", rarity = 6.39e13, bladeLength = 8.8, color = Color3.fromRGB(20, 20, 40), material = Enum.Material.Glass },
	{ name = "Origin Sword", rarity = 2.7e14, bladeLength = 9, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Infinity Sword", rarity = 5.67e17, bladeLength = 9.5, color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas (añadidas después: por eso no van ordenadas por rareza).
	{ name = "Lumberjack Axe", kind = "axe", rarity = 7.6, bladeLength = 3.5, color = Color3.fromRGB(170, 175, 185), material = Enum.Material.Metal },
	{ name = "Twin Daggers", kind = "dual", rarity = 12.7, bladeLength = 2.4, color = Color3.fromRGB(190, 200, 215), material = Enum.Material.Metal },
	{ name = "Hunting Spear", kind = "spear", rarity = 38.4, bladeLength = 9, color = Color3.fromRGB(205, 210, 220), material = Enum.Material.Metal },
	{ name = "War Axe", kind = "axe", rarity = 507, bladeLength = 4.5, color = Color3.fromRGB(200, 70, 60), material = Enum.Material.Metal },
	{ name = "Twin Sabers", kind = "dual", rarity = 1040, bladeLength = 3.6, color = Color3.fromRGB(80, 210, 160), material = Enum.Material.Foil },
	{ name = "Jade Spear", kind = "spear", rarity = 10800, bladeLength = 11, color = Color3.fromRGB(70, 200, 130), material = Enum.Material.Glass },
	{ name = "Volcanic Axe", kind = "axe", rarity = 373000, bladeLength = 5.5, color = Color3.fromRGB(255, 110, 30), material = Enum.Material.Neon },
	{ name = "Eclipse Blades", kind = "dual", rarity = 973000, bladeLength = 5, color = Color3.fromRGB(150, 80, 255), material = Enum.Material.Neon },
	{ name = "Lightning Spear", kind = "spear", rarity = 7.27e6, bladeLength = 13, color = Color3.fromRGB(255, 240, 90), material = Enum.Material.Neon },
	-- Martillos: lentos, golpe en área; el daño base sigue la misma curva de rareza.
	{ name = "Stone Maul", kind = "hammer", rarity = 70, bladeLength = 3.2, color = Color3.fromRGB(135, 138, 145), material = Enum.Material.Slate },
	{ name = "War Hammer", kind = "hammer", rarity = 4810, bladeLength = 3.8, color = Color3.fromRGB(120, 150, 190), material = Enum.Material.Metal },
	{ name = "Thunder Hammer", kind = "hammer", rarity = 147000, bladeLength = 4.4, color = Color3.fromRGB(255, 225, 70), material = Enum.Material.Neon },
	{ name = "Magma Hammer", kind = "hammer", rarity = 2.08e7, bladeLength = 5, color = Color3.fromRGB(255, 90, 30), material = Enum.Material.Neon },
	{ name = "Glacial Hammer", kind = "hammer", rarity = 6.2e9, bladeLength = 5.4, color = Color3.fromRGB(150, 225, 255), material = Enum.Material.Ice },
	{ name = "Cosmic Hammer", kind = "hammer", rarity = 2.72e11, bladeLength = 5.8, color = Color3.fromRGB(150, 70, 255), material = Enum.Material.ForceField },
	{ name = "Doomsday Hammer", kind = "hammer", rarity = 1.17e15, bladeLength = 6.2, color = Color3.fromRGB(230, 255, 255), material = Enum.Material.Neon },
	-- Hachas, espadas dobles y lanzas de las rarezas altas (Mítica, Secreta y Divina).
	{ name = "Abyss Axe", kind = "axe", rarity = 5.8e8, bladeLength = 6, color = Color3.fromRGB(70, 60, 200), material = Enum.Material.Neon },
	{ name = "Shadow Fangs", kind = "dual", rarity = 1.86e8, bladeLength = 5.4, color = Color3.fromRGB(110, 40, 160), material = Enum.Material.Glass },
	{ name = "Abyssal Spear", kind = "spear", rarity = 1.87e9, bladeLength = 14, color = Color3.fromRGB(40, 90, 230), material = Enum.Material.Neon },
	{ name = "Stellar Axe", kind = "axe", rarity = 3.93e12, bladeLength = 6.4, color = Color3.fromRGB(255, 110, 200), material = Enum.Material.Neon },
	{ name = "Aurora Sabers", kind = "dual", rarity = 1.02e12, bladeLength = 5.8, color = Color3.fromRGB(90, 255, 210), material = Enum.Material.ForceField },
	{ name = "Nova Spear", kind = "spear", rarity = 1.56e13, bladeLength = 15, color = Color3.fromRGB(255, 130, 220), material = Enum.Material.Neon },
	{ name = "Dawn Axe", kind = "axe", rarity = 2.43e16, bladeLength = 6.8, color = Color3.fromRGB(255, 235, 170), material = Enum.Material.Neon },
	{ name = "Eternal Dawn Blades", kind = "dual", rarity = 5.26e15, bladeLength = 6.2, color = Color3.fromRGB(250, 255, 255), material = Enum.Material.Neon },
	{ name = "Big Bang Spear", kind = "spear", rarity = 1.16e17, bladeLength = 16, color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	-- La más rara: mandoble modelado en Blender (colmillo con muescas, canal de energía y aura turquesa y magenta).
	-- `mesh` = módulo de shared/Meshes con su forma (la dibuja shared/MeshWeapon en vez de las piezas de SwordModel).
	{ name = "Astral Fang", mesh = "ColmilloAstral", rarity = 3e18, bladeLength = 10, color = Color3.fromRGB(60, 230, 215), material = Enum.Material.Neon },
}

-- Se conserva el campo damage para los consumidores existentes, pero ya no se equilibra a mano.
function Config.damageFromRarity(odds: number): number
	return 1.5 ^ math.max(math.log(odds / 2, 2), 0)
end
for _, sword in Config.Swords do
	sword.damage = Config.damageFromRarity(sword.rarity or 2)
end

-- Niveles de rareza, de menor a mayor: a partir de "1 entre min" se usa ese nombre y color
-- (borde de las casillas del inventario, carteles).
Config.RarityTiers = {
	{ min = 0, name = "Common", color = Color3.fromRGB(190, 195, 205) },
	{ min = 10, name = "Uncommon", color = Color3.fromRGB(90, 220, 100) },
	{ min = 100, name = "Rare", color = Color3.fromRGB(70, 150, 255) },
	{ min = 1e4, name = "Epic", color = Color3.fromRGB(180, 90, 255) },
	{ min = 1e6, name = "Legendary", color = Color3.fromRGB(255, 190, 40) },
	{ min = 1e9, name = "Mythic", color = Color3.fromRGB(255, 70, 70) },
	{ min = 1e15, name = "Secret", color = Color3.fromRGB(255, 90, 210) },
	{ min = 1e21, name = "Divine", color = Color3.fromRGB(120, 255, 240) },
	-- Por encima de Divina solo se llega con metal y tamaño (el arma más rara sola es Secreta): reparten las
	-- combinaciones más altas, que si no eran todas Divinas.
	{ min = 1e24, name = "Eternal", color = Color3.fromRGB(195, 255, 90) },
	{ min = 1e28, name = "Primordial", color = Color3.fromRGB(255, 140, 50) },
	{ min = 1e32, name = "Absolute", color = Color3.fromRGB(255, 232, 140) }, -- no en blanco: la casilla saldría gris, como las sin descubrir del Índice
}

-- Modificadores permanentes: cada arma que sale del gacha puede llevar además UN metal y UN tamaño, tirados
-- a la vez que ella y que ya no cambian. "odds" = 1 entre N de que salgan, y es de verdad: solo la suerte de
-- armas propia del jugador (Stats.gachaLuck: renacimientos, pociones) divide N. Ni el objeto que da la tirada
-- (su suerte solo decide el arma) ni la mejora de suerte los abaratan. Cada uno multiplica el daño con la misma regla que las armas (rareza x2 = +50 % de daño,
-- ver Permanent.damage) y suma su rareza a la del arma (los N se multiplican). El metal cambia el color y el
-- material del arma; el tamaño la agranda (scale) y con ella su alcance. No cambies el orden: lo guardado usa
-- la posición. Lo nuevo va al final.
Config.Metals = {
	{ name = "Copper", odds = 10, color = Color3.fromRGB(205, 118, 72), material = Enum.Material.Metal },
	{ name = "Iron", odds = 100, color = Color3.fromRGB(150, 156, 168), material = Enum.Material.Metal },
	{ name = "Gold", odds = 1e3, color = Color3.fromRGB(255, 205, 60), material = Enum.Material.Foil },
	{ name = "Lunarite", odds = 1e4, color = Color3.fromRGB(190, 215, 255), material = Enum.Material.Glass },
	{ name = "Solarium", odds = 1e5, color = Color3.fromRGB(255, 140, 70), material = Enum.Material.Neon },
	{ name = "Etherium", odds = 1e6, color = Color3.fromRGB(130, 255, 225), material = Enum.Material.ForceField },
}
Config.Sizes = {
	{ name = "Large", odds = 1e2, scale = 1.25, color = Color3.fromRGB(120, 200, 120) },
	{ name = "Giant", odds = 1e5, scale = 1.6, color = Color3.fromRGB(90, 160, 255) },
	{ name = "Titanic", odds = 1e8, scale = 2.1, color = Color3.fromRGB(200, 100, 255) },
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
	-- Lo difícil que era un arma para el jugador ("1 entre N": la probabilidad de que una tirada suya cualquiera
	-- saque algo así de raro o más, Permanent.rollOdds con la suerte media de sus objetos, ObjectSpec.meanLuck; la
	-- cuenta está en server/Gacha) decide cuánto se celebra: "1 entre 1.000" es una de cada 1.000 tiradas.
	-- Las tiradas se enseñan en el mundo (client/RollReveal): la energía sale del objeto roto, se destapa el arma y
	-- vuela al jugador. Desde estos "1 entre N" sube de nivel el espectáculo: Normal por debajo del primero, y luego
	-- Genial (en el mundo, más cargada) y las cuatro con cinemática (client/RollCinematic): Estrella fugaz, Herrero
	-- celestial, Supernova y Supernova absoluta. Como N cuenta la suerte del jugador, la misma arma se celebra más a
	-- quien le era más difícil. Escalera pedida por el usuario.
	RevealOdds = { 100, 1000, 10000, 100000, 1000000 },
	ShowcaseOdds = 2000, -- (solo con FreeRoll) desde aquí la tirada gratis pasa a pantalla completa
	RevealTimeout = 30, -- si el cliente no avisa de que ha destapado una tirada rara, su aura y aviso salen igual a los N segundos
	AuraOdds = 500, -- desde aquí el aura se ve en el personaje (también para los demás)
	AnnounceOdds = 25000, -- con AuraOdds: desde el menor el cliente avisa de que ha destapado la tirada (el chat va por Config.Announce)
	SellValue = 0, -- gemas por vender una espada (a mano o con la venta automática). 0: las gemas salen de la parcela
	SellCoins = 30, -- monedas por vender una espada, por cada punto de su daño (Stats.sellCoins; a mano y con la venta automática). Tal cual, sin multiplicadores de monedas
}

-- Avisos en el chat de lo que le sale a alguien (pedido por el usuario el 18-10-2026: salían avisos de todo): solo
-- armas (y el récord de "Mejor tirada"); objetos, rasgos, grados, armadura, accesorios, pociones y renacer ya no van
-- al chat, solo el aviso a quien le sale. Van con el mismo "1 entre N" que decide la animación de la tirada (lo
-- difícil que era para quien la saca) y con sus mismos cortes (pedido por el usuario): Supernova = chat de su
-- servidor, Supernova absoluta = chat de todos los servidores (server/Tell, Tell.rare).
Config.Announce = {
	weapon = { Server = Config.Gacha.RevealOdds[4], Global = Config.Gacha.RevealOdds[5] },
}

-- Máquina de fusión (pedida por el usuario; server/Fusion, client/Fusion, cuentas en shared/FusionInfo): se meten Count
-- armas y sale una tirada de arma (Permanent.rollWeapon) con la suerte de la SUMA de sus rarezas totales (arma x metal
-- x tamaño) entre Divisor (pedido por el usuario: con la suma entera estaba muy rota). Así sale siempre algo de "1 entre
-- esa suerte" o más raro: cinco iguales dan una 2 veces más rara, y con suerte mucho más. Ninguna otra suerte se suma (la
-- de las armas ya va dentro de su rareza). Se pierden sus rasgos y grados.
-- Precio en gemas según esa suerte: CostScale x suerte ^ CostPower (nunca menos de MinCost). Medido con tools/equilibrio
-- (jugador tipo de 1 a 130 h): sus gemas por hora salen ~1e-6 x S ^ 1,73, siendo S la suma de las rarezas de cinco armas
-- como las de su bolsa. Pedido por el usuario que cueste de verdad: esa fusión cuesta alrededor de 20 min de gemas a
-- cualquier hora del juego (con la suma entera y 1.6e-7 eran unos 10 min; con 4.6e-6, 1 h; con 2.3e-6, 30 min, y el 18-10-2026 la pidió
-- otra vez algo más barata).
Config.Fusion = {
	Count = 5, -- armas por fusión
	Divisor = 2.5, -- la suerte es la suma de las rarezas entre esto
	CostScale = 1.5e-6,
	CostPower = 1.73,
	MinCost = 100,
	Cooldown = 1, -- segundos entre fusiones de un mismo jugador
	Reach = 40, -- studs desde la máquina en los que el servidor acepta la fusión (la ventana se abre a OpenDistance)
	OpenDistance = 12,
	Angle = 135, -- dónde está en el hub: grados alrededor del centro (entre Rasgos, 112,5°, y Grados, 157,5°) y distancia
	Distance = 70,
}

-- Objetos del inventario. "dropChance" = probabilidad de que lo suelte un objeto raro
-- (los que dan gemas) al romperse. La del Cristal de rasgo va con el calendario de tools/equilibrio (objetivo.rasgo):
-- al 5 % de antes la parcela daba ella sola varias veces las tiradas de rasgo que pide el calendario.
Config.ItemOrder = { "traitCrystal", "missionToken", "gradeCrystal", "luckClover", "smallClover" }
Config.Items = {
	traitCrystal = { name = "Trait Crystal", description = "Spent at the Traits shop in the hub: gives a random trait to the sword you choose (replacing the one it had).", dropChance = 0.007, color = Color3.fromRGB(90, 230, 255), image = "cristal_rasgo" },
	-- Moneda gratuita (f2p) que dan las misiones diarias y semanales (el usuario los llama "tickets"): con ellos se compran
	-- los pases de la Tienda (Config.Tickets). No cae de los objetos (sin dropChance) y no se comercia (noTrade: si no,
	-- con cuentas de más haciendo misiones se le pasarían todos a una sola).
	missionToken = { name = "Ticket", description = "Earned from daily and weekly missions. Use them to buy the passes in the Shop.", color = Color3.fromRGB(255, 190, 60), image = "ticket", noTrade = true },
	-- Trébol de la suerte (pedido por el usuario): se pulsa en la mochila, se elige una parcela y la suerte de armas de
	-- todos sus objetos se multiplica por Config.Clover.Luck, encima de todo lo que ya tuvieran (server/Clover). Se compra
	-- con Robux (Config.Products) o con tickets (Config.Tickets.Shop); no cae de nada. Se comercia (pedido por el usuario).
	luckClover = { name = "Lucky Clover", description = "Tap it and pick a plot: the weapon luck of all its objects is multiplied by 999.", color = Color3.fromRGB(90, 220, 130), image = "trebol" },
	-- Trébol pequeño (pedido por el usuario): x100 en un solo objeto, para recompensas (códigos y demás). No se vende.
	smallClover = { name = "Small Clover", description = "Tap it and pick an object on any plot: its weapon luck is multiplied by 99.", color = Color3.fromRGB(160, 220, 80), image = "trebol" },
	-- Lo sueltan los enemigos de las mazmorras y se saca al desmontar armadura. No cae de los objetos (sin dropChance).
	gradeCrystal = { name = "Grade Crystal", description = "Spent at the Grades shop in the hub: gives a random grade to the sword you choose. Dropped by dungeon enemies.", color = Color3.fromRGB(200, 120, 255), image = "cristal_grado" },
}

-- Armas equipadas a la vez (pedido por el usuario: con una sola, rasgos y grados solo se mejoraban en la mejor). Cada
-- una pega con su daño (arma, metal, tamaño, SU rasgo y SU grado) y el daño del jugador es la suma; la suerte y las
-- monedas de sus rasgos se multiplican entre sí (ver shared/Stats). Las armas giran alrededor del jugador y vuelan al
-- objetivo que elige con un clic (server/Combat, client/OrbitWeapons):
-- Radius = círculo alrededor del jugador dentro del que se puede elegir objetivo; Leash = studs de más que puede alejarse
-- del objetivo ya elegido antes de que las armas lo suelten; Travel = segundos que tardan en llegar al objetivo (antes no
-- pega ninguna); Chain = lo mismo al saltar solas al siguiente enemigo de una mazmorra.
-- MaxSlots = huecos con la ventaja "extraSlots" de los pases (Stats.loadoutSlots): el tope al revisar lo guardado.
-- FarmRadius = el radio con el Auto de la parcela encendido (pase "auto"): cubre la parcela entera desde cualquier
-- punto de ella, así que las armas llegan a todo sin que el jugador se mueva (Stats.reach); 200 = la diagonal de la
-- parcela más grande (Config.Plot.MaxSize).
Config.Loadout = { Slots = 4, MaxSlots = 8, Radius = 26, FarmRadius = 200, Leash = 8, Travel = 0.25, Chain = 0.15 }

-- Bolsa de oro (server/GoldBag, cuentas en shared/BagInfo): detrás de cada parcela hay un saco al que pegan solas las
-- armas que su dueño deposita (aparte de las equipadas), también mientras está desconectado y sin tope de tiempo.
-- Slots = armas que caben. HitTime = segundos entre golpes de cada arma depositada (igual para todos los tipos).
-- Lo que saca cada golpe lo decidió el usuario (11 oct 2026) y está SIN EQUILIBRAR a propósito: una moneda por cada
-- punto de daño (1 de daño = 1 moneda, 10M de daño = 10M monedas). La cuenta es: con Damage de daño, Coins monedas, y
-- cada vez que el daño se dobla, Double veces más; con 1, 1 y 2 sale daño = monedas (antes fue 100, 50 y 1,5: 200 de
-- daño daban 75). No pasa por los multiplicadores de monedas. First = monedas de la primera bolsa; cada una lleva Growth veces las de
-- la anterior, sin fin. MinAway = segundos fuera a partir de los que se avisa de lo ganado al volver.
Config.GoldBag = {
	Slots = 4,
	MaxSlots = 8, -- huecos con la ventaja "extraSlots" de los pases (Stats.bagSlots): el tope al revisar lo guardado
	HitTime = 1,
	Coins = 0.002, -- con Damage y Double: monedas de un golpe de la bolsa (BagInfo.coins); ajustados para que la bolsa dé más o menos lo mismo que los destructibles toda la partida (pedido por el usuario; antes, 1 moneda por punto de daño, daba casi todo)
	Damage = 1,
	Double = 2.4, -- más de 2: lo que saca crece algo más deprisa que el daño, como los premios de los objetos (que suben más que su vida)
	First = 1000,
	Growth = 4,
	StageBoost = 1.1, -- cada bolsa vaciada multiplica por esto lo que saca cada golpe (BagInfo.boost), pedido por el usuario (con x2 la bolsa se comía el juego)
	MinAway = 60,
}

-- Rasgos de espada (tienda de Rasgos del hub). Se tiran con un Cristal de rasgo; "chance" = peso
-- de salir (el % se calcula sobre el total, sin suerte). Mientras la espada está equipada
-- multiplican su daño (solo el de esa arma) y las monedas y la suerte del jugador; lo que no se pone vale 1.
-- El daño va alto y la suerte y las monedas bajas (decidido por el usuario): con varias armas equipadas el daño se
-- suma, pero la suerte y las monedas de sus rasgos se multiplican (cuatro Paradojas = x16).
-- "icon" = coins, damage, luck o all (los que lo suben todo salen con arcoíris).
-- No cambies el orden: el guardado usa la posición en la lista; lo nuevo, al final.
-- "noStop = true": no sale en "Parar con" de la tienda (pedido por el usuario: solo se para en los III o mejores).
Config.Traits = {
	{ name = "Coins I", coins = 1.05, chance = 24.76, noStop = true, icon = "coins", color = Color3.fromRGB(110, 220, 120) },
	{ name = "Damage I", damage = 1.2, chance = 24.76, noStop = true, icon = "damage", color = Color3.fromRGB(90, 210, 230) },
	{ name = "Luck I", luck = 1.05, chance = 24.76, noStop = true, icon = "luck", color = Color3.fromRGB(150, 230, 90) },
	{ name = "Coins II", coins = 1.1, chance = 6.7, noStop = true, icon = "coins", color = Color3.fromRGB(60, 200, 90) },
	{ name = "Damage II", damage = 1.5, chance = 6.7, noStop = true, icon = "damage", color = Color3.fromRGB(50, 170, 240) },
	{ name = "Luck II", luck = 1.1, chance = 6.7, noStop = true, icon = "luck", color = Color3.fromRGB(120, 210, 50) },
	{ name = "Coins III", coins = 1.2, chance = 1.5, icon = "coins", color = Color3.fromRGB(30, 180, 70) },
	{ name = "Damage III", damage = 2, chance = 1.5, icon = "damage", color = Color3.fromRGB(40, 120, 255) },
	{ name = "Luck III", luck = 1.2, chance = 1.5, icon = "luck", color = Color3.fromRGB(90, 190, 30) },
	{ name = "Samurai", coins = 1.25, damage = 3, luck = 1.25, chance = 0.9, pity = true, icon = "all", image = "rasgo_samurai", color = Color3.fromRGB(255, 120, 200), rainbow = true },
	{ name = "Shogun", coins = 1.35, damage = 5, luck = 1.35, chance = 0.17, icon = "all", image = "rasgo_shogun", color = Color3.fromRGB(120, 230, 160), rainbow = true },
	{ name = "Monarch", coins = 1.5, damage = 8, luck = 1.5, chance = 0.039, icon = "all", image = "rasgo_monarca", color = Color3.fromRGB(180, 120, 255), rainbow = true },
	{ name = "Transcendent", coins = 1.65, damage = 15, luck = 1.65, chance = 0.01, icon = "all", image = "rasgo_trascendente", color = Color3.fromRGB(255, 80, 60) },
	{ name = "Timeless", coins = 1.8, damage = 30, luck = 1.8, chance = 0.0045, icon = "all", image = "rasgo_eterno", color = Color3.fromRGB(220, 40, 40) },
	{ name = "Paradox", coins = 2, damage = 57.5, luck = 2, chance = 0.0019, icon = "all", image = "rasgo_paradoja", color = Color3.fromRGB(235, 235, 245) },
}

-- Grados de espada (tienda de Grados del hub). Se tiran con Cristales de grado (GradeCost cada vez) y
-- multiplican el daño de esa arma mientras está equipada (decidido por el usuario: antes daban monedas). "chance"
-- como en los rasgos.
-- No cambies el orden: el guardado usa la posición en la lista.
Config.Grades = {
	{ name = "D", damage = 1.1, chance = 50.21, color = Color3.fromRGB(200, 200, 205) },
	{ name = "C", damage = 1.25, chance = 25, color = Color3.fromRGB(80, 210, 80) },
	{ name = "B", damage = 1.5, chance = 12, color = Color3.fromRGB(60, 140, 255) },
	{ name = "A", damage = 2, chance = 7.4, color = Color3.fromRGB(160, 80, 255) },
	{ name = "A+", damage = 3, chance = 3.8, color = Color3.fromRGB(255, 190, 40) },
	{ name = "S", damage = 5, chance = 1.3, color = Color3.fromRGB(240, 50, 60) },
	{ name = "S+", damage = 8, chance = 0.2, color = Color3.fromRGB(50, 80, 255) },
	{ name = "Z", damage = 12, chance = 0.063, color = Color3.fromRGB(40, 210, 190) },
	{ name = "Z+", damage = 20, chance = 0.019, color = Color3.fromRGB(200, 90, 255), rainbow = true },
	-- "tones" (con rainbow): en vez del arcoíris, un degradado de esos dos colores que gira (Modifiers.tones). Pedido por
	-- el usuario: el ∞ en blanco y negro (probó el X en verde y lo devolvió al arcoíris).
	{ name = "X", damage = 40, chance = 0.0057, color = Color3.fromRGB(230, 40, 40), rainbow = true },
	{ name = "∞", damage = 100, chance = 0.0016, color = Color3.fromRGB(240, 240, 245), rainbow = true, tones = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 30, 36) } },
}
-- Pity de rasgos y grados (Modifiers.rollWithPity): solo lo tienen los resultados de "1 entre MinOdds" o más raros
-- (pedido por el usuario: de S+ para arriba en grados, que en rasgos es de Shogun para arriba). Los fáciles no: su
-- garantía se comía tiradas en las que podía haber salido algo mejor. Una entrada con `pity = true` lo tiene aunque
-- sea más fácil (Samurái, pedido por el usuario).
Config.ModifierPity = { MinOdds = 400 }
Config.GradeCost = 1 -- Cristales de grado por tirada de grado
Config.ModifierCooldown = 0.3 -- segundos mínimos entre tiradas de rasgo o grado

-- Nivel de arma (pedido por el usuario): cada copia sube de nivel pagando gemas, hasta MaxLevel. Cada nivel multiplica
-- el daño de esa arma por PerLevel (x7,2 en el 100). El nivel va con la copia: se guarda, se comercia con ella y se
-- pierde al venderla o fusionarla; renacer no lo quita. Precio del nivel n -> n+1 (shared/WeaponLevel):
-- max(MinCost, CostBase * rareza total ^ RarityPower) * Growth ^ n. RarityPower sale de lo que gana de gemas el jugador
-- tipo frente a lo raras que son sus armas (crecen como rareza ^ 1,5): así subir un arma cuesta parecido a cualquier
-- hora. CostBase medido con tools/equilibrio/informe.luau sin regenerar lo demás (docs/sistemas/nivel-armas.md). El jugador tipo de tools/equilibrio gasta en niveles la parte `gemasNiveles` de sus gemas (objetivo.luau).
Config.WeaponLevel = { MaxLevel = 100, PerLevel = 1.02, CostBase = 1e-4, RarityPower = 1.5, Growth = 1.06, MinCost = 100 }

-- Renacimiento: solo cuesta monedas y no quita nada (ni monedas ganadas, ni espadas, ni mejoras). Cada uno
-- multiplica para siempre (por cada renacimiento, ese número elevado a los renacimientos que lleve).
-- "costs" = precio de cada renacimiento. NÚMEROS GENERADOS por tools/equilibrio/generar.luau para que caigan hacia las
-- 2, 6,5, 20, 55 y 120 h de juego (objetivo.luau): no los retoques a mano.
Config.Rebirth = { max = 5, costs = { 5e7, 1.2e13, 6.4e17, 1.8e22, 3.7e27 }, coins = 2, damage = 3, luck = 1.5, gachaLuck = 1.5 }

-- Artefactos (equipo). Pueden caer al romper cualquier objeto ("rarity" = 1 entre N, la
-- suerte de destructibles multiplica la probabilidad). "stat": damage, luck (suerte de destructibles),
-- coins o gems. No cambies el orden: el guardado usa la posición en la lista.
-- Los "mult" van con presupuesto (los de suerte, x1,5 / x3 / x6: sumados a la mejora, el rasgo, la armadura y renacer
-- no deben pasar de la rareza del objeto más raro; antes llegaban a x1000 y x1e6 y lo rompían todo). Las "rarity" son
-- NÚMEROS GENERADOS por tools/equilibrio para que cada uno caiga a su hora (de los 5 min a las 155 h): no los retoques.
Config.GearSlots = 3
Config.ArtifactCopies = 1 -- copias de un mismo accesorio que se pueden tener (pedido por el usuario: uno de cada y sin comerciar; al cargar, lo que sobre se quita)
Config.Artifacts = {
	{ name = "Copper Amulet", stat = "coins", mult = 1.5, rarity = 830, color = Color3.fromRGB(200, 120, 70), image = "acc_amuleto_cobre" },
	{ name = "Sharp Ring", stat = "damage", mult = 2, rarity = 9100, color = Color3.fromRGB(200, 205, 210), image = "acc_anillo_afilado" },
	{ name = "Clover", stat = "luck", mult = 1.5, rarity = 270000, color = Color3.fromRGB(90, 200, 100), image = "acc_trebol" },
	{ name = "Gem Pendant", stat = "gems", mult = 2, rarity = 1.7e7, color = Color3.fromRGB(190, 110, 255), image = "acc_colgante_gemas" },
	{ name = "Gauntlet", stat = "damage", mult = 4, rarity = 4e10, color = Color3.fromRGB(120, 160, 200), image = "acc_guantelete" },
	{ name = "Golden Crown", stat = "coins", mult = 4, rarity = 8.7e13, color = Color3.fromRGB(255, 200, 50), image = "acc_corona_dorada" },
	{ name = "Eye of Fortune", stat = "luck", mult = 3, rarity = 2.4e17, color = Color3.fromRGB(60, 255, 170), image = "acc_ojo_fortuna" },
	{ name = "Stellar Heart", stat = "damage", mult = 10, rarity = 4.1e21, color = Color3.fromRGB(255, 240, 150), image = "acc_corazon_estelar" },
	{ name = "Void Relic", stat = "luck", mult = 6, rarity = 6.1e24, color = Color3.fromRGB(130, 50, 255), image = "acc_reliquia_vacio" },
	{ name = "Infinity Core", stat = "damage", mult = 25, rarity = 1.9e27, color = Color3.fromRGB(255, 40, 60), image = "acc_nucleo_infinito" },
}
Config.StatNames = { damage = "damage", luck = "luck", coins = "coins", gems = "gems" }

-- Decorado del mapa: "japan" (bosque japonés de atardecer, server/SceneryJapan) o "tropical" (la isla de siempre, server/Scenery).
Config.Theme = "japan"

-- Ciclo de día y noche de la superficie (client/DayCycle): `Length` = segundos reales de un día entero, `DayShare` =
-- parte de la vuelta que es de día (de 6 a 18 h). Es el mismo para todos (sigue la hora del servidor).
Config.DayCycle = { Length = 720, DayShare = 2 / 3 }

Config.PlotLighting = { Height = 18, Offset = 0.18, Brightness = 1, Range = 55 }
Config.Water = { Depth = 6, Transparency = 0.35, WaveHeight = 0.12, WaveSpeed = 0.9 }

-- CLIMA (server/Weather y client/Weather). Cada `Interval` segundos empieza un evento de clima, el mismo en todos los
-- servidores (sale de la hora), que dura `Duration` (o el "duration" del evento); el resto del tramo está despejado.
-- Se tira del más raro al más común de `Order` ("rarity" = 1 entre N por tramo; el primero es el de relleno), así que
-- lo que enseñan los carteles es la probabilidad real (WeatherInfo.chance). Mientras dura, todos los jugadores tienen
-- "luck" (suerte de destructibles: entra por Stats.spawnLuck, como la poción de cajas) y, los más raros, "weaponLuck"
-- (suerte de armas: Stats.gachaLuck). "tier" = posición en Config.RarityTiers (nombre y color de su rareza en los
-- carteles) y "color" el del evento. Lo que se ve de cada uno (luz, cielo, partículas) está en client/WeatherDefs.
-- Un clima nuevo = una entrada aquí, su id en `Order` (por rareza) y su aspecto en WeatherDefs.
-- Eventos de admin (server/AdminEvents, panel "Eventos" del menú de admin): un administrador multiplica un stat para
-- todos durante un rato, en su servidor o en todos. El multiplicador no tiene tope (pedido por el usuario: lo quiere
-- para probar y para sus eventos); MaxMinutes = lo que puede durar una orden; MaxMessage = letras del mensaje grande. Cada stat entra en un solo sitio (Stats.boost).
Config.AdminEvents = {
	MaxMinutes = 180,
	MaxMessage = 120,
	BannerTime = 8, -- segundos que se queda en pantalla el mensaje grande
	Order = { "luck", "weaponLuck", "coins", "damage", "traitLuck", "gradeLuck" },
	Stats = {
		luck = { name = "Box luck", color = Color3.fromRGB(126, 224, 122) },
		weaponLuck = { name = "Weapon luck", color = Color3.fromRGB(201, 160, 255) },
		coins = { name = "Coins", color = Color3.fromRGB(255, 205, 70) },
		damage = { name = "Damage", color = Color3.fromRGB(255, 110, 110) },
		traitLuck = { name = "Trait luck", color = Color3.fromRGB(110, 200, 255) },
		gradeLuck = { name = "Grade luck", color = Color3.fromRGB(255, 150, 60) },
	},
}

Config.Weather = {
	Interval = 1800,
	Duration = 600,
	Fade = 8, -- segundos que tardan la luz y las partículas en entrar y en irse
	LowTime = 60, -- el reloj del HUD se pone rojo y late cuando quedan menos segundos
	Warning = 90, -- segundos antes de un clima en que todos ven el aviso "se acerca un clima" con su cuenta; antes, la cuenta solo la ven los administradores
	Order = { "rain", "petals", "fog", "snow", "storm", "goldenRain", "volcanic", "aurora", "bloodMoon", "eclipse", "cosmic", "starfall" },
	Events = {
		rain = { name = "Rain", desc = "It rains over the whole island.", rarity = 1, tier = 1, luck = 2, color = Color3.fromRGB(90, 150, 235) },
		petals = { name = "Sakura Gale", desc = "The wind tears the petals off every cherry tree.", rarity = 3, tier = 1, luck = 2, color = Color3.fromRGB(255, 140, 190) },
		fog = { name = "Fog", desc = "A thick mist swallows the forest.", rarity = 4, tier = 1, luck = 2.5, color = Color3.fromRGB(190, 205, 225) },
		snow = { name = "Snowfall", desc = "Snow falls silently on the rooftops.", rarity = 6, tier = 2, luck = 3, color = Color3.fromRGB(160, 225, 255) },
		storm = { name = "Thunderstorm", desc = "It pours and lightning strikes all over the map.", rarity = 10, tier = 2, luck = 4, color = Color3.fromRGB(255, 225, 90) },
		goldenRain = { name = "Golden Rain", desc = "Rain in the sunshine: golden drops and a rainbow.", rarity = 16, tier = 3, luck = 6, color = Color3.fromRGB(255, 200, 60) },
		volcanic = { name = "Fuji Eruption", desc = "Mount Fuji awakens: red sky, ash and embers.", rarity = 30, tier = 3, luck = 10, color = Color3.fromRGB(255, 110, 50) },
		aurora = { name = "Aurora", desc = "Ribbons of light dance in the night sky.", rarity = 50, tier = 4, luck = 15, color = Color3.fromRGB(90, 240, 170) },
		bloodMoon = { name = "Blood Moon", desc = "A huge moon paints the night red.", rarity = 80, tier = 4, luck = 20, color = Color3.fromRGB(230, 50, 60) },
		eclipse = { name = "Eclipse", desc = "The moon covers the sun: night falls and only the corona remains.", rarity = 150, tier = 5, luck = 30, weaponLuck = 1.5, color = Color3.fromRGB(150, 130, 235) },
		cosmic = { name = "Cosmic Storm", desc = "The sky splits open and you can see outer space.", rarity = 300, tier = 6, luck = 50, weaponLuck = 2, color = Color3.fromRGB(190, 90, 255) },
		starfall = { name = "Starfall", desc = "The whole sky lights up and stars fall on the island.", rarity = 500, tier = 7, luck = 100, weaponLuck = 3, color = Color3.fromRGB(130, 225, 255) },
	},
}

-- Mapa: un hub circular en el centro y las parcelas en círculo a su alrededor.
Config.Plot = {
	Count = 8,
	Size = 100, -- lado de la parcela (múltiplo de 20: la valla va en tramos de 10 con la entrada en el centro)
	RingRadius = 300, -- distancia del centro del mapa al centro de cada parcela (era 250: con las parcelas de 140 se pisaban con el decorado)
	HubRadius = 90,
	LimitRadius = 495, -- radio del muro invisible que cierra el mapa (server/MapBounds); la orilla de la isla queda a 452
	FloorHeight = 0.4,
	SpawnInterval = 1.5, -- segundos entre apariciones de objetos en una parcela (sin mejoras: la rama "Velocidad de aparición" lo baja)
	MinSpawnInterval = 0.3, -- nunca aparecen más rápido que esto
	-- La parcela crece con los renacimientos (Stats.plotSize, pedido por el usuario): GrowStep studs por lado al llegar a
	-- cada número de GrowAt, sin pasar de MaxSize. Crece alrededor de su centro: con 140 las esquinas de delante de dos
	-- parcelas vecinas quedan a 46 studs, con sitio para el estanque y el santuario de entre medias. El decorado deja
	-- libre MaxSize.
	GrowAt = { 1, 3 },
	GrowStep = 20,
	MaxSize = 140,
}

-- Aspecto de la parcela con cada renacimiento (server/PlotLooks; pedido por el usuario: cambia poco a poco, y habrá 20
-- o más). La entrada n es la del renacimiento n: "floor" = los dos tonos de la tarima (mapa japonés) y "add" = lo que
-- se pone desde ese renacimiento y se queda en los siguientes (las piezas de PlotLooks.BUILDERS). Con más renacimientos
-- que entradas se queda el de la última; para los siguientes, añadir entradas al final.
Config.PlotLooks = {
	{ floor = { Color3.fromRGB(218, 158, 100), Color3.fromRGB(198, 136, 86) }, add = { "border" } },
	{ floor = { Color3.fromRGB(214, 150, 94), Color3.fromRGB(192, 128, 80) }, add = { "banners" } },
	{ floor = { Color3.fromRGB(206, 140, 88), Color3.fromRGB(184, 118, 74) }, add = { "garden" } },
	{ floor = { Color3.fromRGB(196, 128, 82), Color3.fromRGB(174, 108, 70) }, add = { "gold" } },
	{ floor = { Color3.fromRGB(186, 116, 78), Color3.fromRGB(164, 98, 66) }, add = { "sakura" } },
}

-- Ordenados de común a raro. "rarity" = 1 entre N de que salga en cada aparición;
-- la suerte del jugador multiplica esa probabilidad. El primero es el de relleno.
-- "gems" = gemas que suelta (solo los raros). Todos dan tiradas de arma al romperse (Config.ObjectRolls, debajo,
-- que explica también lo que puede llevar de más un objeto especial: luck, rolls, minScale...).
-- "hp" y "reward" son NÚMEROS GENERADOS por tools/equilibrio/generar.luau (no los retoques a mano): el premio es
-- 2 * rareza ^ 0,75 (con una potencia de 1 o más, un objeto raro pagaba de golpe varios niveles de suerte) y la vida,
-- lo que pega el jugador tipo cuando ese tipo empieza a salirle 1 de cada 10 veces, por 1 a 3 golpes.
Config.Destructibles = {
	{ name = "Crate", rarity = 1, hp = 2, reward = 2, gems = 0, size = Vector3.new(3, 3, 3), color = Color3.fromRGB(170, 125, 75), material = Enum.Material.WoodPlanks },
	{ name = "Barrel", rarity = 4, hp = 2.4, reward = 5.7, gems = 0, size = Vector3.new(3, 4.5, 3), color = Color3.fromRGB(120, 75, 45), material = Enum.Material.Wood },
	{ name = "Rock", rarity = 20, hp = 46, reward = 19, gems = 1, size = Vector3.new(5, 4, 5), color = Color3.fromRGB(110, 110, 115), material = Enum.Material.Slate },
	{ name = "Pillar", rarity = 120, hp = 540, reward = 73, gems = 8, size = Vector3.new(4, 12, 4), color = Color3.fromRGB(225, 220, 205), material = Enum.Material.Marble },
	{ name = "Crystal", rarity = 800, hp = 3400, reward = 300, gems = 60, size = Vector3.new(7, 11, 7), color = Color3.fromRGB(110, 220, 255), material = Enum.Material.Glass },
	{ name = "Weapon Rock", rarity = 2000, hp = 7900, reward = 0, gems = 0, luck = 3, rolls = 1, size = Vector3.new(6, 6, 6), color = Color3.fromRGB(255, 120, 40), material = Enum.Material.Neon },
	{ name = "Monolith", rarity = 5000, hp = 29000, reward = 1200, gems = 500, size = Vector3.new(11, 20, 11), color = Color3.fromRGB(45, 40, 60), material = Enum.Material.Basalt },
	{ name = "Obelisk", rarity = 5e4, hp = 61000, reward = 6700, gems = 4000, size = Vector3.new(6, 22, 6), color = Color3.fromRGB(230, 190, 70), material = Enum.Material.Foil },
	{ name = "Meteorite", rarity = 1e6, hp = 940000, reward = 63000, gems = 5e4, size = Vector3.new(12, 10, 12), color = Color3.fromRGB(200, 70, 30), material = Enum.Material.CrackedLava },
	{ name = "Core", rarity = 5e7, hp = 3.8e7, reward = 1.2e6, gems = 1.5e6, size = Vector3.new(9, 9, 9), color = Color3.fromRGB(60, 255, 140), material = Enum.Material.Neon },
	{ name = "Star", rarity = 5e9, hp = 1.3e9, reward = 3.8e7, gems = 1e8, size = Vector3.new(12, 12, 12), color = Color3.fromRGB(255, 240, 150), material = Enum.Material.Neon },
	{ name = "Black Hole", rarity = 1e12, hp = 2.5e10, reward = 2e9, gems = 1e10, size = Vector3.new(13, 13, 13), color = Color3.fromRGB(5, 5, 10), material = Enum.Material.Glass, sound = "energy" },
	{ name = "Void Shard", rarity = 1e15, hp = 2.6e12, reward = 3.6e11, gems = 5e12, size = Vector3.new(8, 24, 8), color = Color3.fromRGB(130, 50, 255), material = Enum.Material.ForceField },
	{ name = "Singularity", rarity = 1e18, hp = 1.1e14, reward = 6.3e13, gems = 3e15, size = Vector3.new(10, 10, 10), color = Color3.fromRGB(255, 60, 200), material = Enum.Material.Neon },
	{ name = "Origin", rarity = 1e21, hp = 2.4e16, reward = 1.1e16, gems = 1e18, size = Vector3.new(14, 18, 14), color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon },
	{ name = "Infinity", rarity = 1e24, hp = 1.8e18, reward = 2e18, gems = 5e20, size = Vector3.new(14, 26, 14), color = Color3.fromRGB(255, 40, 60), material = Enum.Material.Neon },
	-- Endgame (pedido por el usuario, 17-10-2026): tres objetos para los niveles 51 a 60 de la suerte. Vida, premio y
	-- gemas puestos A OJO, sin tools/equilibrio (el usuario no quiso calendario): mucho más duros que el Infinito. La vida, subida
	-- para el mejor jugador (8,8e18 por andanada de sus 4 armas): el Sol negro le dura unos 2,5 min, la Galaxia 20 y el Génesis 2 h
	-- con las armas de ahora (pedido por el usuario: "que sea un cambio de verdad"); con las que sueltan bajan unas 10 veces.
	-- "luck": x15, x30 y x24 a su suerte de armas (pedido por el usuario: si cuestan tanto, que valgan la pena; subida el
	-- 18-10-2026 desde x5, x10 y x20, que se quedaban cortos; el Génesis, el más raro, casi no sube: x24 es lo más que dejan las pruebas "el consumible de suerte no regala el arma más rara"), aunque
	-- con eso el Colmillo astral a secas se vuelve alcanzable al final (decidido por el usuario el 17-10-2026).
	-- "accent" = color de su luz (Glow y Halo del modelo, y la de ObjectAmbient), distinto del cuerpo.
	{ name = "Black Sun", rarity = 1e25, hp = 3e21, luck = 15, reward = 1.1e19, gems = 1e22, size = Vector3.new(13, 13, 13), color = Color3.fromRGB(42, 32, 58), accent = Color3.fromRGB(255, 170, 70), material = Enum.Material.Slate, sound = "energy" },
	{ name = "Galaxy", rarity = 3e26, hp = 2.5e22, luck = 30, reward = 1.5e20, gems = 3e23, size = Vector3.new(16, 10, 16), color = Color3.fromRGB(90, 70, 200), accent = Color3.fromRGB(255, 140, 220), material = Enum.Material.Neon, sound = "energy" },
	{ name = "Genesis", rarity = 1e28, hp = 1.5e23, luck = 24, reward = 2e21, gems = 1e25, size = Vector3.new(14, 24, 14), color = Color3.fromRGB(240, 235, 255), accent = Color3.fromRGB(120, 230, 255), material = Enum.Material.Marble },
}

-- Gemas de los objetos de la parcela: cada objeto con "gems" las suelta con probabilidad "gemChance" (1 si no
-- lo pone) y la cantidad es gems * azar entre min y max (con el multiplicador de gemas del jugador).
Config.GemDrop = { min = 0.7, max = 1.3 }

-- ARMAS DESDE LOS OBJETOS. Cada objeto que aparece en una parcela lleva, además de su tipo (la lista de arriba, que
-- sale según la suerte de parcela), una RAREZA y un TAMAÑO propios, tirados al aparecer. Al romperlo da tiradas de
-- arma (server/Gacha) con la SUERTE DEL OBJETO, que sale de las tres cosas que lo hacen especial:
--   suerte del objeto = suerte del tipo * "luck" de su rareza * escala ^ SizeLuckPower      (como mucho MaxLuck)
--   suerte del tipo = lo raro que es de ver ("rarity" de Config.Destructibles) ^ TypeLuckPower
-- (por el "luck" propio de los objetos especiales: la Roca de armas da el triple de lo que le toca por su rareza).
-- Una Caja común de tamaño normal da x1:
-- el "1 entre N" de cada arma es su probabilidad con ella. La suerte de armas no se compra: sale del objeto que se
-- rompe, y la mejora "Suerte de destructibles" solo trae tipos más raros (decidido por el usuario: esa mejora es
-- solo para los destructibles). Lo único que multiplica además es Stats.gachaLuck (renacimientos y, cuando existan,
-- pociones). La suerte solo multiplica probabilidades, como toda la del juego: un objeto enorme no garantiza ningún
-- arma. Y se aplica UNA vez, al arma: el metal y el tamaño no dependen del objeto que la da (ver Config.Metals),
-- así que un objeto de xN da armas de alrededor de "1 entre N".
-- Tiradas = "rolls" de la rareza + "rolls" del tamaño + "rolls" del tipo; la parte decimal es la probabilidad de
-- una más (1.5 = una, y otra la mitad de las veces), con el tope MaxRolls.
-- El tamaño multiplica también la vida (escala ^ SizeHpPower) y las monedas y gemas (escala ^ SizeRewardPower).
-- OBJETOS ESPECIALES: un tipo de Config.Destructibles puede llevar además "luck" (su suerte), "rolls" (tiradas de
-- más), "minScale" y "maxScale" (límites de su escala), "rarityLuck" y "sizeLuck" (multiplican la probabilidad de
-- sus rarezas y de sus tamaños grandes) y "minRarity" (rareza mínima, posición en ObjectRarities). Con eso se hace
-- un objeto nuevo sin tocar código. Las cuentas están en shared/ObjectSpec.
Config.ObjectRolls = {
	-- Suerte del tipo = lo raro que es ^ TypeLuckPower: Barril (1 entre 4) x1.8, Roca (20) x3.5, Pilar (120) x7.4,
	-- Monolito (5000) x35, Meteorito (1e6) x330, Agujero negro (1e12) x110K... Infinito (1e24) x11B.
	-- NÚMERO GENERADO por tools/equilibrio/generar.luau: es el que hace que el arma más rara de Config.Swords salga de
	-- media 1 vez cada 500 h (objetivo.horasArmaTope, decidido por el usuario) con TODA la suerte al máximo. Con 2/3,
	-- que es lo que hubo, un Infinito daba x1e16 y el Colmillo astral salía cada 12 s.
	TypeLuckPower = 0.423,
	SizeLuckPower = 4, -- el tamaño cuenta de verdad: al 70 % x0.24, al 115 % x1.75, al 150 % x5, al 200 % x16, al 250 % x39
	SizeHpPower = 2,
	SizeRewardPower = 2,
	MaxLuck = 1e16, -- tope de seguridad de la suerte de un objeto (un Infinito mítico y colosal no llega a x1e14)
	MaxRolls = 5, -- tope de tiradas de arma de un solo objeto
	MaxWidth = 30, -- studs: ningún objeto se agranda más que esto de ancho...
	MaxHeight = 56, -- ...ni de alto (los tipos más grandes llegan a menos escala que los pequeños)
	-- Lo que se VE (ObjectSpec.visualScale, pedido por el usuario: con todo mejorado salían tan grandes que cabían muy
	-- pocos): por encima de 1 crece VisualGrowth veces lo que la escala que cuenta (un Colosal x2,5 se ve x1,6) y la
	-- pieza no pasa de VisualMaxWidth x VisualMaxHeight. La suerte, la vida y el premio siguen con la escala de verdad.
	VisualGrowth = 0.4,
	VisualMaxWidth = 18,
	VisualMaxHeight = 32,
	NoticeOdds = 250, -- aviso al dueño cuando le aparece un objeto de "1 entre N" o más (rareza por tamaño)
}

-- Rarezas de los objetos, de peor a mejor. Son suyas (no son las de las espadas ni las de la armadura), pero con
-- los mismos nombres y colores para que se entiendan de un vistazo. "odds" = 1 entre N de que un objeto salga así
-- (se prueba de la más rara a la más común; Stats.objectLuck multiplica la probabilidad, no la suerte de parcela),
-- "luck" = multiplica la suerte de sus tiradas de arma, "rolls" = tiradas que da, "hp" y "reward" = multiplican su
-- vida y sus monedas y gemas, "sizeLuck" = multiplica la probabilidad de que además salga grande.
Config.ObjectRarities = {
	{ name = "Common", odds = 1, luck = 1, rolls = 1, hp = 1, reward = 1, sizeLuck = 1, color = Config.RarityTiers[1].color },
	{ name = "Uncommon", odds = 4, luck = 2, rolls = 1, hp = 1.5, reward = 2, sizeLuck = 1, color = Config.RarityTiers[2].color },
	{ name = "Rare", odds = 15, luck = 4, rolls = 1, hp = 2.5, reward = 4, sizeLuck = 1.2, color = Config.RarityTiers[3].color },
	{ name = "Epic", odds = 60, luck = 9, rolls = 1.5, hp = 4, reward = 8, sizeLuck = 1.5, color = Config.RarityTiers[4].color },
	{ name = "Legendary", odds = 300, luck = 22, rolls = 2, hp = 7, reward = 20, sizeLuck = 2, color = Config.RarityTiers[5].color },
	{ name = "Mythic", odds = 2000, luck = 60, rolls = 3, hp = 12, reward = 60, sizeLuck = 3, color = Config.RarityTiers[6].color },
}

-- Tamaños de los objetos: el primero es el normal y los demás salen 1 entre "odds" (como las rarezas). La escala
-- exacta se tira al azar entre "min" y "max" (1 = el tamaño de Config.Destructibles) y es la que cuenta para la
-- suerte, la vida y el premio; "rolls" = tiradas de arma de más.
Config.ObjectSizes = {
	{ name = "Normal", odds = 1, min = 0.9, max = 1.15, rolls = 0 },
	{ name = "Small", odds = 4, min = 0.7, max = 0.9, rolls = 0 },
	{ name = "Large", odds = 5, min = 1.15, max = 1.5, rolls = 0 },
	{ name = "Huge", odds = 25, min = 1.5, max = 2, rolls = 0.5 },
	{ name = "Colossal", odds = 150, min = 2, max = 2.5, rolls = 1 },
}

-- Mejoras. Valor: "add" = base + perLevel * nivel; "mul" = base * perLevel ^ nivel (exponencial).
-- Precio: "costs" = el de cada nivel (o cost * growth ^ nivel si no la trae), en monedas, en gemas (currency = "gems") o en monedas de bolsa (currency = "bag").
-- Los "costs" son NÚMEROS GENERADOS por tools/equilibrio/generar.luau a partir del calendario de progreso
-- (tools/equilibrio/objetivo.luau: a qué hora de juego se compra cada nivel). No los retoques a mano: se pisan.
-- Los cálculos están en shared/Upgrades.
-- En el árbol de mejoras cada mejora es una rama y cada nivel un nodo: "short" es el nombre
-- del nodo, "icon" su dibujo (box, orb, sword, gem) y "color" el de la rama; "desc" (opcional) explica lo que hace.
-- No hay mejora de suerte de armas (la hubo, "gachaLuck", pagada con gemas): esa suerte sale de los objetos.
-- Tampoco de velocidad de golpe (la hubo, "speed": el usuario la mandó quitar): el golpe va siempre al ritmo de su arma.
Config.UpgradeOrder = { "capacity", "luck", "rollSpeed", "fortune", "bagBoost" }
Config.Upgrades = {
	-- Pocos niveles y cada uno da mucho (pedido por el usuario: el árbol era demasiado largo).
	capacity = { name = "More Objects", short = "Objects", icon = "box", color = Color3.fromRGB(235, 150, 60), mode = "add", base = 8, perLevel = 4, maxLevel = 8, costs = { 27, 380, 3000, 17000, 86000, 1.7e6, 1e7, 5.5e7 }, display = "%d" },
	-- Suerte de destructibles (misma clave de siempre, "luck": lo comprado se conserva). x2,5 por nivel, x79Qi al máximo:
	-- lo que falta hasta la rareza del objeto más raro (1e24) lo ponen renacer, el rasgo, los accesorios y la armadura
	-- (con x3 por nivel la mejora sola ya los agotaba y todo lo demás sobraba). Multiplica la probabilidad
	-- de los tipos raros de Config.Destructibles, que son los que dan más monedas, gemas y suerte de armas.
	-- Niveles 51 a 60 (endgame, pedido por el usuario el 17-10-2026): precios A OJO (pedido por el usuario: el primero cerca del 50, para que no se queden fuera los demás, y
	-- saltos cada vez más gordos, de x10 a x1250 por nivel) y traen el Sol negro, la Galaxia y el Génesis. Si se regenera con tools/equilibrio se pisan.
	luck = { name = "Destructible Luck", short = "Luck", desc = "Raises the chance of finding rare destructibles, which give better weapons.", icon = "luck", color = Color3.fromRGB(70, 200, 90), mode = "mul", base = 1, perLevel = 2.5, maxLevel = 60, costs = { 22, 170, 1200, 6200, 17000, 89000, 1e6, 7.3e6, 1.8e7, 1.6e8, 4.3e9, 1.5e10, 3.1e10, 6.7e10, 1.1e11, 4.7e11, 2.3e12, 5.4e12, 1.5e13, 1.3e14, 9.9e14, 4.9e15, 2.5e16, 9e16, 3.2e17, 2e18, 1.9e19, 7.8e19, 1.4e20, 2.4e20, 5.6e20, 1.3e21, 3.3e21, 8e21, 1.8e22, 1.5e23, 1.5e24, 5e24, 1.9e25, 6.7e25, 1.1e26, 1.8e26, 6.5e26, 1.8e27, 4.4e27, 3.9e28, 2.8e29, 6.3e29, 1.5e30, 2.9e30, 3e31, 9e32, 5e34, 4e36, 5e38, 1e41, 3e43, 1.5e46, 1.2e49, 1.5e52 }, display = "x%s" },
	-- Segundos entre apariciones de objetos en la parcela (lo lee Stats.spawnTime): cada objeto trae tiradas de arma, así
	-- que es la antigua "Velocidad de tirada" (misma clave, para no perder lo comprado). 1,5 s al principio, -12 % por
	-- nivel, ~0,42 s al final. Con Config.Gacha.FreeRoll también acorta la tirada gratis (Stats.rollTime).
	rollSpeed = { name = "Spawn Speed", short = "Spawn", icon = "clock", color = Color3.fromRGB(255, 190, 40), mode = "mul", base = Config.Plot.SpawnInterval, perLevel = 0.88, maxLevel = 10, costs = { 1200, 14000, 1.4e6, 2.8e7, 1.3e11, 1.4e14, 9.2e16, 1.2e20, 1.5e22, 1.3e26 }, display = "%.2fs" },
	-- Monedas (pedido por el usuario): multiplica las que dan los objetos (Stats.coins; la Bolsa de oro no) y se paga con
	-- gemas, que hasta ahora no se gastaban en nada. Sus compras caen entre las de suerte, para que siempre haya algo cerca.
	fortune = { name = "Fortune", short = "Fortune", desc = "Multiplies the coins from objects and from your Gold Bag. Paid with gems.", icon = "coins", color = Color3.fromRGB(190, 110, 255), mode = "mul", base = 1, perLevel = 1.5, maxLevel = 20, currency = "gems", costs = { 1900, 62000, 230000, 740000, 1.9e7, 1.2e9, 3.6e10, 6.2e11, 5.8e12, 7.3e13, 1.5e15, 1.5e16, 1.3e17, 4.6e18, 1.8e20, 1.6e21, 1.8e22, 6e23, 5.3e24, 1.8e25 }, display = "x%s" },
	-- Monedas de bolsa (pedido por el usuario): cada Bolsa de oro vaciada da una, y solo se gastan aquí. Multiplica
	-- TODAS las monedas: las de los objetos (Stats.coins) y las que sacan las armas de la bolsa (Stats.bagCoins). No se
	-- guarda cuántas tiene: son las bolsas vaciadas menos lo gastado en estos niveles (Stats.wallet), así quien ya iba
	-- por bolsas avanzadas las tiene desde el primer día. Precios puestos a mano (el nivel n cuesta n): no los genera
	-- tools/equilibrio, que no tiene calendario para ella.
	bagBoost = { name = "Golden Bag", short = "Bag", desc = "Multiplies all the coins you earn. Paid with bag coins: you get one for each Gold Bag you empty.", icon = "bag", color = Color3.fromRGB(255, 200, 60), mode = "mul", base = 1, perLevel = 2, maxLevel = 20, currency = "bag", costs = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }, display = "x%s" },
}

-- ARMADURA (cae en las mazmorras). Cuatro huecos, una pieza equipada por hueco. Lo que suma un jugador a cada hora
-- (calidad, "bonus" de la zona y bases de aquí) está medido con tools/equilibrio/informe.luau contra la tabla
-- `armadura` de objetivo.luau: si tocas las bases, pásalo.
-- Cada pieza guarda sus valores ya tirados (PlayerData recorta al cargar los porcentajes de las guardadas con la regla
-- antigua, cuando escalaban con el power). Valor de un stat = base del hueco * azar (Roll) * mult de la calidad * lo
-- que escala con la zona (shared/ArmorStats.scaling): la vida, su "power"; los porcentajes, su "bonus", mucho más
-- suave; los de scales = false, nada. "health" es vida que se suma; el resto son
-- porcentajes (0.05 = +5 %) que se suman entre piezas y luego multiplican el stat final (ver shared/Stats).
Config.Armor = {
	MaxPieces = 60, -- con el inventario lleno, las piezas nuevas se desmontan solas
	BaseHealth = 100, -- vida del personaje sin armadura
	Roll = { min = 0.8, max = 1.2 },
	-- Pedido por el usuario: la 4.ª stat de una pieza no puede ser vida máxima (con "Equipar mejores" una pieza con
	-- 200 de vida de más se quedaba sin elegirse). Un modificador extra que cayera ahí como vida se vuelve a tirar.
	NoHealthAt = 4,
	SlotOrder = { "helmet", "chest", "legs", "boots" },
	Slots = {
		helmet = { name = "Helmet", stats = { health = 40, luck = 0.05 } },
		chest = { name = "Chestplate", stats = { health = 100 } },
		legs = { name = "Greaves", stats = { health = 60, rollSpeed = 0.03 } },
		boots = { name = "Boots", stats = { health = 30, damage = 0.03, luck = 0.03 } },
	},
	StatOrder = { "health", "damage", "luck", "rollSpeed" },
	Stats = {
		health = { name = "Max Health", flat = true, color = Color3.fromRGB(255, 110, 110) },
		damage = { name = "Attack", color = Color3.fromRGB(255, 154, 106) },
		luck = { name = "Luck", color = Color3.fromRGB(126, 224, 122) },
		rollSpeed = { name = "Spawn Speed", scales = false, color = Color3.fromRGB(255, 200, 90) },
	},
	-- Calidades, de peor a mejor: "odds" = 1 entre N de que salga (la suerte de la dificultad y del enemigo divide N),
	-- "mods" = modificadores extra que trae, "value" = Cristales de grado al desmontarla: las corrientes no dan ninguno y
	-- ya no se multiplica por el loot de la zona (daba 1 a 100 por pieza y por x2048: de ahí salía el 96 % de los
	-- cristales de grado). Ahora desmontar da alrededor del 30 % de los cristales de grado y los enemigos el resto.
	-- Son propias de la armadura (no las rarezas de las espadas). No cambies el orden: lo nuevo, al final.
	Qualities = {
		{ name = "Common", odds = 1, mult = 1, mods = 0, value = 0, color = Color3.fromRGB(190, 195, 205) },
		{ name = "Uncommon", odds = 4, mult = 1.4, mods = 0, value = 0, color = Color3.fromRGB(90, 220, 100) },
		{ name = "Rare", odds = 20, mult = 2, mods = 1, value = 4, color = Color3.fromRGB(70, 150, 255) },
		{ name = "Epic", odds = 150, mult = 3, mods = 1, value = 8, color = Color3.fromRGB(180, 90, 255) },
		{ name = "Legendary", odds = 2000, mult = 5, mods = 2, value = 20, color = Color3.fromRGB(255, 190, 40) },
		{ name = "Mythic", odds = 50000, mult = 8, mods = 3, value = 60, color = Color3.fromRGB(255, 70, 70) },
	},
	-- Modificadores extra: "chance" = peso de salir, "value" = base (se escala como los stats del hueco).
	Mods = {
		{ stat = "health", value = 30, chance = 40 },
		{ stat = "luck", value = 0.04, chance = 25 },
		{ stat = "damage", value = 0.04, chance = 25 },
		{ stat = "rollSpeed", value = 0.02, chance = 10 },
	},
}

-- MAZMORRAS (partida): cada grupo juega en su arena. Lo que dan (ClearDrops aquí, "drops" de Config.Enemies, "loot" y
-- "qualityLuck" de Config.Dungeons) está ajustado con tools/equilibrio para dos cosas: que el jugador normal lleve a
-- cada hora el rasgo, el grado y la armadura que le supone el calendario (objetivo.rasgo, .grado y .armadura), y que
-- quien deje el personaje en Auto y Repetir 24 h en la última zona saque unos 30 000 cristales de rasgo y 30 000 de
-- grado (objetivo.bucle, decidido por el usuario al pasar a cuatro armas equipadas: Paradoja en la primera en 1,75
-- días de bucle y en las cuatro en unos 7). Una partida dura de 23 s a algo más de un minuto (44 s la de la última
-- zona con todo cayendo de un golpe): la de la primera zona da de media un cristal y medio de rasgo y uno de grado,
-- y la de la última, unos quince de cada.
Config.Dungeon = {
	TimeLimit = 300, -- segundos para terminar la mazmorra
	WaveDelay = 2, -- pausa entre oleadas
	ExitDelay = 4, -- segundos en la arena tras ganar, antes de volver al hub
	HitStop = 0.25, -- segundos que se queda parado un enemigo al recibir un golpe que no lo mata (no lo empuja)
	-- Menú de botín al acabar la partida (server/DropMenu, client/DropMenu): el botín se retiene mientras dura la
	-- partida y el jugador marca lo que tira. Sin respuesta en `Timeout` s, o con Repetir / Auto de pelea, se queda todo.
	DropMenu = {
		Timeout = 60,
		ConfirmQuality = 5, -- calidad de armadura desde la que pide confirmación para tirarla (5 = Legendaria)
		ConfirmTier = 6, -- tier de poción desde el que la pide (6 = VI)
	},
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
		{ kind = "item", item = "traitCrystal", chance = 0.515 },
		{ kind = "item", item = "gradeCrystal", chance = 0.375 },
		{ kind = "potion", chance = 0.018 },
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
-- "hp" = daño recomendado (el del cartel de la sala): la vida de un enemigo es su hp por este número. NÚMERO GENERADO
-- por tools/equilibrio (`generar.luau 9 mazmorras aplicar` lo rehace sin tocar lo demás): la vida con la que una
-- partida le dura 75 s (objetivo.mazmorra.comoda) al jugador tipo, con sus cuatro armas, a la hora en que le toca cada
-- zona (de los 5 min a las 175 h); sale de un tercio a algo más de la mitad de su daño total. Va suavizado con las
-- zonas vecinas para que la escalera suba parejo (x10 a x40 por zona; sin suavizar había un salto de x200 y otro de x2).
-- "power" multiplica el daño de los enemigos Y la vida de la armadura que cae: cada dificultad pide la armadura de la
-- anterior. "bonus" multiplica los porcentajes de esa armadura (suerte, ataque): crece mucho más despacio que el
-- power para que la armadura no tape al resto de fuentes de suerte y de daño (x1 a x10,5: con él, el jugador simulado
-- lleva la suerte y el ataque de la tabla `armadura` de objetivo.luau).
-- "count" = más enemigos, "loot" = más cristales (x1 a x6,5; la parte decimal es la probabilidad de uno más),
-- "qualityLuck" = mejor calidad de armadura (x1 a x30: en una partida de 260 h caen 4 o 5 piezas Míticas).
-- Antes llegaban a x2048 y x12000 y sobraban cristales y armadura Mítica: el juego entero se acababa en 12 h.
-- "set", "armorColor" y "armorMaterial" = nombre y aspecto de la armadura que cae ahí ("Casco de cuero").
-- "color" = acento de la zona. "minDamage" (opcional) = daño mínimo para entrar (si no llega, la sala sale cerrada).
-- No cambies el orden: las piezas de armadura guardan la posición. Lo nuevo, al final.
Config.Dungeons = {
	{ id = "forest", name = "Whispering Woods", difficulty = "Easy", tagline = "Old roots that murmur your name.", hp = 700, power = 1, bonus = 1, count = 1, loot = 1, qualityLuck = 1, color = Color3.fromRGB(90, 210, 110), set = "Leather {slot}", armorColor = Color3.fromRGB(150, 105, 65), armorMaterial = Enum.Material.Leather },
	{ id = "mines", name = "Abandoned Mines", difficulty = "Normal", tagline = "Forgotten tunnels where something is still digging.", hp = 20000, power = 4, bonus = 1.3, count = 1.25, loot = 1.3, qualityLuck = 1.4, color = Color3.fromRGB(240, 170, 70), set = "Iron {slot}", armorColor = Color3.fromRGB(175, 180, 192), armorMaterial = Enum.Material.Metal },
	{ id = "crypt", name = "Crypt of the Fallen King", difficulty = "Hard", tagline = "A restless king and his court of bones.", hp = 900000, power = 16, bonus = 1.65, count = 1.5, loot = 1.6, qualityLuck = 2, color = Color3.fromRGB(160, 125, 225), set = "Obsidian {slot}", armorColor = Color3.fromRGB(58, 50, 82), armorMaterial = Enum.Material.Slate },
	{ id = "temple", name = "Temple of Ashes", difficulty = "Nightmare", tagline = "Embers, incense and worshippers who never yield.", hp = 4e7, power = 64, bonus = 2.1, count = 1.75, loot = 2, qualityLuck = 2.8, color = Color3.fromRGB(235, 70, 80), set = "Crimson {slot}", armorColor = Color3.fromRGB(165, 40, 52), armorMaterial = Enum.Material.Metal },
	{ id = "abyss", name = "Sunken Abyss", difficulty = "Abyss", tagline = "Drowned waters where the light no longer reaches.", hp = 2e9, power = 256, bonus = 2.6, count = 2, loot = 2.4, qualityLuck = 4, color = Color3.fromRGB(50, 200, 210), set = "Abyssal {slot}", armorColor = Color3.fromRGB(88, 62, 200), armorMaterial = Enum.Material.Foil },
	-- Endgame.
	{ id = "inferno", name = "Hell's Cauldron", difficulty = "Inferno", tagline = "A living cauldron: everything burns, everything strikes.", hp = 6e10, power = 1024, bonus = 3.1, count = 2, loot = 2.9, qualityLuck = 5.5, color = Color3.fromRGB(255, 110, 40), set = "Infernal {slot}", armorColor = Color3.fromRGB(200, 70, 30), armorMaterial = Enum.Material.CrackedLava },
	{ id = "void", name = "Void Wasteland", difficulty = "Void", tagline = "The ground ends. The silence doesn't.", hp = 1e12, power = 4096, bonus = 3.7, count = 2, loot = 3.4, qualityLuck = 7.5, color = Color3.fromRGB(130, 70, 255), set = "Void {slot}", armorColor = Color3.fromRGB(60, 40, 110), armorMaterial = Enum.Material.Metal },
	{ id = "nebula", name = "Nebula Garden", difficulty = "Nebula", tagline = "A garden of stardust… with teeth.", hp = 2e13, power = 16384, bonus = 4.3, count = 2.25, loot = 3.9, qualityLuck = 10, color = Color3.fromRGB(230, 90, 160), set = "Nebula {slot}", armorColor = Color3.fromRGB(205, 85, 150), armorMaterial = Enum.Material.Foil },
	{ id = "galaxy", name = "Galactic Observatory", difficulty = "Galaxy", tagline = "Look at the stars. They're looking back at you.", hp = 8e14, power = 65536, bonus = 5, count = 2.25, loot = 4.5, qualityLuck = 14, color = Color3.fromRGB(60, 110, 255), set = "Galaxy {slot}", armorColor = Color3.fromRGB(45, 70, 190), armorMaterial = Enum.Material.Metal },
	{ id = "cosmos", name = "Cosmos Bastion", difficulty = "Cosmos", tagline = "Crystal towers that turn with the cosmos.", hp = 1e16, power = 262144, bonus = 6.2, count = 2.5, loot = 5.1, qualityLuck = 18, color = Color3.fromRGB(60, 255, 170), set = "Cosmos {slot}", armorColor = Color3.fromRGB(30, 60, 80), armorMaterial = Enum.Material.Slate },
	{ id = "origin", name = "Sanctuary of the Origin", difficulty = "Origin", tagline = "Where it all began, and where everything is measured.", hp = 4e16, power = 1048576, bonus = 8.2, count = 2.5, loot = 5.8, qualityLuck = 24, color = Color3.fromRGB(240, 245, 255), set = "Origin {slot}", armorColor = Color3.fromRGB(240, 240, 250), armorMaterial = Enum.Material.Marble },
	{ id = "infinity", name = "Throne of Infinity", difficulty = "Infinity", tagline = "The last throne. No one has sat on it since.", hp = 1.2e17, power = 4194304, bonus = 10.5, count = 3, loot = 6.5, qualityLuck = 30, color = Color3.fromRGB(255, 40, 60), set = "Infinity {slot}", armorColor = Color3.fromRGB(215, 35, 55), armorMaterial = Enum.Material.Foil },
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
			grunt = { name = "Whispering Sprout", color = rgb(104, 176, 78), look = "leaf" },
			brute = { name = "Young Ent", color = rgb(112, 86, 60), look = { "antlers", "leaf" }, scale = 1.05 },
			boss = { name = "Elder Ent", color = rgb(76, 112, 64), look = { "antlers", "crown" } },
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
			grunt = { name = "Cave Mole", color = rgb(146, 112, 86), look = "helmet" },
			brute = { name = "Iron Foreman", color = rgb(150, 152, 164), look = { "helmet", "spikes" }, scale = 1.05 },
			boss = { name = "Ore Golem", color = rgb(126, 102, 84), look = { "spikes", "crown" } },
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
			grunt = { name = "Skeleton", color = rgb(226, 222, 204), look = "skull" },
			brute = { name = "Fallen Knight", color = rgb(122, 120, 144), look = { "skull", "horns" }, scale = 1.05 },
			boss = { name = "Fallen King", color = rgb(204, 198, 178), look = { "skull", "crown" } },
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
			grunt = { name = "Ashen Acolyte", color = rgb(132, 72, 68), look = "hood" },
			brute = { name = "Executioner", color = rgb(92, 62, 62), look = { "hood", "horns" }, scale = 1.05 },
			boss = { name = "High Priest", color = rgb(176, 52, 62), look = { "hood", "flame", "crown" } },
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
			grunt = { name = "Lantern Fish", color = rgb(64, 150, 190), look = "halo" },
			brute = { name = "Coral Crab", color = rgb(216, 104, 92), look = "spikes", scale = 1.05 },
			boss = { name = "Leviathan", color = rgb(52, 92, 172), look = { "spikes", "crown" } },
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
			grunt = { name = "Ash Imp", color = rgb(232, 104, 52), look = "flame" },
			brute = { name = "Magma Demon", color = rgb(192, 74, 42), look = { "horns", "flame" }, scale = 1.05 },
			boss = { name = "Lord of the Cauldron", color = rgb(152, 42, 32), look = { "horns", "crown", "flame" } },
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
			grunt = { name = "Wandering Shadow", color = rgb(62, 42, 104), look = "hood" },
			brute = { name = "Void Stalker", color = rgb(94, 62, 154), look = { "hood", "halo" }, scale = 1.05 },
			boss = { name = "Void Herald", color = rgb(42, 22, 84), look = { "halo", "crown" } },
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
			grunt = { name = "Star Spore", color = rgb(242, 134, 192), look = "leaf" },
			brute = { name = "Floral Guardian", color = rgb(204, 94, 172), look = { "leaf", "horns" }, scale = 1.05 },
			boss = { name = "Nebula Queen", color = rgb(174, 84, 204), look = { "leaf", "crown", "halo" } },
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
			grunt = { name = "Rogue Satellite", color = rgb(124, 144, 204), look = "spikes" },
			brute = { name = "Wandering Astronomer", color = rgb(84, 104, 194), look = { "hood", "halo" }, scale = 1.05 },
			boss = { name = "Star Titan", color = rgb(60, 92, 232), look = { "halo", "spikes" } },
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
			grunt = { name = "Cosmic Shard", color = rgb(84, 232, 184), look = "spikes" },
			brute = { name = "Crystal Sentinel", color = rgb(62, 192, 172), look = { "helmet", "spikes" }, scale = 1.05 },
			boss = { name = "Archon of the Cosmos", color = rgb(42, 162, 152), look = { "halo", "crown" } },
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
			grunt = { name = "Echo of the Origin", color = rgb(236, 238, 250), look = "halo" },
			brute = { name = "Marble Guardian", color = rgb(214, 218, 236), look = { "horns", "halo" }, scale = 1.05 },
			boss = { name = "First Witness", color = rgb(255, 246, 222), look = { "halo", "crown" } },
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
			grunt = { name = "Infinite Shadow", color = rgb(74, 32, 54), look = "hood" },
			brute = { name = "Throne Executioner", color = rgb(112, 32, 44), look = { "horns", "spikes" }, scale = 1.05 },
			boss = { name = "King of Infinity", color = rgb(212, 32, 58), look = { "crown", "horns", "flame" } },
		},
		room = { { kind = "column", count = 3 }, { kind = "banner", count = 3, color = rgb(190, 30, 50) }, { kind = "brazier", count = 3 } },
	},
}

-- Daños pensados para que, con el set común de la dificultad anterior, el jefe necesite unos 5 golpes para matarte.
-- Enemigos. "hp" en golpes (por el hp de la dificultad), "damage" por golpe (por el power de la dificultad),
-- "speed" al andar, "attackRange" desde su borde, "attackTime" segundos entre golpes. scaleCount = false: su
-- cantidad no crece con la dificultad. "look" = adornos ("horns", "crown"). "drops" = tabla de premios al morir (ver server/Loot): cada entrada lleva
-- "kind" ("item" con item, min y max; "armor" con luck que multiplica la suerte de calidad) y "chance".
-- Las "chance" de cristales y armadura van con el calendario de tools/equilibrio (ver Config.Dungeon): tras cambiarlas,
-- pasar `lune run tools/equilibrio/informe.luau`, que juega las mazmorras y lo compara con el calendario.
Config.Enemies = {
	grunt = { name = "Minion", hp = 6, damage = 3, speed = 17, attackRange = 3.5, attackTime = 1.2, size = Vector3.new(4, 4, 4), color = Color3.fromRGB(120, 200, 90), drops = {
		{ kind = "item", item = "traitCrystal", chance = 0.014 },
		{ kind = "item", item = "gradeCrystal", chance = 0.0095 },
		{ kind = "armor", chance = 0.0075 },
		{ kind = "potion", chance = 0.00018 },
	} },
	brute = { name = "Brute", hp = 20, damage = 7, speed = 11, attackRange = 4, attackTime = 1.8, look = "horns", size = Vector3.new(6.5, 6.5, 6.5), color = Color3.fromRGB(200, 110, 70), drops = {
		{ kind = "item", item = "traitCrystal", chance = 0.07 },
		{ kind = "item", item = "gradeCrystal", chance = 0.047 },
		{ kind = "armor", chance = 0.025, luck = 2 },
		{ kind = "potion", chance = 0.0009 },
	} },
	boss = { name = "Guardian", hp = 120, damage = 12, speed = 13, attackRange = 5, attackTime = 2, scaleCount = false, look = "crown", size = Vector3.new(11, 11, 11), color = Color3.fromRGB(150, 80, 220), drops = {
		{ kind = "item", item = "traitCrystal", chance = 0.515 },
		{ kind = "item", item = "gradeCrystal", chance = 0.375 },
		{ kind = "armor", chance = 0.15, luck = 5 },
		{ kind = "potion", chance = 0.006 },
	} },
}

-- COMERCIO entre jugadores (server/Trade). Countdown = segundos de la cuenta atrás final, en los que aún se puede
-- cancelar; InviteTime = lo que dura una invitación; RequestCooldown = espera entre invitaciones.
-- Peticiones dentro del trato (botón "Pedir": pides algo del inventario del otro): SuggestCooldown = espera entre
-- peticiones, SuggestTime = lo que dura una sin respuesta, SuggestMaxAmount = tope de la cantidad pedida, SuggestWant = qué se puede pedir.
-- Allow = lo que se puede ofrecer y pedir: objetos (cristales y pociones), espadas, armadura y accesorios. Monedas ("coins") y
-- gemas ("gems") no están, decidido por el usuario: con ellas un jugador avanzado le regalaba el progreso a otro.
Config.Trade = {
	-- Renacimientos que hacen falta para comerciar (pedido por el usuario: con cuentas nuevas se juntaban tréboles y
	-- pociones gratis en una sola). Para probar el comercio en Studio con el bot, bajarlo a 0 un momento.
	MinRebirths = 1,
	Countdown = 3,
	InviteTime = 20,
	RequestCooldown = 3,
	SuggestCooldown = 0.4,
	SuggestTime = 20,
	SuggestMaxAmount = 1e36,
	SuggestWant = { items = true, swords = true, armor = true },
	Allow = { items = true, swords = true, armor = true }, -- accesorios no (pedido por el usuario: uno de cada, atado a la cuenta)
}

-- PASES DE JUEGO (gamepass; tienda del menú, client/PassShop y server/Passes). "id" = id del pase en Roblox
-- (se crea en la página del juego; con 0 aún no está a la venta y el botón dice "Pronto"). "price" = Robux que se
-- enseñan hasta que Roblox dice el precio real. "perksText" = lo que se lee en la tienda. "perks" = ventajas que
-- lee Stats.perk (si varios pases dan la misma, vale la mayor): traitCount = rasgos que se pueden tirar de golpe;
-- gradeSpeed = por cuánto se multiplica la velocidad de las tiradas de grado (4 = 400 %); autoFarm = botón "Auto" junto
-- al arma: en tu parcela, las armas llegan solas a todos los objetos sin que el personaje se mueva (Stats.reach, server/AutoPlay y client/AutoPlay).
-- Las que multiplican se acumulan entre pases (Stats.passMult: x2 y x5 de suerte de armas juntos son x10): weaponLuck =
-- suerte de armas (Stats.gachaLuck); luck = suerte de destructibles (Stats.luck); coins = monedas (Stats.coins);
-- walkSpeed = velocidad al andar (Stats.walkSpeed); dungeonLoot = premios de mazmorra (server/Loot). chatTag = etiqueta
-- delante del nombre en el chat (client/ChatTags), del color del pase. Para la tarjeta de la tienda: "icon" = logo de
-- Ui.IMAGES (el grande y los que caen por detrás), "tag" = texto gordo de la esquina y "ribbon" (opcional) = cinta.
-- extraSlots = armas de más que se pueden equipar y, otras tantas, dejar en la Bolsa de oro (Stats.loadoutSlots y
-- Stats.bagSlots; pedido por el usuario).
-- Con tickets (los de las misiones) se compra cualquier pase: cuesta su "price" en Robux por PerRobux (pedido por el
-- usuario: 100 Robux = 150 tickets). La cuenta es Stats.ticketPrice y la compra, server/Passes. Lo que dan las misiones
-- (50 al día y 200 a la semana como mucho) está en shared/MissionList.
-- "Shop" = lo que se compra con tickets en el puesto de Misiones (pestaña "Comprar", server/TicketShop): item = clave de
-- Config.Items (las pociones son potion_<familia>_<tier>: las de tier máximo, pedido por el usuario), price = tickets y
-- amount = cuántos da cada compra (1 si falta). Los cristales de rasgo y de grado van a 10 por ticket (pedido por el usuario).
-- Todos los pases juntos son unas 10 semanas de misiones (pedido por el usuario: con x3 eran 20).
Config.Tickets = {
	PerRobux = 1.5,
	Shop = {
		{ item = "luckClover", price = 150 },
		{ item = "traitCrystal", price = 1, amount = 10 },
		{ item = "gradeCrystal", price = 1, amount = 10 },
		{ item = "potion_weaponLuck_5", price = 20 },
		{ item = "potion_boxLuck_5", price = 20 },
		{ item = "potion_coins_5", price = 20 },
		{ item = "potion_damage_5", price = 20 },
		{ item = "potion_health_5", price = 20 },
	},
}
-- TUTORIAL de los primeros minutos (server/Tutorial decide cuándo se cumple cada paso; client/Tutorial pone la tarjeta y
-- la flecha). Los pasos van en orden. text = lo que se le pide; kind = cómo se cumple: "breaks" (romper `goal` objetos) y
-- "upgrades" (comprar una mejora) se cuentan solos; "equip" (tener 2 armas equipadas), "bag" (un arma en la Bolsa de oro)
-- y "lobby" (estar en el lobby de mazmorras) los comprueba el servidor; "seen" = abrir la ventana `window` de la interfaz.
-- point = a qué señala la flecha: "object" (un objeto de tu parcela), "bag" (tu saco), "stall:<tienda>" (un puesto del
-- hub) o "button:<ruta dentro de Hud.HudRoot>". Reward = lo que da al acabar (clave de Config.Items). El id de cada paso no
-- se guarda (se guarda su posición): los pasos nuevos, al final.
Config.Tutorial = {
	Reward = { item = "luckClover", amount = 1 },
	Steps = {
		{ id = "break", kind = "breaks", goal = 1, text = "Click an object on your plot to break it", point = "object" },
		{ id = "break10", kind = "breaks", goal = 10, text = "Break 10 objects: they drop coins and weapons", point = "object" },
		{ id = "equip", kind = "equip", text = "Open the Backpack and press Equip best", point = "button:Menu.Backpack" },
		{ id = "upgrade", kind = "upgrades", goal = 1, text = "Buy an upgrade with your coins", point = "button:Menu.Upgrades" },
		{ id = "bag", kind = "bag", text = "Tap the sack behind your plot and leave a weapon: it will earn coins on its own", point = "bag" },
		{ id = "missions", kind = "seen", window = "Missions", text = "Go to the Missions stall in the center and take a look", point = "stall:missions" },
		{ id = "dungeon", kind = "seen", window = "DungeonMenu", text = "Open the Dungeons menu and pick one", point = "button:Travel.Travel_dungeon" },
	},
}
-- CÓDIGOS DE REGALO: la lista (y cómo se escribe cada uno) está en server/CodeList, no aquí: lo de shared lo puede leer
-- cualquier cliente con trampas.
-- TRÉBOLES DE LA SUERTE: Items[clave de Config.Items] = { luck = por cuánto multiplica la suerte de armas (una sola vez
-- por objeto); plot = a todos los objetos que hay en ese momento en la parcela elegida (pedido por el usuario: el de
-- x1000 solo se consigue pagando y en un objeto valía poco) }. Item y Luck son los del grande (Tienda, tickets, Misiones).
Config.Clover = {
	Item = "luckClover",
	Luck = 999,
	Items = {
		luckClover = { luck = 999, plot = true },
		smallClover = { luck = 99 },
	},
}

-- Bono de amigos (pedido por el usuario): por cada amigo de Roblox en el mismo servidor, +Bonus de suerte
-- (Stats.luck) y de monedas (Stats.coins), sumado y hasta Max amigos (los servidores son de 8: 7 amigos como mucho).
-- Lo cuenta server/Friends y lo publica en el atributo "Friends". No entra en tools/equilibrio, como los pases.
Config.Friends = { Bonus = 0.1, Max = 7 }

-- RECOMPENSAS DIARIAS (pedido por el usuario; server/DailyRewards, client/DailyRewards). Playtime = premios por tiempo
-- de juego en el día (minutos de juego de verdad, contados por el servidor; el día cambia a la vez que las misiones
-- diarias, 00:00 UTC, y lo no recogido se pierde). Streak = una casilla por día que entras, de la 1 a la 7 y vuelta a
-- empezar; faltar un día no hace perder la racha (decidido por el usuario: sigue por donde iba). Cada premio es una lista
-- de { item = clave de Config.Items, amount = N }, atados a la cuenta (no se comercian: con cuentas de más se juntarían).
-- Nada de pago: el Trébol grande (x999) sigue siendo solo de compra. Los tickets del día 7 son pocos a propósito (las
-- misiones dan 200 a la semana y con ellos se compran los pases). Números puestos a ojo, más generosos tras pedirlo el usuario.
Config.DailyRewards = {
	Playtime = {
		{ minutes = 5, rewards = { { item = "traitCrystal", amount = 15 } } },
		{ minutes = 15, rewards = { { item = "gradeCrystal", amount = 15 }, { item = "potion_coins_3", amount = 1 } } },
		{ minutes = 30, rewards = { { item = "traitCrystal", amount = 30 }, { item = "potion_weaponLuck_3", amount = 1 } } },
		{ minutes = 60, rewards = { { item = "smallClover", amount = 1 }, { item = "gradeCrystal", amount = 30 }, { item = "potion_boxLuck_4", amount = 1 } } },
		{ minutes = 120, rewards = { { item = "traitCrystal", amount = 50 }, { item = "gradeCrystal", amount = 50 }, { item = "potion_damage_5", amount = 1 } } },
		{ minutes = 240, rewards = { { item = "smallClover", amount = 2 }, { item = "potion_weaponLuck_5", amount = 1 }, { item = "potion_coins_5", amount = 1 } } },
	},
	Streak = {
		{ { item = "traitCrystal", amount = 20 }, { item = "potion_coins_3", amount = 1 } },
		{ { item = "gradeCrystal", amount = 20 }, { item = "potion_damage_3", amount = 1 } },
		{ { item = "smallClover", amount = 1 }, { item = "potion_boxLuck_4", amount = 1 } },
		{ { item = "traitCrystal", amount = 40 }, { item = "potion_weaponLuck_4", amount = 1 } },
		{ { item = "gradeCrystal", amount = 40 }, { item = "potion_coins_5", amount = 1 } },
		{ { item = "smallClover", amount = 2 }, { item = "potion_boxLuck_5", amount = 1 } },
		{ { item = "smallClover", amount = 3 }, { item = "potion_weaponLuck_5", amount = 1 }, { item = "missionToken", amount = 15 } },
	},
}

-- PRODUCTOS DE ROBUX que se compran las veces que se quiera (server/Products; salen los primeros en la Tienda). "id" =
-- id del producto en Roblox (0 = aún no se vende, "Pronto"); "price" = Robux que se enseñan hasta que Roblox dice el
-- precio real; item y amount = lo que da (clave de Config.Items). icon, tag, ribbon y color, como en los pases.
Config.ProductOrder = { "clover1", "clover5", "clover10" }
Config.Products = {
	clover1 = { id = 3718055245, name = "Lucky Clover", price = 50, item = "luckClover", amount = 1, icon = "trebol", tag = "x1", color = Color3.fromRGB(90, 220, 130), perksText = { "Pick a plot: x999 weapon luck on all its objects", "Stacks with all the luck they already have" } },
	clover5 = { id = 3718055248, name = "Pack of 5 Clovers", price = 225, item = "luckClover", amount = 5, icon = "trebol_5", tag = "x5", ribbon = "-10%", color = Color3.fromRGB(60, 205, 190), perksText = { "5 clovers: x999 weapon luck on 5 whole plots", "Cheaper than buying one at a time" } },
	clover10 = { id = 3718055274, name = "Pack of 10 Clovers", price = 400, item = "luckClover", amount = 10, icon = "trebol_10", tag = "x10", ribbon = "-20%", color = Color3.fromRGB(255, 190, 60), perksText = { "10 clovers: x999 weapon luck on 10 whole plots", "The cheapest pack per clover" } },
}

Config.GamepassOrder = { "vip", "coins2", "weaponLuck2", "weaponLuck5", "dungeonLoot", "forge", "auto", "arsenal" }
Config.Gamepasses = {
	vip = {
		id = 2027114984,
		name = "VIP",
		icon = "pase_vip", tag = "VIP", ribbon = "POPULAR",
		price = 449,
		color = Color3.fromRGB(255, 205, 70),
		perksText = { "x1.5 coins", "x1.5 destructible luck", "x2 walk speed", "[VIP] tag in chat" },
		perks = { coins = 1.5, luck = 1.5, walkSpeed = 2 },
		chatTag = "VIP",
	},
	weaponLuck2 = {
		id = 2025987032,
		name = "Weapon Luck x2",
		icon = "pase_suerte2", tag = "x2",
		price = 299,
		color = Color3.fromRGB(90, 220, 130),
		perksText = { "x2 luck on every weapon roll", "Stacks with the x5: together, x10" },
		perks = { weaponLuck = 2 },
	},
	weaponLuck5 = {
		id = 2026598990,
		name = "Weapon Luck x5",
		icon = "pase_suerte5", tag = "x5", ribbon = "BEST DEAL",
		price = 999,
		color = Color3.fromRGB(255, 110, 200),
		perksText = { "x5 luck on every weapon roll", "Stacks with the x2: together, x10" },
		perks = { weaponLuck = 5 },
	},
	dungeonLoot = {
		id = 2027079048,
		name = "Dungeon Loot x2",
		icon = "pase_botin", tag = "x2",
		price = 349,
		color = Color3.fromRGB(170, 120, 255),
		perksText = { "Double the crystals, armor and potions in dungeons" },
		perks = { dungeonLoot = 2 },
	},
	auto = {
		id = 2026755018,
		name = "Auto",
		icon = "pase_auto", tag = "AUTO",
		price = 249,
		color = Color3.fromRGB(255, 200, 60),
		perksText = { "Auto button next to your weapon: on your plot, your weapons reach every object on their own", "No need to move or click" },
		perks = { autoFarm = 1 },
	},
	arsenal = {
		id = 2026904972,
		name = "Double Arsenal",
		icon = "pase_arsenal", tag = "+4",
		price = 799,
		color = Color3.fromRGB(240, 80, 90),
		perksText = { "Equip 4 more weapons: 8 attacking at once", "4 more slots in the Gold Bag: 8 weapons earning coins" },
		perks = { extraSlots = 4 },
	},
	forge = {
		id = 2025668973,
		name = "Forge Master",
		icon = "pase_forja", tag = "x10",
		price = 199,
		color = Color3.fromRGB(255, 150, 60),
		perksText = { "Roll 10 traits at once (keeps the best)", "Grade rolls at 400% speed" },
		perks = { traitCount = 10, gradeSpeed = 4 },
	},
	coins2 = {
		id = 2025747023,
		name = "Coins x2",
		icon = "pase_monedas2", tag = "x2",
		price = 299,
		color = Color3.fromRGB(70, 200, 230),
		perksText = { "x2 coins on everything you break", "Stacks with VIP: together, x3" },
		perks = { coins = 2 },
	},
}

-- AUTOCLICKER (botón a la izquierda del arma: da espadazos solo). Gratis para quien esté en el grupo del juego:
-- "group" = id del grupo de Roblox (0 = el grupo dueño del juego; si el juego no es de un grupo, no se pide nada).
-- El "me gusta" se pide en el cartel, pero Roblox no deja comprobarlo.
Config.AutoClicker = { group = 1002188803 }

-- RECONEXIÓN (server/Rejoin y client/Rejoin): Roblox expulsa a los 20 min sin tocar nada. Antes de eso el juego saca al
-- jugador y lo vuelve a meter él mismo, donde estaba y haciendo lo que hacía. After = segundos sin tocar nada a los que
-- se reconecta; Countdown = segundos de aviso (tocar algo lo cancela); DungeonWait = cuánto se espera, como mucho, a que
-- acabe la partida de mazmorra en curso para no perder sus premios (After + DungeonWait tiene que quedar por debajo de
-- 1200); MinSession = segundos mínimos en el servidor antes de poder pedirlo.
Config.Rejoin = { After = 1020, Countdown = 10, DungeonWait = 90, MinSession = 300 }

-- JEFE DEL MUNDO (server/WorldBoss, client/WorldBoss; cuentas en shared/WorldBossInfo). Cae a los First segundos de abrir el
-- servidor y luego cada Interval (pedido por el usuario: minuto 20, 50, 80... de cada servidor, 10 min después de que acabe
-- cada clima, que empieza en el 30 y dura 10). Se abre un portal en el hub Warning segundos antes de que caiga el Rey Slime en su arena,
-- lejos de la isla. Todo el servidor le pega a la vez. No tiene vida (pedido por el usuario): a los Lifetime segundos se
-- va y reparte los premios según el daño de cada uno. Esbirros, cristales del escudo y barriles tienen la vida de lo que
-- un jugador medio de los que hay quita en sus "Seconds".
--   Barrage: globos a círculos rojos (Damage = parte de la vida máxima de quien sigue dentro). Summon: esbirros que
--   persiguen y muerden. Shield: a los First segundos, y luego cada Every, se pone un escudo hasta romper sus
--   cristales. Charge: carga un
--   golpe a toda la arena (salvo SafeZones) que se corta si le llegan Needed barriles; aturdido recibe StunMult de daño.
--   Count de cada cosa = Base + PerPlayer × jugadores en la arena, hasta Max.
--   Rewards (pedido por el usuario: por cantidad de daño, no por porcentaje): Tiers = tramos de daño de menos a más; a cada
--   uno le toca el más alto al que llega. rolls = tiradas de arma (con la suerte media de sus objetos, ObjectSpec.meanLuck,
--   por Luck), crystals = Cristales de rasgo y de grado (esa cantidad de cada), potions = pociones de cada familia de
--   Potions.Order del tier potionTier (1 = I ... 5 = V). Con menos daño que el primero, nada. Los tres que más daño hacen
--   suman TopBonusRolls tiradas y sus Tickets. Las filas del cartel de premios junto al portal salen de aquí.
Config.WorldBoss = {
	First = 1200, Interval = 1800, Warning = 60, AdminWarning = 10, Lifetime = 180, ReturnDelay = 10,
	Portal = { Angle = 67.5, Distance = 72 },
	Origin = Vector3.new(0, 200, -3000), ArenaRadius = 80, FallTime = 1.3, FallHeight = 160,
	Name = "Slime King", Color = Color3.fromRGB(120, 200, 90), Look = "crown", Size = Vector3.new(34, 28, 34),
	Barrage = { Every = 7, Base = 3, PerPlayer = 1, Max = 12, Radius = 8, Warn = 1.8, Damage = 0.25 },
	Summon = { Every = 30, Base = 2, PerPlayer = 0.5, Max = 8, Seconds = 3, Damage = 0.1, Speed = 14, BiteEvery = 1.5, Size = 5, Range = 3.5 },
	Shield = { First = 60, Every = 70, Base = 3, PerPlayer = 0.34, Max = 8, Seconds = 6 },
	Charge = { Every = 55, Time = 12, Barrels = 4, Needed = 2, BarrelSeconds = 2, Flight = 1.1, StunTime = 8, StunMult = 2,
		MegaDamage = 0.8, SafeZones = 3, SafeRadius = 10 },
	Rewards = { Luck = 10, MaxRolls = 5, TopBonusRolls = 1, Tickets = { 2, 1, 1 },
		Tiers = {
			{ damage = 10, rolls = 1, crystals = 10 },
			{ damage = 1e3, rolls = 1, crystals = 50 },
			{ damage = 1e5, rolls = 1, crystals = 100, potions = 1, potionTier = 2 },
			{ damage = 1e7, rolls = 1, crystals = 125, potions = 1, potionTier = 2 },
			{ damage = 1e9, rolls = 2, crystals = 150, potions = 1, potionTier = 3 },
			{ damage = 1e11, rolls = 2, crystals = 200, potions = 2, potionTier = 3 },
			{ damage = 1e13, rolls = 2, crystals = 250, potions = 2, potionTier = 3 },
			{ damage = 1e15, rolls = 3, crystals = 300, potions = 2, potionTier = 4 },
			{ damage = 1e17, rolls = 3, crystals = 350, potions = 3, potionTier = 4 },
			{ damage = 1e19, rolls = 3, crystals = 400, potions = 3, potionTier = 4 },
			{ damage = 1e21, rolls = 4, crystals = 425, potions = 4, potionTier = 5 },
			{ damage = 1e23, rolls = 4, crystals = 450, potions = 4, potionTier = 5 },
			{ damage = 1e25, rolls = 5, crystals = 500, potions = 5, potionTier = 5 },
		},
	},
}

-- POCIONES (server/Potions, client/Potions y client/PotionFx; los textos salen de shared/PotionInfo). Aceleradores
-- temporales: no sustituyen a mejores armas, rasgos, grados, armadura ni mejoras. Cinco familias, cada una con su valor
-- por tier en "values" (lo que multiplica, o lo que suma si es "additive": 0.15 = +15 %). Los tiers son 1-5 (I a V).
-- Para cambiar "Daño V de x2,4 a x2,2" basta con tocar su valor aquí. Números a ojo, sin equilibrar.
--   damage: multiplica el daño (Stats.damage).    health: suma un % a la vida máxima (Stats.maxHealth).
--   boxLuck: suerte de APARICIÓN de los objetos de la parcela (su tipo, su rareza y su tamaño: Stats.spawnLuck). No es la
--     de las armas: las armas solo mejoran de rebote, porque salen mejores objetos.
--   weaponLuck: suerte de las tiradas de arma al romper objetos (Stats.gachaLuck, la misma casilla que los renacimientos).
--   coins: multiplica las monedas que ganas (Stats.coins).
-- "fx" = estilo del efecto en el personaje (client/PotionFx), "glyph" = símbolo del icono hecho con marcos (Ui.potionIcon),
-- que solo sale si la poción no tiene imagen (Ui.IMAGES potion_<familia>_<tier>; hoy la tienen todas).
Config.Potions = {
	Order = { "damage", "health", "boxLuck", "weaponLuck", "coins" },
	Tiers = { "I", "II", "III", "IV", "V" },
	-- Color de cada tier: el de la rareza que ocupa su posición en Config.RarityTiers.
	-- Duración de cada tier en segundos de juego: 10, 15, 20, 25 y 30 min. Solo corre con el jugador conectado
	-- (lo que queda se guarda en sus datos, así que sale y vuelve y sigue igual).
	Durations = { 600, 900, 1200, 1500, 1800 },
	MaxStack = math.huge, -- usar otra del mismo tier suma su duración, hasta esta cantidad de veces la duración del tier (sin tope, pedido por el usuario)
	UseCooldown = 0.3, -- segundos mínimos entre dos usos de un jugador
	LowTime = 60, -- el HUD avisa (el tiempo se pone rojo y late) cuando quedan menos segundos
	Families = {
		damage = {
			name = "Damage Potion", effect = "Damage", desc = "Multiplies the damage of your hits.",
			color = Color3.fromRGB(255, 90, 80), glyph = "sword", fx = "embers",
			values = { 1.15, 1.30, 1.55, 1.90, 2.40 },
		},
		health = {
			name = "Health Potion", effect = "Max Health", desc = "Raises your max health, armor included.",
			color = Color3.fromRGB(255, 140, 50), glyph = "heart", fx = "vitality", additive = true,
			values = { 0.15, 0.30, 0.50, 0.80, 1.25 },
		},
		boxLuck = {
			name = "Crate Luck Potion", effect = "Spawn Luck",
			desc = "Improves the luck of the objects that appear on your plot: rarer types, better rarity and bigger size. It doesn't change weapon luck.",
			color = Color3.fromRGB(90, 225, 100), glyph = "box", fx = "fortune",
			values = { 1.20, 1.45, 1.80, 2.30, 3.00 },
		},
		weaponLuck = {
			name = "Weapon Luck Potion", effect = "Weapon Luck",
			desc = "Improves the luck of the weapons you get from breaking objects. It doesn't change which objects appear.",
			color = Color3.fromRGB(175, 90, 255), glyph = "star", fx = "stars",
			values = { 1.10, 1.25, 1.45, 1.75, 2.15 },
		},
		coins = {
			name = "Coin Potion", effect = "Coins", desc = "Multiplies the coins you earn.",
			color = Color3.fromRGB(255, 205, 60), glyph = "spark", fx = "coins",
			values = { 1.25, 1.50, 2.00, 2.50, 3.50 },
		},
	},
	-- Efectos en el personaje (client/PotionFx), por tier: partículas por segundo y tamaño de cada efecto, brillo de la luz
	-- (0 = sin luz; una sola por personaje, la de su mejor poción) y desde qué tier salen los destellos grandes del pecho.
	Fx = {
		rate = { 4, 5, 6, 8, 10 },
		size = { 1.6, 1.75, 1.9, 2.1, 2.3 },
		light = { 0, 0, 0, 0.2, 0.4 },
		halo = 5,
	},

	-- CAÍDAS. Dos fuentes, cada una por NIVEL DE CONTENIDO (1 bajo, 2 medio, 3 bueno, 4 alto, 5 excepcional):
	--  · "object": al romper un objeto de la parcela. Su nivel sale del tipo (ObjectLevel: un valor por entrada de
	--    Config.Destructibles, y los tipos nuevos sin valor cuentan como el último nivel) y la probabilidad de ObjectChance
	--    (por objeto roto) por QualityChance (una cifra por rareza del objeto, Config.ObjectRarities: uno raro suelta más).
	--  · "dungeon": en las mazmorras, con drops { kind = "potion", chance } en Config.Enemies y Config.Dungeon.ClearDrops
	--    (la probabilidad por enemigo o por victoria); el nivel sale de la zona (DungeonLevel, uno por entrada de
	--    Config.Dungeons).
	-- Cuando cae una poción, Pools dice cuál: primero la familia por su "weight" en ese nivel (0 o ausente = no sale) y
	-- luego el tier por los pesos "tiers" de esa familia (el primero es el I; los que faltan valen 0).
	ObjectLevel = { 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5 },
	ObjectChance = { 1 / 700, 1 / 650, 1 / 1200, 1 / 2000, 1 / 2500 },
	QualityChance = { 1, 1.5, 2.5, 4, 8, 20 },
	DungeonLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5 },
	Pools = {
		object = {
			{ -- 1: bajo (Caja, Barril). Casi todo es suerte de cajas y de tier I; lo demás, casi nunca.
				boxLuck = { weight = 56, tiers = { 100 } },
				damage = { weight = 20, tiers = { 100 } },
				health = { weight = 20, tiers = { 100 } },
				weaponLuck = { weight = 0.3, tiers = { 100 } },
				coins = { weight = 20, tiers = { 100 } },
			},
			{ -- 2: medio (Roca, Pilar, Cristal, Roca de armas)
				boxLuck = { weight = 46, tiers = { 55, 30, 15 } },
				damage = { weight = 18, tiers = { 55, 30, 15 } },
				health = { weight = 18, tiers = { 55, 30, 15 } },
				weaponLuck = { weight = 4, tiers = { 70, 30 } },
				coins = { weight = 18, tiers = { 55, 30, 15 } },
			},
			{ -- 3: bueno (Monolito, Obelisco, Meteorito)
				boxLuck = { weight = 32, tiers = { 0, 50, 33, 17 } },
				damage = { weight = 15, tiers = { 0, 50, 33, 17 } },
				health = { weight = 15, tiers = { 0, 50, 33, 17 } },
				weaponLuck = { weight = 7, tiers = { 0, 50, 33, 17 } },
				coins = { weight = 15, tiers = { 0, 50, 33, 17 } },
			},
			{ -- 4: alto (Núcleo, Estrella, Agujero negro)
				boxLuck = { weight = 24, tiers = { 0, 0, 45, 35, 20 } },
				damage = { weight = 12, tiers = { 0, 0, 45, 35, 20 } },
				health = { weight = 12, tiers = { 0, 0, 45, 35, 20 } },
				weaponLuck = { weight = 6, tiers = { 0, 0, 45, 35, 20 } },
				coins = { weight = 12, tiers = { 0, 0, 45, 35, 20 } },
			},
			{ -- 5: excepcional (Fragmento del vacío, Singularidad, Origen, Infinito). Aquí está el premio gordo de las cajas.
				boxLuck = { weight = 20, tiers = { 0, 0, 0, 40, 35 } },
				damage = { weight = 10, tiers = { 0, 0, 0, 40, 35 } },
				health = { weight = 10, tiers = { 0, 0, 0, 40, 35 } },
				weaponLuck = { weight = 5, tiers = { 0, 0, 0, 40, 35 } },
				coins = { weight = 10, tiers = { 0, 0, 0, 40, 35 } },
			},
		},
		dungeon = {
			{ -- 1: bajo (Bosque, Minas)
				boxLuck = { weight = 40, tiers = { 70, 30 } },
				damage = { weight = 22, tiers = { 70, 30 } },
				health = { weight = 22, tiers = { 70, 30 } },
				weaponLuck = { weight = 1.5, tiers = { 80, 20 } },
				coins = { weight = 22, tiers = { 70, 30 } },
			},
			{ -- 2: medio (Cripta, Templo)
				boxLuck = { weight = 30, tiers = { 30, 40, 30 } },
				damage = { weight = 18, tiers = { 30, 40, 30 } },
				health = { weight = 18, tiers = { 30, 40, 30 } },
				weaponLuck = { weight = 4, tiers = { 50, 35, 15 } },
				coins = { weight = 18, tiers = { 30, 40, 30 } },
			},
			{ -- 3: bueno (Abismo, Infierno)
				boxLuck = { weight = 24, tiers = { 0, 30, 40, 30 } },
				damage = { weight = 14, tiers = { 0, 30, 40, 30 } },
				health = { weight = 14, tiers = { 0, 30, 40, 30 } },
				weaponLuck = { weight = 6, tiers = { 0, 35, 40, 25 } },
				coins = { weight = 14, tiers = { 0, 30, 40, 30 } },
			},
			{ -- 4: alto (Vacío, Nebulosa, Galaxia)
				boxLuck = { weight = 24, tiers = { 0, 0, 30, 40, 30 } },
				damage = { weight = 10, tiers = { 0, 0, 30, 40, 30 } },
				health = { weight = 10, tiers = { 0, 0, 30, 40, 30 } },
				weaponLuck = { weight = 7, tiers = { 0, 0, 30, 40, 30 } },
				coins = { weight = 10, tiers = { 0, 0, 30, 40, 30 } },
			},
			{ -- 5: endgame (Cosmos, Origen, Infinito)
				boxLuck = { weight = 24, tiers = { 0, 0, 0, 30, 40 } },
				damage = { weight = 8, tiers = { 0, 0, 0, 30, 40 } },
				health = { weight = 8, tiers = { 0, 0, 0, 30, 40 } },
				weaponLuck = { weight = 8, tiers = { 0, 0, 0, 30, 40 } },
				coins = { weight = 8, tiers = { 0, 0, 0, 30, 40 } },
			},
		},
	},
}

-- Cada poción es un objeto normal de Config.Items ("potion_<familia>_<tier>", se amontonan por cantidad). No van en
-- Config.ItemOrder (las enseña aparte la mochila): sus claves, en orden de familia y de tier, están en ItemKeys.
Config.Potions.ItemKeys = {}
for _, family in Config.Potions.Order do
	local info = Config.Potions.Families[family]
	for tier in info.values do
		local key = `potion_{family}_{tier}`
		table.insert(Config.Potions.ItemKeys, key)
		Config.Items[key] = {
			name = `{info.name} {Config.Potions.Tiers[tier]}`,
			description = info.desc,
			color = Config.RarityTiers[tier].color,
			potion = { family = family, tier = tier },
		}
	end
end

return Config
