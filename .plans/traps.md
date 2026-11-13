# Traps: the full accounts

AGENTS.md carries each trap's one-line rule; this file keeps the incident behind it. Each account
names the repository it happened in. The traps the family hit before this repository existed are
told in chez-curl's `.plans/traps.md`.

## Chez and the FFI

- **Chez fixes no order for a call's arguments, and a probe follows the same rules as a test.**
  M0 slice 0's value probe called
  `(printf "…" (bind-double st 1 1.5) (step st) (col-type st 0))` in a `--script` program.
  `bind` returned `SQLITE_MISUSE` because `step` had already run. The control case exposed it:
  binding 1.5 can't fail, yet it failed exactly as NaN did. Rewritten with `let*`, the probe
  bound 1.5 cleanly and showed that NaN stores NULL.

  Measuring why showed that the rule AGENTS.md inherited was wrong on this Chez in both halves.
  Compiled code ran one call's arguments `abc`, `bca` or `cab` depending on where the call
  appeared, and interpreted code ran them right to left. The probe and its outputs are in
  [research/evaluation-order/](research/evaluation-order/). (chez-sqlite3)

## Editing the records

- **A global replace also hits the sentence that defines what it replaces.** In M0 slice 0,
  `sed 's/ \*(provisional)\*//g'` over `global-constraints.md` removed every rule's marker. It also
  removed the marker from the preamble, the sentence that says what the marker means: "is marked
  *(provisional)* until" became "is marked until". A `grep -c` afterwards answered 0, where 1 was
  due. (chez-sqlite3)
- **A sibling's record cited by its number alone reads as one of ours.** Four citations in M0 slice 0's records named a sibling's
  record by its number alone, after a line break or the word "its". The slice's check of cited
  record numbers flagged the one with no record here; the other three needed a read. (chez-sqlite3)
