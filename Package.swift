// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HideIt",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "HideIt", targets: ["HideIt"])],
    targets: [.executableTarget(name: "HideIt")]
)
