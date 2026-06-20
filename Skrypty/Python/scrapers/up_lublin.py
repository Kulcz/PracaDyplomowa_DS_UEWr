"""
HISTORYCZNY - uczelnia poza proba finalna, niewykorzystywany w core analizie.
(UP Lublin wykluczony: wlasny system OpenUP o asymetrycznej metodyce ekstrakcji,
kategoria B+; lamalby porownywalnosc z 4 instancjami Omega-PSIR. Parser zostaje
na wypadek powrotu - brak dla niego danych w Dane/ i nie wchodzi do pipeline'u R.)

Scraper UP Lublin - open.up.lublin.pl (OpenUP, ASP.NET MVC).

Hybryda Playwright (lista osob - paginator JS-driven) + httpx (profile - server-rendered HTML).

Endpoint listy: /Uczelnia/Wyszukiwarka/Osoby
  - Paginator JS (POST do /Uczelnia/Publiczna/Wyszukiwarka/WyszukiwarkaList).
  - Total: ~2257 osob (PageListSize default 30, max 50).

Endpoint profilu: /Uczelnia/Publiczna/Wyszukiwarka/ProfilDetail/{ID}?obiektId=Osoby
  - raw HTTP zwraca 38 KB HTML z polami Dane podstawowe (label.control-label + sibling div).
  - Header z tytulem + katedra + wydzial dolaczany jest JS po renderze - nie pobieramy.

Dostepne pola (z raw HTTP):
- profil (z <h2>)
- stanowisko (label 'Stanowisko')
- orcid (label 'Numer ORCID')
- scopus_id (label 'Scopus Author ID') - BONUS, ulatwia matching z OpenAlex
- n_pub (label 'Liczba publikacji')
- sum_MEiN (label 'Liczba punktow' - = punktacja ministerialna)

Pominete (wymagalyby Playwright per profil):
- tytul, jednostka (katedra), wydzial

Strategia metodyczna (B): brakujace pola tytul/jednostka uzupelniamy w R z OpenAlex
(affiliations.institution.display_name, affiliations.years, etc.).
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

import httpx
import pandas as pd
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

from .base import (
    BaseParser, UniConfig, ProfileRecord, COLUMNS,
    squish, parse_int_loose, parse_mein_loose,
)


class UPLublinParser(BaseParser):
    UNI = UniConfig(
        code="up_lublin",
        name="UP_Lublin",
        base_url="https://open.up.lublin.pl",
    )
    LIST_URL_PATH = "/Uczelnia/Wyszukiwarka/Osoby"
    PROFILE_URL_TEMPLATE = "/Uczelnia/Publiczna/Wyszukiwarka/ProfilDetail/{id}?obiektId=Osoby"
    WAIT_LIST = 3.0
    HTTPX_TIMEOUT = 30.0
    AUTOSAVE_EVERY = 25

    def profile_url(self, profile_id: str) -> str:
        return f"{self.UNI.base_url}{self.PROFILE_URL_TEMPLATE.format(id=profile_id)}"

    # ---------- ETAP 1: paginator (Playwright) ----------
    def fetch_all_ids(self, headless: bool = True, max_pages: int = 200) -> list[str]:
        ids: list[str] = []
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=headless, args=["--no-sandbox"])
            page = browser.new_context().new_page()
            page.goto(f"{self.UNI.base_url}{self.LIST_URL_PATH}",
                      wait_until="networkidle", timeout=30_000)
            time.sleep(self.WAIT_LIST)

            # Ustaw PageListSize=50 jesli sie da.
            try:
                page.select_option("select[name='PageListSize']", "50")
                time.sleep(self.WAIT_LIST)
            except Exception:
                pass

            for k in range(1, max_pages + 1):
                html = page.content()
                page_ids = re.findall(r"/ProfilDetail/(\d+)", html)
                before = len(ids)
                for pid in page_ids:
                    if pid not in ids:
                        ids.append(pid)
                added = len(ids) - before
                print(f"  [list page {k}] +{added}  total={len(ids)}")
                if added == 0:
                    break
                # Klik next: <a data-pager='pager' data-pager-page='{k+1}'>
                next_sel = f"a.page-link[data-pager-page='{k+1}']"
                next_btn = page.locator(next_sel).first
                if next_btn.count() == 0:
                    print(f"  [list] brak next page (k+1={k+1}) - koniec paginacji")
                    break
                try:
                    next_btn.click(timeout=5000)
                except Exception as e:
                    print(f"  [list] next-click ERROR: {e}")
                    break
                time.sleep(self.WAIT_LIST + 1)

            browser.close()
        return ids

    # ---------- ETAP 2: profile (httpx) ----------
    def parse_profile(self, html: str) -> ProfileRecord:
        soup = BeautifulSoup(html, "lxml")

        # Imie nazwisko - h2 w naglowku
        h2 = soup.find("h2")
        profil = squish(h2.get_text(" ", strip=True)) if h2 else None

        # Pola Dane podstawowe: <label class='control-label'>X:</label><div>VAL</div>
        fields: dict[str, str | None] = {}
        for label in soup.find_all("label", class_="control-label"):
            label_text = squish(label.get_text(" ", strip=True)) or ""
            # Strip trailing ":" i "*" (required marker)
            key = re.sub(r"[\s:*]+$", "", label_text).strip().lower()
            sibling = label.find_next_sibling()
            val = squish(sibling.get_text(" ", strip=True)) if sibling else None
            fields[key] = val

        scopus_id = fields.get("scopus author id")
        if scopus_id and not re.match(r"^\d+$", scopus_id):
            scopus_id = None  # czasem "Sprawdz cytowania" zamiast ID

        return ProfileRecord(
            profil=profil,
            tytul=None,         # header dodawany przez JS - nie mamy w raw HTTP
            stanowisko=fields.get("stanowisko"),
            jednostka=None,     # header JS
            wydzial=None,       # header JS
            orcid=fields.get("numer orcid"),
            scopus_id=scopus_id,
            n_pub=parse_int_loose(fields.get("liczba publikacji")),
            sum_MEiN=parse_mein_loose(fields.get("liczba punktow") or fields.get("liczba punktów")),
            # h-index/IF/SNIP - OpenUP nie eksponuje
        )

    def fetch_profile(self, profile_id: str, client: httpx.Client) -> ProfileRecord:
        url = self.profile_url(profile_id)
        try:
            r = client.get(url)
            r.raise_for_status()
        except Exception as e:
            return ProfileRecord(author_id=profile_id, url=url, error=str(e))
        rec = self.parse_profile(r.text)
        rec.author_id = profile_id
        rec.url = url
        return rec

    # ---------- Run ----------
    def run(self, args: argparse.Namespace) -> int:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_csv = out_dir / f"{self.UNI.code}_{args.dyscyplina}_{timestamp}.csv"

        print(f"\n[CONFIG] UNI={self.UNI.name} | base={self.UNI.base_url}")
        print(f"[OUT] {out_csv}")

        print("\n[ETAP 1] Playwright: paginator listy osob...")
        ids = self.fetch_all_ids(headless=args.headless or True, max_pages=args.max_pages)
        if not ids:
            print("Brak ProfilDetail IDs.", file=sys.stderr)
            return 1
        print(f"Zebrano {len(ids)} ProfilDetail IDs.")

        if args.limit_profiles:
            ids = ids[: args.limit_profiles]
            print(f"[LIMIT] {len(ids)} (--limit-profiles)")

        print(f"\n[ETAP 2] httpx: pobieram profile (n={len(ids)})...")
        records: list[ProfileRecord] = []
        with httpx.Client(timeout=self.HTTPX_TIMEOUT, follow_redirects=True,
                          headers={"User-Agent": "praca-dyplomowa-scraper/1.0"}) as client:
            for i, pid in enumerate(ids, start=1):
                rec = self.fetch_profile(pid, client)
                records.append(rec)
                if i <= 5:
                    print(f"  [{i}] id={pid} -> {rec.profil!r} stan={rec.stanowisko!r} "
                          f"n_pub={rec.n_pub} mein={rec.sum_MEiN}")
                if i % self.AUTOSAVE_EVERY == 0 or i == len(ids):
                    rows = [asdict(r) for r in records]
                    pd.DataFrame(rows, columns=COLUMNS).to_csv(out_csv, index=False, encoding="utf-8")
                    print(f"  [AUTOSAVE] {i}/{len(ids)} -> {out_csv}")

        print(f"\nZapisano: {out_csv}  ({len(records)} wierszy)")
        return 0
