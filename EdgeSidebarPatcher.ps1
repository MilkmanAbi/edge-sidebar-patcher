<#
.SYNOPSIS
  Restores the classic Microsoft Edge sidebar (the right-hand app strip) on profiles signed in
  with a personal Microsoft account.

.DESCRIPTION
  Edge (checked on 157) still ships the full sidebar, but only shows the strip when the profile's
  account is a work/school (AAD) account. The decision is read from the profile's Preferences file:

      account_info[0].edge_account_type   1 = personal MSA   2 = work/school AAD

  This script flips that one value to 2 for the chosen profile, and makes sure the sidebar's own
  "visible" prefs are on (they get switched off if you close the sidebar with its button).
  It does not touch Edge's program files, sync settings, or any other profile data.

  A full copy of Preferences is saved next to it before any change, and -Revert puts the original
  values back.

.EXAMPLE
  .\EdgeSidebarPatcher.ps1                 # interactive: lists profiles, asks which one
  .\EdgeSidebarPatcher.ps1 -List
  .\EdgeSidebarPatcher.ps1 -Profile Default
  .\EdgeSidebarPatcher.ps1 -Profile Default -Revert
  .\EdgeSidebarPatcher.ps1 -Channel Beta -Profile "Profile 2" -Yes
#>
[CmdletBinding()]
param(
    [Alias('Profile')]
    [string]$ProfileDir,
    [switch]$List,
    [switch]$Revert,
    [switch]$Yes,
    [ValidateSet('Stable', 'Beta', 'Dev', 'Canary')]
    [string]$Channel = 'Stable',
    [string]$UserDataDir
)

$ErrorActionPreference = 'Stop'
$StateFile = 'sidebar-patch.json'

# ---------------------------------------------------------------- helpers

function Get-UserDataDir {
    if ($UserDataDir) { return $UserDataDir }
    $leaf = @{ Stable = 'Edge'; Beta = 'Edge Beta'; Dev = 'Edge Dev'; Canary = 'Edge SxS' }[$Channel]
    return Join-Path $env:LOCALAPPDATA "Microsoft\$leaf\User Data"
}

function Read-JsonFile([string]$Path) {
    # Edge prefs contain keys PowerShell 5.1's ConvertFrom-Json rejects (e.g. empty names),
    # so parse with -AsHashtable on 7+, JavaScriptSerializer on 5.1. Used for reading only.
    $text = [IO.File]::ReadAllText($Path)
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return ($text | ConvertFrom-Json -AsHashtable -Depth 200)
    }
    Add-Type -AssemblyName System.Web.Extensions
    $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $s.MaxJsonLength = [int]::MaxValue
    $s.RecursionLimit = 1000
    return $s.DeserializeObject($text)
}

function Get-Dig($obj, [string[]]$path) {
    foreach ($k in $path) {
        if ($null -eq $obj) { return $null }
        if ($k -match '^\d+$') { $obj = @($obj)[[int]$k] } else { if ($obj.ContainsKey($k)) { $obj = $obj[$k] } else { return $null } }
    }
    return $obj
}

function Get-Profiles([string]$udd) {
    $ls = Read-JsonFile (Join-Path $udd 'Local State')
    $cache = Get-Dig $ls @('profile', 'info_cache')
    foreach ($dir in $cache.Keys) {
        $pref = Join-Path $udd "$dir\Preferences"
        $type = $null; $tower = $null
        if (Test-Path $pref) {
            $p = Read-JsonFile $pref
            $type = Get-Dig $p @('account_info', '0', 'edge_account_type')
            $tower = Get-Dig $p @('browser', 'hub_apps_tower_visible')
        }
        [pscustomobject]@{
            Dir         = $dir
            Name        = $cache[$dir]['name']
            AccountType = switch ($type) { 1 { 'personal (1)' } 2 { 'work/school (2)' } $null { 'not signed in' } default { "$type" } }
            TowerOn     = $tower
            Patched     = Test-Path (Join-Path $udd "$dir\$StateFile")
        }
    }
}

function Stop-Edge {
    $procs = Get-Process msedge -ErrorAction SilentlyContinue
    if ($UserDataDir) {
        # custom user-data-dir (e.g. a test copy): only close instances running on it
        $ids = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like "*$UserDataDir*" } | ForEach-Object ProcessId
        $procs = $procs | Where-Object { $ids -contains $_.Id }
    }
    if (-not $procs) { return }
    if (-not $Yes) {
        $a = Read-Host 'Edge is running and has to be closed (tabs come back on restore). Close it now? [y/N]'
        if ($a -notmatch '^(y|yes)$') { throw 'Aborted: Edge is still running.' }
    }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 40 -and ($procs | Where-Object { -not $_.HasExited }); $i++) { Start-Sleep -Milliseconds 250 }
    if ($procs | Where-Object { -not $_.HasExited }) { throw 'Edge did not exit; close it (and Startup Boost) and retry.' }
    Start-Sleep -Milliseconds 500   # let file handles drop
}

# Text-level edits keep the rest of Preferences byte-for-byte identical (no re-serialisation,
# so no number/escaping drift). Each edit is anchored to its parent object and verified after.

