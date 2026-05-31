# TODO: UPWr_bibliometria

## Etap 1: Zbieranie danych
- [x] Skonfigurować środowisko R (renv)
- [x] Przenieść skrypt scrapera (`test.R`) z projektu `X_profile test`
- [x] Pierwsze uruchomienie — dane UPWR zebrane (2026-03-06)
- [ ] Zweryfikować kompletność danych (ile profili zebrano vs. ilu jest pracowników)
- [ ] Uruchomić scraper dla SGGW (ustawić `RESULTS_URL` z dyscypliną)

## Etap 2: Czyszczenie i przygotowanie danych (Wydz. Przyrodniczo-Technologiczny)
- [x] Filtracja: tylko Wydział Przyrodniczo-Technologiczny (145 rekordów)
- [x] Usunąć kolumny techniczne (author_id, url, error)
- [x] Zbadać i opisać braki (40 stanowisk, 16 h-index, 8 IF/SNIP/MEiN)
- [x] Zapisać oczyszczone dane do CSV (`output_bibliometria/WPT_oczyszczone.csv`)

## Etap 3: Analiza (Wydz. Przyrodniczo-Technologiczny)
- [x] Statystyki opisowe metryk per stanowisko i jednostka
- [x] Rozkłady metryk (h-index, IF, SNIP, MEiN)
- [x] Korelacje między metrykami (wszystkie r > 0.85)
- [x] Top-10 najaktywniejszych pracowników (h-index, IF, MEiN)

## Etap 4: Wizualizacja
- [x] Histogramy/density rozkładów metryk (`Wykresy/01_rozklady_metryk.png`)
- [x] Boxploty metryk per stanowisko (`Wykresy/02_boxploty_stanowisko.png`)
- [x] Boxploty metryk per jednostka (`Wykresy/03_boxploty_jednostka.png`)
- [x] Mapa ciepła korelacji (`Wykresy/04_korelacje_mapa.png`)

## Etap 3b: Analiza indywidualna pracowników (Wydz. Przyrodniczo-Technologiczny)
- [x] Ranking Top-15 pracowników per metryka (lollipop charts)
- [x] Profil radarowy Top-10 (średnia rang z 3 metryk, znormalizowane 0–1)
- [x] Scatter plot IF vs MEiN (rozmiar = h-index, kolor = stanowisko)
- [x] Eksport rankingów do Excela (`output_bibliometria/WPT_ranking_pracownikow.xlsx`)
- [x] Skrypt: `Skrypty/R/03_analiza_pracownicy_WPT.R`

## Etap 5: Raport
- [x] Przygotować raport Quarto (.qmd) z renderowaniem do PDF (`Raport/raport_WPT.qmd`)
- [x] Podsumowanie wyników (15 stron: wprowadzenie, statystyki, ANOVA stanowiska/jednostki, korelacje, rankingi, nota metodologiczna)

---
## Etap 6: Szeregi czasowe (publikacje + punkty MEiN rocznie) — WPT, 145 osób

**Cel:** roczny szereg czasowy liczby publikacji i sumy punktów MEiN dla
pracowników WPT (z jednego scrapingu, retrospektywnie). IF/rok poza zakresem
(brak IF w liście publikacji — wymagałby kart pojedynczych publikacji).

**Ustalenia techniczne (zweryfikowane na profilu Kulczyckiego):**
- Lista `tab=publications` grupowana: rok (`resultListHeader0`) → punkty
  (`resultListHeader1`) → liczność `[n]` (`resultListHeaderCount`).
- Rok dodatkowo w COinS `<span class="Z3988" title="...rft.date=YYYY...">`.
- `ps=100` ucina listę → użyć dużego `ps` (np. 1000) + walidacja liczności.
- Render JS: Chrome headless `--dump-dom --virtual-time-budget` —
  BEZ Selenium/chromedriver (inaczej niż `01_scraper`). Pełna automatyzacja.
- author_id dla WPT: filtr `wydzial == "Wydział Przyrodniczo-Technologiczny"`
  na surowym CSV (`upwr_profiles_metrics_HTML_20260306_075402.csv`) → 145 id.

**Zadania:**
- [x] `Skrypty/R/04_scraper_publikacje.R` (base R + Chrome headless `--dump-dom`):
  - [x] 145 author_id WPT z surowego CSV; parser rok(header0)+punkty(header1) per rowEntry
  - [x] `ps=200` (portal akceptuje tylko 20/50/100/200; `&pn=`/filtr roku ignorowane — JSF POST)
  - [x] retry (rosnący budżet) + wznawianie + autosave; flaga `capped` (>200 poz.)
  - [x] zapis `output_bibliometria/WPT_publikacje_rocznie.csv`
        (profil, author_id, rok, n_publikacji, suma_pkt, capped)
- [x] `Skrypty/R/06_scraper_capped_selenium.R` (RSelenium + chromedriver):
  - [x] doratowanie 18 profili `capped` (>200) przez klikanie `.ui-paginator-next`
  - [x] czekanie na render paginatora + na zmianę treści; flaga kompletności
  - [x] scalenie do CSV (capped → FALSE); wszystkie 18 kompletne
- [x] `Skrypty/R/05_analiza_szeregi_czasowe.R`:
  - [x] agregaty WPT: publikacje/rok, punkty/rok (ogółem + per stanowisko + per jednostka)
  - [x] 6 wykresów (słupki + składane pola) → `Wykresy/WPT/szeregi_czasowe/`
- [x] walidacja: Σpkt per autor vs `sum_MEiN` z profilu — większość zgodna co do jednostki

**Wynik:** 137 autorów z publikacjami + 8 realnie pustych = 145. Lata 1990–2026,
14 066 publikacji, 226 803 pkt MEiN. Kluczowa obserwacja: skok punktów 2019
(reforma Ustawa 2.0 — punkty 100/140/200), liczba publikacji stabilna (~600–700/rok).

**Ograniczenia (do noty metodologicznej):**
- Stanowisko/jednostka z migawki 2026 stosowane wstecz (kto dziś profesorem, liczy
  się jako profesor też dla wcześniejszych publikacji sprzed awansu).
- 2026 niepełny (stan na 2026-05-31).
- Σ punktów per-pozycja ≠ headline `sum_MEiN` dla części osób (różnica księgowania
  portalu, nie błąd — parser zweryfikowany; 60+ idealnych zgodności).

---
## Recenzja
[Uzupełnić po zakończeniu prac]
