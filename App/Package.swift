// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoverArtwall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CoverArtwall",
            path: "Sources/CoverArtwall"
        )
    ]
)
