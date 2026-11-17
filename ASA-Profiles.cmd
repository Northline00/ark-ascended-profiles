<# : ASA Profiles - double-click this file to start the tool
@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "iex ([IO.File]::ReadAllText('%~f0'))"
exit /b
#>

# ============================================================================
#  ASA Profiles
#  Several single-player setups for ARK: Survival Ascended (Steam, PC), each
#  with its own settings, active mods and saves.
#
#  How it works: the game always reads ShooterGame\Saved. This tool stores the
#  Saved folder of every inactive profile in ShooterGame\ASA-Profiles\<name>
#  and moves the chosen profile's folder back into place. Moves happen on the
#  same drive, so they are instant. Nothing is ever deleted.
#
#  License: MIT. Not affiliated with Studio Wildcard.
# ============================================================================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Version    = '1.1'
$script:AppTitle   = 'ASA Profiles'
$script:ConfigDir  = Join-Path $env:APPDATA 'ASA-Profiles'
$script:ConfigFile = Join-Path $script:ConfigDir 'config.json'
$script:StoreName  = 'ASA-Profiles'
$script:MarkerName = '.asa-profile'
$script:ExtrasName = '.asa-extras'
$script:SteamAppId = '2399830'
$script:GameProcs  = @('ArkAscended', 'ArkAscended_BE')

# Names used by version 1.0 (French only), migrated automatically.
$script:OldConfigDir  = Join-Path $env:APPDATA 'ASA-Profils'
$script:OldStoreName  = 'ASA-Profils'
$script:OldMarkerName = '.asa-profil'

# ------------------------------------------------------------------ language
# French if Windows is in French, English otherwise.
$script:IsFr = ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr')
function T([string]$en, [string]$fr) { if ($script:IsFr) { return $fr } else { return $en } }

# ------------------------------------------------------------------ helpers

function Show-Info([string]$msg) {
    [void][System.Windows.Forms.MessageBox]::Show($msg, $script:AppTitle, 'OK', 'Information')
}
function Show-Error([string]$msg) {
    [void][System.Windows.Forms.MessageBox]::Show($msg, $script:AppTitle, 'OK', 'Error')
}

function Load-Config {
    $cfg = [pscustomobject]@{ ShooterGame = $null; ExtraPaths = @() }
    if (Test-Path -LiteralPath $script:ConfigFile) {
        try {
            $raw = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($raw.ShooterGame) { $cfg.ShooterGame = [string]$raw.ShooterGame }
            if ($raw.ExtraPaths)  { $cfg.ExtraPaths  = @($raw.ExtraPaths | ForEach-Object { [string]$_ }) }
        } catch { }
    }
    return $cfg
}

function Save-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
        [void](New-Item -ItemType Directory -Path $script:ConfigDir)
    }
    $obj = [ordered]@{
        ShooterGame = $script:Cfg.ShooterGame
        ExtraPaths  = @($script:Cfg.ExtraPaths)
    }
    [IO.File]::WriteAllText($script:ConfigFile, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
}

# Looks for ...\steamapps\common\ARK Survival Ascended\ShooterGame in every
# Steam library (registry + libraryfolders.vdf + usual locations).
function Find-ShooterGame {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($v in @($p.SteamPath, $p.InstallPath)) {
            if ($v) { $libs.Add(($v -replace '/', '\')) }
        }
    }
    foreach ($root in @($libs)) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }
    }
    foreach ($drive in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }) {
        $libs.Add((Join-Path $drive.RootDirectory.FullName 'SteamLibrary'))
        $libs.Add((Join-Path $drive.RootDirectory.FullName 'Program Files (x86)\Steam'))
        $libs.Add((Join-Path $drive.RootDirectory.FullName 'Steam'))
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $sg = Join-Path $lib 'steamapps\common\ARK Survival Ascended\ShooterGame'
        if (Test-Path -LiteralPath $sg) { return $sg }
    }
    return $null
}

function Pick-ShooterGame {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = T "ARK: Survival Ascended was not found automatically.`nSelect the 'ARK Survival Ascended' folder (inside steamapps\common)." `
                         "ARK: Survival Ascended n'a pas été trouvé automatiquement.`nChoisis le dossier « ARK Survival Ascended » (dans steamapps\common)."
    if ($dlg.ShowDialog() -ne 'OK') { return $null }
    $p = $dlg.SelectedPath
    if ((Split-Path $p -Leaf) -ne 'ShooterGame') { $p = Join-Path $p 'ShooterGame' }
    if (-not (Test-Path -LiteralPath (Join-Path $p 'Binaries'))) {
        Show-Error ((T "This folder does not look like an ASA installation:`n{0}" "Ce dossier ne ressemble pas à une installation d'ASA :`n{0}") -f $p)
        return $null
    }
    return $p
}

