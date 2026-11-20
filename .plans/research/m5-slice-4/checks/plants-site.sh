#!/bin/sh
# Plants for check-site's invariant 7 without its fallback. Run from the
# worktree root, inside the container, after make site-deps on the host:
#   scripts/guix-env sh build/m5s4-checks/plants-site.sh
# site/README.org.main and site/check-site.sps.main are main's (8c18272), taken
# with git show on the host. Each plant replaces README.org, runs main's
# check-site.sps and this tree's on it, and restores it. docs/quickstart.md,
# a stand-in site/pages.sls does not list, is moved aside for every run, so
# invariant 1 holds, and put back on exit.
set -u
out=build/m5s4-checks/site
cp README.org "$out/README.org.orig"
mv docs/quickstart.md "$out/quickstart.md.aside"
restore() { cp "$out/README.org.orig" README.org; }
trap 'restore; mv "$out/quickstart.md.aside" docs/quickstart.md' EXIT

site() { # name program
  SITE_REF=main $CHEZ --libdirs .:build/akku/chez-cmark-gfm/src --program "$2" >"$out/$1.log" 2>&1
  echo "--- $1: exit $?"; cat "$out/$1.log"
}

echo "=== the stand-in README, whole"
site old-on-stand-in "$out/check-site.sps.main"
site new-on-stand-in tests/check-site.sps

echo "=== s-heading-deleted: the stand-in README with its ** Documentation line deleted"
grep -v '^\*\* Documentation$' "$out/README.org.orig" >README.org
cmp -s README.org "$out/README.org.orig" && echo "PLANT CHANGED NOTHING"
site old-heading-deleted "$out/check-site.sps.main"
site new-heading-deleted tests/check-site.sps
restore

echo "=== s-main-readme: main's README.org, which has no ** Documentation section and links the reference elsewhere"
cp "$out/README.org.main" README.org
site old-main-readme "$out/check-site.sps.main"
site new-main-readme tests/check-site.sps
restore

echo "=== restored"
site new-restored tests/check-site.sps
