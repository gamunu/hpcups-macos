import Foundation
import SwiftUI

/// Where a guided maintenance flow is.
enum FlowStage: Equatable {
    case prepare
    case starting
    case running            // printer is busy (printing, cleaning, calibrating)
    case awaitScan          // alignment page is out, waiting for the user
    case scanning           // printer is scanning the alignment page
    case done
    case failed(String)
}

/// Something the user has to fix while a flow waits. The job continues by itself afterwards.
enum Attention: Equatable {
    case loadPaper
    case closeDoor
    case other(String)

    var title: String {
        switch self {
        case .loadPaper: return "Load paper"
        case .closeDoor: return "Close the door"
        case .other(let s): return s
        }
    }
    var detail: String {
        switch self {
        case .loadPaper: return "Load plain paper in the input tray and push the tray in. The job continues by itself."
        case .closeDoor: return "Close the printer's door or cover. The job continues by itself."
        case .other: return "Check the printer. The job continues once the problem is fixed."
        }
    }
    var symbol: String {
        switch self {
        case .loadPaper: return "doc.badge.plus"
        case .closeDoor: return "door.left.hand.open"
        case .other: return "exclamationmark.triangle"
        }
    }
}

enum Maintenance {
    // Body from HPLIP base/maint.py (CleanXML, setCleanType), sent as in cleanTypeLedm.
    static func jobXML(_ jobType: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!--  THIS DATA SUBJECT TO DISCLAIMER(S)INCLUDED WITH THE PRODUCT OF ORIGIN. -->\n<ipcap:InternalPrintCap xmlns:ipcap=\"http://www.hp.com/schemas/imaging/con/ledm/internalprintcap/2008/03/21\" xmlns:ipdyn=\"http://www.hp.com/schemas/imaging/con/ledm/internalprintdyn/2008/03/21\" xmlns:dd=\"http://www.hp.com/schemas/imaging/con/dictionaries/1.0/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.hp.com/schemas/imaging/con/ledm/internalprintcap/2008/03/21 ../schemas/InternalPrintCap.xsd http://www.hp.com/schemas/imaging/con/ledm/internalprintdyn/2008/03/21 ../schemas/InternalPrintDyn.xsd http://www.hp.com/schemas/imaging/con/dictionaries/1.0/ ../schemas/dd/DataDictionaryMasterLEDM.xsd\">\n                                <ipdyn:JobType>\(jobType)</ipdyn:JobType>\n</ipcap:InternalPrintCap>"
    }

    // base/maint.py dataModelHelper, with the attribute quotes written as plain quotes.
    static let calibrationPrintingXML = "<cal:CalibrationState xmlns:cal=\"http://www.hp.com/schemas/imaging/con/cnx/markingagentcalibration/2009/04/08\" xmlns:dd=\"http://www.hp.com/schemas/imaging/con/dictionaries/1.0/\">Printing</cal:CalibrationState>"

    static func supportedJobTypes(_ data: Data) -> [String] {
        guard let root = parseXML(data) else { return [] }
        return root.descendants("JobType").map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Status categories from ProductStatusDyn.
    static func statusCategories(_ data: Data) -> [String] {
        guard let root = parseXML(data) else { return [] }
        return root.all("Status").compactMap { $0.value("StatusCategory") }
    }

    static func isBusy(_ categories: [String]) -> Bool {
        categories.contains { c in
            let l = c.lowercased()
            return ["process", "clean", "align", "calibrat", "busy", "printing", "initializ", "warm"].contains { l.contains($0) }
        }
    }

    /// The first category that needs the user. genuineHP and ready are informational.
    static func attention(_ categories: [String]) -> Attention? {
        for c in categories {
            let l = c.lowercased()
            if l == "trayemptyoropen" { return .loadPaper }
            if l == "closedoororcover" { return .closeDoor }
            if ["jam", "error", "inkout", "inkempty", "cartridge", "missing"].contains(where: { l.contains($0) }) {
                return .other(describe(c))
            }
        }
        return nil
    }

    /// Plain words for a status category.
    static func describe(_ category: String) -> String {
        switch category.lowercased() {
        case "ready": return "Ready"
        case "processing": return "Printing"
        case "calibrating": return "Calibrating"
        case "trayemptyoropen": return "Paper tray empty or open"
        case "closedoororcover": return "Door or cover open"
        case "genuinehp": return "Genuine HP cartridges"
        default: return category
        }
    }

    /// Summary of the live categories for display, ignoring informational ones.
    static func liveText(_ categories: [String]) -> String {
        let shown = categories.filter { $0.lowercased() != "genuinehp" }
        if shown.isEmpty { return categories.isEmpty ? "Waiting for the printer" : "Ready" }
        return shown.map(describe).joined(separator: ", ")
    }
}

@MainActor
final class MaintenanceController: ObservableObject {
    @Published var job: MaintenanceJob?          // non-nil while the guided sheet is open
    @Published var stage: FlowStage = .prepare
    @Published var categories: [String] = []     // live ProductStatusDyn categories
    @Published var calState: String?             // live /Calibration/State, alignment only
    @Published var attention: Attention?
    @Published var reached = 0                   // index of the furthest step shown
    @Published var note: String?                 // extra line on the done screen
    @Published var supported: [String]?          // JobType values from InternalPrintCap

