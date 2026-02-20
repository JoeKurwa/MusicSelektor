@echo off
setlocal EnableExtensions
title MusicSelektor by JoeKurwa - Start App
cd /d "%~dp0"

call "%~dp0MusicSelektor.bat"
exit /b %ERRORLEVEL%
