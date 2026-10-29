// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Gamunu Balagalla

import SwiftUI

extension StatusStore {
    /// Short connection text for one queue.
    func connectionText(_ p: PrinterInfo) -> String {
        switch connection[p.name] {
        case true?: return "Connected"
        case false?: return "Not connected"
        case nil: return DeviceURI.isUSB(p.deviceURI) ? "USB" : "Network"
        }
    }

    func connectionColor(_ p: PrinterInfo) -> Color {
        switch connection[p.name] {
        case true?: return .green
        case false?: return .red
        case nil: return .secondary
        }
    }

    /// Model for display. The nickname ends in ", hpcups-macos", which is not part of the model.
    nonisolated static func model(of p: PrinterInfo) -> String {
        var m = p.makeAndModel
        if let r = m.range(of: ", hpcups-macos", options: [.caseInsensitive, .backwards]) { m.removeSubrange(r) }
        return m.isEmpty ? (DeviceURI.model(p.deviceURI) ?? "Unknown model") : m
    }
}

/// Every printer queue the app manages, one row each with name, model and connection state.
struct PrinterList: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.printers.count == 1 ? "Printer" : "Printers")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.printers, id: \.name) { p in row(p) }
                    if store.printers.isEmpty {
                        Text("No printers found").font(TypeScale.secondary).foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: 170)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }

    private func row(_ p: PrinterInfo) -> some View {
        let isSelected = p.name == store.selected
        return Button { store.selected = p.name } label: {
            HStack(spacing: 8) {
                Image(systemName: "printer").frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StatusStore.displayName(p.name)).font(.callout.weight(.medium)).lineLimit(1)
                    Text(StatusStore.model(of: p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(store.connectionColor(p)).frame(width: 6, height: 6)
                        Text(store.connectionText(p)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.16) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(StatusStore.displayName(p.name)), \(StatusStore.model(of: p)), \(store.connectionText(p))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Compact menu for the menu bar popover.
struct PrinterMenu: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        let current = store.selectedInfo
        VStack(alignment: .leading, spacing: 2) {
            if store.printers.count > 1 {
                Picker("Printer", selection: $store.selected) {
                    ForEach(store.printers, id: \.name) { p in
                        Text("\(StatusStore.displayName(p.name)) (\(store.connectionText(p).lowercased()))").tag(p.name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Text(store.displayName).font(.subheadline.weight(.semibold))
            }
            if let current {
                Text(StatusStore.model(of: current)).font(TypeScale.note).foregroundStyle(.secondary)
            }
        }
    }
}
