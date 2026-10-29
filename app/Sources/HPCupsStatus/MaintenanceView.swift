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
        case .clean: return "Clears clogged nozzles. Try this first when print is faint or has gaps."
        case .deepClean: return "A stronger cycle for when a normal clean did not help. Uses more ink."
        case .diagnostics: return "Prints a test page so you can check colors and black text."
        case .align: return "Prints a page that you scan on the printer so the heads line up."
        }
    }
}

struct MaintenanceView: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let why = store.maintenanceBlockReason {
                    Label(why, systemImage: "exclamationmark.circle")
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(MaintenanceJob.allCases) { job in card(job) }
                }
                Text("Each task walks you through the steps and shows what the printer reports. These tasks use ink and paper. Load plain paper first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func card(_ job: MaintenanceJob) -> some View {
        let supported = store.maint.supports(job)
        return Card {
            HStack(spacing: 12) {
                Image(systemName: job.symbol).font(.title).frame(width: 36).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(job.title).font(.headline)
            }
            Text(job.summary).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            HStack {
                Button("Start") { store.maint.open(job) }
                    .disabled(!store.canMaintain || !supported)
                if !supported { Text("Not supported by this printer").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: guided sheet

struct MaintenanceSheet: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var maint: MaintenanceController

    var body: some View {
        if let job = maint.job {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: job.symbol).font(.title2).foregroundStyle(Color.accentColor)
                    Text(job.title).font(.title2.bold())
                    Spacer()
                }
                StepBar(steps: MaintenanceController.steps(for: job), current: maint.reached, failed: isFailed)
                Divider()
                content(job).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Divider()
                footer(job)
            }
            .padding(20)
            .frame(width: 520, height: 460)
            .interactiveDismissDisabled(maint.isBusy)
        }
    }

    private var isFailed: Bool { if case .failed = maint.stage { return true } else { return false } }

    // MARK: content

    @ViewBuilder private func content(_ job: MaintenanceJob) -> some View {
        switch maint.stage {
        case .prepare: prepare(job)
        case .starting:
            Label("Sending the request to the printer", systemImage: "paperplane").foregroundStyle(.secondary)
            ProgressView()
        case .running: running(job)
        case .awaitScan: scanInstructions(scanning: false)
        case .scanning: scanInstructions(scanning: true)
        case .done: done(job)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func prepare(_ job: MaintenanceJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Load plain paper in the input tray.", systemImage: "doc.badge.plus")
            Text(job.summary).foregroundStyle(.secondary)
            switch job {
            case .deepClean:
                Label("Deep clean uses more ink than a normal clean. Try a normal clean first.", systemImage: "drop.fill")
                    .foregroundStyle(.orange)
            case .align:
                Label("You will scan the printed page on the printer's glass. Stay near the printer.", systemImage: "scanner")
            default:
                Text("This uses a little ink.").foregroundStyle(.secondary)
            }
            if let why = store.maintenanceBlockReason {
                Label(why, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        }
    }

    private func running(_ job: MaintenanceJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(runningTitle(job)).font(.headline)
            }
            livePrinterState
            if let a = maint.attention { attentionBanner(a) }
        }
    }

    private func runningTitle(_ job: MaintenanceJob) -> String {
        switch job {
        case .clean, .deepClean: return "Cleaning the print heads"
        case .diagnostics: return "Printing the diagnostics page"
        case .align: return "Printing the alignment page"
        }
    }

    private var livePrinterState: some View {
        HStack {
            Text("Printer").foregroundStyle(.secondary)
            Text(Maintenance.liveText(maint.categories)).monospacedDigit()
            if let c = maint.calState, maint.job == .align {
                Text("(\(c))").foregroundStyle(.secondary).font(.caption)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func attentionBanner(_ a: Attention) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: a.symbol).font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.headline)
                Text(a.detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
    }

    private func scanInstructions(scanning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if scanning {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("The printer is scanning the page").font(.headline) }
                Text("Keep the lid closed until the printer finishes.").foregroundStyle(.secondary)
            } else {
                Text("The page is out. Scan it now.").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Place the page printed side down on the scanner glass.")
                    Text("2. Put the top edge toward the back, in the corner with the marker.")
                    Text("3. Close the lid.")
                    Text("4. Press Color Copy once.")
                }
            }
            livePrinterState
            if let a = maint.attention { attentionBanner(a) }
        }
    }

    @ViewBuilder private func done(_ job: MaintenanceJob) -> some View {
        switch job {
        case .clean, .deepClean:
            Label("Cleaning finished", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text("This printer does not print a page after cleaning. Print the diagnostics page to check the result.")
                .foregroundStyle(.secondary)
        case .diagnostics:
            Label("The page has printed", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text("How did it look?").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                guidance("checkmark.circle", .green, "Solid color blocks and dark black text: the heads are fine.")
                guidance("sparkles", .orange, "Faint black text or gaps in the blocks: run a deep clean.")
                guidance("exclamationmark.triangle", .orange, "Ink flows but is still faint: clean the cartridge's copper contacts and the carriage contacts.")
            }
        case .align:
            Label("Alignment finished", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text("The printer scanned the page and is ready.").foregroundStyle(.secondary)
            Text("If the printer's Attention light is blinking, the alignment failed. Reload the page and try again.")
        }
        if let n = maint.note { Text(n).font(.callout).foregroundStyle(.secondary) }
    }

    private func guidance(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(text)
        }
    }

    // MARK: footer

    @ViewBuilder private func footer(_ job: MaintenanceJob) -> some View {
        HStack {
            switch maint.stage {
            case .prepare:
                Spacer()
                Button("Cancel") { maint.close() }.keyboardShortcut(.cancelAction)
                Button("Start") { maint.begin() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.canMaintain)
            case .starting, .running, .awaitScan, .scanning:
                Text("Closing this window does not stop the printer.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Stop watching") { maint.close() }
            case .done:
                Spacer()
                if job == .clean || job == .deepClean {
                    Button("Print diagnostics page to check") { maint.open(.diagnostics) }
                }
                Button("Close") { maint.close() }.keyboardShortcut(.defaultAction)
            case .failed:
                Spacer()
                Button("Close") { maint.close() }.keyboardShortcut(.cancelAction)
                Button("Try again") { maint.retry() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct StepBar: View {
    let steps: [String]
    let current: Int
    var failed = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(fill(i)).frame(width: 22, height: 22)
                        if i < current || (i == current && current == steps.count - 1 && !failed) {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        } else if i == current && failed {
                            Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(i == current ? .white : .secondary)
                        }
                    }
                    Text(name).font(.callout).foregroundStyle(i <= current ? .primary : .secondary)
                }
                if i < steps.count - 1 { Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(current + 1, steps.count)) of \(steps.count): \(steps[min(current, steps.count - 1)])")
    }

    private func fill(_ i: Int) -> Color {
        if i == current && failed { return .orange }
        if i < current { return .green }
        if i == current { return .accentColor }
        return Color.secondary.opacity(0.2)
    }
}
