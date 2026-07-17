# ============================================================
#  POS Connect — Installation serveur local Windows
#
#  Structure attendue du package de déploiement :
#    posconnect-package\
#      certificat\
#        setup-windows.ps1   ← ce fichier
#        nginx-windows.conf
#        server.crt
#        server.key
#      api\                  ← contenu du build Nuitka (GitHub Actions)
#        posconnect-server.exe
#        api\  (données statiques, migrations)
#        *.dll / *.pyd
#      pos_server.ini        ← config BDD, secret_key, etc. (pas de .env sur Windows)
#
#  Ce script installe tout dans :
#    C:\Program Files\POS_Connect\
#
#  Doit être lancé en tant qu'Administrateur.
# ============================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# ── Chemins ───────────────────────────────────────────────────────────────────
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir   = Split-Path -Parent $ScriptDir          # dossier parent du package

$InstallRoot  = Join-Path $env:ProgramFiles "POS_Connect"
$NginxDir     = Join-Path $InstallRoot "nginx"
$NginxCerts   = Join-Path $NginxDir   "certs"
$NginxConf    = Join-Path $NginxDir   "conf"
$ApiDir       = Join-Path $InstallRoot "api"
$NssmDir      = Join-Path $InstallRoot "nssm"
$NssmExe      = Join-Path $NssmDir    "nssm.exe"

$NginxVer     = "1.27.4"
$NginxUrl     = "https://nginx.org/download/nginx-$NginxVer.zip"
$NssmUrl      = "https://nssm.cc/release/nssm-2.24.zip"

$HostsFile    = "C:\Windows\System32\drivers\etc\hosts"
$Hostname     = "infini-post.local"
$NginxSvc     = "POS-Nginx"
$ApiSvc       = "POS-API"
$ApiExe       = Join-Path $ApiDir "posconnect-server.exe"

# Ports par défaut — peuvent être remplacés si occupés (voir étape 2)
$HttpPort     = 80
$HttpsPort    = 443

# MySQL — utilisé si MySQL absent du système
$MysqlVer     = "8.0.39"
$MysqlInstDir = Join-Path $env:ProgramFiles "MySQL\MySQL Server 8.0"
$MysqlZipName = "mysql-$MysqlVer-winx64.zip"
$MysqlZipLocal= Join-Path $InstallRoot $MysqlZipName   # cache local avant téléchargement
$MysqlUrl     = "https://dev.mysql.com/get/Downloads/MySQL-8.0/$MysqlZipName"
$DbHost       = "127.0.0.1"
$DbPort       = 3307
$DbName       = "pos_db"

# MySQL bundlé dans le dossier POS_Connect (prioritaire sur le MySQL système)
$BundledMysqlDir  = Join-Path $InstallRoot "mysql"
$BundledMysqldExe = Join-Path $BundledMysqlDir "bin\mysqld.exe"
$BundledMysqlExe  = Join-Path $BundledMysqlDir "bin\mysql.exe"
$BundledMyIni     = Join-Path $BundledMysqlDir "my.ini"
$BundledDataDir   = "C:\ProgramData\POS_Connect_MySQL"
$BundledSvcName   = "POS_Connect_MySQL"

function Write-Step($msg) { Write-Host "`n→ $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`n  X $msg" -ForegroundColor Red; exit 1 }

