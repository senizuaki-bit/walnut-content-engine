@echo off
setlocal
start "核桃代码世界 Demo" powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0launch-data-garden.ps1"
endlocal
