On 16 CPUs, with a median fsync of 0.000 ms on this disk. nats-server v2.15.1, 128-byte messages, R1 file stream. Medians of 3 alternating runs.

| Workload | Stock | Patched | Speedup |
|---|---|---|---|
| sync_interval: always, 1 sync publisher | 1,774 msg/s | 1,652 msg/s | 0.9x |
| sync_interval: always, 64 sync publishers | 17,470 msg/s | 16,456 msg/s | 0.9x |
| sync_interval: always, 4 async publishers | 106,953 msg/s | 110,631 msg/s | 1.0x |
| default mode, 4 async publishers (regression check) | 114,318 msg/s | 111,122 msg/s | 1.0x |

Sandbox numbers, the syscall-trace check and the LazyFS power-cut results are in [results/results.md](results/results.md).
