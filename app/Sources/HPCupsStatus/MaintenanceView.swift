import SwiftUI

extension MaintenanceJob {
    var symbol: String {
        switch self {
        case .clean: return "sparkles"
        case .deepClean: return "drop.degreesign"
        case .diagnostics: return "doc.text.magnifyingglass"
        case .align: return "arrow.left.and.right"
        }
    }
    var summary: String {
        switch self {
        case .clean: return "Fixes faint prints and gaps. Try this first."
        case .deepClean: return "A stronger clean. Use it when a normal clean did not help. Uses more ink."
        case .diagnostics: return "Prints a test page so you can check the colors and the black text."
        case .align: return "Prints a page that you scan on the printer. This lines up the print heads."
        }
    }
    var startLabel: String {
        switch self {
        case .clean: return "Start cleaning"
        case .deepClean: return "Start deep clean"
        case .diagnostics: return "Print the page"
        case .align: return "Start"
        }
    }
}

struct MaintenanceView: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let why = store.maintenanceBlockReason {
                    Banner { Label(why, systemImage: "exclamationmark.circle") }
                }
                let jobs = MaintenanceJob.allCases
                ForEach(Array(stride(from: 0, to: jobs.count, by: 2)), id: \.self) { i in
                    CardRow {
                        ForEach(jobs[i..<min(i + 2, jobs.count)]) { card($0) }
                    }
                }
                Text("These tasks use ink and paper. Put plain paper in the printer first.")
                    .font(TypeScale.secondary).foregroundStyle(.secondary)
            }
            .padding(Space.page)
        }
    }

    private func card(_ job: MaintenanceJob) -> some View {
        let supported = store.maint.supports(job)
        return Card {
            HStack(spacing: Space.m) {
                Image(systemName: job.symbol).font(.title).frame(width: 36, height: 36).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(job.title).font(TypeScale.cardTitle)
            }
            Text(job.summary).font(TypeScale.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Start") { store.maint.open(job) }
                    .primaryAction()
                    .disabled(!store.canMaintain || !supported)
                if !supported {
                    Text("Not supported by this printer").font(TypeScale.note).foregroundStyle(.secondary)
                }
            }
        }
    }
}
