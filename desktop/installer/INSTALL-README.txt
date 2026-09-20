Meta Hawladar for Windows - install guide (v31)
================================================

Normal install
--------------
Double-click "Meta Hawladar-1.0.1.msi" (or the .exe). Windows will show a UAC
(administrator) prompt - click Yes. This is expected from v31: the installer
now runs elevated, which is what prevents the "error code 2503 / 2502" seen
on some PCs.

If you still see error 2503 / 2502
----------------------------------
1. Keep "Install-MetaHawladar.bat" in the same folder as the .msi.
2. Right-click "Install-MetaHawladar.bat" -> "Run as administrator".
   It repairs the C:\Windows\Temp permission that causes the error and
   installs the MSI with a log (%TEMP%\MetaHawladar-install.log).

Alternative: run it manually from an elevated Command Prompt:
   msiexec /i "C:\path\to\Meta Hawladar-1.0.1.msi"

No installer at all (portable)
------------------------------
Download "MetaHawladar-windows-portable.zip", unzip anywhere (e.g. Desktop)
and run "Meta Hawladar.exe" inside the folder. Nothing is installed, so
Windows Installer errors cannot happen. App data is kept in
%APPDATA%\MetaHawladar exactly like the installed version.

Upgrading from v30 or older
---------------------------
Older versions were installed "per user". Uninstall the old "Meta Hawladar"
from Settings -> Apps first, then install v31. Your data, accounts and theme
are kept (%APPDATA%\MetaHawladar is not removed by the uninstaller).