function Paths {
    $sg = $script:Cfg.ShooterGame
    return [pscustomobject]@{
        SG    = $sg
        Saved = Join-Path $sg 'Saved'
        Store = Join-Path $sg $script:StoreName
    }
}

# Steam keeps userdata\<account>\2399830 only if Steam Cloud was used for ASA.
function Test-SteamCloudUsed {
    $p = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if (-not $p.SteamPath) { return $false }
    $userdata = Join-Path ($p.SteamPath -replace '/', '\') 'userdata'
    if (-not (Test-Path -LiteralPath $userdata)) { return $false }
    foreach ($acc in Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path -LiteralPath (Join-Path $acc.FullName $script:SteamAppId)) { return $true }
    }
    return $false
}

function Test-GameRunning {
    return [bool](Get-Process -Name $script:GameProcs -ErrorAction SilentlyContinue)
}

function Test-ValidName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    if ($name.Trim() -ne $name) { return $false }
    if ($name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    if ($name.StartsWith('.')) { return $false }
    if ($name.Length -gt 60) { return $false }
    return $true
}
function Get-InvalidNameText {
    return (T "Invalid name. Avoid \ / : * ? `" < > | and spaces at the start or end." `
              "Nom invalide. Évite \ / : * ? `" < > | et les espaces au début ou à la fin.")
}

function Set-Marker([string]$folder, [string]$name) {
    $marker = Join-Path $folder $script:MarkerName
    # A hidden file cannot be overwritten by WriteAllText: unhide it first.
    if (Test-Path -LiteralPath $marker) { (Get-Item -LiteralPath $marker -Force).Attributes = 'Normal' }
    [IO.File]::WriteAllText($marker, $name, (New-Object System.Text.UTF8Encoding($false)))
    try { (Get-Item -LiteralPath $marker -Force).Attributes = 'Hidden' } catch { }
    $old = Join-Path $folder $script:OldMarkerName
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
}

function Get-ActiveProfile {
    $p = Paths
    $marker = Join-Path $p.Saved $script:MarkerName
    if (Test-Path -LiteralPath $marker) {
        return ([IO.File]::ReadAllText($marker)).Trim()
    }
    $old = Join-Path $p.Saved $script:OldMarkerName
    if (Test-Path -LiteralPath $old) {
        $name = ([IO.File]::ReadAllText($old)).Trim()
        Set-Marker $p.Saved $name
        return $name
    }
    return $null
}

function Get-StoredProfiles {
    $p = Paths
    if (-not (Test-Path -LiteralPath $p.Store)) { return @() }
    return @(Get-ChildItem -LiteralPath $p.Store -Directory -Force |
        Where-Object { -not $_.Name.StartsWith('.') } |
        Sort-Object Name | ForEach-Object { $_.Name })
}

function Get-FolderSizeText([string]$path) {
    try {
        $bytes = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return (T 'empty' 'vide') }
        if ($bytes -ge 1GB) { return ('{0:N1} {1}' -f ($bytes / 1GB), (T 'GB' 'Go')) }
        return ('{0:N0} {1}' -f ($bytes / 1MB), (T 'MB' 'Mo'))
    } catch { return '?' }
}

# Moves v1.0 folders (French names) to the new names, once.
function Migrate-FromV10 {
    if ((Test-Path -LiteralPath $script:OldConfigDir) -and -not (Test-Path -LiteralPath $script:ConfigDir)) {
        Move-Item -LiteralPath $script:OldConfigDir -Destination $script:ConfigDir
    }
}
function Migrate-StoreFromV10 {
    $p = Paths
    $old = Join-Path $p.SG $script:OldStoreName
    if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $p.Store)) {
        Move-Item -LiteralPath $old -Destination $p.Store
    }
}

# ------------------------------------------------------------ extra paths
# Optional paths relative to ShooterGame to swap together with Saved
# (edit "ExtraPaths" in %APPDATA%\ASA-Profiles\config.json). Not needed for a
# standard Steam install: the active mod list lives in Saved\Config.
# When a profile is stored, they go to <profile>\.asa-extras\<path>.

function Stash-Extras([string]$savedFolder) {
    $p = Paths
    foreach ($rel in $script:Cfg.ExtraPaths) {
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $src = Join-Path $p.SG $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path (Join-Path $savedFolder $script:ExtrasName) $rel
        $parent = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        Move-Item -LiteralPath $src -Destination $dst
    }
}

