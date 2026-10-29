import Foundation

let cliArgs = CommandLine.arguments
if let i = cliArgs.firstIndex(of: "--ledm-get") {
    ledmGetAndExit(path: i + 1 < cliArgs.count ? cliArgs[i + 1] : "/DevMgmt/ProductStatusDyn.xml")
} else if cliArgs.contains("--dump") {
    dumpAndExit()
} else {
    HPCupsStatusApp.main()
}
