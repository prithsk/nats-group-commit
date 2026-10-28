#!/usr/bin/env bash
# One command: build stock and patched nats-server v2.15.1, measure this disk's fsync, and benchmark both.
# Linux or WSL2. Set SKIP_BUILD=1 with NATS_STOCK and NATS_GROUP pointing at existing binaries to skip building.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd); WORK=${WORK:-$HOME/ngc-work}; mkdir -p "$WORK"
GO_VER=1.26.10; NATS_VER=v2.15.1; CLI_VER=v0.5.0
if ! command -v go >/dev/null 2>&1 && [ -z "${SKIP_BUILD:-}" ]; then
  echo "installing Go $GO_VER"; curl -sSL "https://go.dev/dl/go$GO_VER.linux-amd64.tar.gz" | tar -xz -C "$WORK"
  export PATH="$WORK/go/bin:$PATH"
fi
if ! command -v nats >/dev/null 2>&1; then
  echo "installing nats CLI $CLI_VER"
  curl -sSL -o "$WORK/cli.zip" "https://github.com/nats-io/natscli/releases/download/$CLI_VER/nats-${CLI_VER#v}-linux-amd64.zip"
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$WORK/cli.zip" "$WORK"
  chmod +x "$WORK"/nats-*/nats; export PATH="$(dirname "$(ls "$WORK"/nats-*/nats | head -1)"):$PATH"
fi
if [ -z "${SKIP_BUILD:-}" ]; then
  [ -d "$WORK/nats-server" ] || git clone -q https://github.com/nats-io/nats-server "$WORK/nats-server"
  cd "$WORK/nats-server"; git fetch -q --tags; git checkout -q -f "$NATS_VER"; git clean -fdq server
  echo "building stock $NATS_VER"; go build -o "$WORK/nats-stock" .
  git apply "$ROOT/patch/0001-jetstream-group-commit-sync-always.patch"
  echo "building patched"; go build -o "$WORK/nats-group" .
  git checkout -q -f "$NATS_VER"; git clean -fdq server
  NATS_STOCK="$WORK/nats-stock"; NATS_GROUP="$WORK/nats-group"
fi
FSYNC=$(python3 - <<'PY'
import os, time, statistics
fd = os.open("/tmp/ngc_fsync_probe", os.O_CREAT | os.O_WRONLY | os.O_TRUNC); lat = []
for _ in range(200):
    os.write(fd, b"x" * 256); t = time.perf_counter(); os.fsync(fd); lat.append((time.perf_counter() - t) * 1000)
os.close(fd); os.remove("/tmp/ngc_fsync_probe"); print(f"{statistics.median(lat):.3f}")
PY
)
echo "fsync median on this disk: $FSYNC ms"
cd "$ROOT/bench"; OUT="$ROOT/results/machine-$(hostname)-$(date +%Y-%m-%d).md"
# Each row alternates stock and patched 3 times and reports medians, since single runs vary 10-20% on small machines.
row() { a=""; b=""
  for i in 1 2 3; do a="$a $(./bench.sh "$NATS_STOCK" stock "$1" "$2" "$3" 20000)"; b="$b $(./bench.sh "$NATS_GROUP" group "$1" "$2" "$3" 20000)"; done
  python3 -c "
import sys, statistics
med = lambda v: statistics.median(float(x.replace(',', '')) for x in v.split())
a, b = med(sys.argv[1]), med(sys.argv[2])
print(f'| {sys.argv[3]} | {a:,.0f} msg/s | {b:,.0f} msg/s | {b/a:.1f}x |')" "$a" "$b" "$4"; }
{
  echo "On $(nproc) CPUs, with a median fsync of $FSYNC ms on this disk. nats-server $NATS_VER, 128-byte messages, R1 file stream. Medians of 3 alternating runs."
  echo
  echo "| Workload | Stock | Patched | Speedup |"
  echo "|---|---|---|---|"
  row always sync 1 "sync_interval: always, 1 sync publisher"
  row always sync 64 "sync_interval: always, 64 sync publishers"
  row always async 4 "sync_interval: always, 4 async publishers"
  row default async 4 "default mode, 4 async publishers (regression check)"
  echo
  echo "Sandbox numbers, the syscall-trace check and the LazyFS power-cut results are in [results/results.md](results/results.md)."
} | tee "$OUT"
echo; echo "saved $OUT"
