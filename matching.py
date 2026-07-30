"""
Logica di matching tra scioperi e avvisi, condivisa tra l'endpoint
GET /scioperi, POST /avvisi, e il servizio di notifiche push
(notifiche_push.py) -- prima viveva solo dentro main.py, ora e' qui per
evitare import circolari tra main.py e notifiche_push.py.
"""
from datetime import date
from typing import List, Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session

from models import Sciopero
from regioni_province import REGIONE_NAZIONALE, PROVINCIA_TUTTE


def query_scioperi(
    db: Session,
    da: date,
    a: date,
    settori: Optional[List[str]] = None,
    regione: Optional[str] = None,
    provincia: Optional[str] = None,
):
    q = db.query(Sciopero).filter(
        Sciopero.inizio_data <= a,
        Sciopero.fine_data >= da,
    )

    if settori and "Tutti" not in settori:
        q = q.filter(Sciopero.settore.in_(settori))

    if regione:
        q = q.filter(
            or_(Sciopero.regione == regione, Sciopero.regione == REGIONE_NAZIONALE)
        )

    if provincia:
        q = q.filter(
            or_(Sciopero.provincia == provincia, Sciopero.provincia == PROVINCIA_TUTTE)
        )

    return q.order_by(Sciopero.inizio_data.asc()).all()
