import Foundation

/// Tiny namespace-agnostic XML tree, enough for LEDM documents.
final class XMLNode {
    let name: String            // local name, prefix removed
    var text = ""
    var children: [XMLNode] = []
    init(name: String) { self.name = name }

    func first(_ n: String) -> XMLNode? { children.first { $0.name == n } }
    func all(_ n: String) -> [XMLNode] { children.filter { $0.name == n } }
    func value(_ path: String...) -> String? {
        var node: XMLNode? = self
        for p in path { node = node?.first(p) }
        guard let t = node?.text.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
    func descendants(_ n: String) -> [XMLNode] {
        var out: [XMLNode] = []
        for c in children {
            if c.name == n { out.append(c) }
            out += c.descendants(n)
        }
        return out
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let n = XMLNode(name: local)
        if let top = stack.last { top.children.append(n) } else { root = n }
        stack.append(n)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) { _ = stack.popLast() }
}

func parseXML(_ data: Data) -> XMLNode? {
    let b = XMLTreeBuilder()
    let p = XMLParser(data: data)
    p.delegate = b
    p.shouldProcessNamespaces = false
    return p.parse() ? b.root : (b.root)
}

enum InkState: String, Equatable, Sendable {
    case ok, low, veryLow, empty, missing, nonHP, unknown

    var text: String {
        switch self {
        case .ok: return "OK"
        case .low: return "Low"
        case .veryLow: return "Very low"
        case .empty: return "Empty"
        case .missing: return "Missing"
        case .nonHP: return "Non-HP or refilled"
        case .unknown: return "Unknown"
        }
    }

    /// States worth a notification.
    var needsAttention: Bool {
        switch self {
        case .low, .veryLow, .empty, .missing: return true
        default: return false
        }
    }
}

struct InkCartridge: Identifiable, Equatable, Sendable {
    var label: String          // CMY or K, as the printer reports it
    var percent: Int?          // nil when the printer does not report one
    var state: InkState
    var rawState: String
    var measured: String
    var product: String?       // e.g. 682

    var id: String { label }
    var name: String {
        switch label {
        case "K": return "Black"
        case "CMY": return "Tri-color"
        default: return label
        }
    }
    var colorHex: String {
        switch label {
        case "K": return "#222222"
        case "CMY": return "#2A9DF4"
        default: return "#888888"
        }
    }
}

struct InkReport: Equatable, Sendable {
    var cartridges: [InkCartridge]
    var alignmentMode: String?
    var fetched: Date
}

enum InkParser {
    /// Maps the ConsumableConfigDyn reply to cartridges. Level and state rules follow
    /// HPLIP's StatusType10Agents (base/status.py): 0 percent means empty (unless the
    /// quantity state is unknown) and 10 percent or less means low.
    static func parse(_ data: Data) -> InkReport? {
        guard let root = parseXML(data), root.name == "ConsumableConfigDyn" else { return nil }
        var out: [InkCartridge] = []
        for info in root.all("ConsumableInfo") {
            let type = info.value("ConsumableTypeEnum") ?? ""
            guard ["ink", "inkCartridge", "inkTank", "toner", "tonerCartridge", "rechargeableToner"].contains(type)
            else { continue }
            let label = info.value("ConsumableLabelCode") ?? "?"
            let raw = info.value("ConsumableLifeState", "ConsumableState") ?? "unknown"
            let measured = info.value("ConsumableLifeState", "MeasuredQuantityState") ?? "unknown"
            let brand = info.value("ConsumableLifeState", "Brand")
            let refilled = info.value("ConsumableLifeState", "IsRefilled") == "true"
            let pct = info.value("ConsumablePercentageLevelRemaining").flatMap { Int($0) }.map { max(0, min(100, $0)) }
            let state = classify(raw: raw, measured: measured, percent: pct, brand: brand, refilled: refilled)
            out.append(InkCartridge(label: label, percent: pct, state: state, rawState: raw,
                                    measured: measured, product: info.value("ConsumableSelectibilityNumber")))
        }
        let mode = root.descendants("AlignmentMode").first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return InkReport(cartridges: out, alignmentMode: mode, fetched: Date())
    }

    static func classify(raw: String, measured: String, percent: Int?, brand: String?, refilled: Bool) -> InkState {
        let r = raw.lowercased()
        if r.contains("missing") || r.contains("misinstalled") { return .missing }
        if r.contains("nonhp") || r.contains("refill") || r.contains("counterfeit") || refilled
            || (brand != nil && brand!.uppercased() != "HP" && brand!.lowercased() != "unknown") {
            return .nonHP
        }
        if r == "empty" || r == "out" || r.contains("depleted") { return .empty }
        if r.contains("verylow") { return .veryLow }
        if r == "low" { return .low }
        if let p = percent {
            if p == 0 { return measured == "unknown" ? .unknown : .empty }
            if p <= 5 { return .veryLow }
            if p <= 10 { return .low }
        }
        if r == "unknown" { return .unknown }
        return .ok   // ok, genuineHP, newGenuineHP, and similar
    }
}

enum MaintenanceJob: String, CaseIterable, Identifiable, Sendable {
    case clean, deepClean, diagnostics, align

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: return "Clean print heads"
        case .deepClean: return "Deep clean"
        case .diagnostics: return "Check print quality"
        case .align: return "Line up print heads"
        }
    }
    /// InternalPrintDyn JobType, nil for alignment.
    var jobType: String? {
        switch self {
        case .clean: return "cleaningPage"
        case .deepClean: return "cleaningPageLevel2"
        case .diagnostics: return "diagnosticsPage"
        case .align: return nil
        }
    }
}
