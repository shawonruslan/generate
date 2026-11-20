@echo off
REM Run as Administrator. Removes the MH Virtualcam registration.
setlocal
cd /d "%~dp0"
if exist "filter\x64\Release\MHVirtualCamFilter.dll" (
    %SystemRoot%\System32\regsvr32.exe /u "filter\x64\Release\MHVirtualCamFilter.dll"
)
if exist "filter\Release\MHVirtualCamFilter.dll" (
    %SystemRoot%\SysWOW64\regsvr32.exe /u "filter\Release\MHVirtualCamFilter.dll"
)
echo Done.
pause
