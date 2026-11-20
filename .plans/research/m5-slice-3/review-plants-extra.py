# The review's plants beyond its builder's (its p2 and p3), and two more, each
# under ROOT/p/NAME, from the worktree's two workflows. From the repository
# root, after the review's own builder has filled ROOT/p:
#
#   WT=$PWD python3 -I .plans/research/m5-slice-3/review-plants-extra.py ROOT
import os
import sys

root = sys.argv[1]
src = os.path.join(os.environ["WT"], ".github", "workflows")
ci0 = open(os.path.join(src, "ci.yml"), "rb").read()
pg0 = open(os.path.join(src, "pages.yml"), "rb").read()


def sub(text, old, new):
    """OLD, which must occur once in TEXT, as NEW."""
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new, 1)


def job_sub(text, job, old, new):
    """The first OLD after JOB's header line, as NEW."""
    at = text.index(b"\n  " + job + b":\n")
    i = text.index(old, at)
    return text[:i] + new + text[i + len(old):]


nel = b"          # note\xc2\x85        if: false\n"
inj = b"          # ${{ fromJSON('\"\\necho MAKEFLAGS=-n >> \\\"$GITHUB_ENV\\\"\"') }}\n"
apt = b"          sudo apt-get install -y --no-install-recommends $pkgs\n"
upd = b"          sudo apt-get update -qq\n"
idl = b'          echo "id=${ID}-${VERSION_ID}-${RUNNER_ARCH}" >> "$GITHUB_OUTPUT"\n'

plants = {
    # the review's p2 and p3
    "p2-run-exit-true": (ci0, sub(pg0, b"            exit 1\n", b"            true\n")),
    "p3-nel-content-comment": (job_sub(ci0, b"site", upd, upd + nel), pg0),
    "p3-nel-content-comment-last": (job_sub(ci0, b"site", apt, apt + nel), pg0),
    # an expression in a comment line after pages.yml's run block's last line
    "x-pg-expr-after-block": (ci0, sub(pg0, apt, apt + inj)),
    # the same in main's runner-image block, which no copy holds
    "x-main-expr-in-block": (job_sub(ci0, b"main", idl, idl + inj), pg0),
}
for name, (ci, pg) in plants.items():
    d = os.path.join(root, "p", name)
    os.makedirs(d)
    open(os.path.join(d, "ci.yml"), "wb").write(ci)
    open(os.path.join(d, "pages.yml"), "wb").write(pg)
print(len(plants), "extra plants")
