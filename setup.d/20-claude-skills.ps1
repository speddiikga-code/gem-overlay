# Copies each folder in the overlay's skills\ into ~\.claude\skills\, where Claude Code loads
# user-level skills. A file is written only when its content differs, so a rerun changes nothing.
# The overlay copy is the source: an edit made in ~\.claude\skills is replaced on the next run.
$ErrorActionPreference = 'Stop'

$overlay = $env:DEVSTARTER_OVERLAY ? $env:DEVSTARTER_OVERLAY : (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $overlay 'skills'
$userHome = $env:DEVSTARTER_SANDBOX ? (Join-Path $env:DEVSTARTER_SANDBOX 'home') : $HOME
$target = Join-Path $userHome '.claude\skills'
# Test suites and caches are for developing a skill, not for Claude Code to load.
$skipDirs = 'tests', '__pycache__', '.pytest_cache'

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    Write-Host "   skills: no skills folder in $overlay"
    exit 0
}

function Get-SkillFiles([string]$Dir) {
    foreach ($item in Get-ChildItem -LiteralPath $Dir) {
        if ($item.PSIsContainer) {
            if ($item.Name -notin $skipDirs) { Get-SkillFiles $item.FullName }
        } else { $item }
    }
}

foreach ($skill in Get-ChildItem -LiteralPath $source -Directory | Sort-Object Name) {
    $dest = Join-Path $target $skill.Name
    $written = 0
    foreach ($file in Get-SkillFiles $skill.FullName) {
        $to = Join-Path $dest ([IO.Path]::GetRelativePath($skill.FullName, $file.FullName))
        if ((Test-Path -LiteralPath $to) -and (Get-FileHash -LiteralPath $to).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) {
            continue
        }
        New-Item -ItemType Directory -Force (Split-Path -Parent $to) | Out-Null
        Copy-Item -LiteralPath $file.FullName $to -Force
        $written++
    }
    $state = $written ? "$written file(s) written" : 'up to date'
    Write-Host "   skills: $($skill.Name) -> $dest ($state)"
}
