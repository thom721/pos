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

; Dossier d'installation — ProgramData (accessible en écriture sans admin)
DefaultDirName={commonappdata}\POS_Connect
DisableDirPage=yes
DisableProgramGroupPage=yes

; Droits admin obligatoires (services Windows, certificats, ports)
PrivilegesRequired=admin

; Architecture 64 bits uniquement
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Fichiers de documentation (chemins relatifs au .iss)
LicenseFile=setup-info\LICENSE.txt
InfoBeforeFile=setup-info\AVANT_INSTALLATION.txt
InfoAfterFile=setup-info\APRES_INSTALLATION.txt

; Icône et output
SetupIconFile=setup-info\pos.ico
UninstallDisplayIcon={app}\pos.ico
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
; Répertoire d'install = {app} = C:\ProgramData\POS_Connect\
Name: "{app}\logs"
Name: "{app}\nginx\logs"
Name: "{app}\nginx\temp"
; POS_Connect_MySQL n'est PAS créé ici : setup-windows.ps1 le crée avec
; des permissions strictes (SYSTEM + Admins uniquement, héritage bloqué).
; Si InnoSetup le créait, il hériterait les ACL de C:\ProgramData (Users lisible)
; ce que MySQL 8 refuse comme datadir (errno 13 "world-writable").

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

; NB : le ZIP MySQL n'est PAS bundlé — setup-windows.ps1 le télécharge
; automatiquement lors de l'installation si absent ($MySqlZipUrl).

; Certificat SSL (à la racine de certificat/, commités dans git)
Source: "server.crt"; DestDir: "{app}\certificat"; Flags: ignoreversion
Source: "server.key"; DestDir: "{app}\certificat"; Flags: ignoreversion

; Icône de l'application
Source: "setup-info\pos.ico"; DestDir: "{app}"; Flags: ignoreversion

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
  ValueData: "{commonappdata}\POS_Connect_MySQL"; Flags: uninsdeletevalue
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
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\pos.ico"
Name: "{autodesktop}\{#MyAppName}";  Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\pos.ico"; \
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

; ── Code Pascal — désinstallation ────────────────────────────────────────────
; Note : le contrôle 64-bit est déjà géré par ArchitecturesAllowed=x64compatible
[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Les données MySQL (C:\ProgramData\POS_Connect_MySQL\) ne sont JAMAIS supprimées
  // automatiquement — elles survivent à toute désinstallation.
  // On propose uniquement de supprimer les logs et la configuration.
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox(
      'Voulez-vous supprimer les logs et la configuration POS Connect ?' + #13#10 +
      '(pos_server.ini, logs d''installation)' + #13#10 + #13#10 +
      'Les données MySQL (base de données) sont conservées dans :' + #13#10 +
      'C:\ProgramData\POS_Connect_MySQL\' + #13#10 + #13#10 +
      'Cliquez Non pour conserver tous les fichiers.',
      mbConfirmation, MB_YESNO
    ) = IDYES then
    begin
      // Supprimer uniquement les fichiers de configuration et logs
      // POS_Connect_MySQL reste intact
      DeleteFile(ExpandConstant('{app}\pos_server.ini'));
      DeleteFile(ExpandConstant('{app}\install.log'));
      DelTree(ExpandConstant('{app}\logs'), True, True, True);
    end;
  end;
end;
