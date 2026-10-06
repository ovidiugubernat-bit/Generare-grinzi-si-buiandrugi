;; Revizie:
;;  - handler-ul de erori e local comenzii (nu mai ramane schimbat global) si
;;    nu mai afiseaza "[EROARE]" la ESC sau la iesirea normala
;;  - tabelul Excel lipit: punctul nu mai e mutat de OSNAP, iar daca lipirea
;;    nu reuseste, SCALE nu se mai aplica din greseala ultimului obiect din
;;    desen (sau cand nu s-a ales punctul)
;; =========================================================================
;; EXTRAS DE ARMARE - v5: motor de calcul comun + iesire tabel AutoCAD SI Excel
;; Compatibil AutoCAD 2024
;; =========================================================================

;; =========================================================================
;; COPIERE SIGURA DIN EXCEL IN CLIPBOARD
;; Uneori clipboard-ul e tinut ocupat de alt program si Excel nu poate
;; copia ("Clipboard error ... in use by another application"); atunci
;; PASTECLIP nu lipeste nimic. Aici: punem un text-martor in clipboard,
;; copiem din Excel si verificam ca in clipboard a ajuns tabelul (nu mai e
;; martorul). Daca nu, asteptam putin si reincercam, de cateva ori.
;; =========================================================================
(defun xlc:clipboard ( / html cb r)
  (setq r (vl-catch-all-apply
            '(lambda ( / tx)
               (setq html (vlax-create-object "htmlfile"))
               (setq cb (vlax-get (vlax-get html 'parentWindow) 'clipboardData))
               (setq tx (vlax-invoke cb 'getData "Text"))
               tx)))
  (if html (vl-catch-all-apply 'vlax-release-object (list html)))
  (if (= (type r) 'STR) r "")
)

(defun xlc:pune-in-clipboard (s / html)
  (vl-catch-all-apply
    '(lambda ()
       (setq html (vlax-create-object "htmlfile"))
       (vlax-invoke (vlax-get (vlax-get html 'parentWindow) 'clipboardData) 'setData "Text" s)))
  (if html (vl-catch-all-apply 'vlax-release-object (list html)))
)

;; xlApp = aplicatia Excel (poate fi nil), rng = domeniul de copiat
;; intoarce T daca tabelul a ajuns in clipboard
(defun xlc:copiaza (xlApp rng / martor tx i ok)
  (setq martor (strcat "martor-" (rtos (getvar "CDATE") 2 8)) i 0)
  (xlc:pune-in-clipboard martor)
  ;; daca nici martorul nu se poate citi inapoi, verificarea nu e posibila:
  ;; copiem simplu (de doua ori, cu o pauza) si mergem mai departe
  (if (/= (xlc:clipboard) martor)
    (progn
      (vl-catch-all-apply 'vlax-invoke-method (list rng 'Copy))
      (vl-cmdf "_.DELAY" 300)
      (vl-catch-all-apply 'vlax-invoke-method (list rng 'Copy))
      (setq ok T i 99)))
  (while (and (not ok) (< i 8))
    (if xlApp (vl-catch-all-apply 'vlax-put-property (list xlApp "CutCopyMode" :vlax-false)))
    (vl-catch-all-apply 'vlax-invoke-method (list rng 'Copy))
    (setq tx (xlc:clipboard))
    (setq ok (and (/= tx "") (/= tx martor)))
    (if (not ok)
      (progn
        (setq i (1+ i))
        (princ (strcat "\nClipboard ocupat, reincerc (" (itoa i) ")..."))
        (vl-cmdf "_.DELAY" 400))))
  (if (not ok)
    (alert (strcat "Excel nu a putut pune tabelul in clipboard (clipboard ocupat de alt program)."
                   "\nRulati comanda inca o data.")))
  ok
)

(defun grz-curata-numar (str / rez idx c)
  (setq str (strcase str) rez "" idx 1)
  (while (<= idx (strlen str))
    (setq c (substr str idx 1))
    (if (or (and (>= c "0") (<= c "9")) (= c ".")) (setq rez (strcat rez c)))
    (setq idx (1+ idx))
  )
  rez
)

;; asigura ca layerul "Tabele" exista (il creeaza daca lipseste), ca
;; tabelele generate sa mearga mereu acolo, indiferent de layerul activ
(defun grz-asigura-layer-tabele ( / doc layers )
  (if (not (tblsearch "LAYER" "Tabele"))
    (progn
      (setq doc (vla-get-activedocument (vlax-get-acad-object)))
      (setq layers (vla-get-layers doc))
      (vl-catch-all-apply 'vla-add (list layers "Tabele"))
    )
  )
)

(defun grz-extrage-diametru-etrier (str / pos_slash sub_str rez idx c)
  (setq str (strcase str))
  (setq pos_slash (vl-string-search "/" str))
  (if pos_slash
    (progn
      (setq sub_str (substr str 1 pos_slash))
      (setq rez "" idx 1)
      (while (<= idx (strlen sub_str))
        (setq c (substr sub_str idx 1))
        (if (and (>= c "0") (<= c "9")) (setq rez (strcat rez c)))
        (setq idx (1+ idx))
      )
      (if (/= rez "") rez "8")
    )
    (grz-curata-numar str)
  )
)

;; distinge etrier/centura de bara dreapta prin STRUCTURA, nu prin cuvant-cheie
;; (ETR/AGR/etc, care se poate schimba oricand): daca imediat dupa cifrele
;; diametrului urmeaza "/" (pasul, ex "%%C8/10/15"), e etrier/centura. Daca
;; nu urmeaza nimic de genul (doar diametrul simplu, ex "4%%C12"), e bara
;; dreapta. Functioneaza indiferent de eticheta text folosita in fata.
(defun grz-are-pas (str / pos idx_len)
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

(defun grz-analizeaza-diametru-bare (str / pos nr_bare dia idx_skip)
  (setq str (strcase str))
  (cond
    ((vl-string-search "%%C" str) (setq pos (vl-string-search "%%C" str) idx_skip 4))
    ((vl-string-search (chr 216) str)   (setq pos (vl-string-search (chr 216) str) idx_skip 2))
    ((vl-string-search "O" str)   (setq pos (vl-string-search "O" str) idx_skip 1))
    (t (setq pos nil))
  )
  (if pos
    (progn
      (setq nr_bare (substr str 1 pos))
      (setq dia (substr str (+ pos idx_skip)))
      (setq nr_bare (grz-curata-numar nr_bare))
      (setq dia (grz-curata-numar dia))
      (if (= nr_bare "") (setq nr_bare "1"))
      (cons (atoi nr_bare) dia)
    )
    (cons 1 (grz-curata-numar str))
  )
)

(defun grz-extrage-buc (str / pos idx num-str)
  (setq str (strcase str))
  (setq pos (vl-string-search "BUC." str))
  (if pos
    (progn
      (setq idx (1- pos) num-str "")
      (while (and (>= idx 0) (= (substr str (1+ idx) 1) " ")) (setq idx (1- idx)))
      (while (and (>= idx 0) (wcmatch (substr str (1+ idx) 1) "[0-9]"))
        (setq num-str (strcat (substr str (1+ idx) 1) num-str))
        (setq idx (1- idx))
      )
      (if (/= num-str "") (atoi num-str) 1)
    )
    1
  )
)

(defun grz-obtine-puncte-polilinie (ent / elist pts)
  (setq elist (entget ent) pts nil)
  (foreach item elist
    (if (= (car item) 10) (setq pts (cons (list (nth 1 item) (nth 2 item)) pts)))
  )
  (reverse pts)
)

(defun grz-punct-in-poligon (p pts / x y inside i j p1 p2 x1 y1 x2 y2)
  (setq x (car p) y (cadr p) inside nil i 0 j (1- (length pts)))
  (while (< i (length pts))
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

;; rotunjeste in sus la cel mai apropiat multiplu de 5 (ca la Excel,
;; CEILING(x,5))
(defun grz-rotunjeste5 (x / n nf)
  (setq n (/ x 5.0))
  (setq nf (fix n))
  (if (> (- n nf) 1e-9) (setq nf (1+ nf)))
  (* nf 5.0)
)

;; formateaza un numar cu EXACT n zecimale (cu zerouri la coada) - rtos
;; nu garanteaza mereu zecimale fixe, asa ca facem asta manual, sigur
(defun grz-fixn (x n / neg mult xi ip fp fp_str)
  (setq neg (< x 0) x (abs x))
  (setq mult (expt 10.0 n))
  (setq xi (fix (+ (* x mult) 0.5)))
  (setq ip (/ xi (fix mult)))
  (setq fp (rem xi (fix mult)))
  (setq fp_str (itoa fp))
  (while (< (strlen fp_str) n) (setq fp_str (strcat "0" fp_str)))
  (strcat (if neg "-" "") (itoa ip) "." fp_str)
)

(defun grz-afla-greutate (dia / d_int)
  (setq d_int (atoi dia))
  (cond
    ((= d_int 6)  0.222) ((= d_int 8)  0.395) ((= d_int 10) 0.617)
    ((= d_int 12) 0.888) ((= d_int 14) 1.210) ((= d_int 16) 1.580)
    ((= d_int 18) 1.990) ((= d_int 20) 2.470) ((= d_int 22) 2.980)
    ((= d_int 25) 3.850) (t 0.0)
  )
)

;; Centrul real (vizual) al unui text, prin bounding-box - functioneaza
;; corect indiferent de justificare (stanga, centru, mijloc etc), spre
;; deosebire de punctul brut de inseratie (DXF 10), care poate fi altundeva
;; pentru texte cu justificare centrata/mijloc.
(defun grz-centru-calc (obj / minp maxp minl maxl)
  (vla-getboundingbox obj 'minp 'maxp)
  (setq minl (vlax-safearray->list (vlax-variant-value minp)))
  (setq maxl (vlax-safearray->list (vlax-variant-value maxp)))
  (list (/ (+ (car minl) (car maxl)) 2.0) (/ (+ (cadr minl) (cadr maxl)) 2.0))
)

;; La fel ca mai sus, dar daca bounding-box-ul esueaza pentru vreo entitate
;; (se intampla rar, la unele MTEXT-uri), cade pe punctul de rezerva
;; (punctul brut de inserare DXF 10), fara sa opreasca tot calculul.
(defun grz-centru-obiect (obj pt_fallback / res)
  (setq res (vl-catch-all-apply 'grz-centru-calc (list obj)))
  (if (vl-catch-all-error-p res) pt_fallback res)
)

;; Punctul REAL (vizual) al unui TEXT/MTEXT. Pentru TEXT cu justificare
;; (centru, mijloc etc), conform standardului DXF, punctul adevarat e in
;; campul 11 (al doilea punct de aliniere), nu in campul 10 (care poate fi
;; vechi/nesetat pentru text justificat). Daca nu e cazul, cade pe
;; bounding-box (mai sigur decat campul 10 brut).
(defun grz-punct-text (edata obj / p10 p11 j72 j73 etype)
  (setq etype (cdr (assoc 0 edata)))
  (setq p10 (cdr (assoc 10 edata)))
  (setq p10 (if p10 (list (car p10) (cadr p10)) (list 0.0 0.0)))
  (setq p11 (cdr (assoc 11 edata)))
  (setq j72 (cdr (assoc 72 edata)))
  (setq j73 (cdr (assoc 73 edata)))
  (if (and (= etype "TEXT") p11
           (or (/= (car p11) 0.0) (/= (cadr p11) 0.0))
           (or (and j72 (/= j72 0)) (and j73 (/= j73 0))))
    (list (car p11) (cadr p11))
    (grz-centru-obiect obj p10)
  )
)

(defun grz-dist2 (p1 p2 / dx dy)
  (setq dx (- (car p1) (car p2)) dy (- (cadr p1) (cadr p2)))
  (+ (* dx dx) (* dy dy))
)

;; Gaseste, dintr-o lista de (text punct), elementul cel mai apropiat de pt.
;; Nu foloseste prag - e menita sa caute DOAR in interiorul unui singur grup
;; AutoCAD, unde toate elementele sunt deja legate logic intre ele.
(defun grz-cel-mai-apropiat (pt lista / best_d best_item d it)
  (setq best_d nil best_item nil)
  (foreach it lista
    (setq d (grz-dist2 pt (cadr it)))
    (if (or (not best_d) (< d best_d)) (setq best_d d best_item it))
  )
  best_item
)

(defun grz-get-group-id (ent / elist item grp)
  (setq elist (entget ent) grp nil)
  (foreach item elist
    (if (= (car item) 330)
      (if (= (cdr (assoc 0 (entget (cdr item)))) "GROUP") (setq grp (cdr item)))
    )
  )
  grp
)

;; TOATE grupurile din care face parte o entitate (o entitate poate fi in
;; mai multe grupuri, ex dupa copieri sau regrupari)
(defun grz-get-group-ids (ent / r)
  (foreach item (entget ent)
    (if (and (= (car item) 330) (= (cdr (assoc 0 (entget (cdr item)))) "GROUP"))
      (setq r (cons (cdr item) r))))
  r
)

;; textele unui grup, direct din grup (nu din selectie), in forma
;; (layer text punct entitate) - ca in group_map
(defun grz-elemente-grup (grpid / ed r)
  (foreach it (entget grpid)
    (if (and (= (car it) 340)
             (setq ed (entget (cdr it)))
             (member (cdr (assoc 0 ed)) '("TEXT" "MTEXT")))
      (setq r (cons (list (strcase (cdr (assoc 8 ed)))
                          (vla-get-textstring (vlax-ename->vla-object (cdr it)))
                          (grz-punct-text ed (vlax-ename->vla-object (cdr it)))
                          (cdr it))
                    r))))
  (reverse r)
)

;; are grupul (lista de elemente) marca + diametru + lungime?
(defun grz-grup-complet-p (elems)
  (and (assoc "OTEL MARCA" elems) (assoc "OTEL DIAMETRU" elems) (assoc "OTEL LUNGIME" elems))
)

;; Construieste o lista globala marca -> (diametru . lungime) pentru ETRIERI.
;; Cauta grupurile AutoCAD; in fiecare grup, ia toate textele de tip
;; OTEL MARCA, OTEL DIAMETRU (doar cele cu "ETR") si OTEL LUNGIME. Daca un
;; grup contine MAI MULTE seturi (ex: dupa o copiere), fiecare marca din
;; grup e asociata cu diametrul/lungimea cele mai apropiate DIN ACELASI GRUP
;; - niciodata cu ceva din alt grup, deci fara riscul de a lua o bara gresita.
(defun grz-construieste-definitii-etrier (grp_map / grp elems el marci diam lung mi mval dn ln d_val l_val etr_defs existing)
  (setq etr_defs nil)
  (foreach grp grp_map
    (setq elems (cdr grp) marci nil diam nil lung nil)
    (foreach el elems
      (cond
        ((= (car el) "OTEL MARCA") (setq marci (cons (list (cadr el) (caddr el) (cadddr el)) marci)))
        ((and (= (car el) "OTEL DIAMETRU") (grz-are-pas (cadr el)))
         (setq diam (cons (list (cadr el) (caddr el) (cadddr el)) diam)))
        ((= (car el) "OTEL LUNGIME") (setq lung (cons (list (cadr el) (caddr el) (cadddr el)) lung)))
      )
    )
    (if diam
      (foreach mi marci
        (setq mval (grz-curata-numar (car mi)))
        (setq dn (grz-cel-mai-apropiat (cadr mi) diam))
        (setq ln (grz-cel-mai-apropiat (cadr mi) lung))
        (if (and dn ln)
          (progn
            (setq d_val (grz-extrage-diametru-etrier (car dn)))
            (setq l_val (grz-curata-numar (car ln)))
            (setq existing (assoc mval etr_defs))
            (if existing
              (if (not (and (= (nth 1 existing) d_val) (= (nth 2 existing) l_val)))
                (setq *grz-warnings*
                  (cons (strcat "Marca etrier " mval ":  D=" (nth 1 existing) " / L=" (nth 2 existing)
                                 "   fata de   D=" d_val " / L=" l_val
                                 "  -> definitii DIFERITE gasite in desen pentru aceeasi marca de etrier!")
                        *grz-warnings*))
              )
              (setq etr_defs (cons (list mval d_val l_val (caddr mi) (caddr dn) (caddr ln)) etr_defs))
            )
          )
          (setq *grz-warnings*
            (cons (strcat "Marca etrier " mval " este intr-un grup care pare sa contina definitii de etrier, "
                           "dar nu am gasit in ACELASI grup si diametru(ETR) si lungime pereche pentru ea. Verificati grupul.")
                  *grz-warnings*))
        )
      )
    )
  )
  etr_defs
)

(defun grz-adauga-marca (m d l cnt lst ent / existing marca_key)
  (if ent (setq *grz-marca-entitati* (cons (cons m ent) *grz-marca-entitati*)))
  (setq existing (assoc m lst))
  (cond
    ((not existing) (cons (list m d l cnt) lst))
    ((and (= (nth 1 existing) d) (= (nth 2 existing) l))
     (subst (list m d l (+ (nth 3 existing) cnt)) existing lst)
    )
    (t
     (setq *grz-warnings*
       (cons (strcat "Marca " m ":  D=" (nth 1 existing) " / L=" (nth 2 existing)
                      "   fata de   D=" d " / L=" l
                      "  -> a doua a fost trecuta separat ca marca " m "*")
             *grz-warnings*))
     (setq marca_key (strcat m "*"))
     (if ent (setq *grz-marca-entitati* (cons (cons marca_key ent) *grz-marca-entitati*)))
     (setq existing (assoc marca_key lst))
     (if (and existing (= (nth 1 existing) d) (= (nth 2 existing) l))
       (subst (list marca_key d l (+ (nth 3 existing) cnt)) existing lst)
       (cons (list marca_key d l cnt) lst)
     )
    )
  )
)

;; =========================================================================
;; MOTORUL DE CALCUL - comun ambelor comenzi (tabel AutoCAD si Excel)
;; Foloseste GRUPURI AutoCAD ca sursa principala de asociere (sigur, nu
;; sare niciodata la o bara din alta parte a desenului). In interiorul unui
;; grup, daca sunt mai multe seturi marca/diametru/lungime, le distinge prin
;; apropiere DOAR intre ele, ca sa reziste la copieri care extind grupul.
;; Primeste un selection-set, returneaza sorted_list: ((marca diametru lungime total_buc) ...)
;; Populeaza *grz-warnings* (global) cu orice conflict gasit.
;; =========================================================================
(defun grz-calculeaza-lista ( ss / i ent edata lay txt obj pt pt_rezerva base_list sorted_list
                                    all_chenare_stalp all_chenare_etr all_stalpi_txt
                                    all_linii_etr all_marci_texte group_map grpid etr_definitii
                                    chenar poly_pts stalpi_buc s_txt_item
                                    grp elems el marci diam lung mi mval mpt dn ln
                                    in_etrier ch_etr2 bare_din_diam nr_bare d_final
                                    ch_etr etr_poly_pts linii_count marci_in_careu m_item val_m def_etr mc linii_gasite le
                                    grupuri_centuri buc_txt buc_manual
                                    all_buc_centuri grupuri_extra bc gid gelems gasit_grup )

  (setq base_list nil all_chenare_stalp nil all_chenare_etr nil all_stalpi_txt nil
        all_linii_etr nil all_marci_texte nil group_map nil all_buc_centuri nil)

  (setq i 0)
  (repeat (sslength ss)
    (setq ent (ssname ss i))
    (setq edata (entget ent))
    (setq lay (strcase (cdr (assoc 8 edata))))

    (cond
      ((= lay "CHENAR PENTRU ARMATURA") (setq all_chenare_stalp (cons ent all_chenare_stalp)))
      ((= lay "CHENAR ETRIERI")         (setq all_chenare_etr (cons ent all_chenare_etr)))
      ((= lay "OTEL ETRIERI")
       (setq pt (cdr (assoc 10 edata)))
       (if pt (setq all_linii_etr (cons (list (car pt) (cadr pt) ent) all_linii_etr))))
    )

    (if (member (cdr (assoc 0 edata)) '("TEXT" "MTEXT"))
      (progn
        (setq obj (vlax-ename->vla-object ent) txt (vla-get-textstring obj))
        (setq pt (grz-punct-text edata obj))

        (if (= lay "OTEL MARCA") (setq all_marci_texte (cons (list txt pt ent) all_marci_texte)))
        (if (and (= lay "BUCATI ELEMENT") (vl-string-search "BUC" (strcase txt)))
          (setq all_stalpi_txt (cons (list txt pt) all_stalpi_txt))
        )
        (if (= lay "BUCATI ETRIERI CENTURI")
          (setq all_buc_centuri (cons (list txt ent) all_buc_centuri)))

        (setq grpid (grz-get-group-id ent))
        (if grpid
          (if (assoc grpid group_map)
            (setq group_map (subst (append (assoc grpid group_map) (list (list lay txt pt ent))) (assoc grpid group_map) group_map))
            (setq group_map (cons (list grpid (list lay txt pt ent)) group_map))
          )
        )
      )
    )
    (setq i (1+ i))
  )

  ;; definitiile de etrier (marca -> diametru/lungime), pe baza de grup
  (setq etr_definitii (grz-construieste-definitii-etrier group_map))

  ;; ---- GRUPURI CU BUCATI INTRODUSE MANUAL (centuri) ----
  ;; grup cu marca+diametru+lungime, plus un text pe layerul
  ;; "BUCATI ETRIERI CENTURI" - acel numar e totalul direct (fara inmultire),
  ;; indiferent daca marca e o bara sau un etrier. Nu tine de niciun chenar.
  ;; textele "... buc." de centura al caror grup (cel gasit primul) nu are
  ;; marca+diametru+lungime: le cautam in CELELALTE grupuri din care fac
  ;; parte (ex dupa copiere textul a ramas si intr-un grup vechi). Daca nu
  ;; gasim niciun grup complet, avertizam - altfel s-ar pierde fara mesaj.
  (setq grupuri_extra nil)
  (foreach bc all_buc_centuri
    (setq gid (grz-get-group-id (cadr bc)))
    (if (not (and gid (grz-grup-complet-p (cdr (assoc gid group_map)))))
      (progn
        (setq gasit_grup nil)
        (foreach gid (grz-get-group-ids (cadr bc))
          (if (and (not gasit_grup)
                   (grz-grup-complet-p (setq gelems (grz-elemente-grup gid))))
            (setq gasit_grup (cons gid gelems))))
        (if gasit_grup
          ;; (nu de doua ori: nici daca grupul e deja numarat ca centura)
          (if (not (or (assoc (car gasit_grup) grupuri_extra)
                       (and (grz-grup-complet-p (cdr (assoc (car gasit_grup) group_map)))
                            (assoc "BUCATI ETRIERI CENTURI" (cdr (assoc (car gasit_grup) group_map))))))
            (setq grupuri_extra (cons gasit_grup grupuri_extra)))
          (setq *grz-warnings*
            (cons (strcat "Textul \"" (car bc) "\" (bucati centura) NU e in acelasi grup cu o marca+diametru+lungime"
                          " - NU a fost numarat! Refaceti grupul (marca, diametru, lungime si textul cu bucati).")
                  *grz-warnings*))))))

  (setq grupuri_centuri nil)
  (foreach grp (append group_map grupuri_extra)
    (setq elems (cdr grp) marci nil diam nil lung nil buc_txt nil)
    (foreach el elems
      (cond
        ((= (car el) "OTEL MARCA")    (setq marci (cons (list (cadr el) (caddr el) (cadddr el)) marci)))
        ((= (car el) "OTEL DIAMETRU") (setq diam (cons (list (cadr el) (caddr el) (cadddr el)) diam)))
        ((= (car el) "OTEL LUNGIME")  (setq lung (cons (list (cadr el) (caddr el) (cadddr el)) lung)))
        ((= (car el) "BUCATI ETRIERI CENTURI") (setq buc_txt (cadr el)))
      )
    )
    (if (and buc_txt marci diam lung)
      (progn
        (setq grupuri_centuri (cons (car grp) grupuri_centuri))
        (foreach mi marci
          (setq mval (grz-curata-numar (car mi)))
          (setq dn (grz-cel-mai-apropiat (cadr mi) diam))
          (setq ln (grz-cel-mai-apropiat (cadr mi) lung))
          (if (and dn ln)
            (progn
              (if (grz-are-pas (car dn))
                (setq d_final (grz-extrage-diametru-etrier (car dn)))
                (setq d_final (cdr (grz-analizeaza-diametru-bare (car dn))))
              )
              (setq buc_manual (grz-extrage-buc buc_txt))
              (setq base_list (grz-adauga-marca mval d_final (grz-curata-numar (car ln)) buc_manual base_list (caddr mi)))
              (setq *grz-marca-entitati* (cons (cons mval (caddr dn)) *grz-marca-entitati*))
              (setq *grz-marca-entitati* (cons (cons mval (caddr ln)) *grz-marca-entitati*))
              (setq *grz-warnings*
                (cons (strcat "Marca " mval ": " (itoa buc_manual) " buc introdus MANUAL (centura) - verificati daca e corect pentru acest proiect.")
                      *grz-warnings*))
            )
            (princ (strcat "\n[ATENTIE] Marca " mval " are text de bucati centura, dar nu am gasit diametru+lungime pereche in acelasi grup."))
          )
        )
      )
    )
  )

  (foreach chenar all_chenare_stalp
    (setq poly_pts (grz-obtine-puncte-polilinie chenar))
    (setq stalpi_buc 1)
    (foreach s_txt_item all_stalpi_txt
      (if (grz-punct-in-poligon (cadr s_txt_item) poly_pts)
        (setq stalpi_buc (grz-extrage-buc (car s_txt_item)))
      )
    )

    ;; ---- BARE LUNGI ----
    ;; parcurgem grupurile; in fiecare grup, marcile aflate in chenarul mare
    ;; (si NU intr-un chenar mic de etrieri) sunt asociate cu diametrul/
    ;; lungimea cele mai apropiate DIN ACELASI GRUP.
    (foreach grp group_map
      (setq elems (cdr grp) marci nil diam nil lung nil)
      (foreach el elems
        (cond
          ((= (car el) "OTEL MARCA") (setq marci (cons (list (cadr el) (caddr el) (cadddr el)) marci)))
          ((and (= (car el) "OTEL DIAMETRU") (not (grz-are-pas (cadr el))))
           (setq diam (cons (list (cadr el) (caddr el) (cadddr el)) diam)))
          ((= (car el) "OTEL LUNGIME") (setq lung (cons (list (cadr el) (caddr el) (cadddr el)) lung)))
        )
      )
      (if (and diam marci (not (member (car grp) grupuri_centuri)))
        (foreach mi marci
          (setq mpt (cadr mi))
          (if (grz-punct-in-poligon mpt poly_pts)
            (progn
              (setq in_etrier nil)
              (foreach ch_etr2 all_chenare_etr
                (setq etr_poly_pts (grz-obtine-puncte-polilinie ch_etr2))
                (if (and etr_poly_pts (grz-punct-in-poligon mpt etr_poly_pts)) (setq in_etrier t))
              )
              (if (not in_etrier)
                (progn
                  (setq mval (grz-curata-numar (car mi)))
                  (setq dn (grz-cel-mai-apropiat mpt diam))
                  (setq ln (grz-cel-mai-apropiat mpt lung))
                  (if (and dn ln)
                    (progn
                      (setq bare_din_diam (grz-analizeaza-diametru-bare (car dn)))
                      (setq nr_bare (car bare_din_diam))
                      (setq d_final (cdr bare_din_diam))
                      (setq base_list (grz-adauga-marca mval d_final (grz-curata-numar (car ln)) (* nr_bare stalpi_buc) base_list (caddr mi)))
                      (setq *grz-marca-entitati* (cons (cons mval (caddr dn)) *grz-marca-entitati*))
                      (setq *grz-marca-entitati* (cons (cons mval (caddr ln)) *grz-marca-entitati*))
                    )
                    (princ (strcat "\n[ATENTIE] Marca " mval " (bara) e in grup dar nu am gasit diametru+lungime pereche in acelasi grup."))
                  )
                )
              )
            )
          )
        )
      )
    )

    ;; ---- ETRIERI ----
    (foreach ch_etr all_chenare_etr
      (setq etr_poly_pts (grz-obtine-puncte-polilinie ch_etr))
      (if (and etr_poly_pts (grz-punct-in-poligon (car etr_poly_pts) poly_pts))
        (progn
          (setq linii_count 0 linii_gasite nil)
          (foreach pt all_linii_etr
            (if (grz-punct-in-poligon pt etr_poly_pts)
              (progn (setq linii_count (1+ linii_count)) (setq linii_gasite (cons (caddr pt) linii_gasite)))
            )
          )
          (setq marci_in_careu nil)
          (foreach m_item all_marci_texte
            (if (grz-punct-in-poligon (cadr m_item) etr_poly_pts)
              (progn
                (setq val_m (grz-curata-numar (car m_item)))
                (if (not (assoc val_m marci_in_careu)) (setq marci_in_careu (cons (cons val_m (caddr m_item)) marci_in_careu)))
              )
            )
          )
          (foreach mc marci_in_careu
            (setq val_m (car mc))
            (setq def_etr (assoc val_m etr_definitii))
            (if def_etr
              (progn
                (setq base_list (grz-adauga-marca val_m (nth 1 def_etr) (nth 2 def_etr) (* linii_count stalpi_buc) base_list (cdr mc)))
                (foreach le linii_gasite (setq *grz-marca-entitati* (cons (cons val_m le) *grz-marca-entitati*)))
                (setq *grz-marca-entitati* (cons (cons val_m (nth 3 def_etr)) *grz-marca-entitati*))
                (setq *grz-marca-entitati* (cons (cons val_m (nth 4 def_etr)) *grz-marca-entitati*))
                (setq *grz-marca-entitati* (cons (cons val_m (nth 5 def_etr)) *grz-marca-entitati*))
              )
              (princ (strcat "\n[ATENTIE] Nu am gasit un grup complet (cu ETR) pentru marca etrier " val_m))
            )
          )
        )
      )
    )
  )

  (setq sorted_list (vl-sort base_list '(lambda (e1 e2) (< (atof (car e1)) (atof (car e2))))))
  sorted_list
)


(defun grz-arata-avertismente ( / fname f dcl_id w )
  (if *grz-warnings*
    (progn
      (setq fname (strcat (getvar "TEMPPREFIX") "grz_avertismente.dcl"))
      (setq f (open fname "w"))
      (write-line "avert_dlg : dialog { label = \"ATENTIE - verificati urmatoarele\"; width = 100;" f)
      (write-line "  : list_box { key = \"lst\"; width = 98; height = 25; }" f)
      (write-line "  ok_only;" f)
      (write-line "}" f)
      (close f)
      (setq dcl_id (load_dialog fname))
      (if (new_dialog "avert_dlg" dcl_id)
        (progn
          (start_list "lst")
          (foreach w (reverse *grz-warnings*) (add_list w))
          (end_list)
          (action_tile "accept" "(done_dialog)")
          (start_dialog)
        )
      )
      (unload_dialog dcl_id)
    )
  )
)

;; =========================================================================
;; COMANDA 1: EXTRASFASONARE - genereaza tabel nativ AutoCAD
;; =========================================================================

(defun grz-col-litera (n / s r)
  (setq s "")
  (while (> n 0)
    (setq r (rem (1- n) 26))
    (setq s (strcat (chr (+ 65 r)) s))
    (setq n (/ (- n 1 r) 26))
  )
  s
)

(defun grz-xl-set (sheet addr val)
  (vlax-put-property (vlax-get-property sheet 'Range addr) "Value2" val)
)

(defun grz-xl-merge (sheet addr)
  (vlax-invoke (vlax-get-property sheet 'Range addr) "Merge")
)

(defun grz-xl-formateaza (sheet addr / rng)
  (setq rng (vlax-get-property sheet 'Range addr))
  (vlax-put-property (vlax-get-property rng "Font") "Name" "Times New Roman")
  (vlax-put-property (vlax-get-property rng "Font") "Size" 12)
  (vlax-put-property rng "HorizontalAlignment" -4108) ;; xlCenter
  (vlax-put-property rng "VerticalAlignment" -4108) ;; xlCenter
  (vlax-put-property rng "WrapText" :vlax-true)
  (vlax-put-property (vlax-get-property rng "Borders") "LineStyle" 1)
)

;; =========================================================================
;; COMANDA UNIFICATA: EXTRASGRINZI
;; Calculeaza o singura data (acelasi motor, neschimbat), apoi intreaba ce
;; tip de tabel vrei - Excel sau nativ AutoCAD. Structura si rotunjirile
;; sunt IDENTICE in ambele variante (matrice pe diametre, grupare OB37/
;; BST500C, rotunjire la 5kg pe diametru) - singura diferenta e unde iese
;; rezultatul.
;; =========================================================================
(defun c:ExtrasGrinzi ( / *error* last_inainte ss sorted_list alegere diametre item dv row cota
                                  ob37 bst xlApp xlBooks xlBook xlSheet
                                  n col_diam_start last_col last_col_l r
                                  row_t1 row_t2 row_h1 row_h2 row_h3
                                  row_ds row_de row_sum row_wt row_wtt row_tot
                                  m d l b addr col_letter j m_ob m_bst
                                  ob37_end bst_start pt old_osmode old_cmdecho old_clayer olderr new_ole
                                  num_rows num_cols table_ent diam_totale existing suma kg_m kg_rotunjit
                                  suma_ob suma_bst l_val l_tot col_idx )

  (vl-load-com)
  (setq old_osmode (getvar "OSMODE") old_cmdecho (getvar "CMDECHO") old_clayer (getvar "CLAYER"))
  (setvar "CMDECHO" 0)
  (setq *grz-warnings* nil *grz-marca-entitati* nil)
  (setq xlApp nil xlBook nil)

  (setq olderr *error*)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*,*EXIT*")))
      (princ (strcat "\n[EROARE] " msg)))
    (if xlApp  (vl-catch-all-apply '(lambda () (vlax-put-property xlApp "DisplayAlerts" :vlax-false)) '()))
    (if xlBook (vl-catch-all-apply '(lambda () (vlax-invoke xlBook "Close" :vlax-false)) '()))
    (if xlApp  (vl-catch-all-apply '(lambda () (vlax-invoke xlApp "Quit")) '()))
    (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho) (setvar "CLAYER" old_clayer)
    (setq *error* olderr)
    (princ)
  )

  (princ "\nSelectati toata planasa (grinzi, centuri, buiandrugi, sectiuni, tot): ")
  (setq ss (ssget))
  (if (not ss) (progn (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho) (setvar "CLAYER" old_clayer) (exit)))

  ;; cota implicita +2.75 (sau ultima folosita in sesiunea asta);
  ;; Enter o pastreaza, orice altceva scris o inlocuieste
  (if (not *extras-cota*) (setq *extras-cota* "+2.75"))
  (setq cota (vl-string-trim " " (getstring t (strcat "\nCota <" *extras-cota* ">: "))))
  (if (= cota "") (setq cota *extras-cota*) (setq *extras-cota* cota))

  (setq sorted_list (grz-calculeaza-lista ss))
  (if (= (length sorted_list) 0)
    (progn (princ "\n[ATENTIE] Nu am gasit nimic de pus in tabel.") (grz-arata-avertismente) (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho) (setvar "CLAYER" old_clayer) (exit))
  )
  (princ (strcat "\n[OK] Lista calculata: " (itoa (length sorted_list)) " marci."))

  (initget "Excel Nativ")
  (setq alegere (getkword "\nCe tip de tabel? [Excel/Nativ] <Excel>: "))
  (if (not alegere) (setq alegere "Excel"))

  ;; --- diametrele distincte si impartirea OB37/BST500C - COMUNE la ambele tipuri ---
  (setq diametre nil)
  (foreach item sorted_list
    (setq dv (atoi (nth 1 item)))
    (if (not (member dv diametre)) (setq diametre (cons dv diametre)))
  )
  (setq diametre (vl-sort diametre '<))
  (setq n (length diametre))
  (setq ob37 nil bst nil)
  (foreach dv diametre (if (< dv 8) (setq ob37 (cons dv ob37)) (setq bst (cons dv bst))))
  (setq ob37 (reverse ob37) bst (reverse bst))

  (if (= alegere "Nativ")
    (progn
      ;; =====================================================================
      ;; TABEL NATIV - structura identica cu Excel-ul
      ;; =====================================================================
      (setq col_diam_start 4)
      (setq row_t1 0 row_t2 1 row_h1 2 row_h2 3 row_h3 4)
      (setq row_ds 5 row_de (+ 4 (length sorted_list)))
      (setq row_sum (+ row_de 1) row_wt (+ row_de 2) row_wtt (+ row_de 3) row_tot (+ row_de 4))
      (setq num_rows (1+ row_tot))
      (setq num_cols (+ col_diam_start n))

      (setq pt (getpoint "\nAlege punctul de insertie pentru tabel: "))
      (if (not pt) (progn (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho) (setvar "CLAYER" old_clayer) (exit)))

      (grz-asigura-layer-tabele)
      (setq table_ent (vla-addtable (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))) (vlax-3d-point (trans pt 1 0)) num_rows num_cols 8.0 30.0))
      (vl-catch-all-apply 'vla-put-layer (list table_ent "Tabele"))
      (vla-put-regeneratetablesuppressed table_ent :vlax-true)

      (vla-mergecells table_ent row_t1 row_t1 0 (1- num_cols))
      (vla-settext table_ent row_t1 0 "Extras de armatura")
      (vla-mergecells table_ent row_t2 row_t2 0 (1- num_cols))
      (vla-settext table_ent row_t2 0 (strcat "grinzi, centuri si buiandrugi cota " cota))

      (vla-mergecells table_ent row_h1 row_h3 0 0) (vla-settext table_ent row_h1 0 "Marca")
      (vla-mergecells table_ent row_h1 row_h3 1 1) (vla-settext table_ent row_h1 1 "Diametru mm.")
      (vla-mergecells table_ent row_h1 row_h2 2 2) (vla-settext table_ent row_h1 2 "Lung.")
      (vla-settext table_ent row_h3 2 "m.")
      (vla-mergecells table_ent row_h1 row_h3 3 3) (vla-settext table_ent row_h1 3 "Buc.")
      (vla-mergecells table_ent row_h1 row_h1 col_diam_start (1- num_cols))
      (vla-settext table_ent row_h1 col_diam_start (strcat "Lung in ml/ " (chr 216)))

      (if ob37
        (progn
          (setq ob37_end (+ col_diam_start (length ob37) -1))
          (if (> (length ob37) 1) (vla-mergecells table_ent row_h2 row_h2 col_diam_start ob37_end))
          (vla-settext table_ent row_h2 col_diam_start "OB 37")
        )
      )
      (if bst
        (progn
          (setq bst_start (+ col_diam_start (length ob37)))
          (if (> (length bst) 1) (vla-mergecells table_ent row_h2 row_h2 bst_start (1- num_cols)))
          (vla-settext table_ent row_h2 bst_start "BST 500C")
        )
      )
      (setq j 0)
      (foreach dv diametre
        (vla-settext table_ent row_h3 (+ col_diam_start j) (strcat (chr 216) (itoa dv)))
        (setq j (1+ j))
      )

      (setq row row_ds diam_totale nil)
      (foreach item sorted_list
        (setq m (nth 0 item) d (nth 1 item) l (nth 2 item) b (nth 3 item))
        (setq l_val (atof l)) (setq l_tot (* l_val b))
        (vla-settext table_ent row 0 m)
        (vla-settext table_ent row 1 d)
        (vla-settext table_ent row 2 (grz-fixn l_val 2))
        (vla-settext table_ent row 3 (itoa b))
        (setq j 0)
        (foreach dv diametre
          (setq col_idx (+ col_diam_start j))
          (if (= (atoi d) dv)
            (progn
              (vla-settext table_ent row col_idx (grz-fixn l_tot 2))
              (setq existing (assoc dv diam_totale))
              (if existing
                (setq diam_totale (subst (cons dv (+ (cdr existing) l_tot)) existing diam_totale))
                (setq diam_totale (cons (cons dv l_tot) diam_totale))
              )
            )
            (vla-settext table_ent row col_idx "")
          )
          (setq j (1+ j))
        )
        (setq row (1+ row))
      )

      (vla-mergecells table_ent row_sum row_sum 0 3)
      (vla-settext table_ent row_sum 0 (strcat "Lung. In ml/ " (chr 216)))
      (vla-mergecells table_ent row_wt row_wt 0 3)
      (vla-settext table_ent row_wt 0 "Greut. In Kg/ m")
      (vla-mergecells table_ent row_wtt row_wtt 0 3)
      (vla-settext table_ent row_wtt 0 (strcat "Greut. In Kg/ " (chr 216)))

      (setq j 0)
      (foreach dv diametre
        (setq col_idx (+ col_diam_start j))
        (setq existing (assoc dv diam_totale))
        (setq suma (if existing (cdr existing) 0.0))
        (setq kg_m (grz-afla-greutate (itoa dv)))
        (setq kg_rotunjit (grz-rotunjeste5 (* suma kg_m)))
        (vla-settext table_ent row_sum col_idx (grz-fixn suma 2))
        (vla-settext table_ent row_wt col_idx (grz-fixn kg_m 3))
        (vla-settext table_ent row_wtt col_idx (grz-fixn kg_rotunjit 2))
        (setq j (1+ j))
      )

      (vla-mergecells table_ent row_tot row_tot 0 3)
      (vla-settext table_ent row_tot 0 "Total in Kg")
      (if ob37
        (progn
          (setq suma_ob 0.0)
          (foreach dv ob37
            (setq suma_ob (+ suma_ob (grz-rotunjeste5 (* (cdr (assoc dv diam_totale)) (grz-afla-greutate (itoa dv))))))
          )
          (if (> (length ob37) 1) (vla-mergecells table_ent row_tot row_tot col_diam_start ob37_end))
          (vla-settext table_ent row_tot col_diam_start (grz-fixn suma_ob 2))
        )
      )
      (if bst
        (progn
          (setq suma_bst 0.0)
          (foreach dv bst
            (setq suma_bst (+ suma_bst (grz-rotunjeste5 (* (cdr (assoc dv diam_totale)) (grz-afla-greutate (itoa dv))))))
          )
          (if (> (length bst) 1) (vla-mergecells table_ent row_tot row_tot bst_start (1- num_cols)))
          (vla-settext table_ent row_tot bst_start (grz-fixn suma_bst 2))
        )
      )

      (vla-put-regeneratetablesuppressed table_ent :vlax-false) (vla-update table_ent)
      (vla-scaleentity table_ent (vlax-3d-point (trans pt 1 0)) 50)
      (command "_.ZOOM" "_Object" (vlax-vla-object->ename table_ent) "")
      (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho) (setvar "CLAYER" old_clayer)
      (setq *error* olderr)
      (princ "\n[Succes] Extrasul general centralizat (tabel nativ) a fost generat!")
      (grz-arata-avertismente)
      (princ)
    )
    (progn
      ;; =====================================================================
      ;; TABEL EXCEL (OLE)
      ;; =====================================================================
      (setq col_diam_start 8) ;; coloana H
      (setq last_col (+ col_diam_start n -1))
      (setq last_col_l (grz-col-litera last_col))
      (setq row_t1 12 row_t2 13 row_h1 14 row_h2 15 row_h3 16)
      (setq row_ds 17 row_de (+ 16 (length sorted_list)))
      (setq row_sum (+ row_de 1) row_wt (+ row_de 2) row_wtt (+ row_de 3) row_tot (+ row_de 4))
      (princ (strcat "\n[OK] " (itoa n) " diametre distincte, randuri de la " (itoa row_ds) " la " (itoa row_de) "."))

      (setq xlApp (vlax-create-object "Excel.Application"))
      (princ "\n[OK] Excel.Application creat.")
      (vlax-put-property xlApp "Visible" :vlax-true)
      ;; fara redesenare la fiecare celula: tabelul se completeaza mult mai repede
      (vl-catch-all-apply 'vlax-put-property (list xlApp "ScreenUpdating" :vlax-false))
      (setq xlBooks (vlax-get-property xlApp "Workbooks"))
      (setq xlBook (vlax-invoke xlBooks "Add"))
      (princ "\n[OK] Workbook creat.")
      (setq xlSheet (vlax-get-property xlBook "ActiveSheet"))
      (princ "\n[OK] Foaie activa obtinuta.")

      (grz-xl-merge xlSheet (strcat "D" (itoa row_t1) ":" last_col_l (itoa row_t1)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_t1)) "Extras de armatura")
      (grz-xl-merge xlSheet (strcat "D" (itoa row_t2) ":" last_col_l (itoa row_t2)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_t2)) (strcat "grinzi, centuri si buiandrugi cota " cota))
      (princ "\n[OK] Titlu scris.")

      (grz-xl-merge xlSheet (strcat "D" (itoa row_h1) ":D" (itoa row_h3))) (grz-xl-set xlSheet (strcat "D" (itoa row_h1)) "Marca")
      (grz-xl-merge xlSheet (strcat "E" (itoa row_h1) ":E" (itoa row_h3))) (grz-xl-set xlSheet (strcat "E" (itoa row_h1)) "Diametru mm.")
      (vl-catch-all-apply 'vlax-put-property (list (vlax-get-property xlSheet 'Range (strcat "E" (itoa row_h1))) "Orientation" 90))
      (vl-catch-all-apply 'vlax-put-property (list (vlax-get-property xlSheet 'Range "E1") "ColumnWidth" 5.0))
      (grz-xl-merge xlSheet (strcat "F" (itoa row_h1) ":F" (itoa row_h2))) (grz-xl-set xlSheet (strcat "F" (itoa row_h1)) "Lung.")
      (grz-xl-set xlSheet (strcat "F" (itoa row_h3)) "m.")
      (grz-xl-merge xlSheet (strcat "G" (itoa row_h1) ":G" (itoa row_h3))) (grz-xl-set xlSheet (strcat "G" (itoa row_h1)) "Buc.")
      (grz-xl-merge xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_h1) ":" last_col_l (itoa row_h1)))
      (grz-xl-set xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_h1)) (strcat "Lung in ml/ " (chr 216)))
      (princ "\n[OK] Capete de tabel scrise.")

      (if ob37
        (progn
          (setq ob37_end (+ col_diam_start (length ob37) -1))
          (if (> (length ob37) 1)
            (grz-xl-merge xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_h2) ":" (grz-col-litera ob37_end) (itoa row_h2)))
          )
          (grz-xl-set xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_h2)) "OB 37")
        )
      )
      (if bst
        (progn
          (setq bst_start (+ col_diam_start (length ob37)))
          (if (> (length bst) 1)
            (grz-xl-merge xlSheet (strcat (grz-col-litera bst_start) (itoa row_h2) ":" last_col_l (itoa row_h2)))
          )
          (grz-xl-set xlSheet (strcat (grz-col-litera bst_start) (itoa row_h2)) "BST 500C")
        )
      )
      (princ "\n[OK] Rand material (OB37/BST500C) scris.")

      (setq j 0)
      (foreach dv diametre
        (setq col_letter (grz-col-litera (+ col_diam_start j)))
        (grz-xl-set xlSheet (strcat col_letter (itoa row_h3)) (strcat (chr 216) (itoa dv)))
        (setq j (1+ j))
      )
      (princ "\n[OK] Etichete diametru scrise.")

      (setq row row_ds)
      (foreach item sorted_list
        (setq m (nth 0 item) d (nth 1 item) l (nth 2 item) b (nth 3 item))
        (grz-xl-set xlSheet (strcat "D" (itoa row)) m)
        (grz-xl-set xlSheet (strcat "E" (itoa row)) (atoi d))
        (grz-xl-set xlSheet (strcat "F" (itoa row)) (atof l))
        (grz-xl-set xlSheet (strcat "G" (itoa row)) b)
        (setq j 0)
        (foreach dv diametre
          (setq col_letter (grz-col-litera (+ col_diam_start j)))
          (grz-xl-set xlSheet (strcat col_letter (itoa row))
            (strcat "=IF($E" (itoa row) "=" (itoa dv) ",$G" (itoa row) "*$F" (itoa row) ",0)"))
          (setq j (1+ j))
        )
        (setq row (1+ row))
      )
      (princ "\n[OK] Randuri de date scrise.")

      (grz-xl-merge xlSheet (strcat "D" (itoa row_sum) ":G" (itoa row_sum)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_sum)) (strcat "Lung. In ml/ " (chr 216)))
      (setq j 0)
      (foreach dv diametre
        (setq col_letter (grz-col-litera (+ col_diam_start j)))
        (grz-xl-set xlSheet (strcat col_letter (itoa row_sum))
          (strcat "=SUM(" col_letter (itoa row_ds) ":" col_letter (itoa row_de) ")"))
        (setq j (1+ j))
      )

      (grz-xl-merge xlSheet (strcat "D" (itoa row_wt) ":G" (itoa row_wt)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_wt)) "Greut. In Kg/ m")
      (setq j 0)
      (foreach dv diametre
        (setq col_letter (grz-col-litera (+ col_diam_start j)))
        (grz-xl-set xlSheet (strcat col_letter (itoa row_wt)) (grz-afla-greutate (itoa dv)))
        (setq j (1+ j))
      )

      (grz-xl-merge xlSheet (strcat "D" (itoa row_wtt) ":G" (itoa row_wtt)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_wtt)) (strcat "Greut. In Kg/ " (chr 216)))
      (setq j 0)
      (foreach dv diametre
        (setq col_letter (grz-col-litera (+ col_diam_start j)))
        (grz-xl-set xlSheet (strcat col_letter (itoa row_wtt))
          (strcat "=CEILING(" col_letter (itoa row_wt) "*" col_letter (itoa row_sum) ",5)"))
        (setq j (1+ j))
      )

      (vlax-put-property
        (vlax-get-property xlSheet 'Range (strcat "F" (itoa row_ds) ":F" (itoa row_de)))
        "NumberFormat" "0.00"
      )
      (vlax-put-property
        (vlax-get-property xlSheet 'Range (strcat (grz-col-litera col_diam_start) (itoa row_ds) ":" last_col_l (itoa row_de)))
        "NumberFormat" "0.00;-0.00;;"
      )
      (vlax-put-property
        (vlax-get-property xlSheet 'Range (strcat (grz-col-litera col_diam_start) (itoa row_sum) ":" last_col_l (itoa row_sum)))
        "NumberFormat" "0.00;-0.00;;"
      )
      (vlax-put-property
        (vlax-get-property xlSheet 'Range (strcat (grz-col-litera col_diam_start) (itoa row_wt) ":" last_col_l (itoa row_wt)))
        "NumberFormat" "0.000"
      )
      (vlax-put-property
        (vlax-get-property xlSheet 'Range (strcat (grz-col-litera col_diam_start) (itoa row_wtt) ":" last_col_l (itoa row_wtt)))
        "NumberFormat" "0.00;-0.00;;"
      )

      (grz-xl-merge xlSheet (strcat "D" (itoa row_tot) ":G" (itoa row_tot)))
      (grz-xl-set xlSheet (strcat "D" (itoa row_tot)) "Total in Kg")
      (if ob37
        (progn
          (setq m_ob (strcat "=SUM(" (grz-col-litera col_diam_start) (itoa row_wtt) ":" (grz-col-litera ob37_end) (itoa row_wtt) ")"))
          (if (> (length ob37) 1)
            (grz-xl-merge xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_tot) ":" (grz-col-litera ob37_end) (itoa row_tot)))
          )
          (grz-xl-set xlSheet (strcat (grz-col-litera col_diam_start) (itoa row_tot)) m_ob)
          (vlax-put-property (vlax-get-property xlSheet 'Range (strcat (grz-col-litera col_diam_start) (itoa row_tot))) "NumberFormat" "0.00")
        )
      )
      (if bst
        (progn
          (setq m_bst (strcat "=SUM(" (grz-col-litera bst_start) (itoa row_wtt) ":" last_col_l (itoa row_wtt) ")"))
          (if (> (length bst) 1)
            (grz-xl-merge xlSheet (strcat (grz-col-litera bst_start) (itoa row_tot) ":" last_col_l (itoa row_tot)))
          )
          (grz-xl-set xlSheet (strcat (grz-col-litera bst_start) (itoa row_tot)) m_bst)
          (vlax-put-property (vlax-get-property xlSheet 'Range (strcat (grz-col-litera bst_start) (itoa row_tot))) "NumberFormat" "0.00")
        )
      )

      (vl-catch-all-apply 'vlax-put-property (list (vlax-get-property xlSheet 'Range "D1") "ColumnWidth" 7.0))
      (vl-catch-all-apply 'vlax-put-property (list (vlax-get-property xlSheet 'Range "G1") "ColumnWidth" 7.0))
      (princ "\n[OK] Latimi de coloana setate (sau ignorate daca a esuat).")

      (grz-xl-formateaza xlSheet (strcat "D" (itoa row_t1) ":" last_col_l (itoa row_tot)))
      (vlax-put-property (vlax-get-property (vlax-get-property xlSheet 'Range (strcat "D" (itoa row_t1) ":" last_col_l (itoa row_t2))) "Borders") "LineStyle" -4142)
      (princ "\n[OK] Rand total si formatare scrise.")

      (xlc:copiaza xlApp (vlax-get-property xlSheet 'Range (strcat "D" (itoa row_t1) ":" last_col_l (itoa row_tot))))
      (princ "\n[OK] Interval copiat in clipboard.")

      (setq pt (getpoint "\nAlege punctul de insertie pentru tabelul Excel: "))
      (if pt
        (progn
          (grz-asigura-layer-tabele)
          (setvar "CLAYER" "Tabele")
          (setq last_inainte (entlast))
          (command "_.PASTECLIP" "_non" pt)
          (setq new_ole (entlast))
          ;; daca lipirea n-a mers, nu se scaleaza alt obiect din desen
          (if (or (null pt) (eq new_ole last_inainte)) (setq new_ole nil))
          (if new_ole (command "_.SCALE" new_ole "" "_non" pt 50))
          (setvar "CLAYER" old_clayer)
        )
      )
      (princ "\n[OK] Obiect OLE lipit in desen.")

      (vlax-put-property xlApp "DisplayAlerts" :vlax-false)
      (vlax-invoke xlBook "Close" :vlax-false)
      (vlax-invoke xlApp "Quit")
      (vlax-release-object xlSheet) (vlax-release-object xlBook) (vlax-release-object xlBooks) (vlax-release-object xlApp)
      (setq xlApp nil)
      (gc)

      (setvar "OSMODE" old_osmode) (setvar "CMDECHO" old_cmdecho)
      (setq *error* olderr)
      (princ "\n[Succes] Extrasul a fost generat in Excel si lipit in desen ca obiect OLE!")
      (grz-arata-avertismente)
      (princ)
    )
  )
)

(princ "\nScrieti 'ExtrasGrinzi' - va intreaba ce tip de tabel vreti (Excel sau nativ AutoCAD).")


;; =========================================================================
;; COMANDA: GASESTEMARCAGRINZI
;; Cere o SELECTIE PROPRIE (independenta de ExtrasGrinzi),
;; ruleaza acelasi motor de calcul (grz-calculeaza-lista) doar pe ea, apoi
;; selecteaza (cu grip-uri aprinse) toate elementele care au contribuit la
;; marca ceruta.
;; =========================================================================
(defun c:GasesteMarcaGrinzi ( / ss mval ss2 e gasite)
  (princ "\nSelectati zona in care cautati marca (chenare, marci, tot ce tine de ea): ")
  (setq ss (ssget))
  (if (not ss) (exit))
  (setq *grz-warnings* nil *grz-marca-entitati* nil)
  (grz-calculeaza-lista ss)

  (setq mval (strcase (getstring "\nCe marca cautati (ex: 7, sau 7* pentru varianta cu conflict): ")))
  (setq gasite nil)
  (foreach e *grz-marca-entitati*
    (if (= (car e) mval) (setq gasite (cons (cdr e) gasite)))
  )
  (if gasite
    (progn
      (setq ss2 (ssadd))
      (foreach e gasite (if e (ssadd e ss2)))
      (sssetfirst nil ss2)
      (princ (strcat "\n[OK] " (itoa (length gasite)) " element(e) de marca " mval " selectate in desen."))
    )
    (princ (strcat "\n[ATENTIE] Nu am gasit nicio marca " mval " in selectia facuta."))
  )
  (princ)
)

(princ "\nScrieti 'GasesteMarcaGrinzi' pentru a selecta o zona si a gasi in ea toate elementele unei marci.")
(princ)
