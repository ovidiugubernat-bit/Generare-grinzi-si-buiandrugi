;; =========================================================================
;; COFRAJ  -  sectiunile de cofraj de pe un plan de cofraj
;;
;; Pe fiecare linie indicata cu click, se taie toate centurile, grinzile si
;; buiandrugii pe care linia ii intalneste si, chiar pe plan, in dreptul
;; fiecaruia, se deseneaza grupul de cofraj:
;;   - sectiunea betonului (contur + hasura plina), cu fata de sus pe linie;
;;     cu placa, sectiunea e in T (sau in L la margine)
;;   - cota de inaltime (impartita in placa + restul, cand e placa)
;;   - cele doua etichete de nivel: partea de sus si partea de jos
;; Fiecare grup e un GROUP AutoCAD (nu bloc), pe layerul "Cofrag".
;; Hasura e asociativa (la un STRETCH al conturului se umple din nou), iar
;; cota de jos e field: cota de sus minus cota (cotele) de inaltime - la un
;; STRETCH si REGEN se recalculeaza singura.

;;
;; La pornire se cer: cota partii de sus [m], inaltimea centurilor [cm] si
;; grosimea placii [cm] (0 = plan fara placa). Apoi liniile: intai cele
;; ORIZONTALE (click = linia fetei de sus a sectiunilor; sectiunile cresc in
;; jos), apoi cele VERTICALE (fata de sus e in stanga, sectiunile cresc spre
;; dreapta - textele se citesc de jos in sus).
;;
;; Ce e taiat se recunoaste dupa eticheta din plan (C1 30x25, G1 30x50,
;; B1 30x55 - latime x inaltime, in cm):
;;   C...  centura   - inaltimea ceruta la pornire
;;   G...  grinda    - inaltimea din eticheta (si GF... grinda de fundare,
;;                     GP... grinda in placa)
;;   B...  buiandrug - inaltimea din eticheta
;;   BP... (cota de buiandrug) nu e eticheta de element si nu se ia in seama
;; Latimea se masoara pe desen, nu se ia din eticheta. Eticheta trebuie sa
;; stea intre cele doua linii ale elementului, paralela cu el. Un element fara
;; eticheta: pe layerul Centuri e centura; pe Grinzi se pune cu inaltimea
;; centurilor si se semnaleaza in raport si intr-o fereastra la final.
;; Pe un plan fara placa (ex. fundatii) grosimea placii se da 0.
;;
;; Cu placa: placa iese din fata elementului cu *kf:stub* spre interior.
;; Spre exterior (nimic mai incolo pe linie) sau spre un gol de placa
;; (layerul "Gol placa") nu iese.
;;
;; Asezarea: grupurile de pe aceeasi linie stau toate la acelasi nivel, cu
;; fata de sus pe linie. Cota de inaltime si etichetele de nivel se pun de o
;; parte sau de alta a sectiunii - amandoua pe aceeasi parte sau cate una pe
;; fiecare - astfel incat sa incapa in golurile dintre elemente, sa nu se
;; calce intre ele, sa nu iasa spre exterior (acolo sunt cotele) si sa nu
;; calce peste texte, cote sau grupurile puse deja.
;; =========================================================================

(vl-load-com)

;; ---- parametri ----------------------------------------------------------
(setq *kf:layEl*   '("Centuri" "Grinzi")  ;; de pe ele se citesc elementele
      *kf:layCent* "Centuri"              ;; fara eticheta = centura
      *kf:layGol*  "Gol placa"
      *kf:lay*     "Cofrag"               ;; layerul grupurilor
      *kf:stilDim* "Centimetri 50"
      *kf:stilTxt* "cezar"
      *kf:htxt*    110.0   ;; inaltimea textului la etichetele de nivel
      *kf:wmin*    80.0    ;; cel mai ingust element asteptat [mm]
      *kf:wmax*    600.0   ;; cel mai lat element asteptat [mm]
      *kf:stub*    185.0   ;; cat iese placa din fata elementului [mm]
      *kf:dimIn*   250.0   ;; linia cotei, cand textul ei cade spre sectiune
      *kf:dimOut*  100.0   ;; linia cotei, cand textul ei cade in afara
      *kf:ldim*    300.0   ;; cat ocupa cota de inaltime, de la sectiune
      *kf:gap*     150.0   ;; de la sectiune la etichete (fara cota intre ele)
      *kf:gapdm*   60.0    ;; intre cota de inaltime si etichete
      *kf:marg*    100.0   ;; loc liber minim intre doua grupuri vecine
      *kf:tol*     1.0     ;; toleranta geometrica [mm]
)

;; valorile date data trecuta raman propuse
(if (null *kf:niv*) (setq *kf:niv* 2.75))
(if (null *kf:hp*)  (setq *kf:hp* 14.0))

;; ---- helperi ------------------------------------------------------------

(defun kf:eq (a b) (< (abs (- a b)) *kf:tol*))

(defun kf:doc ( ) (vla-get-ActiveDocument (vlax-get-acad-object)))

(defun kf:space ( )
  (if (= 1 (getvar "CVPORT")) (vla-get-PaperSpace (kf:doc)) (vla-get-ModelSpace (kf:doc)))
)

