@echo off
rem Double-click entry point on a new PC. Runs restore.ps1 with the stock Windows PowerShell; execution
rem policy is bypassed for this one process only. Arguments are passed on (for example -DryRun).
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1" %*
set result=%errorlevel%
echo.
pause
exit /b %result%
