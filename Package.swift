// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Undertone",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Undertone", targets: ["Undertone"])],
    targets: [
        .executableTarget(name: "Undertone", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "UndertoneTests", dependencies: ["Undertone"])
    ],
    swiftLanguageModes: [.v6]
)
