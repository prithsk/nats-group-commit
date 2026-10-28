#!/bin/bash
# usage: bench.sh <binary> <tag> <sync: default|always> <kind: sync|async> <clients> <msgs>
# Starts the server with a fresh store, runs nats bench, prints aggregate msgs/sec.
bin=$1; tag=$2; mode=$3; kind=$4; clients=$5; msgs=$6
dir=/tmp/js-$tag-$mode; rm -rf $dir
if [ "$mode" = always ]; then extra="sync_interval: always"; else extra=""; fi
printf 'listen: 127.0.0.1:4222\njetstream { store_dir: "%s"\n %s }\n' "$dir" "$extra" > /tmp/$tag-$mode.conf
$bin -c /tmp/$tag-$mode.conf > /tmp/server-$tag-$mode.log 2>&1 &
spid=$!; sleep 1
out=/tmp/res-$tag-$mode-$kind-$clients.txt
timeout 300 nats bench js pub $kind bench.x --create --purge --storage file --replicas 1 --clients $clients --msgs $msgs --size 128B --no-progress > $out 2>&1
kill $spid; wait $spid 2>/dev/null
python3 - "$out" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"aggregated stats: ([\d,]+) msgs/sec", t) or re.search(r"stats: ([\d,]+) msgs/sec", t)
print(m.group(1) if m else "ERR " + t[-200:].replace("\n", " "))
PY
