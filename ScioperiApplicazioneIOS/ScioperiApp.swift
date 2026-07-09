import SwiftUI

@main
struct ScioperiApp: App {
    @StateObject private var notifiche = NotificheManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                CalendarioView()
                    .tabItem {
                        Label("Calendario", systemImage: "calendar")
                    }

                ScioperiListView()
                    .tabItem {
                        Label("Lista", systemImage: "list.bullet")
                    }

                AvvisiListView()
                    .tabItem {
                        Label("I miei avvisi", systemImage: "bell")
                    }
                    .badge(notifiche.nuoviMatchCount)
            }
            .environmentObject(notifiche)
            .task {
                await notifiche.controllaNuoviMatch()
            }
            .onChange(of: scenePhase) { _, nuovaFase in
                if nuovaFase == .active {
                    Task { await notifiche.controllaNuoviMatch() }
                }
            }
        }
    }
}
