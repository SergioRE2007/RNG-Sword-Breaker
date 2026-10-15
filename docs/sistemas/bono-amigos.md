# Bono de amigos

Pedido por el usuario (15-10-2026): por cada amigo de Roblox en el mismo servidor, +10 % de suerte y de monedas,
sumado, hasta 7 amigos (los servidores son de 8): con 7, x1,7.

- Números en `Config.Friends` (`Bonus`, `Max`).
- `server/Friends` pregunta `IsFriendsWith` una vez por pareja al entrar cada jugador (se guarda para los dos) y
  publica el número en el atributo `Friends` del `Player`; al salir alguien se recuenta.
- `Stats.friendBonus(player)` lo convierte en multiplicador y entra en `Stats.luck` (suerte de destructibles, no la
  de armas) y en `Stats.coins`. No entra en `tools/equilibrio`, como los pases.
- HUD (`client/Hud`): `HudRoot.Friends`, encima de las gemas, con el logo `grupo` (el de Jugadores del menú de
  admin) y el "+N %" (gris sin amigos, azul con alguno; late al cambiar), y a su lado `HudRoot.InviteFriends`, que
  abre la ventana de invitar de Roblox (`SocialService:PromptGameInvite`). Son bajitos (40) y el menú de la
  izquierda se subió a `0.455` para que no se toquen con el HUD al mínimo.

## Probar

- Desde `Server`: `player:SetAttribute("Friends", 3)` y mirar el HUD y `Stats.luck` / `Stats.coins` (con un
  `require` de `Shared.Stats`, que solo lee atributos).
- La ventana de invitar no sale en Studio: solo en el juego publicado.
