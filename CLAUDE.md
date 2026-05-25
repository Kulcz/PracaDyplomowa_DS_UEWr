# Pamięć projektu: PracaDyplomowa_DS_UEWr

## Charakter projektu

Praca dyplomowa studiów podyplomowych Data Science na Uniwersytecie Ekonomicznym we Wrocławiu. Analiza bibliometryczna 3 dyscyplin × **6 uczelni przyrodniczych** (~3000-4500 naukowców). Trzy warstwy DS: klastrowanie + modelowanie predykcyjne + sieci współautorstwa.

**6 uczelni (TOP 6 ośrodków rolniczych w Polsce, decyzja 2026-05-25):**
- UPWr, SGGW, URK, UWM (Omega-PSIR)
- UP Poznań (DSpace-CRIS REST API)
- UP Lublin (OpenUP - własny CRIS oparty o ASP.NET MVC)

**Strategia metodyczna B (decyzja 2026-05-25):** z CRIS uczelnianych ciągniemy TYLKO TOŻSAMOŚĆ (kto, gdzie, ORCID/POL-on/Scopus ID, dyscyplina). Metryki bibliometryczne (h-index, FWCI, n_pub, cited_by_count) liczymy z OpenAlex jednolicie dla wszystkich 6 uczelni. Eliminuje to różnice per system CRIS i daje globalnie porównywalne FWCI zamiast lokalnego IF. Strata: brak sum_MEiN (polska metryka, OpenAlex jej nie ma) — ale ta i tak była problematyczna (SGGW jej nie eksponuje).

**Dyscypliny (decyzja 2026-05-24, po pre-screeningu OpenAlex):**
- rolnictwo i ogrodnictwo (baza referencyjna)
- weterynaria (kontrast bio-STEM: duże zespoły, wysokie IF)
- zootechnika i rybactwo (drugi pion zwierzęcy, klasyka dziedziny rolniczej)

Wszystkie 3 w dziedzinie nauk rolniczych (rozporządzenie MEiN) — spójność systemu punktacji + bezpieczne liczebności na każdej z 4 uczelni (≥800 prac per komórka w OpenAlex).

**Odrzucone:** „nauki leśne" — UPWR ma bardzo małą reprezentację (155 prac vs 1249 SGGW), brak osobnego wydziału leśnego.

Pełny plan: `~/.claude/plans/chce-wykona-projekt-ko-cowy-zany-rabbit.md`

Fundament metodyczny: `~/Analiza_projekty/UPWr_bibliometria` (scraper UPWr, analiza WPT). Wiele patternów stąd reusable — przy implementacji najpierw sprawdź czy nie ma już gotowego rozwiązania w UPWr_bibliometria.

## Środowisko

- **IDE:** Positron (cwd = root projektu)
- **R:** zarządzane przez renv (`renv::restore()` przy first run) — analiza, modelowanie, raporty
- **Python:** używamy do scrapingu (Playwright/Selenium dojrzalsze niż w R) — venv lokalnie w projekcie; wymiana danych z R przez CSV/Parquet
- **Quarto:** rendering pracy do PDF + DOCX

## Konfiguracja uczelni (6 CRIS)

| Uczelnia | System | URL |
|---|---|---|
| UPWR | Omega-PSIR | bazawiedzy.upwr.edu.pl |
| SGGW | Omega-PSIR | **bw.sggw.edu.pl** (stara `bazawiedzy.sggw.edu.pl` daje 404) |
| URK | Omega-PSIR | repo.ur.krakow.pl |
| UWM | Omega-PSIR | bazawiedzy.uwm.edu.pl |
| UP Poznań | **DSpace-CRIS** | sciencerep.up.poznan.pl (REST API JSON, bez Playwright) |
| UP Lublin | **OpenUP** | open.up.lublin.pl (ASP.NET MVC, Playwright + httpx) |

Per-CRIS różnice + strategia ekstrakcji — szczegóły w `Skrypty/Python/README.md`. Najważniejsze:

- **SGGW nie eksponuje sum_MEiN/punktacji ministerialnej** w UI profilu — pole 100% NA.
- **URK i UWM** używają labela `Sumaryczna punktacja ministerialna` (nie `MEiN`).
- **URK/SGGW/UWM** wymagają `WAIT_PROFILE ≥ 12 s` (PrimeFaces wolniej ładuje).
- **UP Poznań DSpace**: tożsamość przez REST API — `person.researcharea` jako pole tekstowe, POL-on ID 100% pokrycia, ORCID 92%. Brak h-index/IF/n_pub w CRIS (uzupełnia OpenAlex).
- **UP Lublin OpenUP**: lista przez Playwright, profile przez raw httpx (38 KB HTML). Bonus: Scopus Author ID + LICZBA PUNKTÓW (= sum_MEiN). Header z tytułem+katedrą jest renderowany JS — brakuje go w raw HTTP.

## Workflow scrapingu

Stack: Python 3.12 + Playwright (Chromium bundled) + BeautifulSoup. Parsery per uczelnia w `Skrypty/Python/scrapers/{upwr,sggw,urk,uwm}.py` dziedziczą z `BaseParser`. R-scraper zarchiwizowany w `Skrypty/R/_archive/`.

1. `source .venv/bin/activate`
2. `python Skrypty/Python/scrape.py --uni URK --dyscyplina rolnictwo_i_ogrodnictwo`
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

## Plan harmonogramu

| Tydzień | Etap |
|---|---|
| 1 | Audyt uczelni + scaffold (✓ zrobione) |
| 2-3 | Pełny scraping **18 komórek (3 dyscypliny × 6 uczelni)** |
| 4 | Czyszczenie + matching OpenAlex (ROR-y, ORCID, POL-on, Scopus ID) |
| 5 | OpenAlex Works (publikacje + coauthors + FWCI dla wszystkich 6 uczelni jednolicie) |
| 6 | EDA + 2-czynnikowa ANOVA |
| 7 | Klastrowanie + PCA |
| 8 | Modele predykcyjne + SHAP |
| 9-10 | Sieci współautorstwa |
| 11-13 | Pisanie pracy + iteracje z promotorem |
