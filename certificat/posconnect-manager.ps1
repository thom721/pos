#Requires -Version 5.1
<#
.SYNOPSIS
    POS Serveur - Gestionnaire de services
    Lance depuis l'icone bureau via :
    powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File posconnect-manager.ps1
#>

# -- Elevation admin (UAC) -----------------------------------------------------
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    $self = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe `
        -ArgumentList "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$self`"" `
        -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -- Services (ordre de demarrage) ---------------------------------------------
$SVCS = [ordered]@{
    "POS_Connect_MySQL" = "MySQL        (base de donnees)"
    "POS_Connect_API"   = "API POS      (serveur)"
    "POS_Connect_Nginx" = "Nginx        (connexions HTTPS)"
}

# -- Palette -------------------------------------------------------------------
$clrBg      = [System.Drawing.Color]::FromArgb(27,  42,  59)
$clrPanel   = [System.Drawing.Color]::FromArgb(38,  56,  76)
$clrText    = [System.Drawing.Color]::White
$clrSub     = [System.Drawing.Color]::FromArgb(160, 175, 190)
$clrGreen   = [System.Drawing.Color]::FromArgb(46,  204, 113)
$clrRed     = [System.Drawing.Color]::FromArgb(231,  76,  60)
$clrOrange  = [System.Drawing.Color]::FromArgb(230, 126,  34)
$clrGray    = [System.Drawing.Color]::FromArgb(127, 140, 141)
$clrBtnDark = [System.Drawing.Color]::FromArgb(52,  73,  94)
$clrBtnGrn  = [System.Drawing.Color]::FromArgb(39,  174,  96)
$clrBtnBlue = [System.Drawing.Color]::FromArgb(41,  128, 185)
$clrBtnRed  = [System.Drawing.Color]::FromArgb(192,  57,  43)

function Get-StatusColor($st) {
    switch ($st) {
        "Running"      { return $clrGreen  }
        "Stopped"      { return $clrRed    }
        "StartPending" { return $clrOrange }
        "StopPending"  { return $clrOrange }
        default        { return $clrGray   }
    }
}
function Get-StatusLabel($st) {
    switch ($st) {
        "Running"      { return "En marche"    }
        "Stopped"      { return "Arrete"       }
        "StartPending" { return "Demarrage..." }
        "StopPending"  { return "Arret..."     }
        "Non installe" { return "Non installe" }
        default        { return $st            }
    }
}
function Get-SvcStatus($name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { return "Non installe" }
    return $s.Status.ToString()
}

# -- Formulaire ----------------------------------------------------------------
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "POS Serveur — Etat des services"
$form.ClientSize       = New-Object System.Drawing.Size(420, 310)
$form.StartPosition    = "CenterScreen"
$form.FormBorderStyle  = "FixedDialog"
$form.MaximizeBox      = $false
$form.BackColor        = $clrBg
$form.Font             = New-Object System.Drawing.Font("Segoe UI", 9)

# Titre
$lTitle = New-Object System.Windows.Forms.Label
$lTitle.Text      = "POS Serveur"
$lTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lTitle.ForeColor = $clrText
$lTitle.Location  = New-Object System.Drawing.Point(18, 12)
$lTitle.AutoSize  = $true
$form.Controls.Add($lTitle)

$lSub = New-Object System.Windows.Forms.Label
$lSub.Text      = "Gestion des services Windows"
$lSub.ForeColor = $clrSub
$lSub.Location  = New-Object System.Drawing.Point(18, 42)
$lSub.AutoSize  = $true
$form.Controls.Add($lSub)

# Panel statuts
$panel              = New-Object System.Windows.Forms.Panel
$panel.Location     = New-Object System.Drawing.Point(14, 68)
$panel.Size         = New-Object System.Drawing.Size(392, 136)
$panel.BackColor    = $clrPanel
$panel.BorderStyle  = "None"
$form.Controls.Add($panel)

$dotLabels    = @{}
$statusLabels = @{}
$row = 0
foreach ($svcName in $SVCS.Keys) {
    $y = 14 + ($row * 38)

    $dot           = New-Object System.Windows.Forms.Label
    $dot.Text      = [char]0x25CF   # ●
    $dot.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $dot.ForeColor = $clrGray
    $dot.Location  = New-Object System.Drawing.Point(12, $y)
    $dot.AutoSize  = $true
    $panel.Controls.Add($dot)
    $dotLabels[$svcName] = $dot

    $lName           = New-Object System.Windows.Forms.Label
    $lName.Text      = $SVCS[$svcName]
    $lName.ForeColor = $clrText
    $lName.Location  = New-Object System.Drawing.Point(36, ($y + 2))
    $lName.Size      = New-Object System.Drawing.Size(240, 20)
    $panel.Controls.Add($lName)

    $lSt           = New-Object System.Windows.Forms.Label
    $lSt.Text      = "..."
    $lSt.ForeColor = $clrSub
    $lSt.Location  = New-Object System.Drawing.Point(282, ($y + 2))
    $lSt.Size      = New-Object System.Drawing.Size(100, 20)
    $panel.Controls.Add($lSt)
    $statusLabels[$svcName] = $lSt

    $row++
}

# Message avertissement / progression
$lWarn           = New-Object System.Windows.Forms.Label
$lWarn.Text      = ""
$lWarn.ForeColor = [System.Drawing.Color]::FromArgb(230, 126, 34)
$lWarn.Location  = New-Object System.Drawing.Point(14, 210)
$lWarn.Size      = New-Object System.Drawing.Size(392, 36)
$lWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$form.Controls.Add($lWarn)

# Boutons
function New-Btn($text, $bgColor, $x) {
    $b             = New-Object System.Windows.Forms.Button
    $b.Text        = $text
    $b.Size        = New-Object System.Drawing.Size(92, 34)
    $b.Location    = New-Object System.Drawing.Point($x, 254)
    $b.BackColor   = $bgColor
    $b.ForeColor   = [System.Drawing.Color]::White
    $b.FlatStyle   = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.Font        = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($b)
    return $b
}

$btnRefresh = New-Btn "Actualiser" $clrBtnDark  14
$btnStart   = New-Btn "Demarrer"   $clrBtnGrn  112
$btnRestart = New-Btn "Redemarrer" $clrBtnBlue 210
$btnStop    = New-Btn "Arreter"    $clrBtnRed  308

# -- Helpers etat UI -----------------------------------------------------------
$allBtns = @($btnRefresh, $btnStart, $btnRestart, $btnStop)

function Set-Busy($msg) {
    $allBtns | ForEach-Object { $_.Enabled = $false }
    $lWarn.Text  = $msg
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}
function Set-Free {
    $allBtns | ForEach-Object { $_.Enabled = $true }
    $lWarn.Text  = ""
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
}

function Update-Status {
    foreach ($n in $SVCS.Keys) {
        $st = Get-SvcStatus $n
        $c  = Get-StatusColor $st
        $dotLabels[$n].ForeColor    = $c
        $statusLabels[$n].Text      = Get-StatusLabel $st
        $statusLabels[$n].ForeColor = $c
    }
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

# -- Evenements ----------------------------------------------------------------
$btnRefresh.Add_Click({
    Update-Status
})

$btnStart.Add_Click({
    Set-Busy "Demarrage en cours..."
    Start-Service "POS_Connect_MySQL" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    Update-Status
    Start-Service "POS_Connect_API"   -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Update-Status
    Start-Service "POS_Connect_Nginx" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Update-Status
    Set-Free
})

$btnStop.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Arreter les services interrompra TOUTES les caisses connectees." + [System.Environment]::NewLine +
        "Les ventes en cours peuvent etre perdues." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Confirmer l'arret ?",
        "Arreter POS Serveur",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Set-Busy "Arret en cours..."
    Stop-Service "POS_Connect_Nginx","POS_Connect_API","POS_Connect_MySQL" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Update-Status
    Set-Free
})

$btnRestart.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Le redemarrage causera une interruption de 15 a 30 secondes" + [System.Environment]::NewLine +
        "pour toutes les caisses connectees." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Confirmer le redemarrage ?",
        "Redemarrer POS Serveur",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Set-Busy "Arret des services..."
    Stop-Service "POS_Connect_Nginx","POS_Connect_API","POS_Connect_MySQL" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    Update-Status
    Set-Busy "Redemarrage en cours..."
    Start-Service "POS_Connect_MySQL" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    Update-Status
    Start-Service "POS_Connect_API"   -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Update-Status
    Start-Service "POS_Connect_Nginx" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Update-Status
    Set-Free
})

# -- Statut initial + lancement ------------------------------------------------
Update-Status
[System.Windows.Forms.Application]::Run($form)
