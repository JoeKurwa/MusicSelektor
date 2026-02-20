@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Regression Checks
cd /d "%~dp0"

echo ========================================
echo   MUSICSELEKTOR BY JOEKURWA - REGRESSION
echo ========================================
echo.
echo Lancement des checks automatiques...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TestRegression.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Aucun echec detecte.
) else (
    echo [ERREUR] Echec regression checks ^(code: %EXIT_CODE%^).
)

echo.
echo Fermeture automatique dans 4 secondes...
timeout /t 4 /nobreak >nul
exit /b %EXIT_CODE%
