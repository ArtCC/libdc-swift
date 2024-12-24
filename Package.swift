// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LibDCSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LibDCSwift",
            targets: ["LibDCSwift"]),
        .library(
            name: "LibDCSwiftUI", 
            targets: ["LibDCSwiftUI"]),
        .library(
            name: "LibDCBridge",
            targets: ["LibDCBridge"])
    ],
    targets: [
        .target(
            name: "Clibdivecomputer",
            dependencies: [],
            path: "Sources/Clibdivecomputer",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../libdivecomputer/include")
            ]
        ),
        .target(
            name: "LibDCSwift",
            dependencies: ["LibDCBridge", "Clibdivecomputer"],
            path: "Sources/LibDCSwift"
        ),
        .target(
            name: "LibDCSwiftUI",
            dependencies: ["LibDCSwift"],
            path: "Sources/LibDCSwiftUI"
        ),
        .target(
            name: "LibDCBridge",
            dependencies: ["Clibdivecomputer"],
            path: "Sources/LibDCBridge",
            sources: ["src/configuredc.c", "src/BLEBridge.m"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("../libdivecomputer/include")
            ]
        ),
        // Test targets
        .testTarget(
            name: "LibDCSwiftTests",
            dependencies: ["LibDCSwift"],
            path: "Tests/LibDCSwiftTests"),
            
        .testTarget(
            name: "LibDCSwiftUITests", 
            dependencies: ["LibDCSwiftUI"],
            path: "Tests/LibDCSwiftUITests"),
            
        .testTarget(
            name: "LibDCBridgeTests",
            dependencies: ["LibDCBridge"],
            path: "Tests/LibDCBridgeTests")
    ]
) 