;; Revizie:
;;  - marcile legate (generate de GenerareGrinziBuiandrugi / SectiuniGrinzi):
;;    un text pe "Otel marca" cu legatura ascunsa (XDATA "GBMARCA", ex
;;    "C300x250" = etrierul centurii 30x25, "CB4x12" = barele centurii 4%%C12)
;;    primeste numarul definitiei cu aceeasi legatura (etrierul / bara din
;;    detaliul centurii), oriunde ar fi - ex marca etrierului centurii din
;;    sectiunea unui buiandrug. Nu mai trebuie corectate manual ("Marci otel
;;    de corectat"). Intr-un "Chenar pentru sectiuni etrieri", marcile legate
;;    nu mai primesc numarul definitiei din chenar. O legatura fara definitie
;;    e semnalata.
;;  - toata renumerotarea se anuleaza cu un singur U (inainte, fiecare marca
;;    era un pas separat de UNDO); la ESC marcajul de UNDO se inchide corect
;;  - sortarile folosesc vl-sort-i, care nu poate pierde niciodata elemente
;;    (vl-sort poate elimina elementele considerate egale)
;;  - la iesirile normale (nimic selectat, niciun chenar) nu mai apare mesaj
;;    de eroare
(vl-load-com)
(defun rmk:sort (lst fn) (mapcar '(lambda (i) (nth i lst)) (vl-sort-i lst fn)))

;; =========================================================================
;; FORMA ETRIERULUI (ramurile), pe langa diametru+lungime
;; Doi etrieri cu aceeasi lungime pot avea ramuri diferite (ex 20x35 si
;; 25x30 au amandoi perimetrul 110). Forma se citeste din COTELE din
;; grupul definitiei: cotele liniare orizontale dau ramurile orizontale,
;; cele verticale ramurile verticale. Cotele inclinate (aliniate - ex
;; ciocurile de 10 cm) se ignora. Daca grupul nu are cote, se ia
;; latimea x inaltimea poliliniei etrierului (in unitati de desen).
;;
;; Acelasi numar DOAR daca diametrul, lungimea si ramurile sunt aceleasi.
;; Un etrier doar rotit (25x30 desenat ca 30x25) e aceeasi bucata
;; fasonata -> acelasi numar. Ramuri diferite cu aceeasi lungime (ex 35x20
;; fata de 30x25, ambele L=1.30) -> numere diferite.
;; =========================================================================

;; perechea de ramuri, mereu cu latura mai mica prima: "25x30"
(defun rmk:pereche (a b)
  (if (or (< (atof b) (atof a)) (and (= (atof a) (atof b)) (< b a)))
    (strcat b "x" a)
    (strcat a "x" b))
)

;; valorile unice, sortate, unite cu "/" (ex (30 25 25) -> "25/30")
(defun rmk:lista-text (lst / r)
  (foreach v lst (if (not (member v r)) (setq r (cons v r))))
  (setq r (rmk:sort r '(lambda (a b) (< (atof a) (atof b)))))
  (if r (apply 'strcat (cons (car r) (mapcar '(lambda (s) (strcat "/" s)) (cdr r)))) "")
)

;; valoarea afisata de o cota: textul scris peste cota, daca e un numar,
;; altfel valoarea masurata
(defun rmk:valoare-cota (ed / txt val)
  (setq txt (vl-string-trim " " (cond ((cdr (assoc 1 ed))) (""))))
  (if (and (/= txt "") (not (vl-string-search "<>" txt))
           (setq val (distof (vl-string-translate "," "." txt) 2)))
    val
    (cdr (assoc 42 ed)))
)

;; forma etrierului din grupul grpid: "25x30", "P625x750" sau ""
(defun rmk:forma-etrier (grpid / ed ang h v pts xs ys hs vs)
  (foreach it (entget grpid)
    (if (and (= (car it) 340)
             (setq ed (entget (cdr it))))
      (cond
        ( (and (= (cdr (assoc 0 ed)) "DIMENSION")
               (= 0 (logand 7 (cdr (assoc 70 ed)))))       ; cota liniara (nu aliniata)
          (setq ang (rem (abs (cdr (assoc 50 ed))) pi))
          (cond
            ( (or (< ang 0.01) (> ang (- pi 0.01)))
              (setq h (cons (rtos (rmk:valoare-cota ed) 2 1) h)))
            ( (< (abs (- ang (/ pi 2))) 0.01)
              (setq v (cons (rtos (rmk:valoare-cota ed) 2 1) v)))
          )
        )
        ( (= (cdr (assoc 0 ed)) "LWPOLYLINE")
          (foreach p ed (if (= (car p) 10) (setq pts (cons (cdr p) pts))))
        )
      )
    )
  )
  (cond
    ( (or h v)
      (setq hs (rmk:lista-text h) vs (rmk:lista-text v))
      (rmk:pereche hs vs))
    ( pts
      (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts))
      (setq hs (rtos (- (apply 'max xs) (apply 'min xs)) 2 0)
            vs (rtos (- (apply 'max ys) (apply 'min ys)) 2 0))
      (strcat "P" (rmk:pereche hs vs)))
    ( T "")
  )
)


;; =========================================================================
;; ORDINEA DE NUMEROTARE (nu mai depinde de pozitia din desen)
;;  1. bare lungi, chenar cu chenar, dupa NUMELE grinzii scris in
;;     "Chenar pentru armatura": G1, G2 ... (GP7, GP8 continua sirul G),
;;     apoi B1, B2 ..., apoi chenarele fara nume G/B (ex fierul lung al
;;     centurilor, 4%%C12 L=12.00m), de la stanga la dreapta
;;  2. etrieri, dupa sectiunea lor: 1-1, 2-2, 3-3 ...
;;  3. la urma etrierii care nu sunt in niciun "Chenar pentru sectiuni
;;     etrieri" (ex etrierii centurilor, cu "255 buc." in grup)
;; Grinzile pot fi asezate oricum pe plansa; o grinda adaugata ulterior
;; isi ia locul dupa nume.
;; =========================================================================

;; textul fara codurile de formatare MTEXT ({\fArial;G1} -> G1)
(defun rmk:text-curat (str / i n c c2 r)
  (setq i 1 n (strlen str) r "")
  (while (<= i n)
    (setq c (substr str i 1))
    (cond
      ( (= c "\\")
        (setq c2 (substr str (1+ i) 1))
        (cond
          ( (member (strcase c2) '("P" "~")) (setq r (strcat r " ") i (+ i 2)))
          ( (member c2 '("\\" "{" "}")) (setq r (strcat r c2) i (+ i 2)))
          ( (member (strcase c2) '("L" "O" "K")) (setq i (+ i 2)))
          ( T (while (and (<= i n) (/= (substr str i 1) ";")) (setq i (1+ i)))
              (setq i (1+ i)))))
      ( (member c '("{" "}")) (setq i (1+ i)))
      ( T (setq r (strcat r c) i (1+ i)))))
  (vl-string-trim " " r)
)

;; numele grinzii -> (categorie numar subcategorie), sau nil
;; G1..Gn si GP.. -> categoria 0; B1..Bn -> categoria 1
(defun rmk:nume-grinda (str)
  (setq str (strcase (rmk:text-curat str)))
  (cond
    ( (wcmatch str "GP#*") (list 0 (atoi (substr str 3)) 1))
    ( (wcmatch str "G#*")  (list 0 (atoi (substr str 2)) 0))
    ( (wcmatch str "B#*")  (list 1 (atoi (substr str 2)) 0))
  )
)

;; primul cuvant ("G1 30x40 1buc." -> "G1")
(defun rmk:primul-cuvant (str / p)
  (if (setq p (vl-string-search " " str)) (substr str 1 p) str)
)

;; compara doua chei (liste de numere), element cu element
(defun rmk:cheie< (a b)
  (cond
    ( (null a) (and b T))
    ( (null b) nil)
    ( (< (car a) (car b)) T)
    ( (> (car a) (car b)) nil)
    ( T (rmk:cheie< (cdr a) (cdr b)))
  )
)

;; =========================================================================
;; RENUMEROTEAZA MARCI GRINZI
;; Renumeroteaza automat marcile de armare la grinzi, in doua etape:
;;
;; ETAPA 1 - BARE LUNGI: pentru fiecare "Chenar pentru armatura" (in
;; ordinea numelor G.., GP.., B.., apoi fara nume - vezi mai sus), gaseste toate grupurile complete marca+diametru
;; (FARA pas)+lungime a caror marca cade in interiorul chenarului. Le
;; ordoneaza: cea mai de jos (Y minim) prima; la aceeasi inaltime (Y
;; identic), de la stanga la dreapta (X crescator). Le numeroteaza
;; consecutiv, continuand intre chenare; doua grupuri cu acelasi diametru
;; de baza si aceeasi lungime primesc automat acelasi numar.
;;
;; ETAPA 2 - ETRIERI: cauta, in toata selectia, toate grupurile complete
;; de DEFINITIE de etrier (marca+diametru CU pas+lungime+cuvantul "etr"),
;; le ordoneaza dupa sectiune (1-1, 2-2 ...; cele din afara chenarelor de
;; sectiuni la urma), si le numeroteaza continuand
;; de unde a ramas etapa 1 (cu aceeasi regula de potrivire dupa diametru+
;; lungime). Numarul nou se copiaza apoi:
;;   a) la toate celelalte texte de pe "Otel marca" gasite in interiorul
;;      aceluiasi poligon "Chenar pentru sectiuni etrieri" ca definitia
;;      (indicatoarele mici, marca+cerc, care insotesc etichetele N-N);
;;   b) la indicatorul (marca+cerc) din interiorul fiecarui "Chenar
;;      etrieri" de la grinda, gasit prin eticheta N-N: in Chenar etrieri
;;      cautam o pereche de grupuri (text+linie) pe layerul "Sectiuni
;;      grinzi" cu ACEEASI cifra (ex 2 si 2), formam eticheta "2-2", si o
;;      cautam printre etichetele N-N gasite la punctul (a).
;;
;; Functioneaza chiar daca unele layere sunt stinse (OFF) - entitatile
;; raman complet accesibile din cod indiferent de vizibilitate; doar
;; layerele INGHETATE (FREEZE) ar fi excluse din selectie. IMPORTANT:
;; daca ati oprit selectarea automata pe grup (Ctrl+Shift+A), o fereastra
;; trasa doar peste partea vizibila NU va prinde restul grupului - lasati
;; Ctrl+Shift+A pe modul normal (grupuri active) cand selectati.
;;
;; ATENTIE: mecanism complex, cu multe piese care trebuie sa se lege
;; corect - testati cu grija, pe o zona mica, inainte de tot planul.
;;
;; Daca in selectie exista ceva pe layerul "Marci otel de corectat"
;; (marci mutate manual acolo, ca sa fie ajustate ulterior in functie de
;; numerele primite de etrierii din centuri - ex la buiandrugi cu
;; suprapuneri de etrieri), la final apare un avertisment vizibil care
;; reaminteste sa fie verificate/corectate manual.
;; =========================================================================

(defun grn-get-group-id (ent / elist item grp)
  (setq elist (entget ent) grp nil)
  (foreach item elist
    (if (= (car item) 330)
      (if (= (cdr (assoc 0 (entget (cdr item)))) "GROUP") (setq grp (cdr item)))
    )
  )
  grp
)

;; legatura ascunsa a unei marci (XDATA "GBMARCA"), sau nil
(defun grn-tag (ent / x)
  (if (setq x (cdr (assoc -3 (entget ent '("GBMARCA")))))
    (cdr (assoc 1000 (cdr (car x)))))
)

;; adevarat daca textul de diametru are PAS (cifre urmate de "/") - la fel
;; ca la stalpi/grinzi/mansarda: distinge etrier de bara dreapta prin
;; forma, nu prin cuvant-cheie
(defun grn-are-pas (str / pos idx)
  (setq str (strcase str))
  (cond
    ((setq pos (vl-string-search "%%C" str)) (setq pos (+ pos 3)))
    ((setq pos (vl-string-search (chr 216) str)) (setq pos (+ pos 1)))
    (t (setq pos nil))
  )
  (if pos
    (progn
      (while (and (< pos (strlen str)) (wcmatch (substr str (1+ pos) 1) "[0-9]"))
        (setq pos (1+ pos))
      )
      (and (< pos (strlen str)) (= (substr str (1+ pos) 1) "/"))
    )
    nil
  )
)

(defun grn-extrage-diam-baza (str / pos idx rez)
  (setq str (strcase str))
  (cond
    ((setq pos (vl-string-search "%%C" str)) (setq idx (+ pos 4)))
    ((setq pos (vl-string-search (chr 216) str)) (setq idx (+ pos 2)))
    (t (setq idx nil))
  )
  (setq rez "")
  (if idx
    (while (and (<= idx (strlen str)) (wcmatch (substr str idx 1) "[0-9]"))
      (setq rez (strcat rez (substr str idx 1)))
      (setq idx (1+ idx))
    )
  )
  rez
)

(defun grn-extrage-lungime (str / pos idx rez)
  (setq str (strcase str))
  (setq pos (vl-string-search "L=" str))
  (setq rez "")
  (if pos
    (progn
      (setq idx (+ pos 3))
      (while (and (<= idx (strlen str)) (wcmatch (substr str idx 1) "[0-9.]"))
        (setq rez (strcat rez (substr str idx 1)))
        (setq idx (1+ idx))
      )
    )
  )
  rez
)

(defun grn-obtine-puncte-polilinie (ent / elist pts item)
  (setq elist (entget ent) pts nil)
  (foreach item elist
    (if (= (car item) 10) (setq pts (cons (list (cadr item) (caddr item)) pts)))
  )
  (reverse pts)
)

(defun grn-punct-in-poligon (p pts / x y inside i j p1 p2 x1 y1 x2 y2 n)
  (setq n (length pts))
  (setq x (car p) y (cadr p) inside nil i 0 j (1- n))
  (while (< i n)
    (setq p1 (nth i pts) p2 (nth j pts))
    (setq x1 (car p1) y1 (cadr p1) x2 (car p2) y2 (cadr p2))
    (if (and (or (and (< y1 y) (>= y2 y)) (and (< y2 y) (>= y1 y)))
             (< (+ x1 (/ (* (- y y1) (- x2 x1)) (- y2 y1))) x))
      (setq inside (not inside))
    )
    (setq j i i (1+ i))
  )
  inside
)

;; cheia de potrivire dupa diametru+lungime, ca la celelalte extrase
(defun grn-cheie (diam_baza lung_val)
  (strcat (itoa (atoi diam_baza)) "|" (rtos (atof lung_val) 2 3))
)

;; sortare bare lungi: Y crescator (jos->sus); la Y identic, X crescator
;; (stanga->dreapta). g = (marca_ent pt diam_baza lung_val)
(defun grn-sorteaza-bare (lista)
  (rmk:sort lista
    '(lambda (a b / ya yb xa xb)
       (setq ya (cadr (cadr a)) yb (cadr (cadr b)))
       (setq xa (car (cadr a)) xb (car (cadr b)))
       (if (equal ya yb 1e-6) (< xa xb) (< ya yb))
     )
  )
)

(defun c:RenumeroteazaMarciGrinzi ( / *error* rmk:doc ss i ent edata etype lay grpid group_map grp elems el
                                       chenare_armatura chenare_etrieri chenare_sectiuni
                                       marca_ent marca_pt diam_txt lung_txt txt_continut are_etr_cuvant
                                       diam_baza lung_val g bare_toate ch poly_pts
                                       urmator harta_numere cheie existing nr raport old_txt
                                       definitii_etrier def dg dpt ddiam dlung txt2 el2
                                       harta_eticheta_nou harta_ent_nou
                                       marci_in_chenar_sectiuni val_originala
                                       sectiuni_perechi sv sp txt3 lay3 grpid3 grp3 val3 pt3 toate_etichete_nn are_marci_de_corectat
                                       toate_textele chei_chenare nume_ch k ordine_txt sect_ch nr_sect t1
                                       eticheta gasit_nr indicator_ent nr_sarite nr_definitii
                                       g_din_chenar valori_gasite valori_unice v r
                                       harta_tag tg marci_legate nelegate are_buc_centura numerotate descr )

  (princ "\nSelectati toata zona de renumerotat (grinzi - chenare armatura, chenare etrieri, chenare sectiuni etrieri, tot): ")
  (setq ss (ssget))
  (defun *error* (msg)
    (if rmk:doc (vla-endundomark rmk:doc))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*,*EXIT*")))
      (princ (strcat "\nEroare: " msg)))
    (princ))
  (if (not ss) (exit))
  ;; toata renumerotarea se anuleaza cu un singur U
  (setq rmk:doc (vla-get-activedocument (vlax-get-acad-object)))
  (vla-endundomark rmk:doc)
  (vla-startundomark rmk:doc)

  ;; --- PASUL 1: colectam tot ce ne trebuie, intr-o singura trecere ---
  (setq group_map nil chenare_armatura nil chenare_etrieri nil chenare_sectiuni nil marci_in_chenar_sectiuni nil sectiuni_perechi nil toate_etichete_nn nil are_marci_de_corectat nil toate_textele nil)
  (setq i 0)
  (repeat (sslength ss)
    (setq ent (ssname ss i))
    (setq edata (entget ent))
    (setq etype (cdr (assoc 0 edata)))
    (setq lay (strcase (cdr (assoc 8 edata))))

    (cond
      ((and (= etype "LWPOLYLINE") (= lay "CHENAR PENTRU ARMATURA")) (setq chenare_armatura (cons ent chenare_armatura)))
      ((and (= etype "LWPOLYLINE") (= lay "CHENAR ETRIERI")) (setq chenare_etrieri (cons ent chenare_etrieri)))
      ((and (= etype "LWPOLYLINE") (= lay "CHENAR PENTRU SECTIUNI ETRIERI")) (setq chenare_sectiuni (cons ent chenare_sectiuni)))
    )
    (if (= lay "MARCI OTEL DE CORECTAT") (setq are_marci_de_corectat t))
    ;; marcile legate (cu XDATA GBMARCA)
    (if (and (= etype "TEXT") (= lay "OTEL MARCA") (setq tg (grn-tag ent)))
      (setq marci_legate (cons (list ent tg) marci_legate)))

    ;; toate textele (pentru numele grinzilor din Chenar pentru armatura)
    (if (member etype '("TEXT" "MTEXT"))
      (setq toate_textele (cons (list (cdr (assoc 10 edata)) (cdr (assoc 1 edata))) toate_textele)))
    (if (= etype "TEXT")
      (progn
        ;; etichetele N-N pot fi NEGRUPATE - le colectam separat, direct,
        ;; indiferent de grup
        (if (and (= lay "SECTIUNI GRINZI") (vl-string-search "-" (cdr (assoc 1 edata))))
          (setq toate_etichete_nn (cons (list (cdr (assoc 10 edata)) (cdr (assoc 1 edata))) toate_etichete_nn))
        )
        (setq grpid (grn-get-group-id ent))
        (if grpid
          (progn
            (setq el (list lay ent (cdr (assoc 10 edata)) (cdr (assoc 1 edata))))
            (if (assoc grpid group_map)
              (setq group_map (subst (append (assoc grpid group_map) (list el)) (assoc grpid group_map) group_map))
              (setq group_map (cons (list grpid el) group_map))
            )
          )
        )
      )
    )
    (setq i (1+ i))
  )

  (if (not chenare_armatura)
    (progn (princ "\n[ATENTIE] Niciun \"Chenar pentru armatura\" gasit in selectie.") (exit))
  )

  ;; --- construim, din group_map, listele de grupuri utile:
  ;;     bare_toate = grupuri complete marca+diametru(fara pas)+lungime
  ;;     definitii_etrier = grupuri complete marca+diametru(cu pas)+lungime+"etr"
  ;;     marci_in_chenar_sectiuni = TOATE textele Otel marca, indiferent
  ;;       daca fac parte dintr-un grup complet sau sunt doar indicatoare
  (setq bare_toate nil definitii_etrier nil)
  (foreach grp group_map
    (setq elems (cdr grp))
    (setq marca_ent nil marca_pt nil diam_txt nil lung_txt nil are_etr_cuvant nil are_buc_centura nil)
    (foreach el elems
      (cond
        ((= (car el) "OTEL MARCA") (setq marca_ent (nth 1 el) marca_pt (nth 2 el)))
        ((= (car el) "OTEL DIAMETRU") (setq diam_txt (nth 3 el)))
        ((= (car el) "OTEL LUNGIME") (setq lung_txt (nth 3 el)))
        ((= (car el) "BUCATI ETRIERI CENTURI") (setq are_buc_centura t))
      )
      (setq txt_continut (strcase (nth 3 el)))
      (if (vl-string-search "ETR" txt_continut) (setq are_etr_cuvant t))
    )
    (if (and marca_ent diam_txt lung_txt)
      (progn
        (setq diam_baza (grn-extrage-diam-baza diam_txt))
        (setq lung_val (grn-extrage-lungime lung_txt))
        (if (grn-are-pas diam_txt)
          (if are_etr_cuvant
            (setq definitii_etrier (cons (list marca_ent marca_pt diam_baza lung_val (rmk:forma-etrier (car grp))) definitii_etrier))
          )
          (setq bare_toate (cons (list marca_ent marca_pt diam_baza lung_val are_buc_centura) bare_toate))
        )
      )
    )
  )

  ;; toate textele Otel marca (definitii + indicatoare simple marca+cerc)
  (setq marci_in_chenar_sectiuni nil)
  (foreach grp group_map
    (setq elems (cdr grp))
    (foreach el elems
      (if (= (car el) "OTEL MARCA")
        (setq marci_in_chenar_sectiuni (cons (list (nth 1 el) (nth 2 el) (nth 3 el)) marci_in_chenar_sectiuni))
      )
    )
  )

  ;; perechile "N si N" de pe layerul Sectiuni grinzi (grupuri text+linie)
  (setq sectiuni_perechi nil)
  (foreach grp group_map
    (setq elems (cdr grp))
    (foreach el elems
      (if (= (car el) "SECTIUNI GRINZI")
        (setq sectiuni_perechi (cons (list (nth 1 el) (nth 2 el) (nth 3 el)) sectiuni_perechi))
      )
    )
  )

  (if (not bare_toate)
    (princ "\n[ATENTIE] Nicio bara lunga (marca+diametru fara pas+lungime) gasita.")
  )
  (if (not definitii_etrier)
    (princ "\n[ATENTIE] Nicio definitie de etrier (marca+diametru cu pas+lungime+cuvantul etr) gasita.")
  )

  (setq harta_numere nil urmator 1 raport nil)

  ;; --- ETAPA 1: bare lungi, chenar cu chenar, dupa numele grinzii ---
  ;; ordinea chenarelor dupa numele grinzii: G.. (si GP..), B.., apoi
  ;; cele fara nume; la egalitate, de la stanga la dreapta
  (setq chei_chenare nil ordine_txt nil)
  (foreach ch chenare_armatura
    (setq poly_pts (grn-obtine-puncte-polilinie ch) nume_ch nil)
    (foreach t1 toate_textele
      (if (and (setq k (rmk:nume-grinda (cadr t1)))
               (grn-punct-in-poligon (car t1) poly_pts)
               (or (null (car nume_ch)) (rmk:cheie< k (car nume_ch))))
        (setq nume_ch (list k (rmk:text-curat (cadr t1))))))
    (setq chei_chenare
      (cons (cons ch (append (if nume_ch (car nume_ch) (list 2 0 0))
                             (list (apply 'min (mapcar 'car poly_pts)))))
            chei_chenare))
    (setq ordine_txt (cons (cons ch (if nume_ch (cadr nume_ch) "fara_nume")) ordine_txt)))
  (setq chenare_armatura
    (rmk:sort chenare_armatura
      '(lambda (a b) (rmk:cheie< (cdr (assoc a chei_chenare)) (cdr (assoc b chei_chenare))))))
  (princ "\nOrdinea chenarelor: ")
  (foreach ch chenare_armatura
    (princ (strcat (rmk:primul-cuvant (cdr (assoc ch ordine_txt))) "  ")))
  (foreach ch chenare_armatura
    (setq poly_pts (grn-obtine-puncte-polilinie ch))
    (setq g_din_chenar nil)
    (foreach g bare_toate
      (if (grn-punct-in-poligon (cadr g) poly_pts) (setq g_din_chenar (cons g g_din_chenar)))
    )
    (foreach g (grn-sorteaza-bare g_din_chenar)
      (setq diam_baza (nth 2 g) lung_val (nth 3 g))
      (setq cheie (grn-cheie diam_baza lung_val))
      (setq existing (assoc cheie harta_numere))
      (if existing
        (setq nr (cdr existing))
        (progn
          (setq nr urmator)
          (setq harta_numere (cons (cons cheie nr) harta_numere))
          (setq urmator (1+ urmator))
        )
      )
      (setq marca_ent (nth 0 g))
      (setq numerotate (cons marca_ent numerotate))
      (setq old_txt (cdr (assoc 1 (entget marca_ent))))
      (setq raport (cons (strcat old_txt " -> " (itoa nr) " (bara)") raport))
      (entmod (subst (cons 1 (itoa nr)) (assoc 1 (entget marca_ent)) (entget marca_ent)))
    )
  )
  ;; barele drepte ale centurilor (grup cu "... buc." pe Bucati etrieri
  ;; centuri) care nu sunt in niciun Chenar pentru armatura: le numerotam si
  ;; pe ele, dupa cele din chenare - extrasul le numara oricum
  (foreach g (grn-sorteaza-bare (vl-remove-if-not '(lambda (g) (and (nth 4 g) (not (member (car g) numerotate)))) bare_toate))
    (setq cheie (grn-cheie (nth 2 g) (nth 3 g)) existing (assoc cheie harta_numere))
    (if existing
      (setq nr (cdr existing))
      (setq nr urmator harta_numere (cons (cons cheie nr) harta_numere) urmator (1+ urmator)))
    (setq marca_ent (nth 0 g) numerotate (cons marca_ent numerotate))
    (setq old_txt (cdr (assoc 1 (entget marca_ent))))
    (setq raport (cons (strcat old_txt " -> " (itoa nr) " (bara centura, in afara chenarelor)") raport))
    (entmod (subst (cons 1 (itoa nr)) (assoc 1 (entget marca_ent)) (entget marca_ent))))

  ;; --- ETAPA 2: definitii de etrier, dupa sectiune ---
  ;; ordinea etrierilor dupa sectiune: 1-1, 2-2 ...; cei care nu sunt in
  ;; niciun Chenar pentru sectiuni etrieri (ex etrierii centurilor) la urma
  (setq chei_chenare nil)
  (foreach def definitii_etrier
    (setq nr_sect nil sect_ch nil)
    (foreach ch chenare_sectiuni
      (if (and (not sect_ch) (grn-punct-in-poligon (cadr def) (setq poly_pts (grn-obtine-puncte-polilinie ch))))
        (progn
          (setq sect_ch ch)
          (foreach txt2 toate_etichete_nn
            (if (and (not nr_sect) (grn-punct-in-poligon (car txt2) poly_pts))
              (setq nr_sect (atoi (vl-string-trim " " (cadr txt2)))))))))
    (setq chei_chenare
      (cons (cons (car def)
                  (list (cond ((and nr_sect (> nr_sect 0)) 0) (sect_ch 1) (T 2))
                        (if nr_sect nr_sect 0)
                        (car (cadr def))
                        (- (cadr (cadr def)))))
            chei_chenare)))
  (setq definitii_etrier
    (rmk:sort definitii_etrier
      '(lambda (a b) (rmk:cheie< (cdr (assoc (car a) chei_chenare)) (cdr (assoc (car b) chei_chenare))))))
  (setq harta_eticheta_nou nil nr_definitii 0)
  (foreach def definitii_etrier
    (setq nr_definitii (1+ nr_definitii))
    (setq marca_ent (nth 0 def) marca_pt (nth 1 def) diam_baza (nth 2 def) lung_val (nth 3 def))
    (setq old_txt (cdr (assoc 1 (entget marca_ent))))
    ;; etrierul se potriveste dupa diametru+lungime+FORMA (ramurile);
    ;; "|E" ca un etrier sa nu ia niciodata numarul unei bare drepte
    (setq cheie (strcat (grn-cheie diam_baza lung_val) "|E" (nth 4 def)))
    (setq existing (assoc cheie harta_numere))
    (if existing
      (setq nr (cdr existing))
      (progn
        (setq nr urmator)
        (setq harta_numere (cons (cons cheie nr) harta_numere))
        (setq urmator (1+ urmator))
      )
    )
    ;; retinem legatura: identitatea exacta a definitiei -> numarul nou
    (setq harta_ent_nou (cons (cons marca_ent nr) harta_ent_nou))
    (setq raport (cons (strcat old_txt " -> " (itoa nr) " (definitie etrier" (if (/= (nth 4 def) "") (strcat ", ramuri " (nth 4 def)) "") ")") raport))
    (entmod (subst (cons 1 (itoa nr)) (assoc 1 (entget marca_ent)) (entget marca_ent)))
  )

  ;; --- 2: pentru fiecare poligon "Chenar pentru sectiuni etrieri",
  ;; gasim DEFINITIA care cade geometric in el (ar trebui sa fie una
  ;; singura), luam numarul EI (deja atribuit, prin identitatea exacta a
  ;; entitatii - nu prin text, ca sa nu conteze daca mai multe zone au
  ;; intamplator acelasi text original, ex "x" la toate ca test). Cu acel
  ;; numar: (a) actualizam toate indicatoarele (Otel marca) gasite in
  ;; ACELASI poligon, si (b) retinem toate etichetele N-N gasite tot in
  ;; acel poligon -> numarul respectiv ---
  (foreach ch chenare_sectiuni
    (setq poly_pts (grn-obtine-puncte-polilinie ch))
    (setq gasit_nr nil)
    (foreach def definitii_etrier
      (if (and (not gasit_nr) (grn-punct-in-poligon (cadr def) poly_pts))
        (setq gasit_nr (cdr (assoc (car def) harta_ent_nou)))
      )
    )
    (if gasit_nr
      (progn
        (foreach sv marci_in_chenar_sectiuni
          (if (and (grn-punct-in-poligon (cadr sv) poly_pts) (not (assoc (car sv) marci_legate)))
            (progn
              (setq marca_ent (car sv))
              (setq old_txt (cdr (assoc 1 (entget marca_ent))))
              (if (/= old_txt (itoa gasit_nr))
                (progn
                  (setq raport (cons (strcat old_txt " -> " (itoa gasit_nr) " (indicator sectiuni etrieri)") raport))
                  (entmod (subst (cons 1 (itoa gasit_nr)) (assoc 1 (entget marca_ent)) (entget marca_ent)))
                )
              )
            )
          )
        )
        (foreach txt2 toate_etichete_nn
          (if (grn-punct-in-poligon (car txt2) poly_pts)
            (setq harta_eticheta_nou (cons (cons (strcase (vl-string-trim " " (cadr txt2))) gasit_nr) harta_eticheta_nou))
          )
        )
      )
    )
  )

  ;; --- ETAPA 3: la fiecare "Chenar etrieri", gasim perechea N+N, formam
  ;; eticheta N-N, cautam numarul nou, il punem la indicatorul din acest
  ;; chenar (Otel marca gasit in interiorul lui) ---
  (foreach ch chenare_etrieri
    (setq poly_pts (grn-obtine-puncte-polilinie ch))
    ;; grupam perechile text+linie de pe Sectiuni grinzi dupa VALOARE,
    ;; doar cele din interiorul acestui chenar
    (setq valori_gasite nil)
    (foreach sp sectiuni_perechi
      (if (grn-punct-in-poligon (cadr sp) poly_pts)
        (setq valori_gasite (cons (caddr sp) valori_gasite))
      )
    )
    ;; pentru fiecare valoare care apare de cel putin 2 ori, formam eticheta
    (setq valori_unice nil)
    (foreach v valori_gasite (if (not (member v valori_unice)) (setq valori_unice (cons v valori_unice))))
    (foreach v valori_unice
      (if (>= (length (vl-remove-if-not '(lambda (x) (= x v)) valori_gasite)) 2)
        (progn
          (setq eticheta (strcat (strcase (vl-string-trim " " v)) "-" (strcase (vl-string-trim " " v))))
          (setq existing (assoc eticheta harta_eticheta_nou))
          (if existing
            (progn
              (setq nr (cdr existing))
              ;; gasim indicatorul (Otel marca) din interiorul acestui Chenar etrieri
              (foreach sv marci_in_chenar_sectiuni
                (if (grn-punct-in-poligon (cadr sv) poly_pts)
                  (progn
                    (setq marca_ent (car sv))
                    (setq old_txt (cdr (assoc 1 (entget marca_ent))))
                    (if (/= old_txt (itoa nr))
                      (progn
                        (setq raport (cons (strcat old_txt " -> " (itoa nr) " (indicator la grinda, eticheta " eticheta ")") raport))
                        (entmod (subst (cons 1 (itoa nr)) (assoc 1 (entget marca_ent)) (entget marca_ent)))
                      )
                    )
                  )
                )
              )
            )
            (princ (strcat "\n[ATENTIE] Eticheta " eticheta " gasita la o grinda, dar nu am gasit-o in niciun Chenar pentru sectiuni etrieri - etrierul nu a fost renumerotat acolo."))
          )
        )
      )
    )
  )

  ;; --- ETAPA 4: marcile legate. Legatura -> numarul definitiei (bara
  ;; lunga sau etrier) care o poarta; apoi toate marcile cu acea legatura ---
  (setq harta_tag nil nelegate nil)
  (foreach ml marci_legate
    (if (and (not (assoc (cadr ml) harta_tag))
             (or (vl-some '(lambda (d) (eq (car d) (car ml))) definitii_etrier)
                 (vl-some '(lambda (d) (eq (car d) (car ml))) bare_toate))
             (wcmatch (cdr (assoc 1 (entget (car ml)))) "#*"))
      (setq harta_tag (cons (cons (cadr ml) (cdr (assoc 1 (entget (car ml))))) harta_tag))))
  (foreach ml marci_legate
    (setq existing (assoc (cadr ml) harta_tag) old_txt (cdr (assoc 1 (entget (car ml)))))
    (cond
      ((null existing)
       (if (not (member (cadr ml) nelegate)) (setq nelegate (cons (cadr ml) nelegate))))
      ((/= old_txt (cdr existing))
       (setq raport (cons (strcat old_txt " -> " (cdr existing) " (marca legata " (cadr ml) ")") raport))
       (entmod (subst (cons 1 (cdr existing)) (assoc 1 (entget (car ml))) (entget (car ml)))))))
  ;; descrierea unei legaturi, pentru mesaje: "C300x250" -> etrierul centurii 30x25
  (defun grn-descr-tag (tg / p)
    (cond
      ((wcmatch tg "CB*")
       (setq p (vl-string-search "X" (strcase tg)))
       (strcat "barele drepte ale centurilor " (substr tg 3 (- p 2)) "%%C" (substr tg (+ p 2))
               " (grupul cu L=12.00m de sub detaliile centurilor)"))
      ((wcmatch tg "C*")
       (setq p (vl-string-search "X" (strcase tg)))
       (strcat "etrierul centurii " (rtos (/ (atof (substr tg 2 (1- p))) 10.0) 2 0) "x" (rtos (/ (atof (substr tg (+ p 2))) 10.0) 2 0)
               " (etrierul desfasurat din detaliul centurii)"))
      (T tg)))
  (foreach tg nelegate
    (princ (strcat "\n[ATENTIE] Marcile care arata " (grn-descr-tag tg) " au ramas nerenumerotate: definitia lor nu e in"
                   " selectie, sau nu are inca numar.")))

  (princ (strcat "\n[OK] Renumerotare terminata - " (itoa nr_definitii) " definitii de etrier, " (itoa (1- urmator)) " numere distincte folosite in total."))
  (foreach r (reverse raport) (princ (strcat "\n  " r)))
  (princ)
  (cond
    (nelegate
     (alert (strcat "Unele marci au ramas nerenumerotate, pentru ca nu am gasit in selectie elementul la care se refera:\n\n"
                    (apply 'strcat (mapcar '(lambda (x) (strcat "  - marcile care arata " (grn-descr-tag x) "\n")) nelegate))
                    "\nSelectati si detaliile centurilor de la capatul randului de desfasurate (cu etrierii si bara de 12 m)"
                    " si rulati din nou.")))
    (are_marci_de_corectat
     (alert "Verifica marcile de modificat manual in functie de etrierii din centuri.")))
  (vla-endundomark rmk:doc)
  (princ)
)

(princ "\nScrieti 'RenumeroteazaMarciGrinzi' pentru a renumerota automat marcile de armare grinzi (bare lungi + etrieri).")
(princ)
