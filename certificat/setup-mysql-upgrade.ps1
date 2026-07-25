<#
.SYNOPSIS
    Upgrade POS Connect SQLite -> MySQL sur une machine existante.

.DESCRIPTION
    Ce script :
      1. Vérifie que la config actuelle est SQLite
      2. Demande les identifiants admin POS
      3. Arrête les services POS
      4. Installe MySQL 8 (bundlé dans POS_Connect) si absent
      5. Crée la base et l'utilisateur pos_user
      6. Migre les données SQLite -> MySQL via migrate_db.py
      7. Réécrit pos_server.ini (type = mysql)
      8. Redémarre les services

.NOTES
    Doit être lancé en tant qu'Administrateur Windows.
    Lance depuis posconnect-manager.ps1 ou directement.
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paramètres
# ---------------------------------------------------------------------------
param(
    [string]$IniPath     = "C:\ProgramData\POS_Connect\pos_server.ini",
    [string]$AdminLogin  = "",   # pré-rempli si appelé depuis le manager
    [string]$AdminPass   = "",   # idem
    [switch]$SkipMigrate,        # sauter migrate_db.py (debug)
    [switch]$NoBackup            # sauter le backup SQLite
)

# ---------------------------------------------------------------------------
# Chemins (mêmes constantes que setup-windows.ps1)
# ---------------------------------------------------------------------------
$InstallRoot      = Join-Path $env:ProgramFiles "POS_Connect"
$ApiDir           = Join-Path $InstallRoot "api"
$MigrateScript    = Join-Path $ApiDir       "migrate_db.py"
$BundledMysqlDir  = Join-Path $InstallRoot  "mysql"
$BundledMysqldExe = Join-Path $BundledMysqlDir "bin\mysqld.exe"
$BundledMysqlExe  = Join-Path $BundledMysqlDir "bin\mysql.exe"
$BundledMyIni     = Join-Path $BundledMysqlDir "my.ini"
$BundledDataDir   = "C:\ProgramData\POS_Connect_MySQL"
$BundledSvcName   = "POS_Connect_MySQL"
$MysqlVer         = "8.0.39"
$MysqlZipName     = "mysql-$MysqlVer-winx64.zip"
$MysqlZipLocal    = Join-Path $InstallRoot $MysqlZipName
$MysqlUrl         = "https://dev.mysql.com/get/Downloads/MySQL-8.0/$MysqlZipName"
$DbHost           = "127.0.0.1"
$DbPort           = 3307
$DbName           = "pos_db"
$PosUser          = "pos_user"
$ApiSvcName       = "POS_Connect_API"
$NginxSvcName     = "POS_Connect_Nginx"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step($msg) { Write-Host "`n-> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "   OK  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   !   $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "   ERR $msg" -ForegroundColor Red }

function Die($msg) {
    Write-Fail $msg
    Write-Host "`nUpgrade annulé." -ForegroundColor Red
    exit 1
}

function New-RandPass([int]$n = 24) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#%'
    -join ((1..$n) | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })
}

function Get-IniValue($path, $section, $key) {
    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ($content -match "(?m)^\s*$key\s*=\s*(.+)\s*$") { return $Matches[1].Trim() }
    return $null
}

function Set-IniValue($path, $key, $value) {
    $content = Get-Content $path -Raw
    $content = $content -replace "(?m)^(\s*$key\s*=).*$", "`${1} $value"
    Set-Content $path $content -Encoding UTF8
}

function Invoke-MySQL {
    param($User, $Pass, [string[]]$Statements)
    $env:MYSQL_PWD = $Pass
    foreach ($sql in $Statements) {
        $result = & $BundledMysqlExe "--host=$DbHost" "--port=$DbPort" `
                    "--user=$User" "-e" $sql 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "SQL: $sql"
            Write-Warn "Résultat: $result"
            return $false
        }
    }
    return $true
}

function Get-SvcStatus($name) {
    $svc = Get-Service $name -ErrorAction SilentlyContinue
    if (-not $svc) { return "Absent" }
    return $svc.Status
}

# ---------------------------------------------------------------------------
# Vérifications initiales
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  POS Connect — Upgrade SQLite -> MySQL   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. INI doit exister et être en mode SQLite
if (-not (Test-Path $IniPath)) {
    Die "pos_server.ini introuvable : $IniPath"
}
$currentType = Get-IniValue $IniPath "database" "type"
if ($currentType -ne "sqlite") {
    Die "pos_server.ini indique type=$currentType — déjà en MySQL ou inconnu."
}
$SqlitePath = Get-IniValue $IniPath "database" "path"
if (-not $SqlitePath) {
    $SqlitePath = Join-Path $InstallRoot "pos_data.db"
}
if (-not (Test-Path $SqlitePath)) {
    Die "Fichier SQLite introuvable : $SqlitePath"
}
Write-OK "SQLite détecté : $SqlitePath"

# 2. Trouver python embarqué
$PythonExe = Join-Path $ApiDir "python.exe"
if (-not (Test-Path $PythonExe)) {
    # Chercher python dans PATH
    $PythonExe = (Get-Command "python" -ErrorAction SilentlyContinue)?.Source
    if (-not $PythonExe) {
        Die "python.exe introuvable dans $ApiDir ni dans PATH."
    }
}
Write-OK "Python : $PythonExe"

# 3. Script de migration
if (-not $SkipMigrate -and -not (Test-Path $MigrateScript)) {
    Die "migrate_db.py introuvable : $MigrateScript`nCopiez-le depuis le package POS Connect."
}

# ---------------------------------------------------------------------------
# Authentification admin POS (sauf si déjà fourni par le manager)
# ---------------------------------------------------------------------------
if (-not $AdminLogin -or -not $AdminPass) {
    Write-Step "Authentification administrateur POS"
    Write-Host "   (nécessaire pour autoriser l'upgrade)" -ForegroundColor DarkGray
    $AdminLogin = Read-Host "   Identifiant admin"
    $secPass    = Read-Host "   Mot de passe"    -AsSecureString
    $AdminPass  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass))
}

