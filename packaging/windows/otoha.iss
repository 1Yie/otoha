#ifndef SourceDir
  #error SourceDir must point to the Windows release directory.
#endif

#ifndef OutputDir
  #error OutputDir must point to the release artifact directory.
#endif

#ifndef MyAppVersion
  #error MyAppVersion must be supplied by the release workflow.
#endif

[Setup]
AppId={{E7A9AF50-1F6D-4E78-AB47-2C3BFD8BDE58}
AppName=Otoha
AppVersion={#MyAppVersion}
AppPublisher=Ingstar
DefaultDirName={autopf}\Otoha
DefaultGroupName=Otoha
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=Otoha-setup-{#MyAppVersion}-x64
SetupIconFile={#SourceDir}\resources\app_icon.ico
UninstallDisplayIcon={app}\otoha.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\Otoha"; Filename: "{app}\otoha.exe"
Name: "{autodesktop}\Otoha"; Filename: "{app}\otoha.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\otoha.exe"; Description: "Launch Otoha"; Flags: nowait postinstall skipifsilent
