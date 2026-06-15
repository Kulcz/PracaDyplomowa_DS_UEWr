"""
Scraper LIST PUBLIKACJI Omega-PSIR (szeregi czasowe: rok + punkty per publikacja).

Cel: dla analizy DYNAMIKI ROZWOJU (output/rok) per uczelnia, odporne na bias
pokrycia OpenAlex. Ciagniemy bezposrednio z CRIS -> 100% proby, punktacja MEiN.

Wejscie: author_id znane z Dane/raw/<uni>_rolnictwo_i_ogrodnictwo_*.csv (ETAP 1
scrape.py juz wykonany - nie powtarzamy zbierania id).

Layout listy publikacji rozni sie per uczelnia (ten sam Omega-PSIR, inna konfiguracja):
- UPWR / URK: grupowanie rok (div.resultListHeader0 "2025[9]") -> punkty
  (div.resultListHeader1) -> wpisy (div.rowEntry). Rok i punkty z naglowkow grup.
- UWM: lista PLASKA (brak resultListHeader0). Rok wyciagany z TEKSTU wpisu
  (pierwszy 4-cyfrowy rok 1950-biezacy). Punkty niedostepne -> NA.
- SGGW: jak UPWR (grupowane), ale czesto >200 publikacji -> ucina sie na ps=200.

Ucinanie (ps=200, lista od najnowszych): autorzy >200 prac traca stare lata.
Rozwiazanie: paginacja przez '.ui-paginator-next' (PrimeFaces) az do wyczerpania.
Wykrycie: jesli na stronie 200 wpisow LUB istnieje aktywny przycisk next -> paginuj.

Output: Dane/raw/publications_omega/pub_years.csv (long: uczelnia, author_id, rok,
n_pub, sum_pkt, capped). Autosave co AUTOSAVE_EVERY autorow, RESUME pomija zrobionych.

Uruchomienie (z roota projektu, venv aktywny):
  python Skrypty/Python/scrape_publications.py                 # wszystkie 4 uczelnie
  python Skrypty/Python/scrape_publications.py --uni UWM       # jedna uczelnia
  python Skrypty/Python/scrape_publications.py --limit 3       # test: 3 osoby/uczelnia
"""
from __future__ import annotations

import argparse
import glob
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import pandas as pd
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright, Page, TimeoutError as PWTimeout

# ---------- Konfiguracja uczelni ----------
BASE = {
    "upwr": "https://bazawiedzy.upwr.edu.pl",
    "sggw": "https://bw.sggw.edu.pl",
    "urk":  "https://repo.ur.krakow.pl",
    "uwm":  "https://bazawiedzy.uwm.edu.pl",
}
WAIT = {"upwr": 6.0, "sggw": 6.0, "urk": 9.0, "uwm": 11.0}  # render listy (s)
PS = 200
AUTOSAVE_EVERY = 10
MAX_PAGES = 30                 # bezpiecznik paginacji (30*200 = 6000 publikacji)
YEAR_MIN, YEAR_MAX = 1950, datetime.now().year

OUT_DIR = Path("Dane/raw/publications_omega")
OUT_CSV = OUT_DIR / "pub_years.csv"
OUT_COLS = ["uczelnia", "author_id", "rok", "n_pub", "sum_pkt", "capped"]


def pub_url(uni: str, author_id: str) -> str:
    return (f"{BASE[uni]}/info/author/{author_id}"
            f"?r=publication&ps={PS}&tab=publications&lang=pl")


# ---------- Parser jednej strony: (rok, punkty) per wpis ----------
def parse_page(html: str) -> tuple[list[tuple[int, float | None]], bool]:
    """Zwraca (lista (rok, punkty) per publikacja, czy_layout_grupowany).

    Sekwencyjny przejazd DOM: header0 -> ustaw rok, header1 -> ustaw punkty,
    rowEntry -> emituj (rok, punkty). Dla layoutu plaskiego (UWM) rok z tekstu wpisu.
    """
    soup = BeautifulSoup(html, "lxml")
    grouped = bool(soup.select('[class*="resultListHeader0"]'))
    out: list[tuple[int, float | None]] = []

    if grouped:
        cur_year: int | None = None
        cur_pts: float | None = None
        # elementy istotne w kolejnosci dokumentu
        for el in soup.find_all(class_=re.compile(r"resultListHeader0|resultListHeader1|rowEntry")):
            cls = " ".join(el.get("class", []))
            txt = el.get_text(" ", strip=True)
            if "resultListHeader0" in cls:
                m = re.search(r"(19\d{2}|20\d{2})", txt)
                cur_year = int(m.group(1)) if m else None
                cur_pts = None
            elif "resultListHeader1" in cls:
                m = re.search(r"(\d[\d\s]*)", txt)
                cur_pts = float(re.sub(r"\s", "", m.group(1))) if m else None
            elif "rowEntry" in cls:
                if cur_year is not None:
                    out.append((cur_year, cur_pts))
    else:
        # layout plaski (UWM): rok z tekstu wpisu (pierwszy sensowny rok)
        for el in soup.select(".rowEntry"):
            txt = el.get_text(" ", strip=True)
            yrs = [int(y) for y in re.findall(r"\b(19\d{2}|20\d{2})\b", txt)
                   if YEAR_MIN <= int(y) <= YEAR_MAX]
            if yrs:
                out.append((yrs[0], None))   # pierwszy rok = rok publikacji
    return out, grouped


def has_next(page: Page) -> bool:
    try:
        return page.evaluate(
            "() => !!document.querySelector('a.ui-paginator-next:not(.ui-state-disabled)')"
        )
    except Exception:
        return False


