;; =========================================================================
;; GENERARE GRINZI SI BUIANDRUGI - desfasoara automat grinzile (G) si
;; buiandrugii (B) de pe planul de cofraj selectat.
;; Compatibil AutoCAD 2024. Desenul e in mm, numele in cm.
;;
;; Comanda: GenerareGrinziBuiandrugi
;;
;; Ce se citeste din selectie (restul e ignorat):
;;   - "Markers": numele elementelor, ex "G1 30x40" (grinda), "B2 30x55"
;;     (buiandrug), "C1 30x25" (centura - doar ca reazem); latime x
;;     inaltime in cm. "BP ..." (buiandrugi porotherm) se ignora.
;;   - "Grinzi": liniile grinzilor si buiandrugilor; "Centuri": ale
;;     centurilor (linii sau polilinii, ortogonale)
;;   - "Stalpi": stalpii (polilinii inchise)
;;   - "Axe": liniile de axe si numele lor (in cercurile de la capete)
;;   - "Cofrag": grupurile cu sectiunea mica prin element (hasura,
;;     cote, cote de nivel cu field). Sectiunea apartine elementului care
;;     are aceleasi doua fete ca ea; din grup se ia textul liber (cota de
;;     sus) si textul cu field (cota de jos), plus cotele (ex 14 + 11).
;;
;; Ce deseneaza, pentru fiecare element, intr-un rand, toate cu fata de
;; sus la acelasi nivel:
;;   - dreptunghiul elementului (layer 0), lung de la marginea exterioara
;;     a reazemului din stanga pana la a celui din dreapta, inalt cat
;;     inaltimea din nume; carcasa (FIER) la 25 mm in interior
;;   - reazemele, ca grupuri pe layer 0: stalpul (latimea lui, inalt de
;;     30 cm, hasura ANSI31) sub element; grinda pe care reazema
;;     (sectiunea ei, hasurata); la buiandrugi, capatul fara stalp primeste
;;     caramida (30 cm lat, hasura AR-B88)
;;   - etrierii (LINE pe "Otel etrieri", %%C8):
;;       grinzi: pe fiecare deschidere, zona de capat = 1/4 din lumina,
;;         rotunjita in sus la 5 cm; din punctul de impartire se merge cu
;;         10 cm spre stalp (fara sa intre in el), in mijloc cu 15 cm de
;;         la stanga la dreapta, apoi iar 10 cm pana la stalpul din dreapta
;;       buiandrugi: la 15 cm, peste tot in afara de stalpi (si peste
;;         caramida); ultimul se pune la capat, ca sa nu ramana mai mult
;;         de 15 cm
;;   - lantul de cote de sus (stalpi si zonele de etrieri) cu
;;     "etr. %%C8/10" / "etr. %%C8/15" sub el; lantul de jos (reazeme si
;;     deschideri)
;;   - axele care trec prin reazeme, cu numele lor
;;   - cota de inaltime si cotele de nivel (grup pe "Cote"): sus cota
;;     data la pornire, jos un FIELD = cota de sus - cota de inaltime
;;   - sectiunea "xx" (grup pe "Sectiuni grinzi"), in prima treime a
;;     primei deschideri, de la reazemul din stanga; textul "xx" are
;;     punctul de insertie in dreapta jos
;;   - deasupra: "G1 30x40 1buc." si "Scara 1:50" ("Bucati element");
;;     elementele identice (acelasi nume, aceeasi geometrie) se deseneaza
;;     o singura data, cu numarul de bucati
;;
;; Greselile gasite (latimea din nume diferita de plan, inaltimea din
;; nume diferita de grupul de cofraj, cote de nivel lipsa, capete fara
;; reazem, ...) apar intr-o fereastra la final si sunt marcate pe plan
;; cu un cerc rosu numerotat (layer "Erori grinzi", neprintabil; marcajele
;; vechi se sterg la fiecare rulare).
;; Toata generarea se anuleaza cu un singur U.
;; =========================================================================
(vl-load-com)

;; ---------------- parametri ----------------
(setq gb:*tol*      2.0)     ; toleranta de coordonate (mm)
(setq gb:*acop*     25.0)    ; carcasa fata de marginea elementului (mm)
(setq gb:*h-reazem* 300.0)   ; inaltimea desenata a stalpului / caramizii (mm)
(setq gb:*l-caram*  300.0)   ; latimea caramizii la buiandrugi (mm)
(setq gb:*pas-cap*  100.0)   ; pasul etrierilor la capete, grinzi (mm)
(setq gb:*pas-mij*  150.0)   ; pasul etrierilor in camp / la buiandrugi (mm)
(setq gb:*desc-mica* 1200.0) ; grinzi cu lumina mai mica: toti etrierii la 15 cm (mm)
(setq gb:*etr-dist* 50.0)    ; primul etrier de la capatul liber al buiandrugului (mm)
(setq gb:*lat-etr*  280.0)   ; jumatate din latimea textului "etr. %%C8/15" (mm)
(setq gb:*diam*     "%%C8")
(setq gb:*spatiu*   1800.0)  ; distanta intre desfasurate (mm)
(setq gb:*sect-max* 1500.0)  ; cat de departe de element poate sta sectiunea de cofraj (mm)

(setq gb:*l-markers* "MARKERS")
(setq gb:*l-grinzi*  "GRINZI")
(setq gb:*l-centuri* "CENTURI")
(setq gb:*l-stalpi*  "STALPI")
(setq gb:*l-axe*     "AXE")
(setq gb:*l-cofrag*  "COFRAG")

(setq gb:*l-elem*    "0")
(setq gb:*l-fier*    "FIER")
(setq gb:*l-etr*     "Otel etrieri")
(setq gb:*l-cote*    "Cote")
(setq gb:*l-axe-d*   "Axe")
(setq gb:*l-sect*    "Sectiuni grinzi")
(setq gb:*l-bucati*  "Bucati element")
(setq gb:*l-erori*   "Erori grinzi")
(setq gb:*ds*        "Centimetri 50 cu virgula")
(setq gb:*st-text*   "cezar")
(setq gb:*st-axe*    "WMF-Times New Roman0")
(setq gb:*st-titlu*  "Roman Triplex")

