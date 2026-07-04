// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListeningClipPipe",
    platforms: [
        .macOS("14.4")
    ],
    targets: [
        .executableTarget(
            name: "ListeningClipPipe",
            path: "Sources/ListeningClipPipe"
        )
    ],
    swiftLanguageVersions: [.v5]
)
