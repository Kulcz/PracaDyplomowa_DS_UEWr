"""
Parser Bazy Wiedzy URK (Uniwersytet Rolniczy w Krakowie).

Roznice wzgledem UPWR (stwierdzone 2026-05-25 na rendered HTML profilu Adeli Adamus):

1. URK uzywa labela 'Sumaryczna punktacja ministerialna' zamiast 'Sumaryczna punktacja MEiN'
   - regex pojscie z bazy musi obejmowac obie warianty.

2. PrimeFaces na URK laduje wolniej - po 6s HTML ma 91 KB i metryki nie sa jeszcze
   widoczne; po 12s rosnie do 125 KB i wszystko jest. Dlatego WAIT_PROFILE=12.

Po dostosowaniu: rendered HTML jednego profilu zawiera 'Sumaryczny IF 31,917',
'Sumaryczna punktacja ministerialna 924', 'h-index (Scopus) 4', 'h-index (WoS) 9'.
"""
from .base import OmegaPsirBaseParser, UniConfig


class URKParser(OmegaPsirBaseParser):
    UNI = UniConfig(
        code="urk",
        name="URK",
        base_url="https://repo.ur.krakow.pl",
        results_url="https://repo.ur.krakow.pl/search/author?ps=20&t=simple&lang=pl",
    )
    # 12s po obserwacji rosnacego rendered HTML (91 KB @ 6s -> 125 KB @ 12s).
    WAIT_PROFILE = 12.0

    # URK uzywa "ministerialna" zamiast "MEiN"; zostawiamy oba w regexie zeby
    # zlapac potencjalne mieszanki na poszczegolnych profilach.
    LABEL_SUM_MEIN = r"Sumaryczna\s*punktacja\s*(?:MEiN|ministerialna|MNiSW)"
