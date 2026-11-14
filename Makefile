# chez-sqlite3
#
# On a Guix host, run targets through the container (ADR-0006):
#   scripts/guix-env make <target>

# The Chez binary. In the container, scripts/guix-env-enter exports the
# profile's real `scheme` binary. Elsewhere it is `scheme` on PATH, or else
# `chez`, the name Homebrew installs it under on macOS. Exported, so that a
# suite which spawns Chez spawns this one.
CHEZ ?= $(or $(if $(shell command -v scheme 2>/dev/null),scheme),$(if $(shell command -v chez 2>/dev/null),chez),scheme)
export CHEZ

# The make target to name in a missing-tool hint (scripts/require-tools):
# what the user typed, $(MAKECMDGOALS), or, when that is empty, the
# recipe's own target, $@. Recursively expanded (=, not :=), so each
# reference picks up whichever recipe is running it.
GOAL = $(strip $(if $(MAKECMDGOALS),$(MAKECMDGOALS),$@))

# chez-srfi, which supplies SRFI-64, is a git submodule pinned in Akku.lock
# (ADR-0007). `make deps` links it into SRFI_LIBS, for Chez's library path
# (LIBDIRS) to name.
SRFI_SRC  := vendor/chez-srfi
SRFI_LIBS := build/scheme-libs

# Chez's library path for the suites: src/ holds chez-sqlite3's own
# libraries, (chez-sqlite3 private ...) among them, and tests/ holds
# (chez-sqlite3-testing).
LIBDIRS := src:tests:$(SRFI_LIBS)

# Every suite, in one order everywhere: make 3.82 to 4.2 leave $(wildcard)
# unsorted.
SUITES := $(sort $(wildcard tests/test-*.sps))

# Seconds a suite may run before timeout kills it and make test names it
# HUNG. make test refuses any value but a positive whole number: GNU timeout
# reads 0 as no limit at all.
TEST_TIMEOUT ?= 300

# GNU timeout. Homebrew's coreutils installs it as gtimeout on macOS.
TIMEOUT ?= $(or $(shell command -v timeout 2>/dev/null),$(shell command -v gtimeout 2>/dev/null),timeout)

# The memory gate (ADR-0005): Valgrind, and the seconds a suite may run
# under it before timeout kills it and make test-memory names it HUNG.
# Valgrind runs 10 to 50 times slower than Chez alone. Most suites take 7 to
# 12 s under it in the container (.plans/research/memory-gate/). The exception
# is tests/test-library-loading.sps, whose 55 children each run under a
# Valgrind of their own: 230 s in the container, 308 s on CI (run
# 43609564593), against 6 s without it. 600 s is about twice that, and far
# below CI's 60-minute job limit, so a hang is named HUNG before the job is
# killed. make test-memory refuses a MEMORY_TIMEOUT that is
# not a positive whole number, as make test refuses such a TEST_TIMEOUT.
VALGRIND ?= valgrind
MEMORY_TIMEOUT ?= 600

# The suites make test-memory runs: every suite, unless a run names others.
MEMORY_SUITES ?= $(SUITES)

# Where make test-memory writes each suite's logs: <suite>.log, the suite's
# own output, and <suite>.valgrind, Valgrind's.
MEMORY_LOGS := build/memory

# One physical line: check-help reads it with awk, and fails if it ends in
# a backslash.
.PHONY: help check-help check-guix check-guix-inside deps build dev check-dev check-pins test check-suites check-seam check-floors check-ci check-nothreads check-test-fails test-memory check-memory-gate clean check-clean

.DEFAULT_GOAL := help

# The name column is as wide as the longest target's name.
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { n++; name[n] = $$1; text[n] = $$2; if (length($$1) > width) width = length($$1) } \
	  END { format = "  \033[36m%-" width "s\033[0m %s\n"; \
	        for (i = 1; i <= n; i++) printf format, name[i], text[i] }' $(MAKEFILE_LIST)

# Reads what `make help` prints, colour codes stripped, so it checks the
# listing itself. Both directions: every .PHONY target is listed, and every
# listed target is in .PHONY. A listed target left out of .PHONY silently
# stops running once a file of its name exists.
check-help: ## Fail unless `make help` lists exactly the .PHONY targets
	@status=0; \
	if grep -qE '^\.PHONY:.*\\$$' Makefile; then \
	  echo "check-help: the .PHONY line ends in a backslash; keep it on one line" >&2; \
	  status=1; \
	fi; \
	help=$$($(MAKE) --no-print-directory help) || { \
	  echo "check-help: make help failed" >&2; \
	  exit 1; \
	}; \
	esc=$$(printf '\033'); \
	listed=$$(printf '%s\n' "$$help" | sed "s/$$esc\[[0-9;]*m//g" | awk '{ print $$1 }'); \
	phony=$$(awk '/^\.PHONY:/ { $$1 = ""; print }' Makefile); \
	for t in $$phony; do \
	  printf '%s\n' $$listed | grep -qxF "$$t" || { \
	    echo "check-help: make help does not list .PHONY target '$$t'; give it a '## ' description on its target line" >&2; \
	    status=1; \
	  }; \
	done; \
	for t in $$listed; do \
	  printf '%s\n' $$phony | grep -qxF "$$t" || { \
	    echo "check-help: make help lists '$$t', which is not in .PHONY" >&2; \
	    status=1; \
	  }; \
	done; \
	exit $$status

