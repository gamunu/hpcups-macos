import SwiftUI
import Sparkle

/// Wraps Sparkle's standard updater. Updates arrive as the same .pkg that
/// installs the driver, so the filter and PPD are updated with the app.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    @Published var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
        refreshLastCheck()
    }

    func refreshLastCheck() {
        lastCheck = controller.updater.lastUpdateCheckDate
    }
}

struct UpdatesSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automaticChecks)
            LabeledContent("Last checked") {
                if let date = updater.lastCheck {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never")
                }
            }
            Button("Check for Updates...") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
        .onAppear { updater.refreshLastCheck() }
    }
}
