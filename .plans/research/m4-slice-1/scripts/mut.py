#!/usr/bin/env python3
"""M4 slice 1's mutation driver. Run it from the worktree's root, on the host:
the tree is the working directory, and every path it writes is relative to it.

  mut.py [--into DIR] prepare NAME...   copy the tree into DIR/NAME, and apply
                                        NAME's edits from mutants.py, each
                                        checked to match its file's text
                                        exactly once before it is written
  mut.py [--into DIR] red BASE          the red runs' copies, by hand from git:
                                        DIR/REDA, the tree with BASE's
                                        settings.sls and conditions.sls; DIR/REDB,
                                        the same with RED's stubs
  mut.py [--into DIR] before BASE       DIR/BEFORE, the tree with every file
                                        changed since BASE as BASE has it, and
                                        the slice's log left out: the gate's
                                        times before the slice
  mut.py [--into DIR] scripts NAME...   write DIR/NAME/run.sh for each, to run
                                        inside scripts/guix-env from the root:
                                        ls DIR/*/run.sh | xargs -P 6 -n 1 sh
  mut.py [--into DIR] report NAME...    each copy's counts, from its suites' logs

Run it as python3 -I -B, so that no bytecode is left beside it. DIR is
build/mut unless given, relative to the tree. NAME may be all, every
mutant but RED, REDA and REDB. prepare and red need tar; red and before need
git, so they run on the host, never in the container.
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutants import MUTANTS, DEFAULT_SUITES, SET, CON  # noqa: E402

TREE = os.getcwd()
INTO = "build/mut"
LOG = ".plans/m4-slice-1-mutation-log.md"


def find(name):
    for m in MUTANTS:
        if m["name"] == name:
            return m
    raise SystemExit("no mutant " + name)


def names(args):
    if args == ["all"]:
        return [m["name"] for m in MUTANTS if m["name"] not in ("RED", "REDA", "REDB")]
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


def at_base(base, path):
    return subprocess.check_output(["git", "-C", TREE, "show", "%s:%s" % (base, path)])


def prepare(name):
    m = find(name)
    if name in ("RED", "REDA", "REDB"):
        raise SystemExit(name + " is made by red, from git")
    dest = copy_tree(name)
    apply_edits(name, dest, m["edits"])
    print("prepared", name, len(m["edits"]), "edits")


def red(base):
    for name in ("REDA", "REDB"):
        dest = copy_tree(name)
        for path in (SET, CON):
            open(os.path.join(dest, path), "wb").write(at_base(base, path))
        if name == "REDB":
            apply_edits("RED", dest, find("RED")["edits"])
        print("prepared", name, "from", base)


def before(base):
    dest = copy_tree("BEFORE")
    changed = subprocess.check_output(["git", "-C", TREE, "diff", "--name-only", base]).decode().split()
    for path in changed:
        open(os.path.join(dest, path), "wb").write(at_base(base, path))
    log = os.path.join(dest, LOG)
    if os.path.exists(log):
        os.remove(log)
    print("prepared BEFORE from", base, ":", " ".join(changed))


def scripts(ns):
    for name in ns:
        m = find(name)
        suites = m.get("suites", DEFAULT_SUITES)
        lines = ["cd %s/%s || exit 1" % (INTO, name), "make deps > logs-deps.txt 2>&1 || echo 'deps failed'"]
        for s in suites:
            lines.append(
                "timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/%s.sps "
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
            died = re.search(r"^Exception.*$", text, re.M)
            desc = "%s %d/%d rc=%s" % (s.replace("test-", ""), fails, passes + fails, rc[-1] if rc else "?")
            if died and passes + fails == 0:
                desc += " DIED: " + died.group(0)[:150]
            parts.append(desc)
        print("%-6s %s" % (name, "; ".join(parts)))


def main():
    global INTO
    args = sys.argv[1:]
    if args[:1] == ["--into"]:
        INTO, args = args[1], args[2:]
    cmd, rest = args[0], args[1:]
    if cmd == "prepare":
        for n in names(rest):
            prepare(n)
    elif cmd == "red":
        red(rest[0])
    elif cmd == "before":
        before(rest[0])
    elif cmd == "scripts":
        scripts(names(rest))
    elif cmd == "report":
        report(names(rest))
    else:
        raise SystemExit("unknown command " + cmd)


main()