# Ecriture UTF-8 SANS BOM (PS 5.1 ajoute un BOM avec -Encoding UTF8)
function Write-UTF8NoBOM {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function New-RandPass([int]$n = 20) {
    $c = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'
    -join ((1..$n) | ForEach-Object { $c[(Get-Random -Maximum $c.Length)] })
}
function New-HexKey([int]$bytes = 32) {
    -join ((1..$bytes) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
}

# Trouve mysql.exe : bundlé POS_Connect d'abord, puis PATH, puis emplacements courants
function Find-MysqlExe {
    # 1. MySQL bundlé dans POS_Connect (prioritaire)
    $bundled = Join-Path $InstallRoot "mysql\bin\mysql.exe"
    if (Test-Path $bundled) { return $bundled }
    # 2. PATH système
    $fromPath = Get-Command "mysql" -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    # 3. Emplacements MySQL standard
    $candidates = Get-ChildItem "$env:ProgramFiles\MySQL" -Recurse -Filter "mysql.exe" -ErrorAction SilentlyContinue
    if ($candidates) { return $candidates[0].FullName }
    return $null
}

# Exécute une liste d'instructions SQL via mysql.exe
function Invoke-Sql {
    param($Exe, $Host, $Port, $User, $Pass, [string[]]$Statements)
    $env:MYSQL_PWD = $Pass
    foreach ($sql in $Statements) {
        & $Exe -h$Host -P$Port -u$User --execute=$sql 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
            return $false
        }
    }
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    return $true
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  POS Connect — Setup serveur local Windows      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ── 0. Vérifier les certificats ───────────────────────────────────────────────
Write-Step "Vérification des certificats..."
if (-not (Test-Path "$ScriptDir\server.crt")) { Fail "server.crt introuvable dans $ScriptDir" }
if (-not (Test-Path "$ScriptDir\server.key")) { Fail "server.key introuvable dans $ScriptDir" }
Write-OK "Certificats présents."

# ── 1. Ajouter le certificat dans le magasin racine Windows ──────────────────
# Fait EN PREMIER : nginx doit démarrer avec un certificat déjà approuvé
# par Windows pour que les connexions HTTPS soient acceptées immédiatement.
Write-Step "Certificat dans le magasin de confiance Windows (Root)..."
try {
    $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$ScriptDir\server.crt")
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    # Supprimer l'ancienne version si présente (renouvellement)
    $store.Certificates |
        Where-Object { $_.Subject -eq $cert.Subject } |
        ForEach-Object { $store.Remove($_) }
    $store.Add($cert)
    $store.Close()
    Write-OK "Certificat '$($cert.Subject)' approuvé (expire $($cert.GetExpirationDateString()))."
} catch {
    Fail "Impossible d'ajouter le certificat au Root store : $_"
}

# ── 2. Créer le dossier d'installation ───────────────────────────────────────
Write-Step "Dossier d'installation : $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Write-OK "Dossier prêt."

# ── 3. Vérifier les conflits de port — basculement silencieux ────────────────
Write-Step "Vérification des ports 80 et 443..."
foreach ($port in @(80, 443)) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.Name } else { "PID $($conn.OwningProcess)" }
        if ($name -eq "nginx") {
            Write-Host "  Port $port : nginx déjà en écoute (sera reconfiguré)." -ForegroundColor DarkGray
        } else {
            $alt = if ($port -eq 80) { 8080 } else { 8443 }
            if ($port -eq 80)  { $HttpPort  = $alt }
            if ($port -eq 443) { $HttpsPort = $alt }
            Write-Host "  Port $port utilisé par '$name' → basculement automatique sur $alt." -ForegroundColor DarkGray
        }
    }
}

# ── 4. Télécharger Nginx si nginx.exe absent ──────────────────────────────────
# On vérifie nginx.exe (pas seulement le dossier) pour détecter une
# extraction partielle. Les binaires nginx d'une autre installation
# (Chocolatey, manuelle) ne sont PAS utilisés : on isole notre propre
# copie dans $NginxDir pour éviter tout conflit de configuration.
Write-Step "Nginx $NginxVer (installation isolée dans $NginxDir)..."
if (Test-Path "$NginxDir\nginx.exe") {
    Write-Host "  nginx.exe présent — téléchargement ignoré." -ForegroundColor DarkGray
} else {
    if (Test-Path $NginxDir) {
        Write-Host "  Dossier présent mais nginx.exe manquant — re-téléchargement..." -ForegroundColor DarkGray
        Remove-Item $NginxDir -Recurse -Force
    }
    $nginxZip = "$env:TEMP\nginx-$NginxVer.zip"
    Write-Host "  Téléchargement..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $NginxUrl -OutFile $nginxZip -UseBasicParsing
    Expand-Archive -Path $nginxZip -DestinationPath "$env:TEMP\nginx_tmp" -Force
    Move-Item "$env:TEMP\nginx_tmp\nginx-$NginxVer" $NginxDir
    Remove-Item "$env:TEMP\nginx_tmp" -Recurse -Force
    Remove-Item $nginxZip -Force
    Write-OK "Nginx extrait dans $NginxDir"
}

