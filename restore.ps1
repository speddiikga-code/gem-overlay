# Rebuilds this workstation from GitHub on a new PC: pulls this overlay, clones or updates the
# gem-setting kit next to it, clones the repositories listed in repos.txt, then runs the kit's
# bootstrap.ps1 with this overlay. Started by restore.cmd under the stock Windows PowerShell 5.1,
# because a new PC has no PowerShell 7 yet, so this file keeps to 5.1 syntax and ASCII.
#   restore.cmd            do it
#   restore.cmd -DryRun    print every action without doing it
# The overlay is this script's folder and DEV is its parent: <DEV>\gem-overlay, <DEV>\gem-setting,
# and every repos.txt path under <DEV>.
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$overlay = $PSScriptRoot
$dev = Split-Path -Parent $overlay
$kit = Join-Path $dev 'gem-setting'
$problems = New-Object System.Collections.Generic.List[string]

function Step([string]$Text) { Write-Host "-> $Text" -ForegroundColor Cyan }

# Installers put their folders on the machine and user PATH after this shell started; appended, so
# what is already first on PATH stays first.
function Update-SessionPath {
    $known = $env:PATH -split ';'
    $new = foreach ($scope in 'Machine', 'User') {
        [Environment]::GetEnvironmentVariable('PATH', $scope) -split ';' | Where-Object { $_ -and $_ -notin $known }
    }
    if ($new) { $env:PATH = (@($env:PATH) + $new) -join ';' }
}

function Format-Command([string]$Exe, [string[]]$Arguments) {
    (@($Exe) + $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
}

# git and gh print progress on stderr, which Windows PowerShell 5.1 turns into a terminating error
# under 'Stop' when its own output is redirected; the exit code is what tells success.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $shown = Format-Command $Exe $Arguments
    if ($DryRun) {
        Write-Host "   would run: $shown"
        return 0
    }
    Write-Host "   $shown"
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments | Out-Host
    return $LASTEXITCODE
}

function Test-Native([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments *> $null
    return ($LASTEXITCODE -eq 0)
}

if ($DryRun) { Write-Host 'restore: dry run, nothing is changed' -ForegroundColor Yellow }
Write-Host "restore: overlay $overlay, DEV $dev"
Update-SessionPath

Step 'checking git and the GitHub CLI'
$install = @()
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $install += 'winget install --id Git.Git -e --source winget' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { $install += 'winget install --id GitHub.cli -e --source winget' }
if ($install.Count) {
    Write-Host 'Git and the GitHub CLI are needed first. Install them with:' -ForegroundColor Red
    $install | ForEach-Object { Write-Host "   $_" }
    Write-Host 'Then close this window, open a new terminal, run  gh auth login  and start restore.cmd again.'
    exit 1
}
if (-not (Test-Native gh @('auth', 'status'))) {
    Write-Host 'The GitHub CLI is not signed in. Run this, follow the steps in the browser, then start restore.cmd again:' -ForegroundColor Red
    Write-Host '   gh auth login'
    exit 1
}

# gh clones with its own sign-in, but the git pull and git push that come later need git to use it too.
Step 'git: use the GitHub CLI sign-in'
$code = Invoke-Native gh @('auth', 'setup-git')
if ($code) { $problems.Add("gh auth setup-git failed (exit code $code); git may ask you to sign in again") }

Step "updating the overlay: $overlay"
$code = Invoke-Native git @('-C', $overlay, 'pull', '--ff-only')
if ($code) { $problems.Add("git pull in $overlay failed (exit code $code); the overlay was used as it is") }

if (Test-Path -LiteralPath (Join-Path $kit '.git')) {
    Step "updating the kit: $kit"
    $code = Invoke-Native git @('-C', $kit, 'pull', '--ff-only')
    if ($code) { $problems.Add("git pull in $kit failed (exit code $code); the kit was used as it is") }
} else {
    Step "cloning the kit into $kit"
    $code = Invoke-Native gh @('repo', 'clone', 'gem-setting', $kit)
    if ($code) {
        Write-Host "gem-setting could not be cloned into $kit (exit code $code)." -ForegroundColor Red
        Write-Host 'Check that the repository exists on your GitHub account:  gh repo view gem-setting'
        Write-Host "and that $kit is missing or an empty folder, then start restore.cmd again."
        exit 1
    }
}

Step 'cloning the repositories in repos.txt'
$list = Join-Path $overlay 'repos.txt'
# save.ps1 writes UTF-8 without a BOM, which 5.1 would otherwise read in the ANSI code page and
# turn a Korean folder name into question marks.
$lines = if (Test-Path -LiteralPath $list) { @(Get-Content -LiteralPath $list -Encoding UTF8) } else { @() }
$listed = 0
foreach ($raw in $lines) {
    $line = "$raw".Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $listed++
    $parts = $line -split '\s+', 2
    $repo = $parts[0]
    $relative = if ($parts.Count -gt 1) { $parts[1].Trim() } else { ($repo -split '/')[-1] }
    $relative = $relative -replace '/', '\'
    if ($repo -notmatch '^[\w.-]+/[\w.-]+$' -or [IO.Path]::IsPathRooted($relative) -or ($relative -split '\\') -contains '..') {
        $problems.Add("repos.txt: skipped '$line' (expected: owner/name relative\path)")
        continue
    }
    $target = Join-Path $dev $relative
    if (Test-Path -LiteralPath $target) {
        Write-Host "   $($repo): already at $target"
        continue
    }
    $code = Invoke-Native gh @('repo', 'clone', $repo, $target)
    if ($code) { $problems.Add("gh repo clone $repo failed (exit code $code)") }
}
if (-not $listed) { Write-Host '   repos.txt lists no repositories' }

$bootstrap = Join-Path $kit 'bootstrap.ps1'
# Not $PSHOME: started from PowerShell 7, that folder has no powershell.exe, the call fails without
# setting an exit code, and restore would report the kit as done.
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bootstrapArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bootstrap, '-Overlay', $overlay, '-Dev', $dev)
Step 'running the kit (bootstrap.ps1): apps, settings and this overlay'
$code = 0
if ($DryRun) {
    Write-Host "   would run: $(Format-Command $powershell $bootstrapArgs)"
} elseif (-not (Test-Path -LiteralPath $bootstrap)) {
    $problems.Add("$bootstrap is missing, so the kit did not run")
    $code = 1
} else {
    # Not through Invoke-Native: winget progress and setup's questions need this console.
    $ErrorActionPreference = 'Continue'
    & $powershell @bootstrapArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
}

Write-Host ''
if ($problems.Count) {
    Write-Host 'restore: these steps did not complete (running restore.cmd again is safe):' -ForegroundColor Yellow
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} elseif (-not $DryRun -and -not $code) {
    Write-Host 'restore: done. Open a new terminal and run  claude  once to sign in.' -ForegroundColor Green
}
if ($code) { exit $code }
if ($problems.Count) { exit 1 }
exit 0
