"""
API per l'app Scioperi.

Avvio in locale:
    uvicorn main:app --reload

Documentazione interattiva auto-generata:
    http://127.0.0.1:8000/docs
"""

from datetime import date, datetime
import logging
import os
from typing import List, Optional

import requests
from fastapi import FastAPI, Depends, HTTPException, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_

from database import get_db, init_db
from models import Sciopero, Avviso, DeviceToken, NotificaInviata, RefreshState
from regioni_province import (
    elenco_regioni, elenco_province, REGIONE_NAZIONALE, PROVINCIA_TUTTE,
)
from fetch_scioperi import fetch_html, parse_scioperi
from import_scioperi import importa_records
from matching import query_scioperi
from notifiche_push import notifica_nuovi_match

app = FastAPI(title="Scioperi API", version="0.1")


@app.on_event("startup")
def _startup():
    init_db()


# --------------------------------------------------------------------------
# Schemi Pydantic (request/response)
# --------------------------------------------------------------------------

class ScioperoOut(BaseModel):
    id: int
    inizio_data: date
    fine_data: date
    ora_inizio: Optional[str]
    ora_fine: Optional[str]
    fascia_oraria: str
    settore: str
    categoria: Optional[str]
    modalita_originale: Optional[str]
    sindacati: Optional[str]
    rilevanza: Optional[str]
    regione: Optional[str]
    provincia: Optional[str]
    note: Optional[str]

    class Config:
        from_attributes = True


class AvvisoIn(BaseModel):
    utente_id: str
    data_inizio: date
    data_fine: date
    settori: List[str] = Field(..., min_items=1, description="es. ['Aereo'] oppure ['Tutti']")
    regione: Optional[str] = None
    provincia: Optional[str] = None


class AvvisoOut(BaseModel):
    id: int
    utente_id: str
    data_inizio: date
    data_fine: date
    settori: List[str]
    regione: Optional[str]
    provincia: Optional[str]
    attivo: bool

    class Config:
        from_attributes = True


class AvvisoConMatch(BaseModel):
    avviso: AvvisoOut
    scioperi_corrispondenti: List[ScioperoOut]


class DeviceTokenIn(BaseModel):
    utente_id: str
    token: str
    # "ios" o "android". Default "ios" per compatibilita' con eventuali
    # client vecchi (l'app iOS gia' pubblicata) che non mandano ancora
    # questo campo esplicitamente.
    platform: str = "ios"


class RefreshResult(BaseModel):
    scioperi_trovati: int
    nuovi: int
    aggiornati: int
    notifiche_inviate: int
    notifiche_fallite: int
    match_senza_token: int


# --------------------------------------------------------------------------
# Endpoint: dropdown regioni/province (dati statici, per il form dell'app)
# --------------------------------------------------------------------------

@app.get("/")
def health_check():
    return {"status": "ok", "service": "scioperi-api"}


@app.get("/regioni", response_model=List[str])
def get_regioni():
    return elenco_regioni()


@app.get("/regioni/{regione}/province", response_model=List[str])
def get_province(regione: str):
    province = elenco_province(regione)
    if not province:
        raise HTTPException(status_code=404, detail=f"Regione '{regione}' non trovata")
    return province


# --------------------------------------------------------------------------
# Endpoint: calendario scioperi
# --------------------------------------------------------------------------

@app.get("/scioperi", response_model=List[ScioperoOut])
def get_scioperi(
    da: date,
    a: date,
    settore: Optional[str] = None,  # comma-separated, es. "Aereo,Ferroviario"
    regione: Optional[str] = None,
    provincia: Optional[str] = None,
    db: Session = Depends(get_db),
):
    if a < da:
        raise HTTPException(status_code=400, detail="'a' deve essere >= 'da'")

    settori = [s.strip() for s in settore.split(",")] if settore else None
    return query_scioperi(db, da, a, settori, regione, provincia)


# --------------------------------------------------------------------------
# Endpoint: avvisi (creazione, lista, cancellazione)
# --------------------------------------------------------------------------

@app.post("/avvisi", response_model=AvvisoConMatch)
def crea_avviso(payload: AvvisoIn, db: Session = Depends(get_db)):
    if payload.data_fine < payload.data_inizio:
        raise HTTPException(status_code=400, detail="data_fine deve essere >= data_inizio")

    avviso = Avviso(
        utente_id=payload.utente_id,
        data_inizio=payload.data_inizio,
        data_fine=payload.data_fine,
        settori=payload.settori,
        regione=payload.regione,
        provincia=payload.provincia,
    )
    db.add(avviso)
    db.commit()
    db.refresh(avviso)

    match = query_scioperi(
        db, payload.data_inizio, payload.data_fine,
        payload.settori, payload.regione, payload.provincia,
    )

    return AvvisoConMatch(avviso=avviso, scioperi_corrispondenti=match)


@app.get("/avvisi/{utente_id}", response_model=List[AvvisoOut])
def lista_avvisi(utente_id: str, db: Session = Depends(get_db)):
    return (
        db.query(Avviso)
        .filter(Avviso.utente_id == utente_id, Avviso.attivo == True)  # noqa: E712
        .order_by(Avviso.data_inizio.asc())
        .all()
    )


