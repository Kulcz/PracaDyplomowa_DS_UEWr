# TODO: PracaDyplomowa_DS_UEWr

## Tydzień 1: Setup + audyt

- [x] Audyt 4 uczelni (URL Baz Wiedzy + status Omega-PSIR)
- [x] Scaffold repo (struktura, init R, gitignore, README, CLAUDE.md)
- [x] Rozszerzenie `UNIVERSITY_CONFIG` o URK i UWM
- [x] Szkielety skryptów 02-10 z TODO
- [x] Szablon pracy Quarto (Praca/praca.qmd)
- [ ] `Rscript init_r_env.R` — instalacja pakietów + snapshot renv
- [ ] Manualna walidacja filtra dyscypliny w przeglądarce (per uczelnia):
  - [ ] UPWR — pobrać URL z aktywnym filtrem "rolnictwo i ogrodnictwo"
  - [ ] SGGW — j.w.
  - [ ] URK — j.w.
  - [ ] UWM — j.w.
- [x] Wybór 3 dyscyplin: rolnictwo i ogrodnictwo + weterynaria + zootechnika i rybactwo (2026-05-24, po pre-screeningu OpenAlex)
- [x] Pre-screening OpenAlex: ≥800 prac per komórka macierzy 3×4 (2026-05-24)
- [ ] Weryfikacja liczebności pracowników w panelu Omega-PSIR per (uczelnia × dyscyplina) — 12 komórek
- [ ] Uzgodnienie zakresu z promotorem

## Tydzień 2-3: Scraping

- [ ] Test scrapera na UPWR + "rolnictwo i ogrodnictwo" (znana baseline, n≈145)
- [ ] Scraping wszystkich 12 komórek macierzy (3 dyscypliny × 4 uczelnie)
- [ ] Walidacja: ile profili zebrano vs deklarowane

## Tydzień 4: Czyszczenie + matching OpenAlex

- [ ] Implementacja `02_czyszczenie.R`
- [ ] Weryfikacja ROR-ów uczelni (https://ror.org)
- [ ] Implementacja `03_openalex_match.R`
- [ ] Raport match_rate; cel ≥ 70%

## Tydzień 5: OpenAlex Works

- [ ] `04_openalex_works.R` — publications + coauthors + FWCI
- [ ] Cache RDS per author

## Tydzień 6-10: Analiza

- [ ] `05_features.R` — feature engineering
- [ ] `06_eda_anova.R` — warstwa 1
- [ ] `07_klastrowanie_pca.R` — warstwa 2
- [ ] `08_modele_predykcja.R` — warstwa 3 (RF + XGB + SHAP)
- [ ] `09_sieci_wspolautorstwa.R` — warstwa 4 (igraph + Louvain)

## Tydzień 11-13: Pisanie

- [ ] Praca.qmd — uzupełnienie sekcji Wyniki/Dyskusja/Wnioski
- [ ] Iteracje z promotorem
- [ ] Render PDF + DOCX

## Recenzja

[Uzupełnić po obronie]
