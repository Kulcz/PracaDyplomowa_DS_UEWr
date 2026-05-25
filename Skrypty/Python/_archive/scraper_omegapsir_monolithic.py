"""
Baza Wiedzy Omega-PSIR (UPWR / SGGW / URK / UWM) - scraper Pythonowy.

Port logiki z Skrypty/R/01_scraper_omegapsir.R na Playwright + BeautifulSoup.
Output CSV kompatybilny ze schematem R (te same kolumny -> dalsza analiza w R bez zmian).

Uzycie:
    source .venv/bin/activate
    python Skrypty/Python/scraper_omegapsir.py --uni URK --dyscyplina rolnictwo_i_ogrodnictwo

Flow:
    1. Otwiera Chromium (Playwright bundled - bez chromedrivera).
    2. Czeka na ENTER w terminalu - tymczasem rcznie ustawiasz filtr dyscypliny.
    3. ETAP 1: paginator PrimeFaces -> zbiera unikalne author_id.
    4. ETAP 2: dla kazdego author_id -> profil + bibliometria.
    5. Autosave co AUTOSAVE_EVERY rekordow + finalny CSV.
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Callable

import pandas as pd
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright, Page, TimeoutError as PWTimeout


# ---------- Konfiguracja uczelni ----------
@dataclass(frozen=True)
class UniConfig:
    code: str
    name: str
    base_url: str
    results_url: str
    author_id_regex: str = r"/info/author/([^?/#&]+)"

    def profile_url(self, author_id: str) -> str:
        return f"{self.base_url}/info/author/{author_id}?lang=pl&r=publication&tab=main"


UNIVERSITY_CONFIG: dict[str, UniConfig] = {
    "UPWR": UniConfig(
        code="upwr",
        name="UPWR",
        base_url="https://bazawiedzy.upwr.edu.pl",
        results_url="https://bazawiedzy.upwr.edu.pl/search/author?ps=20&t=simple&lang=pl",
    ),
    # 2026-05-24: stara bazawiedzy.sggw.edu.pl daje 404, baza przeniesiona pod bw.sggw.edu.pl.
    "SGGW": UniConfig(
        code="sggw",
        name="SGGW",
        base_url="https://bw.sggw.edu.pl",
        results_url="https://bw.sggw.edu.pl/search/author?ps=20&t=simple&lang=pl",
    ),
    "URK": UniConfig(
        code="urk",
        name="URK",
        base_url="https://repo.ur.krakow.pl",
        results_url="https://repo.ur.krakow.pl/search/author?ps=20&t=simple&lang=pl",
    ),
    "UWM": UniConfig(
        code="uwm",
        name="UWM",
        base_url="https://bazawiedzy.uwm.edu.pl",
        results_url="https://bazawiedzy.uwm.edu.pl/search/author?ps=20&t=simple&lang=pl",
    ),
}


# ---------- Parametry runtime ----------
WAIT_RESULTS = 4.0
WAIT_PROFILE = 6.0
MAX_NEXT_CLICKS = 300
AUTOSAVE_EVERY = 10
LIST_RETRY = 3


# ---------- Schemat rekordu ----------
COLUMNS = [
    "profil", "tytul", "stanowisko", "jednostka", "wydzial", "orcid",
    "h_index_scopus", "h_index_wos", "sum_IF", "sum_SNIP", "sum_MEiN", "n_pub",
    "author_id", "url", "error",
]


@dataclass
class ProfileRecord:
    profil: str | None = None
    tytul: str | None = None
    stanowisko: str | None = None
    jednostka: str | None = None
    wydzial: str | None = None
    orcid: str | None = None
    # h_index_*, sum_* zostawione w schemacie - uzupelnianie z OpenAlex w tyg 4-5.
    h_index_scopus: float | None = None
    h_index_wos: float | None = None
    sum_IF: float | None = None
    sum_SNIP: float | None = None
    sum_MEiN: float | None = None
    n_pub: float | None = None
    author_id: str = ""
    url: str = ""
    error: str | None = None

    def has_any_data(self) -> bool:
        return any(v is not None for v in (
            self.profil, self.tytul, self.stanowisko,
            self.jednostka, self.wydzial, self.orcid,
            self.h_index_scopus, self.h_index_wos,
            self.sum_IF, self.sum_MEiN, self.n_pub,
        ))


# ---------- Helpery parsujace ----------
NBSP = " "


def to_num_pl(x: str | None) -> float | None:
    if x is None:
        return None
    x = x.replace(NBSP, " ").strip()
    if not x:
        return None
    try:
        return float(x.replace(",", "."))
    except ValueError:
        return None


def squish(s: str | None) -> str | None:
    if s is None:
        return None
    s = re.sub(r"\s+", " ", s).strip()
    return s or None


def extract_author_ids_from_html(html: str, pattern: str) -> list[str]:
    """Zbiera unikalne author_id z calego HTML, zachowujac kolejnosc wystapien."""
    found = re.findall(pattern, html)
    seen: dict[str, None] = {}
    for fid in found:
        fid = re.split(r"[?/#&]", fid)[0]
        if fid and fid not in seen:
            seen[fid] = None
    return list(seen.keys())


def get_value_by_label(soup: BeautifulSoup, label_regex: str) -> str | None:
    """Znajduje wartosc po etykiecie (dt/th/div/span -> nastepny sibling lub kolejny element DOM)."""
    pat = re.compile(label_regex, re.IGNORECASE)
    for tag in soup.find_all(["dt", "th", "div", "span"]):
        txt = squish(tag.get_text(" ", strip=True))
        if not txt or not pat.search(txt):
            continue
        sib = tag.find_next_sibling()
        if sib:
            val = squish(sib.get_text(" ", strip=True))
            if val:
                return val
        nxt = tag.find_next()
        if nxt:
            val = squish(nxt.get_text(" ", strip=True))
            if val:
                return val
    return None


def extract_metric_value(page_txt: str, label_regex: str,
                         num_regex: str = r"[0-9]+(?:[\.,][0-9]+)?",
                         max_gap: int = 120) -> str | None:
    """Fallback gdy etykieta i wartosc sa w jednej linii/bloku tekstu."""
    patterns = [
        rf"(?is)(?:{label_regex})\s*[:=]?\s*({num_regex})",
        rf"(?is)(?:{label_regex}).{{0,{max_gap}}}?({num_regex})",
        rf"(?is)({num_regex})\s*[:=]?\s*(?:{label_regex})",
        rf"(?is)({num_regex}).{{0,{max_gap}}}?(?:{label_regex})",
    ]
    for p in patterns:
        m = re.search(p, page_txt)
        if m and m.group(1):
            return m.group(1)
    return None


def clean_profile_name(x: str | None) -> str | None:
    if x is None:
        return None
    x = squish(x) or ""
    x = re.sub(r"^Profil osoby\s*[–—-]\s*", "", x)
    x = re.sub(r"\s*[–—-]\s*Uniwersytet.*$", "", x)
    return squish(x)


_ORG_TAIL = (
    r"\s*(Wydział\b|Strona\s+domowa:|Email\b|Profil\b|Publikacje\b|"
    r"ORCID\b|Google\s+Scholar\b).*"
)
_POS_TAIL = (
    r"\s*(Jednostka\b|Wydział\b|Strona\s+domowa:|Email\b|Profil\b|"
    r"Publikacje\b|ORCID\b|Google\s+Scholar\b).*"
)


def clean_org_fragment(x: str | None) -> str | None:
    if x is None:
        return None
    return squish(re.sub(_ORG_TAIL, "", squish(x) or ""))


def clean_position(x: str | None) -> str | None:
    if x is None:
        return None
    return squish(re.sub(_POS_TAIL, "", squish(x) or ""))


def _direct_text(tag) -> str:
    """Tekst tylko z bezposrednich text-node'ow tagu (bez tekstu z dzieci)."""
    return "".join(s for s in tag.find_all(string=True, recursive=False)).strip()


