@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Scanner
cd /d "%~dp0"

if not exist "CreateLibrary.ps1" (
    echo [ERREUR] CreateLibrary.ps1 introuvable.
    timeout /t 3 /nobreak >nul
    exit /b 1
)

echo ========================================
echo   MUSICSELEKTOR BY JOEKURWA - SCAN UNIQUEMENT
echo ========================================
echo.

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0CreateLibrary.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Scan termine avec succes.
    echo [INFO] Scan uniquement: le lecteur n'est pas lance ici.
    echo [INFO] Utilisez MusicSelektor.bat pour ouvrir l'application.
) else (
    echo [ERREUR] Le scan a echoue ^(code: %EXIT_CODE%^).
)

echo Fermeture automatique dans 2 secondes...
timeout /t 2 /nobreak >nul
exit /b %EXIT_CODE%