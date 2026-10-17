-- Único sitio donde se definen los RemoteEvents. El servidor los crea; el cliente los espera.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Attack", -- cliente -> servidor: (pieza o nada) mandar las armas equipadas a por ese objeto de mi parcela o ese enemigo de mi partida, dentro de mi círculo (Config.Loadout.Radius); sin pieza, que vuelvan
	"RollGacha", -- cliente -> servidor: tirada gratis del gacha (una cada Stats.rollTime); solo con Config.Gacha.FreeRoll, si no el servidor la ignora
	"EquipSword", -- cliente -> servidor: (id) equipar una copia de espada del inventario, o quitarla si ya lo estaba (hasta Config.Loadout.Slots a la vez; sin huecos sustituye a la de menos daño); ("best") equipar las de más daño
	"SellSword", -- cliente -> servidor: (id) vender una copia que no esté equipada
	"SellSwords", -- cliente -> servidor: ({ ids }) venta múltiple validada por el servidor
	"LockSword", -- cliente -> servidor: (id) poner o quitar el candado a una copia: bloqueada no se vende (ni a mano ni sola) ni se comercia
	"SetAutoSell", -- cliente -> servidor: (rarity) vender solas las espadas de rareza menor; 0 = no
	"Teleport", -- cliente -> servidor: (destino) "hub", "home" (su parcela), "shops" (tiendas del hub) o "dungeon" (portal)
	"Teleported", -- servidor -> cliente: viaje completado, cerrar menús y escenas
	"BuyUpgrade", -- cliente -> servidor: (name) subir un nivel una mejora de Config.Upgrades
	"BuyAllUpgrades", -- cliente -> servidor: subir todas las mejoras que se puedan pagar
	"Hit", -- servidor -> clientes: (player, part, position, damage, hueco del arma que ha pegado)
	"Broken", -- servidor -> clientes: (player, cframe, size, color, material, reward, gems, índice del objeto en Config.Destructibles; sin él, los enemigos, info = { quality, scale, luck, rolls } del objeto roto)
	"GachaRolled", -- servidor -> cliente: (index, kept, luck, source, metal, size, extra) espada sacada; kept = false si se vendió sola; source = "object" (la dio un objeto de la parcela) o "gacha"; extra = { boost = suerte del objeto, odds = lo difícil que era para el jugador, id = el de la copia guardada (nil si se vendió), roll, rolls, batch = tanda, name, quality, origin y box = dónde estaba el objeto y su tamaño }
	"GachaRevealed", -- cliente -> servidor: ya he destapado mi siguiente tirada rara (para mandar su aura y aviso a todos)
	"GachaAura", -- servidor -> clientes: (player, index, odds) aura en el personaje de quien sacó algo raro para su suerte (odds = rareza / suerte)
	"RollTrait", -- cliente -> servidor: (id) gastar un Cristal de rasgo en esa copia de espada (tienda de Rasgos)
	"RollGrade", -- cliente -> servidor: (id) gastar Config.GradeCost Cristales de grado en un grado para esa copia (tienda de Grados)
	"RevertGrade", -- cliente -> servidor: (id) descartar el grado recién tirado a mano en la forja y volver al anterior
	"ModifierRolled", -- servidor -> cliente: (kind, id, index) resultado de una tirada de rasgo ("traits") o grado ("grades")
	"ToggleGear", -- cliente -> servidor: (artifactIndex) equipar o quitar un artefacto
	"Notice", -- servidor -> cliente: (text, color) aviso en pantalla solo para él
	"Announce", -- servidor -> clientes: (text, color) aviso de algo muy raro
	"Rebirth", -- cliente -> servidor: renacer (hace falta el precio en monedas; quita monedas, gemas, mejoras y la bolsa)
	"Reborn", -- servidor -> todos: (jugador, renacimientos que lleva, monedas y gemas que tenía) acaba de renacer
	"BuyPassTickets", -- cliente -> servidor: (clave de Config.Gamepasses) comprar ese pase con tickets de misión
	"BuyTicketItem", -- cliente -> servidor: (posición en Config.Tickets.Shop) comprar ese objeto con tickets de misión
	"UseClover", -- cliente -> servidor: (objeto de una parcela, tuya o de otro) gastar un Trébol de la suerte en él
	"RedeemCode", -- cliente -> servidor: (texto) canjear un código de regalo de Config.Codes
	"TutorialCheck", -- cliente -> servidor: (id del paso, opcional) "creo que ya he cumplido el paso del tutorial": el servidor lo comprueba
	"TutorialSkip", -- cliente -> servidor: dar el tutorial por terminado, sin premio
	"ClaimMission", -- cliente -> servidor: (periodo "daily" o "weekly", id de la misión) cobrar la recompensa de una misión cumplida
	"ClaimDaily", -- cliente -> servidor: ("playtime", posición) o ("streak") recoger una recompensa diaria (server/DailyRewards)
	"AdminSetModifier", -- cliente -> servidor: (kind "traits" o "grades", id de la copia, índice o 0 = quitar) modo admin de pruebas, solo en Studio
	"TradeRequest", -- cliente -> servidor: (userId) invitar a comerciar a ese jugador (0 = bot de pruebas, solo en Studio)
	"TradeRespond", -- cliente -> servidor: (userId de quien invitó, true o false) aceptar o rechazar la invitación
	"TradeOffer", -- cliente -> servidor: (categoría, clave, cantidad) cambiar mi oferta: "coins"/"gems" (cantidad), "items" (nombre, cantidad), "swords"/"armor"/"artifacts" (id o índice, 1 = poner, 0 = quitar)
	"TradeAccept", -- cliente -> servidor: (true o false) aceptar las ofertas; false en el paso de confirmar = volver a editar
	"TradeConfirm", -- cliente -> servidor: confirmar el trato (segundo paso)
	"TradeCancel", -- cliente -> servidor: cancelar el trato (también durante la cuenta atrás)
	"TradeInvite", -- servidor -> cliente: (userId, nombre) ese jugador te invita a comerciar
	"TradeState", -- servidor -> cliente: ({ state, ends, you, them }) estado del trato, o nil si se ha cerrado; you.suggest / them.suggest = sugerencia en curso de cada uno ({ intent, category, key, amount, ends, ignored, sword o piece })
	"TradeSuggest", -- cliente -> servidor: (intención, categoría, clave, cantidad) sugerir algo en el trato: "want" (quiero eso tuyo; solo monedas, gemas y objetos) o "give" (te doy eso mío); sin intención = quitar mi sugerencia
	"TradeSuggestRespond", -- cliente -> servidor: (true o false) aceptar o ignorar la sugerencia del otro
	"SetDungeonLoop", -- cliente -> servidor: (true o false) repetir la mazmorra sola cada vez que la supere (si lideras el grupo)
	"LeaveDungeon", -- cliente -> servidor: salir de la mazmorra en la que está
	"DungeonEvent", -- servidor -> cliente: (tipo, datos) "hurt" (daño recibido) o "result" ({ won, reason, level, drops?, armorFree?, expires?, granted? }); `drops` = el botín retenido para el menú
	"DropDecision", -- cliente -> servidor: ({ ids }) los drops del menú de botín que tira (descarta); el resto entra al inventario
	"EquipArmor", -- cliente -> servidor: (id) poner o quitar una pieza de armadura; ("best") la mejor de cada hueco
	"SalvageArmor", -- cliente -> servidor: (id, o { ids } para varias sin equipar) desmontar armadura a cambio de Cristales de grado
	"SetArmorHidden", -- cliente -> servidor: (true o false) esconder la armadura del personaje (sigue contando); se guarda y se publica en "ArmorHidden"
	"SetModifierPrefs", -- cliente -> servidor: (kind "traits"|"grades", resultados de "Parar con" como índices separados por comas, desempate de rasgos como texto o nil) los ajustes de la tienda; se guardan y se publican en "StopAt_<kind>" y "TraitPriority"
	"PartyRequest", -- cliente -> servidor: (acción, a, b) sala de grupo de las mazmorras: "open" (zona) y "close" miran o dejan de mirar una sala; "create" (zona), "join" (id del grupo), "leave", "ready" (true o false), "start", "solo" (zona), "dungeon" (zona nueva), "option" (nombre, true o false), "kick" (userId), "invite" (userId), "respond" (userId del líder, true o false)
	"PartyState", -- servidor -> cliente: ({ room, mine, parties }) la sala que miras, tu grupo (zona, líder, miembros, listos, opciones, estado) y los grupos abiertos de esa sala; nil = nada que enseñar
	"PartyInvite", -- servidor -> cliente: (userId del líder, nombre del líder, zona) te invitan a un grupo de mazmorra
	"UsePotion", -- cliente -> servidor: (familia de Config.Potions.Families, tier) usar una poción del inventario; el servidor decide si activa, mejora, suma tiempo o rechaza
	"SetAuto", -- cliente -> servidor: (modo "click" o "farm", true o false) encender o apagar el autoclicker o el Auto de la parcela; el servidor decide y lo publica en "AutoClick" / "AutoFarm"
	"AutoDenied", -- servidor -> cliente: (modo, id del grupo) no puede encenderlo: "click" = le falta unirse al grupo, "farm" = le falta el pase
	"SetBag", -- cliente -> servidor: (id) dejar esa copia de espada en mi Bolsa de oro, o sacarla si ya estaba (hasta Config.GoldBag.Slots; llena, sustituye a la de menos daño; una equipada deja de estarlo); "best" = dejar las de más daño de las que no están equipadas, "clear" = vaciarla
	"BagEvent", -- servidor -> cliente: (tipo, datos) "emptied" ({ stage = bolsa nueva, bags = vaciadas }) o "away" ({ seconds, coins, bags }: lo que han sacado sus armas mientras no estaba)
	"SetLang", -- cliente -> servidor: ("es" o "en") el idioma que tengo elegido para esta experiencia (client/Language): en ese me escribe el servidor
	"Rejoin", -- cliente -> servidor: ({ fight, dungeon }) llevo mucho rato sin tocar nada: reconéctame antes de que Roblox me expulse (fight = peleaba en Auto, dungeon = zona en la que estaba)
	"AdminWeather",-- cliente -> servidor: (acción) menú de admin, solo administradores (server/Admin): un id de Config.Weather.Events = poner ese clima ya, "none" = despejar, "auto" = volver al calendario, "next" = el siguiente de la lista
	"AdminCommand", -- cliente -> servidor: (acción, ...) órdenes del menú de admin, solo administradores (server/AdminCommands): "give" (userId o 0 = todos, objeto, cantidad), "sword", "kick" (userId), "goto" / "bring" (userId), "announce" (texto), "banner" (texto), "boost" (stat, multiplicador, minutos), "stopBoost" (stat), "clover" (suerte del trébol de prueba, 0 = quitarlo), "worldBoss" (sacar ya el Jefe del mundo en este servidor); con "all" delante, en todos los servidores
	"AdminBanner", -- servidor -> clientes: (texto) mensaje grande de un administrador (client/BoostHud)
	"WeatherSchedule", -- servidor -> cliente: (hora de GetServerTimeNow) cuándo empieza el siguiente clima; solo se manda a los administradores, los demás no ven la cuenta atrás
	"WorldBoss", -- servidor -> cliente: (tipo, datos) Jefe del mundo: "barrage" ({ spots, radius, at }), "charge" ({ safe, radius, at }), "mega", "launch" ({ from, to, flight }), "boom" (posición), "fall" ({ at }), "rank" ({ list, total, mine, rank, count }), "result" ({ list, rank, rewards? }) (server/WorldBoss)
	"WorldBossRequest", -- cliente -> servidor: ("leave") salir de la arena del Jefe del mundo y volver al portal del hub
	"FuseSwords", -- cliente -> servidor: ({ ids }) fusionar Config.Fusion.Count copias de espada (sin usar ni bloquear) pagando las gemas de FusionInfo.cost (server/Fusion)
	"FusionDone", -- servidor -> cliente: ({ swords = { { sword, metal, size } }, luck }) fusión hecha: las armas que se han metido, para la animación de la máquina (el arma que sale llega por GachaRolled)
	"LevelSword", -- cliente -> servidor: (id, cuántos) subir de nivel esa copia de espada pagando gemas (shared/WeaponLevel); sube los que pueda pagar, hasta esa cantidad (server/WeaponLevels)
}

local Remotes = {}

if RunService:IsServer() then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		Remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
else
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in NAMES do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
