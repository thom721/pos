<#
.SYNOPSIS
    Configure POS Connect après installation Inno Setup.
    - Télécharge MySQL si le ZIP est absent
    - Extrait et installe MySQL localement dans {app}\mysql\ (port 3307)
    - Crée pos_db + pos_user avec mot de passe
    - Installe les services Windows via NSSM
    - Écrit pos_server.ini dans ProgramData
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Chemins ────────────────────────────────────────────────────────────────────
$InstallDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir     = "$env:ProgramData\POS_Connect"
$NssmExe     = "$InstallDir\nssm\nssm.exe"
$NginxExe    = "$InstallDir\nginx\nginx.exe"
$ApiExe      = "$InstallDir\posconnect-server.exe"
$MySqlVersion = "8.0.41"
$MySqlZip    = "$InstallDir\mysql-$MySqlVersion-winx64.zip"
$MySqlZipUrl = "https://downloads.mysql.com/archives/get/p/23/file/mysql-$MySqlVersion-winx64.zip"
$MySqlDir    = "$InstallDir\mysql"
# Données MySQL dans un dossier séparé — survivent à toute suppression de POS_Connect
$MySqlData   = "$env:ProgramData\POS_Connect_MySQL"
$MyIni       = "$MySqlDir\my.ini"
$MySqlBinDir = "$MySqlDir\bin"
$MySqlPort   = 3307
$IniTarget   = "$DataDir\pos_server.ini"
$LogFile     = "$DataDir\install.log"

# ── Journalisation ─────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

Write-Log "=== Début de la configuration POS Connect ==="
Write-Log "InstallDir : $InstallDir"
Write-Log "DataDir    : $DataDir"

# ── Vérification droits Administrateur ────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "ERREUR : ce script doit etre execute en tant qu'Administrateur." "ERROR"
    Write-Log "Relancez posconnect-server.exe via un terminal Administrateur." "ERROR"
    Write-Log "=== Configuration POS Connect terminee (erreur droits) ===" "ERROR"
    exit 1
}

