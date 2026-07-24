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

# -- Port API (lu depuis pos_server.ini) ---------------------------------------
$ApiPort = 9003
$IniPath = "$env:ProgramData\POS_Connect\pos_server.ini"
if (Test-Path $IniPath) {
    $inServer = $false
    foreach ($line in (Get-Content $IniPath -Encoding UTF8)) {
        if ($line -match '^\[server\]')   { $inServer = $true;  continue }
        if ($line -match '^\[')           { $inServer = $false; continue }
        if ($inServer -and $line -match '^\s*port\s*=\s*(\d+)') {
            $ApiPort = [int]$Matches[1]; break
        }
    }
}

# -- Services (ordre de demarrage) ---------------------------------------------
$SVCS = [ordered]@{
    "POS_Connect_MySQL" = "MySQL        (base de donnees)"
    "POS_Connect_API"   = "API POS      (serveur)"
    "POS_Connect_Nginx" = "Nginx        (connexions HTTPS)"
}

# -- Palette -------------------------------------------------------------------
$clrBg      = [System.Drawing.Color]::FromArgb(27,  42,  59)
$clrPanel   = [System.Drawing.Color]::FromArgb(38,  56,  76)
$clrInput   = [System.Drawing.Color]::FromArgb(20,  30,  44)
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
$clrError   = [System.Drawing.Color]::FromArgb(231,  76,  60)

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