check-guix: ## Test scripts/guix-env on the host, then the toolchain inside the container
	@scripts/require-tools "$(GOAL)" guix
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env make check-guix-inside

check-guix-inside: ## (inside the container) Assert the pinned toolchain, isolation and loopback-only network
	@CHEZ='$(CHEZ)' CC='$(CC)' sh scripts/guix-env-selftest

# Links vendor/chez-srfi into build/scheme-libs/srfi, and never fetches: the
# container has no network (ADR-0006), so an empty submodule is filled on the
# host. chez-srfi ships Akku's percent-encoded filenames (%3a64.sls) and Chez
# resolves (srfi :64) only from the decoded spelling (:64.sls), so every entry
# is linked under both and the submodule's own tree is left alone. It always
# relinks. `ln -sfn` replaces a link in place, and the -n is what stops it
# following an existing link to a directory into the submodule. A rerun
# changes nothing, and `set -e` keeps a failed link from hiding behind the
# loop's last iteration. Every path is quoted, since the checkout's may hold
# a space.
deps: ## Link vendor/chez-srfi into build/scheme-libs; never fetches
	@if [ ! -f $(SRFI_SRC)/%3a64.sls ]; then \
	  echo "deps: $(SRFI_SRC)/%3a64.sls not found, so the submodule is empty or missing. Run 'git submodule update --init $(SRFI_SRC)' on the host: make deps never fetches, and the container has no network." >&2; \
	  exit 1; \
	fi
	@mkdir -p $(SRFI_LIBS)/srfi
	@set -e; \
	src="$(abspath $(SRFI_SRC))"; dst="$(abspath $(SRFI_LIBS))/srfi"; \
	for f in "$$src"/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done
	@echo "deps: $(SRFI_SRC) linked into $(SRFI_LIBS)/srfi"

# Loads libsqlite3 as chez-sqlite3 would, through tests/preflight.sps, and
# names it: its path and source, its version and number, and its source id.
# A refused libsqlite3 fails it, exit 1, with the reason, the path, the
# detail, the candidates checked and a remedy, and, when the refusal came
# after the version was read, that library's own report. Its last line, on
# either stream, is its counts, all zero (ADR-0005, decision 4);
# tests/test-library-loading.sps holds the whole output. chez-sqlite3
# compiles nothing (ADR-0001), so this is the question an install asks. It
# writes nothing: no build output, under src/ or anywhere. build is in
# .PHONY: the build/ directory exists, and without it make would answer that
# build is up to date and run nothing. make test does not depend on it.
build: ## Load libsqlite3 as chez-sqlite3 would and name it; fail with the reason when it is refused
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs src --program tests/preflight.sps

# Runs make deps and make build, then a REPL with the suites' library path:
# chez-sqlite3's own libraries, (chez-sqlite3-testing) and SRFI-64. A refused
# libsqlite3 stops make at build, before any REPL starts. Until M1 slice 4
# there is no public library: import (chez-sqlite3 private native) to load.
dev: deps build ## Start a REPL with the suites' library path, after make build; a refused libsqlite3 stops it
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs $(LIBDIRS)

# Runs make dev through make, in a fresh copy of the tree with no build/, with
# forms piped into its REPL. It requires build's report, the banner, and two
# lines those forms print only once (chez-sqlite3 private native), its report's
# library, (chez-sqlite3-testing) and (srfi :64) have imported, naming the
# version and path build named. With CHEZ_SQLITE3_LIBRARY naming no file, make
# dev must fail with build's refusal before any REPL starts
# (tests/check-dev.sh).
check-dev: ## Fail unless make dev runs build, then a REPL with the suites' libraries; a refused libsqlite3 must stop it
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' sh tests/check-dev.sh

