"""
Fetch scioperi (strikes) data from the Italian Ministry of Transport (MIT) website.

Source: https://scioperi.mit.gov.it/mit2/public/scioperi
This page is updated periodically by MIT's "osservatorio sui conflitti sindacali"
and lists upcoming transport strikes with sector, region/province, dates, times, etc.

Usage:
    python fetch_scioperi.py                  # print summary to console
    python fetch_scioperi.py --json out.json  # save structured data to JSON
    python fetch_scioperi.py --settore Aereo  # filter client-side by settore

Notes / legal:
    - This is a public government website providing official information.
    - Before running this on a schedule (e.g. every few hours via cron),
      check https://scioperi.mit.gov.it/robots.txt and don't hammer the
      server -- a fetch every 3-6 hours is more than enough since the page
      itself says it's updated periodically, not in real time to the second.
    - Set a descriptive User-Agent so MIT can identify/contact you if needed.
"""

import argparse
import json
import re
import sys
import time
from datetime import datetime, date, timedelta

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://scioperi.mit.gov.it/mit2/public/scioperi"

HEADERS = {
    # Be a good citizen: identify your app/bot clearly.
    "User-Agent": "ScioperiAppMVP/0.1 (contact: YOUR-EMAIL@example.com)"
}

# Column order as they appear in the table on the MIT page
COLUMNS = [
    "inizio",
    "fine",
    "sindacati",
    "settore",
    "categoria",
    "modalita",
    "rilevanza",
    "note",
    "data_proclamazione",
    "regione",
    "provincia",
    "data_ricezione",
]


# Pause (secondi) prima di ciascun nuovo tentativo: 1 tentativo + 2 retry.
RETRY_BACKOFF = (5, 15)


def fetch_html(url: str = BASE_URL) -> str:
    for attesa in (*RETRY_BACKOFF, None):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=(10, 30))
            break
        except (requests.ConnectTimeout, requests.ReadTimeout, requests.ConnectionError):
            if attesa is None:
                raise
            time.sleep(attesa)
    resp.raise_for_status()
    return resp.text


def parse_date(value: str):
    """Convert dd/mm/yyyy (optionally with time) to ISO 8601, or return None."""
    value = value.strip()
    if not value:
        return None
    for fmt in ("%d/%m/%Y %H:%M", "%d/%m/%Y"):
        try:
            return datetime.strptime(value, fmt).isoformat()
        except ValueError:
            continue
    return value  # fallback: leave as-is if format is unexpected


# --- Parsing delle fasce orarie dal campo libero "modalita" -----------------
#
# Esempi reali visti nei dati MIT:
#   "24 ORE"
#   "24 ORE: DALLE 21.00 DEL 6/7 ALLE 21.00 DEL 7/7"
#   "4 ORE: DALLE 18.30 ALLE 22.30"
#   "23 ORE: DALLE 03.00 DEL 9/7 ALLE 02.00 DEL 10/7"
#   "8 ORE: 8.30-12.30 / 15.30-19.30"          <- turni spezzati
#   "INTERO TURNO DI LAVORO"
#   "INTERA GIORNATA - TPL: INTERO TURNO DI SERVIZIO"
#   "SETTORE FERROVIARIO ... 24 ORE: DALLE 21.00 DEL 23/7 ALLE 20.59 DEL 24/7; *TPL: ..."

# Pattern 1: "DALLE hh.mm [DEL gg/mm] ALLE hh.mm [DEL gg/mm]"
_RANGE_WITH_DEL = re.compile(
    r"DALLE\s+(\d{1,2})[.:](\d{2})(?:\s+DEL\s+(\d{1,2})/(\d{1,2}))?"
    r"\s+ALLE\s+(\d{1,2})[.:](\d{2})(?:\s+DEL\s+(\d{1,2})/(\d{1,2}))?",
    re.IGNORECASE,
)

