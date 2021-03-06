#lang typed/racket/base

(provide

  email->string

  university->string
  university-name

  person->short-name
  person->full-name
  person->adjective

  person-short-name
  person-full-name
  person-title
  person->mailto
  person->href
  person->image
  pi->history
  student-university
  student->university-id
  alma-mater

  make-student
  make-pi
  make-person
  make-university
  make-conference
  make-workshop

  venue->string

  (rename-out
   [make-publication publication]
   [publication-author* publication->author*]
   [publication-venue publication->venue])
  publication->name

  add-commas
  word*->string
  university*->string
  author*->string

  ->href
  string->id
)

(require
  (only-in racket/list add-between)
  racket/string
  typed/net/url
  typed/file/glob
)
(require/typed "util.rkt"
  (make-a (-> (U String URL) String Any)))

(require/typed racket/path
  (find-relative-path (-> Path-String Path-String Path)))

;; =============================================================================
;; --- Email Addresses

(struct email (
  [>string : String]
) #:transparent)

(define LETTER "[a-zA-Z0-9-]")
(define LETTER+ (string-append LETTER "+"))
(define DOMAIN (string-append LETTER+ "\\." LETTER+))
(define LOCALPART "[^@]+")
(define RX-EMAIL (pregexp (string-append "^" LOCALPART "@" LOCALPART "$")))

(: email-address? (-> String Boolean))
(define (email-address? str)
  (regexp-match? RX-EMAIL str))

(: string->email (-> String Email))
(define (string->email str)
  (unless (email-address? str)
    (raise-argument-error 'string->email "email-address?" str))
  (email str))

;; -----------------------------------------------------------------------------
;; --- Universities

(struct university (
  [name : String]
  [href : URL]
) #:transparent )
(define-type University university)

(: make-university (-> String #:href String University))
(define (make-university name
                         #:href href)
  (university name (string->url href)))

(: university->string (-> University Any))
(define (university->string uni)
  (make-a (university-href uni) (university-name uni)))

;; -----------------------------------------------------------------------------
;; --- Types for people / students / professors

(define-type Year Natural)
(define-type Degree (U 'reu 'phd 'me 'bse 'diplom 'ms 'msc 'postdoc 'bs 'bsc))
(define-type D+ (List Degree University Year))
(define-type Degree* (Listof D+))
(define-type Email email)
(define-type P+ (List University Year))
(define-type Position* (Listof P+))

(: add-student? (-> Degree Boolean))
(define (add-student? x)
  (and (memq x '(phd me bse ms msc bs bsc)) #t))

(: degree-year (-> (List Degree University Year) Year))
(define (degree-year d)
  (caddr d))

(: position-year (-> (List University Year) Year))
(define (position-year p)
  (cadr p))

(struct person (
  [short-name : String]
  [full-name  : String]
  [gender     : Symbol]
  [title      : String]
  [mailto     : (U #f Email)]
  [href       : URL]
  [degree*    : Degree*]
) #:transparent )
(define-type Person person)

(struct student person (
  [university : University]
) #:transparent )
(define-type Student student)

(struct pi person (
  [position* : Position*]
) #:transparent )
(define-type PI pi)

;; -----------------------------------------------------------------------------
;; --- Functions for people

(: make-person (->* [String #:title String #:href String] [#:full-name (U #f String) #:gender Symbol #:mailto (U #f String) #:degree* Degree*] Person))
(define (make-person short-name
                      #:title     title
                      #:href      href
                      #:degree*   [degree* '()]
                      #:mailto    [mailto #f]
                      #:gender    [gender 'M]
                      #:full-name [full-name #f])
  (person short-name
          (or full-name short-name)
          gender
          title
          (if mailto (string->email mailto) mailto)
          (string->url href)
          degree*))


(: make-pi (->* [String #:mailto String #:href String #:degree* Degree* #:position* Position* #:title String] [#:full-name (U #f String) #:gender Symbol] PI))
(define (make-pi short-name
                 #:mailto    mailto
                 #:href      href
                 #:degree*   degree*
                 #:position* position*
                 #:title title
                 #:gender    [gender 'M]
                 #:full-name [full-name #f])
  (pi short-name
      (or full-name short-name)
      gender
      title
      (string->email mailto)
      (string->url href)
      ((inst sort D+ Year) degree* > #:key degree-year)
      ((inst sort P+ Year) position* > #:key position-year)))

(: make-student (->* [String #:university University #:title (U Degree String) #:mailto (U #f String) #:href String #:degree* Degree*] [#:full-name (U #f String) #:gender Symbol] Student))
(define (make-student short-name
                      #:university uni
                      #:title     title
                      #:mailto    mailto
                      #:href      href
                      #:degree*   degree*
                      #:gender    [gender 'M]
                      #:full-name [full-name #f])
  (student short-name
           (or full-name short-name)
           gender
           (cond
            [(string? title) title]
            [else
             (string-append (degree->string title) (if (add-student? title) " Student" ""))])
           (if mailto (string->email mailto) mailto)
           (string->url href)
           degree*
           uni))

(: person->short-name (-> Person Any))
(define (person->short-name p)
  (make-a (person-href p) (person-short-name p)))

(: person->full-name (-> Person Any))
(define (person->full-name p)
  (make-a (person-href p) (person-full-name p)))

;; Person => His/Her
(: person->adjective (-> Person String))
(define (person->adjective p)
  (case (person-gender p)
    [(M) "his"]
    [(F) "her"]
    [else "their"]))

(: pi->history (-> PI (Listof Any)))
(define (pi->history pi)
  (append (for/list : (Listof Any)
                    ([p (in-list (pi-position* pi))])
            (P+->string p))
          (for/list : (Listof Any)
                    ([d (in-list (person-degree* pi))]
                     #:when (phd? d))
            (D+->string d))))

(: alma-mater (-> Person Any))
(define (alma-mater p)
  (define d* (person-degree* p))
  (if (null? d*)
    (format "Former ~a" (person-title p))
    (D+->string (car d*))))

(: phd? (-> D+ Boolean))
(define (phd? d+)
  (eq? 'phd (car d+)))

(: P+->string (-> P+ Any))
(define (P+->string pos)
  (list "Joined " (university->string (car pos)) ", " (cadr pos)))

(: D+->string (-> D+ Any))
(define (D+->string d+)
  (add-between (list (degree->string (car d+))
                     (university->string (cadr d+))
                     (caddr d+))
               ", "))

(: degree->string (-> Degree String))
(define (degree->string d)
  (case d
   [(phd) "Ph.D"]
   [(diplom) "Diplom"]
   [(ms) "M.S."]
   [(msc) "M.Sc."]
   [(postdoc) "Post-doc"]
   [(bs) "B.S."]
   [(bsc) "B.Sc."]
   [(reu) "REU"]
   [else (raise-argument-error 'degree->string "Unknown degree" d)]))

(: person->image (-> Person String))
(define (person->image p)
  (define id (string->id (person-short-name p)))
  (define pic* (glob (string-append "images/people/" id "*")))
  (if (null? pic*)
    "images/people/unknown.png"
    (begin
      (unless (null? (cdr pic*))
        (printf "WARNING: found multiple images matching '~a': ~a\n" id pic*))
      (path->string (find-relative-path (current-directory) (car pic*))))))

(: person->href (-> Person Any))
(define (person->href pi)
  (define href (url->string (person-href pi)))
  (make-a href href))

(: person->mailto (-> Person Any))
(define (person->mailto pi)
  (define maybe-e (person-mailto pi))
  (define mailto (if maybe-e (email->string maybe-e) ""))
  (make-a mailto mailto))

(: student->university-id (-> Student Symbol))
(define (student->university-id s)
  (string->symbol (university-name (student-university s))))

;; -----------------------------------------------------------------------------
;; --- Venue

(struct venue (
  [name : String]
  [year : Year]
  [href : URL]
) #:transparent )
(define-type Venue venue)

(struct conference venue () #:transparent)
(define-type Conference conference)

(: make-conference (-> String #:year Year #:href String Conference))
(define (make-conference name #:year year #:href href)
  (conference name year (string->url href)))

(struct workshop venue () #:transparent)
(define-type Workshop workshop)

(: make-workshop (-> String #:year Year #:href String Workshop))
(define (make-workshop name #:year year #:href href)
  (workshop name year (string->url href)))

(: venue->string (-> Venue Any))
(define (venue->string vnu)
  (make-a (venue-href vnu) (format "~a ~a" (venue-name vnu) (venue-year vnu))))

;; -----------------------------------------------------------------------------
;; --- Publications

(struct publication (
  [name : String]
  [href : URL]
  [author* : (Listof Person)]
  [venue : Venue]
) #:transparent )
(define-type Publication publication)

(: publication->year (-> Publication Year))
(define (publication->year pub)
  (venue-year (publication-venue pub)))

(: make-publication (-> #:title String #:href String #:author (U Person (Listof Person)) #:venue Venue Publication))
(define (make-publication #:title title #:href href #:author author #:venue venue)
  (publication title (string->url href) (if (list? author) author (list author)) venue))

(: publication->name (-> Publication Any))
(define (publication->name pub)
  (make-a (publication-href pub) (publication-name pub)))

(: word*->string (-> (Listof Any) Any))
(define (word*->string w*)
  (add-commas w* (lambda ([x : Any]) x)))

(: author*->string (-> (Listof Person) Any))
(define (author*->string a*)
  (add-commas a* person->full-name))

(: university*->string (-> (Listof University) Any))
(define (university*->string u*)
  (add-commas u* university->string))

(: add-commas (All (A) (-> (Listof A) (-> A Any) Any)))
(define (add-commas a* fmt)
  (cond
   [(null? a*)
    (raise-argument-error 'add-commas "Expected non-empty list of authors" a*)]
   [(null? (cdr a*))
    (list (fmt (car a*)))]
   [(null? (cddr a*))
    (list (fmt (car a*))
          " and "
          (fmt (cadr a*)))]
   [else
    ((inst add-between Any String) (map fmt a*) ", " #:before-last ", and ")]))

;; -----------------------------------------------------------------------------
;; --- Misc

(: ->href (-> (U Venue Publication Person University) Any))
(define (->href val)
  (cond
   [(venue? val)
    (venue->string val)]
   [(person? val)
    (person->short-name val)]
   [(publication? val)
    (publication->name val)]
   [(university? val)
    (university->string val)]
   [else
    (raise-argument-error '->href "Cannot convert value to href" val)]))

;(: make-a (-> (U URL String) String Any))
;(define (make-a href text)
;  (define str (if (url? href) (url->string href) href))
;  (element/not-empty 'a href: str text))
;  ;(a 'href str text))

(: string->id (-> String String))
(define (string->id str)
  (string-join (string-split (string-downcase str)) "-"))

;; =============================================================================

(module+ test
  (require typed/rackunit rackunit-abbrevs/typed)

  (check-apply* email-address?
   ["bob@bob.bob"
    => #t]
   ["obama@whitehouse.gov"
    => #t]
   ["HELLO-world@x.x"
    => #t]
   [""
    => #f]
   ["@@@"
    => #f]
   [".."
    => #f])

  (let ([str "yolo@wepa.net"])
    (check-equal? (email->string (string->email str)) str))
)

