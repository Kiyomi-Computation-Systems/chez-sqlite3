/* F1: what an FTS5 suite and a JSON suite would assert, on each library (the
 * M4 plan, sections 4.5 and 8).
 *
 *   f1-fts5-json DIR TIMING     (DIR and TIMING unused: every database is
 *                                :memory:, and nothing is timed)
 *
 * Every statement is printed with what SQLite answered: each row's columns
 * by their sqlite3_column_type, INTEGER as an integer, FLOAT to 17
 * significant digits, TEXT in quotes, BLOB as x'..', NULL; or the failure,
 * at prepare or at step, with its code, extended code and message. Text is
 * printed as bytes, so UTF-8 shows as itself.
 *
 *   F0  the compile options the suites would choose their rows by
 *   F1  FTS5's refusal, where the library lacks it: at prepare or at step
 *   F2  FTS5's behaviour, where it has it
 *   F3  JSON's, everywhere
 */
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void version_lines(void) {
  if (sqlite3_libversion_number() != SQLITE_VERSION_NUMBER
      || strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID) != 0) {
    fprintf(stderr, "refused: header %d %s, library %d %s\n", SQLITE_VERSION_NUMBER,
            SQLITE_SOURCE_ID, sqlite3_libversion_number(), sqlite3_sourceid());
    exit(2);
  }
  printf("libversion: %s\n", sqlite3_libversion());
  printf("sourceid: %s\n", sqlite3_sourceid());
}

static sqlite3 *open_memory(void) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                           | SQLITE_OPEN_EXRESCODE | SQLITE_OPEN_FULLMUTEX, NULL);
  if (rc != SQLITE_OK) { fprintf(stderr, "open: %d\n", rc); exit(2); }
  return db;
}

static void column(sqlite3_stmt *s, int i) {
  switch (sqlite3_column_type(s, i)) {
  case SQLITE_INTEGER: printf("int %lld", (long long)sqlite3_column_int64(s, i)); break;
  case SQLITE_FLOAT: printf("real %.17g", sqlite3_column_double(s, i)); break;
  case SQLITE_TEXT: {
    const unsigned char *t = sqlite3_column_text(s, i);
    int n = sqlite3_column_bytes(s, i);
    printf("text \"%.*s\"", n, (const char *)t);
    break;
  }
  case SQLITE_BLOB: {
    const unsigned char *b = sqlite3_column_blob(s, i);
    int n = sqlite3_column_bytes(s, i);
    printf("blob x'");
    for (int k = 0; k < n; k++) printf("%02X", b[k]);
    printf("'");
    break;
  }
  default: printf("null");
  }
}

/* run: SQL with TEXT bound to ?1 when it is not NULL; every row printed. */
static void run_bound(sqlite3 *db, const char *sql, const char *text, const void *blob, int nblob) {
  sqlite3_stmt *s = NULL;
  printf("  %s", sql);
  if (text) printf("   [?1 = \"%s\"]", text);
  if (blob) {
    printf("   [?1 = x'");
    for (int k = 0; k < nblob; k++) printf("%02X", ((const unsigned char *)blob)[k]);
    printf("']");
  }
  printf("\n");
  int p = sqlite3_prepare_v2(db, sql, -1, &s, NULL);
  if (p != SQLITE_OK) {
    printf("    prepare %d, extended %d: %s\n", p, sqlite3_extended_errcode(db), sqlite3_errmsg(db));
    return;
  }
  if (text) sqlite3_bind_text(s, 1, text, -1, SQLITE_TRANSIENT);
  if (blob) sqlite3_bind_blob(s, 1, blob, nblob, SQLITE_TRANSIENT);
  int r, rows = 0;
  while ((r = sqlite3_step(s)) == SQLITE_ROW) {
    printf("    row:");
    for (int i = 0; i < sqlite3_column_count(s); i++) {
      printf(i ? ", " : " ");
      column(s, i);
    }
    printf("\n");
    rows++;
  }
  if (r == SQLITE_DONE)
    printf("    done, %d row%s\n", rows, rows == 1 ? "" : "s");
  else
    printf("    step %d, extended %d: %s\n", r, sqlite3_extended_errcode(db), sqlite3_errmsg(db));
  sqlite3_finalize(s);
}

