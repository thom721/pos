#Requires -Version 5.1
<#
.SYNOPSIS
    Compile posconnect-manager.ps1 → posconnect-manager.exe (pas de console PowerShell).

.DESCRIPTION
    Utilise le module ps2exe (PSGallery) pour produire un exécutable Windows natif.
    L'EXE lance directement l'interface WinForms sans afficher de fenêtre console.

.NOTES
    - Exécuter UNE FOIS sur une machine Windows de build (pas en production).
    - Nécessite un accès Internet pour installer ps2exe si absent.
    - Le résultat posconnect-manager.exe est à distribuer avec le package d'installation.
#>

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

Write-Host "`n=== Build posconnect-manager.exe ===" -ForegroundColor Cyan

# ── 1. Installer ps2exe si absent ─────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "  Installation de ps2exe depuis PSGallery..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Force -Scope CurrentUser -Repository PSGallery
        Write-Host "  ps2exe installé." -ForegroundColor Green
    } catch {
        Write-Host "  ERREUR installation ps2exe : $_" -ForegroundColor Red
        Write-Host "  Si vous n'avez pas Internet, installez manuellement :" -ForegroundColor Yellow
        Write-Host "    Install-Module ps2exe -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }
}
Import-Module ps2exe -ErrorAction Stop

# ── 2. Fichiers source / destination ──────────────────────────────────────────
$InputPs1  = Join-Path $ScriptDir "posconnect-manager.ps1"
$OutputExe = Join-Path $ScriptDir "posconnect-manager.exe"
$IconFile  = Join-Path $ScriptDir "posconnect.ico"

if (-not (Test-Path $InputPs1)) {
    Write-Host "  ERREUR : posconnect-manager.ps1 introuvable dans $ScriptDir" -ForegroundColor Red
    exit 1
}

# ── 3. Compilation ────────────────────────────────────────────────────────────
Write-Host "  Compilation de $InputPs1 ..." -ForegroundColor Yellow

$params = @{
    inputFile   = $InputPs1
    outputFile  = $OutputExe
    noConsole   = $true          # ← fenêtre PowerShell cachée, WinForms direct
    title       = "POS Connect Manager"
    description = "Gestionnaire de service POS Connect"
    company     = "POS Connect"
    version     = "1.0.0.0"
    requireAdmin = $true         # UAC prompt automatique si droits insuffisants
}

# Ajouter l'icône uniquement si le fichier existe
if (Test-Path $IconFile) {
    $params['iconFile'] = $IconFile
} else {
    Write-Host "  (posconnect.ico absent — EXE compilé sans icône)" -ForegroundColor DarkGray
}

Invoke-ps2exe @params

if (Test-Path $OutputExe) {
    $size = [math]::Round((Get-Item $OutputExe).Length / 1KB)
    Write-Host "`n  OK → $OutputExe  ($size Ko)" -ForegroundColor Green
    Write-Host "  Le .bat n'est plus nécessaire — distribuer uniquement l'EXE." -ForegroundColor DarkGray
} else {
    Write-Host "`n  ERREUR : EXE non généré." -ForegroundColor Red
    exit 1
}
