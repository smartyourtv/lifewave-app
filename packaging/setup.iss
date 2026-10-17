; =====================================================================
; Inno Setup script for Lifewave AI (Flutter Windows app).
;
; Adapted from the windows-health reusable template for a FLUTTER
; WINDOWS app: the payload is a whole folder (lifewave_app.exe +
; flutter_windows.dll + data\ + plugin DLLs), not a single exe.
;
; Per-user installer: NO admin rights needed to install. Installs into
;   {localappdata}\Programs\LifewaveAI
; creates a Start Menu shortcut (+ optional Desktop shortcut), and
; registers a standard uninstaller (Settings > Apps).
;
; Every per-app value is an Inno preprocessor define with a default;
; build-windows.ps1 / CI passes /D defines read from
; packaging\app-config.json. Each app MUST keep its own MyAppId GUID.
; =====================================================================

#ifndef MyAppId
  #define MyAppId "E4BD9E22-5592-46BA-A1BC-2696C4DC2D88"
#endif
#ifndef MyAppName
  #define MyAppName "Lifewave AI"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "Independent Brand Partner tool"
#endif
#ifndef MyExeName
  #define MyExeName "lifewave_app.exe"
#endif
#ifndef MyInstallFolder
  #define MyInstallFolder "LifewaveAI"
#endif
#ifndef MySetupBaseName
  #define MySetupBaseName "Lifewave-Setup"
#endif
; Path to the Flutter Windows Release folder. Default assumes this
; .iss lives in packaging\ at the lifewave repo root and Flutter wrote
; to app\build\windows\x64\runner\Release\.
#ifndef MySourceDir
  #define MySourceDir "..\app\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\dist"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Per-user install: lowest privileges, no admin prompt to install.
; NOTE: PrivilegesRequiredOverridesAllowed is intentionally OMITTED.
; Inno Setup 6 accepts only "commandline"/"dialog" there; the value
; "no" is invalid and broke the windows-health build in CI.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#MyInstallFolder}
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyExeName}
OutputDir={#MyOutputDir}
OutputBaseFilename={#MySetupBaseName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Unsigned for now: Windows SmartScreen will warn on first run
; ("More info" -> "Run anyway"). Documented in the README.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; The whole Flutter Release folder: the exe, flutter_windows.dll, the
; plugin DLLs, and the data\ tree (flutter_assets, icudtl.dat, app.so).
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyExeName}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
