import Foundation

/// Rispecchia AvvisoOut del backend.
struct AvvisoOut: Identifiable, Codable {
    let id: Int
    let utenteId: String
    let dataInizio: String
    let dataFine: String
    let settori: [String]
    let regione: String?
    let provincia: String?
    let attivo: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case utenteId = "utente_id"
        case dataInizio = "data_inizio"
        case dataFine = "data_fine"
        case settori, regione, provincia, attivo
    }

    var dataInizioDate: Date? { Self.formatter.date(from: dataInizio) }
    var dataFineDate: Date? { Self.formatter.date(from: dataFine) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return f
    }()
}

/// Rispecchia AvvisoConMatch del backend -- risposta di POST /avvisi.
struct AvvisoConMatch: Codable {
    let avviso: AvvisoOut
    let scioperiCorrispondenti: [Sciopero]

    enum CodingKeys: String, CodingKey {
        case avviso
        case scioperiCorrispondenti = "scioperi_corrispondenti"
    }
}

/// Corpo della richiesta POST /avvisi (rispecchia AvvisoIn del backend).
struct AvvisoIn: Codable {
    let utenteId: String
    let dataInizio: String
    let dataFine: String
    let settori: [String]
    let regione: String?
    let provincia: String?

    enum CodingKeys: String, CodingKey {
        case utenteId = "utente_id"
        case dataInizio = "data_inizio"
        case dataFine = "data_fine"
        case settori, regione, provincia
    }
}

/// Risposta minima per endpoint tipo DELETE /avvisi/{id} -> {"ok": true}.
struct OkResponse: Codable {
    let ok: Bool
}
