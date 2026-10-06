# Generare grinzi si buiandrugi

LISP AutoCAD (2024) care desfasoara grinzile si buiandrugii de pe planul de cofraj.

| Fisier | Comanda | Ce face |
| --- | --- | --- |
| `Generare grinzi si buiandrugi.lsp` | `GenerareGrinziBuiandrugi` | Desfasoara toate grinzile (G..) si buiandrugii (B..) din planul selectat, plus detaliile centurilor, si semnaleaza greselile gasite pe plan |
| `Generare grinzi si buiandrugi.lsp` | `SectiuniGrinzi` | Deseneaza sectiunile (1:20) pentru numerele sectiunilor de pe desfasurate |
| `Generare grinzi si buiandrugi.lsp` | `RenumeroteazaSectiuni` | Renumeroteaza sectiunile de pe desfasurate 1, 2, 3... de la stanga la dreapta (si titlurile N-N ale chenarelor) |
| `Renumeroteaza Marci Grinzi.lsp` | `RenumeroteazaMarciGrinzi` | Renumeroteaza marcile (bare lungi, etrieri); marcile legate (etrierul centurii din sectiunea buiandrugului) primesc singure numarul |
| `Extras grinzi.lsp` | `ExtrasGrinzi`, `GasesteMarcaGrinzi` | Extrasul de armatura (Excel sau tabel AutoCAD); avertizeaza cand o marca e sarita |

Se incarca la fel ca celelalte lisp-uri (vezi `acaddoc.lsp` din repo-ul de placi: puneti fisierul
in acelasi folder).

## Folosire

1. `GenerareGrinziBuiandrugi`, apoi selectati tot planul de cofraj cu o fereastra.
2. Comanda propune cota de sus gasita pe grupurile de cofraj (ex. `<+2.75>`): Enter daca e buna,
   sau scrieti alta.
3. Dati coltul stanga-sus al primei desfasurate. Desfasuratele se pun intr-un rand, toate cu fata de
   sus la acelasi nivel: intai grinzile (G1, G2, ...), apoi buiandrugii (B1, B2, ...).
4. La final apare o fereastra cu problemele gasite; fiecare e marcata pe plan cu un cerc rosu
   numerotat, pe layerul `Erori grinzi`, care nu se printeaza (marcajele vechi se sterg la fiecare rulare).

Toata generarea se anuleaza cu un singur `U`.

## Ce citeste din plan

- **Markers**: numele elementelor: `G1 30x40` = grinda, `B2 30x55` = buiandrug (latime x inaltime, in cm).
  `C1 30x25` (centuri) servesc doar ca reazem; `BP ...` (buiandrugi porotherm) se ignora.
- **Grinzi**: cele doua linii ale fiecarei grinzi / fiecarui buiandrug (linii sau polilinii, ortogonale).
  Elementul e fasia dintre cele doua linii in care sta textul. Liniile se pot opri la fata stalpului
  sau pot intra peste stalp. Peste un stalp intermediar elementul continua (grinda continua), daca dincolo
  nu e alt element (alt nume).
- **Centuri**: liniile centurilor (pentru reazeme).
- **Stalpi**: dreptunghiurile stalpilor.
- **Axe**: liniile de axe si numele din cercurile de la capete.
- **Cofrag**: sectiunea mica prin element (hasura + cote + cote de nivel cu field). Sectiunea apartine
  elementului care are aceleasi doua fete ca ea. Din grup se iau textul liber (cota de sus), textul cu
  field (cota de jos) si cotele (ex. 14 + 11).

## Ce deseneaza

- dreptunghiul elementului (layer `0`), de la marginea exterioara a reazemului din stanga pana la a celui
  din dreapta, inalt cat inaltimea din nume; carcasa pe `FIER`, la 25 mm in interior
- reazemele, ca grupuri pe layer `0`:
  - stalp: latimea lui, 30 cm inaltime, hasura ANSI31
  - grinda pe care reazema (ex. G3 pe G1): sectiunea ei, hasurata
  - la buiandrugi, capatul fara stalp: caramida de 30 cm (hasura AR-B88), de ajustat manual daca e cazul
- etrierii, linii pe `Otel etrieri`:
  - **grinzi**: la o deschidere (lumina) mai mica de 1.20 m, toti etrierii la 15 cm; altfel, pe fiecare deschidere, zona de capat = 1/4 din lumina, rotunjita in sus la 5 cm
    (4.975 m -> 1.25 m). Din punctul de impartire se merge cu 10 cm spre stalp, fara sa intre in el; la
    mijloc cu 15 cm, de la stanga la dreapta; din al doilea punct de impartire iar cu 10 cm pana la stalpul
    din dreapta. Daca la mijloc ramane un rest, ultimii doi etrieri sunt mai apropiati (niciodata mai
    departe de 15 cm).
  - **buiandrugi**: la 15 cm peste tot, in afara de stalpi (si peste caramida); ultimul se pune la capat.
  - nu se pun etrieri in stalpi (si nici in grinda pe care reazema elementul).
