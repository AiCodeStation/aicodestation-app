<#
    Update-Release.ps1

    Rolls a new AiCodeStation version through every file that names a version or a checksum:
    the README, the product page, the winget manifests, and the AUR PKGBUILD.

    The checksums are taken from the SIGNED SHA256SUMS.txt.asc, never from a web page and
    never typed by hand, and the signature is verified against the pinned release-key
    fingerprint before a single file is touched. A wrong checksum therefore cannot reach a
    public page: the script stops instead.

    Usage:
      .\Update-Release.ps1 -Version 1.0.31 -DryRun     # show what would change
      .\Update-Release.ps1 -Version 1.0.31             # apply
      .\Update-Release.ps1 -Version 1.0.31 -Publish    # apply, commit, push, draft the release
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [string] $RepoRoot = $PSScriptRoot,
    [string] $BaseUrl  = 'https://acsdownloads.blob.core.windows.net/releases',

    # Pinned release key. Verification fails if the signature is not from this key.
    [string] $KeyFingerprint = 'E77976A5D8A617528244D939E4E65E9412CD53CA',

    [switch] $DryRun,
    [switch] $Publish,

    # Only for a build published before the signed sums exist. Prints a loud warning.
    [switch] $SkipSignature
)

# Native tools write progress to stderr, which Stop turns into a false terminating error
# on Windows PowerShell 5.1. Exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Windows PowerShell 5.1 gets UTF-8 wrong in both directions, and both failures are silent:
# Get-Content reads a BOM-less UTF-8 file as ANSI, corrupting every non-ASCII character, and
# Set-Content -Encoding utf8 writes a byte-order mark that breaks PKGBUILD and can fail winget
# validation. Read and write explicitly instead.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Read-Utf8  { param([string] $Path) [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Write-Utf8 { param([string] $Path, [string] $Text) [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom) }

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

# The five artefacts, and how each filename is spelled for a given version.
$Artefacts = @(
    @{ Key = 'exe';      Name = { param($v) "AiCodeStation-Setup-$v.exe" } }
    @{ Key = 'deb';      Name = { param($v) "aicodestation_${v}_amd64.deb" } }
    @{ Key = 'rpm';      Name = { param($v) "aicodestation-$v-1.x86_64.rpm" } }
    @{ Key = 'appimage'; Name = { param($v) "AiCodeStation-$v-x86_64.AppImage" } }
    @{ Key = 'targz';    Name = { param($v) "AiCodeStation-$v-linux-x86_64.tar.gz" } }
)

# Files that carry a version or a checksum.
$Targets = @('README.md', 'docs/index.html', 'packaging/aur/PKGBUILD')

# ------------------------------------------------------------------ PREFLIGHT
Write-Step 'Preflight (read-only)'
$fatal = 0

if (-not (Test-Path (Join-Path $RepoRoot 'README.md'))) {
    Write-Fail "RepoRoot does not look like the repository: $RepoRoot"; exit 1
}
Write-Ok "repository: $RepoRoot"

# Work out the version currently in the tree.
$page = Read-Utf8 (Join-Path $RepoRoot 'docs/index.html')
$m = [regex]::Match($page, '"softwareVersion":\s*"(\d+\.\d+\.\d+)"')
if (-not $m.Success) { Write-Fail 'Could not read the current version from docs/index.html'; exit 1 }
$OldVersion = $m.Groups[1].Value

if ($OldVersion -eq $Version) {
    Write-Fail "The tree is already at $Version. Nothing to do."; exit 1
}
Write-Ok "version: $OldVersion -> $Version"

foreach ($t in $Targets) {
    if (Test-Path (Join-Path $RepoRoot $t)) { Write-Ok "target present: $t" }
    else { Write-Fail "missing: $t"; $fatal++ }
}

