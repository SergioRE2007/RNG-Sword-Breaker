-- Arranque del servidor: cada sistema es un módulo hijo con una función start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- crea los RemoteEvents antes de que nadie los use

require(script.CollisionGroups).start()
require(script.PlayerData).start()
require(script.Passes).start()
require(script.Plots).start()
require(script.Teleport).start()
require(script.Scenery).start()
require(script.MapBounds).start()
require(script.DungeonLobby).start() -- después de Plots y Scenery: corta el suelo de la isla
require(script.TempleEntrance).start() -- después de DungeonLobby: viste su entrada como un templo japonés
require(script.LightLift).start() -- después de DungeonLobby: el ascensor de luz del pozo
require(script.Destructibles).start()
require(script.Movement).start()
require(script.Swords).start()
require(script.Index).start() -- Índice de armas: antes de Gacha, que le apunta cada tirada
require(script.Gacha).start()
require(script.Traits).start()
require(script.ModifierShops).start()
require(script.Gear).start()
require(script.Armor).start()
require(script.Potions).start()
require(script.Dungeons).start()
require(script.Party).start()
require(script.Combat).start()
require(script.Trade).start()
require(script.Shop).start()
require(script.Rebirth).start()
require(script.Leaderboards).start()
require(script.BestRoll).start()
require(script.Missions).start()
require(script.AutoPlay).start() -- autoclicker y Auto de la parcela: después de Plots y Passes
require(script.Admin).start() -- antes de quien obedece órdenes de admin
require(script.Weather).start()
