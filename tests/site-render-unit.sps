#!r6rs
;;; The docs site's whole pipeline, (site render), on small inputs: markdown
;;; through chez-cmark-gfm, headings slugged, links rewritten across pages,
;;; each page templated.  Imports (cmark gfm), which loads libcmark-gfm.  Not
;;; named test-*.sps, so `make test` does not run it; `make check-site` does.
;;; From the repository root:
;;;   CHEZSCHEMELIBDIRS=.:build/akku/chez-cmark-gfm/src:tests:build/scheme-libs \
;;;     scheme --program tests/site-render-unit.sps
;;;
;;; The home page is the first of (site pages)' pages, whatever docs/ holds,
;;; and the other page an input names, guide.md, is one docs/ never holds.
;;; A suite's top-level definition that raises ends it naming no test, so
;;; each that can raise answers what it raised instead, and every row that
;;; reads it fails by name.
(import (rnrs) (srfi :64) (site-testing) (site render) (site serializer)
        (only (site pages) pages page-file-name))

;; string-contains-sub? : String String -> Boolean
(define (string-contains-sub? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

;; count-substring : String String -> Integer
;; Non-overlapping occurrences of NEEDLE in HAY.
(define (count-substring hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0) (count 0))
      (cond ((> (+ i n) h) count)
            ((string=? needle (substring hay i (+ i n))) (loop (+ i n) (+ count 1)))
            (else (loop (+ i 1) count))))))

