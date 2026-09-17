#!/usr/bin/env python3
"""Generate the bundled offline species taxonomy from WoRMS.

The app uses App/Resources/species.json at runtime and never calls WoRMS
directly. Run this script manually when the bundled reference data should be
refreshed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, as_completed, wait
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "App" / "Resources" / "species.json"
WORMS_REST_BASE_URL = "https://www.marinespecies.org/rest"
PAGE_SIZE = 50
REQUEST_DELAY_SECONDS = 0.05
REQUEST_TIMEOUT_SECONDS = 30
MAX_RETRIES = 3
DEFAULT_WORKERS = 8


@dataclass(frozen=True)
class TaxonSeed:
    name: str
    group: str


TAXON_SEEDS = [
    TaxonSeed(name="Elasmobranchii", group="elasmobranch"),
    TaxonSeed(name="Odontoceti", group="odontocete"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch elasmobranch and odontocete species from WoRMS and write App/Resources/species.json."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output JSON path. Defaults to {DEFAULT_OUTPUT}.",
    )
    parser.add_argument(
        "--include-extinct",
        action="store_true",
        help="Include extinct taxa. By default only extant marine taxa are fetched.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch and validate the taxonomy without writing the output file.",
    )
    parser.add_argument(
        "--skip-common-names",
        action="store_true",
        help="Skip vernacular-name lookups. Useful for quick API smoke checks.",
    )
    parser.add_argument(
        "--request-delay",
        type=float,
        default=REQUEST_DELAY_SECONDS,
        help="Seconds to wait after each WoRMS request. Defaults to 0.05.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help="Maximum concurrent WoRMS requests. Defaults to 8.",
    )
    parser.add_argument(
        "--max-species",
        type=int,
        default=None,
        help="Stop after this many species. Intended only for smoke testing.",
    )
    parser.add_argument(
        "--taxon",
        action="append",
        default=None,
        metavar="GROUP:NAME",
        help=(
            "Taxon seed to fetch, such as elasmobranch:Elasmobranchii. "
            "Use multiple times. When provided, replaces the default seeds."
        ),
    )
    parser.add_argument(
        "--extra-taxon",
        action="append",
        default=None,
        metavar="GROUP:NAME",
        help="Additional taxon seed to fetch on top of the defaults.",
    )
    return parser.parse_args()


def parse_taxon_seed(value: str) -> TaxonSeed:
    try:
        group, name = value.split(":", 1)
    except ValueError as error:
        raise argparse.ArgumentTypeError("Taxon seeds must use GROUP:NAME format.") from error

    group = group.strip()
    name = name.strip()
    if not group or not name:
        raise argparse.ArgumentTypeError("Taxon seed group and name must both be non-empty.")
    return TaxonSeed(name=name, group=group)


def selected_taxon_seeds(args: argparse.Namespace) -> list[TaxonSeed]:
    seeds = [parse_taxon_seed(value) for value in args.taxon] if args.taxon else list(TAXON_SEEDS)
    seeds.extend(parse_taxon_seed(value) for value in args.extra_taxon or [])
    return seeds


def request_json(
    path: str,
    query: dict[str, str | int | bool] | None = None,
    allow_empty: bool = False,
    request_delay: float = REQUEST_DELAY_SECONDS,
) -> Any:
    query_string = urllib.parse.urlencode(query or {})
    url = f"{WORMS_REST_BASE_URL}/{path}"
    if query_string:
        url = f"{url}?{query_string}"

    last_error: Exception | None = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(url, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                time.sleep(max(0, request_delay))
                body = response.read()
                if not body:
                    if allow_empty:
                        return None
                    raise json.JSONDecodeError("Empty response", "", 0)
                return json.loads(body)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = error
            if attempt == MAX_RETRIES:
                break
            time.sleep(REQUEST_DELAY_SECONDS * attempt)

    raise RuntimeError(f"WoRMS request failed after {MAX_RETRIES} attempts: {url}") from last_error


def resolve_taxon_id(name: str, request_delay: float) -> int:
    records = request_json(
        f"AphiaRecordsByName/{urllib.parse.quote(name)}",
        {"like": "false", "marine_only": "true"},
        request_delay=request_delay,
    )
    if not isinstance(records, list):
        raise RuntimeError(f"Unexpected WoRMS response while resolving {name}.")

    for record in records:
        if not isinstance(record, dict):
            continue
        if record.get("scientificname") == name and record.get("status") == "accepted":
            aphia_id = record.get("AphiaID")
            if isinstance(aphia_id, int):
                return aphia_id

    raise RuntimeError(f"Could not resolve accepted WoRMS AphiaID for {name}.")


def children(parent_id: int, include_extinct: bool, request_delay: float) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    offset = 1

    while True:
        page = request_json(
            f"AphiaChildrenByAphiaID/{parent_id}",
            {
                "marine_only": "true",
                "extant_only": "false" if include_extinct else "true",
                "offset": offset,
            },
            allow_empty=True,
            request_delay=request_delay,
        )
        if not page:
            break
        if not isinstance(page, list):
            raise RuntimeError(f"Unexpected WoRMS children response for AphiaID {parent_id}.")

        typed_page = [record for record in page if isinstance(record, dict)]
        records.extend(typed_page)
        if len(typed_page) < PAGE_SIZE:
            break
        offset += PAGE_SIZE

    return records


def english_common_name(aphia_id: int, request_delay: float) -> str | None:
    try:
        vernaculars = request_json(
            f"AphiaVernacularsByAphiaID/{aphia_id}",
            allow_empty=True,
            request_delay=request_delay,
        )
    except RuntimeError:
        return None

    if not isinstance(vernaculars, list):
        return None

    english_names: list[str] = []
    fallback_names: list[str] = []
    for vernacular in vernaculars:
        if not isinstance(vernacular, dict):
            continue
        name = vernacular.get("vernacular")
        if not isinstance(name, str) or not name.strip():
            continue
        language = str(vernacular.get("language", "")).lower()
        language_code = str(vernacular.get("language_code", "")).lower()
        if language == "english" or language_code in {"eng", "en"}:
            english_names.append(name.strip())
        else:
            fallback_names.append(name.strip())

    candidates = english_names or fallback_names
    return sorted(set(candidates), key=lambda value: (len(value), value.lower()))[0] if candidates else None


def species_record(record: dict[str, Any], group: str) -> dict[str, Any] | None:
    aphia_id = record.get("AphiaID")
    scientific_name = record.get("scientificname")
    if not isinstance(aphia_id, int) or not isinstance(scientific_name, str):
        return None

    parts = scientific_name.split()
    if len(parts) < 2:
        return None

    family = record.get("family")
    if not isinstance(family, str) or not family:
        family = ""

    return {
        "id": aphia_id,
        "scientificName": scientific_name,
        "genus": parts[0],
        "family": family,
        "commonName": None,
        "group": group,
    }


def collect_species(
    parent_id: int,
    group: str,
    include_extinct: bool,
    request_delay: float,
    max_species: int | None,
    workers: int,
) -> list[dict[str, Any]]:
    pending = [parent_id]
    seen_parents: set[int] = set()
    species: dict[int, dict[str, Any]] = {}

    with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {}

        while pending or futures:
            while pending and len(futures) < max(1, workers):
                current_id = pending.pop()
                if current_id in seen_parents:
                    continue
                seen_parents.add(current_id)
                futures[executor.submit(children, current_id, include_extinct, request_delay)] = current_id

            if not futures:
                continue

            done, _ = wait(futures, return_when=FIRST_COMPLETED)
            for future in done:
                futures.pop(future)
                for child in future.result():
                    child_id = child.get("AphiaID")
                    rank = child.get("rank")
                    status = child.get("status")
                    valid_id = child.get("valid_AphiaID")

                    if not isinstance(child_id, int):
                        continue
                    if status != "accepted" or valid_id not in {None, child_id}:
                        continue
                    if rank == "Species":
                        record = species_record(child, group)
                        if record is not None:
                            species[record["id"]] = record
                            if max_species is not None and len(species) >= max_species:
                                for remaining in futures:
                                    remaining.cancel()
                                return list(species.values())
                    else:
                        pending.append(child_id)

                if len(seen_parents) % 20 == 0:
                    print(
                        f"  visited {len(seen_parents)} taxon nodes, collected {len(species)} {group} species...",
                        file=sys.stderr,
                    )

    return list(species.values())


def add_common_names(records: list[dict[str, Any]], request_delay: float, workers: int) -> None:
    def load(record: dict[str, Any]) -> tuple[int, str | None]:
        return record["id"], english_common_name(record["id"], request_delay)

    records_by_id = {record["id"]: record for record in records}
    with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = [executor.submit(load, record) for record in records]
        completed = 0
        for future in as_completed(futures):
            species_id, common_name = future.result()
            records_by_id[species_id]["commonName"] = common_name
            completed += 1
            if completed % 100 == 0:
                print(f"  fetched common names for {completed}/{len(records)} species...", file=sys.stderr)


def write_species(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(records, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    records: list[dict[str, Any]] = []

    for seed in selected_taxon_seeds(args):
        print(f"Resolving {seed.name}...", file=sys.stderr)
        parent_id = resolve_taxon_id(seed.name, args.request_delay)
        print(f"Fetching {seed.name} descendants from AphiaID {parent_id}...", file=sys.stderr)
        records.extend(
            collect_species(
                parent_id,
                seed.group,
                args.include_extinct,
                request_delay=args.request_delay,
                max_species=args.max_species,
                workers=args.workers,
            )
        )
        if args.max_species is not None and len(records) >= args.max_species:
            records = records[:args.max_species]
            break

    if not args.skip_common_names:
        print(f"Fetching common names for {len(records)} species...", file=sys.stderr)
        add_common_names(records, args.request_delay, args.workers)

    records = sorted(
        records,
        key=lambda record: (
            record["group"],
            record["family"],
            record["genus"],
            record["scientificName"],
            record["id"],
        ),
    )

    if args.dry_run:
        print(json.dumps(records[:5], indent=2, ensure_ascii=False))
        print(f"Fetched {len(records)} species.", file=sys.stderr)
        return 0

    write_species(args.output, records)
    print(f"Wrote {len(records)} species to {args.output}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