static void run(sqlite3 *db, const char *sql) {
  run_bound(db, sql, NULL, NULL, 0);
}

static void f2(sqlite3 *db) {
  run(db, "create virtual table docs using fts5(title, body)");
  run(db, "insert into docs(rowid, title, body) values"
          " (1, '\xc3\x89lan vital', 'the caf\xc3\xa9 serves cr\xc3\xa8me br\xc3\xbbl\xc3\xa9""e'),"
          " (2, 'Second', 'sqlite full text search with fts5'),"
          " (3, 'Third', 'search engines rank documents and sqlite ranks them too')");
  run(db, "select rowid from docs where docs match 'sqlite' order by rank");
  run(db, "select rowid, bm25(docs) from docs where docs match 'search' order by rank");
  run(db, "select rowid from docs where docs match 'cafe'");
  run(db, "select rowid from docs where docs match 'caf\xc3\xa9'");
  run(db, "select rowid from docs where docs match 'creme'");
  run(db, "select highlight(docs, 1, '[', ']') from docs where docs match 'caf\xc3\xa9'");
  run(db, "select highlight(docs, 0, '[', ']') from docs where docs match 'elan'");
  run(db, "select snippet(docs, 1, '<', '>', '...', 3) from docs where docs match 'engines'");
  run(db, "select rowid from docs where docs match 'searc*' order by rowid");
  run(db, "select rowid from docs where docs match '\"full text\"'");
  run(db, "select rowid from docs where docs match 'NEAR(sqlite fts5, 3)'");
  run(db, "select rowid from docs where docs match 'title:second'");
  run(db, "select rowid from docs where docs match 'title:sqlite'");
  run(db, "select rowid from docs where docs match 'sqlite NOT fts5'");
  run_bound(db, "select rowid from docs where docs match ?1 order by rowid", "sqlite OR caf\xc3\xa9",
            NULL, 0);
  run(db, "select rowid from docs where docs match '\"unterminated'");
  run(db, "select rowid from docs where docs match 'nosuchcolumn:x'");
  run(db, "select rowid from docs where docs match 'AND'");
  run(db, "delete from docs where rowid = 2");
  run(db, "update docs set body = 'fts5 again' where rowid = 3");
  run(db, "select rowid from docs where docs match 'fts5' order by rowid");
  run(db, "insert into docs(docs) values ('optimize')");
  run(db, "insert into docs(docs) values ('integrity-check')");
  run(db, "select count(*) from docs");
  run(db, "create virtual table v using fts5vocab(docs, 'row')");
  run(db, "select term, doc, cnt from v where term in ('cafe', 'fts5', 'sqlite') order by term");
  run(db, "create virtual table t2 using fts5(x, tokenize = 'unicode61 remove_diacritics 0')");
  run(db, "insert into t2 values ('caf\xc3\xa9')");
  run(db, "select count(*) from t2 where t2 match 'cafe'");
  run(db, "select count(*) from t2 where t2 match 'caf\xc3\xa9'");
  run(db, "create virtual table t3 using fts5(x, tokenize = 'porter unicode61')");
  run(db, "insert into t3 values ('running runners ran')");
  run(db, "select count(*) from t3 where t3 match 'run'");
  run(db, "create virtual table t4 using fts5(x, tokenize = 'nosuchtokenizer')");
  run(db, "select fts5_source_id() is not null");
}

