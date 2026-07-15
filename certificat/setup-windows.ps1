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
#      pos_server.ini
#      .env
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
$NssmExe      = Join-Path $InstallRoot "nssm.exe"

$NginxVer     = "1.27.4"
$NginxUrl     = "https://nginx.org/download/nginx-$NginxVer.zip"
$NssmUrl      = "https://nssm.cc/release/nssm-2.24.zip"

$HostsFile    = "C:\Windows\System32\drivers\etc\hosts"
$Hostname     = "infini-post.local"
$NginxSvc     = "POS-Nginx"
$ApiSvc       = "POS-API"
$ApiExe       = Join-Path $ApiDir "posconnect-server.exe"

function Write-Step($msg) { Write-Host "`n→ $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`n  X $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  POS Connect — Setup serveur local Windows      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ── 0. Vérifier les certificats ───────────────────────────────────────────────
Write-Step "Vérification des certificats..."
if (-not (Test-Path "$ScriptDir\server.crt")) { Fail "server.crt introuvable dans $ScriptDir" }
if (-not (Test-Path "$ScriptDir\server.key")) { Fail "server.key introuvable dans $ScriptDir" }
Write-OK "Certificats présents."

# ── 1. Créer le dossier d'installation ───────────────────────────────────────
Write-Step "Dossier d'installation : $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Write-OK "Dossier prêt."

# ── 2. Vérifier les conflits de port avant de continuer ──────────────────────
Write-Step "Vérification des ports 80 et 443..."
$portConflict = $false
foreach ($port in @(80, 443)) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.Name } else { "PID $($conn.OwningProcess)" }
        # Conflit uniquement si ce n'est PAS notre propre service nginx
        if ($name -ne "nginx") {
            Write-Warn "Port $port déjà utilisé par '$name' (PID $($conn.OwningProcess))."
            Write-Warn "Arrête ce processus avant de continuer, sinon nginx ne démarrera pas."
            $portConflict = $true
        } else {
            Write-Host "  Port $port : nginx déjà en écoute (sera reconfiguré)." -ForegroundColor DarkGray
        }
    }
}
if ($portConflict) {
    $rep = Read-Host "`n  Continuer quand même ? (o/N)"
    if ($rep -notmatch '^[oOyY]') { exit 1 }
}

# ── 3. Télécharger Nginx si nginx.exe absent ──────────────────────────────────
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

# ── 4. Appliquer la configuration (toujours, même si nginx existait déjà) ─────
# Cette étape s'exécute à chaque lancement du script pour s'assurer
# que les certificats et la config sont à jour.
Write-Step "Configuration Nginx (certs + nginx.conf)..."
New-Item -ItemType Directory -Path $NginxCerts -Force | Out-Null
Copy-Item "$ScriptDir\server.crt"         "$NginxCerts\server.crt" -Force
Copy-Item "$ScriptDir\server.key"         "$NginxCerts\server.key" -Force
Copy-Item "$ScriptDir\nginx-windows.conf" "$NginxConf\default.conf" -Force

Set-Content "$NginxConf\nginx.conf" @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    include conf/default.conf;
}
"@ -Encoding UTF8
Write-OK "Certificats et configuration appliqués."

# ── 5. Copier les fichiers API (build Nuitka) ─────────────────────────────────
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

# ── 6. Copier pos_server.ini et .env ─────────────────────────────────────────
Write-Step "Fichiers de configuration..."
foreach ($f in @("pos_server.ini", ".env")) {
    $src = Join-Path $PackageDir $f
    $dst = Join-Path $InstallRoot $f
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-OK "$f copié."
    } else {
        Write-Warn "$f introuvable dans le package — à configurer manuellement dans $InstallRoot"
    }
}

# ── 7. Télécharger NSSM ───────────────────────────────────────────────────────
Write-Step "NSSM (gestionnaire de services Windows)..."
if (Test-Path $NssmExe) {
    Write-Host "  NSSM déjà présent." -ForegroundColor DarkGray
} else {
    $nssmZip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri $NssmUrl -OutFile $nssmZip -UseBasicParsing
    Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm_tmp" -Force
    Copy-Item "$env:TEMP\nssm_tmp\nssm-2.24\win64\nssm.exe" $NssmExe -Force
    Remove-Item "$env:TEMP\nssm_tmp" -Recurse -Force
    Remove-Item $nssmZip -Force
    Write-OK "NSSM installé."
}

# ── 8. Service Nginx ──────────────────────────────────────────────────────────
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

# ── 9. Service API (FastAPI compilé Nuitka) ────────────────────────────────────
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

# ── 10. Ports pare-feu : 80, 443, 9003 ───────────────────────────────────────
Write-Step "Pare-feu (ports 80, 443, 9003)..."
foreach ($port in @(80, 443, 9003)) {
    $rule = "POS Connect Port $port"
    if (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue) {
        Write-Host "  Port $port déjà autorisé." -ForegroundColor DarkGray
    } else {
        New-NetFirewallRule -DisplayName $rule `
            -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        Write-OK "Port $port ouvert."
    }
}

# ── 11. Certificat dans le magasin de confiance Windows ──────────────────────
Write-Step "Certificat dans le magasin de confiance Windows..."
try {
    $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$ScriptDir\server.crt")
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $store.Certificates |
        Where-Object { $_.Subject -eq $cert.Subject } |
        ForEach-Object { $store.Remove($_) }
    $store.Add($cert)
    $store.Close()
    Write-OK "Certificat approuvé."
} catch {
    Fail "Impossible d'ajouter le certificat : $_"
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
Write-Host "  Dossier  : $InstallRoot" -ForegroundColor White
Write-Host "  Nginx    : service '$NginxSvc'  (ports 80/443)" -ForegroundColor White
Write-Host "  API      : service '$ApiSvc'    (port 9003)" -ForegroundColor White
Write-Host "  URL      : https://infini-post.local" -ForegroundColor White
Write-Host ""