# ── 0. Visual C++ Redistributable (requis par MySQL 8) ────────────────────────
$VcRuntime = "$env:SystemRoot\System32\vcruntime140.dll"
if (-not (Test-Path $VcRuntime)) {
    Write-Log "vcruntime140.dll absent — installation du Visual C++ Redistributable..." "WARN"
    $VcRedist = "$InstallDir\vcredist\vc_redist.x64.exe"
    if (-not (Test-Path $VcRedist)) {
        Write-Log "Téléchargement vc_redist.x64.exe depuis Microsoft..."
        $VcRedistDir = "$InstallDir\vcredist"
        New-Item -ItemType Directory -Force -Path $VcRedistDir | Out-Null
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            (New-Object System.Net.WebClient).DownloadFile(
                "https://aka.ms/vs/17/release/vc_redist.x64.exe",
                $VcRedist
            )
            Write-Log "vc_redist.x64.exe téléchargé"
        } catch {
            Write-Log "Impossible de télécharger vc_redist : $_" "WARN"
        }
    }
    if (Test-Path $VcRedist) {
        Write-Log "Installation vc_redist.x64.exe (silencieux)..."
        Start-Process -FilePath $VcRedist -ArgumentList "/install /quiet /norestart" `
            -Wait -NoNewWindow
        if (Test-Path $VcRuntime) {
            Write-Log "Visual C++ Redistributable installé avec succès"
        } else {
            Write-Log "vcruntime140.dll toujours absent après install — MySQL pourrait échouer" "WARN"
        }
    }
} else {
    Write-Log "Visual C++ Redistributable OK ($VcRuntime)"
}

# ── 1. Certificat SSL ──────────────────────────────────────────────────────────
$CertFile = "$InstallDir\certificat\server.crt"
if (Test-Path $CertFile) {
    try {
        $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertFile)
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        Write-Log "Certificat SSL installé"
    } catch {
        Write-Log "Certificat SSL : $_" "WARN"
    }
} else {
    Write-Log "Certificat absent ($CertFile) — ignoré" "WARN"
}

# ── 2. MySQL : télécharger si ZIP absent ──────────────────────────────────────
if (-not (Test-Path "$MySqlBinDir\mysqld.exe")) {
    if (-not (Test-Path $MySqlZip)) {
        Write-Log "MySQL ZIP absent — téléchargement depuis MySQL officiel..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($MySqlZipUrl, $MySqlZip)
            $sizeMb = [math]::Round((Get-Item $MySqlZip).Length / 1MB, 1)
            Write-Log "MySQL $MySqlVersion téléchargé ($sizeMb Mo)"
        } catch {
            Write-Log "Impossible de télécharger MySQL : $_" "WARN"
        }
    }

    # Extraire
    if (Test-Path $MySqlZip) {
        Write-Log "Extraction de MySQL dans $InstallDir ..."
        try {
            Expand-Archive -Path $MySqlZip -DestinationPath $InstallDir -Force
            $Extracted = Get-ChildItem -Path $InstallDir -Directory -Filter "mysql-*" |
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($Extracted -and $Extracted.FullName -ne $MySqlDir) {
                if (Test-Path $MySqlDir) { Remove-Item $MySqlDir -Recurse -Force }
                Rename-Item -Path $Extracted.FullName -NewName "mysql" -Force
            }
            Write-Log "MySQL extrait dans $MySqlDir"
        } catch {
            Write-Log "Extraction MySQL : $_" "WARN"
        }
    }
}

# ── 3. Initialiser MySQL ───────────────────────────────────────────────────────
if (Test-Path "$MySqlBinDir\mysqld.exe") {
    New-Item -ItemType Directory -Force -Path $MySqlData | Out-Null

    # Protéger le dossier MySQL : refuser la suppression pour tous sauf SYSTEM + Administrateurs
    try {
        icacls $MySqlData /inheritance:r `
            /grant "SYSTEM:(OI)(CI)F" `
            /grant "Administrators:(OI)(CI)F" `
            /deny  "Users:(D,DC)" | Out-Null
        Write-Log "Protection dossier MySQL : suppression refusée aux utilisateurs standard"
    } catch {
        Write-Log "Impossible de protéger le dossier MySQL : $_" "WARN"
    }

    if (-not (Test-Path "$MySqlData\ibdata1")) {
        Write-Log "Initialisation du datadir MySQL ($MySqlData)..."

        # my.ini : port 3307, datadir dans ProgramData
        $basedirFwd = $MySqlDir   -replace '\\', '/'
        $datadirFwd = $MySqlData  -replace '\\', '/'
        @"
[mysqld]
basedir  = "$basedirFwd"
datadir  = "$datadirFwd"
port     = $MySqlPort
max_allowed_packet = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default-authentication-plugin = mysql_native_password
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
innodb_buffer_pool_size = 64M
max_connections = 50

[mysql]
default-character-set = utf8mb4
port = $MySqlPort

[client]
port = $MySqlPort
"@ | Out-File $MyIni -Encoding UTF8

        & "$MySqlBinDir\mysqld.exe" --defaults-file="$MyIni" --initialize-insecure 2>&1 |
            ForEach-Object { Write-Log "  [mysqld-init] $_" }
        Write-Log "MySQL initialisé (root sans mot de passe)"
    } else {
        Write-Log "MySQL déjà initialisé"
        if (-not (Test-Path $MyIni)) {
            $basedirFwd = $MySqlDir  -replace '\\', '/'
            $datadirFwd = $MySqlData -replace '\\', '/'
            @"
[mysqld]
basedir  = "$basedirFwd"
datadir  = "$datadirFwd"
port     = $MySqlPort
max_allowed_packet = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default-authentication-plugin = mysql_native_password

[client]
port = $MySqlPort
"@ | Out-File $MyIni -Encoding UTF8
        }
    }

    # ── Service MySQL ──────────────────────────────────────────────────────────
    $SvcMySQL = "POS_Connect_MySQL"
    $svcStatus = & $NssmExe status $SvcMySQL 2>&1
    if ($LASTEXITCODE -ne 0 -or "$svcStatus" -match "can't open service|No such service") {
        Write-Log "Installation service $SvcMySQL..."
        & $NssmExe install $SvcMySQL "$MySqlBinDir\mysqld.exe"
        & $NssmExe set    $SvcMySQL AppParameters "--defaults-file=`"$MyIni`""
        & $NssmExe set    $SvcMySQL DisplayName   "POS Connect — MySQL"
        & $NssmExe set    $SvcMySQL Description   "Base de données MySQL locale pour POS Connect"
        & $NssmExe set    $SvcMySQL Start         SERVICE_AUTO_START
        & $NssmExe set    $SvcMySQL AppStdout     "$DataDir\mysql-stdout.log"
        & $NssmExe set    $SvcMySQL AppStderr     "$DataDir\mysql-stderr.log"
        Write-Log "Service $SvcMySQL installé"
    } else {
        Write-Log "Service $SvcMySQL existe déjà ($svcStatus)"
    }

    # Démarrer MySQL et attendre qu'il soit prêt
    Start-Service -Name $SvcMySQL -ErrorAction SilentlyContinue
    Write-Log "Attente démarrage MySQL..."
    $MySqlReady = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        $ping = & "$MySqlBinDir\mysqladmin.exe" --host=127.0.0.1 --port=$MySqlPort `
                    --connect-timeout=2 ping 2>&1
        if ("$ping" -match "mysqld is alive") {
            $MySqlReady = $true
            Write-Log "MySQL prêt (${i}x2s)"
            break
        }
    }
    if (-not $MySqlReady) {
        Write-Log "MySQL n'a pas répondu dans les 40s — vérifiez les logs" "WARN"
    }

    # ── Créer pos_db + pos_user ────────────────────────────────────────────────
    $DbName = "pos_db"
    $DbUser = "pos_user"
    $MySqlExe = "$MySqlBinDir\mysql.exe"

    # Réutiliser mot de passe existant si pos_server.ini déjà configuré
    $DbPass = $null
    if (Test-Path $IniTarget) {
        foreach ($line in (Get-Content $IniTarget)) {
            if ($line -match '^\s*password\s*=\s*(.+)$') {
                $DbPass = $Matches[1].Trim()
                break
            }
        }
    }
    if (-not $DbPass) {
        # Générer un mot de passe fort (16 chars alphanumériques + symboles)
        $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%'
        $DbPass = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }

    if ($MySqlReady -and (Test-Path $MySqlExe)) {
        $Sql = @"
CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
CREATE USER IF NOT EXISTS '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER  USER '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER  USER '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@
        try {
            $Sql | & $MySqlExe --host=127.0.0.1 --port=$MySqlPort -u root --connect-timeout=10
            Write-Log "Base '$DbName' et utilisateur '$DbUser' créés/vérifiés"
        } catch {
            Write-Log "Création DB/user : $_" "WARN"
        }
    }

    # ── Écrire pos_server.ini complet avec MySQL ───────────────────────────────
    @"
