// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JigScreen",
    platforms: [.macOS(.v13)],
    targets: [
        // The status file's shape and what the panel shows from it. No UI.
        .target(name: "JigScreenCore"),
        // The menu bar app.
        .executableTarget(name: "JigScreen", dependencies: ["JigScreenCore"]),
        // Checks for the core, as a plain program: `swift run jig-screen-check`.
        .executableTarget(name: "jig-screen-check", dependencies: ["JigScreenCore"]),
    ]
)
