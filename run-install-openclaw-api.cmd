@echo off
setlocal

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-openclaw-api.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Setup failed with exit code %EXIT_CODE%.
) else (
    echo Setup finished.
)

echo.
pause
exit /b %EXIT_CODE%
