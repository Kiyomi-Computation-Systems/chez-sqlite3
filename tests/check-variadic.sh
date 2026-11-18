#!/bin/sh
# tests/check-variadic.sh, run by `make check-variadic` (ADR-0001, amended
# 2026-11-17; ADR-0021, decision 4; the M4 plan, section 4.2).
#
#   sh tests/check-variadic.sh
#
# Why it exists. native binds sqlite3_db_config, a variadic C function,
# with Chez's __varargs_after convention and a count of 2. Where an ABI
# passes variadic arguments as it passes named ones, x86-64 and Linux arm64,
# the binding answers alike without it, so no behaviour row on CI could
# notice the convention gone. test-conventions reads the form instead. This
# script shows that it notices: it works on a scratch copy of the tree this
# file sits in, and nothing it does touches that tree.
#
# What it does, in order. A step that passes prints "check-variadic: ok
# STEP: ..." on stdout; one that fails prints "check-variadic: FAILED STEP:
# ..." on stderr, with the evidence. Where a later step could say nothing,
# the run ends there, "stopped after ...".
#
#   copy     the tree's src/, tests/ and .plans/decisions/, which the two
#            suites read, into a directory under TMPDIR. The suites find
#            SRFI-64 in the tree's own build/scheme-libs, so `make deps` must
#            have run.
#   machine  the machine type, as CHEZ itself answers (machine-type): the
#            ABI is Chez's, so a Chez under Rosetta, ta6osx, is x86-64 on
#            an arm64 Mac. uname is never read.
#   control  the copy, unchanged, passes tests/test-conventions.sps and
#            tests/test-native.sps. Passing is exit 0, no FAIL line, and the
#            runner's count of passes, all three.
#   mutant   the convention's text stands on exactly one line of the copy's
#            native.sls; sed deletes it there, with the space after it; then
#            no line holds it, and that line is the only one that changed.
#   static   on the mutant, test-conventions exits 1; the tests it names as
#            failing are exactly the ten listed in expected_failures, in that
#            order; and its row "src: no violation" shows one violation,
#            ((mismatch "sqlite3_db_config" convention variadic plain)).
#   arm64    on arm64osx or tarm64osx only: test-native, on the mutant, must
#            fail, either naming a failing test that holds sqlite3_db_config,
#            the binding the mutant broke, or by dying, an exit past 128.
#            Exit 0, a hang (124), and a failure naming no such test while
#            exiting below 129, each fail the step.
#   other    anywhere else: test-native runs on the mutant, and what it did
#            is reported, never failed.
#
# Exit 0 when every step is ok, with a last line saying so; 1 when one
# failed; 2 for an argument, which it takes none of.
#
# make test does not run it: inside make test it would also run inside each
# of check-test-fails' cases, under their 5 s suite timeout. CI's main job
# runs it as a step of its own; the Mac's hand run runs it by hand, the one
# place the arm64 step bites. make check-variadic hands it CHEZ, TIMEOUT and
# TEST_TIMEOUT; run directly, it uses scheme, timeout and 300 s.
# tests/test-check-variadic.sps exercises every branch with stand-ins for
# CHEZ, TIMEOUT and sed, and holds the list of ten to test-conventions' own
# tests. Portable sh for macOS's tools as well as GNU's: awk does the line
# work, sed only the mutation.
set -o nounset
export LC_ALL=C

prog=check-variadic
if [ "$#" -gt 0 ]; then
  echo "$prog: usage: sh tests/check-variadic.sh" >&2
  exit 2
fi

chez=${CHEZ:-scheme}
bound=${TIMEOUT:-timeout}
limit=${TEST_TIMEOUT:-300}

here=$(dirname -- "$0")
tree=$(cd -- "$here" && cd .. && pwd) || {
  echo "$prog: cannot find the tree this script sits in" >&2
  exit 1
}

oks=0
fails=0

# say TEXT: one line of the run's account, on stdout.
say() { printf '%s\n' "$prog: $*"; }

# passed STEP-TEXT and failed STEP-TEXT: a step's verdict.
passed() {
  oks=$((oks + 1))
  say "ok $*"
}
failed() {
  fails=$((fails + 1))
  say "FAILED $*" >&2
}

# give_up STEP-TEXT: a failed step after which nothing more can be shown.
give_up() {
  failed "$@"
  say "stopped after $oks ok, $fails FAILED" >&2
  exit 1
}

