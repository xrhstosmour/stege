// swift-tools-version: 5.9
import PackageDescription

/// Tests for the parts of Stege that are pure logic.
///
/// A separate package rather than an Xcode test target, because there is no
/// Xcode on the machine this is developed on, only Command Line Tools, so an
/// `xcodebuild test` target could not be run before pushing it. `swift test`
/// can. The sources are symlinks into `Stege/Core`, so there is one copy of
/// each file and the application and the tests cannot drift apart.
let package = Package(
    name: "StegeCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StegeCore"),
        .testTarget(name: "StegeCoreTests", dependencies: ["StegeCore"]),
    ]
)
