# TODO: PracaDyplomowa_DS_UEWr

## ⏩ STAN NA 2026-05-31 — start następnej sesji tutaj

**Pipeline danych 02→03→04→05 uruchomiony end-to-end (pierwszy raz).**
Master gotowy: `Dane/master/profiles_features.csv` (462 osoby × 30 cech; 318 z metrykami OpenAlex).

**Następne kroki (priorytet):**
1. **Diagnoza słabego matchu URK (47.5%, 144 profile bez OA)** — sprawdzić `clean_name_for_search`
   na nazwiskach URK i/lub pokrycie ROR URK (`012dxyr07`) w OpenAlex. To największa dziura w danych.
2. **Refactor 06–10: `dyscyplina → stanowisko`** — wszystkie mają nagłówek „REFACTOR PENDING";
   ~58 odwołań do nieistniejącej `dyscyplina`. Konieczne PRZED odpaleniem warstw analitycznych.
   W `08` dodatkowo: target `high_impact` liczyć globalnie, nie `group_by(dyscyplina)`.
3. **`renv::snapshot()`** — biblioteka przebudowana pod R 4.6 (zob. memory `reference-r46-env-fix`),
   lockfile nieaktualny. Zapisać działający stan (renv też podbity 1.1.5→1.2.3).
4. Potem: odpalić 06 (EDA/ANOVA) → 07 (klastrowanie) → 08 (modele) → 09 (sieci) → 10 (wykresy).

**Środowisko:** R 4.6.0; ~50 pakietów zaktualizowanych do wersji wspierających 4.6.
Gdyby `igraph`/warstwa 09 czegoś wymagała: `sudo apt install libglpk-dev` (teraz BRAK).

---

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

## Tydzień 3: Czyszczenie + matching OpenAlex (✓ uruchomione 2026-05-31)

- [x] `02_czyszczenie.R`: levels `upwr/sggw/urk/uwm`, filtr nie-naukowców → **462 rekordy** (z 491)
- [x] `03_openalex_match.R`: ROR 4 uczelni, fuzzy match Jaro-Winkler ≥0.85 → **68.8% (318/462)**
  - [ ] poprawić match URK (47.5% — patrz blok „STAN" u góry)
- [x] Raport match_rate (cel ≥70% osiągnięty globalnie, ale URK ciągnie w dół)

## Tydzień 4: OpenAlex Works (✓ uruchomione 2026-05-31)

- [x] `04_openalex_works.R` → `publications.csv` (15 453 prac) + `coauthorship_edges.csv` (23 478 krawędzi)
- [x] Cache RDS per author w `Dane/openalex/cache/`

## Tydzień 5-9: Analiza

- [x] `05_features.R` — dokończony join OA (mean_fwci, h_index_oa, n_unique_coauthors, ...) → **462×30**
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
