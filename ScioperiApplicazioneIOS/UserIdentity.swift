import Foundation

/// Identificatore anonimo e persistente per il device, usato come `utente_id`
/// verso il backend. Non c'e' un vero login nell'MVP: generiamo un UUID al
/// primo avvio e lo riusiamo sempre, salvato in UserDefaults.
enum UserIdentity {
    private static let chiave = "scioperi.utenteId"

    static var utenteId: String {
        if let esistente = UserDefaults.standard.string(forKey: chiave) {
            return esistente
        }
        let nuovo = UUID().uuidString
        UserDefaults.standard.set(nuovo, forKey: chiave)
        return nuovo
    }
}
