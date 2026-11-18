# plant.py TREE PLANTS.json OUTDIR: copy TREE (no build/, no .git) to OUTDIR/NAME, apply each edit exactly once, write run.sh
import json, os, subprocess, sys
tree, spec, out = sys.argv[1], sys.argv[2], sys.argv[3]
plants = json.load(open(spec))
os.makedirs(out, exist_ok=True)
for p in plants:
    d = os.path.join(out, p["name"])
    if os.path.exists(d):
        sys.exit("exists: " + d)
    os.makedirs(d)
    subprocess.run("tar -C %s --exclude=./build --exclude=./.git -cf - . | tar -C %s -xf -" % (tree, d), shell=True, check=True)
    for f, old, new in p["edits"]:
        path = os.path.join(d, f)
        text = open(path).read()
        n = text.count(old)
        if n != 1:
            sys.exit("%s: %s matches %d times in %s" % (p["name"], old, n, f))
        open(path, "w").write(text.replace(old, new))
    lines = ["cd %s || exit 1" % os.path.relpath(d, tree), "make deps > lead-deps.txt 2>&1 || echo deps-failed"]
    for s in p["suites"]:
        lines.append("timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/%s.sps > lead-%s.txt 2>&1; echo rc=$? >> lead-%s.txt" % (s, s, s))
    open(os.path.join(d, "run.sh"), "w").write("\n".join(lines) + "\n")
    print("planted", p["name"])
