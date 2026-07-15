# ============================================================
#  POS Connect — Compilation FastAPI → exe Windows (Nuitka)
#  Lance depuis la racine du projet avec Python activé.
#
#  Résultat : dist\pos-server.exe  (~50-120 MB, standalone)
#  Copie pos-server.exe dans C:\POS_Connect\ avant de lancer
#  setup-windows.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$Root    = $PSScriptRoot
$OutDir  = "$Root\dist"
$OutName = "pos-server"

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  POS Connect — Build Windows (Nuitka)          " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Vérifier Python ───────────────────────────────────────────────────────
if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
    Write-Host "X Python introuvable. Installe Python 3.11+." -ForegroundColor Red
    exit 1
}
$pyVer = python --version
Write-Host "  Python : $pyVer" -ForegroundColor DarkGray

# ── 2. Installer Nuitka et dépendances de compilation ─────────────────────────
Write-Host "`n→ Installation Nuitka..." -ForegroundColor Cyan
pip install --quiet nuitka ordered-set zstandard
Write-Host "  ✓ Nuitka prêt." -ForegroundColor Green

# ── 3. Compilation ────────────────────────────────────────────────────────────
Write-Host "`n→ Compilation (peut prendre 5-15 min)..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

python -m nuitka `
    --standalone `
    --onefile `
    --output-dir="$OutDir" `
    --output-filename="$OutName" `
    --include-package=api `
    --include-package=uvicorn `
    --include-package=fastapi `
    --include-package=starlette `
    --include-package=sqlalchemy `
    --include-package=alembic `
    --include-package=pydantic `
    --include-package=pydantic_core `
    --include-package=pymysql `
    --include-package=pwdlib `
    --include-package=argon2 `
    --include-package=cryptography `
    --include-package=jose `
    --include-package=dotenv `
    --include-package=multipart `
    --include-package=email_validator `
    --include-data-dir="api/alembic=api/alembic" `
    --include-data-dir="api/static=api/static" `
    --assume-yes-for-downloads `
    --windows-console-mode=disable `
    "$Root\server.py"

# ── 4. Résultat ───────────────────────────────────────────────────────────────
$exePath = "$OutDir\$OutName.exe"
if (Test-Path $exePath) {
    $sizeMb = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host "  ✓ Build réussi !" -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Fichier : $exePath ($sizeMb MB)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Étape suivante :" -ForegroundColor Cyan
    Write-Host "  1. Copie pos-server.exe dans C:\POS_Connect\" -ForegroundColor White
    Write-Host "  2. Copie le dossier certificat\ dans C:\POS_Connect\" -ForegroundColor White
    Write-Host "  3. Copie .env dans C:\POS_Connect\" -ForegroundColor White
    Write-Host "  4. Lance (Admin) : .\certificat\setup-windows.ps1" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "X Compilation échouée. Vérifie les erreurs ci-dessus." -ForegroundColor Red
    exit 1
}
