"""
Bazowe klasy + wspolne helpery dla scraperow CRIS uczelnianych.

Hierarchia:
- BaseParser (ABC) - minimalny interfejs: UNI, WAIT_*, parse_profile(), run(args)
- OmegaPsirBaseParser(BaseParser) - implementacja dla 4 uczelni z Omega-PSIR
  (UPWR/SGGW/URK/UWM); poszczegolne uczelnie nadpisuja LABEL_SUM_MEIN i WAIT_PROFILE.
- UPPoznanParser(BaseParser) - DSpace REST API (osobny modul up_poznan.py).
- UPLublinParser(BaseParser) - OpenUP HTML scraping (osobny modul up_lublin.py).

Strategia metodyczna (FINAL 2026-05-26, rewizja decyzji z 2026-05-25):
Omega-PSIR jest ZRODLEM PODSTAWOWYM metryk bibliometrycznych. Z CRIS ciagniemy
TOZSAMOSC (profil, tytul, stanowisko, jednostka, wydzial, orcid, scopus_id, polon_id)
ORAZ lokalne agregaty (sum_IF, sum_SNIP, sum_MEiN, h_index_wos/scopus, n_pub).
OpenAlex pelni role UZUPELNIAJACA (FWCI, cited_by_count, sieci wspolautorstwa) i
cross-checku QA dla metryk lokalnych. Wczesniejsza wersja ("OpenAlex jako primary,
Omega-PSIR jako cross-check") zostala zrewidowana po tescie kompletnosci 2026-05-26:
Omega-PSIR to srednio 2-3x bogatszy katalog (polskie czasopisma, monografie,
materialy konferencyjne nieindeksowane w Scopus/WoS), wiec dla porownan
miedzyuczelnianych jest wiarygodniejszy niz globalny indeks.
"""
from __future__ import annotations

import argparse
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from typing import ClassVar

from bs4 import BeautifulSoup


# ---------- Konfiguracja uczelni ----------
@dataclass(frozen=True)
class UniConfig:
    code: str
    name: str
    base_url: str
    # Pola ponizej sa Omega-PSIR-specific - dla DSpace/OpenUP klasa parsera
    # nadpisuje profile_url() i nie uzywa author_id_regex.
    results_url: str = ""
    author_id_regex: str = r"/info/author/([^?/#&]+)"

    def profile_url(self, author_id: str) -> str:
        """Default Omega-PSIR; DSpace/OpenUP parsery nadpisuja w klasie."""
        return f"{self.base_url}/info/author/{author_id}?lang=pl&r=publication&tab=main"


# ---------- Schemat rekordu ----------
COLUMNS = [
    "profil", "tytul", "stanowisko", "jednostka", "wydzial", "orcid",
    "scopus_id", "polon_id", "researcharea",
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
    # Identifyfikatory zewnetrzne - ulatwiaja matching z OpenAlex/RAD-on.
    scopus_id: str | None = None
    polon_id: str | None = None
    # Dyscyplina (DSpace CRIS: person.researcharea; OpenUP: filtr dyscypliny).
    researcharea: str | None = None
    # Metryki Omega-PSIR (cross-check do OpenAlex; dla DSpace/OpenUP zostaja None).
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
            self.scopus_id, self.polon_id,
            self.h_index_scopus, self.h_index_wos,
            self.sum_IF, self.sum_MEiN, self.n_pub,
        ))


# ============================================================
# BaseParser - minimalny interfejs dla wszystkich CRIS
# ============================================================
class BaseParser(ABC):
    """Minimalny interfejs scrapera CRIS. Konkretne klasy musza zaimplementowac
    run() (caly flow scraping) lub dziedziczyc OmegaPsirBaseParser ktory ma run()
    delegujace do core.run_scraper."""

    UNI: ClassVar[UniConfig]
    WAIT_PROFILE: ClassVar[float] = 6.0
    WAIT_RESULTS: ClassVar[float] = 4.0

    @abstractmethod
    def run(self, args: argparse.Namespace) -> int:
        """Wykonuje pelen flow scraping. Zwraca exit code (0 = sukces)."""
        ...


