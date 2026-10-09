// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundDihsignCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SoundCore", targets: ["SoundCore"])],
    targets: [.target(name: "SoundCore", path: "Sources/SoundCore", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")])],
    cxxLanguageStandard: .cxx17
)