$oldWinget = Join-Path $RepoRoot "packaging/winget/$OldVersion"
if (Test-Path $oldWinget) { Write-Ok "winget template: packaging/winget/$OldVersion" }
else { Write-Fail "missing winget folder for $OldVersion"; $fatal++ }

if ($fatal -gt 0) { Write-Host "`nPreflight failed. Nothing changed." -ForegroundColor Red; exit 1 }

# ------------------------------------------------- SIGNED CHECKSUMS
Write-Step "Fetch and verify the signed checksums for $Version"

$sumsUrl = "$BaseUrl/$Version/SHA256SUMS.txt.asc"
$work    = Join-Path ([IO.Path]::GetTempPath()) "acs-release-$Version-$stamp"
New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
$sumsPath = Join-Path $work 'SHA256SUMS.txt.asc'

try {
    Invoke-WebRequest -Uri $sumsUrl -OutFile $sumsPath -UseBasicParsing -TimeoutSec 60
    Write-Ok "downloaded $sumsUrl"
} catch {
    Write-Fail "Could not fetch $sumsUrl"
    Write-Host "           $($_.Exception.Message)" -ForegroundColor DarkYellow
    Write-Host "           Publish the build and its signed checksums first." -ForegroundColor DarkYellow
    exit 1
}

if ($SkipSignature) {
    Write-Warn2 'SIGNATURE NOT VERIFIED (-SkipSignature). Checksums are being trusted blindly.'
} else {
    # Git for Windows ships gpg but does not put it on the system PATH, so a plain
    # PowerShell session finds nothing even though the tool is installed. Look there too.
    $gpgExe = $null
    $cmd = Get-Command gpg -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        $gpgExe = $cmd.Source
    } else {
        foreach ($candidate in @(
            "$env:ProgramFiles\Git\usr\bin\gpg.exe",
            "${env:ProgramFiles(x86)}\Git\usr\bin\gpg.exe",
            "$env:ProgramFiles\GnuPG\bin\gpg.exe",
            "${env:ProgramFiles(x86)}\GnuPG\bin\gpg.exe",
            "$env:LOCALAPPDATA\Programs\Git\usr\bin\gpg.exe"
        )) {
            if (Test-Path $candidate) { $gpgExe = $candidate; break }
        }
    }
    if ($null -eq $gpgExe) {
        Write-Fail 'gpg not found, so the signature cannot be verified.'
        Write-Host "           Install Gpg4win from https://gpg4win.org, or re-run with" -ForegroundColor DarkYellow
        Write-Host "           -SkipSignature if you accept publishing unverified checksums." -ForegroundColor DarkYellow
        exit 1
    }
    Write-Ok "gpg: $gpgExe"
    $out = & $gpgExe --status-fd 1 --verify $sumsPath 2>&1 | Out-String
    $fpr = $KeyFingerprint.ToUpper()
    if ($out -match "VALIDSIG\s+$fpr" -or $out -match [regex]::Escape($fpr)) {
        if ($out -match 'GOODSIG|VALIDSIG') {
            Write-Ok "signature verified against $KeyFingerprint"
        } else {
            Write-Fail 'The key matched but the signature is not good.'; Write-Host $out; exit 1
        }
    } else {
        Write-Fail 'The checksums are NOT signed by the pinned release key.'
        Write-Host "           expected $fpr" -ForegroundColor DarkYellow
        Write-Host ($out) -ForegroundColor DarkYellow
        Write-Host "           Import the key first: gpg --recv-keys $fpr" -ForegroundColor DarkYellow
        exit 1
    }
}

# Parse "<sha256>  <filename>" out of the signed document.
$sums = @{}
foreach ($line in (Get-Content $sumsPath)) {
    $lm = [regex]::Match($line, '^\s*([a-fA-F0-9]{64})\s+\*?(\S+)\s*$')
    if ($lm.Success) { $sums[$lm.Groups[2].Value] = $lm.Groups[1].Value.ToLower() }
}
Write-Ok "parsed $($sums.Count) checksum(s)"

