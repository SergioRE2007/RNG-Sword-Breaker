"""Discord Rich Presence de RNG: Sword Breaker.

Mientras Roblox está abierto en este PC, el perfil de Discord enseña el juego (título, tiempo jugado y dos botones:
unirse al juego y unirse al Discord) en vez de solo "Roblox". Lee su configuración de config.json (junto a este archivo).

Un juego de Roblox no puede hacer esto por sí mismo: Discord solo acepta la presencia de un programa que corra en el
mismo PC que su aplicación de escritorio. Por eso es una herramienta aparte, que cada jugador que la quiera ejecuta en
su ordenador (ver README.md).
"""
import json
import subprocess
import sys
import time
from pathlib import Path

from pypresence import Presence
from pypresence.exceptions import DiscordError, DiscordNotFound, InvalidID, PipeClosed

CONFIG_FILE = Path(__file__).with_name("config.json")
ROBLOX_PROCESSES = ("RobloxPlayerBeta.exe",)  # el cliente de Roblox (no Studio)
CHECK_EVERY = 15  # segundos entre dos vistazos a si Roblox sigue abierto


def load_config() -> dict:
    try:
        config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"Falta {CONFIG_FILE.name}")
    except json.JSONDecodeError as error:
        sys.exit(f"{CONFIG_FILE.name} no es un JSON válido: {error}")
    if not str(config.get("app_id", "")).strip():
        sys.exit(
            "Falta el 'app_id' en config.json: es el Application ID de la aplicación que creas en "
            "https://discord.com/developers/applications (ver README.md)."
        )
    return config


def roblox_running() -> bool:
    output = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout.lower()
    return any(name.lower() in output for name in ROBLOX_PROCESSES)


def build_activity(config: dict, started: int) -> dict:
    activity = {
        "details": config["title"],
        "state": config.get("state", ""),
        "start": started,
        "buttons": [
            {"label": config.get("play_label", "Jugar"), "url": config["game_url"]},
            {"label": config.get("discord_label", "Unirse al Discord"), "url": config["discord_url"]},
        ],
    }
    if config.get("large_image"):
        activity["large_image"] = config["large_image"]
        activity["large_text"] = config["title"]
    return {key: value for key, value in activity.items() if value != ""}


def main() -> None:
    config = load_config()
    rpc = None
    started = 0
    print(f"Discord RPC de {config['title']}: esperando a que se abra Roblox (Ctrl+C para salir).")
    try:
        while True:
            if roblox_running():
                if rpc is None:
                    try:
                        rpc = Presence(str(config["app_id"]))
                        rpc.connect()
                        started = int(time.time())
                        rpc.update(**build_activity(config, started))
                        print("Presencia puesta en Discord.")
                    except DiscordNotFound:
                        print("No encuentro Discord: ábrelo (la aplicación de escritorio). Reintento...")
                        rpc = None
                    except (InvalidID, DiscordError) as error:
                        sys.exit(f"Discord rechazó la presencia: {error}. Revisa el app_id y los botones de config.json.")
                    except (PipeClosed, ConnectionError, OSError) as error:
                        print(f"Se perdió la conexión con Discord ({error}). Reintento...")
                        rpc = None
            elif rpc is not None:
                try:
                    rpc.clear()
                    rpc.close()
                except Exception:  # noqa: BLE001 - al cerrar da igual el motivo
                    pass
                rpc = None
                print("Roblox se cerró: presencia quitada.")
            time.sleep(CHECK_EVERY)
    except KeyboardInterrupt:
        if rpc is not None:
            try:
                rpc.clear()
                rpc.close()
            except Exception:  # noqa: BLE001
                pass
        print("Hasta luego.")


if __name__ == "__main__":
    main()
