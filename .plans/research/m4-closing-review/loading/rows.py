# rows.py OLD-LOGS NEW-LOGS: the old layout's rows mapped to the new
# layout's, from the ROW lines dump-copy.sh's hook printed: each row's
# kind, name and expected value, the scratch directory's random name
# masked. Prints each distinct row once, with the suites that hold it in
# each layout; then every row held in one layout only. Exits 1 if a row of
# the old layout, by name and expected value, is held nowhere in the new,
# or any row is not a pass.
import collections, glob, os, re, sys

ROW = re.compile(r'^ROW \((\w+) ("(?:[^"\\]|\\.)*") (.*)\)$')
SCRATCH = re.compile(r'/tmp/chez-sqlite3-testing\.[A-Za-z0-9]+')

def rows(d):
    found = collections.OrderedDict()
    for log in sorted(glob.glob(os.path.join(d, 'test-library-loading-*.log'))):
        suite = os.path.basename(log)[len('test-library-loading-'):-len('.log')]
        for line in open(log, errors='replace'):
            m = ROW.match(line.rstrip('\n'))
            if m:
                key = (m.group(2), SCRATCH.sub('<scratch>', m.group(3)))
                found.setdefault(key, []).append((suite, m.group(1)))
    return found

old, new = rows(sys.argv[1]), rows(sys.argv[2])
bad = 0
print('old rows: %d run, %d distinct; new rows: %d run, %d distinct' % (
    sum(len(v) for v in old.values()), len(old), sum(len(v) for v in new.values()), len(new)))
for key in list(old) + [k for k in new if k not in old]:
    o = old.get(key, [])
    n = new.get(key, [])
    kinds = set(k for _, k in o + n)
    if kinds != {'pass'}:
        bad = 1
    mark = 'same' if o and n else ('OLD ONLY' if o else 'NEW ONLY')
    print('%-9s %-40s -> %-60s %s' % (mark, ','.join(s for s, _ in o) or '-', ','.join(s for s, _ in n) or '-',
                                      key[0][:150]))
lost = [k for k in old if k not in new]
added = [k for k in new if k not in old]
print('old rows held nowhere in the new layout, by name and expected value: %d' % len(lost))
for k in lost:
    print('  LOST', k[0])
print('new rows the old layout did not hold: %d' % len(added))
for k in added:
    print('  ADDED', k[0])
sys.exit(1 if (lost and '--allow-lost' not in sys.argv) or bad else 0)
