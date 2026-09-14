# ============================================================
#  POS Connect — Faire confiance au certificat de signature auto-signé
#
#  Le certificat qui signe POSConnect-Setup.exe (posconnect-codesign.cer)
#  est auto-signé — Windows SmartScreen ne lui fera JAMAIS confiance
#  automatiquement, sur aucune machine, quel que soit le nombre
#  d'installations (contrairement à un certificat émis par une autorité
#  reconnue, qui accumule une réputation avec le temps).
#
#  Ce script installe ce certificat dans les magasins "Autorités de
#  certification racines de confiance" ET "Éditeurs de confiance" de CETTE
#  machine. Après ça, l'installeur signé avec CE certificat ne déclenchera
#  plus l'écran bleu SmartScreen ici.
#
#  ATTENTION — Portée : ça ne résout le problème QUE sur les machines où ce
#  script est exécuté (utile pour vos postes de test internes). Un vrai
#  client qui télécharge l'installeur sur SA machine verra toujours
#  l'avertissement, quoi qu'il arrive — seul un certificat acheté auprès
#  d'une autorité reconnue (DigiCert, Sectigo, SSL.com...) supprime
#  l'avertissement pour tout le monde.
#
#  À exécuter en tant qu'Administrateur.
# ============================================================

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CerPath   = Join-Path $ScriptDir "posconnect-codesign.cer"

if (-not (Test-Path $CerPath)) {
    Write-Host "X Certificat introuvable : $CerPath" -ForegroundColor Red
    exit 1
}

$cert = Get-PfxCertificate -FilePath $CerPath
Write-Host "Certificat trouvé : $($cert.Subject)" -ForegroundColor Cyan
Write-Host "Thumbprint : $($cert.Thumbprint)" -ForegroundColor Cyan
Write-Host ""

# Root : nécessaire pour que Windows valide la chaîne de confiance
Write-Host "→ Import dans Autorités de certification racines de confiance (Root)..." -ForegroundColor Cyan
Import-Certificate -FilePath $CerPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Write-Host "  OK" -ForegroundColor Green

# TrustedPublisher : nécessaire pour que SmartScreen/Authenticode traite
# les binaires signés par ce certificat comme "éditeur de confiance"
Write-Host "→ Import dans Éditeurs de confiance (TrustedPublisher)..." -ForegroundColor Cyan
Import-Certificate -FilePath $CerPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
Write-Host "  OK" -ForegroundColor Green

Write-Host ""
Write-Host "Terminé. Les fichiers signés avec ce certificat (posconnect-codesign.cer," -ForegroundColor Green
Write-Host "thumbprint $($cert.Thumbprint)) ne déclencheront plus l'écran SmartScreen" -ForegroundColor Green
Write-Host "sur cette machine." -ForegroundColor Green
