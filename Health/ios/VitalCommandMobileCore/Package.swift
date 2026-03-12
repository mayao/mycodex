// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VitalCommandMobileCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VitalCommandMobileCore",
            targets: ["VitalCommandMobileCore"]
        )
    ],
    targets: [
        .target(
            name: "VitalCommandMobileCore"
        ),
        .testTarget(
            name: "VitalCommandMobileCoreTests",
            dependencies: ["VitalCommandMobileCore"]
        )
    ]
)