# Three places name the chez-srfi commit, and nothing else keeps them equal:
# Akku.lock (what a consumer installs), the gitlink the superproject records
# (what a clone checks out) and the submodule's checkout (what the tests
# import). The gitlink and the checkout move separately: `git checkout` in the
# submodule moves the checkout, `git add` moves the gitlink, and `git
# submodule update` undoes the first, so each is read. The lock names a short
# commit (Akku's `akku.N.<short>`), so it is compared as a prefix, and a
# prefix shorter than seven digits is not read at all: an empty or one-digit
# one would match every commit. An empty or half-made submodule directory is
# no error to git, which answers there for the superproject, so the checkout
# counts only when git's toplevel for it is that directory itself. Read-only.
# It needs git, which the container does not have: run it on the host and in
# CI. `make test` does not run it.
check-pins: ## Fail unless Akku.lock, the gitlink and the checkout name one chez-srfi commit
	@scripts/require-tools "$(GOAL)" git
	@lock=$$(sed -n 's#.*/chez-srfi_[^"]*-akku\.[0-9]*\.\([a-f0-9]\{7,40\}\)_repack.*#\1#p' Akku.lock | head -n 1); \
	rec=$$(git ls-files -s -- $(SRFI_SRC) | awk '$$1 == "160000" && $$3 == 0 { print $$2 }'); \
	top=$$(git -C $(SRFI_SRC) rev-parse --show-toplevel 2>/dev/null); \
	want=$$(cd $(SRFI_SRC) 2>/dev/null && pwd -P); \
	fail=0; drift=0; \
	if [ -z "$$lock" ]; then \
	  echo "check-pins: could not read a chez-srfi commit from Akku.lock" >&2; \
	  exit 1; \
	fi; \
	if [ -z "$$rec" ]; then \
	  echo "check-pins: could not read the commit the superproject records for $(SRFI_SRC) (is it a git submodule, and is this a git checkout?)" >&2; \
	  fail=1; \
	else \
	  case "$$rec" in \
	    "$$lock"*) ;; \
	    *) echo "check-pins: PIN DRIFT: Akku.lock names $$lock, but the superproject records $$rec for $(SRFI_SRC)." >&2; \
	       fail=1; drift=1 ;; \
	  esac; \
	fi; \
	if [ -z "$$top" ] || [ "$$top" != "$$want" ]; then \
	  echo "check-pins: $(SRFI_SRC) is not checked out. Run 'git submodule update --init $(SRFI_SRC)' on the host." >&2; \
	  fail=1; \
	elif ! out=$$(git -C $(SRFI_SRC) rev-parse HEAD 2>/dev/null) || [ -z "$$out" ]; then \
	  echo "check-pins: could not read the commit checked out in $(SRFI_SRC)" >&2; \
	  fail=1; \
	else \
	  case "$$out" in \
	    "$$lock"*) ;; \
	    *) echo "check-pins: PIN DRIFT: Akku.lock names $$lock, but $(SRFI_SRC) is checked out at $$out." >&2; \
	       fail=1; drift=1 ;; \
	  esac; \
	fi; \
	if [ "$$drift" -eq 1 ]; then \
	  echo "check-pins: Bump the submodule and Akku.lock together (ADR-0007). To restore the recorded checkout, run 'git submodule update --init $(SRFI_SRC)' on the host." >&2; \
	fi; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "check-pins: chez-srfi $$lock: Akku.lock, the recorded commit and the checkout agree"; \
	fi; \
	exit $$fail

# Runs every suite, after a failure too, each under timeout, and fails if any
# failed or hung, or if none matched. --foreground keeps a suite in make's
# process group, so Ctrl-C at a terminal reaches it at once, and does not
# wait out the timeout. `make check-test-fails` proves the loop fails. The
# checks come first: check-help, check-suites, check-seam, check-floors and check-ci each
# stop it.
test: deps check-help check-suites check-seam check-floors check-ci ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@case '$(TEST_TIMEOUT)' in \
	  '' | *[!0-9]* | 0*) \
	    echo "test: TEST_TIMEOUT is '$(TEST_TIMEOUT)', not a positive whole number of seconds" >&2; \
	    exit 2 ;; \
	esac
	@if [ -z "$(SUITES)" ]; then \
	  echo "test: no suites: nothing matches tests/test-*.sps" >&2; \
	  exit 1; \
	fi; \
	passed=0; failed=0; hung=0; \
	for t in $(SUITES); do \
	  echo "=== $$t"; \
	  $(TIMEOUT) --foreground $(TEST_TIMEOUT) $(CHEZ) --libdirs $(LIBDIRS) --program $$t; \
	  rc=$$?; \
	  if [ $$rc -eq 0 ]; then \
	    echo "test: pass $$t"; passed=$$((passed + 1)); \
	  elif [ $$rc -eq 124 ]; then \
	    echo "test: HUNG $$t (no exit within $(TEST_TIMEOUT)s)"; hung=$$((hung + 1)); \
	  else \
	    echo "test: FAIL $$t (exit $$rc)"; failed=$$((failed + 1)); \
	  fi; \
	done; \
	echo "test: ran $$((passed + failed + hung)), passed $$passed, failed $$failed, hung $$hung"; \
	[ $$failed -eq 0 ] && [ $$hung -eq 0 ]

