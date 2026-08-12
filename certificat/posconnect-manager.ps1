#Requires -Version 5.1
<#
.SYNOPSIS
    POS Serveur - Gestionnaire de services
    Tourne dans la zone de notification (systray) - lance au demarrage de
    Windows (raccourci Startup) et reste actif en arriere-plan. Cliquer
    l'icone (ou le raccourci Menu Demarrer) ouvre la fenetre de gestion ;
    fermer la fenetre la cache seulement, "Quitter" du menu tray arrete l'app.
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

# -- Log d'erreur (visible meme quand la fenetre ne s'affiche pas) -------------
$_LogFile = "$env:ProgramData\POS_Connect\manager-error.log"
function Write-CrashLog($msg) {
    try {
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $dir   = Split-Path $_LogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $_LogFile -Value "[$stamp] $msg" -Encoding UTF8
    } catch {}
}

try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -- Instance unique -------------------------------------------------------
# Le raccourci Startup ET le raccourci Menu Démarrer peuvent tous deux lancer
# l'app - sans cette protection, un second lancement créerait une deuxième
# icône systray dupliquée. "Global\" = mutex machine-wide, pas juste par
# session utilisateur (cohérent avec l'app qui tourne déjà en admin).
$mutexName = "Global\POSConnectManagerSingleInstance"
$createdNew = $false
$script:singleInstanceMutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    [System.Windows.Forms.MessageBox]::Show(
        "POS Connect Manager tourne déjà — voir l'icône dans la zone de notification (près de l'horloge).",
        "POS Connect Manager",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit
}

# -- Lecture pos_server.ini (port + type de base) ------------------------------
$ApiPort = 9003
$DbTypeIni = "mysql"    # "mysql" | "sqlite"
$IniPath = "$env:ProgramData\POS_Connect\pos_server.ini"
if (Test-Path $IniPath) {
    $inServer = $false; $inDb = $false
    foreach ($line in (Get-Content $IniPath -Encoding UTF8)) {
        if ($line -match '^\[server\]')   { $inServer = $true;  $inDb = $false; continue }
        if ($line -match '^\[database\]') { $inDb = $true; $inServer = $false; continue }
        if ($line -match '^\[')           { $inServer = $false; $inDb = $false; continue }
        if ($inServer -and $line -match '^\s*port\s*=\s*(\d+)') {
            $ApiPort = [int]$Matches[1]
        }
        if ($inDb -and $line -match '^\s*type\s*=\s*(\w+)') {
            $DbTypeIni = $Matches[1].Trim().ToLower()
        }
    }
}

# -- Services (adaptes au type de base) ----------------------------------------
if ($DbTypeIni -eq "sqlite") {
    $SVCS = [ordered]@{
        "POS_Connect_API"   = "API POS      (serveur)"
        "POS_Connect_Nginx" = "Nginx        (connexions HTTPS)"
    }
} else {
    $SVCS = [ordered]@{
        "POS_Connect_MySQL" = "MySQL        (base de donnees)"
        "POS_Connect_API"   = "API POS      (serveur)"
        "POS_Connect_Nginx" = "Nginx        (connexions HTTPS)"
    }
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

    $script:authResult = $false

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
    return $script:authResult
}

# -- Formulaire principal ------------------------------------------------------
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "POS Serveur -- Etat des services"
$form.ClientSize       = New-Object System.Drawing.Size(500, 440)
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

# Bandeau mise à jour serveur disponible — caché par défaut, rempli et
# affiché par Test-ServerUpdate (voir plus bas). Persiste dans la fenêtre
# principale, contrairement à la bulle systray qui disparaît après 10s.
$lUpdateBanner            = New-Object System.Windows.Forms.LinkLabel
$lUpdateBanner.Text       = ""
$lUpdateBanner.LinkColor  = $clrOrange
$lUpdateBanner.ActiveLinkColor = $clrOrange
$lUpdateBanner.Location   = New-Object System.Drawing.Point(14, 62)
$lUpdateBanner.Size       = New-Object System.Drawing.Size(472, 20)
$lUpdateBanner.Font       = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lUpdateBanner.Visible    = $false
$form.Controls.Add($lUpdateBanner)