;; page-html : SiteResult String -> String
(define (page-html r name)
  (sxml->html (cond ((assoc name (site-result-pages r)) => cdr)
                    (else (error 'site-render-unit "page missing" name)))))

;; rendered : (Listof (Pairof String String)) -> (U SiteResult (List 'raised Any))
;; render-site's answer for INPUTS at the ref main, or what it raised.
(define (rendered inputs)
  (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
    (render-site inputs "main")))

;; html-of : (U SiteResult (List 'raised Any)) String -> String
;; The page NAME of R as HTML, or a line naming why there is none, which no
;; row below finds what it looks for in.
(define (html-of r name)
  (guard (e (#t (string-append "no page " name)))
    (page-html r name)))

(define home (guard (e (#t "no-home-page.md")) (car (car pages))))
(define home-label (guard (e (#t "no home page")) (cdr (car pages))))

;; Two pages; the home page links to a heading on guide.md, and guide.md
;; links back to the home page.  The anchor is only knowable after guide.md
;; is slugged.
(define inputs
  `((,home . "# Home\n\nSee [reading](guide.md#reading-a-request).\n")
    ("guide.md" . ,(string-append "# Guide\n\n## Reading a request\n\ntext\n\n"
                                  "### The path\n\nmore text\n\n[home](" home ")\n"))))

(define r (rendered inputs))
(define guide-html (html-of r "guide.md"))
(define home-html (html-of r home))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-render-unit")

(test-equal "every input yields a page, in input order"
  (list home "guide.md") (map car (site-result-pages r)))
(test-equal "the registry carries every one of a page's heading slugs, its h1 included"
  '("guide" "reading-a-request" "the-path")
  (cond ((assoc "guide.md" (site-result-registry r)) => cdr) (else 'missing)))
(test-equal "resolvable cross-page links, the home page among them, do not dangle"
  '() (site-result-leaked r))

(test-equal "the rail links the h2 anchor, and neither the h1's nor the h3's"
  '(#t #f #f)
  (list (string-contains-sub? guide-html "href=\"#reading-a-request\"")
        (string-contains-sub? guide-html "href=\"#guide\"")
        (string-contains-sub? guide-html "href=\"#the-path\"")))
(test-eq "an h3 remains a rendered link target" 'present
  (if (string-contains-sub? guide-html "id=\"the-path\"") 'present 'missing))
;; The wordmark, the home page's nav entry and the page's own link to it.
(test-equal "a link to the home page is written as index.html, beside the wordmark's and the nav's, and none keeps its .md name"
  '(3 #f)
  (list (count-substring guide-html "href=\"index.html\"")
        (string-contains-sub? guide-html (string-append "href=\"" home))))
(test-equal "a page that is in no nav is titled by its file name"
  '(#t) (list (string-contains-sub? guide-html "<title>guide.md</title>")))

;; The home page is a page of the nav: its own entry links index.html too,
;; marked as the current page.
(test-equal "on the home page, index.html is linked by the wordmark and by its own nav entry, marked"
  '(2 #t)
  (list (count-substring home-html "href=\"index.html\"")
        (string-contains-sub?
         home-html (string-append "<a href=\"index.html\" class=\"on\" aria-current=\"page\">"
                                  home-label "</a>"))))
(test-equal "the home page's title is its nav label"
  '(#t) (list (string-contains-sub? home-html (string-append "<title>" home-label "</title>"))))

;; --- the footer's neighbours -------------------------------------------
(define nav3 '(("a.md" . "A") ("b.md" . "B") ("c.md" . "C")))
;; both : (-> (Values Any Any)) -> (List Any Any)
(define (both thunk) (call-with-values thunk list))

(test-equal "the first page's neighbours: none before it, and the next after"
  '(#f ("b.md" . "B")) (both (lambda () (neighbors nav3 "a.md"))))
(test-equal "a middle page's neighbours: the pages either side of it"
  '(("a.md" . "A") ("c.md" . "C")) (both (lambda () (neighbors nav3 "b.md"))))
(test-equal "the last page's neighbours: the page before it, and none after"
  '(("b.md" . "B") #f) (both (lambda () (neighbors nav3 "c.md"))))
(test-equal "a page not in the nav has no neighbours"
  '(#f #f) (both (lambda () (neighbors nav3 "d.md"))))

;; pagenav-of : String -> (U String #f) — the footer div of HTML, whole.
(define (pagenav-of html)
  (let ((open "<div class=\"pagenav\">"))
    (let loop ((i 0))
      (cond ((> (+ i (string-length open)) (string-length html)) #f)
            ((string=? open (substring html i (+ i (string-length open))))
             (let find ((j i))
               (cond ((> (+ j 6) (string-length html)) #f)
                     ((string=? "</div>" (substring html j (+ j 6)))
                      (substring html i (+ j 6)))
                     (else (find (+ j 1))))))
            (else (loop (+ i 1)))))))

;; expected-pagenav : String -> (U String #f) — the footer for NAME's place
;; in (site pages)' pages, read here from the list itself: a link to each
;; neighbour, labelled, or an empty span on a side with none; and no footer
;; when there is neither.
(define (expected-pagenav name)
  (let* ((names (map car pages))
         (before (let loop ((ps pages) (prev #f))
                   (if (string=? (caar ps) name) prev (loop (cdr ps) (car ps)))))
         (after (let ((tail (member name names)))
                  (and (pair? (cdr tail)) (assoc (cadr tail) pages)))))
    (and (or before after)
         (string-append
          "<div class=\"pagenav\">"
          (if before
              (string-append "<a href=\"" (page-file-name (car before))
                             "\"><span class=\"lbl\">Previous</span>\x2190; " (cdr before) "</a>")
              "<span></span>")
          (if after
              (string-append "<a href=\"" (page-file-name (car after))
                             "\" class=\"next\"><span class=\"lbl\">Next</span>" (cdr after) " \x2192;</a>")
              "<span></span>")
          "</div>"))))

;; Every page of the nav rendered, each its h1 alone: each page's footer is
;; the one its place in the nav calls for.
(let ((site (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
              (rendered (map (lambda (p) (cons (car p) (string-append "# " (cdr p) "\n"))) pages)))))
  (test-equal "each page's footer links its neighbours in the nav, or is absent with none"
    (map (lambda (p) (guard (e (#t (list 'raised (car p)))) (expected-pagenav (car p)))) pages)
    (map (lambda (p) (pagenav-of (html-of site (car p)))) pages)))

;; A warning-led blockquote passes through the whole pipeline as a callout.
(test-eq "a warning blockquote is rendered inside a callout div" 'present
  (if (string-contains-sub? (html-of (rendered '(("guide.md" . "> ⚠️ Answer quickly.\n")))
                                     "guide.md")
                            "<div class=\"callout warning\"><blockquote>")
      'present 'missing))

(test-equal "an unresolvable cross-page anchor is reported"
  '(("guide.md" . "other.md#gone"))
  (site-result-leaked
   (rendered '(("guide.md" . "[x](other.md#gone)\n") ("other.md" . "# Other\n")))))
(test-equal "an unresolvable anchor of the home page is reported"
  `(("guide.md" . ,(string-append home "#gone")))
  (site-result-leaked
   (rendered `((,home . "# Home\n")
               ("guide.md" . ,(string-append "[x](" home "#gone)\n"))))))
(test-equal "danglers across pages come back in page order"
  '(("guide.md" . "#a") ("other.md" . "#b"))
  (site-result-leaked
   (rendered '(("guide.md" . "[x](#a)\n") ("other.md" . "[y](#b)\n")))))

(test-end "site-render-unit")

(exit (site-exit-status runner))
