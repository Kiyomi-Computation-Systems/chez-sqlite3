#!/usr/bin/env python3
# plant.py TREE SPEC: apply SPEC's edits to TREE, each old text matching its
# file exactly once, or fail naming it. SPEC is a Python file defining
# EDITS = [(path, old, new), ...].
import sys, runpy
tree, spec = sys.argv[1], sys.argv[2]
edits = runpy.run_path(spec)["EDITS"]
for path, old, new in edits:
    full = f"{tree}/{path}"
    with open(full) as f:
        text = f.read()
    n = text.count(old)
    if n != 1:
        sys.exit(f"plant: {spec}: {path}: the old text matches {n} times, not once")
    with open(full, "w") as f:
        f.write(text.replace(old, new))
print(f"planted {spec} in {tree}: {len(edits)} edit(s)")
