"""
Parser Bazy Wiedzy UPWR (Uniwersytet Przyrodniczy we Wroclawiu).

Status: zweryfikowany 2026-05-24 na zbiorze 146 profili dyscypliny rolnictwo i ogrodnictwo
(pokrycie: h_scopus 92%, h_wos 87%, sum_IF 91%, n_pub 93%, stanowisko 72%).
Domyslny BaseParser dziala bez zmian - UPWR uzywa standardowych labeli Omega-PSIR.
"""
from .base import OmegaPsirBaseParser, UniConfig


class UPWRParser(OmegaPsirBaseParser):
    UNI = UniConfig(
        code="upwr",
        name="UPWR",
        base_url="https://bazawiedzy.upwr.edu.pl",
        results_url="https://bazawiedzy.upwr.edu.pl/search/author?ps=20&t=simple&lang=pl",
    )
    WAIT_PROFILE = 6.0
