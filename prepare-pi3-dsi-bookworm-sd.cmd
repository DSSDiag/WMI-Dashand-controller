@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-pi3-dsi-bookworm-sd.ps1" %*
