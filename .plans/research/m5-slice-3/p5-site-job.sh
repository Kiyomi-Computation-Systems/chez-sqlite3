#!/bin/sh
# P5: ci.yml's site job, and pages.yml's build job, run in a fresh
# ubuntu:24.04 container, from a copy of the tree: the container cannot show
# what a lane on another toolchain refuses. Run on the host, with Docker and
# git, from the repository root, on a build/m5s3/p5/ that does not exist yet:
#
#   sh .plans/research/m5-slice-3/p5-site-job.sh
#
# The copy is what a checkout with submodules holds: the files git tracks, or
# would (untracked and not ignored), and chez-srfi's, with no .git and no
# build/. p5-inside.sh runs the steps; everything they print is in
# build/m5s3/p5/p5.log. Exits as the container does.
set -eu
out=build/m5s3/p5
mkdir "$out"
here=$(pwd)
{
  git ls-files --cached --others --exclude-standard | grep -v -x vendor/chez-srfi
  git -C vendor/chez-srfi ls-files | sed 's|^|vendor/chez-srfi/|'
} | sort >"$out/files"
tar -cf "$out/tree.tar" -T "$out/files"
docker pull -q ubuntu:24.04
echo "+ image digest: $(docker image inspect ubuntu:24.04 --format '{{index .RepoDigests 0}}')" \
  >"$out/p5.log"
set +e
docker run --rm -v "$here/$out:/p5:ro" \
  -v "$here/.plans/research/m5-slice-3/p5-inside.sh:/p5-inside.sh:ro" \
  ubuntu:24.04 sh /p5-inside.sh >>"$out/p5.log" 2>&1
st=$?
tail -n 1 "$out/p5.log"
# A shell error of the driver's own, such as an unset parameter under set -u,
# can leave a step without its env and still let it pass: it fails the run.
if grep -n '^/p5-inside\.sh: ' "$out/p5.log"; then
  echo "p5: the driver hit a shell error of its own"
  st=1
fi
exit "$st"
