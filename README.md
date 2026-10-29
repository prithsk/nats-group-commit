# nats-group-commit

Durable JetStream acks at close to lazy-fsync speed, with no client changes.

NATS JetStream acknowledges writes before they reach disk by default. Jepsen showed in December 2025 that a power
failure loses those acked writes, and the fix is `sync_interval: always`. On a single-server stream, that mode
pays one fsync per message, so durable throughput stays flat no matter how many publishers send. NATS already
solved this for atomic batches, which share one fsync per batch. This patch gives every publisher the same
treatment: messages that are already queued share one fsync, and each ack still waits for its message to be on disk.

## Results

<!-- results:start -->
| sync_interval: always | Sandbox, fsync 0.120 ms | Sandbox, fsync 0.169 ms | GitHub Codespaces, fsync 0.283 ms |
|---|---|---|---|
| 1 sync publisher | 1.0x | 1.0x | 1.0x |
| 64 sync publishers | 5.7x | 5.8x | 6.6x |
| 4 async publishers | 16.0x | 27.3x | 22.5x |

On the cloud disk, durable async publishing went from 2,532 to 56,939 msg/s, the median of 3 alternating rounds, which
ranged from 9.5x to 41x. Default mode is unchanged on every machine. In five simulated power cuts with LazyFS, the
patched server lost zero acked messages. On WSL2, where fsync is free, the patch changes nothing, as expected.
Full numbers are in [results/results.md](results/results.md).
<!-- results:end -->

## What the code does today

In nats-server v2.15.1, every stored message on a single-server stream calls `writeMsgRecord` with
`flush = fs.fip` (`server/filestore.go`, line 8078), and in SyncAlways mode each flush calls `mb.mfd.Sync()`
(line 8910). The batched mode, SyncOnFlush, is enabled only when replicas are greater than 1. Atomic batches
coalesce their sync by switching the store to SyncOnFlush, storing the batch, calling `FlushAllPending()` once,
and switching back (`server/stream.go`, around line 7954).

## The patch

`internalLoop` already pops every queued inbound message at once. When two or more are waiting on a
SyncAlways file store, the patch applies the atomic-batch sequence to that run: switch to SyncOnFlush, store
the run, `FlushAllPending()` once, then restore SyncAlways.

Why acks still wait for the disk: publish acks go into `mset.outq`, and the only code that pops `outq` is
`internalLoop` itself (`server/stream.go`, line 8618). No ack for the run can reach a client before the loop
finishes the run, and the loop finishes the run only after the shared fsync returns.

Other rules:

- A single queued message takes the original path, so one publisher sees no change.
- The run ends before any atomic or fast-batch message, so their logic runs untouched.
- `isolateMu` is held across the run, as atomic batches do, so direct reads cannot see it before it is durable.
- If the shared fsync fails, the queued acks are dropped, so the server never acks a write that may be lost.
- Streams without `sync_interval: always` exit on a lock-free check and never take a lock here.

The patch is 58 lines in `server/stream.go` plus 3 tests in `server/jetstream_group_commit_test.go`.

## Verification

1. **Calibration.** The source build matches the official release binary within noise.
2. **Throughput.** `bench/bench.sh` runs `nats bench js pub` against any binary and mode.
3. **Ack ordering.** `bench/tracecheck.sh` traces writes, fsyncs and socket acks with strace and counts acks
   sent before their message was fsynced. Stock: 1,000 fsyncs for 1,000 messages. Patched: 3. Both: zero early acks.
4. **Power cuts.** `crash/trial.sh` runs NATS on a LazyFS mount, records every acked sequence on the client,
   kills the server, drops all unsynced data with `lazyfs::clear-cache`, restarts, and counts acked messages that
   did not survive.
5. **NATS tests.** 58 of 58 selected single-server tests pass, including the full atomic batch suite.

## Honest limits

- Measured in a 1-vCPU sandbox with a fast virtual disk (fsync about 120 microseconds). On cloud disks where
  fsync takes 1 to 3 ms, stock durable throughput falls to a few hundred msg/s, so the gap should be larger, but
  that is a prediction until measured on that hardware. `reproduce.sh` measures it on any Linux or WSL2 machine.
- New messages can be delivered to consumers just before their run's fsync completes. NATS atomic batches behave
  the same way; direct reads are blocked until commit. A crash in that window can show a consumer a message that
  later disappears, and its publisher never received an ack.
- Only single-server (R1) streams change. Replicated streams already use SyncOnFlush through Raft.
- Five power cuts per configuration is evidence, not proof. The harness, the traces and the tests are included so
  anyone can run more.

## Reproduce

One command on Linux or WSL2 builds stock and patched servers from v2.15.1, measures the disk's fsync and prints
the comparison:

```
./reproduce.sh
```

Individual pieces:

```
bench/bench.sh <binary> <tag> <default|always> <sync|async> <clients> <msgs>
bench/tracecheck.sh <binary> <tag>                 # needs strace
crash/trial.sh <binary> <name> <default|always> <n> # needs LazyFS mounted at /tmp/lazyfs.mnt
```

## Prior art

Jepsen, NATS 2.12.1 (Kyle Kingsbury, Dec 2025); nats-server issue #7564; NATS atomic batch publishing and its
coalesced sync; group commit in Postgres (`commit_delay`) and Redis (one fsync per event loop); LazyFS.

## License

Apache-2.0, matching nats-server.
