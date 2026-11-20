#!/bin/sh
# check-memory-shards: hold the memory gate's two shards, the Makefile's
# MEMORY_SUITES_1 and MEMORY_SUITES_2, to every suite once between them
# (ADR-0005).
#
#   sh tests/check-memory-shards.sh SUITES ONE TWO
#
# Each argument is a list of paths, split at white space: SUITES the tree's
# suites, every tests/test-*.sps, as make check-memory-shards hands them,
# never a run's narrowed SUITES, and ONE and TWO the two shards,
# which CI's jobs memory-1 and memory-2 run under Valgrind with make
# test-memory MEMORY_SHARD=1 and =2. On a pass it prints one line on stdout
# and exits 0. On a failure it prints each problem on stderr, as
# "check-memory-shards: PROBLEM", then "check-memory-shards: FAILED
# (problems: N)", and exits 1. A usage error exits 2. It fails on:
#
#   - a suite in neither list, which no memory job would run under the gate:
#     so a new suite fails make test here until it is put in a shard;
#   - a suite in both lists, which both jobs would run;
#   - a suite written twice in one list;
#   - a path in a list that is no suite of SUITES, a suite since removed, or
#     one spelt another way: the job would run it, or fail on it, and the
#     suite it meant would run in neither.
#
# Paths are compared as text, so ./tests/test-x.sps is not tests/test-x.sps.
# The problems come in SUITES' order, a suite's own in the order above, then
# each list's strays, in the list's order, each once. Neither list must hold
# a suite: test-memory refuses a shard that names none.
#
# Every rule is held by a row of tests/test-check-memory-shards.sps, and
# tests/check-test-fails.sh holds that make test runs it on the Makefile's
# own lists.

usage() {
  printf 'check-memory-shards: usage: sh tests/check-memory-shards.sh SUITES ONE TWO\n' >&2
  exit 2
}

[ $# -eq 3 ] || usage

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-memory-shards.XXXXXX") || {
  printf 'check-memory-shards: cannot make a scratch directory\n' >&2
  exit 1
}
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# The lists reach awk through its environment, which takes them as they are:
# awk -v would read a backslash in one as an escape.
SHARDS_SUITES=$1 SHARDS_ONE=$2 SHARDS_TWO=$3 LC_ALL=C awk '
function prob(m) { printf "check-memory-shards: %s\n", m; n++ }

BEGIN {
  ns = split(ENVIRON["SHARDS_SUITES"], suite, " ")
  for (i = 1; i <= ns; i++) issuite[suite[i]] = 1
  name[1] = "MEMORY_SUITES_1"; name[2] = "MEMORY_SUITES_2"
  nl[1] = split(ENVIRON["SHARDS_ONE"], l1, " ")
  nl[2] = split(ENVIRON["SHARDS_TWO"], l2, " ")
  for (i = 1; i <= nl[1]; i++) { item[1, i] = l1[i]; count[1, l1[i]]++ }
  for (i = 1; i <= nl[2]; i++) { item[2, i] = l2[i]; count[2, l2[i]]++ }

  for (i = 1; i <= ns; i++) {
    t = suite[i]; a = count[1, t] + 0; b = count[2, t] + 0
    if (a == 0 && b == 0)
      prob(t " is in neither MEMORY_SUITES_1 nor MEMORY_SUITES_2, so no memory job runs it under the gate: add it to the shard whose suites take less time (Makefile; ADR-0005)")
    if (a > 0 && b > 0)
      prob(t " is in both MEMORY_SUITES_1 and MEMORY_SUITES_2, so both memory jobs run it: keep it in one")
    if (a > 1) prob(t " is in MEMORY_SUITES_1 " a " times: write it once")
    if (b > 1) prob(t " is in MEMORY_SUITES_2 " b " times: write it once")
  }

  for (k = 1; k <= 2; k++) {
    split("", told)
    for (i = 1; i <= nl[k]; i++) {
      t = item[k, i]
      if ((t in issuite) || (t in told)) continue
      told[t] = 1
      prob(name[k] " names " t ", which is not one of the suites make test runs: remove it, or spell it as make test does, tests/test-NAME.sps")
    }
  }

  if (n == 0) printf "ok %d\n", ns
}' >"$tmp/out" 2>"$tmp/err"
status=$?

if [ "$status" -ne 0 ]; then
  printf 'check-memory-shards: the check (awk) exited %s: %s\n' "$status" "$(cat "$tmp/err")" >&2
  printf 'check-memory-shards: FAILED (problems: 1)\n' >&2
  exit 1
fi

# A pass is awk's one line "ok N", N the suites' count, and nothing else.
verdict=$(cat "$tmp/out")
case $verdict in
  "ok " | "ok "*[!0-9]*) ;;
  "ok "*)
    printf 'check-memory-shards: MEMORY_SUITES_1 and MEMORY_SUITES_2 run each of the %s suites once between them\n' "${verdict#ok }"
    exit 0 ;;
esac

# Otherwise each problem awk told, and each line it printed that is neither
# a problem nor its verdict, told as one: an awk that prints nothing fails.
grep '^check-memory-shards: ' "$tmp/out" >"$tmp/problems"
grep -v '^check-memory-shards: ' "$tmp/out" >"$tmp/other"
while IFS= read -r other; do
  printf 'check-memory-shards: the check (awk) printed "%s", which is neither a problem nor its verdict\n' "$other" >>"$tmp/problems"
done <"$tmp/other"
[ -s "$tmp/problems" ] || printf 'check-memory-shards: the check (awk) printed nothing\n' >"$tmp/problems"
cat "$tmp/problems" >&2
printf 'check-memory-shards: FAILED (problems: %s)\n' "$(wc -l <"$tmp/problems" | tr -d ' ')" >&2
exit 1
