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
    dependencies: [],
    targets: [
        // Main LibDCSwift target
        .target(
            name: "LibDCSwift",
            dependencies: ["LibDCBridge"],
            path: "Sources/LibDCSwift",
            cSettings: [
                .headerSearchPath("../LibDCBridge/include")
            ]),
        
        // SwiftUI components
        .target(
            name: "LibDCSwiftUI",
            dependencies: ["LibDCSwift"],
            path: "Sources/LibDCSwiftUI"),
            
        // Objective-C bridge target
        .target(
            name: "LibDCBridge",
            dependencies: [],
            path: "Sources/LibDCBridge",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("src")
            ]),
            
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