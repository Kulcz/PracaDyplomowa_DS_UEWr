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

    def _new_client(self) -> httpx.Client:
        return httpx.Client(timeout=self.TIMEOUT, follow_redirects=True,
                            headers={"User-Agent": "praca-dyplomowa-scraper/1.0"})

    def fetch_all_persons(self, client: httpx.Client, max_pages: int = 50) -> list[dict]:
        """Pobiera wszystkie Person entities przez paginowane REST."""
        url = self._api_url()
        persons: list[dict] = []
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
            print(f"  [persons page {page}] +{len(items)}  cumulative={len(persons)}/{total}")
            if len(items) < self.PAGE_SIZE:
                break
        return persons

    # ---------- ETAP 2: publikacje per Person ----------
    PUB_FIELDS = (
        "dc.title", "dc.date.issued", "dc.identifier.doi",
        "dc.identifier.issn", "dc.identifier.eissn", "dc.relation.ispartof",
        "dc.type", "dc.subtype",
        "dc.description.if", "dc.description.points",
        "dc.description.finance", "dc.description.financecost",
        "dc.share.type",
    )

    @staticmethod
    def _to_float_pl(x: str | None) -> float | None:
        if x is None:
            return None
        s = str(x).replace(",", ".").strip()
        if not s:
            return None
        try:
            return float(s)
        except ValueError:
            return None

    def fetch_publications(self, client: httpx.Client, person_uuid: str,
                           max_pages: int = 20) -> list[dict]:
        """Search Publications gdzie person_uuid figuruje jako autor.

        Why search free-text po UUID: DSpace nie wystawia osobnego endpointu
        publikacji-per-autora, ale UUID jako authority osadza sie w metadata,
        wiec query=UUID daje precyzyjne trafienia (zero false positives nazwiskowych).
        Trade-off: gubi prace gdzie UUID nie zostal zaprzypisany - szacujemy ~5-15%
        nizsze n_pub niz przy search po nazwisku, ale tamta metoda ma false positives
        przy popularnych nazwiskach. Wybieramy precyzje.
        """
        url = self._api_url()
        pubs: list[dict] = []
        for page in range(max_pages):
            resp = client.get(url, params={
                "f.entityType": "Publication,equals",
                "query": person_uuid,
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
                    pubs.append(obj)
            if len(items) < self.PAGE_SIZE:
                break
        return pubs

    def parse_publication(self, pub: dict, anchor_uuid: str) -> dict:
        """Wyciaga pola bibliometryczne + bonusy (finansowanie, OA) z publikacji."""
        md = pub.get("metadata", {})

        def get(key: str) -> str | None:
            v = md.get(key)
            if not v:
                return None
            val = v[0].get("value")
            return val.strip() if isinstance(val, str) and val.strip() else None

        return {
            "anchor_uuid": anchor_uuid,
            "work_uuid": pub.get("uuid", ""),
            "title": (get("dc.title") or "")[:250],
            "year": get("dc.date.issued"),
            "doi": get("dc.identifier.doi"),
            "issn": get("dc.identifier.issn"),
            "eissn": get("dc.identifier.eissn"),
            "journal": get("dc.relation.ispartof"),
            "pub_type": get("dc.type"),
            "pub_subtype": get("dc.subtype"),
            "if_value": self._to_float_pl(get("dc.description.if")),
            "points_mein": self._to_float_pl(get("dc.description.points")),
            "finance_model": get("dc.description.finance"),
            "finance_cost": self._to_float_pl(get("dc.description.financecost")),
            "share_type": get("dc.share.type"),
        }

    @staticmethod
    def aggregate_publications(parsed: list[dict]) -> dict:
        """Agreguje listę publikacji do metryk autora."""
        if not parsed:
            return {"n_pub": 0, "sum_IF": None, "sum_MEiN": None}
        ifs = [p["if_value"] for p in parsed if p["if_value"] is not None]
        pts = [p["points_mein"] for p in parsed if p["points_mein"] is not None]
        return {
            "n_pub": len(parsed),
            "sum_IF": sum(ifs) if ifs else None,
            "sum_MEiN": sum(pts) if pts else None,
        }

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

    PUB_COLUMNS = [
        "anchor_uuid", "work_uuid", "title", "year", "doi", "issn", "eissn",
        "journal", "pub_type", "pub_subtype",
        "if_value", "points_mein", "finance_model", "finance_cost", "share_type",
    ]
    AUTOSAVE_EVERY = 25

    def run(self, args: argparse.Namespace) -> int:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_csv = out_dir / f"{self.UNI.code}_{args.dyscyplina}_{timestamp}.csv"
        pubs_csv = out_dir / f"{self.UNI.code}_publications_{args.dyscyplina}_{timestamp}.csv"

        print(f"\n[CONFIG] UNI={self.UNI.name} | API={self.UNI.base_url}/server/api")
        print(f"[OUT persons] {out_csv}")
        print(f"[OUT pubs]    {pubs_csv}")

        with self._new_client() as client:
            # ---------- ETAP 1: Person entities ----------
            print("\n[ETAP 1] Pobieram Person entities z DSpace REST API...")
            persons = self.fetch_all_persons(client, max_pages=args.max_pages)
            if not persons:
                print("Brak wynikow z DSpace API.", file=sys.stderr)
                return 1

            records = [self.metadata_to_record(p) for p in persons]
            print(f"Pobrano {len(records)} osob z DSpace.")

            # Filtrowanie po dyscyplinie (po stronie klienta - brak facetu DSpace).
            if args.dyscyplina and args.dyscyplina != "all":
                disc_query = args.dyscyplina.replace("_", " ").strip().lower()
                filt = [r for r in records if r.researcharea and disc_query in r.researcharea.lower()]
                print(f"[FILTER] dyscyplina ~ {disc_query!r}: {len(filt)}/{len(records)}")
                records = filt

            if args.limit_profiles:
                records = records[: args.limit_profiles]
                print(f"[LIMIT] {len(records)} (--limit-profiles)")

            # ---------- ETAP 2: publikacje per Person ----------
            print(f"\n[ETAP 2] Publikacje per autor (n={len(records)}) — agregacja sum_IF/sum_MEiN/n_pub...")
            all_pubs: list[dict] = []
            for i, rec in enumerate(records, start=1):
                try:
                    raw_pubs = self.fetch_publications(client, rec.author_id)
                except Exception as e:
                    rec.error = f"pub-fetch: {e}"
                    print(f"  [{i}/{len(records)}] {rec.author_id} ERROR: {e}")
                    continue
                parsed = [self.parse_publication(p, rec.author_id) for p in raw_pubs]
                all_pubs.extend(parsed)
                agg = self.aggregate_publications(parsed)
                rec.n_pub = agg["n_pub"]
                rec.sum_IF = agg["sum_IF"]
                rec.sum_MEiN = agg["sum_MEiN"]

                if i % self.AUTOSAVE_EVERY == 0 or i == len(records):
                    pd.DataFrame([asdict(r) for r in records], columns=COLUMNS).to_csv(
                        out_csv, index=False, encoding="utf-8")
                    pd.DataFrame(all_pubs, columns=self.PUB_COLUMNS).to_csv(
                        pubs_csv, index=False, encoding="utf-8")
                    median_n = sorted(r.n_pub or 0 for r in records[:i])[i // 2]
                    print(f"  [{i}/{len(records)}] cumulative pubs={len(all_pubs)} | "
                          f"median n_pub={median_n} | autosave OK")

        # ---------- Finalne zapisy ----------
        pd.DataFrame([asdict(r) for r in records], columns=COLUMNS).to_csv(
            out_csv, index=False, encoding="utf-8")
        pd.DataFrame(all_pubs, columns=self.PUB_COLUMNS).to_csv(
            pubs_csv, index=False, encoding="utf-8")
        print(f"\nZapisano persons: {out_csv}  ({len(records)} wierszy)")
        print(f"Zapisano pubs:    {pubs_csv}  ({len(all_pubs)} wierszy)")
        return 0
