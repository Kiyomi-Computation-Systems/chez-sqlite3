#!/bin/sh
# sweep-check.sh BASE: from the worktree's root, inside scripts/guix-env, with BASE a copy of the
# swept commit's src/ and tests/, which extract-base.sh writes on the host. It holds the comment
# sweep to changing comments alone, in every file of src/ and tests/ but tests/fixtures/:
#   - a .sps or .sls reads, by Chez's read, as the same datums as BASE's (datums.sps);
#   - every line a .sh changes is a whole-line comment or blank, before and after;
#   - a .c reads, its comments stripped by the compiler's -fpreprocessed and its runs of white
#     space folded, as BASE's does, so a token changed in a branch no build compiles is seen; and
#     it compiles, without -g, to the same object code as BASE's, each from a file of the same name,
#     so the object's file symbol matches, with the four values the decoy requires;
#   - a file added, removed, or of any other kind changed is a problem.
# One line a problem, then a summary; exit 1 on any problem. Scratch goes under build/m5s5/check.
set -u
base=$1
here=$(dirname -- "$0")
out=build/m5s5/check
mkdir -p "$out"
: > "$out/problems"
list() { (cd "$1" && find src tests -type f -not -path 'tests/fixtures/*' | LC_ALL=C sort); }
list "$base" > "$out/base.list"
list . > "$out/tree.list"
LC_ALL=C comm -23 "$out/base.list" "$out/tree.list" | sed 's/^/removed: /' >> "$out/problems"
LC_ALL=C comm -13 "$out/base.list" "$out/tree.list" | sed 's/^/added: /' >> "$out/problems"
checked=0
changed=0
LC_ALL=C comm -12 "$out/base.list" "$out/tree.list" > "$out/both.list"
while IFS= read -r f; do
  checked=$((checked + 1))
  cmp -s "$base/$f" "$f" && continue
  changed=$((changed + 1))
  case $f in
    *.sps | *.sls)
      r=$("$CHEZ" --program "$here/datums.sps" "$base/$f" "$f" 2>&1) ||
        echo "$f: $r" >> "$out/problems" ;;
    *.sh)
      diff "$base/$f" "$f" | sed -n 's/^[<>] //p' | grep -nvE '^[[:space:]]*(#.*)?$' > "$out/sh.bad"
      [ -s "$out/sh.bad" ] && echo "$f: a changed line is no comment: $(head -1 "$out/sh.bad")" >> "$out/problems" ;;
    *.c)
      name=${f##*/}
      mkdir -p "$out/c/a" "$out/c/b"
      cp "$base/$f" "$out/c/a/$name"
      cp "$f" "$out/c/b/$name"
      for side in a b; do
        ${CC:-cc} -fpreprocessed -dD -E -P "$out/c/$side/$name" 2> "$out/c/$side.tok.err" |
          tr -s ' \t\n' '   ' > "$out/c/$side.tok"
      done
      cmp -s "$out/c/a.tok" "$out/c/b.tok" ||
        echo "$f: its code, comments stripped, differs" >> "$out/problems"
      defs='-DDECOY_VERSION_NUMBER=3045001 -DDECOY_VERSION=\"3.45.1\" -DDECOY_BELOW_NUMBER=3045000 -DDECOY_BELOW=\"3.45.0\"'
      if (cd "$out/c/a" && eval "${CC:-cc} -c -O0 -w -fPIC $defs -o a.o $name") 2> "$out/c/a.err" &&
         (cd "$out/c/b" && eval "${CC:-cc} -c -O0 -w -fPIC $defs -o b.o $name") 2> "$out/c/b.err"; then
        cmp -s "$out/c/a/a.o" "$out/c/b/b.o" || echo "$f: its object code differs" >> "$out/problems"
      else
        echo "$f: did not compile: $(cat "$out/c/a.err" "$out/c/b.err" | head -1)" >> "$out/problems"
      fi ;;
    *)
      echo "$f: a $(echo "${f##*.}") file changed, and no rule holds its kind" >> "$out/problems" ;;
  esac
done < "$out/both.list"
n=$(wc -l < "$out/problems")
if [ "$n" -gt 0 ]; then
  sed 's/^/sweep-check: /' "$out/problems"
  echo "sweep-check: FAILED ($n problems; $changed of $checked files changed)"
  exit 1
fi
echo "sweep-check: ok: $changed of $checked files changed, each in its comments alone"
