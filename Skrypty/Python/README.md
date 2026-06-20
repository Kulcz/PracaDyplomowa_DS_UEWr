## Scrapery CRIS uczelnianych — Python

Modułowy zestaw scraperów Bazy Wiedzy / CRIS dla polskich uczelni przyrodniczych w dyscyplinie „rolnictwo i ogrodnictwo". Trzy różne systemy źródłowe — każdy ma własny parser dziedziczący ze wspólnego interfejsu `BaseParser`.

> **Aktywny core analizy = 4 uczelnie Omega-PSIR** (UPWr, SGGW, URK, UWM). Parsery `up_poznan.py` (DSpace) i `up_lublin.py` (OpenUP) są **historyczne/pomocnicze**: pozostają w kodzie na wypadek powrotu, ale nie wchodzą do core analizy (DSpace UP Poznań niekompletny ~10–15 % dorobku, OpenUP asymetryczny metodycznie; szczegóły w głównym `CLAUDE.md`). Dane tych dwóch uczelni usunięto z repo 2026-06-20 (backup zewnętrzny). Poniższe sekcje opisujące UP Poznań / UP Lublin dotyczą więc trybu historycznego.

### Architektura

```
Skrypty/Python/
├── scrape.py              # entry point CLI (dispatch po --uni → parser.run(args))
├── scrape_publications.py # pełne listy publikacji + rok wydania (warstwa dynamiki, skrypt R 12)
└── scrapers/
    ├── __init__.py        # REGISTRY: 6 parserów (4 core Omega-PSIR + 2 historyczne)
    ├── base.py            # BaseParser (ABC) + OmegaPsirBaseParser + helpery
    ├── core.py            # Playwright + paginator PrimeFaces (dla Omega-PSIR)
    ├── upwr.py            # UPWRParser    — Omega-PSIR    — label MEiN,         wait 6s
    ├── sggw.py            # SGGWParser    — Omega-PSIR    — sum_MEiN nie w UI,  wait 12s
    ├── urk.py             # URKParser     — Omega-PSIR    — label ministerialna,wait 12s
    ├── uwm.py             # UWMParser     — Omega-PSIR    — label ministerialna,wait 12s
    ├── up_poznan.py       # UPPoznanParser — DSpace-CRIS REST API (JSON, bez Playwright)
    └── up_lublin.py       # UPLublinParser — OpenUP (Playwright lista + httpx profile)
```

### Setup (jednorazowo, w roocie projektu)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium    # ~150 MB do ~/.cache/ms-playwright/
```

### Użycie

```bash
source .venv/bin/activate

# Omega-PSIR (UPWr, SGGW, URK, UWM): wymaga ręcznego ustawienia filtra
python Skrypty/Python/scrape.py --uni URK --dyscyplina rolnictwo_i_ogrodnictwo

# UP Poznań (DSpace REST API): automatyczny, ~30 s na całą uczelnię
python Skrypty/Python/scrape.py --uni UP_POZNAN --dyscyplina rolnictwo_i_ogrodnictwo