# Reads every suite as data and fails unless each one's last datum is the
# shared exit form, (chez-sqlite3-testing)'s suite-exit-form, and no datum
# before it holds an exit form but (exit 1), naming each suite that breaks
# either rule (tests/check-suites.sps). With no suite it passes: make test
# fails that case itself.
check-suites: deps ## Fail unless every tests/test-*.sps ends with the shared exit form
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/check-suites.sps $(SUITES)

# Holds README.org's Requirements section, and every file under
# .github/workflows and scripts/ci, to packaging/floors.sexp, the one file that
# writes the floors (ADR-0008, tests/check-floors.sps): the README must state
# them, and no workflow or CI script may. It needs no deps: (floors) imports
# only (rnrs) and a few of Chez's own bindings.
check-floors: ## Fail unless README.org states the floors in packaging/floors.sexp, and no workflow or CI script does
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org .github/workflows scripts/ci

# Reads every library under src/ as data, and fails on any that breaks the
# seam (ADR-0009, amended): a library outside (chez-sqlite3) and
# (chez-sqlite3 private ...), an import off the allowlists, a name of
# (chezscheme) that only some libraries may import, a re-export of one, a
# macro that could carry one out, a library off its name's path or sharing a
# file. It reads src/ alone: tests and (chez-sqlite3-testing) import private
# libraries. tests/test-check-seam.sps holds each rule on a fixture tree, and
# tests/check-test-fails.sh holds that make test runs it, on src/. It imports
# only (rnrs) and a few of Chez's own bindings, so it needs no deps.
check-seam: ## Fail unless every library under src/ keeps to the seam: the family, the import lists and the names only some libraries may import
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --program tests/check-seam.sps src

# Holds .github/workflows/ci.yml to the one shape tests/check-ci.sh reads
# (ADR-0005, ADR-0001 and ADR-0008, amended in M0 slice 4): its triggers, its
# three jobs and every key in them, each check as a step's whole run line, no
# if: but the cache's own, no variable that steers a check, and no key
# spelled so that a text check would miss it. make test runs it, so every
# make test, the container's self-test and CI's main job among them, holds
# the workflow. tests/test-check-ci.sps plants each fault in a copy of the
# real file. It reads text with sh and awk, and needs no deps.
check-ci: ## Fail unless .github/workflows/ci.yml has the one shape tests/check-ci.sh reads
	@sh tests/check-ci.sh .github/workflows

# Imports every library under src/, private ones too, and requires each
# import to be refused, by name, as (chez-sqlite3 private require-threaded)
# refuses a Chez that is not threaded: a syntax violation from chez-sqlite3,
# whose message starts with the refusal's marker. Every library under src/
# imports require-threaded first (ADR-0001, amended), so every one must be
# refused, and M0 has no public library yet. It fails if it finds no
# library, and names each one that loaded or raised something else
# (tests/check-nothreads.sps). tests/test-check-nothreads.sps holds each rule
# on a fixture tree. On the threaded Chez that make test runs, every import
# loads, so this FAILS there, naming each library: that is its red run, and
# why make test does not run it. CI runs it on a Chez built with --nothreads
# (.github/workflows/ci.yml). It imports only (rnrs) and a few of Chez's own
# bindings, so it needs no deps.
check-nothreads: ## Fail unless every library under src/ refuses to import, by name, on this Chez; CI runs it on a --nothreads Chez
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --program tests/check-nothreads.sps src

# Plants bad suites, a leaking one among them, and a README that disagrees
# with the floors file, one at a time, in a copy of the tree, and requires
# make test to fail on each by name. tests/check-test-fails.sh lists the
# plants. The copy has no .git, so nothing in it runs git.
check-test-fails: ## Plant bad suites, none at all, a stale README and a bad workflow, in a copy; make test must fail on each, by name
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' sh tests/check-test-fails.sh