# expected_failures: the tests of test-conventions that fail on the mutant,
# one name a line, in the suite's own order. They are the ten that hold the
# whole convention table, the variadic row among it, to the real src/, its
# row "src: no violation" and its nine sweeps; nothing else in the suite
# reads src/'s forms against the table. test-check-variadic holds this list
# to the suite's own tests, so renaming one moves it.
expected_failures() {
  cat <<'TEN'
src: no violation: each form is a literal binding held to its row, and each row has its form
sweep: a row removed fails, by name, for each of the 44 rows
sweep: a row with no form fails, by name
sweep: a row's convention flipped fails, by name, for each of the 44 rows: plain to collect-safe, and collect-safe and variadic to plain
sweep: sqlite3_db_config's row made plain, and made collect-safe, each fails, by name, against the real src/
sweep: a row's result type changed fails, by name, for each of the 44 rows: int to uptr, and uptr, integer-64, double and void to int
sweep: sqlite3_memory_used's and sqlite3_column_int64's results, integer-64, and sqlite3_bind_int64's third argument, changed to int, each fail, by name (the M2 plan, section 4.8)
sweep: M3's five made __collect_safe each fail, by name: a binding that held the lock-free counters or the interrupt through a collection would let another thread's collection wait on them
sweep: sqlite3_changes64's, sqlite3_total_changes64's and sqlite3_last_insert_rowid's results, integer-64, changed to int, sqlite3_get_autocommit's, int, changed to integer-64, and sqlite3_interrupt's, void, changed to int, each fail, by name
sweep: a row's argument type changed at each position fails, by name, for each of the 75 arguments
TEN
}

marker='(__varargs_after 2)'
native_rel=src/chez-sqlite3/private/native.sls
row_src='src: no violation: each form is a literal binding held to its row, and each row has its form'
row_src_actual='  actual:   ((mismatch "sqlite3_db_config" convention variadic plain))'
conventions=tests/test-conventions.sps
native_suite=tests/test-native.sps

# ---- step: copy ----------------------------------------------------------
libs=$tree/build/scheme-libs
if [ ! -d "$libs/srfi" ]; then
  give_up "copy: build/scheme-libs/srfi is missing; run make deps"
fi

top=${TMPDIR:-/tmp}
top=${top%/}
scratch=$(mktemp -d "$top/check-variadic.XXXXXX" 2>/dev/null) ||
  give_up "copy: mktemp -d failed under $top"
if [ "$(printf '%s\n' "$scratch" | awk 'END { print NR }')" -ne 1 ]; then
  give_up "copy: mktemp gave more than one line"