# ---------- Helpery niezalezne od uczelni ----------
NBSP = " "


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
    """Znajduje wartosc po etykiecie. Obsluguje 3 wzorce:

    1) UPWR/standardowy: <dt>label</dt><dd>value</dd> -> sibling.
    2) URK: <li><span class="indicatorName">label</span>value</li>
       -> tag zawiera SAM label, wartosc to text-node rodzica po spanie.
    3) Fallback: pierwszy element w DOM po tagu z labelem.

    Kandydatow sortujemy rosnaco po dlugosci tekstu - najkrotszy tag zawierajacy
    label jest najbardziej specyficzny.
    """
    pat = re.compile(label_regex, re.IGNORECASE)
    candidates: list[tuple] = []
    for tag in soup.find_all(["dt", "th", "div", "span"]):
        txt = squish(tag.get_text(" ", strip=True))
        if not txt or not pat.search(txt):
            continue
        candidates.append((len(txt), tag, txt))

    candidates.sort(key=lambda x: x[0])

    for _, tag, txt in candidates:
        if pat.fullmatch(txt):
            parent = tag.parent
            if parent is not None and parent.name in ("li", "p", "div", "td", "dd"):
                parent_txt = squish(parent.get_text(" ", strip=True)) or ""
                if parent_txt != txt and txt in parent_txt:
                    rest = squish(parent_txt.replace(txt, "", 1))
                    if rest:
                        return rest

        sib = tag.find_next_sibling()
        if sib:
            val = squish(sib.get_text(" ", strip=True))
            if val and val != txt:
                return val

        nxt = tag.find_next()
        if nxt:
            val = squish(nxt.get_text(" ", strip=True))
            if val and val != txt:
                return val
    return None


def extract_metric_value(page_txt: str, label_regex: str,
                         num_regex: str = r"[0-9]+(?:[\.,][0-9]+)?",
                         max_gap: int = 120) -> str | None:
    """Fallback: etykieta i wartosc w jednej linii/bloku tekstu."""
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


def parse_int_loose(x: str | None) -> float | None:
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


def _direct_text(tag) -> str:
    """Tekst tylko z bezposrednich text-node'ow tagu."""
    return "".join(s for s in tag.find_all(string=True, recursive=False)).strip()


def _is_visually_hidden(tag) -> bool:
    while tag is not None:
        cls = tag.get("class") if hasattr(tag, "get") else None
        if cls and "visuallyhidden" in cls:
            return True
        tag = getattr(tag, "parent", None)
    return False


def _find_org_span(soup: BeautifulSoup, label_regex: str) -> str | None:
    """Znajdz <span> z BEZPOSREDNIM tekstem zaczynajacym sie od slowa kluczowego.
    Why: Omega-PSIR duplikuje tekst w span.visuallyhidden (screen readers)."""
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


def looks_like_block_page(html: str) -> bool:
    soup = BeautifulSoup(html, "lxml")
    ttl_tag = soup.find("title")
    ttl = (squish(ttl_tag.get_text(" ", strip=True)) or "").lower() if ttl_tag else ""
    txt = (squish(soup.get_text(" ", strip=True)) or "").lower()
    has_password = bool(re.search(r"type\s*=\s*['\"]password['\"]", html.lower()))
    title_block = bool(re.search(r"logowanie|zaloguj|login|sign in|captcha|cloudflare|access denied|forbidden", ttl))
    text_block = bool(re.search(r"captcha|cloudflare|access denied|forbidden|too many requests|403|401", txt))
    return title_block or text_block or has_password


def get_orcid_from_soup(soup: BeautifulSoup) -> str | None:
    """ORCID z dowolnego <a href> zawierajacego orcid.org/<id>."""
    pat = re.compile(r"orcid\.org/(\d{4}-\d{4}-\d{4}-\d{3}[\dX])", re.IGNORECASE)
    for a in soup.find_all("a", href=True):
        m = pat.search(a["href"])
        if m:
            return m.group(1)
    m = pat.search(soup.get_text(" ", strip=True))
    return m.group(1) if m else None


