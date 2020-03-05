@echo off

echo.
PowerShell.exe -ExecutionPolicy Bypass -File "%~dp0\drrs-control.ps1" -disable
echo.
echo.

pause