def _is_visually_hidden(tag) -> bool:
    while tag is not None:
        cls = tag.get("class") if hasattr(tag, "get") else None
        if cls and "visuallyhidden" in cls:
            return True
        tag = getattr(tag, "parent", None)
    return False


def get_profile_name(soup: BeautifulSoup) -> str | None:
    # Selektor Omega-PSIR (dziala na URK; weryfikujemy na pozostalych uczelniach przy pelnym runie).
    el = soup.select_one("p.author-profile__name-panel")
    if el:
        t = squish(el.get_text(" ", strip=True))
        if t:
            return t
    ttl = soup.find("title")
    if ttl:
        t = squish(ttl.get_text(" ", strip=True)) or ""
        m = re.search(r"Profil osoby\s*[–—-]\s*(.+?)\s*[–—-]\s*Uniwersytet", t)
        if m:
            return squish(m.group(1))
        if t:
            return t
    return None


def get_tytul(soup: BeautifulSoup) -> str | None:
    """Tytul naukowy ('prof. dr hab. inz.', 'dr', ...) z naglowka profilu."""
    el = soup.select_one("span.authorName")
    if el:
        t = squish(_direct_text(el)) or squish(el.get_text(" ", strip=True))
        if t:
            return t
    return None


def get_orcid(soup: BeautifulSoup) -> str | None:
    """ORCID z dowolnego <a href> zawierajacego orcid.org/<id>."""
    pat = re.compile(r"orcid\.org/(\d{4}-\d{4}-\d{4}-\d{3}[\dX])", re.IGNORECASE)
    for a in soup.find_all("a", href=True):
        m = pat.search(a["href"])
        if m:
            return m.group(1)
    # fallback - poszukaj w tekscie
    m = pat.search(soup.get_text(" ", strip=True))
    return m.group(1) if m else None


