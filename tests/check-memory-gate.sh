#!/bin/sh
# `make check-memory-gate`: proves that `make test-memory` fails on planted
# memory defects (ADR-0005). Adapted from chez-curl's tests/check-memory-gate.sh
# (its ADR-0014); the cases keep its letters. One case per property:
#
#   a  plain        each plant, run without Valgrind, exits 0 and prints
#                   only its line, so a red gate can only mean Valgrind
#                   saw the defect
#   b  overrun      test-memory names the overrun plant FAIL, with exit 9,
#                   Valgrind's "Invalid write" in its log and in its own
#                   output, and goes on to the suite after it
#   b  leak         the same for the leak plant, with its loss record
#   b  connection   the same for the connection plant, which opens :memory:
#                   through open-database and drops the record: one block
#                   definitely lost, holding others, and allocated within
#                   libsqlite3, read from the loss record's stack
#   b  statement    the same for the statement plant, which prepares select 1
#                   through prepare-statement on a :memory: connection and
#                   drops both: Valgrind sees the statement only through its
#                   connection, the same one block definitely lost, holding
#                   others, allocated within libsqlite3; its plain line, case
#                   a's, holds the counters seeing the statement
#                   (ADR-0005)
#   b  fails        a program that Valgrind finds clean but that exits 1
#                   is named FAIL with its exit, then its own lines, whole:
#                   its FAIL line with its expected and actual values, 18
#                   lines before its end, and its last 10 lines, a FAIL
#                   among them, each line once, and no line between them
#   e  command      the commands test-memory hands Valgrind, whole, read by
#                   a stand-in for Valgrind: first the run that asks it for
#                   its default.supp, then the suite's, with -v,
#                   --command-line-only=yes and the suite's own --log-file,
#                   and timeout its parent. No --suppressions, with
#                   GUIX_ENVIRONMENT set or unset: the gate passes none
#                   anywhere. The stand-in runs nothing, so the suite
#                   FAILs: it wrote no Valgrind log
#   f  hangs        a program that never ends is named HUNG
#   g  none         test-memory refuses to pass with no suite
#   g  timeout      test-memory refuses a MEMORY_TIMEOUT of 0, of nothing,
#                   and of a non-number, each by its whole message, exit 2,
#                   running no suite
#   g  all          with no MEMORY_SUITES, test-memory runs every
#                   tests/test-*.sps, in make's order, and nothing else,
#                   read from its own run, a stand-in for Valgrind running
#                   nothing (chez-curl's n all, without the shards)
#   g  environment  test-memory refuses a MEMORY_SUITES from the
#                   environment, by its whole message, running no suite
#   g  whitespace   test-memory refuses to run from a checkout whose path
#                   holds whitespace, a space or a tab, each in a real
#                   directory of its own (make's CURDIR is the physical
#                   path, so a symlink's name never reaches it), by its
#                   whole message naming the path, exit 2, running no
#                   suite: the gate's child prefix is cut at whitespace
#   n  shards       CI runs the gate in two jobs, memory-1 and memory-2,
#                   one shard each (ADR-0005), and
#                   what a run ran is read from its own "=== " lines, a
#                   stand-in for Valgrind running nothing: MEMORY_SHARD=1
#                   and 2 each run the Makefile's own list, MEMORY_SUITES_1
#                   or MEMORY_SUITES_2 as make itself reads it, in its
#                   order; the two run every tests/test-*.sps once between
#                   them, and nothing else; and each suite is handed to
#                   Valgrind as case e's is (split). With no MEMORY_SHARD,
#                   every suite runs: g all. test-memory refuses, each by
#                   its whole message and running no suite, a MEMORY_SHARD
#                   but 1 or 2 (refused), one from the environment
#                   (environment), one beside a MEMORY_SUITES on its
#                   command line (beside), and a shard's list set on its
#                   command line or, under make -e, in the environment,
#                   with a MEMORY_SHARD or without (lists), a shard whose
#                   list the Makefile leaves empty (empty), and one whose
#                   list holds two suites of one name (names)
#   h  options      test-memory refuses to run while any source of options
#                   its command line does not show is present, each in a
#                   case of its own, planted in the case's own copy:
#                   VALGRIND_OPTS, $HOME/.valgrindrc, ./.valgrindrc,
#                   VALGRIND_LIB (at a copy of Valgrind's library
#                   directory whose default.supp hides every leak), and any
#                   other VALGRIND_ variable. And a suite that writes
#                   $HOME/.valgrindrc mid-run cannot hand the next suite a
#                   suppression: --command-line-only=yes
#   i  suppressions a suppressions file the gate does not pass, named
#                   default.supp and hiding every leak, fails the leak
#                   plant by name, though Valgrind exits 0: beside
#                   Valgrind's own default.supp, and in its place
#   j  evidence     a pass needs the log to show that Valgrind ran Chez
#                   itself, on the suite, and reported 0 errors from 0
#                   contexts: a CHEZ that is a script, exec'ing Chez or
#                   running it as a child, fails the leak plant; a program
#                   that execs away from Valgrind fails; a Valgrind that
#                   runs another program than the suite fails
#   k  options      a pass needs Valgrind's "Valgrind options:" list to be
#                   exactly the gate's, in order. A program that branches
#                   on memory nothing initialised fails, exit 9 (undef);
#                   --undef-value-errors=no, added through VALGRIND, hides
#                   it, and fails it by name (added). Stand-ins for
#                   Valgrind that drop --leak-check=full, or change
#                   --errors-for-leak-kinds=definite to none, each hide the
#                   leak plant, and fail it by name (dropped, changed); one
#                   that moves a flag fails a clean program (order)
#   l  logs         Valgrind writes to a log of its own, and every piece of
#                   evidence is read from it: a suite that prints a clean
#                   ERROR SUMMARY with Valgrind's pid, then execs away,
#                   fails (forged); a Valgrind log an earlier run left is
#                   never read: a Valgrind that writes none fails (stale);
#                   two suites with one name, whose logs would be one, are
#                   refused (names)
#   m  awk          the evidence check is one awk program, and a pass needs
#                   its exit status 0 and its one line "ok". Stand-ins for
#                   awk, first on PATH, each fail a clean program, naming
#                   the check: one that fails, printing nothing, as a broken
#                   program or a missing feature would (fails); one that
#                   prints "ok", then exits 2 (ok-fails); and one that exits
#                   0, printing nothing (silent)
#   p  children     a child that reaches native code runs under the gate's
#                   own Valgrind, through (chez-sqlite3-testing)'s
#                   gated-command, with a log of its own, and the gate reads
#                   it (ADR-0005). Each parent below loses nothing
#                   and ignores its child's exit status, so only the child's
#                   log can fail it. Each runs plainly first, exit 0 and its
#                   one line (plain). A child that leaks the leak plant's 777
#                   bytes fails its parent, naming the child's log, with
#                   Valgrind's loss record in the log and in test-memory's
#                   output (leak); so does one that overruns the overrun
#                   plant's 23-byte block (overrun). A clean child passes,
#                   and leaves its one log (clean)
#                   A child that spawns a process, a fork before its exec, passes
#                   clean and leaves its one log, since the gate's options carry
#                   --child-silent-after-fork=yes; it still fails on a leak of
#                   its own (fork, forkleak)
#   q  child        every rule the parent's log is held to holds for each
#      evidence     child's: a Valgrind that drops --leak-check=full for
#                   children alone hides the child's leak, and fails it by
#                   name (options); a child whose command begins neither
#                   with CHEZ nor with a C program named libsqlite3-oracle,
#                   the suites' oracle, fails (other); such a C program that
#                   leaks the plant's 777 bytes fails, by name, and one that
#                   loses nothing passes (oracle); a child that prints a clean ERROR SUMMARY
#                   on stderr, then execs away, fails: its log has none
#                   (forged); a child log an earlier run left is never read
#                   (stale). And a child run without gated-command runs
#                   outside Valgrind, and the gate cannot see it: its leak
#                   passes (unwrapped). That is the gap ADR-0005 records;
#                   the tests/test-library-loading-*.sps suites close it
#                   for their own children, each of
#                   which must say it ran under memcheck
#   r  slow         test-memory prints each suite's time under the gate, and
#                   names a suite SLOW, failing the run, once its time passes
#                   three quarters of MEMORY_TIMEOUT, as ADR-0005 splits
#                   test-library-loading past 450 s of 600. Under a
#                   MEMORY_TIMEOUT of 12, so past 9 s: a plant that sleeps
#                   until its process is 10 s old is SLOW, and one that
#                   sleeps until 7.5 s passes, just under; each one's line
#                   is followed by its time line, the first 10 or 11 s and
#                   past, the second 7 to 9 s and within. The process is the
#                   one timeout starts for Valgrind, so its age is what the
#                   gate times, give or take its exit, whatever Valgrind's
#                   start costs
#   o  ci           tests/check-ci.sh passes on .github/workflows, with its
#                   one line: it holds the whole workflow, and so the two
#                   steps of each memory job, memory-1 and memory-2, "run:
#                   make check-memory-gate" then "run: make test-memory
#                   MEMORY_SHARD=1" or "=2", with no if: or
#                   continue-on-error: on them or their job, and no variable
#                   that steers the gate. make test runs it too, so a
#                   workflow that drops a memory job fails CI's main job
#
# chez-curl's c and d are not here: they held its one suppression file,
# which this gate has none of (it passes no suppression in any
# environment). Its n all is g all here. Its o held two jobs, one per
# shard, with an awk of its own; ours runs check-ci, which holds the whole
# workflow, both shards' jobs among it (ADR-0005). And the rule
# that the two shards hold every suite once is make test's own, through
# make check-memory-shards; n split holds that each shard runs its list.
#
# Every case runs in a private copy of the tree, made under mktemp -d: the
# working tree without .git (nor any .git below vendor/), build/ and
# .claude/ (Claude Code's local state, which can hold whole worktrees), with
# the chez-srfi checkout, and make deps run there. Every stand-in, scratch
# program and rc file lives in that directory, never in the working tree's
# build/, so two runs of this script, or one beside make test-memory,
# share nothing. Nothing in a copy runs git.
#
# A case compares the lines starting "test-memory: " as a whole: each
# suite's outcome and the count. Case r also compares each suite's time
# line, "  time: ", which follows its outcome. The suite after a plant is
# build/check-memory-gate/after.sps, an empty program, which loses nothing.
# Every run writes build/memory/<suite>.log, the suite's own output, and
# build/memory/<suite>.valgrind, Valgrind's, and the whole directory is
# removed before each run but l stale's second, so no log is left from an
# earlier one. Scratch files are named by relative path: make splits
# MEMORY_SUITES on spaces, and the checkout's path may hold one.
#
# `make check-memory-gate` passes MAKE, TIMEOUT, CHEZ, VALGRIND and
# LIBDIRS, the ones it uses. Run directly, the script takes make, timeout,
# scheme and valgrind from PATH.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 2

