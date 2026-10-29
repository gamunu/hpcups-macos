import SwiftUI

struct StatusView: View {
    @ObservedObject var store: StatusStore
    var detailed = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusSection
            Divider()
            inkSection
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
            if let ink = store.status?.ink, !ink.isEmpty {
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
                Text("Ink levels not available yet").font(.caption).foregroundStyle(.secondary)
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
