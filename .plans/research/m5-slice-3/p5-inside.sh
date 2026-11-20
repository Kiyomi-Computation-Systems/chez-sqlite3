#!/bin/sh
# P5, inside a fresh ubuntu:24.04 container: p5-site-job.sh starts it, with
# the tree's copy at /p5/tree.tar. As root, it gives the image what GitHub's
# runner has and a bare image lacks, a user runner with sudo and no password,
# and unpacks two copies of the tree, one per workflow. Then, as runner, it
# runs ci.yml's site job, and then pages.yml's build job in the other copy,
# each step read from the copy's workflow: its env, and its run text, given
# to bash -e as GitHub gives it. A step that uses an action is named, not
# run: the copy stands in for the checkout, and the upload is GitHub's. Each
# step's output is printed whole, then its exit status and last line. Exits
# 1 unless every step passed.
set -u

if [ "${1:-}" != runner ]; then
  . /etc/os-release
  echo "+ image: $PRETTY_NAME, $(uname -m)"
  apt-get update -qq >/dev/null 2>&1 &&
    apt-get install -y -qq --no-install-recommends sudo >/dev/null 2>&1 ||
    { echo "p5: could not install sudo"; exit 1; }
  useradd -m runner
  echo 'runner ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/runner
  for w in site pages; do
    mkdir -p "/home/runner/work/$w"
    tar -xf /p5/tree.tar -C "/home/runner/work/$w"
  done
  chown -R runner:runner /home/runner
  for t in curl wget make xz chezscheme cmark-gfm; do
    printf '+ before the install step, %s: %s\n' "$t" "$(command -v "$t" || echo none)"
  done
  exec sudo -u runner -H sh "$0" runner
fi

scratch=$(mktemp -d)
n=0; fails=0

# steps FILE JOB: each step of JOB in workflow FILE, as a call of run_step
# NAME ENV, its run text on stdin; a step that uses an action, as a call of
# uses_step.
steps() {
  awk -v JOB="$2" '
    function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
    function flush() {
      if (have && run != "") {
        k++
        printf "run_step %s %s <<\047STEP_%d\047\n%sSTEP_%d\n", q(name), q(envs), k, run, k
      } else if (have && uses != "") printf "uses_step %s\n", q(uses)
      have = 0; name = ""; envs = ""; run = ""; uses = ""; inenv = 0; inrun = 0
    }
    function key(s,   p, k, v) {
      p = index(s, ": ")
      if (p == 0) { k = s; sub(/:$/, "", k); v = "" }
      else { k = substr(s, 1, p - 1); v = substr(s, p + 2) }
      inenv = 0; inrun = 0
      if (k == "name") name = v
      else if (k == "uses") uses = v
      else if (k == "env") inenv = 1
      else if (k == "run") { if (v == "|") inrun = 1; else run = v "\n" }
    }
    /^  [^ #][^:]*:$/ { flush(); injob = ($0 == "  " JOB ":"); next }
    !injob { next }
    /^ *#/ && !inrun { next }
    /^      - / { flush(); have = 1; key(substr($0, 9)); next }
    /^        [^ ]/ { key(substr($0, 9)); next }
    /^          / {
      if (inenv) {
        s = substr($0, 11); p = index(s, ": ")
        envs = envs substr(s, 1, p - 1) "=" substr(s, p + 2) "\n"
      }
      else if (inrun) run = run substr($0, 11) "\n"
      next
    }
    /^$/ { if (inrun) run = run "\n"; next }
    END { flush() }
  ' "$1"
}

uses_step() {
  echo "+ step (an action, not run here): $1"
}

run_step() {
  n=$((n + 1))
  cat >"$scratch/step$n.sh"
  echo "+ step $n: $1"
  printf '%s' "$2" | sed 's/^/+   env /'
  sed 's/^/+   run | /' "$scratch/step$n.sh"
  # The env list is read before set -- empties the arguments, $2 among them.
  envs=$2
  set --
  while IFS= read -r kv; do
    [ -n "$kv" ] && set -- "$@" "$kv"
  done <<EOF
$envs
EOF
  # What the step's shell is given, read back by it.
  env "$@" sh -c 'echo "+   the step sees CHEZ=${CHEZ-(unset)} SITE_REF=${SITE_REF-(unset)}"'
  env "$@" bash -e "$scratch/step$n.sh" >"$scratch/out$n" 2>&1
  st=$?
  cat "$scratch/out$n"
  echo "+ step $n exit $st; last line: $(tail -n 1 "$scratch/out$n")"
  [ "$st" -eq 0 ] || fails=$((fails + 1))
}

# links DIR: the site's links to repository files, counted by the ref they name.
links() {
  echo "+ files in $1/build/site: $(find "$1/build/site" -type f | wc -l)"
  echo "+ links to repository files, by ref:"
  cat "$1"/build/site/*.html |
    grep -o 'https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/blob/[^/"]*/' |
    sort | uniq -c
}

echo "=== ci.yml, job site"
cd /home/runner/work/site || exit 1
steps .github/workflows/ci.yml site >"$scratch/site.sh"
. "$scratch/site.sh"
links /home/runner/work/site
for t in curl wget; do
  printf '+ after the install step, %s: %s\n' "$t" "$(command -v "$t" || echo none)"
done
echo "+ scheme, which make's own default would take: $(command -v scheme || echo none)"
echo "+ chezscheme: $(echo '(display (scheme-version))' | chezscheme -q)"
echo "+ packages: $(dpkg-query -W -f '${Package} ${Version}; ' \
  chezscheme cmark-gfm libcmark-gfm0.29.0.gfm.6 curl xz-utils make ca-certificates)"
echo "+ awk: $(readlink -f "$(command -v awk)")"
echo "+ check-ci, under that awk: $(sh tests/check-ci.sh .github/workflows 2>&1)"

echo "=== pages.yml, job build, SITE_REF the tag v0.1.0"
cd /home/runner/work/pages || exit 1
steps .github/workflows/pages.yml build | sed 's/\${{ github\.ref_name }}/v0.1.0/' \
  >"$scratch/pages.sh"
. "$scratch/pages.sh"
links /home/runner/work/pages

echo "=== p5: $n steps run, $fails failed"
[ "$fails" -eq 0 ]
