# POS Connect — Windows build + MSIX packaging script
# Run from the frontend/ folder on a Windows machine with Flutter + Visual Studio installed:
#   .\build_windows.ps1

param(
    [switch]$SkipMsix
)

$ErrorActionPreference = "Stop"

Write-Host "POS Connect — Windows Build" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# 1. Clean pub cache & get packages
Write-Host "`n[1/3] Getting packages..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "flutter pub get failed" -ForegroundColor Red; exit 1 }

# 2. Build release
Write-Host "`n[2/3] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed" -ForegroundColor Red; exit 1 }

$exePath = "build\windows\x64\runner\Release\pos_connect.exe"
if (Test-Path $exePath) {
    Write-Host "  EXE: $exePath" -ForegroundColor Green
}

# 3. Create MSIX package (skip with -SkipMsix)
if (-not $SkipMsix) {
    Write-Host "`n[3/3] Creating MSIX package..." -ForegroundColor Yellow
    dart run msix:create
    if ($LASTEXITCODE -ne 0) { Write-Host "MSIX creation failed" -ForegroundColor Red; exit 1 }

    $msixPath = "build\windows\x64\runner\Release\pos_connect.msix"
    if (Test-Path $msixPath) {
        $size = [math]::Round((Get-Item $msixPath).Length / 1MB, 1)
        Write-Host "  MSIX: $msixPath ($size MB)" -ForegroundColor Green
    }

    Write-Host "`nTo install on this machine (Developer Mode required):" -ForegroundColor Cyan
    Write-Host "  Add-AppxPackage .\$msixPath" -ForegroundColor White
    Write-Host "`nTo install on another machine (sideloading):" -ForegroundColor Cyan
    Write-Host "  1. Enable Developer Mode or install the certificate first" -ForegroundColor White
    Write-Host "  2. Double-click the .msix file" -ForegroundColor White
}

Write-Host "`nBuild complete!" -ForegroundColor Green
