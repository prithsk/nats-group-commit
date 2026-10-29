#!/bin/bash
# usage: trial.sh <binary> <name> <default|always> <trial#>
# Needs LazyFS mounted at /tmp/lazyfs.mnt with its fault FIFOs at /tmp/faults.fifo and /tmp/faults_completed.fifo.
# Publishes durably, kills the server, drops all unsynced data (power cut), restarts, counts acked messages lost.
here=$(cd "$(dirname "$0")" && pwd)
bin=$1; name=$2; mode=$3; n=$4
dir=/tmp/lazyfs.mnt/js-$name-$mode-$n; rm -rf $dir; mkdir -p $dir
extra=""; [ "$mode" = always ] && extra="sync_interval: always"
printf 'listen: 127.0.0.1:4222\njetstream { store_dir: "%s"\n max_file_store: 1GB\n %s }\n' "$dir" "$extra" > /tmp/pc-$name-$mode.conf
$bin -c /tmp/pc-$name-$mode.conf > /tmp/pc-srv.log 2>&1 & spid=$!; sleep 1.5
nats stream add PC --subjects 'pc.>' --storage file --replicas 1 --defaults > /dev/null 2>&1
acks=/tmp/acked-$name-$mode-$n.json; rm -f $acks
timeout 60 python3 "$here/client.py" $acks & cpid=$!
sleep $(python3 -c "import random; print(round(random.uniform(1.5, 3.0), 2))")
kill -9 $spid; wait $spid 2>/dev/null
timeout 20 python3 "$here/clearcache.py" > /dev/null
wait $cpid 2>/dev/null
$bin -c /tmp/pc-$name-$mode.conf > /tmp/pc-srv2.log 2>&1 & spid=$!; sleep 2
info=$(timeout 10 nats stream info PC --json 2>/dev/null)
kill $spid; wait $spid 2>/dev/null
python3 - "$acks" "$info" "$name" "$mode" "$n" <<'PY'
import json, sys
acks = json.load(open(sys.argv[1])) if sys.argv[1] else []
try:
    st = json.loads(sys.argv[2])["state"]; first, last = st["first_seq"], st["last_seq"]
except Exception:
    first, last = 1, 0
lost = [s for s in acks if not (first <= s <= last)]
print(f"{sys.argv[3]:8} {sys.argv[4]:7} trial {sys.argv[5]}: acked {len(acks):6}, survived up to seq {last:6}, ACKED BUT LOST {len(lost)}")
PY
