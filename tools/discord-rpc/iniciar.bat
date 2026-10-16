@echo off
rem Instala lo que falta (solo la primera vez) y arranca la presencia de Discord.
cd /d "%~dp0"
python -m pip install --quiet -r requirements.txt
python discord_rpc.py
pause
