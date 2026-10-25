@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0css-provenance-collector.ps1" -Action SelfTest
exit /b %ERRORLEVEL%
