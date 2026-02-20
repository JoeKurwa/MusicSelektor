@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Cleanup Workspace
cd /d "%~dp0"

echo ========================================
echo   MUSICSELEKTOR BY JOEKURWA - CLEANUP
echo ========================================
echo.
echo [1/2] Rangement des artefacts generes...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CleanupWorkspaceArtifacts.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Nettoyage termine.
) else (
    echo [ERREUR] Le nettoyage a echoue ^(code: %EXIT_CODE%^).
)

echo.
echo [2/2] Option purge historique:
echo Pour supprimer les anciens rapports (en gardant 5 recents par famille):
echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\CleanupWorkspaceArtifacts.ps1" -DeleteOld -KeepLatest 5
echo.
echo Fermeture automatique dans 3 secondes...
timeout /t 3 /nobreak >nul
exit /b %EXIT_CODE%