def _find_org_span(soup: BeautifulSoup, label_regex: str) -> str | None:
    """Znajdz <span> ktorego BEZPOSREDNI tekst zaczyna sie od slowa kluczowego.

    Why: Omega-PSIR ma duplikat tekstu w <span class='visuallyhidden'> ('Strona domowa:
    Katedra X') uzywany przez screen readery. Bierzemy tylko widoczny tekst (nie
    visuallyhidden) i tylko z bezposrednich text-node'ow, zeby nie zlapac dluzszych
    fragmentow strony zawierajacych slowo kluczowe gdzies w srodku.
    """
    pat = re.compile(label_regex)
    for span in soup.find_all("span"):
        if _is_visually_hidden(span):
            continue
        dt = _direct_text(span)
        if not dt or len(dt) > 200:
            continue
        if pat.match(dt):
            return squish(dt)
    return None


def get_unit(soup: BeautifulSoup, page_txt: str) -> str | None:
    """Jednostka: Katedra/Instytut/Zaklad/Centrum (pierwsze trafienie w sidebarze profilu)."""
    val = _find_org_span(soup, r"^(?:Katedra|Instytut|Zakład|Centrum)\b")
    if val:
        return clean_org_fragment(val)
    # fallback - regex na pelnym tekscie strony (jak w R)
    m = re.search(r"((?:Katedra|Instytut|Zakład|Centrum)[^\n]{0,160})", page_txt)
    return clean_org_fragment(m.group(1)) if m else None


_FACULTY_TAIL = (
    r"\s*(Strona\s+domowa:|Email\b|Profil\b|Publikacje\b|ORCID\b|Google\s+Scholar\b).*"
)


def _clean_faculty(x: str | None) -> str | None:
    """Czyszczenie wydzialu - NIE wycinamy 'Wydzial\\b' (inaczej niz clean_org_fragment)."""
    if x is None:
        return None
    return squish(re.sub(_FACULTY_TAIL, "", squish(x) or ""))


def get_faculty(soup: BeautifulSoup, page_txt: str) -> str | None:
    val = _find_org_span(soup, r"^Wydział\b")
    if val:
        return _clean_faculty(val)
    m = re.search(r"(Wydział[^\n]{0,140})", page_txt)
    return _clean_faculty(m.group(1)) if m else None


def get_position(soup: BeautifulSoup, page_txt: str) -> str | None:
    # Omega-PSIR: <p class="possitionInfo"><span class="authorAffil">profesor</span></p>
    # Czesc profili ma w authorAffil nazwe katedry zamiast stanowiska
    # (URK wpisuje afiliacje gdy stanowisko nie jest zdefiniowane) - odrzucamy.
    el = soup.select_one("p.possitionInfo span.authorAffil") or soup.select_one("span.authorAffil")
    if el:
        t = squish(el.get_text(" ", strip=True))
        if t and not re.match(r"^(?:Katedra|Instytut|Zakład|Centrum|Wydział)\b", t):
            return clean_position(t)

    pattern_with_label = (
        r"(?i)(?:Stanowisko\s*[:\-]?\s*)"
        r"(Profesor(?:\s+uczelni)?|Profesor\s+nadzwyczajny|Profesor\s+zwyczajny|"
        r"Adiunkt(?:\s+badawczo-dydaktyczny)?|Asystent|Wykładowca|"
        r"Starszy\s+wykładowca|Kierownik\s+katedry|Doktorant)"
    )
    m = re.search(pattern_with_label, page_txt)
    if m:
        return clean_position(m.group(1))

    pattern_bare = (
        r"(?i)\b(Profesor(?:\s+uczelni)?|Profesor\s+nadzwyczajny|Profesor\s+zwyczajny|"
        r"Adiunkt(?:\s+badawczo-dydaktyczny)?|Asystent|Wykładowca|"
        r"Starszy\s+wykładowca|Kierownik\s+katedry|Doktorant)\b"
    )
    m = re.search(pattern_bare, page_txt)
    return clean_position(m.group(1)) if m else None