[database]
type     = mysql
host     = 127.0.0.1
port     = $MySqlPort
name     = $DbName
user     = $DbUser
password = $DbPass

[server]
host = 0.0.0.0
port = 9003
"@ | Out-File -FilePath $IniTarget -Encoding UTF8 -Force
    Write-Log "pos_server.ini écrit (MySQL 127.0.0.1:$MySqlPort, db=$DbName, user=$DbUser)"
    # Restreindre les droits : uniquement SYSTEM et Administrateurs peuvent lire le fichier
    try {
        icacls $IniTarget /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" | Out-Null
        Write-Log "Permissions pos_server.ini restreintes (SYSTEM + Administrateurs)"
    } catch {
        Write-Log "Impossible de restreindre les permissions de pos_server.ini : $_" "WARN"
    }

} else {
    # MySQL absent — fallback SQLite
    Write-Log "MySQL non disponible — configuration SQLite" "WARN"
    if (-not (Test-Path $IniTarget)) {
        @"
[database]
type = sqlite
path = $DataDir\pos_connect.db

[server]
host = 0.0.0.0
port = 9003
"@ | Out-File -FilePath $IniTarget -Encoding UTF8
        Write-Log "pos_server.ini minimal créé (SQLite)"
        try {
            icacls $IniTarget /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" | Out-Null
            Write-Log "Permissions pos_server.ini restreintes (SYSTEM + Administrateurs)"
        } catch {
            Write-Log "Impossible de restreindre les permissions de pos_server.ini : $_" "WARN"
        }
    }
}

