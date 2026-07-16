#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure POS Connect après installation Inno Setup.
    - Extrait MySQL si nécessaire
    - Initialise la base de données MySQL
    - Installe les services Windows via NSSM (Nginx + API)
    - Crée pos_server.ini dans ProgramData
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Chemins ────────────────────────────────────────────────────────────────────
$InstallDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir     = "$env:ProgramData\POS_Connect"
$NssmExe     = "$InstallDir\nssm\nssm.exe"
$NginxExe    = "$InstallDir\nginx\nginx.exe"
$ApiExe      = "$InstallDir\posconnect-server.exe"
$MySqlZip    = "$InstallDir\mysql-8.0.41-winx64.zip"
$MySqlDir    = "$InstallDir\mysql"
$MySqlBin    = "$MySqlDir\bin\mysqld.exe"
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

# ── 1. Créer pos_server.ini dans ProgramData si absent ────────────────────────
$IniSource = "$InstallDir\pos_server.ini"
$IniTarget = "$DataDir\pos_server.ini"

if (-not (Test-Path $IniTarget)) {
    if (Test-Path $IniSource) {
        Copy-Item $IniSource $IniTarget -Force
        Write-Log "pos_server.ini copié dans ProgramData"
    } else {
        # Créer un ini minimal avec SQLite comme fallback
        @"
[database]
type     = sqlite
path     = $DataDir\pos_data.db

[server]
host = 0.0.0.0
port = 9003
"@ | Out-File -FilePath $IniTarget -Encoding UTF8
        Write-Log "pos_server.ini minimal créé (SQLite)"
    }
}

# ── 2. Extraire MySQL si le zip est présent et MySQL absent ───────────────────
if ((Test-Path $MySqlZip) -and (-not (Test-Path $MySqlBin))) {
    Write-Log "Extraction de MySQL..."
    try {
        Expand-Archive -Path $MySqlZip -DestinationPath $InstallDir -Force
        # Le zip extrait un dossier du style mysql-8.0.41-winx64 — on le renomme
        $Extracted = Get-ChildItem -Path $InstallDir -Directory -Filter "mysql-*" |
                     Select-Object -First 1
        if ($Extracted) {
            Rename-Item -Path $Extracted.FullName -NewName "mysql" -Force
        }
        Write-Log "MySQL extrait dans $MySqlDir"
    } catch {
        Write-Log "Échec de l'extraction MySQL : $_" "WARN"
    }
}