- lantul de cote de sus: zonele de etrieri, de la coltul grinzii (cu stalp) pana la schimbarea de pas si de la ultima schimbare de pas pana la capatul grinzii (cu stalp); peste un stalp intermediar, zonele cu acelasi pas sunt o singura cota cu `etr. %%C8/10` / `etr. %%C8/15` sub el; lantul
  de jos (reazemele si deschiderile); stil `Centimetri 50 cu virgula`, layer `Cote`
- axele care trec prin reazeme (stalpi / grinda de reazem), cu numele lor; unde nu trece nicio axa, nu se pune
- grupul de cote de nivel (layer `Cote`): cota de inaltime, cota de sus si cota de jos ca FIELD
  (cota de sus - cota de inaltime), ca in desenele facute manual
- sectiunea `xx` (grup pe `Sectiuni grinzi`, textele cu punctul de insertie in dreapta jos), in prima treime a
  primei deschideri, de la reazemul din stanga; daca ar cadea peste textul etrierilor, se muta in aceeasi treime
  (textul etrierilor ramane mereu la mijlocul cotei lui)
- armatura longitudinala, sub desfasurata, ca grupuri (ca la placi: bara cu ciocuri pe `FIER`, cotele ciocurilor si
  a lungimii cu `Fier stalpi 50`, tot pe `FIER`, cercul marcii pe `0`, marca `y` pe `Otel marca` - se renumeroteaza -, diametrul pe
  `Otel diametru`, `L=` ca FIELD pe `Otel lungime`), cu eticheta la mijlocul barei si textul cotei lungimii intre
  diametru si ciocul din dreapta; bara e cu 25 mm mai scurta la fiecare capat:
  - grinzi: un rand sus si unul jos, `3%%C16`, ciocuri de 25 cm
  - buiandrugi: doar jos, `3%%C12`, ciocuri de 30 cm (sus sunt barele centurii)
- la buiandrugi, fierul de jos al centurii: o linie pe `FIER` sub cea de sus a carcasei, la inaltimea centurii minus
  2 x 2.5 cm (centura de 25 -> 20 cm, de 30 -> 25 cm); inaltimea se ia din textul centurii in care sta buiandrugul
- deasupra, pe `Bucati element`: `G1 30x40 1buc.` si `Scara 1:50`. Elementele identice (acelasi nume,
  aceeasi geometrie) se deseneaza o singura data, cu numarul de bucati.

Marca otelului (cercul cu `a`) nu se mai pune: etrierii se pot numara direct din desfasurata.

## Ce semnaleaza

- latimea din nume diferita de distanta dintre linii pe plan
- inaltimea din nume diferita de grupul de cofraj (suma cotelor, ex. 14 + 11 = 25 fata de 40)
- cotele de nivel din grupul de cofraj care nu se potrivesc cu inaltimea din nume, sau care lipsesc
- cota de sus din grupul de cofraj diferita de cea data la pornire
- grinda fara grup de cofraj pe plan
- buiandrug cu latimea din nume diferita de grosimea zidului (distanta dintre liniile de centura in care sta)
- buiandrugi cu cota de jos diferita de a celorlalti (de obicei toti au aceeasi, ex. +2.20)
- capat de grinda care nu reazema pe stalp sau grinda
- text de element care nu e intre doua linii
- acelasi nume (numar) la axe paralele diferite
- acelasi nume la elemente cu lungimi / reazeme diferite (se face cate o desfasurata pentru fiecare)

## Grinzi cu sectiune variabila

Doua texte cu acelasi numar pe aceeasi grinda, pe deschideri diferite (ex. `G1 30x50` si `G1 30x40`), dau o singura
grinda cu sectiune variabila, numita `G1 30x50(30x40)`:
- treapta e la fata stalpului dinspre partea mai joasa (stalpul ramane la partea mai inalta); conturul si carcasa
  urmeaza treapta
- cotele de nivel si de inaltime se pun la ambele capete
- armatura de sus e continua; jos, cate o bara pe fiecare tronson, fiecare trecand peste tot stalpul de la treapta
- pe desfasurata (pe `FIER`), la treapta: ciocul barei de jos a tronsonului inalt si bara tronsonului jos, care trece
  la nivelul ei peste stalp pana la cealalta fata, cu ciocul ei
- cate o sectiune `xx` pe fiecare tronson, in prima lui deschidere
- grupul de cofraj se verifica fata de inaltimea tronsonului in dreptul caruia sta

## Detaliile centurilor (la generare)

La sfarsitul randului de desfasurate, cate un detaliu pentru fiecare tip de centura de pe plan (dupa textele C..):
sectiunea la 1:20 (placa din grupul de cofraj al centurii), 2+2 bare, etrierul in sectiune, cotele de nivel, etrierul
desfasurat (laturi = centura - 5 cm, `etr %%C8/15`, L= field) cu `xxx buc.` pe `Bucati etrieri centuri`, si sub ele
grupul barelor drepte (`4%%C12`, `L=12.00m`, `xxx buc.`), aliniat cu primul detaliu, in `Chenar pentru armatura`. Armatura centurii se intreaba la pornire (`<4%%C12>`).
Bucatile `xxx` se completeaza manual; extrasul avertizeaza daca au ramas necompletate.

