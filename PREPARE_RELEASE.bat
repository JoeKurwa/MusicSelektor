@echo off
setlocal EnableExtensions
title MusicSelektor - Prepare Release
cd /d "%~dp0"

echo ========================================
echo   MUSICSELEKTOR - PREPARE RELEASE
echo ========================================
echo.
echo Nettoyage des artefacts locaux avant publication...
echo.

set "REMOVED=0"

call :DeleteFile "MusicPlayer.startup.trace.log"
call :DeleteFile "MusicPlayer.startup.error.log"
call :DeleteFile "MusicPlayer.startup.out.log"
call :DeleteFile "Library.json"
call :DeleteFile "MusicSelektor_config.json"
call :DeleteFile "CoverSearchCache.json"
call :DeleteFile "AutoCoverReport.json"

if exist "Doublons_MusicSelektor" (
    rmdir /s /q "Doublons_MusicSelektor"
    echo [OK] Dossier supprime : Doublons_MusicSelektor
    set /a REMOVED+=1
)

if exist "Lanceur_Invisible.vbs" (
    attrib -h "Lanceur_Invisible.vbs" >nul 2>&1
    del /f /q "Lanceur_Invisible.vbs" >nul 2>&1
    if not exist "Lanceur_Invisible.vbs" (
        echo [OK] Fichier supprime : Lanceur_Invisible.vbs
        set /a REMOVED+=1
    )
)

echo.
echo Total elements supprimes: %REMOVED%
echo.
echo Verification rapide:
echo - Garder les scripts source et la doc
echo - Verifier le README avant push
echo.
echo Termine.
timeout /t 2 /nobreak >nul
exit /b 0

:DeleteFile
if exist "%~1" (
    del /f /q "%~1" >nul 2>&1
    if not exist "%~1" (
        echo [OK] Fichier supprime : %~1
        set /a REMOVED+=1
    )
)
exit /b 0
