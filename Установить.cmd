@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-windows.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
  echo Установка завершилась с ошибкой. Передайте Claude текст из этого окна.
) else (
  echo Готово. Теперь можно открыть папку в Claude.
)
pause
exit /b %EXIT_CODE%
