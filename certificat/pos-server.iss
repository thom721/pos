; ============================================================
;  POS Connect — Script Inno Setup
;  Génère : POSConnect-Setup-1.0.0.exe
; ============================================================

#define MyAppName    "POS Connect"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "POS Connect"
#define MyAppURL     "https://posconnect.ht"
#define MyAppExeName "posconnect-server.exe"

[Setup]
AppId={{B21FF9C0-EEE3-4C72-BC41-F50544579485}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Dossier d'installation
DefaultDirName={autopf}\POS_Connect
DisableDirPage=yes
DisableProgramGroupPage=yes

; Droits admin obligatoires (services Windows, certificats, ports)
PrivilegesRequired=admin

; Architecture 64 bits uniquement
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Fichiers de documentation (chemins relatifs au .iss)
LicenseFile=LICENSE.txt
InfoBeforeFile=AVANT_INSTALLATION.txt
InfoAfterFile=APRES_INSTALLATION.txt

; Icône et output
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=.
OutputBaseFilename=POSConnect-Setup-{#MyAppVersion}
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "french";  MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; \
  GroupDescription: "Icônes supplémentaires"; Flags: unchecked

; ── Dossiers à créer ──────────────────────────────────────────────────────────
[Dirs]
; Données modifiables sans droits admin (pos_server.ini, logs, DB SQLite)
Name: "{commonappdata}\POS_Connect"
Name: "{app}\logs"
Name: "{app}\nginx\logs"
Name: "{app}\nginx\temp"

; ── Fichiers à copier ─────────────────────────────────────────────────────────
[Files]
; Serveur API compilé (Nuitka)
Source: "backend-windows\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "backend-windows\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; Nginx
Source: "nginx\*"; DestDir: "{app}\nginx"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; NSSM (gestionnaire de services)
Source: "nssm\*"; DestDir: "{app}\nssm"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; MySQL zip (extrait par le script PowerShell)
Source: "mysql-8.0.41-winx64.zip"; DestDir: "{app}"; Flags: ignoreversion

; Certificat SSL
Source: "setup-info\server.crt"; DestDir: "{app}\certificat"; Flags: ignoreversion
Source: "setup-info\server.key"; DestDir: "{app}\certificat"; Flags: ignoreversion

; Script d'installation des services (appelé en [Run])
Source: "setup-info\setup-windows.ps1"; DestDir: "{app}"; Flags: ignoreversion

; ── Registre Windows ──────────────────────────────────────────────────────────
[Registry]
; Informations application (utilise {app} au lieu de chemins hardcodés)
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "DisplayName"; ValueData: "{#MyAppName}"; \
  Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; \
  Flags: uninsdeletevalue
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; \
  Flags: uninsdeletevalue
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "DataPath"; \
  ValueData: "{commonappdata}\POS_Connect"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "Publisher"; ValueData: "{#MyAppPublisher}"; \
  Flags: uninsdeletevalue
Root: HKLM; Subkey: "SOFTWARE\POS Connect"; \
  ValueType: string; ValueName: "Website"; ValueData: "{#MyAppURL}"; \
  Flags: uninsdeletevalue

; Chemin exécutable (accessible via Démarrer → Exécuter)
Root: HKLM; \
  Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; \
  Flags: uninsdeletekey
Root: HKLM; \
  Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueName: "Path"; ValueData: "{app}"; \
  Flags: uninsdeletevalue

; Event Log
Root: HKLM; \
  Subkey: "SYSTEM\CurrentControlSet\Services\EventLog\Application\POS Connect"; \
  ValueType: string; ValueName: "EventMessageFile"; \
  ValueData: "C:\Windows\System32\mscoree.dll"; Flags: uninsdeletekeyifempty
Root: HKLM; \
  Subkey: "SYSTEM\CurrentControlSet\Services\EventLog\Application\POS Connect"; \
  ValueType: dword; ValueName: "TypesSupported"; ValueData: $00000007; \
  Flags: uninsdeletevalue

; ── Icônes ────────────────────────────────────────────────────────────────────
[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}";  Filename: "{app}\{#MyAppExeName}"; \
  Tasks: desktopicon

; ── Commandes après installation ──────────────────────────────────────────────
[Run]
; Tout est géré par setup-windows.ps1 : pos_server.ini, certificat SSL, services NSSM
Filename: "powershell.exe"; \
  Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{app}\setup-windows.ps1"""; \
  StatusMsg: "Configuration de POS Connect (services, certificat, base de données)..."; \
  Flags: runhidden waituntilterminated

; Proposer de lancer l'app après installation
Filename: "{app}\{#MyAppExeName}"; \
  Description: "Démarrer POS Connect maintenant"; \
  Flags: nowait postinstall skipifsilent

; ── Commandes à la désinstallation ────────────────────────────────────────────
[UninstallRun]
; Arrêter et supprimer les services Windows (une seule ligne, pas de \ imbriqués)
Filename: "powershell.exe"; Parameters: "-NonInteractive -ExecutionPolicy Bypass -Command ""Stop-Service 'POS_Connect_Nginx','POS_Connect_API','POS_Connect_MySQL' -Force -ErrorAction SilentlyContinue; & '{app}\nssm\nssm.exe' remove POS_Connect_Nginx confirm; & '{app}\nssm\nssm.exe' remove POS_Connect_API confirm; & '{app}\nssm\nssm.exe' remove POS_Connect_MySQL confirm"""; Flags: runhidden waituntilterminated

; ── Code Pascal — vérifications avant installation ───────────────────────────
[Code]
function InitializeSetup(): Boolean;
begin
  // Vérifie Windows 10 minimum
  if not IsWindows64BitInstallMode then
  begin
    MsgBox(
      'POS Connect nécessite Windows 10 ou 11 (64 bits).' + #13#10 +
      'Votre système n''est pas compatible.',
      mbError, MB_OK
    );
    Result := False;
    Exit;
  end;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Proposer de supprimer les données utilisateur à la désinstallation
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox(
      'Voulez-vous supprimer les données POS Connect ?' + #13#10 +
      '(base de données, configuration, logs)' + #13#10 + #13#10 +
      'Cliquez Non pour conserver vos données.',
      mbConfirmation, MB_YESNO
    ) = IDYES then
    begin
      DelTree(ExpandConstant('{commonappdata}\POS_Connect'), True, True, True);
    end;
  end;
end;
