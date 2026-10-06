-- Único sitio donde se definen los RemoteEvents. El servidor los crea; el cliente los espera.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Swing", -- cliente -> servidor: he dado un espadazo
	"RollGacha", -- cliente -> servidor: tirar el gacha (gratis, una vez cada Stats.rollTime)
	"EquipSword", -- cliente -> servidor: (id) equipar una copia de espada del inventario
	"SellSword", -- cliente -> servidor: (id) vender una copia que no esté equipada
	"SetAutoSell", -- cliente -> servidor: (rarity) vender solas las espadas de rareza menor; 0 = no
	"Teleport", -- cliente -> servidor: (destino) "hub", "home" (su parcela), "shops" (tiendas del hub) o "dungeon" (portal)
	"BuyUpgrade", -- cliente -> servidor: (name) subir un nivel una mejora de Config.Upgrades
	"BuyAllUpgrades", -- cliente -> servidor: subir todas las mejoras que se puedan pagar
	"SwingFx", -- servidor -> los demás clientes: (player) ese jugador ha dado un espadazo
	"Hit", -- servidor -> clientes: (player, part, position, damage)
	"Broken", -- servidor -> clientes: (player, cframe, size, color, material, reward, gems)
	"GachaRolled", -- servidor -> cliente: (index, kept, luck, source) espada sacada; kept = false si se vendió sola; source = "gacha" o "roca"
	"GachaRevealed", -- cliente -> servidor: ya he destapado mi siguiente tirada rara (para mandar su aura y aviso a todos)
	"GachaAura", -- servidor -> clientes: (player, index, odds) aura en el personaje de quien sacó algo raro para su suerte (odds = rareza / suerte)
	"RollTrait", -- cliente -> servidor: (id) gastar un Cristal de rasgo en esa copia de espada (tienda de Rasgos)
	"RollGrade", -- cliente -> servidor: (id) gastar Config.GradeCost Cristales de grado en un grado para esa copia (tienda de Grados)
	"RevertGrade", -- cliente -> servidor: (id) descartar el grado recién tirado a mano en la forja y volver al anterior
	"ModifierRolled", -- servidor -> cliente: (kind, id, index) resultado de una tirada de rasgo ("traits") o grado ("grades")
	"ToggleGear", -- cliente -> servidor: (artifactIndex) equipar o quitar un artefacto
	"Notice", -- servidor -> cliente: (text, color) aviso en pantalla solo para él
	"Announce", -- servidor -> clientes: (text, color) aviso de algo muy raro
	"Rebirth", -- cliente -> servidor: pagar el siguiente renacimiento (solo monedas, no quita nada)
	"ClaimMission", -- cliente -> servidor: (periodo "daily" o "weekly", id de la misión) cobrar la recompensa de una misión cumplida
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
	"DungeonEvent", -- servidor -> cliente: (tipo, datos) "hurt" (daño recibido) o "result" ({ won, level, loot })
	"EquipArmor", -- cliente -> servidor: (id) poner o quitar una pieza de armadura
	"SalvageArmor", -- cliente -> servidor: (id) desmontar una pieza de armadura a cambio de Cristales de grado
	"PartyRequest", -- cliente -> servidor: (acción, a, b) sala de grupo de las mazmorras: "open" (zona) y "close" miran o dejan de mirar una sala; "create" (zona), "join" (id del grupo), "leave", "ready" (true o false), "start", "solo" (zona), "dungeon" (zona nueva), "option" (nombre, true o false), "kick" (userId), "invite" (userId), "respond" (userId del líder, true o false)
	"PartyState", -- servidor -> cliente: ({ room, mine, parties }) la sala que miras, tu grupo (zona, líder, miembros, listos, opciones, estado) y los grupos abiertos de esa sala; nil = nada que enseñar
	"PartyInvite", -- servidor -> cliente: (userId del líder, nombre del líder, zona) te invitan a un grupo de mazmorra
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
