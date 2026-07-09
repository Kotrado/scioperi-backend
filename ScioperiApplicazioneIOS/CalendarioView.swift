import SwiftUI

struct CalendarioView: View {
    @State private var meseVisualizzato: Date
    @State private var scioperiDelMese: [Sciopero] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filtri = FiltriState()
    @State private var mostraFiltri = false
    @State private var giornoSelezionato: GiornoSelezionato?

    private let calendario: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "it_IT")
        cal.firstWeekday = 2 // Lunedi', convenzione italiana
        return cal
    }()

    init() {
        let oggi = Date()
        _meseVisualizzato = State(initialValue: oggi)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !filtri.isEmpty {
                    RiepilogoFiltriBar(filtri: filtri) {
                        filtri = FiltriState()
                        Task { await loadMese() }
                    }
                }

                intestazioneMese
                giorniSettimanaHeader

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        ContentUnavailableErrorView(message: errorMessage) {
                            Task { await loadMese() }
                        }
                    } else {
                        grigliaGiorni
                        Spacer()
                    }
                }
            }
            .navigationTitle("Calendario")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostraFiltri = true
                    } label: {
                        Image(systemName: filtri.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $mostraFiltri, onDismiss: { Task { await loadMese() } }) {
                FiltriView(filtri: $filtri)
            }
            .sheet(item: $giornoSelezionato) { item in
                GiornoDettaglioView(
                    data: item.data,
                    scioperi: scioperiPerGiorno(item.data),
                    calendario: calendario
                )
            }
            .task { await loadMese() }
        }
    }

    // MARK: - Intestazione con navigazione mese

    private var intestazioneMese: some View {
        HStack {
            Button {
                cambiaMese(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(titoloMese)
                    .font(.headline)
                if !calendario.isDate(meseVisualizzato, equalTo: Date(), toGranularity: .month) {
                    Button("Torna a oggi") { vaiAOggi() }
                        .font(.caption)
                }
            }

            Spacer()

            Button {
                cambiaMese(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var titoloMese: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: meseVisualizzato).capitalized
    }

    private func cambiaMese(offset: Int) {
        guard let nuovoMese = calendario.date(byAdding: .month, value: offset, to: meseVisualizzato) else { return }
        meseVisualizzato = nuovoMese
        Task { await loadMese() }
    }

    private func vaiAOggi() {
        meseVisualizzato = Date()
        Task { await loadMese() }
    }

    // MARK: - Header giorni della settimana (Lun, Mar, ...)

    private var simboliGiorniSettimana: [String] {
        let simboli = calendario.shortStandaloneWeekdaySymbols // index 0 = Domenica
        let offset = calendario.firstWeekday - 1
        return Array(simboli[offset...] + simboli[..<offset])
    }

    private var giorniSettimanaHeader: some View {
        HStack {
            ForEach(simboliGiorniSettimana, id: \.self) { simbolo in
                Text(simbolo.uppercased())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Griglia giorni del mese

    /// Genera le celle del mese corrente, con `nil` per il padding prima del
    /// primo giorno e dopo l'ultimo, cosi' la griglia resta allineata a 7 colonne.
    private var giorniGriglia: [Date?] {
        guard let intervalloMese = calendario.dateInterval(of: .month, for: meseVisualizzato) else { return [] }
        let primoGiorno = intervalloMese.start
        let numeroGiorni = calendario.range(of: .day, in: .month, for: meseVisualizzato)?.count ?? 30

        let weekday = calendario.component(.weekday, from: primoGiorno) // 1=Domenica...7=Sabato
        let offsetIniziale = (weekday - calendario.firstWeekday + 7) % 7

        var celle: [Date?] = Array(repeating: nil, count: offsetIniziale)
        for giorno in 0..<numeroGiorni {
            if let data = calendario.date(byAdding: .day, value: giorno, to: primoGiorno) {
                celle.append(data)
            }
        }
        // Padding finale per completare l'ultima riga a multipli di 7.
        while celle.count % 7 != 0 {
            celle.append(nil)
        }
        return celle
    }

    private var grigliaGiorni: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
            ForEach(Array(giorniGriglia.enumerated()), id: \.offset) { _, data in
                cellaGiorno(data)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func cellaGiorno(_ data: Date?) -> some View {
        Group {
            if let data {
                let eventi = scioperiPerGiorno(data)
                let isOggi = calendario.isDateInToday(data)

                VStack(spacing: 3) {
                    Text("\(calendario.component(.day, from: data))")
                        .font(.subheadline)
                        .fontWeight(isOggi ? .bold : .regular)
                        .foregroundStyle(isOggi ? Color.accentColor : Color.primary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().stroke(isOggi ? Color.accentColor : .clear, lineWidth: 1.5)
                        )

                    if !eventi.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(0..<min(eventi.count, 3), id: \.self) { _ in
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    } else {
                        Color.clear.frame(height: 5)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
                .onTapGesture {
                    giornoSelezionato = GiornoSelezionato(data: data)
                }
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 52)
            }
        }
    }

    // MARK: - Dati

    private func scioperiPerGiorno(_ data: Date) -> [Sciopero] {
        let giorno = calendario.startOfDay(for: data)
        return scioperiDelMese.filter { sciopero in
            guard let inizio = sciopero.inizioDate, let fine = sciopero.fineDate else { return false }
            let inizioGiorno = calendario.startOfDay(for: inizio)
            let fineGiorno = calendario.startOfDay(for: fine)
            return giorno >= inizioGiorno && giorno <= fineGiorno
        }
    }

    @MainActor
    private func loadMese() async {
        isLoading = true
        errorMessage = nil

        guard let intervalloMese = calendario.dateInterval(of: .month, for: meseVisualizzato) else {
            isLoading = false
            return
        }
        let inizio = intervalloMese.start
        let fine = calendario.date(byAdding: .day, value: -1, to: intervalloMese.end) ?? intervalloMese.end

        do {
            scioperiDelMese = try await APIService.shared.fetchScioperi(
                da: inizio,
                a: fine,
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

/// Wrapper Identifiable per usare .sheet(item:) con una Date (Date non e' Identifiable).
private struct GiornoSelezionato: Identifiable {
    let id = UUID()
    let data: Date
}

/// Sheet di dettaglio: elenco scioperi per il giorno selezionato nel calendario.
private struct GiornoDettaglioView: View {
    let data: Date
    let scioperi: [Sciopero]
    let calendario: Calendar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if scioperi.isEmpty {
                    ContentUnavailableView(
                        "Nessuno sciopero",
                        systemImage: "checkmark.circle",
                        description: Text("Nessuno sciopero previsto per questo giorno.")
                    )
                } else {
                    List(scioperi) { sciopero in
                        ScioperoRow(sciopero: sciopero)
                    }
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private var titolo: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: data).capitalized
    }
}

#Preview {
    CalendarioView()
}
