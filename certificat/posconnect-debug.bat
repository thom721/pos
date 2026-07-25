@echo off
echo Lancement POS Manager (mode debug)...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0posconnect-manager.ps1"
echo.
echo --- Termine. Code erreur: %ERRORLEVEL% ---
pause
