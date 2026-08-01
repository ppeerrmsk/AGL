param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$OwnerPid,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$TargetPid,
    [Parameter(Mandatory = $true)]
    [ValidateRange(10, 86400)]
    [int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)]
    [string]$TimeoutMarker
)

$ErrorActionPreference = 'SilentlyContinue'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

function Stop-TargetTree {
    $null = & "$env:SystemRoot\System32\taskkill.exe" /PID $TargetPid /T /F 2>&1
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue
}

while ($true) {
    if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) {
        exit 0
    }
    if (-not (Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)) {
        Stop-TargetTree
        exit 125
    }
    if ((Get-Date) -ge $deadline) {
        Set-Content -LiteralPath $TimeoutMarker -Value 'timeout' -NoNewline
        Stop-TargetTree
        exit 124
    }
    Start-Sleep -Milliseconds 200
}
