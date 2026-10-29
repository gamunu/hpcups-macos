import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var store: StatusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let h = store.health
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: h.symbol).font(.title2).foregroundStyle(h.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.healthTitle).font(.headline)
                    Text(store.healthDetails.first ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            Divider()
            if let r = store.ink, !r.cartridges.isEmpty {
                VStack(spacing: 6) { ForEach(r.cartridges) { InkBar(cartridge: $0) } }
            } else {
                Text(store.inkError ?? "Reading ink levels").font(.caption).foregroundStyle(.secondary)
            }
            if let j = store.activeJob {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(j.title).font(.callout).lineLimit(1)
                    Text("\(j.stateText), \(j.sizeKB) KB").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("Open hpcups Status") {
                    openWindow(id: "main")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { Task { await store.refreshInk() } }
    }
}