# ── 5. Appliquer la configuration (toujours, même si nginx existait déjà) ─────
# Généré dynamiquement pour intégrer les ports réels ($HttpPort / $HttpsPort).
Write-Step "Configuration Nginx (ports HTTP=$HttpPort HTTPS=$HttpsPort)..."
New-Item -ItemType Directory -Path $NginxCerts -Force | Out-Null
Copy-Item "$ScriptDir\server.crt" "$NginxCerts\server.crt" -Force
Copy-Item "$ScriptDir\server.key" "$NginxCerts\server.key" -Force

# nginx.conf principal
Write-UTF8NoBOM "$NginxConf\nginx.conf" @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    include conf/default.conf;
}
"@

# Vhost généré avec les ports détectés (backtick = échappement PowerShell pour $)
Write-UTF8NoBOM "$NginxConf\default.conf" @"
server {
    listen      $HttpPort;
    server_name $Hostname localhost;
    return 301  https://`$host:$HttpsPort`$request_uri;
}
server {
    listen      $HttpsPort ssl;
    server_name $Hostname localhost;

    ssl_certificate     certs/server.crt;
    ssl_certificate_key certs/server.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 20M;

    location / {
        proxy_pass         http://127.0.0.1:9003;
        proxy_http_version 1.1;
        proxy_set_header   Host              `$host;
        proxy_set_header   X-Real-IP         `$remote_addr;
        proxy_set_header   X-Forwarded-For   `$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }
}
"@
Write-OK "Certificats et configuration appliqués."

# ── 6. Copier les fichiers API (build Nuitka) ─────────────────────────────────
Write-Step "Fichiers API (posconnect-server)..."
$srcApi = Join-Path $PackageDir "api"
if (Test-Path $srcApi) {
    if (Test-Path $ApiDir) { Remove-Item $ApiDir -Recurse -Force }
    Copy-Item $srcApi $ApiDir -Recurse -Force
    Write-OK "API copiée dans $ApiDir"
} else {
    Write-Warn "Dossier 'api\' absent du package."
    Write-Warn "Copie le build Nuitka (GitHub Actions > backend-windows) dans : $ApiDir"
}

# ── 7. Base de données MySQL ──────────────────────────────────────────────────
# .env est réservé à Docker. Sur Windows la config va dans pos_server.ini.
# Si pos_server.ini existe avec une config DB valide → on ne touche pas.
$IniPath = Join-Path $InstallRoot "pos_server.ini"
$iniExists = (Test-Path $IniPath) -and
             ((Get-Content $IniPath -Raw) -match 'type\s*=\s*mysql') -and
             ((Get-Content $IniPath -Raw) -match 'password\s*=\s*\S')

if ($iniExists) {
    Write-Host "`n→ pos_server.ini déjà configuré — étape DB ignorée." -ForegroundColor DarkGray
} else {

  Write-Step "Base de données MySQL..."

  $PosUser = "pos_user"
  $PosPass = New-RandPass 24
  $RootPass = $null

  # ── CAS 1 : MySQL bundlé dans POS_Connect\mysql\ (prioritaire) ───────────
  if (Test-Path $BundledMysqldExe) {
    Write-Host "  MySQL bundlé détecté : $BundledMysqlDir" -ForegroundColor DarkGray

    # Créer le répertoire de données si absent (mysqld jamais initialisé)
    if (-not (Test-Path $BundledDataDir)) {
      New-Item -Path $BundledDataDir -ItemType Directory -Force | Out-Null
      Write-Host "  Initialisation du répertoire de données MySQL..." -ForegroundColor DarkGray
      # --initialize-insecure : root sans mot de passe (on le change juste après)
      & $BundledMysqldExe --defaults-file="$BundledMyIni" --initialize-insecure --console 2>&1 |
        ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
      Write-OK "Répertoire '$BundledDataDir' initialisé."
    } else {
      Write-Host "  Répertoire de données présent — initialisation ignorée." -ForegroundColor DarkGray
    }

    # Installer le service Windows s'il n'existe pas
    if (-not (Get-Service $BundledSvcName -ErrorAction SilentlyContinue)) {
      & $BundledMysqldExe --install $BundledSvcName --defaults-file="$BundledMyIni" 2>&1 | Out-Null
      Write-OK "Service '$BundledSvcName' installé."
    }

    # Démarrer (ou redémarrer) le service
    $svc = Get-Service $BundledSvcName -ErrorAction SilentlyContinue
    if ($svc.Status -ne "Running") {
      Start-Service $BundledSvcName -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 5
    }
    Write-OK "Service '$BundledSvcName' démarré (port $DbPort)."

    $mysqlExe = $BundledMysqlExe

    # Sécuriser root puis créer pos_user (root sans mot de passe après --initialize-insecure)
    $RootPass = New-RandPass 24
    $ok = Invoke-Sql -Exe $mysqlExe -Host $DbHost -Port $DbPort -User "root" -Pass "" -Statements @(
      "ALTER USER 'root'@'localhost' IDENTIFIED BY '${RootPass}'",
      "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
      "FLUSH PRIVILEGES"
    )
    if (-not $ok) {
      # root a peut-être déjà un mot de passe (réinstallation) — demander
      Write-Host "  Mot de passe root MySQL requis pour continuer :" -ForegroundColor Yellow
      $rp = Read-Host "    Mot de passe root" -AsSecureString
      $RootPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($rp))
      $ok = Invoke-Sql -Exe $mysqlExe -Host $DbHost -Port $DbPort -User "root" -Pass $RootPass -Statements @(
        "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
        "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
        "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
        "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
        "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
        "FLUSH PRIVILEGES"
      )
      if (-not $ok) { Fail "Impossible de configurer la base MySQL bundlée." }
    }
    Write-OK "Base '$DbName' et utilisateur '$PosUser' configurés."
    $DbUser = $PosUser ; $DbPass = $PosPass

  # ── CAS 2 : MySQL système déjà installé et en cours d'exécution ──────────
  } elseif ((Get-Service -Name "MySQL*" -ErrorAction SilentlyContinue |
             Where-Object { $_.Status -eq "Running" } | Select-Object -First 1) -and
            (Find-MysqlExe)) {
    $mysqlSvc = Get-Service -Name "MySQL*" | Where-Object { $_.Status -eq "Running" } | Select-Object -First 1
    $mysqlExe = Find-MysqlExe
    Write-Host "  MySQL système détecté : service '$($mysqlSvc.Name)'." -ForegroundColor DarkGray

    Write-Host "  Identifiants d'un compte admin MySQL (pour créer la base POS) :" -ForegroundColor White
    $adminUser = Read-Host "    Utilisateur (ex: root)"
    $adminPass = Read-Host "    Mot de passe" -AsSecureString
    $adminPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass))

    $env:MYSQL_PWD = $adminPassPlain
    & $mysqlExe -h$DbHost -P$DbPort -u$adminUser --execute="SELECT 1;" 2>&1 | Out-Null
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { Fail "Connexion MySQL échouée. Vérifiez les identifiants." }
    Write-OK "Connexion MySQL réussie."

    $ok = Invoke-Sql -Exe $mysqlExe -Host $DbHost -Port $DbPort -User $adminUser -Pass $adminPassPlain -Statements @(
      "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED BY '${PosPass}'",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED BY '${PosPass}'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
      "FLUSH PRIVILEGES"
    )
    if (-not $ok) { Fail "Impossible de créer la base '$DbName' ou l'utilisateur '$PosUser'." }
    Write-OK "Base '$DbName' et utilisateur '$PosUser' créés."
    $DbUser = $PosUser ; $DbPass = $PosPass

  # ── CAS 3 : MySQL complètement absent — téléchargement et installation ───
  } else {
    Write-Host "  MySQL non détecté — installation en cours..." -ForegroundColor DarkGray

    if (-not (Test-Path "$MysqlInstDir\bin\mysqld.exe")) {
      if (Test-Path $MysqlZipLocal) {
        Write-Host "  ZIP MySQL trouvé dans $InstallRoot — extraction..." -ForegroundColor DarkGray
      } else {
        Write-Host "  Téléchargement MySQL $MysqlVer..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $MysqlUrl -OutFile $MysqlZipLocal -UseBasicParsing
        Write-OK "ZIP téléchargé."
      }
      New-Item -Path (Split-Path $MysqlInstDir -Parent) -ItemType Directory -Force | Out-Null
      Expand-Archive $MysqlZipLocal "$env:TEMP\mysql_tmp" -Force
      Move-Item "$env:TEMP\mysql_tmp\mysql-$MysqlVer-winx64" $MysqlInstDir
      Remove-Item "$env:TEMP\mysql_tmp" -Recurse -Force
      Write-OK "MySQL extrait dans $MysqlInstDir"
    }

    $mysqldExe = "$MysqlInstDir\bin\mysqld.exe"
    $mysqlExe  = "$MysqlInstDir\bin\mysql.exe"
    $dataDir   = "C:\ProgramData\POS_Connect_MySQL"

    $baseDirFwd = $MysqlInstDir -replace '\\', '/'
    $dataDirFwd = $dataDir      -replace '\\', '/'
    Write-UTF8NoBOM "$MysqlInstDir\my.ini" @"
[mysqld]
basedir  = "$baseDirFwd"
datadir  = "$dataDirFwd"
port     = $DbPort
max_allowed_packet = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default-authentication-plugin = mysql_native_password
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
innodb_buffer_pool_size = 64M
max_connections = 50

[mysql]
default-character-set = utf8mb4
port = $DbPort

[client]
port = $DbPort
"@

    if (-not (Test-Path $dataDir)) {
      New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
      & $mysqldExe --defaults-file="$MysqlInstDir\my.ini" --initialize-insecure --console 2>&1 | Out-Null
      Write-OK "Répertoire de données initialisé."
    }

    $svcName = "POS_Connect_MySQL"
    if (-not (Get-Service $svcName -ErrorAction SilentlyContinue)) {
      & $mysqldExe --install $svcName --defaults-file="$MysqlInstDir\my.ini" 2>&1 | Out-Null
    }
    Start-Service $svcName
    Start-Sleep -Seconds 5

    $RootPass = New-RandPass 24
    $ok = Invoke-Sql -Exe $mysqlExe -Host $DbHost -Port $DbPort -User "root" -Pass "" -Statements @(
      "ALTER USER 'root'@'localhost' IDENTIFIED BY '${RootPass}'",
      "CREATE DATABASE IF NOT EXISTS ``${DbName}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'localhost'  IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
      "CREATE USER IF NOT EXISTS '${PosUser}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${PosPass}'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'localhost'",
      "GRANT ALL PRIVILEGES ON ``${DbName}``.* TO '${PosUser}'@'127.0.0.1'",
      "FLUSH PRIVILEGES"
    )
    if (-not $ok) { Fail "Impossible de configurer MySQL." }
    Write-OK "MySQL installé, base '$DbName' et utilisateur '$PosUser' créés."
    $DbUser = $PosUser ; $DbPass = $PosPass
  }

  # Afficher le mot de passe root si généré
  if ($RootPass) {
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  Mot de passe root MySQL : $RootPass" -ForegroundColor Yellow
    Write-Host "  │  Notez-le maintenant — il ne sera plus affiché.          │" -ForegroundColor Yellow
    Write-Host "  └──────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
  }

  # ── Écrire pos_server.ini (UTF-8 sans BOM) ───────────────────────────────
  $SecretKey = New-HexKey 32
  Write-UTF8NoBOM $IniPath @"
