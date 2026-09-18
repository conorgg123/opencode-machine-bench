param([int]$Seconds = 60)

$ErrorActionPreference = 'SilentlyContinue'
function Line($k, $v) { "{0,-30} {1}" -f $k, $v }

Add-Type -TypeDefinition @'
public static class TBench {
    public static long IntLoop(long n) { long x = 1; for (long i = 1; i <= n; i++) { x = (x * 1103515245 + 12345) & 0x7fffffffL; } return x; }
}
'@

function Get-MHz {
    $p = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='0,0'"
    if ($p -and $p.ProcessorFrequency) { return [int]$p.ProcessorFrequency }
    return [int](Get-CimInstance Win32_Processor | Select-Object -First 1).CurrentClockSpeed
}

"=== THERMAL / SUSTAINED LOAD ==="
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Line "cpu" $cpu.Name
$bat = Get-CimInstance Win32_Battery
if ($bat) { Line "on_ac" ((@($bat) | Where-Object { $_.BatteryStatus -eq 2 } | Measure-Object).Count -gt 0) }
try { (Get-Process -Id $PID).ProcessorAffinity = 1; Line "affinity" "cpu0 (single thread)" } catch { Line "affinity" "default (could not pin)" }

$sw = [Diagnostics.Stopwatch]::StartNew()
[void][TBench]::IntLoop(250000000)
$sw.Stop()
$cal = [math]::Max($sw.ElapsedMilliseconds, 250)
$iters = [long]([math]::Round(250000000.0 * 3000.0 / $cal / 50000000.0) * 50000000)
if ($iters -lt 50000000) { $iters = 50000000 }
$chunks = [math]::Max(6, [int][math]::Ceiling($Seconds / 3.0))

Line "chunk_iters" ("{0}M" -f ($iters / 1000000))
Line "chunks" $chunks
""

$times = @()
$clocks = @()
for ($i = 1; $i -le $chunks; $i++) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [void][TBench]::IntLoop($iters)
    $sw.Stop()
    $times += $sw.ElapsedMilliseconds
    $clk = Get-MHz
    $clocks += $clk
    Line ("chunk_{0,2}_ms" -f $i) ("{0}  ({1} MHz)" -f $sw.ElapsedMilliseconds, $clk)
}

$n = $times.Count
$first = ($times[0..([math]::Min(2, $n - 1))] | Measure-Object -Average).Average
$last = ($times[[math]::Max(0, $n - 3)..($n - 1)] | Measure-Object -Average).Average
$slow = [math]::Round((($last / $first) - 1) * 100, 1)
$cmin = ($clocks | Measure-Object -Minimum).Minimum
$cmax = ($clocks | Measure-Object -Maximum).Maximum

""
Line "first3_avg_ms" ([math]::Round($first))
Line "last3_avg_ms" ([math]::Round($last))
Line "slowdown_pct" $slow
Line "clock_min_mhz" $cmin
Line "clock_max_mhz" $cmax
if ($slow -lt 5) { Line "verdict" "stable - no thermal throttling" }
elseif ($slow -lt 15) { Line "verdict" "mild throttling - some sustained slowdown" }
else { Line "verdict" "HEAVY throttling - this machine slows down under sustained load" }

try {
    $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature
    if ($t) {
        $temps = @($t | ForEach-Object { [math]::Round($_.CurrentTemperature / 10.0 - 273.15, 1) })
        Line "temp_c" ($temps -join ',')
    } else {
        Line "temp_c" "not exposed by this machine"
    }
} catch {
    Line "temp_c" "not exposed by this machine"
}
