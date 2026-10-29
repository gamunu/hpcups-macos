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
        if status?.stateCode == 4 { return "printer.fill" }
        return "printer"
    }

    func start() {
        guard !started else { return }
        started = true
        notifier.requestAuthorization()
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
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
        checkNotifications(snap.jobs)
    }

    private func checkNotifications(_ jobs: [PrintJob]) {
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
    func cancelAll() { run("Cancel all jobs") { try Cups.cancelAll(printer: $0) } }
    func testPage() { run("Test page") { _ = try Cups.printTestPage(printer: $0) } }
    func togglePause() {
        let pause = status?.stateCode != 5
        run(pause ? "Pause" : "Resume") { try Cups.setPaused(pause, printer: $0) }
    }

    private func run(_ label: String, _ work: @escaping @Sendable (String) throws -> Void) {
        let name = selected
        Task {
            let result: String? = await Task.detached {
                do { try work(name); return nil } catch { return "\(label) failed: \(error.localizedDescription)" }
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
        snap.jobs = Cups.jobs(for: target.name)
        return snap
    }
}
