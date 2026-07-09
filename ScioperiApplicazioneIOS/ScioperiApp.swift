import SwiftUI

@main
struct ScioperiApp: App {
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
            }
        }
    }
}