# Map each artefact old -> new.
$map = @()
foreach ($a in $Artefacts) {
    $oldName = & $a.Name $OldVersion
    $newName = & $a.Name $Version
    if (-not $sums.ContainsKey($newName)) {
        Write-Fail "SHA256SUMS does not list $newName"
        Write-Host "           listed: $($sums.Keys -join ', ')" -ForegroundColor DarkYellow
        $fatal++
        continue
    }
    $oldSha = $null
    $om = [regex]::Match($page, "(?i)([a-f0-9]{64})(?=[^a-f0-9]*$([regex]::Escape($oldName)))")
    $readme = Read-Utf8 (Join-Path $RepoRoot 'README.md')
    $om2 = [regex]::Matches($readme, "(?i)$([regex]::Escape($oldName)).{0,400}?([a-f0-9]{64})", 'Singleline')
    if ($om2.Count -gt 0) { $oldSha = $om2[0].Groups[1].Value.ToLower() }

    $map += [pscustomobject]@{
        Key = $a.Key; OldName = $oldName; NewName = $newName
        OldSha = $oldSha; NewSha = $sums[$newName]
    }
}
if ($fatal -gt 0) { Write-Host "`nAborted. Nothing changed." -ForegroundColor Red; exit 1 }

Write-Step 'Checksum changes'
foreach ($e in $map) {
    Write-Host ("    {0,-9} {1}" -f $e.Key, $e.NewName)
    if ($e.OldSha) { Write-Host ("              old {0}" -f $e.OldSha) -ForegroundColor DarkGray }
    Write-Host     ("              new {0}" -f $e.NewSha) -ForegroundColor Green
}

# Confirm every artefact is actually downloadable before rewriting anything.
Write-Step 'Confirm each download resolves'
foreach ($e in $map) {
    $u = "$BaseUrl/$Version/$($e.NewName)"
    try {
        $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 30
        Write-Ok ("{0,-9} HTTP {1}  {2:N0} MB" -f $e.Key, $r.StatusCode, ($r.Headers['Content-Length'] / 1MB))
    } catch {
        Write-Fail "$($e.NewName) is not reachable at $u"; $fatal++
    }
}
if ($fatal -gt 0) { Write-Host "`nAborted. Nothing changed." -ForegroundColor Red; exit 1 }