function Restore-Extras([string]$savedFolder) {
    $p = Paths
    $extras = Join-Path $savedFolder $script:ExtrasName
    if (-not (Test-Path -LiteralPath $extras)) { return }
    foreach ($rel in $script:Cfg.ExtraPaths) {
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $src = Join-Path $extras $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $p.SG $rel
        if (Test-Path -LiteralPath $dst) {
            Move-Item -LiteralPath $dst -Destination ($dst + '.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        $parent = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        Move-Item -LiteralPath $src -Destination $dst
    }
    if (-not (Get-ChildItem -LiteralPath $extras -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $extras -Recurse -Force
    }
}

# ------------------------------------------------------------ actions

# First run: an unlabelled Saved folder already exists -> give it a name.
function Ensure-ActiveLabelled {
    $p = Paths
    if (-not (Test-Path -LiteralPath $p.Saved)) { return $true }
    if (Get-ActiveProfile) { return $true }
    $size = Get-FolderSizeText $p.Saved
    $msg = (T "Your current game (Saved folder: {0}) does not have a profile name yet.`n`nWhat do you want to call it? (e.g. Vanilla The Island)" `
              "Ta partie actuelle (dossier Saved : {0}) n'a pas encore de nom de profil.`n`nComment veux-tu l'appeler ? (ex : Vanilla The Island)") -f $size
    $default = T 'My current game' 'Ma partie actuelle'
    while ($true) {
        $name = [Microsoft.VisualBasic.Interaction]::InputBox($msg, $script:AppTitle, $default)
        if ($name -eq '') { return $false }
        if (-not (Test-ValidName $name)) { Show-Error (Get-InvalidNameText); continue }
        if (Test-Path -LiteralPath (Join-Path $p.Store $name)) {
            Show-Error ((T "A profile named '{0}' already exists." "Un profil « {0} » existe déjà.") -f $name); continue
        }
        Set-Marker $p.Saved $name
        return $true
    }
}

function Switch-Profile([string]$target) {
    $p = Paths
    if (Test-GameRunning) {
        Show-Error (T "ARK is running. Close the game before switching profiles." "ARK est en cours d'exécution. Ferme le jeu avant de changer de profil.")
        return $false
    }
    $active = Get-ActiveProfile
    if ($target -eq $active) { return $true }

    $targetDir = Join-Path $p.Store $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        Show-Error ((T "Profile not found: {0}" "Profil introuvable : {0}") -f $targetDir); return $false
    }
    if ((Test-Path -LiteralPath $p.Saved) -and -not $active) {
        Show-Error (T "The Saved folder has no profile name. Restart the tool to name it first." `
                      "Le dossier Saved n'a pas de nom de profil. Relance l'outil pour le nommer d'abord.")
        return $false
    }

    # 1. Store the active profile
    if ($active) {
        $dest = Join-Path $p.Store $active
        if (Test-Path -LiteralPath $dest) {
            Show-Error ((T "Conflict: a folder '{0}' already exists in {1}.`nNothing was moved." `
                           "Conflit : un dossier « {0} » existe déjà dans {1}.`nRien n'a été déplacé.") -f $active, $p.Store)
            return $false
        }
        try {
            Stash-Extras $p.Saved
            Move-Item -LiteralPath $p.Saved -Destination $dest
        } catch {
            $err = $_.Exception.Message
            try { if (Test-Path -LiteralPath $p.Saved) { Restore-Extras $p.Saved } } catch { }
            Show-Error ((T "Could not store profile '{0}':`n{1}`n`nA file may be open (game, Steam, File Explorer). Nothing else was changed." `
                           "Impossible de ranger le profil « {0} » :`n{1}`n`nUn fichier est peut-être ouvert (jeu, Steam, explorateur). Rien d'autre n'a été modifié.") -f $active, $err)
            return $false
        }
    }

    # 2. Move the target profile into Saved
    try {
        Move-Item -LiteralPath $targetDir -Destination $p.Saved
        Set-Marker $p.Saved $target
        Restore-Extras $p.Saved
    } catch {
        Show-Error ((T "Could not activate '{0}':`n{1}`n`nYour profiles are safe in:`n{2}" `
                       "Impossible d'activer « {0} » :`n{1}`n`nTes profils sont intacts dans :`n{2}") -f $target, $_.Exception.Message, $p.Store)
        return $false
    }
    return $true
}

function New-ProfileDialog {
    $p = Paths
    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'New profile' 'Nouveau profil'
    $f.Size = New-Object System.Drawing.Size(460, 230)
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $l = New-Object System.Windows.Forms.Label
    $l.Text = T 'Profile name (e.g. DOX2 Ragnarok, Primal Fear):' 'Nom du profil (ex : DOX2 Ragnarok, Primal Fear) :'
    $l.Location = '15,15'; $l.AutoSize = $true
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = '15,38'; $t.Width = 415

    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = T "Copy the active profile's settings (graphics, multipliers, active mods)`nwithout its saves. You can change them in game afterwards." `
                "Reprendre les réglages du profil actif (graphismes, multiplicateurs, mods)`nsans ses sauvegardes. Tu pourras les changer dans le jeu."
    $c.Location = '15,72'; $c.Size = '425,40'
    $c.Checked = [bool](Get-ActiveProfile)
    $c.Enabled = $c.Checked

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T 'Create' 'Créer'; $ok.Location = '250,130'; $ok.Width = 85
    $ok.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T 'Cancel' 'Annuler'; $cancel.Location = '345,130'; $cancel.Width = 85
    $cancel.DialogResult = 'Cancel'
    $f.AcceptButton = $ok; $f.CancelButton = $cancel
    $f.Controls.AddRange(@($l, $t, $c, $ok, $cancel))

    while ($f.ShowDialog() -eq 'OK') {
        $name = $t.Text
        if (-not (Test-ValidName $name)) { Show-Error (Get-InvalidNameText); continue }
        if ((Test-Path -LiteralPath (Join-Path $p.Store $name)) -or ($name -eq (Get-ActiveProfile))) {
            Show-Error ((T "A profile named '{0}' already exists." "Un profil « {0} » existe déjà.") -f $name); continue
        }
        $dir = Join-Path $p.Store $name
        [void](New-Item -ItemType Directory -Path $dir -Force)
        if ($c.Checked) {
            $cfgSrc = Join-Path $p.Saved 'Config'
            if (Test-Path -LiteralPath $cfgSrc) { Copy-Item -LiteralPath $cfgSrc -Destination (Join-Path $dir 'Config') -Recurse }
        }
        Set-Marker $dir $name
        $f.Dispose()
        return $name
    }
    $f.Dispose()
    return $null
}

function Backup-Profile([string]$name) {
    $p = Paths
    $active = Get-ActiveProfile
    $src = if ($name -eq $active) { $p.Saved } else { Join-Path $p.Store $name }
    if (($name -eq $active) -and (Test-GameRunning)) {
        Show-Error (T "Close the game before backing up the active profile." "Ferme le jeu avant de sauvegarder le profil actif.")
        return
    }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $outDir = Join-Path $docs 'ASA-Profiles-Backups'
    if (-not (Test-Path -LiteralPath $outDir)) { [void](New-Item -ItemType Directory -Path $outDir) }
    $zip = Join-Path $outDir ("{0}_{1}.zip" -f $name, (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip, [System.IO.Compression.CompressionLevel]::Fastest, $false)
        Show-Info ((T "Backup created:`n{0}" "Sauvegarde créée :`n{0}") -f $zip)
    } catch {
        Show-Error ((T "Backup failed:`n{0}" "Échec de la sauvegarde :`n{0}") -f $_.Exception.Message)
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
}

# ------------------------------------------------------------ main window

function Show-MainWindow {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$($script:AppTitle) $($script:Version)"
    $form.Size = New-Object System.Drawing.Size(580, 420)
    $form.MinimumSize = $form.Size
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = T 'ARK: Survival Ascended profiles' 'Profils ARK: Survival Ascended'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.Location = '15,12'; $title.AutoSize = $true

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = '15,48'; $list.Size = '340,270'
    $list.Anchor = 'Top,Bottom,Left,Right'
    $list.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $mk = {
        param($text, $y)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text; $b.Location = "370,$y"; $b.Size = '180,32'
        $b.Anchor = 'Top,Right'
        return $b
    }
    $btnPlay   = & $mk (T 'Activate and launch ASA' 'Activer et lancer ASA') 48
    $btnPlay.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnSwitch = & $mk (T 'Activate only' 'Activer seulement') 88
    $btnNew    = & $mk (T 'New profile...' 'Nouveau profil...') 138
    $btnBackup = & $mk (T 'Back up (zip)' 'Sauvegarder (zip)') 178
    $btnOpen   = & $mk (T 'Open folder' 'Ouvrir le dossier') 218

    $status = New-Object System.Windows.Forms.Label
    $status.Location = '15,328'; $status.Size = '535,44'
    $status.Anchor = 'Bottom,Left,Right'
    $status.ForeColor = [System.Drawing.Color]::DimGray

    $form.Controls.AddRange(@($title, $list, $btnPlay, $btnSwitch, $btnNew, $btnBackup, $btnOpen, $status))

    $script:Names = @()
    $refresh = {
        $active = Get-ActiveProfile
        $names = @()
        if ($active) { $names += $active }
        $names += @(Get-StoredProfiles | Where-Object { $_ -ne $active })
        $script:Names = $names
        $list.Items.Clear()
        $tag = T '(active)' '(actif)'
        foreach ($n in $names) {
            if ($n -eq $active) { [void]$list.Items.Add("$n   $tag") } else { [void]$list.Items.Add($n) }
        }
        if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
        $activeText = if ($active) { $active } else { T 'none' 'aucun' }
        $status.Text = (T "Game: {0}`nActive profile: {1}   -   Close ASA before switching profiles." `
                          "Jeu : {0}`nProfil actif : {1}   -   Ferme ASA avant de changer de profil.") -f $script:Cfg.ShooterGame, $activeText
    }
    $selected = {
        if ($list.SelectedIndex -lt 0) { return $null }
        return $script:Names[$list.SelectedIndex]
    }

    $btnSwitch.Add_Click({
        $n = & $selected; if (-not $n) { return }
        if (Switch-Profile $n) { & $refresh; Show-Info ((T "Active profile: {0}" "Profil actif : {0}") -f $n) }
    })
    $btnPlay.Add_Click({
        $n = & $selected; if (-not $n) { return }
        if (Switch-Profile $n) {
            & $refresh
            Start-Process "steam://rungameid/$($script:SteamAppId)"
        }
    })
    $btnNew.Add_Click({
        $n = New-ProfileDialog
        if ($n) {
            & $refresh
            Show-Info ((T "Profile '{0}' created.`nSelect it and click 'Activate and launch ASA'. In game, set the mods and settings for this playthrough: they will stay with this profile." `
                          "Profil « {0} » créé.`nSélectionne-le puis clique sur « Activer et lancer ASA ». Dans le jeu, règle les mods et les paramètres de cette partie : ils resteront propres à ce profil.") -f $n)
        }
    })
    $btnBackup.Add_Click({
        $n = & $selected; if (-not $n) { return }
        Backup-Profile $n
    })
    $btnOpen.Add_Click({
        $p = Paths
        $target = if (Test-Path -LiteralPath $p.Store) { $p.Store } else { $p.SG }
        Start-Process explorer.exe $target
    })
    $list.Add_DoubleClick({ $btnPlay.PerformClick() })
    $form.Add_Shown({ & $refresh })
    # ShowDialog stays inside this function so the event handlers can still
    # see $list, $refresh, etc. (PowerShell dynamic scoping).
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ------------------------------------------------------------ startup

try {
    Migrate-FromV10
    $script:Cfg = Load-Config
    if (-not $script:Cfg.ShooterGame -or -not (Test-Path -LiteralPath $script:Cfg.ShooterGame)) {
        $sg = Find-ShooterGame
        if (-not $sg) { $sg = Pick-ShooterGame }
        if (-not $sg) { return }
        $script:Cfg.ShooterGame = $sg
        Save-Config
    }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) { Save-Config }
    Migrate-StoreFromV10
    $pp = Paths
    if (-not (Test-Path -LiteralPath $pp.Store)) {
        [void](New-Item -ItemType Directory -Path $pp.Store)
        $welcome = (T "Welcome!`n`nGame found in:`n{0}" "Bienvenue !`n`nJeu trouvé dans :`n{0}") -f $pp.SG
        if (Test-SteamCloudUsed) {
            $welcome += T "`n`nIMPORTANT: Steam Cloud seems to be in use for ASA. Turn it off before switching profiles (Steam > right-click ARK: Survival Ascended > Properties > General > Steam Cloud), otherwise Steam could put another profile's save back in place of the right one." `
                          "`n`nIMPORTANT : Steam Cloud semble actif pour ASA. Désactive-le avant de changer de profil (Steam > clic droit sur ARK: Survival Ascended > Propriétés > Général > Steam Cloud), sinon Steam pourrait remettre la sauvegarde d'un autre profil à la place de la bonne."
        }
        Show-Info $welcome
    }
    if (-not (Ensure-ActiveLabelled)) { return }
    Show-MainWindow
} catch {
    Show-Error ((T "Unexpected error:" "Erreur inattendue :") + "`n" + $_.Exception.Message + "`n`n" + $_.InvocationInfo.PositionMessage)
}
