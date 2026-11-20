#define MyAppName "MH Advanced Tool"
#define MyAppVersion "3.1.2"
#define MyAppExeName "MHVirtualCam.exe"
#define MyHubExeName "browser\MHBrowser.exe"

[Setup]
AppId={{D4E8A120-7F3B-4C9E-8A12-5B6E9D0C3A41}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=MH Advanced Tool
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=MH-Advanced-Tool-Setup
SetupIconFile=..\app\app.ico
UninstallDisplayIcon={app}\{#MyHubExeName}
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

[Dirs]
Name: "{commonappdata}\MHVirtualCam"

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\filter\x64\Release\MHVirtualCamFilter.dll"; DestDir: "{app}\filter\x64"; Flags: ignoreversion
Source: "..\filter\Release\MHVirtualCamFilter.dll"; DestDir: "{app}\filter\x86"; Flags: ignoreversion
Source: "..\mf\x64\Release\MHVirtualCamMF.dll"; DestDir: "{app}\mf"; Flags: ignoreversion
Source: "..\mf\x64\Release\MHVirtualCamReg.exe"; DestDir: "{app}\mf"; Flags: ignoreversion
Source: "..\publish_browser\*"; DestDir: "{app}\browser"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\vpn\openvpn\*"; DestDir: "{app}\vpn\openvpn"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\vpn\wireguard\*"; DestDir: "{app}\vpn\wireguard"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyHubExeName}"
Name: "{group}\MH Virtual Camera"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyHubExeName}"; Tasks: desktopicon
Name: "{autodesktop}\MH Virtual Camera"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\vpn\openvpn\tap-windows-setup.exe"; Parameters: "/S"; StatusMsg: "Installing OpenVPN TAP-Windows6 virtual network driver..."; Flags: runhidden waituntilterminated skipifdoesntexist
Filename: "{sys}\icacls.exe"; Parameters: """{commonappdata}\MHVirtualCam"" /grant ""*S-1-5-32-545:(OI)(CI)M"" /grant ""*S-1-5-19:(OI)(CI)R"""; StatusMsg: "Configuring shared frame folder permissions..."; Flags: runhidden waituntilterminated
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\filter\x64\MHVirtualCamFilter.dll"""; StatusMsg: "Registering 64-bit DirectShow filter..."; Flags: runhidden waituntilterminated
Filename: "{syswow64}\regsvr32.exe"; Parameters: "/s ""{app}\filter\x86\MHVirtualCamFilter.dll"""; StatusMsg: "Registering 32-bit DirectShow filter..."; Flags: runhidden waituntilterminated
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\mf\MHVirtualCamMF.dll"""; StatusMsg: "Registering Windows 11 Media Foundation source..."; Flags: runhidden waituntilterminated
Filename: "{app}\mf\MHVirtualCamReg.exe"; Parameters: "--install"; StatusMsg: "Registering Windows 11 Virtual Camera..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyHubExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\mf\MHVirtualCamReg.exe"; Parameters: "--uninstall"; StatusMsg: "Removing Windows 11 Virtual Camera..."; Flags: runhidden waituntilterminated; RunOnceId: "UnregMFVCam"
Filename: "{sys}\regsvr32.exe"; Parameters: "/u /s ""{app}\mf\MHVirtualCamMF.dll"""; StatusMsg: "Unregistering Media Foundation source..."; Flags: runhidden waituntilterminated; RunOnceId: "UnregMFDLL"
Filename: "{sys}\regsvr32.exe"; Parameters: "/u /s ""{app}\filter\x64\MHVirtualCamFilter.dll"""; StatusMsg: "Unregistering 64-bit DirectShow filter..."; Flags: runhidden waituntilterminated; RunOnceId: "UnregX64"
Filename: "{syswow64}\regsvr32.exe"; Parameters: "/u /s ""{app}\filter\x86\MHVirtualCamFilter.dll"""; StatusMsg: "Unregistering 32-bit DirectShow filter..."; Flags: runhidden waituntilterminated; RunOnceId: "UnregX86"
