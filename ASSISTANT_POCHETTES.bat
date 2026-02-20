@echo off
setlocal
title MusicSelektor by JoeKurwa - Assistant Pochettes
cd /d "%~dp0"

:menu
cls
echo ============================================
echo   MusicSelektor - Assistant Pochettes
echo ============================================
echo.
echo   1^) Ouvrir le prochain cover manquant
echo   2^) Enregistrer la cover depuis URL (presse-papiers)
echo   3^) Verifier l'avancement des covers
echo   4^) Ouvrir le dossier cible courant
echo   5^) Quitter
echo.
set /p CHOICE=Choix [1-5] : 
echo.

if "%CHOICE%"=="1" goto next
if "%CHOICE%"=="2" goto saveurl
if "%CHOICE%"=="3" goto verify
if "%CHOICE%"=="4" goto opentarget
if "%CHOICE%"=="5" goto end
goto menu

:next
call powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0OpenNextMissingCover.ps1" -OpenBrowser
if errorlevel 1 (
  echo.
  echo [ERREUR] L'option 1 a rencontre un probleme. Voir le message ci-dessus.
  echo.
  pause
  goto menu
)
rem N'affiche les etapes suivantes que si une cible valide existe.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$state='%~dp0.next-cover-target.txt'; if (-not (Test-Path -LiteralPath $state)) { exit 1 }; $p=(Get-Content -LiteralPath $state -Raw -Encoding UTF8).Trim(); if ([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path -LiteralPath $p)) { exit 1 }; exit 0"
if errorlevel 1 (
  echo.
  echo Aucune cible cover chargee. Verification terminee.
  echo.
  pause
  goto menu
)
echo.
echo Etape suivante:
echo  - Copie l'adresse directe de l'image (pas la page Google)
echo  - Puis choisis 2 pour enregistrer cover.jpg automatiquement
echo.
pause
goto menu

:saveurl
echo [DEBUG] Script dir: %~dp0
echo [DEBUG] State file: %~dp0.next-cover-target.txt
echo [DEBUG] Write log : %~dp0MusicSelektor.write-actions.log
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0SaveCoverFromClipboardUrl.ps1"
echo.
echo [DEBUG] Dernieres lignes du write log:
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path -LiteralPath '%~dp0MusicSelektor.write-actions.log') { Get-Content -LiteralPath '%~dp0MusicSelektor.write-actions.log' -Tail 5 } else { Write-Host 'write-actions.log introuvable' }"
echo.
pause
goto menu

:verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VerifyManualCovers.ps1"
echo.
pause
goto menu

:opentarget
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$state='%~dp0.next-cover-target.txt'; if (-not (Test-Path -LiteralPath $state)) { Write-Host 'Aucune cible en memoire. Lance d''abord l''option 1.' -ForegroundColor Yellow; exit 0 }; $p=(Get-Content -LiteralPath $state -Raw -Encoding UTF8).Trim(); if ([string]::IsNullOrWhiteSpace($p)) { Write-Host 'Cible vide. Lance d''abord l''option 1.' -ForegroundColor Yellow; exit 0 }; if (-not (Test-Path -LiteralPath $p)) { Write-Host ('Dossier introuvable: ' + $p) -ForegroundColor Yellow; exit 0 }; Start-Process explorer.exe -ArgumentList ('\"' + $p + '\"'); Write-Host ('Dossier ouvert: ' + $p)"
echo.
pause
goto menu

:end
endlocal
exit /b 0
