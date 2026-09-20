@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" %*
set "ERR=%ERRORLEVEL%"
echo %CMDCMDLINE% | find /I "/c" >nul
if not errorlevel 1 pause
exit /b %ERR%
