# opencode-machine-bench

Benchmark + fixer for comparing and speeding up opencode machines.

Same model, same opencode — when one machine feels faster, the reason is always local: single-core CPU speed, disk I/O, antivirus tax, network latency to the API, or power throttling.

## Contents

- `bench.ps1` — measures CPU single-core, disk, network, and throttling context. 30–60s, safe, changes nothing.
- `fixit.ps1` — applies the usual fixes: performance power plan + Defender exclusions for dev folders. Reversible. Needs admin (self-elevates, shows a UAC prompt).

## Full diagnose -> fix -> verify (copy-paste into opencode)

> Run this end-to-end on this machine and show all the raw outputs verbatim, in order. Do not summarize, do not truncate:
>
> ```powershell
> Invoke-WebRequest "https://raw.githubusercontent.com/conorgg123/opencode-machine-bench/main/bench.ps1" -OutFile "$env:TEMP\bench.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\bench.ps1"
>
> Invoke-WebRequest "https://raw.githubusercontent.com/conorgg123/opencode-machine-bench/main/fixit.ps1" -OutFile "$env:TEMP\fixit.ps1"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\fixit.ps1"
>
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\bench.ps1"
> ```
>
> A UAC prompt will appear during fixit — click Yes. Then paste all three output blocks back.

## What fixit changes (all reversible)

| Fix | Why | Undo |
|---|---|---|
| Power plan -> Ultimate/High performance + "Best performance" overlay | Quiet/Balanced profiles cap CPU clocks | `powercfg /setactive SCHEME_BALANCED` |
| Defender path exclusions: opencode dirs, TEMP, npm/bun dirs, current project folder | real-time scanning taxes every file tool call | `Remove-MpPreference -ExclusionPath "<path>"` |

Real-time protection stays ON. Only dev folders are excluded.

## Reading benchmark results

- `int_loop_500M_ms`, `fp_loop_300M_ms`, `sha256_256MB_ms` — lower is better. Single-core speed dominates day-to-day opencode responsiveness.
- `seq_write_512MB_MBps`, `seq_read_512MB_MBps` — higher is better.
- `small_write_1000x4KB_ms` — antivirus/Defender tax. Much slower than `small_read` means real-time scanning is slowing every file tool call.
- `https_ttfb_ms_3runs`, `ping_1.1.1.1_avg_ms` — API round-trip latency; every request pays it.
- `power_scheme` — Quiet/Balanced/Power Saver profiles cap CPU clocks; Performance is fastest.
- `cpu_load_pct`, `processes` — background noise while testing.

## Reference result (i9-14900HX laptop, NVMe, wired 18ms ping)

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
