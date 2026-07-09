import SwiftUI

struct ScioperiListView: View {
    @State private var scioperi: [Sciopero] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filtri = FiltriState()
    @State private var mostraFiltri = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !filtri.isEmpty {
                    RiepilogoFiltriBar(filtri: filtri) {
                        filtri = FiltriState()
                        loadScioperi()
                    }
                }

                Group {
                    if isLoading {
                        ProgressView("Caricamento scioperi...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        ContentUnavailableErrorView(message: errorMessage, retry: loadScioperi)
                    } else if scioperi.isEmpty {
                        ContentUnavailableView(
                            "Nessuno sciopero",
                            systemImage: "checkmark.circle",
                            description: Text(filtri.isEmpty
                                ? "Nessuno sciopero previsto nei prossimi 30 giorni."
                                : "Nessuno sciopero corrisponde ai filtri selezionati.")
                        )
                    } else {
                        List(groupedByDate.keys.sorted(), id: \.self) { date in
                            Section(header: Text(sectionTitle(for: date))) {
                                ForEach(groupedByDate[date] ?? []) { sciopero in
                                    ScioperoRow(sciopero: sciopero)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Scioperi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostraFiltri = true
                    } label: {
                        Image(systemName: filtri.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $mostraFiltri, onDismiss: loadScioperi) {
                FiltriView(filtri: $filtri)
            }
            .task { await loadScioperiAsync() }
            .refreshable { await loadScioperiAsync() }
        }
    }

    private var groupedByDate: [Date: [Sciopero]] {
        Dictionary(grouping: scioperi) { sciopero in
            let date = sciopero.inizioDate ?? Date()
            return Calendar.current.startOfDay(for: date)
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date).capitalized
    }

    private func loadScioperi() {
        Task { await loadScioperiAsync() }
    }

    @MainActor
    private func loadScioperiAsync() async {
        isLoading = true
        errorMessage = nil

        let oggi = Calendar.current.startOfDay(for: Date())
        let tra30Giorni = Calendar.current.date(byAdding: .day, value: 30, to: oggi) ?? oggi

        do {
            scioperi = try await APIService.shared.fetchScioperi(
                da: oggi,
                a: tra30Giorni,
                settori: filtri.settoriSelezionati.isEmpty ? nil : Array(filtri.settoriSelezionati),
                regione: filtri.regione,
                provincia: filtri.provincia
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

/// Barra compatta che mostra un riassunto dei filtri attivi, con pulsante per azzerarli.
struct RiepilogoFiltriBar: View {
    let filtri: FiltriState
    let onAzzera: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(descrizione)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Azzera", action: onAzzera)
                .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private var descrizione: String {
        var parti: [String] = []
        if !filtri.settoriSelezionati.isEmpty {
            parti.append(filtri.settoriSelezionati.map(\.etichettaBreve).joined(separator: ", "))
        }
        if let provincia = filtri.provincia {
            parti.append(provincia)
        } else if let regione = filtri.regione {
            parti.append(regione)
        }
        return parti.joined(separator: " · ")
    }
}

struct ScioperoRow: View {
    let sciopero: Sciopero

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sciopero.settore)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let rilevanza = sciopero.rilevanza {
                    Text(rilevanza)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if let categoria = sciopero.categoria {
                Text(categoria)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label(sciopero.fasciaOrariaLabel, systemImage: "clock")
                if let provincia = sciopero.provincia, provincia != "Tutte" {
                    Label(provincia, systemImage: "location")
                } else if let regione = sciopero.regione {
                    Label(regione, systemImage: "map")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Vista di errore semplice con pulsante di retry (evito la dipendenza da
/// ContentUnavailableView per gli errori, cosi' posso aggiungere l'azione).
struct ContentUnavailableErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Non riesco a caricare i dati")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Riprova", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ScioperiListView()
}