(defun kf:onlay (e lays)
  (member (strcase (cdr (assoc 8 e))) (mapcar 'strcase lays))
)

(defun kf:get (k el) (cdr (assoc k el)))

;; cota de nivel in metri -> "+2.75", "-0.10", "%%p0.00"
;; (nu cu rtos, care tine cont de DIMZIN si poate taia zerourile)
(defun kf:fmtniv (v / n a fr)
  (setq n (fix (if (minusp v) (- (* v 100.0) 0.5) (+ (* v 100.0) 0.5))))
  (if (= n 0)
    "%%p0.00"
    (progn
      (setq a (abs n) fr (rem a 100))
      (strcat (if (> n 0) "+" "-") (itoa (/ a 100)) "."
              (if (< fr 10) "0" "") (itoa fr))
    )
  )
)

;; ---- stilurile desenului -------------------------------------------------
;; Daca un desen nu are stilurile de care e nevoie (de exemplu dupa un PURGE),
;; se creeaza, cu setarile din desenele obisnuite - altfel textele si cotele
;; s-ar pune cu stilul curent si ar iesi gresite. Ce exista nu se atinge.

(defun kf:fa-stil-text (nume font)
  (if (not (tblsearch "STYLE" nume))
    (progn
      (entmake (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbTextStyleTableRecord")
                     (cons 2 nume) '(70 . 0) '(40 . 0.0) '(41 . 1.0) '(50 . 0.0) '(71 . 0) '(42 . 2.5)
                     (cons 3 font) '(4 . "")))
      (princ (strcat "\n(Am creat stilul de text lipsa \"" nume "\".)"))))
)

;; baza: stilul de la care se porneste (daca exista); vars: ((variabila . valoare) ...)
(defun kf:fa-stil-cota (nume baza vars / cur och)
  (if (not (tblsearch "DIMSTYLE" nume))
    (progn
      (setq cur (getvar "DIMSTYLE") och (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (if (and baza (tblsearch "DIMSTYLE" baza)) (command "_.-DIMSTYLE" "_Restore" baza))
      (foreach v vars (vl-catch-all-apply 'setvar (list (car v) (cdr v))))
      (command "_.-DIMSTYLE" "_Save" nume)
      (if (tblsearch "DIMSTYLE" cur) (command "_.-DIMSTYLE" "_Restore" cur))
      (setvar "CMDECHO" och)
      (princ (strcat "\n(Am creat stilul de cotare lipsa \"" nume "\".)"))))
)

;; "Centimetri 50" si "Centimetri 50 cu virgula": desen in mm, cote in cm
(defun kf:stiluri-cm50 ( / v)
  (kf:fa-stil-text "WMF-Times New Roman0" "times.ttf")
  (setq v (list '("DIMSCALE" . 1.0) '("DIMLFAC" . 0.1) '("DIMTXT" . 120.0) '("DIMASZ" . 80.0)
                '("DIMGAP" . 50.0) '("DIMEXO" . 1.0) '("DIMEXE" . 1.0) '("DIMDLI" . 10.0)
                '("DIMTAD" . 1) '("DIMTIH" . 0) '("DIMTOH" . 0) '("DIMTIX" . 1) '("DIMTOFL" . 1)
                '("DIMSE1" . 1) '("DIMSE2" . 1) '("DIMSD1" . 0) '("DIMSD2" . 0)
                '("DIMZIN" . 8) '("DIMDEC" . 0) '("DIMCEN" . 40.0)
                '("DIMCLRD" . 256) '("DIMCLRE" . 256) '("DIMCLRT" . 256)
                '("DIMBLK" . "_ArchTick") '("DIMTXSTY" . "WMF-Times New Roman0")))
  (kf:fa-stil-cota "Centimetri 50" nil v)
  (kf:fa-stil-cota "Centimetri 50 cu virgula" "Centimetri 50"
               (append v (list '("DIMZIN" . 12) '("DIMDEC" . 1) '("DIMCEN" . 0.0))))
)

;; ---- citirea elementelor ------------------------------------------------
;; segmente drepte (ent p1 p2) de pe layerele elementelor; arcele nu intra -
;; un element curb nu se taie

(defun kf:lwpts (e / lst)
  (foreach x e (if (= 10 (car x)) (setq lst (cons (cdr x) lst))))
  (reverse lst)
)

(defun kf:segs (ss / i ent e tip lst pts closed)
  (setq lst nil i 0)
  (repeat (sslength ss)
    (setq ent (ssname ss i) i (1+ i)
          e   (entget ent)
          tip (cdr (assoc 0 e)))
    (if (kf:onlay e *kf:layEl*)
      (cond
        ((= tip "LINE")
         (setq lst (cons (list ent (cdr (assoc 10 e)) (cdr (assoc 11 e))) lst)))
        ((= tip "LWPOLYLINE")
         (setq pts    (kf:lwpts e)
               closed (= 1 (logand 1 (cond ((cdr (assoc 70 e))) (0)))))
         (if (and closed (> (length pts) 2)) (setq pts (append pts (list (car pts)))))
         (while (cdr pts)
           (setq lst (cons (list ent (car pts) (cadr pts)) lst)
                 pts (cdr pts))
         )
        )
      )
    )
  )
  lst
)

;; contururile inchise (fara bulge): ((puncte) xmin ymin xmax ymax)
(defun kf:poly (e / pts)
  (setq pts (kf:lwpts e))
  (list pts
        (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts))
        (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts)))
)

;; buiandrugii si grinzile desenate inchis (dreptunghiuri inguste) si golurile
;; de placa -> (mici goluri)
(defun kf:polys (ss / i e mici goluri pl)
  (setq i 0 mici nil goluri nil)
  (repeat (sslength ss)
    (setq e (entget (ssname ss i)) i (1+ i))
    (if (and (= "LWPOLYLINE" (cdr (assoc 0 e)))
             (= 1 (logand 1 (cond ((cdr (assoc 70 e))) (0))))
             (> (length (kf:lwpts e)) 2))
      (cond
        ((kf:onlay e (list *kf:layGol*))
         (setq goluri (cons (kf:poly e) goluri)))
        ((kf:onlay e *kf:layEl*)
         (setq pl (kf:poly e))
         (if (<= (min (- (nth 3 pl) (nth 1 pl)) (- (nth 4 pl) (nth 2 pl)))
                 (+ *kf:wmax* *kf:tol*))
           (setq mici (cons pl mici))))
      )
    )
  )
  (list mici goluri)
)

;; punct in contur (raza spre dreapta)
(defun kf:inpoly (p pl / pts in a b x y)
  (setq x (car p) y (cadr p) in nil)
  (if (and (>= x (nth 1 pl)) (<= x (nth 3 pl)) (>= y (nth 2 pl)) (<= y (nth 4 pl)))
    (progn
      (setq pts (car pl) a (last pts))
      (foreach b pts
        (if (and (/= (> (cadr a) y) (> (cadr b) y))
                 (< x (+ (car a) (/ (* (- y (cadr a)) (- (car b) (car a)))
                                    (- (cadr b) (cadr a))))))
          (setq in (not in)))
        (setq a b)
      )
    )
  )
  in
)

(defun kf:inany (p pls / r)
  (foreach pl pls (if (kf:inpoly p pl) (setq r pl)))
  r
)

;; ---- etichete si obstacole ----------------------------------------------

;; e o eticheta de grinda intoarsa? ("G2 30x45 (intoarsa)")
(defun kf:intoarsa (str) (and str (vl-string-search "INTOARS" (strcase str))))

;; "C1 30x25" -> ("C" 30.0 25.0 "C1 30x25"); altceva -> nil
(defun kf:parse (s / u i sp nm dm x w h lit c)
  (setq u (vl-string-trim " " (strcase s)) i 1 sp nil)
  ;; "G2 30x45 (intoarsa)": cuvantul se scoate (kf:intoarsa il recunoaste)
  (if (setq x (vl-string-search "INTOARS" u))
    (setq u (vl-string-right-trim " (" (substr u 1 x)) x nil))
  (while (<= i (strlen u))
    (if (= " " (substr u i 1)) (setq sp i))
    (setq i (1+ i))
  )
  (if sp
    (progn
      (setq nm (vl-string-trim " " (substr u 1 sp))
            dm (vl-string-trim " " (substr u (1+ sp)))
            x  (vl-string-search "X" dm))
      (if x
        (setq w (distof (substr dm 1 x) 2)
              h (distof (substr dm (+ x 2)) 2)))
      (setq lit "" i 1)
      (while (and (<= i (strlen nm))
                  (setq c (substr nm i 1))
                  (wcmatch c "@"))
        (setq lit (strcat lit c) i (1+ i))
      )
      (if (and w h (> w 0) (> h 0)
               (wcmatch lit "C*,G*,B*")
               (not (wcmatch lit "BP*")))
        (list lit w h (vl-string-trim " " s))
      )
    )
  )
)

(defun kf:bbox (ent / o mn mx r)
  (setq o (vlax-ename->vla-object ent))
  (setq r (vl-catch-all-apply 'vla-GetBoundingBox (list o 'mn 'mx)))
  (if (not (vl-catch-all-error-p r))
    (progn
      (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx))
      (list (car mn) (cadr mn) (car mx) (cadr mx))
    )
  )
)

;; -> (etichete obstacole)
;;   eticheta: (lit latime inaltime text xc yc verticala ename)
;;   obstacol: (xmin ymin xmax ymax) - texte, cote, blocuri
(defun kf:texte (ss / i ent e tip lb bb rot ets obs)
  (setq i 0 ets nil obs nil)
  (repeat (sslength ss)
    (setq ent (ssname ss i) i (1+ i)
          e   (entget ent)
          tip (cdr (assoc 0 e)))
    (if (member tip '("TEXT" "MTEXT" "DIMENSION" "INSERT"))
      (progn
        (setq bb (kf:bbox ent))
        (if bb (setq obs (cons bb obs)))
        (if (and bb (member tip '("TEXT" "MTEXT"))
                 (setq lb (kf:parse (cdr (assoc 1 e)))))
          (progn
            (setq rot (cond ((cdr (assoc 50 e))) (0.0)))
            (setq ets (cons (append lb
                                    (list (/ (+ (car bb) (caddr bb)) 2.0)
                                          (/ (+ (cadr bb) (cadddr bb)) 2.0)
                                          (> (abs (sin rot)) 0.7)
                                          ent))
                            ets))
          )
        )
      )
    )
  )
  (list ets obs)
)

;; ---- taierea cu o dreapta -----------------------------------------------
;; dir "H": dreapta y=c, pozitiile sunt X; dir "V": dreapta x=c, pozitiile Y.
;; Numai segmentele perpendiculare pe dreapta conteaza (fete de element);
;; cele oblice fac taietura "murdara".
;; -> lista sortata de (pozitie curata (segmente perpendiculare))

(defun kf:cross (segs dir c / lst p q a b tt x cl)
  (setq lst nil)
  (foreach s segs
    (setq p (cadr s) q (caddr s))
    (if (= dir "H")
      (setq a (cadr p) b (cadr q))
      (setq a (car p)  b (car q))
    )
    (if (and (> (abs (- a b)) 1e-9)
             (>= c (- (min a b) *kf:tol*))
             (<= c (+ (max a b) *kf:tol*)))
      (progn
        (setq tt (/ (- c a) (- b a)))
        (if (= dir "H")
          (setq x  (+ (car p) (* tt (- (car q) (car p))))
                cl (kf:eq (car p) (car q)))
          (setq x  (+ (cadr p) (* tt (- (cadr q) (cadr p))))
                cl (kf:eq (cadr p) (cadr q)))
        )
        (setq lst (cons (list x cl s) lst))
      )
    )
  )
  ;; sortare + lipirea celor din acelasi loc
  (setq b nil)
  (foreach a (vl-sort lst '(lambda (u v) (< (car u) (car v))))
    (if (and b (kf:eq (car a) (car (car b))))
      (setq b (cons (list (car (car b))
                          (or (cadr (car b)) (cadr a))
                          (if (cadr a) (cons (caddr a) (caddr (car b))) (caddr (car b))))
                    (cdr b)))
      (setq b (cons (list (car a) (cadr a) (if (cadr a) (list (caddr a)))) b))
    )
  )
  (reverse b)
)

;; cel mai scurt segment dintr-o lista
(defun kf:scurt (lst / best)
  (foreach s lst
    (if (or (null best) (< (distance (cadr s) (caddr s)) (distance (cadr best) (caddr best))))
      (setq best s)))
  best
)

;; intinderea segmentului pe directia elementului (perpendicular pe dreapta)
(defun kf:intind (s dir)
  (if (= dir "H")
    (list (min (cadr (cadr s)) (cadr (caddr s))) (max (cadr (cadr s)) (cadr (caddr s))))
    (list (min (car (cadr s)) (car (caddr s))) (max (car (cadr s)) (car (caddr s)))))
)

;; punctul de plan (pozitie pe dreapta) -> WCS
(defun kf:pp (s dir c) (if (= dir "H") (list s c) (list c s)))

;; e golul de la pozitia m "inauntru"? = dreapta perpendiculara prin el
;; intalneste elemente de ambele parti ale liniei
(defun kf:interior (m dir c segs / cr sub peste)
  (setq cr (kf:cross segs (if (= dir "H") "V" "H") m))
  (foreach x cr
    (if (< (car x) (- c *kf:tol*)) (setq sub T))
    (if (> (car x) (+ c *kf:tol*)) (setq peste T))
  )
  (and sub peste)
)

;; eticheta elementului taiat intre pozitiile a si b
(defun kf:eticheta (a b sa sb dir c ets mici / ia ib lo hi mid pl best bd d xa xl ok)
  (setq ia (kf:intind sa dir) ib (kf:intind sb dir)
        lo (max (car ia) (car ib)) hi (min (cadr ia) (cadr ib))
        mid (kf:pp (/ (+ a b) 2.0) dir c)
        pl  (kf:inany mid mici))
  (foreach et ets
    ;; et: (lit w h text xc yc verticala)
    (if (= "H" dir)
      (setq xa (nth 4 et) xl (nth 5 et) ok (nth 6 et))
      (setq xa (nth 5 et) xl (nth 4 et) ok (not (nth 6 et)))
    )
    (if (and ok
             (>= xa (- a 50.0)) (<= xa (+ b 50.0))
             (>= xl (- lo *kf:tol*)) (<= xl (+ hi *kf:tol*))
             ;; o eticheta dintr-un buiandrug (contur inchis) e numai a lui
             (if pl
               (kf:inpoly (list (nth 4 et) (nth 5 et)) pl)
               (not (kf:inany (list (nth 4 et) (nth 5 et)) mici))))
      (progn
        (setq d (abs (- xl c)))
        (if (or (null best) (< d bd)) (setq best et bd d))
      )
    )
  )
  best
)

;; ---- reperul sectiunii --------------------------------------------------
;; s = pozitia pe linie, t = in sus (t=0 e linia, sectiunea e la t<0).
;;   linie orizontala: s -> +X, t -> +Y
;;   linie verticala:  s -> +Y, t -> -X  (adica rotit cu 90 de grade)

(defun kf:w (s tt)
  (if (= *kf:dir* "H")
    (list s (+ *kf:c* tt) 0.0)
    (list (- *kf:c* tt) s 0.0))
)

;; dreptunghi in reper -> (xmin ymin xmax ymax) in WCS
(defun kf:rect (s1 s2 t1 t2 / p q)
  (setq p (kf:w s1 t1) q (kf:w s2 t2))
  (list (min (car p) (car q)) (min (cadr p) (cadr q))
        (max (car p) (car q)) (max (cadr p) (cadr q)))
)

(defun kf:overlap (r1 r2)
  (and (< (car r1) (- (caddr r2) 5.0)) (< (car r2) (- (caddr r1) 5.0))
       (< (cadr r1) (- (cadddr r2) 5.0)) (< (cadr r2) (- (cadddr r1) 5.0)))
)

;; ---- entitati -----------------------------------------------------------

(defun kf:line (p q)
  (entmakex (list '(0 . "LINE") (cons 8 *kf:lay*) (cons 10 p) (cons 11 q)))
)

(defun kf:pline (pts closed)
  (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *kf:lay*)
                          '(100 . "AcDbPolyline") (cons 90 (length pts))
                          (cons 70 (if closed 1 0)))
                    (mapcar '(lambda (p) (cons 10 (list (car p) (cadr p)))) pts)))
)

(defun kf:solid3 (a b c)
  (entmakex (list '(0 . "SOLID") (cons 8 *kf:lay*)
                  (cons 10 a) (cons 11 b) (cons 12 c) (cons 13 c)))
)

(defun kf:text (str p rot)
  (entmakex (list '(0 . "TEXT") (cons 8 *kf:lay*) (cons 7 *kf:stilT*)
                  (cons 10 p) (cons 11 p) (cons 40 *kf:htxt*) (cons 1 str)
                  (cons 50 rot) '(72 . 1) '(73 . 1)))
)

;; hasura plina in conturul pl (ename) -> ename sau nil.
;; Asociativa: la un STRETCH al conturului se umple din nou.
(defun kf:hatch (pl / h arr r)
  (setq h (vl-catch-all-apply 'vla-AddHatch (list (kf:space) 1 "SOLID" :vlax-true)))
  (if (vl-catch-all-error-p h)
    nil
    (progn
      (setq arr (vlax-make-safearray vlax-vbObject '(0 . 0)))
      (vlax-safearray-fill arr (list (vlax-ename->vla-object pl)))
      (setq r (vl-catch-all-apply 'vla-AppendOuterLoop (list h arr)))
      (if (vl-catch-all-error-p r)
        (progn (vla-Delete h) nil)
        (progn
          (vl-catch-all-apply 'vla-Evaluate (list h))
          (vla-put-Layer h *kf:lay*)
          (vlax-vla-object->ename h)
        )
      )
    )
  )
)

;; cota liniara rotita cu ang, puncte WCS -> ename sau nil
(defun kf:dim (p1 p2 pl ang / o)
  (setq o (vl-catch-all-apply 'vla-AddDimRotated
            (list (kf:space) (vlax-3d-point p1) (vlax-3d-point p2) (vlax-3d-point pl) ang)))
  (if (vl-catch-all-error-p o)
    nil
    (progn
      (vl-catch-all-apply 'vla-put-Layer (list o *kf:lay*))
      (if (tblsearch "dimstyle" *kf:stilDim*)
        (vl-catch-all-apply 'vla-put-StyleName (list o *kf:stilDim*)))
      (vlax-vla-object->ename o)
    )
  )
)

;; Cota placii (14) e prea scurta ca textul sa incapa intre liniile ajutatoare
;; (DIMTIX il tine inauntru, peste capete), asa ca textul ei se scoate dincolo
;; de fata de sus, pastrandu-i departarea fata de linia de cota. m = -1 la
;; grinda intoarsa: placa e jos, textul iese sub linie.
(defun kf:mutsus (ent len m / obj auto tw tn tp dst)
  (if ent
    (progn
      (setq obj (vlax-ename->vla-object ent)
            dst (tblsearch "dimstyle" *kf:stilDim*)
            tw  (* 0.6 (cond ((cdr (assoc 140 dst))) ((getvar "DIMTXT")))
                   (strlen (rtos (/ len 10.0) 2 0)))
            tn  (* m (+ 40.0 (/ tw 2.0))))
      (setq auto (vl-catch-all-apply
                   '(lambda ( )
                      (vlax-safearray->list
                        (vlax-variant-value (vla-get-TextPosition obj))))
                   nil))
      (if (not (vl-catch-all-error-p auto))
        (progn
          (setq tp (if (= *kf:dir* "H")
                     (list (car auto) (+ *kf:c* tn) 0.0)
                     (list (- *kf:c* tn) (cadr auto) 0.0)))
          (vl-catch-all-apply 'vla-put-TextMovement (list obj 2))
          (vl-catch-all-apply 'vla-put-TextPosition (list obj (vlax-3d-point tp)))
        )
      )
    )
  )
  ent
)

;; grup anonim din entitati (ActiveX; daca nu merge, cu comanda -GROUP)
(defun kf:group (ents / r ss)
  (setq ents (vl-remove nil ents))
  (if ents
    (progn
      (setq r (vl-catch-all-apply
                '(lambda ( / g arr)
                   (setq g   (vla-Add (vla-get-Groups (kf:doc)) "*")
                         arr (vlax-make-safearray vlax-vbObject (cons 0 (1- (length ents)))))
                   (vlax-safearray-fill arr (mapcar 'vlax-ename->vla-object ents))
                   (vla-AppendItems g arr)
                   g)
                nil))
      (if (vl-catch-all-error-p r)
        (progn
          (setq ss (ssadd))
          (foreach e ents (ssadd e ss))
          (command "_.-GROUP" "_Create" "*" "" ss "")
        )
      )
    )
  )
)

;; ObjectId-ul unui obiect, ca text, pentru coduri de field
(defun kf:oid (ent / obj r)
  (setq obj (vlax-ename->vla-object ent)
        r   (vl-catch-all-apply 'vla-GetObjectIdString
              (list (vla-get-Utility (kf:doc)) obj :vlax-false)))
  (if (vl-catch-all-error-p r) (itoa (vla-get-ObjectID obj)) r)
)

;; Textul cotei de jos devine field, la fel ca in desenele de mana:
;;   +%<\AcExpr (sus - masura cotei*0.01 [- masura cotei placii*0.01])>%
;; Masura cotei se citeste in centimetri (DIMLFAC 0.1), deci *0.01 = metri.
;; La un STRETCH al sectiunii si un REGEN, cota de jos se recalculeaza.
;; La grinda intoarsa (op "+") e invers: field-ul e sus, = cota de jos + cotele.
(defun kf:field (txt sus dims niv op / s)
  (setq dims (vl-remove nil dims))
  (if (and txt sus dims)
    (progn
      (setq s (strcat (if (> niv 0.0) "+" "")
                      "%<\\AcExpr (%<\\AcObjProp Object(%<\\_ObjId " (kf:oid sus)
                      ">%).TextString>%"))
      (foreach d dims
        (setq s (strcat s op "%<\\AcObjProp.16.2 Object(%<\\_ObjId " (kf:oid d)
                        ">%).Measurement \\f \"%lu6%ct8[0.01]\">%*0.01")))
      (setq s (strcat s ") \\f \"%lu6\">%"))
      (vl-catch-all-apply 'vla-put-TextString (list (vlax-ename->vla-object txt) s))
    )
  )
)

;; latimea unui text de nivel
(defun kf:tw (str / tb)
  (setq tb (textbox (list (cons 1 str) (cons 40 *kf:htxt*) (cons 7 *kf:stilT*))))
  (if tb (- (car (cadr tb)) (car (car tb))) (* 0.75 *kf:htxt* (strlen str)))
)

;; eticheta de nivel: varful triunghiului in (st, tl), textul la dreapta lui
;; (in sensul de citire). Intoarce entitatile.
(defun kf:marker (st tl str / tw rot)
  (setq tw  (kf:tw str)
        rot (if (= *kf:dir* "H") 0.0 (/ pi 2.0)))
  (list
    (kf:line  (kf:w (- st 74.0) tl) (kf:w (+ st 73.0) tl))
    (kf:solid3 (kf:w st tl) (kf:w (- st 31.0) (+ tl 69.0)) (kf:w st (+ tl 69.0)))
    (kf:pline (list (kf:w st tl) (kf:w st (+ tl 69.0)) (kf:w (+ st 30.0) (+ tl 69.0))) T)
    (kf:line  (kf:w (- st 31.0) (+ tl 69.0)) (kf:w (+ st 30.0 tw 40.0) (+ tl 69.0)))
    (kf:text  str (kf:w (+ st 30.0 (/ tw 2.0)) (+ tl 86.0)) rot)
  )
)

;; ---- un element ---------------------------------------------------------
;; el: lista asociativa
;;   s1 s2   fetele pe linie        h     inaltimea [mm]
;;   tip     "C" "G" "B"            nume  pentru raport
;;   pl pr   placa iese la stanga / la dreapta (T/nil)
;;   il ir   golul din stanga / din dreapta e interior (T/nil)
;;   lmk     cat ocupa etichetele de nivel pe linie
;;   sus jos textele de nivel

;; configuratii: 1 = cota+etichete la dreapta, 2 = amandoua la stanga,
;;               3 = cota la dreapta, etichete la stanga, 4 = invers,
(defun kf:dside (cfg) (if (member cfg '(1 3)) 1 -1))
(defun kf:mside (cfg) (if (member cfg '(1 4)) 1 -1))

;; cat iese placa pe partea side
(defun kf:stubs (el side)
  (if (and (> *kf:hpmm* 0.0) (< *kf:hpmm* (kf:get 'h el))
           (kf:get (if (= side 1) 'pr 'pl) el))
    *kf:stub* 0.0)
)

;; cat ocupa grupul pe partea side, de la fata elementului: (placa extra)
(defun kf:need (el cfg side / d m)
  (setq d (= side (kf:dside cfg)) m (= side (kf:mside cfg)))
  (list (kf:stubs el side)
        (+ (if d *kf:ldim* 0.0)
           (if m (+ (if d *kf:gapdm* *kf:gap*) (kf:get 'lmk el)) 0.0)))
)

;; amprenta pe partea side (WCS) sau nil
(defun kf:amprenta (el cfg side / n f t1 t2)
  (setq n (kf:need el cfg side))
  ;; pe inaltime: normal de sub sectiune pana deasupra textului de sus; la
  ;; grinda intoarsa de sub linie (textul cotei placii) pana deasupra ei
  (if (kf:get 'inv el)
    (setq t1 -200.0 t2 (+ (kf:get 'h el) 210.0))
    (setq t1 (- (+ (kf:get 'h el) 30.0)) t2 210.0))
  (if (> (cadr n) 0.0)
    (if (= side 1)
      (progn (setq f (kf:get 's2 el))
             (kf:rect f (+ f (car n) (cadr n)) t1 t2))
      (progn (setq f (kf:get 's1 el))
             (kf:rect (- f (car n) (cadr n)) f t1 t2))
    )
  )
)

;; costul unei configuratii pentru un element singur
(defun kf:cost (el cfg obs / c r side)
  (setq c (cond ((= cfg 1) 0.0) ((= cfg 2) 0.1) ((= cfg 3) 0.5) (T 0.6)))
  (foreach side '(1 -1)
    (if (> (cadr (kf:need el cfg side)) 0.0)
      (progn
        ;; spre exterior nu se pune nimic (acolo sunt cotele)
        (if (not (kf:get (if (= side 1) 'ir 'il) el)) (setq c (+ c 100.0)))
        (if (setq r (kf:amprenta el cfg side))
          (foreach o obs (if (kf:overlap r o) (setq c (+ c 10.0)))))
      )
    )
  )
  c
)

;; costul golului dintre doua elemente vecine
(defun kf:costgol (ea ca eb cb / na nb L)
  (setq na (kf:need ea ca 1) nb (kf:need eb cb -1)
        L  (- (kf:get 's1 eb) (kf:get 's2 ea)))
  (if (> (+ (car na) (cadr na) (car nb) (cadr nb)
            (if (and (> (cadr na) 0.0) (> (cadr nb) 0.0)) *kf:marg* 0.0))
         L)
    50.0 0.0)
)

;; alegerea configuratiilor pe toata linia (programare dinamica: fiecare
;; element depinde numai de vecinii lui, prin golurile comune)
(defun kf:alege (els obs / cfgs prev cur best bc c p tab res k)
  (setq tab nil prev nil)
  (foreach el els
    (setq cfgs '(1 2 3 4)
          cur  nil)
    (foreach cfg cfgs
      (setq best nil bc nil)
      (if prev
        (foreach p prev
          ;; p: (cfg cost elprev)
          (setq c (+ (cadr p) (kf:costgol (caddr p) (car p) el cfg)))
          (if (or (null best) (< c best)) (setq best c bc (car p)))
        )
        (setq best 0.0)
      )
      (setq cur (cons (list cfg (+ best (kf:cost el cfg obs)) el bc) cur))
    )
    (setq tab (cons cur tab) prev cur)
  )
  ;; inapoi, de la ultimul element
  (setq res nil k nil)
  (foreach cur tab
    (setq best nil)
    (foreach x cur
      (if (if k (= (car x) k) (or (null best) (< (cadr x) (cadr best))))
        (setq best x)))
    (setq res (cons (list (car best) (cadr best)) res)
          k   (cadddr best))
  )
  ;; -> ((cfg costcumulat) ...) in ordinea elementelor
  res
)

;; desenarea grupului unui element -> entitatile lui
(defun kf:deseneaza (el cfg / s1 s2 h hp sl sr pts out pl ents ds ms e sd inw
                              ang tm r dims msus mjos m)
  (setq s1 (kf:get 's1 el) s2 (kf:get 's2 el) h (kf:get 'h el)
        hp (if (and (> *kf:hpmm* 0.0) (< *kf:hpmm* h)) *kf:hpmm* 0.0)
        sl (- s1 (kf:stubs el -1)) sr (+ s2 (kf:stubs el 1))
        ;; grinda intoarsa: totul oglindit fata de linie - pleaca de la ea in sus
        m  (if (kf:get 'inv el) -1.0 1.0))

  ;; conturul sectiunii, in sens trigonometric, fara puncte dublate
  (setq pts (if (> hp 0.0)
              (list (list sl 0.0) (list sr 0.0) (list sr (- hp)) (list s2 (- hp))
                    (list s2 (- h)) (list s1 (- h)) (list s1 (- hp)) (list sl (- hp)))
              (list (list s1 0.0) (list s2 0.0) (list s2 (- h)) (list s1 (- h)))))
  (setq out nil)
  (foreach p pts
    (if (not (and out (kf:eq (car p) (car (car out))) (kf:eq (cadr p) (cadr (car out)))))
      (setq out (cons p out))))
  (if (and (cdr out) (kf:eq (car (car out)) (car (last out))) (kf:eq (cadr (car out)) (cadr (last out))))
    (setq out (cdr out)))
  (setq pts (kf:colin (reverse out)))
  (if (< m 0.0) (setq pts (mapcar '(lambda (p) (list (car p) (- (cadr p)))) pts)))

  (setq pl   (kf:pline (mapcar '(lambda (p) (kf:w (car p) (cadr p))) pts) T)
        ents (list pl (kf:hatch pl))
        dims nil)

  ;; cota de inaltime
  (setq ds (kf:dside cfg) ms (kf:mside cfg)
        ang (if (= *kf:dir* "H") (/ pi 2.0) 0.0))
  (if (/= ds 0)
    (progn
      ;; textul cotei cade la stanga liniei de cota pe orizontala (cota
      ;; verticala) si deasupra ei pe verticala (cota orizontala)
      (setq inw (if (= *kf:dir* "H") (= ds 1) (= ds -1))
            e   (if (= ds 1) sr sl)
            sd  (+ e (* ds (if inw *kf:dimIn* *kf:dimOut*))))
      (setq dims
        (if (> hp 0.0)
          (list (kf:mutsus (kf:dim (kf:w e 0.0) (kf:w e (* m (- hp))) (kf:w sd 0.0) ang) hp m)
                (kf:dim (kf:w (if (= ds 1) s2 s1) (* m (- hp)))
                        (kf:w (if (= ds 1) s2 s1) (* m (- h)))
                        (kf:w sd 0.0) ang))
          (list (kf:dim (kf:w e 0.0) (kf:w e (* m (- h))) (kf:w sd 0.0) ang))))
      (setq ents (append ents dims))
    )
  )

  ;; etichetele de nivel
  (if (/= ms 0)
    (progn
      (setq e (if (= ms 1) sr sl)
            r (if (= ds ms) (+ *kf:ldim* *kf:gapdm*) *kf:gap*))
      (setq tm (if (= ms 1)
                 (+ e r 31.0)
                 (- e r (- (kf:get 'lmk el) 31.0))))
      (setq msus (kf:marker tm 0.0 (kf:get 'sus el))
            mjos (kf:marker tm (* m (- h)) (kf:get 'jos el))
            ents (append ents msus mjos))
      ;; capatul celalalt = cota de la linie -/+ inaltimea din cota(cotele) de
      ;; inaltime (jos la grinzile obisnuite, sus la cele intoarse)
      (kf:field (last mjos) (last msus) dims
                (if (< m 0.0) (+ *kf:niv* (/ h 1000.0)) (- *kf:niv* (/ h 1000.0)))
                (if (< m 0.0) "+" "-"))
    )
  )
  (kf:group ents)
  ents
)

;; scoate varfurile coliniare (conturul e ortogonal)
(defun kf:colin (pts / n i a b c res)
  (setq n (length pts) i 0 res nil)
  (repeat n
    (setq a (nth (rem (+ i n -1) n) pts) b (nth i pts) c (nth (rem (1+ i) n) pts))
    (if (not (or (and (kf:eq (car a) (car b)) (kf:eq (car b) (car c)))
                 (and (kf:eq (cadr a) (cadr b)) (kf:eq (cadr b) (cadr c)))))
      (setq res (cons b res)))
    (setq i (1+ i))
  )
  (reverse res)
)

;; ---- o linie ------------------------------------------------------------
;; -> lista de randuri de raport

(defun kf:linie (dir c segs ets mici goluri obs / cr i a b els el et tip h nm lay
                                                 n k cfgs rap nr j ok inv)
  (setq *kf:dir* dir *kf:c* c)
  (setq cr (kf:cross segs dir c) els nil i 0)

  ;; perechile de fete apropiate = elemente
  (while (< i (1- (length cr)))
    (setq a (nth i cr) b (nth (1+ i) cr))
    (if (and (cadr a) (cadr b)
             (>= (- (car b) (car a)) *kf:wmin*)
             (<= (- (car b) (car a)) *kf:wmax*))
      (progn
        (setq et (kf:eticheta (car a) (car b) (kf:scurt (caddr a)) (kf:scurt (caddr b))
                              dir c ets mici))
        (setq lay (cdr (assoc 8 (entget (car (kf:scurt (caddr a)))))))
        (cond
          ((null et)
           (if (= (strcase lay) (strcase *kf:layCent*))
             (setq tip "C" h *kf:hcmm* nm "centura fara eticheta")
             (setq tip "G" h *kf:hcmm* nm "GRINDA FARA ETICHETA (pusa cu inaltimea centurii)"
                   *kf:fara* (1+ *kf:fara*))))
          ((wcmatch (car et) "C*") (setq tip "C" h *kf:hcmm* nm (nth 3 et)))
          ((wcmatch (car et) "G*") (setq tip "G" h (* 10.0 (nth 2 et)) nm (nth 3 et)))
          (T                       (setq tip "B" h (* 10.0 (nth 2 et)) nm (nth 3 et)))
        )
        ;; grinda intoarsa: pleaca de la cota data la pornire in sus
        (setq inv (and et (wcmatch (car et) "G*") (kf:intoarsa (nth 3 et))))
        (setq els (cons (list (cons 's1 (car a)) (cons 's2 (car b)) (cons 'h h)
                              (cons 'tip tip) (cons 'nume nm) (cons 'inv inv)
                              (cons 'sus (kf:fmtniv *kf:niv*))
                              (cons 'jos (kf:fmtniv (if inv (+ *kf:niv* (/ h 1000.0))
                                                            (- *kf:niv* (/ h 1000.0))))))
                        els))
        (setq i (+ i 2))
      )
      (setq i (1+ i))
    )
  )
  (setq els (reverse els) n (length els))

  ;; vecinatati: golurile interioare si placa
  (setq k 0 a nil)
  (foreach el els
    (setq b (nth (1+ k) els))
    (setq ok (and b (kf:interior (/ (+ (kf:get 's2 el) (kf:get 's1 b)) 2.0) dir c segs)))
    (setq el (append el
                     (list (cons 'il (and a (kf:get 'ir a)))
                           (cons 'ir ok)
                           (cons 'pl (and a (kf:get 'ir a)
                                          (not (kf:inany (kf:pp (- (kf:get 's1 el) 50.0) dir c) goluri))))
                           (cons 'pr (and ok
                                          (not (kf:inany (kf:pp (+ (kf:get 's2 el) 50.0) dir c) goluri))))
                           (cons 'lmk (+ 31.0 30.0 40.0
                                         (max (kf:tw (kf:get 'sus el)) (kf:tw (kf:get 'jos el))))))))
    (setq els (subst el (nth k els) els) a el k (1+ k))
  )

  (setq rap nil nr 0)
  (if (= n 0)
    (setq rap (list "  nu taie nicio centura sau grinda"))
    (progn
      (setq cfgs (kf:alege els obs) j 0 a 0.0)
      (foreach el els
        (setq k (car (nth j cfgs)))
        (kf:deseneaza el k)
        (setq nr (1+ nr))
        ;; sectiunea si amprentele devin obstacole pentru liniile urmatoare
        (setq b (kf:rect (- (kf:get 's1 el) (kf:stubs el -1)) (+ (kf:get 's2 el) (kf:stubs el 1))
                         (if (kf:get 'inv el) 0.0 (- (kf:get 'h el)))
                         (if (kf:get 'inv el) (kf:get 'h el) 0.0))
              obs (cons b obs))
        (foreach side '(1 -1)
          (if (setq b (kf:amprenta el k side)) (setq obs (cons b obs))))
        (setq rap (cons (strcat "  " (kf:get 'nume el)
                                (if (>= (- (cadr (nth j cfgs)) a) 10.0)
                                  "  <-- INGHESUIT, verificati asezarea" ""))
                        rap))
        (setq a (cadr (nth j cfgs)) j (1+ j))
      )
      (setq rap (cons (strcat "  " (itoa nr) " sectiuni") (reverse rap)))
    )
  )
  (setq *kf:obs* obs)
  rap
)

;; ---- bucla de linii -----------------------------------------------------

(defun kf:bucla (dir segs ets mici goluri / p nr rap)
  (setq nr (if (= dir "H")
             "ORIZONTALA (fata de sus a sectiunilor)"
             "VERTICALA (fata de sus a sectiunilor, ea e in stanga)"))
  (setq p (getpoint (strcat "\nIndicati linia " nr " <Enter = gata>: ")))
  (while p
    (setq p (trans p 1 0))
    (setq rap (kf:linie dir (if (= dir "H") (cadr p) (car p))
                        segs ets mici goluri *kf:obs*))
    (foreach l rap (princ (strcat "\n" l)))
    (setq p (getpoint (strcat "\nAlta linie " nr " <Enter = gata>: ")))
  )
  (princ)
)

;; inaltimea centurilor din etichete (cea mai deasa), in cm
(defun kf:hcent (ets / cnt best x)
  (foreach et ets
    (if (wcmatch (car et) "C*")
      (if (setq x (assoc (nth 2 et) cnt))
        (setq cnt (subst (cons (car x) (1+ (cdr x))) x cnt))
        (setq cnt (cons (cons (nth 2 et) 1) cnt)))))
  (foreach x cnt (if (or (null best) (> (cdr x) (cdr best))) (setq best x)))
  (if best (car best))
)

;; ---- comanda ------------------------------------------------------------

(defun c:COFRAJ ( / *error* ss segs tx ets pls och osm clay undok v hdef)

  (defun *error* (msg)
    (if och (setvar "CMDECHO" och))
    (if osm (setvar "OSMODE" osm))
    (if clay (setvar "CLAYER" clay))
    (if undok (vl-catch-all-apply 'vla-EndUndoMark (list (kf:doc))))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*")))
      (princ (strcat "\n*** Eroare: " msg))
      (princ "\n*** Intrerupt."))
    (princ)
  )

  (princ "\nSelectati planul de cofraj (centuri, grinzi, etichete, cote): ")
  (setq ss (ssget))
  (if (null ss)
    (progn (princ "\nNimic selectat.") (princ))
    (progn
      (setq segs (kf:segs ss))
      (if (null segs)
        (princ "\nNu am gasit centuri sau grinzi in selectie.")
        (progn
          (setq tx  (kf:texte ss)
                ets (car tx)
                pls (kf:polys ss))
          (setq *kf:obs* (cadr tx))
          (princ (strcat "\n" (itoa (length segs)) " fete de element, "
                         (itoa (length ets)) " etichete de element, "
                         (itoa (length (car pls))) " buiandrugi/grinzi inchise, "
                         (itoa (length (cadr pls))) " goluri de placa."))

          ;; intrebarile
          (initget 0)
          (setq v (getreal (strcat "\nCota partii de sus [m] <" (kf:fmtniv *kf:niv*) ">: ")))
          (if v (setq *kf:niv* v))
          (setq hdef (cond (*kf:hc*) ((kf:hcent ets)) (25.0)))
          (initget 6)
          (setq v (getreal (strcat "\nInaltimea centurilor [cm] <" (rtos hdef 2 0) ">: ")))
          (setq *kf:hc* (if v v hdef))
          (initget 4)
          (setq v (getreal (strcat "\nGrosimea placii [cm], 0 = fara placa <" (rtos *kf:hp* 2 0) ">: ")))
          (if v (setq *kf:hp* v))
          (setq *kf:hcmm* (* 10.0 *kf:hc*)
                *kf:hpmm* (* 10.0 *kf:hp*))

          (setq och  (getvar "CMDECHO")
                osm  (getvar "OSMODE")
                clay (getvar "CLAYER"))
          (vla-StartUndoMark (kf:doc))
          (setq undok T)
          (setvar "CMDECHO" 0)
          (setvar "OSMODE" 0)
          (if (null (tblsearch "layer" *kf:lay*))
            (command "_.-LAYER" "_Make" *kf:lay* ""))
          (kf:stiluri-cm50)
          (kf:fa-stil-text "cezar" "times.ttf")
          (setq *kf:stilT* (if (tblsearch "style" *kf:stilTxt*) *kf:stilTxt* (getvar "TEXTSTYLE")))

          (setq *kf:fara* 0)
          (kf:bucla "H" segs ets (car pls) (cadr pls))
          (kf:bucla "V" segs ets (car pls) (cadr pls))
          (command "_.REGEN")
          (if (> *kf:fara* 0)
            (alert (strcat (itoa *kf:fara*) " sectiuni de grinda fara eticheta gasita - le-am pus cu inaltimea"
                           " centurilor (" (rtos *kf:hc* 2 0) " cm).\n\nEticheta (ex. G1 30x50, GF1 30x50) trebuie"
                           " sa stea intre cele doua linii ale grinzii, paralela cu ea. Vedeti raportul din linia de"
                           " comanda, mutati eticheta, stergeti grupurile gresite si refaceti linia.")))

          (setvar "CMDECHO" och)
          (setvar "OSMODE" osm)
          (setvar "CLAYER" clay)
          (vla-EndUndoMark (kf:doc))
          (setq undok nil)
        )
      )
      (princ)
    )
  )
)

(princ "\nCOFRAJ - sectiunile de cofraj (centuri, grinzi, buiandrugi) pe liniile indicate.")
(princ)
