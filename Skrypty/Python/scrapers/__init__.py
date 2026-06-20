"""Rejestr scraperow CRIS uczelnianych (6 uczelni: 4 Omega-PSIR + DSpace + OpenUP).

Uzycie z linii polecen:
    python Skrypty/Python/scrape.py --uni URK --dyscyplina rolnictwo_i_ogrodnictwo

Uzycie programowe:
    from scrapers import REGISTRY
    parser = REGISTRY["URK"]()
    parser.run(args)
"""
from .base import (
    BaseParser, OmegaPsirBaseParser, UniConfig, ProfileRecord, COLUMNS,
)
from .upwr import UPWRParser
from .sggw import SGGWParser
from .urk import URKParser
from .uwm import UWMParser
from .up_poznan import UPPoznanParser
from .up_lublin import UPLublinParser

REGISTRY: dict[str, type[BaseParser]] = {
    # --- Core: 4 instancje Omega-PSIR (proba finalna) ---
    "UPWR": UPWRParser,
    "SGGW": SGGWParser,
    "URK": URKParser,
    "UWM": UWMParser,
    # --- HISTORYCZNE: uczelnie poza proba finalna, niewykorzystywane w core ---
    # Zostaja na wypadek powrotu; brak dla nich danych w Dane/, nie wchodza do
    # pipeline'u R. UP Poznan - niekompletny DSpace; UP Lublin - OpenUP (B+).
    "UP_POZNAN": UPPoznanParser,
    "UP_LUBLIN": UPLublinParser,
}

__all__ = [
    "BaseParser", "OmegaPsirBaseParser", "UniConfig", "ProfileRecord", "COLUMNS",
    "UPWRParser", "SGGWParser", "URKParser", "UWMParser",
    "UPPoznanParser", "UPLublinParser",
    "REGISTRY",
]
