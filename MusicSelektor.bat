@echo off
title MusicSelektor by JoeKurwa
cd /d "%~dp0"
cls

echo ========================================
echo   MUSICSELEKTOR BY JOEKURWA
echo ========================================
echo.

echo [OK] Fichiers lanceurs verifies.
echo.

REM Verification des fichiers essentiels
if not exist "CreateLibrary.ps1" (
    echo [ERREUR] CreateLibrary.ps1 introuvable!
    pause
    exit /b 1
)
if not exist "MusicPlayer.ps1" (
    echo [ERREUR] MusicPlayer.ps1 introuvable!
    pause
    exit /b 1
)
if not exist "MusicPlayerGUI.xaml" (
    echo [ERREUR] MusicPlayerGUI.xaml introuvable!
    pause
    exit /b 1
)

REM Scan si Library.json n'existe pas
if not exist "Library.json" (
    echo [1/2] SCAN DE LA BIBLIOTHEQUE
    echo.
    echo ========================================
    echo   INSTRUCTIONS
    echo ========================================
    echo.
    echo Une fenetre va s'ouvrir pour selectionner votre dossier de musique.
    echo.
    echo ETAPES:
    echo   1. Cliquez sur "Parcourir..." dans la fenetre qui s'ouvre
    echo   2. Selectionnez le dossier racine contenant TOUS vos fichiers musicaux
    echo   3. Cliquez sur "OK" pour confirmer
    echo.
    echo IMPORTANT: Selectionnez le dossier RACINE (ex: E:\ ou D:\Musique)
    echo            Le scan va parcourir tous les sous-dossiers automatiquement.
    echo.
    echo Demarrage automatique du scan...
    timeout /t 1 /nobreak >nul
    echo.
    echo Lancement du scanneur...
    echo (Cela peut prendre plusieurs minutes selon la taille de votre collection)
    echo.
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0CreateLibrary.ps1"
    set SCAN_EXIT_CODE=%ERRORLEVEL%
    
    echo.
    echo Code de retour du scan: %SCAN_EXIT_CODE%
    echo.
    
    if %SCAN_EXIT_CODE% NEQ 0 (
        echo [ERREUR] Le scan a echoue avec le code: %SCAN_EXIT_CODE%
        echo.
        if not exist "Library.json" (
            echo Library.json n'a pas ete cree.
            echo.
            echo Le player ne peut pas demarrer sans bibliotheque.
            echo Relancez MusicSelektor.bat et selectionnez un dossier avec des fichiers audio.
            pause
            exit /b 1
        ) else (
            echo ATTENTION: Library.json existe malgre l'erreur.
        )
    )
    
    if not exist "Library.json" (
        echo.
        echo [ATTENTION] Library.json n'a pas ete cree.
        echo Vous avez peut-etre annule la selection du dossier.
        echo.
        echo Le player ne peut pas demarrer sans Library.json.
        echo Relancez MusicSelektor.bat et selectionnez un dossier cette fois.
        pause
        exit /b 1
    )
    
    echo.
    echo ========================================
    echo   SCAN TERMINE AVEC SUCCES!
    echo ========================================
    echo.
    
    powershell -NoProfile -Command "try { $data = Get-Content '%~dp0Library.json' -Raw -Encoding UTF8 | ConvertFrom-Json; $albums = ($data | Select-Object -ExpandProperty FullDir -Unique).Count; Write-Host 'Fichiers indexes:' $data.Count -ForegroundColor Green; Write-Host 'Albums detectes:' $albums -ForegroundColor Cyan; Write-Host '' } catch { Write-Host 'Impossible de lire les statistiques' -ForegroundColor Yellow }"
    
    echo.
    echo Le lecteur va maintenant s'ouvrir...
    echo.
) else (
    echo [1/2] Library.json existe - lancement direct.
    echo.
)

REM Verification finale avant lancement
if not exist "Library.json" (
    echo [ERREUR] Library.json n'existe pas!
    echo Le player ne peut pas demarrer sans bibliotheque.
    pause
    exit /b 1
)

REM [2/2] Lancement du lecteur (sans fenetre CMD)
echo [2/2] Ouverture du lecteur...
echo.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0MusicPlayer.ps1"
set "PLAYER_EXIT=%ERRORLEVEL%"

if not "%PLAYER_EXIT%"=="0" (
    echo [ATTENTION] Echec lancement cache. Tentative de secours...
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MusicPlayer.ps1"
)

echo.
echo ========================================
echo   TERMINE
echo ========================================
echo.
echo Le lecteur devrait maintenant etre ouvert!
echo.
echo Fermeture dans 2 secondes...
timeout /t 2 /nobreak >nul

exit