# Vérifier les identifiants via l'API si elle tourne
$ApiRunning = (Get-SvcStatus $ApiSvcName) -eq "Running"
if ($ApiRunning) {
    $ApiPort = Get-IniValue $IniPath "server" "port"
    if (-not $ApiPort) { $ApiPort = "8443" }
    try {
        $body    = @{ username = $AdminLogin; password = $AdminPass } | ConvertTo-Json
        $headers = @{ "Content-Type" = "application/json" }
        $resp    = Invoke-RestMethod -Uri "https://localhost:$ApiPort/api/auth/login" `
                       -Method POST -Body $body -Headers $headers `
                       -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
        if (-not $resp.access_token) { Die "Identifiants admin POS invalides." }
        Write-OK "Authentification réussie."
    } catch {
        Die "Échec de l'authentification admin POS : $_"
    }
} else {
    Write-Warn "API arrêtée — vérification des identifiants ignorée."
}

# ---------------------------------------------------------------------------
# Confirmation finale
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  RÉSUMÉ DE L'OPÉRATION" -ForegroundColor Yellow
Write-Host "  Source SQLite : $SqlitePath" -ForegroundColor White
Write-Host "  Dest MySQL    : $DbName @ $DbHost:$DbPort" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Continuer ? (o/n)"
if ($confirm -notmatch "^[oOyY]") {
    Write-Host "Annulé." -ForegroundColor DarkGray
    exit 0
}

# ---------------------------------------------------------------------------
# Epic 2 Step A : Arrêter les services
# ---------------------------------------------------------------------------
Write-Step "Arrêt des services POS..."
Stop-Service $NginxSvcName, $ApiSvcName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-OK "Services arrêtés."

# ---------------------------------------------------------------------------
# Epic 2 Step B : Installer MySQL si absent
# ---------------------------------------------------------------------------
Write-Step "MySQL $MysqlVer..."

if (Test-Path $BundledMysqldExe) {
    Write-OK "MySQL bundlé déjà présent : $BundledMysqlDir"
} else {
    Write-Host "   Téléchargement MySQL $MysqlVer..." -ForegroundColor DarkGray

    if (-not (Test-Path $MysqlZipLocal)) {
        try {
            [System.Net.WebClient]::new().DownloadFile($MysqlUrl, $MysqlZipLocal)
            Write-OK "Téléchargé : $MysqlZipLocal"
        } catch {
            Die "Téléchargement MySQL échoué : $_`nTéléchargez manuellement $MysqlUrl et placez-le dans $InstallRoot"
        }
    } else {
        Write-OK "ZIP trouvé dans cache : $MysqlZipLocal"
    }

    Write-Host "   Extraction..." -ForegroundColor DarkGray
    Expand-Archive -Path $MysqlZipLocal -DestinationPath $InstallRoot -Force
    $extracted = Get-ChildItem $InstallRoot -Directory | Where-Object { $_.Name -like "mysql-*" } |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $extracted) { Die "Extraction MySQL échouée." }
    Rename-Item $extracted.FullName $BundledMysqlDir -Force -ErrorAction SilentlyContinue
    Write-OK "MySQL extrait dans $BundledMysqlDir"
}

