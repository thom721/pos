<#
.SYNOPSIS
    Configure POS Connect apres installation Inno Setup.
    -DbType mysql  : telecharge MySQL (si absent), extrait, initialise, cree les services
    -DbType sqlite : cree pos_server.ini SQLite uniquement, pas de MySQL
    Dans les deux cas : installe les services API + Nginx, ecrit pos_server.ini.
#>
param(
    [ValidateSet("mysql", "sqlite")]
    [string]$DbType = "mysql"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# -- Chemins --------------------------------------------------------------------
$InstallDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir     = "$env:ProgramData\POS_Connect"
$NssmExe     = "$InstallDir\nssm\nssm.exe"
$NginxExe    = "$InstallDir\nginx\nginx.exe"
$ApiExe      = "$InstallDir\posconnect-server.exe"
$MySqlVersion = "8.0.41"
$MySqlZip    = "$InstallDir\mysql-$MySqlVersion-winx64.zip"
$MySqlZipUrl = "https://downloads.mysql.com/archives/get/p/23/file/mysql-$MySqlVersion-winx64.zip"
$MySqlDir    = "$InstallDir\mysql"
# Donnees MySQL dans un dossier separe -- survivent a toute suppression de POS_Connect
$MySqlData   = "$env:ProgramData\POS_Connect_MySQL\data"
# my.ini dans le dossier BINAIRE (pas dans le datadir) :
# MySQL 8 verifie la securite du --defaults-file et refuse d'ouvrir un fichier
# situe dans le datadir ou dans un dossier trop permissif.
$MyIni       = "$MySqlDir\my.ini"
$MySqlBinDir = "$MySqlDir\bin"
$MySqlPort   = 3307
$IniTarget    = "$DataDir\pos_server.ini"
$LogFile      = "$DataDir\install.log"
$InitFlagFile = "$DataDir\mysql_init_ok.flag"

# -- Journalisation -------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts [$Level] $Msg" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

# -- Ecriture UTF-8 SANS BOM ----------------------------------------------------
# PowerShell 5.1 (natif Windows) ecrit un BOM avec -Encoding UTF8 / Out-File.
# [System.IO.File]::WriteAllText avec UTF8Encoding($false) garantit l'absence de BOM
# sur toutes les versions de PowerShell, ce qui est requis par Python configparser
# et par mysqld qui rejettent les fichiers debutant par ﻿.
function Write-UTF8NoBOM {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

Write-Log "=== Debut de la configuration POS Connect ==="
Write-Log "InstallDir : $InstallDir"
Write-Log "DataDir    : $DataDir"

# -- Verification droits Administrateur ----------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "ERREUR : ce script doit etre execute en tant qu'Administrateur." "ERROR"
    Write-Log "Relancez posconnect-server.exe via un terminal Administrateur." "ERROR"
    Write-Log "=== Configuration POS Connect terminee (erreur droits) ===" "ERROR"
    exit 1
}

# -- 0. Visual C++ Redistributable (requis par MySQL 8) ------------------------
$VcRuntime = "$env:SystemRoot\System32\vcruntime140.dll"
if (-not (Test-Path $VcRuntime)) {
    Write-Log "vcruntime140.dll absent -- installation du Visual C++ Redistributable..." "WARN"
    $VcRedist = "$InstallDir\vcredist\vc_redist.x64.exe"
    if (-not (Test-Path $VcRedist)) {
        Write-Log "Telechargement vc_redist.x64.exe depuis Microsoft..."
        $VcRedistDir = "$InstallDir\vcredist"
        New-Item -ItemType Directory -Force -Path $VcRedistDir | Out-Null
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            (New-Object System.Net.WebClient).DownloadFile(
                "https://aka.ms/vs/17/release/vc_redist.x64.exe",
                $VcRedist
            )
            Write-Log "vc_redist.x64.exe telecharge"
        } catch {
            Write-Log "Impossible de telecharger vc_redist : $_" "WARN"
        }
    }
    if (Test-Path $VcRedist) {
        Write-Log "Installation vc_redist.x64.exe (silencieux)..."
        Start-Process -FilePath $VcRedist -ArgumentList "/install /quiet /norestart" `
            -Wait -NoNewWindow
        if (Test-Path $VcRuntime) {
            Write-Log "Visual C++ Redistributable installe avec succes"
        } else {
            Write-Log "vcruntime140.dll toujours absent apres install -- MySQL pourrait echouer" "WARN"
        }
    }
} else {
    Write-Log "Visual C++ Redistributable OK ($VcRuntime)"
}

# -- 1. Certificat SSL ----------------------------------------------------------
$CertFile = "$InstallDir\certificat\server.crt"
if (Test-Path $CertFile) {
    try {
        $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertFile)
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        Write-Log "Certificat SSL installe"
    } catch {
        Write-Log "Certificat SSL : $_" "WARN"
    }
} else {
    Write-Log "Certificat absent ($CertFile) -- ignore" "WARN"
}

# -- 2. Arreter tous les services POS avant toute operation sur les fichiers ---
# Fait ICI (avant extraction) pour que mysqld.exe ne soit pas verrouille
# lors de la reinstallation -- un service actif empeche d'ecraser le binaire.
foreach ($killSvc in @("POS_Connect_Nginx", "POS_Connect_API", "POS_Connect_MySQL")) {
    $ks = Get-Service -Name $killSvc -ErrorAction SilentlyContinue
    if ($ks) {
        if ($ks.Status -eq "Paused") {
            Resume-Service -Name $killSvc -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        if ((Get-Service -Name $killSvc -ErrorAction SilentlyContinue).Status -ne "Stopped") {
            Write-Log "Arret $killSvc avant extraction..."
            Stop-Service -Name $killSvc -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
}
if ($DbType -eq "mysql") {
    # Tuer tout processus mysqld residuel avant d'ecraser les binaires
    $zomb = @(Get-Process -Name "mysqld" -ErrorAction SilentlyContinue)
    if ($zomb.Count -gt 0) {
        Write-Log "Arret force $($zomb.Count) processus mysqld avant extraction..."
        $zomb | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    # -- 2b. MySQL : telecharger si ZIP absent ------------------------------------
    if (-not (Test-Path "$MySqlBinDir\mysqld.exe")) {
        if (-not (Test-Path $MySqlZip)) {
            Write-Log "MySQL ZIP absent -- telechargement depuis MySQL officiel..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $wc = New-Object System.Net.WebClient
                $wc.DownloadFile($MySqlZipUrl, $MySqlZip)
                $sizeMb = [math]::Round((Get-Item $MySqlZip).Length / 1MB, 1)
                Write-Log "MySQL $MySqlVersion telecharge ($sizeMb Mo)"
            } catch {
                Write-Log "Impossible de telecharger MySQL : $_" "WARN"
            }
        }

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
}

# -- 3. Base de donnees : MySQL ou SQLite ---------------------------------------
if ($DbType -eq "mysql") {
    # Creer le datadir avec permissions strictes via API .NET.
    # Fait TOUJOURS (fresh install ET reinstallation) car :
    # - InnoSetup ne cree plus ce dossier (evite l'heritage des ACL de C:\ProgramData)
    # - MySQL 8 refuse un datadir accessible a BUILTIN\Users (errno 13 world-writable)
    # SetAccessRuleProtection($true, $false) = bloque l'heritage, n'en copie aucun.
    New-Item -ItemType Directory -Force -Path $MySqlData | Out-Null
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        Set-Acl -Path $MySqlData -AclObject $acl
        Write-Log "Permissions datadir MySQL : SYSTEM + Administrateurs (heritage bloque)"
    } catch {
        Write-Log "ACL .NET echoue : $_ -- fallback icacls" "WARN"
        takeown /F "$MySqlData" /R /D Y 2>&1 | Out-Null
        icacls "$MySqlData" /reset /T /C /Q 2>&1 | Out-Null
        icacls "$MySqlData" /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
    }

    # -- Variables DB et mot de passe generes AVANT l'init ---------------------
    # Meme approche que MySQLInstaller (Main_run.py) : le mot de passe est connu
    # avant le demarrage de MySQL, mis dans init.sql que MySQL execute
    # automatiquement a CHAQUE demarrage via init-file dans [mysqld].
    # Aucun appel mysql.exe post-demarrage necessaire.
    $DbName  = "pos_db"
    $DbUser  = "pos_user"
    $MySqlExe = "$MySqlBinDir\mysql.exe"

    # Reutiliser mot de passe existant si pos_server.ini deja configure
    $DbPass = $null
    if (Test-Path $IniTarget) {
        foreach ($line in (Get-Content $IniTarget)) {
            if ($line -match '^\s*password\s*=\s*(.+)$') { $DbPass = $Matches[1].Trim(); break }
        }
    }
    if (-not $DbPass) {
        $chars  = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        $DbPass = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }

    $InitSqlFwd  = ($MySqlDir -replace '\\', '/') + '/init.sql'
    $InitSqlPath = "$MySqlDir\init.sql"
    $hasFlag     = Test-Path $InitFlagFile
    $hasIbdata   = Test-Path "$MySqlData\ibdata1"

    # my.ini : identique dans les trois cas (flag / recuperation / fresh init).
    # Toujours ecrit pour garantir que les parametres sont a jour.
    # innodb_flush_method=normal est OBLIGATOIRE sur Windows (pas O_DIRECT).
    Write-UTF8NoBOM $MyIni @"
[mysqld]
basedir = $MySqlDir
datadir = $MySqlData
bind-address = 0.0.0.0
port = $MySqlPort
socket = mysql${MySqlPort}.sock
skip_shared_memory = ON
shared_memory = OFF
skip_name_resolve = ON
log_bin_trust_function_creators = 1

# InnoDB
innodb_force_recovery = 0
innodb_flush_method = normal
innodb_buffer_pool_size = 512M
innodb_redo_log_capacity = 268435456
innodb_file_per_table = ON
innodb_flush_log_at_trx_commit = 2
innodb_buffer_pool_instances = 2

init-file = $InitSqlFwd
authentication_policy = caching_sha2_password,mysql_native_password
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

# Journaux
log_error = $DataDir\logs\mysql-error.log
general_log_file = $DataDir\logs\mysql-query.log
general_log = 1

# Memoire
key_buffer_size = 232M
max_allowed_packet = 464M
thread_cache_size = 10
table_open_cache = 2000
max_connections = 50

[mysql]
default-character-set = utf8mb4
port = $MySqlPort

[client]
port = $MySqlPort
"@

    if ($hasFlag) {
        # -- CAS 1 : installation connue comme operationnelle --------------------
        Write-Log "MySQL connu operationnel (flag present) -- my.ini mis a jour, donnees intactes"

    } elseif ($hasIbdata) {
        # -- CAS 2 : donnees presentes mais flag absent (ancien install ou flag supprime)
        # SECURITE : on ne touche PAS aux donnees. On tente juste de demarrer MySQL
        # avec les donnees existantes. Si ca marche, le flag sera ecrit plus bas.
        Write-Log "Recuperation MySQL : ibdata1 detecte dans le datadir -- flag absent" "WARN"
        Write-Log "SECURITE : les donnees MySQL existantes sont conservees -- pas de reinitialisation"
        # init.sql avec IF NOT EXISTS : inoffensif si user/db existent deja
        Write-UTF8NoBOM $InitSqlPath @"
CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1'   IDENTIFIED WITH caching_sha2_password BY '';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
CREATE USER IF NOT EXISTS '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER USER '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER USER '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@
        Write-Log "init.sql (re)ecrit pour recuperation -- sera efface apres confirmation"

    } else {
        # -- CAS 3 : datadir vide ou absent -- initialisation fraiche -----------
        Write-Log "Initialisation MySQL (datadir vide ou absent)..."
        # init.sql avec credentials -- sera efface apres confirmation operationnelle
        Write-UTF8NoBOM $InitSqlPath @"
CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1'   IDENTIFIED WITH caching_sha2_password BY '';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
CREATE USER IF NOT EXISTS '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER USER '$DbUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$DbPass';
ALTER USER '$DbUser'@'localhost'  IDENTIFIED WITH mysql_native_password BY '$DbPass';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@
        Write-Log "init.sql cree (contenu sera efface apres confirmation)"

        # Nettoyer les residus d'une init incomplete (#innodb_redo, #innodb_temp...).
        # Remove-Item echoue silencieusement sur ces fichiers systeme MySQL.
        # rd /s /q (cmd.exe) les supprime de force.
        $residus = @(Get-ChildItem -Path "$MySqlData" -Force -ErrorAction SilentlyContinue)
        if ($residus.Count -gt 0) {
            Write-Log "Nettoyage de $($residus.Count) fichier(s) residuel(s) dans le datadir (rd /s /q)..."
            cmd.exe /c "rd /s /q `"$MySqlData`"" 2>&1 | ForEach-Object { Write-Log "  [rd] $_" }
            Start-Sleep -Seconds 3
            New-Item -ItemType Directory -Force -Path $MySqlData | Out-Null
            $apresNettoyage = @(Get-ChildItem -Path "$MySqlData" -Force -ErrorAction SilentlyContinue)
            if ($apresNettoyage.Count -gt 0) {
                Write-Log "ATTENTION : $($apresNettoyage.Count) fichier(s) encore presents -- init risque d'echouer" "WARN"
                $apresNettoyage | ForEach-Object { Write-Log "  residuel: $($_.Name)" "WARN" }
            } else {
                Write-Log "Datadir vide apres nettoyage -- pret pour init"
            }
            try {
                $aclR = New-Object System.Security.AccessControl.DirectorySecurity
                $aclR.SetAccessRuleProtection($true, $false)
                $aclR.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
                $aclR.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
                Set-Acl -Path $MySqlData -AclObject $aclR
                Write-Log "Permissions reappliquees sur datadir vide"
            } catch {
                Write-Log "ACL apres nettoyage : $_" "WARN"
            }
        }

        # --defaults-file obligatoire : sans lui mysqld cherche my.ini dans C:\Windows\
        # et pourrait trouver un fichier d'une ancienne installation.
        $_initOut  = & "$MySqlBinDir\mysqld.exe" "--defaults-file=$MyIni" --initialize-insecure --console 2>&1
        $_initCode = $LASTEXITCODE
        $_initOut | ForEach-Object { Write-Log "  [mysqld-init] $_" }
        if ($_initCode -ne 0) {
            Write-Log "mysqld --initialize-insecure a echoue (code $_initCode)" "ERROR"
        } else {
            Write-Log "MySQL initialise -- init.sql s'executera au premier demarrage du service"
        }
    }

    # -- Service MySQL ----------------------------------------------------------
    $SvcMySQL = "POS_Connect_MySQL"
    $svcStatus = & $NssmExe status $SvcMySQL 2>&1
    if ($LASTEXITCODE -ne 0 -or "$svcStatus" -match "can't open service|No such service") {
        Write-Log "Installation service $SvcMySQL..."
        & $NssmExe install $SvcMySQL "$MySqlBinDir\mysqld.exe"
        & $NssmExe set    $SvcMySQL DisplayName   "POS Connect -- MySQL"
        & $NssmExe set    $SvcMySQL Description   "Base de donnees MySQL locale pour POS Connect"
        & $NssmExe set    $SvcMySQL Start         SERVICE_AUTO_START
        & $NssmExe set    $SvcMySQL AppStdout     "$DataDir\mysql-stdout.log"
        & $NssmExe set    $SvcMySQL AppStderr     "$DataDir\mysql-stderr.log"
        Write-Log "Service $SvcMySQL installe"
    } else {
        Write-Log "Service $SvcMySQL existe deja ($svcStatus) -- deja arrete en section 2"
    }
    # Toujours mettre a jour AppParameters pour corriger le chemin my.ini (reinstallation)
    & $NssmExe set $SvcMySQL AppParameters "--defaults-file=$MyIni"

    # Demarrer MySQL et attendre qu'il soit pret
    Start-Service -Name $SvcMySQL -ErrorAction SilentlyContinue
    Write-Log "Attente demarrage MySQL..."
    $MySqlReady = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        $ping = & "$MySqlBinDir\mysqladmin.exe" --host=127.0.0.1 --port=$MySqlPort `
                    --user=root --connect-timeout=2 ping 2>&1
        if ("$ping" -match "mysqld is alive") {
            $MySqlReady = $true
            Write-Log "MySQL pret (${i}x2s)"
            break
        }
    }
    if (-not $MySqlReady) {
        Write-Log "MySQL n'a pas repondu dans les 40s" "WARN"
        # Lire les dernieres lignes du log MySQL pour faciliter le diagnostic
        $MySqlErrLog = "$DataDir\logs\mysql-error.log"
        if (Test-Path $MySqlErrLog) {
            Write-Log "--- Dernieres lignes de mysql-error.log ---" "WARN"
            Get-Content $MySqlErrLog -Tail 20 | ForEach-Object { Write-Log "  [mysql] $_" "WARN" }
            Write-Log "--- Fin mysql-error.log ---" "WARN"
        } else {
            Write-Log "mysql-error.log introuvable ($MySqlErrLog)" "WARN"
        }
    }

    # -- pos_server.ini MySQL (seulement si MySQL tourne) -------------------------
    if ($MySqlReady) {
        Write-Log "Base '$DbName' et utilisateur '$DbUser' configures via init.sql"
        Write-UTF8NoBOM $IniTarget @"
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
"@
        Write-Log "pos_server.ini ecrit (MySQL 127.0.0.1:$MySqlPort, db=$DbName, user=$DbUser)"
        icacls $IniTarget /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" 2>&1 | Out-Null
        Write-Log "Permissions pos_server.ini restreintes (SYSTEM + Administrateurs)"
        # Flag : MySQL completement operationnel -- la prochaine execution ne reinit pas
        Write-UTF8NoBOM $InitFlagFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') MySQL initialise et operationnel"
        Write-Log "Flag d'init MySQL ecrit : $InitFlagFile"
        # Effacer le contenu sensible de init.sql (mot de passe en clair).
        # MySQL continuera de trouver le fichier reference dans init-file de my.ini
        # mais n'executera rien -- les grants sont deja persistes dans mysql.user.
        Write-UTF8NoBOM $InitSqlPath "-- initialisation terminee $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Log "init.sql securise (contenu sensible efface)"
    } else {
        Write-Log "MySQL non demarre -- pos_server.ini NON ecrit, flag NON ecrit" "WARN"
    }

} else {
    # -- SQLite -------------------------------------------------------------------
    Write-Log "Configuration SQLite..."
    Write-UTF8NoBOM $IniTarget @"
[database]
type = sqlite
path = $DataDir\pos_connect.db

[server]
host = 0.0.0.0
port = 9003
"@
    Write-Log "pos_server.ini ecrit (SQLite : $DataDir\pos_connect.db)"
    icacls $IniTarget /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" 2>&1 | Out-Null
    Write-Log "Permissions pos_server.ini restreintes (SYSTEM + Administrateurs)"
}

# -- 3b. Permissions dossier de données (SQLite fallback inscriptible par SYSTEM) --
# Cas frequent : pos_connect.db cree par une installation precedente avec des
# permissions restrictives → SYSTEM ne peut pas ecrire → SQLITE_READONLY au demarrage.
Write-Log "Correction permissions $DataDir (SYSTEM + Administrateurs)..."
takeown /F "$DataDir" /R /D Y 2>&1 | Out-Null
icacls "$DataDir" /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Log "Permissions $DataDir accordees"
} else {
    Write-Log "icacls $DataDir code $LASTEXITCODE (non bloquant)" "WARN"
}

# -- 4. Service : POS Connect API -----------------------------------------------
$SvcApi = "POS_Connect_API"
$svcApiStatus = & $NssmExe status $SvcApi 2>&1
if ($LASTEXITCODE -ne 0 -or "$svcApiStatus" -match "can't open service|No such service") {
    Write-Log "Installation service $SvcApi..."
    & $NssmExe install $SvcApi $ApiExe
    & $NssmExe set    $SvcApi AppDirectory  $InstallDir
    & $NssmExe set    $SvcApi DisplayName   "POS Connect -- Serveur API"
    & $NssmExe set    $SvcApi Description   "Serveur API FastAPI POS Connect"
    & $NssmExe set    $SvcApi Start         SERVICE_AUTO_START
    & $NssmExe set    $SvcApi AppStdout     "$DataDir\api-stdout.log"
    & $NssmExe set    $SvcApi AppStderr     "$DataDir\api-stderr.log"
    if ($DbType -eq "mysql") {
        & $NssmExe set $SvcApi DependOnService "POS_Connect_MySQL"
    }
    Write-Log "Service $SvcApi installe"
} else {
    Write-Log "Service $SvcApi existe deja -- arret pour eviter conflit port 9003..."
    Stop-Service -Name $SvcApi -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# -- 4b. Configuration Nginx : conf + certificats -------------------------------
# Nginx lit ses fichiers relatifs a son prefix (dossier de nginx.exe).
# Structure attendue :
#   $InstallDir\nginx\conf\nginx.conf
#   $InstallDir\nginx\certs\server.crt   (ssl_certificate)
#   $InstallDir\nginx\certs\server.key   (ssl_certificate_key)
#   $InstallDir\nginx\logs\              (access.log, error.log)
#   $InstallDir\nginx\temp\              (fichiers temporaires)

$NginxConfDir  = "$InstallDir\nginx\conf"
$NginxCertsDir = "$InstallDir\nginx\certs"
$NginxLogsDir  = "$InstallDir\nginx\logs"
$NginxTempDir  = "$InstallDir\nginx\temp"

foreach ($d in @($NginxConfDir, $NginxCertsDir, $NginxLogsDir, $NginxTempDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# Copier les certificats SSL depuis le sous-dossier certificat\ du package
$SrcCert = "$InstallDir\certificat\server.crt"
$SrcKey  = "$InstallDir\certificat\server.key"
$SrcConf = "$InstallDir\certificat\nginx-windows.conf"

if (Test-Path $SrcCert) {
    Copy-Item $SrcCert "$NginxCertsDir\server.crt" -Force
    Write-Log "Certificat SSL nginx copie -> $NginxCertsDir\server.crt"
} else {
    Write-Log "server.crt introuvable ($SrcCert) -- nginx SSL ne fonctionnera pas" "WARN"
}
if (Test-Path $SrcKey) {
    Copy-Item $SrcKey "$NginxCertsDir\server.key" -Force
    Write-Log "Cle SSL nginx copiee -> $NginxCertsDir\server.key"
} else {
    Write-Log "server.key introuvable ($SrcKey) -- nginx SSL ne fonctionnera pas" "WARN"
}
if (Test-Path $SrcConf) {
    Copy-Item $SrcConf "$NginxConfDir\nginx.conf" -Force
    Write-Log "nginx.conf copie -> $NginxConfDir\nginx.conf"
} else {
    Write-Log "nginx-windows.conf introuvable ($SrcConf) -- nginx utilisera sa config par defaut" "WARN"
}

# -- 5. Service : Nginx ---------------------------------------------------------
$SvcNginx = "POS_Connect_Nginx"
$svcNginxStatus = & $NssmExe status $SvcNginx 2>&1
if ($LASTEXITCODE -ne 0 -or "$svcNginxStatus" -match "can't open service|No such service") {
    Write-Log "Installation service $SvcNginx..."
    & $NssmExe install $SvcNginx $NginxExe
    & $NssmExe set    $SvcNginx AppDirectory  "$InstallDir\nginx"
    & $NssmExe set    $SvcNginx DisplayName   "POS Connect -- Nginx"
    & $NssmExe set    $SvcNginx Description   "Reverse proxy Nginx pour POS Connect"
    & $NssmExe set    $SvcNginx Start         SERVICE_AUTO_START
    & $NssmExe set    $SvcNginx AppStdout     "$InstallDir\nginx\logs\nssm-stdout.log"
    & $NssmExe set    $SvcNginx AppStderr     "$InstallDir\nginx\logs\nssm-stderr.log"
    & $NssmExe set    $SvcNginx DependOnService "POS_Connect_API"
    Write-Log "Service $SvcNginx installe"
} else {
    Write-Log "Service $SvcNginx existe deja -- arret pour reinitialisation..."
    Stop-Service -Name $SvcNginx -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# -- 6. Demarrer API + Nginx ----------------------------------------------------
Write-Log "Demarrage des services API et Nginx..."
foreach ($svc in @($SvcApi, $SvcNginx)) {
    try {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq "Running") {
            Write-Log "  OK $svc demarre"
        } else {
            Write-Log "  WARN $svc n'a pas demarré (verifiez les logs)" "WARN"
        }
    } catch {
        Write-Log "  FAIL $svc : $_" "WARN"
    }
}

# -- 7. Regles pare-feu --------------------------------------------------------
# Profile Any = Private + Domain + Public : evite les blocages silencieux
# quand Windows classe le reseau en "Public" (reseaux inconnus, Wi-Fi public).

function Add-FwRule {
    param([string]$Name, [int]$Port)
    $existing = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        # Mettre a jour le profil si la regle existe deja avec Private/Domain seulement
        try {
            Set-NetFirewallRule -DisplayName $Name -Profile Any -ErrorAction SilentlyContinue
        } catch {}
        Write-Log "Regle pare-feu mise a jour (Any) : $Name"
    } else {
        try {
            New-NetFirewallRule `
                -DisplayName $Name `
                -Direction   Inbound `
                -Protocol    TCP `
                -LocalPort   $Port `
                -Action      Allow `
                -Profile     Any | Out-Null
            Write-Log "Regle pare-feu ajoutee (Any) : $Name -- port $Port"
        } catch {
            Write-Log "Pare-feu $Name : $_" "WARN"
        }
    }
}

Add-FwRule -Name "POS Connect Serveur API (9003)" -Port 9003
Add-FwRule -Name "POS Connect Nginx HTTP (80)"    -Port 80
Add-FwRule -Name "POS Connect Nginx HTTPS (443)"  -Port 443

Write-Log "=== Configuration POS Connect terminee ==="
Write-Log "Log complet : $LogFile"
