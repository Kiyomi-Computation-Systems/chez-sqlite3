# mutants3.py: round three, after sqlite3_stmt_busy was taken out. Round
# two's plants but sqlite3_stmt_busy's, with the texts that move back to
# the first round's, and the script's stale-list plant against 75.
import os, sys
sys.argv_saved = sys.argv
import mutants as m1
import mutants2 as m2
from mutants import LL, CV, make

orig = {x[0]: x for x in m1.M + m1.M3}
M = []
for x in m2.M + m2.M_EXTRA:
    name = x[0]
    if name.startswith('busy-') or name == 'decoy-busy-inverted' or name in [m[0] for m in M]:
        continue
    if name in ('optional-moved', 'optional-appended', 'decoy-parts-moved'):
        x = orig[name]
    if name == 'marker-in-comment':
        x = (name, x[1], [(m1.NATIVE, "  ;; M4's two required and its one optional", "  ;; The variadic one carries (__varargs_after 2).\n  ;; M4's two required and its one optional")], ())
    if name == 'list-stale':
        x = (name, x[1], [(CV, 'for each of the 75 arguments\nTEN', 'for each of the 74 arguments\nTEN')], ())
    M.append(x)
ENV = m2.ENV
if __name__ == '__main__' and sys.argv[1] == 'make':
    m1.MUT = os.path.join(os.getcwd(), 'build/mut3')
    m1.M[:] = M
    make([])
    for name, text in ENV.items():
        p = os.path.join(m1.MUT, name)
        if os.path.isdir(p):
            open(os.path.join(p, '.env'), 'w').write(text)