# The inner make starts afresh: nothing of an outer make's flags or
# command-line variables reaches it, nor a shard or a list of suites from
# the environment, which test-memory reads, nor a child prefix of an outer
# test-memory's, which gated-command reads.
unset MAKEFLAGS MFLAGS MAKELEVEL MEMORY_SHARD MEMORY_SUITES MEMORY_SUITES_1 MEMORY_SUITES_2 CHEZ_SQLITE3_GATE_CHILD

MAKE=${MAKE:-make}
TIMEOUT=${TIMEOUT:-timeout}
CHEZ=${CHEZ:-scheme}
VALGRIND=${VALGRIND:-valgrind}
LIBDIRS=${LIBDIRS:-src:tests:build/scheme-libs}

# Each run's per-suite cap, in seconds: a plant ends in a few. The hang
# case's is shorter, so its plant is killed soon. Case r's is 12, so a suite
# is SLOW past 9 s, three quarters of it.
suite_timeout=300
hang_timeout=15
slow_timeout=12

overrun=tests/memory-plant-overrun.sps
leak=tests/memory-plant-leak.sps
connection=tests/memory-plant-connection.sps
statement=tests/memory-plant-statement.sps
scratch=build/check-memory-gate
after=$scratch/after.sps
fails=$scratch/fails.sps
hangs=$scratch/hangs.sps
slow=$scratch/slow.sps
nearly=$scratch/nearly.sps
latrc=$scratch/late-rc.sps
execs=$scratch/execs.sps
undef=$scratch/undef.sps
forge=$scratch/forge.sps
twin=$scratch/twin/after.sps
stub=$scratch/valgrind-stub
mute=$scratch/valgrind-mute
swap=$scratch/valgrind-swap
logs=build/memory

tmp=$(mktemp -d) || { echo "check-memory-gate: could not make a temporary directory" >&2; exit 2; }
tmp=$(CDPATH='' cd -- "$tmp" && pwd)
trap 'cd /; rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

out=$tmp/out
shared=$tmp/shared     # read-only for every case: the suppression, Valgrind's directory
kit=$tmp/kit           # the stand-ins and scratch programs, copied into each case's tree
template=$tmp/template
mkdir "$shared" "$kit" "$template" || exit 2

# ---- the template: a copy of the tree, with make deps run in it ----
# cp -a, as check-test-fails does; no .git is copied, so none is ever
# deleted. vendor/'s checkouts hold a .git file each, which is left out.
for entry in "$root"/* "$root"/.[!.]* "$root"/..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  case "$entry" in
    "$root/.git" | "$root/build" | "$root/.claude") continue ;;
    "$root/vendor")
      mkdir "$template/vendor" || exit 2
      for sub in "$entry"/*; do
        [ -e "$sub" ] || continue
        mkdir "$template/vendor/${sub##*/}" || exit 2
        for f in "$sub"/* "$sub"/.[!.]* "$sub"/..?*; do
          [ -e "$f" ] || [ -L "$f" ] || continue
          [ "${f##*/}" = .git ] && continue
          cp -a "$f" "$template/vendor/${sub##*/}/" || { echo "check-memory-gate: could not copy $f" >&2; exit 2; }
        done
      done
      continue ;;
  esac
  cp -a "$entry" "$template/" || { echo "check-memory-gate: could not copy $entry" >&2; exit 2; }
done
if [ -n "$(find "$template" -name .git)" ]; then
  echo "check-memory-gate: the copy holds a .git" >&2
  exit 2
fi
"$MAKE" --no-print-directory -C "$template" deps >"$tmp/deps.out" 2>&1 || {
  echo "check-memory-gate: make deps failed in the copy:" >&2
  sed 's/^/  | /' "$tmp/deps.out" >&2
  exit 2
}

# Valgrind's own default.supp, as Valgrind names it in a run that nothing
# outside its command line steers. Case i needs it.
vgbin=${VALGRIND%% *}
vgdefault=$(cd "$tmp" && env -u VALGRIND_LIB "$vgbin" -v --command-line-only=yes true 2>&1 |
  sed -n 's/^--[0-9]*-- Reading suppressions file: //p')
