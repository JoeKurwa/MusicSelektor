@echo off
setlocal EnableExtensions
title MusicSelektor - Doublons
cd /d "%~dp0"
chcp 65001 >nul

if not exist "FindDuplicates.ps1" (
    echo [ERREUR] FindDuplicates.ps1 introuvable.
    timeout /t 3 /nobreak >nul
    exit /b 1
)

echo ========================================
echo   MUSICSELEKTOR - DOUBLONS UNIQUEMENT
echo ========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FindDuplicates.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Analyse des doublons terminee.
) else (
    echo [ERREUR] L'analyse des doublons a echoue ^(code: %EXIT_CODE%^).
)

echo Fermeture automatique dans 2 secondes...
timeout /t 2 /nobreak >nul
exit /b %EXIT_CODE%