function Set-AccountType([string]$text, [int]$value) {
    $start = $text.IndexOf('"account_info":[')
    if ($start -lt 0) { throw 'Profile has no account_info (not signed in?). Sign in to Edge with the account first.' }
    # end of the account_info array = matching ']' (strings in prefs are JSON-escaped, so a simple
    # depth scan that skips string contents is enough)
    $i = $start + '"account_info":'.Length; $depth = 0; $inStr = $false; $end = -1
    for (; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($inStr) { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inStr = $false }; continue }
        if ($c -eq '"') { $inStr = $true } elseif ($c -eq '[' -or $c -eq '{') { $depth++ } elseif ($c -eq ']' -or $c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
    }
    if ($end -lt 0) { throw 'Could not find the end of account_info.' }
    $seg = $text.Substring($start, $end - $start + 1)
    $rx = [regex]'"edge_account_type":\d+'
    $m = $rx.Matches($seg)
    if ($m.Count -ne 1) { throw "Expected exactly one edge_account_type inside account_info, found $($m.Count)." }
    $old = [int]($m[0].Value -replace '\D', '')
    $seg2 = $rx.Replace($seg, "`"edge_account_type`":$value", 1)
    return @{ Text = $text.Substring(0, $start) + $seg2 + $text.Substring($end + 1); Old = $old }
}

function Set-BrowserBool([string]$text, [string]$key, [bool]$value) {
    $v = if ($value) { 'true' } else { 'false' }
    $rx = [regex]('"' + [regex]::Escape($key) + '":(true|false)')
    $m = $rx.Matches($text)
    if ($m.Count -gt 1) { throw "Key $key appears $($m.Count) times; refusing to guess." }
    if ($m.Count -eq 1) {
        return @{ Text = $rx.Replace($text, "`"$key`":$v", 1); Old = ($m[0].Groups[1].Value -eq 'true') }
    }
    # absent: insert as first member of the top-level "browser" object
    $b = $text.IndexOf('"browser":{')
    if ($b -lt 0) { return @{ Text = $text; Old = $null } }
    $at = $b + '"browser":{'.Length
    $sep = if ($text[$at] -eq '}') { '' } else { ',' }
    return @{ Text = $text.Insert($at, "`"$key`":$v$sep"); Old = $null }
}

# ---------------------------------------------------------------- main

$udd = Get-UserDataDir
if (-not (Test-Path (Join-Path $udd 'Local State'))) { throw "No Edge user data at: $udd" }

$profiles = @(Get-Profiles $udd)
if ($List -or -not $ProfileDir) {
    Write-Host "Edge $Channel profiles in $udd`n"
    $n = 0
    $profiles | ForEach-Object { $n++; [pscustomobject]@{ '#' = $n; Folder = $_.Dir; Name = $_.Name; Account = $_.AccountType; SidebarPrefOn = $_.TowerOn; Patched = $_.Patched } } | Format-Table -AutoSize | Out-Host
    if ($List) { return }
    $pick = Read-Host 'Number of the profile to patch (or blank to quit)'
    if (-not $pick) { return }
    $ProfileDir = $profiles[[int]$pick - 1].Dir
    if (-not $Revert) {
        $r = Read-Host "Patch '$ProfileDir'? Type R to revert it instead, Enter to patch"
        if ($r -match '^r$') { $Revert = $true }
    }
}

$target = $profiles | Where-Object Dir -eq $ProfileDir
if (-not $target) { throw "No profile folder '$ProfileDir'. Use -List to see them." }
$pdir = Join-Path $udd $ProfileDir
$prefs = Join-Path $pdir 'Preferences'
$state = Join-Path $pdir $StateFile

Stop-Edge
$text = [IO.File]::ReadAllText($prefs)

if ($Revert) {
    if (-not (Test-Path $state)) { throw "No $StateFile in $pdir; nothing recorded to revert." }
    $s = Get-Content $state -Raw | ConvertFrom-Json
    $r = Set-AccountType $text ([int]$s.original_account_type)
    $text = $r.Text
    [IO.File]::WriteAllText($prefs, $text, (New-Object Text.UTF8Encoding($false)))
    Remove-Item $state
    Write-Host "Reverted '$ProfileDir': edge_account_type -> $($s.original_account_type). Full pre-patch backup kept at $($s.backup)."
    return
}

# backup
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $pdir "Preferences.sidebar-backup-$stamp"
Copy-Item $prefs $backup

$r1 = Set-AccountType $text 2
$r2 = Set-BrowserBool $r1.Text 'hub_apps_tower_visible' $true
$r3 = Set-BrowserBool $r2.Text 'show_hub_apps_tower_pinned' $true
$new = $r3.Text

# validate before writing: must still parse, and the values must read back as intended
$tmp = "$prefs.sidebar-tmp"
[IO.File]::WriteAllText($tmp, $new, (New-Object Text.UTF8Encoding($false)))
$chk = Read-JsonFile $tmp
if ((Get-Dig $chk @('account_info', '0', 'edge_account_type')) -ne 2 -or
    (Get-Dig $chk @('browser', 'hub_apps_tower_visible')) -ne $true) {
    Remove-Item $tmp; throw 'Validation failed; Preferences left untouched.'
}
Move-Item -Force $tmp $prefs

# record originals only on the first patch, so re-patching never overwrites the true original
if (-not (Test-Path $state)) {
    @{ original_account_type = $r1.Old; backup = $backup; patched_at = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -Encoding UTF8 $state
}

Write-Host "Patched '$ProfileDir' ($($target.Name)):"
Write-Host "  account_info[0].edge_account_type  $($r1.Old) -> 2"
Write-Host "  browser.hub_apps_tower_visible     $($r2.Old) -> True"
Write-Host "  browser.show_hub_apps_tower_pinned $($r3.Old) -> True"
Write-Host "  backup: $backup"
Write-Host "Start Edge. To undo: .\EdgeSidebarPatcher.ps1 -Profile '$ProfileDir' -Revert"