if ($DryRun) {
    Write-Host "`n-DryRun set. Verified only, nothing written." -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------- REWRITE
Write-Step 'Rewrite the tracked files'

$backupDir = Join-Path $RepoRoot ".release-backup/$stamp"
New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null

foreach ($t in $Targets) {
    $p = Join-Path $RepoRoot $t
    $text = Read-Utf8 $p

    $dest = Join-Path $backupDir ($t -replace '[\\/]', '_')
    Write-Utf8 $dest $text

    foreach ($e in $map) {
        if ($e.OldSha) { $text = $text -replace $e.OldSha, $e.NewSha }
        $text = $text.Replace($e.OldName, $e.NewName)
    }
    $text = $text.Replace($OldVersion, $Version)

    Write-Utf8 $p $text
    Write-Ok "$t  (backup in .release-backup/$stamp)"
}

# winget wants a folder per version.
$newWinget = Join-Path $RepoRoot "packaging/winget/$Version"
if (Test-Path $newWinget) { Write-Warn2 "packaging/winget/$Version already exists, overwriting" }
else { New-Item -ItemType Directory -Path $newWinget -Force -ErrorAction Stop | Out-Null }

$today = Get-Date -Format 'yyyy-MM-dd'
foreach ($f in (Get-ChildItem $oldWinget -Filter *.yaml)) {
    $text = Read-Utf8 $f.FullName
    $exe  = $map | Where-Object { $_.Key -eq 'exe' }
    $text = $text.Replace($OldVersion, $Version)
    if ($exe.OldSha) { $text = $text -replace "(?i)$($exe.OldSha)", $exe.NewSha.ToUpper() }
    $text = $text -replace 'ReleaseDate:\s*\d{4}-\d{2}-\d{2}', "ReleaseDate: $today"
    Write-Utf8 (Join-Path $newWinget $f.Name) $text
    Write-Ok "packaging/winget/$Version/$($f.Name)"
}

# ------------------------------------------------------------------ VALIDATE
Write-Step 'Validate the result'
$problems = 0

$allFiles = @()
foreach ($t in $Targets) { $allFiles += (Join-Path $RepoRoot $t) }
$allFiles += (Get-ChildItem $newWinget -Filter *.yaml | ForEach-Object { $_.FullName })

foreach ($p in $allFiles) {
    $text = Read-Utf8 $p
    $rel  = $p.Replace($RepoRoot, '').TrimStart('\', '/')

    if ($text -match [regex]::Escape($OldVersion)) {
        Write-Fail "$rel still mentions $OldVersion"; $problems++
    }

    # Every 64-hex string left in the file must be a checksum from the signed document.
    $known = @($map | ForEach-Object { $_.NewSha })
    foreach ($h in [regex]::Matches($text, '[a-fA-F0-9]{64}')) {
        if ($known -notcontains $h.Value.ToLower()) {
            Write-Fail "$rel contains a checksum that is not in the signed SHA256SUMS: $($h.Value)"
            $problems++
        }
    }
}
if ($problems -eq 0) { Write-Ok 'no stale versions, and every checksum traces to the signed document' }

foreach ($e in $map) {
    $readme = Read-Utf8 (Join-Path $RepoRoot 'README.md')
    if ($readme -match [regex]::Escape($e.NewSha)) { Write-Ok "$($e.Key): new checksum present in README" }
    else { Write-Fail "$($e.Key): new checksum missing from README"; $problems++ }
}

if ($problems -gt 0) {
    Write-Host "`n$problems problem(s). The originals are in .release-backup/$stamp" -ForegroundColor Red
    exit 1
}

Write-Host "`nUpdated to $Version." -ForegroundColor Green
Write-Host "Review with: git -C `"$RepoRoot`" diff" -ForegroundColor White

# ------------------------------------------------------------------- PUBLISH
if ($Publish) {
    Write-Step 'Commit, push, and draft the GitHub release'
    & git -C $RepoRoot add -A
    & git -C $RepoRoot commit -m "Release $Version"
    if ($LASTEXITCODE -ne 0) { Write-Fail 'commit failed'; exit 1 }
    & git -C $RepoRoot push origin main
    if ($LASTEXITCODE -ne 0) { Write-Fail 'push failed'; exit 1 }
    Write-Ok 'pushed'

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        Write-Warn2 'gh not found, so the GitHub release was not created. Create it manually.'
    } else {
        $notes = "AiCodeStation $Version. Checksums below are taken from the signed SHA256SUMS.txt.asc.`n`n"
        foreach ($e in $map) {
            $notes += "- [$($e.NewName)]($BaseUrl/$Version/$($e.NewName))`n  ``$($e.NewSha)```n"
        }
        $notes += "`nVerify: https://app.aicodestation.com/#verify-what-you-downloaded"
        $nf = Join-Path $work 'notes.md'
        Write-Utf8 $nf $notes
        & gh release create "v$Version" --repo AiCodeStation/aicodestation-app --title "AiCodeStation $Version" --notes-file $nf --draft
        if ($LASTEXITCODE -eq 0) { Write-Ok "draft release v$Version created, review and publish it on GitHub" }
        else { Write-Warn2 'gh release create failed' }
    }
}

Write-Host "`nStill to do by hand:" -ForegroundColor Yellow
Write-Host "  1. Submit packaging/winget/$Version to microsoft/winget-pkgs" -ForegroundColor Yellow
Write-Host "  2. Push the refreshed PKGBUILD to AUR (regenerate .SRCINFO first)" -ForegroundColor Yellow
