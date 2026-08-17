; Inno Setup script for the Windows installer.
;
; Built by .github/workflows/build-windows.yml, which passes the version from
; pubspec.yaml:
;   ISCC.exe /DAppVersion=1.0.0 windows\packaging\export_csv.iss

#define AppName "Excel to CSV"
#define AppExe "export_csv.exe"
#define AppUrl "https://github.com/soemintheinsmt6/export-csv"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Identifies the application to Windows across upgrades. Never change it, or
; an update installs alongside the old copy instead of replacing it.
AppId={{B3DB0D45-5911-470F-A4A7-6B9FE33C8091}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Installs per-user by default, so no administrator prompt is needed. The user
; can still choose an all-users install from the first page.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=ExcelToCSV-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; The whole release bundle: the executable, the Flutter engine DLL, plugin
; DLLs, and the data directory holding the assets and ICU data.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
