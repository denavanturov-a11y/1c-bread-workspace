@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0connector-check.ps1"
if errorlevel 1 (
  echo The diagnostic tool could not start.
  echo No 1C data was changed.
  pause
)
