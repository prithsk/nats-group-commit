# Results

All runs on nats-server v2.15.1 (latest stable, Oct 9 2026), built from source, in a 1-vCPU Linux sandbox
with ext4 on a virtual disk where one fsync takes about 120 microseconds. Absolute numbers are small because
of the single CPU; compare columns, not rows across machines. Messages are 128 bytes, R1 file streams.

## Calibration

| Build | Durable async, 1 client | Durable sync, 16 clients |
|---|---|---|
| Official release binary | 4,897 msg/s | 4,069 msg/s |
| Stock built from source | 5,496 msg/s | 3,632 msg/s |

The source build matches the release within run-to-run noise, so gains below come from the patch.

## The gap: durability cost by publish style (stock)

| Publish style | Default | sync_interval: always | Penalty |
|---|---|---|---|
| Sync, 1 client | 21,728 | 3,625 | 6.0x |
| Sync, 64 clients | 24,375 | 4,346 | 5.6x |
| Async | 106,370 | 5,916 | 18x |
| Fast batch | 173,880 | 5,927 | 29x |
| Atomic batch | 54,558 | 59,628 | none |

Durable throughput does not rise with more publishers, which matches one fsync per message.
Atomic batches already coalesce their fsync; ordinary publishers do not.

## Throughput with the patch (sync_interval: always)

| Publishers | Stock | Patched | Speedup |
|---|---|---|---|
| 1 sync | 3,417 | 3,443 | 1.0x |
| 16 sync | 3,559 | 12,784 | 3.6x |
| 64 sync | 4,052 | 22,945 | 5.7x |
| 1 async | 5,916 | 83,550 | 14.1x |
| 4 async | 5,695 | 90,999 | 16.0x |

Final build, rerun (see final-runs.txt): durable 4 async 5,011 to 70,930 (14.2x), durable 64 sync 3,337 to 18,027 (5.4x),
default mode unchanged (1.01x and 1.07x).

## Ack ordering, from syscall traces (strace, 1,000 durable async messages)

| Server | fsyncs | Acks seen before their message was fsynced |
|---|---|---|
| Stock | 1,000 | 0 |
| Patched | 3 | 0 |

984 of 1,000 acks were readable in the trace; the rest fell in writes longer than the capture limit.

## Power-cut test (LazyFS clear-cache after kill -9, the method Jepsen used)

| Server and mode | Power cuts | Acked | Acked but lost |
|---|---|---|---|
| Stock, default | 3 | 46,856 | 46,856 (100%) |
| Stock, always | 5 | 60,184 | 0 |
| Patched, always | 5 | 71,840 | 0 |

## NATS test suite

58 of 58 selected tests pass on the patched server: all single-server tests matching SyncAlways, SyncInterval,
AtomicBatch, Durab or FlushAll (55 existing), plus the 3 new TestJetStreamGroupCommit tests.

## Second sandbox, slower disk

A fresh sandbox with a median fsync of 0.169 ms (vs 0.120 ms above), running reproduce.sh on rebuilt binaries:

| Workload | Stock | Patched | Speedup |
|---|---|---|---|
| sync_interval: always, 1 sync publisher | 2,427 msg/s | 2,456 msg/s | 1.0x |
| sync_interval: always, 64 sync publishers | 3,135 msg/s | 18,324 msg/s | 5.8x |
| sync_interval: always, 4 async publishers | 3,739 msg/s | 101,896 msg/s | 27.3x |

The speedup grows as fsync gets slower, as predicted. The default-mode check read 0.9x in that single run;
four alternating repeats gave medians of 98,196 (stock) and 104,593 (patched), 1.07x, with stock alone ranging
from 92,371 to 113,847. That was noise, and reproduce.sh now reports medians of 3 alternating runs.
