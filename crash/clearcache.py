"""Simulate power loss on a LazyFS mount: drop every write not yet fsynced. Waits for LazyFS to confirm."""
import threading

def clear_cache(timeout=15):
    done = []
    def wait_done():
        with open("/tmp/faults_completed.fifo") as f:
            done.append(f.readline().strip())
    t = threading.Thread(target=wait_done, daemon=True); t.start()
    with open("/tmp/faults.fifo", "w") as f:
        f.write("lazyfs::clear-cache\n")
    t.join(timeout)
    return done[0] if done else None

if __name__ == "__main__":
    print(clear_cache())
