# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release (see [CHANGELOG.md](CHANGELOG.md)) | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Please report a suspected vulnerability privately, through GitHub's
[report form](https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/security/advisories/new)
(**Security → Report a vulnerability** on this repository). Don't open a
public issue.

You can expect an acknowledgement within 7 days.

chez-sqlite3 hands C pointers to SQLite's library on your program's behalf,
so these reports are especially welcome:

- memory safety at the native boundary: a handle used after its close or
  finalize, or freed twice, or a value handed to C that doesn't fit its type;
- a connection or its statement used from a thread other than the one that
  opened it without raising the wrong-thread condition
  (`interrupt-database!` alone may come from any thread);
- an engine's expiry, or a continuation, that runs a call's step twice or
  skips a close or a finalize;
- an extension loaded on a connection opened without
  `(enable-load-extension . #t)`, or SQL's `load_extension()` working on a
  connection where no extension you loaded turned it on.

Please include your platform, your Chez version, and the output of
`make build`, which names the SQLite library loaded and its version.

## What is not a vulnerability

- **SQL built from untrusted text.** Bind each value to a `?` instead; the
  [quick start](docs/quickstart.md) shows how.
- **A flaw in SQLite itself.** Report it to
  [SQLite's developers](https://sqlite.org/support.html), and update the
  SQLite your program loads.
- **An extension you chose to load.** It runs as native code, with your
  program's rights.
