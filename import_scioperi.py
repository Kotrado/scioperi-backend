"""
Importa gli scioperi nel database a partire dal JSON prodotto da fetch_scioperi.py.

Uso tipico (import manuale da file, utile in locale):
    python fetch_scioperi.py --json /tmp/scioperi.json
    python import_scioperi.py /tmp/scioperi.json

In produzione, l'import viene invece fatto dall'endpoint POST /admin/refresh
(vedi main.py), che chiama importa_records() direttamente senza passare da
un file JSON intermedio -- questo file resta utile per l'uso locale/debug.
"""

import json
import sys
from datetime import datetime, date, timezone

from sqlalchemy.orm import Session

from database import SessionLocal, init_db
from models import Sciopero


def _parse_date(value: str) -> date | None:
    if not value:
        return None
    return datetime.strptime(value, "%d/%m/%Y").date()


def _parse_datetime(value: str) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value)


def importa_records(db: Session, records: list[dict]) -> tuple[int, int]:
    """Upsert di una lista di record (dict, stesso formato del JSON dello
    scraper) nel database. Ritorna (nuovi, aggiornati)."""
    nuovi, aggiornati = 0, 0

    for r in records:
        inizio_data = _parse_date(r["inizio"])
        fine_data = _parse_date(r["fine"])

        # Chiave naturale per capire se questo sciopero esiste gia' (evita
        # duplicati quando rifacciamo il fetch periodico e ritroviamo gli
        # stessi scioperi gia' noti).
        esistente = (
            db.query(Sciopero)
            .filter_by(
                fonte="mit",
                inizio_data=inizio_data,
                categoria=r.get("categoria"),
                modalita_originale=r.get("modalita"),
                sindacati=r.get("sindacati"),
            )
            .first()
        )

        campi = dict(
            fonte="mit",
            inizio_data=inizio_data,
            fine_data=fine_data,
            ora_inizio=r.get("ora_inizio"),
            ora_fine=r.get("ora_fine"),
            inizio_datetime=_parse_datetime(r.get("inizio_datetime_iso")),
            fine_datetime=_parse_datetime(r.get("fine_datetime_iso")),
            fascia_oraria=r.get("fascia_oraria", "non_strutturata"),
            settore=r.get("settore"),
            categoria=r.get("categoria"),
            modalita_originale=r.get("modalita"),
            sindacati=r.get("sindacati"),
            rilevanza=r.get("rilevanza"),
            regione=r.get("regione"),
            provincia=r.get("provincia"),
            note=r.get("note"),
            data_proclamazione=_parse_date(r.get("data_proclamazione", "")),
            data_ricezione=_parse_datetime(r.get("data_ricezione_iso")),
        )

        if esistente:
            for k, v in campi.items():
                setattr(esistente, k, v)
            esistente.aggiornato_il = datetime.now(timezone.utc)
            aggiornati += 1
        else:
            db.add(Sciopero(**campi))
            nuovi += 1

    db.commit()
    return nuovi, aggiornati


def importa(json_path: str):
    """Import da file JSON, per uso locale/manuale da riga di comando."""
    init_db()
    db = SessionLocal()
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            records = json.load(f)
        nuovi, aggiornati = importa_records(db, records)
        print(f"Import completato: {nuovi} nuovi, {aggiornati} aggiornati.", file=sys.stderr)
    finally:
        db.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uso: python import_scioperi.py <path_al_json>", file=sys.stderr)
        sys.exit(1)
    importa(sys.argv[1])
