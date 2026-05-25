"""
Entry point dla scrapera Omega-PSIR (Python/Playwright).

Uzycie:
    source .venv/bin/activate
    python Skrypty/Python/scrape.py --uni URK --dyscyplina rolnictwo_i_ogrodnictwo

Flagi:
    --uni              UPWR / SGGW / URK / UWM (wymagane)
    --dyscyplina       etykieta do nazwy pliku wyjsciowego (default 'all')
    --url              override URL listy wynikow (default z UniConfig)
    --out-dir          katalog wyjsciowy (default 'Dane/raw')
    --headless         bez okna (do testow; do scrapingu zostaw off)
    --max-pages        limit klikniec next (default 300)
    --limit-profiles   limit pobranych profili (do testow)

Flow:
1. Otwiera Chromium z URL listy wynikow uczelni.
2. Ustaw filtr dyscypliny w panelu po lewej -> 'Filtruj'.
3. Wcisnij ENTER w terminalu -> ETAP 1 (zbieranie author_id) -> ETAP 2 (profile + bibliometria).
4. Wynik: Dane/raw/<code>_<dyscyplina>_<timestamp>.csv (autosave co 10).
"""
import sys
from pathlib import Path

# Wstrzykuj katalog skryptu do sys.path, zeby 'from scrapers import ...' dzialalo
# zarowno przy 'python scrape.py' jak i 'python -m scrape'.
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from scrapers import REGISTRY
from scrapers.core import build_arg_parser


def main() -> int:
    args = build_arg_parser(list(REGISTRY.keys())).parse_args()
    parser_cls = REGISTRY[args.uni]
    parser = parser_cls()
    return parser.run(args)


if __name__ == "__main__":
    sys.exit(main())