fi
case $scratch in
  /*) [ -d "$scratch" ] || give_up "copy: mktemp gave $scratch, no directory" ;;
  *) give_up "copy: mktemp gave $scratch, no absolute path" ;;
esac
trap 'rm -rf -- "$scratch"' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15

work=$scratch/tree
log=$scratch/run.log
if mkdir -p -- "$work/.plans" &&
   cp -R -P -- "$tree/src" "$tree/tests" "$work" &&
   cp -R -P -- "$tree/.plans/decisions" "$work/.plans" &&
   cp -- "$work/$native_rel" "$scratch/native.orig"; then
  passed "copy: src/, tests/ and .plans/decisions/ copied to a scratch tree"
else
  give_up "copy: src/, tests/ and .plans/decisions/ could not be copied to a scratch tree"
fi

# ---- the pieces each later step uses ---------------------------------------

# suite NAME: tests/NAME.sps run in the copy, as make test runs a suite;
# its output in $log, its exit status in $rc.
suite() {
  (cd -- "$work" &&
    exec "$bound" --foreground "$limit" "$chez" --libdirs "src:tests:$libs" --program "tests/$1.sps") \
    >"$log" 2>&1
  rc=$?
}

# failures: the lines of $log that name a failing test.
failures() { grep -e '^FAIL ' -- "$log" || :; }

# counted: whether $log holds the runner's count of passes.
counted() { grep -q -e '^# of expected passes ' -- "$log"; }

# actual_for NAME: the line holding the actual value the runner printed for
# the failing test NAME, two lines after its FAIL line.
actual_for() {
  awk -v want="FAIL $1" 'hit == 2 { print; exit } hit == 1 { hit = 2; next } $0 == want { hit = 1 }' "$log"
}

# holding TEXT FILE: how many lines of FILE hold TEXT, as a fixed string.
holding() { grep -c -F -e "$1" -- "$2" || :; }

# changed_between A B: how many lines differ between A and B, place by
# place, a line that one has and the other lacks counted too.
changed_between() {
  awk -v other="$2" '{ if ((getline theirs < other) <= 0 || theirs != $0) n++ }
    END { while ((getline theirs < other) > 0) n++; print n + 0 }' "$1"
}

# show_run: $log, each line after "  | ", on stderr.
show_run() { awk '{ print "  | " $0 }' "$log" >&2; }

# list_failures: the failing tests $log names, indented, on stdout.
list_failures() { failures | awk '{ print "  " $0 }'; }

# account: what the run that left $log and $rc did, in words.
account() {
  count=$(failures | awk 'END { print NR }')
  death=
  if [ "$rc" -eq 255 ]; then
    death="dying by an uncaught raise (exit 255)"
  elif [ "$rc" -gt 128 ]; then
    death="dying by signal $((rc - 128))"
  fi
  if [ "$count" -gt 0 ]; then
    printf 'naming %s failing tests%s' "$count" "${death:+, then $death}"
  elif [ -n "$death" ]; then
    printf '%s, naming no test' "$death"
  elif [ "$rc" -eq 124 ]; then
    printf 'hanging: no exit within %ss' "$limit"
  else
    printf '%s' "naming no test"
  fi
}

# ---- step: machine -----------------------------------------------------------
printf '(display (machine-type))\n(newline)\n' >"$scratch/machine.ss"
"$bound" --foreground "$limit" "$chez" --script "$scratch/machine.ss" >"$log" 2>&1
rc=$?
machine=$(awk 'NR == 1 && /^[a-z0-9]+$/ { type = $0 } END { if (NR == 1) print type }' "$log")
if [ "$rc" -ne 0 ] || [ -z "$machine" ]; then
  show_run
  give_up "machine: $chez --script printing (machine-type) must exit 0, printing one machine type alone on one line; it exited $rc"
fi
apple=no
for arm in arm64osx tarm64osx; do
  if [ "$machine" = "$arm" ]; then apple=yes; fi
done
passed "machine: Chez's machine type is $machine"

# ---- step: control -----------------------------------------------------------
for name in test-conventions test-native; do
  suite "$name"
  if [ "$rc" -eq 0 ] && [ -z "$(failures)" ] && counted; then
    passed "control: tests/$name.sps passes on the unchanged copy (exit 0)"
  else
    show_run
    give_up "control: tests/$name.sps must pass on the unchanged copy, by exit 0, no FAIL line and the runner's count of passes; it exited $rc, $(account), so nothing below would say anything about the mutation"
  fi
done

# ---- step: mutant ------------------------------------------------------------
before=$(holding "$marker" "$scratch/native.orig")
[ "$before" -eq 1 ] || give_up "mutant: $marker stands on $before lines of $native_rel, not one"
sed -e "s/$marker //" "$scratch/native.orig" >"$scratch/native.mut" ||
  give_up "mutant: sed failed on $native_rel"
cp -- "$scratch/native.mut" "$work/$native_rel" ||
  give_up "mutant: could not write the copy's $native_rel"
after=$(holding "$marker" "$work/$native_rel")
diffs=$(changed_between "$scratch/native.orig" "$work/$native_rel")
if [ "$diffs" -eq 1 ] && [ "$after" -eq 0 ]; then
  passed "mutant: $marker stood on one line of $native_rel; removed, it stands on none, and no other line changed"
else
  give_up "mutant: removing $marker changed $diffs lines of $native_rel and left it on $after; it must change one line and leave it on none"
fi

# ---- step: static ------------------------------------------------------------
static_claim="$conventions fails on the mutant (exit 1), naming exactly the ten tests that hold the table to src/, its violations exactly ((mismatch \"sqlite3_db_config\" convention variadic plain))"
suite test-conventions
expected_failures >"$scratch/want.names"
failures | awk '{ print substr($0, 6) }' >"$scratch/got.names"
seen=$(actual_for "$row_src")
why=$scratch/why
: >"$why"
if [ "$rc" -ne 1 ]; then
  printf '  it exited %s, not 1, %s\n' "$rc" "$(account)" >>"$why"
fi
if ! cmp -s -- "$scratch/want.names" "$scratch/got.names"; then
  {
    echo "  the tests it named differ:"
    awk '{ print "    wanted: FAIL " $0 }' "$scratch/want.names"
    if [ -s "$scratch/got.names" ]; then
      awk '{ print "    got:    FAIL " $0 }' "$scratch/got.names"
    else
      echo "    got:    "
    fi
  } >>"$why"
fi
if [ "$seen" != "$row_src_actual" ]; then
  printf '  its violations differ:\n    wanted: %s\n    got:    %s\n' "$row_src_actual" "$seen" >>"$why"
fi
if [ -s "$why" ]; then
  failed "static: $conventions must fail on the mutant, exit 1, naming exactly the ten tests that hold the table to src/, its violations exactly ((mismatch \"sqlite3_db_config\" convention variadic plain))"
  cat -- "$why" >&2
  show_run
else
  passed "static: $static_claim"
fi

# ---- step: arm64, or other -----------------------------------------------------
suite test-native
if [ "$apple" = yes ]; then
  through=$(failures | grep -c -F -e sqlite3_db_config || :)
  shown=no
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
    if [ "$through" -gt 0 ] || [ "$rc" -gt 128 ]; then shown=yes; fi
  fi
  if [ "$shown" = yes ]; then
    passed "arm64: on $machine, $native_suite fails on the mutant (exit $rc), $(account)"
    list_failures
  else
    failed "arm64: on $machine, $native_suite must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited $rc, $(account)"
    show_run
  fi
elif [ "$rc" -eq 0 ]; then
  passed "other: on $machine, $native_suite passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation by behaviour"
else
  passed "other: on $machine, $native_suite fails on the mutant (exit $rc), $(account); reported, never failed: only Apple arm64 is required to show the mutation by behaviour"
  list_failures
fi

# ---- the verdict ---------------------------------------------------------------
if [ "$fails" -gt 0 ]; then
  say "$oks ok, $fails FAILED" >&2
  exit 1
fi
say "all $oks steps ok, on $machine"
