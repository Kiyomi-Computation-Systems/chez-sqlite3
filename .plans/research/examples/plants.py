# plants.py build | report: the examples' plants.
#
# build, on the host, from the worktree's root: one tree per plant under build/plants/NAME/,
# a copy of the working tree's files (git ls-files -co --exclude-standard) with build/akku and
# build/scheme-libs, the plant applied. A control tree takes none.
# Then, in scripts/guix-env, from the root: sh .plans/research/examples/run-plants.sh
# report: each tree's failing rows against the rows its plant should fail, in
# .plans/research/examples/out/plants.txt.
import os, shutil, subprocess, sys

ROOT = os.getcwd()
OUT = os.path.join(ROOT, 'build', 'plants')

def edit(tree, path, old, new):
    p = os.path.join(tree, path)
    s = open(p, encoding='utf-8').read()
    assert s.count(old) == 1, (path, old, s.count(old))
    open(p, 'w', encoding='utf-8').write(s.replace(old, new))

def twin_edit(tree, name, old, new):
    # The file and its block on the page, changed alike, so the twins still match.
    f = os.path.join(tree, 'examples', name + '.sps')
    before = open(f, encoding='utf-8').read()
    edit(tree, 'examples/' + name + '.sps', old, new)
    after = open(f, encoding='utf-8').read()
    edit(tree, 'docs/examples.md', '```scheme\n' + before + '```\n', '```scheme\n' + after + '```\n')

def add_file(tree, path, text):
    open(os.path.join(tree, path), 'w', encoding='utf-8').write(text)

TD = 'tests/test-docs.sps'
PAGE = 'docs/examples.md'

