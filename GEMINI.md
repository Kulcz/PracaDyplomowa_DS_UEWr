# Kontekst projektu dla agenta: PracaDyplomowa_DS_UEWr

> Plik kontekstu dla agenta Gemini (Antigravity). Odpowiednik `CLAUDE.md`
> używanego przez Claude Code. Zawiera wiedzę o projekcie + zasady pracy.

## Zasady pracy agenta (PRZECZYTAJ NAJPIERW)

- **Zwracaj się do użytkownika po polsku, per „ty".** Zwięźle, bez preambuł.
- **To repozytorium git.** Przed większymi zmianami (>2 plików) najpierw
  opisz, co zamierzasz zrobić, i poczekaj na zgodę. Wolę zatwierdzić plan
  niż cofać zmiany.
- **NIE uruchamiaj destrukcyjnych komend git** (`reset --hard`, `rebase`,
  `clean`, `push --force`). Projekt jest auto-synchronizowany między dwoma
  komputerami — przepisanie historii produkuje konflikty. Git obsługuje
  użytkownik ręcznie.
- **NIE commituj sam.** Zmiany zapisuje auto-sync (`spa`). Named commit
  tylko gdy użytkownik wprost poprosi.
- **Przy wyborach metodologicznych** (test statystyczny, transformacja
  danych, metoda interpolacji/klastrowania) zadaj 1–3 pytania zamiast iść
  z domyślnym założeniem.
- **NIE używaj `sed -i` na plikach w `~/pCloudDrive/`** — zeruje pliki.
- Renderowanie Quarto/LaTeX: jeden render, sprawdź wynik, nie iteruj w pętli.

## Charakter projektu

Praca dyplomowa studiów podyplomowych Data Science (Uniwersytet Ekonomiczny
we Wrocławiu). Analiza bibliometryczna naukowców dyscypliny **rolnictwo
i ogrodnictwo** w **4 polskich uczelniach przyrodniczych z systemem
Omega-PSIR** (~491 osób). Trzy warstwy DS: klastrowanie + modelowanie
predykcyjne + sieci współautorstwa.

**4 uczelnie Omega-PSIR (decyzja 2026-05-26 po teście kompletności CRIS):**

| Uczelnia | Kategoria MEiN | CRIS | n |
|---|---|---|---:|
| UPWR — Uniwersytet Przyrodniczy we Wrocławiu | A | Omega-PSIR | 146 |
| SGGW — Szkoła Główna Gospodarstwa Wiejskiego | A | Omega-PSIR | 112 |
| URK — Uniwersytet Rolniczy w Krakowie | A | Omega-PSIR | 163 |
| UWM — Uniwersytet Warmińsko-Mazurski | B+ | Omega-PSIR | 70 |
| **Razem** | | | **491** |

**Kryterium próby:** polskie uczelnie ewaluowane w dyscyplinie rolnictwo
i ogrodnictwo (wykaz MEiN) z publicznie dostępnym CRIS-em Omega-PSIR.
Homogeniczność metodyki ekstrakcji (1 system, ten sam parser) ważniejsza
niż jednorodność kategorii ewaluacji. Kategoria A vs B+ jako zmienna
kontrolna (3A + 1B+, niezbalansowana — nie główny czynnik).

**Strategia metodyczna B (2026-05-26):** z CRIS Omega-PSIR ciągniemy
TOŻSAMOŚĆ + LOKALNE METRYKI (sum_IF, sum_SNIP, sum_MEiN, h_index_scopus,
h_index_wos, n_pub). OpenAlex jako **uzupełnienie** (FWCI, cited_by_count,
sieci współautorstwa) i **QA cross-check**. Omega-PSIR jest średnio 2–3×
bogatszy katalog niż OpenAlex (akceptuje polskie czasopisma, książki,
materiały konferencyjne nieindeksowane w Scopus/WoS).

**Próba zarchiwizowana w `Dane/raw/_archive/` (poza core analizą):**
- UP Poznań (DSpace niekompletny — Potarzycki: 9 prac w DSpace vs 66 OpenAlex
  vs 112 w wykazie). Dane finansowe/model OA — ewentualny materiał do Dyskusji.
