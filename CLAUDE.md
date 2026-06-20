# Pamięć projektu: PracaDyplomowa_DS_UEWr

## Charakter projektu

Praca dyplomowa studiów podyplomowych Data Science na Uniwersytecie Ekonomicznym we Wrocławiu. Analiza bibliometryczna naukowców dyscypliny **rolnictwo i ogrodnictwo** w **4 polskich uczelniach przyrodniczych z systemem Omega-PSIR** (~491 osób). Trzy warstwy DS: klastrowanie + modelowanie predykcyjne + sieci współautorstwa.

**4 uczelnie z Omega-PSIR ewaluowane w dyscyplinie rolnictwo i ogrodnictwo (decyzja 2026-05-26 po teście kompletności CRIS):**

| Uczelnia | Kategoria MEiN | CRIS | n |
|---|---|---|---:|
| UPWR — Uniwersytet Przyrodniczy we Wrocławiu | A | Omega-PSIR | 146 |
| SGGW — Szkoła Główna Gospodarstwa Wiejskiego | A | Omega-PSIR | 112 |
| URK — Uniwersytet Rolniczy w Krakowie | A | Omega-PSIR | 163 |
| UWM — Uniwersytet Warmińsko-Mazurski | B+ | Omega-PSIR | 70 |
| **Razem** | | | **491** |

**Kryterium próby:** polskie uczelnie ewaluowane w dyscyplinie rolnictwo i ogrodnictwo (wykaz MEiN) **z publicznie dostępnym CRIS-em Omega-PSIR**. Motywacja: homogeniczność metodyki ekstrakcji (1 system, ten sam parser, te same pola) jest ważniejsza niż jednorodność kategorii ewaluacji. Kategoria A vs B+ wchodzi do analizy jako zmienna kontrolna (3A + 1B+, niezbalansowana — nie jako główny czynnik).

