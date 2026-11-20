# Finding SQLite

chez-sqlite3 loads SQLite's library, `libsqlite3`, once, the first time
your program needs it. This page says which file it picks, why it can
refuse one, and how to name your own. The reference's
[Which SQLite](reference.md#which-sqlite) is the short form.

## Name it yourself

Set `CHEZ_SQLITE3_LIBRARY` to the library's absolute path:

```sh
export CHEZ_SQLITE3_LIBRARY=/opt/sqlite/lib/libsqlite3.so.0
```

chez-sqlite3 loads that file with no search of its own, and has nothing to
fall back to; on a Mac,
[`DYLD_LIBRARY_PATH`](#dyld_library_path-on-a-mac) can still swap it. A
relative path, a bare name and `""` are refused.

## Or let it look

With `CHEZ_SQLITE3_LIBRARY` unset, it takes the first file that exists on
a short list. The list depends on the system:

| System | Where it looks, in order | Source |
|---|---|---|
| Linux, when Chez runs on Guix's C library, as Guix's Chez does | `lib/libsqlite3.so.0` in `$GUIX_ENVIRONMENT`, `$GUIX_PROFILE`, `~/.guix-home/profile`, `~/.guix-profile`, then `/run/current-system/profile` | `guix-environment`, `guix-profile`, `guix-home`, `guix-user-profile`, `guix-system` |
| Other Linux | `libsqlite3.so.0` in `/usr/local/lib`, `/usr/lib/x86_64-linux-gnu` (`/usr/lib/aarch64-linux-gnu` on arm64), `/usr/lib64`, then `/usr/lib` | `system` |
| A Mac | Apple's `/usr/lib/libsqlite3.dylib` | `macos-system` |
| Any other system | nothing | |

The source is what `sqlite-library-source` answers, and `override` for
`CHEZ_SQLITE3_LIBRARY`. The
[quick start](quickstart.md#which-sqlite-did-it-load) shows how to read it.

Apple's library is no file on disk: macOS keeps it in its shared cache. So
`ls` won't find it, but it loads.

## When it is refused

When no file can be chosen, or the chosen one fails to load or fails its
checks, the load is refused, and no other file is tried. The refusal is a
condition that `sqlite-library-unavailable?` holds, and
`sqlite-library-unavailable-reason` gives one of these:

| Reason | Why |
|---|---|
| `invalid-override` | `CHEZ_SQLITE3_LIBRARY` is set, but not to an absolute path. |
| `not-found` | No file on the list exists. `sqlite-library-unavailable-candidates` gives every path it looked at. |
| `load-failed` | The system's loader could not load the file, as when an override names no file, or the library misbehaved as it started. |
| `below-floor` | The library is older than [README.org's Requirements](../README.org) allow. |
| `not-threadsafe` | The library was built for one thread alone, `THREADSAFE=0`. |
| `missing-api` | The library lacks a function chez-sqlite3 needs. |

Each refusal's message says what to do, and
[`sqlite-library-unavailable-detail`](reference.md#sqlite-library-unavailable-detail)
and the entries beside it give the details: the path, where it came from,
and more by reason, such as the loader's message or the version found. The
fix is to name a SQLite that passes with `CHEZ_SQLITE3_LIBRARY`; or, with it
unset, to install one where the list looks before the file refused, such as
`/usr/local/lib` on Linux outside Guix.

## Who needs the override

- **Guix:** no one, when SQLite is in the profile or the `guix shell`.
- **Ubuntu 24.04:** no one, with its `libsqlite3-0` package installed. Its
  own library is found.
- **macOS 26:** no one, for Apple's library. An older macOS's library may be
  older than [README.org's Requirements](../README.org) allow, and is then
  refused as `below-floor`: name Homebrew's. Any other library, Homebrew's
  among them, needs the override. On an arm64 Mac, Homebrew's is
  `/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib`. Apple's has no extension
  loading, so a program that loads extensions names another.
- **A library off the list,** such as one from Nix, one under `/opt`, or
  your own build installed outside the list's folders.
- **A system whose SQLite is too old:** it is found, then refused as
  `below-floor`. Name a newer one.
- **Any other system,** where the tests have not run: there is no list, so
  only the override names a library.

## `DYLD_LIBRARY_PATH` on a Mac

chez-sqlite3 never reads `LD_LIBRARY_PATH` or `DYLD_LIBRARY_PATH`. On
Linux, `LD_LIBRARY_PATH` doesn't change which file an absolute path loads.
On a Mac, `DYLD_LIBRARY_PATH` can: macOS's loader looks in its folders
first for a file of the same name, and loads that instead. That holds for
Apple's path, for an override's, and for an extension's.

Then `sqlite-library-path` still gives the path asked for, while
`sqlite-version` and `sqlite-source-id` describe the file loaded. So on a
Mac, set `DYLD_LIBRARY_PATH` only to folders you trust, or leave it unset
([Which SQLite](reference.md#which-sqlite)).
