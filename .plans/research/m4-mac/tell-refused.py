# tell-refused.py TREE OUT: on the host (the container has no python3), Apple's refusal of
# sqlite3_auto_extension stood in on Linux. TREE's tests/ is copied to OUT/tests, and each of
# the four bindings the suites reach sqlite3_auto_extension through answers 21, SQLITE_MISUSE,
# registering nothing, as Apple's 3.51.0 does. The direct reading each gate is held by goes
# through the same binding, so the gate sees the refusal on both sides. OUT/suites.txt names
# the fourteen suites that reach a binding. Run each from TREE's root, inside scripts/guix-env:
#   $CHEZ --libdirs OUT/tests:src:build/scheme-libs --program OUT/tests/SUITE.sps
# Every suite must pass, each row that reads the tell printed UNAVAILABLE with "refused
# sqlite3_auto_extension". Run in M4's closing review's Mac step, on Guix's 3.53.1:
# out/closing-review/tell-refused-linux.txt.
import os
import shutil
import sys

tree, out = sys.argv[1], sys.argv[2]
shutil.copytree(os.path.join(tree, "tests"), os.path.join(out, "tests"), symlinks=True)

bindings = [("test-open-db-config.sps", ""), ("test-open-interleave.sps", ""),
            ("test-load-extension.sps", ""), ("conveniences-pending.sls", "  ")]
for name, indent in bindings:
    path = os.path.join(out, "tests", name)
    with open(path) as f:
        s = f.read()
    old = (indent + "(define auto-extension\n" + indent
           + "  (bound 'sqlite3_auto_extension (foreign-procedure \"sqlite3_auto_extension\" (uptr) int)))")
    if s.count(old) != 1:
        sys.exit("tell-refused.py: " + name + "'s binding is not there exactly once")
    with open(path, "w") as f:
        f.write(s.replace(old, indent + "(define auto-extension (lambda (entry) 21))"))

suites = sorted(n[:-4] for n in os.listdir(os.path.join(tree, "tests"))
                if n.startswith("test-conveniences-pending-") and n.endswith(".sps"))
suites += ["test-open-db-config", "test-open-interleave", "test-load-extension"]
with open(os.path.join(out, "suites.txt"), "w") as f:
    f.write("\n".join(suites) + "\n")
