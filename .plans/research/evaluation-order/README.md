# Research: the order Chez evaluates a call's arguments

Date: 2026-11-13 (M0 slice 1). It corrects a rule AGENTS.md inherited from the family. The
explanation was corrected after the slice's review.

## Why

The family's rule, from chez-cmark-gfm, chez-libuv and chez-curl, said: "Chez evaluates
arguments right to left in compiled library code, left to right when interpreted." M0 slice 0's
value probe, a `--script` program, called
`(printf "…" (bind-double st 1 1.5) (step st) (col-type st 0))`. `bind` returned
`SQLITE_MISUSE`, because `step` had already run. The question was whether the rule holds.

## Toolchain

| | |
|---|---|
| Host | Pop!_OS 22.04, x86_64 |
| Chez | 10.4.0 from Guix, `ta6le`, threaded, default optimize level |

## The probe

`order.ss` calls libc's `putchar` directly as each argument, three times: 97, 98, 99. Each
call writes a byte, so the bytes show the order the arguments ran in. It does this at top level,
inside a lambda and inside a `define`d procedure, for `list` and for `format`. `lib/orderlib.sls`
does the same inside a library.

From this directory:

```
scheme -q --script order.ss
scheme -q --libdirs lib --program order-program.sps
echo '(parameterize ([current-eval interpret]) (load "order.ss"))' | scheme -q
echo '(compile-interpret-simple #f) (load "order.ss")' | scheme -q
```

`order-inlinable.ss` and `order-set.ss` run the same ways as `order.ss`.

## Results

Each mode was run twice, with the same output both times.

| Site | `--script` | library | `interpret` | `compile-interpret-simple` off |
|---|---|---|---|---|
| top level, `list` | `cab` | | `cba` | `abc` |
| top level, `format` | `bca` | | `cba` | `abc` |
| in a lambda, `list` | `cab` | | `cba` | `abc` |
| in a lambda, `format` | `bca` | | `cba` | `abc` |
| in a `define`, `format` | `abc` | | `cba` | `abc` |
| in the library, `list` | | `abc` | | |
| in the library, `format` | | `abc` | | |

`(compile-interpret-simple)` is `#t` by default. Under it, Chez's `compile` hands an expression
it judges simple to the interpreter instead of compiling it. That is what `--script` and `load`
do with each top-level form. Turned off, every site ran `abc`. So the mixed orders, `cab` and
`bca`, came from that interpreter path, not from compiled code.

Two more probes put Scheme procedures in place of `putchar`. In `order-inlinable.ss` they are
small enough to inline; in `order-set.ss` they are `set!`-bound, which prevents inlining, or
wrap a foreign call. Both ran `abc` under `--script` and `cba` under `interpret`, at every site,
over two runs each.

## Verdict

| Claim | Holds? |
|---|---|
| Compiled library code runs arguments right to left | No: both library sites ran `abc`. |
| Interpreted code runs them left to right | No: `interpret` ran `cba` everywhere, and the interpreter path for simple expressions ran `cab` and `bca`. |
| A given site's order is stable from run to run | Yes, at every site, over two runs. |
| No assertion may depend on the order | Yes: this is the rule that matters. Compiled code ran `abc` at every site measured here, but nothing promises it. |

chez-curl's own accounts agree that there's no fixed order. A `let` in its library code ran its
second init first, and `map` called its procedure on 5 6 3 4 1 2 (chez-curl's `traps.md`).

## Deliberately untested

- Chez 10.4.1 and the Mac, arm64, and other optimize levels.
- Libraries compiled ahead of time to `.so` files, rather than at import.
- Whether a site's order survives a change elsewhere in the same file.
- Which expressions `compile` judges simple.
