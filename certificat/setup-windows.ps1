# Setup Windows — infini-post.local
# Génère le certificat, l'approuve dans le magasin Windows et ajoute le host.
# Doit être lancé en tant qu'Administrateur.

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertFile   = Join-Path $ScriptDir "server.crt"
$KeyFile    = Join-Path $ScriptDir "server.key"
$CnfFile    = Join-Path $ScriptDir "openssl.cnf"
$HostsFile  = "C:\Windows\System32\drivers\etc\hosts"
$Hostname   = "infini-post.local"

Write-Host ""
Write-Host "=== POS Connect — Setup HTTPS local (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Générer le certificat si absent ────────────────────────────────────────
if (-not (Test-Path $CertFile)) {
    Write-Host "→ Génération du certificat auto-signé..." -ForegroundColor Cyan

    # Cherche openssl : WSL, Git for Windows, ou PATH
    $openssl = $null
    if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
        # Utilise openssl via WSL (disponible avec Docker Desktop)
        $wslScriptDir = wsl wslpath -u $ScriptDir.Replace('\', '/')
        wsl openssl req -x509 -nodes -days 3650 `
            -newkey rsa:2048 `
            -keyout "$wslScriptDir/server.key" `
            -out    "$wslScriptDir/server.crt" `
            -config "$wslScriptDir/openssl.cnf"
        Write-Host "  (via WSL + openssl)" -ForegroundColor DarkGray
    } elseif (Get-Command "openssl" -ErrorAction SilentlyContinue) {
        openssl req -x509 -nodes -days 3650 `
            -newkey rsa:2048 `
            -keyout $KeyFile `
            -out    $CertFile `
            -config $CnfFile
        Write-Host "  (via openssl PATH)" -ForegroundColor DarkGray
    } else {
        Write-Host "X openssl introuvable." -ForegroundColor Red
        Write-Host "  Installe Git for Windows (git-scm.com) ou Docker Desktop avec WSL2," -ForegroundColor Yellow
        Write-Host "  puis relance ce script." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✓ Certificat généré." -ForegroundColor Green
} else {
    Write-Host "→ Certificat déjà présent." -ForegroundColor DarkGray
}

# ── 2. Approuver le certificat dans le magasin Racine Windows ─────────────────
Write-Host "→ Ajout du certificat dans le magasin de confiance Windows..." -ForegroundColor Cyan
try {
    $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertFile)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")

    # Supprime l'ancienne version si elle existe (renouvellement)
    $existing = $store.Certificates | Where-Object { $_.Subject -eq $cert.Subject }
    foreach ($old in $existing) { $store.Remove($old) }

    $store.Add($cert)
    $store.Close()
    Write-Host "✓ Certificat approuvé par Windows." -ForegroundColor Green
} catch {
    Write-Host "X Impossible d'ajouter le certificat : $_" -ForegroundColor Red
    exit 1
}

# ── 3. Ajouter 127.0.0.1 infini-post.local dans le fichier hosts ──────────────
Write-Host "→ Vérification du fichier hosts..." -ForegroundColor Cyan
$hostsContent = Get-Content $HostsFile -Raw

if ($hostsContent -match [regex]::Escape($Hostname)) {
    Write-Host "→ $Hostname déjà présent dans le fichier hosts." -ForegroundColor DarkGray
} else {
    Add-Content $HostsFile "`r`n127.0.0.1`t$Hostname"
    Write-Host "✓ $Hostname ajouté au fichier hosts." -ForegroundColor Green
}

# ── Résumé ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "✓ Configuration terminée." -ForegroundColor Green
Write-Host "  Lance maintenant : docker compose up -d" -ForegroundColor White
Write-Host "  Puis ouvre      : https://infini-post.local" -ForegroundColor White
Write-Host ""
