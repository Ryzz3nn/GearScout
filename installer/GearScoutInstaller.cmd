@echo off
rem GearScout Installer launcher.
rem Double click this file. It starts the PowerShell + WPF app in this same
rem folder. Nothing is installed on your machine to run this, and nothing
rem is left behind afterward except whatever you choose to install.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GearScoutInstaller.ps1"

rem If the app closed immediately with an error before its window could
rem even open, keep this console visible so the message can be read.
if errorlevel 1 (
    echo.
    echo GearScout Installer closed with an error. See above for details.
    pause
)