# ---------- Czyszczenie pol tekstowych ----------
_ORG_TAIL = (
    r"\s*(Wydział\b|Strona\s+domowa:|Email\b|Profil\b|Publikacje\b|"
    r"ORCID\b|Google\s+Scholar\b).*"
)
_POS_TAIL = (
    r"\s*(Jednostka\b|Wydział\b|Strona\s+domowa:|Email\b|Profil\b|"
    r"Publikacje\b|ORCID\b|Google\s+Scholar\b).*"
)
_FACULTY_TAIL = (
    r"\s*(Strona\s+domowa:|Email\b|Profil\b|Publikacje\b|ORCID\b|Google\s+Scholar\b).*"
)


def clean_profile_name(x: str | None) -> str | None:
    if x is None:
        return None
    x = squish(x) or ""
    x = re.sub(r"^Profil osoby\s*[–—-]\s*", "", x)
    x = re.sub(r"\s*[–—-]\s*Uniwersytet.*$", "", x)
    return squish(x)


def clean_org_fragment(x: str | None) -> str | None:
    if x is None:
        return None
    return squish(re.sub(_ORG_TAIL, "", squish(x) or ""))


def clean_position(x: str | None) -> str | None:
    if x is None:
        return None
    return squish(re.sub(_POS_TAIL, "", squish(x) or ""))


def clean_faculty(x: str | None) -> str | None:
    if x is None:
        return None
    return squish(re.sub(_FACULTY_TAIL, "", squish(x) or ""))


