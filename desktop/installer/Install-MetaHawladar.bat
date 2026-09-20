@echo off
:: Meta Hawladar - elevated installer helper (v31)
:: Fixes Windows Installer error 2503 / 2502 ("unexpected error installing this package").
:: That error happens when msiexec runs without admin rights and cannot write to C:\Windows\Temp.
:: This script (1) repairs the Temp folder permission and (2) runs the MSI elevated.
setlocal EnableDelayedExpansion
cd /d "%~dp0"

:: --- find the MSI sitting next to this .bat
set "MSI="
for %%f in ("%~dp0*.msi") do set "MSI=%%~ff"
if not defined MSI (
    echo [ERROR] No .msi file found next to this script. Keep Install-MetaHawladar.bat in the same folder as the MSI.
    pause
    exit /b 1
)

:: --- re-launch elevated if we are not admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator permission...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo === Meta Hawladar installer ===
echo MSI: %MSI%
echo.

:: --- 1) repair the permission that causes 2503/2502 (harmless if already fine)
echo Repairing Windows\Temp permissions...
icacls "%WINDIR%\Temp" /grant "*S-1-5-32-545:(OI)(CI)F" /T /C /Q >nul 2>&1
icacls "%WINDIR%\Temp" /grant "*S-1-5-11:(OI)(CI)F" /T /C /Q >nul 2>&1

:: --- 2) make sure the Windows Installer service is running
sc query msiserver | find "RUNNING" >nul 2>&1
if %errorlevel% neq 0 (
    echo Starting Windows Installer service...
    net start msiserver >nul 2>&1
)

:: --- 3) run the installer elevated, with a log for support
set "LOG=%TEMP%\MetaHawladar-install.log"
echo Installing (log: %LOG%)...
msiexec /i "%MSI%" /L*v "%LOG%"
set "RC=%errorlevel%"

echo.
if "%RC%"=="0" (
    echo [OK] Meta Hawladar installed. Find it in the Start menu.
) else if "%RC%"=="1602" (
    echo [CANCELLED] Installation was cancelled.
) else if "%RC%"=="3010" (
    echo [OK] Installed - a restart is required to finish.
) else (
    echo [FAILED] msiexec exit code %RC%. Send this log file for support: %LOG%
)
echo.
pause
endlocal
