# Copies what a cloud workstation needs into the overlay's cloud\ folder, so a codespace built from
# the overlay (.devcontainer\post-create.sh) gets the same agent rules and git hooks as this PC: the
# generated global rules, DEV's AGENTS.md and the kit's hooks, with LF endings because they are read
# on Linux. Runs after the kit's own steps, so the generated files are current; save.ps1 runs it too.
# A source that is missing or out of date is reported and skipped, and the script then exits 1.
#   -DryRun   list what would change; exits 2 when something would be written (save.ps1 -DryRun reads it)
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$overlay = Split-Path -Parent $PSScriptRoot
$userHome = $env:DEVSTARTER_SANDBOX ? (Join-Path $env:DEVSTARTER_SANDBOX 'home') : $HOME
$dev = $env:DEV ? $env:DEV : (Split-Path -Parent $overlay)
$kit = $env:DEVSTARTER_ROOT ? $env:DEVSTARTER_ROOT : (Join-Path $dev 'gem-setting')
$cloud = Join-Path $overlay 'cloud'

$copies = [ordered]@{
    'CLAUDE.md'              = Join-Path $userHome '.claude\CLAUDE.md'
    'AGENTS.md'              = Join-Path $dev 'AGENTS.md'
    'git-hooks\commit-msg'   = Join-Path $kit 'commit-msg'
    'git-hooks\forward-hook' = Join-Path $kit 'forward-hook'
    'git-hooks\pre-push'     = Join-Path $kit 'pre-push'
}

$skipped = 0
$changed = 0
foreach ($name in $copies.Keys) {
    $source = $copies[$name]
    $target = Join-Path $cloud $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Host "   cloud: $source is missing, so cloud\$name was not refreshed" -ForegroundColor Yellow
        $skipped++
        continue
    }
    $text = [IO.File]::ReadAllText($source).Replace("`r`n", "`n")
    # Setup appends each rules\*.md to the generated rules; until it runs again after a rule
    # changes, exporting them (as gem-save does) would hand the codespace older rules than the ones
    # committed next to them.
    if ($name -eq 'CLAUDE.md') {
        $stale = @(Get-ChildItem -LiteralPath (Join-Path $overlay 'rules') -Filter *.md -File -ErrorAction Ignore |
            Where-Object { -not $text.Contains([IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n").Trim()) })
        if ($stale) {
            Write-Host "   cloud: $source lacks rules\$($stale[0].Name), so cloud\$name was not refreshed; run gem-setup first" -ForegroundColor Yellow
            $skipped++
            continue
        }
    }
    if ((Test-Path -LiteralPath $target) -and [IO.File]::ReadAllText($target) -ceq $text) { continue }
    $changed++
    if ($DryRun) {
        Write-Host "   cloud: would write cloud\$name from $source"
        continue
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
    [IO.File]::WriteAllText($target, $text)
    Write-Host "   cloud: wrote cloud\$name from $source"
}
if (-not $changed -and -not $skipped) { Write-Host "   cloud: $cloud is up to date" }
if ($skipped) { exit 1 }
if ($DryRun -and $changed) { exit 2 }
