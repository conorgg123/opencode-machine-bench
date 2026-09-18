# opencode-machine-bench

Benchmark + thermal test + fixer for comparing and speeding up opencode machines.

Same model, same opencode — when one machine feels faster, the reason is always local: single-core CPU speed, disk I/O, antivirus tax, network latency to the API, or power/thermal throttling. These scripts measure all of it, fix what's fixable, and verify the result.

## Why one machine is faster (the short version)

The model runs on datacenter GPUs, not on your PC. Same model + same opencode = identical raw inference speed. What differs is everything the local machine does around each API call:

1. **The local half is single-threaded.** opencode's TUI, file reads/writes, and shell commands run on one core. More cores don't help; faster single-core does. A machine that looks weaker on paper can beat a many-core one.
2. **Every step pays network latency.** Each turn of the agent loop is a round-trip to the API. 150ms of extra latency x hundreds of tool calls = seconds to minutes of dead time. Wi-Fi, VPNs, and ISP routing show up here.
3. **Antivirus taxes every file operation.** Real-time scanning intercepts each read/write; folders with many small files pay it on every tool call.
4. **Power and thermal limits throttle the CPU.** Quiet/Balanced power plans and warm laptops drop clocks exactly when the machine is working hard.
5. **Disk speed** is a smaller but real factor for file-heavy work.

That is also the fix priority order: power plan -> antivirus exclusions -> nothing scriptable left (network routing and hardware stay as-is, and the numbers will name them).

## Contents

- `bench.ps1` — CPU single-core, disk, network, throttling context. ~30-60s, changes nothing.
- `thermal.ps1` — 60s sustained single-core load, per-chunk times + live clocks, detects machines that only slow down after warming up. Needs no admin.
- `fixit.ps1` — power plan (Ultimate/High performance, aggressive boost, max state), Defender exclusions for dev folders. Self-elevates (UAC prompt), reversible.

## Full autonomous run (copy-paste into opencode)

> You are diagnosing why this machine runs opencode slower than another machine with the same model and same opencode. Run everything below end-to-end, then analyze it yourself and give me the final verdict. Show raw outputs verbatim, then your analysis. Do not ask questions; a UAC prompt will appear at the fix step — tell the user to click Yes.
>
> ```powershell
> Invoke-WebRequest "https://raw.githubusercontent.com/conorgg123/opencode-machine-bench/main/bench.ps1" -OutFile "$env:TEMP\bench.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\bench.ps1"
>
> Invoke-WebRequest "https://raw.githubusercontent.com/conorgg123/opencode-machine-bench/main/thermal.ps1" -OutFile "$env:TEMP\thermal.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\thermal.ps1"
>
> Invoke-WebRequest "https://raw.githubusercontent.com/conorgg123/opencode-machine-bench/main/fixit.ps1" -OutFile "$env:TEMP\fixit.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\fixit.ps1"
>
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\bench.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\thermal.ps1"
> ```
>
> Then compare this machine's before/after numbers against the reference results below and against each other, and report:
> 1. Which factor makes this machine slower (single-core CPU / disk / network latency / throttling / antivirus)
> 2. What the fixes recovered
> 3. What remains unfixable in software (hardware or network), if anything
> 4. A short plain-English explanation of why this machine was slower, based on the "Why one machine is faster" section above

Total runtime ~4-5 minutes. No admin needed except the fixit step.

## What fixit changes (all reversible)

| Fix | Why | Undo |
|---|---|---|
| Power plan -> Ultimate/High performance + "Best performance" overlay | Quiet/Balanced profiles cap CPU clocks | `powercfg /setactive SCHEME_BALANCED` |
| CPU boost mode -> Aggressive, max processor state 100% (AC) | stops clocks dipping between bursts | `powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 1` |
| Defender path exclusions: opencode dirs, TEMP, npm/bun dirs, current project folder | real-time scanning taxes every file tool call | `Remove-MpPreference -ExclusionPath "<path>"` |

Real-time protection stays ON. Only dev folders are excluded.

## Is it safe on machines with different specs?

Yes. The fixes are generic Windows settings, not tuned to specific hardware, and every change is reversible (see undo column above). On a machine already running a performance plan with exclusions, it is a no-op. The proof is always the machine's own before/after result — the reference numbers are just a yardstick, not a target.

Two notes: the fixes target plugged-in use (on battery, Windows may throttle regardless), and Defender exclusions trade a small amount of security for speed in dev folders only. If a machine has an OEM performance mode (Lenovo/ASUS/Dell software), that mode can still cap clocks — the thermal test will show it.

## Reading benchmark results

- `int_loop_500M_ms`, `fp_loop_300M_ms`, `sha256_256MB_ms` — lower is better. Single-core speed dominates day-to-day opencode responsiveness.
- `seq_write_512MB_MBps`, `seq_read_512MB_MBps` — higher is better.
- `small_write_1000x4KB_ms` — antivirus/Defender tax. Much slower than `small_read` means real-time scanning is slowing every file tool call.
- `https_ttfb_ms_3runs`, `ping_1.1.1.1_avg_ms` — API round-trip latency; every request pays it.
- `power_scheme` — Quiet/Balanced/Power Saver profiles cap CPU clocks; Performance is fastest.
- `cpu_load_pct`, `processes` — background noise while testing.

## Reading thermal results

- `chunk_N_ms` — should be flat. Rising later chunks = thermal/power throttling.
- `slowdown_pct` — last3 vs first3 chunks: under 5% stable, 5-15% mild throttle, over 15% heavy throttle.
- `clock_min/max_mhz` — if clocks drop during load, power limits or thermals are the cause.
- `temp_c` — often "not exposed by this machine" on modern laptops; not a failure.

## Reference results (i9-14900HX, NVMe, ~18ms ping, power scheme "Quiet")

bench.ps1:
```
int_loop_500M_ms               1230
fp_loop_300M_ms                1038
sha256_256MB_ms                447
seq_write_512MB_MBps           1115.5
seq_read_512MB_MBps            2994.2
small_write_1000x4KB_ms        998
small_read_1000x4KB_ms         223
https_ttfb_ms_3runs            227,228,180
ping_1.1.1.1_avg_ms            18.2
```

thermal.ps1:
```
chunk_iters                    1100M
first3_avg_ms                  3017
last3_avg_ms                   2939
slowdown_pct                   -2.6
clock_min_mhz                  1466
clock_max_mhz                  2200
verdict                        stable - no thermal throttling
```
