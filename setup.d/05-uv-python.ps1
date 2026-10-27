# The WindowsApps python.exe on this PC is the Python install manager alias, and probing it (as
# `uv python list` or `uv run` without a managed match do) silently downloads a runtime. Limiting uv
# to its own Pythons keeps one Python source and stops those surprise installs.
$ErrorActionPreference = 'Stop'
$name, $value = 'UV_PYTHON_PREFERENCE', 'only-managed'

if ($env:DEVSTARTER_SANDBOX) {
    $file = Join-Path $env:DEVSTARTER_SANDBOX 'user-variables.json'
    $vars = (Test-Path $file) ? (Get-Content $file -Raw | ConvertFrom-Json -AsHashtable) : @{}
    $vars[$name] = $value
    $vars | ConvertTo-Json | Set-Content $file
} elseif ([Environment]::GetEnvironmentVariable($name, 'User') -ne $value) {
    [Environment]::SetEnvironmentVariable($name, $value, 'User')
}
Write-Host "   uv: $name=$value"
