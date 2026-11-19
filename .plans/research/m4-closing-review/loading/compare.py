# compare.py OUT: each plant's verdict on both layouts, from its copies'
# .summary and the suites' ROW lines (dump-copy.sh's hook).
#
# A layout catches a plant when a suite exits other than 0, or a make
# target fails. Prints one line a plant: its name, each layout's verdict
# and failing-row count, the suites that failed, and the failing rows that
# differ by name between the layouts. Then the rule: every plant the old
# layout catches, the new catches. Exits 1 if one breaks it.
import os, re, sys

out = sys.argv[1]
ROW = re.compile(r'^ROW \((\w+) "((?:[^"\\]|\\.)*)"')

def read(layout, name):
    d = os.path.join(out, layout, name)
    if not os.path.isdir(d):
        return None
    summary = os.path.join(d, '.summary')
    if not os.path.exists(summary):
        return {'ran': False}
    want = len(open(os.path.join(d, '.plant')).read().split())
    lines = [l for l in open(summary) if l.strip()]
    if len(lines) != want:
        return {'ran': False}
    suites, targets, deps = {}, {}, None
    for line in lines:
        w = line.split()
        if w[0] == 'suite':
            suites[w[1]] = {'exit': int(w[3]), 'passes': w[5], 'failures': w[7]}
        elif w[0] == 'target':
            targets[w[1]] = int(w[3])
        elif w[0] == 'deps':
            deps = line.strip()
    fails, rows = set(), 0
    for s in suites:
        log = os.path.join(d, '.logs', s + '.log')
        for line in open(log, errors='replace'):
            m = ROW.match(line)
            if m:
                rows += 1
                if m.group(1) in ('fail', 'xpass'):
                    fails.add(m.group(2))
    failed = sorted(s for s, v in suites.items() if v['exit'] != 0)
    died = sorted(s for s, v in suites.items() if v['passes'] == 'none')
    caught = bool(failed) or any(v != 0 for v in targets.values()) or deps is not None
    return {'ran': True, 'caught': caught, 'failed': failed, 'died': died, 'fails': fails,
            'rows': rows, 'targets': targets, 'deps': deps}

names = sorted(set(os.listdir(os.path.join(out, 'old'))) | set(os.listdir(os.path.join(out, 'new'))))
stale = {}
if os.path.exists(os.path.join(out, 'stale.txt')):
    for line in open(os.path.join(out, 'stale.txt')):
        layout, name, why = line.rstrip('\n').split(' ', 2)
        stale[(layout, name)] = why

def short(s):
    return s.replace('test-library-loading-', '')

broken = []
counts = {'both': 0, 'neither': 0, 'new-only': 0, 'old-only': 0, 'one-layout': 0}
for name in names:
    o, n = read('old', name), read('new', name)
    def verdict(r):
        if r is None:
            return '-'
        if not r['ran']:
            return 'not-run'
        return ('CAUGHT' if r['caught'] else 'passed') + '(%d)' % len(r['fails'])
    line = '%-58s old %-11s new %-11s' % (name, verdict(o), verdict(n))
    if o and o.get('ran'):
        line += ' old:' + ','.join(short(s) for s in o['failed'])
        if o['died']:
            line += ' died:' + ','.join(short(s) for s in o['died'])
        if o['targets']:
            line += ' ' + ' '.join('%s=%d' % kv for kv in o['targets'].items())
    if n and n.get('ran'):
        line += ' new:' + ','.join(short(s) for s in n['failed'])
        if n['died']:
            line += ' died:' + ','.join(short(s) for s in n['died'])
        if n['targets']:
            line += ' ' + ' '.join('%s=%d' % kv for kv in n['targets'].items())
    if o and n and o.get('ran') and n.get('ran'):
        only_old = sorted(o['fails'] - n['fails'])
        only_new = sorted(n['fails'] - o['fails'])
        if only_old:
            line += '\n    rows failing in old only: ' + ' | '.join(only_old)
        if only_new:
            line += '\n    rows failing in new only: ' + ' | '.join(only_new)
        if o['caught'] and not n['caught']:
            broken.append(name)
            counts['old-only'] += 1
        elif o['caught'] and n['caught']:
            counts['both'] += 1
        elif n['caught']:
            counts['new-only'] += 1
        else:
            counts['neither'] += 1
    else:
        counts['one-layout'] += 1
    print(line)
for (layout, name), why in sorted(stale.items()):
    print('stale on %s: %s: %s' % (layout, name, why))
print('counts:', counts, 'stale:', len(stale))
print('caught by old, not by new:', broken or 'none')
sys.exit(1 if broken else 0)
