import Foundation
import SwiftUI

enum MaintPhase: Equatable {
    case idle
    case running(MaintenanceJob, String)
    case awaitingScan(String)          // alignment page printed, user must scan it
    case done(MaintenanceJob, String)
    case failed(MaintenanceJob, String)

    var isBusy: Bool {
        switch self {
        case .running, .awaitingScan: return true
        default: return false
        }
    }
}

@MainActor
final class MaintenanceController: ObservableObject {
    @Published var phase: MaintPhase = .idle
    @Published var supported: [String]?        // JobType values from InternalPrintCap

    private var task: Task<Void, Never>?
    private let client = LEDMClient.shared

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

    func dismiss() {
        if !phase.isBusy { phase = .idle }
    }

    func start(_ job: MaintenanceJob) {
        guard !phase.isBusy else { return }
        task = Task { [weak self] in
            guard let self else { return }
            if job == .align { await self.runAlign() } else { await self.runJob(job) }
        }
    }

    /// Alignment: the user pressed the printer's button (or closes the dialog).
    func finishAlignment() {
        task?.cancel()
        phase = .done(.align, "Alignment finished. If the printer's lights are still blinking, wait for them to stop.")
    }

    // MARK: job pages

    private func runJob(_ job: MaintenanceJob) async {
        guard let jt = job.jobType else { return }
        phase = .running(job, "Sending the request to the printer")
        do {
            let r = try await client.postAsync("/DevMgmt/InternalPrintDyn.xml", xml: Maintenance.jobXML(jt))
            guard (200..<300).contains(r.status) else {
                phase = .failed(job, "The printer refused the request (HTTP \(r.status) \(r.reason)).")
                return
            }
            phase = .running(job, "The printer accepted the job. Waiting for it to finish")
            var quiet = 0
            for i in 0..<45 {
                try await Task.sleep(for: .seconds(4))
                let s = try await client.getAsync("/DevMgmt/ProductStatusDyn.xml")
                let cats = Maintenance.statusCategories(s.body)
                if Maintenance.isBusy(cats) { quiet = 0 } else { quiet += 1 }
                phase = .running(job, "Printer status: \(cats.isEmpty ? "unknown" : cats.joined(separator: ", "))")
                if quiet >= 2 && i >= 2 { break }
            }
            phase = .done(job, "Done. The printer finished the \(job.title.lowercased()) job.")
        } catch is CancellationError {
        } catch {
            phase = .failed(job, error.localizedDescription)
        }
    }

    // MARK: alignment (base/maint.py dataModelHelper, AlignType15)

    private func runAlign() async {
        let job = MaintenanceJob.align
        phase = .running(job, "Checking the calibration state")
        do {
            var state = try await client.getAsync("/Calibration/State", expectRoot: "CalibrationState")
            if state.body.isEmpty { state = try await client.getAsync("/Calibration/State", expectRoot: "CalibrationState") }
            if state.status == 404 {
                phase = .failed(job, "This printer does not support alignment over this channel.")
                return
            }
            let st = state.text
            if st.contains("ParmsRequested") {
                phase = .failed(job, "The printer is waiting for an earlier alignment. Turn it off and on, then try again.")
                return
            }
            if st.contains("Printing<") {
                phase = .failed(job, "A previous alignment job has not finished. Wait for the printer to go idle.")
                return
            }
            let cfg = try await client.getAsync("/DevMgmt/ConsumableConfigDyn.xml")
            let mode = InkParser.parse(cfg.body)?.alignmentMode ?? ""
            guard cfg.text.contains("AlignmentMode") else {
                phase = .failed(job, "This printer does not report an alignment mode.")
                return
            }
            if mode == "manual" {
                phase = .failed(job, "This printer uses manual alignment, which this app does not support.")
                return
            }
            phase = .running(job, "Asking the printer to print the alignment page")
            let r = try await client.postFooterAsync("/Calibration/Session", xml: Maintenance.calibrationPrintingXML)
            guard (200..<300).contains(r.status) else {
                phase = .failed(job, "The printer refused the request (HTTP \(r.status) \(r.reason)).")
                return
            }
            if mode == "automatic" {
                phase = .done(job, "The printer is aligning itself. Wait for it to finish.")
                return
            }
            phase = .awaitingScan("Waiting for the alignment page")
            // Read-only polling of the calibration state while the user scans the page.
            for _ in 0..<60 {
                try await Task.sleep(for: .seconds(5))
                if let s = try? await client.getAsync("/Calibration/State", expectRoot: "CalibrationState"),
                   s.status == 200 {
                    let text = s.text
                    if text.contains("CalibrationValid") {
                        phase = .done(job, "The printer reports the alignment as valid.")
                        return
                    }
                    phase = .awaitingScan("Printer state: \(calibrationWord(text))")
                }
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(job, error.localizedDescription)
        }
    }

    private func calibrationWord(_ xml: String) -> String {
        for w in ["CalibrationValid", "CalibrationRequired", "ParmsRequested", "Printing", "Scanning"] where xml.contains(w) {
            return w
        }
        return "unknown"
    }
}
