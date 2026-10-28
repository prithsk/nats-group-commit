"""Publish durably from 8 concurrent publishers and record every sequence the server acked."""
import asyncio, json, sys
import nats

async def main(out_path, workers=8):
    nc = await nats.connect("nats://127.0.0.1:4222", allow_reconnect=False, connect_timeout=3)
    js = nc.jetstream()
    acked, stop = [], asyncio.Event()
    async def worker(w):
        i = 0
        while not stop.is_set():
            try:
                ack = await js.publish("pc.x", f"{w}-{i}".encode(), timeout=2)
                acked.append(ack.seq); i += 1
            except Exception:
                stop.set(); return
    await asyncio.gather(*(worker(w) for w in range(workers)))
    json.dump(sorted(acked), open(out_path, "w"))
    try: await nc.close()
    except Exception: pass

asyncio.run(main(sys.argv[1]))
