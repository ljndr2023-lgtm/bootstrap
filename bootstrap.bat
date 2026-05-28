@echo off
title Bootstrap Windows
cd /d "%~dp0"

echo ========================================
echo   BOOTSTRAP WINDOWS
echo   Chrome + Steam + Epic + Drivers
echo ========================================
echo.

:: Buscar PowerShell y ejecutar script
where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    pwsh.exe -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
) else (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
)

pause