# UP Lublin (OpenUP): automatyczny, ~15-20 min (Playwright + 2257 profili)
python Skrypty/Python/scrape.py --uni UP_LUBLIN --dyscyplina rolnictwo_i_ogrodnictwo
```

Flow per uczelnia:

**Omega-PSIR (UPWr/SGGW/URK/UWM):**
1. Otwiera Chromium z URL `/search/author` danej uczelni.
2. Ręcznie ustawiasz filtr dyscypliny w panelu po lewej → „Filtruj".
3. ENTER w terminalu → ETAP 1 (paginator → author_id) → ETAP 2 (profile + autosave).

**UP Poznań (DSpace REST):**
1. Pobiera wszystkie ~933 osoby przez REST API (paginacja przez `?size=100&page=N`).
2. Filtruje po polu `person.researcharea` w Pythonie (DSpace nie ma facetu dla researcharea).
3. Zapisuje CSV (~30 s end-to-end).

**UP Lublin (OpenUP):**
1. ETAP 1: Playwright + paginator listy osób (~76 stron × 30 osób = 2257).
2. ETAP 2: dla każdego ID raw HTTP request, parser `<label class="control-label">` + sibling `<div>`.
3. Filtrowanie dyscypliny: na razie nie w API — pobierz wszystkich, filtruj w R po `stanowisko`/`jednostka` (która przyjdzie z OpenAlex).

### Flagi CLI

| Flaga | Domyślnie | Opis |
|---|---|---|
| `--uni` | (wymagane) | `UPWR` / `SGGW` / `URK` / `UWM` / `UP_POZNAN` / `UP_LUBLIN` |
| `--dyscyplina` | `all` | Etykieta do nazwy pliku + filtr researcharea (UP Poznań) |
| `--url` | z `UniConfig` | Override URL listy (Omega-PSIR) |
| `--out-dir` | `Dane/raw` | Katalog wyjściowy |
| `--headless` | off (Omega) / on (UP_LUBLIN) | Bez okna |
| `--max-pages` | 300 / 50 / 200 | Limit klików next (Omega / UP Poznań paginacja / UP Lublin) |
| `--limit-profiles` | brak | Limit pobranych profili (do testów) |

### Schemat CSV (ujednolicony dla wszystkich parserów)

```
profil, tytul, stanowisko, jednostka, wydzial, orcid,
scopus_id, polon_id, researcharea,
h_index_scopus, h_index_wos, sum_IF, sum_SNIP, sum_MEiN, n_pub,
author_id, url, error
```

Pola których dana uczelnia nie eksponuje → `None`/pusta komórka (przewidywane braki opisane niżej).

### Strategia metodyczna (FINAL 2026-05-26, rewizja decyzji z 2026-05-25)

**Omega-PSIR jest źródłem podstawowym** metryk bibliometrycznych. Z CRIS ciągniemy tożsamość (kto, gdzie pracuje, ORCID/POL-on/Scopus ID, stanowisko) **oraz lokalne agregaty** (`sum_IF`, `sum_SNIP`, `sum_MEiN`, `h_index_wos/scopus`, `n_pub`). OpenAlex pełni rolę **uzupełniającą** (`FWCI`, `cited_by_count`, sieci współautorstwa) i cross-checku QA dla metryk lokalnych (`Skrypty/R/04_openalex_works.R`, `05_features.R`).

Skutki:
- Wcześniejsza wersja („OpenAlex jako primary, Omega-PSIR jako cross-check") została zrewidowana po teście kompletności 2026-05-26: Omega-PSIR to średnio 2-3× bogatszy katalog (polskie czasopisma, monografie, materiały konferencyjne nieindeksowane w Scopus/WoS).
- `sum_MEiN` (polska metryka, nieobecna w OpenAlex) bierzemy gdzie jest (UPWr, URK, UWM; SGGW nie eksponuje w UI → 100% NA); w analizie międzyuczelnianej ograniczono ją do 3 uczelni.

### Różnice per uczelnia (źródła danych)

| Uczelnia | System | h-index/IF w CRIS | sum_MEiN | Filtr dyscypliny | Bonus pola |
|---|---|---|---|---|---|
| UPWR | Omega-PSIR | ✓ (cross-check) | ✓ MEiN | ręczny w UI | — |
| SGGW | Omega-PSIR | ✓ (cross-check) | ✗ (brak w UI) | ręczny w UI | — |
| URK | Omega-PSIR | ✓ (cross-check) | ✓ ministerialna | ręczny w UI | — |
| UWM | Omega-PSIR | ✓ (cross-check) | ✓ ministerialna | ręczny w UI | — |
| UP Poznań | DSpace REST | ✗ | ✗ | po polu `researcharea` (programowo) | **POL-on ID (100%)**, researcharea jako pole |
| UP Lublin | OpenUP HTML | ✗ | ✓ („liczba punktów") | brak — filtr w R po wydziale | **Scopus Author ID** |

### Dodanie nowej uczelni

1. Sprawdź jakim systemem CRIS uczelnia dysponuje (Omega-PSIR / DSpace / Pure / Sciencecloud / własny).
2. Jeśli Omega-PSIR — utwórz `scrapers/xxx.py` dziedziczący z `OmegaPsirBaseParser`, override `LABEL_SUM_MEIN` i `WAIT_PROFILE` jeśli trzeba.
3. Jeśli DSpace — wzoruj na `up_poznan.py` (REST API).
4. Jeśli inny — własny parser dziedziczący z `BaseParser`, własna metoda `run(args)`.
5. Zarejestruj klasę w `scrapers/__init__.py` w `REGISTRY`.

### Test krótki

```bash
python Skrypty/Python/scrape.py --uni UP_POZNAN --dyscyplina rolnictwo_i_ogrodnictwo
# ~30s, output: Dane/raw/up_poznan_rolnictwo_i_ogrodnictwo_<ts>.csv

python Skrypty/Python/scrape.py --uni UP_LUBLIN --dyscyplina test --limit-profiles 10 --max-pages 1
# ~30s, output: Dane/raw/up_lublin_test_<ts>.csv (10 osob z pierwszej strony)
```
