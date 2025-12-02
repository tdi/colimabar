// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ColimaBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ColimaBar",
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
