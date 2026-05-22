// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreasuryKernel",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TreasuryKernel", targets: ["TreasuryKernel"]),
        .library(name: "TreasuryTrading", targets: ["TreasuryTrading"]),
        .library(name: "TreasuryUI", targets: ["TreasuryUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TreasuryKernel",
            path: "Sources/TreasuryKernel",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "TreasuryTrading",
            dependencies: ["TreasuryKernel"],
            path: "Sources/TreasuryTrading"
        ),
        .target(
            name: "TreasuryUI",
            dependencies: ["TreasuryKernel", "TreasuryTrading"],
            path: "Sources/TreasuryUI"
        ),
        .testTarget(
            name: "TreasuryKernelTests",
            dependencies: ["TreasuryKernel"],
            path: "Tests/TreasuryKernelTests"
        ),
        .testTarget(
            name: "TreasuryTradingTests",
            dependencies: ["TreasuryTrading", "TreasuryKernel"],
            path: "Tests/TreasuryTradingTests"
        ),
    ]
)
