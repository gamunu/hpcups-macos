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
    let jobs = Cups.jobs(for: info.name)
    print("Jobs: \(jobs.count)")
    for j in jobs {
        print("  #\(j.id) \(j.stateText) \"\(j.title)\" user=\(j.user) \(j.sizeKB)KB \(j.time.formatted(date: .abbreviated, time: .standard)) reasons=\(j.reasons.joined(separator: ","))")
    }
    exit(0)
}
