# PracaDyplomowa_DS_UEWr

Praca dyplomowa studiów podyplomowych Data Science na Uniwersytecie Ekonomicznym we Wrocławiu — analiza bibliometryczna naukowców dyscypliny **rolnictwo i ogrodnictwo** w czterech polskich uczelniach przyrodniczych z systemem **Omega-PSIR** (UPWr, SGGW, URK, UWM) — łącznie 491 osób.

> **Omega-PSIR** to opracowany na Politechnice Warszawskiej system klasy CRIS (*Current Research Information System*) — instytucjonalna baza wiedzy gromadząca dorobek naukowy uczelni (publikacje, projekty, patenty, metryki bibliometryczne, dane afiliacyjne). Jeden z dominujących systemów CRIS w Polsce; tu pełni rolę publicznie dostępnego źródła danych (Baza Wiedzy uczelni).

## Plan

Trzy warstwy DS: klastrowanie + modelowanie predykcyjne + sieci współautorstwa. Czynnik różnicujący w analizach: **uczelnia × stanowisko** (kategoria ewaluacyjna MEiN A/B+ jako zmienna kontrolna).

## Struktura

```
Dane/
├── raw/                   # surowe CSV ze scrapingu Omega-PSIR (per uczelnia) + pub_years
├── openalex/              # OpenAlex (matching + works + coauthors + FWCI); cache/ poza gitem
└── master/                # finalny dataset analityczny
Skrypty/Python/
├── scrape.py              # entry point (dispatch po --uni → parser.run)
└── scrapers/              # BaseParser + 4 parsery Omega-PSIR + 2 archiwalne (UP Poznań, UP Lublin)
Skrypty/R/
├── 02_czyszczenie.R           # scalanie + standaryzacja + dedup
├── 03_openalex_match.R        # fuzzy match Omega-PSIR ↔ OpenAlex (po ROR + nazwisku)
├── 04_openalex_works.R        # publikacje + coauthors + FWCI + h-index z OA
├── 05_features.R              # feature engineering
├── 06_eda_anova.R             # warstwa 1: statystyka klasyczna (uczelnia × stanowisko)
├── 07_klastrowanie_pca.R      # warstwa 2: typologia profili
├── 08_modele_predykcja.R      # warstwa 3: RF + XGBoost + SHAP
├── 09_sieci_wspolautorstwa.R  # warstwa 4: igraph + Louvain
└── 10_wykresy_pracy.R         # finalne figury
output/                    # processed RDS, model results
Wykresy/                   # PNG do pracy
Praca/                     # praca.qmd + referencje.bib + praca.pdf
```

## Pierwsze uruchomienie

```bash
# 1. Otwórz w Positron → ustaw cwd = root projektu
# 2. R: instalacja pakietów + snapshot renv
Rscript init_r_env.R
# 3. Python: venv + Playwright
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
# 4. Scraping per uczelnia (Omega-PSIR — interaktywny filtr w Chromium):
python Skrypty/Python/scrape.py --uni UPWR --dyscyplina rolnictwo_i_ogrodnictwo
```

## Konfiguracja uczelni (4 Omega-PSIR)

Próba dobrana wg dwóch kryteriów: (1) ewaluacja MEiN w dyscyplinie rolnictwo i ogrodnictwo, (2) publicznie dostępny CRIS Omega-PSIR. Wybór Omega-PSIR jako kryterium spójności metodologicznej (jeden parser, te same pola, porównywalne metryki) — kategoria A vs B+ wchodzi do analizy jako zmienna kontrolna.

| Kod | Uczelnia | Kat. | URL | n (2026-05-26) |
|---|---|---|---|---:|
| UPWR | Uniwersytet Przyrodniczy we Wrocławiu | A | bazawiedzy.upwr.edu.pl | 146 |
| SGGW | Szkoła Główna Gospodarstwa Wiejskiego | A | bw.sggw.edu.pl | 112 |
| URK | Uniwersytet Rolniczy w Krakowie | A | repo.ur.krakow.pl | 163 |
| UWM | Uniwersytet Warmińsko-Mazurski | B+ | bazawiedzy.uwm.edu.pl | 70 |
| **Razem** | | | | **491** |

**Uczelnie pominięte:**
- **Uniwersytet Przyrodniczy w Poznaniu** (kategoria A, DSpace-CRIS) — wykluczony z próby. Test kompletności 2026-05-26: DSpace UP Poznań pokazuje ~10-15% rzeczywistego dorobku autorów (np. prof. Potarzycki: 9 prac w DSpace vs 66 w OpenAlex vs 112 w wykazie autora). Włączenie złamałoby porównywalność z Omega-PSIR (średnio 2-3× pełniejszy katalog).
- **Zachodniopomorski Uniwersytet Technologiczny w Szczecinie** (kategoria A) — brak publicznego CRIS.
- **UP Lublin** (kategoria B+, OpenUP) — asymetryczna metodyka.

## Strategia metodyczna

Z Omega-PSIR ciągniemy **tożsamość** (kto, gdzie, ORCID) + **lokalne metryki bibliometryczne** (sum_IF, sum_SNIP, sum_MEiN, h-index Scopus/WoS, n_pub) — Omega-PSIR jest bogatym katalogiem (test 2026-05-26: 2-3× więcej prac per autor niż OpenAlex; obejmuje polskie czasopisma, książki, materiały konferencyjne).

OpenAlex używamy jako **uzupełnienie**: FWCI (field-weighted citation impact, niepoliczalny lokalnie), `cited_by_count`, lista współautorów do sieci współautorstwa, oraz **QA cross-check** dla metryk lokalnych.

## Odtwarzalność (uwagi)

- **Rok referencyjny przypięty na stałe.** Skrypty `12_dynamika_omega.R` i `14_model_jakosc.R` używają stałej `2026L` (rok przygotowania pracy) zamiast `Sys.Date()`, żeby okna analizy (trend 2008–2024, wiek akademicki) nie dryfowały przy ponownym uruchomieniu w kolejnych latach.
- **Scraping nie jest w pełni bezobsługowy.** Pozyskanie danych z Omega-PSIR wymaga ręcznego ustawienia filtra dyscypliny w Chromium (portale PrimeFaces, paginacja bez stabilnych URL). Odtwarzalność analizy opiera się więc na **zamrożonych CSV** w `Dane/raw/`, a nie na automatycznym ponownym scrapingu.
- **Matching OpenAlex** odbywa się po identyfikatorze ROR uczelni + nazwisku (Jaro-Winkler ≥ 0,85). ORCID jest pobierany z Omega-PSIR, ale **nie służy jako klucz dopasowania** — automatyczny match bez ręcznej weryfikacji jest źródłem szumu w cechach OA (opisane w sekcji Ograniczenia pracy).