La buiandrugi, langa fiecare etrier (la 25 mm) e figurat etrierul centurii pe `Otel centuri global` (de la fierul de
jos al centurii pana sus), cat se vede pe zidarie, fara sa intre in stalpi. Liniile acestea nu se numara.

## Sectiunile (`SectiuniGrinzi`)

1. Dupa generare (si eventuale corecturi), scrieti numerele sectiunilor in locul lui `xx` (sus si jos acelasi numar).
2. `SectiuniGrinzi`: selectati desfasuratele, apoi coltul stanga-sus al primului chenar.

Pentru fiecare numar se deseneaza, intr-un `Chenar pentru sectiuni etrieri`, sectiunea la 1:20: titlul `N-N`,
`Sc 1:20`, conturul cu placa (din grupul de cofraj, cu rupere; fara placa daca planul nu are grupuri de cofraj),
etrierul cu ciocuri, barele de sus si de jos (din grupurile de armatura de sub element, in dreptul sectiunii), etichetele,
cota de latime, cotele de nivel (cota de jos = field) si indicatorul de marca. Sub ea, etrierul desfasurat (grupul
definitiei: laturi = sectiunea - 5 cm, colturi rotunjite, ciocuri de 10 cm, cotele, marca `y`, `etr %%C8/10/15` sau
`/15` dupa pasii din desfasurata, L= field). Sectiunile aceluiasi element cu acelasi etrier stau in acelasi chenar,
cu un singur etrier desfasurat.

Barele din desfasurata pot fi modificate de mana: intrerupte, cu cioc la un singur capat sau drepte (polilinie
sau linie pe `FIER`, in grup cu textul de diametru). Bara cu ciocuri in jos e de sus, cu ciocuri in sus e de jos; bara
dreapta ia randul barei cu ciocuri cele mai apropiate pe verticala. La o innadire se ia bara din care sectiunea e mai
departe de capat.

La buiandrugi: etrierul centurii sus (cu cele 4 bare ale centurii - armatura se intreaba, ex. `4%%C12`, `6%%C12` =
jumatate sus, jumatate jos) si etrierul buiandrugului pe toata inaltimea; doua marci - sus cea a etrierului centurii,
jos cea a buiandrugului. Etrierul desfasurat al buiandrugului e deschis: trei laturi, ciocuri intoarse care adauga
impreuna 20 cm.

Datele (dimensiuni, placa, centura) sunt salvate ascuns pe conturul desfasuratei la generare, deci sectiunile merg doar
pe desfasurate generate cu versiunea aceasta.

## Renumerotare si extras (modificari)

- Marcile generate au o legatura ascunsa (XDATA `GBMARCA`, ex. `C300x250` = etrierul centurii 30x25). La
  `RenumeroteazaMarciGrinzi`, marca etrierului centurii din sectiunea unui buiandrug primeste numarul etrierului din
  detaliul centurii; nu mai e nevoie de `Marci otel de corectat`. Legaturile fara definitie sunt semnalate, cu ce anume lipseste. Barele drepte ale centurilor (grup cu `... buc.` pe
  `Bucati etrieri centuri`) primesc numar si daca nu sunt intr-un `Chenar pentru armatura`.
- `ExtrasGrinzi`: un `Chenar etrieri` fara marca isi afla marca din numerele sectiunilor din el (ca la renumerotare),
  deci grupul cerc+marca de pe desfasurata nu mai e obligatoriu. Avertismente noi: etrieri nenumarati (fara marca si
  fara sectiune, sau in afara oricarui Chenar etrieri), definitii sau bare care nu ajung in tabel, numere lipsa in sirul
  marcilor, marci nerenumerotate (`y`), bucati necompletate (`xxx buc.`).

## Chenarele (la generare)

Fiecare desfasurata primeste chenarele de care au nevoie renumerotarea si extrasul, strict pe lungimea elementului
(cotele de nivel raman in afara, ca desfasuratele sa poata fi apropiate fara ca chenarele sa se suprapuna):
- `Chenar pentru armatura`: titlul (numele cu bucatile) si grupurile barelor lungi de dedesubt
- `Chenar etrieri`: etrierii si numerele sectiunilor (sus si jos)

## Numerele sectiunilor

La generare, fiecare sectiune primeste direct un numar, 1, 2, 3... de la stanga la dreapta. Daca adaugati sau stergeti o
sectiune (copiati un grup de sectiune existent unde e nevoie), rulati `RenumeroteazaSectiuni` si selectati tot (nu
trebuie izolat nimic): comanda gaseste grupurile de sectiune (doua linii si doua texte pe `Sectiuni grinzi`) si le
numeroteaza de la 1, de la stanga la dreapta, pe randuri de sus in jos. Titlurile `N-N` ale chenarelor de sectiuni din
selectie se schimba la fel (fosta 4-4 devine 3-3 etc.), ca sa ramana legate de grinzi; pentru sectiunea noua se
deseneaza chenarul cu `SectiuniGrinzi`.
