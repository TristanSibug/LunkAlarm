// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunkAlarmCore",
    products: [.library(name: "LunkAlarmCore", targets: ["LunkAlarmCore"])],
    targets: [
        .target(name: "LunkAlarmCore", path: "LunkAlarm/Core"),
        .testTarget(name: "LunkAlarmCoreTests", dependencies: ["LunkAlarmCore"], path: "CoreTests")
    ]
)
