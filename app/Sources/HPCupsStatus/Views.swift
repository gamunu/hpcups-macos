import SwiftUI

struct StatusView: View {
    @ObservedObject var store: StatusStore
    var detailed = false
    @Environment(\.openWindow) private var openWindow
    @State private var confirming: MaintenanceJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusSection
            Divider()
            inkSection
            Divider()
            MaintenanceSection(store: store, maint: store.maint, confirming: $confirming)
            Divider()
            jobsSection
            Divider()
            actions
            if let m = store.actionMessage {
                Text(m).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: detailed ? 520 : 360)
        .onAppear { Task { await store.refreshInk() } }
        .sheet(item: $confirming) { job in
            ConfirmSheet(job: job, store: store, maint: store.maint) { confirming = nil }
        }
        .sheet(isPresented: Binding(
            get: { store.maint.phase != .idle && confirming == nil },
            set: { if !$0 { store.maint.dismiss() } })) {
            ProgressSheet(maint: store.maint)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: store.iconName).font(.title2)
                .foregroundStyle(store.hasProblem ? .orange : .primary)
            if store.printers.count > 1 {
                Picker("", selection: $store.selected) {
                    ForEach(store.printers, id: \.name) { Text($0.name).tag($0.name) }
                }.labelsHidden()
            } else {
                Text(store.selected).font(.headline)
            }
            Spacer()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = store.status {
                if let e = s.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    row("State", s.stateText)
                    if !s.message.isEmpty { row("Message", s.message) }
                }
                if let usb = store.usbPresent {
                    row("USB", usb ? "Connected" : "Not found")
                }
                ForEach(store.reasonLines, id: \.self) { line in
                    Label(line, systemImage: "info.circle").font(.callout)
                }
                if detailed {
                    row("Model", s.makeAndModel)
                    row("Device", s.deviceURI)
                    if !s.reasons.isEmpty { row("Raw reasons", s.reasons.joined(separator: ", ")) }
                }
            } else {
                Text("Loading").foregroundStyle(.secondary)
            }
        }
    }

    private var inkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ink").font(.subheadline.bold())
            if let report = store.ink, !report.cartridges.isEmpty {
                ForEach(report.cartridges) { c in
                    HStack {
                        Circle().fill(color(c.colorHex)).frame(width: 10, height: 10)
                        Text(c.name).font(.callout)
                        Spacer()
                        if let p = c.percent {
                            ProgressView(value: Double(p), total: 100).frame(width: 90)
                                .tint(c.state.needsAttention ? .orange : nil)
                            Text("\(p)%").font(.caption).monospacedDigit().frame(width: 36, alignment: .trailing)
                        } else {
                            Text("unknown").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(c.state.text).font(.caption)
                            .foregroundStyle(c.state.needsAttention ? .orange : .secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    if detailed {
                        Text("Cartridge HP \(c.product ?? "?"), printer state \(c.rawState), measured \(c.measured)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if let ink = store.status?.ink, !ink.isEmpty {
                ForEach(ink, id: \.name) { s in
                    HStack {
                        Circle().fill(color(s.colorHex)).frame(width: 10, height: 10)
                        Text(s.name).font(.callout)
                        Spacer()
                        if s.level >= 0 {
                            ProgressView(value: Double(min(s.level, 100)), total: 100).frame(width: 90)
                            Text("\(s.level)%").font(.caption).monospacedDigit()
                        } else {
                            Text("unknown").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text(store.inkError ?? "Reading ink levels").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Jobs").font(.subheadline.bold())
            if store.jobs.isEmpty {
                Text("No jobs").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.jobs.prefix(detailed ? 15 : 5)) { j in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(j.title).font(.callout).lineLimit(1)
                        Text(jobSubtitle(j)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !j.reasons.isEmpty && detailed {
                            Text(j.reasons.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if j.isActive {
                        Button("Cancel") { store.cancel(j) }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(store.status?.stateCode == 5 ? "Resume" : "Pause") { store.togglePause() }
            Button("Cancel all") { store.cancelAll() }
                .disabled(!store.jobs.contains(where: \.isActive))
            Button("Test page") { store.testPage() }
            Spacer()
            if !detailed {
                Button("Details") {
                    openWindow(id: "details")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(v).textSelection(.enabled)
            Spacer()
        }.font(.callout)
    }

    private func jobSubtitle(_ j: PrintJob) -> String {
        let t = j.time.formatted(date: .abbreviated, time: .shortened)
        return "\(j.stateText) - \(j.user) - \(j.sizeKB) KB - \(t)"
    }

    private func color(_ hex: String?) -> Color {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return .gray }
        h.removeFirst()
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .gray }
        return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                     blue: Double(v & 255) / 255)
    }
}

// MARK: maintenance

struct MaintenanceSection: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var maint: MaintenanceController
    @Binding var confirming: MaintenanceJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Maintenance").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(MaintenanceJob.allCases) { job in
                    Button(job.title) { confirming = job }
                        .disabled(!store.canMaintain || !maint.supports(job))
                        .help(job.detail)
                }
            }
            .controlSize(.small)
            if !store.canMaintain {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var reason: String {
        if store.usbPresent == false { return "Connect the printer by USB to use these." }
        if maint.phase.isBusy { return "A maintenance job is running." }
        return "Available when no print job is active."
    }
}

struct ConfirmSheet: View {
    let job: MaintenanceJob
    @ObservedObject var store: StatusStore
    @ObservedObject var maint: MaintenanceController
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(job.title).font(.headline)
            Text(job.detail)
            Text(job.warning).fontWeight(.semibold)
            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Start") {
                    maint.start(job)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canMaintain)
            }
        }
        .padding(18)
        .frame(width: 320)
    }
}

struct ProgressSheet: View {
    @ObservedObject var maint: MaintenanceController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch maint.phase {
            case .idle:
                EmptyView()
            case .running(let job, let msg):
                Text(job.title).font(.headline)
                HStack { ProgressView().controlSize(.small); Text(msg) }
            case .awaitingScan(let msg):
                Text("Align print heads").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Wait for the alignment page to print.")
                    Text("2. Place the alignment page, with the printed side facing down, on the scanner glass.")
                    Text("3. Press the Enter or Scan button on the printer.")
                }
                HStack { ProgressView().controlSize(.small); Text(msg).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Spacer()
                    Button("Done") { maint.finishAlignment() }.keyboardShortcut(.defaultAction)
                }
            case .done(let job, let msg):
                Text(job.title).font(.headline)
                Label(msg, systemImage: "checkmark.circle").foregroundStyle(.green)
                HStack { Spacer(); Button("Close") { maint.dismiss() }.keyboardShortcut(.defaultAction) }
            case .failed(let job, let msg):
                Text(job.title).font(.headline)
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                HStack { Spacer(); Button("Close") { maint.dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(18)
        .frame(width: 340)
        .interactiveDismissDisabled(maint.phase.isBusy)
    }
}
