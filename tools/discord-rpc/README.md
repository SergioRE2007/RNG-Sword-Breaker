# Discord RPC de RNG: Sword Breaker

Mientras Roblox está abierto en tu PC, tu perfil de Discord enseña **RNG: Sword Breaker** (título, tiempo jugado) con dos botones: **Jugar** (abre el juego) y **Unirse al Discord** (`discord.gg/6M4Erw84Yw`).

## Lo que hay que saber

- Un juego de Roblox no puede poner esto desde dentro: Discord solo acepta la presencia de un programa que corra en el mismo PC que su aplicación de escritorio. Esta herramienta es ese programa, y **solo vale para quien la ejecute** (cada jugador que quiera su presencia tiene que arrancarla en su PC).
- Necesita la aplicación de escritorio de Discord abierta (no vale la web) y Python 3.
- Roblox sigue apareciendo como juego detectado. Para que en tu perfil solo salga el juego, en Discord → Ajustes → Juegos registrados, desactiva la detección de Roblox.
- Los botones solo los ven los demás, no tú. El botón **Jugar** solo deja entrar a quien tenga acceso al juego: mientras siga en privado, no entrará nadie más.

## Puesta en marcha (una sola vez)

1. Entra en <https://discord.com/developers/applications> → **New Application**. El nombre que le pongas es lo que sale en Discord como "Jugando a …" (por ejemplo `RNG: Sword Breaker`).
2. En **General Information** copia el **Application ID** y pégalo en `app_id` de `config.json`.
3. (Opcional) En **Rich Presence → Art Assets** sube el logo con el nombre `logo` y pon `"large_image": "logo"` en `config.json`.
4. Haz doble clic en `iniciar.bat` (instala `pypresence` la primera vez) y deja la ventana abierta mientras juegas. Solo hace algo cuando detecta `RobloxPlayerBeta.exe`.

## Ajustes (`config.json`)

| Campo | Qué es |
| --- | --- |
| `app_id` | Application ID de Discord (obligatorio). |
| `title` | Primera línea de la presencia. |
| `state` | Segunda línea (puede ir vacía). |
| `game_url` | A dónde lleva el botón de jugar. |
| `discord_url` | Invitación del servidor de Discord. |
| `play_label`, `discord_label` | Texto de los botones (Discord los limita a 32 caracteres). |
| `large_image` | Clave de la imagen subida en Art Assets (vacío = sin imagen). |
