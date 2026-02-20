@echo off
title MusicSelektor by JoeKurwa - Verify Manual Covers
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VerifyManualCovers.ps1"
pause
