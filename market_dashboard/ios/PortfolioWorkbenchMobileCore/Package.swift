// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PortfolioWorkbenchMobileCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PortfolioWorkbenchMobileCore",
            targets: ["PortfolioWorkbenchMobileCore"]
        )
    ],
    targets: [
        .target(
            name: "PortfolioWorkbenchMobileCore"
        ),
        .testTarget(
            name: "PortfolioWorkbenchMobileCoreTests",
            dependencies: ["PortfolioWorkbenchMobileCore"]
        )
    ]
)
