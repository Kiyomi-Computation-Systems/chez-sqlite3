#!/usr/bin/env python3
"""Summarize build/mut/NAME.log: per run, the exit, the counts and the FAIL lines."""
import os, re, sys
wt = sys.argv[1]
names = sys.argv[2:]
guards = dict(l.rstrip('\n').split('\t', 1) for l in open(os.path.join(wt, 'build/mut/GUARDS.txt')))
for n in names:
    text = open(os.path.join(wt, 'build/mut', n + '.log'), encoding='utf-8', errors='replace').read()
    print('== %s: %s' % (n, guards.get(n, '?')))
    for block in text.split('@@@ run ')[1:]:
        head, _, body = block.partition('\n')
        m = re.search(r'@@@ exit (\d+)', body)
        ex = m.group(1) if m else '?'
        p = re.search(r'# of expected passes\s+(\d+)', body)
        f = re.search(r'# of unexpected failures\s+(\d+)', body)
        xf = re.search(r'# of expected failures\s+(\d+)', body)
        xp = re.search(r'# of unexpected successes\s+(\d+)', body)
        fails = re.findall(r'^(?:FAIL|XPASS) (.*)$', body, re.M)
        counts = 'pass %s fail %s xfail %s xpass %s' % (p.group(1) if p else 0, f.group(1) if f else 0,
                                                      xf.group(1) if xf else 0, xp.group(1) if xp else 0)
        print('  %s: exit %s; %s' % (head, ex, counts))
        for fl in fails:
            print('     - ' + fl[:150])
        if not p and not f:
            # a script's run: its last lines
            tail = [l for l in body.split('\n') if l and not l.startswith('@@@')][-6:]
            for l in tail:
                print('     | ' + l[:160])
