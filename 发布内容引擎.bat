@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-content-engine.ps1"
set "publish_exit=%errorlevel%"
echo.
if not "%publish_exit%"=="0" (
  echo Content publish failed. See the error above.
) else (
  echo Content publish finished. You can restart the Data Garden demo.
)
pause
exit /b %publish_exit%
