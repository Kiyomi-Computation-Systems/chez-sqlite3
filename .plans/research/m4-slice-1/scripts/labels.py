#!/usr/bin/env python3
"""labels.py [--into DIR] NAME...: the rows each mutant's copy failed, by the
mutation log's labels, read from DIR/NAME/log-*.txt. Run it from the
worktree's root; DIR is build/mut unless given."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutants import MUTANTS, DEFAULT_SUITES  # noqa: E402

INTO = "build/mut"

L = [
    ("(chez-sqlite3 private settings) exports", "s-exports"),
    ("db-config-settings, written out", "s-table"),
    ("db-config-setting-names, written out", "s-names"),
    ("the ops of 3.45.1", "s-ops"),
    ("the four stay out of the live list", "s-out"),
    ("each step, written out", "s-steps"),
    ("each of the four against every value of the universe", "s-domain"),
    ("the names, against the whole complement", "s-complement"),
    ("a name that is none of the four", "s-every"),
    ("every other op of the headers", "s-plan-ops"),
    ("db-config-sentinel, what the cell", "s-sentinel"),
    ("the verdict, written out", "s-verdict"),
    ("a cell the call left at its sentinel", "s-left"),
    ("a value asked outside the domain", "s-outside"),
    ("the verdict, for each of the four", "s-matrix"),
    ("the step and the verdict raise nothing", "s-total"),
    ("setting-names, written out", "s-setting-names (M3)"),
    ("a read-back that answered no row", "s-no-row (M3)"),
    ("(chez-sqlite3 private conditions) exports", "c-exports"),
    ("the matrix, whole", "c-matrix"),
    ("the eight predicates are false", "c-false8"),
    ("sqlite-extensions-unavailable? is false", "c-false"),
    ("the exported types sit where", "c-parent"),
    ("the types' own fields", "c-fields"),
    ("an sqlite-extensions-unavailable is a", "c-kind"),
    ("raise-extensions-unavailable raises the whole", "c-raise"),
    ("raise-extensions-unavailable names the who", "c-who"),
    ("raise-extensions-unavailable's condition is exactly", "c-simple"),
    ("raise-extensions-unavailable's message is fixed", "c-message"),
    ("each fixed &message is a string", "c-messages"),
    ("raise-extensions-unavailable refuses a who", "c-refuse"),
    ("raise-extensions-unavailable never returns", "c-return"),
    ("every accessor of another type refuses", "c-accessors"),
    ("raise-invalid-text raises the whole", "c-col"),
    ("raise-setting-mismatch raises the whole", "c-col"),
    ("an sqlite-transaction-ended is", "c-col"),
    ("raise-transaction-ended raises the whole", "c-col"),
    ("each of db_config's four, #t and #f, is refused by open-database", "o-memory"),
    ("each of db_config's four, #t and #f, is refused the same on a file", "o-file"),
    ("every refusal of the settings list", "o-refusals (M3)"),
    ("a bad option and a bad setting together", "o-order (M3)"),
    ("(chez-sqlite3) exports exactly", "public-list"),
    ("(chez-sqlite3) exports 68 names", "public-count"),
    ("every export has an entry", "reference-entries"),
    ("the entries are the exports", "reference-exports"),
]


def label(name):
    for k, v in L:
        if name.startswith(k):
            return v
    return "?? " + name[:60]


def main():
    global INTO
    args = sys.argv[1:]
    if args[:1] == ["--into"]:
        INTO, args = args[1], args[2:]
    for n in args:
        m = [x for x in MUTANTS if x["name"] == n][0]
        out = []
        for s in m.get("suites", DEFAULT_SUITES):
            t = open(os.path.join(INTO, n, "log-%s.txt" % s)).read()
            fails = re.findall(r"^FAIL (.*)$", t, re.M)
            p = re.search(r"^# of expected passes\s+(\d+)", t, re.M)
            passes = int(p.group(1)) if p else 0
            died = re.search(r"^Exception.*$", t, re.M)
            if fails:
                labs = []
                for f in fails:
                    lab = label(f)
                    if lab not in labs:
                        labs.append(lab)
                out.append("%s %d of %d: %s" % (s.replace("test-", ""), len(fails), len(fails) + passes,
                                                ", ".join(labs)))
            elif died and passes == 0:
                out.append("%s DIED: %s" % (s.replace("test-", ""), died.group(0)[:120]))
        print("%-6s %s" % (n, "; ".join(out) if out else "SURVIVED"))


main()