# Runs every MEMORY_SUITES suite under Valgrind, in order, each under
# timeout, and goes on after a failure (ADR-0005). timeout wraps Valgrind
# and never sits between it and Chez: Valgrind checks only the command it
# is handed. A suite's own output goes to build/memory/<suite>.log, and
# Valgrind writes its report to build/memory/<suite>.valgrind (--log-file),
# where nothing the suite prints can reach. Two suites with one name would
# share both, so test-memory refuses them. One line names each suite's
# outcome: pass, FAIL with its exit status (9 is Valgrind's: an error, or a
# definite leak), or HUNG when timeout killed it (exit 124).
#
# Valgrind runs with -v, and a suite that exits 0 passes only when its
# Valgrind log, and nothing else, shows what Valgrind checked, else it
# FAILs, naming each thing wrong. One awk program reads the log, and prints
# the things wrong, or "ok" alone when it finds none: a suite passes only
# on that line and awk's exit status 0, so an awk that fails, or prints
# nothing, FAILs it, naming the check. It checks that:
#   - the log exists: each run removes the one before;
#   - Valgrind's "Command:" line is CHEZ, the libraries and the suite, so
#     Valgrind ran this suite;
#   - its "Valgrind options:" list is exactly the options test-memory
#     hands it, in order: -v, --command-line-only=yes, the suite's
#     --log-file and ADR-0005's four flags. So nothing VALGRIND, CHEZ or a
#     stand-in for Valgrind adds, drops or changes gets past it (measured
#     in chez-curl: --undef-value-errors=no through VALGRIND hid an
#     undefined-value plant, and a dropped --leak-check=full hid the leak
#     plant). make check-memory-gate holds the options themselves to
#     ADR-0005's;
#   - the first program it read is the file CHEZ names, not a script's
#     interpreter: a CHEZ that is a script runs the shell under Valgrind,
#     and Chez outside it;
#   - it reported "ERROR SUMMARY: 0 errors from 0 contexts": a program that
#     execs away from Valgrind, or a CHEZ script that execs Chez, exits 0
#     with no report at all;
#   - the suppressions files it read are exactly its own default.supp: the
#     gate passes none (ADR-0005). Its own default.supp is the one it names
#     in a run on true, with VALGRIND_LIB unset.
# A FAIL also prints, from Valgrind's log, its first error, the definite
# loss, the suppressed total and its error summary, and, unless the exit
# was Valgrind's, the suite's FAIL lines with the indented lines after
# each, its expected and actual values, every one, then its last 10 lines,
# each line once and no other, so a CI log says why, and names the tests
# that failed. It fails if any suite failed or hung, or if none was named.
#
# Valgrind also takes options and files that its command line does not
# show, and one of them can hide a leak (measured in chez-curl: a
# suppression in VALGRIND_OPTS, in a .valgrindrc, or in the default.supp of
# a directory VALGRIND_LIB names, each hid the planted one). So it refuses
# to run while any VALGRIND_ variable is set (Valgrind reads VALGRIND_OPTS,
# VALGRIND_LIB and VALGRIND_LAUNCHER) or a .valgrindrc exists in $HOME or
# here, and hands Valgrind --command-line-only=yes, so that no .valgrindrc
# a suite writes reaches the next. It refuses a MEMORY_SUITES from the
# environment, where one left exported would narrow every run unseen: give
# it on make's command line. `make check-memory-gate` proves each rule
# fails.
#
# Each suite's children that reach native code run under the gate's own
# Valgrind: the suite starts each through (chez-sqlite3-testing)'s
# gated-command, which reads CHEZ_SQLITE3_GATE_CHILD, exported here, the
# gate's Valgrind and options with a log per child, %p, in
# build/memory/<suite>.children/. After the suite, every child's log is read
# with the parent's rules, but that its Command: line must begin with CHEZ, or
# name a C program called libsqlite3-oracle, the program Valgrind ran, its path
# resolved with readlink -f as Valgrind's is (ADR-0005, amended). Valgrind
# follows no child itself: --trace-children was measured and not taken. Its
# options carry --child-silent-after-fork=yes: a child that forks before it
# execs, as capture-command does, would otherwise leave a second log with a
# Command: line and no summary. Each child's log path is absolute, for a child
# that runs from another working directory.
# Not covered (ADR-0005, amended):
#   - a child started without gated-command runs outside Valgrind, unseen:
#     the children of tests/test-library-loading.sps and test-blocks.sps each
#     say whether they ran under memcheck (preflight's, which prints no such
#     line, by the one new log in the gate's directory), and those suites fail
#     if one did not; no other suite's children are held so;
#   - the gate trusts the programs VALGRIND, TIMEOUT and CHEZ name: a
#     compiled CHEZ that runs Chez as a child passes the leak plant;
#   - its evidence holds against accident, not against a suite that means
#     harm, which can write its own Valgrind log;
#   - make -i, on the command line or in MAKEFLAGS, ignores a failing
#     recipe, this one's as any other's;
#   - two runs in one tree remove each other's logs, and fail, naming the
#     wrong reason: run one at a time in a tree, as check-memory-gate runs
#     each of its cases in a copy of its own.
test-memory: deps ## Run every MEMORY_SUITES suite under Valgrind; fail on any error or definite leak, a hang, or no suite
	@scripts/require-tools "$(GOAL)" $(firstword $(VALGRIND)) $(TIMEOUT) $(CHEZ)
	@case '$(MEMORY_TIMEOUT)' in \
	  '' | *[!0-9]* | 0*) \
	    echo "test-memory: MEMORY_TIMEOUT is '$(MEMORY_TIMEOUT)', not a positive whole number of seconds" >&2; \
	    exit 2 ;; \
	esac
	@case '$(CURDIR)' in \
	  *[[:space:]]*) \
	    echo "test-memory: the checkout's path holds whitespace, '$(CURDIR)': the gate's child prefix, CHEZ_SQLITE3_GATE_CHILD, is cut at whitespace, so its absolute --log-file path would split; run from a path without whitespace" >&2; \
	    exit 2 ;; \
	esac
	@case '$(origin MEMORY_SUITES)' in \
	  environment*) \
	    echo "test-memory: MEMORY_SUITES is set in the environment, where one left exported would narrow every run unseen; give it on make's command line, or unset it (ADR-0005)" >&2; \
	    exit 1 ;; \
	esac
	@if [ -z "$(strip $(MEMORY_SUITES))" ]; then \
	  echo "test-memory: no suites: MEMORY_SUITES is empty" >&2; \
	  exit 1; \
	fi; \
	refused=0; \
	for v in $$(env | sed -n 's/^\(VALGRIND_[A-Za-z0-9_]*\)=.*/\1/p'); do \
	  case $$v in \
	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
	  esac; \
	  echo "test-memory: $$v is set ($$(printenv $$v)): $$why; unset it (ADR-0005)" >&2; \
	  refused=1; \
	done; \
	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
	  if [ -e "$$rc" ]; then \
	    echo "test-memory: $$rc exists: Valgrind would add its options to the gate's; remove it (ADR-0005)" >&2; \
	    refused=1; \
	  fi; \
	done; \
	seen=; \
	for t in $(MEMORY_SUITES); do \
	  name=$$(basename "$$t" .sps); \
	  for u in $$seen; do \
	    if [ "$$(basename "$$u" .sps)" = "$$name" ]; then \
	      echo "test-memory: $$u and $$t share the name $$name, so they would share $(MEMORY_LOGS)/$$name.log and $(MEMORY_LOGS)/$$name.valgrind; rename one (ADR-0005)" >&2; \
	      refused=1; \
	    fi; \
	  done; \
	  seen="$$seen $$t"; \
	done; \
	[ $$refused -eq 0 ] || exit 1; \
	vgdefault=$$(env -u VALGRIND_LIB $(firstword $(VALGRIND)) -v --command-line-only=yes true 2>&1 | sed -n 's/^--[0-9]*-- Reading suppressions file: //p'); \
	case $$vgdefault in \
	  /*/default.supp) ;; \
	  *) vgdefault=; ;; \
	esac; \
	if [ -z "$$vgdefault" ] || [ "$$(printf '%s\n' "$$vgdefault" | wc -l)" -ne 1 ]; then \
	  echo "test-memory: $(firstword $(VALGRIND)) -v, run on true, named no one default.supp of its own" >&2; \
	  exit 1; \
	fi; \
	allowed=$$vgdefault; \
	chez=$$(readlink -f "$$(command -v $(CHEZ))"); \
	evidence_awk='pid == "" && /^==[0-9]+== Command: / { pid = $$0; sub(/^==/, "", pid); sub(/==.*/, "", pid); \
	          got = $$0; sub(/^==[0-9]+== Command: /, "", got); syms = "--" pid "-- Reading syms from "; \
	          supps = "--" pid "-- Reading suppressions file: "; mine = "==" pid "== "; \
	          head = "--" pid "-- Valgrind options:"; option = "--" pid "--    "; next } \
	        pid == "" { next } \
	        listing && index($$0, option) == 1 { opts[++nopts] = substr($$0, length(option) + 1); next } \
	        listing { listing = 0; listed = 1 } \
	        !listed && $$0 == head { listing = 1; next } \
	        index($$0, syms) == 1 && ran == "" { ran = substr($$0, length(syms) + 1) } \
	        index($$0, supps) == 1 { f = substr($$0, length(supps) + 1); read = (read == "" ? f : read ", " f) } \
	        index($$0, mine "ERROR SUMMARY: ") == 1 { summary = substr($$0, length(mine) + 1) } \
	        END { if (pid == "") { print "the log has no Valgrind \"Command:\" line"; exit } \
	          expect = chez; whose = ", the file CHEZ names"; \
	          if (prefix && substr(got, 1, length(cmd)) != cmd) { prog = got; sub(/ .*/, "", prog); base = prog; sub(/.*\//, "", base); \
	            if (oracle != "" && base == oracle) { expect = prog; whose = ", the program its Command: line names"; \
	              if (index(prog, "\047") == 0) { rl = "readlink -f \047" prog "\047"; if ((rl | getline resolved) > 0 && resolved != "") expect = resolved; close(rl) } } \
	            else why[++n] = "Valgrind\047s Command: line is \"" got "\", which begins neither with \"" cmd "\" nor with a program named " oracle } \
	          else if (!prefix && got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
	          nwant = split(ENVIRON["options"], want, "\n"); same = (nopts == nwant); \
	          for (i = 1; i <= nwant; i++) if (opts[i] != want[i]) same = 0; \
	          if (!same) { g = ""; for (i = 1; i <= nopts; i++) g = g (i > 1 ? " " : "") opts[i]; \
	            w = ""; for (i = 1; i <= nwant; i++) w = w (i > 1 ? " " : "") want[i]; \
	            why[++n] = "Valgrind\047s options are [" g "], not the gate\047s [" w "]" } \
	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
	          else if (ran != expect) why[++n] = "Valgrind ran " ran ", not " expect whose; \
	          if (summary !~ /^ERROR SUMMARY: 0 errors from 0 contexts( |$$)/) \
	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
	          for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "; " : ""), why[i]; \
	          if (n) print ""; else print "ok" }'; \
	excerpt_awk='/^==[0-9]+== Command: / { body = 1; next } \
	      !body || !/^==[0-9]+==/ { next } \
	      { line = $$0; sub(/^==[0-9]+== ?/, "", line) } \
	      line == "" { if (inerr) { inerr = 0; done = 1 }; cand = ""; next } \
	      !done && !inerr && cand != "" && line ~ /^ +at 0x/ { inerr = 1; first[++n] = cand } \
	      inerr && n < 16 { first[++n] = $$0 } \
	      !inerr { cand = (line ~ /^[^ ]/) ? $$0 : "" } \
	      line ~ /^ *definitely lost: / { lost = $$0 } \
	      line ~ /^ *suppressed: / { hidden = $$0 } \
	      line ~ /^ERROR SUMMARY: / { summary = $$0 } \
	      END { for (i = 1; i <= n; i++) print "  " first[i]; \
	            if (lost != "") print "  " lost; \
	            if (hidden != "") print "  " hidden; \
	            if (summary != "") print "  " summary; \
	            else print "  (the log holds no Valgrind ERROR SUMMARY)" }'; \
	mkdir -p $(MEMORY_LOGS); \
	passed=0; failed=0; hung=0; \
	for t in $(MEMORY_SUITES); do \
	  name=$$(basename "$$t" .sps); \
	  log=$(MEMORY_LOGS)/$$name.log; \
	  vlog=$(MEMORY_LOGS)/$$name.valgrind; \
	  children=$(MEMORY_LOGS)/$$name.children; \
	  rm -f "$$log" "$$vlog"; \
	  mkdir -p "$$children"; \
	  rm -f "$$children"/*.valgrind; \
	  echo "=== $$t"; \
	  set -- -v --command-line-only=yes "--log-file=$$vlog" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --child-silent-after-fork=yes; \
	  child=; \
	  for o in "$$@"; do \
	    case $$o in --log-file=*) o="--log-file=$(CURDIR)/$$children/%p.valgrind" ;; esac; \
	    child="$$child$${child:+ }$$o"; \
	  done; \
	  CHEZ_SQLITE3_GATE_CHILD="$(VALGRIND) $$child" $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) "$$@" $(CHEZ) --libdirs $(LIBDIRS) --program $$t >"$$log" 2>&1; \
	  rc=$$?; \
	  why=; \
	  if [ $$rc -eq 0 ] && [ ! -f "$$vlog" ]; then \
	    why="Valgrind wrote no log, $$vlog"; \
	  elif [ $$rc -eq 0 ]; then \
	    evidence=$$(options=$$(printf '%s\n' "$$@") awk -v cmd="$(CHEZ) --libdirs $(LIBDIRS) --program $$t" -v prefix=0 -v chez="$$chez" -v allowed="$$allowed" "$$evidence_awk" "$$vlog"); \
	    checked=$$?; \
	    if [ $$checked -ne 0 ]; then \
	      why="the evidence check (awk) exited $$checked"; \
	    elif [ -z "$$evidence" ]; then \
	      why='the evidence check (awk) printed no "ok" line'; \
	    elif [ "$$evidence" != ok ]; then \
	      why=$$evidence; \
	    fi; \
	  fi; \
	  childwhy=; bad=; \
	  if [ $$rc -ne 124 ]; then \
	    for c in "$$children"/*.valgrind; do \
	      [ -e "$$c" ] || continue; \
	      cwhy=; \
	      cevidence=$$(options=$$(printf '%s\n' $$child) awk -v cmd="$(CHEZ) " -v prefix=1 -v oracle=libsqlite3-oracle -v chez="$$chez" -v allowed="$$allowed" "$$evidence_awk" "$$c"); \
	      cchecked=$$?; \
	      if [ $$cchecked -ne 0 ]; then \
	        cwhy="the evidence check (awk) exited $$cchecked"; \
	      elif [ -z "$$cevidence" ]; then \
	        cwhy='the evidence check (awk) printed no "ok" line'; \
	      elif [ "$$cevidence" != ok ]; then \
	        cwhy=$$cevidence; \
	      fi; \
	      if [ -n "$$cwhy" ]; then \
	        childwhy="$$childwhy$${childwhy:+; }a child's Valgrind log, $$c: $$cwhy"; \
	        bad="$$bad $$c"; \
	      fi; \
	    done; \
	  fi; \
	  if [ $$rc -eq 0 ] && [ -n "$$childwhy" ]; then why="$$why$${why:+; }$$childwhy"; fi; \
	  if [ $$rc -eq 0 ] && [ -z "$$why" ]; then \
	    echo "test-memory: pass $$t"; passed=$$((passed + 1)); \
	  elif [ $$rc -eq 124 ]; then \
	    echo "test-memory: HUNG $$t (no exit within $(MEMORY_TIMEOUT)s)"; hung=$$((hung + 1)); \
	  else \
	    if [ $$rc -eq 0 ]; then \
	      echo "test-memory: FAIL $$t (exit 0, but $$why)"; \
	    elif [ $$rc -eq 9 ]; then \
	      echo "test-memory: FAIL $$t (exit 9, Valgrind's: an error or a definite leak)"; \
	    else \
	      echo "test-memory: FAIL $$t (exit $$rc)"; \
	    fi; \
	    failed=$$((failed + 1)); \
	    echo "  log: $$log"; \
	    echo "  Valgrind's log: $$vlog"; \
	    if [ ! -f "$$vlog" ]; then echo "  (Valgrind wrote no log)"; else \
	    awk "$$excerpt_awk" "$$vlog"; \
	    fi; \
	    for c in $$bad; do \
	      echo "  a child's Valgrind log: $$c"; \
	      awk "$$excerpt_awk" "$$c"; \
	    done; \
	    if [ $$rc -ne 9 ]; then \
	      awk '{ line[NR] = $$0 } \
	        END { from = NR - 9; if (from < 1) from = 1; \
	          for (i = 1; i < from; i++) { \
	            if (line[i] ~ /^FAIL /) inside = 1; else if (line[i] !~ /^  /) inside = 0; \
	            if (inside) print line[i] } \
	          for (i = from; i <= NR; i++) print line[i] }' "$$log" | sed 's/^/  | /'; \
	    fi; \
	  fi; \
	done; \
	echo "test-memory: ran $$((passed + failed + hung)), passed $$passed, failed $$failed, hung $$hung"; \
	[ $$failed -eq 0 ] && [ $$hung -eq 0 ]

# Plants a heap overrun and a definite leak (tests/memory-plant-*.sps) and
# requires make test-memory to fail on each, by name, with Valgrind's own
# report. It requires the commands handed to Valgrind to carry no
# suppression, and test-memory to name a hang and refuse no suite. It plants
# each source of options test-memory's command line does not show, each in
# a copy, and requires test-memory to refuse it; a suppressions file the
# gate does not pass, and requires it named; a run with no evidence that
# Valgrind checked Chez on the suite, and requires it to fail; an option
# added, dropped, changed or moved, each hiding a plant where it can, and
# requires it named; a suite that forges Valgrind's lines, and requires
# them unread; and an awk that fails, or prints no "ok", and requires a
# clean program to fail, naming the evidence check. It requires a run with
# no MEMORY_SUITES to run every suite, in order, and one with MEMORY_SUITES
# in the environment to be refused.
# tests/check-memory-gate.sh lists the cases. CI's memory job runs it
# before test-memory (ADR-0005).
check-memory-gate: ## Plant a heap overrun and a leak; make test-memory must fail on each, by name
	@scripts/require-tools "$(GOAL)" $(firstword $(VALGRIND)) $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' VALGRIND='$(VALGRIND)' LIBDIRS='$(LIBDIRS)' sh tests/check-memory-gate.sh

# Removes build/, and nothing else: make deps' links (the links, never what
# they name, since rm does not follow a link), the memory gate's logs and
# every check's scratch. The
# path is written out, not a variable, so no make command line can point it
# elsewhere. With no build/, it passes.
clean: ## Remove build/, and nothing else
	rm -rf build

# Runs make clean in a copy of the tree, after make deps and a few planted
# files and links out of build/, and requires build/ gone, every other path
# unchanged, no link followed, a second make clean to pass, and make deps to
# work after it (tests/check-clean.sh).
check-clean: ## Fail unless make clean, in a copy, removes build/, changes nothing else, follows no link, and can run twice
	@MAKE='$(MAKE)' sh tests/check-clean.sh
