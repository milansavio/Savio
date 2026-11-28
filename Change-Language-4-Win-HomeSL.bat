@echo off
title Tools Thay Doi Ngon Ngu Windows - Pure PowerShell Launcher (by Savio)
setlocal
set "LOCAL_PS1=%~dp0Change-Language-4-Win-HomeSL.ps1"
if exist "%LOCAL_PS1%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_PS1%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/milansavio/Savio/main/Change-Language-4-Win-HomeSL.ps1' | iex"
)
exit /b %errorlevel%
