# TODO: PracaDyplomowa_DS_UEWr

## ⏩ STAN NA 2026-06-13 — start następnej sesji tutaj

**Pipeline danych 02→03→04→05 kompletny.** Master: `profiles_features.csv` (462×30; 318 z OA).
**`renv::snapshot()` zrobiony** (lockfile zsync z R 4.6, +seriation/vegan/corrr). **06 zrefaktorowany i uruchomiony** ✓

**Decyzje metodyczne warstwy 1 (2026-06-13):**
- Czynniki: `uczelnia × stanowisko` (3 poziomy: adiunkt/prof. uczelni/profesor; **asystent wykluczony** — n=26, brak w UWM/UPWr).
- `kategoria` MEiN — **tylko opisowo** (współliniowa z uczelnią; UWM=jedyny B+). Confounding do Ograniczeń.
- Metryki MEiN (sum_MEiN, if_to_mein): SGGW=100% NA → auto-redukcja do 3 uczelni (droplevels).
- Wszystkie 6 metryk → ścieżka nieparametryczna (Kruskal-Wallis + Dunn-Bonferroni; rozkłady silnie skośne).
- Wyniki: `output/eda_summary.rds`, `eda_opisowe*.csv`, `Wykresy/eda/0{1,2,3}_*.png`.

**07 zrefaktorowany i uruchomiony** ✓ (2026-06-13)
- Cechy klastrowania: pełne pokrycie 4 uczelni (`h_index_wos, sum_IF, if_per_pub, n_pub`) — BEZ sum_MEiN/if_to_mein,
  które wyrzuciłyby całe SGGW. n=449.
- k=2 (silhouette): klaster wysokiego dorobku (n=104) vs reszta (n=345). PCA: PC1=54%, PC2=34%.
- Walidacja zewn.: niezależne od uczelni (χ² p=0.19, V=0.10), silnie zależne od stanowiska (V=0.45).
- ⚠️ Decyzja do rozważenia: silhouette dało k=2 (gruby podział). Jeśli praca chce bogatszej typologii (3-4 typy),
  trzeba wymusić k ręcznie i uzasadnić — na razie zostawione na danych.
- Wyniki: `output/clusters.rds`, `klaster_profile.csv`, `Wykresy/klastrowanie/0{1..7}_*.png`.

**08 zrefaktorowany i uruchomiony** ✓ (2026-06-13)
- Target `high_impact` = top 10% sum_IF GLOBALNIE (bez dyscypliny). n=452, 46 yes (10.2%).
- Predyktory: stanowisko, uczelnia, n_pub + OA (n_unique_coauthors, avg_authors_per_pub, mean_fwci; imputacja median).
- RF + XGB, 5-fold CV, tuning grid=10. Test: ROC AUC RF=0.953, XGB=0.931. SHAP: n_pub dominuje.
- ⚠️ Klasy niezbalansowane (10%) → przy progu 0.5 czułość=0.20 (model rankuje dobrze, ale klasyfikuje słabo).
  Decyzja do podjęcia: (a) raportować AUC jako headline + nota w Ograniczeniach, (b) rebalans (themis/case weights),
  (c) niższy próg targetu (top 20%). Na razie zostawione na surowych danych.
- Brakujące pakiety doinstalowane: tune, workflowsets, ranger, shapviz (+deps); `renv::snapshot()` zrobiony.
- Wyniki: `output/model_results.rds`, `Wykresy/modele/0{1..4}_*.png`.

**09 zrefaktorowany i uruchomiony** ✓ (2026-06-13)
- Naprawiony bug: master nie ma `openalex_id` → dołączony z `author_match.csv` (match_accepted) po author_id.
- Sieć wewn.: 318 węzłów / 465 krawędzi (weight≥2); giant component 210 (66%) / 430. Transitivity 0.42.
- Louvain: 19 społeczności, Q=0.852. ARI(społ.,stanowisko)=0.02 (NMI 0.13), ARI(społ.,uczelnia)=0.31 (NMI 0.62).
  → współpraca grupuje się wg AFILIACJI, nie roli akademickiej. Top węzły: grupa gleboznawcza UPWr.
