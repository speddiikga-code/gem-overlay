# Installs the Claude Code CLI when it is missing. The official installer puts claude.exe in
# ~\.local\bin, which may not be on this shell's PATH yet, so a file there counts as installed.
$ErrorActionPreference = 'Stop'

if ($env:DEVSTARTER_SANDBOX) {
    Write-Host '   claude: skipped in a sandbox run'
    exit 0
}

$localExe = Join-Path $HOME '.local\bin\claude.exe'
$onPath = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($onPath -or (Test-Path -LiteralPath $localExe)) {
    Write-Host "   claude: already installed ($($onPath ? $onPath.Source : $localExe))"
    exit 0
}

Write-Host '   claude: installing with the official installer (https://claude.ai/install.ps1)'
# A child process, so a throw or exit inside the downloaded script cannot end this hook early
# and its exit code is the one thing checked.
& pwsh -NoProfile -Command 'irm https://claude.ai/install.ps1 | iex'
if ($LASTEXITCODE) {
    Write-Host "   claude: the installer failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $localExe) -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "   claude: the installer finished but $localExe is missing" -ForegroundColor Red
    exit 1
}
Write-Host "   claude: installed; open a new terminal and run  claude  to sign in"
