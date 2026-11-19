# shards.py GATE-LOG[,GATE-LOG...] JOB-LOG...: where each new loading suite goes, by
# AGENTS.md's rule: a new suite goes in the shard whose suites take less
# time on CI. CI's times are main's latest three runs' "time:" lines, each
# memory job's log (gh run view --job ID --log). A new suite's CI time on a
# run's shard is its time here under the gate, the mean of the GATE-LOGs'
# "time:" lines,
# times that shard's rate on that run: the old loading suites' CI time
# there over their time here. -real and -decoys keep their shards; the old
# -missing leaves shard 1; each new suite then goes, largest first, to the
# shard whose three runs' total is less.
import re, sys
from collections import defaultdict

def gate_times(path):
    times, suite = {}, None
    for line in open(path, errors='replace'):
        m = re.search(r'=== (tests/\S+\.sps)', line)
        if m:
            suite = m.group(1)
            continue
        m = re.search(r'time: (\d+)s under the gate', line)
        if m and suite:
            times.setdefault(suite, []).append(int(m.group(1)))
            suite = None
    return times

gates = [gate_times(p) for p in sys.argv[1].split(',')]
ci = defaultdict(dict)   # (run-job) -> suite -> time
shard_of = {}
for path in sys.argv[2:]:
    shard, suite = None, None
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r'memory-(\d) \(the Valgrind gate', line)
        if m:
            shard = int(m.group(1))
        m = re.search(r'Z === (tests/\S+\.sps)\s*$', line)
        if m:
            suite = m.group(1)
            continue
        m = re.search(r'Z   time: (\d+)s under the gate', line)
        if m and suite:
            ci[path][suite] = int(m.group(1))
            shard_of[suite] = shard
            suite = None
    ci[path]['__shard__'] = shard

OLD = {'tests/test-library-loading-real.sps': 1, 'tests/test-library-loading-missing.sps': 1,
       'tests/test-library-loading-decoys.sps': 2}
# The old suites' times here, from the old layout's run: the second of each
# name's times in GATE-LOG (the new layout's -real and -decoys come first).
old_local = {s: sum(g[s][-1] for g in gates) / len(gates) for s in OLD}
new_local = {s: sum(g[s][0] for g in gates) / len(gates) for s in gates[0]}

runs = sorted(ci)
print('old suites here:', old_local)
rate = {}
for path in runs:
    shard = ci[path]['__shard__']
    olds = [s for s in OLD if OLD[s] == shard]
    rate[path] = sum(ci[path][s] for s in olds) / sum(old_local[s] for s in olds)
    print('%s shard %d: old loading suites %s s on CI, rate %.2f of here' % (
        path, shard, '+'.join(str(ci[path][s]) for s in olds), rate[path]))

def rest_total(shard):
    return sum(t for path in runs if ci[path]['__shard__'] == shard
               for s, t in ci[path].items() if s != '__shard__' and s not in OLD)

total = {1: rest_total(1), 2: rest_total(2)}
print('the shards without the loading suites, three runs:', total)

def estimate(suite, shard):
    return sum(new_local[suite] * rate[path] for path in runs if ci[path]['__shard__'] == shard)

place = {'tests/test-library-loading-real.sps': 1, 'tests/test-library-loading-decoys.sps': 2}
for s, shard in place.items():
    total[shard] += estimate(s, shard)
print('with -real in 1 and -decoys in 2, as now:', {k: round(v) for k, v in total.items()})
new = [s for s in new_local if s not in place and s not in OLD and 'library-loading' in s]
for s in sorted(new, key=lambda s: (-new_local[s], s)):
    shard = 1 if total[1] <= total[2] else 2
    total[shard] += estimate(s, shard)
    place[s] = shard
    print('%-45s %5.1f s here -> shard %d; totals %s' % (s, new_local[s], shard,
                                                      {k: round(v) for k, v in total.items()}))
print('shard 1:', sorted(s for s in place if place[s] == 1))
print('shard 2:', sorted(s for s in place if place[s] == 2))
