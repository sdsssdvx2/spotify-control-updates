@echo off
setlocal
cd /d "%~dp0"
echo Spotify Control CSS Provenance Collector v0.1.0
echo ------------------------------------------------
echo Read-only capture of active user.css / colors.css and theme provenance.
echo Spotify can stay open. Nothing in Spotify or Spicetify will be changed.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0css-provenance-collector.ps1" -Action Collect
set "EC=%ERRORLEVEL%"
echo.
if not "%EC%"=="0" (
  echo FAILED. Do not rerun automatically; send the console output.
) else (
  echo DONE. Upload the latest ZIP path printed above.
)
pause
exit /b %EC%
