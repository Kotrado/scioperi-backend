import SwiftUI

struct AvvisiListView: View {
    @EnvironmentObject private var notifiche: NotificheManager
    @State private var avvisi: [AvvisoOut] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mostraNuovoAvviso = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableErrorView(message: errorMessage) {
                        Task { await load() }
                    }
                } else if avvisi.isEmpty {
                    ContentUnavailableView(
                        "Nessun avviso",
                        systemImage: "bell",
                        description: Text("Crea un avviso per essere notificato di scioperi in un periodo e zona specifici.")
                    )
                } else {
                    List {
                        ForEach(avvisi) { avviso in
                            AvvisoRow(avviso: avviso, matchCount: notifiche.matchCount(perAvvisoId: avviso.id))
                        }
                        .onDelete(perform: elimina)
                    }
                }
            }
            .navigationTitle("I miei avvisi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostraNuovoAvviso = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $mostraNuovoAvviso) {
                NuovoAvvisoView { Task { await load() } }
            }
            .task {
                await load()
                await notifiche.controllaNuoviMatch()
            }
            .refreshable {
                await load()
                await notifiche.controllaNuoviMatch()
            }
            .onDisappear {
                // L'utente ha visto la lista (con gli eventuali conteggi match
                // accanto ad ogni avviso) -- il badge puo' azzerarsi.
                notifiche.segnaComeVisti()
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            avvisi = try await APIService.shared.fetchAvvisi(utenteId: UserIdentity.utenteId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func elimina(at offsets: IndexSet) {
        let daEliminare = offsets.map { avvisi[$0] }
        avvisi.remove(atOffsets: offsets)
        Task {
            for avviso in daEliminare {
                try? await APIService.shared.eliminaAvviso(id: avviso.id)
            }
        }
    }
}

private struct AvvisoRow: View {
    let avviso: AvvisoOut
    let matchCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(periodoLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if matchCount > 0 {
                    Text(matchCount == 1 ? "1 sciopero" : "\(matchCount) scioperi")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            Text(avviso.settori.joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let localita = localitaLabel {
                Label(localita, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var periodoLabel: String {
        guard let inizio = avviso.dataInizioDate, let fine = avviso.dataFineDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "it_IT")
        return "\(f.string(from: inizio)) - \(f.string(from: fine))"
    }

    private var localitaLabel: String? {
        avviso.provincia ?? avviso.regione
    }
}

#Preview {
    AvvisiListView()
        .environmentObject(NotificheManager.shared)
}