[database]
type     = mysql
host     = $DbHost
port     = $DbPort
name     = $DbName
user     = $DbUser
password = $DbPass

[server]
host                 = 0.0.0.0
port                 = 9003
secret_key           = $SecretKey
token_expire_minutes = 480
admin_email          =
admin_password_hash  =

cloud_sync_url        =
cloud_sync_token      =
cloud_sync_enabled    = false
identity_private_key  =
billing_url           =
cors_origins          = *
web_dir               = web
"@
  Write-OK "pos_server.ini généré dans $IniPath"

} # fin bloc DB

# ── 8. Télécharger NSSM si le dossier est absent ─────────────────────────────
Write-Step "NSSM (gestionnaire de services Windows)..."
if (Test-Path $NssmDir) {
    Write-Host "  Dossier NSSM déjà présent — téléchargement ignoré." -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Path $NssmDir -Force | Out-Null
    $nssmZip = "$env:TEMP\nssm.zip"
    Write-Host "  Téléchargement..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $NssmUrl -OutFile $nssmZip -UseBasicParsing
    Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm_tmp" -Force
    Copy-Item "$env:TEMP\nssm_tmp\nssm-2.24\win64\nssm.exe" $NssmExe -Force
    Remove-Item "$env:TEMP\nssm_tmp" -Recurse -Force
    Remove-Item $nssmZip -Force
    Write-OK "NSSM installé dans $NssmDir"
}

