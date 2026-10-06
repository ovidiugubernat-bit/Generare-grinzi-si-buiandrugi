# Generare grinzi si buiandrugi

LISP AutoCAD (2024) care desfasoara grinzile si buiandrugii de pe planul de cofraj.

| Fisier | Comanda | Ce face |
| --- | --- | --- |
| `Generare grinzi si buiandrugi.lsp` | `GenerareGrinziBuiandrugi` | Desfasoara toate grinzile (G..) si buiandrugii (B..) din planul selectat si semnaleaza greselile gasite pe plan |

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
  a lungimii cu `Fier stalpi 50`, cercul marcii pe `0`, marca `y` pe `Otel marca` - se renumeroteaza -, diametrul pe
  `Otel diametru`, `L=` ca FIELD pe `Otel lungime`); bara e cu 25 mm mai scurta la fiecare capat:
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
- acelasi nume la elemente cu lungimi / reazeme diferite (se face cate o desfasurata pentru fiecare)
