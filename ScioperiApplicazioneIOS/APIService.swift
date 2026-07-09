import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido."
        case .serverError(let code):
            return "Errore dal server (codice \(code))."
        case .decodingError:
            return "Risposta del server in un formato inatteso."
        case .networkError(let err):
            return "Errore di connessione: \(err.localizedDescription)"
        }
    }
}

/// Client per il backend Scioperi (FastAPI su Render).
///
/// NB: sostituisci `baseURL` con l'URL reale del tuo Web Service Render.
final class APIService {
    static let shared = APIService()

    private let baseURL = URL(string: "https://scioperi-backend.onrender.com")!
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        // Il piano free di Render puo' avere un cold start di 30-60s se il
        // servizio "dormiva" -- un timeout troppo corto darebbe errore anche
        // quando in realta' basterebbe aspettare un po' di piu'.
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// GET /scioperi -- calendario filtrato.
    func fetchScioperi(
        da: Date,
        a: Date,
        settori: [Settore]? = nil,
        regione: String? = nil,
        provincia: String? = nil
    ) async throws -> [Sciopero] {
        var components = URLComponents(url: baseURL.appendingPathComponent("scioperi"), resolvingAgainstBaseURL: false)!

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var queryItems = [
            URLQueryItem(name: "da", value: df.string(from: da)),
            URLQueryItem(name: "a", value: df.string(from: a)),
        ]

        if let settori, !settori.isEmpty {
            queryItems.append(URLQueryItem(name: "settore", value: settori.map(\.rawValue).joined(separator: ",")))
        }
        if let regione {
            queryItems.append(URLQueryItem(name: "regione", value: regione))
        }
        if let provincia {
            queryItems.append(URLQueryItem(name: "provincia", value: provincia))
        }

        components.queryItems = queryItems

        guard let url = components.url else { throw APIError.invalidURL }

        return try await performRequest(url: url)
    }

    /// GET /regioni -- per i dropdown.
    func fetchRegioni() async throws -> [String] {
        let url = baseURL.appendingPathComponent("regioni")
        return try await performRequest(url: url)
    }

    /// GET /regioni/{regione}/province -- per i dropdown a cascata.
    func fetchProvince(regione: String) async throws -> [String] {
        guard let encoded = regione.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }
        let url = baseURL.appendingPathComponent("regioni").appendingPathComponent(encoded).appendingPathComponent("province")
        return try await performRequest(url: url)
    }

    /// POST /avvisi -- crea un avviso, ritorna l'avviso salvato + i match immediati.
    func creaAvviso(_ avviso: AvvisoIn) async throws -> AvvisoConMatch {
        var request = URLRequest(url: baseURL.appendingPathComponent("avvisi"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(avviso)
        return try await performRequest(request: request)
    }

    /// GET /avvisi/{utente_id} -- lista avvisi salvati per questo device.
    func fetchAvvisi(utenteId: String) async throws -> [AvvisoOut] {
        let url = baseURL.appendingPathComponent("avvisi").appendingPathComponent(utenteId)
        return try await performRequest(url: url)
    }

    /// DELETE /avvisi/{id}
    func eliminaAvviso(id: Int) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("avvisi").appendingPathComponent("\(id)"))
        request.httpMethod = "DELETE"
        let _: OkResponse = try await performRequest(request: request)
    }

    /// GET /avvisi-con-nuovi-match -- tutti gli avvisi attivi che hanno
    /// almeno uno sciopero corrispondente al momento. Usato per il badge
    /// locale (nessuna push, solo controllo quando l'app e' in foreground).
    func fetchAvvisiConNuoviMatch() async throws -> [AvvisoConMatch] {
        let url = baseURL.appendingPathComponent("avvisi-con-nuovi-match")
        return try await performRequest(url: url)
    }

    // MARK: - Helper generico

    private func performRequest<T: Decodable>(url: URL) async throws -> T {
        try await performRequest(request: URLRequest(url: url))
    }

    private func performRequest<T: Decodable>(request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}
