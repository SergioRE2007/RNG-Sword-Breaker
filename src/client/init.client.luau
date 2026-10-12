-- Arranque del cliente: cada sistema es un módulo hijo con una función start().
require(script.Language).start() -- lo primero: decide el idioma antes de que nadie escriba un texto
require(script.Performance).start()
require(script.Sfx).start()
require(script.Hud).start()
require(script.WorldText).start() -- carteles del mundo y avisos de E en el idioma del jugador
require(script.Potions).start() -- después de Hud (cuelga junto a sus monedas) y antes de Backpack (comparte sus carteles)
require(script.Backpack).start()
require(script.SellMenu).start()
require(script.Index).start()
require(script.Settings).start()
require(script.Rebirth).start()
require(script.Missions).start()
require(script.Tutorial).start() -- tutorial de los primeros minutos: tarjeta y flechas
require(script.Clover).start() -- Trébol de la suerte: elegir objeto y brillo de los que ya lo llevan
require(script.PassShop).start()
require(script.ChatTags).start() -- etiqueta de los pases (VIP) delante del nombre en el chat
require(script.Trade).start()
require(script.ModifierShops).start()
require(script.DropMenu).start() -- menú de botín de mazmorra: después de Potions (usa sus iconos), antes de Dungeons
require(script.Dungeons).start()
require(script.Party).start()
require(script.DungeonMenu).start() -- menú de mazmorras (botón "Mazmorras" de arriba): elegir zona sin buscar su sala
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
-- script.SwingAnim (la animación del espadazo en la mano) ya no se arranca: las armas van solas (OrbitWeapons).
require(script.OrbitWeapons).start() -- las armas equipadas girando y atacando; después de WeaponAura y WeaponMesh, que las visten
require(script.GoldBag).start() -- Bolsa de oro: cartel de cada saco y sus armas depositadas; después de WeaponAura, que las viste
require(script.BagMenu).start() -- menú de la Bolsa de oro (clic en el saco); después de Backpack, que le presta sus carteles
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
require(script.BoostHud).start() -- pastillas de los eventos de admin y mensaje grande; después de Hud
require(script.AdminPanel).start() -- menú de admin (solo para administradores); después de Hud y de Weather
require(script.StationFx).start()
require(script.HitboxDebug).start() -- opción "Ver hitbox" de Ajustes