# ── 4. Service : POS Connect API ───────────────────────────────────────────────
$SvcApi = "POS_Connect_API"
$svcApiStatus = & $NssmExe status $SvcApi 2>&1
if ($LASTEXITCODE -ne 0 -or "$svcApiStatus" -match "can't open service|No such service") {
    Write-Log "Installation service $SvcApi..."
    & $NssmExe install $SvcApi $ApiExe
    & $NssmExe set    $SvcApi AppDirectory  $InstallDir
    & $NssmExe set    $SvcApi DisplayName   "POS Connect — Serveur API"
    & $NssmExe set    $SvcApi Description   "Serveur API FastAPI POS Connect"
    & $NssmExe set    $SvcApi Start         SERVICE_AUTO_START
    & $NssmExe set    $SvcApi AppStdout     "$DataDir\api-stdout.log"
    & $NssmExe set    $SvcApi AppStderr     "$DataDir\api-stderr.log"
    if (Test-Path "$MySqlBinDir\mysqld.exe") {
        & $NssmExe set $SvcApi DependOnService "POS_Connect_MySQL"
    }
    Write-Log "Service $SvcApi installé"
} else {
    Write-Log "Service $SvcApi existe déjà"
}

# ── 5. Service : Nginx ─────────────────────────────────────────────────────────
$SvcNginx = "POS_Connect_Nginx"
$svcNginxStatus = & $NssmExe status $SvcNginx 2>&1
if ($LASTEXITCODE -ne 0 -or "$svcNginxStatus" -match "can't open service|No such service") {
    Write-Log "Installation service $SvcNginx..."
    & $NssmExe install $SvcNginx $NginxExe
    & $NssmExe set    $SvcNginx AppDirectory  "$InstallDir\nginx"
    & $NssmExe set    $SvcNginx DisplayName   "POS Connect — Nginx"
    & $NssmExe set    $SvcNginx Description   "Reverse proxy Nginx pour POS Connect"
    & $NssmExe set    $SvcNginx Start         SERVICE_AUTO_START
    & $NssmExe set    $SvcNginx AppStdout     "$InstallDir\nginx\logs\nssm-stdout.log"
    & $NssmExe set    $SvcNginx AppStderr     "$InstallDir\nginx\logs\nssm-stderr.log"
    & $NssmExe set    $SvcNginx DependOnService "POS_Connect_API"
    Write-Log "Service $SvcNginx installé"
} else {
    Write-Log "Service $SvcNginx existe déjà"
}

# ── 6. Démarrer API + Nginx ────────────────────────────────────────────────────
Write-Log "Démarrage des services API et Nginx..."
foreach ($svc in @($SvcApi, $SvcNginx)) {
    try {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Write-Log "  ✓ $svc démarré"
    } catch {
        Write-Log "  ✗ $svc : $_" "WARN"
    }
}

# ── 7. Règles pare-feu ────────────────────────────────────────────────────────
# Profile Any = Private + Domain + Public : évite les blocages silencieux
# quand Windows classe le réseau en "Public" (réseaux inconnus, Wi-Fi public).

function Add-FwRule {
    param([string]$Name, [int]$Port)
    $existing = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        # Mettre à jour le profil si la règle existe déjà avec Private/Domain seulement
        try {
            Set-NetFirewallRule -DisplayName $Name -Profile Any -ErrorAction SilentlyContinue
        } catch {}
        Write-Log "Règle pare-feu mise à jour (Any) : $Name"
    } else {
        try {
            New-NetFirewallRule `
                -DisplayName $Name `
                -Direction   Inbound `
                -Protocol    TCP `
                -LocalPort   $Port `
                -Action      Allow `
                -Profile     Any | Out-Null
            Write-Log "Règle pare-feu ajoutée (Any) : $Name — port $Port"
        } catch {
            Write-Log "Pare-feu $Name : $_" "WARN"
        }
    }
}

Add-FwRule -Name "POS Connect Serveur API (9003)" -Port 9003
Add-FwRule -Name "POS Connect Nginx HTTP (80)"    -Port 80
Add-FwRule -Name "POS Connect Nginx HTTPS (443)"  -Port 443

Write-Log "=== Configuration POS Connect terminée ==="
Write-Log "Log complet : $LogFile"
