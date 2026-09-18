param(
    [switch]$Elevated,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$LogPath = ""
)

if (-not $LogPath) { $LogPath = Join-Path $env:TEMP "opencode-fix-result.txt" }

function Say([string]$m) {
    Write-Host $m
    Add-Content -LiteralPath $LogPath -Value $m -ErrorAction SilentlyContinue
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $Elevated) {
    Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
    Write-Host "Requesting administrator rights (a UAC prompt will appear - click Yes)..."
    try {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated -ProjectPath `"$ProjectPath`" -LogPath `"$LogPath`""
        Start-Process powershell -Verb RunAs -Wait -ArgumentList $argList
    } catch {
        Write-Host "Elevation failed or was cancelled. Re-run opencode as administrator, or run fixit.ps1 from an elevated PowerShell."
        exit 1
    }
    if (Test-Path -LiteralPath $LogPath) {
        Get-Content -LiteralPath $LogPath
    } else {
        Write-Host "No log was produced; elevation was probably cancelled."
    }
    exit 0
}

Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue

Say "=== opencode machine fixes ==="
Say ("time:    {0}" -f (Get-Date).ToString("u"))
Say ("project: {0}" -f $ProjectPath)
Say ("admin:   {0}" -f $isAdmin)

$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) {
    $onAc = (@($bat) | Where-Object { $_.BatteryStatus -eq 2 } | Measure-Object).Count
    Say ("on AC:   {0}" -f ($onAc -gt 0))
}

Say ""
Say "--- power plan ---"
$ultimate = "e9a42b02-d5df-448d-aa00-03f14749eb61"
if (((powercfg /list) -join "`n") -notmatch $ultimate) {
    [void](powercfg /duplicatescheme $ultimate 2>$null)
}
if (((powercfg /list) -join "`n") -match $ultimate) {
    [void](powercfg /setactive $ultimate)
    Say "set: Ultimate Performance"
} else {
    [void](powercfg /setactive SCHEME_MIN)
    Say "set: High performance (Ultimate Performance not available on this system)"
}
[void](powercfg /overlaysetactive ded574b5-45a0-4f42-8737-46345c09c238 2>$null)
[void](powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2)
[void](powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100)
[void](powercfg /setactive SCHEME_CURRENT)
Say "boost: aggressive, max processor state 100% (AC)"
Say ("active now: {0}" -f ((powercfg /getactivescheme) -join ''))

Say ""
Say "--- defender exclusions ---"
$paths = @(
    (Join-Path $env:USERPROFILE ".opencode"),
    (Join-Path $env:LOCALAPPDATA "opencode"),
    (Join-Path $env:APPDATA "opencode"),
    (Join-Path $env:USERPROFILE ".bun"),
    (Join-Path $env:APPDATA "npm"),
    $env:TEMP,
    $ProjectPath
) | Where-Object { $_ } | Select-Object -Unique

$existing = @()
try { $existing = @((Get-MpPreference).ExclusionPath) } catch { }

foreach ($p in $paths) {
    if ($existing -contains $p) { Say ("already excluded: {0}" -f $p); continue }
    try {
        Add-MpPreference -ExclusionPath $p -ErrorAction Stop
        Say ("excluded: {0}" -f $p)
    } catch {
        Say ("FAILED: {0} ({1})" -f $p, $_.Exception.Message)
    }
}

Say ""
Say "--- verify ---"
try { Say ("realtime protection still on: {0}" -f (Get-MpComputerStatus).RealTimeProtectionEnabled) } catch { }
try { Say ("exclusions: {0}" -f (((Get-MpPreference).ExclusionPath) -join '; ')) } catch { }

Say ""
Say "--- undo ---"
Say "powercfg /setactive SCHEME_BALANCED"
Say "Remove-MpPreference -ExclusionPath '<path>'"
Say ""
Say "Done. Re-run bench.ps1 and compare with the baseline."
