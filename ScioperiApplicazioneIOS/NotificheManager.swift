import Foundation
import SwiftUI
import Combine

/// Tiene traccia di quali "match" (scioperi che corrispondono a un avviso
/// attivo) l'utente ha gia' visto, per calcolare il badge sulla tab
/// "I miei avvisi" -- senza bisogno di push notifications.
///
/// Logica: ad ogni controllo, confrontiamo gli ID degli scioperi trovati
/// con l'insieme di ID gia' "visti" salvato in UserDefaults. La differenza
/// e' il numero mostrato sul badge. Quando l'utente lascia la tab avvisi,
/// tutto il corrente viene marcato come visto.
@MainActor
final class NotificheManager: ObservableObject {
    static let shared = NotificheManager()

    @Published private(set) var nuoviMatchCount: Int = 0
    @Published private(set) var risultatiCorrenti: [AvvisoConMatch] = []

    private let chiaveVisti = "scioperi.idScioperiVisti"

    private var idVisti: Set<Int> {
        get {
            let array = UserDefaults.standard.array(forKey: chiaveVisti) as? [Int] ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: chiaveVisti)
        }
    }

    private init() {}

    /// Chiamare quando l'app diventa attiva/in foreground.
    func controllaNuoviMatch() async {
        do {
            let risultati = try await APIService.shared.fetchAvvisiConNuoviMatch()
            risultatiCorrenti = risultati

            let idCorrenti = Set(risultati.flatMap { $0.scioperiCorrispondenti.map(\.id) })
            nuoviMatchCount = idCorrenti.subtracting(idVisti).count
        } catch {
            // Silenzioso: e' un controllo in background, non vogliamo
            // interrompere l'utente per un errore di rete qui.
        }
    }

    /// Chiamare quando l'utente ha effettivamente visto la lista avvisi
    /// (es. quando lascia quella tab), cosi' il badge si azzera.
    func segnaComeVisti() {
        let idCorrenti = Set(risultatiCorrenti.flatMap { $0.scioperiCorrispondenti.map(\.id) })
        idVisti = idVisti.union(idCorrenti)
        nuoviMatchCount = 0
    }

    /// Numero di match correnti (nuovi o gia' visti) per un dato avviso,
    /// usato per mostrare "3 scioperi trovati" accanto a un avviso in lista.
    func matchCount(perAvvisoId avvisoId: Int) -> Int {
        risultatiCorrenti.first { $0.avviso.id == avvisoId }?.scioperiCorrispondenti.count ?? 0
    }
}
