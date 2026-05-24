# Pamięć projektu: PracaDyplomowa_DS_UEWr

## Charakter projektu

Praca dyplomowa studiów podyplomowych Data Science na Uniwersytecie Ekonomicznym we Wrocławiu. Analiza bibliometryczna 3 dyscyplin × 4 uczelni przyrodniczych (~1500-2500 naukowców). Trzy warstwy DS: klastrowanie + modelowanie predykcyjne + sieci współautorstwa.

Pełny plan: `~/.claude/plans/chce-wykona-projekt-ko-cowy-zany-rabbit.md`

Fundament metodyczny: `~/Analiza_projekty/UPWr_bibliometria` (scraper UPWr, analiza WPT). Wiele patternów stąd reusable — przy implementacji najpierw sprawdź czy nie ma już gotowego rozwiązania w UPWr_bibliometria.

## Środowisko

- **IDE:** Positron (cwd = root projektu)
- **R:** zarządzane przez renv (`renv::restore()` przy first run)
- **Python:** nie używamy (to jest projekt R-only)
- **Quarto:** rendering pracy do PDF + DOCX

## Konfiguracja uczelni (Omega-PSIR)

Wszystkie 4 potwierdzone (audyt 2026-05-24):

- UPWR: bazawiedzy.upwr.edu.pl
- SGGW: bazawiedzy.sggw.edu.pl
- URK: repo.ur.krakow.pl
- UWM: bazawiedzy.uwm.edu.pl

Identyczna struktura URL Omega-PSIR (`/search/author?...` + `/info/author/<id>`).

## Workflow scrapingu

1. Otwórz Bazę Wiedzy uczelni w przeglądarce.
2. Ustaw filtr dyscypliny w panelu po lewej, kliknij "Filtruj".
3. Skopiuj URL z paska adresu i wstaw jako `results_url` w `UNIVERSITY_CONFIG` (`Skrypty/R/01_scraper_omegapsir.R`).
4. `Sys.setenv(UNI = "...")`, `Sys.setenv(DYSCYPLINA = "...")`, `source(...)`.
5. Scraper czeka na ENTER po otwarciu Chrome — pozwala doprecyzować filtry.

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

## Plan harmonogramu

| Tydzień | Etap |
|---|---|
| 1 | Audyt uczelni + scaffold (✓ zrobione) |
| 2-3 | Pełny scraping 12 komórek |
| 4 | Czyszczenie + matching OpenAlex |
| 5 | OpenAlex Works (publikacje + coauthors) |
| 6 | EDA + 2-czynnikowa ANOVA |
| 7 | Klastrowanie + PCA |
| 8 | Modele predykcyjne + SHAP |
| 9-10 | Sieci współautorstwa |
| 11-13 | Pisanie pracy + iteracje z promotorem |
