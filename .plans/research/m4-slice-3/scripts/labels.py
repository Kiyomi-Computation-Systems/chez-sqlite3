"""The mutation log's labels for the rows of M4 slice 3's suites: each a
suite's name and a row title's start. A row with no label is named by the
first 48 characters of its title, for M3's and slice 1's rows."""

LABELS = {
    "test-settings": [
        ("(chez-sqlite3 private settings) exports", "s-exports"),
        ("setting-names, written out", "s-setting-names"),
        ("the four are in the live list", "s-in"),
        ("db-config-settings' ops are constants.sls's", "s-ops-const"),
        ("there are 3,914", "s-join-count"),
        ("every ordering of every subset of two sets", "s-join-order"),
        ("all eleven, in an order", "s-join-whole"),
        ("each of the four through the plan", "s-join-domain"),
        ("a name given twice among the four", "s-join-twice"),
        ("the one pass holds the four", "s-join-pass"),
        ("db-config-step? holds each step", "s-step?"),
        ("db-config-step? holds nothing else", "s-step?-not"),
        ("steps-opt-in? reads the opt-in", "s-opt-in"),
        ("steps-opt-in? holds only", "s-opt-in-only"),
        ("unknown-setting's and setting-out-of-domain's messages", "s-messages"),
        ("a read-back that answered no row, none, reads", "s-no-row"),
        ("db-config-settings, written out", "s-table"),
        ("each step, written out", "s-steps"),
        ("each of the four against every value of the universe", "s-domain"),
        ("db-config-sentinel, what the cell holds", "s-sentinel"),
    ],
    "test-open-settings": [
        ("each of db_config's four, #t and #f, is accepted by open-database on :memory:", "o-accept"),
        ("each of db_config's four, #t and #f, is accepted the same on a file", "o-accept-file"),
        ("each raise site's with-exception-handler", "o-depth"),
    ],
    "test-open-db-config": [
        ("native records sqlite3_load_extension as a boolean", "c-sentinel"),
        ("each set held: ", "c-held"),
        ("each set held the same through call-with-database", "c-held-cwd"),
        ("each set held on every connection", "c-held-kinds"),
        ("the library's start is read", "c-start-read"),
        ("each start unasked", "c-start"),
        ("a list naming one op", "c-start-one"),
        ("where an entry point every open runs", "c-switch-on"),
        ("an entry point every open runs moves each", "c-moved"),
        ("over the moved starts, a connection open-database opens", "c-moved-unasked"),
        ("over the moved starts, each list of one op reads", "c-moved-held"),
        ("over the moved starts, each list of one op leaves", "c-moved-others"),
        ("over the moved starts, settings beside PRAGMAs", "c-moved-beside"),
        ("the order across PRAGMAs and sets", "c-order"),
        ("database-extension-loading? makes the owner check", "c-opt-in-thread"),
        ("under defensive", "c-writable"),
        ("with dqs-dml off", "c-dqs"),
        ("a stand-in that answers 0 and writes the value", "c-match"),
        ("a set's failures and mismatches through a stand-in", "c-failures"),
        ("a failure's code is the call's own", "c-code"),
        ("after a constraint's failure", "c-message"),
        ("each set is made once", "c-once"),
        ("a set that matched before one that fails", "c-once-fail"),
        ("a close that fails after a set's failure", "c-close-fails"),
        ("the record holds the opt-in", "c-opt-in"),
        ("database-extension-loading? checks", "c-opt-in-check"),
        ("each of the four's values outside its domain", "c-refusals"),
        ("every other op of 3.45.1's", "c-complement"),
        ("all four among the six", "c-six"),
        ("each new raise site's", "c-depth"),
        ("every count is zero at the end", "c-end"),
    ],
    "test-open-db-config-engines": [
        ("the clean answer", "e-clean"),
        ("open-database with the three ops and the opt-in among the six PRAGMAs and statement-cache on a file, as an engine", "e-fuel"),
        ("open-database's remainder resumed twice", "e-twice"),
        ("call-with-database with the ops re-entered", "e-reentry"),
        ("call-with-database with the ops on a file, as an engine", "e-cwd"),
        ("open-database's remainder R with the ops", "e-interleave"),
        ("applied-settings/with on a connection of the suite's", "e-once"),
        ("applied-settings/with whose stand-in fails", "e-failing"),
    ],
    "test-public": [
        ("(chez-sqlite3) exports 69", "p-count"),
        ("(chez-sqlite3) exports exactly", "p-list"),
        ("(chez-sqlite3 private connection) exports", "p-conn"),
        ("(chez-sqlite3 private open) exports", "p-open"),
        ("each public name is the procedure", "p-eq"),
    ],
    "test-reference": [
        ("sqlite-extensions-unavailable?'s entry", "r-line"),
    ],
    "test-library-loading-real": [
        ("decoy lacks-sqlite3_load_extension: an open that opts in", "l-lacking"),
        ("decoy control: the control, with the entry point", "l-control"),
        ("decoy lacks-sqlite3_load_extension: (enable-load-extension . #f)", "l-false"),
    ],
}


def label_of(suite, title):
    for prefix, label in LABELS.get(suite, []):
        if title.startswith(prefix):
            return label
    return "'" + title[:48] + "'"
