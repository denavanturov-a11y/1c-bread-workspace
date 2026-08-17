@echo off
setlocal
set "script_file=%~dp0test-write-preflight.ps1"
set "error_file=%~dp0startup-error.txt"

if not exist "%script_file%" (
  echo Required file test-write-preflight.ps1 was not found.
  echo Extract all files from the ZIP archive first.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%script_file%" 2> "%error_file%"
set "result=%errorlevel%"

if not "%result%"=="0" (
  echo The read-only preflight could not start.
  echo No 1C data was changed.
  echo Send startup-error.txt to the developer.
  pause
)

exit /b %result%
