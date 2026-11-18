#!/usr/bin/env python3
"""M4 slice 3's mutation driver. Run it from the worktree's root: the tree is
the working directory, and every path it writes is relative to it.

  mut.py [--into DIR] prepare NAME...   copy the tree into DIR/NAME, and apply
                                        NAME's edits from mutants.py, each
                                        checked to match its file's text
                                        exactly once before it is written
  mut.py [--into DIR] scripts NAME...   write DIR/NAME/run.sh for each, to run
                                        inside scripts/guix-env from the root:
                                        ls DIR/*/run.sh | xargs -P 6 -n 1 sh
  mut.py [--into DIR] report NAME...    each copy's counts, from its suites'
                                        logs, and its failing rows by label

Run it as python3 -I -B, so that no bytecode is left beside it. DIR is
build/mut unless given, relative to the tree, which make clean removes and
git ignores. NAME may be all, every mutant in mutants.py. prepare needs tar.
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutants import MUTANTS, DEFAULT_SUITES  # noqa: E402
from labels import label_of  # noqa: E402

TREE = os.getcwd()
INTO = "build/mut"


def find(name):
    for m in MUTANTS:
        if m["name"] == name:
            return m
    raise SystemExit("no mutant " + name)


def names(args):
    if args == ["all"]:
        return [m["name"] for m in MUTANTS]
    return args


def copy_tree(name):
    dest = os.path.join(TREE, INTO, name)
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    tar = subprocess.Popen(["tar", "-C", TREE, "--exclude=./build", "--exclude=./.git", "-cf", "-", "."],
                           stdout=subprocess.PIPE)
    subprocess.check_call(["tar", "-C", dest, "-xf", "-"], stdin=tar.stdout)
    if tar.wait() != 0:
        raise SystemExit("tar failed")
    return dest


def apply_edits(name, dest, edits):
    for path, old, new in edits:
        p = os.path.join(dest, path)
        text = open(p).read()
        n = text.count(old)
        if n != 1:
            raise SystemExit("%s: %s: the edit's text matches %d times, not once:\n%s" % (name, path, n, old))
        open(p, "w").write(text.replace(old, new))


def prepare(name):
    m = find(name)
    dest = copy_tree(name)
    apply_edits(name, dest, m["edits"])
    print("prepared", name, len(m["edits"]), "edits")


def scripts(ns):
    for name in ns:
        m = find(name)
        suites = m.get("suites", DEFAULT_SUITES)
        lines = ["cd %s/%s || exit 1" % (INTO, name), "make deps > logs-deps.txt 2>&1 || echo 'deps failed'"]
        for s in suites:
            lines.append(
                "timeout 600 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/%s.sps "
                "> log-%s.txt 2>&1; echo \"rc=$?\" >> log-%s.txt" % (s, s, s))
        lines.append("echo done %s" % name)
        open(os.path.join(TREE, INTO, name, "run.sh"), "w").write("\n".join(lines) + "\n")
    print("wrote", len(ns), "run.sh")


def count(text, label):
    m = re.search(r"^# of %s\s+(\d+)" % label, text, re.M)
    return int(m.group(1)) if m else 0


def report(ns):
    for name in ns:
        m = find(name)
        suites = m.get("suites", DEFAULT_SUITES)
        parts = []
        for s in suites:
            p = os.path.join(TREE, INTO, name, "log-%s.txt" % s)
            if not os.path.exists(p):
                parts.append("%s: no log" % s)
                continue
            text = open(p).read()
            rc = re.findall(r"^rc=(\d+)", text, re.M)
            passes, fails = count(text, "expected passes"), count(text, "unexpected failures")
            if fails == 0 and passes > 0:
                continue
            died = re.search(r"^Exception.*$", text, re.M)
            rows = [label_of(s, line[5:]) for line in text.splitlines() if line.startswith("FAIL ")]
            desc = "%s %d of %d: %s" % (s.replace("test-", ""), fails, passes + fails, ", ".join(rows))
            if passes + fails == 0:
                desc = "%s DIED rc=%s: %s" % (s.replace("test-", ""), rc[-1] if rc else "?",
                                              died.group(0)[:160] if died else "no output")
            parts.append(desc)
        print("%-22s %s" % (name, "; ".join(parts) if parts else "SURVIVED"))


def main():
    global INTO
    args = sys.argv[1:]
    if args[:1] == ["--into"]:
        INTO, args = args[1], args[2:]
    cmd, rest = args[0], args[1:]
    if cmd == "prepare":
        for n in names(rest):
            prepare(n)
    elif cmd == "scripts":
        scripts(names(rest))
    elif cmd == "report":
        report(names(rest))
    else:
        raise SystemExit("unknown command " + cmd)


main()