    private var task: Task<Void, Never>?
    private let client = LEDMClient.shared
    private let pollInterval: Duration = .seconds(2)

    var isBusy: Bool {
        guard job != nil else { return false }
        switch stage {
        case .starting, .running, .awaitScan, .scanning: return true
        default: return false
        }
    }

    static func steps(for job: MaintenanceJob) -> [String] {
        switch job {
        case .clean, .deepClean: return ["Prepare", "Cleaning", "Done"]
        case .diagnostics: return ["Prepare", "Printing", "Check"]
        case .align: return ["Prepare", "Printing", "Scan", "Done"]
        }
    }

    func supports(_ job: MaintenanceJob) -> Bool {
        guard let jt = job.jobType else { return true }   // alignment checked when it starts
        return supported?.contains(jt) ?? true             // unknown until the capability read finishes
    }

    func loadCapabilities() async {
        guard supported == nil else { return }
        if let r = try? await client.getAsync("/DevMgmt/InternalPrintCap.xml"), r.status == 200 {
            let list = Maintenance.supportedJobTypes(r.body)
            if !list.isEmpty { supported = list }
        }
    }

    // MARK: sheet control

    func open(_ job: MaintenanceJob) {
        guard !isBusy else { return }
        task?.cancel()
        reset()
        self.job = job
    }

    /// Closes the sheet. The printer keeps going with a job it already started.
    func close() {
        task?.cancel()
        task = nil
        job = nil
        reset()
    }

    func retry() {
        guard let j = job else { return }
        task?.cancel()
        reset()
        job = j
    }

    private func reset() {
        stage = .prepare
        categories = []
        calState = nil
        attention = nil
        reached = 0
        note = nil
    }

    func begin() {
        guard let job, !isBusy else { return }
        stage = .starting
        reached = 1
        task = Task { [weak self] in
            guard let self else { return }
            if job == .align { await self.runAlign() } else { await self.runJob(job) }
        }
    }

    private func fail(_ message: String) { stage = .failed(message) }

    private func readCategories() async -> [String]? {
        guard let s = try? await client.getAsync("/DevMgmt/ProductStatusDyn.xml"), s.status == 200 else { return nil }
        let cats = Maintenance.statusCategories(s.body)
        return cats.isEmpty ? nil : cats
    }

    // MARK: clean, deep clean, diagnostics

