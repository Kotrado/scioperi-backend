import SwiftUI

/// Stato dei filtri condiviso tra la lista e la sheet dei filtri.
struct FiltriState: Equatable {
    var settoriSelezionati: Set<Settore> = []
    var regione: String? = nil
    var provincia: String? = nil

    var isEmpty: Bool {
        settoriSelezionati.isEmpty && regione == nil && provincia == nil
    }

    var conteggioAttivi: Int {
        var count = settoriSelezionati.isEmpty ? 0 : 1
        if regione != nil { count += 1 }
        // La provincia conta come raffinamento della regione, non un filtro
        // separato agli occhi dell'utente -- non la sommiamo al badge.
        return count
    }
}

struct FiltriView: View {
    @Binding var filtri: FiltriState
    @Environment(\.dismiss) private var dismiss

    @State private var regioni: [String] = []
    @State private var province: [String] = []
    @State private var isLoadingRegioni = false
    @State private var isLoadingProvince = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Mezzo di trasporto") {
                    // Layout a chip che vanno a capo, invece di una lista Toggle
                    // verticale -- piu' compatto e scansionabile su schermi piccoli.
                    FlowLayout(spacing: 8) {
                        ForEach(Settore.allCases) { settore in
                            ChipToggle(
                                label: settore.etichettaBreve,
                                isSelected: filtri.settoriSelezionati.contains(settore)
                            ) {
                                toggleSettore(settore)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if !filtri.settoriSelezionati.isEmpty {
                        Button("Deseleziona tutti") {
                            filtri.settoriSelezionati.removeAll()
                        }
                        .font(.footnote)
                    }
                }

                Section("Località") {
                    if isLoadingRegioni {
                        ProgressView()
                    } else {
                        Picker("Regione", selection: regioneBinding) {
                            Text("Tutta Italia").tag(String?.none)
                            ForEach(regioni, id: \.self) { regione in
                                Text(regione).tag(String?.some(regione))
                            }
                        }
                    }

                    if filtri.regione != nil {
                        if isLoadingProvince {
                            ProgressView()
                        } else if !province.isEmpty {
                            Picker("Provincia", selection: provinciaBinding) {
                                Text("Tutta la regione").tag(String?.none)
                                ForEach(province, id: \.self) { provincia in
                                    Text(provincia).tag(String?.some(provincia))
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Filtri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") { dismiss() }
                        .fontWeight(.semibold)
                }
                if !filtri.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Azzera tutti i filtri", role: .destructive) {
                            filtri = FiltriState()
                            province = []
                        }
                    }
                }
            }
            .task { await loadRegioni() }
        }
    }

    // MARK: - Bindings che gestiscono anche il reset della provincia quando cambia regione

    private var regioneBinding: Binding<String?> {
        Binding(
            get: { filtri.regione },
            set: { nuovaRegione in
                filtri.regione = nuovaRegione
                filtri.provincia = nil
                province = []
                if let nuovaRegione {
                    Task { await loadProvince(regione: nuovaRegione) }
                }
            }
        )
    }

    private var provinciaBinding: Binding<String?> {
        Binding(get: { filtri.provincia }, set: { filtri.provincia = $0 })
    }

    private func toggleSettore(_ settore: Settore) {
        if filtri.settoriSelezionati.contains(settore) {
            filtri.settoriSelezionati.remove(settore)
        } else {
            filtri.settoriSelezionati.insert(settore)
        }
    }

    @MainActor
    private func loadRegioni() async {
        isLoadingRegioni = true
        errorMessage = nil
        do {
            regioni = try await APIService.shared.fetchRegioni()
            // Se una regione era gia' selezionata (riapertura filtri), ricarica le province.
            if let regioneSelezionata = filtri.regione {
                await loadProvince(regione: regioneSelezionata)
            }
        } catch {
            errorMessage = "Impossibile caricare le regioni: \(error.localizedDescription)"
        }
        isLoadingRegioni = false
    }

    @MainActor
    private func loadProvince(regione: String) async {
        isLoadingProvince = true
        do {
            province = try await APIService.shared.fetchProvince(regione: regione)
        } catch {
            errorMessage = "Impossibile caricare le province: \(error.localizedDescription)"
        }
        isLoadingProvince = false
    }
}

// MARK: - Componenti riutilizzabili

/// Chip selezionabile stile "pillola", usata per il multi-select dei settori.
struct ChipToggle: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Layout semplice "a capo automatico" per le chip, senza dipendenze esterne.
/// Disponibile nativamente solo da iOS 16+ (Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > width, currentRowWidth > 0 {
                totalHeight += currentRowHeight + spacing
                currentRowWidth = 0
                currentRowHeight = 0
            }
            currentRowWidth += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

#Preview {
    FiltriView(filtri: .constant(FiltriState()))
}