# Pattern 2: bare "hh.mm-hh.mm" or "hh.mm - hh.mm" ranges (may repeat, e.g. split shifts)
_BARE_RANGE = re.compile(
    r"(\d{1,2})[.:](\d{2})\s*-\s*(\d{1,2})[.:](\d{2})"
)

_FULL_DAY_HINTS = ("24 ORE", "INTERA GIORNATA", "INTERO TURNO", "GIORNATA INTERA")


def _combine(d: date, hh: str, mm: str) -> str:
    hour = int(hh)
    if hour == 24:
        # "24.00" e' un modo comune (non-standard per Python) di scrivere
        # mezzanotte di fine giornata -> diventa 00:00 del giorno dopo.
        next_day = d + timedelta(days=1)
        return datetime(next_day.year, next_day.month, next_day.day, 0, int(mm)).isoformat()
    return datetime(d.year, d.month, d.day, hour, int(mm)).isoformat()


def parse_orario(modalita: str, inizio_date: date, fine_date: date) -> dict:
    """Estrae ora_inizio/ora_fine (e datetime completi) dal campo modalita.

    Ritorna un dict con:
      - ora_inizio, ora_fine: stringhe "HH:MM" o None
      - inizio_datetime_iso, fine_datetime_iso: datetime completi ISO o None
      - fascia_oraria: uno tra
            "esplicita"            -> orario preciso trovato e affidabile
            "turni_spezzati"       -> piu' fasce orarie nello stesso giorno
            "giornata_intera_assunta" -> nessun orario esplicito, assunto 00:00-23:59
            "non_strutturata"      -> non e' stato possibile determinare l'orario
    """
    modalita = (modalita or "").strip()
    if not modalita:
        return {
            "ora_inizio": None, "ora_fine": None,
            "inizio_datetime_iso": None, "fine_datetime_iso": None,
            "fascia_oraria": "non_strutturata",
        }

    m = _RANGE_WITH_DEL.search(modalita)
    if m:
        h1, m1, gg1, mm1, h2, m2, gg2, mm2 = m.groups()
        start_date = (
            date(inizio_date.year, int(mm1), int(gg1)) if gg1 else inizio_date
        )
        end_date = (
            date(fine_date.year, int(mm2), int(gg2)) if gg2 else fine_date
        )
        return {
            "ora_inizio": f"{int(h1):02d}:{m1}",
            "ora_fine": f"{int(h2):02d}:{m2}",
            "inizio_datetime_iso": _combine(start_date, h1, m1),
            "fine_datetime_iso": _combine(end_date, h2, m2),
            "fascia_oraria": "esplicita",
        }

    bare_matches = _BARE_RANGE.findall(modalita)
    if bare_matches:
        if len(bare_matches) > 1:
            # Turni spezzati: prendo l'inviluppo (prima ora inizio, ultima ora fine)
            # ma segnalo che ci sono buchi nel mezzo -> il chiamante deve saperlo.
            first = bare_matches[0]
            last = bare_matches[-1]
            return {
                "ora_inizio": f"{int(first[0]):02d}:{first[1]}",
                "ora_fine": f"{int(last[2]):02d}:{last[3]}",
                "inizio_datetime_iso": _combine(inizio_date, first[0], first[1]),
                "fine_datetime_iso": _combine(fine_date, last[2], last[3]),
                "fascia_oraria": "turni_spezzati",
            }
        h1, m1, h2, m2 = bare_matches[0]
        return {
            "ora_inizio": f"{int(h1):02d}:{m1}",
            "ora_fine": f"{int(h2):02d}:{m2}",
            "inizio_datetime_iso": _combine(inizio_date, h1, m1),
            "fine_datetime_iso": _combine(fine_date, h2, m2),
            "fascia_oraria": "esplicita",
        }

    if any(hint in modalita.upper() for hint in _FULL_DAY_HINTS):
        return {
            "ora_inizio": "00:00",
            "ora_fine": "23:59",
            "inizio_datetime_iso": _combine(inizio_date, "00", "00"),
            "fine_datetime_iso": _combine(fine_date, "23", "59"),
            "fascia_oraria": "giornata_intera_assunta",
        }

    return {
        "ora_inizio": None, "ora_fine": None,
        "inizio_datetime_iso": None, "fine_datetime_iso": None,
        "fascia_oraria": "non_strutturata",
    }


