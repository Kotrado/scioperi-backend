import os

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import Base

# In locale, se non imposti DATABASE_URL, usa SQLite (comodo per sviluppo/test).
# Su Render, imposta DATABASE_URL con la connection string del Postgres.
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./scioperi.db")

# Render (come Heroku) fornisce a volte l'URL con schema "postgres://", ma
# SQLAlchemy 2.x richiede "postgresql://" -- correggiamo automaticamente.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

# Log diagnostico (senza esporre la password) -- visibile nei log di avvio
# di Render, per verificare sempre a colpo d'occhio quale DB e' in uso.
_destinazione = DATABASE_URL.split("@")[-1] if "@" in DATABASE_URL else DATABASE_URL
print(f"[DB] Connesso a: {_destinazione}")

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
