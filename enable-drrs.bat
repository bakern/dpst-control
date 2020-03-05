@echo off

echo.
PowerShell.exe -ExecutionPolicy Bypass -File "%~dp0\drrs-control.ps1" -enable
echo.
echo.

pause
