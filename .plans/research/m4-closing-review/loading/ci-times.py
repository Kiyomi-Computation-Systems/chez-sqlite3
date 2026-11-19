# ci-times.py LOG...: each memory job log's suites and their "time:" lines.
# Prints: run-label shard suite seconds, one per line, then each job's sum.
import re, sys
for path in sys.argv[1:]:
    suite = None
    rows = []
    shard = None
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r'memory-(\d) \(the Valgrind gate', line)
        if m: shard = m.group(1)
        m = re.search(r'Z === (tests/\S+\.sps)\s*$', line)
        if m: suite = m.group(1); continue
        m = re.search(r'Z   time: (\d+)s under the gate', line)
        if m and suite:
            rows.append((suite, int(m.group(1)))); suite = None
    for s, t in rows:
        print(path, shard, s, t)
    print(path, shard, 'SUM', sum(t for _, t in rows), 'N', len(rows))
