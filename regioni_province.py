"""
Elenco statico di regioni e province italiane.

Usato per:
- popolare i dropdown lato app (evita chiamate API solo per questo)
- validare/normalizzare l'input prima di salvare un avviso
- fare da "dizionario" per riconciliare eventuali discrepanze di nome
  tra il form utente e i valori che arrivano dal sito MIT (es. "Tutte")

NB: i nomi qui sono quelli ufficiali; il campo "provincia" nei dati MIT
usa in genere il nome del capoluogo (es. "Milano", non "Città Metropolitana
di Milano") quindi ho tenuto la forma breve per facilitare il match diretto.
"""

REGIONI_PROVINCE = {
    "Abruzzo": ["Chieti", "L'Aquila", "Pescara", "Teramo"],
    "Basilicata": ["Matera", "Potenza"],
    "Calabria": ["Catanzaro", "Cosenza", "Crotone", "Reggio Calabria", "Vibo Valentia"],
    "Campania": ["Avellino", "Benevento", "Caserta", "Napoli", "Salerno"],
    "Emilia-Romagna": [
        "Bologna", "Ferrara", "Forlì-Cesena", "Modena", "Parma",
        "Piacenza", "Ravenna", "Reggio Emilia", "Rimini",
    ],
    "Friuli-Venezia Giulia": ["Gorizia", "Pordenone", "Trieste", "Udine"],
    "Lazio": ["Frosinone", "Latina", "Rieti", "Roma", "Viterbo"],
    "Liguria": ["Genova", "Imperia", "La Spezia", "Savona"],
    "Lombardia": [
        "Bergamo", "Brescia", "Como", "Cremona", "Lecco", "Lodi", "Mantova",
        "Milano", "Monza e della Brianza", "Pavia", "Sondrio", "Varese",
    ],
    "Marche": ["Ancona", "Ascoli Piceno", "Fermo", "Macerata", "Pesaro e Urbino"],
    "Molise": ["Campobasso", "Isernia"],
    "Piemonte": [
        "Alessandria", "Asti", "Biella", "Cuneo", "Novara",
        "Torino", "Verbano-Cusio-Ossola", "Vercelli",
    ],
    "Puglia": ["Bari", "Barletta-Andria-Trani", "Brindisi", "Foggia", "Lecce", "Taranto"],
    "Sardegna": ["Cagliari", "Nuoro", "Oristano", "Sassari", "Sud Sardegna"],
    "Sicilia": [
        "Agrigento", "Caltanissetta", "Catania", "Enna", "Messina",
        "Palermo", "Ragusa", "Siracusa", "Trapani",
    ],
    "Toscana": [
        "Arezzo", "Firenze", "Grosseto", "Livorno", "Lucca",
        "Massa-Carrara", "Pisa", "Pistoia", "Prato", "Siena",
    ],
    "Trentino-Alto Adige": ["Bolzano", "Trento"],
    "Umbria": ["Perugia", "Terni"],
    "Valle d'Aosta": ["Aosta"],
    "Veneto": [
        "Belluno", "Padova", "Rovigo", "Treviso", "Venezia", "Verona", "Vicenza",
    ],
}

# Valori speciali che compaiono nei dati MIT per scioperi che coprono
# l'intero territorio nazionale: vanno sempre inclusi nel match, a
# prescindere dal filtro regione/provincia scelto dall'utente.
REGIONE_NAZIONALE = "Italia"
PROVINCIA_TUTTE = "Tutte"


def elenco_regioni() -> list[str]:
    return sorted(REGIONI_PROVINCE.keys())


def _trova_chiave_regione(regione: str) -> str | None:
    """Trova la chiave regione originale confrontando senza distinzione di
    maiuscole/minuscole, cosi' il match funziona anche se l'app manda
    'lombardia' invece di 'Lombardia'."""
    regione_norm = regione.strip().lower()
    for chiave in REGIONI_PROVINCE:
        if chiave.lower() == regione_norm:
            return chiave
    return None


def elenco_province(regione: str) -> list[str]:
    chiave = _trova_chiave_regione(regione)
    if chiave is None:
        return []
    return sorted(REGIONI_PROVINCE[chiave])