# ── 3. Initialiser MySQL si nécessaire ────────────────────────────────────────
if (Test-Path $MySqlBin) {
    $MySqlData = "$MySqlDir\data"
    if (-not (Test-Path "$MySqlData\ibdata1")) {
        Write-Log "Initialisation du datadir MySQL..."
        try {
            # Créer my.ini minimal
            @"
[mysqld]
basedir  = $($MySqlDir -replace '\\','/')
datadir  = $($MySqlData -replace '\\','/')
port     = 3306
max_allowed_packet = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

[mysql]
default-character-set = utf8mb4
"@ | Out-File "$MySqlDir\my.ini" -Encoding UTF8

            & "$MySqlDir\bin\mysqld.exe" --initialize-insecure `
                --basedir="$MySqlDir" --datadir="$MySqlData" 2>&1 |
                ForEach-Object { Write-Log "  [mysqld] $_" }
            Write-Log "MySQL initialisé avec mot de passe root vide"
        } catch {
            Write-Log "Échec init MySQL : $_" "WARN"
        }
    } else {
        Write-Log "MySQL déjà initialisé"
    }

    # Installer le service MySQL via NSSM
    $SvcMySQL = "POS_Connect_MySQL"
    $existing = & $NssmExe status $SvcMySQL 2>&1
    if ($LASTEXITCODE -ne 0 -or $existing -match "can't open service") {
        Write-Log "Installation service $SvcMySQL..."
        & $NssmExe install $SvcMySQL "$MySqlDir\bin\mysqld.exe"
        & $NssmExe set    $SvcMySQL AppParameters "--defaults-file=`"$MySqlDir\my.ini`""
        & $NssmExe set    $SvcMySQL DisplayName   "POS Connect — MySQL"
        & $NssmExe set    $SvcMySQL Description   "Base de données MySQL pour POS Connect"
        & $NssmExe set    $SvcMySQL Start         SERVICE_AUTO_START
        & $NssmExe set    $SvcMySQL AppStdout     "$DataDir\mysql-stdout.log"
        & $NssmExe set    $SvcMySQL AppStderr     "$DataDir\mysql-stderr.log"
        Write-Log "Service $SvcMySQL installé"
    } else {
        Write-Log "Service $SvcMySQL existe déjà"
    }

    # Démarrer MySQL
    try {
        Start-Service -Name $SvcMySQL -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Write-Log "Service $SvcMySQL démarré"
    } catch {
        Write-Log "Impossible de démarrer $SvcMySQL : $_" "WARN"
    }

    # Créer la base de données pos_db si absente
    $MySqlClient = "$MySqlDir\bin\mysql.exe"
    if (Test-Path $MySqlClient) {
        try {
            & $MySqlClient -u root --execute "CREATE DATABASE IF NOT EXISTS pos_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 |
                ForEach-Object { Write-Log "  [mysql] $_" }
            Write-Log "Base pos_db vérifiée/créée"

            # Mettre à jour pos_server.ini pour MySQL
            $IniContent = Get-Content $IniTarget -Raw
            $IniContent = $IniContent -replace 'type\s*=\s*sqlite', 'type = mysql'
            $IniContent | Out-File $IniTarget -Encoding UTF8
            Write-Log "pos_server.ini mis à jour pour MySQL"
        } catch {
            Write-Log "Impossible de créer pos_db : $_" "WARN"
        }
    }
}

# ── 4. Service Windows : POS Connect API ─────────────────────────────────────
$SvcApi = "POS_Connect_API"
$existingApi = & $NssmExe status $SvcApi 2>&1
if ($LASTEXITCODE -ne 0 -or $existingApi -match "can't open service") {
    Write-Log "Installation service $SvcApi..."
    & $NssmExe install $SvcApi $ApiExe
    & $NssmExe set    $SvcApi AppDirectory  $InstallDir
    & $NssmExe set    $SvcApi DisplayName   "POS Connect — Serveur API"
    & $NssmExe set    $SvcApi Description   "Serveur API FastAPI POS Connect"
    & $NssmExe set    $SvcApi Start         SERVICE_AUTO_START
    & $NssmExe set    $SvcApi AppStdout     "$DataDir\api-stdout.log"
    & $NssmExe set    $SvcApi AppStderr     "$DataDir\api-stderr.log"

    # Dépend de MySQL si présent
    if (Test-Path $MySqlBin) {
        & $NssmExe set $SvcApi DependOnService "POS_Connect_MySQL"
    }
    Write-Log "Service $SvcApi installé"
} else {
    Write-Log "Service $SvcApi existe déjà"
}

# ── 5. Service Windows : Nginx ────────────────────────────────────────────────
$SvcNginx = "POS_Connect_Nginx"
$existingNginx = & $NssmExe status $SvcNginx 2>&1
if ($LASTEXITCODE -ne 0 -or $existingNginx -match "can't open service") {
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

# ── 6. Démarrer les services dans l'ordre ────────────────────────────────────
Write-Log "Démarrage des services..."
foreach ($svc in @($SvcApi, $SvcNginx)) {
    try {
        Start-Service -Name $svc
        Write-Log "  ✓ $svc démarré"
    } catch {
        Write-Log "  ✗ Impossible de démarrer $svc : $_" "WARN"
    }
}

# ── 7. Règle pare-feu Windows ────────────────────────────────────────────────
$FwRuleName = "POS Connect Serveur (port 9003)"
$existing = Get-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
if (-not $existing) {
    try {
        New-NetFirewallRule `
            -DisplayName $FwRuleName `
            -Direction   Inbound `
            -Protocol    TCP `
            -LocalPort   9003 `
            -Action      Allow `
            -Profile     Private, Domain | Out-Null
        Write-Log "Règle pare-feu ajoutée : port 9003"
    } catch {
        Write-Log "Pare-feu non configuré : $_" "WARN"
    }
}

Write-Log "=== Configuration terminée avec succès ==="
Write-Log "Logs détaillés : $LogFile"
