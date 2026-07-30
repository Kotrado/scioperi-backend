"""
Confronta gli avvisi attivi con gli scioperi correnti e invia una notifica
push per ogni nuovo match non ancora notificato in precedenza. Chiamato
dall'endpoint POST /admin/refresh subito dopo l'import dei dati (vedi
main.py), quindi gira automaticamente ogni volta che GitHub Actions
scatena il refresh (ogni 4 ore).

La tabella NotificaInviata tiene traccia di cosa e' gia' stato notificato
per evitare di rimandare la stessa notifica ad ogni refresh successivo.
"""
from sqlalchemy.orm import Session

from apns_client import invia_push
from matching import query_scioperi
from models import Avviso, DeviceToken, NotificaInviata


def notifica_nuovi_match(db: Session) -> dict:
    avvisi_attivi = db.query(Avviso).filter(Avviso.attivo == True).all()  # noqa: E712

    notifiche_inviate = 0
    notifiche_fallite = 0
    nessun_token = 0

    for avviso in avvisi_attivi:
        match = query_scioperi(
            db, avviso.data_inizio, avviso.data_fine,
            avviso.settori, avviso.regione, avviso.provincia,
        )

        for sciopero in match:
            gia_notificato = (
                db.query(NotificaInviata)
                .filter_by(avviso_id=avviso.id, sciopero_id=sciopero.id)
                .first()
            )
            if gia_notificato:
                continue

            tokens = db.query(DeviceToken).filter_by(utente_id=avviso.utente_id).all()

            if not tokens:
                nessun_token += 1
            else:
                titolo = f"Sciopero {sciopero.settore}"
                corpo_categoria = sciopero.categoria or sciopero.settore
                corpo = f"{sciopero.inizio_data.strftime('%d/%m')}: {corpo_categoria}"

                almeno_uno_riuscito = False
                for dt in tokens:
                    inviata = invia_push(
                        dt.token, titolo, corpo,
                        {"sciopero_id": sciopero.id, "avviso_id": avviso.id},
                    )
                    almeno_uno_riuscito = almeno_uno_riuscito or inviata

                if almeno_uno_riuscito:
                    notifiche_inviate += 1
                else:
                    notifiche_fallite += 1

            # Segniamo il match come "notificato" anche se non c'erano
            # token registrati (utente che non ha ancora dato il permesso
            # notifiche): evita di ritentare all'infinito lo stesso match.
            db.add(NotificaInviata(avviso_id=avviso.id, sciopero_id=sciopero.id))

    db.commit()

    return {
        "notifiche_inviate": notifiche_inviate,
        "notifiche_fallite": notifiche_fallite,
        "match_senza_token": nessun_token,
    }
