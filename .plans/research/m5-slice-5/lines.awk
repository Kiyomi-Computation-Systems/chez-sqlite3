# lines.awk: sweep-check.sh's judge of one side of one changed file, line by line.
#   awk -v kind=sh|c|scheme|make|hash|semi -v file=PATH -v side=NAME \
#       -v allow='PATH:DELIM ...' -f lines.awk NUMBERS SOURCE
# NUMBERS holds the numbers of SOURCE's changed lines, one a line, and may be empty. Each
# problem is printed as a line: FILE: SIDE's line N WHY: TEXT.
#   - sh: a changed line is a whole-line comment or blank, outside every quoted string and
#     heredoc, and not line 1; or a # line in a heredoc ALLOW names by its file and
#     delimiter, whose body awk reads. None follows a line ending in a backslash. The
#     scanner tracks quotes, comments and heredocs, and a file it ends inside one of is a
#     problem, since it lost its place.
#   - c: no changed line ends in a backslash, or follows one that does: a // comment so
#     ended swallows the next line, which -fpreprocessed does not splice.
#   - scheme: no changed line holds #! or #;, which read passes over: #!r6rs and
#     #!chezscheme read alike, and #; drops a datum.
#   - make, the Makefile: a changed line is a whole-line comment at column 0, # its first
#     character, or empty: never a recipe line, which begins with a tab and goes to the
#     shell, nor one a space begins. It lies in no define ... endef block, whose lines are
#     a variable's value, comments among them; it ends in no backslash, which carries a
#     make comment on to the next line; and it follows no line that ends in one. The
#     scanner counts define and endef lines, and a file it ends inside a block of is a
#     problem.
#   - hash, packaging/*.txt, .gitignore and .gitattributes: a changed line is a comment
#     with # at column 0, or empty. CI's install step drops only lines that begin with #
#     and empty ones, and git's ignore rules read a # after a blank as a pattern.
#   - semi, packaging/*.sexp: a changed line is a ; comment, past any blanks, or blank.
#     sweep-check.sh reads the file's datums too, so a line inside a string is seen.
BEGIN {
  n = split(allow, a, " ")
  for (i = 1; i <= n; i++) allowed[a[i]] = 1
  st = "code"; qh = 1; nq = 0
  depth = 0
}
FILENAME == ARGV[1] { if ($1 != "") changed[$1 + 0] = 1; next }
{
  if (FNR in changed) judge($0)
  if (kind == "sh") advance($0)
  if (kind == "make") blocks($0)
  prev = $0
}
END {
  if (kind == "sh" && st != "code")
    printf "%s: %s's scanner ends inside %s\n", file, side, place()
  if (kind == "make" && depth != 0)
    printf "%s: %s's scanner ends inside a define block\n", file, side
}

function bad(why) { printf "%s: %s's line %d %s: %s\n", file, side, FNR, why, $0 }

function place() {
  if (st == "heredoc") return "the heredoc " hd
  if (st == "squote") return "a single-quoted string"
  return "a double-quoted string"
}

function judge(line) {
  if (kind == "sh") {
    if (FNR == 1) bad("is line 1")
    if (prev ~ /\\$/) bad("follows a line ending in a backslash")
    if (st == "heredoc") {
      if (!((file ":" hd) in allowed)) bad("lies in the heredoc " hd)
      else if (line !~ /^[[:space:]]*#/) bad("lies in the heredoc " hd " and is no # line")
    } else if (st != "code") bad("lies in " place())
    else if (line !~ /^[[:space:]]*(#.*)?$/) bad("is no comment")
  } else if (kind == "c") {
    if (line ~ /\\[[:space:]]*$/) bad("ends in a backslash")
    if (prev ~ /\\[[:space:]]*$/) bad("follows a line ending in a backslash")
  } else if (kind == "scheme") {
    if (line ~ /#!/) bad("holds #!")
    if (line ~ /#;/) bad("holds #;")
  } else if (kind == "make") {
    if (line ~ /^\t/) bad("is a recipe line")
    else if (line !~ /^(#.*)?$/) bad("is no comment at column 0")
    if (depth > 0) bad("lies in a define block")
    if (line ~ /\\$/) bad("ends in a backslash")
    if (prev ~ /\\$/) bad("follows a line ending in a backslash")
  } else if (kind == "hash") {
    if (line !~ /^(#.*)?$/) bad("is no comment at column 0")
  } else if (kind == "semi") {
    if (line !~ /^[ \t]*(;.*)?$/) bad("is no ; comment")
  } else bad("has no rule of kind " kind)
}

# blocks: the Makefile's define depth after LINE. A define line, past any override, export
# or private, opens a block, also inside one, as make nests them; an endef line closes one.
# A recipe line, and a line a backslash carries on, opens or closes nothing.
function blocks(line) {
  if (line ~ /^\t/ || prev ~ /\\$/) return
  if (line ~ /^[ ]*((override|export|private)[ ]+)*define([ \t]|$)/) depth++
  else if (depth > 0 && line ~ /^[ ]*endef([ \t]|$)/) depth--
}

# advance: the state after LINE, from the state before it.
function advance(line,   i, n, c, t, w, strip) {
  if (st == "heredoc") {
    t = line
    if (hs) sub(/^\t+/, "", t)
    if (t == hd) {
      qh++
      if (qh <= nq) { hd = qd[qh]; hs = qs[qh] } else { st = "code"; qh = 1; nq = 0 }
    }
    return
  }
  n = length(line)
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (st == "squote") { if (c == "\047") st = "code"; continue }
    if (st == "dquote") { if (c == "\\") i++; else if (c == "\"") st = "code"; continue }
    if (c == "\\") { i++; continue }
    if (c == "\047") { st = "squote"; continue }
    if (c == "\"") { st = "dquote"; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|()]/)) break
    if (c == "<" && substr(line, i + 1, 1) == "<" && substr(line, i + 2, 1) != "<" &&
        (i == 1 || substr(line, i - 1, 1) != "<")) {
      i += 2
      strip = 0
      if (substr(line, i, 1) == "-") { strip = 1; i++ }
      while (substr(line, i, 1) ~ /[ \t]/) i++
      w = ""
      while (i <= n && substr(line, i, 1) !~ /[ \t;&|()<>]/) { w = w substr(line, i, 1); i++ }
      i--
      gsub(/[\047"\\]/, "", w)
      if (w != "") { nq++; qd[nq] = w; qs[nq] = strip }
    }
  }
  if (st == "code" && nq >= qh) { st = "heredoc"; hd = qd[qh]; hs = qs[qh] }
}
