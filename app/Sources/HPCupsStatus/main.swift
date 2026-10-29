import Foundation

if CommandLine.arguments.contains("--dump") {
    dumpAndExit()
} else {
    HPCupsStatusApp.main()
}
