# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release (see [CHANGELOG.md](CHANGELOG.md)) | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Please report a suspected vulnerability privately, through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a
public issue.

You can expect an acknowledgement within 7 days.

chez-sqlite3 hands C pointers to SQLite's library on your program's behalf,
so these reports are especially welcome:

- memory safety at the native boundary: a handle used after its close or
  finalize, or freed twice, or a value handed to C that doesn't fit its type;
- a connection used from a thread other than the one that opened it, past
  the wrong-thread condition;
- an engine's expiry, or a continuation, that runs a call's step twice or
  skips a close or a finalize;
- an extension loaded without `(enable-load-extension . #t)`.

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
