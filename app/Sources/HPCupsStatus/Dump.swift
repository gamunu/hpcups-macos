import Foundation

/// Command-line self-check: prints what the GUI would show.
func dumpAndExit() -> Never {
    let all = Cups.listPrinters()
    print("Queues (all): \(all.map(\.name).joined(separator: ", "))")
    let shown = Snapshot.filtered(all)
    print("Queues (shown): \(shown.map(\.name).joined(separator: ", "))")
    let args = CommandLine.arguments
    var name = "HP_DeskJet_2300"
    if let i = args.firstIndex(of: "--printer"), i + 1 < args.count { name = args[i + 1] }
    guard let info = shown.first(where: { $0.name == name }) ?? shown.first else {
        print("No printer queues found"); exit(1)
    }
    let st = Cups.printerStatus(info)
    print("\nPrinter: \(st.name)")
    print("Model: \(st.makeAndModel)")
    print("Device URI: \(st.deviceURI)")
    if let e = st.error { print("Error: \(e)") }
    print("State: \(st.stateText) (\(st.stateCode))")
    print("Message: \(st.message.isEmpty ? "(none)" : st.message)")
    print("Reasons (raw): \(st.reasons.joined(separator: ", "))")
    let plain = StatusText.describe(all: st.reasons)
    print("Reasons (plain): \(plain.isEmpty ? "(none)" : plain.joined(separator: "; "))")
    if let serial = USBCheck.serial(fromURI: st.deviceURI) {
        print("USB serial: \(serial)")
        print("USB device present: \(USBCheck.devicePresent(deviceURI: st.deviceURI) == true ? "yes" : "no")")
    } else {
        print("USB device present: n/a")
    }
    if st.ink.isEmpty {
        print("Ink: Ink levels not available yet")
    } else {
        for s in st.ink { print("Ink: \(s.name) \(s.level)% \(s.colorHex ?? "")") }
    }
    LEDMClient.shared.serial = USBCheck.serial(fromURI: st.deviceURI)
    LEDMClient.shared.verbose = args.contains("-v")
    print("\nLEDM (live over USB):")
    do {
        let r = try LEDMClient.shared.get("/DevMgmt/ConsumableConfigDyn.xml")
        if let rep = InkParser.parse(r.body), !rep.cartridges.isEmpty {
            for c in rep.cartridges {
                let pct = c.percent.map { "\($0)%" } ?? "unknown"
                print("Ink: \(c.name) (\(c.label)) level=\(pct) state=\(c.state.text) raw=\(c.rawState) measured=\(c.measured) product=\(c.product ?? "?")")
            }
            print("Alignment mode: \(rep.alignmentMode ?? "unknown")")
        } else {
            print("Ink: unknown (HTTP \(r.status), no cartridges parsed)")
        }
        let cap = try LEDMClient.shared.get("/DevMgmt/InternalPrintCap.xml")
        let types = Maintenance.supportedJobTypes(cap.body)
        print("Maintenance job types: \(types.isEmpty ? "unknown" : types.joined(separator: ", "))")
    } catch {
        print("LEDM error: \(error.localizedDescription)")
    }
    let jobs = Cups.jobs(for: info.name)
    print("Jobs: \(jobs.count)")
    for j in jobs {
        print("  #\(j.id) \(j.stateText) \"\(j.title)\" user=\(j.user) \(j.sizeKB)KB \(j.time.formatted(date: .abbreviated, time: .standard)) reasons=\(j.reasons.joined(separator: ","))")
    }
    exit(0)
}

/// Debug helper: GET one LEDM resource and print the raw body.
/// Starts a clean, deep clean or diagnostics page from the command line.
func maintJobAndExit(name: String) -> Never {
    LEDMClient.shared.verbose = cliArgs.contains("-v")
    guard name == "cancel" || MaintenanceJob(rawValue: name) != nil else {
        FileHandle.standardError.write(Data("usage: --maint clean|deepClean|diagnostics|align|cancel\n".utf8))
        exit(64)
    }
    if name == "cancel" {
        LEDMClient.shared.serial = cliSerial()
        let r = Maintenance.cancelActivePrinterJobs()
        print(r.summary)
        exit(r.error == nil ? 0 : 1)
    }
    let job = MaintenanceJob(rawValue: name)!
    do {
        let r: LEDMResponse
        if let jt = job.jobType {
            r = try LEDMClient.shared.post("/DevMgmt/InternalPrintDyn.xml", xml: Maintenance.jobXML(jt))
        } else {
            r = try LEDMClient.shared.postFooter("/Calibration/Session", xml: Maintenance.calibrationPrintingXML)
        }
        print("\(job.title): HTTP \(r.status) \(r.reason)")
        exit((200..<300).contains(r.status) ? 0 : 2)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

func ledmGetAndExit(path: String) -> Never {
    LEDMClient.shared.verbose = cliArgs.contains("-v")
    do {
        let r = try LEDMClient.shared.get(path)
        FileHandle.standardError.write(Data("HTTP \(r.status) \(r.reason)\n".utf8))
        FileHandle.standardOutput.write(r.body)
        if r.body.last != 10 { print("") }
        exit(r.status == 200 ? 0 : 2)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

/// Cancels one job through the same code path the GUI uses.
func cancelJobAndExit(id: Int?) -> Never {
    guard let id else {
        FileHandle.standardError.write(Data("usage: --cancel <job-id> [--printer <name>]\n".utf8))
        exit(64)
    }
    var name = "HP_DeskJet_2300"
    if let i = cliArgs.firstIndex(of: "--printer"), i + 1 < cliArgs.count { name = cliArgs[i + 1] }
    do {
        try Cups.cancel(job: id, printer: name)
        print("Canceled job \(id) on \(name)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

/// USB serial of the printer queue named by --printer (default HP_DeskJet_2300), for LEDM.
func cliSerial() -> String? {
    var name = "HP_DeskJet_2300"
    if let i = cliArgs.firstIndex(of: "--printer"), i + 1 < cliArgs.count { name = cliArgs[i + 1] }
    let all = Snapshot.filtered(Cups.listPrinters())
    guard let info = all.first(where: { $0.name == name }) ?? all.first else { return nil }
    return USBCheck.serial(fromURI: Cups.printerStatus(info).deviceURI)
}

/// Prints the parsed /Jobs/JobList (read-only).
func ledmJobsAndExit() -> Never {
    LEDMClient.shared.verbose = cliArgs.contains("-v")
    LEDMClient.shared.serial = cliSerial()
    do {
        let r = try LEDMClient.shared.get("/Jobs/JobList", expectRoot: "JobList")
        guard r.status == 200 else { print("HTTP \(r.status) \(r.reason)"); exit(2) }
        let jobs = Maintenance.parseJobList(r.body)
        print("Printer jobs: \(jobs.count), active: \(jobs.filter(\.isActive).count)")
        for j in jobs {
            let cal = j.calibrationState.map { " calibration=\($0)" } ?? ""
            print("  \(j.url) category=\(j.category) state=\(j.state) active=\(j.isActive ? "yes" : "no")\(cal)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