- UP Lublin (OpenUP, kategoria B+, asymetryczna metodyka).

Fundament metodyczny: pilotaż **`pilot_UPWr/`** (wchłonięty 2026-05-31 dawny
projekt `UPWr_bibliometria`) — scraper UPWr i analiza wydziału WPT. Wiele
patternów stąd reusable. Notatki: `pilot_UPWr/CLAUDE_pilot_archiwum.md`.

## Środowisko

- **IDE użytkownika:** Positron (cwd = root projektu). Antigravity to
  narzędzie pomocnicze, nie zamiennik.
- **R:** zarządzane przez renv (`renv::restore()` przy first run) — analiza,
  modelowanie, raporty.
- **Python:** scrapery Omega-PSIR (Playwright/Selenium) — venv lokalnie
  w projekcie; wymiana danych z R przez CSV.
- **Quarto:** rendering pracy do PDF + DOCX.

## Konfiguracja uczelni (4 Omega-PSIR)

| Uczelnia | URL | Specyfika |
|---|---|---|
| UPWR | bazawiedzy.upwr.edu.pl | label `MEiN`, WAIT_PROFILE 6s |
| SGGW | bw.sggw.edu.pl (stara `bazawiedzy.sggw.edu.pl` daje 404) | brak sum_MEiN w UI (100% NA), niska ekstrakcja `wydzial` (5%) — TODO override |
| URK | repo.ur.krakow.pl | label `ministerialna`, WAIT_PROFILE 12s |
| UWM | bazawiedzy.uwm.edu.pl | label `ministerialna`, WAIT_PROFILE 12s, brak sum_SNIP w UI (0%) |

Per-uczelnia różnice + strategia ekstrakcji — szczegóły w
`Skrypty/Python/README.md`.

## Workflow scrapingu

Stack: Python 3.12 + Playwright (Chromium bundled) + BeautifulSoup. Parsery
per uczelnia w `Skrypty/Python/scrapers/{upwr,sggw,urk,uwm}.py` dziedziczą
z `OmegaPsirBaseParser`. R-scraper zarchiwizowany w `Skrypty/R/_archive/`.

1. `source .venv/bin/activate`
2. `python Skrypty/Python/scrape.py --uni <UPWR|SGGW|URK|UWM> --dyscyplina rolnictwo_i_ogrodnictwo`
3. Otwiera się Chromium — ręcznie ustaw filtr dyscypliny, kliknij „Filtruj".
4. ENTER w terminalu — ETAP 1 (paginator → author_id), ETAP 2 (profile + autosave co 10).
5. Wynik: `Dane/raw/<code>_<dyscyplina>_<timestamp>.csv`.

## Konwencje kodu

- Komentarze nagłówkowe `# LTeX: enabled=false` w skryptach R.
- Polskie znaki w outputach (raporty, wykresy); w komentarzach kodu można
  bez ogonków.
- Tabele w Quarto: zawsze pipe-tables.
- Nowe dokumenty: zawsze `.qmd` z YAML PDF+DOCX.

## Zasady pracy z literaturą

Baza Markdown: `~/pCloudDrive/Zotero_markdown/INDEKS.md`. Workflow
przeszukiwania 6-krokowy. Cytaty z numerami linii w plikach `*_merged.md`.
Każde twierdzenie merytoryczne weryfikuj w min. 2 niezależnych źródłach.

## Plan harmonogramu (2026-05-26)

| Tydzień | Etap | Status |
|---|---|---|
| 1 | Audyt uczelni + scaffold | ✓ |
| 2 | Scraping 4 uczelni × 1 dyscyplina | ✓ |
| 3 | Czyszczenie + matching OpenAlex (ROR-y, ORCID) | bieżący |
| 4 | OpenAlex Works (FWCI + h-index + sieci współautorstwa) | |
| 5 | EDA + 2-czynnikowa ANOVA (uczelnia × stanowisko, kategoria jako kontrola) | |
| 6 | Klastrowanie + PCA (typologia profili bibliometrycznych) | |
| 7 | Modele predykcyjne + SHAP | |
| 8-9 | Sieci współautorstwa (igraph + Louvain) | |
| 10-13 | Pisanie pracy + iteracje z promotorem | |