# ============================================================
# OmegaPsirBaseParser - implementacja dla UPWR/SGGW/URK/UWM
# ============================================================
class OmegaPsirBaseParser(BaseParser):
    """Bazowy parser Omega-PSIR. Domyslna implementacja dziala dla UPWR;
    URK/UWM nadpisuja LABEL_SUM_MEIN (ministerialna vs MEiN) i WAIT_PROFILE."""

    WAIT_PROFILE: ClassVar[float] = 6.0
    WAIT_RESULTS: ClassVar[float] = 4.0

    LABEL_H_SCOPUS: ClassVar[str] = r"h-?index\s*\(\s*Cytowania\s*Scopus\s*\)"
    LABEL_H_WOS: ClassVar[str] = r"h-?index\s*\(\s*Cytowania\s*WoS\s*\)"
    LABEL_SUM_IF: ClassVar[str] = r"Sumaryczny\s*IF"
    LABEL_SUM_SNIP: ClassVar[str] = r"Sumaryczny\s*SNIP"
    LABEL_SUM_MEIN: ClassVar[str] = r"Sumaryczna\s*punktacja\s*MEiN"
    LABEL_N_PUB: ClassVar[str] = r"Liczba\s*publikacji|Liczba\s*pozycji|Wszystkie\s*publikacje"

    FALLBACK_H_SCOPUS: ClassVar[str] = (
        r"(?:h-?index[^a-zA-Z0-9]{0,25}(?:scopus|cytowania\s*scopus)|"
        r"(?:scopus|cytowania\s*scopus)[^a-zA-Z0-9]{0,25}h-?index)"
    )
    FALLBACK_H_WOS: ClassVar[str] = (
        r"(?:h-?index[^a-zA-Z0-9]{0,25}(?:wos|web\s*of\s*science|cytowania\s*wos)|"
        r"(?:wos|web\s*of\s*science|cytowania\s*wos)[^a-zA-Z0-9]{0,25}h-?index)"
    )
    FALLBACK_SUM_IF: ClassVar[str] = r"(?:sumaryczny\s*if|if\s*sumaryczny)"
    FALLBACK_SUM_SNIP: ClassVar[str] = r"(?:sumaryczny\s*snip|snip\s*sumaryczny)"
    FALLBACK_SUM_MEIN: ClassVar[str] = (
        r"(?:sumaryczna\s*punktacja\s*(?:mein|mnisw|ministerialna)|"
        r"punktacja\s*(?:mein|mnisw|ministerialna))"
    )
    FALLBACK_N_PUB: ClassVar[str] = (
        r"(?:liczba\s*publikacji|liczba\s*pozycji|wszystkie\s*publikacje|publikacje)"
    )

    # ---------- Metody parsujace - override gdy uczelnia ma inny selektor ----------
    def get_profile_name(self, soup: BeautifulSoup) -> str | None:
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

    def get_tytul(self, soup: BeautifulSoup) -> str | None:
        el = soup.select_one("span.authorName")
        if el:
            t = squish(_direct_text(el)) or squish(el.get_text(" ", strip=True))
            if t:
                return t
        return None

    def get_orcid(self, soup: BeautifulSoup) -> str | None:
        return get_orcid_from_soup(soup)

    def get_unit(self, soup: BeautifulSoup, page_txt: str) -> str | None:
        val = _find_org_span(soup, r"^(?:Katedra|Instytut|Zakład|Centrum)\b")
        if val:
            return clean_org_fragment(val)
        m = re.search(r"((?:Katedra|Instytut|Zakład|Centrum)[^\n]{0,160})", page_txt)
        return clean_org_fragment(m.group(1)) if m else None

    def get_faculty(self, soup: BeautifulSoup, page_txt: str) -> str | None:
        val = _find_org_span(soup, r"^Wydział\b")
        if val:
            return clean_faculty(val)
        m = re.search(r"(Wydział[^\n]{0,140})", page_txt)
        return clean_faculty(m.group(1)) if m else None

    def get_position(self, soup: BeautifulSoup, page_txt: str) -> str | None:
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

    # ---------- Parser glowny ----------
    def parse_profile(self, html: str) -> ProfileRecord:
        soup = BeautifulSoup(html, "lxml")
        page_txt = squish(soup.get_text(" ", strip=True)) or ""

        tytul = self.get_tytul(soup)
        profil = clean_profile_name(self.get_profile_name(soup))
        if tytul and profil and profil.lower().startswith(tytul.lower()):
            profil = squish(profil[len(tytul):])

        rec = ProfileRecord(
            profil=profil,
            tytul=tytul,
            stanowisko=self.get_position(soup, page_txt),
            jednostka=self.get_unit(soup, page_txt),
            wydzial=self.get_faculty(soup, page_txt),
            orcid=self.get_orcid(soup),
        )

        h_scopus = get_value_by_label(soup, self.LABEL_H_SCOPUS) \
                   or extract_metric_value(page_txt, self.FALLBACK_H_SCOPUS, r"[0-9]+", 80)
        h_wos = get_value_by_label(soup, self.LABEL_H_WOS) \
                or extract_metric_value(page_txt, self.FALLBACK_H_WOS, r"[0-9]+", 80)
        sum_if = get_value_by_label(soup, self.LABEL_SUM_IF) \
                 or extract_metric_value(page_txt, self.FALLBACK_SUM_IF, r"[0-9]+(?:[\.,][0-9]+)?", 80)
        sum_snip = get_value_by_label(soup, self.LABEL_SUM_SNIP) \
                   or extract_metric_value(page_txt, self.FALLBACK_SUM_SNIP, r"[0-9]+(?:[\.,][0-9]+)?", 80)
        sum_mein = get_value_by_label(soup, self.LABEL_SUM_MEIN) \
                   or extract_metric_value(page_txt, self.FALLBACK_SUM_MEIN, r"[0-9][0-9 ]*", 120)
        n_pub = get_value_by_label(soup, self.LABEL_N_PUB) \
                or extract_metric_value(page_txt, self.FALLBACK_N_PUB, r"[0-9]+", 80)

        rec.h_index_scopus = parse_int_loose(h_scopus)
        rec.h_index_wos = parse_int_loose(h_wos)
        rec.sum_IF = parse_float_first(sum_if)
        rec.sum_SNIP = parse_float_first(sum_snip)
        rec.sum_MEiN = parse_mein_loose(sum_mein)
        rec.n_pub = parse_int_loose(n_pub)
        return rec

    def run(self, args: argparse.Namespace) -> int:
        # Import opozniony: core importuje z base, wiec unikamy cyklu.
        from .core import run_scraper
        return run_scraper(self, args)