def parse_int_loose(x: str | None) -> float | None:
    """Wyciaga liczbe calkowita ignorujac spacje (np. punktacja MEiN: '1 234')."""
    if x is None:
        return None
    digits = re.sub(r"\D", "", x)
    return float(digits) if digits else None


def parse_float_first(x: str | None) -> float | None:
    if x is None:
        return None
    m = re.search(r"([0-9]+(?:[\.,][0-9]+)?)", x)
    return to_num_pl(m.group(1)) if m else None


def parse_mein_loose(x: str | None) -> float | None:
    if x is None:
        return None
    m = re.search(r"([0-9 ]+)", x)
    if not m:
        return None
    return parse_int_loose(m.group(1).replace(" ", ""))


# ---------- Parser profilu ----------
def parse_profile_html(html: str) -> ProfileRecord:
    soup = BeautifulSoup(html, "lxml")
    page_txt = squish(soup.get_text(" ", strip=True)) or ""

    tytul = get_tytul(soup)
    profil = clean_profile_name(get_profile_name(soup))
    # Jesli profil zaczyna sie od tytulu (np. "prof. dr hab. inz. Adela Adamus"),
    # odetnij tytul zeby zostalo samo imie + nazwisko.
    if tytul and profil and profil.lower().startswith(tytul.lower()):
        profil = squish(profil[len(tytul):])

    rec = ProfileRecord(
        profil=profil,
        tytul=tytul,
        stanowisko=get_position(soup, page_txt),
        jednostka=get_unit(soup, page_txt),
        wydzial=get_faculty(soup, page_txt),
        orcid=get_orcid(soup),
    )

    h_scopus = get_value_by_label(soup, r"h-?index\s*\(\s*Cytowania\s*Scopus\s*\)")
    h_wos = get_value_by_label(soup, r"h-?index\s*\(\s*Cytowania\s*WoS\s*\)")
    sum_if = get_value_by_label(soup, r"Sumaryczny\s*IF")
    sum_snip = get_value_by_label(soup, r"Sumaryczny\s*SNIP")
    sum_mein = get_value_by_label(soup, r"Sumaryczna\s*punktacja\s*MEiN")
    n_pub = get_value_by_label(soup, r"Liczba\s*publikacji|Liczba\s*pozycji|Wszystkie\s*publikacje")

    if h_scopus is None:
        h_scopus = extract_metric_value(
            page_txt,
            r"(?:h-?index[^a-zA-Z0-9]{0,25}(?:scopus|cytowania\s*scopus)|"
            r"(?:scopus|cytowania\s*scopus)[^a-zA-Z0-9]{0,25}h-?index)",
            r"[0-9]+", 80,
        )
    if h_wos is None:
        h_wos = extract_metric_value(
            page_txt,
            r"(?:h-?index[^a-zA-Z0-9]{0,25}(?:wos|web\s*of\s*science|cytowania\s*wos)|"
            r"(?:wos|web\s*of\s*science|cytowania\s*wos)[^a-zA-Z0-9]{0,25}h-?index)",
            r"[0-9]+", 80,
        )
    if sum_if is None:
        sum_if = extract_metric_value(page_txt, r"(?:sumaryczny\s*if|if\s*sumaryczny)",
                                      r"[0-9]+(?:[\.,][0-9]+)?", 80)
    if sum_snip is None:
        sum_snip = extract_metric_value(page_txt, r"(?:sumaryczny\s*snip|snip\s*sumaryczny)",
                                        r"[0-9]+(?:[\.,][0-9]+)?", 80)
    if sum_mein is None:
        sum_mein = extract_metric_value(
            page_txt, r"(?:sumaryczna\s*punktacja\s*(?:mein|mnisw)|punktacja\s*(?:mein|mnisw))",
            r"[0-9][0-9 ]*", 120,
        )
    if n_pub is None:
        # Omega-PSIR pokazuje liczbe publikacji w naglowku zakladki, np. "Publikacje (145)".
        n_pub = extract_metric_value(
            page_txt,
            r"(?:liczba\s*publikacji|liczba\s*pozycji|wszystkie\s*publikacje|publikacje)",
            r"[0-9]+", 80,
        )

    rec.h_index_scopus = parse_int_loose(h_scopus)
    rec.h_index_wos = parse_int_loose(h_wos)
    rec.sum_IF = parse_float_first(sum_if)
    rec.sum_SNIP = parse_float_first(sum_snip)
    rec.sum_MEiN = parse_mein_loose(sum_mein)
    rec.n_pub = parse_int_loose(n_pub)
    return rec


