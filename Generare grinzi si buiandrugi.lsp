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
;;   - sectiunea (grup pe "Sectiuni grinzi", numerotata 1, 2, 3... de la
;;     stanga la dreapta; RenumeroteazaSectiuni o renumeroteaza oricand), in
;;     prima treime a primei deschideri, de la reazemul din stanga; textul are
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
(setq gb:*xx-centru* 98.3)   ; mijlocul cifrei (care inlocuieste "xx") fata de punctul de jos al textului (h 120, mm)
(setq gb:*lat-etr*  280.0)   ; jumatate din latimea textului "etr. %%C8/15" (mm)
(setq gb:*diam*     "%%C8")
(setq gb:*arm-g*    "3%%C16")  ; armatura grinzilor, sus si jos
(setq gb:*arm-b*    "3%%C12")  ; armatura buiandrugilor, jos
(setq gb:*cioc-g*   250.0)     ; ciocurile barelor la grinzi (mm)
(setq gb:*cioc-b*   300.0)     ; ciocurile barelor la buiandrugi (mm)
;; randurile barelor de grinda sub fata de jos: sus la 1085 (ciocuri in jos),
;; jos cu 9 cm intre ciocuri (1085 + 250 + 90 + 250), al doilea rand de jos
;; (sectiune variabila) inca 330 mai jos
(setq gb:*y-jos-1*  1675.0)
(setq gb:*y-jos-2*  2005.0)
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
(setq gb:*ds-fier*   "Fier stalpi 50")
(setq gb:*l-marca*   "Otel marca")
(setq gb:*l-diam*    "Otel diametru")
(setq gb:*l-lung*    "Otel lungime")
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
                                 (cons 'id (strcat (nth 0 nm) (itoa (nth 1 nm))))
                                 (cons 'h (nth 3 nm)) (cons 'name (nth 4 nm))
                                 (cons 'p (list (car p) (cadr p))) (cons 'dir dr))
                           gb:*mk*)))
      ;; sectiunile de cofraj si cotele lor
      ;; sectiunea fara placa e un simplu dreptunghi (4 varfuri), cu placa
      ;; e in T sau L; triunghiurile cotelor de nivel nu intra
      ((and (= lay gb:*l-cofrag*) (= tip "LWPOLYLINE"))
       (setq v (gb:varfuri ed) pts (car v))
       (if (and (cadr v) (>= (length pts) 4)) (setq gb:*cof* (cons (list e pts) gb:*cof*))))
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