def click_next(page: Page) -> bool:
    try:
        return page.evaluate("""() => {
            var el = document.querySelector('a.ui-paginator-next:not(.ui-state-disabled)');
            if (!el) return false;
            el.click(); return true;
        }""")
    except Exception:
        return False


def scrape_author(page: Page, uni: str, author_id: str) -> list[dict]:
    """Zwraca wiersze long: (uczelnia, author_id, rok, n_pub, sum_pkt, capped)."""
    url = pub_url(uni, author_id)
    try:
        page.goto(url, timeout=40_000, wait_until="domcontentloaded")
    except PWTimeout:
        return [{"uczelnia": uni, "author_id": author_id, "rok": -1,
                 "n_pub": 0, "sum_pkt": None, "capped": False}]
    time.sleep(WAIT[uni])

    all_entries: list[tuple[int, float | None]] = []
    capped = False
    for p in range(MAX_PAGES):
        html = page.content()
        entries, _ = parse_page(html)
        all_entries.extend(entries)
        if not has_next(page):
            break
        capped = True
        if not click_next(page):
            break
        time.sleep(WAIT[uni])
    else:
        capped = True  # wyczerpano MAX_PAGES

    # agregacja rok -> (n, suma punktow)
    agg: dict[int, list[float]] = {}
    for yr, pts in all_entries:
        if not (YEAR_MIN <= yr <= YEAR_MAX):
            continue
        a = agg.setdefault(yr, [0, 0.0, False])  # [n, sum_pkt, has_pkt]
        a[0] += 1
        if pts is not None:
            a[1] += pts
            a[2] = True
    rows = []
    for yr, (n, spkt, has_pkt) in sorted(agg.items()):
        rows.append({"uczelnia": uni, "author_id": author_id, "rok": yr,
                     "n_pub": n, "sum_pkt": spkt if has_pkt else None,
                     "capped": capped})
    if not rows:  # autor bez publikacji w zakresie
        rows = [{"uczelnia": uni, "author_id": author_id, "rok": 0,
                 "n_pub": 0, "sum_pkt": None, "capped": capped}]
    return rows


# ---------- Wejscie: author_id z surowych CSV ----------
def load_authors(unis: list[str], limit: int | None) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for uni in unis:
        files = sorted(glob.glob(f"Dane/raw/{uni}_rolnictwo_i_ogrodnictwo_*.csv"))
        if not files:
            print(f"[WARN] brak surowego CSV dla {uni}", file=sys.stderr)
            continue
        df = pd.read_csv(files[-1])
        ids = [a for a in df["author_id"].dropna().astype(str) if a]
        if limit:
            ids = ids[:limit]
        pairs.extend((uni, a) for a in ids)
    return pairs


def load_done() -> set[tuple[str, str]]:
    if not OUT_CSV.exists():
        return set()
    df = pd.read_csv(OUT_CSV)
    return set(zip(df["uczelnia"].astype(str), df["author_id"].astype(str)))


def save(rows: list[dict]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows, columns=OUT_COLS).to_csv(OUT_CSV, index=False, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--uni", default=None, help="UPWR/SGGW/URK/UWM (domyslnie wszystkie)")
    ap.add_argument("--limit", type=int, default=None, help="limit osob/uczelnia (test)")
    ap.add_argument("--no-resume", action="store_true")
    args = ap.parse_args()

    unis = [args.uni.lower()] if args.uni else ["upwr", "sggw", "urk", "uwm"]
    authors = load_authors(unis, args.limit)
    done = set() if args.no_resume else load_done()
    todo = [(u, a) for (u, a) in authors if (u, a) not in done]

    # zaladuj juz zapisane wiersze (zeby autosave nie nadpisal)
    existing_rows: list[dict] = []
    if OUT_CSV.exists() and not args.no_resume:
        existing_rows = pd.read_csv(OUT_CSV).to_dict("records")

    print(f"[CONFIG] uczelnie={unis} | autorow_total={len(authors)} | "
          f"juz_zrobione={len(done)} | do_zrobienia={len(todo)}")
    if not todo:
        print("Nic do zrobienia (wszystko w cache).")
        return 0

    rows = list(existing_rows)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, args=["--no-sandbox", "--disable-gpu"])
        page = browser.new_context().new_page()
        for i, (uni, aid) in enumerate(todo, start=1):
            t0 = time.time()
            try:
                r = scrape_author(page, uni, aid)
            except Exception as e:
                r = [{"uczelnia": uni, "author_id": aid, "rok": -1,
                      "n_pub": 0, "sum_pkt": None, "capped": False}]
                print(f"  [ERROR] {uni}/{aid}: {e}")
            rows.extend(r)
            yrs = [x["rok"] for x in r if x["rok"] > 0]
            cap = any(x["capped"] for x in r)
            print(f"[{i}/{len(todo)}] {uni}/{aid[:18]} | lata={len(yrs)} "
                  f"({min(yrs) if yrs else '-'}-{max(yrs) if yrs else '-'}) "
                  f"| pub={sum(x['n_pub'] for x in r)}{' CAPPED' if cap else ''} "
                  f"| {time.time()-t0:.1f}s")
            if i % AUTOSAVE_EVERY == 0 or i == len(todo):
                save(rows)
                print(f"  [AUTOSAVE] {len(rows)} wierszy -> {OUT_CSV}")
        browser.close()
    save(rows)
    print(f"\nGotowe. Zapisano {len(rows)} wierszy do {OUT_CSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
