; ============================================================
;  POS Connect Client — Script Inno Setup
;  Génère : POSConnect-Client-Setup-1.0.0.exe
;  Installe uniquement l'application Flutter Windows (UI caisse).
;  Le serveur backend est installé séparément via pos-server.iss.
; ============================================================

#define MyAppName    "POS Connect"
; Valeur de repli uniquement — le CI passe toujours /DMyAppVersion=$ver.
; Sans ce garde, ce #define écrase silencieusement celle fournie par /D.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
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

; Admin requis — nécessaire pour que le certutil -addstore Root du [Run]
; (installation du certificat de signature dans le magasin de confiance
; Windows) s'exécute sans invite UAC supplémentaire.
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
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=.
OutputBaseFilename=POSConnect-Client-Setup-{#MyAppVersion}
SolidCompression=yes
WizardStyle=modern

; Signature Authenticode — la commande réelle est passée par le CI via
; /SPosConnectSignTool=... au moment de la compilation (voir build.yml :
; un petit script sign.cmd écrit sur disque, référencé ici par son chemin
; pour éviter de faire transiter des guillemets imbriqués par PowerShell).
SignTool=PosConnectSignTool

[Languages]
Name: "french";  MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; \
  GroupDescription: "Icônes supplémentaires"

; ── Fichiers à copier ─────────────────────────────────────────────────────────
[Files]
; Application Flutter Windows — "sign" applique PosConnectSignTool à cet
; exe précis pendant la compilation.
Source: "frontend-windows\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion sign
Source: "frontend-windows\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; Icône
Source: "setup-info\pos.ico"; DestDir: "{app}"; Flags: ignoreversion

; Certificat public de signature — installé dans le magasin de confiance
; Windows par le [Run] ci-dessous, puis supprimé (ne reste jamais sur disque).
Source: "setup-info\posconnect-codesign.cer"; DestDir: "{tmp}"; \
  Flags: ignoreversion deleteafterinstall

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
; Fait confiance au certificat de signature — sans ça, SmartScreen avertit
; quand même au premier lancement même si l'exe est signé (auto-signé =
; pas encore dans une chaîne de confiance reconnue par Windows). Une fois
; installé ici, toutes les futures mises à jour signées par ce même
; certificat ne redéclencheront plus jamais l'avertissement sur cette machine.
Filename: "certutil.exe"; \
  Parameters: "-addstore Root ""{tmp}\posconnect-codesign.cer"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "Installation du certificat de signature..."

Filename: "{app}\{#MyAppExeName}"; \
  Description: "Démarrer POS Connect maintenant"; \
  Flags: nowait postinstall skipifsilent

