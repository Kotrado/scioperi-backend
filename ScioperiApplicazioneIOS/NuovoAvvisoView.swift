import SwiftUI

struct NuovoAvvisoView: View {
    @Environment(\.dismiss) private var dismiss
    var onSalvato: () -> Void

    @State private var dataInizio = Date()
    @State private var dataFine = Date()
    @State private var settoriSelezionati: Set<Settore> = []
    @State private var regione: String?
    @State private var provincia: String?

    @State private var regioni: [String] = []
    @State private var province: [String] = []
    @State private var isLoadingRegioni = false
    @State private var isLoadingProvince = false

    @State private var isSalvando = false
    @State private var errorMessage: String?
    @State private var risultato: AvvisoConMatch?

    var body: some View {
        NavigationStack {
            Group {
                if let risultato {
                    RisultatoAvvisoView(risultato: risultato) {
                        onSalvato()
                        dismiss()
                    }
                } else {
                    formView
                }
            }
            .navigationTitle("Nuovo avviso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if risultato == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSalvando {
                            ProgressView()
                        } else {
                            Button("Salva") { Task { await salva() } }
                                .fontWeight(.semibold)
                                .disabled(settoriSelezionati.isEmpty)
                        }
                    }
                }
            }
            .task { await loadRegioni() }
        }
    }

    private var formView: some View {
        Form {
            Section("Periodo") {
                DatePicker("Dal", selection: $dataInizio, displayedComponents: .date)
                    .onChange(of: dataInizio) { _, nuovaData in
                        if dataFine < nuovaData { dataFine = nuovaData }
                    }
                DatePicker("Al", selection: $dataFine, in: dataInizio..., displayedComponents: .date)
            }

            Section("Mezzo di trasporto") {
                FlowLayout(spacing: 8) {
                    ForEach(Settore.allCases) { settore in
                        ChipToggle(
                            label: settore.etichettaBreve,
                            isSelected: settoriSelezionati.contains(settore)
                        ) {
                            if settoriSelezionati.contains(settore) {
                                settoriSelezionati.remove(settore)
                            } else {
                                settoriSelezionati.insert(settore)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                if settoriSelezionati.isEmpty {
                    Text("Seleziona almeno un mezzo di trasporto")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Località (opzionale)") {
                if isLoadingRegioni {
                    ProgressView()
                } else {
                    Picker("Regione", selection: regioneBinding) {
                        Text("Tutta Italia").tag(String?.none)
                        ForEach(regioni, id: \.self) { r in
                            Text(r).tag(String?.some(r))
                        }
                    }
                }

                if regione != nil {
                    if isLoadingProvince {
                        ProgressView()
                    } else if !province.isEmpty {
                        Picker("Provincia", selection: $provincia) {
                            Text("Tutta la regione").tag(String?.none)
                            ForEach(province, id: \.self) { p in
                                Text(p).tag(String?.some(p))
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
    }

    // MARK: - Binding che ricarica le province quando cambia la regione

    private var regioneBinding: Binding<String?> {
        Binding(
            get: { regione },
            set: { nuovaRegione in
                regione = nuovaRegione
                provincia = nil
                province = []
                if let nuovaRegione {
                    Task { await loadProvince(regione: nuovaRegione) }
                }
            }
        )
    }

    @MainActor
    private func loadRegioni() async {
        isLoadingRegioni = true
        do {
            regioni = try await APIService.shared.fetchRegioni()
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

    @MainActor
    private func salva() async {
        guard !settoriSelezionati.isEmpty else { return }
        isSalvando = true
        errorMessage = nil

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let payload = AvvisoIn(
            utenteId: UserIdentity.utenteId,
            dataInizio: df.string(from: dataInizio),
            dataFine: df.string(from: dataFine),
            settori: settoriSelezionati.map(\.rawValue),
            regione: regione,
            provincia: provincia
        )

        do {
            risultato = try await APIService.shared.creaAvviso(payload)
        } catch {
            errorMessage = "Impossibile salvare l'avviso: \(error.localizedDescription)"
        }

        isSalvando = false
    }
}

/// Schermata di conferma mostrata subito dopo il salvataggio, con gli
/// eventuali scioperi che gia' corrispondono ai criteri scelti.
private struct RisultatoAvvisoView: View {
    let risultato: AvvisoConMatch
    let onFatto: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Avviso salvato")
                    .font(.headline)
                Text(sottotitolo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()

            if risultato.scioperiCorrispondenti.isEmpty {
                ContentUnavailableView(
                    "Nessun match al momento",
                    systemImage: "checkmark.circle",
                    description: Text("Ti avviseremo se emergono scioperi che corrispondono a questo avviso.")
                )
            } else {
                List(risultato.scioperiCorrispondenti) { sciopero in
                    ScioperoRow(sciopero: sciopero)
                }
            }

            Button("Fatto", action: onFatto)
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    private var sottotitolo: String {
        risultato.scioperiCorrispondenti.isEmpty
            ? "Nessuno sciopero trovato per ora nel periodo scelto."
            : "\(risultato.scioperiCorrispondenti.count) sciopero/i già trovati per il periodo scelto:"
    }
}

#Preview {
    NuovoAvvisoView(onSalvato: {})
}
