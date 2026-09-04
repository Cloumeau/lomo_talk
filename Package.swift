// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LomoTalk",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "lomo_talk", targets: ["LomoTalk"])],
    targets: [.executableTarget(name: "LomoTalk")]
)
