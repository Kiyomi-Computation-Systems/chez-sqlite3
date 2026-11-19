#!/usr/bin/env python3
"""Each plant's log, read: its suite's exit, its counts, and the rows that
failed, from the FAIL and XPASS lines, never by eye.

  python3 -I summarize.py WORKTREE NAME...
"""
import os, re, sys

WT = sys.argv[1]
for name in sys.argv[2:]:
    path = os.path.join(WT, 'build', 'e1', 'plants', name + '.log')
    run = os.path.join(WT, 'build', 'e1', 'plants', name, 'RUN.sh')
    guards = open(run).readline().strip().lstrip('# ') if os.path.exists(run) else '?'
    try:
        text = open(path).read()
    except OSError:
        print(f'{name}: NO LOG')
        continue
    fails = re.findall(r'^(?:FAIL|XPASS) (.*)$', text, re.M)
    passes = re.search(r'^# of expected passes +(\d+)', text, re.M)
    unexp = re.search(r'^# of unexpected failures +(\d+)', text, re.M)
    ex = re.search(r'^exit (\d+)$', text, re.M)
    print(f'{guards}')
    print(f'  exit {ex.group(1) if ex else "?"}, passed {passes.group(1) if passes else 0}, '
          f'failed {unexp.group(1) if unexp else 0}')
    for f in fails:
        print(f'    FAIL {f}')
