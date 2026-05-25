"""
Core scraper Omega-PSIR: Playwright lifecycle + paginator + ETAP1/ETAP2 + autosave.

Niezalezne od konkretnej uczelni - przyjmuje BaseParser jako argument.
"""
from __future__ import annotations

import argparse
import sys
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

import pandas as pd
from playwright.sync_api import sync_playwright, Page, TimeoutError as PWTimeout

from .base import (
    BaseParser, ProfileRecord, COLUMNS,
    extract_author_ids_from_html, looks_like_block_page,
)


# ---------- Parametry runtime ----------
MAX_NEXT_CLICKS = 300
AUTOSAVE_EVERY = 10
LIST_RETRY = 3


# ---------- Paginator ----------
def go_to_next_page_js(page: Page) -> bool:
    """PrimeFaces paginator - klik przez JS (native click bywa ignorowany przez event delegation)."""
    script = """() => {
        var el = document.querySelector('a.ui-paginator-next:not(.ui-state-disabled)');
        if (!el) return 'no-button';
        if (el.getAttribute('aria-disabled') === 'true') return 'disabled';
        el.click();
        return 'clicked';
    }"""
    try:
        res = page.evaluate(script)
    except Exception as e:
        res = f"ERR:{e}"
    print(f"  [next-js] {res}")
    return res == "clicked"


def click_next_fallback(page: Page) -> bool:
    """Fallback Playwright native click."""
    selectors = [
        "a.ui-paginator-next:not(.ui-state-disabled)",
        "a.ui-paginator-next",
        "a[rel='next']",
        "a[aria-label*='Nast']",
        "a[title*='Nast']",
        "li.next a",
        ".pagination li.next a",
    ]
    for css in selectors:
        try:
            loc = page.locator(css).first
            if loc.count() > 0:
                loc.click(timeout=3000)
                print(f"  [click] OK przez CSS '{css}'")
                return True
        except Exception as e:
            print(f"  [click] CSS '{css}' ERR: {e}")
    return False


# ---------- Pobieranie profilu ----------
def get_profile_record(page: Page, parser: BaseParser, author_id: str,
                       debug_dir: Path | None = None) -> ProfileRecord:
    url = parser.UNI.profile_url(author_id)
    try:
        page.goto(url, timeout=30_000, wait_until="domcontentloaded")
    except PWTimeout:
        return ProfileRecord(author_id=author_id, url=url, error="goto-timeout")

    time.sleep(parser.WAIT_PROFILE)
    html = page.content()
    rec = parser.parse_profile(html)

    if not rec.has_any_data():
        time.sleep(3)
        html = page.content()
        rec = parser.parse_profile(html)

    if not rec.has_any_data() and looks_like_block_page(html):
        rec.error = "block-or-login-page"

    if not rec.has_any_data() and debug_dir is not None:
        (debug_dir / f"{author_id}.html").write_text(html, encoding="utf-8")

    rec.author_id = author_id
    rec.url = url
    return rec


# ---------- I/O ----------
def save_outputs(records: list[ProfileRecord], out_csv: Path) -> None:
    rows = [asdict(r) for r in records]
    df = pd.DataFrame(rows, columns=COLUMNS)
    df.to_csv(out_csv, index=False, encoding="utf-8")


# ---------- CLI ----------
def build_arg_parser(uni_choices: list[str]) -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Scraper Omega-PSIR (Python/Playwright)")
    p.add_argument("--uni", required=True, choices=sorted(uni_choices),
                   help="Kod uczelni: UPWR/SGGW/URK/UWM")
    p.add_argument("--dyscyplina", default="all",
                   help="Etykieta dyscypliny do tagowania plikow wyjsciowych")
    p.add_argument("--url", default=None,
                   help="Opcjonalny URL listy wynikow (override defaultu UniConfig)")
    p.add_argument("--out-dir", default="Dane/raw",
                   help="Katalog wyjsciowy (default: Dane/raw)")
    p.add_argument("--headless", action="store_true",
                   help="Headless mode (default: widoczne okno - filtr ustawia sie recznie)")
    p.add_argument("--max-pages", type=int, default=MAX_NEXT_CLICKS,
                   help=f"Limit klikniec next (default {MAX_NEXT_CLICKS})")
    p.add_argument("--limit-profiles", type=int, default=None,
                   help="Limit liczby profili do pobrania (do testow)")
    return p


