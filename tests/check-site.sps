#!r6rs
;;; `make check-site` -- the gate that proves the generated site cannot rot
;;; silently. Named check-site.sps, as the other check programs are, not
;;; test-*.sps, which make test runs (SUITES), nor site-*.sps, the site's
;;; suites, which check-suites holds to site-exit-form: this program asserts
;;; on the REAL docs/*.md, not on fixtures, needs chez-cmark-gfm, which make
;;; test does not, and exits through die or (exit 0).
;;;
;;; NOT pure: imports (site render), which imports (cmark gfm) and so loads
;;; a shared object.
;;;
;;; From the repository root:
;;;   CHEZSCHEMELIBDIRS=.:build/akku/chez-cmark-gfm/src SITE_REF=main \
;;;     scheme --program tests/check-site.sps
;;; or simply `make check-site`.
;;;
;;; Asserts eight invariants, on render-site's return value and the files
;;; it reads -- no filesystem write, no `build/site/` dependency:
;;;   1. nav completeness -- (site pages) names exactly docs/*.md on disk,
;;;      the home page, its first, included.
;;;   2. anchor resolution -- render-site left no dangling intra-site link.
;;;   3. no relative .md leak -- every serialized href/src either resolves
;;;      to .html, is a same-page #anchor, or is an absolute (http...) URL;
;;;      none is a relative link still ending in .md.
;;;   4. no <pre> reflow -- the serializer never reindents preformatted code.
;;;   5. every relative link names a written file -- a page under the name
;;;      (site pages) writes it to, or the stylesheet.
;;;   6. every link out to the repository (a ../ escape) names a file the
;;;      checkout has.
;;;   7. the nav is README.org's list of the pages, in its "** Documentation"
;;;      section, its pages in its order, under its labels, so the home page
;;;      is that list's first.
;;;   8. every page's first line is "# " and its nav label, so a label and
;;;      its page's H1 cannot drift apart.
;;;
;;; Each invariant `die`s with its own name on failure and exits 1, so a
;;; caller reading this program's stderr learns which invariant broke.
(import (rnrs) (only (chezscheme) getenv directory-list)
        (site io) (site render) (site pages) (site serializer)
        (only (site links) repo-blob))

(define (die . parts)
  (for-each (lambda (x) (display x (current-error-port))) parts)
  (newline (current-error-port))
  (exit 1))

;; --- small string helpers, deliberately dumb ------------------------------
;; No general HTML/URL parsing anywhere below: (3)'s scan only ever asks two
;; questions of an already-delimited attribute value ("does it start with
;; http", "does it end in .md or carry .md#"), so a fragile hand-rolled URL
;; parser would buy nothing a straight substring search doesn't already give.

(define (string-starts-with? prefix s)
  (and (>= (string-length s) (string-length prefix))
       (string=? prefix (substring s 0 (string-length prefix)))))

(define (string-ends-with? suffix s)
  (let ((ls (string-length s)) (lf (string-length suffix)))
    (and (>= ls lf) (string=? suffix (substring s (- ls lf) ls)))))

(define (string-contains? needle hay)
  (let ((hn (string-length hay)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? needle (substring hay i (+ i nn))) #t)
            (else (loop (+ i 1)))))))

;; Index of the first occurrence of `needle` in `hay` at or after `start`,
;; or #f. Used only to find the closing '"' of an attribute value.
(define (string-search hay needle start)
  (let ((hn (string-length hay)) (nn (string-length needle)))
    (let loop ((i start))
      (cond ((> (+ i nn) hn) #f)
            ((string=? needle (substring hay i (+ i nn))) i)
            (else (loop (+ i 1)))))))

(define (md-file-name? name)
  (and (string-ends-with? ".md" name) (> (string-length name) 3)))

;; --- (1) nav completeness -------------------------------------------------
;; (site pages)'s own file (site/pages.sls) is documented as "the nav's
;; single source of order and labels"; this asserts that it names exactly
;; the docs/*.md files on disk, the home page included. Named by the actual
;; set difference in each direction, not by dumping both full lists, so the
;; failure reads as "here is what's wrong" rather than "here is everything,
;; go diff it".
(define (list-minus a b) (filter (lambda (x) (not (member x b))) a))

(define nav-docs
  (list-sort string<? (map car pages)))
(define disk-docs
  (list-sort string<? (filter md-file-name? (directory-list "docs"))))

(define missing-from-nav (list-minus disk-docs nav-docs))  ; on disk, absent from the nav
(define extra-in-nav (list-minus nav-docs disk-docs))      ; in the nav, absent from disk

(unless (and (null? missing-from-nav) (null? extra-in-nav))
  (die "check-site: nav completeness FAILED. "
       "missing-from-site/pages.sls=" missing-from-nav " "
       "extra-in-site/pages.sls=" extra-in-nav))

;; --- render the real site once, for checks (2) and (3) --------------------
(define ref (or (getenv "SITE_REF") "main"))
(define result (render-site (read-site-inputs) ref))

;; --- (2) anchor resolution -------------------------------------------------
;; site-result-leaked is render-site's own accumulator of every href/src
;; whose target -- a same-page #slug or a cross-page page.md#slug -- was not
;; found in the id-registry built from every page's actual headings. An
;; empty list here is also the only mechanism proving the slug algorithm
;; (site/slug.sls) matches the anchors docs/*.md write by hand in prose.
(unless (null? (site-result-leaked result))
  (die "check-site: anchor resolution FAILED. danglers=" (site-result-leaked result)))

;; --- (3) no relative .md leak ----------------------------------------------
;; Find every href="..."/src="..." VALUE in a serialized page and flag one
;; that (a) does not start with "http" -- ruling out the absolute GitHub
;; blob URLs a ../ escape produces, which legitimately end in .md -- and
;; (b) ends in ".md" or carries ".md#" -- a relative link (site/links.sls)
;; failed to rewrite to .html. escape-attr (site/serializer.sls) turns any
;; literal '"' inside an attribute's own text into &quot; before this string
;; ever exists, so scanning for the next bare '"' to close the value is safe
;; -- it can never fire early on a quote that is part of the value itself.
(define (attr-values html marker)
  (let ((hn (string-length html)) (mn (string-length marker)))
    (let loop ((i 0) (acc '()) (in-tag #f))
      (cond
        ((> (+ i mn) hn) (reverse acc))
        ((char=? (string-ref html i) #\<) (loop (+ i 1) acc #t))
        ((char=? (string-ref html i) #\>) (loop (+ i 1) acc #f))
        ((and in-tag (string=? marker (substring html i (+ i mn))))
         (let* ((start (+ i mn))
                (end (or (string-search html "\"" start) hn)))
           (loop (+ end 1) (cons (substring html start end) acc) #t)))
        (else (loop (+ i 1) acc in-tag))))))

;; Only markup is scanned. escape-text turns every < and > in text into
;; &lt; and &gt;, so a raw < opens a tag and a raw > closes it. Text is not
;; scanned: a code sample showing href="x.md" is not a link. This probe holds
;; that: a code sample with an href in it, then a real link.
(let ((probe (sxml->html '(p (code "<a href=\"x.md\">") (a (^ (href "y.md")) "y")))))
  (unless (equal? (attr-values probe "href=\"") '("y.md"))
    (die "check-site: the link scan reads text as links: "
         (attr-values probe "href=\""))))

(define (relative-md-leak? v)
  (and (not (string-starts-with? "http" v))
       (or (string-ends-with? ".md" v) (string-contains? ".md#" v))))

(define (leaked-md-values html)
  (filter relative-md-leak?
          (append (attr-values html "href=\"") (attr-values html "src=\""))))

(for-each
  (lambda (pg)
    (let* ((html (sxml->html (cdr pg)))
           (leaks (leaked-md-values html)))
      (unless (null? leaks)
        (die "check-site: a relative .md link leaked into " (car pg) ": " leaks))))
  (site-result-pages result))

;; --- (5) every relative link names a written file ---------------------------
;; A relative href/src must name a file `make site` writes: a page, by the
;; name (site pages) gives it, or the stylesheet. Without this, a home page
;; written under its own name, not index.html, which the wordmark links,
;; passes (2), which looks pages up by their .md name, and (3), which only
;; looks for .md.
(define written
  (cons "style.css" (map (lambda (pg) (page-file-name (car pg))) pages)))

(define (link-path v)
  (let ((hash (string-search v "#" 0)))
    (if hash (substring v 0 hash) v)))

(define (unwritten-targets html)
  (filter (lambda (v)
            (let ((path (link-path v)))
              (and (not (string-starts-with? "http" v))
                   (not (string=? path ""))
                   (not (member path written)))))
          (append (attr-values html "href=\"") (attr-values html "src=\""))))

(for-each
  (lambda (pg)
    (let ((bad (unwritten-targets (sxml->html (cdr pg)))))
      (unless (null? bad)
        (die "check-site: a link names a file the site does not write, in "
             (car pg) ": " bad))))
  (site-result-pages result))

;; --- (6) every link out to the repository names a file it has -------------
;; A ../ escape becomes a GitHub URL under repo-blob at SITE_REF, which
;; nothing on the site resolves. The file it names must exist in this
;; checkout, or the published page links to a 404.
(define blob-prefix (string-append repo-blob ref "/"))

(define (missing-repo-files html)
  (filter (lambda (v)
            (and (string-starts-with? blob-prefix v)
                 (let ((path (link-path (substring v (string-length blob-prefix)
                                                   (string-length v)))))
                   (or (string-starts-with? "../" path)
                       (not (file-exists? path))))))
          (attr-values html "href=\"")))

(for-each
  (lambda (pg)
    (let ((bad (missing-repo-files (sxml->html (cdr pg)))))
      (unless (null? bad)
        (die "check-site: a link out to the repository names no file in it, in "
             (car pg) ": " bad))))
  (site-result-pages result))

;; --- (7) the nav is README.org's list of the pages ----------------------------
;; README.org lists the pages: each an Org link [[file:docs/PAGE.md][LABEL]],
;; on any line of its "** Documentation" section, after its heading and up to
;; the next heading of any level. A link into docs/ elsewhere in the file lists
;; no page, and a README.org with no such section, or with two, fails, naming
;; it: the nav is held to that one list. (site pages) must be those links, in
;; order: so a page listed there and not in the nav, a label changed in one
;; alone, or two pages swapped, fails, and the home page, the nav's first, is
;; the list's first. A link into docs/ that names no .md file, as
;; [[file:docs/][docs/]] does, lists no page.
(define (file-lines path)
  (call-with-input-file path
    (lambda (p)
      (let loop ((acc '()))
        (let ((line (get-line p)))
          (if (eof-object? line) (reverse acc) (loop (cons line acc))))))))

;; org-heading? : String -> Boolean
;; Whether LINE is an Org heading: one or more stars, then a space.
(define (org-heading? line)
  (let ((n (string-length line)))
    (let loop ((i 0))
      (cond ((= i n) #f)
            ((char=? (string-ref line i) #\*) (loop (+ i 1)))
            (else (and (> i 0) (char=? (string-ref line i) #\space)))))))

;; documentation-lines : (Listof String) -> (Listof String)
;; The lines of the "** Documentation" section of README.org's LINES, after
;; its heading and up to the next heading. It dies, naming the section, when
;; README.org has none, or more than one.
(define (documentation-lines lines)
  (let ((tail (member "** Documentation" lines)))
    (unless tail
      (die "check-site: README.org has no \"** Documentation\" section, the list of the pages the nav is held to"))
    (when (member "** Documentation" (cdr tail))
      (die "check-site: README.org has more than one \"** Documentation\" section: the nav is held to one list of the pages"))
    (let loop ((ls (cdr tail)) (acc '()))
      (if (or (null? ls) (org-heading? (car ls)))
          (reverse acc)
          (loop (cdr ls) (cons (car ls) acc))))))

;; docs-links : (Listof String) -> (Listof (Pairof String String))
;; The (page . label) of each [[file:docs/PAGE.md][LABEL]] in LINES, in
;; order. It dies, naming the line, on such a link with no label, or one
;; that no ]] closes on its line.
(define (docs-links lines)
  (let ((open "[[file:docs/"))
    (let line-loop ((ls lines) (acc '()))
      (if (null? ls)
          (reverse acc)
          (let ((line (car ls)))
            (let link-loop ((i 0) (acc acc))
              (let ((at (string-search line open i)))
                (if (not at)
                    (line-loop (cdr ls) acc)
                    (let* ((start (+ at (string-length open)))
                           (close (string-search line "]" start)))
                      (unless close
                        (die "check-site: README.org has a link into docs/ that no ] closes: " line))
                      (let ((target (substring line start close))
                            (rest (substring line close (string-length line))))
                        (cond
                          ((not (md-file-name? target)) (link-loop close acc))
                          ((not (string-starts-with? "][" rest))
                           (die "check-site: README.org links docs/" target
                                " with no label: " line))
                          (else
                           (let ((end (string-search line "]]" (+ close 2))))
                             (unless end
                               (die "check-site: README.org's link to docs/" target
                                    " has a label that no ]] closes on its line: " line))
                             (link-loop (+ end 2)
                                        (cons (cons target (substring line (+ close 2) end))
                                              acc)))))))))))))))

(let ((listed (docs-links (documentation-lines (file-lines "README.org")))))
  (unless (equal? listed pages)
    (die "check-site: the nav is not README.org's list of the pages. "
         "listed=" listed " nav=" pages)))

;; --- (4) no <pre> reflow ----------------------------------------------------
;; A fixed probe, independent of the real corpus: a deeply-indented code
;; block must round-trip byte-for-byte, so `make check-site` alone catches
;; a serializer that reindents preformatted code.
(let ((probe (sxml->html '(pre (code "a\n        b\n")))))
  (unless (string=? probe "<pre><code>a\n        b\n</code></pre>")
    (die "check-site: <pre> reflow FAILED: " probe)))

;; --- (8) every page's H1 is its nav label -------------------------------------
;; A page's first line must be "# " and its label in (site pages). (7) holds
;; the labels to README.org's; this holds the pages' headings to both: a
;; heading changed on its page alone, or a label changed in the nav and
;; README.org and not on its page, fails, naming the page, the line it wants
;; and the line it found.
(for-each
  (lambda (pg)
    (let* ((path (string-append "docs/" (car pg)))
           (lines (file-lines path))
           (want (string-append "# " (cdr pg))))
      (unless (and (pair? lines) (string=? (car lines) want))
        (die "check-site: a page's H1 is not its nav label, in " path ": wanted \"" want
             "\" as its first line, found "
             (if (pair? lines) (string-append "\"" (car lines) "\"") "an empty page")))))
  pages)

(display "check-site: nav, anchors, no .md leak, every link written, repository links exist, nav is README.org's list, no <pre> reflow, each page's H1 its label -- all green\n")
(exit 0)
