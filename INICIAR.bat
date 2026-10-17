
@echo off
title CHX - Traductor automatico
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0traductor.ps1" -Root "%~dp0"

echo.
echo El traductor CHX se ha detenido.
pause
