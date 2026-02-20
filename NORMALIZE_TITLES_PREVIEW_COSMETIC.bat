@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Normalize Titles Preview (Cosmetic)
cd /d "%~dp0"

if not exist "NormalizeTrackNames.ps1" (
    echo [ERREUR] NormalizeTrackNames.ps1 introuvable.
    timeout /t 3 /nobreak >nul
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NormalizeTrackNames.ps1" -IncludeGeneralCleanup
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Preview COSMETIQUE terminee. Consultez les rapports CSV/JSON generes.
) else (
    echo [ERREUR] Echec preview COSMETIQUE ^(code: %EXIT_CODE%^).
)

timeout /t 2 /nobreak >nul
exit /b %EXIT_CODE%
