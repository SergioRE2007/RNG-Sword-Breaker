"""
Publica el texto de novedades.md en el canal de actualizaciones (🔔・updates).

Uso:
  python publicar_novedades.py                 -> solo enseña cómo quedará (no manda nada)
  python publicar_novedades.py --enviar        -> lo publica (pega el token cuando te lo pida)
  python publicar_novedades.py --enviar --canal anuncios --archivo otro.md

Opciones:
  --canal    parte del nombre del canal (por defecto "updates")
  --archivo  texto a publicar (por defecto novedades.md, junto a este script)

Discord corta los mensajes a 2000 caracteres: si el texto es más largo se parte
por bloques (en blanco) en varios mensajes. No menciona a nadie (ni @everyone).
"""

import argparse
import getpass
import os
from pathlib import Path

GUILD_ID = 1558491782734676169
LIMITE = 1900  # margen bajo los 2000 caracteres de Discord


def partir(texto: str) -> list[str]:
    """Parte el texto por bloques separados por una línea en blanco, sin pasar de LIMITE."""
    partes, actual = [], ""
    for bloque in texto.strip().split("\n\n"):
        if actual and len(actual) + 2 + len(bloque) > LIMITE:
            partes.append(actual)
            actual = bloque
        else:
            actual = f"{actual}\n\n{bloque}" if actual else bloque
    if actual:
        partes.append(actual)
    return partes


def main():
    parser = argparse.ArgumentParser(description="Publica novedades.md en Discord")
    parser.add_argument("--enviar", action="store_true", help="publicar de verdad (sin esto, solo vista previa)")
    parser.add_argument("--canal", default="updates", help='parte del nombre del canal (por defecto "updates")')
    parser.add_argument("--archivo", default=str(Path(__file__).with_name("novedades.md")))
    args = parser.parse_args()

    texto = Path(args.archivo).read_text(encoding="utf-8")
    partes = partir(texto)

    print(f"--- Vista previa ({len(partes)} mensaje/s) ---")
    for numero, parte in enumerate(partes, 1):
        print(f"\n[{numero}/{len(partes)}] ({len(parte)} caracteres)\n{parte}")
    if not args.enviar:
        print("\nNo se ha enviado nada. Añade --enviar para publicarlo.")
        return

    import discord  # aquí, para que la vista previa funcione aunque falte la librería

    token = os.environ.get("DISCORD_TOKEN") or getpass.getpass(
        "Pega el token del bot (no se verá al escribir) y pulsa Enter: ").strip()
    client = discord.Client(intents=discord.Intents.default())

    @client.event
    async def on_ready():
        guild = client.get_guild(GUILD_ID)
        try:
            if guild is None:
                print("❌ El bot no está en el servidor.")
                return
            canal = next((c for c in guild.text_channels if args.canal.lower() in c.name.lower()), None)
            if canal is None:
                print(f'❌ No encuentro ningún canal de texto con "{args.canal}" en el nombre.')
                return
            for parte in partes:
                await canal.send(parte, allowed_mentions=discord.AllowedMentions.none())
            print(f"✅ Publicado en #{canal.name} ({len(partes)} mensaje/s).")
        except discord.Forbidden:
            print("❌ Faltan permisos: el bot necesita poder escribir en ese canal.")
        except discord.HTTPException as e:
            print("❌ Error de Discord:", e)
        finally:
            await client.close()

    try:
        client.run(token, log_handler=None)
    except discord.LoginFailure:
        print("❌ Token inválido.")


if __name__ == "__main__":
    main()
