import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    /// Closing the window keeps the app and its menu bar item running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct HPCupsStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = StatusStore()
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        Window("hpcups Status", id: "main") {
            MainWindow(store: store)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") { Updater.shared.checkForUpdates() }
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView(store: store)
        } label: {
            Image(systemName: store.iconName)
                .accessibilityLabel("hpcups Status: \(store.healthTitle)")
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
