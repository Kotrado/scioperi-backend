"""
Client per l'invio di notifiche push Android tramite Firebase Cloud
Messaging, usando il pacchetto ufficiale firebase-admin (HTTP v1 API --
l'unica supportata da Google, la vecchia "server key" e' stata dismessa).

Le credenziali del service account Firebase vanno impostate su Render come
variabile d'ambiente FCM_CREDENTIALS_JSON, contenente l'INTERO contenuto
del file JSON scaricato da:
  Firebase Console -> Impostazioni progetto -> Account di servizio ->
  Genera nuova chiave privata
(stesso pattern gia' usato per APNS_AUTH_KEY con il file .p8 di Apple).

Se la variabile non e' impostata, invia_push_fcm() non fa nulla e
restituisce False silenziosamente -- il backend continua a funzionare
normalmente (utile finche' Firebase non e' ancora configurato).
"""
import json
import os
from typing import Optional

import firebase_admin
from firebase_admin import credentials, messaging

_app: Optional[firebase_admin.App] = None
_inizializzazione_tentata = False


def _get_app() -> Optional[firebase_admin.App]:
    global _app, _inizializzazione_tentata

    if _app is not None:
        return _app
    if _inizializzazione_tentata:
        # Gia' provato e fallito (o variabile assente) in questo processo:
        # non ritentare ad ogni chiamata, solo silenzio.
        return None
    _inizializzazione_tentata = True

    credenziali_json = os.environ.get("FCM_CREDENTIALS_JSON")
    if not credenziali_json:
        return None

    try:
        info = json.loads(credenziali_json)
        cred = credentials.Certificate(info)
        _app = firebase_admin.initialize_app(cred, name="scioperi-fcm")
        return _app
    except Exception as e:
        print(f"[FCM] Errore inizializzazione: {e}")
        return None


def invia_push_fcm(token: str, titolo: str, corpo: str, dati: dict) -> bool:
    """Invia una notifica push Android. Restituisce True se accettata da
    Firebase, False se le credenziali non sono configurate o l'invio e'
    fallito (es. token scaduto/disinstallato -- non e' un errore fatale)."""
    app = _get_app()
    if app is None:
        return False

    # FCM richiede che i valori del payload "data" siano tutte stringhe.
    dati_str = {k: str(v) for k, v in dati.items()}

    message = messaging.Message(
        notification=messaging.Notification(title=titolo, body=corpo),
        data=dati_str,
        token=token,
    )

    try:
        messaging.send(message, app=app)
        return True
    except Exception as e:
        print(f"[FCM] Invio fallito per token {token[:12]}...: {e}")
        return False
