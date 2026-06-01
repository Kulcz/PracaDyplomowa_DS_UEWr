# UPWr_bibliometria (pilotaż — podprojekt PracaDyplomowa_DS_UEWr)

> **Status (2026-05-31):** To NIE jest już samodzielny projekt. Dawny
> `UPWr_bibliometria` został wchłonięty jako **pilotaż** do nadrzędnej pracy
> dyplomowej **PracaDyplomowa_DS_UEWr** i żyje w podfolderze `pilot_UPWr/`.
> Nie ma własnego `renv`/`.venv`/git — korzysta z parasola projektu nadrzędnego.
> Wszystkie ścieżki w skryptach są względne → uruchamiać z cwd `pilot_UPWr/`.
> Rolę pilotażu i listę reużywalnych modułów opisuje nadrzędny `CLAUDE.md`
> (sekcja „Pilotaż wchłonięty: pilot_UPWr/”). Poniższy opis jest historyczny.

## 📋 Opis projektu

Analiza bibliometryczna pracowników Uniwersytetu Przyrodniczego we Wrocławiu
na podstawie danych z portalu Baza Wiedzy UPWr. Pipeline obejmuje:

1. **Scraping** profili i metryk (h-index WoS/Scopus, sumaryczny IF, SNIP,
   punktacja MEiN) z Bazy Wiedzy (Selenium + parsowanie HTML).
2. **Czyszczenie i analizę** — obecnie skupioną na Wydziale
   Przyrodniczo-Technologicznym (WPT, n = 145): statystyki opisowe,
   diagnostyka założeń, testy porównawcze (ANOVA/Kruskal-Wallis), korelacje.
3. **Wizualizacje** (ggplot2) i **raporty Quarto** → PDF: zbiorczy raport
   wydziałowy oraz indywidualne profile pracowników.

## 📁 Struktura katalogów

```
UPWr_bibliometria/
├── Skrypty/
│   ├── R/                    # 01_scraper, 02_czyszczenie_analiza, 03_analiza_pracownicy
│   └── Python/               # narzędzia utility (obecnie pusty)
├── output_bibliometria/      # dane (surowe ze scrapera + oczyszczone) i wyniki CSV/Excel
│   └── debug_html/           # zrzuty HTML profili bez danych (debug scrapera)
├── Wykresy/WPT/              # wykresy (PNG) — rozkłady, boxploty, rankingi, korelacje
├── Raport/
│   ├── wydzial/              # raport_WPT.qmd + PDF
│   └── pracownicy/           # indywidualne profile (.qmd + PDF)
└── Tasks/                    # todo.md — lista zadań i postęp
```

## 📊 Dane

- **Surowe** (cała uczelnia): `output_bibliometria/upwr_profiles_metrics_HTML_<timestamp>.csv`
  (148 profili, scraping z 2026-03-06).
- **Oczyszczone** (WPT, 145 rekordów): `output_bibliometria/WPT_oczyszczone.csv`.
- **Rankingi**: `output_bibliometria/WPT_ranking_pracownikow.xlsx`.

## ⚙️ Uruchomienie

Ścieżki w skryptach są względne od roota projektu (`getwd()` = katalog z `.Rproj`).

```r
# 1. Scraping (wymaga uruchomionego chromedriver na porcie 9515)
source("Skrypty/R/01_scraper_baza_wiedzy.R")
# 2. Czyszczenie + analiza WPT (statystyki, testy, wykresy)
source("Skrypty/R/02_czyszczenie_analiza_WPT.R")
# 3. Analiza indywidualna pracowników (rankingi, eksport Excel)
source("Skrypty/R/03_analiza_pracownicy_WPT.R")
```

Raporty: renderowanie `.qmd` w `Raport/` (Quarto → PDF).

## 🐍 R i Python

```r
# Pakiety R zarządzane przez renv
renv::restore()   # przywrócenie pakietów z renv.lock
```

```bash
# Python (utility) — venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 📝 Notatki

- Data utworzenia: 2026-03-06
- Autor: Grzegorz Kulczycki
- Synchronizacja między komputerami: alias `spa` (auto-sync projektów dom/praca).
