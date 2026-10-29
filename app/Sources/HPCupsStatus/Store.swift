import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class StatusStore: ObservableObject {
    @Published var printers: [PrinterInfo] = []
    @Published var selected: String = UserDefaults.standard.string(forKey: "printer") ?? "HP_DeskJet_2300" {
        didSet {
            UserDefaults.standard.set(selected, forKey: "printer")
            previousJobStates = [:]
            Task { await refresh() }
        }
    }
    @Published var status: PrinterStatus?
    @Published var usbPresent: Bool?
    @Published var jobs: [PrintJob] = []
    @Published var actionMessage: String?
    /// LEDM status categories read over USB, nil when not read yet.
    @Published var ledmCategories: [String]?
    /// True when CUPS says "processing" but has had no active job for a while.
    @Published var queueStuck = false
    private var staleSince: Date?
    private var ledmInFlight = false
    private var lastLedmFetch = Date.distantPast
    static let staleSeconds = 10.0
    @Published var ink: InkReport?
    @Published var inkError: String?
    @Published var inkLoading = false
    let maint = MaintenanceController()

    static let defaultPollSeconds = 3.0
    static let defaultInkSeconds = 60.0
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "notificationsEnabled": true, "showMenuBar": true,
            "pollSeconds": defaultPollSeconds, "inkSeconds": defaultInkSeconds,
        ])
    }
    private static func seconds(_ key: String, _ fallback: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v >= 1 ? v : fallback
    }

    private var lastInkFetch = Date.distantPast
    private var inkInFlight = false

    private var previousJobStates: [Int: Int] = [:]
    private var pollCount = 0
    private var started = false
    private let notifier = Notifier()

    var reasonLines: [String] { StatusText.describe(all: status?.reasons ?? []) }
    var hasProblem: Bool {
        guard let s = status else { return false }
        return s.error != nil || s.stateCode == 5 || s.reasons.contains(where: StatusText.isProblem)
            || usbPresent == false
    }

    var iconName: String {
        if hasProblem { return "exclamationmark.triangle.fill" }
        if isBusy { return "printer.fill" }
        return "printer"
    }

    func start() {
        guard !started else { return }
        started = true
        StatusStore.registerDefaults()
        if UserDefaults.standard.bool(forKey: "notificationsEnabled") { notifier.requestAuthorization() }
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(StatusStore.seconds("pollSeconds", StatusStore.defaultPollSeconds)))
            }
        }
        Task { [weak self] in
            while let self {
                await self.refreshInk()
                try? await Task.sleep(for: .seconds(StatusStore.seconds("inkSeconds", StatusStore.defaultInkSeconds)))
            }
        }
    }

    /// Why maintenance is unavailable, nil when it can start.
    var maintenanceBlockReason: String? {
        if usbPresent == false { return "The printer is not connected over USB." }
        if maint.isBusy { return "A maintenance job is running." }
        if jobs.contains(where: \.isActive) { return "A print job is active. Wait for it to finish or cancel it." }
        if isCalibrating { return Self.calibratingNote }
        if isBusy { return "The printer is busy printing." }
        return nil
    }
    var canMaintain: Bool { maintenanceBlockReason == nil }

    var activeJob: PrintJob? { jobs.first(where: \.isActive) }

    /// The one busy rule. Busy means CUPS has an active job (pending, held, processing) or the
    /// printer itself reports processing or calibrating. The CUPS printer-state alone does not
    /// count: it can stay at "processing" after the job is gone.
    var isBusy: Bool {
        if activeJob != nil { return true }
        if let c = ledmCategories, Maintenance.isBusy(c) { return true }
        return false
    }

    enum Health { case ready, printing, attention, disconnected }

    var health: Health {
        guard let s = status else { return .disconnected }
        if usbPresent == false || s.error != nil { return .disconnected }
        if s.stateCode == 5 || s.reasons.contains(where: StatusText.isProblem) { return .attention }
        if let ink = ink, ink.cartridges.contains(where: { $0.state == .empty || $0.state == .missing }) { return .attention }
        if isBusy { return .printing }
        return .ready
    }

    var healthTitle: String {
        switch health {
        case .ready: return "Ready"
        case .printing: return isCalibrating && activeJob == nil ? "Aligning" : "Printing"
        case .attention: return "Needs attention"
        case .disconnected: return "Disconnected"
        }
    }

    static let stuckNote = "The print queue reports a job that does not exist."
    static let calibratingNote = "The printer is in the middle of a head alignment. If the alignment page is out, place it face down on the scanner glass and press Color Copy. To stop the alignment instead, press the Cancel (X) button on the printer."

    /// The printer reports an alignment in progress (LEDM "calibrating").
    var isCalibrating: Bool { ledmCategories?.contains("calibrating") ?? false }

    /// Plain-language reasons behind the current state.
    var healthDetails: [String] {
        var out: [String] = []
        guard let s = status else { return ["Reading the printer state"] }
        if usbPresent == false { out.append("The USB cable is unplugged or the printer is off.") }
        if let e = s.error { out.append(e) }
        if s.stateCode == 5 { out.append("The queue is paused or stopped.") }
        if isCalibrating && activeJob == nil { out.append(Self.calibratingNote) }
        out += reasonLines
        if let ink = ink {
            for c in ink.cartridges where c.state == .empty || c.state == .missing || c.state == .veryLow || c.state == .low {
                out.append("\(c.name) cartridge: \(c.state.text.lowercased())")
            }
        }
        if queueStuck { out.append(StatusStore.stuckNote) }
        else if !s.message.isEmpty && s.stateCode != 3 && !(s.stateCode == 4 && !isBusy) { out.append(s.message) }
        if out.isEmpty {
            switch health {
            case .ready: out.append("The printer is idle and can take a job.")
            case .printing: out.append(activeJob.map { "Printing \($0.title)" } ?? "The printer is working.")
            default: break
            }
        }
        return out
    }

    /// Reads ink levels over LEDM. Called on open and every 60 s.
    func refreshInk(force: Bool = false) async {
        guard !inkInFlight, !maint.isBusy else { return }
        guard force || Date().timeIntervalSince(lastInkFetch) > 10 else { return }
        if usbPresent == false { ink = nil; inkError = "Printer not connected over USB"; return }
        inkInFlight = true
        inkLoading = true
        defer { inkInFlight = false; inkLoading = false }
        lastInkFetch = Date()
        if let uri = status?.deviceURI { LEDMClient.shared.serial = USBCheck.serial(fromURI: uri) }
        do {
            let r = try await LEDMClient.shared.getAsync("/DevMgmt/ConsumableConfigDyn.xml")
            guard r.status == 200, let report = InkParser.parse(r.body) else {
                inkError = "Printer returned no ink data (HTTP \(r.status))"
                return
            }
            ink = report
            inkError = nil
            notifyInk(report)
        } catch {
            inkError = error.localizedDescription
        }
        await maint.loadCapabilities()
    }

    /// One notification per cartridge each time its state changes to a problem state.
    private func notifyInk(_ report: InkReport) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        let d = UserDefaults.standard
        for c in report.cartridges {
            let key = "inkState.\(c.label)"
            let prev = d.string(forKey: key)
            guard prev != c.state.rawValue else { continue }
            d.set(c.state.rawValue, forKey: key)
            guard c.state.needsAttention else { continue }
            let pct = c.percent.map { ", \($0)% left" } ?? ""
            notifier.post(title: "\(c.name) ink: \(c.state.text.lowercased())", body: "The \(c.name.lowercased()) cartridge is \(c.state.text.lowercased())\(pct).")
        }
    }

    func refresh() async {
        let name = selected
        let reloadList = printers.isEmpty || pollCount % 10 == 0
        pollCount += 1
        let snap = await Task.detached(priority: .utility) { () -> Snapshot in
            Snapshot.load(selected: name, reloadList: reloadList)
        }.value
        if let list = snap.printers { printers = list }
        if let chosen = snap.resolvedName, chosen != selected {
            selected = chosen
            return
        }
        status = snap.status
        usbPresent = snap.usb
        jobs = snap.jobs
        updateStale()
        checkNotifications(snap.jobs)
        await refreshLEDM()
    }

    /// Tracks how long CUPS has reported "processing" with no active job.
    private func updateStale() {
        if status?.stateCode == 4 && activeJob == nil {
            if staleSince == nil { staleSince = Date() }
        } else {
            staleSince = nil
        }
        let stuck = staleSince.map { Date().timeIntervalSince($0) > StatusStore.staleSeconds } ?? false
        queueStuck = stuck && !isBusy
    }

    /// Reads the printer's own status over LEDM, at most every 5 s and never during maintenance.
    private func refreshLEDM() async {
        guard usbPresent == true, !ledmInFlight, !maint.isBusy, !inkInFlight else {
            if usbPresent != true { ledmCategories = nil }
            return
        }
        guard Date().timeIntervalSince(lastLedmFetch) >= 5 else { return }
        ledmInFlight = true
        lastLedmFetch = Date()
        defer { ledmInFlight = false }
        if let uri = status?.deviceURI { LEDMClient.shared.serial = USBCheck.serial(fromURI: uri) }
        if let r = try? await LEDMClient.shared.getAsync("/DevMgmt/ProductStatusDyn.xml"), r.status == 200 {
            let cats = Maintenance.statusCategories(r.body)
            ledmCategories = cats.isEmpty ? nil : cats
        } else {
            ledmCategories = nil
        }
        updateStale()
    }

    private func checkNotifications(_ jobs: [PrintJob]) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            previousJobStates = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.stateCode) })
            return
        }
        defer { previousJobStates = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.stateCode) }) }
        guard !previousJobStates.isEmpty || !jobs.isEmpty else { return }
        for j in jobs {
            guard let old = previousJobStates[j.id], old >= 3, old <= 6 else { continue }
            if j.stateCode == 9 { notifier.post(title: "Print job completed", body: j.title) }
            else if j.stateCode == 8 { notifier.post(title: "Print job failed", body: j.title) }
        }
    }

    // MARK: actions

    func cancel(_ job: PrintJob) { run("Cancel job \(job.id)") { try Cups.cancel(job: job.id, printer: $0) } }
    func cancel(ids: [Int]) { run("Cancel jobs") { p in for id in ids { try Cups.cancel(job: id, printer: p) } } }
    func cancelAll() { run("Cancel all jobs") { try Cups.cancelAll(printer: $0) } }
    func testPage() { run("Test page") { _ = try Cups.printTestPage(printer: $0) } }
    func resetQueue() { run("Reset queue") { try Cups.resetQueue(printer: $0) } }
    func togglePause() {
        let pause = status?.stateCode != 5
        run(pause ? "Pause" : "Resume") { try Cups.setPaused(pause, printer: $0) }
    }

    private func run(_ label: String, _ work: @escaping @Sendable (String) throws -> Void) {
        let name = selected
        Task {
            let result: String? = await Task.detached {
                do { try work(name); return nil } catch {
                    if case CupsError.denied(let m) = error { return m }
                    return "\(label) failed: \(error.localizedDescription)"
                }
            }.value
            actionMessage = result
            await refresh()
        }
    }
}

