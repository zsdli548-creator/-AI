@echo off
setlocal

set "SCRIPT_PATH=%~dp0Windows-install-codex-claude.ps1"

if not exist "%SCRIPT_PATH%" (
    echo.
    echo Cannot find the PowerShell installer script.
    echo Expected:
    echo   %~dp0Windows-install-codex-claude.ps1
    echo.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
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
