; ============================================================================
;  Meta Hawladar - Windows installer (Inno Setup 6)
;
;  Produces a real Windows setup program (MetaHawladar-<profile>-windows-x64-
;  setup-v<version>.exe): Program Files install, Start-menu + Desktop shortcut,
;  "Apps & features" entry with uninstaller, in-place upgrades, optional
;  per-user install without admin rights.
;
;  Built automatically by .github/workflows/build-desktop.yml (Inno Setup is
;  pre-installed on the GitHub windows runners). Local build:
;
;    flutter build windows --release --dart-define=BUILD=tarek
;    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ^
;        /DMyAppVersion=27.10.2 /DMyProfile=tarek installer\windows.iss
;
;  Every value below can be overridden from the command line with /D<name>=...
; ============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyProfile
  #define MyProfile "template"
#endif
#ifndef MySourceDir
  ; Flutter release output (relative to this script's folder)
  #define MySourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\build\installer"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "MetaHawladar-" + MyProfile + "-windows-x64-setup-v" + MyAppVersion
#endif

#define MyAppName        "Meta Hawladar"
#define MyAppTagline     "Zedge Content Studio"
#define MyAppPublisher   "Meta Hawladar"
#ifndef MyAppExeName
  #define MyAppExeName "MetaHawladar.exe"
#endif
; One AppId for every profile: installing a different profile on the same PC
; upgrades the existing install instead of leaving two copies behind.
#define MyAppId          "{{6E1F2C4A-8B3D-4F5E-A9C7-2D1B0E9F8A76}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion} ({#MyProfile})
AppPublisher={#MyAppPublisher}
AppComments={#MyAppTagline} - profile {#MyProfile}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
AllowNoIcons=yes
UninstallDisplayName={#MyAppName} ({#MyProfile})
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\assets\icon\app_icon.ico
WizardStyle=modern
WizardSizePercent=110
WizardSmallImageFile=wizard_small_*.bmp
WizardImageFile=wizard_large_*.bmp
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
; 64-bit only (Flutter Windows desktop is x64). `x64compatible` also covers
; Windows-on-ARM devices that run x64 apps through emulation.
#if Ver >= EncodeVer(6,3,0,0)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#else
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
#endif
; Windows 10 or newer (Flutter requirement)
MinVersion=10.0
; Ask "Install for all users (admin) / only for me (no admin)". Default =
; per-user so the app installs even on PCs without administrator rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Close a running app before upgrading, restart it afterwards
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes
ShowLanguageDialog=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup ({#MyProfile})
VersionInfoProductName={#MyAppName}
VersionInfoProductTextVersion={#MyAppVersion} {#MyProfile}
VersionInfoCopyright={#MyAppPublisher}
ChangesAssociations=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start {#MyAppName} automatically when Windows starts"; GroupDescription: "Start-up:"; Flags: unchecked

[InstallDelete]
; Flutter bundles are replaced as a whole - drop stale assets/plugins from an
; older version before the new files are copied (prevents ghost .dll / asset
; leftovers after an upgrade).
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "{#MyAppTagline}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "{#MyAppTagline}"; Tasks: desktopicon
Name: "{autostartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Make sure the app is not running while its files are removed
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""{#MyAppExeName}"" /F /T"; Flags: runhidden; RunOnceId: "KillApp"

[Code]
// Show the profile that was compiled in on the Welcome page so the customer
// can see at a glance which bundle they are installing.
procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption :=
    'This will install {#MyAppName} {#MyAppVersion} ({#MyAppTagline}) on your computer.' + #13#10 + #13#10 +
    'Profile: {#MyProfile}' + #13#10 + #13#10 +
    'It is recommended that you close all other applications before continuing.';
end;
