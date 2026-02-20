@echo off
title MusicSelektor by JoeKurwa - Save Cover From Clipboard URL
cd /d "%~dp0"
echo Copie l'adresse directe de l'image (jpg/png), puis appuie sur une touche...
pause >nul
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0SaveCoverFromClipboardUrl.ps1"
pause
