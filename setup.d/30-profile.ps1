# Writes the PowerShell 7 profile for all hosts (Documents\PowerShell\profile.ps1) with the
# workstation commands gem-save, gem-setup and gem-restore-help. The kit owns the current-host
# profile next to it (Microsoft.PowerShell_profile.ps1); PowerShell loads both. Written only when the
# content differs; a different existing file is kept as profile.ps1.bak first.
$ErrorActionPreference = 'Stop'

$overlay = Split-Path -Parent $PSScriptRoot
$dev = $env:DEV ? $env:DEV : (Split-Path -Parent $overlay)
$kit = $env:DEVSTARTER_ROOT ? $env:DEVSTARTER_ROOT : (Join-Path $dev 'gem-setting')
# MyDocuments, not $HOME\Documents: OneDrive often moves Documents, and PowerShell follows it.
$documents = $env:DEVSTARTER_SANDBOX ? (Join-Path $env:DEVSTARTER_SANDBOX 'home\Documents') : [Environment]::GetFolderPath('MyDocuments')
$path = Join-Path $documents 'PowerShell\profile.ps1'

function ConvertTo-Literal([string]$Text) { "'" + $Text.Replace("'", "''") + "'" }

$save = ConvertTo-Literal (Join-Path $overlay 'save.ps1')
$setup = ConvertTo-Literal (Join-Path $kit 'setup.ps1')
$guide = ConvertTo-Literal (Join-Path $overlay 'MIGRATE.ko.md')
# Each command runs in its own pwsh, so the variables a script sets stay out of this shell.
$text = @"
# Written by $(Join-Path $PSScriptRoot '30-profile.ps1') on every setup run; change that script, not this file.
function gem-save { & pwsh -NoProfile -File $save @args }
function gem-setup { & pwsh -NoProfile -File $setup @args }
function gem-restore-help {
    Write-Host 'Moving this workstation to another PC or to the cloud, step by step (Korean):'
    Write-Host ('  ' + $guide)
    Write-Host '  also in your gem-overlay repository on GitHub, file MIGRATE.ko.md'
}

"@
# The here-string takes this file's line endings, which depend on the checkout.
$text = $text.Replace("`r`n", "`n")

$old = (Test-Path -LiteralPath $path) ? [IO.File]::ReadAllText($path) : $null
if ($old -ceq $text) {
    Write-Host "   profile: $path is up to date"
    exit 0
}
if ($null -ne $old) {
    # As in the kit: the first .bak holds the file from before setup, so later ones get a timestamp.
    $bak = "$path.bak"
    if (Test-Path -LiteralPath $bak) { $bak = "$path.$(Get-Date -Format yyyyMMdd-HHmmss).bak" }
    Copy-Item -LiteralPath $path $bak -Force
}
New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
[IO.File]::WriteAllText($path, $text)
Write-Host "   profile: wrote $path (gem-save, gem-setup, gem-restore-help; open a new terminal to use them)"
