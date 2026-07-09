import Foundation

/// Rispecchia lo schema `ScioperoOut` del backend FastAPI.
/// I nomi dei campi devono combaciare con le chiavi JSON restituite dall'API
/// (uso CodingKeys esplicite per chiarezza, anche se qui coincidono).
struct Sciopero: Identifiable, Codable, Hashable {
    let id: Int
    let inizioData: String       // formato "yyyy-MM-dd", vedi `inizioDate` sotto
    let fineData: String
    let oraInizio: String?
    let oraFine: String?
    let fasciaOraria: String     // "esplicita" | "turni_spezzati" | "giornata_intera_assunta" | "non_strutturata"
    let settore: String
    let categoria: String?
    let modalitaOriginale: String?
    let sindacati: String?
    let rilevanza: String?
    let regione: String?
    let provincia: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case inizioData = "inizio_data"
        case fineData = "fine_data"
        case oraInizio = "ora_inizio"
        case oraFine = "ora_fine"
        case fasciaOraria = "fascia_oraria"
        case settore
        case categoria
        case modalitaOriginale = "modalita_originale"
        case sindacati
        case rilevanza
        case regione
        case provincia
        case note
    }

    /// Converte "yyyy-MM-dd" in Date, per usarlo con calendario/confronti.
    var inizioDate: Date? {
        Self.dateFormatter.date(from: inizioData)
    }

    var fineDate: Date? {
        Self.dateFormatter.date(from: fineData)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return f
    }()

    /// Etichetta leggibile per la fascia oraria, da mostrare nell'UI.
    var fasciaOrariaLabel: String {
        switch fasciaOraria {
        case "esplicita":
            if let oi = oraInizio, let of = oraFine {
                return "\(oi) - \(of)"
            }
            return "Orario definito"
        case "turni_spezzati":
            return "Turni spezzati (vedi dettagli)"
        case "giornata_intera_assunta":
            return "Tutta la giornata"
        default:
            return "Orario non specificato"
        }
    }
}

/// Elenco dei settori cosi' come li restituisce il backend (utile per i filtri).
enum Settore: String, CaseIterable, Identifiable {
    case aereo = "Aereo"
    case ferroviario = "Ferroviario"
    case tpl = "Trasporto pubblico locale"
    case marittimo = "Marittimo"
    case trasportoMerci = "Trasporto merci"
    case appaltiFerroviari = "Appalti ferroviari"
    case elicotteri = "Elicotteri"
    case taxi = "Taxi"
    case ncc = "Ncc"
    case circolazioneStradale = "Circolazione e sicurezza stradale"
    case generale = "Generale"
    case intersettoriale = "Intersettoriale"

    var id: String { rawValue }

    /// Nome breve per chip/filtri compatti in UI.
    var etichettaBreve: String {
        switch self {
        case .tpl: return "TPL"
        case .circolazioneStradale: return "Circolazione"
        default: return rawValue
        }
    }
}
