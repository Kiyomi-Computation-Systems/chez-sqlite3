# What M3's plan measured

Measured 2026-11-15, before M3's plan, while M2 was being built. Two halves, each on Guix's
SQLite 3.53.1 and on the floor, 3.45.1:

- [concurrency/](concurrency/README.md): `sqlite3_interrupt`, the busy timeout, two
  connections contending in WAL and rollback-journal mode, and a Chez probe of a thread blocked in
  a `__collect_safe` step.
- [single/](single/README.md): transactions and savepoints, which errors end a transaction, the
  change counters, the settings (PRAGMAs), and what a statement cache and a script runner rest on.

Each README ends with what it contradicts in the records and with questions for M3's plan. An
adversarial review checked both halves the same day. Its findings were measured again and fixed
in place, and each README says what changed.

## The floor the probes ran against

Both halves load the floor from the git-ignored `build/m3-floor/`, which CI's `floor` lane
builds: SQLite's pinned 3.45.1 autoconf amalgamation, checked against both of
`scripts/ci/build-sqlite.sh`'s digests and compiled with its flags. The concurrency half's
`HAVE_NANOSLEEP=0` variant also compiles from the source in `build/m3-floor-dl/`. To rebuild
both, from the repository's root:

```
# On the host: the download, and its two pinned digests.
mkdir -p build/m3-floor-dl
curl -fsSL -o build/m3-floor-dl/sqlite-autoconf-3450100.tar.gz \
  https://sqlite.org/2024/sqlite-autoconf-3450100.tar.gz
openssl dgst -sha3-256 -r build/m3-floor-dl/sqlite-autoconf-3450100.tar.gz
sed -n 's/^floor_archive=//p' scripts/ci/build-sqlite.sh        # must equal the line above
tar xzf build/m3-floor-dl/sqlite-autoconf-3450100.tar.gz -C build/m3-floor-dl \
  sqlite-autoconf-3450100/sqlite3.c sqlite-autoconf-3450100/sqlite3.h \
  sqlite-autoconf-3450100/sqlite3ext.h
openssl dgst -sha3-256 -r build/m3-floor-dl/sqlite-autoconf-3450100/sqlite3.c
sed -n 's/^floor_source=//p' scripts/ci/build-sqlite.sh         # must equal the line above

# In the container: CI's compile line, then CI's own check.
scripts/guix-env sh -c 'P=$PWD/build/m3-floor; S=build/m3-floor-dl/sqlite-autoconf-3450100;
  mkdir -p $P/lib $P/include &&
  $CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs -o $P/lib/libsqlite3.so.0 \
    $S/sqlite3.c -lpthread -lm &&
  cp $S/sqlite3.h $S/sqlite3ext.h $P/include/ &&
  CHEZ_SQLITE3_LIBRARY=$P/lib/libsqlite3.so.0 C_INCLUDE_PATH=$P/include \
    sh scripts/ci/check-sqlite.sh $P'
```

The library this built on 2026-11-15 had SHA-256
`a36320cba88bfe5b5ef7dad8b7525abfdeb8cda0f9296edbc6f70eb4f85af433`. Another compiler can give
other bytes, and the same library.