# Panel statuts
$panel             = New-Object System.Windows.Forms.Panel
$panel.Location    = New-Object System.Drawing.Point(14, 98)
$panel.Size        = New-Object System.Drawing.Size(472, 156)
$panel.BackColor   = $clrPanel
$panel.BorderStyle = "None"
$form.Controls.Add($panel)

$dotLabels    = @{}
$statusLabels = @{}
$startSvcBtns = @{}
$stopSvcBtns  = @{}
$row = 0
foreach ($svcName in $SVCS.Keys) {
    $y = 14 + ($row * 44)

    $dot           = New-Object System.Windows.Forms.Label
    $dot.Text      = [char]0x25CF
    $dot.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $dot.ForeColor = $clrGray
    $dot.Location  = New-Object System.Drawing.Point(10, ($y + 8))
    $dot.AutoSize  = $true
    $panel.Controls.Add($dot)
    $dotLabels[$svcName] = $dot

    $lName           = New-Object System.Windows.Forms.Label
    $lName.Text      = $SVCS[$svcName]
    $lName.ForeColor = $clrText
    $lName.Location  = New-Object System.Drawing.Point(34, ($y + 10))
    $lName.Size      = New-Object System.Drawing.Size(140, 20)
    $panel.Controls.Add($lName)

    $lSt           = New-Object System.Windows.Forms.Label
    $lSt.Text      = "..."
    $lSt.ForeColor = $clrSub
    $lSt.Location  = New-Object System.Drawing.Point(178, ($y + 10))
    $lSt.Size      = New-Object System.Drawing.Size(86, 20)
    $panel.Controls.Add($lSt)
    $statusLabels[$svcName] = $lSt

    $bOn           = New-Object System.Windows.Forms.Button
    $bOn.Text      = "Demarrer"
    $bOn.Size      = New-Object System.Drawing.Size(86, 26)
    $bOn.Location  = New-Object System.Drawing.Point(268, ($y + 7))
    $bOn.BackColor = $clrBtnGrn
    $bOn.ForeColor = $clrText
    $bOn.FlatStyle = "Flat"
    $bOn.FlatAppearance.BorderSize = 0
    $bOn.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($bOn)
    $startSvcBtns[$svcName] = $bOn

    $bOff          = New-Object System.Windows.Forms.Button
    $bOff.Text     = "Arreter"
    $bOff.Size     = New-Object System.Drawing.Size(86, 26)
    $bOff.Location = New-Object System.Drawing.Point(360, ($y + 7))
    $bOff.BackColor = $clrBtnRed
    $bOff.ForeColor = $clrText
    $bOff.FlatStyle = "Flat"
    $bOff.FlatAppearance.BorderSize = 0
    $bOff.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($bOff)
    $stopSvcBtns[$svcName] = $bOff

    $row++
}

# Message avertissement / progression
$lWarn           = New-Object System.Windows.Forms.Label
$lWarn.Text      = ""
$lWarn.ForeColor = $clrOrange
$lWarn.Location  = New-Object System.Drawing.Point(14, 264)
$lWarn.Size      = New-Object System.Drawing.Size(472, 36)
$lWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$form.Controls.Add($lWarn)

# Boutons
function New-Btn($text, $bgColor, $x) {
    $b          = New-Object System.Windows.Forms.Button
    $b.Text     = $text
    $b.Size     = New-Object System.Drawing.Size(108, 34)
    $b.Location = New-Object System.Drawing.Point($x, 320)
    $b.BackColor = $bgColor
    $b.ForeColor = $clrText
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($b)
    return $b
}

$btnRefresh = New-Btn "Actualiser"    $clrBtnDark  14
$btnStart   = New-Btn "Demarrer tout" $clrBtnGrn  128
$btnRestart = New-Btn "Redemarrer"    $clrBtnBlue 242
$btnStop    = New-Btn "Arreter tout"  $clrBtnRed  356

# -- Séparateur + bouton migration DB (Epic 3 / Epic 4) -----------------------
$clrBtnPurple = [System.Drawing.Color]::FromArgb(142, 68, 173)
$clrBtnSqlite = [System.Drawing.Color]::FromArgb(41, 128, 185)

