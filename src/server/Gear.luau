-- Artefactos ("Accesorios" para el jugador): pueden caer al romper objetos y se equipan en unas pocas ranuras.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chance = require(ReplicatedStorage.Shared.Chance)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Gear = {}

-- Se llama cuando el jugador rompe un objeto. Prueba del artefacto más raro al más común, saltando los que ya
-- tiene repetidos hasta el tope (Config.ArtifactCopies; pedido por el usuario: se pueden tener varios iguales,
-- para comerciar con los que sobran). Sin tope, con la suerte alta caería uno con cada objeto.
function Gear.onBroken(player: Player)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local luck = Stats.luck(player)
	for index = #Config.Artifacts, 1, -1 do
		local artifact = Config.Artifacts[index]
		local owned = Stats.copies(data.artifacts, index)
		if owned < Config.ArtifactCopies and Chance.roll(luck / artifact.rarity) then
			PlayerData.edit(player, function(edited)
				table.insert(edited.artifacts, index)
				table.sort(edited.artifacts)
			end)
			Tell.notice(player, artifact.color, "Accessory: {name}!", { name = Lang.t(player, artifact.name) })
			return
		end
	end
end

local function onToggle(player: Player, index: unknown)
	local data = PlayerData.read(player)
	if not data or type(index) ~= "number" or not table.find(data.artifacts, index) then
		return
	end
	local slot = table.find(data.gear, index)
	if not slot and #data.gear >= Config.GearSlots then
		return
	end
	PlayerData.edit(player, function(edited)
		if slot then
			table.remove(edited.gear, slot)
		else
			table.insert(edited.gear, index)
		end
	end)
end

function Gear.start()
	Remotes.ToggleGear.OnServerEvent:Connect(onToggle)
end

return Gear