;; =========================================================================
;; UTILITARE
;; =========================================================================
(defun gb:sort (lst fn) (mapcar '(lambda (i) (nth i lst)) (vl-sort-i lst fn)))
(defun gb:g (k e) (cdr (assoc k e)))
(defun gb:pune (k v e)
  (if (assoc k e) (subst (cons k v) (assoc k e) e) (append e (list (cons k v))))
)
;; u = de-a lungul elementului, v = perpendicular; dir 0 = element
;; orizontal (u = x), dir 1 = vertical (u = y). Functia e simetrica, deci
;; tot ea transforma (u v) inapoi in (x y).
(defun gb:uv (dr x y) (if (= dr 0) (list x y) (list y x)))
;; cutia unui stalp (x1 y1 x2 y2) in coordonate (u1 v1 u2 v2)
(defun gb:cbox (dr c) (if (= dr 0) c (list (cadr c) (car c) (cadddr c) (caddr c))))
(defun gb:suprap (a1 a2 b1 b2) (- (min a2 b2) (max a1 b1)))
(defun gb:err (p s) (setq gb:*err* (cons (list p s) gb:*err*)))
(defun gb:cm (mm / r)
  (setq r (gb:rtos (/ mm 10.0) 1))
  (if (wcmatch r "*.0") (substr r 1 (- (strlen r) 2)) r)
)
(defun gb:rtos (v p / z r)
  ;; fara influenta lui DIMZIN (2.50 ramane 2.50)
  (setq z (getvar "DIMZIN"))
  (setvar "DIMZIN" 0)
  (setq r (rtos v 2 p))
  (setvar "DIMZIN" z)
  r
)
(defun gb:fmt-cota (v) (strcat (if (>= v 0.0) "+" "") (gb:rtos v 2)))
(defun gb:numar-cota (s / r)
  (setq s (vl-string-trim " " s))
  (if (= (substr s 1 1) "+") (setq s (substr s 2)))
  (setq r (distof s 2))
)
(defun gb:unic-num (l / r)
  (foreach x l (if (not (vl-some '(lambda (y) (equal x y gb:*tol*)) r)) (setq r (cons x r))))
  (gb:sort r '<)
)
;; textul fara formatarea MTEXT ("\A1;{\fBell MT|b1;1}" -> "1")
(defun gb:fara-format (s / p)
  (while (setq p (vl-string-search ";" s)) (setq s (substr s (+ p 2))))
  (vl-string-trim " " (vl-string-translate "{}" "  " s))
)
;; varfurile unei polilinii / linii: (pts inchisa arce)
(defun gb:varfuri (ed / tip pts arce)
  (setq tip (cdr (assoc 0 ed)))
  (cond
    ((= tip "LINE")
     (list (list (list (cadr (assoc 10 ed)) (caddr (assoc 10 ed)))
                 (list (cadr (assoc 11 ed)) (caddr (assoc 11 ed))))
           nil nil))
    ((= tip "LWPOLYLINE")
     (foreach it ed
       (cond ((= (car it) 10) (setq pts (cons (list (cadr it) (caddr it)) pts) arce (cons 0.0 arce)))
             ((and (= (car it) 42) arce) (setq arce (cons (cdr it) (cdr arce))))))
     (list (reverse pts) (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse arce)))
  )
)

;; numele unui element: "G1 30x40" -> ("G" 1 300.0 400.0 "G1 30x40"), altfel nil
(defun gb:nume (s / tip i c num b h n)
  (setq s (vl-string-trim " \t" s))
  (while (vl-string-search "  " s) (setq s (vl-string-subst " " "  " s)))
  (setq tip (strcase (substr s 1 1)) i 2 num "" b "" h "" n (strlen s))
  (if (member tip '("G" "B" "C"))
    (progn
      (while (and (<= i n) (wcmatch (setq c (substr s i 1)) "#")) (setq num (strcat num c) i (1+ i)))
      (if (and (/= num "") (<= i n) (= (substr s i 1) " "))
        (progn
          (setq i (1+ i))
          (while (and (<= i n) (wcmatch (setq c (substr s i 1)) "#")) (setq b (strcat b c) i (1+ i)))
          (if (and (/= b "") (<= i n) (member (substr s i 1) '("x" "X")))
            (progn
              (setq i (1+ i))
              (while (and (<= i n) (wcmatch (setq c (substr s i 1)) "#")) (setq h (strcat h c) i (1+ i)))
              (if (and (/= h "") (> i n))
                (list tip (atoi num) (* 10.0 (atoi b)) (* 10.0 (atoi h)) s)))))))
  )
)

;; =========================================================================
;; CITIREA PLANULUI
;; =========================================================================
(defun gb:are-field (ed / xd)
  (and (setq xd (cdr (assoc 360 ed))) (dictsearch xd "ACAD_FIELD"))
)

;; textele de pe "Cofrag" din grupurile din care face parte e:
;; (texte-libere texte-cu-field)
(defun gb:texte-grup (e / lib fld g ged m med)
  (foreach it (entget e)
    (if (and (= (car it) 330) (setq ged (entget (setq g (cdr it))))
             (= (cdr (assoc 0 ged)) "GROUP"))
      (foreach gi ged
        (if (and (= (car gi) 340) (setq med (entget (setq m (cdr gi))))
                 (= (cdr (assoc 0 med)) "TEXT")
                 (= (strcase (cdr (assoc 8 med))) gb:*l-cofrag*))
          (if (gb:are-field med)
            (if (not (member (cdr (assoc 1 med)) fld)) (setq fld (cons (cdr (assoc 1 med)) fld)))
            (if (not (member (cdr (assoc 1 med)) lib)) (setq lib (cons (cdr (assoc 1 med)) lib))))))))
  (list lib fld)
)

(defun gb:citeste (ss / i e ed tip lay v pts inch arce n k a b xs ys bx nm p rot dr s)
  (setq gb:*seg* nil gb:*col* nil gb:*axe* nil gb:*axtx* nil gb:*mk* nil gb:*cof* nil gb:*cofdim* nil)
  (setq i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) ed (entget e) tip (cdr (assoc 0 ed)) lay (strcase (cdr (assoc 8 ed))) i (1+ i))
    (cond
      ;; liniile grinzilor si centurilor, pe segmente ortogonale
      ((and (member lay (list gb:*l-grinzi* gb:*l-centuri*)) (member tip '("LINE" "LWPOLYLINE")))
       (setq v (gb:varfuri ed) pts (car v) inch (cadr v) arce (caddr v) n (length pts) k 0)
       (repeat (if inch n (1- n))
         (setq a (nth k pts) b (nth (rem (1+ k) n) pts))
         (if (and (or (null arce) (equal (nth k arce) 0.0 1e-9))
                  (> (distance a b) gb:*tol*)
                  (or (equal (car a) (car b) gb:*tol*) (equal (cadr a) (cadr b) gb:*tol*)))
           (setq gb:*seg* (cons (list lay (car a) (cadr a) (car b) (cadr b)) gb:*seg*)))
         (setq k (1+ k))))
      ;; stalpii: cutiile poliliniilor inchise (dublurile se pun o data)
      ((and (= lay gb:*l-stalpi*) (= tip "LWPOLYLINE"))
       (setq v (gb:varfuri ed) pts (car v))
       (if (and (cadr v) (>= (length pts) 4))
         (progn
           (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts)
                 bx (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys)))
           (if (not (vl-some '(lambda (c) (equal c bx gb:*tol*)) gb:*col*))
             (setq gb:*col* (cons bx gb:*col*))))))
      ;; axele
      ((and (= lay gb:*l-axe*) (= tip "LINE"))
       (setq a (cdr (assoc 10 ed)) b (cdr (assoc 11 ed)))
       (cond
         ((equal (cadr a) (cadr b) gb:*tol*)
          (setq gb:*axe* (cons (list 0 (cadr a) (min (car a) (car b)) (max (car a) (car b))) gb:*axe*)))
         ((equal (car a) (car b) gb:*tol*)
          (setq gb:*axe* (cons (list 1 (car a) (min (cadr a) (cadr b)) (max (cadr a) (cadr b))) gb:*axe*)))))
      ((and (= lay gb:*l-axe*) (member tip '("TEXT" "MTEXT")))
       (setq s (cdr (assoc 1 ed)))
       (if (= tip "MTEXT")
         (setq s (apply 'strcat (append (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 3)) ed)) (list s)))))
       (setq p (if (and (= tip "TEXT") (or (/= 0 (cond ((cdr (assoc 72 ed))) (0))) (/= 0 (cond ((cdr (assoc 73 ed))) (0)))))
                 (cdr (assoc 11 ed)) (cdr (assoc 10 ed))))
       (setq s (gb:fara-format s))
       (if (/= s "") (setq gb:*axtx* (cons (list (car p) (cadr p) s) gb:*axtx*))))
      ;; numele elementelor
      ((and (= lay gb:*l-markers*) (= tip "TEXT") (setq nm (gb:nume (cdr (assoc 1 ed)))))
       (setq p (if (or (/= 0 (cond ((cdr (assoc 72 ed))) (0))) (/= 0 (cond ((cdr (assoc 73 ed))) (0))))
                 (cdr (assoc 11 ed)) (cdr (assoc 10 ed))))
       (setq rot (rem (cdr (assoc 50 ed)) pi))
       (setq dr (if (or (< rot (/ pi 4.0)) (> rot (* 0.75 pi))) 0 1))
       (setq gb:*mk* (cons (list (cons 'tip (nth 0 nm)) (cons 'num (nth 1 nm)) (cons 'b (nth 2 nm))
                                 (cons 'h (nth 3 nm)) (cons 'name (nth 4 nm))
                                 (cons 'p (list (car p) (cadr p))) (cons 'dir dr))
                           gb:*mk*)))
      ;; sectiunile de cofraj si cotele lor
      ((and (= lay gb:*l-cofrag*) (= tip "LWPOLYLINE"))
       (setq pts (car (gb:varfuri ed)))
       (if (>= (length pts) 6) (setq gb:*cof* (cons (list e pts) gb:*cof*))))
      ((and (= lay gb:*l-cofrag*) (= tip "DIMENSION"))
       ;; marimea cotei in mm, din punctele ei (valoarea din desen e deja
       ;; inmultita cu factorul stilului, ex. in cm)
       (setq a (cdr (assoc 13 ed)) b (cdr (assoc 14 ed)) rot (cond ((cdr (assoc 50 ed))) (0.0)))
       (setq gb:*cofdim* (cons (list a b (abs (+ (* (- (car b) (car a)) (cos rot)) (* (- (cadr b) (cadr a)) (sin rot)))))
                               gb:*cofdim*)))
    )
  )
)

;; =========================================================================
;; RECUNOASTEREA ELEMENTELOR
;; =========================================================================
;; segmentele de pe layerul lay paralele cu directia dr: (v umin umax)
(defun gb:paralele (lay dr / r a b)
  (foreach s gb:*seg*
    (if (= (car s) lay)
      (progn
        (setq a (gb:uv dr (nth 1 s) (nth 2 s)) b (gb:uv dr (nth 3 s) (nth 4 s)))
        (if (equal (cadr a) (cadr b) gb:*tol*)
          (setq r (cons (list (cadr a) (min (car a) (car b)) (max (car a) (car b))) r))))))
  r
)

(defun gb:uneste (iv / r)
  (foreach x (gb:sort iv '(lambda (a b) (< (car a) (car b))))
    (if (and r (<= (car x) (+ (cadr (car r)) gb:*tol*)))
      (setq r (cons (list (car (car r)) (max (cadr (car r)) (cadr x))) (cdr r)))
      (setq r (cons x r))))
  (reverse r)
)

(defun gb:intersectie (la lb / r lo hi)
  (foreach a la
    (foreach b lb
      (setq lo (max (car a) (car b)) hi (min (cadr a) (cadr b)))
      (if (> hi (+ lo gb:*tol*)) (setq r (cons (list lo hi) r)))))
  (gb:sort r '(lambda (a b) (< (car a) (car b))))
)

;; un stalp acopera golul [g1 g2] dintre doua bucati ale elementului?
(defun gb:stalp-in-gol (dr g1 g2 va vb)
  (vl-some '(lambda (c / k)
              (setq k (gb:cbox dr c))
              (and (<= (car k) (+ g1 gb:*tol*)) (>= (caddr k) (- g2 gb:*tol*))
                   (> (gb:suprap (cadr k) (cadddr k) va vb) gb:*tol*)))
           gb:*col*)
)

;; alt element (alt nume) are textul intre lo si hi, in fasia va-vb?
(defun gb:alt-nume (dr mk lo hi va vb)
  (vl-some '(lambda (o / q)
              (and (= (gb:g 'dir o) dr) (/= (gb:g 'name o) (gb:g 'name mk))
                   (setq q (gb:uv dr (car (gb:g 'p o)) (cadr (gb:g 'p o))))
                   (<= (- lo gb:*tol*) (car q) (+ hi gb:*tol*))
                   (< va (cadr q) vb)))
           gb:*mk*)
)

;; fasia unui element, pornind de la textul lui; nil daca nu se gaseste
(defun gb:element (mk / dr lay q pu pv ps sus jos va vb ia ib iv k lo hi j)
  (setq dr (gb:g 'dir mk)
        lay (if (= (gb:g 'tip mk) "C") gb:*l-centuri* gb:*l-grinzi*)
        q (gb:uv dr (car (gb:g 'p mk)) (cadr (gb:g 'p mk)))
        pu (car q) pv (cadr q)
        ps (gb:paralele lay dr))
  (foreach s ps
    (if (<= (- (cadr s) gb:*tol*) pu (+ (caddr s) gb:*tol*))
      (cond
        ((> (car s) (+ pv gb:*tol*)) (if (or (null sus) (< (car s) sus)) (setq sus (car s))))
        ((< (car s) (- pv gb:*tol*)) (if (or (null jos) (> (car s) jos)) (setq jos (car s)))))))
  (cond
    ((not (and sus jos))
     (if (/= (gb:g 'tip mk) "C")
       (gb:err (gb:g 'p mk) (strcat (gb:g 'name mk) ": nu am gasit cele doua linii ale elementului in jurul textului")))
     nil)
    (T
     (setq va jos vb sus
           ia (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) va gb:*tol*)) ps)))
           ib (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) vb gb:*tol*)) ps)))
           iv (gb:intersectie ia ib)
           j 0)
     (foreach x iv
       (if (<= (- (car x) gb:*tol*) pu (+ (cadr x) gb:*tol*)) (setq k j))
       (setq j (1+ j)))
     (if (null k)
       (progn
         (if (/= (gb:g 'tip mk) "C")
           (gb:err (gb:g 'p mk) (strcat (gb:g 'name mk) ": textul nu este intre liniile elementului")))
         nil)
       (progn
         ;; peste stalpii intermediari elementul continua, daca dincolo nu
         ;; incepe alt element (alt nume)
         (setq lo (car (nth k iv)) hi (cadr (nth k iv)) j k)
         (while (and (< (1+ j) (length iv))
                     (gb:stalp-in-gol dr (cadr (nth j iv)) (car (nth (1+ j) iv)) va vb)
                     (not (gb:alt-nume dr mk (car (nth (1+ j) iv)) (cadr (nth (1+ j) iv)) va vb)))
           (setq j (1+ j) hi (cadr (nth j iv))))
         (setq j k)
         (while (and (> j 0)
                     (gb:stalp-in-gol dr (cadr (nth (1- j) iv)) (car (nth j iv)) va vb)
                     (not (gb:alt-nume dr mk (car (nth (1- j) iv)) (cadr (nth (1- j) iv)) va vb)))
           (setq j (1- j) lo (car (nth j iv))))
         (if (and (/= (gb:g 'tip mk) "C") (not (equal (- vb va) (gb:g 'b mk) gb:*tol*)))
           (gb:err (gb:g 'p mk) (strcat (gb:g 'name mk) ": latimea din nume este " (gb:cm (gb:g 'b mk))
                                        " cm, pe plan are " (gb:cm (- vb va)) " cm")))
         (append mk (list (cons 'lo lo) (cons 'hi hi) (cons 'va va) (cons 'vb vb))))))
  )
)

;; reazemul de la un capat (lat 0 = stanga/jos, 1 = dreapta/sus):
;; ("S" a b nil) stalp, ("G" a b h) grinda/centura pe care reazema, nil
(defun gb:reazem-capat (e lat / dr u r k)
  (setq dr (gb:g 'dir e) u (gb:g (if (= lat 0) 'lo 'hi) e))
  (foreach c gb:*col*
    (setq k (gb:cbox dr c))
    (if (and (null r)
             (> (gb:suprap (cadr k) (cadddr k) (gb:g 'va e) (gb:g 'vb e)) gb:*tol*)
             (<= (car k) (+ u gb:*tol*)) (>= (caddr k) (- u gb:*tol*)))
      (setq r (list "S" (car k) (caddr k) nil))))
  (if (null r)
    (foreach o gb:*el*
      (if (and (null r) (/= (gb:g 'dir o) dr)
               (<= (gb:g 'va o) (+ u gb:*tol*)) (>= (gb:g 'vb o) (- u gb:*tol*))
               (<= (gb:g 'lo o) (+ (gb:g 'va e) gb:*tol*)) (>= (gb:g 'hi o) (- (gb:g 'vb e) gb:*tol*)))
        (setq r (list "G" (gb:g 'va o) (gb:g 'vb o) (gb:g 'h o))))))
  r
)

;; reazemele elementului, de la stanga la dreapta, si capetele ua / ub
(defun gb:reazeme (e / s0 s1 ua ub mij k vm)
  (setq s0 (gb:reazem-capat e 0) s1 (gb:reazem-capat e 1))
  (if (and (null s0) (= (gb:g 'tip e) "B"))
    (setq s0 (list "Z" (gb:g 'lo e) (+ (gb:g 'lo e) gb:*l-caram*) nil)))
  (if (and (null s1) (= (gb:g 'tip e) "B"))
    (setq s1 (list "Z" (- (gb:g 'hi e) gb:*l-caram*) (gb:g 'hi e) nil)))
  (setq vm (/ (+ (gb:g 'va e) (gb:g 'vb e)) 2.0))
  (if (null s0)
    (progn
      (gb:err (gb:uv (gb:g 'dir e) (gb:g 'lo e) vm)
              (strcat (gb:g 'name e) ": capatul " (if (= (gb:g 'dir e) 0) "stang" "de jos") " nu reazema pe stalp sau grinda"))
      (setq s0 (list "N" (gb:g 'lo e) (gb:g 'lo e) nil))))
  (if (null s1)
    (progn
      (gb:err (gb:uv (gb:g 'dir e) (gb:g 'hi e) vm)
              (strcat (gb:g 'name e) ": capatul " (if (= (gb:g 'dir e) 0) "drept" "de sus") " nu reazema pe stalp sau grinda"))
      (setq s1 (list "N" (gb:g 'hi e) (gb:g 'hi e) nil))))
  (setq ua (min (gb:g 'lo e) (cadr s0)) ub (max (gb:g 'hi e) (caddr s1)))
  ;; stalpii intermediari
  (foreach c gb:*col*
    (setq k (gb:cbox (gb:g 'dir e) c))
    (if (and (> (gb:suprap (cadr k) (cadddr k) (gb:g 'va e) (gb:g 'vb e)) gb:*tol*)
             (> (car k) (+ (caddr s0) (- gb:*tol*))) (< (caddr k) (- (cadr s1) (- gb:*tol*)))
             (> (car k) (+ ua gb:*tol*)) (< (caddr k) (- ub gb:*tol*))
             (not (equal (car k) (cadr s0) gb:*tol*)) (not (equal (car k) (cadr s1) gb:*tol*)))
      (setq mij (cons (list "S" (car k) (caddr k) nil) mij))))
  (setq mij (gb:sort mij '(lambda (a b) (< (cadr a) (cadr b)))))
  (gb:pune 'sups (append (list s0) mij (list s1)) (gb:pune 'ua ua (gb:pune 'ub ub e)))
)

;; =========================================================================
;; ETRIERI
;; =========================================================================
(defun gb:sus50 (x) (* 50.0 (fix (+ (/ x 50.0) 0.999999))))

;; grinzi: pe fiecare deschidere, zone de capat de 1/4 (rotunjit la 5 cm)
;; cu pas 10, la mijloc pas 15. Intoarce (pozitii zone deschideri), zona =
;; (a b pas_cm)
(defun gb:etr-grinda (sups / poz zone desc s0 a b z p1 p2 x ultim)
  (setq s0 (car sups))
  (foreach s1 (cdr sups)
    (setq a (caddr s0) b (cadr s1) s0 s1)
    (cond
      ((<= (- b a) gb:*tol*))
      ;; deschidere scurta: toti etrierii la 15 cm
      ((< (- b a) gb:*desc-mica*)
       (setq desc (cons (list a b) desc) x a ultim nil)
       (while (<= x (+ b gb:*tol*)) (setq poz (cons x poz) ultim x x (+ x gb:*pas-mij*)))
       (if (and ultim (> (- b ultim) 10.0)) (setq poz (cons b poz)))
       (setq zone (append zone (list (list a b 15)))))
      (T
        (setq desc (cons (list a b) desc)
              z (gb:sus50 (/ (- b a) 4.0)) p1 (+ a z) p2 (- b z))
        (if (>= p1 p2) (setq p1 (/ (+ a b) 2.0) p2 p1))
        (setq x p1)
        (while (>= x (- a gb:*tol*)) (setq poz (cons x poz) x (- x gb:*pas-cap*)))
        (setq x (+ p1 gb:*pas-mij*))
        (while (< x (- p2 gb:*tol*)) (setq poz (cons x poz) x (+ x gb:*pas-mij*)))
        (setq x (if (> p2 p1) p2 (+ p2 gb:*pas-cap*)))
        (while (<= x (+ b gb:*tol*)) (setq poz (cons x poz) x (+ x gb:*pas-cap*)))
        (setq zone (append zone (list (list a p1 10))
                           (if (> p2 p1) (list (list p1 p2 15)))
                           (list (list p2 b 10)))))))
  (list (gb:unic-num poz) zone (reverse desc))
)

;; buiandrugi: pas 15 peste tot in afara de stalpi / grinzi
(defun gb:etr-buiandrug (sups ua ub / poz zone desc blocuri cur a b x ultim)
  (setq blocuri (vl-remove-if-not '(lambda (s) (member (car s) '("S" "G"))) sups) cur ua)
  (foreach s blocuri
    (if (> (cadr s) (+ cur gb:*tol*)) (setq zone (cons (list cur (cadr s) 15) zone)))
    (setq cur (max cur (caddr s))))
  (if (> ub (+ cur gb:*tol*)) (setq zone (cons (list cur ub 15) zone)))
  (setq zone (reverse zone))
  (foreach zn zone
    (setq a (if (vl-some '(lambda (s) (equal (caddr s) (car zn) gb:*tol*)) blocuri) (car zn) (+ (car zn) gb:*etr-dist*))
          b (if (vl-some '(lambda (s) (equal (cadr s) (cadr zn) gb:*tol*)) blocuri) (cadr zn) (- (cadr zn) gb:*etr-dist*))
          x a ultim nil)
    (while (<= x (+ b gb:*tol*)) (setq poz (cons x poz) ultim x x (+ x gb:*pas-mij*)))
    (if (and ultim (> (- b ultim) 10.0)) (setq poz (cons b poz)))
    (setq desc (cons (list (car zn) (cadr zn)) desc)))
  (list (gb:unic-num poz) zone (reverse desc))
)

;; =========================================================================
;; AXE SI SECTIUNI DE COFRAJ
;; =========================================================================
;; axele perpendiculare care trec prin reazemele elementului: ((u nume) ...)
(defun gb:axe-element (e / dr vm r c best tu tv dd q)
  (setq dr (gb:g 'dir e) vm (/ (+ (gb:g 'va e) (gb:g 'vb e)) 2.0))
  (foreach a gb:*axe*
    (setq c (cadr a))
    (if (and (/= (car a) dr)
             (<= (- (caddr a) gb:*tol*) vm (+ (cadddr a) gb:*tol*))
             (vl-some '(lambda (s) (and (member (car s) '("S" "G")) (<= (- (cadr s) gb:*tol*) c (+ (caddr s) gb:*tol*))))
                      (gb:g 'sups e))
             (not (vl-some '(lambda (x) (equal (car x) c gb:*tol*)) r)))
      (progn
        (setq best nil)
        (foreach t1 gb:*axtx*
          (setq q (gb:uv dr (car t1) (cadr t1)) tu (car q) tv (cadr q)
                dd (min (abs (- tv (caddr a))) (abs (- tv (cadddr a)))))
          (if (and (<= (abs (- tu c)) 350.0) (< dd 800.0)
                   (or (> tv (- (cadddr a) 50.0)) (< tv (+ (caddr a) 50.0)))
                   (or (null best) (< dd (car best))))
            (setq best (list dd (caddr t1)))))
        (setq r (cons (list c (if best (cadr best) "?")) r)))))
  (gb:sort r '(lambda (a b) (< (car a) (car b))))
)

;; elementul caruia ii apartine o sectiune de cofraj (aceleasi doua fete,
;; cel mai aproape de-a lungul lui); nil daca nu e niciunul
(defun gb:proprietar (pts / best dr q vs us c dd)
  (foreach e gb:*el*
    (setq dr (gb:g 'dir e)
          q (mapcar '(lambda (p) (gb:uv dr (car p) (cadr p))) pts)
          vs (mapcar 'cadr q) us (mapcar 'car q))
    (if (and (vl-some '(lambda (v) (equal v (gb:g 'va e) gb:*tol*)) vs)
             (vl-some '(lambda (v) (equal v (gb:g 'vb e) gb:*tol*)) vs))
      (progn
        (setq c (/ (+ (apply 'min us) (apply 'max us)) 2.0)
              dd (max (- (gb:g 'lo e) c) 0.0 (- c (gb:g 'hi e))))
        (if (and (<= dd gb:*sect-max*) (or (null best) (< dd (car best))))
          (setq best (list dd e))))))
  (cadr best)
)

;; datele unei sectiuni: (cote-mm texte-libere texte-field)
(defun gb:date-sectiune (e pts / xs ys x1 x2 y1 y2 dims tx)
  (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts)
        x1 (- (apply 'min xs) 10.0) x2 (+ (apply 'max xs) 10.0)
        y1 (- (apply 'min ys) 10.0) y2 (+ (apply 'max ys) 10.0))
  (foreach dm gb:*cofdim*
    (if (and (<= x1 (car (car dm)) x2) (<= y1 (cadr (car dm)) y2)
             (<= x1 (car (cadr dm)) x2) (<= y1 (cadr (cadr dm)) y2))
      (setq dims (cons (caddr dm) dims))))
  (setq tx (gb:texte-grup e))
  (list (reverse dims) (car tx) (cadr tx))
)

;; verificarea inaltimii unui element fata de sectiunile lui de cofraj
;; latimea zidului in care sta buiandrugul: distanta dintre liniile de
;; centura paralele cu el, cele mai apropiate de o parte si de alta
(defun gb:latime-zid (e / dr vm sus jos)
  (setq dr (gb:g 'dir e) vm (/ (+ (gb:g 'va e) (gb:g 'vb e)) 2.0))
  (foreach s (gb:paralele gb:*l-centuri* dr)
    (if (and (> (gb:suprap (cadr s) (caddr s) (- (gb:g 'lo e) 1000.0) (+ (gb:g 'hi e) 1000.0)) gb:*tol*)
             (< (abs (- (car s) vm)) 1000.0))
      (cond
        ((> (car s) vm) (if (or (null sus) (< (car s) sus)) (setq sus (car s))))
        ((< (car s) vm) (if (or (null jos) (> (car s) jos)) (setq jos (car s)))))))
  (if (and sus jos) (- sus jos))
)

(defun gb:verifica-buiandrugi (el top / bs hs r hm w)
  (setq bs (vl-remove-if-not '(lambda (e) (= (gb:g 'tip e) "B")) el))
  ;; latimea din nume = grosimea zidului (distanta dintre liniile de centura)
  (foreach e bs
    (if (and (setq w (gb:latime-zid e)) (not (equal w (gb:g 'b e) gb:*tol*)))
      (gb:err (gb:g 'p e) (strcat (gb:g 'name e) ": latimea din nume este " (gb:cm (gb:g 'b e))
                                  " cm, zidul (intre liniile de centura) are " (gb:cm w) " cm"))))
  ;; de obicei toti buiandrugii au cota de jos la acelasi nivel
  (foreach e bs
    (if (setq r (assoc (gb:g 'h e) hs)) (setq hs (subst (cons (car r) (1+ (cdr r))) r hs)) (setq hs (cons (cons (gb:g 'h e) 1) hs))))
  (if (> (length hs) 1)
    (progn
      (setq hm (car (car (gb:sort hs '(lambda (a b) (> (cdr a) (cdr b)))))))
      (foreach e bs
        (if (not (equal (gb:g 'h e) hm 0.1))
          (gb:err (gb:g 'p e) (strcat (gb:g 'name e) ": cota de jos " (gb:fmt-cota (- top (/ (gb:g 'h e) 1000.0)))
                                      ", ceilalti buiandrugi au " (gb:fmt-cota (- top (/ hm 1000.0)))
                                      " (inaltime " (gb:cm hm) " cm) - verificati inaltimea"))))))
)

(defun gb:verifica-cofraj (e top / secs s dims lib fld sum t1 b1 p)
  (setq secs (gb:g 'secs e) p (gb:g 'p e))
  (cond
    ((null secs)
     (if (= (gb:g 'tip e) "G")
       (gb:err p (strcat (gb:g 'name e) ": nu am gasit grupul de cofraj (sectiunea) pe plan"))))
    (T
     (foreach s secs
       (setq dims (car s) lib (cadr s) fld (caddr s))
       (if dims
         (progn
           (setq sum (apply '+ dims))
           (if (not (equal sum (gb:g 'h e) gb:*tol*))
             (gb:err p (strcat (gb:g 'name e) ": inaltimea din nume este " (gb:cm (gb:g 'h e))
                               " cm, grupul de cofraj arata "
                               (apply 'strcat (cdr (apply 'append (mapcar '(lambda (d) (list "+" (gb:cm d))) dims))))
                               " = " (gb:cm sum) " cm")))))
       (if (and lib fld (setq t1 (gb:numar-cota (car lib))) (setq b1 (gb:numar-cota (car fld))))
         (progn
           (if (not (equal (* 1000.0 (- t1 b1)) (gb:g 'h e) gb:*tol*))
             (gb:err p (strcat (gb:g 'name e) ": cotele de nivel din grupul de cofraj (" (car lib) " / " (car fld)
                               ") dau " (gb:cm (* 1000.0 (- t1 b1))) " cm, numele spune " (gb:cm (gb:g 'h e)) " cm")))
           (if (not (equal t1 top 0.0005))
             (gb:err p (strcat (gb:g 'name e) ": grupul de cofraj are cota de sus " (car lib)
                               ", diferita de " (gb:fmt-cota top)))))
         (gb:err p (strcat (gb:g 'name e) ": grupul de cofraj nu are cotele de nivel (textul liber si textul cu field)"))))))
)

;; =========================================================================
;; DESENARE
;; =========================================================================
(defun gb:straturi ()
  (foreach l (list (list gb:*l-elem* 7 nil) (list gb:*l-fier* 100 nil) (list gb:*l-etr* 6 nil)
                   (list gb:*l-cote* 7 nil) (list gb:*l-axe-d* 1 "ACAD_ISO10W100") (list gb:*l-sect* 11 nil)
                   (list gb:*l-bucati* 7 nil) (list gb:*l-erori* 1 nil))
    (if (not (tblsearch "LAYER" (car l)))
      (entmake (append (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                             (cons 2 (car l)) '(70 . 0) (cons 62 (cadr l)))
                       (if (and (caddr l) (tblsearch "LTYPE" (caddr l))) (list (cons 6 (caddr l))))))))
  ;; marcajele de erori nu ies la print (si nici daca layerul exista deja)
  (vl-catch-all-apply 'vla-put-plottable
    (list (vla-item (vla-get-layers (vla-get-activedocument (vlax-get-acad-object))) gb:*l-erori*) :vlax-false))
)

(defun gb:o (en) (vlax-ename->vla-object en))

(defun gb:linie (lay p1 p2)
  (entmakex (list '(0 . "LINE") (cons 8 lay) (list 10 (car p1) (cadr p1) 0.0) (list 11 (car p2) (cadr p2) 0.0)))
)
(defun gb:poli (lay pts)
  (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDbPolyline")
                          (cons 90 (length pts)) '(70 . 1))
                    (mapcar '(lambda (p) (list 10 (car p) (cadr p))) pts)))
)
(defun gb:dreptunghi (lay x1 y1 x2 y2)
  (gb:poli lay (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2)))
)
;; just: "BC" jos-centru, "MC" mijloc-centru, "BR" jos-dreapta
(defun gb:text (lay pt h s stil just culoare / l j)
  (setq j (cond ((= just "MC") '(1 2)) ((= just "BR") '(2 1)) (T '(1 0))))
  (setq l (list '(0 . "TEXT") (cons 8 lay) (list 10 (car pt) (cadr pt) 0.0) (cons 40 h) (cons 1 s)
                '(50 . 0.0) '(41 . 1.0) (cons 72 (car j)) (list 11 (car pt) (cadr pt) 0.0) (cons 73 (cadr j))))
  (if (tblsearch "STYLE" stil) (setq l (append l (list (cons 7 stil)))))
  (if culoare (setq l (append l (list (cons 62 culoare)))))
  (entmakex l)
)
(defun gb:hasura (ms pl pat sc lay / h arr)
  (setq h (vla-addhatch ms 1 pat :vlax-true))
  (vla-put-layer h lay)
  (setq arr (vlax-make-safearray vlax-vbObject '(0 . 0)))
  (vlax-safearray-put-element arr 0 pl)
  (vla-appendouterloop h arr)
  (if (/= (strcase pat) "SOLID") (vla-put-patternscale h sc))
  (vla-evaluate h)
  h
)
(defun gb:cota (ms p1 p2 pl rot / d)
  (setq d (vla-adddimrotated ms (vlax-3d-point (list (car p1) (cadr p1) 0.0)) (vlax-3d-point (list (car p2) (cadr p2) 0.0))
                             (vlax-3d-point (list (car pl) (cadr pl) 0.0)) rot))
  (vla-put-layer d gb:*l-cote*)
  (if (tblsearch "DIMSTYLE" gb:*ds*) (vl-catch-all-apply 'vla-put-stylename (list d gb:*ds*)))
  d
)
(defun gb:grup (doc objs / arr r n)
  (setq arr (vlax-make-safearray vlax-vbObject (cons 0 (1- (length objs)))))
  (vlax-safearray-fill arr objs)
  (setq r (vl-catch-all-apply 'vla-add (list (vla-get-groups doc) "*")))
  (if (vl-catch-all-error-p r)
    (progn
      (setq n 1)
      (while (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-item (list (vla-get-groups doc) (strcat "GRINZI" (itoa n))))))
        (setq n (1+ n)))
      (setq r (vla-add (vla-get-groups doc) (strcat "GRINZI" (itoa n))))))
  (vla-appenditems r arr)
  r
)
;; stilul de cota curent (DIMSTYLE nu se poate schimba cu setvar)
(defun gb:stil-cota (doc nume)
  (if (tblsearch "DIMSTYLE" nume)
    (vl-catch-all-apply 'vla-put-activedimstyle (list doc (vla-item (vla-get-dimstyles doc) nume))))
)
(defun gb:id (doc o) (vla-getobjectidstring (vla-get-utility doc) o :vlax-false))

;; reazemul de sub element: stalp (hasura ANSI31) sau caramida (AR-B88)
(defun gb:simbol-reazem (doc ms x1 x2 yb pat sc / pl)
  (setq pl (gb:o (gb:dreptunghi gb:*l-elem* x1 yb x2 (- yb gb:*h-reazem*))))
  (gb:grup doc (list pl (gb:hasura ms pl pat sc gb:*l-elem*)))
)

;; cota de inaltime si cotele de nivel, la dreapta elementului
(defun gb:cote-nivel (doc ms xr yt h top / d objs x0 tsus tjos pl yl fc)
  (setq d (gb:cota ms (list xr yt) (list xr (- yt h)) (list (+ xr 250.0) yt) (/ pi 2.0)))
  (setq objs (list d) x0 (+ xr 409.5))
  (foreach yl (list yt (- yt h))
    (setq pl (gb:o (gb:poli gb:*l-cote* (list (list x0 (+ yl 68.5)) (list (+ x0 30.6) (+ yl 68.5)) (list (+ x0 30.6) yl)))))
    (setq objs (append objs
                       (list (gb:o (gb:linie gb:*l-cote* (list (+ xr 367.0) yl) (list (+ xr 513.0) yl)))
                             pl (gb:hasura ms pl "SOLID" 1.0 gb:*l-cote*)
                             (gb:o (gb:linie gb:*l-cote* (list x0 (+ yl 68.5)) (list (+ x0 518.0) (+ yl 68.5))))))))
  (setq tsus (gb:o (gb:text gb:*l-cote* (list (+ x0 209.9) (+ yt 179.4)) 125.0 (gb:fmt-cota top) gb:*st-text* "MC" nil))
        tjos (gb:o (gb:text gb:*l-cote* (list (+ x0 209.9) (+ (- yt h) 179.4)) 125.0
                            (gb:fmt-cota (- top (/ h 1000.0))) gb:*st-text* "MC" nil)))
  ;; cota de jos = cota de sus - cota de inaltime, ca FIELD (ca in desenele
  ;; facute manual): se actualizeaza daca se schimba cota de sus sau inaltimea
  (setq fc (strcat (if (>= (- top (/ h 1000.0)) 0.0) "+" "")
                   "%<\\AcExpr (%<\\AcObjProp Object(%<\\_ObjId " (gb:id doc tsus) ">%).TextString>%-"
                   "%<\\AcObjProp.16.2 Object(%<\\_ObjId " (gb:id doc d) ">%).Measurement \\f \"%lu6%ct8[0.01]\">%"
                   "*0.01) \\f \"%lu6\">%"))
  (vl-catch-all-apply 'vla-put-textstring (list tjos fc))
  (gb:grup doc (append objs (list tsus tjos)))
)

;; o desfasurata; ox = marginea stanga, oy = fata de sus. Intoarce lungimea.
;; textul unei zone de etrieri sta mereu la mijlocul cotei zonei; sectiunea
;; "xx" (linia la xs, textul "xx" la stanga ei) se muta daca ar cadea peste el
;; zonele de etrieri pentru cote: (a b pas) unite peste reazeme
(defun gb:zone-cote (zones ua ub / r p)
  (foreach z zones
    (cond
      ((null r) (setq r (list (list ua (cadr z) (caddr z)))))
      ((= (caddr z) (caddr (car r)))
       (setq r (cons (list (car (car r)) (cadr z) (caddr z)) (cdr r))))
      (T
       ;; pas diferit: golul (stalpul) ramane la zona din stanga
       (setq p (car r) r (cons (list (car p) (car z) (caddr p)) (cdr r))
             r (cons (list (car z) (cadr z) (caddr z)) r)))))
  (if r (setq r (cons (list (car (car r)) ub (caddr (car r))) (cdr r))))
  (reverse r)
)
(defun gb:xx-loveste (xs txs)
  (vl-some '(lambda (xm) (and (< (- xm gb:*lat-etr*) (+ xs 20.0)) (> (+ xm gb:*lat-etr*) (- xs 220.0)))) txs)
)
;; cel mai apropiat loc liber pentru sectiune, in deschiderea s; altfel xs
(defun gb:xx-liber (xs s txs / d r)
  (setq d 25.0)
  (while (and (null r) (< d (- (cadr s) (car s))))
    (foreach x (list (- xs d) (+ xs d))
      (if (and (null r) (>= x (+ (car s) 220.0)) (<= x (cadr s)) (not (gb:xx-loveste x txs)))
        (setq r x)))
    (setq d (+ d 25.0)))
  (if r r xs)
)

(defun gb:deseneaza (doc ms e n top ox oy / ua ub lt h yb x et zones desc pct pt2 a b xm s xs txs titlu)
  (setq ua (gb:g 'ua e) ub (gb:g 'ub e) lt (- ub ua) h (gb:g 'h e) yb (- oy h))
  (defun gb:x (u) (+ ox (- u ua)))
  ;; elementul si carcasa
  (gb:dreptunghi gb:*l-elem* ox oy (+ ox lt) yb)
  (gb:dreptunghi gb:*l-fier* (+ ox gb:*acop*) (- oy gb:*acop*) (+ ox lt (- gb:*acop*)) (+ yb gb:*acop*))
  ;; reazemele
  (foreach s (gb:g 'sups e)
    (cond
      ((= (car s) "S") (gb:simbol-reazem doc ms (gb:x (cadr s)) (gb:x (caddr s)) yb "ANSI31" 35.0))
      ((= (car s) "Z") (gb:simbol-reazem doc ms (gb:x (cadr s)) (gb:x (caddr s)) yb "AR-B88" 0.8))
      ((= (car s) "G")
       (setq a (gb:o (gb:dreptunghi gb:*l-elem* (gb:x (cadr s)) oy (gb:x (caddr s)) (- oy (cadddr s)))))
       (gb:grup doc (list a (gb:hasura ms a "ANSI31" 35.0 gb:*l-elem*))))))
  ;; etrierii
  (setq et (if (= (gb:g 'tip e) "G")
             (gb:etr-grinda (gb:g 'sups e))
             (gb:etr-buiandrug (gb:g 'sups e) ua ub))
        zones (cadr et) desc (caddr et))
  (foreach u (car et)
    (gb:linie gb:*l-etr* (list (gb:x u) (- oy gb:*acop*)) (list (gb:x u) (+ yb gb:*acop*))))
  ;; lantul de sus: zonele de etrieri, fara opriri la stalpi: prima incepe
  ;; din coltul grinzii (cu stalp), ultima se termina la capatul ei, iar
  ;; zonele cu acelasi pas de o parte si de alta a unui stalp intermediar
  ;; sunt o singura cota
  (setq zones (gb:zone-cote zones ua ub))
  (foreach z zones
    (gb:cota ms (list (gb:x (car z)) oy) (list (gb:x (cadr z)) oy) (list (gb:x (car z)) (+ oy 300.0)) 0.0))
  ;; sectiunea "xx" sta in prima treime a primei deschideri (de la reazemul
  ;; din stanga), spre capatul treimii; daca ar cadea peste textul unei
  ;; zone, se muta ea in treime (textul ramane la mijlocul cotei)
  (setq s (car desc))
  (if s (setq s (list (car s) (+ (car s) (/ (- (cadr s) (car s)) 3.0)))
              xs (- (cadr s) 50.0)))
  (setq txs (mapcar '(lambda (z) (/ (+ (car z) (cadr z)) 2.0)) zones))
  (if (and xs (gb:xx-loveste xs txs)) (setq xs (gb:xx-liber xs s txs)))
  (mapcar '(lambda (z xm)
             (gb:text gb:*l-elem* (list (gb:x xm) (+ oy 148.3)) 90.0
                      (strcat "etr. " gb:*diam* "/" (itoa (caddr z))) gb:*st-text* "BC" nil))
          zones txs)
  ;; lantul de jos: reazemele si deschiderile
  (setq pt2 (list ua ub))
  (foreach s (gb:g 'sups e) (if (/= (car s) "N") (setq pt2 (append pt2 (list (cadr s) (caddr s))))))
  (setq pt2 (vl-remove-if '(lambda (u) (or (< u (- ua gb:*tol*)) (> u (+ ub gb:*tol*)))) (gb:unic-num pt2)))
  (setq a (car pt2))
  (foreach b (cdr pt2)
    (gb:cota ms (list (gb:x a) (- yb gb:*h-reazem*)) (list (gb:x b) (- yb gb:*h-reazem*))
             (list (gb:x a) (- yb gb:*h-reazem* 250.0)) 0.0)
    (setq a b))
  ;; axele
  (foreach ax (gb:g 'axes e)
    (setq x (gb:x (car ax)))
    ;; doar linia e linie-punct; cercul continuu si numele alb
    (entmakex (append (list '(0 . "LINE") (cons 8 gb:*l-axe-d*))
                      (if (tblsearch "LTYPE" "ACAD_ISO10W100") '((6 . "ACAD_ISO10W100")))
                      (list '(48 . 20.0) (list 10 x (+ oy 520.0) 0.0) (list 11 x (- yb 855.0) 0.0))))
    (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-axe-d*) '(6 . "Continuous") '(62 . 7)
                    (list 10 x (+ oy 639.4) 0.0) '(40 . 119.2)))
    (gb:text gb:*l-axe-d* (list x (+ oy 639.4)) 140.0 (cadr ax) gb:*st-axe* "MC" 7))
  ;; cota de inaltime si cotele de nivel
  (gb:cote-nivel doc ms (+ ox lt) oy h top)
  ;; sectiunea "xx"
  (if xs
    (progn
      (setq xs (gb:x xs))
      (gb:grup doc (list (gb:o (gb:linie gb:*l-sect* (list xs (+ oy 83.7)) (list xs (+ oy 195.6))))
                         (gb:o (gb:linie gb:*l-sect* (list xs (- yb 103.5)) (list xs (- yb 215.3))))
                         (gb:o (gb:text gb:*l-sect* (list (- xs 40.0) (+ oy 83.7)) 120.0 "xx" gb:*st-text* "BR" nil))
                         (gb:o (gb:text gb:*l-sect* (list (- xs 40.0) (- yb 215.3)) 120.0 "xx" gb:*st-text* "BR" nil))))))
  ;; titlul
  (setq xm (+ ox (/ lt 2.0)) titlu (strcat (gb:g 'name e) " " (itoa n) "buc."))
  (gb:text gb:*l-bucati* (list xm (+ oy 1000.0)) 140.0 titlu gb:*st-titlu* "MC" (if (= (gb:g 'tip e) "G") 6 3))
  (gb:text gb:*l-bucati* (list xm (+ oy 830.0)) 110.0 "Scara 1:50" gb:*st-titlu* "MC" (if (= (gb:g 'tip e) "G") 6 3))
  lt
)

;; semnatura geometriei, ca sa se recunoasca elementele identice
(defun gb:semnatura (e / ua)
  (setq ua (gb:g 'ua e))
  (apply 'strcat
         (append (list (gb:g 'name e) "|" (gb:rtos (- (gb:g 'ub e) ua) 0))
                 (mapcar '(lambda (s) (strcat "|" (car s) (gb:rtos (- (cadr s) ua) 0) "-" (gb:rtos (- (caddr s) ua) 0)))
                         (gb:g 'sups e))))
)

;; marcajele greselilor pe plan
(defun gb:marcheaza-erori (lst / ss i k)
  (if (setq ss (ssget "_X" (list (cons 8 gb:*l-erori*))))
    (progn (setq i 0) (repeat (sslength ss) (entdel (ssname ss i)) (setq i (1+ i)))))
  (setq k 1)
  (foreach x lst
    (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-erori*) '(62 . 1)
                    (list 10 (car (car x)) (cadr (car x)) 0.0) '(40 . 400.0)))
    (gb:text gb:*l-erori* (list (+ (car (car x)) 400.0) (+ (cadr (car x)) 400.0)) 250.0 (itoa k) gb:*st-text* "MC" 1)
    (setq k (1+ k)))
)

;; =========================================================================
;; COMANDA
;; =========================================================================
(defun c:GenerareGrinziBuiandrugi ( / *error* doc ms ss el e r lv top s p ox oy grupe sem g lst k txt ds0 n gata)
  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms (vla-get-modelspace doc))
  (defun *error* (msg)
    (if ds0 (gb:stil-cota doc ds0))
    (vla-endundomark doc)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nEroare: " msg)))
    (princ)
  )
  (setq gb:*err* nil gb:*el* nil)
  (princ "\nSelectati planul de cofraj (fereastra peste tot planul): ")
  (if (setq ss (ssget (list (cons 8 "Markers,Grinzi,Centuri,Stalpi,Axe,Cofrag"))))
    (progn
      (gb:citeste ss)
      ;; elementele (dublurile - doua texte pe acelasi element - o data)
      (foreach mk (reverse gb:*mk*)
        (if (and (setq e (gb:element mk))
                 (not (vl-some '(lambda (o) (and (= (gb:g 'name o) (gb:g 'name e))
                                                (equal (gb:g 'lo o) (gb:g 'lo e) gb:*tol*)
                                                (equal (gb:g 'hi o) (gb:g 'hi e) gb:*tol*)
                                                (equal (gb:g 'va o) (gb:g 'va e) gb:*tol*)))
                               el)))
          (setq el (cons e el))))
      (setq gb:*el* (reverse el) el nil)
      ;; sectiunile de cofraj, la elementele lor
      (foreach c gb:*cof*
        (if (setq e (gb:proprietar (cadr c)))
          (setq gb:*el* (subst (gb:pune 'secs (append (gb:g 'secs e) (list (gb:date-sectiune (car c) (cadr c)))) e)
                               e gb:*el*))))
      ;; reazeme, etrieri, axe - doar pentru grinzi si buiandrugi
      (foreach e gb:*el*
        (if (/= (gb:g 'tip e) "C")
          (progn
            (setq e (gb:reazeme e))
            (setq el (cons (gb:pune 'axes (gb:axe-element e) e) el)))))
      (setq el (gb:sort (reverse el)
                        '(lambda (a b) (if (= (gb:g 'tip a) (gb:g 'tip b))
                                         (< (gb:g 'num a) (gb:g 'num b))
                                         (= (gb:g 'tip a) "G")))))
      (if (null el)
        (alert "Nu am gasit nicio grinda (G..) sau buiandrug (B..) in selectie.")
        (progn
          ;; cota de sus: cea mai des intalnita pe grupurile de cofraj
          (foreach e gb:*el*
            (foreach sc (gb:g 'secs e)
              (foreach t1 (cadr sc)
                (if (setq r (assoc t1 lv)) (setq lv (subst (cons t1 (1+ (cdr r))) r lv)) (setq lv (cons (cons t1 1) lv))))))
          (setq top (if lv (gb:numar-cota (car (car (gb:sort lv '(lambda (a b) (> (cdr a) (cdr b)))))))))
          (if (null top) (setq top 2.75))
          (setq s (getstring (strcat "\nCota de sus a grinzilor si buiandrugilor (gasita pe cofraj) <" (gb:fmt-cota top) ">: ")))
          (if (and (/= s "") (gb:numar-cota s)) (setq top (gb:numar-cota s)))
          (foreach e el (gb:verifica-cofraj e top))
          (gb:verifica-buiandrugi el top)
          ;; elementele identice o singura data, cu numarul de bucati
          (foreach e el
            (setq sem (gb:semnatura e))
            (if (setq g (assoc sem grupe))
              (setq grupe (subst (list sem (cadr g) (1+ (caddr g))) g grupe))
              (setq grupe (append grupe (list (list sem e 1))))))
          (foreach g grupe
            (if (> (length (vl-remove-if-not '(lambda (x) (= (gb:g 'name (cadr x)) (gb:g 'name (cadr g)))) grupe)) 1)
              (if (not (member (gb:g 'name (cadr g)) lst))
                (progn
                  (setq lst (cons (gb:g 'name (cadr g)) lst))
                  (gb:err (gb:g 'p (cadr g)) (strcat (gb:g 'name (cadr g)) ": acelasi nume la elemente cu lungimi/reazeme diferite (am facut cate o desfasurata)"))))))
          (setq p (getpoint "\nColtul stanga-sus al primei desfasurate (fata de sus a elementelor): "))
          (if p
            (progn
              (vla-startundomark doc)
              (setq ds0 (getvar "DIMSTYLE"))
              (gb:stil-cota doc gb:*ds*)
              (gb:straturi)
              (setq p (trans p 1 0) ox (car p) oy (cadr p) n 0)
              (foreach g grupe
                (setq ox (+ ox (gb:deseneaza doc ms (cadr g) (caddr g) top ox oy) gb:*spatiu*) n (1+ n)))
              (setq gb:*err* (reverse gb:*err*))
              (gb:marcheaza-erori gb:*err*)
              (gb:stil-cota doc ds0)
              (setq ds0 nil)
              (vla-endundomark doc)
              (setq gata T)))
          (if gata
            (progn
              (princ (strcat "\nAm desenat " (itoa n) " desfasurate."))
              (if gb:*err*
                (progn
                  (setq k 1 txt "")
                  (foreach x gb:*err*
                    (setq txt (strcat txt (itoa k) ". " (cadr x) "\n") k (1+ k)))
                  (princ (strcat "\nProbleme gasite (marcate pe plan cu cerc rosu, layer \"" gb:*l-erori* "\"):\n" txt))
                  (alert (strcat "Am desenat " (itoa n) " desfasurate.\n\n"
                                 "Probleme gasite (numerele sunt marcate pe plan cu cerc rosu, layer \""
                                 gb:*l-erori* "\"):\n\n" txt)))
                (alert (strcat "Am desenat " (itoa n) " desfasurate. Nu am gasit probleme.")))))))))
  (princ)
)

(princ "\nGenerare grinzi si buiandrugi incarcat. Comanda: GenerareGrinziBuiandrugi")
(princ)
