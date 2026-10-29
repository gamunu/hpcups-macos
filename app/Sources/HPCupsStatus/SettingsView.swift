import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notifications = true
    @AppStorage("inkSeconds") private var inkSeconds = 60.0
    @AppStorage("pollSeconds") private var pollSeconds = 3.0
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify when a job completes or fails, and when ink runs low", isOn: $notifications)
            }
            Section("Refresh") {
                Picker("Ink refresh interval", selection: $inkSeconds) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                Picker("Queue polling interval", selection: $pollSeconds) {
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
            }
            Section("Menu bar") {
                Toggle("Show in menu bar", isOn: $showMenuBar)
            }
        }
        .formStyle(.grouped)
    }
}
