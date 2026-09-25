// swift-tools-version:5.9
import PackageDescription

// Builds and tests the framework-free core (models + statistics) so its
// behaviour is verified independently. The SwiftUI files under UI/ are
// reference source: copy them into an app target (see INTEGRATION.md).
let package = Package(
    name: "WorkoutActivityCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "WorkoutActivityCore", targets: ["WorkoutActivityCore"])],
    targets: [
        .target(name: "WorkoutActivityCore"),
        .testTarget(name: "WorkoutActivityCoreTests", dependencies: ["WorkoutActivityCore"]),
    ]
)