# ── 9. Service Nginx ──────────────────────────────────────────────────────────
Write-Step "Service Windows : $NginxSvc..."
$svc = Get-Service -Name $NginxSvc -ErrorAction SilentlyContinue
if ($svc) {
    & $NssmExe stop   $NginxSvc 2>$null
    & $NssmExe remove $NginxSvc confirm 2>$null
}
& $NssmExe install $NginxSvc "`"$NginxDir\nginx.exe`""
& $NssmExe set     $NginxSvc AppDirectory "`"$NginxDir`""
& $NssmExe set     $NginxSvc DisplayName  "POS Connect - Nginx"
& $NssmExe set     $NginxSvc Description  "Reverse proxy HTTPS pour POS Connect local"
& $NssmExe set     $NginxSvc Start SERVICE_AUTO_START
& $NssmExe start   $NginxSvc
Write-OK "Service $NginxSvc démarré."

# ── 10. Service API (FastAPI compilé Nuitka) ──────────────────────────────────
Write-Step "Service Windows : $ApiSvc..."
if (-not (Test-Path $ApiExe)) {
    Write-Warn "posconnect-server.exe introuvable — service $ApiSvc non créé."
    Write-Warn "Copie le build (backend-windows) dans $ApiDir puis relance ce script."
} else {
    $svc = Get-Service -Name $ApiSvc -ErrorAction SilentlyContinue
    if ($svc) {
        & $NssmExe stop   $ApiSvc 2>$null
        & $NssmExe remove $ApiSvc confirm 2>$null
    }
    & $NssmExe install $ApiSvc "`"$ApiExe`""
    & $NssmExe set     $ApiSvc AppDirectory "`"$ApiDir`""
    & $NssmExe set     $ApiSvc DisplayName  "POS Connect - API"
    & $NssmExe set     $ApiSvc Description  "Serveur FastAPI compilé avec Nuitka"
    & $NssmExe set     $ApiSvc Start SERVICE_AUTO_START
    & $NssmExe start   $ApiSvc
    Write-OK "Service $ApiSvc démarré."
}

