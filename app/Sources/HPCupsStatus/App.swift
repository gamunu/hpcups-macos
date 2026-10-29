import SwiftUI

struct HPCupsStatusApp: App {
    @StateObject private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            StatusView(store: store)
        } label: {
            Image(systemName: store.iconName)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)

        Window("hpcups Status", id: "details") {
            StatusView(store: store, detailed: true)
        }
        .windowResizability(.contentSize)
    }
}
