"""
Scraper UP Poznan - sciencerep.up.poznan.pl (DSpace-CRIS 2023.01).

Wykorzystuje DSpace REST API (JSON) - nie wymaga Playwright ani recznego filtra.

Endpoint: GET /server/api/discover/search/objects?f.entityType=Person,equals
- Zwraca 933 rekordy typu Person, paginacja przez 'page'/'size'.
- Kazdy Person ma w metadata: givenName, familyName, title (tytul nauk.), ORCID,
  POL-on ID (klucz do RAD-on/PBN!), researcharea (DYSCYPLINA!), affiliation (wydzial),
  oairecerif.person.additionalaffiliation (katedra/jednostka).
- Filter po dyscyplinie nie ma facetu DSpace - filtrujemy w Pythonie po polu
  person.researcharea (zwykly string typu 'rolnictwo i ogrodnictwo').

Strategia metodyczna (B): scrapujemy TYLKO TOZSAMOSC. Metryki bibliometryczne
(h-index, FWCI, n_pub, cited_by_count) liczymy z OpenAlex w 04_openalex_works.R.
DSpace UP Poznan nie eksponuje agregatow bibliometrycznych w UI ani w API.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

import httpx
import pandas as pd

from .base import BaseParser, UniConfig, ProfileRecord, COLUMNS


class UPPoznanParser(BaseParser):
    UNI = UniConfig(
        code="up_poznan",
        name="UP_Poznan",
        base_url="https://sciencerep.up.poznan.pl",
    )
    PAGE_SIZE = 100
    TIMEOUT = 30.0

    def profile_url(self, uuid: str) -> str:
        return f"{self.UNI.base_url}/entities/person/{uuid}"

    def _api_url(self) -> str:
        return f"{self.UNI.base_url}/server/api/discover/search/objects"

    def fetch_all_persons(self, max_pages: int = 50) -> list[dict]:
        """Pobiera wszystkie Person entities przez paginowane REST."""
        url = self._api_url()
        persons: list[dict] = []
        with httpx.Client(timeout=self.TIMEOUT, follow_redirects=True,
                          headers={"User-Agent": "praca-dyplomowa-scraper/1.0"}) as client:
            for page in range(max_pages):
                resp = client.get(url, params={
                    "f.entityType": "Person,equals",
                    "size": self.PAGE_SIZE,
                    "page": page,
                })
                resp.raise_for_status()
                data = resp.json()
                sr = data.get("_embedded", {}).get("searchResult", {})
                items = sr.get("_embedded", {}).get("objects", [])
                if not items:
                    break
                for it in items:
                    obj = it.get("_embedded", {}).get("indexableObject", {})
                    if obj:
                        persons.append(obj)
                page_info = sr.get("page", {})
                total = page_info.get("totalElements", "?")
                print(f"  [page {page}] +{len(items)}  cumulative={len(persons)}/{total}")
                if len(items) < self.PAGE_SIZE:
                    break
        return persons

    def metadata_to_record(self, obj: dict) -> ProfileRecord:
        """Mapuje DSpace Person metadata na ProfileRecord."""
        md = obj.get("metadata", {})

        def get(key: str) -> str | None:
            v = md.get(key)
            if not v:
                return None
            val = v[0].get("value")
            return val.strip() if isinstance(val, str) and val.strip() else None

        given = get("person.givenName")
        family = get("person.familyName")
        if given and family:
            profil = f"{given} {family}"
        else:
            profil = get("dc.title")

        return ProfileRecord(
            profil=profil,
            tytul=get("person.title"),
            # DSpace nie ma 'stanowisko' jako odrebnego pola.
            stanowisko=None,
            jednostka=get("oairecerif.person.additionalaffiliation"),
            wydzial=get("dc.affiliation"),
            orcid=get("person.identifier.orcid"),
            scopus_id=get("person.identifier.scopus-author-id"),
            polon_id=get("person.identifier.polon"),
            researcharea=get("person.researcharea"),
            author_id=obj.get("uuid", ""),
            url=self.profile_url(obj.get("uuid", "")),
        )

    def parse_profile(self, html: str) -> ProfileRecord:
        """Niewymagane - UP Poznan uzywa REST API, nie HTML scrapingu."""
        raise NotImplementedError("UP Poznan uses REST API; use run() instead")

    def run(self, args: argparse.Namespace) -> int:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_csv = out_dir / f"{self.UNI.code}_{args.dyscyplina}_{timestamp}.csv"

        print(f"\n[CONFIG] UNI={self.UNI.name} | API={self.UNI.base_url}/server/api")
        print(f"[OUT] {out_csv}")

        print("\n[FETCH] Pobieram wszystkie Person entities z DSpace REST API...")
        persons = self.fetch_all_persons(max_pages=args.max_pages)
        if not persons:
            print("Brak wynikow z DSpace API.", file=sys.stderr)
            return 1

        records = [self.metadata_to_record(p) for p in persons]
        print(f"\nPobrano {len(records)} osob z DSpace.")

        # Filtrowanie po dyscyplinie (po stronie klienta - brak facetu DSpace).
        if args.dyscyplina and args.dyscyplina != "all":
            disc_query = args.dyscyplina.replace("_", " ").strip().lower()
            filt = [r for r in records if r.researcharea and disc_query in r.researcharea.lower()]
            print(f"[FILTER] dyscyplina ~ {disc_query!r}: {len(filt)}/{len(records)}")
            records = filt

        if args.limit_profiles:
            records = records[: args.limit_profiles]
            print(f"[LIMIT] {len(records)} (--limit-profiles)")

        rows = [asdict(r) for r in records]
        df = pd.DataFrame(rows, columns=COLUMNS)
        df.to_csv(out_csv, index=False, encoding="utf-8")
        print(f"\nZapisano: {out_csv}  ({len(df)} wierszy)")
        return 0
