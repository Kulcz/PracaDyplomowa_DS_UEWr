"""
Parser Bazy Wiedzy UWM (Uniwersytet Warminsko-Mazurski).

Status: zweryfikowany 2026-05-25 na 3 probnych profilach.

Ustalenia:
- UWM uzywa identycznego labelu co URK: 'Sumaryczna punktacja ministerialna'
  (nie 'MEiN'). Dziedziczymy regex z URK-style.
- WAIT_PROFILE = 12s - HTML profilu rosnie ze ~85 KB (@ 6s) do ~102-116 KB (@ 12s).
- Wszystkie pola bibliometryczne sa eksponowane: h-index (Scopus/WoS), Sumaryczny IF,
  Sumaryczny SNIP, Sumaryczna punktacja ministerialna, Liczba publikacji.
- Mlodzi naukowcy (asystenci, doktoranci) maja "Brak danych" przy IF/h-index -
  parser zwraca None, co jest poprawne.

Re-check po pelnym scrapingu - jesli niespodzianki na nietypowych profilach.
"""
from .base import OmegaPsirBaseParser, UniConfig


class UWMParser(OmegaPsirBaseParser):
    UNI = UniConfig(
        code="uwm",
        name="UWM",
        base_url="https://bazawiedzy.uwm.edu.pl",
        results_url="https://bazawiedzy.uwm.edu.pl/search/author?ps=20&t=simple&lang=pl",
    )
    WAIT_PROFILE = 12.0
    LABEL_SUM_MEIN = r"Sumaryczna\s*punktacja\s*(?:MEiN|ministerialna|MNiSW)"