**Strategia metodyczna B (zaktualizowana 2026-05-26):** z CRIS Omega-PSIR ciągniemy TOŻSAMOŚĆ + LOKALNE METRYKI bibliometryczne (sum_IF, sum_SNIP, sum_MEiN, h_index_scopus, h_index_wos, n_pub). OpenAlex używamy jako **uzupełnienie** (FWCI, cited_by_count, sieci współautorstwa) i **QA cross-check** dla metryk lokalnych. Wcześniejsza wersja strategii B („OpenAlex jako primary source") została zrewidowana po teście 2026-05-26: Omega-PSIR jest średnio 2-3× bogatszy katalog niż OpenAlex (akceptuje polskie czasopisma, książki, materiały konferencyjne nieindeksowane w Scopus/WoS).

**Historia decyzji o próbie:**
1. Wstępnie: 3 dyscypliny × 4 uczelnie przyrodnicze (UPWr/SGGW/URK/UWM) — wszystkie Omega-PSIR
2. Rozszerzenie 2026-05-25: 3 dyscypliny × 6 uczelni (+ UP Poznań DSpace, UP Lublin OpenUP)
3. Zawężenie 2026-05-26: 1 dyscyplina × 4 uczelnie kategorii A (UPWr/SGGW/URK/UP Poznań)
4. **FINAL 2026-05-26: 1 dyscyplina × 4 uczelnie Omega-PSIR** (UPWr/SGGW/URK/UWM) — po teście wykazującym dramatyczną niekompletność UP Poznań DSpace (Potarzycki: 9 prac w DSpace vs 66 OpenAlex vs 112 w wykazie autora) i bogactwo Omega-PSIR (test 6 osób: średni ratio CRIS/OA = 2.3 dla Omega-PSIR vs 0.13 dla DSpace UP Poznań).

**Próba poza core analizą (dane usunięte z repo 2026-06-20 przy optymalizacji, backup zewnętrzny; parsery `up_poznan.py`/`up_lublin.py` zostają w kodzie):**
- UP Poznań (208 osób + 2582 publikacji ETAP 2) — DSpace niekompletny, łamałby porównywalność z Omega-PSIR.
- UP Lublin (2257 osób) — OpenUP, kategoria B+, asymetryczna metodyka.

**Próba pominięta (kategoria A bez publicznego CRIS):**
- Zachodniopomorski Uniwersytet Technologiczny w Szczecinie — brak Bazy Wiedzy w publicznym API.

Pilotaż metodyczny `pilot_UPWr/` (dawny projekt `UPWr_bibliometria` — scraper UPWr + analiza wydziału WPT, ~145 osób; pierwowzór metodyki) **usunięty z repo 2026-06-20 przy optymalizacji pod oddanie** (backup zewnętrzny). Moduł szeregów czasowych z pilota został już uogólniony na 4 uczelnie w głównym pipelinie (skrypty 11/12 + `scrape_publications.py`).

## Środowisko

- **IDE:** Positron (cwd = root projektu)
- **R:** zarządzane przez renv (`renv::restore()` przy first run) — analiza, modelowanie, raporty
- **Python:** scrapery Omega-PSIR (Playwright/Selenium dojrzalsze niż w R) — venv lokalnie w projekcie; wymiana danych z R przez CSV
- **Quarto:** rendering pracy do PDF + DOCX

## Konfiguracja uczelni (4 Omega-PSIR)

| Uczelnia | URL | Specyfika |
|---|---|---|
| UPWR | bazawiedzy.upwr.edu.pl | label `MEiN`, WAIT_PROFILE 6s |
| SGGW | **bw.sggw.edu.pl** (stara `bazawiedzy.sggw.edu.pl` daje 404) | brak sum_MEiN w UI (100% NA), niska ekstrakcja `wydzial` (5%) — TODO override |
| URK | repo.ur.krakow.pl | label `ministerialna`, WAIT_PROFILE 12s |
| UWM | bazawiedzy.uwm.edu.pl | label `ministerialna`, WAIT_PROFILE 12s, brak sum_SNIP w UI (0%) |

Per-uczelnia różnice + strategia ekstrakcji — szczegóły w `Skrypty/Python/README.md`.

## Workflow scrapingu

Stack: Python 3.12 + Playwright (Chromium bundled) + BeautifulSoup. Parsery per uczelnia w `Skrypty/Python/scrapers/{upwr,sggw,urk,uwm}.py` dziedziczą z `OmegaPsirBaseParser`. Parsery UP Poznań i UP Lublin pozostają w kodzie na wypadek powrotu, ale nie używane w core analizie. (Stary monolityczny R-scraper i jego archiwum usunięte 2026-06-20.)

1. `source .venv/bin/activate`
2. `python Skrypty/Python/scrape.py --uni <UPWR|SGGW|URK|UWM> --dyscyplina rolnictwo_i_ogrodnictwo`
3. Otwiera się Chromium z listą wyników — ręcznie ustaw filtr dyscypliny w panelu po lewej, kliknij „Filtruj".
4. ENTER w terminalu — ETAP 1 (paginator → author_id), ETAP 2 (profile + autosave co 10).
5. Wynik: `Dane/raw/<code>_<dyscyplina>_<timestamp>.csv`.

## Zasady pracy z literaturą

(reuse z UPWr_bibliometria)
Baza Markdown: `~/pCloudDrive/Zotero_markdown/INDEKS.md`. Workflow przeszukiwania 6-krokowy. Cytaty z numerami linii w plikach `*_merged.md`.

## Konwencje kodu

- Komentarze nagłówkowe `# LTeX: enabled=false` w skryptach R (wyłącza LTeX-a w Positron).
- Polskie znaki w outputach (raport, wykresy); w komentarzach kodu można bez ogonków dla wygody.
- Tabele w Quarto: zawsze pipe-tables (kompatybilność z Visual Mode Positron).
- Nowe dokumenty: zawsze `.qmd` z YAML PDF+DOCX (zgodnie z globalnym CLAUDE.md).

## Git / sync

Standardowo: auto-sync przez `spa`, brak named commitów bez wyraźnej prośby. Wyjątek: milestone'y (master dataset gotowy, warstwa 2 ukończona, draft pracy gotowy) — propozycja commita ze mnie, decyzja użytkownika.

## Plan harmonogramu (zaktualizowany 2026-05-26)

| Tydzień | Etap | Status |
|---|---|---|
| 1 | Audyt uczelni + scaffold | ✓ |
| 2 | Scraping 4 uczelni × 1 dyscyplina | ✓ |
| 3 | Czyszczenie + matching OpenAlex (ROR-y, ORCID) | bieżący |
| 4 | OpenAlex Works (FWCI + h-index policzone + sieci współautorstwa) | |
| 5 | EDA + 2-czynnikowe porównania uczelnia × stanowisko (Kruskal-Wallis+Dunn, bo założenia ANOVA naruszone; kategoria jako kontrola) | |
| 6 | Klastrowanie + PCA (typologia profili bibliometrycznych) | |
| 7 | Modele predykcyjne + SHAP | |
| 8-9 | Sieci współautorstwa (igraph + Louvain) | |
| 10-13 | Pisanie pracy + iteracje z promotorem | |
