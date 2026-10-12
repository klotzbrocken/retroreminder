// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "RetroReminder",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "RetroReminder", path: "Sources/RetroReminder")]
)
