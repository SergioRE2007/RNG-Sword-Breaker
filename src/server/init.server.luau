-- Arranque del servidor: cada sistema es un módulo hijo con una función start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- crea los RemoteEvents antes de que nadie los use

require(script.CollisionGroups).start()
require(script.Language).start() -- el idioma que dice cada cliente (atributo "Lang"), para los textos del servidor
require(script.PlayerData).start()
require(script.Passes).start()
require(script.Friends).start() -- bono de amigos: cuántos amigos tiene cada uno en el servidor (atributo "Friends")
require(script.Policy).start() -- normas por país: tréboles de Robux y comercio
require(script.Plots).start()
require(script.Teleport).start()
require(script.Scenery).start()
require(script.MapBounds).start()
require(script.DungeonLobby).start() -- después de Plots y Scenery: corta el suelo de la isla
require(script.TempleEntrance).start() -- después de DungeonLobby: viste su entrada como un templo japonés
require(script.LightLift).start() -- después de DungeonLobby: el ascensor de luz del pozo
require(script.Destructibles).start()
require(script.Movement).start()
-- script.Swords (el arma en la mano) ya no se arranca: las armas equipadas las dibuja cada cliente (client/OrbitWeapons).
require(script.Index).start() -- Índice de armas: antes de Gacha, que le apunta cada tirada
require(script.Gacha).start()
require(script.GoldBag).start() -- Bolsa de oro: después de Plots (pone un saco detrás de cada parcela)
require(script.Traits).start()
require(script.ModifierShops).start()
require(script.Fusion).start() -- máquina de fusión del hub: después de ModifierShops (usa su cartel) y de Gacha
require(script.WeaponLevels).start() -- subir de nivel las armas con gemas
require(script.Gear).start()
require(script.Armor).start()
require(script.Potions).start()
require(script.DropMenu).start() -- antes de Dungeons: le ofrece el botín retenido al acabar la partida
require(script.Dungeons).start()
require(script.Party).start()
require(script.WorldBoss).start() -- Jefe del mundo: portal del hub y su arena; después de Plots y Scenery (usa workspace.Map)
require(script.Combat).start()
require(script.Trade).start()
require(script.Shop).start()
require(script.Rebirth).start()
require(script.Leaderboards).start()
require(script.BestRoll).start()
require(script.Missions).start()
require(script.Tutorial).start() -- tutorial de los primeros minutos: después de Missions
require(script.TicketShop).start() -- lo que se compra con tickets en el puesto de Misiones
require(script.Clover).start() -- Trébol de la suerte: después de Destructibles
require(script.Codes).start() -- códigos de regalo de la Tienda
require(script.DailyRewards).start() -- recompensas por tiempo jugado y por días seguidos
require(script.Products).start() -- productos de Robux (ProcessReceipt)
require(script.AutoPlay).start() -- autoclicker y Auto de la parcela: después de Plots y Passes
require(script.Rejoin).start() -- reconexión antes de la expulsión por inactividad: después de Party, Dungeons y AutoPlay
require(script.Admin).start() -- antes de quien obedece órdenes de admin
require(script.Broadcast).start() -- avisos entre servidores, para las órdenes de admin de "todos los servidores"
require(script.AdminEvents).start() -- eventos de admin (multiplicadores para todos) y mensaje grande
require(script.AdminCommands).start() -- regalar, echar, ir y avisar desde el menú de admin
require(script.Weather).start()
