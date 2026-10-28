"""Package sanity check: the patch has both functions and all 3 tests, every script is present with Unix line endings, and the README has its results markers."""
import pathlib
root = pathlib.Path(__file__).parent
patch = (root / "patch" / "0001-jetstream-group-commit-sync-always.patch").read_text()
assert "func (mset *stream) groupSyncBegin() *fileStore" in patch
assert "func (mset *stream) groupSyncEnd(fs *fileStore) *fileStore" in patch
for t in ("TestJetStreamGroupCommitSyncAlwaysAsyncBurst", "TestJetStreamGroupCommitAtomicBatchInterleaved", "TestJetStreamGroupCommitOnlyForSyncAlways"):
    assert t in patch, t
for f in ["reproduce.sh", "bench/bench.sh", "bench/tracecheck.sh", "crash/trial.sh", "crash/client.py", "crash/clearcache.py"]:
    p = root / f
    assert p.exists(), f
    assert b"\r\n" not in p.read_bytes(), f + " has Windows line endings"
readme = (root / "README.md").read_text(encoding="utf-8")
assert "<!-- results:start -->" in readme and "<!-- results:end -->" in readme
print("all tests passed")
