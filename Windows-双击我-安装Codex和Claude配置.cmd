@echo off
setlocal

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows-install-codex-claude.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Installation failed with exit code %EXIT_CODE%.
) else (
    echo Installation completed.
)

echo.
pause
exit /b %EXIT_CODE%