def looks_like_block_page(html: str) -> bool:
    soup = BeautifulSoup(html, "lxml")
    ttl_tag = soup.find("title")
    ttl = (squish(ttl_tag.get_text(" ", strip=True)) or "").lower() if ttl_tag else ""
    txt = (squish(soup.get_text(" ", strip=True)) or "").lower()
    has_password = bool(re.search(r"type\s*=\s*['\"]password['\"]", html.lower()))
    title_block = bool(re.search(r"logowanie|zaloguj|login|sign in|captcha|cloudflare|access denied|forbidden", ttl))
    text_block = bool(re.search(r"captcha|cloudflare|access denied|forbidden|too many requests|403|401", txt))
    return title_block or text_block or has_password


# ---------- Playwright: paginator + profile ----------
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
    """Fallback Playwright native click - rzadko potrzebny gdy JS evaluate dziala."""
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


def get_profile_record(page: Page, cfg: UniConfig, author_id: str,
                       wait_sec: float = WAIT_PROFILE,
                       debug_dir: Path | None = None) -> ProfileRecord:
    url = cfg.profile_url(author_id)
    try:
        page.goto(url, timeout=30_000, wait_until="domcontentloaded")
    except PWTimeout:
        rec = ProfileRecord(author_id=author_id, url=url, error="goto-timeout")
        return rec

    time.sleep(wait_sec)
    html = page.content()
    rec = parse_profile_html(html)

    if not rec.has_any_data():
        time.sleep(3)
        html = page.content()
        rec = parse_profile_html(html)

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


# ---------- Main ----------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Scraper Omega-PSIR (Python/Playwright)")
    p.add_argument("--uni", required=True, choices=sorted(UNIVERSITY_CONFIG.keys()),
                   help="Kod uczelni: UPWR/SGGW/URK/UWM")
    p.add_argument("--dyscyplina", default="all",
                   help="Etykieta dyscypliny do tagowania plikow wyjsciowych")
    p.add_argument("--url", default=None,
                   help="Opcjonalny URL listy wynikow (override defaultu z UNIVERSITY_CONFIG)")
    p.add_argument("--out-dir", default="Dane/raw",
                   help="Katalog wyjsciowy (default: Dane/raw)")
    p.add_argument("--headless", action="store_true",
                   help="Headless mode (default: widoczne okno - filtr ustawia sie recznie)")
    p.add_argument("--max-pages", type=int, default=MAX_NEXT_CLICKS,
                   help=f"Limit klikniec next (default {MAX_NEXT_CLICKS})")
    p.add_argument("--limit-profiles", type=int, default=None,
                   help="Limit liczby profili do pobrania (do testow)")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    cfg = UNIVERSITY_CONFIG[args.uni]
    results_url = args.url or cfg.results_url

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    debug_dir = out_dir / "debug_html" / cfg.code
    debug_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    file_stem = f"{cfg.code}_{args.dyscyplina}_{timestamp}"
    out_csv = out_dir / f"{file_stem}.csv"

    print(f"\n[CONFIG] UNI={cfg.name} | URL_RESULTS={results_url}")
    print(f"[OUT] {out_csv}")

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=args.headless,
                                     args=["--no-sandbox", "--disable-gpu"])
        context = browser.new_context()
        page = context.new_page()
        page.goto(results_url, timeout=30_000, wait_until="domcontentloaded")
        time.sleep(WAIT_RESULTS)

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
            time.sleep(WAIT_RESULTS)
            html = page.content()
            ids = extract_author_ids_from_html(html, cfg.author_id_regex)

            for retry in range(1, LIST_RETRY):
                if ids:
                    break
                print(f"strona={k} | brak wynikow w DOM, retry {retry}/{LIST_RETRY - 1} po {WAIT_RESULTS}s...")
                time.sleep(WAIT_RESULTS)
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
                rec = get_profile_record(page, cfg, aid, debug_dir=debug_dir)
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


if __name__ == "__main__":
    sys.exit(main())