$sep           = New-Object System.Windows.Forms.Label
$sep.Text      = ""
$sep.BackColor = [System.Drawing.Color]::FromArgb(52, 73, 94)
$sep.Location  = New-Object System.Drawing.Point(14, 368)
$sep.Size      = New-Object System.Drawing.Size(472, 1)
$form.Controls.Add($sep)

$lDbType           = New-Object System.Windows.Forms.Label
$lDbType.Text      = "Base de donnees : " + $DbTypeIni.ToUpper()
$lDbType.ForeColor = $clrSub
$lDbType.Location  = New-Object System.Drawing.Point(14, 378)
$lDbType.AutoSize  = $true
$form.Controls.Add($lDbType)

# Bouton "Passer a MySQL" — visible seulement si mode SQLite (Epic 3)
$btnToMySQL        = New-Object System.Windows.Forms.Button
$btnToMySQL.Text   = "Passer a MySQL"
$btnToMySQL.Size   = New-Object System.Drawing.Size(148, 34)
$btnToMySQL.Location = New-Object System.Drawing.Point(222, 398)
$btnToMySQL.BackColor = $clrBtnPurple
$btnToMySQL.ForeColor = $clrText
$btnToMySQL.FlatStyle = "Flat"
$btnToMySQL.FlatAppearance.BorderSize = 0
$btnToMySQL.Font   = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnToMySQL.Visible = ($DbTypeIni -eq "sqlite")
$form.Controls.Add($btnToMySQL)

# Bouton "Revenir a SQLite" — visible seulement si mode MySQL ET 1 seule caisse (Epic 4)
$btnToSQLite        = New-Object System.Windows.Forms.Button
$btnToSQLite.Text   = "Revenir a SQLite"
$btnToSQLite.Size   = New-Object System.Drawing.Size(148, 34)
$btnToSQLite.Location = New-Object System.Drawing.Point(338, 398)
$btnToSQLite.BackColor = $clrBtnSqlite
$btnToSQLite.ForeColor = $clrText
$btnToSQLite.FlatStyle = "Flat"
$btnToSQLite.FlatAppearance.BorderSize = 0
$btnToSQLite.Font   = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnToSQLite.Visible = ($DbTypeIni -eq "mysql")
$form.Controls.Add($btnToSQLite)

# Attente non-bloquante : garde la fenetre reactive pendant les sleeps
function Start-UIWait([int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
}

# -- Helpers etat UI -----------------------------------------------------------
$allBtns = @($btnRefresh, $btnStart, $btnRestart, $btnStop, $btnToMySQL, $btnToSQLite) +
           @($startSvcBtns.Values) + @($stopSvcBtns.Values)

# -- Handlers par service (GetNewClosure capture la variable de boucle) --------
foreach ($svcName in $SVCS.Keys) {
    $startSvcBtns[$svcName].Add_Click({
        param($s, $e)
        $name = $s.Tag
        if ((Get-SvcStatus $name) -eq "Running") { return }
        Set-Busy "Demarrage $($SVCS[$name])..."
        Start-Service $name -ErrorAction SilentlyContinue
        Start-UIWait 3
        Update-Status
        Set-Free
    }.GetNewClosure())
    $startSvcBtns[$svcName].Tag = $svcName

    $stopSvcBtns[$svcName].Add_Click({
        param($s, $e)
        $name = $s.Tag
        if ((Get-SvcStatus $name) -eq "Stopped") { return }
        $ok = Show-AuthDialog "Arreter $($SVCS[$name])"
        if (-not $ok) { return }
        Set-Busy "Arret $($SVCS[$name])..."
        Stop-Service $name -Force -ErrorAction SilentlyContinue
        Start-UIWait 2
        Update-Status
        Set-Free
    }.GetNewClosure())
    $stopSvcBtns[$svcName].Tag = $svcName
}

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
    # n'est pas accessible. Les droits admin Windows (UAC) suffisent.
    Set-Busy "Verification..."
    Update-Status

    if ((Get-SvcStatus "POS_Connect_MySQL") -ne "Running") {
        Set-Busy "Demarrage MySQL..."
        Start-Service "POS_Connect_MySQL" -ErrorAction SilentlyContinue
        Start-UIWait 4
        Update-Status
    }
    if ((Get-SvcStatus "POS_Connect_API") -ne "Running") {
        Set-Busy "Demarrage API POS..."
        Start-Service "POS_Connect_API"   -ErrorAction SilentlyContinue
        Start-UIWait 3
        Update-Status
    }
    if ((Get-SvcStatus "POS_Connect_Nginx") -ne "Running") {
        Set-Busy "Demarrage Nginx..."
        Start-Service "POS_Connect_Nginx" -ErrorAction SilentlyContinue
        Start-UIWait 2
        Update-Status
    }
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
    Start-UIWait 3
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
    Start-UIWait 4
    Update-Status
    Set-Busy "Demarrage MySQL..."
    Start-Service "POS_Connect_MySQL" -ErrorAction SilentlyContinue
    Start-UIWait 4
    Update-Status
    Set-Busy "Demarrage API POS..."
    Start-Service "POS_Connect_API"   -ErrorAction SilentlyContinue
    Start-UIWait 3
    Update-Status
    Set-Busy "Demarrage Nginx..."
    Start-Service "POS_Connect_Nginx" -ErrorAction SilentlyContinue
    Start-UIWait 2
    Update-Status
    Set-Free
})