;; alt element (alt numar: G1 si G2; G1 30x50 si G1 30x40 sunt acelasi
;; element, cu sectiune variabila) are textul intre lo si hi, in fasia va-vb?
(defun gb:alt-nume (dr mk lo hi va vb)
  (vl-some '(lambda (o / q)
              (and (= (gb:g 'dir o) dr) (/= (gb:g 'id o) (gb:g 'id mk))
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
;; tronsoanele de inaltime ale unei grinzi: textele cu acelasi numar (ex.
;; "G1 30x50" si "G1 30x40") pe deschideri diferite dau sectiune variabila.
;; 'tr = ((u1 u2 h) ...) de la ua la ub; treapta e la fata stalpului dinspre
;; partea mai joasa (stalpul ramane la partea mai inalta). 'h = cea mai
;; mare inaltime; numele devine "G1 30x50(30x40)".
(defun gb:tronsoane (e / sups mks hs i a b q h tr st hu nm)
  (setq sups (gb:g 'sups e)
        mks (vl-remove-if-not
              '(lambda (o / q)
                 (and (= (gb:g 'id o) (gb:g 'id e)) (= (gb:g 'dir o) (gb:g 'dir e))
                      (setq q (gb:uv (gb:g 'dir e) (car (gb:g 'p o)) (cadr (gb:g 'p o))))
                      (< (gb:g 'va e) (cadr q) (gb:g 'vb e))
                      (<= (- (gb:g 'ua e) gb:*tol*) (car q) (+ (gb:g 'ub e) gb:*tol*))))
              gb:*mk*))
  ;; inaltimea fiecarei deschideri, dupa textul din ea
  (setq i 0)
  (repeat (1- (length sups))
    (setq a (cadr (nth i sups)) b (caddr (nth (1+ i) sups)) h nil)
    (foreach o mks
      (setq q (car (gb:uv (gb:g 'dir e) (car (gb:g 'p o)) (cadr (gb:g 'p o)))))
      (if (and (null h) (<= (- a gb:*tol*) q (+ b gb:*tol*))) (setq h (gb:g 'h o))))
    (setq hs (append hs (list h)) i (1+ i)))
  ;; deschiderile fara text iau inaltimea vecinei
  (setq h nil hs (mapcar '(lambda (x) (if x (setq h x) h)) hs))
  (setq h nil hs (reverse (mapcar '(lambda (x) (if x (setq h x) h)) (reverse hs))))
  (setq hs (mapcar '(lambda (x) (if x x (gb:g 'h e))) hs))
  (if (null hs) (setq hs (list (gb:g 'h e))))
  (setq st (gb:g 'ua e) i 0)
  (repeat (1- (length hs))
    (if (not (equal (nth i hs) (nth (1+ i) hs) 0.1))
      (progn
        (setq b (nth (1+ i) sups)
              a (if (> (nth i hs) (nth (1+ i) hs)) (caddr b) (cadr b))
              tr (append tr (list (list st a (nth i hs))))
              st a)))
    (setq i (1+ i)))
  (setq tr (append tr (list (list st (gb:g 'ub e) (last hs)))))
  (if (> (length tr) 1)
    (progn
      (foreach x tr (if (not (member (caddr x) hu)) (setq hu (append hu (list (caddr x))))))
      (setq nm (strcat (gb:g 'id e) " " (gb:cm (gb:g 'b e)) "x" (gb:cm (car hu))))
      (foreach x (cdr hu) (setq nm (strcat nm "(" (gb:cm (gb:g 'b e)) "x" (gb:cm x) ")")))
      (setq e (gb:pune 'name nm e))))
  (gb:pune 'h (apply 'max (mapcar 'caddr tr)) (gb:pune 'tr tr e))
)
;; inaltimea elementului in dreptul lui u
(defun gb:h-la (e u / r)
  (foreach x (gb:g 'tr e) (if (and (null r) (<= u (+ (cadr x) gb:*tol*))) (setq r (caddr x))))
  (if r r (caddr (last (gb:g 'tr e))))
)
;; conturul elementului (d = 0) sau al carcasei (d = 25 mm), in coordonate
;; locale (x de la capatul stang, y in jos de la fata de sus), cu trepte
(defun gb:contur (tr ua lt d / r pts k dr st hl hr x)
  (setq r (reverse tr)
        pts (list (list d (- d)) (list (- lt d) (- d)) (list (- lt d) (- d (caddr (car r))))))
  (setq k 0)
  (repeat (1- (length r))
    (setq dr (nth k r) st (nth (1+ k) r) hr (caddr dr) hl (caddr st)
          x (- (car dr) ua) x (if (> hl hr) (- x d) (+ x d))
          pts (append pts (list (list x (- d hr)) (list x (- d hl))))
          k (1+ k)))
  (append pts (list (list d (- d (caddr (last r))))))
)

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
(defun gb:axe-element (e / dr vm r c)
  (setq dr (gb:g 'dir e) vm (/ (+ (gb:g 'va e) (gb:g 'vb e)) 2.0))
  (foreach a gb:*axe*
    (setq c (cadr a))
    (if (and (/= (car a) dr)
             (<= (- (caddr a) gb:*tol*) vm (+ (cadddr a) gb:*tol*))
             (vl-some '(lambda (s) (and (member (car s) '("S" "G")) (<= (- (cadr s) gb:*tol*) c (+ (caddr s) gb:*tol*))))
                      (gb:g 'sups e))
             (not (vl-some '(lambda (x) (equal (car x) c gb:*tol*)) r)))
      (setq r (cons (list c (gb:eticheta-axa a)) r))))
  (gb:sort r '(lambda (a b) (< (car a) (car b))))
)

;; numele unei axe (dir c lo hi): textul de pe "Axe" de langa un capat al ei
(defun gb:eticheta-axa (a / dr c best q tu tv dd)
  (setq dr (- 1 (car a)) c (cadr a))
  (foreach t1 gb:*axtx*
    (setq q (gb:uv dr (car t1) (cadr t1)) tu (car q) tv (cadr q)
          dd (min (abs (- tv (caddr a))) (abs (- tv (cadddr a)))))
    (if (and (<= (abs (- tu c)) 350.0) (< dd 800.0)
             (or (> tv (- (cadddr a) 50.0)) (< tv (+ (caddr a) 50.0)))
             (or (null best) (< dd (car best))))
      (setq best (list dd (caddr t1)))))
  (if best (cadr best) "?")
)

;; acelasi nume la axe paralele diferite (la distanta una de alta) = greseala
(defun gb:verifica-axe ( / lst vazut n p)
  (foreach a gb:*axe*
    (if (not (vl-some '(lambda (x) (and (= (car x) (car a)) (equal (cadr x) (cadr a) gb:*tol*))) lst))
      (setq lst (cons (list (car a) (cadr a) (gb:eticheta-axa a) (caddr a) (cadddr a)) lst))))
  (foreach a lst
    (if (and (/= (caddr a) "?") (not (member (list (car a) (caddr a)) vazut)))
      (progn
        (setq n (length (vl-remove-if-not '(lambda (x) (and (= (car x) (car a)) (= (caddr x) (caddr a)))) lst)))
        (if (> n 1)
          (progn
            (setq vazut (cons (list (car a) (caddr a)) vazut)
                  p (if (= (car a) 1) (list (cadr a) (nth 4 a)) (list (nth 3 a) (cadr a))))
            (gb:err p (strcat "Axa " (caddr a) " apare la " (itoa n) " axe " (if (= (car a) 1) "verticale" "orizontale")
                              " diferite - verificati numerotarea axelor")))))))
)

;; un stalp din fasia elementului e, intre pozitia c (in afara elementului)
;; si capatul cel mai apropiat al lui? Atunci sectiunea din c e a altui
;; element din prelungire (de obicei o centura), nu a lui e.
(defun gb:stalp-intre (e c / dr a b)
  (setq dr (gb:g 'dir e))
  (if (< c (gb:g 'lo e))
    (setq a c b (gb:g 'lo e))
    (setq a (gb:g 'hi e) b c))
  (vl-some '(lambda (col / k)
              (setq k (gb:cbox dr col))
              (and (> (gb:suprap (cadr k) (cadddr k) (gb:g 'va e) (gb:g 'vb e)) gb:*tol*)
                   (>= (car k) (- a gb:*tol*)) (<= (caddr k) (+ b gb:*tol*))))
           gb:*col*)
)

;; Centura in care sta un buiandrug fara centura cu nume (C..) aproape:
;; daca buiandrugul e intre doua linii de centura (layer Centuri), la o
;; distanta de cel mult 60 cm una de alta, centura e acolo, doar ca nu are
;; text. Inaltimea ei = cea mai deasa inaltime din numele centurilor.
;; Se adauga la elemente, ca sa-si primeasca si sectiunile de cofraj.
(defun gb:centura-fara-nume (e / dr pu vm sus jos ia ib iv x lo hi hs r h)
  (setq dr (gb:g 'dir e) vm (/ (+ (gb:g 'va e) (gb:g 'vb e)) 2.0)
        pu (/ (+ (gb:g 'lo e) (gb:g 'hi e)) 2.0))
  (foreach s (gb:paralele gb:*l-centuri* dr)
    (if (<= (- (cadr s) gb:*tol*) pu (+ (caddr s) gb:*tol*))
      (cond
        ((>= (car s) (- (gb:g 'vb e) gb:*tol*)) (if (or (null sus) (< (car s) sus)) (setq sus (car s))))
        ((<= (car s) (+ (gb:g 'va e) gb:*tol*)) (if (or (null jos) (> (car s) jos)) (setq jos (car s)))))))
  (if (and sus jos (<= (- sus jos) 600.0))
    (progn
      (setq ia (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) jos gb:*tol*)) (gb:paralele gb:*l-centuri* dr))))
            ib (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) sus gb:*tol*)) (gb:paralele gb:*l-centuri* dr))))
            iv (gb:intersectie ia ib))
      (foreach x iv (if (<= (- (car x) gb:*tol*) pu (+ (cadr x) gb:*tol*)) (setq lo (car x) hi (cadr x))))
      (foreach m gb:*mk*
        (if (= (gb:g 'tip m) "C")
          (if (setq r (assoc (gb:g 'h m) hs)) (setq hs (subst (cons (car r) (1+ (cdr r))) r hs)) (setq hs (cons (cons (gb:g 'h m) 1) hs)))))
      (if (and lo hs)
        (progn
          (setq h (car (car (gb:sort hs '(lambda (a b) (> (cdr a) (cdr b)))))))
          (list (cons 'tip "C") (cons 'num 0) (cons 'b (- sus jos)) (cons 'id "C?")
                (cons 'h h) (cons 'name (strcat "centura fara nume langa " (gb:g 'name e)))
                (cons 'p (gb:uv dr pu vm)) (cons 'dir dr)
                (cons 'lo lo) (cons 'hi hi) (cons 'va jos) (cons 'vb sus))))))
)

;; elementul caruia ii apartine o sectiune de cofraj (aceleasi doua fete,
;; cel mai aproape de-a lungul lui); nil daca nu e niciunul. O sectiune din
;; afara elementului ii apartine numai daca nu e un stalp intre ele.
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
        (if (and (<= dd gb:*sect-max*)
                 (or (<= dd gb:*tol*) (not (gb:stalp-intre e c)))
                 (or (null best) (< dd (car best))))
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
  (list (reverse dims) (car tx) (cadr tx) (list (/ (+ x1 x2) 2.0) (/ (+ y1 y2) 2.0)) pts)
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

(defun gb:verifica-cofraj (e top / secs s dims lib fld sum t1 b1 p hh)
  (setq secs (gb:g 'secs e) p (gb:g 'p e))
  (cond
    ((null secs)
     (if (= (gb:g 'tip e) "G")
       (gb:err p (strcat (gb:g 'name e) ": nu am gasit grupul de cofraj (sectiunea) pe plan"))))
    (T
     (foreach s secs
       (setq dims (car s) lib (cadr s) fld (caddr s)
             ;; inaltimea elementului in dreptul sectiunii (sectiune variabila)
             hh (gb:h-la e (car (gb:uv (gb:g 'dir e) (car (cadddr s)) (cadr (cadddr s))))))
       (if dims
         (progn
           (setq sum (apply '+ dims))
           (if (not (equal sum hh gb:*tol*))
             (gb:err p (strcat (gb:g 'name e) ": inaltimea din nume este " (gb:cm hh)
                               " cm, grupul de cofraj arata "
                               (apply 'strcat (cdr (apply 'append (mapcar '(lambda (d) (list "+" (gb:cm d))) dims))))
                               " = " (gb:cm sum) " cm")))))
       (if (and lib fld (setq t1 (gb:numar-cota (car lib))) (setq b1 (gb:numar-cota (car fld))))
         (progn
           (if (not (equal (* 1000.0 (- t1 b1)) hh gb:*tol*))
             (gb:err p (strcat (gb:g 'name e) ": cotele de nivel din grupul de cofraj (" (car lib) " / " (car fld)
                               ") dau " (gb:cm (* 1000.0 (- t1 b1))) " cm, numele spune " (gb:cm hh) " cm")))
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
                   (list gb:*l-bucati* 7 nil) (list gb:*l-erori* 1 nil)
                   (list gb:*l-marca* 2 nil) (list gb:*l-diam* 7 nil) (list gb:*l-lung* 7 nil)
                   (list gb:*l-ocg* 4 nil) (list gb:*l-buc-c* 7 nil) (list gb:*l-chenar-s* 23 "HIDDEN")
                   (list gb:*l-chenar-a* 6 nil) (list gb:*l-chenar-e* 21 "HIDDEN"))
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
  (setq j (cond ((= just "MC") '(1 2)) ((= just "BR") '(2 1)) ((= just "L") '(0 0)) ((= just "M") '(4 0)) (T '(1 0))))
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
(defun gb:cota (ms p1 p2 pl rot)
  (gb:cota-stil ms p1 p2 pl rot gb:*ds*)
)
(defun gb:cota-stil (ms p1 p2 pl rot ds / d)
  (setq d (vla-adddimrotated ms (vlax-3d-point (list (car p1) (cadr p1) 0.0)) (vlax-3d-point (list (car p2) (cadr p2) 0.0))
                             (vlax-3d-point (list (car pl) (cadr pl) 0.0)) rot))
  (vla-put-layer d gb:*l-cote*)
  (if (tblsearch "DIMSTYLE" ds) (vl-catch-all-apply 'vla-put-stylename (list d ds)))
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
;; xr = capatul elementului; stanga = T pentru grupul de la capatul stang
;; (sectiune variabila). Simbolul: triunghi cu varful pe linia de nivel,
;; impartit in doua: jumatatea stanga hasurata SOLID, cea dreapta goala.
(defun gb:cote-nivel (doc ms xr yt h top stanga / d objs ax tsus tjos pl pr yl yv fc)
  (setq ax (if stanga (- xr 885.1) (+ xr 440.1)))
  (setq d (gb:cota ms (list xr yt) (list xr (- yt h)) (list (if stanga (- xr 206.4) (+ xr 250.0)) yt) (/ pi 2.0)))
  (setq objs (list d))
  (foreach yl (list yt (- yt h))
    (setq yv (+ yl 68.5)
          pl (gb:o (gb:poli gb:*l-cote* (list (list (- ax 30.6) yv) (list ax yv) (list ax yl))))
          pr (gb:o (gb:poli gb:*l-cote* (list (list ax yv) (list (+ ax 30.6) yv) (list ax yl)))))
    (setq objs (append objs
                       (list (gb:o (gb:linie gb:*l-cote* (list (- ax 73.0) yl) (list (+ ax 73.0) yl)))
                             pl (gb:hasura ms pl "SOLID" 1.0 gb:*l-cote*) pr
                             (gb:o (gb:linie gb:*l-cote* (list (- ax 30.6) yv) (list (+ ax 487.4) yv)))))))
  (setq tsus (gb:o (gb:text gb:*l-cote* (list (+ ax 179.3) (+ yt 179.4)) 125.0 (gb:fmt-cota top) gb:*st-text* "MC" nil))
        tjos (gb:o (gb:text gb:*l-cote* (list (+ ax 179.3) (+ (- yt h) 179.4)) 125.0
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
;; linia sectiunii (si o cifra langa ea, cat ramane din "xx") nu trebuie
;; sa treaca peste textul etrierilor; "xx" poate sta peste hasuri
;; grup de armatura longitudinala, ca cele desenate manual (si ca la placi):
;; bara cu ciocuri (FIER), cotele ciocurilor si a lungimii ("Fier stalpi 50"),
;; cercul marcii (0), marca "y" (se renumeroteaza), diametrul si lungimea
;; L= ca FIELD legat de lungimea barei. vb = bara, cioc > 0 in sus, < 0 in jos.
(defun gb:armatura (doc ms x1 x2 vb cioc diam cu / pl yc d1 d2 d3 cerc marca dt lung ut tp g)
  (setq yc (+ vb cioc))
  ;; marca, diametrul si L= cam la mijlocul barei; textul cotei lungimii
  ;; (ut) la mijlocul distantei dintre diametru si cota ciocului din dreapta,
  ;; ca sa nu stea pe mijlocul barei (s-ar muta bara cu el). La barele
  ;; scurte, eticheta (cerc..diametru, ~590 mm) si textul cotei (~300 mm)
  ;; se aseaza cu spatii egale intre ele si fata de capete.
  (if (< (- x2 x1) 3000.0)
    (setq g (max 0.0 (/ (- x2 x1 590.0 300.0) 3.0))
          cu (+ x1 g 117.0)
          ut (+ cu 470.0 g 150.0))
    (setq ut (/ (+ cu 470.0 x2) 2.0)))
  (setq pl (entmakex
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-fier*) '(100 . "AcDbPolyline")
                   '(90 . 4) '(70 . 0)
                   (list 10 x1 yc) (list 10 x1 vb) (list 10 x2 vb) (list 10 x2 yc))))
  (setq cerc (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-elem*) (list 10 cu (+ vb 142.4) 0.0) '(40 . 116.994))))
  (setq marca (gb:text gb:*l-marca* (list (- cu 5.6) (+ vb 87.5)) 120.0 "y" gb:*st-axe* "BC" nil))
  (setq dt (gb:text gb:*l-diam* (list (+ cu 218.7) (+ vb 68.2)) 100.0 diam gb:*st-axe* "L" nil))
  (setq lung (gb:text gb:*l-lung* (list (+ cu 205.1) (- vb 156.3)) 100.0
                      (strcat "L=" (gb:rtos (/ (+ (- x2 x1) (* 2.0 (abs cioc))) 1000.0) 2) "m") gb:*st-axe* "L" 5))
  (vl-catch-all-apply 'vla-put-textstring
    (list (gb:o lung) (strcat "L=%<\\AcObjProp Object(%<\\_ObjId " (gb:id doc (gb:o pl))
                              ">%).Length \\f \"%lu2%pr2%ct8[0.001]\">%m")))
  (setq d1 (gb:cota-stil ms (list x1 vb) (list x1 yc) (list x1 yc) (/ pi 2.0) gb:*ds-fier*)
        d2 (gb:cota-stil ms (list x2 vb) (list x2 yc) (list x2 yc) (/ pi 2.0) gb:*ds-fier*)
        d3 (gb:cota-stil ms (list x1 vb) (list x2 vb) (list x2 vb) 0.0 gb:*ds-fier*))
  ;; cotele armaturii stau pe layerul FIER
  (foreach d (list d1 d2 d3) (vla-put-layer d gb:*l-fier*))
  (if (and (setq tp (vl-catch-all-apply 'vlax-get (list d3 'TextPosition)))
           (not (vl-catch-all-error-p tp)))
    ;; mijlocul textului pe linia cotei, ca in desenele facute manual
    (vl-catch-all-apply 'vlax-put (list d3 'TextPosition (list ut vb (caddr tp)))))
  (gb:grup doc (append (mapcar 'gb:o (list pl cerc marca dt lung)) (list d1 d2 d3)))
)

;; =========================================================================
;; NUMARAREA ETRIERILOR SI BARELOR CENTURILOR, DIN PLAN
;; =========================================================================
;; fasiile centurilor: doua linii paralele de pe "Centuri", la distanta egala
;; cu latimea unei centuri cu nume (C..), fara alta linie intre ele, pe
;; portiunea pe care exista amandoua. Intoarce ((dr va vb lo hi) ...)
(defun gb:fasii-centuri ( / lat ps vs r ia ib)
  (foreach m gb:*mk*
    (if (and (= (gb:g 'tip m) "C") (not (vl-some '(lambda (x) (equal x (gb:g 'b m) gb:*tol*)) lat)))
      (setq lat (cons (gb:g 'b m) lat))))
  (foreach dr '(0 1)
    (setq ps (gb:paralele gb:*l-centuri* dr) vs nil)
    (foreach s ps
      (if (not (vl-some '(lambda (x) (equal x (car s) gb:*tol*)) vs)) (setq vs (cons (car s) vs))))
    (foreach v1 vs
      (foreach v2 vs
        (if (and (> v2 (+ v1 gb:*tol*)) (vl-some '(lambda (b) (equal (- v2 v1) b gb:*tol*)) lat))
          (progn
            (setq ia (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) v1 gb:*tol*)) ps)))
                  ib (gb:uneste (mapcar 'cdr (vl-remove-if-not '(lambda (s) (equal (car s) v2 gb:*tol*)) ps))))
            (foreach x (gb:intersectie ia ib)
              (if (not (vl-some '(lambda (s) (and (> (car s) (+ v1 gb:*tol*)) (< (car s) (- v2 gb:*tol*))
                                                  (> (gb:suprap (cadr s) (caddr s) (car x) (cadr x)) gb:*tol*)))
                                ps))
                (setq r (cons (list dr v1 v2 (car x) (cadr x)) r)))))))))
  (reverse r)
)

;; centura (textul C..) a unei fasii: textul aflat in ea; altfel, dupa
;; latime, singurul tip de centura cu latimea ei. nil daca nu se gaseste
(defun gb:tip-fasie (f / dr va vb lo hi q m r tips)
  (setq dr (car f) va (cadr f) vb (caddr f) lo (nth 3 f) hi (nth 4 f))
  (foreach m gb:*mk*
    (if (= (gb:g 'tip m) "C")
      (progn
        (setq q (gb:uv dr (car (gb:g 'p m)) (cadr (gb:g 'p m))))
        (if (and (null r) (< va (cadr q) vb) (<= (- lo gb:*tol*) (car q) (+ hi gb:*tol*)))
          (setq r m)))))
  (if (and r (not (equal (gb:g 'b r) (- vb va) gb:*tol*)))
    (gb:err (gb:uv dr (* 0.5 (+ lo hi)) (* 0.5 (+ va vb)))
            (strcat (gb:g 'name r) ": latimea din nume este " (gb:cm (gb:g 'b r)) " cm, pe plan are " (gb:cm (- vb va)) " cm")))
  (if (null r)
    (progn
      (foreach m gb:*mk*
        (if (and (= (gb:g 'tip m) "C") (equal (gb:g 'b m) (- vb va) gb:*tol*)
                 (not (vl-some '(lambda (o) (equal (gb:g 'h o) (gb:g 'h m) gb:*tol*)) tips)))
          (setq tips (cons m tips))))
      (setq r (car tips))
      (if (cdr tips)
        (gb:err (gb:uv dr (* 0.5 (+ lo hi)) (* 0.5 (+ va vb)))
                (strcat "Centura fara nume, lata de " (gb:cm (- vb va)) " cm: sunt mai multe centuri cu latimea asta;"
                        " am numarat-o la " (gb:g 'name r) " - scrieti numele pe ea")))))
  r
)

;; portiunile fasiei ocupate de stalpi si de grinzi (fara etrieri de centura)
(defun gb:blocuri-fasie (f / dr va vb lo hi k r)
  (setq dr (car f) va (cadr f) vb (caddr f) lo (nth 3 f) hi (nth 4 f))
  (foreach c gb:*col*
    (setq k (gb:cbox dr c))
    (if (and (> (gb:suprap (cadr k) (cadddr k) va vb) gb:*tol*) (>= (gb:suprap (car k) (caddr k) lo hi) (- gb:*tol*)))
      (setq r (cons (list (car k) (caddr k)) r))))
  (foreach o gb:*el*
    (if (= (gb:g 'tip o) "G")
      (progn
        (setq k (if (= (gb:g 'dir o) dr)
                  (list (gb:g 'lo o) (gb:g 'va o) (gb:g 'hi o) (gb:g 'vb o))
                  (list (gb:g 'va o) (gb:g 'lo o) (gb:g 'vb o) (gb:g 'hi o))))
        (if (and (> (gb:suprap (cadr k) (cadddr k) va vb) gb:*tol*) (>= (gb:suprap (car k) (caddr k) lo hi) (- gb:*tol*)))
          (setq r (cons (list (car k) (caddr k)) r))))))
  (gb:uneste r)
)

;; etrierii unei fasii: pas 15 intre stalpi / grinzi (de la fata lor),
;; ultimul la capat ca sa nu ramana mai mult de 15 cm; la capetele libere
;; (fata zidului perpendicular) primul la 5 cm
(defun gb:etr-fasie (f bl / lo hi cur n zs a b L k)
  (setq lo (nth 3 f) hi (nth 4 f) cur lo n 0)
  (foreach x bl
    (if (> (car x) (+ cur gb:*tol*)) (setq zs (cons (list cur (min (car x) hi)) zs)))
    (setq cur (max cur (cadr x))))
  (if (> hi (+ cur gb:*tol*)) (setq zs (cons (list cur hi) zs)))
  (foreach z zs
    (setq a (if (vl-some '(lambda (x) (equal (cadr x) (car z) gb:*tol*)) bl) (car z) (+ (car z) gb:*etr-dist*))
          b (if (vl-some '(lambda (x) (equal (car x) (cadr z) gb:*tol*)) bl) (cadr z) (- (cadr z) gb:*etr-dist*))
          L (- b a))
    (if (>= L 0.0)
      (progn
        (setq k (1+ (fix (+ (/ L gb:*pas-mij*) 1e-6))))
        (if (> (- L (* (1- k) gb:*pas-mij*)) 10.0) (setq k (1+ k)))
        (setq n (+ n k)))))
  n
)

;; cat intra barele centurii dincolo de capatul u al fasiei: peste stalpul
;; sau zidul perpendicular de acolo, pana la 25 mm de fata lui
(defun gb:ext-capat (f u fasii / dr va vb r k)
  (setq dr (car f) va (cadr f) vb (caddr f) r 0.0)
  (foreach c gb:*col*
    (setq k (gb:cbox dr c))
    (if (and (> (gb:suprap (cadr k) (cadddr k) va vb) gb:*tol*)
             (or (equal (car k) u gb:*tol*) (equal (caddr k) u gb:*tol*)))
      (setq r (max r (- (caddr k) (car k) 25.0)))))
  (foreach g fasii
    (if (and (/= (car g) dr)
             (or (equal (cadr g) u gb:*tol*) (equal (caddr g) u gb:*tol*))
             (>= (gb:suprap (nth 3 g) (nth 4 g) va vb) (- gb:*tol*)))
      (setq r (max r (- (caddr g) (cadr g) 25.0)))))
  r
)

;; numararea: ((tag . etrieri) ...) pe tipuri de centura ("C300x250") si
;; o estimare a barelor de 12 m (cu innadiri de 50 de diametre), doar in
;; rezumatul din linia de comanda (barele raman "xxx buc." in desen)
(defun gb:centuri-calcul (arm / fasii f m tag r n lt nb lap buc lv)
  (setq fasii (gb:fasii-centuri) lt 0.0)
  (foreach f fasii
    (if (setq m (gb:tip-fasie f))
      (progn
        (setq tag (strcat "C" (gb:rtos (gb:g 'b m) 0) "x" (gb:rtos (gb:g 'h m) 0))
              n (gb:etr-fasie f (gb:blocuri-fasie f)))
        (if (setq r (assoc tag lv))
          (setq lv (subst (list tag (+ (cadr r) n) (caddr r)) r lv))
          (setq lv (append lv (list (list tag n (gb:g 'name m))))))
        (setq lt (+ lt (- (nth 4 f) (nth 3 f)) (gb:ext-capat f (nth 3 f) fasii) (gb:ext-capat f (nth 4 f) fasii))))
      (gb:err (gb:uv (car f) (* 0.5 (+ (nth 3 f) (nth 4 f))) (* 0.5 (+ (cadr f) (caddr f))))
              (strcat "Centura lata de " (gb:cm (- (caddr f) (cadr f))) " cm fara nume (C..) - nu am numarat-o"))))
  (setq nb (if arm (car arm) 4) lap (* 50.0 (if arm (cadr arm) 12))
        buc (if (> lt 0.0) (fix (+ (/ (* nb lt) (- 12000.0 lap)) 0.999999)) 0))
  (princ "\nCenturi (din plan):")
  (foreach r lv
    (princ (strcat "\n  " (caddr r) ": " (itoa (cadr r)) " etrieri")))
  (princ (strcat "\n  bare " gb:*arm-c* ": " (gb:rtos (/ lt 1000.0) 2) " m de centura x " (itoa nb)
                 " = " (gb:rtos (/ (* nb lt) 1000.0) 1) " m -> ~" (itoa buc) " bare de 12 m (innadiri de "
                 (gb:rtos (/ lap 10.0) 0) " cm), fara barele L / T si fara grinzile scurte in continuarea centurii"
                 " - doar orientativ; bucatile barelor se completeaza manual (xxx buc.)"))
  (list (mapcar '(lambda (r) (cons (car r) (cadr r))) lv) buc)
)

;; inaltimea centurii in care sta buiandrugul (aceeasi fasie, cea mai
;; apropiata de-a lungul lui); nil daca nu se gaseste
(defun gb:h-centura (e / o) (if (setq o (gb:centura-el e)) (gb:g 'h o)))
(defun gb:centura-el (e / best dd)
  (foreach o gb:*el*
    (if (and (= (gb:g 'tip o) "C") (= (gb:g 'dir o) (gb:g 'dir e))
             (> (gb:suprap (gb:g 'va o) (gb:g 'vb o) (gb:g 'va e) (gb:g 'vb e)) (* 0.5 (- (gb:g 'vb e) (gb:g 'va e)))))
      (progn
        (setq dd (max 0.0 (- (gb:g 'lo o) (gb:g 'hi e)) (- (gb:g 'lo e) (gb:g 'hi o))))
        (if (and (<= dd 3000.0) (or (null best) (< dd (car best))))
          (setq best (list dd o))))))
  (cadr best)
)

(defun gb:xx-loveste (xs txs)
  (vl-some '(lambda (xm) (and (< (- xm gb:*lat-etr*) (+ xs 30.0)) (> (+ xm gb:*lat-etr*) (- xs 100.0)))) txs)
)
;; cel mai apropiat loc liber pentru sectiune, in deschiderea s; altfel xs
(defun gb:xx-liber (xs s txs / d r)
  (setq d 25.0)
  (while (and (null r) (< d (- (cadr s) (car s))))
    (foreach x (list (- xs d) (+ xs d))
      (if (and (null r) (>= x (+ (car s) 100.0)) (<= x (cadr s)) (not (gb:xx-loveste x txs)))
        (setq r x)))
    (setq d (+ d 25.0)))
  (if r r xs)
)

(defun gb:deseneaza (doc ms e n top ox oy / ua ub lt h yb yj x et zones desc pct pt2 a b xm s xs xss txs titlu cu hc tr k j x1 x2 ce pc)
  (setq ua (gb:g 'ua e) ub (gb:g 'ub e) lt (- ub ua) h (gb:g 'h e) yb (- oy h) tr (gb:g 'tr e))
  (defun gb:x (u) (+ ox (- u ua)))
  (defun gb:yjos (u) (- oy (gb:h-la e u)))
  ;; elementul si carcasa (cu trepte la sectiune variabila)
  ;; conturul poarta datele pentru SectiuniGrinzi (ascunse, XDATA)
  (setq ce (gb:centura-el e) hc (if ce (gb:g 'h ce) 250.0)
        pc (cond ((gb:placa e)) ((and (= (gb:g 'tip e) "B") ce) (gb:placa ce)) ((and (/= (gb:g 'tip e) "B") gb:*t-placa*) (list gb:*t-placa* T T))))
  (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-elem*) '(100 . "AcDbPolyline")
                          (cons 90 (length (gb:contur tr ua lt 0.0))) '(70 . 1))
                    (mapcar '(lambda (p) (list 10 (+ ox (car p)) (+ oy (cadr p)))) (gb:contur tr ua lt 0.0))
                    (list (gb:date-scrie
                            (list (cons "tip" (gb:g 'tip e)) (cons "nume" (gb:g 'name e))
                                  (cons "b" (gb:rtos (gb:g 'b e) 1)) (cons "top" (gb:rtos top 3))
                                  (cons "placa" (if pc (strcat (gb:rtos (car pc) 1) (if (cadr pc) " T" " nil") (if (caddr pc) " T" " nil")) ""))
                                  (cons "hc" (gb:rtos hc 1))
                                  (cons "tagc" (strcat "C" (gb:rtos (if ce (gb:g 'b ce) (gb:g 'b e)) 0) "x" (gb:rtos hc 0))))))))
  (gb:poli gb:*l-fier* (mapcar '(lambda (p) (list (+ ox (car p)) (+ oy (cadr p)))) (gb:contur tr ua lt gb:*acop*)))
  ;; reazemele
  (foreach s (gb:g 'sups e)
    (cond
      ((= (car s) "S") (gb:simbol-reazem doc ms (gb:x (cadr s)) (gb:x (caddr s)) (gb:yjos (/ (+ (cadr s) (caddr s)) 2.0)) "ANSI31" 35.0))
      ((= (car s) "Z") (gb:simbol-reazem doc ms (gb:x (cadr s)) (gb:x (caddr s)) (gb:yjos (/ (+ (cadr s) (caddr s)) 2.0)) "AR-B88" 0.8))
      ((= (car s) "G")
       (setq a (gb:o (gb:dreptunghi gb:*l-elem* (gb:x (cadr s)) oy (gb:x (caddr s)) (- oy (cadddr s)))))
       (gb:grup doc (list a (gb:hasura ms a "ANSI31" 35.0 gb:*l-elem*))))))
  ;; etrierii
  (setq et (if (= (gb:g 'tip e) "G")
             (gb:etr-grinda (gb:g 'sups e))
             (gb:etr-buiandrug (gb:g 'sups e) ua ub))
        zones (cadr et) desc (caddr et))
  (foreach u (car et)
    (gb:linie gb:*l-etr* (list (gb:x u) (- oy gb:*acop*)) (list (gb:x u) (+ (gb:yjos u) gb:*acop*))))
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
  ;; la sectiune variabila: cate o sectiune pe fiecare tronson, in prima lui
  ;; deschidere
  (setq txs (mapcar '(lambda (z) (/ (+ (car z) (cadr z)) 2.0)) zones) xss nil)
  (foreach x tr
    (setq a (vl-some '(lambda (d) (if (>= (car d) (- (car x) gb:*tol*)) d)) desc))
    (if a
      (progn
        (setq s (list (car a) (+ (car a) (/ (- (cadr a) (car a)) 3.0)))
              xs (- (cadr s) 50.0))
        ;; intai in prima treime, apoi oriunde in deschidere
        (if (gb:xx-loveste xs txs) (setq xs (gb:xx-liber xs s txs)))
        (if (gb:xx-loveste xs txs) (setq xs (gb:xx-liber xs a txs)))
        (if (not (member xs xss)) (setq xss (append xss (list xs)))))))
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
  ;; la treptele sectiunii variabile: ciocurile barelor de jos, pe carcasa.
  ;; Bara tronsonului inalt se opreste la treapta (cioc in sus); bara
  ;; tronsonului jos trece la nivelul ei peste stalp, pana la cealalta fata
  ;; a lui (cioc in sus). La capete ciocurile cad pe carcasa.
  (setq k 0)
  (repeat (1- (length tr))
    (setq x1 (nth k tr) x2 (nth (1+ k) tr) s (gb:reazem-la e (cadr x1)))
    (if s
      (progn
        (if (> (caddr x1) (caddr x2))
          (setq a (- (caddr s) gb:*acop*) b (+ (cadr s) gb:*acop*))
          (setq a (+ (cadr s) gb:*acop*) b (- (caddr s) gb:*acop*)))
        (setq hc (- (max (caddr x1) (caddr x2)) gb:*acop*) j (- (min (caddr x1) (caddr x2)) gb:*acop*))
        (gb:linie gb:*l-fier* (list (gb:x a) (- oy hc)) (list (gb:x a) (+ (- oy hc) gb:*cioc-g*)))
        (entmakex (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-fier*) '(100 . "AcDbPolyline")
                        '(90 . 3) '(70 . 0)
                        (list 10 (gb:x a) (- oy j)) (list 10 (gb:x b) (- oy j))
                        (list 10 (gb:x b) (+ (- oy j) gb:*cioc-g*))))))
    (setq k (1+ k)))
  ;; cota de inaltime si cotele de nivel; la sectiune variabila la ambele capete
  (gb:cote-nivel doc ms (+ ox lt) oy (caddr (last tr)) top nil)
  (if (> (length tr) 1) (gb:cote-nivel doc ms ox oy (caddr (car tr)) top T))
  ;; sectiunile "xx"
  (foreach xs xss
    (progn
      ;; jos, sub fata de jos a grinzii in dreptul sectiunii (sectiune variabila)
      (setq yj (gb:yjos xs) xs (gb:x xs) gb:*nr-sect* (1+ gb:*nr-sect*))
      (gb:grup doc (list (gb:o (gb:linie gb:*l-sect* (list xs (+ oy 83.7)) (list xs (+ oy 195.6))))
                         (gb:o (gb:linie gb:*l-sect* (list xs (- yj 103.5)) (list xs (- yj 215.3))))
                         (gb:o (gb:text gb:*l-sect* (list (- xs 40.0) (+ oy 139.7 (- gb:*xx-centru*))) 120.0 (itoa gb:*nr-sect*) gb:*st-text* "BR" nil))
                         (gb:o (gb:text gb:*l-sect* (list (- xs 40.0) (- yj 159.4 gb:*xx-centru*)) 120.0 (itoa gb:*nr-sect*) gb:*st-text* "BR" nil))))))
  ;; armatura longitudinala: la grinzi un rand sus si unul jos (3%%C16),
  ;; la buiandrugi doar jos (3%%C12; sus sunt barele centurii); bara e cu
  ;; 25 mm mai scurta la fiecare capat; marca "y" se renumeroteaza
  ;; centrul cercului marcii: eticheta (cerc, diametru, L=) centrata pe bara
  (setq cu (+ ox (/ lt 2.0) -200.0))
  (if (= (gb:g 'tip e) "G")
    (progn
      ;; sus: continua
      (gb:armatura doc ms (+ ox gb:*acop*) (+ ox lt (- gb:*acop*)) (- yb 1085.0) (- gb:*cioc-g*) gb:*arm-g* cu)
      (if (= (length tr) 1)
        (gb:armatura doc ms (+ ox gb:*acop*) (+ ox lt (- gb:*acop*)) (- yb gb:*y-jos-1*) gb:*cioc-g* gb:*arm-g* cu)
        ;; jos, la sectiune variabila: cate o bara pe fiecare tronson, peste
        ;; tot stalpul de la treapta (barele vecine se petrec pe stalp), pe
        ;; doua randuri alternate
        (progn
          (setq k 0)
          (foreach x tr
            (setq s (if (> k 0) (gb:reazem-la e (car x)))
                  x1 (if s (+ (gb:x (cadr s)) gb:*acop*) (+ ox gb:*acop*))
                  s (if (< k (1- (length tr))) (gb:reazem-la e (cadr x)))
                  x2 (if s (- (gb:x (caddr s)) gb:*acop*) (+ ox lt (- gb:*acop*)))
                  j (- (length tr) 1 k))
            (gb:armatura doc ms x1 x2 (- yb (if (= (rem j 2) 0) gb:*y-jos-1* gb:*y-jos-2*)) gb:*cioc-g* gb:*arm-g*
                         (+ (/ (+ x1 x2) 2.0) -200.0))
            (setq k (1+ k))))))
    (progn
      ;; fierul de jos al centurii: la (inaltimea centurii - 2 x 25 mm) sub
      ;; fierul de sus al carcasei
      (setq hc (gb:h-centura e))
      (if (null hc)
        (progn
          (setq hc 250.0)
          (gb:err (gb:g 'p e) (strcat (gb:g 'name e) ": nu am gasit centura in care sta; fierul centurii l-am pus pentru centura de 25 cm"))))
      (gb:linie gb:*l-fier* (list (+ ox gb:*acop*) (- oy hc (- gb:*acop*)))
                (list (+ ox lt (- gb:*acop*)) (- oy hc (- gb:*acop*))))
      ;; etrierii centurii, langa cei ai buiandrugului (la 25 mm), pe "Otel
      ;; centuri global" - doar figurati, nu se numara; nu intra in stalpi
      (foreach u (car et)
        (setq x (+ u gb:*acop*) s (gb:reazem-la e x))
        (if (and (not (and s (member (car s) '("S" "G")))) (< x (- ub gb:*acop*)))
          (gb:linie gb:*l-ocg* (list (gb:x x) (- oy gb:*acop*)) (list (gb:x x) (- oy hc (- gb:*acop*))))))
      (gb:armatura doc ms (+ ox gb:*acop*) (+ ox lt (- gb:*acop*)) (- yb 1210.0) gb:*cioc-b* gb:*arm-b* cu)))
  ;; chenarele pentru renumerotare si extras, strict pe lungimea elementului
  ;; (cotele de nivel raman afara, ca desfasuratele sa poata fi apropiate):
  ;;  - "Chenar etrieri": etrierii si numerele sectiunilor (sus si jos)
  ;;  - "Chenar pentru armatura": titlul (numele, bucatile) si grupurile
  ;;    barelor lungi de dedesubt
  (gb:dreptunghi gb:*l-chenar-e* (+ ox 5.0) (+ oy 260.0) (+ ox lt -5.0) (- yb 330.0))
  (gb:dreptunghi gb:*l-chenar-a* (- ox 100.0) (+ oy 1150.0) (+ ox lt 100.0)
                 (- yb (cond ((/= (gb:g 'tip e) "G") 1210.0) ((> (length tr) 1) gb:*y-jos-2*) (T gb:*y-jos-1*)) 450.0))
  ;; titlul
  (setq xm (+ ox (/ lt 2.0)) titlu (strcat (gb:g 'name e) " " (itoa n) "buc."))
  (gb:text gb:*l-bucati* (list xm (+ oy 1000.0)) 140.0 titlu gb:*st-titlu* "MC" (if (= (gb:g 'tip e) "G") 6 3))
  (gb:text gb:*l-bucati* (list xm (+ oy 830.0)) 110.0 "Scara 1:50" gb:*st-titlu* "MC" (if (= (gb:g 'tip e) "G") 6 3))
  lt
)

;; reazemul (din 'sups) care cuprinde punctul u
(defun gb:reazem-la (e u / r)
  (foreach s (gb:g 'sups e)
    (if (and (null r) (<= (- (cadr s) gb:*tol*) u (+ (caddr s) gb:*tol*))) (setq r s)))
  r
)

;; semnatura geometriei, ca sa se recunoasca elementele identice
(defun gb:semnatura (e / ua)
  (setq ua (gb:g 'ua e))
  (apply 'strcat
         (append (list (gb:g 'name e) "|" (gb:rtos (- (gb:g 'ub e) ua) 0))
                 (mapcar '(lambda (s) (strcat "|" (car s) (gb:rtos (- (cadr s) ua) 0) "-" (gb:rtos (- (caddr s) ua) 0)))
                         (gb:g 'sups e))
                 (mapcar '(lambda (x) (strcat "|h" (gb:rtos (- (car x) ua) 0) "-" (gb:rtos (caddr x) 0)))
                         (gb:g 'tr e))))
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
(defun c:GenerareGrinziBuiandrugi ( / *error* doc ms ss el e r lv top s p ox oy grupe sem g lst k txt ds0 n gata cc)
  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms (vla-get-modelspace doc))
  (defun *error* (msg)
    (if ds0 (gb:stil-cota doc ds0))
    (vla-endundomark doc)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nEroare: " msg)))
    (princ)
  )
  (setq gb:*err* nil gb:*el* nil gb:*nr-sect* 0)
  (princ "\nSelectati planul de cofraj (fereastra peste tot planul): ")
  (if (setq ss (ssget (list (cons 8 "Markers,Grinzi,Centuri,Stalpi,Axe,Cofrag"))))
    (progn
      (gb:citeste ss)
      (gb:verifica-axe)
      ;; elementele (dublurile - doua texte pe acelasi element - o data)
      (foreach mk (reverse gb:*mk*)
        (if (and (setq e (gb:element mk))
                 (not (vl-some '(lambda (o) (and (= (gb:g 'id o) (gb:g 'id e))
                                                (equal (gb:g 'lo o) (gb:g 'lo e) gb:*tol*)
                                                (equal (gb:g 'hi o) (gb:g 'hi e) gb:*tol*)
                                                (equal (gb:g 'va o) (gb:g 'va e) gb:*tol*)))
                               el)))
          (setq el (cons e el))))
      (setq gb:*el* (reverse el) el nil)
      ;; centurile fara nume in care stau buiandrugi
      (foreach e gb:*el*
        (if (and (= (gb:g 'tip e) "B") (null (gb:centura-el e))
                 (setq r (gb:centura-fara-nume e))
                 (not (vl-some '(lambda (o) (and (= (gb:g 'tip o) "C")
                                                 (equal (gb:g 'va o) (gb:g 'va r) gb:*tol*)
                                                 (equal (gb:g 'lo o) (gb:g 'lo r) gb:*tol*)))
                               el)))
          (setq el (cons r el))))
      (setq gb:*el* (append gb:*el* (reverse el)) el nil)
      ;; sectiunile de cofraj, la elementele lor
      (foreach c gb:*cof*
        (if (setq e (gb:proprietar (cadr c)))
          (setq gb:*el* (subst (gb:pune 'secs (append (gb:g 'secs e) (list (gb:date-sectiune (car c) (cadr c)))) e)
                               e gb:*el*))))
      ;; reazeme, etrieri, axe - doar pentru grinzi si buiandrugi
      (foreach e gb:*el*
        (if (/= (gb:g 'tip e) "C")
          (progn
            (setq e (gb:tronsoane (gb:reazeme e)))
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
          (setq s (getstring (strcat "\nArmatura longitudinala a centurilor <" gb:*arm-c* ">: ")))
          (if (and (/= s "") (gb:n-diam s)) (setq gb:*arm-c* (strcase s)))
          ;; grosimea placii cea mai des intalnita (pentru grinzile fara grup de cofraj)
          (setq gb:*t-placa* nil lv nil)
          (foreach e gb:*el*
            (if (and (setq r (gb:placa e)) (setq r (assoc (fix (+ (car r) 0.5)) lv)))
              (setq lv (subst (cons (car r) (1+ (cdr r))) r lv))
              (if (setq r (gb:placa e)) (setq lv (cons (cons (fix (+ (car r) 0.5)) 1) lv)))))
          (if lv (setq gb:*t-placa* (float (car (car (gb:sort lv '(lambda (a b) (> (cdr a) (cdr b)))))))))
          (foreach e el (gb:verifica-cofraj e top))
          ;; si centurile cu nume care au sectiuni de cofraj: inaltimea din
          ;; nume fata de grup (centurile fara nume au inaltimea presupusa)
          (foreach e gb:*el*
            (if (and (= (gb:g 'tip e) "C") (/= (gb:g 'id e) "C?") (gb:g 'secs e))
              (gb:verifica-cofraj
                (gb:pune 'tr (list (list (gb:g 'lo e) (gb:g 'hi e) (gb:g 'h e))) e) top)))
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
                ;; loc si pentru cotele de nivel de la capatul stang (sectiune variabila)
                (if (> (length (gb:g 'tr (cadr g))) 1) (setq ox (+ ox 1100.0)))
                (setq ox (+ ox (gb:deseneaza doc ms (cadr g) (caddr g) top ox oy) gb:*spatiu*) n (1+ n)))
              ;; la urma: detaliile centurilor (cate unul pe tip) si barele lor drepte
              (setq lv nil)
              (foreach c (gb:sort (vl-remove-if-not '(lambda (o) (= (gb:g 'tip o) "C")) gb:*el*)
                                  '(lambda (a b) (< (gb:g 'num a) (gb:g 'num b))))
                (if (not (assoc (list (gb:g 'b c) (gb:g 'h c)) lv))
                  (setq lv (append lv (list (cons (list (gb:g 'b c) (gb:g 'h c)) c))))))
              (if lv
                (progn
                  (setq r ox gb:*y-det* oy cc (gb:centuri-calcul (gb:n-diam gb:*arm-c*)))
                  (foreach c lv
                    (setq k (cdr (assoc (strcat "C" (gb:rtos (gb:g 'b (cdr c)) 0) "x" (gb:rtos (gb:g 'h (cdr c)) 0)) (car cc))))
                    (setq ox (+ ox (gb:detaliu-centura doc ms (cdr c) ox oy top (gb:n-diam gb:*arm-c*)
                                                       (if (and k (> k 0)) (strcat (itoa k) " buc.") "xxx buc."))
                                500.0)))
                  ;; barele drepte sub detalii, aliniate cu primul, in chenarul
                  ;; lor pentru armatura (renumerotarea le cauta acolo)
                  (gb:bare-centura doc ms (+ r 1300.0 -232.1) (- gb:*y-det* 417.5) (gb:n-diam gb:*arm-c*) "xxx buc.")))
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

;; =========================================================================
;; SECTIUNI (1:20) - desen comun pentru detaliile centurilor (la generare)
;; si pentru comanda SectiuniGrinzi. Totul e desenat de 2.5 ori mai mare
;; decat desfasuratele (1:20 fata de 1:50), ca in desenele facute manual.
;; =========================================================================
(setq gb:*sc*        2.5)      ; 1:20 fata de 1:50
(setq gb:*s-acop*    62.5)     ; acoperirea (25 mm) la scara sectiunii
(setq gb:*s-bara*    35.0)     ; distanta etrier - marginea barei, la scara sectiunii
(setq gb:*r-bara*    25.0)     ; raza cercului unei bare in sectiune (diametru 50), aceeasi la orice diametru
(setq gb:*s-placa*   242.9)    ; cat iese placa in afara inimii, in sectiune
(setq gb:*r-colt*    59.8)     ; raza colturilor etrierului desfasurat
(setq gb:*cioc-e*    250.0)    ; ciocul etrierului (10 cm) la scara sectiunii
(setq gb:*ds-20*     "Centimetrii sc 1la20")
(setq gb:*ds-etr*    "etrier 20 marit")
(setq gb:*l-chenar-s* "Chenar pentru sectiuni etrieri")
(setq gb:*l-chenar-a* "Chenar pentru armatura")
(setq gb:*l-chenar-e* "Chenar etrieri")
(setq gb:*l-ocg*     "Otel centuri global")
(setq gb:*l-buc-c*   "Bucati etrieri centuri")
(setq gb:*app*       "GBGRINDA")   ; date ascunse pe conturul desfasuratei
(setq gb:*app-m*     "GBMARCA")    ; legatura indicator / definitie, pentru renumerotare
(setq gb:*arm-c*     "4%%C12")     ; armatura longitudinala a centurilor (se intreaba)

;; "4%%C12" -> (4 12); nil daca nu se poate citi
(defun gb:n-diam (s / p n d)
  (setq s (strcase (vl-string-trim " " s)))
  (if (setq p (vl-string-search "%%C" s))
    (progn
      (setq n (atoi (substr s 1 p)) d (atoi (substr s (+ p 4))))
      (if (and (> n 0) (> d 0)) (list n d))))
)

;; placa din sectiunea de cofraj a elementului: (grosime-mm stanga dreapta),
;; stanga = partea cu v mai mic; nil daca sectiunea nu are aripi
(defun gb:placa (e / sec dr q fl us u1 u2 top t1 st dr2)
  (if (setq sec (car (gb:g 'secs e)))
    (progn
      (setq dr (gb:g 'dir e)
            q (mapcar '(lambda (p) (gb:uv dr (car p) (cadr p))) (nth 4 sec))
            us (mapcar 'car q))
      (foreach p q
        (cond
          ((< (cadr p) (- (gb:g 'va e) gb:*tol*)) (setq st T fl (cons (car p) fl)))
          ((> (cadr p) (+ (gb:g 'vb e) gb:*tol*)) (setq dr2 T fl (cons (car p) fl)))))
      (if fl
        (progn
          (setq u1 (apply 'min fl) u2 (apply 'max fl)
                top (if (equal u1 (apply 'min us) gb:*tol*) u1 u2)
                t1 (abs (- u2 u1)))
          (if (> t1 gb:*tol*) (list t1 st dr2))))))
)

;; conturul sectiunii (layer 0): inima b x h, cu placa (aripi rupte) pe
;; partile cerute; x0 = fata stanga a inimii, y0 = fata de sus.
;; Intoarce (x-stanga x-dreapta) ale desenului.
(defun gb:s-contur (x0 y0 W H tp sl sr / pts xe z1 z2)
  (setq pts (list (list x0 (- y0 H))))
  (if (and tp sl)
    (setq xe (- x0 gb:*s-placa*) z1 (+ (- y0 tp) (* 0.358 tp)) z2 (+ (- y0 tp) (* 0.565 tp))
          pts (append pts (list (list x0 (- y0 tp)) (list xe (- y0 tp)) (list xe z1) (list (- xe 61.0) z1)
                                (list (+ xe 61.0) z2) (list xe z2) (list xe y0))))
    (setq pts (append pts (list (list x0 y0)))))
  (if (and tp sr)
    (setq xe (+ x0 W gb:*s-placa*) z1 (- y0 (* 0.358 tp)) z2 (- y0 (* 0.565 tp))
          pts (append pts (list (list xe y0) (list xe z1) (list (+ xe 61.0) z1) (list (- xe 61.0) z2)
                                (list xe z2) (list xe (- y0 tp)) (list (+ x0 W) (- y0 tp)))))
    (setq pts (append pts (list (list (+ x0 W) y0)))))
  (setq pts (append pts (list (list (+ x0 W) (- y0 H)))))
  (gb:poli gb:*l-elem* pts)
  (list (if (and tp sl) (- x0 gb:*s-placa* 61.0) x0) (if (and tp sr) (+ x0 W gb:*s-placa* 61.0) (+ x0 W)))
)

;; etrierul in sectiune (FIER), de la fata de sus pana la hs; cu ciocurile
;; la 45 de grade in coltul din dreapta sus, daca e cazul
(defun gb:s-etrier (x0 y0 W hs ciocuri / c xr yt)
  (setq c gb:*s-acop* xr (- (+ x0 W) c) yt (- y0 c))
  (gb:dreptunghi gb:*l-fier* (+ x0 c) yt xr (+ (- y0 hs) c))
  (if ciocuri
    (progn
      (gb:linie gb:*l-fier* (list (- xr 56.3) yt) (list (- xr 122.7) (- yt 66.4)))
      (gb:linie gb:*l-fier* (list xr (- yt 56.2)) (list (- xr 66.4) (- yt 122.6)))))
)

;; n bare de diametru d (mm), la cota y, intre fetele etrierului; intoarce
;; lista x-urilor
(defun gb:s-bare (x0 W y n d / r xa xb k xs pl)
  (setq r gb:*r-bara*
        xa (+ x0 gb:*s-acop* gb:*s-bara* r) xb (- (+ x0 W) gb:*s-acop* gb:*s-bara* r) k 0)
  (repeat n
    (setq xs (cons (if (> n 1) (+ xa (* k (/ (- xb xa) (1- n)))) (/ (+ xa xb) 2.0)) xs) k (1+ k)))
  (foreach x xs
    (setq pl (gb:o (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-fier*) (list 10 x y 0.0) (cons 40 r)))))
    (gb:hasura (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))) pl "SOLID" 1.0 gb:*l-fier*))
  (reverse xs)
)

;; eticheta barelor: linii verticale de la bare pana la yl, una orizontala
;; spre stanga pana la xl, textul deasupra ei (centrat la xt sau, cu stanga
;; = T, aliniat la stanga de la xt)
(defun gb:s-eticheta (xs ybare yl xl xt txt lay stanga)
  (foreach x xs (gb:linie gb:*l-elem* (list x ybare) (list x yl)))
  (gb:linie gb:*l-elem* (list (apply 'max xs) yl) (list xl yl))
  (gb:text lay (list xt (+ yl (if stanga 63.4 87.4))) 125.0 txt gb:*st-text* (if stanga "L" "MC") nil)
)

;; indicatorul de marca (cerc + "y"), cu linie spre etrier; tag = legatura
;; pentru renumerotare (ex "C300x250" = etrierul centurii 30x25), sau nil
(defun gb:s-indicator (doc xc y xs r tag / c m l)
  (setq c (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-elem*) (list 10 xc y 0.0) (cons 40 r)))
        m (gb:text-marca (list xc y) "MC" tag)
        l (gb:linie gb:*l-elem* (list (+ xc r) y) (list xs y)))
  (gb:grup doc (mapcar 'gb:o (list c m l)))
)

;; textul de marca "y" (Otel marca, h150), cu legatura ascunsa tag
(defun gb:text-marca (pt just tag / e)
  (setq e (gb:text gb:*l-marca* pt 150.0 "y" gb:*st-text* just nil))
  (if tag (gb:pune-tag e tag))
  e
)
(defun gb:pune-tag (e tag / ed)
  (regapp gb:*app-m*)
  (setq ed (entget e))
  (entmod (append ed (list (list -3 (list gb:*app-m* (cons 1000 tag))))))
)

;; cotele de nivel ale sectiunii (layer 0, stil 1:20), la dreapta lui xr
(defun gb:s-nivel (doc ms xr y0 H top / ax d objs yl yv pl pr tsus tjos fc)
  (setq ax (+ xr 491.4))
  (setq d (gb:cota-stil ms (list xr y0) (list xr (- y0 H)) (list (+ xr 276.5) y0) (/ pi 2.0) gb:*ds-20*))
  (setq objs (list d))
  (foreach yl (list y0 (- y0 H))
    (setq yv (+ yl 68.5)
          pl (gb:o (gb:poli gb:*l-elem* (list (list (- ax 30.6) yv) (list ax yv) (list ax yl))))
          pr (gb:o (gb:poli gb:*l-elem* (list (list ax yv) (list (+ ax 30.6) yv) (list ax yl)))))
    (setq objs (append objs
                       (list (gb:o (gb:linie gb:*l-elem* (list (- ax 73.0) yl) (list (+ ax 73.0) yl)))
                             pl (gb:hasura ms pl "SOLID" 1.0 gb:*l-elem*) pr
                             (gb:o (gb:linie gb:*l-elem* (list (- ax 30.6) yv) (list (+ ax 487.4) yv)))))))
  (setq tsus (gb:o (gb:text gb:*l-elem* (list (+ ax 216.0) (+ y0 175.9)) 125.0 (gb:fmt-cota top) gb:*st-text* "MC" nil))
        tjos (gb:o (gb:text gb:*l-elem* (list (+ ax 216.0) (+ (- y0 H) 175.9)) 125.0
                            (gb:fmt-cota (- top (/ H gb:*sc* 1000.0))) gb:*st-text* "MC" nil)))
  (setq fc (strcat (if (>= (- top (/ H gb:*sc* 1000.0)) 0.0) "+" "")
                   "%<\\AcExpr (%<\\AcObjProp Object(%<\\_ObjId " (gb:id doc tsus) ">%).TextString>%-"
                   "%<\\AcObjProp.16.2 Object(%<\\_ObjId " (gb:id doc d) ">%).Measurement \\f \"%lu6%ct8[0.01]\">%"
                   "*0.01) \\f \"%lu6\">%"))
  (vl-catch-all-apply 'vla-put-textstring (list tjos fc))
  (gb:grup doc (append objs (list tsus tjos)))
  (+ ax 216.0 300.0)
)

;; textele etrierului desfasurat (cerc, marca y, diametru, L= ca FIELD legat
;; de lungimea poliliniei / 2.5); X,Yb = coltul stanga-jos al etrierului
(defun gb:etr-texte (doc pl X Yb diam tag / c m dt lg)
  (setq c (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-elem*) (list 10 (- X 303.3) (- Yb 332.1) 0.0) '(40 . 140.7)))
        m (gb:text-marca (list (- X 300.0) (- Yb 401.2)) "BC" tag)
        dt (gb:text gb:*l-diam* (list (- X 56.8) (- Yb 306.6)) 125.0 diam gb:*st-text* "L" nil)
        lg (gb:text gb:*l-lung* (list (+ X 9.4) (- Yb 522.2)) 125.0
                     (strcat "L=" (gb:rtos (* 0.0004 (vlax-curve-getdistatparam pl (vlax-curve-getendparam pl))) 2) "m")
                     gb:*st-text* "L" nil))
  (vl-catch-all-apply 'vla-put-textstring
    (list (gb:o lg) (strcat "L=%<\\AcObjProp.16.2 Object(%<\\_ObjId " (gb:id doc pl)
                            ">%).Length \\f \"%lu6%ct8[0.0004]\">%m")))
  (list c m dt lg)
)

;; etrier inchis desfasurat (grupul definitiei): X,Y = coltul stanga-sus,
;; Ws x Hs = laturile la scara; colturi rotunjite, ciocuri de 10 cm la 45
;; de grade; cotele ca in desenele manuale. buc = text "xxx buc." (centuri)
(defun gb:etrier-inchis (doc ms X Y Ws Hs diam tag buc / r c pl d1 d2 d3 d4 d5 tx bt)
  (setq r gb:*r-colt* c (/ gb:*cioc-e* (sqrt 2.0)))
  (setq pl (entmakex
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-fier*) '(100 . "AcDbPolyline")
                   '(90 . 12) '(70 . 0)
                   (list 10 (- (+ X Ws) c) (- Y r c)) '(42 . 0.0)
                   (list 10 (+ X Ws) (- Y r)) '(42 . 0.414214)
                   (list 10 (- (+ X Ws) r) Y) '(42 . 0.0)
                   (list 10 (+ X r) Y) '(42 . 0.414214)
                   (list 10 X (- Y r)) '(42 . 0.0)
                   (list 10 X (+ (- Y Hs) r)) '(42 . 0.414214)
                   (list 10 (+ X r) (- Y Hs)) '(42 . 0.0)
                   (list 10 (- (+ X Ws) r) (- Y Hs)) '(42 . 0.414214)
                   (list 10 (+ X Ws) (+ (- Y Hs) r)) '(42 . 0.0)
                   (list 10 (+ X Ws) (- Y r)) '(42 . 0.414214)
                   (list 10 (- (+ X Ws) r) Y) '(42 . 0.0)
                   (list 10 (- (+ X Ws) r c) (- Y c)) '(42 . 0.0))))
  (setq d1 (gb:cota-stil ms (list X (- Y r)) (list (+ X Ws) (- Y r)) (list (+ X Ws) Y) 0.0 gb:*ds-etr*)
        d2 (vla-adddimaligned ms (vlax-3d-point (list (- (+ X Ws) r c) (- Y c) 0.0))
                              (vlax-3d-point (list (- (+ X Ws) r) Y 0.0))
                              (vlax-3d-point (list (- (+ X Ws) r) Y 0.0)))
        d3 (gb:cota-stil ms (list (- (+ X Ws) 6.2) (- Y Hs)) (list (- (+ X Ws) r) Y) (list (+ X Ws 268.1) Y) (/ pi 2.0) gb:*ds-etr*)
        d4 (gb:cota-stil ms (list X (- Y Hs)) (list X Y) (list X Y) (/ pi 2.0) gb:*ds-etr*)
        d5 (gb:cota-stil ms (list X (- Y Hs)) (list (+ X Ws) (- Y Hs)) (list (+ X Ws) (- Y Hs)) 0.0 gb:*ds-etr*))
  (vla-put-layer d1 gb:*l-elem*) (vla-put-layer d2 gb:*l-elem*)
  (if (tblsearch "DIMSTYLE" gb:*ds-etr*) (vl-catch-all-apply 'vla-put-stylename (list d2 gb:*ds-etr*)))
  (setq tx (gb:etr-texte doc (gb:o pl) X (- Y Hs) diam tag))
  (if buc (setq bt (list (gb:text gb:*l-buc-c* (list (+ X 380.9) (- Y Hs 708.4)) 125.0 buc gb:*st-axe* "MC" nil))))
  (gb:grup doc (append (list (gb:o pl) d1 d2 d3 d4 d5) (mapcar 'gb:o (append tx bt))))
)

;; etrier deschis (buiandrugi): trei laturi, ciocuri intoarse la 180 de
;; grade; ciocurile adauga impreuna 20 cm. X,Yb = coltul stanga-jos.
(defun gb:etrier-u (doc ms X Yb Ws Hs diam tag / ra hk yt pl d1 d2 d3 tx)
  (setq ra 61.5 hk (- (+ gb:*cioc-e* ra) (* pi ra)) yt (- (+ Yb Hs) ra))
  (setq pl (entmakex
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-fier*) '(100 . "AcDbPolyline")
                   '(90 . 8) '(70 . 0)
                   (list 10 (+ X ra ra) (- yt hk)) '(42 . 0.0)
                   (list 10 (+ X ra ra) yt) '(42 . 1.0)
                   (list 10 X yt) '(42 . 0.0)
                   (list 10 X Yb) '(42 . 0.0)
                   (list 10 (+ X Ws) Yb) '(42 . 0.0)
                   (list 10 (+ X Ws) yt) '(42 . 1.0)
                   (list 10 (- (+ X Ws) ra ra) yt) '(42 . 0.0)
                   (list 10 (- (+ X Ws) ra ra) (- yt hk)) '(42 . 0.0))))
  (setq d1 (gb:cota-stil ms (list (+ X ra) (+ Yb Hs)) (list X Yb) (list X Yb) (/ pi 2.0) gb:*ds-etr*)
        d2 (gb:cota-stil ms (list (- (+ X Ws) ra) (+ Yb Hs)) (list (+ X Ws) Yb) (list (+ X Ws) Yb) (/ pi 2.0) gb:*ds-etr*)
        d3 (gb:cota-stil ms (list X Yb) (list (+ X Ws) Yb) (list (+ X Ws) Yb) 0.0 gb:*ds-etr*))
  (setq tx (gb:etr-texte doc (gb:o pl) X Yb diam tag))
  (gb:grup doc (append (list (gb:o pl) d1 d2 d3) (mapcar 'gb:o tx)))
)

;; chenarul unei sectiuni (sau al unui grup de sectiuni)
(defun gb:s-chenar (x1 y1 x2 y2)
  (gb:dreptunghi gb:*l-chenar-s* x1 y1 x2 y2)
)

;; -------------------------------------------------------------------------
;; o sectiune completa (fara etrierul desfasurat): contur, etrier(i),
;; bare, etichete, cota de latime, indicator(i). x0,y0 = inima stanga-sus.
;; s = lista de proprietati:
;;   'b 'h (mm), 'placa (t st dr) sau nil, 'sus (n d) 'jos (n d),
;;   'tip "G"/"B"/"C", 'hc 'bc (centura, la buiandrugi), 'cent (n d) bare
;;   centura la buiandrugi, 'tag-c tag-ul etrierului centurii,
;;   'tag-e tag-ul etrierului propriu, 'tag-b tag-ul barelor (centuri)
;; Intoarce (xstanga xdreapta ybaza) ale desenului.
;; -------------------------------------------------------------------------
(defun gb:sectiune (doc ms x0 y0 s / W H pl ext xl xr ys yb sus jos tp sl sr hc yc xsus xjos cent)
  (setq W (* gb:*sc* (gb:g 'b s)) H (* gb:*sc* (gb:g 'h s)) pl (gb:g 'placa s)
        tp (if pl (* gb:*sc* (car pl))) sl (if pl (cadr pl)) sr (if pl (caddr pl)))
  (setq ext (gb:s-contur x0 y0 W H tp sl sr) xl (car ext) xr (cadr ext))
  (setq sus (gb:g 'sus s) jos (gb:g 'jos s))
  (cond
    ;; buiandrug: etrierul centurii sus, al buiandrugului pe toata inaltimea
    ((= (gb:g 'tip s) "B")
     (setq hc (* gb:*sc* (gb:g 'hc s)) cent (gb:g 'cent s))
     (gb:s-etrier x0 y0 W hc T)
     (gb:s-etrier x0 y0 W H nil)
     (setq yc (+ (- y0 hc) gb:*s-acop* gb:*s-bara*))
     (if cent
       (progn
         (setq xsus (gb:s-bare x0 W (- y0 gb:*s-acop* gb:*s-bara* gb:*r-bara*) (/ (car cent) 2) (cadr cent)))
         (gb:s-bare x0 W (+ yc gb:*r-bara*) (- (car cent) (/ (car cent) 2)) (cadr cent))
         (gb:s-eticheta (append xsus (list (- (+ x0 W) gb:*s-acop* gb:*s-bara* gb:*r-bara*)))
                        (+ yc gb:*r-bara*) (+ y0 279.0) (- x0 785.4) (- x0 730.4)
                        (strcat (itoa (car cent)) "%%C" (itoa (cadr cent)) " din centura") gb:*l-elem* T)))
     (if jos
       (progn
         (setq xjos (gb:s-bare x0 W (+ (- y0 H) gb:*s-acop* gb:*s-bara* gb:*r-bara*) (car jos) (cadr jos)))
         (gb:s-eticheta xjos (+ (- y0 H) gb:*s-acop* gb:*s-bara* gb:*r-bara*) (- y0 H 544.1)
                        (- x0 513.9) (- x0 239.4) (strcat (itoa (car jos)) "%%C" (itoa (cadr jos))) gb:*l-diam* nil)))
     ;; marca de sus: etrierul centurii; cea de jos: etrierul buiandrugului
     (gb:s-indicator doc (- (+ x0 gb:*s-acop*) 612.7) (+ (- y0 hc) gb:*s-acop* 93.5)
                     (+ x0 gb:*s-acop*) 156.3 (gb:g 'tag-c s))
     (gb:s-indicator doc (- (+ x0 gb:*s-acop*) 423.4) (+ (/ (+ (- y0 hc) (- y0 H)) 2.0) gb:*s-acop*)
                     (+ x0 gb:*s-acop*) 149.3 (gb:g 'tag-e s)))
    (T
     (gb:s-etrier x0 y0 W H T)
     (if sus
       (progn
         (setq ys (- y0 gb:*s-acop* gb:*s-bara* gb:*r-bara*))
         (setq xsus (gb:s-bare x0 W ys (car sus) (cadr sus)))
         (gb:s-eticheta xsus ys (+ y0 221.6) (- x0 497.8) (- x0 245.4)
                        (strcat (itoa (+ (car sus) (if (= (gb:g 'tip s) "C") (car jos) 0))) "%%C" (itoa (cadr sus)))
                        gb:*l-elem* nil)))
     (if jos
       (progn
         (setq yb (+ (- y0 H) gb:*s-acop* gb:*s-bara* gb:*r-bara*))
         (setq xjos (gb:s-bare x0 W yb (car jos) (cadr jos)))
         (if (/= (gb:g 'tip s) "C")
           (gb:s-eticheta xjos yb (- y0 H 544.1) (- x0 513.9) (- x0 239.4)
                          (strcat (itoa (car jos)) "%%C" (itoa (cadr jos))) gb:*l-diam* nil)
           ;; la centuri, eticheta de sus le cuprinde pe toate
           (foreach x xjos (gb:linie gb:*l-elem* (list x yb) (list x ys))))))
     (if (= (gb:g 'tip s) "C")
       (gb:s-indicator doc (- x0 497.8 149.3) (+ y0 221.6) (- x0 497.8) 149.3 (gb:g 'tag-b s)))
     (gb:s-indicator doc (- (+ x0 gb:*s-acop*) 450.6) (+ (- y0 H) gb:*s-acop* 108.9)
                     (+ x0 gb:*s-acop*) 149.3 (gb:g 'tag-e s))))
  ;; cota de latime, sub sectiune
  (gb:cota-stil ms (list x0 (- y0 H)) (list (+ x0 W) (- y0 H)) (list (+ x0 W) (- y0 H 307.6)) 0.0 gb:*ds-20*)
  (list (min xl (- x0 1015.0)) xr (- y0 H))
)

;; -------------------------------------------------------------------------
;; DETALIUL UNEI CENTURI (la generare): titlu, sectiune, etrier desfasurat
;; cu "xxx buc."; intoarce latimea ocupata
;; -------------------------------------------------------------------------
(defun gb:detaliu-centura (doc ms c ox oy top arm buc / b h pl x0 r xr Ws Hs tag)
  (setq b (gb:g 'b c) h (gb:g 'h c) pl (gb:placa c)
        x0 (+ ox 1300.0) tag (strcat "C" (gb:rtos b 0) "x" (gb:rtos h 0)))
  (gb:text gb:*l-elem* (list (+ x0 (* 0.5 gb:*sc* b)) (+ oy 918.8)) 225.0
           (strcat (gb:g 'id c) " " (gb:cm b) "x" (gb:cm h)) gb:*st-axe* "MC" nil)
  (gb:text gb:*l-elem* (list (+ x0 (* 0.5 gb:*sc* b)) (+ oy 618.4)) 125.0 "Sc 1:20" gb:*st-text* "MC" nil)
  (setq r (gb:sectiune doc ms x0 oy
                       (list (cons 'tip "C") (cons 'b b) (cons 'h h) (cons 'placa pl)
                             (cons 'sus (list (/ (car arm) 2) (cadr arm)))
                             (cons 'jos (list (- (car arm) (/ (car arm) 2)) (cadr arm)))
                             (cons 'tag-e tag) (cons 'tag-b (strcat "CB" (itoa (car arm)) "x" (itoa (cadr arm)))))))
  (setq xr (gb:s-nivel doc ms (cadr r) oy (* gb:*sc* h) top))
  (setq Ws (* gb:*sc* (- b 50.0)) Hs (* gb:*sc* (- h 50.0)))
  (gb:etrier-inchis doc ms x0 (- (caddr r) 888.0) Ws Hs (strcat "etr " gb:*diam* "/15") tag buc)
  ;; cel mai de jos punct al detaliilor (sub "xxx buc."), pentru barele drepte
  (setq gb:*y-det* (min (cond (gb:*y-det*) (0.0)) (- (caddr r) 888.0 Hs 900.0)))
  (- xr ox -300.0)
)

;; grupul barelor drepte ale centurilor (4%%C12, L=12.00m, "xxx buc.")
(defun gb:bare-centura (doc ms bx by arm buc / l1 l2 s1 s2 c m dt lg bt)
  (setq l1 (gb:linie gb:*l-fier* (list (+ bx 24.4) by) (list (+ bx 1324.3) by))
        l2 (gb:linie gb:*l-fier* (list (+ bx 1409.9) by) (list (+ bx 2458.8) by)))
  (setq s1 (entmakex (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-elem*) '(100 . "AcDbPolyline")
                           '(90 . 3) '(70 . 0)
                           (list 10 (+ bx 1286.6) (- by 80.8)) '(42 . 0.793)
                           (list 10 (+ bx 1324.3) by) '(42 . -0.793)
                           (list 10 (+ bx 1362.0) (+ by 80.8)) '(42 . 0.0)))
        s2 (entmakex (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 gb:*l-elem*) '(100 . "AcDbPolyline")
                           '(90 . 3) '(70 . 0)
                           (list 10 (+ bx 1372.2) (- by 80.8)) '(42 . 0.793)
                           (list 10 (+ bx 1409.9) by) '(42 . -0.793)
                           (list 10 (+ bx 1447.6) (+ by 80.8)) '(42 . 0.0))))
  (setq c (entmakex (list '(0 . "CIRCLE") (cons 8 gb:*l-elem*) (list 10 (+ bx 444.5) (+ by 213.8) 0.0) '(40 . 154.2)))
        m (gb:text-marca (list (+ bx 444.5) (+ by 139.0)) "BC" (strcat "CB" (itoa (car arm)) "x" (itoa (cadr arm))))
        dt (gb:text gb:*l-diam* (list (+ bx 895.6) (+ by 122.3)) 125.0 (strcat (itoa (car arm)) "%%C" (itoa (cadr arm))) gb:*st-text* "M" nil)
        lg (gb:text gb:*l-lung* (list (+ bx 895.6) (- by 175.4)) 125.0 "L=12.00m" gb:*st-text* "M" nil)
        bt (gb:text gb:*l-buc-c* (list (+ bx 1784.5) (- by 175.4)) 125.0 buc gb:*st-axe* "M" nil))
  (gb:grup doc (mapcar 'gb:o (list l1 l2 s1 s2 c m dt lg bt)))
  (gb:dreptunghi gb:*l-chenar-a* (- bx 18.7) (+ by 417.5) (+ bx 2545.1) (- by 393.2))
)

;; =========================================================================
;; DATELE ASCUNSE DE PE CONTURUL DESFASURATEI ("cheie=valoare")
;; =========================================================================
(defun gb:date-scrie (lst)
  (regapp gb:*app*)
  (list -3 (cons gb:*app* (mapcar '(lambda (kv) (cons 1000 (strcat (car kv) "=" (cdr kv)))) lst)))
)
(defun gb:date-citeste (e / x r p)
  (if (setq x (cdr (assoc -3 (entget e (list gb:*app*)))))
    (foreach it (cdr (car x))
      (if (and (= (car it) 1000) (setq p (vl-string-search "=" (cdr it))))
        (setq r (cons (cons (substr (cdr it) 1 p) (substr (cdr it) (+ p 2))) r)))))
  r
)
(defun gb:d (k lst) (cdr (assoc k lst)))

;; =========================================================================
;; COMANDA: SectiuniGrinzi
;; Selectati desfasuratele (cu numerele sectiunilor scrise in locul lui
;; "xx"), apoi punctul de inserare. Pentru fiecare numar se deseneaza
;; sectiunea la 1:20, din datele desfasuratei: dimensiunile si placa (luate
;; de pe cofraj la generare), barele de sus/jos din grupurile de armatura
;; de sub element, pasii etrierilor din textele "etr." ale desfasuratei.
;; Sectiunile aceluiasi element cu acelasi etrier sunt in acelasi chenar,
;; cu un singur etrier desfasurat. La buiandrugi: etrierul centurii sus
;; (marca lui se leaga de detaliul centurii) si etrierul deschis al
;; buiandrugului; armatura centurii se intreaba.
;; =========================================================================
(defun gb:grupuri-ent (e / r)
  (foreach it (entget e)
    (if (and (= (car it) 330) (= (cdr (assoc 0 (entget (cdr it)))) "GROUP")) (setq r (cons (cdr it) r))))
  r
)
(defun gb:membri (g / r)
  (foreach it (entget g) (if (= (car it) 340) (setq r (cons (cdr it) r))))
  r
)

;; o bara FIER din desfasurata (polilinie deschisa sau linie): segmentul
;; orizontal cel mai lung -> (x1 x2 y cioc); cioc = 'sus daca ciocurile
;; coboara (bara de sus), 'jos daca urca (bara de jos), nil la bara dreapta
(defun gb:bara-geom (pts / k a b best L cioc)
  (setq k 0)
  (repeat (1- (length pts))
    (setq a (nth k pts) b (nth (1+ k) pts) k (1+ k))
    (if (and (equal (cadr a) (cadr b) 1.0) (> (abs (- (car b) (car a))) 1.0)
             (or (null best) (> (abs (- (car b) (car a))) L)))
      (setq best (list (min (car a) (car b)) (max (car a) (car b)) (cadr a))
            L (abs (- (car b) (car a))))))
  (if best
    (progn
      (foreach p pts
        (if (> (abs (- (cadr p) (caddr best))) 1.0)
          (setq cioc (if (< (cadr p) (caddr best)) 'sus 'jos))))
      (append best (list cioc))))
)

;; fata de jos a conturului in dreptul lui x (sectiune variabila)
(defun gb:jos-contur (pts x ytop / n k a b r)
  (setq n (length pts) k 0)
  (repeat n
    (setq a (nth k pts) b (nth (rem (1+ k) n) pts) k (1+ k))
    (if (and (equal (cadr a) (cadr b) 1.0) (< (cadr a) (- ytop 1.0))
             (<= (- (min (car a) (car b)) 1.0) x (+ (max (car a) (car b)) 1.0))
             (or (null r) (> (cadr a) r)))
      (setq r (cadr a))))
  r
)

;; datele unei sectiuni care conteaza la armare (pentru comparare): fara
;; numele elementului, placa (poate fi de o parte sau de alta) si cota
(defun gb:s-cheie (s) (vl-remove-if '(lambda (p) (member (car p) '(nume placa top))) s))
;; "2 (B1), 5 (B2)" din ((num s) ...)
(defun gb:lista-sect (l / r)
  (foreach a l
    (setq r (if r (strcat r ", ") "")
          r (strcat r (car a) " (" (gb:g 'nume (cadr a)) ")")))
  r
)

;; "G3 25x25 si G1 30x40" din ((num s) ...)
(defun gb:lista-nume (l / r)
  (foreach a l
    (setq r (if r (strcat r (if (eq a (last l)) " si " ", ")) "") r (strcat r (gb:g 'nume (cadr a)))))
  r
)

(defun c:SectiuniGrinzi ( / *error* doc ms ss i e ed lay tip el bare zone sect x y g n d pts bb data s
                            ytop ybot h r k cadre key c p px py arm cent ds0 b nr lst val txt pas
                            toate grupe msg opreste
                            v cand best ad)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)) ms (vla-get-modelspace doc))
  (defun *error* (msg)
    (if ds0 (gb:stil-cota doc ds0))
    (vla-endundomark doc)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))) (princ (strcat "\nEroare: " msg)))
    (princ))
  (setq gb:*err* nil)
  (princ "\nSelectati desfasuratele (cu numerele sectiunilor scrise in locul lui xx): ")
  (if (setq ss (ssget))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) ed (entget e) tip (cdr (assoc 0 ed)) lay (strcase (cdr (assoc 8 ed))) i (1+ i))
        (cond
          ;; conturul unei desfasurate generate (cu date)
          ((and (= tip "LWPOLYLINE") (= lay "0") (setq data (gb:date-citeste e)))
           (setq pts (car (gb:varfuri ed)))
           (setq el (cons (list e pts (apply 'min (mapcar 'car pts)) (apply 'max (mapcar 'car pts))
                                (apply 'min (mapcar 'cadr pts)) (apply 'max (mapcar 'cadr pts)) data)
                          el)))
          ;; barele: polilinii FIER deschise (cu ciocuri la ambele capete, la
          ;; unul sau drepte) sau linii, din grupuri cu diametru (fara pas)
          ((and (member tip '("LWPOLYLINE" "LINE")) (= lay (strcase gb:*l-fier*))
                (not (cadr (setq v (gb:varfuri ed))))
                (setq pts (gb:bara-geom (car v))))
           (setq nr nil)
           (foreach g (gb:grupuri-ent e)
             (foreach m (gb:membri g)
               (if (and (null nr) (= (strcase (cdr (assoc 8 (entget m)))) (strcase gb:*l-diam*))
                        (= (cdr (assoc 0 (entget m))) "TEXT")
                        (not (vl-string-search "/" (cdr (assoc 1 (entget m))))))
                 (setq nr (gb:n-diam (cdr (assoc 1 (entget m))))))))
           (if nr (setq bare (cons (append pts (list nr)) bare))))
          ;; textele zonelor de etrieri ("etr. %%C8/10")
          ((and (= tip "TEXT") (= lay "0") (wcmatch (strcase (cdr (assoc 1 ed))) "ETR.*"))
           (setq p (cdr (assoc 11 ed)) zone (cons (list (car p) (cadr p) (cdr (assoc 1 ed))) zone)))
          ;; numerele sectiunilor
          ((and (= tip "TEXT") (= lay (strcase gb:*l-sect*)))
           (setq txt (vl-string-trim " " (cdr (assoc 1 ed))))
           (if (and (/= txt "") (not (vl-string-search "-" txt)) (not (wcmatch (strcase txt) "XX*")))
             (progn
               (setq p (if (/= 0 (cond ((cdr (assoc 72 ed))) (0))) (cdr (assoc 11 ed)) (cdr (assoc 10 ed))))
               (setq sect (cons (list txt (+ (car p) 40.0) (cadr p)) sect)))))))
      ;; fiecare numar, la elementul lui (o singura data)
      (foreach sc sect
        (setq x (cadr sc) y (caddr sc) c nil)
        (foreach o el
          (if (and (null c) (<= (nth 2 o) x (nth 3 o)) (<= (- (nth 4 o) 1500.0) y (+ (nth 5 o) 600.0)))
            (setq c o)))
        (cond
          ((null c) (gb:err (list x y) (strcat "Sectiunea " (car sc) ": nu e pe o desfasurata generata (fara date) - regenerati desfasurata")))
          ((not (vl-some '(lambda (q) (and (= (car q) (car sc)) (eq (cadr q) (car c)))) lst))
           (setq lst (cons (list (car sc) (car c) x c) lst)))))
      ;; armatura centurii, pentru buiandrugi
      (if (vl-some '(lambda (q) (= (gb:d "tip" (nth 6 (nth 3 q))) "B")) lst)
        (progn
          (setq s (getstring (strcat "\nArmatura centurii la buiandrugi (sus si jos) <" gb:*arm-c* ">: ")))
          (if (and (/= s "") (gb:n-diam s)) (setq gb:*arm-c* (strcase s)))))
      (setq arm (gb:n-diam gb:*arm-c*))
      ;; datele fiecarei sectiuni, grupate pe element + inaltime
      (foreach q lst
        (setq c (nth 3 q) x (nth 2 q) data (nth 6 c) ytop (nth 5 c)
              ybot (gb:jos-contur (nth 1 c) x ytop) h (- ytop ybot) b (atof (gb:d "b" data))
              s (list (cons 'tip (gb:d "tip" data)) (cons 'b b) (cons 'h h)
                      (cons 'placa (if (/= (gb:d "placa" data) "")
                                     (read (strcat "(" (gb:d "placa" data) ")"))))))
        ;; barele de sub element
        (setq cand nil)
        (foreach br bare
          (if (and (< (caddr br) (nth 4 c)) (> (caddr br) (- (nth 4 c) 4000.0))
                   (<= (- (nth 2 c) 1.0) (car br)) (>= (+ (nth 3 c) 1.0) (cadr br)))
            (setq cand (cons br cand))))
        ;; barele drepte (fara ciocuri) sunt sus sau jos dupa randul cu
        ;; ciocuri cel mai apropiat; fara asa ceva, dupa inaltimea fata de element
        (setq cand
          (mapcar '(lambda (br / o dm)
                     (if (cadddr br)
                       br
                       (progn
                         (foreach o cand
                           (if (and (cadddr o) (or (null dm) (< (abs (- (caddr o) (caddr br))) (car dm))))
                             (setq dm (list (abs (- (caddr o) (caddr br))) (cadddr o)))))
                         (list (car br) (cadr br) (caddr br)
                               (cond (dm (cadr dm)) ((> (caddr br) (- (nth 4 c) 1380.0)) 'sus) ('jos))
                               (nth 4 br)))))
                  cand))
        ;; in dreptul sectiunii: pe fiecare parte, bara care o cuprinde cel mai
        ;; adanc (la o innadire, cea din care sectiunea e mai departe de capat)
        (foreach parte '(sus jos)
          (setq best nil)
          (foreach br cand
            (if (and (eq (cadddr br) parte) (<= (- (car br) 30.0) x (+ (cadr br) 30.0))
                     (or (null best) (> (min (- x (car br)) (- (cadr br) x)) ad)))
              (setq best br ad (min (- x (car br)) (- (cadr br) x)))))
          (if best (setq s (append s (list (cons parte (nth 4 best)))))))
        (if (= (gb:d "tip" data) "B")
          (setq s (append s (list (cons 'hc (atof (gb:d "hc" data))) (cons 'cent arm)
                                  (cons 'tag-c (gb:d "tagc" data))))))
        ;; pasii etrierilor, din textele zonelor elementului
        (setq pas nil)
        (foreach z zone
          (if (and (<= (nth 2 c) (car z) (nth 3 c)) (<= ytop (cadr z) (+ ytop 400.0))
                   (setq p (vl-string-search "/" (caddr z))))
            (if (not (member (substr (caddr z) (+ p 2)) pas)) (setq pas (cons (substr (caddr z) (+ p 2)) pas)))))
        (setq pas (gb:sort (if pas pas '("15")) '(lambda (a b) (< (atoi a) (atoi b)))))
        (setq s (append s (list (cons 'etr (strcat "etr " gb:*diam* "/" (apply 'strcat (cons (car pas) (mapcar '(lambda (v) (strcat "/" v)) (cdr pas))))))
                                (cons 'nume (gb:d "nume" data)) (cons 'top (atof (gb:d "top" data))))))
        (if (not (gb:g 'jos s))
          (gb:err (list x (nth 4 c)) (strcat "Sectiunea " (car q) " (" (gb:d "nume" data) "): nu am gasit barele de jos sub element")))
        (if (and (= (gb:d "tip" data) "G") (not (gb:g 'sus s)))
          (gb:err (list x (nth 4 c)) (strcat "Sectiunea " (car q) " (" (gb:d "nume" data) "): nu am gasit barele de sus sub element")))
        (setq key (list (car c) (fix (+ h 0.5))))
        ;; acelasi numar pe mai multe elemente: sectiunea se deseneaza o data
        (cond
          ((vl-some '(lambda (o) (= (car o) (car q))) toate))
          ((setq g (assoc key cadre))
           (setq cadre (subst (append g (list (cons (car q) s))) g cadre)))
          (T (setq cadre (append cadre (list (list key (cons (car q) s)))))))
        (setq toate (cons (list (car q) s) toate)))
      ;; sectiuni identice cu numere diferite / acelasi numar la sectiuni diferite
      (setq toate (gb:sort toate '(lambda (a b) (< (atoi (car a)) (atoi (car b))))))
      (foreach a toate
        (if (setq g (vl-some '(lambda (o) (if (equal (car o) (gb:s-cheie (cadr a)) 0.5) o)) grupe))
          (setq grupe (subst (append g (list a)) g grupe))
          (setq grupe (append grupe (list (list (gb:s-cheie (cadr a)) a))))))
      (foreach g grupe
        (setq nr nil)
        (foreach a (cdr g) (if (not (member (car a) nr)) (setq nr (append nr (list (car a))))))
        (if (cdr nr)
          (setq msg (cons (strcat "Sectiunile " (gb:lista-sect (cdr g))
                                  " au aceeasi forma, dimensiuni, bare si etrieri (placa poate diferi) - pot avea acelasi numar")
                          msg))))
      (foreach a toate
        (if (and (not (vl-some '(lambda (m) (wcmatch m (strcat "Sectiunea " (car a) " *"))) msg))
                 (vl-some '(lambda (o) (and (= (car o) (car a)) (not (equal (gb:s-cheie (cadr o)) (gb:s-cheie (cadr a)) 0.5))))
                          toate))
          (setq msg (cons (strcat "Sectiunea " (car a) " apare pe "
                                  (gb:lista-nume (vl-remove-if-not '(lambda (o) (= (car o) (car a))) toate))
                                  ", dar sectiunile difera - dati-le numere diferite")
                          msg))))
      (if msg
        (progn
          (setq msg (reverse msg))
          (foreach m msg (princ (strcat "\n" m)))
          (alert (strcat "Numerotarea sectiunilor:\n\n" (apply 'strcat (mapcar '(lambda (m) (strcat m "\n\n")) msg))
                         "Puteti corecta numerele pe desfasurate (si rula RenumeroteazaSectiuni), apoi relansati comanda."))
          (initget "Da Nu")
          (if (= (getkword "\nDesenez totusi sectiunile asa? [Da/Nu] <Nu>: ") "Da")
            nil
            (setq cadre nil opreste T))))
      (if (null cadre)
        (if (not opreste) (alert "Nu am gasit nicio sectiune numerotata pe desfasuratele generate."))
        (progn
          ;; cadrele in ordinea primei sectiuni
          (setq cadre (mapcar '(lambda (g) (cons (car g) (gb:sort (cdr g) '(lambda (a b) (< (atoi (car a)) (atoi (car b)))))))
                              cadre))
          (setq cadre (gb:sort cadre '(lambda (a b) (< (atoi (car (cadr a))) (atoi (car (cadr b)))))))
          (if (setq p (getpoint "\nColtul stanga-sus al primului chenar de sectiuni: "))
            (progn
              (vla-startundomark doc)
              (setq ds0 (getvar "DIMSTYLE"))
              (gb:straturi)
              (setq p (trans p 1 0) px (car p) py (cadr p))
              (foreach g cadre
                (setq px (+ (gb:cadru-sectiuni doc ms (cdr g) px py) 500.0)))
              (gb:stil-cota doc ds0)
              (setq ds0 nil)
              (vla-endundomark doc)
              (princ (strcat "\nAm desenat " (itoa (length cadre)) " chenare de sectiuni."))
              (if gb:*err*
                (alert (strcat "Probleme gasite:\n\n"
                               (apply 'strcat (mapcar '(lambda (x) (strcat (cadr x) "\n")) (reverse gb:*err*))))))))))))
  (princ)
)

;; un chenar: sectiunile (num . props) ale aceluiasi element, cu acelasi
;; etrier; intoarce marginea din dreapta
(defun gb:cadru-sectiuni (doc ms lst px py / ty y0 x0 x0p s W r xr xmin ybot xe Ws Hs X Yt yfin p)
  (setq ty (- py 251.6) y0 (- ty 963.3) x0 (+ px 1295.0) x0p x0 ybot y0)
  (foreach q lst
    (setq s (cdr q) W (* gb:*sc* (gb:g 'b s)))
    (gb:text gb:*l-sect* (list (+ x0 (* 0.5 W)) ty) 300.0 (strcat (car q) "-" (car q)) gb:*st-text* "MC" nil)
    (gb:text gb:*l-elem* (list (+ x0 (* 0.5 W) -20.0) (- ty 335.2)) 125.0 "Sc 1:20" gb:*st-text* "MC" nil)
    (setq r (gb:sectiune doc ms x0 y0 s) xr (cadr r) ybot (min ybot (caddr r)))
    ;; cotele de nivel si de inaltime, la fiecare sectiune
    (setq xe (gb:s-nivel doc ms xr y0 (* gb:*sc* (gb:g 'h s)) (gb:g 'top s)))
    (setq x0 (+ xe 1100.0)))
  ;; etrierul desfasurat (definitia), sub prima sectiune
  (setq s (cdr (car lst))
        Ws (* gb:*sc* (- (gb:g 'b s) 50.0)) Hs (* gb:*sc* (- (gb:g 'h s) 50.0))
        X x0p Yt (- ybot 888.0))
  (if (= (gb:g 'tip s) "B")
    (gb:etrier-u doc ms X (- Yt Hs) Ws Hs (gb:g 'etr s) nil)
    (gb:etrier-inchis doc ms X Yt Ws Hs (gb:g 'etr s) nil nil))
  (setq yfin (- Yt Hs 597.0))
  (gb:s-chenar px py (max (+ xe 110.0) (+ X Ws 900.0)) yfin)
  (max (+ xe 110.0) (+ X Ws 900.0))
)

;; =========================================================================
;; COMANDA: RenumeroteazaSectiuni
;; Selectati tot (nu trebuie izolat nimic). Comanda gaseste grupurile de
;; sectiune de pe desfasurate (pe "Sectiuni grinzi": doua linii si doua
;; texte, sus si jos) si le numeroteaza 1, 2, 3 ... de la stanga la dreapta;
;; daca desfasuratele sunt pe mai multe randuri, randurile de sus in jos.
;; Titlurile N-N ale chenarelor de sectiuni din selectie se actualizeaza la
;; fel (fosta 3-3 devine noua ei eticheta), ca sa ramana legate de grinzi.
;; =========================================================================
(defun c:RenumeroteazaSectiuni ( / *error* doc ss i e ed g grp tx ln gr vazut rand y0 nr harta k v nn old)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-endundomark doc)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))) (princ (strcat "\nEroare: " msg)))
    (princ))
  (princ "\nSelectati desfasuratele (tot; se iau doar grupurile de sectiune): ")
  (if (setq ss (ssget (list (cons 8 gb:*l-sect*))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) ed (entget e) i (1+ i))
        (cond
          ;; titlurile N-N ale chenarelor de sectiuni
          ((and (= (cdr (assoc 0 ed)) "TEXT") (vl-string-search "-" (cdr (assoc 1 ed))))
           (setq nn (cons e nn)))
          ;; textele din grupurile de sectiune (cu linie in acelasi grup)
          ((= (cdr (assoc 0 ed)) "TEXT")
           (foreach g (gb:grupuri-ent e)
             (if (not (member g vazut))
               (progn
                 (setq vazut (cons g vazut) tx nil ln nil)
                 (foreach m (gb:membri g)
                   (cond
                     ((/= (strcase (cdr (assoc 8 (entget m)))) (strcase gb:*l-sect*)))
                     ((= (cdr (assoc 0 (entget m))) "TEXT") (setq tx (cons m tx)))
                     ((= (cdr (assoc 0 (entget m))) "LINE") (setq ln (cons m ln)))))
                 (if (and tx ln (not (vl-some '(lambda (t1) (vl-string-search "-" (cdr (assoc 1 (entget t1))))) tx)))
                   (setq grp (cons (list (car (cdr (assoc 10 (entget (car ln)))))
                                         (apply 'max (mapcar '(lambda (l) (max (caddr (assoc 10 (entget l))) (caddr (assoc 11 (entget l))))) ln))
                                         tx)
                                   grp)))))))))
      (if (null grp)
        (alert "Nu am gasit niciun grup de sectiune (doua linii si doua texte pe \"Sectiuni grinzi\").")
        (progn
          ;; randuri: de sus in jos (grupuri la mai putin de 3 m pe verticala =
          ;; acelasi rand), in fiecare rand de la stanga la dreapta
          (setq grp (gb:sort grp '(lambda (a b) (> (cadr a) (cadr b)))) rand nil y0 nil)
          (foreach q grp
            (if (or (null y0) (> (- y0 (cadr q)) 3000.0)) (setq y0 (cadr q) rand (cons nil rand)))
            (setq rand (cons (cons q (car rand)) (cdr rand))))
          (vla-startundomark doc)
          (setq nr 0)
          (foreach r (reverse rand)
            (foreach q (gb:sort r '(lambda (a b) (< (car a) (car b))))
              (setq old (cdr (assoc 1 (entget (car (caddr q))))))
              ;; vechiul numar -> noul numar (si pentru titlurile N-N); sectiunile
              ;; care aveau acelasi numar (ex. buiandrugii identici) il pastreaza comun
              (cond
                ((or (= old "") (wcmatch (strcase old) "XX*")) (setq nr (1+ nr) v (itoa nr)))
                ((setq k (assoc old harta)) (setq v (cdr k)))
                (T (setq nr (1+ nr) v (itoa nr) harta (cons (cons old v) harta))))
              (foreach t1 (caddr q)
                (setq ed (entget t1))
                (entmod (subst (cons 1 v) (assoc 1 ed) ed)))))
          ;; titlurile N-N
          (setq k 0)
          (foreach t1 nn
            (setq ed (entget t1) v (vl-string-trim " " (cdr (assoc 1 ed))))
            (setq old (substr v 1 (vl-string-search "-" v)))
            (if (and (setq g (assoc old harta)) (/= (strcat (cdr g) "-" (cdr g)) v))
              (progn
                (entmod (subst (cons 1 (strcat (cdr g) "-" (cdr g))) (assoc 1 ed) ed))
                (setq k (1+ k)))))
          (vla-endundomark doc)
          (princ (strcat "\nAm numerotat " (itoa nr) " sectiuni (1.." (itoa nr) ")"
                         (if (> k 0) (strcat ", am actualizat " (itoa k) " titluri N-N") "") "."))
          )))
    (princ "\nNimic selectat."))
  (princ)
)

(princ "\nGenerare grinzi si buiandrugi incarcat. Comenzi: GenerareGrinziBuiandrugi, SectiuniGrinzi, RenumeroteazaSectiuni")
(princ)
