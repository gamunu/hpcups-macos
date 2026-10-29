import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, jobs, ink, maintenance, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .jobs: return "Jobs"
        case .ink: return "Ink"
        case .maintenance: return "Maintenance"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "printer"
        case .jobs: return "list.bullet.rectangle"
        case .ink: return "drop"
        case .maintenance: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

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
        .task {
            if let spec = PreviewMode.spec { store.maint.applyPreview(spec) } else { store.start() }
        }
        .sheet(isPresented: Binding(get: { store.maint.job != nil }, set: { if !$0 { store.maint.close() } })) {
            MaintenanceSheet(store: store, maint: store.maint)
        }
    }
}
