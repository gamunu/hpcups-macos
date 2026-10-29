import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: StatusStore
    var goTo: (SidebarItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stateCard
                HStack(alignment: .top, spacing: 16) {
                    inkCard
                    jobCard
                }
                actionsCard
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selected.replacingOccurrences(of: "_", with: " ")).font(.title2.bold())
                Text(model).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            usbBadge
        }
    }

    private var model: String {
        let m = store.status?.makeAndModel ?? ""
        return m.isEmpty ? "Printer model unknown" : m
    }

    private var usbBadge: some View {
        let usb = store.usbPresent
        let text = usb == true ? "USB connected" : usb == false ? "USB not found" : "USB not checked"
        let color: Color = usb == true ? .green : usb == false ? .red : .secondary
        return Label(text, systemImage: usb == false ? "cable.connector.slash" : "cable.connector")
            .font(.callout)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
            .accessibilityLabel(text)
    }

    private var stateCard: some View {
        let h = store.health
        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: h.symbol)
                .font(.system(size: 44))
                .foregroundStyle(h.color)
                .frame(width: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.healthTitle).font(.largeTitle.bold())
                ForEach(store.healthDetails, id: \.self) { line in
                    Text(line).foregroundStyle(.secondary)
                }
                if store.queueStuck {
                    Button("Reset queue") { store.resetQueue() }
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(h.color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(h.color.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }

    private var inkCard: some View {
        Card(title: "Ink") {
            if let r = store.ink, !r.cartridges.isEmpty {
                ForEach(r.cartridges) { InkBar(cartridge: $0) }
            } else if let ink = store.status?.ink, !ink.isEmpty {
                ForEach(ink, id: \.name) { s in
                    HStack {
                        InkDot(isBlack: isBlackHex(s.colorHex) || s.name.localizedCaseInsensitiveContains("black"), hex: s.colorHex)
                        Text(s.name)
                        Spacer()
                        Text(s.level >= 0 ? "\(min(s.level, 100))%" : "unknown").foregroundStyle(.secondary)
                    }.font(.callout)
                }
            } else {
                Text(store.inkError ?? "Reading ink levels").font(.callout).foregroundStyle(.secondary)
            }
            Button("Show ink details") { goTo(.ink) }.buttonStyle(.link)
        }
    }

    private var jobCard: some View {
        Card(title: "Current job") {
            if let j = store.activeJob {
                Text(j.title).font(.body.weight(.medium)).lineLimit(2)
                Text("\(j.stateText), \(j.sizeKB) KB, \(j.user)").font(.callout).foregroundStyle(.secondary)
                Button("Cancel job") { store.cancel(j) }
            } else if store.isBusy {
                Text("The printer is working.").font(.callout).foregroundStyle(.secondary)
                Button("Show job history") { goTo(.jobs) }.buttonStyle(.link)
            } else {
                Text("No job is printing.").font(.callout).foregroundStyle(.secondary)
                Button("Show job history") { goTo(.jobs) }.buttonStyle(.link)
            }
        }
    }

    private var actionsCard: some View {
        Card(title: "Quick actions") {
            HStack {
                Button { store.testPage() } label: { Label("Print test page", systemImage: "doc.text") }
                    .disabled(store.usbPresent == false)
                Button { store.maint.open(.clean) } label: { Label("Clean heads", systemImage: "sparkles") }
                    .disabled(!store.canMaintain)
                Button { store.maint.open(.align) } label: { Label("Align heads", systemImage: "arrow.left.and.right") }
                    .disabled(!store.canMaintain)
                Spacer()
            }
            if let why = store.maintenanceBlockReason {
                Text("Maintenance is off: \(why)").font(.caption).foregroundStyle(.secondary)
            }
            if let m = store.actionMessage {
                Text(m).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