    /// Clean and diagnostics: send the job, then watch the status categories every 2 s.
    /// Done when the printer was busy and is ready again with nothing for the user to fix.
    private func runJob(_ job: MaintenanceJob) async {
        guard let jt = job.jobType else { return }
        do {
            let r = try await client.postAsync("/DevMgmt/InternalPrintDyn.xml", xml: Maintenance.jobXML(jt))
            guard (200..<300).contains(r.status) else {
                fail("The printer refused the request (HTTP \(r.status) \(r.reason)).")
                return
            }
            stage = .running
            var sawBusy = false, quiet = 0, failures = 0
            let started = Date()
            while true {
                try await Task.sleep(for: pollInterval)
                if Date().timeIntervalSince(started) > 300 {
                    fail("The printer did not finish within 5 minutes. Check it, then try again.")
                    return
                }
                guard let cats = await readCategories() else {
                    failures += 1
                    if failures >= 10 { fail("The printer stopped answering."); return }
                    continue
                }
                failures = 0
                categories = cats
                let a = Maintenance.attention(cats)
                attention = a
                if Maintenance.isBusy(cats) { sawBusy = true; quiet = 0 }
                else if a == nil { quiet += 1 }
                else { quiet = 0 }
                if (sawBusy && quiet >= 2) || (!sawBusy && quiet >= 10) {
                    if !sawBusy { note = "The printer did not report any activity, so the job may have finished very quickly." }
                    stage = .done
                    reached = 2
                    return
                }
            }
        } catch is CancellationError {
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: alignment (base/maint.py dataModelHelper, AlignType15)

    /// Words for the calibration state XML. ScanRequested is checked before Scanning.
    static func calibrationWord(_ xml: String) -> String? {
        for w in ["CalibrationValid", "CalibrationRequired", "ParmsRequested", "ScanRequested", "Scanning", "Printing"]
        where xml.contains(w) { return w }
        return nil
    }

    private func readCalibration() async -> String? {
        guard let s = try? await client.getAsync("/Calibration/State", expectRoot: "CalibrationState"),
              s.status == 200 else { return nil }
        return Self.calibrationWord(s.text)
    }

    /// Sequence seen on a DeskJet 2300 over USB:
    /// CalibrationRequired -> Printing (calibrating) -> ScanRequested -> Scanning -> CalibrationRequired + ready.
    /// The printer does not report CalibrationValid after a good alignment, so success is
    /// "passed through Scanning, then ready with nothing to fix". CalibrationValid also counts.
    private func runAlign() async {
        do {
            var state = try await client.getAsync("/Calibration/State", expectRoot: "CalibrationState")
            if state.body.isEmpty { state = try await client.getAsync("/Calibration/State", expectRoot: "CalibrationState") }
            if state.status == 404 {
                fail("This printer does not support alignment over this channel.")
                return
            }
            let st = state.text
            if st.contains("ParmsRequested") {
                fail("The printer is waiting for an earlier alignment. Turn it off and on, then try again.")
                return
            }
            if st.contains("Printing<") {
                fail("A previous alignment job has not finished. Wait for the printer to go idle.")
                return
            }
            let cfg = try await client.getAsync("/DevMgmt/ConsumableConfigDyn.xml")
            let mode = InkParser.parse(cfg.body)?.alignmentMode ?? ""
            guard cfg.text.contains("AlignmentMode") else {
                fail("This printer does not report an alignment mode.")
                return
            }
            if mode == "manual" {
                fail("This printer uses manual alignment, which this app does not support.")
                return
            }
            let r = try await client.postFooterAsync("/Calibration/Session", xml: Maintenance.calibrationPrintingXML)
            guard (200..<300).contains(r.status) else {
                fail("The printer refused the request (HTTP \(r.status) \(r.reason)).")
                return
            }
            if mode == "automatic" {
                note = "The printer aligns itself. Wait for its lights to stop."
                stage = .done
                reached = 3
                return
            }
            stage = .running

            var left = false          // state moved off the starting point
            var sawScan = false
            var settled = 0           // consecutive polls that look ready
            var failures = 0
            let started = Date()
            while true {
                try await Task.sleep(for: pollInterval)
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 900 {
                    fail("The scan was not detected. The page was never scanned within 15 minutes.")
                    return
                }
                if !left && elapsed > 60 {
                    fail("The printer did not start printing the alignment page.")
                    return
                }
                let cats = await readCategories()
                let cal = await readCalibration()
                if cats == nil && cal == nil {
                    failures += 1
                    if failures >= 10 { fail("The printer stopped answering."); return }
                    continue
                }
                failures = 0
                if let c = cats { categories = c; attention = Maintenance.attention(c) }
                if let w = cal { calState = w }
                let word = cal ?? calState

                switch word {
                case "ScanRequested":
                    left = true
                    stage = .awaitScan
                    reached = 2
                case "Scanning":
                    left = true
                    sawScan = true
                    stage = .scanning
                    reached = 2
                case "Printing", "ParmsRequested":
                    left = true
                case "CalibrationValid":
                    if left || sawScan { finishAlign(); return }
                default: break
                }
                let busy = cats.map(Maintenance.isBusy) ?? true
                if busy && cats != nil { left = true }
                let ready = cats != nil && !busy && attention == nil
                    && (word == "CalibrationRequired" || word == "CalibrationValid")
                settled = ready ? settled + 1 : 0
                if sawScan && settled >= 1 { finishAlign(); return }
                if left && !sawScan && settled >= 10 {
                    fail("The printer went back to ready without scanning the page. The scan was not detected.")
                    return
                }
            }
        } catch is CancellationError {
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishAlign() {
        stage = .done
        reached = 3
    }
}
