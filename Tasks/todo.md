# TODO: PracaDyplomowa_DS_UEWr

## Finalna próba (decyzja 2026-05-26)

**4 polskie uczelnie przyrodnicze z systemem Omega-PSIR ewaluowane w dyscyplinie rolnictwo i ogrodnictwo (491 osób):**

| Uczelnia | Kat. MEiN | n |
|---|---|---:|
| UPWr | A | 146 |
| SGGW | A | 112 |
| URK | A | 163 |
| UWM | B+ | 70 |

Pominięte: UP Poznań (DSpace niekompletny → `_archive/`), ZUT Szczecin (brak CRIS), UP Lublin (OpenUP → `_archive/`).

## Tydzień 1: Setup + audyt (✓ ukończone)

- [x] Audyt uczelni (URL Baz Wiedzy + status CRIS)
- [x] Scaffold repo (struktura, init R, gitignore, README, CLAUDE.md)
- [x] Szkielety skryptów 02-10 z TODO
- [x] Szablon pracy Quarto (Praca/praca.qmd)
- [x] Decyzja o próbie: 4 uczelnie Omega-PSIR (test kompletności 2026-05-26)
- [ ] `Rscript init_r_env.R` — instalacja pakietów + snapshot renv
- [ ] Uzgodnienie próby z promotorem

## Tydzień 2: Scraping (✓ kompletny)

- [x] UPWR/rolnictwo (146 profili, Omega-PSIR, 2026-05-26)
- [x] SGGW/rolnictwo (112 profili, Omega-PSIR, 2026-05-26)
- [x] URK/rolnictwo (163 profili, Omega-PSIR, 2026-05-26)
- [x] UWM/rolnictwo (70 profili, Omega-PSIR, 2026-05-26)
- [x] Przywrócenie UWM z `_archive/` po teście kompletności
- [x] UP Poznań i UP Lublin do `_archive/` (poza core analizą)

**Macierz 4×1 (4 uczelnie Omega-PSIR × rolnictwo i ogrodnictwo): kompletna.**

## Tydzień 3: Czyszczenie + matching OpenAlex

- [ ] `02_czyszczenie.R`:
  - dostosować `uczelnia` levels = `upwr/sggw/urk/uwm`
  - filtr nie-naukowców (UPWr „specjalista", „starszy specjalista")
  - filtr profili bez ORCID i n_pub=0 (administracyjne)
- [ ] `03_openalex_match.R`:
  - ROR vector dla 4 uczelni Omega-PSIR (UPWr/SGGW/URK/UWM zweryfikowane)
  - matching ORCID-first, potem fuzzy po nazwisku + ROR
- [ ] Raport match_rate; cel ≥ 70%

## Tydzień 4: OpenAlex Works

- [ ] `04_openalex_works.R` — publications + coauthors + FWCI + h-index liczone z listy works (jako QA cross-check dla h-index_scopus z CRIS)
- [ ] Cache RDS per author (resumability)

## Tydzień 5-9: Analiza

- [ ] `05_features.R` — feature engineering (usunąć `factor(dyscyplina)`, levels uczelni `upwr/sggw/urk/uwm`)
- [ ] `06_eda_anova.R` — warstwa 1 (2-czynnikowa ANOVA: uczelnia × stanowisko, kategoria MEiN jako zmienna kontrolna)
- [ ] `07_klastrowanie_pca.R` — warstwa 2 (typologia profili)
- [ ] `08_modele_predykcja.R` — warstwa 3 (RF + XGB + SHAP)
- [ ] `09_sieci_wspolautorstwa.R` — warstwa 4 (igraph + Louvain)

## Tydzień 10-13: Pisanie

- [ ] Praca.qmd — uzupełnienie sekcji Wyniki/Dyskusja/Wnioski
- [ ] Iteracje z promotorem
- [ ] Render PDF + DOCX

## Znane luki strukturalne (do raportu „Ograniczenia")

- SGGW: `sum_MEiN` 0% (UI nie eksponuje), `wydzial` 5% (parser do dopracowania w `sggw.py`)
- UWM: `sum_SNIP` 0% (UI nie eksponuje)
- Wszystkie uczelnie: w analizach które używają `sum_MEiN` — SGGW wykluczyć lub policzyć MEiN z OpenAlex+wykaz MEiN przez ISSN

## Materiał poza core analizą (potencjalna sekcja Dyskusji)

- `Dane/raw/_archive/up_poznan_*.csv` (208 osób + 2582 publikacji) — case study DSpace + ETAP 2:
  - finansowanie publikacji (`dc.description.finance`, `financecost`)
  - model OA (`dc.share.type` — 64% `OPEN_JOURNAL`)
  - Można dorzucić jako 1-2 strony „Polskie CRIS-y a globalne bazy bibliograficzne — niejednorodność polityki deponowania" jeśli zostanie czas.

## Recenzja

[Uzupełnić po obronie]
