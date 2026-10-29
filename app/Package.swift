// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HPCupsStatus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Thin module that exposes libcups from the macOS SDK to Swift.
        .target(
            name: "CCups",
            cSettings: [.unsafeFlags(["-Wno-deprecated-declarations"])],
            linkerSettings: [.linkedLibrary("cups")]
        ),
        .executableTarget(
            name: "HPCupsStatus",
            dependencies: [
                "CCups",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // libcups is deprecated in the SDK but still works.
                .unsafeFlags(["-Xcc", "-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [
                // Sparkle.framework lives in Contents/Frameworks of the app bundle.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
