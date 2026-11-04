; Team Drive — Windows installer (Inno Setup 6)
; Compiled in CI: ISCC.exe /DAPP_VERSION=<ver> packaging/windows/teamdrive.iss

[Setup]
AppName=Team Drive
AppVersion={#APP_VERSION}
AppVerName=Team Drive {#APP_VERSION}
AppPublisher=Team Drive
DefaultDirName={autopf}\TeamDrive
DefaultGroupName=Team Drive
OutputDir=installer
OutputBaseFilename=TeamDrive-Setup-{#APP_VERSION}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=assets\icon\windows\app_icon.ico
UninstallDisplayIcon={app}\teamdrive.exe
UninstallDisplayName=Team Drive
PrivilegesRequired=lowest

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Team Drive"; Filename: "{app}\teamdrive.exe"
Name: "{autodesktop}\Team Drive"; Filename: "{app}\teamdrive.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\teamdrive.exe"; Description: "Launch Team Drive"; Flags: nowait postinstall skipifsilent
