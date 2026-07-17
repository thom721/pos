; ============================================================
;  POS Connect Client — Script Inno Setup
;  Génère : POSConnect-Client-Setup-1.0.0.exe
;  Installe uniquement l'application Flutter Windows (UI caisse).
;  Le serveur backend est installé séparément via pos-server.iss.
; ============================================================

#define MyAppName    "POS Connect"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "POS Connect"
#define MyAppURL     "https://posconnect.ht"
#define MyAppExeName "pos_connect.exe"

[Setup]
AppId={{B7386C96-FF8E-468F-B8C1-AE821FF39AEF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Program Files — standard pour une application bureau
DefaultDirName={autopf}\POS Connect
DisableDirPage=no
DisableProgramGroupPage=yes

; Pas d'admin obligatoire — élévation UAC proposée si Program Files est choisi
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Architecture 64 bits uniquement
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Fichiers de documentation (chemins relatifs au .iss)
LicenseFile=setup-info\LICENSE.txt
InfoBeforeFile=setup-info\AVANT_INSTALLATION.txt
InfoAfterFile=setup-info\APRES_INSTALLATION.txt

; Icône et output
SetupIconFile=setup-info\pos.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=.
OutputBaseFilename=POSConnect-Client-Setup-{#MyAppVersion}
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "french";  MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; \
  GroupDescription: "Icônes supplémentaires"

; ── Fichiers à copier ─────────────────────────────────────────────────────────
[Files]
; Application Flutter Windows
Source: "frontend-windows\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "frontend-windows\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; Icône
Source: "setup-info\pos.ico"; DestDir: "{app}"; Flags: ignoreversion

; ── Registre Windows ──────────────────────────────────────────────────────────
[Registry]
Root: HKCU; Subkey: "SOFTWARE\POS Connect Client"; \
  ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; \
  Flags: uninsdeletekey
Root: HKCU; Subkey: "SOFTWARE\POS Connect Client"; \
  ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; \
  Flags: uninsdeletevalue

; Chemin exécutable (accessible via Démarrer → Exécuter)
Root: HKCU; \
  Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; \
  Flags: uninsdeletekey
Root: HKCU; \
  Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueName: "Path"; ValueData: "{app}"; \
  Flags: uninsdeletevalue

; ── Icônes ────────────────────────────────────────────────────────────────────
[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
  IconFilename: "{app}\pos.ico"
Name: "{autodesktop}\{#MyAppName}";  Filename: "{app}\{#MyAppExeName}"; \
  IconFilename: "{app}\pos.ico"; Tasks: desktopicon

; ── Commandes après installation ──────────────────────────────────────────────
[Run]
Filename: "{app}\{#MyAppExeName}"; \
  Description: "Démarrer POS Connect maintenant"; \
  Flags: nowait postinstall skipifsilent

