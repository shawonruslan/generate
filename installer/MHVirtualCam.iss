#define MyAppName "MH Virtualcam"
#define MyAppVersion "1.0.0"
#define MyAppExeName "MHVirtualCam.exe"

[Setup]
AppId={{D4E8A120-7F3B-4C9E-8A12-5B6E9D0C3A41}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=MH Virtualcam
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=MH-Virtualcam-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\filter\x64\Release\MHVirtualCamFilter.dll"; DestDir: "{app}\filter\x64"; Flags: ignoreversion
Source: "..\filter\Release\MHVirtualCamFilter.dll"; DestDir: "{app}\filter\x86"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\filter\x64\MHVirtualCamFilter.dll"""; StatusMsg: "Registering 64-bit virtual camera filter..."; Flags: runhidden waituntilterminated
Filename: "{syswow64}\regsvr32.exe"; Parameters: "/s ""{app}\filter\x86\MHVirtualCamFilter.dll"""; StatusMsg: "Registering 32-bit virtual camera filter..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\regsvr32.exe"; Parameters: "/u /s ""{app}\filter\x64\MHVirtualCamFilter.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "UnregX64"
Filename: "{syswow64}\regsvr32.exe"; Parameters: "/u /s ""{app}\filter\x86\MHVirtualCamFilter.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "UnregX86"