static void f3(sqlite3 *db) {
  run(db, "select json(' { \"a\" : [1, 2.5, \"x\", null, true] } ')");
  run(db, "select json('{')");
  run(db, "select json_valid('{\"a\":1}'), json_valid('{'), json_valid(NULL)");
  run(db, "select json_extract('{\"a\":{\"b\":[10,20]}}', '$.a.b[1]')");
  run(db, "select json_extract('{\"a\":{\"b\":[10,20]}}', '$.a.b')");
  run(db, "select json_extract('{\"a\":1}', '$.nosuch')");
  run(db, "select json_extract('{\"a\":1}', 'nopath')");
  run(db, "select '{\"a\":\"\xc3\xa9\"}' -> '$.a', '{\"a\":\"\xc3\xa9\"}' ->> '$.a'");
  run(db, "select '{\"a\":2.5}' ->> 'a', '[7,8]' ->> 1");
  run(db, "select json_type('{\"a\":[1]}', '$.a'), json_type('1.5'), json_type('null')");
  run(db, "select json_array_length('[1,2,3]'), json_array_length('{}')");
  run(db, "select key, value, type from json_each('{\"x\":1,\"y\":[2],\"z\":\"s\"}') order by key");
  run(db, "select fullkey, atom from json_tree('{\"a\":{\"b\":1}}') where atom is not null");
  run(db, "select jsonb('{\"a\":1}'), typeof(jsonb('{}')), typeof(json('{}'))");
  run(db, "select json(jsonb('{\"a\":[1,\"\xc3\xa9\"]}'))");
  run(db, "select jsonb_extract(jsonb('{\"a\":[1,2]}'), '$.a')");
  run(db, "select json_extract(jsonb('{\"a\":[1,2]}'), '$.a[0]')");
  run(db, "select json_insert('{\"a\":1}', '$.b', 2), json_set('{\"a\":1}', '$.a', 3),"
          " json_replace('{\"a\":1}', '$.c', 4), json_remove('[1,2,3]', '$[1]')");
  run(db, "select json_group_array(value) from (select 1 as value union all select 'x' union all"
          " select null)");
  run(db, "select json_group_object(k, v) from (select 'a' as k, 1 as v union all select 'b', 2)");
  run(db, "select json_quote('a\"b'), json_quote(1.5), json_quote(null)");
  run(db, "select json_object('k', 'v', 'n', 1), json_array(1, 'two', null)");
  run(db, "select json_error_position('{\"a\":}'), json_error_position('{\"a\":1}')");
  run(db, "select json_pretty('{\"a\":1}')");
  run(db, "select json_extract('[1e400]', '$[0]'), json_extract('[-1e400]', '$[0]')");
  run(db, "select json_extract('[9223372036854775807]', '$[0]'),"
          " json_extract('[9223372036854775808]', '$[0]')");
  run(db, "select json('\"\\u00e9\"'), json_extract('\"\\u00e9\"', '$')");
  run_bound(db, "select json(?1), json_valid(?1)", "[1, 2]", NULL, 0);
  static const unsigned char jb[] = {0x0C};
  run_bound(db, "select json(?1), json_valid(?1, 4), typeof(?1)", NULL, jb, 1);
  static const unsigned char bad[] = {0x01, 0x02};
  run_bound(db, "select json(?1)", NULL, bad, 2);
  run_bound(db, "select json_valid(?1, 8)", NULL, bad, 2);
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  version_lines();
  printf("\nF0. Compile options\n");
  const char *options[] = {"ENABLE_FTS5", "ENABLE_FTS4", "ENABLE_FTS3", "ENABLE_JSON1", "OMIT_JSON",
                           "ENABLE_LOAD_EXTENSION", "OMIT_LOAD_EXTENSION"};
  for (size_t i = 0; i < sizeof options / sizeof options[0]; i++)
    printf("  sqlite3_compileoption_used(\"%s\"): %d\n", options[i],
           sqlite3_compileoption_used(options[i]));

  sqlite3 *db = open_memory();
  printf("\nF1. Whether FTS5 is here\n");
  run(db, "select count(*) from pragma_module_list where name = 'fts5'");
  run(db, "create virtual table probe using fts5(body)");
  int fts5 = sqlite3_compileoption_used("ENABLE_FTS5");
  sqlite3_close(db);
  db = open_memory();
  if (fts5) {
    printf("\nF2. FTS5's behaviour\n");
    f2(db);
  } else {
    printf("\nF2. FTS5's behaviour: not run, the library lacks ENABLE_FTS5\n");
    run(db, "select fts5_source_id()");
    run(db, "select rowid from nosuch where nosuch match 'x'");
  }
  sqlite3_close(db);
  db = open_memory();
  printf("\nF3. JSON\n");
  f3(db);
  int c = sqlite3_close(db);
  if (c != SQLITE_OK) { fprintf(stderr, "close %d\n", c); return 2; }
  return 0;
}