case $vgdefault in
  /*/default.supp) ;;
  *) echo "check-memory-gate: $vgbin -v, run on true, named no default.supp of its own: \"$vgdefault\"" >&2
     exit 2 ;;
esac
vglibdir=${vgdefault%/default.supp}

# The real file sh names, as Valgrind reports what it ran.
sh_real=$(readlink -f "$(command -v sh)")

# A suppression that matches every definite leak, the plant's among them.
everything=$shared/everything.supp
cat >"$everything" <<'EOF'
{
   everything
   Memcheck:Leak
   match-leak-kinds: definite
   fun:*
   ...
}
EOF

# A copy of Valgrind's library directory, every file linked but
# default.supp, which gains the suppression above: VALGRIND_LIB pointed
# here hid the leak plant from the gate before it refused VALGRIND_LIB.
vglib=$shared/vglib
mkdir -p "$vglib"
for f in "$vglibdir"/*; do ln -s "$f" "$vglib/"; done
rm -f "$vglib/default.supp"
cat "$vgdefault" "$everything" >"$vglib/default.supp"

# ---- the kit: stand-ins and scratch programs, one copy per case's tree ----
mkdir -p "$kit/twin"

cat >"$kit/after.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: an empty program, which loses
;;; nothing, run after a plant to show that test-memory goes on.
(import (rnrs))
(display "after: ran")
(newline)
EOF
cp "$kit/after.sps" "$kit/twin/after.sps"

cat >"$kit/fails.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a program that fails on its own.
(import (rnrs))
(display "FAIL a planted check\n  expected: (planted 1)\n  actual:   (planted 2)\n")
(let loop ((i 1))
  (when (<= i 12)
    (display "fails: line ") (display i) (newline)
    (loop (+ i 1))))
(display "FAIL a late check\n  expected: (late 1)\n  actual:   (late 2)\n")
(display "fails: exits 1, with no memory defect")
(newline)
(exit 1)
EOF

cat >"$kit/hangs.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a program that never ends.
(import (rnrs) (only (chezscheme) sleep make-time))
(sleep (make-time 'time-duration 0 3600))
EOF

# Case r's two plants. Each sleeps until its process is AGE seconds old, then
# exits 0. Its process is the one timeout starts for Valgrind, which execs
# its tool in place, so its age is what test-memory times, but for the
# moments after it wakes. Linux counts a process's start, /proc/self/stat's
# 22nd field, in clock ticks after boot, 100 a second (USER_HZ, on amd64 and
# arm64 alike), and /proc/uptime gives the seconds since. The fields are
# counted after the ")" that ends the second, the command's name, which may
# hold a space.
for how in slow nearly; do
  case $how in
    slow) age=10 ;;
    *)    age=15/2 ;;
  esac
  cat >"$kit/$how.sps" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: sleeps until its process is $age
;;; seconds old, then exits 0, losing nothing.
(import (rnrs) (only (chezscheme) sleep make-time))
(define (text path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    get-string-all))
(define (data s)
  (let ((port (open-string-input-port s)))
    (let loop ((found '()))
      (let ((datum (read port)))
        (if (eof-object? datum) (reverse found) (loop (cons datum found)))))))
(define stat (text "/proc/self/stat"))
(define started
  (let loop ((i (- (string-length stat) 1)))
    (if (char=? (string-ref stat i) #\\))
        (/ (list-ref (data (substring stat (+ i 1) (string-length stat))) 19) 100)
        (loop (- i 1)))))
(define left (- $age (- (car (data (text "/proc/uptime"))) started)))
(when (> left 0)
  (let ((ns (exact (round (* left 1000000000)))))
    (sleep (make-time 'time-duration (mod ns 1000000000) (div ns 1000000000)))))
(display "$how: slept until its process was $age seconds old")
(newline)
EOF
done

cat >"$kit/late-rc.sps" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: writes \$HOME/.valgrindrc, naming
;;; a suppression that matches every definite leak, for the suite after it.
(import (rnrs) (only (chezscheme) getenv))
(call-with-output-file (string-append (getenv "HOME") "/.valgrindrc")
  (lambda (port)
    (display "--suppressions=$everything" port)
    (newline port)))
(display "late-rc: wrote \$HOME/.valgrindrc")
(newline)
EOF

cat >"$kit/execs.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: replaces itself with /bin/sh,
;;; which exits 0. Valgrind follows no exec, so it never reports on the run.
(import (rnrs)
        (only (chezscheme) load-shared-object foreign-procedure foreign-alloc
              foreign-set! foreign-sizeof))
(load-shared-object "libc.so.6")
(define execv (foreign-procedure "execv" (string uptr) int))
(define (c-string s)
  (let* ((b (string->utf8 s)) (n (bytevector-length b)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))
(define args '("sh" "-c" "exit 0"))
(define width (foreign-sizeof 'uptr))
(define argv (foreign-alloc (* width (+ (length args) 1))))
(let loop ((i 0) (args args))
  (if (null? args)
      (foreign-set! 'uptr argv (* width i) 0)
      (begin
        (foreign-set! 'uptr argv (* width i) (c-string (car args)))
        (loop (+ i 1) (cdr args)))))
(display "execs: replacing itself with /bin/sh, which exits 0")
(newline)
(flush-output-port (current-output-port))
(execv "/bin/sh" argv)
(display "execs: execv failed")
(newline)
(exit 1)
EOF

cat >"$kit/undef.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: branches on four bytes of foreign
;;; memory that nothing initialised, which Valgrind reports as a
;;; "Conditional jump or move depends on uninitialised value(s)".
(import (rnrs) (only (chezscheme) foreign-alloc foreign-ref foreign-free))
(define p (foreign-alloc 8))
(display (if (= (foreign-ref 'unsigned-32 p 0) 12345) "undef: branched one way" "undef: branched"))
(newline)
(foreign-free p)
EOF

# The forger prints one line as Valgrind would, with Valgrind's pid, which
# is its own, then replaces itself with /bin/sh, so Valgrind never reports.
cat >"$kit/forge.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: prints, on stderr and with its
;;; own pid, which is Valgrind's, the ERROR SUMMARY of a clean run, then
;;; replaces itself with /bin/sh, which exits 0, so that Valgrind itself
;;; reports nothing.
(import (rnrs)
        (only (chezscheme) load-shared-object foreign-procedure foreign-alloc
              foreign-set! foreign-sizeof))
(load-shared-object "libc.so.6")
(define getpid (foreign-procedure "getpid" () int))
(define execv (foreign-procedure "execv" (string uptr) int))
(define (c-string s)
  (let* ((b (string->utf8 s)) (n (bytevector-length b)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))
(define args '("sh" "-c" "exit 0"))
(define width (foreign-sizeof 'uptr))
(define argv (foreign-alloc (* width (+ (length args) 1))))
(let loop ((i 0) (args args))
  (if (null? args)
      (foreign-set! 'uptr argv (* width i) 0)
      (begin
        (foreign-set! 'uptr argv (* width i) (c-string (car args)))
        (loop (+ i 1) (cdr args)))))
(let ((err (current-error-port)) (pid (number->string (getpid))))
  (put-string err (string-append "==" pid "== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)\n"))
  (flush-output-port err))
(execv "/bin/sh" argv)
(display "forge: execv failed")
(newline)
(exit 1)
EOF

# Two children that fork before they exec: each runs `true` through
# capture-command. Valgrind, given --log-file with %p, opens a second log for
# a fork before its exec, with a Command: line and no summary, unless it is
# given --child-silent-after-fork=yes. The second also
# leaks the leak plant's 777 bytes.
cat >"$kit/forkclean.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a clean child that spawns a process.
(import (rnrs) (chez-sqlite3-testing))
(capture-command '("true"))
(exit 0)
EOF
cat >"$kit/forkleak.sps" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a child that spawns a process, then
;;; loses 777 bytes.
(import (rnrs) (only (chezscheme) foreign-alloc) (chez-sqlite3-testing))
(capture-command '("true"))
(foreign-alloc 777)
(display "forkleak: spawned a process, then planted a 777-byte block")
(newline)
(exit 0)
EOF

# The parents of cases p and q. Each runs one child and ignores the child's
# exit status, so a red gate can only mean the gate read the child's log.
for how in leak overrun clean forged other unwrapped stale forkclean forkleak elsewhere; do
  case $how in
    leak)      run='(gated-command getenv (list (getenv "CHEZ") "--program" "tests/memory-plant-leak.sps"))' ;;
    overrun)   run='(gated-command getenv (list (getenv "CHEZ") "--program" "tests/memory-plant-overrun.sps"))' ;;
    clean)     run="(gated-command getenv (list (getenv \"CHEZ\") \"--program\" \"$after\"))" ;;
    forged)    run="(gated-command getenv (list (getenv \"CHEZ\") \"--program\" \"$forge\"))" ;;
    other)     run="(gated-command getenv (list \"env\" (getenv \"CHEZ\") \"--program\" \"$after\"))" ;;
    unwrapped) run='(list (getenv "CHEZ") "--program" "tests/memory-plant-leak.sps")' ;;
    stale)     run='(gated-command getenv (list (getenv "CHEZ") "--program" "tests/memory-plant-leak.sps"))' ;;
    forkclean) run="(gated-command getenv (list (getenv \"CHEZ\") \"--libdirs\" \"$LIBDIRS\" \"--program\" \"$scratch/forkclean.sps\"))" ;;
    elsewhere) run="(append (list \"sh\" \"-c\" \"cd / && exec \\\"\$@\\\"\" \"sh\") (gated-command getenv (list (getenv \"CHEZ\") \"--program\" (string-append (current-directory) \"/$after\"))))" ;;
    forkleak)  run="(gated-command getenv (list (getenv \"CHEZ\") \"--libdirs\" \"$LIBDIRS\" \"--program\" \"$scratch/forkleak.sps\"))" ;;
  esac
  cat >"$kit/child-$how.sps" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: runs one child, and ignores its
;;; exit status, so that only Valgrind's log of the child can fail it.
(import (rnrs) (only (chezscheme) getenv current-directory) (chez-sqlite3-testing))
(capture-command $run)
(display "child-$how: ran its child")
(newline)
(exit 0)
EOF
done

# A C program named as the suites' oracle is, for case q oracle: given leak,
# it loses a 777-byte block; given nothing, it loses nothing.
mkdir "$kit/oracle"
cat >"$kit/oracle/plant.c" <<'EOF'
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv)
{
  if (argc > 1 && strcmp(argv[1], "leak") == 0) {
    void *volatile block = malloc(777);
    block = 0;
    (void)block;
  }
  return 0;
}
EOF
${CC:-cc} -O0 -o "$kit/oracle/libsqlite3-oracle" "$kit/oracle/plant.c" 2>"$tmp/cc.err" || {
  echo "check-memory-gate: could not compile case q's oracle plant:" >&2
  sed 's/^/  | /' "$tmp/cc.err" >&2
  exit 2
}
for how in oracle-leak oracle-clean; do
  case $how in
    oracle-leak) arg=' "leak"' ;;
    *)           arg='' ;;
  esac
  cat >"$kit/child-$how.sps" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: runs one child, a C program named
;;; libsqlite3-oracle, through gated-command, and ignores its exit status.
(import (rnrs) (only (chezscheme) getenv current-directory) (chez-sqlite3-testing))
(capture-command (gated-command getenv (list (string-append (current-directory) "/$scratch/oracle/libsqlite3-oracle")$arg)))
(display "child-$how: ran its child")
(newline)
(exit 0)
EOF
done

# The oracle again, run through a symlinked directory, as a TMPDIR that is a
# link makes it (macOS's /var is one): its Command: line names the link, and
# Valgrind's "Reading syms from" line names the file the link leads to, so the
# gate resolves the Command: line's program before it compares them.
cat >"$kit/child-oracle-link.sps" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: runs the oracle through a symlinked
;;; directory, through gated-command, and ignores its exit status.
(import (rnrs) (only (chezscheme) getenv current-directory) (chez-sqlite3-testing))
(capture-command (list "ln" "-sfn" "oracle" "$scratch/oracle-link"))
(capture-command (gated-command getenv (list (string-append (current-directory) "/$scratch/oracle-link/libsqlite3-oracle"))))
(display "child-oracle-link: ran its child")
(newline)
(exit 0)
EOF

# A Valgrind that drops --leak-check=full from a child's options alone: one
# whose --log-file is under a .children directory. The parent's options
# pass as they came.
cat >"$kit/valgrind-childdrop" <<EOF
#!/bin/sh
child=
for arg in "\$@"; do
  case \$arg in --log-file=*.children/*) child=yes ;; esac
done
n=\$#
for arg in "\$@"; do
  if [ -n "\$child" ] && [ "\$arg" = --leak-check=full ]; then continue; fi
  set -- "\$@" "\$arg"
done
shift "\$n"
exec "$vgbin" "\$@"
EOF

# A stand-in for Valgrind: it appends the name of the process that started
# it, then each argument, one per line, then a line "--", to
# <itself>.argv. It names a default.supp, as Valgrind -v does, so that
# test-memory's question of its default.supp has an answer, and exits 0
# having run nothing.
cat >"$kit/valgrind-stub" <<'EOF'
#!/bin/sh
{
  printf 'parent: %s\n' "$(cat "/proc/$PPID/comm" 2>/dev/null || echo unknown)"
  for arg in "$@"; do printf '%s\n' "$arg"; done
  printf '%s\n' --
} >>"$0.argv"
echo "--1-- Reading suppressions file: /check-memory-gate/valgrind-stub/default.supp" >&2
exit 0
EOF

# Another that runs nothing, but names Valgrind's own default.supp, so that
# a log left from a real run would pass every check but its existence.
cat >"$kit/valgrind-mute" <<EOF
#!/bin/sh
echo "--1-- Reading suppressions file: $vgdefault" >&2
exit 0
EOF

# A Valgrind that runs another program than the suite it is handed: the
# empty one, after.sps. It hands Valgrind every other argument as it came.
cat >"$kit/valgrind-swap" <<EOF
#!/bin/sh
n=\$#
i=0
for arg in "\$@"; do
  i=\$((i + 1))
  case \$i:\$arg in
    \$n:*.sps) set -- "\$@" "$after" ;;
    *)         set -- "\$@" "\$arg" ;;
  esac
done
shift "\$n"
exec "$vgbin" "\$@"
EOF

# Three Valgrinds that edit the options they are handed, up to the first
# argument that is no option, and hand the rest on as it came: one drops
# --leak-check=full, one changes --errors-for-leak-kinds=definite to none,
# and one moves --leak-check=full to the end of the options.
for how in drop change order; do
  cat >"$kit/valgrind-$how" <<EOF
#!/bin/sh
n=\$#
moved=
options=yes
for arg in "\$@"; do
  if [ -n "\$options" ]; then
    case \$arg in
      -*) ;;
      *) options=
         [ -z "\$moved" ] || set -- "\$@" "\$moved" ;;
    esac
  fi
  if [ -n "\$options" ]; then
    case $how:\$arg in
      drop:--leak-check=full) continue ;;
      change:--errors-for-leak-kinds=definite) arg=--errors-for-leak-kinds=none ;;
      order:--leak-check=full) moved=\$arg; continue ;;
    esac
  fi
  set -- "\$@" "\$arg"
done
shift "\$n"
exec "$vgbin" "\$@"
EOF
done

# Two scripts for CHEZ: one execs the real Chez, the other runs it as a
# child. Valgrind runs the shell, not Chez, and follows no exec or child.
for how in exec child; do
  case $how in
    exec) run='exec' ;;
    *)    run='' ;;
  esac
  printf '#!%s\n%s "%s" "$@"\n' "$sh_real" "$run" "$CHEZ" >"$kit/chez-$how"
done

# Three stand-ins for awk, each logging its arguments, one call per line, to
# <itself>.calls. Only the evidence check hands awk the suite's command.
for how in fails ok-fails silent; do
  mkdir "$kit/awk-$how"
  case $how in
    fails)    body='echo "awk: syntax error (planted)" >&2; exit 2' ;;
    ok-fails) body='echo ok; exit 2' ;;
    *)        body='exit 0' ;;
  esac
  {
    printf '#!%s\n' "$sh_real"
    printf '%s\n' 'printf "%s\n" "$*" >>"$0.calls"' "$body"
  } >"$kit/awk-$how/awk"
done
find "$kit" -type f \( -name 'valgrind-*' -o -name 'chez-*' -o -name awk \) -exec chmod +x {} +

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf 'check-memory-gate: ok %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'check-memory-gate: FAILED %s\n' "$1" >&2; }

# newtree: a private copy of the template for the next case, with the kit in
# its build/check-memory-gate/. The copy before it is removed. The shell is
# left in the new copy; every path a case names is relative to it.
trees=0
T=
newtree() {
  cd "$tmp" || exit 2
  [ -z "$T" ] || rm -rf "$T"
  trees=$((trees + 1))
  T=$tmp/case-$trees
  cp -a "$template" "$T" || { echo "check-memory-gate: could not copy the tree" >&2; exit 2; }
  mkdir -p "$T/$scratch" || exit 2
  cp -a "$kit/." "$T/$scratch/" || { echo "check-memory-gate: could not copy the kit" >&2; exit 2; }
  cd "$T" || exit 2
}

# gate MAKE-ARG...: runs make test-memory with MEMORY_TIMEOUT=$per_suite and
# the arguments, output to $out, under a cap of its own: room for two
# suites to run out their time, and two minutes more. A make that runs
# longer has lost its per-suite timeout. Answers make's status.
per_suite=$suite_timeout
gate() {
  rm -rf "$logs"
  gate_keep "$@"
}

# gate_keep MAKE-ARG...: gate, with the logs of the run before left in place.
gate_keep() {
  "$TIMEOUT" $((2 * per_suite + 120)) "$MAKE" --no-print-directory test-memory \
    MEMORY_TIMEOUT="$per_suite" "$@" >"$out" 2>&1
}

# Problems found in the current case, one per line, and the case's verdict.
problems=
problem() { problems="$problems$1
"; }

# verdict NAME [plain]: ok when the case found no problem, else FAILED with
# each, and then, unless the case ran no make, the whole output of its last
# run.
verdict() {
  if [ -z "$problems" ]; then
    ok "$1"
  else
    bad "$1"
    printf '%s' "$problems" | sed 's/^/  /' >&2
    [ "${2:-}" = plain ] || [ ! -f "$out" ] || sed 's/^/  | /' "$out" >&2
  fi
  problems=
}

# want_status WANT STATUS: WANT is 0, nonzero, or a status. A status of 124
# is the case's own cap: make test-memory never finished.
want_status() {
  if [ "$2" -eq 124 ]; then
    problem "make test-memory did not finish within its cap, so no per-suite timeout stopped it"
  elif [ "$1" = 0 ] && [ "$2" -ne 0 ]; then
    problem "make test-memory exited $2, not 0"
  elif [ "$1" = nonzero ] && [ "$2" -eq 0 ]; then
    problem "make test-memory exited 0"
  fi
}

# want_lines WANTED: the run's "test-memory: " lines must be exactly WANTED.
want_lines() {
  got=$(grep '^test-memory: ' "$out")
  if [ "$got" != "$1" ]; then
    problem "make test-memory's lines differ:
$(printf '%s\n' "$1" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
  fi
}

# want_in FILE TEXT WHAT: FILE must hold a line containing TEXT.
want_in() {
  if [ ! -f "$1" ]; then
    problem "$3: $1 does not exist"
  elif ! grep -qF -- "$2" "$1"; then
    problem "$3: no \"$2\" in $1"
  fi
}

# want_match FILE ERE WHAT: FILE must hold a line matching the extended
# regular expression ERE. For Valgrind's lines whose sizes vary by SQLite's
# version and build.
want_match() {
  if [ ! -f "$1" ]; then
    problem "$3: $1 does not exist"
  elif ! grep -qE -- "$2" "$1"; then
    problem "$3: no line matching \"$2\" in $1"
  fi
}

# want_sqlite_stack VLOG: the stack of VLOG's definite loss record must pass
# through libsqlite3: a frame in a file of that name, as a library with no
# debug information shows it, or in sqlite3_open_v2, as one with it does.
# So the block lost is SQLite's, not Chez's own.
want_sqlite_stack() {
  if [ ! -f "$1" ]; then
    problem "its Valgrind log: $1 does not exist"
  elif ! awk '/are definitely lost in loss record/ { inside = 1; next }
              inside && /^==[0-9]+== *$/ { inside = 0 }
              inside && (/libsqlite3/ || /sqlite3_open_v2/) { found = 1 }
              END { exit !found }' "$1"; then
    problem "its Valgrind log: the definite loss record's stack passes through no libsqlite3 frame, in $1"
  fi
}

failed_line() { printf 'test-memory: FAIL %s (exit 9, Valgrind'"'"'s: an error or a definite leak)\n' "$1"; }

# zero_line SUITE PROBLEM...: the line naming SUITE FAIL though Valgrind
# exited 0, with each problem test-memory found in its log, in its order.
zero_line() {
  suite=$1
  shift
  why=$1
  shift
  for extra in "$@"; do why="$why; $extra"; done
  printf 'test-memory: FAIL %s (exit 0, but %s)\n' "$suite" "$why"
}

# want_lines_pid WANTED: as want_lines, with each child log's pid read as
# PID, since a pid differs from run to run.
want_lines_pid() {
  got=$(grep '^test-memory: ' "$out" | sed 's|\.children/[0-9][0-9]*\.valgrind|.children/PID.valgrind|g')
  if [ "$got" != "$1" ]; then
    problem "make test-memory's lines differ:
$(printf '%s\n' "$1" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
  fi
}

# children_of SUITE: the directory of SUITE's children's Valgrind logs.
children_of() { printf '%s/%s.children' "$logs" "$(basename "$1" .sps)"; }

# want_children SUITE N: SUITE's run left exactly N child logs.
want_children() {
  found=$(ls "$(children_of "$1")" 2>/dev/null | grep -c '\.valgrind$')
  [ "$found" -eq "$2" ] || problem "$(children_of "$1") holds $found child logs, not $2"
}

# child_why SUITE PROBLEM: one child log's problem, as test-memory words it.
child_why() { printf "a child's Valgrind log, %s/PID.valgrind: %s" "$(children_of "$1")" "$2"; }

# child_options SUITE: the options test-memory hands a child's Valgrind.
child_options() {
  printf '%s' "-v --command-line-only=yes --log-file=$(pwd -P)/$(children_of "$1")/%p.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --child-silent-after-fork=yes"
}

# A suite's two logs: its own output, and Valgrind's.
log_of()  { printf '%s/%s.log' "$logs" "$(basename "$1" .sps)"; }
vlog_of() { printf '%s/%s.valgrind' "$logs" "$(basename "$1" .sps)"; }

# gate_options SUITE: the options test-memory hands Valgrind for SUITE, in
# order, one space between each, as other_options lists them. They are
# ADR-0005's, written out here and not read from the Makefile. No
# suppression, in any environment.
gate_options() {
  printf '%s' "-v --command-line-only=yes --log-file=$(vlog_of "$1") --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --child-silent-after-fork=yes"
}

# The problems zero_line names, worded as test-memory words them.
no_log() { printf 'Valgrind wrote no log, %s' "$(vlog_of "$1")"; }
no_zero='Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts"'
ran_other() { printf 'Valgrind ran %s, not %s, the file CHEZ names' "$1" "$2"; }
other_command() { printf 'Valgrind'"'"'s Command: line is "%s", not "%s"' "$1" "$2"; }
other_options() { printf 'Valgrind'"'"'s options are [%s], not the gate'"'"'s [%s]' "$1" "$2"; }
other_files() { printf 'Valgrind read the suppressions files [%s], and the gate allows exactly [%s]' "$1" "$2"; }

# The suppressions files test-memory allows, as other_files lists them:
# Valgrind's own, and no other.
allowed=$vgdefault
count_line()  { printf 'test-memory: ran %d, passed %d, failed %d, hung %d, slow %d\n' "$1" "$2" "$3" "$4" "${5:-0}"; }

# ---- a: each plant, run plainly ----
for p in "$overrun" "$leak" "$connection" "$statement"; do
  newtree
  case "$p" in
    "$overrun")    line="memory-plant-overrun: planted a one-byte write just past a 23-byte foreign block" ;;
    "$leak")       line="memory-plant-leak: planted a 777-byte foreign block that nothing frees or holds" ;;
    "$connection") line="memory-plant-connection: opened :memory: through open-database and dropped the record, never closed" ;;
    *)             line="memory-plant-statement: prepared select 1 on :memory: through prepare-statement and dropped both, never finalized or closed; counts ((block . 0) (connection . 1) (statement . 1))" ;;
  esac
  plain=$("$CHEZ" --libdirs "$LIBDIRS" --program "$p" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || problem "it exited $rc without Valgrind"
  [ "$plain" = "$line" ] || problem "its output, without Valgrind, is not the one line \"$line\":
$(printf '%s\n' "$plain" | sed 's/^/  | /')"
  verdict "a plain: $p exits 0 without Valgrind, and prints only its line" plain
done

# ---- b: test-memory fails on each plant, by name, with Valgrind's marker ----
# The connection and statement plants' sizes are SQLite's, and vary by
# version and build, so their markers are patterns: one block definitely
# lost, holding others, in the loss record and in the summary, then its
# stack.
for p in "$overrun" "$leak" "$connection" "$statement"; do
  newtree
  gate MEMORY_SUITES="$p $after"
  status=$?
  want_status nonzero "$status"
  want_lines "$(failed_line "$p")
test-memory: pass $after
$(count_line 2 1 1 0)"
  vlog=$(vlog_of "$p")
  case "$p" in
    "$overrun") markers="Invalid write of size 1
0 bytes after a block of size 23 alloc'd" ;;
    "$leak")    markers="777 bytes in 1 blocks are definitely lost in loss record" ;;
    *)          markers= ;;
  esac
  markers="$markers
ERROR SUMMARY: 1 errors from 1 contexts"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    want_in "$vlog" "$m" "its Valgrind log"
    want_in "$out" "$m" "test-memory's own output"
  done <<EOF
$markers
EOF
  if [ "$p" = "$connection" ] || [ "$p" = "$statement" ]; then
    while IFS= read -r m; do
      want_match "$vlog" "$m" "its Valgrind log"
      want_match "$out" "$m" "test-memory's own output"
    done <<'EOF'
==[0-9]+== [0-9,]+ \([0-9,]+ direct, [0-9,]+ indirect\) bytes in 1 blocks are definitely lost in loss record [0-9]+ of [0-9]+$
definitely lost: [0-9,]+ bytes in 1 blocks$
EOF
    want_sqlite_stack "$vlog"
  fi
  verdict "b $(basename "$p" .sps): test-memory names $p FAIL, with Valgrind's report in its log and its output, and runs the suite after it"
done

newtree
gate MEMORY_SUITES="$fails $after"
status=$?
want_status nonzero "$status"
want_lines "test-memory: FAIL $fails (exit 1)
test-memory: pass $after
$(count_line 2 1 1 0)"
# The program's own lines, whole: the FAIL 18 lines before its end with its
# two indented lines, then its last 10, which hold the late FAIL. Lines 4 to
# 9, fails: line 1 to 6, are neither, and none may be shown.
wanted="  | FAIL a planted check
  |   expected: (planted 1)
  |   actual:   (planted 2)
  | fails: line 7
  | fails: line 8
  | fails: line 9
  | fails: line 10
  | fails: line 11
  | fails: line 12
  | FAIL a late check
  |   expected: (late 1)
  |   actual:   (late 2)
  | fails: exits 1, with no memory defect"
got=$(grep '^  | ' "$out")
[ "$got" = "$wanted" ] || problem "test-memory's own output shows other lines of the program:
$(printf '%s\n' "$wanted" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
want_in "$out" "ERROR SUMMARY: 0 errors from 0 contexts" "test-memory's own output, Valgrind's verdict"
verdict "b fails: test-memory names a program that exits 1 FAIL, with its exit, its FAIL lines and its last lines, and runs the suite after it"

# ---- e: the commands Valgrind is handed ----
# suite_argv SUITE: what the stand-in must write for SUITE's run: its parent,
# timeout, then ADR-0005's flags with the suite's own --log-file, then Chez
# on the suite. Case n holds each shard's runs to it too.
suite_argv() {
  printf 'parent: %s\n' "$(basename -- "$TIMEOUT")"
  printf '%s\n' -v --command-line-only=yes "--log-file=$(vlog_of "$1")" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --child-silent-after-fork=yes
  printf '%s\n' "$CHEZ" --libdirs "$LIBDIRS" --program "$1" --
}
# expected_argv: what the stand-in must write. First comes the run that asks
# Valgrind for its default.supp, whose parent this does not hold, then the
# suite's. Neither arm has a --suppressions: the gate passes none.
expected_argv() {
  printf '%s\n' -v --command-line-only=yes true --
  suite_argv "$leak"
}
for arm in outside inside; do
  newtree
  if [ "$arm" = outside ]; then
    ( unset GUIX_ENVIRONMENT; gate MEMORY_SUITES="$leak" VALGRIND="$stub" )
    status=$?
  else
    ( GUIX_ENVIRONMENT=${GUIX_ENVIRONMENT:-/gnu/store/check-memory-gate-profile}
      export GUIX_ENVIRONMENT
      gate MEMORY_SUITES="$leak" VALGRIND="$stub" )
    status=$?
  fi
  wanted=$(expected_argv)
  got=$(sed '1{/^parent: /d;}' "$stub.argv" 2>/dev/null)
  [ "$got" = "$wanted" ] || problem "the stand-in for Valgrind was handed other commands:
$(printf '%s\n' "$wanted" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
  want_status nonzero "$status"
  want_lines "$(zero_line "$leak" "$(no_log "$leak")")
$(count_line 1 0 1 0)"
  case "$arm" in
    outside) verdict "e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0005's flags, no suppression, then Chez, and a Valgrind that runs nothing fails" ;;
    *)       verdict "e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0005's flags, no suppression either, then Chez, and a Valgrind that runs nothing fails" ;;
  esac
done

# ---- f: a program that never ends ----
newtree
per_suite=$hang_timeout
gate MEMORY_SUITES="$hangs"
status=$?
per_suite=$suite_timeout
want_status nonzero "$status"
want_lines "test-memory: HUNG $hangs (no exit within ${hang_timeout}s)
$(count_line 1 0 0 1)"
verdict "f hangs: a program that never ends is named HUNG"

# ---- g: no suite, and no whole number of seconds ----
newtree
gate MEMORY_SUITES=
status=$?
want_status nonzero "$status"
want_lines "test-memory: no suites: MEMORY_SUITES is empty"
verdict "g none: test-memory refuses to pass with no suite"

newtree
for value in 0 '' abc; do
  rm -f "$stub.argv"
  gate MEMORY_SUITES="$after" VALGRIND="$stub" MEMORY_TIMEOUT="$value"
  status=$?
  [ "$status" -eq 2 ] || problem "MEMORY_TIMEOUT='$value': make test-memory exited $status, not 2"
  want_lines "test-memory: MEMORY_TIMEOUT is '$value', not a positive whole number of seconds"
  if grep -q '^=== ' "$out" || [ -e "$stub.argv" ] || [ -e "$(log_of "$after")" ]; then
    problem "MEMORY_TIMEOUT='$value': a suite ran"
  fi
done
verdict "g timeout: test-memory refuses a MEMORY_TIMEOUT of 0, of nothing and of a non-number, each by its whole message, exit 2, running no suite"

# With no MEMORY_SUITES, every suite, in make's order: $(sort) is byte
# order. The stand-in runs nothing, so each suite fails for want of a log;
# the lines show which ran.
newtree
suites=$(printf '%s\n' tests/test-*.sps | LC_ALL=C sort)
n=$(printf '%s\n' "$suites" | grep -c '')
[ "$n" -gt 0 ] && [ -f "$(printf '%s\n' "$suites" | head -n 1)" ] ||
  problem "the copy holds no tests/test-*.sps, so this case checks nothing"
gate VALGRIND="$stub"
status=$?
want_status nonzero "$status"
got=$(sed -n 's/^=== //p' "$out")
[ "$got" = "$suites" ] || problem "test-memory ran other suites than every tests/test-*.sps, in order:
$(printf '%s\n' "$suites" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
wanted=$(printf '%s\n' "$suites" | while IFS= read -r t; do zero_line "$t" "$(no_log "$t")"; done)
want_lines "$wanted
$(count_line "$n" 0 "$n" 0)"
verdict "g all: with no MEMORY_SUITES, test-memory runs every tests/test-*.sps, in order, and nothing else"

newtree
rm -f "$stub.argv"
( MEMORY_SUITES=$after; export MEMORY_SUITES; gate VALGRIND="$stub" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES is set in the environment, where one left exported would narrow every run unseen; give it on make's command line, or unset it (ADR-0005)"
if grep -q '^=== ' "$out" || [ -e "$stub.argv" ] || [ -e "$(log_of "$after")" ]; then
  problem "with MEMORY_SUITES in the environment, a suite ran"
fi
verdict "g environment: test-memory refuses a MEMORY_SUITES from the environment, by its whole message, running no suite"

# The checkout's path holds whitespace: the gate's child prefix, which holds
# an absolute --log-file path, would be cut there. A real directory, since
# CURDIR is the physical path. A space, and a tab, each in a copy of its own.
for name in "with space" "with	tab"; do
  newtree
  holder=$tmp/$name
  mkdir "$holder" || exit 2
  cp -a "$T" "$holder/tree" || { echo "check-memory-gate: could not copy the tree" >&2; exit 2; }
  cd "$holder/tree" || exit 2
  here=$(pwd -P)
  rm -f "$stub.argv"
  gate MEMORY_SUITES="$after" VALGRIND="$stub"
  status=$?
  [ "$status" -eq 2 ] || problem "in '$here': make test-memory exited $status, not 2"
  want_lines "test-memory: the checkout's path holds whitespace, '$here': the gate's child prefix, CHEZ_SQLITE3_GATE_CHILD, is cut at whitespace, so its absolute --log-file path would split; run from a path without whitespace"
  if grep -q '^=== ' "$out" || [ -e "$stub.argv" ] || [ -e "$(log_of "$after")" ]; then
    problem "in '$here': a suite ran"
  fi
  cd "$tmp" || exit 2
  verdict "g whitespace: test-memory refuses to run from a path holding whitespace ($(printf '%s' "$name" | tr '\t' 'T')), by its whole message, exit 2, running no suite"
done

# ---- n: the two shards ----
# What a run of test-memory ran, from its "=== " lines, in order. The
# stand-in for Valgrind runs nothing, so each suite FAILs at once, for want
# of a log.
runs_of_out() { sed -n 's/^=== //p' "$out"; }
# list_of N: the Makefile's MEMORY_SUITES_N, one suite a line, asked of make
# itself, which reads the list as test-memory's make does.
list_of() {
  "$MAKE" --no-print-directory --eval "print-shard-list: ; @printf '%s\\n' \$(MEMORY_SUITES_$1)" print-shard-list
}
# nothing_ran WHAT: no suite ran, and the stand-in for Valgrind never did.
nothing_ran() {
  if [ -n "$(runs_of_out)" ] || [ -e "$stub.argv" ]; then
    problem "$1: a suite ran"
  fi
}
newtree
printf '%s\n' tests/test-*.sps | LC_ALL=C sort >"$scratch/suites"
[ -s "$scratch/suites" ] || problem "the copy holds no tests/test-*.sps, so this case checks nothing"
for shard in 1 2; do
  rm -f "$stub.argv"
  gate MEMORY_SHARD=$shard VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  runs_of_out >"$scratch/shard-$shard"
  list_of $shard >"$scratch/list-$shard" 2>"$scratch/list-$shard.err" ||
    problem "make could not print MEMORY_SUITES_$shard: $(cat "$scratch/list-$shard.err")"
  n=$(grep -c '' "$scratch/shard-$shard")
  if [ "$n" -eq 0 ]; then
    problem "MEMORY_SHARD=$shard ran no suite"
  fi
  cmp -s "$scratch/list-$shard" "$scratch/shard-$shard" ||
    problem "MEMORY_SHARD=$shard ran other suites than the Makefile's MEMORY_SUITES_$shard, in its order (wanted <, ran >):
$(diff "$scratch/list-$shard" "$scratch/shard-$shard" | head -n 20 | sed 's/^/  /')"
  wanted=$(while IFS= read -r t; do zero_line "$t" "$(no_log "$t")"; done <"$scratch/list-$shard")
  want_lines "$wanted
$(count_line "$(grep -c '' "$scratch/list-$shard")" 0 "$(grep -c '' "$scratch/list-$shard")" 0)"
  {
    printf '%s\n' -v --command-line-only=yes true --
    while IFS= read -r t; do suite_argv "$t"; done <"$scratch/list-$shard"
  } >"$scratch/argv-wanted-$shard"
  sed '1{/^parent: /d;}' "$stub.argv" >"$scratch/argv-got-$shard" 2>/dev/null
  cmp -s "$scratch/argv-wanted-$shard" "$scratch/argv-got-$shard" ||
    problem "MEMORY_SHARD=$shard handed the stand-in for Valgrind other commands than case e's, suite by suite (wanted <, got >):
$(diff "$scratch/argv-wanted-$shard" "$scratch/argv-got-$shard" | head -n 20 | sed 's/^/  /')"
done
# The two runs, merged and sorted as the suites are, must be the suites: a
# suite in neither, in both or twice in one, and a path that is no suite,
# each shows in the difference.
cat "$scratch/shard-1" "$scratch/shard-2" | LC_ALL=C sort >"$scratch/merged"
cmp -s "$scratch/suites" "$scratch/merged" ||
  problem "the two shards' runs, merged, are not every tests/test-*.sps once (every suite <, the two runs >):
$(diff "$scratch/suites" "$scratch/merged" | head -n 20 | sed 's/^/  /')"
verdict "n split: MEMORY_SHARD=1 and 2 each run the Makefile's own list, in its order, the two run every tests/test-*.sps once between them, and nothing else, and each suite is handed to Valgrind as case e's is"

for value in 0 3 '1 2' '1 ' "1'" '1"' 01 one; do
  rm -f "$stub.argv"
  gate MEMORY_SHARD="$value" VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  want_lines "test-memory: MEMORY_SHARD is \"$value\", and the gate has two shards: give 1 or 2, or no MEMORY_SHARD for every suite of MEMORY_SUITES (ADR-0005)"
  nothing_ran "MEMORY_SHARD='$value'"
done
verdict "n refused: test-memory refuses a MEMORY_SHARD of 0, 3, \"1 2\", \"1 \", 1', 1\", 01 or one, by its whole message, running no suite"

rm -f "$stub.argv"
( MEMORY_SHARD=1; export MEMORY_SHARD; gate VALGRIND="$stub" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SHARD is set in the environment, where one left exported would narrow every run unseen; give it on make's command line, or unset it (ADR-0005)"
nothing_ran "with MEMORY_SHARD in the environment"
verdict "n environment: test-memory refuses a MEMORY_SHARD from the environment, by its whole message, running no suite"

rm -f "$stub.argv"
gate MEMORY_SHARD=1 MEMORY_SUITES="$after" VALGRIND="$stub"
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES is given on make's command line with MEMORY_SHARD=1, whose own list would run in its place: give one of the two (ADR-0005)"
nothing_ran "beside a command line's MEMORY_SUITES"
verdict "n beside: test-memory refuses a MEMORY_SHARD beside a MEMORY_SUITES on its command line, by its whole message, running no suite"

# A shard's list set from outside: on the command line, with the shard that
# runs it and with none, and from the environment, which make -e lets
# override the Makefile's.
for arm in shard none other environment; do
  rm -f "$stub.argv"
  v=MEMORY_SUITES_2; where="on make's command line"
  case $arm in
    shard) v=MEMORY_SUITES_1
           gate MEMORY_SHARD=1 MEMORY_SUITES_1="$after" VALGRIND="$stub"; status=$? ;;
    none)  gate MEMORY_SUITES_2="$after" VALGRIND="$stub"; status=$? ;;
    other) gate MEMORY_SHARD=1 MEMORY_SUITES_2="$after" VALGRIND="$stub"; status=$? ;;
    *)     where="in the environment"
           ( MEMORY_SUITES_2=$after; export MEMORY_SUITES_2; gate -e MEMORY_SHARD=2 VALGRIND="$stub" ); status=$? ;;
  esac
  want_status nonzero "$status"
  want_lines "test-memory: $v is set $where, but the Makefile writes each shard's list, and a shard runs that list or none; to run other suites, give MEMORY_SUITES and no MEMORY_SHARD (ADR-0005)"
  nothing_ran "$v set $where ($arm)"
done
verdict "n lists: test-memory refuses a shard's list set on its command line, with its shard, another or none, or under make -e in the environment, by its whole message, running no suite"

# set_list N LIST: the copy's Makefile writes MEMORY_SUITES_N as LIST, on one
# line: its definition and the lines that continue it are replaced.
set_list() {
  awk -v shard="$1" -v list="$2" '
    cont { cont = /\\$/; next }
    index($0, "MEMORY_SUITES_" shard " :=") == 1 { n++; cont = /\\$/; print "MEMORY_SUITES_" shard " := " list; next }
    { print }
    END { exit (n != 1) }' Makefile >Makefile.new && mv Makefile.new Makefile ||
    problem "could not write MEMORY_SUITES_$1 in the copy's Makefile"
}

# A shard whose list the copy's Makefile leaves empty: without its refusal,
# test-memory would run no suite and pass.
for shard in 1 2; do
  newtree
  set_list "$shard" ""
  rm -f "$stub.argv"
  gate MEMORY_SHARD=$shard VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  want_lines "test-memory: no suites: MEMORY_SUITES_$shard is empty"
  nothing_ran "with MEMORY_SUITES_$shard empty"
  verdict "n empty: test-memory refuses a shard, MEMORY_SHARD=$shard, whose list the Makefile leaves empty, by its whole message, running no suite"
done

# Two suites of one name in a shard's list, which the copy's Makefile writes:
# refused from the list the shard runs, as l names refuses them in
# MEMORY_SUITES, since their logs would be one.
newtree
set_list 2 "$after $twin"
rm -f "$stub.argv"
gate MEMORY_SHARD=2 VALGRIND="$stub"
status=$?
want_status nonzero "$status"
want_lines "test-memory: $after and $twin share the name after, so they would share $logs/after.log and $logs/after.valgrind; rename one (ADR-0005)"
nothing_ran "with two suites of one name in MEMORY_SUITES_2"
verdict "n names: two suites with one name in a shard's list are refused, so one suite's logs are never another's, running no suite"

# ---- h: options from outside the command line ----
# Each source is planted in the case's own copy, never in the working tree,
# $HOME or Valgrind's own directory, and each must stop test-memory before
# any suite runs.
leaklog=$(basename "$leak" .sps).log

newtree
( VALGRIND_OPTS="--suppressions=$everything"
  export VALGRIND_OPTS
  gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_OPTS is set (--suppressions=$everything): Valgrind would add it to the gate's options; unset it (ADR-0005)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with VALGRIND_OPTS set"

newtree
home=$PWD/$scratch/home
mkdir -p "$home"
printf '%s\n' "--suppressions=$everything" >"$home/.valgrindrc"
( HOME=$home; export HOME; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: $home/.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0005)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with a \$HOME/.valgrindrc"

# Every case's tree is a copy, so the rc file is planted in this one.
newtree
printf '%s\n' "--suppressions=$everything" >.valgrindrc
gate MEMORY_SUITES="$leak"
status=$?
want_status nonzero "$status"
want_lines "test-memory: ./.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0005)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree"

newtree
( VALGRIND_LIB=$vglib; export VALGRIND_LIB; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_LIB is set ($vglib): Valgrind would take its tool, its preloads and its default.supp from there; unset it (ADR-0005)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with VALGRIND_LIB set, at a copy of Valgrind's directory whose default.supp hides every leak"

newtree
launcher=$PWD/$stub
( VALGRIND_LAUNCHER=$launcher; export VALGRIND_LAUNCHER; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_LAUNCHER is set ($launcher): Valgrind reads its VALGRIND_ variables, and no command line shows them; unset it (ADR-0005)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with any other VALGRIND_ variable set, VALGRIND_LAUNCHER"

# A $HOME with no .valgrindrc when test-memory starts: the first suite
# writes one, naming the suppression that hides every leak.
newtree
late=$PWD/$scratch/home-late
mkdir -p "$late"
( HOME=$late; export HOME; gate MEMORY_SUITES="$latrc $leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: pass $latrc
$(failed_line "$leak")
$(count_line 2 1 1 0)"
[ -f "$late/.valgrindrc" ] || problem "$latrc wrote no $late/.valgrindrc, so this case shows nothing"
want_in "$(vlog_of "$leak")" "777 bytes in 1 blocks are definitely lost in loss record" "the planted leak"
verdict "h options: a \$HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes"

# ---- i: suppressions files the gate does not pass ----
# Each is named default.supp, as Valgrind's own is, and hides every leak:
# first beside Valgrind's own, then in its place. The options that pass it
# come through VALGRIND, so the options rule names them first.
for arm in beside instead; do
  newtree
  case $arm in
    beside)  extra="--suppressions=$vglib/default.supp"
             gate MEMORY_SUITES="$leak" VALGRIND="$VALGRIND $extra"
             status=$?
             read_files="$vglib/default.supp, $allowed" ;;
    *)       extra="--default-suppressions=no --suppressions=$vglib/default.supp"
             gate MEMORY_SUITES="$leak" VALGRIND="$VALGRIND $extra"
             status=$?
             read_files=$vglib/default.supp ;;
  esac
  want_status nonzero "$status"
  options=$(other_options "$extra $(gate_options "$leak")" "$(gate_options "$leak")")
  wanted=$(zero_line "$leak" "$options" "$(other_files "$read_files" "$allowed")")
  want_lines "$wanted
$(count_line 1 0 1 0)"
  case $arm in
    beside) verdict "i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name" ;;
    *)      verdict "i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name" ;;
  esac
done

# ---- j: a pass needs evidence that Valgrind ran Chez on the suite ----
for how in exec child; do
  newtree
  wrapper=$scratch/chez-$how
  wrapper_real=$(readlink -f "$wrapper")
  gate MEMORY_SUITES="$leak" CHEZ="$wrapper"
  status=$?
  want_status nonzero "$status"
  case $how in
    exec) wanted=$(zero_line "$leak" "$(ran_other "$sh_real" "$wrapper_real")" "$no_zero") ;;
    *)    wanted=$(zero_line "$leak" "$(ran_other "$sh_real" "$wrapper_real")") ;;
  esac
  want_lines "$wanted
$(count_line 1 0 1 0)"
  want_in "$logs/$leaklog" "memory-plant-leak: planted a 777-byte foreign block" "the plant's line, so Chez ran"
  case $how in
    exec) verdict "j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw" ;;
    *)    verdict "j evidence: a CHEZ that is a script running Chez as a child fails the leak plant, which Valgrind never saw" ;;
  esac
done

newtree
gate MEMORY_SUITES="$execs"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$execs" "$no_zero")
$(count_line 1 0 1 0)"
want_in "$logs/$(basename "$execs" .sps).log" "execs: replacing itself with /bin/sh, which exits 0" "the program's line, so it ran"
verdict "j evidence: a program that execs away from Valgrind, which then reports nothing, fails"

newtree
gate MEMORY_SUITES="$leak" VALGRIND="$swap"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$leak" "$(other_command "$CHEZ --libdirs $LIBDIRS --program $after" "$CHEZ --libdirs $LIBDIRS --program $leak")")
$(count_line 1 0 1 0)"
verdict "j evidence: a Valgrind that runs another program than the suite fails the suite"

# ---- k: Valgrind's options are exactly the gate's ----
newtree
gate MEMORY_SUITES="$undef"
status=$?
want_status nonzero "$status"
want_lines "$(failed_line "$undef")
$(count_line 1 0 1 0)"
want_in "$(vlog_of "$undef")" "Conditional jump or move depends on uninitialised value(s)" "its Valgrind log"
want_in "$out" "Conditional jump or move depends on uninitialised value(s)" "test-memory's own output"
verdict "k undef: a program that branches on memory nothing initialised fails, exit 9, with Valgrind's report: the plant the next case hides"

newtree
gate MEMORY_SUITES="$undef" VALGRIND="$VALGRIND --undef-value-errors=no"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$undef" "$(other_options "--undef-value-errors=no $(gate_options "$undef")" "$(gate_options "$undef")")")
$(count_line 1 0 1 0)"
want_in "$(vlog_of "$undef")" "ERROR SUMMARY: 0 errors from 0 contexts" "its Valgrind log, so the option hid the plant"
verdict "k added: --undef-value-errors=no, added through VALGRIND, hides that plant, and fails it by name"

for how in drop change order; do
  newtree
  case $how in
    drop)   suite=$leak
            got=$(gate_options "$leak" | sed 's/ --leak-check=full / /') ;;
    change) suite=$leak
            got=$(gate_options "$leak" | sed 's/ --errors-for-leak-kinds=definite/ --errors-for-leak-kinds=none/') ;;
    *)      suite=$after
            got="$(gate_options "$after" | sed 's/ --leak-check=full / /') --leak-check=full" ;;
  esac
  gate MEMORY_SUITES="$suite" VALGRIND="$scratch/valgrind-$how"
  status=$?
  want_status nonzero "$status"
  want_lines "$(zero_line "$suite" "$(other_options "$got" "$(gate_options "$suite")")")
$(count_line 1 0 1 0)"
  case $how in
    order) verdict "k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name" ;;
    *)     want_in "$(vlog_of "$leak")" "ERROR SUMMARY: 0 errors from 0 contexts" "its Valgrind log, so the edit hid the plant"
           case $how in
             drop) verdict "k dropped: a Valgrind that drops --leak-check=full hides the leak plant, and fails it by name" ;;
             *)    verdict "k changed: a Valgrind that turns --errors-for-leak-kinds=definite to none hides the leak plant, and fails it by name" ;;
           esac ;;
  esac
done

# ---- l: the evidence comes from Valgrind's own log ----
newtree
gate MEMORY_SUITES="$forge"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$forge" "$no_zero")
$(count_line 1 0 1 0)"
want_in "$(log_of "$forge")" "== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" "the suite's output, its forged line"
if [ -f "$(vlog_of "$forge")" ] && grep -q 'ERROR SUMMARY' "$(vlog_of "$forge")"; then
  problem "$(vlog_of "$forge") holds an ERROR SUMMARY, so Valgrind reported, and the case shows nothing"
fi
verdict "l forged: a suite that prints a clean ERROR SUMMARY with Valgrind's pid, then execs away, fails: the evidence is Valgrind's own log"

newtree
gate MEMORY_SUITES="$after"
status=$?
want_status 0 "$status"
[ -f "$(vlog_of "$after")" ] || problem "the first run left no $(vlog_of "$after"), so this case shows nothing"
gate_keep MEMORY_SUITES="$after" VALGRIND="$mute"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$after" "$(no_log "$after")")
$(count_line 1 0 1 0)"
verdict "l stale: a Valgrind log an earlier run left is never read: a Valgrind that writes none fails"

newtree
gate MEMORY_SUITES="$after $twin"
status=$?
want_status nonzero "$status"
want_lines "test-memory: $after and $twin share the name after, so they would share $logs/after.log and $logs/after.valgrind; rename one (ADR-0005)"
[ ! -e "$(log_of "$after")" ] || problem "a suite ran"
verdict "l names: two suites with one name, in two directories, are refused, so one suite's logs are never another's"

# ---- m: the evidence check's own verdict ----
for how in fails ok-fails silent; do
  newtree
  dir=$scratch/awk-$how
  case $how in
    fails)    why='the evidence check (awk) exited 2' ;;
    ok-fails) why='the evidence check (awk) exited 2' ;;
    *)        why='the evidence check (awk) printed no "ok" line' ;;
  esac
  ( PATH=$PWD/$dir:$PATH; export PATH; gate MEMORY_SUITES="$after" )
  status=$?
  want_status nonzero "$status"
  want_lines "$(zero_line "$after" "$why")
$(count_line 1 0 1 0)"
  want_in "$dir/awk.calls" "cmd=$CHEZ --libdirs $LIBDIRS --program $after" "the stand-in's calls, so it was the evidence check"
  case $how in
    fails)    verdict "m awk: an awk that fails, printing nothing, fails a clean program, naming the evidence check" ;;
    ok-fails) verdict "m awk: an awk that prints ok, then exits 2, fails a clean program, naming the evidence check" ;;
    *)        verdict "m awk: an awk that exits 0, printing nothing, fails a clean program, naming the evidence check" ;;
  esac
done

# ---- p: a child that reaches native code runs under the gate, which reads its log ----
for how in leak overrun; do
  newtree
  parent=$scratch/child-$how.sps
  line="child-$how: ran its child"
  plain=$("$CHEZ" --libdirs "$LIBDIRS" --program "$parent" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || problem "it exited $rc without Valgrind"
  [ "$plain" = "$line" ] || problem "its output, without Valgrind, is not the one line \"$line\":
$(printf '%s\n' "$plain" | sed 's/^/  | /')"
  verdict "p plain: $parent exits 0 without Valgrind, and prints only its line" plain
done

for how in leak overrun; do
  newtree
  parent=$scratch/child-$how.sps
  gate MEMORY_SUITES="$parent $after"
  status=$?
  want_status nonzero "$status"
  want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "$no_zero")")
test-memory: pass $after
$(count_line 2 1 1 0)"
  want_children "$parent" 1
  want_in "$(vlog_of "$parent")" "ERROR SUMMARY: 0 errors from 0 contexts" "the parent's own Valgrind log, so only the child failed it"
  case $how in
    overrun) markers="Invalid write of size 1
0 bytes after a block of size 23 alloc'd" ;;
    *)       markers="777 bytes in 1 blocks are definitely lost in loss record" ;;
  esac
  markers="$markers
ERROR SUMMARY: 1 errors from 1 contexts"
  clog=$(ls "$(children_of "$parent")"/*.valgrind 2>/dev/null | head -n 1)
  while IFS= read -r m; do
    want_in "${clog:-$(children_of "$parent")/none}" "$m" "the child's Valgrind log"
    want_in "$out" "$m" "test-memory's own output"
  done <<EOF
$markers
EOF
  want_in "$out" "  a child's Valgrind log: $(children_of "$parent")/" "test-memory's own output, naming the child's log"
  verdict "p $how: a child that $( [ $how = leak ] && echo 'leaks 777 bytes' || echo 'overruns a 23-byte block') fails its clean parent, naming the child's log, with Valgrind's report in it and in test-memory's output, and the suite after it runs"
done

newtree
gate MEMORY_SUITES="$scratch/child-clean.sps"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $scratch/child-clean.sps
$(count_line 1 1 0 0)"
want_children "$scratch/child-clean.sps" 1
verdict "p clean: a clean child passes its parent, and leaves its one log"

newtree
gate MEMORY_SUITES="$scratch/child-forkclean.sps"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $scratch/child-forkclean.sps
$(count_line 1 1 0 0)"
want_children "$scratch/child-forkclean.sps" 1
verdict "p fork: a clean child that spawns a process passes, and leaves its one log: Valgrind's log of the fork is silent"

newtree
parent=$scratch/child-forkleak.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status nonzero "$status"
want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "$no_zero")")
$(count_line 1 0 1 0)"
want_children "$parent" 1
want_in "$out" "777 bytes in 1 blocks are definitely lost in loss record" "test-memory's own output"
verdict "p forkleak: a child that spawns a process and then leaks 777 bytes still fails, by name, and leaves its one log"

newtree
gate MEMORY_SUITES="$scratch/child-elsewhere.sps"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $scratch/child-elsewhere.sps
$(count_line 1 1 0 0)"
want_children "$scratch/child-elsewhere.sps" 1
verdict "p elsewhere: a clean child run from another working directory, / here, writes its log where the gate reads it: the log path is absolute"

# ---- q: each child's log is held to the parent's rules ----
newtree
parent=$scratch/child-leak.sps
gate MEMORY_SUITES="$parent" VALGRIND="$scratch/valgrind-childdrop"
status=$?
want_status nonzero "$status"
want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "$(other_options "$(child_options "$parent" | sed 's/ --leak-check=full / /')" "$(child_options "$parent")")")")
$(count_line 1 0 1 0)"
clog=$(ls "$(children_of "$parent")"/*.valgrind 2>/dev/null | head -n 1)
want_in "${clog:-$(children_of "$parent")/none}" "ERROR SUMMARY: 0 errors from 0 contexts" "the child's Valgrind log, so the edit hid the leak"
verdict "q options: a Valgrind that drops --leak-check=full for children alone hides the child's leak, and fails it by name"

newtree
parent=$scratch/child-other.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status nonzero "$status"
want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "Valgrind's Command: line is \"env $CHEZ --program $after\", which begins neither with \"$CHEZ \" nor with a program named libsqlite3-oracle; $(ran_other "$(readlink -f "$(command -v env)")" "$(readlink -f "$(command -v "$CHEZ")")"); $no_zero")")
$(count_line 1 0 1 0)"
verdict "q other: a child whose command begins neither with CHEZ nor with the oracle, here env, which execs Chez away from Valgrind, fails, by name"

newtree
parent=$scratch/child-oracle-leak.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status nonzero "$status"
want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "$no_zero")")
$(count_line 1 0 1 0)"
want_children "$parent" 1
want_in "$out" "777 bytes in 1 blocks are definitely lost in loss record" "test-memory's own output"
verdict "q oracle: a C child named libsqlite3-oracle that loses 777 bytes fails its parent, by name"

newtree
parent=$scratch/child-oracle-clean.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $parent
$(count_line 1 1 0 0)"
want_children "$parent" 1
verdict "q oracle: a C child named libsqlite3-oracle that loses nothing passes, and leaves its one log"

newtree
parent=$scratch/child-oracle-link.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $parent
$(count_line 1 1 0 0)"
want_children "$parent" 1
verdict "q oracle-link: a C child named libsqlite3-oracle, run through a symlinked directory, passes: its program is resolved before it is compared with the file Valgrind ran"

newtree
parent=$scratch/child-forged.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status nonzero "$status"
want_lines_pid "$(zero_line "$parent" "$(child_why "$parent" "$no_zero")")
$(count_line 1 0 1 0)"
verdict "q forged: a child that prints a clean ERROR SUMMARY, then execs away, fails: its own log has none"

newtree
parent=$scratch/child-stale.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status nonzero "$status"
want_children "$parent" 1
cat >"$parent" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh, over its first version: runs no
;;; child.
(import (rnrs))
(display "child-stale: ran no child")
(newline)
(exit 0)
EOF
gate_keep MEMORY_SUITES="$parent"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $parent
$(count_line 1 1 0 0)"
want_children "$parent" 0
verdict "q stale: a child log an earlier run left is never read: the run after it, with no child, passes and leaves none"

newtree
parent=$scratch/child-unwrapped.sps
gate MEMORY_SUITES="$parent"
status=$?
want_status 0 "$status"
want_lines "test-memory: pass $parent
$(count_line 1 1 0 0)"
want_children "$parent" 0
verdict "q unwrapped: a child run without gated-command runs outside Valgrind, and its leak passes: the gap ADR-0005 records"

# ---- r: a suite past three quarters of MEMORY_TIMEOUT ----
# Under a MEMORY_TIMEOUT of 12, a suite is SLOW past 9 s. The slow plant's
# process sleeps until it is 10 s old, so test-memory times it at 10 s or 11;
# the near one's until 7.5 s, so 7 s or 8, just under, or 9 should its exit
# be slow. Each outcome line is followed by its time line, whole but for the
# seconds, which are then held to those bounds: a time line missing, or
# saying within for past, fails.
newtree
per_suite=$slow_timeout
gate MEMORY_SUITES="$slow $nearly"
status=$?
per_suite=$suite_timeout
want_status nonzero "$status"
want_lines "test-memory: SLOW $slow (past 9s under the gate, three quarters of MEMORY_TIMEOUT's 12s)
test-memory: pass $nearly
$(count_line 2 1 0 0 1)"
wanted="test-memory: SLOW $slow (past 9s under the gate, three quarters of MEMORY_TIMEOUT's 12s)
  time: Ns under the gate, past 9s, three quarters of MEMORY_TIMEOUT's 12s
test-memory: pass $nearly
  time: Ns under the gate, within 9s, three quarters of MEMORY_TIMEOUT's 12s
$(count_line 2 1 0 0 1)"
got=$(grep -E '^(test-memory: |  time: )' "$out" | sed -E 's/^  time: [0-9]+s /  time: Ns /')
[ "$got" = "$wanted" ] || problem "make test-memory's outcome and time lines differ:
$(printf '%s\n' "$wanted" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
times=$(sed -n 's/^  time: \([0-9][0-9]*\)s .*/\1/p' "$out" | tr '\n' ' ')
case $times in
  "10 7 " | "10 8 " | "10 9 " | "11 7 " | "11 8 " | "11 9 ") ;;
  *) problem "the plants' times are [$times], not 10 or 11 seconds, then 7 to 9: a plant did not sleep to its age, or the gate timed something else" ;;
