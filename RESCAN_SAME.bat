@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Re-scan (même dossier)
cd /d "%~dp0"

if not exist "CreateLibrary.ps1" (
    echo [ERREUR] CreateLibrary.ps1 introuvable.
    timeout /t 3 /nobreak >nul
    exit /b 1
)

echo ========================================
echo   RE-SCAN DU MÊME DOSSIER
echo ========================================
echo.
echo Re-scan du dossier racine enregistre (sans fenetre de selection).
echo Utile apres avoir ajoute un nouveau dossier ^(ex: divers^).
echo.

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0CreateLibrary.ps1" -Rescan
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Re-scan termine. Actualisez la bibliotheque dans le lecteur
    echo      ^(bouton "ACTUALISER LA BIBLIOTHÈQUE"^) ou relancez MusicSelektor.bat.
) else (
    echo [ERREUR] Le re-scan a echoue ^(code: %EXIT_CODE%^).
    echo Si aucun dossier n'a encore ete enregistre, lancez SCANNER.bat une premiere fois.
)

echo.
echo Fermeture automatique dans 3 secondes...
timeout /t 3 /nobreak >nul
exit /b %EXIT_CODE%
