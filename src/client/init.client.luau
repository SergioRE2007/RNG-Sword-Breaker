-- Arranque del cliente: cada sistema es un módulo hijo con una función start().
require(script.Performance).start()
require(script.Sfx).start()
require(script.Hud).start()
require(script.Potions).start() -- después de Hud (cuelga junto a sus monedas) y antes de Backpack (comparte sus carteles)
require(script.Backpack).start()
require(script.SellMenu).start()
require(script.Index).start()
require(script.Settings).start()
require(script.Rebirth).start()
require(script.Missions).start()
require(script.PassShop).start()
require(script.ChatTags).start() -- etiqueta de los pases (VIP) delante del nombre en el chat
require(script.Trade).start()
require(script.ModifierShops).start()
require(script.DropMenu).start() -- menú de botín de mazmorra: después de Potions (usa sus iconos), antes de Dungeons
require(script.Dungeons).start()
require(script.Party).start()
require(script.DayCycle).start() -- antes de DungeonFx, que lo enciende y apaga según la zona
require(script.MapLights).start()
require(script.DungeonFx).start()
require(script.RoomSigns).start()
require(script.GachaRoll).start()
require(script.RollReveal).start()
require(script.SkillTree).start()
require(script.Effects).start()
require(script.WeaponAura).start()
require(script.WeaponMesh).start()
require(script.SwingAnim).start()
require(script.SwordController).start()
require(script.WeaponSlot).start()
require(script.AutoPlay).start() -- autoclicker y Auto, a los lados de la casilla del arma: después de WeaponSlot y PassShop
require(script.Rejoin).start() -- reconexión antes de la expulsión por inactividad; después de Dungeons
require(script.Ambience).start()
require(script.ObjectAmbient).start()
require(script.ObjectInfo).start()
require(script.ArmorAura).start()
require(script.PotionFx).start()
require(script.JapanFx).start()
require(script.Weather).start() -- después de DayCycle, DungeonFx y JapanFx: mezcla su luz y amaina sus pétalos
require(script.Soundscape).start() -- ambiente de fondo; después de DayCycle y DungeonFx: suena según la hora y la zona
require(script.AdminPanel).start() -- menú de admin (solo para administradores); después de Hud y de Weather
require(script.StationFx).start()
require(script.HitboxDebug).start() -- opción "Ver hitbox" de Ajustes
