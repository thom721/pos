# ============================================================
#  POS Connect — Installation serveur local Windows
#  - Installe Nginx comme service Windows (via NSSM)
#  - Configure HTTPS avec le certificat fourni
#  - Ouvre les ports 80 et 443 dans le pare-feu
#  - Approuve le certificat dans le magasin Windows
#  - Ajoute infini-post.local dans le fichier hosts
#
#  Pré-requis : server.crt et server.key dans ce même dossier
#  Doit être lancé en tant qu'Administrateur
# ============================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir  = "C:\POS_Connect\nginx"
$CertDir     = "$InstallDir\certs"
$ConfDir     = "$InstallDir\conf"
$NssmExe     = "C:\POS_Connect\nssm.exe"
$NginxVer    = "1.27.4"
$NginxUrl    = "https://nginx.org/download/nginx-$NginxVer.zip"
$NssmUrl     = "https://nssm.cc/release/nssm-2.24.zip"
$HostsFile   = "C:\Windows\System32\drivers\etc\hosts"
$Hostname    = "infini-post.local"
$ServiceName = "POS-Nginx"

function Write-Step($msg) { Write-Host "`n→ $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  X $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  POS Connect — Setup serveur local Windows      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ── 0. Vérifier que les certificats sont présents ─────────────────────────────
Write-Step "Vérification des certificats..."
if (-not (Test-Path "$ScriptDir\server.crt")) { Write-Err "server.crt introuvable dans $ScriptDir" }
if (-not (Test-Path "$ScriptDir\server.key")) { Write-Err "server.key introuvable dans $ScriptDir" }
Write-OK "Certificats présents."

# ── 1. Télécharger et extraire Nginx pour Windows ─────────────────────────────
Write-Step "Nginx $NginxVer..."
if (Test-Path "$InstallDir\nginx.exe") {
    Write-Host "  Nginx déjà installé dans $InstallDir." -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Path "C:\POS_Connect" -Force | Out-Null
    $nginxZip = "$env:TEMP\nginx-$NginxVer.zip"
    Write-Host "  Téléchargement..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $NginxUrl -OutFile $nginxZip -UseBasicParsing
    Expand-Archive -Path $nginxZip -DestinationPath "C:\POS_Connect\nginx_tmp" -Force
    Move-Item "C:\POS_Connect\nginx_tmp\nginx-$NginxVer" $InstallDir
    Remove-Item "C:\POS_Connect\nginx_tmp" -Recurse -Force
    Remove-Item $nginxZip -Force
    Write-OK "Nginx extrait dans $InstallDir"
}

# ── 2. Copier les certificats et la config ────────────────────────────────────
Write-Step "Configuration Nginx..."
New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
Copy-Item "$ScriptDir\server.crt" "$CertDir\server.crt" -Force
Copy-Item "$ScriptDir\server.key" "$CertDir\server.key" -Force
Copy-Item "$ScriptDir\nginx-windows.conf" "$ConfDir\default.conf" -Force

# Vider la config principale nginx.conf (inclut conf/*.conf)
$nginxConf = "$ConfDir\nginx.conf"
$mainConf = @"
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
Set-Content $nginxConf $mainConf -Encoding UTF8
Write-OK "Config et certificats copiés."

# ── 3. Télécharger NSSM (gestionnaire de services) ────────────────────────────
Write-Step "NSSM (service manager)..."
if (Test-Path $NssmExe) {
    Write-Host "  NSSM déjà présent." -ForegroundColor DarkGray
} else {
    $nssmZip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri $NssmUrl -OutFile $nssmZip -UseBasicParsing
    Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm_tmp" -Force
    # Prendre le binaire 64-bit
    Copy-Item "$env:TEMP\nssm_tmp\nssm-2.24\win64\nssm.exe" $NssmExe -Force
    Remove-Item "$env:TEMP\nssm_tmp" -Recurse -Force
    Remove-Item $nssmZip -Force
    Write-OK "NSSM installé."
}

# ── 4. Enregistrer Nginx comme service Windows ────────────────────────────────
Write-Step "Service Windows $ServiceName..."
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "  Service existant — arrêt et reconfiguration..." -ForegroundColor DarkGray
    & $NssmExe stop $ServiceName 2>$null
    & $NssmExe remove $ServiceName confirm 2>$null
}
& $NssmExe install $ServiceName "$InstallDir\nginx.exe"
& $NssmExe set $ServiceName AppDirectory $InstallDir
& $NssmExe set $ServiceName DisplayName "POS Connect - Nginx"
& $NssmExe set $ServiceName Description "Reverse proxy HTTPS pour POS Connect local"
& $NssmExe set $ServiceName Start SERVICE_AUTO_START
& $NssmExe start $ServiceName
Write-OK "Service $ServiceName démarré."

# ── 5. Ouvrir les ports 80 et 443 dans le pare-feu Windows ───────────────────
Write-Step "Pare-feu (ports 80 et 443)..."
foreach ($port in @(80, 443)) {
    $ruleName = "POS Connect Port $port"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Port $port déjà autorisé." -ForegroundColor DarkGray
    } else {
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound -Protocol TCP `
            -LocalPort $port -Action Allow | Out-Null
        Write-OK "Port $port ouvert."
    }
}

# ── 6. Approuver le certificat dans le magasin Racine Windows ─────────────────
Write-Step "Certificat dans le magasin de confiance Windows..."
try {
    $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$ScriptDir\server.crt")
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $existing = $store.Certificates | Where-Object { $_.Subject -eq $cert.Subject }
    foreach ($old in $existing) { $store.Remove($old) }
    $store.Add($cert)
    $store.Close()
    Write-OK "Certificat approuvé."
} catch {
    Write-Err "Impossible d'ajouter le certificat : $_"
}

# ── 7. Ajouter infini-post.local dans le fichier hosts ────────────────────────
Write-Step "Fichier hosts..."
$hostsContent = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
if ($hostsContent -and $hostsContent -match [regex]::Escape($Hostname)) {
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
Write-Host "  Nginx   : service '$ServiceName' (démarrage automatique)" -ForegroundColor White
Write-Host "  URL     : https://infini-post.local" -ForegroundColor White
Write-Host ""
Write-Host "  Note : FastAPI doit tourner sur 127.0.0.1:9003" -ForegroundColor DarkGray
Write-Host "  (python -m uvicorn api.main:app --host 127.0.0.1 --port 9003)" -ForegroundColor DarkGray
Write-Host ""
