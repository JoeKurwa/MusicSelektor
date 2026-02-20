@echo off
title MusicSelektor by JoeKurwa - Next Missing Cover
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenNextMissingCover.ps1" -OpenBrowser
pause
