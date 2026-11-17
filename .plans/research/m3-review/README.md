# M3's closing review: probes and outputs

The probes behind M3's closing review's findings and fixes ([the review's
log](../../m3-closing-review-mutation-log.md)). They ran on Guix's 3.53.1, and at the floor where
a name says so, from the review's worktrees: a probe that keeps scratch databases names a
directory under that worktree's git-ignored `build/`. Run one from a tree's root with
`$CHEZ --libdirs src:tests:build/scheme-libs --program <probe>`. A probe that imports a private
library's marks (`fold-twice.sps`, `wt-twice-marked.sps`) needs the marked copy its log
describes.

## The reviewers'

- **Reviewer A, the code and its seams** ([reviewers/a/](reviewers/a/)):
  - `script-reenter3.sps`: `execute-script!` run again by a timer's continuation, 629 of 2804
    trials before the fix (its log);
  - `verbs-twice.sps`, `wt-twice.sps` and `wt-twice-marked.sps`: each writing verb's first
    remainder resumed twice, and `with-transaction` committing again at fuels 9 to 11, 15 and 16;
  - `wt-stale-plan.sps`: the BEGIN's plan read a section early, at fuels 14 to 25;
  - `watchdog-rollback2.sps`, `watchdog-rollback-floor.sps`, `watchdog-loss.sps` and
    `watchdog-docs.sps`: a tight watchdog leaving the transaction open, the write it loses, and
    the reference's pattern, which never did;
  - `surface.sps` and `opts.sps`: M3's exports on a closed connection, the wrong thread and a
    non-database; `fold-twice.sps`, `query-fold`'s flags made at its entry;
  - `script-reenter4.sps`: about 212 of 2804 trials refused by `call-with-open-handle`'s before
    thunk. Reviewer A read them as a timer reaching the window after `finished` is set; the
    transaction's fixer marked that window, saw no timer fire in it, and traced the refusals to
    continuations taken inside the wind before its section (`transaction/window-probe.sps`).
- **Reviewer B, the tests, the gate and the records** ([reviewers/b/](reviewers/b/)):
  - `twice.sps`: `execute!`'s remainder resumed twice, inserting twice under mutant N1;
  - `commit-depth.sps`: the interrupt depth a failed commit's handler runs at, 1 or, under B8, 2;
  - `long-keys.sps` and `shapes-order.sps`: the cache's long keys, and the order the
    near-spellings row checked them out in;
  - `q15-binds.sps` and `contention-late.sps`: the bind row's expiry count, and a late second
    thread in `test-contention`;
  - `times-all.txt`: every suite's time in both memory jobs over seven two-shard CI runs;
  - `docs/`: the reference's claims probed, among them which names load libsqlite3 at startup
    (`load*.sps`, `load.out`);
  - `plant.py`: its mutant copies, one replacement each.
- **The lead's reruns** ([reviewers/lead/](reviewers/lead/)): each major reproduced on the
  review's head, `c0a5408`; `twice-tree.txt` against `twice-N1.txt`; and `sweep.sh`, which names
  every export in a program with no loadable libsqlite3: 37 of 68 load it at startup
  (`sweep.txt`).

## The fixes'

- **The transaction** ([transaction/](transaction/)): `claim-window/`, where a caller's count lands
  against the call's claim; `window-probe.sps`, with `window-probe.patch`, where the timer's
  refusals in `call-with-open-handle` come from.
- **The conveniences** ([conveniences/](conveniences/)): `read-lookaside.sps`, the UTF-16 read's
  lookaside slots, one per read level.
- **The suites** ([suites/](suites/)): `cache-order.sps`, the near-spellings row's verdict compiled
  and interpreted; `prepare-race.sps`, the long prepare alone under the gate's Valgrind options,
  N trials a process, with the prepare called late, the old first round against the handshake.
