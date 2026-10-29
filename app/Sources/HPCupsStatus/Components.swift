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

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

func inkColor(_ hex: String?) -> Color {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return .gray }
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return .gray }
    return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                 blue: Double(v & 255) / 255)
}

extension StatusStore.Health {
    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .printing: return "printer.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .disconnected: return "bolt.slash.fill"
        }
    }
    var color: Color {
        switch self {
        case .ready: return .green
        case .printing: return .blue
        case .attention: return .orange
        case .disconnected: return .red
        }
    }
}

extension InkCartridge {
    var stateColor: Color {
        switch state {
        case .ok: return .green
        case .low, .veryLow, .empty, .missing: return .orange
        case .nonHP, .unknown: return .secondary
        }
    }
    var percentText: String { percent.map { "\($0)%" } ?? "unknown" }
    var spoken: String {
        "\(name) cartridge, \(percent.map { "\($0) percent" } ?? "level unknown"), \(state.text)"
    }
}

let inkCyan = Color(red: 0.0, green: 0.68, blue: 0.93)
let inkMagenta = Color(red: 0.9, green: 0.1, blue: 0.55)
let inkYellow = Color(red: 1.0, green: 0.85, blue: 0.0)

/// Near-black ink. Pure black vanishes on a dark background, so dark mode uses a very dark
/// grey and every black swatch gets an outline (see `inkOutline`).
func blackInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(white: 0.07) : .black
}

/// Outline that keeps a black swatch visible on both backgrounds.
let inkOutline = Color.primary.opacity(0.5)

func isBlackHex(_ hex: String?) -> Bool {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return false }
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return false }
    let r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255
    return r < 0x50 && g < 0x50 && b < 0x50
}

/// Colored dot for one ink. Tri-color is split into cyan, magenta and yellow.
struct InkDot: View {
    var isBlack: Bool = false
    var isTri: Bool = false
    var hex: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if isTri {
                VStack(spacing: 0) {
                    inkCyan; inkMagenta; inkYellow
                }
                .clipShape(Circle())
            } else if isBlack {
                Circle().fill(blackInk(scheme))
            } else {
                Circle().fill(inkColor(hex))
            }
        }
        .frame(width: 10, height: 10)
        .overlay(Circle().strokeBorder(inkOutline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension InkCartridge {
    var isBlack: Bool { label == "K" }
    var isTri: Bool { label == "CMY" }
}

/// Bar with an empty track. Black ink is a near-black fill with an outline, tri-color is three
/// stacked cyan, magenta and yellow stripes.
struct InkLevelBar: View {
    let cartridge: InkCartridge
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fraction = Double(min(max(cartridge.percent ?? 0, 0), 100)) / 100
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                if cartridge.percent != nil, fraction > 0 {
                    fill.frame(width: max(g.size.height, g.size.width * fraction))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(cartridge.isBlack ? inkOutline : .clear, lineWidth: 1)
                            .frame(width: max(g.size.height, g.size.width * fraction)),
                                 alignment: .leading)
                }
                Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
            }
        }
        .frame(height: 10)
    }

    @ViewBuilder private var fill: some View {
        if cartridge.isTri {
            VStack(spacing: 0) { inkCyan; inkMagenta; inkYellow }
        } else if cartridge.isBlack {
            blackInk(scheme)
        } else {
            inkColor(cartridge.colorHex)
        }
    }
}

/// Small horizontal bar used in the overview and the menu bar popover.
struct InkBar: View {
    let cartridge: InkCartridge
    var body: some View {
        HStack(spacing: 8) {
            InkDot(isBlack: cartridge.isBlack, isTri: cartridge.isTri, hex: cartridge.colorHex)
            Text(cartridge.name).frame(width: 64, alignment: .leading)
            InkLevelBar(cartridge: cartridge)
            Text(cartridge.percentText).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cartridge.spoken)
    }
}
