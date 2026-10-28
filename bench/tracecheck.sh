#!/bin/bash
# usage: tracecheck.sh <binary> <tag>
# Traces block-file writes, fsyncs and socket acks with strace during 1,000 durable async
# publishes, then counts acks sent before an fsync covered their message.
bin=$1; tag=$2; rm -rf /tmp/js-tr-$tag /tmp/trace-$tag.txt
printf 'listen: 127.0.0.1:4222\njetstream { store_dir: "/tmp/js-tr-%s"\n sync_interval: always }\n' $tag > /tmp/tr-$tag.conf
strace -f -tt -s 4096 -e trace=openat,write,pwrite64,writev,fsync,fdatasync -o /tmp/trace-$tag.txt $bin -c /tmp/tr-$tag.conf > /dev/null 2>&1 &
sp=$!; sleep 2
timeout 100 nats bench js pub async bench.x --create --purge --storage file --replicas 1 --clients 4 --msgs 1000 --size 128B --no-progress > /dev/null 2>&1
pkill -x $(basename $bin); wait $sp 2>/dev/null; sleep 1
python3 - /tmp/trace-$tag.txt $tag <<'PY'
import re, sys
blk, written, synced, fsyncs, acked, viol = set(), 0, 0, 0, set(), 0
for ln in open(sys.argv[1]):
    m = re.match(r"(\d+) +([\d:.]+) (\w+)\((\d+)?", ln)
    if not m: continue
    call, fd = m.group(3), m.group(4)
    if call == "openat" and ".blk" in ln:
        r = re.search(r"= (\d+)$", ln.strip());  blk.add(r.group(1)) if r else None
    elif fd in blk and call in ("write", "pwrite64", "writev"):
        written += max(ln.count("bench.x"), 1)
    elif fd in blk and call in ("fsync", "fdatasync"):
        fsyncs += 1; synced = written
    elif call in ("write", "writev"):
        for s in re.findall(r'seq\\\\?"?:(\d+)', ln):
            q = int(s); acked.add(q)
            if q > synced: viol += 1
print(f"{sys.argv[2]:8} records {written}, fsyncs {fsyncs} ({written/max(fsyncs,1):.1f} msgs/fsync), distinct acks {len(acked)}, acks before fsync {viol}")
PY