esac
want_in "$(log_of "$slow")" "slow: slept until its process was 10 seconds old" "the slow plant's line, so it ran"
want_in "$(log_of "$nearly")" "nearly: slept until its process was 15/2 seconds old" "the near plant's line, so it ran"
verdict "r slow: under a MEMORY_TIMEOUT of 12, a suite that takes 10 s is SLOW, past 9 s, three quarters of it, and fails the run, by name; one that takes 7 s or 8 passes; each one's time line follows its outcome"

# ---- o: ci.yml runs the gate, as tests/check-ci.sh holds it ----
# check-ci holds the whole workflow, the two memory jobs among its jobs: in
# each, make check-memory-gate, then make test-memory MEMORY_SHARD=1 or =2,
# each a step's whole run line, with no if: or continue-on-error: on them or
# their job, and no variable that steers the gate. make test runs it too, so
# a workflow that drops either job still fails CI's main job.
wanted="check-ci: .github/workflows/ci.yml has the one shape check-ci reads"
got=$(cd "$root" && sh tests/check-ci.sh .github/workflows 2>&1)
status=$?
if [ "$status" -ne 0 ] || [ "$got" != "$wanted" ]; then
  problem "tests/check-ci.sh exited $status, printing:
$(printf '%s\n' "$got" | sed 's/^/  | /')"
fi
verdict "o ci: tests/check-ci.sh holds ci.yml, whose jobs memory-1 and memory-2 each run make check-memory-gate, then make test-memory MEMORY_SHARD=1 or =2, with no if:, no continue-on-error: and no variable that steers the gate" plain

if [ "$fail" -eq 0 ]; then
  printf 'check-memory-gate: the memory gate failed, as it must, its refusals held, and each shard ran its own list, in all %d cases\n' "$pass"
fi
[ "$fail" -eq 0 ]
