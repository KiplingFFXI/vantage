<#
.SYNOPSIS
Installs the Vantage addon archive into a game folder, keeping a backup of the addon it replaces.

.DESCRIPTION
It can run while the game is open, with Vantage loaded or not. A running Vantage keeps its old code until you run
/addon reload vantage in game. It checks the archive against the SHA-256 you pass, notes the hash of every file
under config\addons\vantage (settings, profiles, shared layout and the rest), moves
the current addons\vantage (if there is one) to a dated backup folder outside the game folder, copies the new addon
in, checks the hash of every copied file and checks that no settings file changed. Each folder moves whole or not
at all, so a file another program holds open never leaves an addon split in two. If anything fails after the
backup move, the backup is put back and the partial copy is moved beside it; if the old addon can't be moved, it
stays where it is. A settings file Vantage saves while this runs counts as a change, so change nothing in game
until it is done. A JSON receipt of what it did goes beside the backup. The archive is unpacked beside the backup
first, and that staging copy is removed at the end.

It only changes addons\vantage. It does not touch the launcher or any startup script.

Exit codes: 0 installed, 1 refused before anything changed, 2 failed and the old addon is back in place (put back,
or never moved), 3 failed and the old addon could not be put back, or with no old addon the partial copy could not
be moved out (the receipt says where they are).

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install_addon.ps1 -Zip dist\vantage-1.0.0-addon.zip -Sha256 <hash> -Game C:\Games\PhoenixXI
#>
param(
    [Parameter(Mandatory = $true)] [string] $Zip,
    [Parameter(Mandatory = $true)] [string] $Sha256,
    [Parameter(Mandatory = $true)] [string] $Game,
    # Where the backup folder and the receipt go. It must be outside the game folder, on the same drive.
    [string] $BackupParent = [Environment]::GetFolderPath('MyDocuments'),
    # For the install test only: fail after the copy, to check that the backup is put back. after_copy_held also
    # holds a copied file open, so the partial copy can't be moved out.
    [Parameter(DontShow = $true)] [ValidateSet('', 'after_copy', 'after_copy_held')] [string] $TestFailure = ''
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$receipt = [ordered]@{
    tool = 'install_addon.ps1'; started_utc = $stamp; zip = $Zip; zip_sha256 = $null; game = $Game
    addon = $null; backup = $null; failed_copy = $null; files = [ordered]@{}
    settings_before = $null; settings_after = $null; result = 'refused'; reason = $null
}
$receiptPath = $null

function Get-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StreamSha256($Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream)) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-Inside([string] $Path, [string] $Folder) {
    $folder = $Folder.TrimEnd('\') + '\'
    return $Path.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) -or $Path -ieq $Folder.TrimEnd('\')
}

# relative path -> hash of every file in the settings folder (each character's settings.json, profiles.json,
# shared_layout.json and the rest), or the folder -> 'absent'.
function Get-SettingsHashes([string] $GameFolder) {
    $result = [ordered]@{}
    $relative = 'config/addons/vantage'
    $folder = [IO.Path]::Combine($GameFolder, 'config\addons\vantage')
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { $result[$relative] = 'absent'; return $result }
    # Get-ChildItem gives long names where the game path has short ones (RUNNER~1 on GitHub's runner), and Get-Item
    # gives the same long form, so each file's path is cut at that length.
    $base = (Get-Item -LiteralPath $folder -Force).FullName.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $folder -Recurse -Force -File | Sort-Object FullName)
    if ($files.Count -eq 0) { $result[$relative] = 'no files' }
    foreach ($file in $files) {
        $result[$relative + '/' + $file.FullName.Substring($base.Length + 1).Replace('\', '/')] = Get-Sha256 $file.FullName
    }
    return $result
}

function Test-SameHashes($Before, $After) {
    if ($Before.Count -ne $After.Count) { return $false }
    foreach ($key in $Before.Keys) {
        if (-not $After.Contains($key) -or $After[$key] -ne $Before[$key]) { return $false }
    }
    return $true
}

function Write-Receipt {
    if (-not $script:receiptPath) { return }
    $json = $script:receipt | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($script:receiptPath, $json + "`r`n", (New-Object Text.UTF8Encoding $false))
}

function Stop-Refused([string] $Reason) {
    $script:receipt.result = 'refused'
    $script:receipt.reason = $Reason
    Write-Receipt
    Write-Output ('Not installed: ' + $Reason)
    if ($script:receiptPath) { Write-Output ('Receipt: ' + $script:receiptPath) }
    exit 1
}

# Paths and the places this may write.
try {
    $Game = (Resolve-Path -LiteralPath $Game).ProviderPath.TrimEnd('\')
    $Zip = (Resolve-Path -LiteralPath $Zip).ProviderPath
    $BackupParent = (Resolve-Path -LiteralPath $BackupParent).ProviderPath.TrimEnd('\')
} catch {
    Write-Output ('Not installed: ' + $_.Exception.Message)
    exit 1
}
$receipt.game, $receipt.zip = $Game, $Zip
if (Test-Inside $BackupParent $Game) {
    Write-Output 'Not installed: the backup folder must be outside the game folder. Pass -BackupParent.'
    exit 1
}
$receiptPath = [IO.Path]::Combine($BackupParent, 'vantage-addon-install-' + $stamp + '.json')
$backup = [IO.Path]::Combine($BackupParent, 'vantage-addon-backup-' + $stamp)
$addon = [IO.Path]::Combine($Game, 'addons\vantage')
$receipt.addon = $addon
if ((Test-Path -LiteralPath $receiptPath) -or (Test-Path -LiteralPath $backup) -or
    (Test-Path -LiteralPath ([IO.Path]::Combine($BackupParent, 'vantage-addon-staging-' + $stamp)))) {
    $receiptPath = $null
    Stop-Refused ('a backup or receipt named ' + $stamp + ' already exists. Run it again in a second.')
}
if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($Game, 'addons')) -PathType Container)) {
    Stop-Refused ($Game + ' has no addons folder. Pass the game folder Ashita runs from.')
}
# The archive.
$receipt.zip_sha256 = Get-Sha256 $Zip
if ($receipt.zip_sha256 -ne $Sha256.Trim().ToLowerInvariant()) {
    Stop-Refused ('the archive SHA-256 is ' + $receipt.zip_sha256 + ', not the one passed in.')
}
$receipt.settings_before = Get-SettingsHashes $Game

# The archive is unpacked to a staging folder beside the backup first, and only files under addons/vantage/.
$staging = [IO.Path]::Combine($BackupParent, 'vantage-addon-staging-' + $stamp)
$expected = [ordered]@{}
$problem = $null
try {
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if ($name.EndsWith('/') -or -not $name.StartsWith('addons/vantage/')) { continue }
            $relative = $name.Substring('addons/vantage/'.Length)
            $parts = $relative.Split('/')
            if ($name.Contains('\') -or $name.Contains(':') -or
                @($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                $problem = 'the archive has an unsafe file name: ' + $name; break
            }
            if ($seen.ContainsKey($relative.ToLowerInvariant())) { $problem = 'the archive names a file twice: ' + $name; break }
            $seen[$relative.ToLowerInvariant()] = $true
            $target = [IO.Path]::Combine($staging, $relative.Replace('/', '\'))
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
            $stream = $entry.Open()
            try { $expected[$relative] = Get-StreamSha256 $stream } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
} catch {
    $problem = 'the archive could not be read: ' + $_.Exception.Message
}
if (-not $problem -and -not $expected.Contains('vantage.lua')) { $problem = 'the archive has no addons/vantage/vantage.lua.' }
if (-not $problem) {
    foreach ($relative in $expected.Keys) {
        if ((Get-Sha256 ([IO.Path]::Combine($staging, $relative.Replace('/', '\')))) -ne $expected[$relative]) {
            $problem = 'the archive did not unpack the same: ' + $relative; break
        }
    }
}
if (-not $problem -and (Test-Path -LiteralPath $addon) -and [IO.Path]::GetPathRoot($addon) -ine [IO.Path]::GetPathRoot($backup)) {
    $problem = 'the backup folder must be on the same drive as the game folder. Pass -BackupParent.'
}
if ($problem) {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Stop-Refused $problem
}

# From here on a failure puts the old addon back. Folders move with Directory.Move, which renames the whole folder or
# fails and leaves it as it was; Move-Item moves what it can and leaves the rest behind.
$moved = $false
$created = $false
try {
    if (Test-Path -LiteralPath $addon) {
        [IO.Directory]::Move($addon, $backup)
        $moved = $true
        $receipt.backup = $backup
    }
    [void][IO.Directory]::CreateDirectory($addon)
    $created = $true
    foreach ($relative in $expected.Keys) {
        $target = [IO.Path]::Combine($addon, $relative.Replace('/', '\'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath ([IO.Path]::Combine($staging, $relative.Replace('/', '\'))) -Destination $target
    }
    foreach ($relative in $expected.Keys) {
        $hash = Get-Sha256 ([IO.Path]::Combine($addon, $relative.Replace('/', '\')))
        if ($hash -ne $expected[$relative]) { throw ('the copied file differs from the archive: ' + $relative) }
        $receipt.files[$relative] = $hash
    }
    $copied = @(Get-ChildItem -LiteralPath $addon -Recurse -Force -File).Count
    if ($copied -ne $expected.Count) { throw ('addons\vantage holds ' + $copied + ' files, the archive ' + $expected.Count) }
    if ($TestFailure -like 'after_copy*') { throw 'test failure after the copy' }
    $receipt.settings_after = Get-SettingsHashes $Game
    if (-not (Test-SameHashes $receipt.settings_before $receipt.settings_after)) { throw 'a settings file changed during the install' }
    $receipt.result = 'installed'
} catch {
    $receipt.reason = $_.Exception.Message
    $receipt.result = 'failed, put back'
    $held = $null
    if ($TestFailure -eq 'after_copy_held') { $held = [IO.File]::Open([IO.Path]::Combine($addon, 'vantage.lua'), 'Open', 'Read', 'None') }
    try {
        # Only the copy this made moves aside: an old addon that couldn't be moved is still the old addon.
        if ($created -and (Test-Path -LiteralPath $addon)) {
            $aside = if ($moved) { $backup + '-failed-copy' } else { [IO.Path]::Combine($BackupParent, 'vantage-addon-failed-copy-' + $stamp) }
            [IO.Directory]::Move($addon, $aside)
            $receipt.failed_copy = $aside
        }
        if ($moved) { [IO.Directory]::Move($backup, $addon) }
    } catch {
        $receipt.result = 'failed, not put back'
        $receipt.reason += '. Putting the old addon back failed too: ' + $_.Exception.Message
    } finally {
        if ($held) { $held.Dispose() }
    }
    if ($null -eq $receipt.settings_after) { $receipt.settings_after = Get-SettingsHashes $Game }
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
Write-Receipt

if ($receipt.result -eq 'installed') {
    Write-Output ('Installed ' + $expected.Count + ' files in ' + $addon + '. Every file matches the archive and no settings file changed.')
    if ($receipt.backup) { Write-Output ('The old addon is in ' + $backup + '.') }
    Write-Output ('Receipt: ' + $receiptPath)
    Write-Output 'Next: if the game is running, type /addon reload vantage in game (/addon load vantage if Vantage is not loaded).'
    exit 0
}
Write-Output ('Not installed: ' + $receipt.reason)
if ($receipt.result -eq 'failed, put back') {
    if ($moved) { Write-Output ('The old addon is back in ' + $addon + '.') }
    elseif (-not $created -and (Test-Path -LiteralPath $addon)) { Write-Output ('The old addon was not moved. It is still in ' + $addon + '.') }
    if ($receipt.failed_copy) { Write-Output ('The partial copy is in ' + $receipt.failed_copy + '.') }
    Write-Output ('Receipt: ' + $receiptPath)
    exit 2
}
if ($moved) {
    Write-Output ('The old addon is in ' + $backup + '. Move it back to ' + $addon + ' by hand.')
} else {
    Write-Output ('There was no old addon. The partial copy is still in ' + $addon + '. Move it out of the game folder by hand.')
}
Write-Output ('Receipt: ' + $receiptPath)
exit 3
