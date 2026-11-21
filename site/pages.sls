#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site pages)
  (export pages page-file-name)
  (import (rnrs))

  ;; pages : (Listof (Pairof String String))
  ;; The nav's single source of order and labels: each docs/ file and its
  ;; label, README.org's list of the pages under its ** Documentation
  ;; heading, in its order and under its labels. The first, the quick
  ;; start, is the home page. tests/check-site.sps asserts the file set here
  ;; equals docs/*.md, and the whole list equals README.org's.
  (define pages
    '(("quickstart.md" . "Quick start")
      ("examples.md" . "Examples")
      ("finding-sqlite.md" . "Finding SQLite")
      ("libraries.md" . "What varies by library")
      ("reference.md" . "API reference")))

  ;; page-file-name : String -> String
  ;; The file a page is written to: the home page, the first of `pages`, as
  ;; index.html, and any other page.md as page.html. tests/check-site.sps
  ;; holds every relative link to these names.
  (define (page-file-name name)
    (if (string=? name (car (car pages)))
        "index.html"
        (string-append (substring name 0 (- (string-length name) 3)) ".html"))))