# ── 11. Ports pare-feu (avec les ports réels choisis) ────────────────────────
Write-Step "Pare-feu (ports $HttpPort, $HttpsPort, 9003)..."
foreach ($port in @($HttpPort, $HttpsPort, 9003)) {
    $rule = "POS Connect Port $port"
    if (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue) {
        Write-Host "  Port $port déjà autorisé." -ForegroundColor DarkGray
    } else {
        New-NetFirewallRule -DisplayName $rule `
            -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        Write-OK "Port $port ouvert."
    }
}

# ── 12. Fichier hosts ─────────────────────────────────────────────────────────
Write-Step "Fichier hosts..."
$hosts = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
if ($hosts -and $hosts -match [regex]::Escape($Hostname)) {
    Write-Host "  $Hostname déjà présent." -ForegroundColor DarkGray
} else {
    Add-Content $HostsFile "`r`n127.0.0.1`t$Hostname"
    Write-OK "$Hostname ajouté."
}

# ── Résumé ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  ✓ Installation terminée !" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
Write-Host ""
$FinalUrl = if ($HttpsPort -eq 443) { "https://$Hostname" } else { "https://${Hostname}:${HttpsPort}" }
Write-Host "  Dossier  : $InstallRoot" -ForegroundColor White
Write-Host "  Nginx    : service '$NginxSvc'  (HTTP=$HttpPort  HTTPS=$HttpsPort)" -ForegroundColor White
Write-Host "  API      : service '$ApiSvc'    (port 9003)" -ForegroundColor White
Write-Host "  URL      : $FinalUrl" -ForegroundColor White
Write-Host ""
