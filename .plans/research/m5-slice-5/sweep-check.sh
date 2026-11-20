#!/bin/sh
# sweep-check.sh BASE: from the worktree's root, inside scripts/guix-env, with BASE a copy of the
# swept commit's src/ and tests/, which extract-base.sh writes on the host. It holds the comment
# sweep to changing comments alone, in every file of src/ and tests/ but tests/fixtures/:
#   - every file keeps its mode, as ls prints it;
#   - a .sps or .sls reads, by Chez's read, as the same datums as BASE's (datums.sps), and no
#     changed line holds #! or #; (lines.awk);
#   - every line a .sh changes, before and after, is a whole-line comment or blank, outside
#     every quoted string and heredoc, and not line 1; or a # line in a heredoc named in
#     awk_heredocs below, whose body is an awk program. None follows a line ending in a
#     backslash (lines.awk);
#   - a .c reads, its comments stripped by the compiler's -fpreprocessed, each line's ends
#     trimmed and its blank lines dropped, as BASE's does, so a token changed in a branch no
#     build compiles is seen; no changed line ends in a backslash or follows one that does
#     (lines.awk); and it compiles, without -g, to the same object code as BASE's, each from a
#     file of the same name, so the object's file symbol matches, with the four values the
#     decoy requires, once for each build the suites make of it (variants.sps), or once
#     plainly for a file they don't build;
#   - a file added, removed, or of any other kind changed is a problem.
# One line a problem, then a summary; exit 1 on any problem. Scratch goes under build/m5s5/check.
set -u
base=$1
here=$(dirname -- "$0")
out=build/m5s5/check
# The heredocs whose bodies are awk programs, as FILE:DELIMITER: a # line there is awk's comment.
awk_heredocs='tests/check-ci.sh:AWKPROGRAM'
mkdir -p "$out"
: > "$out/problems"
list() { (cd "$1" && find src tests -type f -not -path 'tests/fixtures/*' | LC_ALL=C sort); }
list "$base" > "$out/base.list"
list . > "$out/tree.list"
LC_ALL=C comm -23 "$out/base.list" "$out/tree.list" | sed 's/^/removed: /' >> "$out/problems"
LC_ALL=C comm -13 "$out/base.list" "$out/tree.list" | sed 's/^/added: /' >> "$out/problems"
"$CHEZ" --program "$here/variants.sps" "$base" > "$out/variants" 2>&1 ||
  echo "the builds: $(head -1 "$out/variants")" >> "$out/problems"
# mode F: F's mode, as ls -l prints it.
mode() { ls -ld -- "$1" | cut -c1-10; }
# numbers SIDE F: the numbers of F's changed lines on SIDE of diff's normal output, < for
# BASE's and > for the tree's, one a line.
numbers() {
  diff "$base/$2" "$2" | awk -v side="$1" '
    /^[0-9]/ {
      match($0, /[acd]/)
      op = substr($0, RSTART, 1)
      r = (side == "<") ? substr($0, 1, RSTART - 1) : substr($0, RSTART + 1)
      if ((side == "<" && op == "a") || (side == ">" && op == "d")) next
      if (split(r, ends, ",") == 1) ends[2] = ends[1]
      for (i = ends[1] + 0; i <= ends[2] + 0; i++) print i
    }'
}
# lines KIND F: lines.awk's problems with F's changed lines, BASE's and the tree's.
lines() {
  numbers '<' "$2" > "$out/lines.base"
  numbers '>' "$2" > "$out/lines.tree"
  awk -v kind="$1" -v file="$2" -v side=BASE -v allow="$awk_heredocs" \
    -f "$here/lines.awk" "$out/lines.base" "$base/$2" >> "$out/problems"
  awk -v kind="$1" -v file="$2" -v side=tree -v allow="$awk_heredocs" \
    -f "$here/lines.awk" "$out/lines.tree" "$2" >> "$out/problems"
}
checked=0
changed=0
builds=0
LC_ALL=C comm -12 "$out/base.list" "$out/tree.list" > "$out/both.list"
while IFS= read -r f; do
  checked=$((checked + 1))
  [ "$(mode "$base/$f")" = "$(mode "$f")" ] ||
    echo "$f: its mode was $(mode "$base/$f"), and is $(mode "$f")" >> "$out/problems"
  cmp -s "$base/$f" "$f" && continue
  changed=$((changed + 1))
  case $f in
    *.sps | *.sls)
      r=$("$CHEZ" --program "$here/datums.sps" "$base/$f" "$f" 2>&1) ||
        echo "$f: $r" >> "$out/problems"
      lines scheme "$f" ;;
    *.sh)
      lines sh "$f" ;;
    *.c)
      lines c "$f"
      name=${f##*/}
      rm -rf "$out/c"
      mkdir -p "$out/c/a" "$out/c/b"
      cp "$base/$f" "$out/c/a/$name"
      cp "$f" "$out/c/b/$name"
      for side in a b; do
        ${CC:-cc} -fpreprocessed -dD -E -P "$out/c/$side/$name" 2> "$out/c/$side.tok.err" |
          sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' > "$out/c/$side.tok"
      done
      cmp -s "$out/c/a.tok" "$out/c/b.tok" ||
        echo "$f: its code, comments stripped, differs" >> "$out/problems"
      awk -v f="$f" '$1 == f { $1 = ""; print substr($0, 2) }' "$out/variants" > "$out/c/builds"
      [ -s "$out/c/builds" ] || echo "plain" > "$out/c/builds"
      defs='-DDECOY_VERSION_NUMBER=3045001 -DDECOY_VERSION=\"3.45.1\" -DDECOY_BELOW_NUMBER=3045000 -DDECOY_BELOW=\"3.45.0\"'
      differ=''
      unbuilt=''
      while read -r build switches; do
        builds=$((builds + 1))
        if (cd "$out/c/a" && eval "${CC:-cc} -c -O0 -w -fPIC $defs $switches -o a.o $name") \
             2> "$out/c/a.err" &&
           (cd "$out/c/b" && eval "${CC:-cc} -c -O0 -w -fPIC $defs $switches -o b.o $name") \
             2> "$out/c/b.err"; then
          cmp -s "$out/c/a/a.o" "$out/c/b/b.o" || differ="$differ $build"
        else
          unbuilt="$unbuilt $build: $(cat "$out/c/a.err" "$out/c/b.err" | head -1)"
        fi
      done < "$out/c/builds"
      [ -z "$differ" ] || echo "$f: its object code differs, built as:$differ" >> "$out/problems"
      [ -z "$unbuilt" ] || echo "$f: did not compile, built as$unbuilt" >> "$out/problems" ;;
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
echo "sweep-check: ok: $changed of $checked files changed, each in its comments alone" \
  "($builds C builds compared)"