# -- Handler : Passer a MySQL (Epic 3) -----------------------------------------
$btnToMySQL.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Cette operation va :" + [System.Environment]::NewLine +
        "  1. Installer MySQL 8 si absent" + [System.Environment]::NewLine +
        "  2. Migrer toutes vos donnees SQLite vers MySQL" + [System.Environment]::NewLine +
        "  3. Redemarrer les services POS" + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Un backup de votre fichier SQLite sera cree automatiquement." + [System.Environment]::NewLine +
        "Duree estimee : 3 a 10 minutes selon la taille des donnees." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Continuer ?",
        "Passer a MySQL",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # Chemin du script d'upgrade
    $upgradeScript = Join-Path $env:ProgramFiles "POS_Connect\setup-mysql-upgrade.ps1"
    if (-not (Test-Path $upgradeScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Script introuvable : $upgradeScript`nVerifiez votre installation POS Connect.",
            "Erreur",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    Set-Busy "Lancement de l'upgrade MySQL..."
    $btnToMySQL.Visible = $false

    # Lancer dans une nouvelle fenetre PowerShell admin (pour voir la progression)
    Start-Process powershell.exe `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$upgradeScript`"" `
        -Verb RunAs `
        -Wait

    # Relire le type de base apres l'upgrade
    $newType = "mysql"
    if (Test-Path $IniPath) {
        foreach ($line in (Get-Content $IniPath -Encoding UTF8)) {
            if ($line -match '^\s*type\s*=\s*(\w+)') { $newType = $Matches[1].Trim().ToLower() }
        }
    }
    $script:DbTypeIni = $newType
    $lDbType.Text = "Base de donnees : " + $newType.ToUpper()
    $btnToMySQL.Visible  = ($newType -eq "sqlite")
    $btnToSQLite.Visible = ($newType -eq "mysql")

    # Recharger la liste des services (MySQL maintenant présent)
    if ($newType -eq "mysql" -and -not $SVCS.Contains("POS_Connect_MySQL")) {
        $SVCS = [ordered]@{
            "POS_Connect_MySQL" = "MySQL        (base de donnees)"
            "POS_Connect_API"   = "API POS      (serveur)"
            "POS_Connect_Nginx" = "Nginx        (connexions HTTPS)"
        }
    }
    Update-Status
    Set-Free
})

# -- Handler : Revenir a SQLite (Epic 4) ---------------------------------------
$btnToSQLite.Add_Click({
    # Vérifier qu'il n'y a qu'une seule caisse active (condition pour rétrograder)
    $ApiRunning = (Get-SvcStatus "POS_Connect_API") -eq "Running"
    if ($ApiRunning) {
        try {
            $headers = @{ "Content-Type" = "application/json" }
            $resp = Invoke-RestMethod -Uri "https://localhost:$ApiPort/api/warehouses/registers" `
                        -Headers $headers -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
            $activeCount = ($resp | Where-Object { $_.is_active -eq $true }).Count
            if ($activeCount -gt 1) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Impossible de revenir a SQLite : $activeCount caisses actives detectees." + [System.Environment]::NewLine +
                    "SQLite est mono-caisse. Desactivez les caisses supplementaires avant de continuer.",
                    "Retour SQLite impossible",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                return
            }
        } catch {
            # API non joignable — continuer avec avertissement
        }
    }

    $r = [System.Windows.Forms.MessageBox]::Show(
        "Cette operation va migrer toutes vos donnees MySQL vers SQLite," + [System.Environment]::NewLine +
        "puis reconfigurer POS Connect en mode mono-poste." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Le service MySQL sera conserve mais inutilise." + [System.Environment]::NewLine +
        "Vous pouvez le supprimer manuellement depuis les services Windows." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "ATTENTION : operation irreversible sans backup." + [System.Environment]::NewLine +
        "Un backup MySQL sera tente (mysqldump) si disponible." + [System.Environment]::NewLine + [System.Environment]::NewLine +
        "Continuer ?",
        "Revenir a SQLite",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # Auth admin POS
    $ok = Show-AuthDialog "Retour vers SQLite"
    if (-not $ok) { return }

    Set-Busy "Migration MySQL -> SQLite..."
    $btnToSQLite.Enabled = $false

    $InstallRoot    = Join-Path $env:ProgramFiles "POS_Connect"
    $ApiDir         = Join-Path $InstallRoot "api"
    $MigrateScript  = Join-Path $ApiDir "migrate_db.py"
    $PythonExe      = Join-Path $ApiDir "python.exe"
    if (-not (Test-Path $PythonExe)) {
        $_pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
        $PythonExe = if ($_pyCmd) { $_pyCmd.Source } else { $null }
    }

    if (-not (Test-Path $MigrateScript) -or -not $PythonExe) {
        Set-Free
        [System.Windows.Forms.MessageBox]::Show(
            "migrate_db.py ou python.exe introuvable dans $ApiDir.",
            "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $btnToSQLite.Enabled = $true
        return
    }

    # Arrêter les services
    Set-Busy "Arret des services..."
    Stop-Service "POS_Connect_Nginx","POS_Connect_API" -Force -ErrorAction SilentlyContinue
    Start-UIWait 3

    # Lancer la migration
    Set-Busy "Migration des donnees..."
    $proc = Start-Process $PythonExe `
        -ArgumentList "`"$MigrateScript`" mysql-to-sqlite --ini `"$IniPath`" --update-ini" `
        -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Start-Service "POS_Connect_API","POS_Connect_Nginx" -ErrorAction SilentlyContinue
        Set-Free
        $btnToSQLite.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show(
            "La migration a echoue (code $($proc.ExitCode))." + [System.Environment]::NewLine +
            "Les services ont ete redemarres en mode MySQL.",
            "Erreur migration",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        Update-Status
        return
    }

    # Relire type
    $newType = "sqlite"
    foreach ($line in (Get-Content $IniPath -Encoding UTF8)) {
        if ($line -match '^\s*type\s*=\s*(\w+)') { $newType = $Matches[1].Trim().ToLower() }
    }
    $lDbType.Text = "Base de donnees : " + $newType.ToUpper()
    $btnToSQLite.Visible = ($newType -eq "mysql")
    $btnToMySQL.Visible  = ($newType -eq "sqlite")

    # Redémarrer
    Set-Busy "Redemarrage..."
    Start-Service "POS_Connect_API"   -ErrorAction SilentlyContinue ; Start-UIWait 4
    Start-Service "POS_Connect_Nginx" -ErrorAction SilentlyContinue ; Start-UIWait 2
    Update-Status
    Set-Free
})

# -- Icone systeme (zone de notification) --------------------------------------
# L'app demarre cachee dans le systray (lancee au demarrage de Windows via le
# raccourci Startup) - la fenetre de gestion ne s'affiche que via le menu de
# l'icone ou le raccourci Menu Demarrer. Fermer la fenetre (X) la cache au
# lieu de quitter le processus - seul "Quitter" dans le menu arrete l'app.
try {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $trayIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
} catch { $trayIcon = [System.Drawing.SystemIcons]::Application }

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $trayIcon
$notifyIcon.Text = "POS Connect Manager"
$notifyIcon.Visible = $true

$menuOpen = New-Object System.Windows.Forms.ToolStripMenuItem "Ouvrir le gestionnaire"
$menuOpen.Add_Click({
    $form.Show()
    $form.WindowState = "Normal"
    $form.Activate()
})
$menuSep = New-Object System.Windows.Forms.ToolStripSeparator
$menuQuit = New-Object System.Windows.Forms.ToolStripMenuItem "Quitter"
$menuQuit.Add_Click({
    $notifyIcon.Visible = $false
    try { $script:singleInstanceMutex.ReleaseMutex() } catch {}
    [System.Windows.Forms.Application]::Exit()
})

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$trayMenu.Items.Add($menuOpen)
[void]$trayMenu.Items.Add($menuSep)
[void]$trayMenu.Items.Add($menuQuit)
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = "Normal"
    $form.Activate()
})

$form.Add_FormClosing({
    if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $_.Cancel = $true
        $form.Hide()
    }
})

# -- Vérification de mise à jour serveur ---------------------------------------
# Interroge toujours l'instance cloud centrale (pas le serveur local) — même
# source que le client Flutter (AppConstants.cloudUrl). Comparaison de
# chaîne simple contre la version installée (registre) ; jamais de blocage
# forcé pour un serveur en prod, juste une notification systray.
$script:updateDownloadUrl = $null
function Test-ServerUpdate {
    try {
        $installedVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\POS Connect" `
            -Name "Version" -ErrorAction SilentlyContinue).Version
        if (-not $installedVersion) { return }

        # PowerShell 5.1 / Windows Server plus anciens n'activent pas TLS 1.2
        # par défaut — la requête échouerait silencieusement sans ça.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $resp = Invoke-RestMethod -Uri "https://pos.infini-software.cloud/api/public/version" `
            -Method Get -TimeoutSec 8
        $latest = $resp.latest_version_server
        if ($latest -and ($latest -ne $installedVersion)) {
            $script:updateDownloadUrl = $resp.update_url_windows_server
            $notifyIcon.ShowBalloonTip(
                10000,
                "Mise à jour disponible",
                "POS Serveur $latest est disponible (version installée : $installedVersion). Cliquez pour ouvrir le lien de téléchargement.",
                [System.Windows.Forms.ToolTipIcon]::Info
            )
            # Bandeau persistant dans la fenêtre principale — contrairement à
            # la bulle systray (disparaît après 10s, facilement manquée), ceci
            # reste visible tant que la mise à jour n'est pas installée, et
            # est visible même si la fenêtre est ouverte après coup.
            $lUpdateBanner.Text    = "Mise à jour disponible : POS Serveur $latest (installee : $installedVersion) - Cliquez pour telecharger"
            $lUpdateBanner.Visible = $true
        }
    } catch {
        # Pas de connexion / serveur cloud injoignable — non bloquant, on
        # retentera au prochain cycle du timer.
    }
}
$notifyIcon.Add_BalloonTipClicked({
    if ($script:updateDownloadUrl) {
        Start-Process $script:updateDownloadUrl
    }
})
$lUpdateBanner.Add_LinkClicked({
    if ($script:updateDownloadUrl) {
        Start-Process $script:updateDownloadUrl
    }
})

$updateCheckTimer = New-Object System.Windows.Forms.Timer
$updateCheckTimer.Interval = 24 * 60 * 60 * 1000   # 24h — l'app tourne en permanence dans le systray
$updateCheckTimer.Add_Tick({ Test-ServerUpdate })
$updateCheckTimer.Start()
Test-ServerUpdate   # premier check immédiat au démarrage

# -- Statut initial + lancement (caché — seul le systray/Menu Démarrer l'affiche) --
Update-Status
[System.Windows.Forms.Application]::Run()

} catch {
    $errMsg = "CRASH: $($_.Exception.GetType().Name)`n$($_.Exception.Message)`n`nStack:`n$($_.ScriptStackTrace)"
    Write-CrashLog $errMsg
    try {
        # Si WinForms est charge, afficher une boite de dialogue
        [System.Windows.Forms.MessageBox]::Show(
            $errMsg,
            "POS Manager -- Erreur fatale",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {
        # WinForms non disponible -- erreur deja dans le log
    }
}
