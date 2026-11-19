@echo off
REM Run as Administrator. Registers the MH Virtualcam DirectShow
REM filter so Chrome / Edge / Firefox / Zoom / Teams / Discord list it as a camera.
setlocal
cd /d "%~dp0"
if exist "filter\x64\Release\MHVirtualCamFilter.dll" (
    %SystemRoot%\System32\regsvr32.exe "filter\x64\Release\MHVirtualCamFilter.dll"
)
if exist "filter\Release\MHVirtualCamFilter.dll" (
    %SystemRoot%\SysWOW64\regsvr32.exe "filter\Release\MHVirtualCamFilter.dll"
)
echo.
echo Done. Open MHVirtualCam.exe, press "Start Virtual Camera",
echo then select "MH Virtualcam" inside your browser or meeting app.
pause
