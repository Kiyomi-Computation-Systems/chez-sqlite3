#!/usr/bin/env python3
"""M4 slice 4's mutation driver. Run it from the worktree's root, as
python3 -I -B, so no bytecode is left beside it: the tree is the working
directory, and every path it writes is relative to it.

  mut.py [--into DIR] prepare NAME...   copy the tree into DIR/NAME, then
                                        apply NAME's edits from mutants.py,
                                        each checked to match its file's text
                                        exactly once before it is written
  mut.py [--into DIR] scripts NAME...   write DIR/NAME/run.sh, to run inside
                                        scripts/guix-env from the root:
                                        ls DIR/*/run.sh | xargs -P 6 -n 1 sh
  mut.py [--into DIR] report NAME...    each copy's failing rows, by suite,
                                        from its suites' logs, or SURVIVED

DIR is build/mut unless given, which git ignores. NAME may be all, every
plant in mutants.py. A plant's suites are its own list, or DEFAULT_SUITES;
its env, words put before each suite's command, such as CC=false; its gate,
when true, runs its suites under make test-memory as well.
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutants import MUTANTS, DEFAULT_SUITES  # noqa: E402

TREE = os.getcwd()
INTO = "build/mut"


def find(name):
    for m in MUTANTS:
        if m["name"] == name:
            return m
    raise SystemExit("no plant " + name)


def names(args):
    return [m["name"] for m in MUTANTS] if args == ["all"] else args


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


def prepare(name):
    m = find(name)
    dest = copy_tree(name)
    for path, old, new in m["edits"]:
        p = os.path.join(dest, path)
        text = open(p).read()
        n = text.count(old)
        if n != 1:
            raise SystemExit("%s: %s: an edit matches %d times, not once:\n%s" % (name, path, n, old))
        open(p, "w").write(text.replace(old, new))
    print("prepared", name, len(m["edits"]), "edits")


def scripts(ns):
    for name in ns:
        m = find(name)
        env = m.get("env", "")
        lines = ["cd %s/%s || exit 1" % (INTO, name),
                 "make deps > logs-deps.txt 2>&1 || echo 'deps failed'"]
        for s in m.get("suites", DEFAULT_SUITES):
            lines.append("%s timeout 600 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/%s.sps "
                         "> log-%s.txt 2>&1; echo \"rc=$?\" >> log-%s.txt" % (env, s, s, s))
        if m.get("gate"):
            gated = " ".join("tests/%s.sps" % s for s in m.get("suites", DEFAULT_SUITES))
            lines.append("make test-memory MEMORY_SUITES=\"%s\" > log-gate.txt 2>&1; echo \"rc=$?\" >> log-gate.txt"
                         % gated)
        lines.append("echo done %s" % name)
        open(os.path.join(TREE, INTO, name, "run.sh"), "w").write("\n".join(lines) + "\n")
    print("wrote", len(ns), "run.sh")


def count(text, label):
    m = re.search(r"^# of %s\s+(\d+)" % label, text, re.M)
    return int(m.group(1)) if m else 0


def report(ns):
    for name in ns:
        m = find(name)
        parts = []
        for s in m.get("suites", DEFAULT_SUITES):
            p = os.path.join(TREE, INTO, name, "log-%s.txt" % s)
            if not os.path.exists(p):
                parts.append("%s: no log" % s)
                continue
            text = open(p).read()
            passes, fails = count(text, "expected passes"), count(text, "unexpected failures")
            exit_failed = "suite-exit-status: exit 1" in text
            if fails == 0 and passes > 0 and not exit_failed:
                continue
            short = s.replace("test-", "")
            if passes + fails == 0:
                died = re.search(r"^Exception.*$", text, re.M)
                parts.append("%s DIED: %s" % (short, died.group(0)[:120] if died else "no output"))
                continue
            rows = [line[5:65] for line in text.splitlines() if line.startswith("FAIL ")]
            checks = [line[19:110] for line in text.splitlines()
                      if line.startswith("suite-exit-status: exit 1") and "check failed" in line]
            parts.append("%s %d of %d%s%s" % (short, fails, passes + fails,
                                             (": " + " | ".join(rows)) if rows else "",
                                             (" [" + " | ".join(checks) + "]") if checks else ""))
        if m.get("gate"):
            p = os.path.join(TREE, INTO, name, "log-gate.txt")
            text = open(p).read() if os.path.exists(p) else "no log"
            summary = re.search(r"^test-memory: ran .*$", text, re.M)
            parts.append("gate: " + (summary.group(0) if summary else "no summary"))
        print("%-26s %s" % (name, "; ".join(parts) if parts else "SURVIVED"))


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
