from datetime import datetime

from sqlalchemy import (
    Column, Integer, String, Date, DateTime, Boolean, Text, JSON, UniqueConstraint, ForeignKey
)

from sqlalchemy.orm import declarative_base

Base = declarative_base()


class Sciopero(Base):
    __tablename__ = "scioperi"

    id = Column(Integer, primary_key=True, autoincrement=True)
    fonte = Column(String, nullable=False, default="mit")
    fonte_id = Column(String, nullable=True)

    inizio_data = Column(Date, nullable=False)
    fine_data = Column(Date, nullable=False)
    ora_inizio = Column(String, nullable=True)   # "HH:MM", None se non_strutturata
    ora_fine = Column(String, nullable=True)
    inizio_datetime = Column(DateTime, nullable=True)
    fine_datetime = Column(DateTime, nullable=True)
    fascia_oraria = Column(String, nullable=False, default="non_strutturata")

    settore = Column(String, nullable=False, index=True)
    categoria = Column(Text, nullable=True)
    modalita_originale = Column(Text, nullable=True)
    sindacati = Column(Text, nullable=True)
    rilevanza = Column(String, nullable=True)

    regione = Column(String, nullable=True, index=True)
    provincia = Column(String, nullable=True, index=True)
    note = Column(Text, nullable=True)

    data_proclamazione = Column(Date, nullable=True)
    data_ricezione = Column(DateTime, nullable=True)

    creato_il = Column(DateTime, default=datetime.utcnow)
    aggiornato_il = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint(
            "fonte", "inizio_data", "categoria", "modalita_originale", "sindacati",
            name="uq_sciopero_naturale",
        ),
    )


class Avviso(Base):
    __tablename__ = "avvisi"

    id = Column(Integer, primary_key=True, autoincrement=True)
    utente_id = Column(String, nullable=False, index=True)

    data_inizio = Column(Date, nullable=False)
    data_fine = Column(Date, nullable=False)

    # Salvato come JSON: es. ["Aereo", "Ferroviario"] oppure ["Tutti"]
    settori = Column(JSON, nullable=False)

    regione = Column(String, nullable=True)      # None = nessun filtro di zona
    provincia = Column(String, nullable=True)     # None = tutta la regione

    attivo = Column(Boolean, default=True)
    creato_il = Column(DateTime, default=datetime.utcnow)

class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    utente_id = Column(String, nullable=False, index=True)
    token = Column(String, nullable=False, unique=True)
    # "ios" o "android" -- decide quale servizio push usare (APNs o FCM).
    # Default "ios" per compatibilita' con i token gia' salvati prima di
    # questo campo (tutti erano iOS, dato che l'app Android non esisteva).
    platform = Column(String, nullable=False, default="ios")
    creato_il = Column(DateTime, default=datetime.utcnow)


class NotificaInviata(Base):
    __tablename__ = "notifiche_inviate"

    id = Column(Integer, primary_key=True, autoincrement=True)
    avviso_id = Column(Integer, ForeignKey("avvisi.id"), nullable=False)
    sciopero_id = Column(Integer, ForeignKey("scioperi.id"), nullable=False)
    inviata_il = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("avviso_id", "sciopero_id", name="uq_notifica_avviso_sciopero"),
    )


class RefreshState(Base):
    __tablename__ = "refresh_state"

    # Una sola riga (id=1): ultimo refresh completato con successo (UTC).
    id = Column(Integer, primary_key=True)
    last_success_at = Column(DateTime, nullable=True)