# ---------- Main ----------
def run_scraper(parser: BaseParser, args: argparse.Namespace) -> int:
    cfg = parser.UNI
    results_url = args.url or cfg.results_url

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    debug_dir = out_dir / "debug_html" / cfg.code
    debug_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    file_stem = f"{cfg.code}_{args.dyscyplina}_{timestamp}"
    out_csv = out_dir / f"{file_stem}.csv"

    print(f"\n[CONFIG] UNI={cfg.name} | URL_RESULTS={results_url}")
    print(f"[TIMING] wait_profile={parser.WAIT_PROFILE}s | wait_results={parser.WAIT_RESULTS}s")
    print(f"[OUT] {out_csv}")

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=args.headless,
                                     args=["--no-sandbox", "--disable-gpu"])
        context = browser.new_context()
        page = context.new_page()
        page.goto(results_url, timeout=30_000, wait_until="domcontentloaded")
        time.sleep(parser.WAIT_RESULTS)

        print("\n--- OKNO CHROMIUM OTWARTE ---")
        print("Ustaw filtry w panelu po lewej i kliknij 'Filtruj'.")
        input("Gdy filtry sa ustawione i zastosowane, wcisnij ENTER w terminalu... ")

        cur_url = page.url
        html = page.content()
        print(f"\n[DIAG] aktualny URL : {cur_url}")
        print(f"[DIAG] rozmiar HTML : {len(html)} znakow")
        screen_path = debug_dir / "screen_after_enter.png"
        try:
            page.screenshot(path=str(screen_path), full_page=False)
            print(f"[DIAG] screenshot   : {screen_path}")
        except Exception as e:
            print(f"[DIAG] screenshot ERROR: {e}")

        # ---------- ETAP 1: author_id ----------
        print("\n[ETAP 1] Zbieram author_id...")
        all_ids: list[str] = []
        prev_ids_on_page: list[str] = []
        no_growth = 0

        for k in range(1, args.max_pages + 1):
            time.sleep(parser.WAIT_RESULTS)
            html = page.content()
            ids = extract_author_ids_from_html(html, cfg.author_id_regex)

            for retry in range(1, LIST_RETRY):
                if ids:
                    break
                print(f"strona={k} | brak wynikow w DOM, retry {retry}/{LIST_RETRY - 1} po {parser.WAIT_RESULTS}s...")
                time.sleep(parser.WAIT_RESULTS)
                html = page.content()
                ids = extract_author_ids_from_html(html, cfg.author_id_regex)

            if not ids:
                break

            before = len(all_ids)
            for fid in ids:
                if fid not in all_ids:
                    all_ids.append(fid)
            added = len(all_ids) - before
            print(f"strona={k} | ids_na_stronie={len(ids)} | unikalne={len(all_ids)} | +{added}")

            if k == 1:
                dump = debug_dir / "page1_source.html"
                dump.write_text(html, encoding="utf-8")
                print(f"  [DEBUG] zapis HTML strony 1: {dump}")

            same_page = bool(prev_ids_on_page) and ids == prev_ids_on_page
            prev_ids_on_page = ids
            no_growth = no_growth + 1 if (added == 0 or same_page) else 0
            if no_growth >= 2:
                break

            moved = go_to_next_page_js(page) or click_next_fallback(page)
            if not moved:
                break

        print(f"\nZebrano profili: {len(all_ids)}")
        if not all_ids:
            browser.close()
            print("Nie zebrano zadnych profili - sprawdz filtry i liste wynikow.", file=sys.stderr)
            return 1

        if args.limit_profiles is not None:
            all_ids = all_ids[: args.limit_profiles]
            print(f"[LIMIT] Ograniczono do {len(all_ids)} profili (--limit-profiles)")

        # ---------- ETAP 2: profile ----------
        print("\n[ETAP 2] Pobieram dane z profili (HTML)...")
        records: list[ProfileRecord] = []
        for i, aid in enumerate(all_ids, start=1):
            print(f"[{i}/{len(all_ids)}] {aid}")
            try:
                rec = get_profile_record(page, parser, aid, debug_dir=debug_dir)
            except Exception as e:
                rec = ProfileRecord(author_id=aid, url=cfg.profile_url(aid), error=str(e))
                print(f"  [ERROR] {e}")

            records.append(rec)
            if i <= 5:
                preview = {k: getattr(rec, k) for k in
                           ("profil", "jednostka", "wydzial", "h_index_scopus", "sum_IF", "sum_MEiN", "n_pub")}
                print(f"  -> {preview}")

            if i % AUTOSAVE_EVERY == 0 or i == len(all_ids):
                save_outputs(records, out_csv)
                print(f"  [AUTOSAVE] zapisano {i}/{len(all_ids)} do: {out_csv}")

        save_outputs(records, out_csv)
        print(f"\nZapisano: {out_csv}")
        print(f"Debug HTML (dla profili bez danych): {debug_dir.resolve()}")

        browser.close()
    return 0
