"""
Parser Bazy Wiedzy SGGW (Szkola Glowna Gospodarstwa Wiejskiego, bw.sggw.edu.pl).

Status: zweryfikowany 2026-05-25 na 3 probnych profilach.

Ustalenia:
- Stara domena bazawiedzy.sggw.edu.pl daje 404; aktualna: bw.sggw.edu.pl.
- WAIT_PROFILE = 12s (PrimeFaces - jak URK/UWM).
- Pole 'Sumaryczna punktacja MEiN/ministerialna' STRUKTURALNIE NIE WYSTEPUJE
  w sekcji Bibliometria profilu SGGW. SGGW eksponuje tylko h-index (Scopus/WoS),
  Sumaryczny IF, Sumaryczny SNIP, Sumaryczny CiteScore. sum_MEiN zostanie 100%
  None dla calego zbioru SGGW - konsekwencja dla 06_eda_anova: trzeba albo
  wykluczyc SGGW z porownan na metryce sum_MEiN, albo pominac te metryke.
- Tytuly/orcid/stanowisko/jednostka/wydzial ekstrahuja sie standardowo (BaseParser).

Re-check po probnym scrapingu pelnej dyscypliny - jesli pojawia sie rozbieznosci
na nietypowych profilach (emerytowanych, doktorantach), dorzucic regex override.
"""
from .base import OmegaPsirBaseParser, UniConfig


class SGGWParser(OmegaPsirBaseParser):
    UNI = UniConfig(
        code="sggw",
        name="SGGW",
        base_url="https://bw.sggw.edu.pl",
        results_url="https://bw.sggw.edu.pl/search/author?ps=20&t=simple&lang=pl",
    )
    WAIT_PROFILE = 12.0