# my.ini
if (-not (Test-Path $BundledMyIni)) {
    @"
[mysqld]
basedir=$($BundledMysqlDir.Replace('\','\\'))
datadir=$($BundledDataDir.Replace('\','\\'))
port=$DbPort
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
default-authentication-plugin=mysql_native_password
"@ | Set-Content $BundledMyIni -Encoding ASCII
    Write-OK "my.ini généré."
}

# Initialiser datadir si vide
if (-not (Test-Path $BundledDataDir) -or
    -not (Test-Path (Join-Path $BundledDataDir "mysql"))) {
    New-Item -Path $BundledDataDir -ItemType Directory -Force | Out-Null
    & $BundledMysqldExe --defaults-file="$BundledMyIni" --initialize-insecure --console 2>&1 |
        Out-Null
    Write-OK "Répertoire données MySQL initialisé."
}

# Installer le service Windows
if (-not (Get-Service $BundledSvcName -ErrorAction SilentlyContinue)) {
    & $BundledMysqldExe --install $BundledSvcName --defaults-file="$BundledMyIni" 2>&1 | Out-Null
    Write-OK "Service '$BundledSvcName' installé."
}

# Démarrer MySQL
if ((Get-SvcStatus $BundledSvcName) -ne "Running") {
    Start-Service $BundledSvcName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
}
if ((Get-SvcStatus $BundledSvcName) -ne "Running") {
    Die "MySQL n'a pas démarré. Consultez les logs Windows (Event Viewer)."
}
Write-OK "MySQL démarré (port $DbPort)."

# ---------------------------------------------------------------------------
# Epic 2 Step C : Créer base + utilisateur
# ---------------------------------------------------------------------------
Write-Step "Création de la base de données '$DbName'..."

$PosPass  = New-RandPass 24
$RootPass = New-RandPass 24

# root sans mot de passe (--initialize-insecure) → sécuriser + créer pos_user
$ok = Invoke-MySQL -User "root" -Pass "" -Statements @(
    "ALTER USER 'root'@'localhost' IDENTIFIED BY '$RootPass'",
    "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
    "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$PosPass'",
    "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$PosPass'",
    "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
    "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
    "FLUSH PRIVILEGES"
)

if (-not $ok) {
    # root peut déjà avoir un mot de passe (restart du script)
    $RootPassSecure = Read-Host "Mot de passe root MySQL" -AsSecureString
    $RootPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPassSecure))
    $ok2 = Invoke-MySQL -User "root" -Pass $RootPass -Statements @(
        "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
        "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$PosPass'",
        "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$PosPass'",
        "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
        "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
        "FLUSH PRIVILEGES"
    )
    if (-not $ok2) { Die "Impossible de créer la base MySQL. Vérifiez les logs MySQL." }
}

Write-OK "Base '$DbName' et utilisateur '$PosUser' prêts."

# ---------------------------------------------------------------------------
# Epic 2 Step D : Migration des données SQLite -> MySQL
# ---------------------------------------------------------------------------
if (-not $SkipMigrate) {
    Write-Step "Migration des données SQLite -> MySQL..."

    $backupFlag = if ($NoBackup) { "--no-backup" } else { "" }
    $migrateArgs = @(
        $MigrateScript,
        "sqlite-to-mysql",
        "--ini", $IniPath,
        "--sqlite", $SqlitePath,
        "--mysql-host", $DbHost,
        "--mysql-port", $DbPort,
        "--mysql-db",   $DbName,
        "--mysql-user", $PosUser,
        "--mysql-pass", $PosPass
    )
    if ($NoBackup) { $migrateArgs += "--no-backup" }

    & $PythonExe @migrateArgs
    if ($LASTEXITCODE -ne 0) {
        Die "Migration échouée (code $LASTEXITCODE). Les services restent arrêtés — corrigez et relancez."
    }
    Write-OK "Migration réussie."
} else {
    Write-Warn "Migration des données sautée (--SkipMigrate)."
}

# ---------------------------------------------------------------------------
# Epic 2 Step E : Réécrire pos_server.ini
# ---------------------------------------------------------------------------
Write-Step "Mise à jour de pos_server.ini..."

$iniContent = @"
[server]
port = $(Get-IniValue $IniPath 'server' 'port' ?? '8443')
host = 0.0.0.0
secret_key = $(Get-IniValue $IniPath 'server' 'secret_key')
workers = 2

[database]
type     = mysql
host     = $DbHost
port     = $DbPort
name     = $DbName
user     = $PosUser
password = $PosPass

[platform]
admin_email         = $(Get-IniValue $IniPath 'platform' 'admin_email')
admin_password_hash = $(Get-IniValue $IniPath 'platform' 'admin_password_hash')
"@

Set-Content $IniPath $iniContent -Encoding UTF8
Write-OK "pos_server.ini réécrit (type = mysql)."

# ---------------------------------------------------------------------------
# Epic 2 Step F : Redémarrer les services
# ---------------------------------------------------------------------------
Write-Step "Redémarrage des services..."

Start-Service $ApiSvcName   -ErrorAction SilentlyContinue ; Start-Sleep -Seconds 4
Start-Service $NginxSvcName -ErrorAction SilentlyContinue ; Start-Sleep -Seconds 2

$apiStatus   = Get-SvcStatus $ApiSvcName
$nginxStatus = Get-SvcStatus $NginxSvcName
Write-OK "API POS  : $apiStatus"
Write-OK "Nginx    : $nginxStatus"

if ($apiStatus -ne "Running") {
    Write-Warn "L'API n'a pas redémarré. Vérifiez les logs Windows."
} else {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Green
    Write-Host "   Upgrade SQLite -> MySQL termine avec succes" -ForegroundColor Green
    Write-Host "  ============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  La base MySQL est maintenant active." -ForegroundColor White
    Write-Host "  Vous pouvez fermer cette fenetre." -ForegroundColor DarkGray
    Write-Host ""
}
