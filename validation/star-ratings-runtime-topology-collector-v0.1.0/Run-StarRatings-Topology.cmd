@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-StarRatings-Topology.ps1"
set "rc=%ERRORLEVEL%"
echo.
if not "%rc%"=="0" echo Collector failed with exit code %rc%.
pause
exit /b %rc%
