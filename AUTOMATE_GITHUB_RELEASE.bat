@echo off
setlocal EnableExtensions
title MusicSelektor - Automate GitHub Release
cd /d "%~dp0"

echo ========================================
echo   AUTOMATE GITHUB RELEASE
echo ========================================
echo.
echo Ce script va:
echo - nettoyer les artefacts versionnes inutiles
echo - commit/push sur main
echo - tagger la version v1.2.0
echo - ouvrir la page release GitHub
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AUTOMATE_GITHUB_RELEASE.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo [OK] Publication automatisee terminee.
) else (
  echo [ERREUR] Echec automation ^(code: %EXIT_CODE%^).
)
echo.
pause
exit /b %EXIT_CODE%
