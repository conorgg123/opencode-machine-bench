$ErrorActionPreference = 'SilentlyContinue'
function Line($k, $v) { "{0,-30} {1}" -f $k, $v }

"=== SYSTEM ==="
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Line "cpu" $cpu.Name
Line "cores_threads" ("{0}c/{1}t" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
Line "max_clock_mhz" $cpu.MaxClockSpeed
Line "ram_gb" ([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))
Line "os" (Get-CimInstance Win32_OperatingSystem).Caption
Line "power_scheme" ((powercfg /getactivescheme) -join '')
Get-PhysicalDisk | ForEach-Object { Line "disk" ("{0} | {1} | {2} | {3}GB" -f $_.FriendlyName, $_.MediaType, $_.BusType, [math]::Round($_.Size / 1GB)) }
try { $mp = Get-MpComputerStatus; Line "defender_realtime" $mp.RealTimeProtectionEnabled } catch { }
try { Line "defender_exclusions" (((Get-MpPreference).ExclusionPath) -join ';') } catch { }
if (Get-Command node -ErrorAction SilentlyContinue) { Line "node" (node --version) }

"=== CPU single-core ==="
Add-Type -TypeDefinition @'
public static class Bench {
    public static long IntLoop(long n) { long x = 1; for (long i = 1; i <= n; i++) { x = (x * 1103515245 + 12345) & 0x7fffffffL; } return x; }
    public static double FpLoop(long n) { double x = 1.0; for (long i = 1; i <= n; i++) { x = x * 1.0000001 + 0.5; } return x; }
}
'@
$sw = [Diagnostics.Stopwatch]::StartNew(); [void][Bench]::IntLoop(500000000); $sw.Stop()
Line "int_loop_500M_ms" $sw.ElapsedMilliseconds
$sw = [Diagnostics.Stopwatch]::StartNew(); [void][Bench]::FpLoop(300000000); $sw.Stop()
Line "fp_loop_300M_ms" $sw.ElapsedMilliseconds
$sha = [System.Security.Cryptography.SHA256]::Create()
$zbuf = New-Object byte[] 268435456
$sw = [Diagnostics.Stopwatch]::StartNew(); [void]$sha.ComputeHash($zbuf); $sw.Stop()
Line "sha256_256MB_ms" $sw.ElapsedMilliseconds

"=== DISK ==="
$dir = Join-Path $env:TEMP "opencode\bench"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$file = Join-Path $dir "seq.bin"
$chunk = New-Object byte[] 4194304
$fs = [System.IO.File]::Create($file, 1048576, [System.IO.FileOptions]::WriteThrough)
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 128; $i++) { $fs.Write($chunk, 0, $chunk.Length) }
$fs.Flush($true); $sw.Stop(); $fs.Close()
Line "seq_write_512MB_MBps" ([math]::Round(512000.0 / $sw.ElapsedMilliseconds, 1))
$fs = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1048576)
$sw = [Diagnostics.Stopwatch]::StartNew()
while (($n = $fs.Read($chunk, 0, $chunk.Length)) -gt 0) { }
$sw.Stop(); $fs.Close()
Line "seq_read_512MB_MBps" ([math]::Round(512000.0 / $sw.ElapsedMilliseconds, 1))
Remove-Item $file -Force

$smallDir = Join-Path $dir "small"
New-Item -ItemType Directory -Path $smallDir -Force | Out-Null
$small = New-Object byte[] 4096
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 1000; $i++) { [System.IO.File]::WriteAllBytes((Join-Path $smallDir "$i.tmp"), $small) }
$sw.Stop()
Line "small_write_1000x4KB_ms" $sw.ElapsedMilliseconds
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 1000; $i++) { [void][System.IO.File]::ReadAllBytes((Join-Path $smallDir "$i.tmp")) }
$sw.Stop()
Line "small_read_1000x4KB_ms" $sw.ElapsedMilliseconds
Remove-Item $smallDir -Recurse -Force

"=== NETWORK ==="
$sw = [Diagnostics.Stopwatch]::StartNew()
[void]([System.Net.Dns]::GetHostAddresses("opencode.ai"))
$sw.Stop()
Line "dns_opencode_ai_ms" $sw.ElapsedMilliseconds
$samples = @()
for ($i = 0; $i -lt 3; $i++) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $req = [System.Net.WebRequest]::Create("https://opencode.ai/")
    $req.Timeout = 15000
    try { $resp = $req.GetResponse(); $resp.Close() } catch { }
    $sw.Stop()
    $samples += $sw.ElapsedMilliseconds
}
Line "https_ttfb_ms_3runs" ($samples -join ',')
$p = Test-Connection -ComputerName 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue
if ($p) { Line "ping_1.1.1.1_avg_ms" ([math]::Round(($p | Measure-Object -Property ResponseTime -Average).Average, 1)) }

"=== LOAD ==="
Line "processes" (Get-Process).Count
$c = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2
Line "cpu_load_pct" ([math]::Round(($c.CounterSamples | Measure-Object -Property CookedValue -Average).Average))