# Each plant: its name, what it does to a tree, the suite it runs, and the start of
# each row that must fail, none other.
PLANTS = [
    ('control', lambda t: None, 'docs', []),
    ('text-line', lambda t: edit(t, PAGE, 'jsonb: #("blob" 1)\n', 'jsonb: #("text" 1)\n'), 'docs',
     ['docs/examples.md:311: the whole program, run as written, prints the text block after it']),
    ('file-only', lambda t: edit(t, 'examples/basics.sps', '"Dune" 1965', '"Dunes" 1965'), 'docs',
     ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('block-only', lambda t: edit(t, PAGE, ';; Each ? takes the next value after the SQL.\n',
                                  ';; Each ? takes a value.\n'), 'docs',
     ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('orphan-file', lambda t: add_file(t, 'examples/extra.sps', '(import (rnrs))\n'), 'docs',
     ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('orphan-block', lambda t: edit(t, PAGE, '\n## JSON\n',
                                    '\n## More\n\n```scheme\n(import (rnrs))\n(display "more\\n")\n```\n\n'
                                    'It prints:\n\n```text\nmore\n```\n\n## JSON\n'), 'docs',
     ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('swapped-links', lambda t: (edit(t, PAGE, '[`examples/basics.sps`](../examples/basics.sps)', '@@A@@'),
                                 edit(t, PAGE, '[`examples/transactions.sps`](../examples/transactions.sps)',
                                      '[`examples/basics.sps`](../examples/basics.sps)'),
                                 edit(t, PAGE, '@@A@@', '[`examples/transactions.sps`](../examples/transactions.sps)')),
     'docs', ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('no-text-block', lambda t: edit(t, PAGE, 'It prints:\n\n```text\nrows: #(1000)\n'
                                     'sum: 333833500\nlast three: ((998 996004) (999 998001) (1000 1000000))\n```\n', ''),
     'docs', ['each whole program of docs/examples.md has a text block after it']),
    ('private-import', lambda t: twin_edit(t, 'basics', '(import (rnrs) (chez-sqlite3))',
                                           '(import (rnrs) (chez-sqlite3) (chez-sqlite3 private utf8))'), 'docs',
     ['no whole program names a (chez-sqlite3 private ...) library']),
    ('stderr', lambda t: twin_edit(t, 'transactions', '(close-database! db)\n',
                                   '(display "warning\\n" (current-error-port))\n(close-database! db)\n'), 'docs',
     ['docs/examples.md:94: the whole program, run as written, exits 0 with nothing on stderr']),
    ('exit-3', lambda t: twin_edit(t, 'prepared', '(close-database! db)\n', '(close-database! db)\n(exit 3)\n'), 'docs',
     ['docs/examples.md:167: the whole program, run as written, exits 0 with nothing on stderr']),
    ('cwd-checkout', lambda t: edit(t, TD, 'cd \\"$1\\" || exit 125; shift; exec \\"$@\\"', 'shift; exec \\"$@\\"'),
     'docs', ['a whole program runs from a directory of its own',
              'a whole program of the docs leaves a file in its directory, and runs again there']),
    ('libdirs-relative', lambda t: edit(t, TD, '(define reader-libdirs (string-append (current-directory) "/src"))',
                                        '(define reader-libdirs "src")'), 'docs',
     ['docs/examples.md:21: the whole program, run as written, exits 0',
      'docs/examples.md:21: the whole program, run as written, prints the text block',
      'docs/examples.md:94: the whole program, run as written, exits 0',
      'docs/examples.md:94: the whole program, run as written, prints the text block',
      'docs/examples.md:167: the whole program, run as written, exits 0',
      'docs/examples.md:167: the whole program, run as written, prints the text block',
      'docs/examples.md:231: the whole program, run as written, exits 0',
      'docs/examples.md:231: the whole program, run as written, prints the text block',
      'docs/examples.md:311: the whole program, run as written, exits 0',
      'docs/examples.md:311: the whole program, run as written, prints the text block',
      'docs/quickstart.md:44: the whole program, run as written, exits 0',
      'docs/quickstart.md:44: the whole program, run as written, prints the text block',
      'docs/quickstart.md:105: the whole program, run as written, exits 0',
      'docs/quickstart.md:105: the whole program, run as written, with the library there',
      'docs/quickstart.md:105: the whole program, run as written, with CHEZ_SQLITE3_LIBRARY naming a missing file',
      'a whole program of the docs leaves a file in its directory, and runs again there',
      'a program that evals a loading call inside the guard the docs show',
      'the same program with the library there, a control']),
    ('never-again', lambda t: edit(t, TD, '(second (and again? (pair? left) (run-in base override program)))',
                                   '(second #f)'), 'docs',
     ['a whole program of the docs leaves a file in its directory, and runs again there']),
    ('rerun-differs', lambda t: (twin_edit(t, 'file-database', '(show "notebooks" (query db "select id, name from notebooks"))\n',
                                           '(show "notebooks" (query db "select id, name from notebooks"))\n'
                                           '(execute! db "insert into notes (notebook, body) values (?, ?)" 1 "hi")\n'
                                           '(show "notes" (query-row db "select count(*) from notes"))\n'),
                                 edit(t, PAGE, 'notebooks: (#(1 "inbox"))\n```\n', 'notebooks: (#(1 "inbox"))\nnotes: #(1)\n```\n')),
     'docs', ['docs/examples.md:231: the whole program, run as written, and run again in its directory']),
    ('h-first-link', lambda t: edit(t, TD, '(and (pair? paths) (car (reverse paths)))', '(and (pair? paths) (car paths))'),
     'docs', ['example-problems: the link counts only after the Scheme block before the program']),
    ('h-from-ignored', lambda t: edit(t, TD, '(if (>= i from) (cons (car rest) out) out)', '(cons (car rest) out)'),
     'docs', ['example-problems: the link counts only after the Scheme block before the program',
              'example-problems: a file no program links']),
    ('h-lines-not-text', lambda t: edit(t, TD, '(and (string? t) (string=? t (joined (block-lines b))))',
                                        '(and (string? t) (equal? (text-lines t) (block-lines b)))'),
     'docs', ["example-problems: a file's text is the program's lines"]),
    ('h-walk-first-only', lambda t: edit(t, TD, '(fold-left (lambda (acc e) (walk e acc)) found (elements x))',
                                         '(walk (car x) found)'), 'docs', ['private-names:']),
    ('h-walk-tails', lambda t: edit(t, TD, '(fold-left (lambda (acc e) (walk e acc)) found (elements x))',
                                    '(walk (cdr x) (walk (car x) found))'), 'docs', ['private-names:']),
    ('h-walk-no-vector', lambda t: edit(t, TD, '    (cond ((vector? x) (fold-left (lambda (acc e) (walk e acc)) found (vector->list x)))\n          ((pair? x)',
                                        '    (cond ((pair? x)'), 'docs', ['private-names:']),
    ('h-walk-twice', lambda t: edit(t, TD, '(if (member name found) found (append found (list name)))',
                                    '(append found (list name))'), 'docs', ['private-names:']),
    ('h-written-any', lambda t: edit(t, TD, '((not (search (joined lines) (written-link page path) 0))',
                                     '((not #t)'), 'docs', ["example-problems: a program whose link's text"]),
    ('body-import', lambda t: twin_edit(t, 'basics', '(import (rnrs) (chez-sqlite3))',
                                        '(import (rnrs) (only (chezscheme) import) (chez-sqlite3))\n'
                                        '(import (chez-sqlite3 private utf8))'), 'docs',
     ['no whole program names a (chez-sqlite3 private ...) library']),
    ('environment', lambda t: twin_edit(t, 'transactions', '(import (rnrs) (chez-sqlite3))',
                                        '(import (rnrs) (rnrs eval) (chez-sqlite3))\n'
                                        "(eval 'strict-utf8->string (environment '(chez-sqlite3 private utf8)))"), 'docs',
     ['no whole program names a (chez-sqlite3 private ...) library']),
    ('link-text', lambda t: edit(t, PAGE, '[`examples/transactions.sps`](../examples/transactions.sps) groups',
                                 '[`examples/basics.sps`](../examples/transactions.sps) groups'), 'docs',
     ["docs/examples.md's whole programs and the .sps files of examples/ are twins"]),
    ('run-line', lambda t: edit(t, PAGE, '--program chez-sqlite3/examples/basics.sps', '--program chez-sqlite3/examples/basic.sps'),
     'docs', ["docs/examples.md's commands run a file of examples/"]),
    ('lock-file', lambda t: add_file(t, 'examples/.#basics.sps', 'user@host.1234:1700000000\n'), 'docs', []),
    ('not-in-nav', lambda t: edit(t, 'site/pages.sls', '      ("examples.md" . "Examples")\n', ''), 'site',
     ['check-site']),
    ('not-in-readme', lambda t: edit(t, 'README.org', '- [[file:docs/examples.md][Examples]]: five programs for '
                                     'everyday work, JSON among them.\n', ''), 'docs',
     ['README.org links every page of docs/']),
]

def build():
    files = subprocess.run(['git', 'ls-files', '-co', '--exclude-standard'], check=True,
                           capture_output=True, text=True).stdout.split('\n')
    files = [f for f in files if f and os.path.isfile(f)]
    if os.path.exists(OUT): shutil.rmtree(OUT)
    for name, plant, _, _ in PLANTS:
        tree = os.path.join(OUT, name)
        for f in files:
            os.makedirs(os.path.join(tree, os.path.dirname(f)), exist_ok=True)
            shutil.copy2(f, os.path.join(tree, f))
        for d in ('build/akku', 'build/scheme-libs'):
            shutil.copytree(d, os.path.join(tree, d), symlinks=True)
        plant(tree)
    with open(os.path.join(OUT, 'suites.txt'), 'w') as f:
        for name, _, suite, _ in PLANTS: f.write(f'{name} {suite}\n')
    print('built', len(PLANTS), 'trees under', os.path.relpath(OUT, ROOT))

def failing(log):
    return [l[5:].strip() for l in open(log, encoding='utf-8', errors='replace') if l.startswith('FAIL ')]

def report():
    lines, bad = [], 0
    for name, _, suite, expected in PLANTS:
        log = os.path.join(OUT, name, 'plant.log')
        status = open(os.path.join(OUT, name, 'plant.status')).read().strip()
        if suite == 'site':
            got = ['check-site'] if status != 'exit 0' else []
            detail = [l.strip() for l in open(log, errors='replace') if 'check-site:' in l][:3]
        else:
            got = failing(log)
            detail = got
        caught = all(any(g.startswith(e) for g in got) for e in expected)
        extra = [g for g in got if not any(g.startswith(e) for e in expected)]
        ok = caught and not extra and (status == 'exit 0') == (not expected)
        bad += not ok
        lines.append(f'{"ok  " if ok else "BAD "} {name}: {status}; failed {len(got)}, expected {len(expected)}')
        for d in detail: lines.append(f'       {d}')
        for e in extra: lines.append(f'       UNEXPECTED {e}')
        if os.path.exists(os.path.join(OUT, name, 'notes.db')):
            lines.append('       notes.db is in the tree\'s root')
    lines.append(f'{len(PLANTS)} trees, {bad} not as expected')
    os.makedirs('.plans/research/examples/out', exist_ok=True)
    open('.plans/research/examples/out/plants.txt', 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))

{'build': build, 'report': report}[sys.argv[1]]()
