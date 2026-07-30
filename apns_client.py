"""
Client minimale per Apple Push Notification service (APNs), basato
sull'API HTTP/2 "token-based" di Apple: le richieste vengono autenticate
con un JWT firmato usando la chiave privata .p8 (niente certificati da
rinnovare ogni anno, a differenza del vecchio sistema a certificato).

Variabili d'ambiente richieste (da impostare su Render quando la chiave
APNs sara' pronta -- finche' mancano, invia_push() ritorna sempre False
senza generare errori, cosi' il resto del sistema funziona comunque):

    APNS_KEY_ID       Key ID della chiave .p8 (pagina della chiave su
                       Apple Developer)
    APNS_TEAM_ID      Team ID del tuo account Apple Developer
    APNS_AUTH_KEY     Contenuto testuale del file .p8, incluse le righe
                       -----BEGIN PRIVATE KEY----- / -----END...-----
    APNS_BUNDLE_ID    Bundle identifier dell'app iOS (es. com.aportsolutions.scioperi)
    APNS_USE_SANDBOX  "true" per build di sviluppo/TestFlight (default),
                       "false" per l'app pubblicata sull'App Store
"""
import os
import time
from typing import Optional

import httpx
import jwt

_APNS_HOST_PROD = "https://api.push.apple.com"
_APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com"

_token_cache = {"value": None, "generato_il": 0.0}


def apns_configurato() -> bool:
    """True se tutte le variabili d'ambiente necessarie sono presenti."""
    return all([
        os.environ.get("APNS_KEY_ID"),
        os.environ.get("APNS_TEAM_ID"),
        os.environ.get("APNS_AUTH_KEY"),
        os.environ.get("APNS_BUNDLE_ID"),
    ])


def _genera_provider_token() -> str:
    """Genera (o riusa dalla cache, valido circa 55 minuti) il JWT
    richiesto da APNs per autenticare le richieste."""
    ora = time.time()
    if _token_cache["value"] and (ora - _token_cache["generato_il"]) < 60 * 55:
        return _token_cache["value"]

    key_id = os.environ["APNS_KEY_ID"]
    team_id = os.environ["APNS_TEAM_ID"]
    # Su Render le variabili d'ambiente multi-riga a volte arrivano con gli
    # "a capo" scappati come \n letterali invece che veri newline: li
    # normalizziamo per sicurezza.
    auth_key = os.environ["APNS_AUTH_KEY"].replace("\\n", "\n")

    token = jwt.encode(
        {"iss": team_id, "iat": int(ora)},
        auth_key,
        algorithm="ES256",
        headers={"kid": key_id},
    )
    _token_cache["value"] = token
    _token_cache["generato_il"] = ora
    return token


def invia_push(
    device_token: str,
    titolo: str,
    corpo: str,
    dati_extra: Optional[dict] = None,
) -> bool:
    """Invia una notifica push a un singolo device token.

    Ritorna True se APNs ha accettato la richiesta, False in ogni altro
    caso (APNs non ancora configurato, device token non valido/scaduto,
    errore di rete). Non solleva mai eccezioni: un fallimento di invio
    non deve mai far fallire l'intero processo di refresh dei dati.
    """
    if not apns_configurato():
        return False

    sandbox = os.environ.get("APNS_USE_SANDBOX", "true").lower() == "true"
    host = _APNS_HOST_SANDBOX if sandbox else _APNS_HOST_PROD
    bundle_id = os.environ["APNS_BUNDLE_ID"]

    payload = {
        "aps": {
            "alert": {"title": titolo, "body": corpo},
            "sound": "default",
        }
    }
    if dati_extra:
        payload.update(dati_extra)

    headers = {
        "authorization": f"bearer {_genera_provider_token()}",
        "apns-topic": bundle_id,
        "apns-push-type": "alert",
    }

    try:
        with httpx.Client(http2=True, timeout=10) as client:
            resp = client.post(
                f"{host}/3/device/{device_token}", json=payload, headers=headers
            )
        return resp.status_code == 200
    except Exception:
        return False
