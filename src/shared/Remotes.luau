-- Único sitio donde se definen los RemoteEvents. El servidor los crea; el cliente los espera.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Swing", -- cliente -> servidor: he dado un espadazo
	"RollGacha", -- cliente -> servidor: (count) tirar el gacha count veces, de Config.Gacha.Counts (hay que estar junto a la máquina del hub)
	"EquipSword", -- cliente -> servidor: (id) equipar una copia de espada del inventario
	"SellSword", -- cliente -> servidor: (id) vender una copia que no esté equipada
	"SetAutoSell", -- cliente -> servidor: (rarity) vender solas las espadas de rareza menor; 0 = no
	"BuyUpgrade", -- cliente -> servidor: (name) subir un nivel una mejora de Config.Upgrades
	"Hit", -- servidor -> clientes: (player, part, position, damage)
	"Broken", -- servidor -> clientes: (player, cframe, size, color, material, reward, gems)
	"SwordObtained", -- servidor -> cliente: (index, kept, source) espada gratis; kept = false si se vendió sola; source = "roca"
	"GachaRolled", -- servidor -> cliente: (results, luck) results = { { index, kept } } de una tirada del gacha
	"RollTrait", -- cliente -> servidor: (id) gastar un Cristal de rasgo en esa copia de espada
	"ToggleGear", -- cliente -> servidor: (artifactIndex) equipar o quitar un artefacto
	"Notice", -- servidor -> cliente: (text, color) aviso en pantalla solo para él
	"Announce", -- servidor -> clientes: (text, color) aviso de algo muy raro
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