# -- Verification admin POS (appel API) ----------------------------------------
# Retourne $true si l'utilisateur a le role "admin", $false sinon.
# L'API attend un POST form-encoded : username (ou email) + password.
function Confirm-AdminCredentials($loginVal, $password) {
    try {
        $body = "username=$([Uri]::EscapeDataString($loginVal))&password=$([Uri]::EscapeDataString($password))"
        $resp = Invoke-RestMethod `
            -Uri          "http://127.0.0.1:$ApiPort/api/auth/login" `
            -Method       Post `
            -ContentType  "application/x-www-form-urlencoded" `
            -Body         $body `
            -ErrorAction  Stop
        # La reponse contient user.roles (ex: ["admin","cashier"])
        $roles = $resp.user.roles
        return ($roles -contains "admin")
    } catch {
        return $false
    }
}

# -- Dialog d'authentification -------------------------------------------------
# Retourne $true si authentifie comme admin, $false si annule ou echec.
function Show-AuthDialog {
    param([string]$ActionLabel)

    $dlg                 = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Authentification requise"
    $dlg.ClientSize      = New-Object System.Drawing.Size(360, 250)
    $dlg.StartPosition   = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = $clrBg
    $dlg.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    $lAction = New-Object System.Windows.Forms.Label
    $lAction.Text      = "Action : $ActionLabel"
    $lAction.ForeColor = $clrOrange
    $lAction.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lAction.Location  = New-Object System.Drawing.Point(18, 14)
    $lAction.Size      = New-Object System.Drawing.Size(320, 20)
    $dlg.Controls.Add($lAction)

    $lInfo = New-Object System.Windows.Forms.Label
    $lInfo.Text      = "Un compte administrateur POS est requis."
    $lInfo.ForeColor = $clrSub
    $lInfo.Location  = New-Object System.Drawing.Point(18, 36)
    $lInfo.Size      = New-Object System.Drawing.Size(320, 18)
    $dlg.Controls.Add($lInfo)

    # Champ email / username
    $lLogin = New-Object System.Windows.Forms.Label
    $lLogin.Text      = "Email ou nom d'utilisateur :"
    $lLogin.ForeColor = $clrText
    $lLogin.Location  = New-Object System.Drawing.Point(18, 68)
    $lLogin.Size      = New-Object System.Drawing.Size(240, 18)
    $dlg.Controls.Add($lLogin)

    $tbLogin               = New-Object System.Windows.Forms.TextBox
    $tbLogin.Location      = New-Object System.Drawing.Point(18, 88)
    $tbLogin.Size          = New-Object System.Drawing.Size(320, 24)
    $tbLogin.BackColor     = $clrInput
    $tbLogin.ForeColor     = $clrText
    $tbLogin.BorderStyle   = "FixedSingle"
    $dlg.Controls.Add($tbLogin)

    # Champ mot de passe
    $lPwd = New-Object System.Windows.Forms.Label
    $lPwd.Text      = "Mot de passe :"
    $lPwd.ForeColor = $clrText
    $lPwd.Location  = New-Object System.Drawing.Point(18, 124)
    $lPwd.Size      = New-Object System.Drawing.Size(240, 18)
    $dlg.Controls.Add($lPwd)

    $tbPwd               = New-Object System.Windows.Forms.TextBox
    $tbPwd.Location      = New-Object System.Drawing.Point(18, 144)
    $tbPwd.Size          = New-Object System.Drawing.Size(320, 24)
    $tbPwd.BackColor     = $clrInput
    $tbPwd.ForeColor     = $clrText
    $tbPwd.BorderStyle   = "FixedSingle"
    $tbPwd.UseSystemPasswordChar = $true
    $dlg.Controls.Add($tbPwd)

    # Message erreur
    $lErr = New-Object System.Windows.Forms.Label
    $lErr.Text      = ""
    $lErr.ForeColor = $clrError
    $lErr.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lErr.Location  = New-Object System.Drawing.Point(18, 176)
    $lErr.Size      = New-Object System.Drawing.Size(320, 18)
    $dlg.Controls.Add($lErr)

    # Boutons
    $btnCancel              = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = "Annuler"
    $btnCancel.Size         = New-Object System.Drawing.Size(100, 32)
    $btnCancel.Location     = New-Object System.Drawing.Point(18, 202)
    $btnCancel.BackColor    = $clrBtnDark
    $btnCancel.ForeColor    = $clrText
    $btnCancel.FlatStyle    = "Flat"
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel

    $btnOk              = New-Object System.Windows.Forms.Button
    $btnOk.Text         = "Confirmer"
    $btnOk.Size         = New-Object System.Drawing.Size(110, 32)
    $btnOk.Location     = New-Object System.Drawing.Point(228, 202)
    $btnOk.BackColor    = $clrBtnBlue
    $btnOk.ForeColor    = $clrText
    $btnOk.FlatStyle    = "Flat"
    $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.Font         = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk

    $authResult = $false

    $btnOk.Add_Click({
        $login = $tbLogin.Text.Trim()
        $pwd   = $tbPwd.Text
        if (-not $login -or -not $pwd) {
            $lErr.Text = "Veuillez remplir tous les champs."
            return
        }
        $btnOk.Enabled    = $false
        $btnOk.Text       = "Verification..."
        $lErr.Text        = ""
        $dlg.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $ok = Confirm-AdminCredentials $login $pwd
        if ($ok) {
            $script:authResult = $true
            $dlg.DialogResult  = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        } else {
            $lErr.Text      = "Identifiants incorrects ou role admin requis."
            $btnOk.Enabled  = $true
            $btnOk.Text     = "Confirmer"
            $tbPwd.Text     = ""
            $tbPwd.Focus()
        }
    })

    $dlg.ShowDialog($form) | Out-Null
    return $authResult
}

# -- Formulaire principal ------------------------------------------------------
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "POS Serveur — Etat des services"
$form.ClientSize       = New-Object System.Drawing.Size(420, 310)
$form.StartPosition    = "CenterScreen"
$form.FormBorderStyle  = "FixedDialog"
$form.MaximizeBox      = $false
$form.BackColor        = $clrBg
$form.Font             = New-Object System.Drawing.Font("Segoe UI", 9)

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
$panel             = New-Object System.Windows.Forms.Panel
$panel.Location    = New-Object System.Drawing.Point(14, 68)
$panel.Size        = New-Object System.Drawing.Size(392, 136)
$panel.BackColor   = $clrPanel
$panel.BorderStyle = "None"
$form.Controls.Add($panel)

$dotLabels    = @{}
$statusLabels = @{}
$row = 0
foreach ($svcName in $SVCS.Keys) {
    $y = 14 + ($row * 38)

    $dot           = New-Object System.Windows.Forms.Label
    $dot.Text      = [char]0x25CF
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
$lWarn.ForeColor = $clrOrange
$lWarn.Location  = New-Object System.Drawing.Point(14, 210)
$lWarn.Size      = New-Object System.Drawing.Size(392, 36)
$lWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$form.Controls.Add($lWarn)

# Boutons
function New-Btn($text, $bgColor, $x) {
    $b          = New-Object System.Windows.Forms.Button
    $b.Text     = $text
    $b.Size     = New-Object System.Drawing.Size(92, 34)
    $b.Location = New-Object System.Drawing.Point($x, 254)
    $b.BackColor = $bgColor
    $b.ForeColor = $clrText
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
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
    # Demarrer ne necessite pas d'auth : les services sont arretes donc l'API
    # n'est pas accessible. Le droits admin Windows (UAC) suffisent.
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
    # Verifier les droits admin POS avant d'arreter
    $ok = Show-AuthDialog "Arreter tous les services POS"
    if (-not $ok) { return }

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
    # Verifier les droits admin POS avant de redemarrer
    $ok = Show-AuthDialog "Redemarrer tous les services POS"
    if (-not $ok) { return }

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
