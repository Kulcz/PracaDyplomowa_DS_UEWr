# PracaDyplomowa_DS_UEWr

Praca dyplomowa studiów podyplomowych Data Science na Uniwersytecie Ekonomicznym we Wrocławiu — analiza bibliometryczna naukowców z wybranych dyscyplin (rolnictwo+ogrodnictwo + 2 dyscypliny kontrastowe) w czterech polskich uczelniach przyrodniczych (UPWr, SGGW, URK, UWM).

## Plan

Pełny plan: `~/.claude/plans/chce-wykona-projekt-ko-cowy-zany-rabbit.md`

Trzy warstwy DS: klastrowanie + modelowanie predykcyjne + sieci współautorstwa.

## Struktura

```
Dane/
├── raw/                   # surowe CSV ze scrapingu Omega-PSIR (per uczelnia × dyscyplina)
├── openalex/              # cache OpenAlex (matching + works + coauthors)
└── master/                # finalny dataset analityczny
Skrypty/R/
├── 01_scraper_omegapsir.R     # Selenium + rvest, 4 uczelnie w UNIVERSITY_CONFIG
├── 02_czyszczenie.R           # scalanie + standaryzacja + dedup
├── 03_openalex_match.R        # fuzzy match Omega-PSIR ↔ OpenAlex
├── 04_openalex_works.R        # publikacje + coauthors + FWCI
├── 05_features.R              # feature engineering
├── 06_eda_anova.R             # warstwa 1: statystyka klasyczna
├── 07_klastrowanie_pca.R      # warstwa 2: typologia profili
├── 08_modele_predykcja.R      # warstwa 3: RF + XGBoost + SHAP
├── 09_sieci_wspolautorstwa.R  # warstwa 4 (wow): igraph + Louvain
└── 10_wykresy_pracy.R         # finalne figury
output/                    # processed RDS, model results
Wykresy/                   # PNG do pracy
Praca/                     # praca.qmd + referencje.bib + praca.pdf
Dashboard/                 # opcjonalnie Shiny
```

## Pierwsze uruchomienie

```bash
# 1. Otwórz w Positron → ustaw cwd = root projektu
# 2. Init środowiska:
Rscript init_r_env.R
# 3. Audyt 4 uczelni: otwórz każdą Bazę Wiedzy w przeglądarce,
#    ustaw filtr dyscypliny, skopiuj URL z paska adresu do UNIVERSITY_CONFIG
#    w 01_scraper_omegapsir.R
# 4. Scraping per uczelnia × dyscyplina:
Sys.setenv(UNI = "URK")
Sys.setenv(DYSCYPLINA = "rolnictwo_i_ogrodnictwo")
source("Skrypty/R/01_scraper_omegapsir.R")
```

## Konfiguracja uczelni

Wszystkie 4 uczelnie potwierdzone na Omega-PSIR (audyt 2026-05-24, HTTP 200/302):

| Kod | Uczelnia | URL |
|---|---|---|
| UPWR | Uniwersytet Przyrodniczy we Wrocławiu | https://bazawiedzy.upwr.edu.pl |
| SGGW | Szkoła Główna Gospodarstwa Wiejskiego | https://bazawiedzy.sggw.edu.pl |
| URK | Uniwersytet Rolniczy w Krakowie | https://repo.ur.krakow.pl |
| UWM | Uniwersytet Warmińsko-Mazurski | https://bazawiedzy.uwm.edu.pl |

## Powiązany projekt

Fundament metodyczny: `~/Analiza_projekty/UPWr_bibliometria` — wcześniejsza analiza WPT UPWr (145 profili, scraper + ANOVA + raport Quarto).