@app.put("/avvisi/{avviso_id}", response_model=AvvisoConMatch)
def aggiorna_avviso(avviso_id: int, payload: AvvisoIn, db: Session = Depends(get_db)):
    if payload.data_fine < payload.data_inizio:
        raise HTTPException(status_code=400, detail="data_fine deve essere >= data_inizio")

    avviso = db.query(Avviso).filter(Avviso.id == avviso_id).first()
    if not avviso:
        raise HTTPException(status_code=404, detail="Avviso non trovato")
    if avviso.utente_id != payload.utente_id:
        raise HTTPException(status_code=403, detail="Avviso non appartenente a questo utente")

    avviso.data_inizio = payload.data_inizio
    avviso.data_fine = payload.data_fine
    avviso.settori = payload.settori
    avviso.regione = payload.regione
    avviso.provincia = payload.provincia
    db.commit()
    db.refresh(avviso)

    match = query_scioperi(
        db, avviso.data_inizio, avviso.data_fine,
        avviso.settori, avviso.regione, avviso.provincia,
    )
    return AvvisoConMatch(avviso=avviso, scioperi_corrispondenti=match)


@app.delete("/avvisi/{avviso_id}")
def elimina_avviso(avviso_id: int, db: Session = Depends(get_db)):
    avviso = db.query(Avviso).filter(Avviso.id == avviso_id).first()
    if not avviso:
        raise HTTPException(status_code=404, detail="Avviso non trovato")

    # Rimuovi prima le eventuali notifiche gia' inviate collegate a questo
    # avviso -- altrimenti il vincolo di chiave esterna su NotificaInviata
    # blocca la cancellazione con un errore 500.
    db.query(NotificaInviata).filter(NotificaInviata.avviso_id == avviso_id).delete()

    db.delete(avviso)
    db.commit()
    return {"ok": True}


# --------------------------------------------------------------------------
# Endpoint di supporto: ricontrolla tutti gli avvisi attivi contro i dati
# correnti (usato dall'app per il badge in-app).
# --------------------------------------------------------------------------

@app.get("/avvisi-con-nuovi-match", response_model=List[AvvisoConMatch])
def avvisi_con_nuovi_match(utente_id: str, db: Session = Depends(get_db)):
    risultati = []
    avvisi_attivi = (
        db.query(Avviso)
        .filter(Avviso.attivo == True, Avviso.utente_id == utente_id)  # noqa: E712
        .all()
    )

    for avviso in avvisi_attivi:
        match = query_scioperi(
            db, avviso.data_inizio, avviso.data_fine,
            avviso.settori, avviso.regione, avviso.provincia,
        )
        if match:
            risultati.append(AvvisoConMatch(avviso=avviso, scioperi_corrispondenti=match))

    return risultati


# --------------------------------------------------------------------------
# Endpoint: registrazione device token per le notifiche push
# --------------------------------------------------------------------------

@app.post("/device-token")
def registra_device_token(payload: DeviceTokenIn, db: Session = Depends(get_db)):
    esistente = db.query(DeviceToken).filter_by(token=payload.token).first()
    if esistente:
        esistente.utente_id = payload.utente_id
        esistente.platform = payload.platform
    else:
        db.add(DeviceToken(
            utente_id=payload.utente_id,
            token=payload.token,
            platform=payload.platform,
        ))
    db.commit()
    return {"ok": True}


# --------------------------------------------------------------------------
# Endpoint di refresh: fa scraping del sito MIT + import nel DB + invio
# delle notifiche push per i nuovi match, tutto nel processo del backend
# gia' deployato. Protetto da un token segreto passato come header, da
# chiamare periodicamente da uno scheduler esterno gratuito (GitHub
# Actions con un workflow schedulato).
# --------------------------------------------------------------------------

logger = logging.getLogger(__name__)


def _verifica_admin(x_admin_token: Optional[str]):
    token_atteso = os.environ.get("ADMIN_TOKEN")
    if not token_atteso:
        raise HTTPException(
            status_code=500,
            detail="ADMIN_TOKEN non configurato lato server -- imposta la variabile "
                   "d'ambiente su Render prima di usare questo endpoint.",
        )
    if x_admin_token != token_atteso:
        raise HTTPException(status_code=401, detail="Token non valido")


@app.post("/admin/refresh", response_model=RefreshResult)
def refresh_scioperi(
    x_admin_token: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    _verifica_admin(x_admin_token)

    try:
        html = fetch_html()
    except requests.RequestException as e:
        logger.warning("Portale MIT non raggiungibile: %s", e)
        return JSONResponse(status_code=502, content={"detail": "MIT portal unreachable"})
    records = parse_scioperi(html)
    nuovi, aggiornati = importa_records(db, records)

    risultato_notifiche = notifica_nuovi_match(db)

    # Solo a run completato (fetch, parse, import e notifiche).
    stato = db.get(RefreshState, 1)
    if stato is None:
        stato = RefreshState(id=1)
        db.add(stato)
    stato.last_success_at = datetime.utcnow()
    db.commit()

    return RefreshResult(
        scioperi_trovati=len(records),
        nuovi=nuovi,
        aggiornati=aggiornati,
        **risultato_notifiche,
    )


@app.get("/admin/status")
def admin_status(
    x_admin_token: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    _verifica_admin(x_admin_token)

    stato = db.get(RefreshState, 1)
    last = stato.last_success_at if stato else None
    if last is None:
        return {"last_success_at": None, "age_hours": None}
    age_hours = (datetime.utcnow() - last).total_seconds() / 3600
    return {"last_success_at": last.isoformat() + "Z", "age_hours": age_hours}
