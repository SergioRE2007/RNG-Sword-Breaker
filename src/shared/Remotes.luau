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
	"ModifierRolled", -- servidor -> cliente: (kind, id, index) resultado de una tirada de rasgo ("traits") o grado ("grades")
	"ToggleGear", -- cliente -> servidor: (artifactIndex) equipar o quitar un artefacto
	"Notice", -- servidor -> cliente: (text, color) aviso en pantalla solo para él
	"Announce", -- servidor -> clientes: (text, color) aviso de algo muy raro
	"Rebirth", -- cliente -> servidor: pagar el siguiente renacimiento (solo monedas, no quita nada)
	"ClaimMission", -- cliente -> servidor: (periodo "daily" o "weekly", id de la misión) cobrar la recompensa de una misión cumplida
	"AdminSetModifier", -- cliente -> servidor: (kind "traits" o "grades", id de la copia, índice o 0 = quitar) modo admin de pruebas, solo en Studio
	"EnterDungeon", -- cliente -> servidor: (índice de Config.Dungeons) entrar a la mazmorra desde el portal del hub
	"SetDungeonLoop", -- cliente -> servidor: (true o false) repetir la mazmorra sola cada vez que la supere
	"LeaveDungeon", -- cliente -> servidor: salir de la mazmorra en la que está
	"DungeonEvent", -- servidor -> cliente: (tipo, datos) "hurt" (daño recibido) o "result" ({ won, level, loot })
	"EquipArmor", -- cliente -> servidor: (id) poner o quitar una pieza de armadura
	"SalvageArmor", -- cliente -> servidor: (id) desmontar una pieza de armadura a cambio de Cristales de grado
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