struct Snapshot: Sendable {
    var printers: [PrinterInfo]?
    var resolvedName: String?
    var status: PrinterStatus?
    var usb: Bool?
    var jobs: [PrintJob] = []

    static func filtered(_ all: [PrinterInfo]) -> [PrinterInfo] {
        let ours = all.filter { $0.makeAndModel.localizedCaseInsensitiveContains("hpcups-macos") }
        return ours.isEmpty ? all : ours
    }

    static func load(selected: String, reloadList: Bool) -> Snapshot {
        var snap = Snapshot()
        var list = filtered(Cups.listPrinters())
        if reloadList { snap.printers = list } else { list = [] }
        var info = list.first(where: { $0.name == selected })
        if reloadList, info == nil, let first = list.first {
            // Selected queue is gone: fall back to the default or first match.
            let pick = list.first(where: { $0.name == "HP_DeskJet_2300" }) ?? first
            snap.resolvedName = pick.name
            info = pick
        }
        let target = info ?? PrinterInfo(name: selected, makeAndModel: "", deviceURI: "")
        let st = Cups.printerStatus(target)
        snap.status = st
        snap.usb = USBCheck.devicePresent(deviceURI: st.deviceURI)
        snap.jobs = Cups.jobs(for: target.name, limit: 100)
        return snap
    }
}