- Doinstalowane: tidygraph, ggraph, graphlayouts (+ggforce); `renv::snapshot()` zrobiony.
- Wyniki: `output/network_metrics.rds`, `Dashboard/network.html`, `Wykresy/sieci/0{1..5}_*.png`.

**10 zrefaktorowany i uruchomiony** ✓ (2026-06-13) — WSZYSTKIE 4 WARSTWY DS + FIGURY GOTOWE.
- Fig 1-5 w `Wykresy/praca/` (proba, metryki box, klastrowanie, modele, sieć). Reuse RDS z 06-09, nic nie liczone od nowa.
- Fig 5 heatmap = community × uczelnia (silniejszy wynik niż stanowisko).

**🏁 MILESTONE: cały pipeline 02→10 uruchomiony end-to-end. Kandydat na named commit (decyzja użytkownika).**

**Następne kroki (priorytet):**
1. **Pisanie pracy** — `Praca/praca.qmd` to wciąż szkielet (Wyniki/Dyskusja/Wnioski puste, bib=2 wpisy).
   Wszystkie liczby/figury do sekcji Wyniki są policzone (output/*.rds, Wykresy/{eda,klastrowanie,modele,sieci,praca}/).
2. **Decyzje metodyczne do rozstrzygnięcia przy pisaniu:**
   - 07: k=2 (silhouette) — czy wymusić bogatszą typologię k=3/4?
   - 08: imbalance (sens=0.20) — raportować AUC + Ograniczenia / rebalans / niższy próg targetu?
   - kategoria MEiN, confounding uczelnia↔kategoria, luki SGGW(MEiN)/UWM(SNIP) → sekcja Ograniczenia.
3. **Diagnoza słabego matchu URK (47.5%)** — `clean_name_for_search` / ROR URK `012dxyr07`. URK rzadszy w sieci (77/162).

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
- [x] `06_eda_anova.R` — warstwa 1 (2-czynnikowa uczelnia × stanowisko; KW+Dunn; kategoria opisowo). Uruchomiony 2026-06-13.
- [x] `07_klastrowanie_pca.R` — warstwa 2 (PCA + k-means, k=2, cechy pełnego pokrycia). Uruchomiony 2026-06-13.
- [x] `08_modele_predykcja.R` — warstwa 3 (RF + XGB + SHAP; target globalny). Uruchomiony 2026-06-13. ⚠️ imbalance (sens=0.20).
- [x] `09_sieci_wspolautorstwa.R` — warstwa 4 (igraph + Louvain, Q=0.852, NMI uczelnia=0.62). Uruchomiony 2026-06-13.

- [x] `10_wykresy_pracy.R` — figury kompozytowe do pracy (fig 1-5). Uruchomiony 2026-06-13.

## Tydzień 10-13: Pisanie

- [x] Praca.qmd — **Wyniki** (P1-P4 + charakterystyka próby, 7 tabel, 5 figur). Render PDF+DOCX OK 2026-06-13.
- [x] Praca.qmd — **Dyskusja** (dwoistość profil~stanowisko / współpraca~afiliacja; kategoria MEiN; Ograniczenia) + **Wnioski** (P1-P4).
- [x] Metody poprawione: kategoria opisowo, asystent wykluczony, target sum_IF, dobór testu KW/ANOVA.
- [x] Bibliografia — 13 wpisów (Hirsch, Garfield, Moed, Waltman, Winkler, Breiman, Chen, Lundberg, Blondel, Newman, Hubert, Youden, +Omega/OpenAlex); cytowania wplecione w tekst.
- [x] 08 rozszerzony o optymalizację progu Youdena (OOF CV): czułość 0,20→1,00, bal.acc 0,91.
- [x] Naprawione znaki bez glifów w PDF (↔, ≈, −, indeksy górne).

**🏁 PEŁNY DRAFT PRACY (10 stron, PDF+DOCX) — kandydat na named commit (decyzja użytkownika).**

**Otwarte na później:**
- Diagnoza matchu URK 47,5% (jakość warstw OA — sieci/FWCI).
- Rozdz. „Procedura pozyskania danych" wciąż skrótowy (1 zdanie) — do rozwinięcia.
- Iteracje z promotorem.
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
