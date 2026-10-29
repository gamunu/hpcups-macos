import SwiftUI

struct MainWindow: View {
    @ObservedObject var store: StatusStore
    @State private var selection: SidebarItem? = MainWindow.initialSection()

    static func initialSection() -> SidebarItem {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--open-section"), i + 1 < a.count,
           let s = SidebarItem(rawValue: a[i + 1].lowercased()) { return s }
        return .overview
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(store: store, goTo: { selection = $0 })
                case .jobs: JobsView(store: store)
                case .ink: InkView(store: store)
                case .maintenance: MaintenanceView(store: store)
                case .settings: SettingsView()
                }
            }
            .navigationTitle((selection ?? .overview).title)
        }
        .task { store.start() }
        .sheet(isPresented: Binding(get: { store.maint.job != nil }, set: { if !$0 { store.maint.close() } })) {
            MaintenanceSheet(store: store, maint: store.maint)
        }
    }
}
