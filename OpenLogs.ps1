$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }

$logPaths = @(
    (Join-Path $scriptDir "MusicSelektor.debug.log"),
    (Join-Path $scriptDir "MusicSelektor.debug.previous.log"),
    (Join-Path $scriptDir "MusicSelektor.network.trace.log"),
    (Join-Path $scriptDir "MusicSelektor.network.trace.previous.log"),
    (Join-Path $scriptDir "MusicSelektor.write-actions.log")
)

$opened = 0
foreach ($path in $logPaths) {
    if (Test-Path -LiteralPath $path) {
        Start-Process "notepad.exe" -ArgumentList "`"$path`""
        $opened++
    }
}

Write-Output ("Logs ouverts: {0}" -f $opened)