def parse_scioperi(html: str) -> list[dict]:
    soup = BeautifulSoup(html, "lxml")

    # The main data table is the first <table> with a header row matching
    # our expected columns (there may be other small tables on the page,
    # e.g. the "Legenda Settore" table at the bottom).
    tables = soup.find_all("table")
    data_table = None
    for t in tables:
        header_text = t.get_text(" ", strip=True).lower()
        if "inizio" in header_text and "sindacati" in header_text:
            data_table = t
            break

    if data_table is None:
        raise RuntimeError(
            "Could not find the scioperi data table -- the site's HTML "
            "structure may have changed. Inspect the page manually."
        )

    rows = data_table.find_all("tr")
    records = []

    for row in rows:
        cells = row.find_all("td")
        if len(cells) < len(COLUMNS):
            continue  # skip header rows / malformed rows

        # First cell is often an empty "expand" column, so align from the
        # right if there's an extra leading cell.
        cell_texts = [c.get_text(" ", strip=True) for c in cells]
        if len(cell_texts) > len(COLUMNS):
            cell_texts = cell_texts[-len(COLUMNS):]

        record = dict(zip(COLUMNS, cell_texts))
        record["inizio_iso"] = parse_date(record.get("inizio", ""))
        record["fine_iso"] = parse_date(record.get("fine", ""))
        record["data_proclamazione_iso"] = parse_date(
            record.get("data_proclamazione", "")
        )
        record["data_ricezione_iso"] = parse_date(record.get("data_ricezione", ""))

        # Estrai la fascia oraria precisa dal campo "modalita" (fondamentale
        # per capire se un viaggio/volo specifico ricade nella finestra di sciopero).
        try:
            inizio_date = datetime.strptime(record["inizio"], "%d/%m/%Y").date()
            fine_date = datetime.strptime(record["fine"], "%d/%m/%Y").date()
            orario = parse_orario(record.get("modalita", ""), inizio_date, fine_date)
        except (ValueError, KeyError):
            orario = {
                "ora_inizio": None, "ora_fine": None,
                "inizio_datetime_iso": None, "fine_datetime_iso": None,
                "fascia_oraria": "non_strutturata",
            }
        record.update(orario)

        records.append(record)

    return records


def main():
    parser = argparse.ArgumentParser(description="Fetch scioperi from MIT")
    parser.add_argument("--json", help="Path to save JSON output", default=None)
    parser.add_argument("--settore", help="Filter by settore (e.g. Aereo)", default=None)
    parser.add_argument("--regione", help="Filter by regione (e.g. Lombardia)", default=None)
    args = parser.parse_args()

    print(f"Fetching {BASE_URL} ...", file=sys.stderr)
    html = fetch_html()
    records = parse_scioperi(html)
    print(f"Parsed {len(records)} scioperi.", file=sys.stderr)

    if args.settore:
        records = [r for r in records if r["settore"].lower() == args.settore.lower()]
    if args.regione:
        records = [r for r in records if r["regione"].lower() == args.regione.lower()]

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(records, f, ensure_ascii=False, indent=2)
        print(f"Saved to {args.json}", file=sys.stderr)
    else:
        for r in records:
            orario = f"{r['ora_inizio'] or '??'}-{r['ora_fine'] or '??'}"
            print(
                f"{r['inizio']} -> {r['fine']} [{orario:<11} {r['fascia_oraria']:<24}] | "
                f"{r['settore']:<28} | {r['regione']:<10} {r['provincia']:<10} | "
                f"{r['categoria'][:50]}"
            )


if __name__ == "__main__":
    main()
